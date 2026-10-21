import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:logging/logging.dart';

/// Centralized logging utility for the Gemma 4 Translation App.
///
/// Configures `package:logging` and `FlutterEdgeAi.logLevel` so every user
/// interaction, router transition, native audio frame, VAD segmentation event,
/// model download progress tick, and LLM translation request/response is
/// surfaced clearly in the debug console.
class AppLogger {
  AppLogger._();

  static StreamSubscription<LogRecord>? _subscription;

  /// Creates a named [Logger] for a specific subsystem or class.
  static Logger of(String name) => Logger(name);

  /// Initializes root logging and attaches a structured console printer.
  ///
  /// Safe to call multiple times (idempotent).
  static void initLogging({Level level = Level.ALL}) {
    hierarchicalLoggingEnabled = true;
    Logger.root.level = level;

    try {
      FlutterEdgeAi.logLevel = EdgeAiLogLevel.verbose;
    } on Object {
      // Ignore if FlutterEdgeAi is not yet initialized in isolated unit tests.
    }

    if (_subscription != null) {
      return;
    }

    _subscription = Logger.root.onRecord.listen((record) {
      final time = _formatTimestamp(record.time);
      final levelTag = record.level.name.padRight(7);
      final buffer = StringBuffer(
        '[$time] [$levelTag] [${record.loggerName}] ${record.message}',
      );
      if (record.error != null) {
        buffer.write('\n  ↳ Error: ${record.error}');
      }
      if (record.stackTrace != null) {
        buffer.write('\n  ↳ StackTrace:\n${record.stackTrace}');
      }
      debugPrint(buffer.toString());
    });
  }

  static String _formatTimestamp(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    final ms = dt.millisecond.toString().padLeft(3, '0');
    return '$h:$m:$s.$ms';
  }
}
