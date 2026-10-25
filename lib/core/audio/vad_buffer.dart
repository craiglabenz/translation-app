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
    this.liveSnapshotInterval = const Duration(milliseconds: 600),
    this.livePauseSnapshotDelay = const Duration(milliseconds: 300),
    this.enableAdaptiveNoiseFloor = true,
    this.noiseFloorMarginMultiplier = 1.75,
    this.maxAdaptiveSilenceThreshold = 0.16,
    this.stationaryNoiseWindow = const Duration(milliseconds: 1000),
  }) : assert(sampleRate > 0, 'sampleRate must be positive');

  static const int defaultSampleRate = 16000;

  /// Responsive 1.6-second silence cutoff for live interactive conversation,
  /// allowing natural mid-sentence breathing pauses without premature flushes.
  static const Duration interactiveSilenceCutoff = Duration(milliseconds: 1600);

  /// Minimum active speech duration required in live interactive mode so brief
  /// clicks, taps, or breaths during a pause do not trigger hallucinated turns.
  static const Duration interactiveMinSpeechDuration = Duration(
    milliseconds: 200,
  );

  /// RMS threshold for live microphone capture to reject quiet room hum while
  /// remaining sensitive to normal conversational speech.
  static const double interactiveSilenceThreshold = 0.015;

  /// Coefficient of variation (`stdDev / mean`) below which a sustained AC
  /// signal is classified as stationary mechanical/background noise (e.g., a
  /// saw, grinder, fan, or engine drone) rather than syllable-modulated speech.
  static const double stationaryEnvelopeCvThreshold = 0.10;

  static final _log = AppLogger.of('VadBuffer');

  final int sampleRate;
  final Duration silenceCutoff;
  final Duration maxChunkDuration;
  final double silenceThreshold;
  final Duration minSpeechDuration;

  /// Interval of active speech accumulation after which a live in-progress
  /// audio snapshot is emitted to [onActiveSpeechSnapshot] so translation can
  /// begin while the speaker is still talking.
  final Duration liveSnapshotInterval;

  /// Short pause duration after active speech that triggers an immediate live
  /// audio snapshot on [onActiveSpeechSnapshot] before the full [silenceCutoff]
  /// expires.
  final Duration livePauseSnapshotDelay;

  /// Whether to dynamically track the ambient noise floor and adapt the silence
  /// threshold upward during sustained background noise (saws, fans, traffic).
  final bool enableAdaptiveNoiseFloor;

  /// Multiplier applied to [noiseFloorRms] to compute [effectiveSilenceThreshold].
  final double noiseFloorMarginMultiplier;

  /// Upper bound on [effectiveSilenceThreshold] so normal near-field speech is
  /// never masked even in loud environments.
  final double maxAdaptiveSilenceThreshold;

  /// Rolling window duration used to detect unmodulated stationary background
  /// drones (e.g. a neighbor's saw or sand grinder).
  final Duration stationaryNoiseWindow;

  final List<double> _buffer = <double>[];
  final List<double> _recentAcWindowRms = <double>[];
  int _trailingSilenceSamples = 0;
  int _activeSpeechSamples = 0;
  int _lastActiveSampleEndIndex = 0;
  int _lastSnapshotActiveSpeechSamples = 0;
  int _lastSnapshotEndIndex = 0;
  double _noiseFloorRms = 0.0;
  double _peakActiveWindowRms = 0.0;
  bool _hasDetectedSpeech = false;

  final StreamController<Float32List> _chunkController =
      StreamController<Float32List>.broadcast();

  final StreamController<Float32List> _snapshotController =
      StreamController<Float32List>.broadcast();

  /// Stream of segmented 16kHz mono [Float32List] audio chunks emitted when an
  /// utterance finishes.
  Stream<Float32List> get onChunkReady => _chunkController.stream;

  /// Stream of cumulative 16kHz mono [Float32List] audio snapshots emitted as
  /// soon as active speech is detected and progressing, allowing live
  /// translation before the utterance ends.
  Stream<Float32List> get onActiveSpeechSnapshot => _snapshotController.stream;

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

  /// Number of active speech samples between periodic live snapshots.
  int get liveSnapshotIntervalSamples =>
      (sampleRate * liveSnapshotInterval.inMicroseconds) ~/
      Duration.microsecondsPerSecond;

  /// Number of trailing silent samples required to trigger an early pause snapshot.
  int get livePauseSnapshotSamples =>
      (sampleRate * livePauseSnapshotDelay.inMicroseconds) ~/
      Duration.microsecondsPerSecond;

  /// Number of samples in the rolling stationary-noise evaluation window.
  int get stationaryNoiseWindowSamples =>
      (sampleRate * stationaryNoiseWindow.inMicroseconds) ~/
      Duration.microsecondsPerSecond;

  /// Current number of buffered samples.
  int get bufferedSampleCount => _buffer.length;

  /// Current number of consecutive trailing silent samples.
  int get trailingSilenceSamples => _trailingSilenceSamples;

  /// Current number of active speech samples accumulated in the buffer.
  int get activeSpeechSamples => _activeSpeechSamples;

  /// True if speech has been detected in the current accumulation window.
  bool get hasDetectedSpeech => _hasDetectedSpeech;

  /// Dynamically tracked ambient noise floor RMS.
  double get noiseFloorRms => _noiseFloorRms;

  /// Effective RMS threshold required for a window to count as active speech,
  /// adapting upward above [silenceThreshold] when sustained ambient noise is present.
  double get effectiveSilenceThreshold {
    if (!enableAdaptiveNoiseFloor || _noiseFloorRms <= 0.0) {
      return silenceThreshold;
    }
    return (_noiseFloorRms * noiseFloorMarginMultiplier).clamp(
      silenceThreshold,
      math.max(silenceThreshold, maxAdaptiveSilenceThreshold),
    );
  }

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

  /// Computes the Zero-Crossing Rate (ZCR) of [samples] in `[0.0, 1.0]`.
  static double computeZeroCrossingRate(Float32List samples) {
    if (samples.length < 2) return 0.0;
    var crossings = 0;
    for (var i = 1; i < samples.length; i++) {
      final prev = samples[i - 1];
      final curr = samples[i];
      if ((prev >= 0.0 && curr < 0.0) || (prev < 0.0 && curr >= 0.0)) {
        crossings++;
      }
    }
    return crossings / (samples.length - 1);
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
    return false;
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
    final stationaryTargetWindows = math.max(
      10,
      stationaryNoiseWindowSamples ~/ windowSize,
    );

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
      final windowZcr = computeZeroCrossingRate(windowView);

      if (enableAdaptiveNoiseFloor) {
        _updateAdaptiveNoiseState(
          windowRms: windowRms,
          windowZcr: windowZcr,
          windowSize: windowSize,
          stationaryTargetWindows: stationaryTargetWindows,
        );
      }

      final currentThreshold = effectiveSilenceThreshold;
      final isWindowSilent = windowRms < currentThreshold;

      if (!isWindowSilent && windowRms > _peakActiveWindowRms) {
        _peakActiveWindowRms = windowRms;
      }

      for (var i = windowStart; i < windowEnd; i++) {
        final sample = samples[i];
        final isSampleSilent = windowSize > 1
            ? isWindowSilent
            : (isWindowSilent && sample.abs() < currentThreshold);

        if (!isSampleSilent) {
          if (!_hasDetectedSpeech) {
            _log.info(
              '[VAD SPEECH ONSET] windowRms=${windowRms.toStringAsFixed(4)} >= '
              'threshold=${currentThreshold.toStringAsFixed(4)} '
              '(noiseFloor=${_noiseFloorRms.toStringAsFixed(4)}, zcr=${windowZcr.toStringAsFixed(3)}) '
              '-> started accumulating utterance buffer.',
            );
          }
          _hasDetectedSpeech = true;
          _trailingSilenceSamples = 0;
          _activeSpeechSamples++;
          _buffer.add(sample);
          _lastActiveSampleEndIndex = _buffer.length;
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
            '[VAD HARD CEILING] Reached ${_buffer.length} samples (${durationSec}s, '
            'activeSpeech=$_activeSpeechSamples samples, peakRms=${_peakActiveWindowRms.toStringAsFixed(4)}) -> flushing chunk.',
          );
          final chunk = _drainBufferIfValid();
          if (chunk != null) {
            emitted.add(chunk);
          }
          continue;
        }

        // 2. Check silence cutoff (~1.6s / 3.0s of trailing silence after speech).
        if (_hasDetectedSpeech &&
            _trailingSilenceSamples >= silenceCutoffSamples) {
          final durationSec = (_buffer.length / sampleRate).toStringAsFixed(2);
          _log.info(
            '[VAD SILENCE CUTOFF] Reached trailingSilence=$_trailingSilenceSamples/$silenceCutoffSamples samples '
            '(activeSpeech=$_activeSpeechSamples/$minSpeechSamples required, '
            'totalChunk=${_buffer.length} samples / ${durationSec}s, peakRms=${_peakActiveWindowRms.toStringAsFixed(4)}) -> evaluating chunk.',
          );
          final chunk = _drainBufferIfValid();
          if (chunk != null) {
            emitted.add(chunk);
          }
        }
      }
    }

    _maybeEmitActiveSpeechSnapshot();

    return emitted;
  }

  void _updateAdaptiveNoiseState({
    required double windowRms,
    required double windowZcr,
    required int windowSize,
    required int stationaryTargetWindows,
  }) {
    // Track stationary AC mechanical drone (saw, sand grinder, fan, AC hum).
    // Synthetic DC test signals have windowZcr == 0.0 and are intentionally excluded.
    if (windowZcr > 0.01 &&
        windowRms >= silenceThreshold &&
        windowRms < 0.085) {
      _recentAcWindowRms.add(windowRms);
      while (_recentAcWindowRms.length > stationaryTargetWindows) {
        _recentAcWindowRms.removeAt(0);
      }

      if (_recentAcWindowRms.length >= stationaryTargetWindows) {
        final mean =
            _recentAcWindowRms.reduce((a, b) => a + b) /
            _recentAcWindowRms.length;
        if (mean > 0.0) {
          var varianceSum = 0.0;
          for (final v in _recentAcWindowRms) {
            final diff = v - mean;
            varianceSum += diff * diff;
          }
          final stdDev = math.sqrt(varianceSum / _recentAcWindowRms.length);
          final cv = stdDev / mean;

          if (cv < stationaryEnvelopeCvThreshold) {
            final maxAllowedFloor =
                maxAdaptiveSilenceThreshold / noiseFloorMarginMultiplier;
            final updatedFloor = math.max(
              _noiseFloorRms,
              math.min(mean, maxAllowedFloor),
            );
            if ((updatedFloor - _noiseFloorRms).abs() > 0.002) {
              _log.info(
                'Stationary background noise detected (meanRms=${mean.toStringAsFixed(4)}, '
                'cv=${cv.toStringAsFixed(3)}) -> adapting noiseFloor=${updatedFloor.toStringAsFixed(4)}, '
                'effectiveThreshold=${(updatedFloor * noiseFloorMarginMultiplier).toStringAsFixed(4)}.',
              );
            }
            _noiseFloorRms = updatedFloor;
            final adaptedThreshold = effectiveSilenceThreshold;

            if (_hasDetectedSpeech) {
              if (_peakActiveWindowRms < adaptedThreshold) {
                _log.info(
                  'Buffer contained only stationary background noise '
                  '(peakRms=${_peakActiveWindowRms.toStringAsFixed(4)} < '
                  'adaptedThreshold=${adaptedThreshold.toStringAsFixed(4)}) -> resetting false speech onset.',
                );
                _clearUtteranceBuffer();
              } else {
                // Real speech occurred earlier in the buffer, followed by a
                // stationary noise tail: reclassify the stationary tail as
                // trailing silence so the utterance can finish promptly.
                final stationarySamples =
                    _recentAcWindowRms.length * windowSize;
                if (_trailingSilenceSamples < stationarySamples) {
                  final credit = math.min(
                    _activeSpeechSamples,
                    stationarySamples - _trailingSilenceSamples,
                  );
                  _activeSpeechSamples = math.max(
                    0,
                    _activeSpeechSamples - credit,
                  );
                  _trailingSilenceSamples += credit;
                  _lastActiveSampleEndIndex = math.max(
                    0,
                    _buffer.length - _trailingSilenceSamples,
                  );
                }
              }
            }
          }
        }
      }
    } else {
      _recentAcWindowRms.clear();
      if (_noiseFloorRms > 0.0 && windowRms < effectiveSilenceThreshold) {
        _noiseFloorRms = _noiseFloorRms * 0.90 + windowRms * 0.10;
        if (_noiseFloorRms < silenceThreshold * 0.6) {
          _noiseFloorRms = 0.0;
        }
      }
    }
  }

  /// Notifies the VAD that the STT model evaluated [nonSpeechSamples] and
  /// determined it contained only background noise / no clear human speech.
  ///
  /// Raises [noiseFloorRms] to cover the rejected audio's RMS and clears any
  /// false speech accumulation if no louder speech has arrived since.
  void reportNonSpeechAudio(Float32List nonSpeechSamples) {
    if (!enableAdaptiveNoiseFloor || nonSpeechSamples.isEmpty) return;
    final rms = computeRms(nonSpeechSamples);
    if (rms >= silenceThreshold) {
      final maxAllowedFloor =
          maxAdaptiveSilenceThreshold / noiseFloorMarginMultiplier;
      _noiseFloorRms = math.max(
        _noiseFloorRms,
        math.min(rms, maxAllowedFloor),
      );
    }
    if (_hasDetectedSpeech &&
        _peakActiveWindowRms < effectiveSilenceThreshold) {
      _log.info(
        'reportNonSpeechAudio(): STT confirmed non-speech (rms=${rms.toStringAsFixed(4)}) '
        '-> adapted noiseFloor=${_noiseFloorRms.toStringAsFixed(4)} and cleared false speech onset.',
      );
      _clearUtteranceBuffer();
    }
  }

  void _maybeEmitActiveSpeechSnapshot() {
    if (!_hasDetectedSpeech ||
        _buffer.isEmpty ||
        _snapshotController.isClosed ||
        _lastActiveSampleEndIndex <= _lastSnapshotEndIndex) {
      return;
    }

    final intervalSamples = liveSnapshotIntervalSamples;
    final pauseSamples = livePauseSnapshotSamples;
    final fallbackMinSpeech = math.max(
      1,
      math.min(
        intervalSamples > 0 ? intervalSamples : sampleRate ~/ 4,
        pauseSamples > 0 ? pauseSamples : sampleRate ~/ 4,
      ),
    );
    final requiredSpeech = minSpeechSamples > 0
        ? minSpeechSamples
        : fallbackMinSpeech;

    if (_activeSpeechSamples < requiredSpeech) {
      if (pauseSamples > 0 && _trailingSilenceSamples >= pauseSamples && _lastSnapshotEndIndex == 0) {
        _log.info(
          '[VAD SNAPSHOT HELD] Pause detected (trailingSilence=$_trailingSilenceSamples >= $pauseSamples), '
          'but activeSpeechSamples=$_activeSpeechSamples < requiredSpeech=$requiredSpeech '
          '(${(requiredSpeech * 1000) ~/ sampleRate}ms) -> waiting for more speech.',
        );
      }
      return;
    }

    final hasIntervalTrigger =
        intervalSamples > 0 &&
        (_activeSpeechSamples - _lastSnapshotActiveSpeechSamples) >=
            intervalSamples;
    final hasPauseTrigger =
        pauseSamples > 0 && _trailingSilenceSamples >= pauseSamples;

    if (!hasIntervalTrigger && !hasPauseTrigger) {
      return;
    }

    final snapshotEnd = math.min(_lastActiveSampleEndIndex, _buffer.length);
    if (snapshotEnd <= 0) return;

    final snapshot = Float32List.fromList(_buffer.sublist(0, snapshotEnd));
    _lastSnapshotActiveSpeechSamples = _activeSpeechSamples;
    _lastSnapshotEndIndex = snapshotEnd;

    final durationSec = (snapshot.length / sampleRate).toStringAsFixed(2);
    _log.info(
      '[VAD SNAPSHOT EMIT] Emitting live active-speech snapshot '
      '(${snapshot.length} samples / ${durationSec}s, '
      'activeSpeech=$_activeSpeechSamples, trailingSilence=$_trailingSilenceSamples, '
      'peakRms=${_peakActiveWindowRms.toStringAsFixed(4)}, '
      'trigger=${hasIntervalTrigger ? "interval" : "pause"}).',
    );
    _snapshotController.add(snapshot);
  }

  /// Flushes any currently buffered speech samples (e.g. when stopping a session).
  Float32List? flush() {
    _log.info(
      '[VAD FLUSH] flush() called: hasDetectedSpeech=$_hasDetectedSpeech, '
      'activeSpeechSamples=$_activeSpeechSamples, '
      'bufferedSamples=${_buffer.length} '
      '(${(_buffer.length / sampleRate).toStringAsFixed(2)}s)',
    );
    if (!_hasDetectedSpeech || _buffer.isEmpty) {
      _clearUtteranceBuffer();
      return null;
    }
    return _drainBufferIfValid();
  }

  void _clearUtteranceBuffer() {
    _buffer.clear();
    _trailingSilenceSamples = 0;
    _activeSpeechSamples = 0;
    _lastActiveSampleEndIndex = 0;
    _lastSnapshotActiveSpeechSamples = 0;
    _lastSnapshotEndIndex = 0;
    _peakActiveWindowRms = 0.0;
    _hasDetectedSpeech = false;
  }

  /// Resets the buffer without emitting a chunk.
  ///
  /// When [preserveNoiseFloor] is `true`, keeps the learned [noiseFloorRms] so
  /// ambient background noise remains suppressed across turns.
  void reset({bool preserveNoiseFloor = false}) {
    _clearUtteranceBuffer();
    if (!preserveNoiseFloor) {
      _recentAcWindowRms.clear();
      _noiseFloorRms = 0.0;
    }
  }

  Float32List? _drainBufferIfValid() {
    if (_buffer.isEmpty) {
      _clearUtteranceBuffer();
      return null;
    }
    final requiredSpeech = minSpeechSamples;
    if (requiredSpeech > 0 && _activeSpeechSamples < requiredSpeech) {
      _log.info(
        '[VAD CHUNK DISCARDED] Transient noise/short sound during pause: '
        'activeSpeechSamples=$_activeSpeechSamples < minSpeechSamples=$requiredSpeech '
        '(${minSpeechDuration.inMilliseconds}ms, peakRms=${_peakActiveWindowRms.toStringAsFixed(4)}).',
      );
      _clearUtteranceBuffer();
      return null;
    }
    final chunk = Float32List.fromList(_buffer);
    final durationSec = (chunk.length / sampleRate).toStringAsFixed(2);
    _log.info(
      '[VAD CHUNK EMIT] Emitting final utterance chunk: ${chunk.length} samples (~${durationSec}s, '
      'activeSpeech=$_activeSpeechSamples samples, peakRms=${_peakActiveWindowRms.toStringAsFixed(4)}).',
    );
    _clearUtteranceBuffer();
    if (!_chunkController.isClosed) {
      _chunkController.add(chunk);
    }
    return chunk;
  }

  Future<void> dispose() async {
    reset();
    unawaited(_chunkController.close());
    unawaited(_snapshotController.close());
  }
}
