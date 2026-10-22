import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:translation_app/core/logging/app_logger.dart';

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
    this.minSpeechDuration = Duration.zero,
  }) : assert(sampleRate > 0, 'sampleRate must be positive');

  static const int defaultSampleRate = 16000;

  /// Responsive 1.6-second silence cutoff for live interactive conversation,
  /// allowing natural mid-sentence breathing pauses without premature flushes.
  static const Duration interactiveSilenceCutoff = Duration(milliseconds: 1600);

  /// Minimum active speech duration required in live interactive mode so brief
  /// clicks, taps, or breaths during a pause do not trigger hallucinated turns.
  static const Duration interactiveMinSpeechDuration = Duration(
    milliseconds: 350,
  );

  /// Slightly higher RMS threshold for live microphone capture to reject room hum.
  static const double interactiveSilenceThreshold = 0.022;

  static final _log = AppLogger.of('VadBuffer');

  final int sampleRate;
  final Duration silenceCutoff;
  final Duration maxChunkDuration;
  final double silenceThreshold;
  final Duration minSpeechDuration;

  final List<double> _buffer = <double>[];
  int _trailingSilenceSamples = 0;
  int _activeSpeechSamples = 0;
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

  /// Minimum number of active speech samples required before a chunk is emitted.
  int get minSpeechSamples =>
      (sampleRate * minSpeechDuration.inMicroseconds) ~/
      Duration.microsecondsPerSecond;

  /// Current number of buffered samples.
  int get bufferedSampleCount => _buffer.length;

  /// Current number of consecutive trailing silent samples.
  int get trailingSilenceSamples => _trailingSilenceSamples;

  /// Current number of active speech samples accumulated in the buffer.
  int get activeSpeechSamples => _activeSpeechSamples;

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

  /// Returns `true` if [samples] contains enough above-threshold energy to
  /// represent human speech rather than silence or a brief click.
  static bool hasMeaningfulSpeech(
    Float32List samples, {
    double silenceThreshold = 0.015,
    int sampleRate = defaultSampleRate,
    Duration minSpeechDuration = const Duration(milliseconds: 250),
  }) {
    if (samples.isEmpty) return false;
    final minWindowLength = sampleRate ~/ 4; // 250ms
    if (samples.length < minWindowLength) {
      return computeRms(samples) >= silenceThreshold;
    }

    final windowSize = math.max(1, sampleRate ~/ 50); // 20ms
    final requiredActiveSamples = math.min(
      samples.length ~/ 2,
      (sampleRate * minSpeechDuration.inMicroseconds) ~/
          Duration.microsecondsPerSecond,
    );

    var activeSamples = 0;
    for (var start = 0; start < samples.length; start += windowSize) {
      final end = math.min(start + windowSize, samples.length);
      final view = Float32List.sublistView(samples, start, end);
      if (computeRms(view) >= silenceThreshold) {
        activeSamples += (end - start);
        if (activeSamples >= requiredActiveSamples) {
          return true;
        }
      }
    }
    return activeSamples >= requiredActiveSamples;
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
      final windowRms = computeRms(windowView);
      final isWindowSilent = windowRms < silenceThreshold;

      for (var i = windowStart; i < windowEnd; i++) {
        final sample = samples[i];
        final isSampleSilent = windowSize > 1
            ? isWindowSilent
            : (isWindowSilent && sample.abs() < silenceThreshold);

        if (!isSampleSilent) {
          if (!_hasDetectedSpeech) {
            _log.info(
              'Speech onset detected! windowRms=${windowRms.toStringAsFixed(4)}, '
              'sample=${sample.toStringAsFixed(4)}, threshold=$silenceThreshold',
            );
          }
          _hasDetectedSpeech = true;
          _trailingSilenceSamples = 0;
          _activeSpeechSamples++;
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
          final durationSec = (_buffer.length / sampleRate).toStringAsFixed(2);
          _log.info(
            'VAD hard ceiling reached (${_buffer.length} samples / ${durationSec}s, '
            'activeSpeechSamples=$_activeSpeechSamples) -> flushing chunk.',
          );
          final chunk = _drainBufferIfValid();
          if (chunk != null) {
            emitted.add(chunk);
          }
          continue;
        }

        // 2. Check silence cutoff (~3.0 seconds of trailing silence after speech).
        if (_hasDetectedSpeech &&
            _trailingSilenceSamples >= silenceCutoffSamples) {
          final durationSec = (_buffer.length / sampleRate).toStringAsFixed(2);
          _log.info(
            'VAD silence cutoff reached (trailingSilence=$_trailingSilenceSamples samples, '
            'activeSpeechSamples=$_activeSpeechSamples, '
            'totalChunk=${_buffer.length} samples / ${durationSec}s) -> evaluating chunk.',
          );
          final chunk = _drainBufferIfValid();
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
    _log.info(
      'flush() called: hasDetectedSpeech=$_hasDetectedSpeech, '
      'activeSpeechSamples=$_activeSpeechSamples, '
      'bufferedSamples=${_buffer.length} '
      '(${(_buffer.length / sampleRate).toStringAsFixed(2)}s)',
    );
    if (!_hasDetectedSpeech || _buffer.isEmpty) {
      reset();
      return null;
    }
    return _drainBufferIfValid();
  }

  /// Resets the buffer without emitting a chunk.
  void reset() {
    _buffer.clear();
    _trailingSilenceSamples = 0;
    _activeSpeechSamples = 0;
    _hasDetectedSpeech = false;
  }

  Float32List? _drainBufferIfValid() {
    if (_buffer.isEmpty) {
      reset();
      return null;
    }
    final requiredSpeech = minSpeechSamples;
    if (requiredSpeech > 0 && _activeSpeechSamples < requiredSpeech) {
      _log.info(
        'Discarding transient noise during pause: activeSpeechSamples=$_activeSpeechSamples '
        '< minSpeechSamples=$requiredSpeech (${minSpeechDuration.inMilliseconds}ms).',
      );
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
