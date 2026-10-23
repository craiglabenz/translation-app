import 'dart:typed_data';

/// Stub implementation of [WebAudioRecorder] for non-web platforms.
class WebAudioRecorder {
  WebAudioRecorder({
    required this.onSamples,
    required this.targetSampleRate,
  });

  final void Function(Float32List samples) onSamples;
  final int targetSampleRate;

  bool get isSupported => false;

  Future<void> start() async {
    throw UnsupportedError('WebAudioRecorder is only supported on web.');
  }

  Future<void> stop() async {}
}
