import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:translation_app/core/audio/audio_exceptions.dart';
import 'package:translation_app/core/audio/vad_buffer.dart';
import 'package:translation_app/core/audio/web_audio_recorder.dart';
import 'package:translation_app/core/logging/app_logger.dart';
import 'package:translation_app/core/utils/platform_env.dart';

/// Native microphone capture service streaming 16kHz mono 32-bit floating-point
/// PCM frames (`Float32List`) and segmenting utterances via [VadBuffer].
class NativeAudioService {
  NativeAudioService({
    VadBuffer? vadBuffer,
    this._customFrameStreamProvider,
    this.enablePlatformChannelInTests = false,
  }) : _vadBuffer = vadBuffer ?? VadBuffer();

  static final _log = AppLogger.of('NativeAudioService');

  static const MethodChannel _controlChannel = MethodChannel(
    'flutter_edge_ai_speech/audio_control',
  );
  static const EventChannel _streamChannel = EventChannel(
    'flutter_edge_ai_speech/audio_stream',
  );

  final VadBuffer _vadBuffer;
  final Stream<Float32List> Function()? _customFrameStreamProvider;
  final bool enablePlatformChannelInTests;

  final StreamController<Float32List> _rawFrameController =
      StreamController<Float32List>.broadcast();
  final StreamController<double> _amplitudeController =
      StreamController<double>.broadcast();

  StreamSubscription<Float32List>? _customStreamSub;
  StreamSubscription<Object?>? _nativeStreamSub;
  WebAudioRecorder? _webRecorder;
  bool _isCapturing = false;
  int _frameCount = 0;

  /// Whether microphone capture is currently active.
  bool get isCapturing => _isCapturing;

  /// Underlying [VadBuffer] instance.
  VadBuffer get vadBuffer => _vadBuffer;

  /// Emits VAD-segmented 16kHz mono [Float32List] audio chunks ready for
  /// multimodal translation.
  Stream<Float32List> get audioChunkStream => _vadBuffer.onChunkReady;

  /// Emits cumulative 16kHz mono [Float32List] audio snapshots as soon as
  /// active speech is detected and progressing, allowing live translation
  /// before the utterance ends.
  Stream<Float32List> get activeSpeechSnapshotStream =>
      _vadBuffer.onActiveSpeechSnapshot;

  /// Emits raw 16kHz mono [Float32List] frames as they arrive.
  Stream<Float32List> get rawFrameStream => _rawFrameController.stream;

  /// Emits normalized audio amplitude (`0.0` to `1.0`) for UI feedback.
  Stream<double> get amplitudeStream => _amplitudeController.stream;

  /// Starts streaming 16kHz mono `Float32List` PCM audio from the microphone.
  Future<void> startCapture() async {
    final isTestEnv = isFlutterTestEnvironment;
    _log.info(
      'startCapture() requested: isCapturing=$_isCapturing, '
      'hasCustomStream=${_customFrameStreamProvider != null}, '
      'isTestEnv=$isTestEnv, enablePlatformChannelInTests=$enablePlatformChannelInTests',
    );

    if (_isCapturing) {
      _log.info('startCapture() ignored because capture is already active.');
      return;
    }
    _vadBuffer.reset();
    _frameCount = 0;
    _isCapturing = true;

    if (_customFrameStreamProvider != null) {
      _log.info('Subscribing to custom audio frame stream provider...');
      final stream = _customFrameStreamProvider();
      _customStreamSub = stream.listen(
        pushSamples,
        onError: (Object error, StackTrace st) {
          _log.severe('Error on custom audio frame stream', error, st);
          _isCapturing = false;
        },
      );
      return;
    }

    if (isTestEnv && !enablePlatformChannelInTests) {
      _log.info(
        'FLUTTER_TEST environment detected (platform channel disabled) -> ready for pushSamples().',
      );
      return;
    }

    if (kIsWeb) {
      try {
        _log.info('Starting WebAudioRecorder at ${VadBuffer.defaultSampleRate}Hz...');
        final webRecorder = WebAudioRecorder(
          onSamples: pushSamples,
          targetSampleRate: VadBuffer.defaultSampleRate,
        );
        _webRecorder = webRecorder;
        await webRecorder.start();
        _log.info('Browser microphone capture is now LIVE.');
        return;
      } on Object {
        _isCapturing = false;
        _webRecorder = null;
        rethrow;
      }
    }

    try {
      _log.info(
        'Invoking native MethodChannel("${_controlChannel.name}").start(sampleRate=${VadBuffer.defaultSampleRate}, channels=1)...',
      );
      await _controlChannel.invokeMethod<void>('start', <String, Object>{
        'sampleRate': VadBuffer.defaultSampleRate,
        'channels': 1,
      });
      _log.info(
        'Native audio_control "start" succeeded. Subscribing to EventChannel("${_streamChannel.name}")...',
      );
      _nativeStreamSub = _streamChannel.receiveBroadcastStream().listen(
        _handleNativePayload,
        onError: (Object error, StackTrace st) {
          _log.severe('Error received from native audio_stream EventChannel', error, st);
        },
        onDone: () {
          _log.info('Native audio_stream EventChannel closed (onDone).');
        },
      );
      _log.info('Microphone capture is now LIVE and listening for PCM frames.');
    } on MissingPluginException catch (e, st) {
      if (isTestEnv) {
        _log.warning(
          'MissingPluginException in test environment; staying ready for pushSamples().',
        );
        return;
      }
      _isCapturing = false;
      _log.severe(
        'MissingPluginException on ${_controlChannel.name}! '
        'The native microphone plugin is not registered. '
        'Please stop and re-run the app (flutter run) so native iOS/Android changes are compiled.',
        e,
        st,
      );
      throw AudioCaptureException(
        'Native microphone channel is not registered on this platform. '
        'Perform a full restart (flutter stop && flutter run) to load native audio capture.',
        e,
      );
    } on PlatformException catch (e, st) {
      _isCapturing = false;
      _log.severe(
        'PlatformException starting native audio capture: code=${e.code}, message=${e.message}, details=${e.details}',
        e,
        st,
      );
      if (e.code.toLowerCase().contains('permission')) {
        throw MicrophonePermissionException(
          e.message ?? 'Microphone permission denied.',
        );
      }
      throw AudioCaptureException(
        e.message ?? 'Failed to start native audio capture.',
        e,
      );
    }
  }

  /// Stops microphone capture and flushes any remaining speech in [VadBuffer].
  Future<Float32List?> stopCapture() async {
    _log.info(
      'stopCapture() requested: isCapturing=$_isCapturing, '
      'totalFramesReceived=$_frameCount, '
      'bufferedSamples=${_vadBuffer.bufferedSampleCount}',
    );
    if (!_isCapturing) return null;
    _isCapturing = false;

    final customSub = _customStreamSub;
    _customStreamSub = null;
    if (customSub != null) {
      unawaited(customSub.cancel());
    }

    final webRecorder = _webRecorder;
    _webRecorder = null;
    if (webRecorder != null) {
      try {
        await webRecorder.stop();
      } on Object catch (e) {
        _log.warning('Ignored error stopping WebAudioRecorder: $e');
      }
    }

    final nativeSub = _nativeStreamSub;
    _nativeStreamSub = null;
    if (nativeSub != null) {
      unawaited(nativeSub.cancel());
      try {
        _log.info('Invoking native MethodChannel("${_controlChannel.name}").stop()...');
        await _controlChannel.invokeMethod<void>('stop');
        _log.info('Native audio_control "stop" succeeded.');
      } on Object catch (e) {
        _log.warning('Ignored error stopping native audio_control channel: $e');
      }
    }

    if (!_amplitudeController.isClosed) {
      _amplitudeController.add(0.0);
    }

    final flushed = _vadBuffer.flush();
    _log.info(
      'stopCapture() finished: flushedChunk=${flushed != null ? "${flushed.length} samples" : "null"}',
    );
    return flushed;
  }

  /// Feeds a 16kHz mono [Float32List] frame into the capture pipeline and VAD.
  List<Float32List> pushSamples(Float32List samples) {
    if (!_isCapturing || samples.isEmpty) {
      return const <Float32List>[];
    }
    _frameCount++;

    if (!_rawFrameController.isClosed) {
      _rawFrameController.add(samples);
    }

    final rms = VadBuffer.computeRms(samples);
    final normalized = (rms * 5.0).clamp(0.0, 1.0);
    if (!_amplitudeController.isClosed) {
      _amplitudeController.add(normalized);
    }

    final emitted = _vadBuffer.addSamples(samples);

    if (_frameCount == 1 || _frameCount % 25 == 0 || emitted.isNotEmpty) {
      _log.info(
        '[AUDIO FRAME #$_frameCount] len=${samples.length}, '
        'rms=${rms.toStringAsFixed(4)} vs threshold=${_vadBuffer.effectiveSilenceThreshold.toStringAsFixed(4)} '
        '(noiseFloor=${_vadBuffer.noiseFloorRms.toStringAsFixed(4)}), '
        'amp=${normalized.toStringAsFixed(2)}, '
        'speechDetected=${_vadBuffer.hasDetectedSpeech}, '
        'activeSpeech=${_vadBuffer.activeSpeechSamples}/${_vadBuffer.minSpeechSamples}, '
        'buffered=${_vadBuffer.bufferedSampleCount} samples '
        '(${(_vadBuffer.bufferedSampleCount / _vadBuffer.sampleRate).toStringAsFixed(2)}s), '
        'trailingSilence=${_vadBuffer.trailingSilenceSamples}/${_vadBuffer.silenceCutoffSamples}, '
        'emittedChunks=${emitted.length}',
      );
    }

    return emitted;
  }

  /// Notifies the underlying [VadBuffer] that [nonSpeechSamples] was evaluated
  /// by the STT model and found to contain only background noise / no speech.
  void reportNonSpeechAudio(Float32List nonSpeechSamples) {
    _vadBuffer.reportNonSpeechAudio(nonSpeechSamples);
    if (!_vadBuffer.hasDetectedSpeech && !_amplitudeController.isClosed) {
      _amplitudeController.add(0.0);
    }
  }

  void _handleNativePayload(Object? event) {
    if (_frameCount == 0) {
      _log.info(
        'First native audio payload arrived from EventChannel: runtimeType=${event.runtimeType}',
      );
    }
    if (event is Float32List) {
      pushSamples(event);
    } else if (event is Uint8List) {
      // Convert 16-bit PCM little-endian bytes to normalized Float32List [-1, 1].
      final sampleCount = event.length ~/ 2;
      final byteData = ByteData.sublistView(event);
      final floatSamples = Float32List(sampleCount);
      for (var i = 0; i < sampleCount; i++) {
        floatSamples[i] = byteData.getInt16(i * 2, Endian.little) / 32768.0;
      }
      pushSamples(floatSamples);
    } else if (event is Int16List) {
      final floatSamples = Float32List(event.length);
      for (var i = 0; i < event.length; i++) {
        floatSamples[i] = event[i] / 32768.0;
      }
      pushSamples(floatSamples);
    } else if (event is List<double>) {
      pushSamples(Float32List.fromList(event));
    } else if (event is List<Object?>) {
      final floatSamples = Float32List(event.length);
      for (var i = 0; i < event.length; i++) {
        final item = event[i];
        if (item is int) {
          floatSamples[i] = item / 32768.0;
        } else if (item is double) {
          floatSamples[i] = item;
        }
      }
      pushSamples(floatSamples);
    } else {
      _log.warning(
        'Received unrecognized payload type from native audio_stream: ${event.runtimeType}',
      );
    }
  }

  Future<void> dispose() async {
    _log.info('Disposing NativeAudioService...');
    await stopCapture();
    await _vadBuffer.dispose();
    unawaited(_rawFrameController.close());
    unawaited(_amplitudeController.close());
  }
}
