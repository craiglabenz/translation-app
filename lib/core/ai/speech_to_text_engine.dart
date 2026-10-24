import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:translation_app/core/ai/language_detector.dart';
import 'package:translation_app/core/ai/local_translation_engine.dart';
import 'package:translation_app/core/ai/model_manager.dart';
import 'package:translation_app/core/audio/vad_buffer.dart';
import 'package:translation_app/core/data/models/app_settings.dart';
import 'package:translation_app/core/logging/app_logger.dart';

part 'speech_to_text_engine.freezed.dart';
part 'speech_to_text_engine.g.dart';

/// Signature for executing on-device Whisper transcription on 16kHz mono
/// 16-bit little-endian PCM bytes.
typedef WhisperTranscribeRunner =
    Future<String> Function(
      Uint8List pcm16kMono, {
      String? language,
    });

/// Structured output of the Speech-to-Text (STT) step (Step 1 of the
/// separated translation pipeline).
@freezed
abstract class SpeechToTextResult with _$SpeechToTextResult {
  const factory SpeechToTextResult({
    required String transcript,
    required String detectedLanguageCode,
    required int durationMs,
    String? modelName,
  }) = _SpeechToTextResult;

  factory SpeechToTextResult.fromJson(Map<String, Object?> json) =>
      _$SpeechToTextResultFromJson(json);
}

/// Abstract contract for Step 1: Speech-to-Text (ASR) and language detection.
abstract class SpeechToTextEngine {
  Future<void> initialize();

  Future<SpeechToTextResult> transcribeAudio({
    required Float32List audioWavChunk,
    required String baseLanguage,
    required String targetLanguage,
  });

  Future<void> dispose();
}

/// On-device Speech-to-Text engine powered by Edge Whisper variants
/// (`whisper-base-int8`, `whisper-tiny-int8`, `whisper-tiny-f32`) via
/// `flutter_edge_ai_speech` and `LiteRtSttBackend`.
class WhisperSpeechToTextEngine implements SpeechToTextEngine {
  WhisperSpeechToTextEngine({
    required this.modelManager,
    this.modelIdProvider,
    this.transcribeRunner,
  });

  static final _log = AppLogger.of('WhisperSpeechToTextEngine');

  final ModelManager modelManager;
  final String Function()? modelIdProvider;
  final WhisperTranscribeRunner? transcribeRunner;

  SpeechRecognizer? _recognizer;
  String? _loadedModelId;
  bool _initialized = false;

  bool get isInitialized => _initialized;

  /// Resolves the currently configured Whisper model ID.
  String get activeModelId {
    final configured =
        (modelIdProvider?.call() ?? AppSettings.defaultOnDeviceSttModelId)
            .trim();
    final model = AppSettings.onDeviceSttModelFor(configured);
    return model.isWhisper ? model.id : AppSettings.defaultOnDeviceSttModelId;
  }

  /// Normalizes a language name or BCP-47 tag into a bare 2- or 3-letter
  /// lowercase code accepted by Whisper's tokenizer (`<|en|>`, `<|es|>`, etc.).
  static String normalizeWhisperLanguageCode(String language) {
    final code = LanguageDetector.normalizeLanguageCode(language)
        .toLowerCase()
        .split(RegExp('[-_]'))
        .first;
    final mapped = switch (code) {
      'fil' => 'tl',
      'iw' => 'he',
      'in' => 'id',
      'nb' || 'nn' => 'no',
      _ => code,
    };
    if (RegExp(r'^[a-z]{2,3}$').hasMatch(mapped)) {
      return mapped;
    }
    return 'en';
  }

  /// Encodes 16kHz mono float32 PCM samples (`[-1.0, 1.0]`) into raw 16-bit
  /// little-endian PCM bytes (`pcm16kMono`) expected by `SpeechRecognizer.transcribe`.
  static Uint8List encodeFloat32PcmToInt16Bytes(Float32List samples) {
    final pcmBytes = Uint8List(samples.length * 2);
    final view = ByteData.sublistView(pcmBytes);
    for (var i = 0; i < samples.length; i++) {
      final clamped = samples[i].clamp(-1.0, 1.0);
      final pcm16 = (clamped * 32767.0).round().clamp(-32768, 32767);
      view.setInt16(i * 2, pcm16, Endian.little);
    }
    return pcmBytes;
  }

  /// Offloads trailing silence trimming and 16-bit PCM encoding to a background
  /// isolate when the sample buffer is large.
  static Future<(Uint8List pcmBytes, int trimmedSampleCount)>
  encodePcm16InIsolate(
    Float32List samples, {
    int isolateThresholdSamples = 4000,
  }) async {
    if (kIsWeb || samples.length < isolateThresholdSamples) {
      final trimmed = LocalTranslationEngine.trimTrailingSilence(samples);
      return (encodeFloat32PcmToInt16Bytes(trimmed), trimmed.length);
    }
    final transferableSamples = Float32List.fromList(samples);
    return Isolate.run(() {
      final trimmed = LocalTranslationEngine.trimTrailingSilence(
        transferableSamples,
      );
      return (encodeFloat32PcmToInt16Bytes(trimmed), trimmed.length);
    });
  }

  @override
  Future<void> initialize() async {
    final targetId = activeModelId;
    if (_initialized &&
        _loadedModelId == targetId &&
        (transcribeRunner != null || _recognizer != null)) {
      return;
    }

    if (transcribeRunner != null) {
      _loadedModelId = targetId;
      _initialized = true;
      return;
    }

    final variant = AppSettings.onDeviceSttModelFor(targetId);
    _log.info(
      'initialize(): ensuring Edge Whisper model (${variant.name}) is downloaded...',
    );
    final ready = await modelManager.ensureWhisperModelDownloaded(variant.id);
    if (!ready) {
      final errMsg =
          modelManager.stateValue.whisperError ??
          'Edge Whisper model (${variant.name}) is not installed on device.';
      throw StateError(errMsg);
    }

    // Ensure the requested Whisper variant is the active STT spec in FlutterEdgeAi
    final activeSpec = FlutterEdgeAi.activeSttSpec;
    if (activeSpec == null || !variant.filename.startsWith(activeSpec.name)) {
      await FlutterEdgeAi.installStt()
          .modelFromNetwork(variant.modelUrl!)
          .tokenizerFromNetwork(variant.tokenizerUrl!)
          .ofType(SttModelType.whisper)
          .install();
    }

    _recognizer = await FlutterEdgeAi.getActiveStt();
    _loadedModelId = targetId;
    _initialized = true;
    _log.info('initialize(): Edge Whisper (${variant.name}) recognizer ready.');
  }

  @override
  Future<SpeechToTextResult> transcribeAudio({
    required Float32List audioWavChunk,
    required String baseLanguage,
    required String targetLanguage,
  }) async {
    if (audioWavChunk.isEmpty) {
      throw ArgumentError('Audio chunk cannot be empty.');
    }

    final baseCode = LanguageDetector.normalizeLanguageCode(baseLanguage);
    final targetCode = LanguageDetector.normalizeLanguageCode(targetLanguage);
    final variantName = AppSettings.onDeviceSttModelFor(activeModelId).name;

    if (audioWavChunk.length >= 4000 &&
        !VadBuffer.hasMeaningfulSpeech(audioWavChunk)) {
      return SpeechToTextResult(
        transcript: '',
        detectedLanguageCode: baseCode,
        durationMs: 0,
        modelName: variantName,
      );
    }

    final stopwatch = Stopwatch()..start();

    if (!_initialized || _loadedModelId != activeModelId) {
      await initialize();
    }

    final (pcm16Bytes, trimmedSamples) = await encodePcm16InIsolate(
      audioWavChunk,
    );
    final whisperBaseCode = normalizeWhisperLanguageCode(baseLanguage);
    final whisperTargetCode = normalizeWhisperLanguageCode(targetLanguage);

    _log.info(
      'transcribeAudio() [Whisper:$activeModelId] started: samples=$trimmedSamples '
      '(pcm16Bytes=${pcm16Bytes.length}), pair=$baseCode <-> $targetCode',
    );

    Future<String> runWhisper(String langCode) {
      final runner = transcribeRunner;
      if (runner != null) {
        return runner(pcm16Bytes, language: langCode);
      }
      final rec = _recognizer;
      if (rec == null) {
        throw StateError('Whisper SpeechRecognizer is not initialized.');
      }
      return rec.transcribe(pcm16Bytes, language: langCode);
    }

    var rawTranscript = (await runWhisper(whisperBaseCode)).trim();

    if ((rawTranscript.isEmpty ||
            LocalTranslationEngine.isNonSpeechOrHallucination(
              translatedText: rawTranscript,
            )) &&
        whisperTargetCode != whisperBaseCode) {
      final retryTranscript = (await runWhisper(whisperTargetCode)).trim();
      if (retryTranscript.isNotEmpty &&
          !LocalTranslationEngine.isNonSpeechOrHallucination(
            translatedText: retryTranscript,
          )) {
        rawTranscript = retryTranscript;
      }
    }

    stopwatch.stop();
    final elapsedMs = stopwatch.elapsedMilliseconds;

    if (rawTranscript.isEmpty ||
        LocalTranslationEngine.isNonSpeechOrHallucination(
          translatedText: rawTranscript,
        )) {
      _log.info(
        'transcribeAudio() [Whisper:$activeModelId] detected silence/non-speech '
        'in ${elapsedMs}ms.',
      );
      return SpeechToTextResult(
        transcript: '',
        detectedLanguageCode: baseCode,
        durationMs: elapsedMs,
        modelName: variantName,
      );
    }

    final detected = LanguageDetector.detectLanguage(
      rawTranscript,
      candidateA: baseCode,
      candidateB: targetCode,
    );
    final resolvedLanguage = detected ?? baseCode;

    _log.info(
      'transcribeAudio() [Whisper:$activeModelId] finished in ${elapsedMs}ms: '
      'detected="$resolvedLanguage", transcript="$rawTranscript"',
    );

    return SpeechToTextResult(
      transcript: rawTranscript,
      detectedLanguageCode: resolvedLanguage,
      durationMs: elapsedMs,
      modelName: variantName,
    );
  }

  @override
  Future<void> dispose() async {
    _initialized = false;
    _loadedModelId = null;
    final rec = _recognizer;
    _recognizer = null;
    if (rec != null) {
      await rec.close();
    }
  }
}
