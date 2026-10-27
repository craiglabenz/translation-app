import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:translation_app/core/audio/audio_exceptions.dart';
import 'package:translation_app/core/audio/native_audio_service.dart';
import 'package:translation_app/core/audio/vad_buffer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('VadBuffer.computeRms', () {
    test('returns 0.0 for empty sample list', () {
      expect(VadBuffer.computeRms(Float32List(0)), 0.0);
    });

    test('returns 0.0 for all-zero silent samples', () {
      expect(VadBuffer.computeRms(Float32List(512)), 0.0);
    });

    test('computes exact RMS for constant positive and negative signals', () {
      final positive = Float32List.fromList(List<double>.filled(100, 0.25));
      expect(VadBuffer.computeRms(positive), closeTo(0.25, 1e-6));

      final negative = Float32List.fromList(List<double>.filled(100, -0.4));
      expect(VadBuffer.computeRms(negative), closeTo(0.4, 1e-6));
    });

    test('computes exact RMS for alternating bipolar square wave', () {
      final wave = Float32List.fromList(
        List<double>.generate(200, (i) => i.isEven ? 0.5 : -0.5),
      );
      expect(VadBuffer.computeRms(wave), closeTo(0.5, 1e-6));
    });
  });

  group('VadBuffer configuration & sample counts', () {
    test('calculates default 16kHz sample thresholds accurately', () {
      final vad = VadBuffer();
      expect(vad.sampleRate, 16000);
      expect(vad.silenceCutoffSamples, 48000); // 16,000 * 3s
      expect(vad.maxSamples, 240000); // 16,000 * 15s
      expect(vad.bufferedSampleCount, 0);
      expect(vad.hasDetectedSpeech, isFalse);
    });

    test('calculates custom sample rate and duration thresholds accurately', () {
      final vad = VadBuffer(
        sampleRate: 8000,
        silenceCutoff: const Duration(milliseconds: 1500),
        maxChunkDuration: const Duration(seconds: 10),
      );
      expect(vad.silenceCutoffSamples, 12000); // 8,000 * 1.5s
      expect(vad.maxSamples, 80000); // 8,000 * 10s
    });
  });

  group('VadBuffer speech segmentation', () {
    test('ignores empty Float32List without side effects', () {
      final vad = VadBuffer(sampleRate: 1000);
      expect(vad.addSamples(Float32List(0)), isEmpty);
      expect(vad.hasDetectedSpeech, isFalse);
      expect(vad.bufferedSampleCount, 0);
    });

    test('ignores leading silence and sub-threshold background noise', () {
      final vad = VadBuffer(
        sampleRate: 1000,
        silenceCutoff: const Duration(seconds: 3),
        maxChunkDuration: const Duration(seconds: 15),
        silenceThreshold: 0.02,
      );

      // 5 seconds of 0.0 silence
      expect(vad.addSamples(Float32List(5000)), isEmpty);
      // 3 seconds of quiet background hum (0.005 < 0.02)
      final quietHum = Float32List.fromList(List<double>.filled(3000, 0.005));
      expect(vad.addSamples(quietHum), isEmpty);

      expect(vad.hasDetectedSpeech, isFalse);
      expect(vad.bufferedSampleCount, 0);
      expect(vad.flush(), isNull);
    });

    test('concatenates speech separated by short pauses (< 3.0s) into one chunk', () {
      final vad = VadBuffer(
        sampleRate: 1000,
        silenceCutoff: const Duration(seconds: 3),
        maxChunkDuration: const Duration(seconds: 15),
        silenceThreshold: 0.02,
      );

      final speech1 = Float32List.fromList(List<double>.filled(1000, 0.25));
      final shortPause = Float32List(1500); // 1.5s pause (< 3.0s cutoff)
      final speech2 = Float32List.fromList(List<double>.filled(1000, 0.30));
      final trailingSilence = Float32List(3000); // 3.0s pause -> flushes

      expect(vad.addSamples(speech1), isEmpty);
      expect(vad.addSamples(shortPause), isEmpty);
      expect(vad.addSamples(speech2), isEmpty);
      // 1000 + 1500 + 1000 = 3500 buffered so far
      expect(vad.bufferedSampleCount, 3500);

      final emitted = vad.addSamples(trailingSilence);
      expect(emitted, hasLength(1));
      expect(emitted.first.length, 6500);
      expect(vad.bufferedSampleCount, 0);
      expect(vad.hasDetectedSpeech, isFalse);
    });

    test('flushes chunk after ~3.0 seconds of trailing silence and emits on stream', () async {
      final vad = VadBuffer(
        sampleRate: 1000,
        silenceCutoff: const Duration(seconds: 3),
        maxChunkDuration: const Duration(seconds: 15),
        silenceThreshold: 0.02,
      );

      final streamChunks = <Float32List>[];
      final sub = vad.onChunkReady.listen(streamChunks.add);

      // 1 second of active speech (1000 samples @ 0.25 amplitude)
      final speechFrame = Float32List.fromList(
        List<double>.filled(1000, 0.25),
      );
      expect(vad.addSamples(speechFrame), isEmpty);
      expect(vad.hasDetectedSpeech, isTrue);
      expect(vad.bufferedSampleCount, 1000);

      // 2 seconds of silence -> not yet at 3.0s cutoff
      final twoSecSilence = Float32List(2000);
      expect(vad.addSamples(twoSecSilence), isEmpty);
      expect(vad.bufferedSampleCount, 3000);

      // Another 1 second of silence -> reaches 3.0s cutoff -> flushes!
      final oneSecSilence = Float32List(1000);
      final emitted = vad.addSamples(oneSecSilence);

      expect(emitted, hasLength(1));
      expect(emitted.first.length, 4000);
      expect(vad.hasDetectedSpeech, isFalse);
      expect(vad.bufferedSampleCount, 0);

      await Future<void>.delayed(Duration.zero);
      expect(streamChunks, hasLength(1));
      expect(streamChunks.first.length, 4000);

      await sub.cancel();
      await vad.dispose();
    });

    test('segments multiple sequential utterances across a session', () {
      final vad = VadBuffer(
        sampleRate: 1000,
        silenceCutoff: const Duration(seconds: 2),
        maxChunkDuration: const Duration(seconds: 15),
        silenceThreshold: 0.02,
      );

      // Utterance 1: 500 speech + 2000 silence = 2500
      final u1 = Float32List.fromList(<double>[
        ...List<double>.filled(500, 0.2),
        ...List<double>.filled(2000, 0.0),
      ]);
      // Leading silence between utterances: 1000 silence (ignored)
      final between = Float32List(1000);
      // Utterance 2: 800 speech + 2000 silence = 2800
      final u2 = Float32List.fromList(<double>[
        ...List<double>.filled(800, 0.4),
        ...List<double>.filled(2000, 0.0),
      ]);

      final c1 = vad.addSamples(u1);
      expect(c1, hasLength(1));
      expect(c1.first.length, 2500);

      expect(vad.addSamples(between), isEmpty);

      final c2 = vad.addSamples(u2);
      expect(c2, hasLength(1));
      expect(c2.first.length, 2800);
    });

    test('enforces 15.0 second hard ceiling during continuous speech', () {
      final vad = VadBuffer(
        sampleRate: 1000,
        silenceCutoff: const Duration(seconds: 3),
        maxChunkDuration: const Duration(seconds: 15),
        silenceThreshold: 0.02,
      );

      // Feed 16 seconds of continuous speech (16,000 samples at 1kHz)
      final continuousSpeech = Float32List.fromList(
        List<double>.filled(16000, 0.3),
      );

      final emitted = vad.addSamples(continuousSpeech);

      expect(emitted, hasLength(1));
      expect(emitted.first.length, 15000);
      // Remaining 1 second of speech stays buffered in the next window
      expect(vad.bufferedSampleCount, 1000);
      expect(vad.hasDetectedSpeech, isTrue);
    });

    test('emits multiple 15.0s chunks when fed 35 seconds of non-stop speech', () {
      final vad = VadBuffer(
        sampleRate: 1000,
        silenceCutoff: const Duration(seconds: 3),
        maxChunkDuration: const Duration(seconds: 15),
        silenceThreshold: 0.02,
      );

      final longSpeech = Float32List.fromList(
        List<double>.filled(35000, 0.25),
      );
      final emitted = vad.addSamples(longSpeech);

      expect(emitted, hasLength(2));
      expect(emitted[0].length, 15000);
      expect(emitted[1].length, 15000);
      expect(vad.bufferedSampleCount, 5000);
    });

    test('flush() emits partial utterance when stopped before 3s silence', () async {
      final vad = VadBuffer(sampleRate: 1000);
      final streamChunks = <Float32List>[];
      final sub = vad.onChunkReady.listen(streamChunks.add);

      vad.addSamples(Float32List.fromList(List<double>.filled(1200, 0.3)));
      expect(vad.bufferedSampleCount, 1200);

      final flushed = vad.flush();
      expect(flushed, isNotNull);
      expect(flushed!.length, 1200);
      expect(vad.bufferedSampleCount, 0);
      expect(vad.hasDetectedSpeech, isFalse);

      // Second flush on empty buffer returns null
      expect(vad.flush(), isNull);

      await Future<void>.delayed(Duration.zero);
      expect(streamChunks, hasLength(1));
      await sub.cancel();
      await vad.dispose();
    });

    test('reset() clears buffered speech without emitting a chunk', () async {
      final vad = VadBuffer(sampleRate: 1000);
      final streamChunks = <Float32List>[];
      final sub = vad.onChunkReady.listen(streamChunks.add);

      vad.addSamples(Float32List.fromList(List<double>.filled(2000, 0.3)));
      expect(vad.hasDetectedSpeech, isTrue);

      vad.reset();
      expect(vad.hasDetectedSpeech, isFalse);
      expect(vad.bufferedSampleCount, 0);

      await Future<void>.delayed(Duration.zero);
      expect(streamChunks, isEmpty);
      await sub.cancel();
      await vad.dispose();
    });

    test('minSpeechDuration discards brief transient clicks or breaths during pauses', () async {
      final vad = VadBuffer(
        sampleRate: 1000,
        silenceCutoff: const Duration(seconds: 2),
        maxChunkDuration: const Duration(seconds: 15),
        minSpeechDuration: const Duration(milliseconds: 350),
        silenceThreshold: 0.02,
      );

      final streamChunks = <Float32List>[];
      final sub = vad.onChunkReady.listen(streamChunks.add);

      // 50ms mic pop / breath (50 samples @ 0.25 < 350 required speech samples)
      // followed by 2.5s of silence
      final transientAndSilence = Float32List.fromList(<double>[
        ...List<double>.filled(50, 0.25),
        ...List<double>.filled(2500, 0.0),
      ]);

      final emitted = vad.addSamples(transientAndSilence);
      expect(emitted, isEmpty);
      expect(vad.bufferedSampleCount, 0);
      expect(vad.hasDetectedSpeech, isFalse);

      // Now 500ms of real speech (>= 350ms) followed by 2s of silence -> emitted!
      final realSpeechAndSilence = Float32List.fromList(<double>[
        ...List<double>.filled(500, 0.25),
        ...List<double>.filled(2000, 0.0),
      ]);
      final realEmitted = vad.addSamples(realSpeechAndSilence);
      expect(realEmitted, hasLength(1));
      expect(realEmitted.first.length, 2500);

      await Future<void>.delayed(Duration.zero);
      expect(streamChunks, hasLength(1));
      await sub.cancel();
      await vad.dispose();
    });

    test('VadBuffer.hasMeaningfulSpeech rejects silence and short clicks in full-length buffers', () {
      // 1 second of pure silence at 16kHz -> false
      final oneSecSilence = Float32List(16000);
      expect(VadBuffer.hasMeaningfulSpeech(oneSecSilence), isFalse);

      // 1 second buffer with only a 50ms transient click (800 samples) -> false (< 350ms)
      final clickInSilence = Float32List(16000);
      for (var i = 0; i < 800; i++) {
        clickInSilence[i] = 0.25;
      }
      expect(VadBuffer.hasMeaningfulSpeech(clickInSilence), isFalse);

      // 1 second buffer with 500ms of speech (8000 samples) -> true (>= 350ms)
      final validSpeech = Float32List(16000);
      for (var i = 0; i < 8000; i++) {
        validSpeech[i] = 0.25;
      }
      expect(VadBuffer.hasMeaningfulSpeech(validSpeech), isTrue);
    });

    test('emits onActiveSpeechSnapshot as soon as active speech reaches interval or short pause before silenceCutoff', () async {
      final vad = VadBuffer(
        sampleRate: 1000,
        silenceCutoff: const Duration(seconds: 2),
        minSpeechDuration: const Duration(milliseconds: 300),
        liveSnapshotInterval: const Duration(milliseconds: 600),
        livePauseSnapshotDelay: const Duration(milliseconds: 250),
        silenceThreshold: 0.02,
      );

      final snapshots = <Float32List>[];
      final finalChunks = <Float32List>[];
      final snapSub = vad.onActiveSpeechSnapshot.listen(snapshots.add);
      final chunkSub = vad.onChunkReady.listen(finalChunks.add);

      // 1. Feed 600ms of active speech -> triggers first live snapshot immediately while still speaking
      vad.addSamples(Float32List.fromList(List<double>.filled(600, 0.25)));
      await Future<void>.delayed(Duration.zero);
      expect(snapshots, hasLength(1));
      expect(snapshots.first.length, 600);
      expect(finalChunks, isEmpty);

      // 2. Feed another 300ms of active speech (total 900ms) followed by 300ms short pause (< 2s silenceCutoff)
      // -> triggers pause snapshot trimmed to the 900 active samples
      vad.addSamples(Float32List.fromList(List<double>.filled(300, 0.25)));
      vad.addSamples(Float32List(300));
      await Future<void>.delayed(Duration.zero);
      expect(snapshots, hasLength(2));
      expect(snapshots.last.length, 900);
      expect(finalChunks, isEmpty);

      // 3. Feed remaining 1700ms of silence to reach 2000ms silenceCutoff -> final chunk emitted, no extra snapshot
      vad.addSamples(Float32List(1700));
      await Future<void>.delayed(Duration.zero);
      expect(snapshots, hasLength(2));
      expect(finalChunks, hasLength(1));
      expect(finalChunks.single.length, 2900);

      await snapSub.cancel();
      await chunkSub.cancel();
      await vad.dispose();
    });
  });

  group('NativeAudioService', () {
    test('ignores pushSamples when capture is not active', () async {
      final service = NativeAudioService();
      expect(service.isCapturing, isFalse);

      final chunks = service.pushSamples(
        Float32List.fromList(List<double>.filled(500, 0.5)),
      );
      expect(chunks, isEmpty);
      await service.dispose();
    });

    test('streams raw frames, normalized amplitude, and VAD chunks from customFrameStreamProvider', () async {
      final controller = StreamController<Float32List>();
      final vad = VadBuffer(
        sampleRate: 1000,
        silenceCutoff: const Duration(seconds: 2),
        maxChunkDuration: const Duration(seconds: 10),
        silenceThreshold: 0.02,
      );
      final service = NativeAudioService(
        vadBuffer: vad,
        customFrameStreamProvider: () => controller.stream,
      );

      final rawFrames = <Float32List>[];
      final amplitudes = <double>[];
      final readyChunks = <Float32List>[];

      final rawSub = service.rawFrameStream.listen(rawFrames.add);
      final ampSub = service.amplitudeStream.listen(amplitudes.add);
      final chunkSub = service.audioChunkStream.listen(readyChunks.add);

      await service.startCapture();
      expect(service.isCapturing, isTrue);

      // Calling startCapture again while capturing is a no-op
      await service.startCapture();
      expect(service.isCapturing, isTrue);

      // Emit 1s speech (amplitude 0.1 -> normalized 0.5) + 2s silence
      controller.add(Float32List.fromList(List<double>.filled(1000, 0.1)));
      controller.add(Float32List(2000));
      await Future<void>.delayed(Duration.zero);

      expect(rawFrames, hasLength(2));
      expect(amplitudes, hasLength(2));
      expect(amplitudes.first, closeTo(0.5, 1e-5));
      expect(amplitudes.last, 0.0);
      expect(readyChunks, hasLength(1));
      expect(readyChunks.first.length, 3000);

      // Add partial speech and verify stopCapture flushes it and resets amplitude to 0.0
      controller.add(Float32List.fromList(List<double>.filled(600, 0.2)));
      await Future<void>.delayed(Duration.zero);

      final flushed = await service.stopCapture();
      expect(service.isCapturing, isFalse);
      expect(flushed, isNotNull);
      expect(flushed!.length, 600);
      expect(amplitudes.last, 0.0);

      // Calling stopCapture when already stopped returns null
      expect(await service.stopCapture(), isNull);

      await rawSub.cancel();
      await ampSub.cancel();
      await chunkSub.cancel();
      await controller.close();
      await service.dispose();
    });

    test('sets isCapturing to false when custom frame stream emits an error', () async {
      final controller = StreamController<Float32List>();
      final service = NativeAudioService(
        customFrameStreamProvider: () => controller.stream,
      );

      await service.startCapture();
      expect(service.isCapturing, isTrue);

      controller.addError(StateError('Hardware disconnected'));
      await Future<void>.delayed(Duration.zero);

      expect(service.isCapturing, isFalse);
      await controller.close();
      await service.dispose();
    });

    test('clamps normalized amplitude to [0.0, 1.0] for loud frames', () async {
      final service = NativeAudioService(
        customFrameStreamProvider: () => const Stream<Float32List>.empty(),
      );
      final amplitudes = <double>[];
      final sub = service.amplitudeStream.listen(amplitudes.add);

      await service.startCapture();
      service.pushSamples(Float32List.fromList(List<double>.filled(100, 0.9)));
      await Future<void>.delayed(Duration.zero);

      expect(amplitudes, <double>[1.0]);
      await sub.cancel();
      await service.dispose();
    });

    test('maps permission PlatformException to MicrophonePermissionException', () async {
      const controlChannel = MethodChannel('flutter_edge_ai_speech/audio_control');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(controlChannel, (call) async {
            throw PlatformException(
              code: 'PERMISSION_DENIED',
              message: 'User denied microphone access',
            );
          });

      final service = NativeAudioService(enablePlatformChannelInTests: true);
      await expectLater(
        service.startCapture(),
        throwsA(isA<MicrophonePermissionException>()),
      );
      expect(service.isCapturing, isFalse);

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(controlChannel, null);
      await service.dispose();
    });

    test('maps generic PlatformException to AudioCaptureException', () async {
      const controlChannel = MethodChannel('flutter_edge_ai_speech/audio_control');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(controlChannel, (call) async {
            throw PlatformException(
              code: 'AUDIO_ENGINE_FAILURE',
              message: 'Could not initialize input node',
            );
          });

      final service = NativeAudioService(enablePlatformChannelInTests: true);
      await expectLater(
        service.startCapture(),
        throwsA(isA<AudioCaptureException>()),
      );
      expect(service.isCapturing, isFalse);

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(controlChannel, null);
      await service.dispose();
    });

    test('receives Float32List and 16-bit PCM Uint8List payloads over EventChannel', () async {
      const controlChannel = MethodChannel('flutter_edge_ai_speech/audio_control');
      const streamChannel = EventChannel('flutter_edge_ai_speech/audio_stream');

      final methodCalls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(controlChannel, (call) async {
            methodCalls.add(call);
            return null;
          });

      MockStreamHandlerEventSink? eventSink;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
            streamChannel,
            MockStreamHandler.inline(
              onListen: (arguments, events) {
                eventSink = events;
              },
              onCancel: (arguments) {
                eventSink = null;
              },
            ),
          );

      final service = NativeAudioService(enablePlatformChannelInTests: true);
      final receivedFrames = <Float32List>[];
      final sub = service.rawFrameStream.listen(receivedFrames.add);

      await service.startCapture();
      expect(methodCalls.map((c) => c.method), contains('start'));
      expect(eventSink, isNotNull);

      // 1. Send Float32List payload
      eventSink!.success(Float32List.fromList(<double>[0.25, -0.25]));

      // 2. Send 16-bit PCM little-endian Uint8List payload (16384 -> 0.5, -16384 -> -0.5)
      final pcmBytes = Uint8List(4);
      ByteData.sublistView(pcmBytes)
        ..setInt16(0, 16384, Endian.little)
        ..setInt16(2, -16384, Endian.little);
      eventSink!.success(pcmBytes);

      // 3. Send Int16List payload (8192 -> 0.25)
      eventSink!.success(Int16List.fromList(<int>[8192]));

      // 4. Send List<Object?> payload
      eventSink!.success(<Object?>[0.125, -0.125]);

      await Future<void>.delayed(Duration.zero);

      expect(receivedFrames, hasLength(4));
      expect(receivedFrames[0][0], closeTo(0.25, 1e-5));
      expect(receivedFrames[1][0], closeTo(0.5, 1e-4));
      expect(receivedFrames[1][1], closeTo(-0.5, 1e-4));
      expect(receivedFrames[2][0], closeTo(0.25, 1e-4));
      expect(receivedFrames[3][0], closeTo(0.125, 1e-5));

      await service.stopCapture();
      expect(methodCalls.map((c) => c.method), contains('stop'));

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(controlChannel, null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(streamChannel, null);
      await sub.cancel();
      await service.dispose();
    });
  });

  group('AudioCaptureException & MicrophonePermissionException', () {
    test('formats AudioCaptureException with and without cause', () {
      const withoutCause = AudioCaptureException('Device busy');
      expect(withoutCause.message, 'Device busy');
      expect(withoutCause.cause, isNull);
      expect(withoutCause.toString(), 'AudioCaptureException: Device busy');

      final withCause = AudioCaptureException(
        'Failed to open stream',
        StateError('Bad state'),
      );
      expect(
        withCause.toString(),
        contains('AudioCaptureException: Failed to open stream (Bad state'),
      );
    });

    test('MicrophonePermissionException provides default and custom messages', () {
      const defaultPerm = MicrophonePermissionException();
      expect(defaultPerm, isA<AudioCaptureException>());
      expect(defaultPerm.message, 'Microphone permission was denied.');

      const customPerm = MicrophonePermissionException('Blocked in OS settings');
      expect(customPerm.message, 'Blocked in OS settings');
    });
  });

  group('VadBuffer background noise resilience', () {
    test('adapts noise floor to steady AC mechanical drone (saw / fan) and clears false speech onset', () async {
      final vad = VadBuffer(
        sampleRate: 16000,
        silenceCutoff: VadBuffer.interactiveSilenceCutoff,
        minSpeechDuration: VadBuffer.interactiveMinSpeechDuration,
        silenceThreshold: VadBuffer.interactiveSilenceThreshold, // 0.022
      );

      // Simulate 1.2 seconds of steady 250Hz AC saw/motor drone at ~0.05 RMS (> 0.022 threshold).
      final sawDrone = Float32List.fromList(
        List<double>.generate(
          19200,
          (i) => 0.05 * math.sqrt2 * math.sin(2 * math.pi * 250 * i / 16000),
        ),
      );

      final emitted = vad.addSamples(sawDrone);
      expect(emitted, isEmpty);
      // Noise floor adapted to ~0.05, raising effectiveSilenceThreshold to ~0.0875
      expect(vad.noiseFloorRms, closeTo(0.05, 0.005));
      expect(vad.effectiveSilenceThreshold, greaterThan(0.08));
      // False speech onset was cleared automatically so the mic does not stay stuck listening!
      expect(vad.hasDetectedSpeech, isFalse);
      expect(vad.bufferedSampleCount, 0);

      await vad.dispose();
    });

    test('rejects sustained high-ZCR sand grinder / hiss noise and clears false speech onset', () async {
      final vad = VadBuffer(
        sampleRate: 16000,
        silenceCutoff: VadBuffer.interactiveSilenceCutoff,
        minSpeechDuration: VadBuffer.interactiveMinSpeechDuration,
        silenceThreshold: VadBuffer.interactiveSilenceThreshold,
      );

      // Alternating +/- 0.055 signal over 1.2s has stationary envelope (CV = 0.0 < 0.10)
      final grinderNoise = Float32List.fromList(
        List<double>.generate(19200, (i) => i.isEven ? 0.055 : -0.055),
      );

      final emitted = vad.addSamples(grinderNoise);
      expect(emitted, isEmpty);
      expect(vad.hasDetectedSpeech, isFalse);
      expect(vad.bufferedSampleCount, 0);
      expect(vad.effectiveSilenceThreshold, greaterThan(0.08));

      await vad.dispose();
    });

    test('flushes speech chunk on schedule even when continuous saw noise persists after the speaker stops talking', () async {
      final vad = VadBuffer(
        sampleRate: 16000,
        silenceCutoff: const Duration(milliseconds: 1600),
        minSpeechDuration: const Duration(milliseconds: 350),
        silenceThreshold: 0.022,
      );

      // 1. 0.8s of loud active speech (~0.25 amplitude)
      final speech = Float32List.fromList(List<double>.filled(12800, 0.25));
      expect(vad.addSamples(speech), isEmpty);
      expect(vad.hasDetectedSpeech, isTrue);

      // 2. Speaker stops talking, but neighbor's saw runs continuously at ~0.05 RMS (> 0.022 static threshold)
      // for 1.8 seconds (28,800 samples).
      // After 1.0s of stationary saw noise, VadBuffer adapts the noise floor, credits the 1.0s
      // stationary tail as trailing silence, and flushes after the remaining 0.6s of saw noise!
      final trailingSawNoise = Float32List.fromList(
        List<double>.generate(
          28800,
          (i) => 0.05 * math.sqrt2 * math.sin(2 * math.pi * 250 * i / 16000),
        ),
      );

      final emitted = vad.addSamples(trailingSawNoise);
      expect(emitted, hasLength(1));
      expect(vad.hasDetectedSpeech, isFalse);
      expect(vad.bufferedSampleCount, 0);

      await vad.dispose();
    });

    test('reportNonSpeechAudio raises noiseFloorRms and clears stuck noise buffer when STT reports non-speech', () async {
      final vad = VadBuffer(
        sampleRate: 16000,
        silenceCutoff: const Duration(milliseconds: 1600),
        silenceThreshold: 0.022,
      );

      // Irregular clatter at ~0.06 RMS triggers speech onset
      final clatter = Float32List.fromList(List<double>.filled(9600, 0.06));
      vad.addSamples(clatter);
      expect(vad.hasDetectedSpeech, isTrue);

      // STT evaluates the 600ms snapshot and reports no speech -> reportNonSpeechAudio
      vad.reportNonSpeechAudio(clatter);
      expect(vad.noiseFloorRms, closeTo(0.06, 0.005));
      expect(vad.effectiveSilenceThreshold, closeTo(0.06 * 1.75, 0.005));
      expect(vad.hasDetectedSpeech, isFalse);
      expect(vad.bufferedSampleCount, 0);

      await vad.dispose();
    });

    test('interactive micro-chunking constants and VadSpeechChunk acoustic timestamps track speechStartTime and speechEndTime', () async {
      expect(
        VadBuffer.interactiveSilenceCutoff,
        const Duration(milliseconds: 500),
      );
      expect(
        VadBuffer.interactiveMaxChunkDuration,
        const Duration(seconds: 6),
      );
      expect(
        VadBuffer.interactiveLiveSnapshotInterval,
        const Duration(milliseconds: 1800),
      );
      expect(
        VadBuffer.interactiveLivePauseSnapshotDelay,
        Duration.zero,
      );

      var currentNow = DateTime.utc(2026, 10, 25, 18, 0, 0);
      final vad = VadBuffer(
        sampleRate: 1000,
        silenceCutoff: VadBuffer.interactiveSilenceCutoff,
        maxChunkDuration: VadBuffer.interactiveMaxChunkDuration,
        minSpeechDuration: VadBuffer.interactiveMinSpeechDuration,
        liveSnapshotInterval: VadBuffer.interactiveLiveSnapshotInterval,
        livePauseSnapshotDelay: VadBuffer.interactiveLivePauseSnapshotDelay,
        silenceThreshold: 0.02,
        clock: () => currentNow,
      );

      final timedChunks = <VadSpeechChunk>[];
      final sub = vad.onTimedChunkReady.listen(timedChunks.add);

      // 1. 800ms of active speech at t=0.0s .. t=0.8s
      vad.addSamples(Float32List.fromList(List<double>.filled(800, 0.25)));
      currentNow = currentNow.add(const Duration(milliseconds: 800));

      // 2. 500ms of trailing silence -> reaches 500ms interactiveSilenceCutoff and flushes!
      vad.addSamples(Float32List(500));
      await Future<void>.delayed(Duration.zero);

      expect(timedChunks, hasLength(1));
      final chunk = timedChunks.single;
      expect(chunk.samples.length, 1300);
      expect(chunk.speechStartTime, DateTime.utc(2026, 10, 25, 18, 0, 0));
      expect(
        chunk.speechEndTime,
        DateTime.utc(2026, 10, 25, 18, 0, 0, 800),
      );
      expect(chunk.speechDuration, const Duration(milliseconds: 800));
      expect(vad.lastEmittedTimedChunk, same(chunk));

      await sub.cancel();
      await vad.dispose();
    });
  });
}
