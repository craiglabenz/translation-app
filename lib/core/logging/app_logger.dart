import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:logging/logging.dart';
import 'package:translation_app/core/logging/stdio_guard.dart';

/// Centralized logging utility for the Gemma 4 Translation App.
///
/// Configures `package:logging` and `FlutterEdgeAi.logLevel` so every user
/// interaction, router transition, native audio frame, VAD segmentation event,
/// model download progress tick, and LLM translation request/response is
/// surfaced clearly in the debug console.
///
/// Also provides:
/// 1. **Cross-isolate log forwarding**: Background isolates forward formatted
///    log messages over a [SendPort] to the main isolate's [ReceivePort] so all
///    isolate logs are printed from the main thread.
/// 2. **Per-logger direct subscriptions**: Every logger created via
///    [AppLogger.of] maintains its own direct `onRecord` listener and
///    `Level.ALL` override so third-party packages calling
///    `Logger.root.clearListeners()` or raising `Logger.root.level` cannot
///    silence app logs.
/// 3. **POSIX stdio FD restoration**: Saves the original `stdout` (fd 1) and
///    `stderr` (fd 2) descriptors at startup before `flutter_edge_ai_litertlm`
///    calls `stream_proxy_redirect_stderr` (which redirects fd 2 to
///    `/tmp/litertlm_native.log` and silences `os_log`/`debugPrint` on iOS
///    under `devicectl --console` with `OS_ACTIVITY_DT_MODE=enable`).
class AppLogger {
  AppLogger._();

  /// Port name registered in `IsolateNameServer` for cross-isolate logging.
  static const String logPortName = 'translation_app_main_log_port';

  static StreamSubscription<LogRecord>? _rootSubscription;
  static ReceivePort? _mainReceivePort;
  static StreamSubscription<dynamic>? _mainReceiveSubscription;
  static SendPort? _isolateForwardSendPort;
  static String? _isolateLabel;
  static bool _isMainIsolate = false;

  static final Map<String, StreamSubscription<LogRecord>>
  _directLoggerSubscriptions = <String, StreamSubscription<LogRecord>>{};

  /// Optional test hook invoked on the main isolate whenever a formatted log
  /// line is emitted.
  @visibleForTesting
  static void Function(String line)? onLogEmitted;

  /// The [SendPort] bound to the main isolate's log [ReceivePort], if
  /// [initLogging] has been called on the main isolate.
  ///
  /// Pass this into `Isolate.run` / `Isolate.spawn` closures and supply it to
  /// [initIsolateLogging] so logs emitted on background isolates are passed
  /// back to the main isolate to be logged.
  static SendPort? get mainLogSendPort => _mainReceivePort?.sendPort;

  /// Creates a named [Logger] for a specific subsystem or class and attaches a
  /// direct listener so it cannot be silenced by `Logger.root.clearListeners()`
  /// or `Logger.root.level` changes, and automatically forwards to the main
  /// isolate when used from a background isolate.
  static Logger of(String name) {
    hierarchicalLoggingEnabled = true;
    final logger = Logger(name);
    if (name.isNotEmpty) {
      logger.level = Level.ALL;
      _attachDirectSubscription(logger);
    }
    if (!_isMainIsolate && _isolateForwardSendPort == null) {
      _isolateForwardSendPort = lookupMainLogPort(logPortName);
    }
    return logger;
  }

  /// Initializes root logging on the main isolate, opens the cross-isolate
  /// [ReceivePort] for background isolate log messages, and saves the original
  /// `stdout`/`stderr` file descriptors.
  ///
  /// Safe to call multiple times (idempotent).
  static void initLogging({Level level = Level.ALL}) {
    saveOriginalStdioFds();
    _isMainIsolate = true;
    hierarchicalLoggingEnabled = true;
    Logger.root.level = level;

    try {
      FlutterEdgeAi.logLevel = EdgeAiLogLevel.verbose;
    } on Object {
      // Ignore if FlutterEdgeAi is not yet initialized in isolated unit tests.
    }

    if (_mainReceivePort == null) {
      final receivePort = ReceivePort('AppLoggerMainReceivePort');
      _mainReceivePort = receivePort;
      registerMainLogPort(logPortName, receivePort.sendPort);
      _mainReceiveSubscription = receivePort.listen((dynamic message) {
        if (message is String) {
          _emitToMainConsole(message);
        }
      });
    }

    // Ensure all loggers created via `AppLogger.of(...)` before `initLogging()`
    // have active direct subscriptions and `Level.ALL`.
    for (final entry in _directLoggerSubscriptions.keys.toList()) {
      final logger = Logger(entry);
      logger.level = Level.ALL;
      _attachDirectSubscription(logger);
    }

    _rootSubscription ??= Logger.root.onRecord.listen((record) {
      // Named app loggers created via `AppLogger.of` emit through their own
      // direct subscription so they survive `Logger.root.clearListeners()`.
      if (_directLoggerSubscriptions.containsKey(record.loggerName)) {
        return;
      }
      _dispatchFormattedLine(_formatRecord(record));
    });
  }

  /// Configures logging inside a background isolate so that any log records
  /// emitted in the isolate are passed back to the main isolate over
  /// [mainSendPort] (or the port registered under [logPortName] in
  /// `IsolateNameServer`) to be logged on the main thread.
  static void initIsolateLogging({
    SendPort? mainSendPort,
    String? isolateLabel,
    Level level = Level.ALL,
  }) {
    hierarchicalLoggingEnabled = true;
    Logger.root.level = level;
    _isolateForwardSendPort =
        mainSendPort ??
        _isolateForwardSendPort ??
        lookupMainLogPort(logPortName);
    _isolateLabel = isolateLabel ?? _isolateLabel ?? currentIsolateDebugName();

    for (final entry in _directLoggerSubscriptions.keys.toList()) {
      final logger = Logger(entry);
      logger.level = Level.ALL;
      _attachDirectSubscription(logger);
    }

    _rootSubscription ??= Logger.root.onRecord.listen((record) {
      if (_directLoggerSubscriptions.containsKey(record.loggerName)) {
        return;
      }
      _dispatchFormattedLine(_formatRecord(record));
    });
  }

  /// Restores the process's original `stdout` (fd 1) and `stderr` (fd 2)
  /// descriptors if a native library (such as `LiteRtLm`'s
  /// `stream_proxy_redirect_stderr`) redirected `stderr` to a temp file.
  static void restoreConsoleStdio() {
    restoreOriginalStdioFds();
  }

  static void _attachDirectSubscription(Logger logger) {
    final fullName = logger.fullName;
    if (fullName.isEmpty) return;
    if (_directLoggerSubscriptions.containsKey(fullName)) {
      return;
    }
    _directLoggerSubscriptions[fullName] = logger.onRecord.listen((record) {
      // Only handle records originating from this logger (not bubbled up from
      // a child that also has a direct subscription).
      if (record.loggerName != fullName &&
          _directLoggerSubscriptions.containsKey(record.loggerName)) {
        return;
      }
      _dispatchFormattedLine(_formatRecord(record));
    });
  }

  static void _dispatchFormattedLine(String formatted) {
    if (_isMainIsolate) {
      _emitToMainConsole(formatted);
      return;
    }
    final port = _isolateForwardSendPort ??= lookupMainLogPort(logPortName);
    if (port != null) {
      port.send(formatted);
    } else {
      _emitToMainConsole(formatted);
    }
  }

  static void _emitToMainConsole(String message) {
    restoreOriginalStdioFds();
    final sanitized = sanitizeForLog(message);
    onLogEmitted?.call(sanitized);
    debugPrint(sanitized);
  }

  static String _formatRecord(LogRecord record) {
    final time = _formatTimestamp(record.time);
    final levelTag = record.level.name.padRight(7);
    final label = _isolateLabel ?? currentIsolateDebugName();
    final isolatePrefix = (!_isMainIsolate && label != 'main')
        ? '[ISO:$label] '
        : '';
    final buffer = StringBuffer(
      '[$time] [$levelTag] $isolatePrefix[${record.loggerName}] ${record.message}',
    );
    if (record.error != null) {
      buffer.write('\n  ↳ Error: ${record.error}');
    }
    if (record.stackTrace != null) {
      buffer.write('\n  ↳ StackTrace:\n${record.stackTrace}');
    }
    return buffer.toString();
  }

  /// Replaces `U+FFFD` and unpaired UTF-16 surrogates with the literal text
  /// `U+FFFD` so `flutter run`'s console UTF-8 stream reader never aborts on
  /// malformed byte sequences.
  static String sanitizeForLog(String text) {
    var needsSanitization = false;
    for (var i = 0; i < text.length; i++) {
      final u = text.codeUnitAt(i);
      if (u == 0xFFFD || (u >= 0xD800 && u <= 0xDFFF)) {
        needsSanitization = true;
        break;
      }
    }
    if (!needsSanitization) return text;

    final out = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      final u = text.codeUnitAt(i);
      if (u == 0xFFFD) {
        out.write('U+FFFD');
      } else if (u >= 0xD800 && u <= 0xDBFF) {
        final hasLow =
            i + 1 < text.length &&
            text.codeUnitAt(i + 1) >= 0xDC00 &&
            text.codeUnitAt(i + 1) <= 0xDFFF;
        if (hasLow) {
          out.writeCharCode(u);
          out.writeCharCode(text.codeUnitAt(i + 1));
          i++;
        } else {
          out.write('U+FFFD');
        }
      } else if (u >= 0xDC00 && u <= 0xDFFF) {
        out.write('U+FFFD');
      } else {
        out.writeCharCode(u);
      }
    }
    return out.toString();
  }

  static String _formatTimestamp(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    final ms = dt.millisecond.toString().padLeft(3, '0');
    return '$h:$m:$s.$ms';
  }

  /// Disposes internal receive ports for testing if needed.
  @visibleForTesting
  static Future<void> resetForTesting() async {
    await _mainReceiveSubscription?.cancel();
    _mainReceiveSubscription = null;
    _mainReceivePort?.close();
    _mainReceivePort = null;
  }
}
