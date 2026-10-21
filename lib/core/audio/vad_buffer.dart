import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

/// Voice Activity Detector (VAD) and audio frame accumulator for 16kHz mono
/// 32-bit floating-point PCM streams.
///
/// - Accumulates audio frames once speech is detected (`rms >= silenceThreshold`).
/// - Flushes a [Float32List] chunk when trailing silence reaches
///   [silenceCutoff] (default: 3.0 seconds).
/// - Enforces a hard safety ceiling at [maxChunkDuration] (default: 15.0 seconds)
///   of accumulated audio, immediately emitting a chunk and resetting the buffer.
class VadBuffer {
  VadBuffer({
    this.sampleRate = defaultSampleRate,
    this.silenceCutoff = const Duration(seconds: 3),
    this.maxChunkDuration = const Duration(seconds: 15),
    this.silenceThreshold = 0.015,
  }) : assert(sampleRate > 0, 'sampleRate must be positive');

  static const int defaultSampleRate = 16000;

  final int sampleRate;
  final Duration silenceCutoff;
  final Duration maxChunkDuration;
  final double silenceThreshold;

  final List<double> _buffer = <double>[];
  int _trailingSilenceSamples = 0;
  bool _hasDetectedSpeech = false;

  final StreamController<Float32List> _chunkController =
      StreamController<Float32List>.broadcast();

  /// Stream of segmented 16kHz mono [Float32List] audio chunks.
  Stream<Float32List> get onChunkReady => _chunkController.stream;

  /// Maximum number of samples allowed before a hard ceiling flush (240,000 at 16kHz / 15s).
  int get maxSamples =>
      (sampleRate * maxChunkDuration.inMicroseconds) ~/
      Duration.microsecondsPerSecond;

  /// Number of consecutive silent samples required to trigger a silence cutoff (48,000 at 16kHz / 3s).
  int get silenceCutoffSamples =>
      (sampleRate * silenceCutoff.inMicroseconds) ~/
      Duration.microsecondsPerSecond;

  /// Current number of buffered samples.
  int get bufferedSampleCount => _buffer.length;

  /// True if speech has been detected in the current accumulation window.
  bool get hasDetectedSpeech => _hasDetectedSpeech;

  /// Computes the Root Mean Square (RMS) energy of [samples].
  static double computeRms(Float32List samples) {
    if (samples.isEmpty) return 0.0;
    var sumSquares = 0.0;
    for (var i = 0; i < samples.length; i++) {
      final s = samples[i];
      sumSquares += s * s;
    }
    return math.sqrt(sumSquares / samples.length);
  }

  /// Feeds 16kHz mono [samples] into the VAD buffer and returns any chunks
  /// that were flushed during this call (also emitted to [onChunkReady]).
  List<Float32List> addSamples(Float32List samples) {
    if (samples.isEmpty) return const <Float32List>[];

    final emitted = <Float32List>[];
    // Evaluate RMS in 20ms windows (min 1 sample) so zero-crossings in active
    // speech are not mistaken for silence, while multi-second buffers containing
    // both speech and trailing silence still segment accurately.
    final windowSize = math.max(1, sampleRate ~/ 50);

    for (
      var windowStart = 0;
      windowStart < samples.length;
      windowStart += windowSize
    ) {
      final windowEnd = math.min(windowStart + windowSize, samples.length);
      final windowView = Float32List.sublistView(
        samples,
        windowStart,
        windowEnd,
      );
      final isWindowSilent = computeRms(windowView) < silenceThreshold;

      for (var i = windowStart; i < windowEnd; i++) {
        final sample = samples[i];
        final isSampleSilent =
            isWindowSilent && sample.abs() < silenceThreshold;

        if (!isSampleSilent) {
          _hasDetectedSpeech = true;
          _trailingSilenceSamples = 0;
          _buffer.add(sample);
        } else if (_hasDetectedSpeech) {
          _buffer.add(sample);
          _trailingSilenceSamples++;
        } else {
          // Ignore leading silence before speech starts.
          continue;
        }

        // 1. Check hard ceiling (15.0 seconds).
        if (_buffer.length >= maxSamples) {
          final chunk = _drainBuffer();
          if (chunk != null) {
            emitted.add(chunk);
          }
          continue;
        }

        // 2. Check silence cutoff (~3.0 seconds of trailing silence after speech).
        if (_hasDetectedSpeech &&
            _trailingSilenceSamples >= silenceCutoffSamples) {
          final chunk = _drainBuffer();
          if (chunk != null) {
            emitted.add(chunk);
          }
        }
      }
    }

    return emitted;
  }

  /// Flushes any currently buffered speech samples (e.g. when stopping a session).
  Float32List? flush() {
    if (!_hasDetectedSpeech || _buffer.isEmpty) {
      reset();
      return null;
    }
    return _drainBuffer();
  }

  /// Resets the buffer without emitting a chunk.
  void reset() {
    _buffer.clear();
    _trailingSilenceSamples = 0;
    _hasDetectedSpeech = false;
  }

  Float32List? _drainBuffer() {
    if (_buffer.isEmpty) {
      reset();
      return null;
    }
    final chunk = Float32List.fromList(_buffer);
    reset();
    if (!_chunkController.isClosed) {
      _chunkController.add(chunk);
    }
    return chunk;
  }

  Future<void> dispose() async {
    reset();
    unawaited(_chunkController.close());
  }
}
