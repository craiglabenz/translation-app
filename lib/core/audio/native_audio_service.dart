import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:translation_app/core/audio/audio_exceptions.dart';
import 'package:translation_app/core/audio/vad_buffer.dart';

/// Native microphone capture service streaming 16kHz mono 32-bit floating-point
/// PCM frames (`Float32List`) and segmenting utterances via [VadBuffer].
class NativeAudioService {
  NativeAudioService({
    VadBuffer? vadBuffer,
    this._customFrameStreamProvider,
    this.enablePlatformChannelInTests = false,
  }) : _vadBuffer = vadBuffer ?? VadBuffer();

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
  bool _isCapturing = false;

  /// Whether microphone capture is currently active.
  bool get isCapturing => _isCapturing;

  /// Underlying [VadBuffer] instance.
  VadBuffer get vadBuffer => _vadBuffer;

  /// Emits VAD-segmented 16kHz mono [Float32List] audio chunks ready for
  /// multimodal translation.
  Stream<Float32List> get audioChunkStream => _vadBuffer.onChunkReady;

  /// Emits raw 16kHz mono [Float32List] frames as they arrive.
  Stream<Float32List> get rawFrameStream => _rawFrameController.stream;

  /// Emits normalized audio amplitude (`0.0` to `1.0`) for UI feedback.
  Stream<double> get amplitudeStream => _amplitudeController.stream;

  /// Starts streaming 16kHz mono `Float32List` PCM audio from the microphone.
  Future<void> startCapture() async {
    if (_isCapturing) return;
    _vadBuffer.reset();
    _isCapturing = true;

    if (_customFrameStreamProvider != null) {
      final stream = _customFrameStreamProvider();
      _customStreamSub = stream.listen(
        pushSamples,
        onError: (Object error) {
          _isCapturing = false;
        },
      );
      return;
    }

    if (Platform.environment.containsKey('FLUTTER_TEST') &&
        !enablePlatformChannelInTests) {
      return;
    }

    try {
      await _controlChannel.invokeMethod<void>('start', <String, Object>{
        'sampleRate': VadBuffer.defaultSampleRate,
        'channels': 1,
      });
      _nativeStreamSub = _streamChannel.receiveBroadcastStream().listen(
        _handleNativePayload,
        onError: (Object _) {},
      );
    } on MissingPluginException {
      // Running in an environment without the native audio channel attached
      // (e.g. desktop preview or widget tests); stays ready for pushSamples().
    } on PlatformException catch (e) {
      _isCapturing = false;
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
    if (!_isCapturing) return null;
    _isCapturing = false;

    final customSub = _customStreamSub;
    _customStreamSub = null;
    if (customSub != null) {
      unawaited(customSub.cancel());
    }

    final nativeSub = _nativeStreamSub;
    _nativeStreamSub = null;
    if (nativeSub != null) {
      unawaited(nativeSub.cancel());
      try {
        await _controlChannel.invokeMethod<void>('stop');
      } on Object {
        // Ignore if native channel is not bound.
      }
    }

    if (!_amplitudeController.isClosed) {
      _amplitudeController.add(0.0);
    }

    return _vadBuffer.flush();
  }

  /// Feeds a 16kHz mono [Float32List] frame into the capture pipeline and VAD.
  List<Float32List> pushSamples(Float32List samples) {
    if (!_isCapturing || samples.isEmpty) {
      return const <Float32List>[];
    }
    if (!_rawFrameController.isClosed) {
      _rawFrameController.add(samples);
    }
    if (!_amplitudeController.isClosed) {
      final rms = VadBuffer.computeRms(samples);
      final normalized = (rms * 5.0).clamp(0.0, 1.0);
      _amplitudeController.add(normalized);
    }
    return _vadBuffer.addSamples(samples);
  }

  void _handleNativePayload(Object? event) {
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
    } else if (event is List<double>) {
      pushSamples(Float32List.fromList(event));
    }
  }

  Future<void> dispose() async {
    await stopCapture();
    await _vadBuffer.dispose();
    unawaited(_rawFrameController.close());
    unawaited(_amplitudeController.close());
  }
}
