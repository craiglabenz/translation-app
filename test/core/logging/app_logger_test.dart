import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:translation_app/core/ai/local_translation_engine.dart';
import 'package:translation_app/core/logging/app_logger.dart';

void _runWorkerIsolateLog(SendPort sendPort) {
  AppLogger.initIsolateLogging(
    mainSendPort: sendPort,
    isolateLabel: 'TestWorker',
  );
  AppLogger.of('WorkerSubsystem').info('Message from worker isolate');
}

Future<void> _spawnWorkerIsolate(SendPort sendPort) {
  return Isolate.run(() => _runWorkerIsolateLog(sendPort));
}

void main() {
  group('AppLogger', () {
    final emittedLines = <String>[];

    setUp(() {
      emittedLines.clear();
      AppLogger.initLogging();
      AppLogger.onLogEmitted = emittedLines.add;
    });

    tearDown(() {
      AppLogger.onLogEmitted = null;
    });

    test(
      'continues emitting logs even after Logger.root.clearListeners() and Level.OFF',
      () {
        final log = AppLogger.of('TestComponent');

        // Simulate a third-party dependency wiping root listeners or mutating root level.
        Logger.root.clearListeners();
        Logger.root.level = Level.OFF;

        log.info('Still alive after clearListeners');

        expect(
          emittedLines.any(
            (line) =>
                line.contains('[TestComponent]') &&
                line.contains('Still alive after clearListeners'),
          ),
          isTrue,
        );
      },
    );

    test(
      'passes logs from background Isolate.run back to the main isolate via SendPort',
      () async {
        final completer = Completer<String>();
        AppLogger.onLogEmitted = (line) {
          emittedLines.add(line);
          if (line.contains('Message from worker isolate') &&
              !completer.isCompleted) {
            completer.complete(line);
          }
        };

        final sendPort = AppLogger.mainLogSendPort!;
        await _spawnWorkerIsolate(sendPort);

        final received = await completer.future.timeout(
          const Duration(seconds: 5),
        );
        expect(received, contains('[ISO:TestWorker]'));
        expect(received, contains('[WorkerSubsystem]'));
        expect(received, contains('Message from worker isolate'));
      },
    );

    test(
      'encodeAudioChunkInIsolate forwards [ISOLATE ENCODE] log back to main isolate',
      () async {
        final completer = Completer<String>();
        AppLogger.onLogEmitted = (line) {
          emittedLines.add(line);
          if (line.contains('[ISOLATE ENCODE]') && !completer.isCompleted) {
            completer.complete(line);
          }
        };

        final samples = Float32List(8000);
        for (var i = 0; i < 4000; i++) {
          samples[i] = 0.25;
        }

        final (wavBytes, trimmedCount) =
            await LocalTranslationEngine.encodeAudioChunkInIsolate(samples);
        expect(wavBytes, isNotEmpty);
        expect(trimmedCount, equals(8000));

        final isolateLog = await completer.future.timeout(
          const Duration(seconds: 5),
        );
        expect(isolateLog, contains('[ISO:AudioEncoder]'));
        expect(isolateLog, contains('[LocalTranslationEngine]'));
        expect(isolateLog, contains('[ISOLATE ENCODE]'));
      },
    );

    test('sanitizeForLog replaces U+FFFD and unpaired surrogates', () {
      const validEmoji = 'Hello 🌍!';
      expect(AppLogger.sanitizeForLog(validEmoji), equals(validEmoji));

      const withReplacement = 'Bad \uFFFD char';
      expect(
        AppLogger.sanitizeForLog(withReplacement),
        equals('Bad U+FFFD char'),
      );

      final loneHighSurrogate = 'Split ${String.fromCharCode(0xD83C)} end';
      expect(
        AppLogger.sanitizeForLog(loneHighSurrogate),
        equals('Split U+FFFD end'),
      );
    });
  });
}
