import 'dart:js_interop';
import 'dart:typed_data';

import 'package:translation_app/core/audio/audio_exceptions.dart';
import 'package:translation_app/core/logging/app_logger.dart';

@JS('navigator.mediaDevices')
external _JSMediaDevices? get _mediaDevices;

extension type _JSMediaDevices(JSObject _) implements JSObject {
  external JSPromise<_JSMediaStream> getUserMedia(JSObject constraints);
}

extension type _JSMediaStream(JSObject _) implements JSObject {
  external JSArray<_JSMediaStreamTrack> getTracks();
}

extension type _JSMediaStreamTrack(JSObject _) implements JSObject {
  external void stop();
}

@JS('AudioContext')
extension type _JSAudioContext._(JSObject _) implements JSObject {
  external factory _JSAudioContext([JSObject? options]);
  external num get sampleRate;
  external String get state;
  external JSPromise<JSAny?> resume();
  external JSPromise<JSAny?> close();
  external _JSMediaStreamAudioSourceNode createMediaStreamSource(
    _JSMediaStream stream,
  );
  external _JSScriptProcessorNode createScriptProcessor(
    int bufferSize,
    int numberOfInputChannels,
    int numberOfOutputChannels,
  );
  external _JSGainNode createGain();
  external JSObject get destination;
}

extension type _JSAudioNode(JSObject _) implements JSObject {
  external void connect(JSObject destination);
  external void disconnect();
}

extension type _JSMediaStreamAudioSourceNode(JSObject _)
    implements _JSAudioNode {}

extension type _JSGainNode(JSObject _) implements _JSAudioNode {
  external _JSAudioParam get gain;
}

extension type _JSAudioParam(JSObject _) implements JSObject {
  external set value(num val);
}

extension type _JSScriptProcessorNode(JSObject _) implements _JSAudioNode {
  external set onaudioprocess(JSFunction? handler);
}

extension type _JSAudioProcessingEvent(JSObject _) implements JSObject {
  external _JSAudioBuffer get inputBuffer;
}

extension type _JSAudioBuffer(JSObject _) implements JSObject {
  external int get numberOfChannels;
  external JSFloat32Array getChannelData(int channel);
}

/// Browser microphone capture implementation using Web Audio API (`getUserMedia`
/// + `AudioContext`), downsampling to [targetSampleRate] (16kHz mono `Float32List`).
class WebAudioRecorder {
  WebAudioRecorder({
    required this.onSamples,
    required this.targetSampleRate,
  });

  static final _log = AppLogger.of('WebAudioRecorder');

  final void Function(Float32List samples) onSamples;
  final int targetSampleRate;

  _JSMediaStream? _mediaStream;
  _JSAudioContext? _audioContext;
  _JSMediaStreamAudioSourceNode? _sourceNode;
  _JSScriptProcessorNode? _processorNode;
  _JSGainNode? _silentGainNode;
  bool _running = false;

  bool get isSupported => _mediaDevices != null;

  Future<void> start() async {
    final devices = _mediaDevices;
    if (devices == null) {
      throw const AudioCaptureException(
        'Browser microphone capture requires a secure context (HTTPS or localhost).',
      );
    }

    try {
      final constraints = <String, Object?>{
        'audio': <String, Object?>{
          'channelCount': 1,
          'sampleRate': targetSampleRate,
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': false,
      }.jsify()! as JSObject;

      _mediaStream = await devices.getUserMedia(constraints).toDart;
    } on Object catch (e) {
      final errStr = e.toString();
      if (errStr.contains('NotAllowedError') ||
          errStr.contains('PermissionDenied') ||
          errStr.toLowerCase().contains('permission')) {
        throw MicrophonePermissionException(
          'Browser microphone permission was denied: $errStr',
        );
      }
      throw AudioCaptureException(
        'Failed to access browser microphone: $errStr',
        e,
      );
    }

    try {
      final contextOptions = <String, Object?>{
        'sampleRate': targetSampleRate,
      }.jsify()! as JSObject;

      final audioCtx = _JSAudioContext(contextOptions);
      _audioContext = audioCtx;
      if (audioCtx.state == 'suspended') {
        await audioCtx.resume().toDart;
      }

      final actualSampleRate = audioCtx.sampleRate.round();
      _log.info(
        'WebAudioRecorder AudioContext started: actualSampleRate=${actualSampleRate}Hz, '
        'targetSampleRate=${targetSampleRate}Hz',
      );

      final source = audioCtx.createMediaStreamSource(_mediaStream!);
      final processor = audioCtx.createScriptProcessor(4096, 1, 1);
      final silentGain = audioCtx.createGain();
      silentGain.gain.value = 0;

      _sourceNode = source;
      _processorNode = processor;
      _silentGainNode = silentGain;
      _running = true;

      processor.onaudioprocess = ((_JSAudioProcessingEvent event) {
        if (!_running) return;
        final inputBuffer = event.inputBuffer;
        if (inputBuffer.numberOfChannels < 1) return;
        final rawSamples = Float32List.fromList(
          inputBuffer.getChannelData(0).toDart,
        );
        if (rawSamples.isEmpty) return;

        final samples = actualSampleRate == targetSampleRate
            ? rawSamples
            : _downsample(rawSamples, actualSampleRate, targetSampleRate);
        if (samples.isNotEmpty) {
          onSamples(samples);
        }
      }).toJS;

      source.connect(processor);
      processor.connect(silentGain);
      silentGain.connect(audioCtx.destination);
    } on Object catch (e) {
      await stop();
      throw AudioCaptureException(
        'Failed to initialize Web AudioContext pipeline: $e',
        e,
      );
    }
  }

  Future<void> stop() async {
    _running = false;
    try {
      _processorNode?.onaudioprocess = null;
      _processorNode?.disconnect();
    } on Object catch (_) {}
    _processorNode = null;

    try {
      _sourceNode?.disconnect();
    } on Object catch (_) {}
    _sourceNode = null;

    try {
      _silentGainNode?.disconnect();
    } on Object catch (_) {}
    _silentGainNode = null;

    final ctx = _audioContext;
    _audioContext = null;
    if (ctx != null) {
      try {
        await ctx.close().toDart;
      } on Object catch (_) {}
    }

    final stream = _mediaStream;
    _mediaStream = null;
    if (stream != null) {
      try {
        final tracks = stream.getTracks().toDart;
        for (final track in tracks) {
          track.stop();
        }
      } on Object catch (_) {}
    }
  }

  static Float32List _downsample(
    Float32List input,
    int inputRate,
    int outputRate,
  ) {
    if (inputRate <= 0 || outputRate <= 0 || inputRate == outputRate) {
      return input;
    }
    final ratio = inputRate / outputRate;
    final outputLength = (input.length / ratio).floor();
    if (outputLength <= 0) return Float32List(0);

    final result = Float32List(outputLength);
    var offsetResult = 0;
    var offsetBuffer = 0.0;
    while (offsetResult < result.length) {
      final nextOffsetBuffer = (offsetResult + 1) * ratio;
      var accum = 0.0;
      var count = 0;
      final start = offsetBuffer.floor();
      final end = nextOffsetBuffer.floor().clamp(0, input.length);
      for (var i = start; i < end; i++) {
        accum += input[i];
        count++;
      }
      result[offsetResult] = count > 0
          ? accum / count
          : input[start.clamp(0, input.length - 1)];
      offsetResult++;
      offsetBuffer = nextOffsetBuffer;
    }
    return result;
  }
}
