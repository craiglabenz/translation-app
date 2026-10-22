import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:translation_app/core/ai/language_detector.dart';
import 'package:translation_app/core/ai/model_manager.dart';
import 'package:translation_app/core/ai/prompt_templates.dart';
import 'package:translation_app/core/ai/translation_engine.dart';
import 'package:translation_app/core/audio/vad_buffer.dart';
import 'package:translation_app/core/data/models/app_settings.dart';
import 'package:translation_app/core/data/models/message.dart' as domain;
import 'package:translation_app/core/logging/app_logger.dart';

/// Signature for executing multimodal audio + prompt inference.
typedef AudioInferenceRunner =
    Future<String> Function({
      required Uint8List wavBytes,
      required String systemPrompt,
    });

/// Signature for streaming multimodal audio + prompt inference token chunks.
typedef AudioStreamingInferenceRunner =
    Stream<String> Function({
      required Uint8List wavBytes,
      required String systemPrompt,
      required String userPrompt,
    });

/// Signature for executing a fast text-to-text fallback translation pass when
/// the audio pass transcribes without translating.
typedef TextInferenceRunner =
    Future<String> Function({
      required String prompt,
      required String systemPrompt,
    });

/// On-device translation engine powered by Gemma 4 (E2B) on `LiteRtLmEngine`.
class LocalTranslationEngine implements TranslationEngine {
  LocalTranslationEngine({
    required this._modelManager,
    this._inferenceRunner,
    this._streamingInferenceRunner,
    this._textInferenceRunner,
  });

  static final _log = AppLogger.of('LocalTranslationEngine');

  final ModelManager _modelManager;
  final AudioInferenceRunner? _inferenceRunner;
  final AudioStreamingInferenceRunner? _streamingInferenceRunner;
  final TextInferenceRunner? _textInferenceRunner;

  InferenceModel? _model;
  Future<void>? _initializingFuture;
  bool _initialized = false;

  bool get isInitialized => _initialized;

  @override
  Future<void> initialize() async {
    if (_initialized && (_model == null || !_model!.isClosed)) {
      _log.info('initialize(): already initialized.');
      return;
    }
    final inFlight = _initializingFuture;
    if (inFlight != null) {
      _log.info('initialize(): joining in-flight model initialization...');
      return inFlight;
    }

    final future = _performInitialize();
    _initializingFuture = future;
    try {
      await future;
    } finally {
      if (identical(_initializingFuture, future)) {
        _initializingFuture = null;
      }
    }
  }

  Future<void> _performInitialize() async {
    if (_inferenceRunner != null ||
        _streamingInferenceRunner != null ||
        _textInferenceRunner != null) {
      _log.info(
        'initialize(): custom inferenceRunner attached -> initialized=true.',
      );
      _initialized = true;
      return;
    }

    _log.info(
      'initialize(): ensuring Gemma 4 E2B model is downloaded and ready...',
    );
    final ready = await _modelManager.ensureModelDownloaded();
    if (!ready) {
      final errMsg =
          _modelManager.stateValue.error ??
          'Gemma 4 E2B model is not installed on device.';
      _log.severe('initialize(): model is not ready -> $errMsg');
      throw StateError(errMsg);
    }

    try {
      _log.info(
        'initialize(): calling FlutterEdgeAi.getActiveModel(maxTokens=2048, '
        'supportAudio=true, preferredBackend=gpu, enableSpeculativeDecoding=true)...',
      );
      final stopwatch = Stopwatch()..start();
      _model = await FlutterEdgeAi.getActiveModel(
        maxTokens: 2048,
        supportAudio: true,
        preferredBackend: PreferredBackend.gpu,
        enableSpeculativeDecoding: true,
      );
      stopwatch.stop();
      _initialized = true;
      _log.info(
        'initialize(): Gemma 4 LiteRT-LM model loaded in ${stopwatch.elapsedMilliseconds}ms '
        '(activeBackend=${_model?.activeBackend}, activeAudioBackend=${_model?.activeAudioBackend}).',
      );
    } on Object catch (e, st) {
      _log.severe(
        'initialize(): Failed to load Gemma 4 LiteRT-LM model',
        e,
        st,
      );
      throw StateError('Failed to initialize Gemma 4 LiteRT-LM engine: $e');
    }
  }

  @override
  Future<TranslationResult> translateAudioChunk({
    required Float32List audioWavChunk,
    required String baseLanguage,
    required String targetLanguage,
    required double exchangeRate,
    required String baseCurrency,
    required String targetCurrency,
    void Function(TranslationResult partialResult)? onPartialResult,
  }) async {
    if (audioWavChunk.isEmpty) {
      throw ArgumentError('Audio chunk cannot be empty.');
    }

    final fallbackSourceCode = LanguageDetector.normalizeLanguageCode(
      baseLanguage,
    );

    // Pre-check real-length audio chunks (>= 250ms at 16kHz) so silent or
    // near-silent pauses never get sent to the LLM to trigger hallucinations.
    if (audioWavChunk.length >= 4000 &&
        !VadBuffer.hasMeaningfulSpeech(audioWavChunk)) {
      _log.info(
        'translateAudioChunk(): audio chunk (${audioWavChunk.length} samples) '
        'contains no meaningful speech energy -> returning empty pause result.',
      );
      return TranslationResult(
        sourceLanguage: fallbackSourceCode,
        translatedText: '',
        originalText: '',
      );
    }

    if (!_initialized || (_model != null && _model!.isClosed)) {
      await initialize();
    }

    final systemPrompt = PromptTemplates.buildSystemPrompt(
      baseLanguage: baseLanguage,
      targetLanguage: targetLanguage,
      exchangeRate: exchangeRate,
      baseCurrency: baseCurrency,
      targetCurrency: targetCurrency,
    );
    final userTurnPrompt = PromptTemplates.buildAudioTurnPrompt(
      baseLanguage: baseLanguage,
      targetLanguage: targetLanguage,
    );

    final (wavBytes, trimmedLength) = await encodeAudioChunkInIsolate(
      audioWavChunk,
    );
    final durationSec = (trimmedLength / 16000.0).toStringAsFixed(2);
    _log.info(
      'translateAudioChunk() started: samples=$trimmedLength '
      '(raw=${audioWavChunk.length}, ~${durationSec}s @ 16kHz, wavBytes=${wavBytes.length}), '
      'pair=$baseLanguage <-> $targetLanguage, '
      'currency=1 $targetCurrency -> ${exchangeRate.toStringAsFixed(4)} $baseCurrency',
    );

    final stopwatch = Stopwatch()..start();
    var lastEmittedPartialText = '';

    void handleStreamingAccumulatedOutput(String accumulatedRaw) {
      if (onPartialResult == null) return;
      final partial = extractStreamingPartialResult(
        accumulatedRaw,
        baseLanguage: baseLanguage,
        targetLanguage: targetLanguage,
      );
      if (partial != null &&
          partial.translatedText.isNotEmpty &&
          partial.translatedText != lastEmittedPartialText) {
        lastEmittedPartialText = partial.translatedText;
        onPartialResult(partial);
      }
    }

    final String rawResponse;
    if (_streamingInferenceRunner != null) {
      final buffer = StringBuffer();
      await for (final tokenChunk in _streamingInferenceRunner(
        wavBytes: wavBytes,
        systemPrompt: systemPrompt,
        userPrompt: userTurnPrompt,
      )) {
        buffer.write(tokenChunk);
        handleStreamingAccumulatedOutput(buffer.toString());
      }
      rawResponse = buffer.toString();
    } else if (_inferenceRunner != null) {
      rawResponse = await _inferenceRunner(
        wavBytes: wavBytes,
        systemPrompt: systemPrompt,
      );
      handleStreamingAccumulatedOutput(rawResponse);
    } else {
      rawResponse = await _runModelInference(
        wavBytes: wavBytes,
        systemPrompt: systemPrompt,
        userPrompt: userTurnPrompt,
        onPartialAccumulated: handleStreamingAccumulatedOutput,
      );
    }
    stopwatch.stop();

    _log.info(
      'Model inference finished in ${stopwatch.elapsedMilliseconds}ms. '
      'Raw LLM output:\n$rawResponse',
    );

    final TranslationResult parsed;
    try {
      parsed = parseTranslationResponse(
        rawResponse,
        fallbackSourceLanguage: fallbackSourceCode,
        allowEmptyForSilence: true,
      );
    } on FormatException catch (e) {
      if (isNonSpeechOrHallucination(translatedText: rawResponse)) {
        _log.info(
          'Model output indicated silence or no speech ($e); returning empty pause result.',
        );
        return TranslationResult(
          sourceLanguage: fallbackSourceCode,
          translatedText: '',
          originalText: '',
        );
      }
      rethrow;
    }

    if (parsed.translatedText.trim().isEmpty ||
        isNonSpeechOrHallucination(
          originalText: parsed.originalText,
          translatedText: parsed.translatedText,
        )) {
      _log.info(
        'Detected conversational pause, silence, or non-speech hallucination '
        '(original="${parsed.originalText}", translated="${parsed.translatedText}") '
        '-> suppressing output gracefully.',
      );
      return TranslationResult(
        sourceLanguage: fallbackSourceCode,
        translatedText: '',
        originalText: '',
      );
    }

    final analysis = LanguageDetector.analyzeTranslation(
      result: parsed,
      baseLanguage: baseLanguage,
      targetLanguage: targetLanguage,
    );

    _log.info(
      'Translation analysis: reportedSource="${parsed.sourceLanguage}", '
      'resolvedSource="${analysis.resolvedSourceCode}" '
      '(isBaseLanguage=${analysis.isBaseLanguage}), '
      'detectedOriginal="${analysis.detectedOriginalCode}", '
      'detectedTranslated="${analysis.detectedTranslatedCode}", '
      'needsFallbackTranslation=${analysis.needsFallbackTranslation}',
    );

    if (analysis.needsFallbackTranslation) {
      final sourceLangName = AppSettings.languageNameFor(
        analysis.resolvedSourceCode,
      );
      final targetLangName = AppSettings.languageNameFor(
        analysis.targetOutputCode,
      );
      _log.warning(
        'Model echoed or failed to translate "$sourceLangName" speech into '
        '"$targetLangName" (got "${parsed.translatedText}"). '
        'Running automatic text-to-text translation pass...',
      );

      final fallbackPrompt = PromptTemplates.buildTextFallbackPrompt(
        textToTranslate: analysis.sourceTextForFallback,
        sourceLanguage: sourceLangName,
        targetLanguage: targetLangName,
        exchangeRate: exchangeRate,
        baseCurrency: baseCurrency,
        targetCurrency: targetCurrency,
      );
      final fallbackSystemPrompt =
          PromptTemplates.buildTextFallbackSystemPrompt(
            sourceLanguage: sourceLangName,
            targetLanguage: targetLangName,
          );

      final fallbackRaw = await _executeTextFallback(
        prompt: fallbackPrompt,
        systemPrompt: fallbackSystemPrompt,
        resolvedSourceCode: analysis.resolvedSourceCode,
        originalText: analysis.sourceTextForFallback,
        onPartialResult: onPartialResult,
      );

      final cleanedFallback = cleanTextFallbackOutput(
        fallbackRaw,
        fallbackSourceLanguage: analysis.resolvedSourceCode,
      );
      if (cleanedFallback.isNotEmpty &&
          !isNonSpeechOrHallucination(
            originalText: analysis.sourceTextForFallback,
            translatedText: cleanedFallback,
          )) {
        _log.info(
          'Text-to-text fallback translation succeeded: '
          '"${analysis.sourceTextForFallback}" -> "$cleanedFallback"',
        );
        return TranslationResult(
          sourceLanguage: analysis.resolvedSourceCode,
          translatedText: cleanedFallback,
          originalText: analysis.sourceTextForFallback,
        );
      } else if (isNonSpeechOrHallucination(
        originalText: analysis.sourceTextForFallback,
        translatedText: cleanedFallback,
      )) {
        _log.info(
          'Text fallback output indicated non-speech or hallucination ("$cleanedFallback") -> suppressing.',
        );
        return TranslationResult(
          sourceLanguage: analysis.resolvedSourceCode,
          translatedText: '',
          originalText: '',
        );
      }
    }

    return parsed.copyWith(
      sourceLanguage: analysis.resolvedSourceCode,
    );
  }

  @override
  Future<String> summarizeConversation({
    required List<domain.Message> messages,
    required String baseLanguage,
    required String targetLanguage,
  }) async {
    if (messages.isEmpty) {
      return '';
    }

    if (!_initialized || (_model != null && _model!.isClosed)) {
      await initialize();
    }

    final systemPrompt = PromptTemplates.buildSummarySystemPrompt(
      baseLanguage: baseLanguage,
    );
    final prompt = PromptTemplates.buildConversationSummaryPrompt(
      messages: messages,
      baseLanguage: baseLanguage,
      targetLanguage: targetLanguage,
    );

    final String rawOutput;
    if (_textInferenceRunner != null) {
      rawOutput = await _textInferenceRunner(
        prompt: prompt,
        systemPrompt: systemPrompt,
      );
    } else if (_inferenceRunner != null) {
      rawOutput = await _inferenceRunner(
        wavBytes: Uint8List(0),
        systemPrompt: prompt,
      );
    } else if (_streamingInferenceRunner != null) {
      final buffer = StringBuffer();
      await for (final tokenChunk in _streamingInferenceRunner(
        wavBytes: Uint8List(0),
        systemPrompt: systemPrompt,
        userPrompt: prompt,
      )) {
        buffer.write(tokenChunk);
      }
      rawOutput = buffer.toString();
    } else {
      rawOutput = await _runModelTextFallback(
        prompt: prompt,
        systemPrompt: systemPrompt,
      );
    }

    var cleaned = cleanSummaryOutput(rawOutput);
    if (cleaned.isNotEmpty) {
      final baseCode = LanguageDetector.normalizeLanguageCode(baseLanguage);
      final targetCode = LanguageDetector.normalizeLanguageCode(targetLanguage);
      String? wrongSourceLangName;

      if (baseCode != 'en') {
        final detectedVsEn = LanguageDetector.detectLanguage(
          cleaned,
          candidateA: baseCode,
          candidateB: 'en',
        );
        if (detectedVsEn == 'en') {
          wrongSourceLangName = 'English';
        }
      }
      if (wrongSourceLangName == null && targetCode != baseCode) {
        final detectedVsTarget = LanguageDetector.detectLanguage(
          cleaned,
          candidateA: baseCode,
          candidateB: targetCode,
        );
        if (detectedVsTarget == targetCode) {
          wrongSourceLangName = AppSettings.languageNameFor(targetCode);
        }
      }

      if (wrongSourceLangName != null) {
        final baseName = AppSettings.languageNameFor(baseCode);
        final nativeName = AppSettings.nativeLanguageNameFor(baseCode);
        final nativeLabel = nativeName != baseName && nativeName.isNotEmpty
            ? '$baseName ($nativeName)'
            : baseName;
        _log.info(
          'summarizeConversation(): summary "$cleaned" was generated in '
          '$wrongSourceLangName instead of native language $nativeLabel ($baseCode) '
          '-> translating summary into $nativeLabel...',
        );
        final translatePrompt = PromptTemplates.buildTextFallbackPrompt(
          textToTranslate: cleaned,
          sourceLanguage: wrongSourceLangName,
          targetLanguage: nativeLabel,
          exchangeRate: 1.0,
          baseCurrency: 'USD',
          targetCurrency: 'USD',
        );
        final translateSystemPrompt =
            PromptTemplates.buildTextFallbackSystemPrompt(
              sourceLanguage: wrongSourceLangName,
              targetLanguage: nativeLabel,
            );
        final String translatedRaw;
        if (_textInferenceRunner != null) {
          translatedRaw = await _textInferenceRunner(
            prompt: translatePrompt,
            systemPrompt: translateSystemPrompt,
          );
        } else if (_inferenceRunner != null) {
          translatedRaw = await _inferenceRunner(
            wavBytes: Uint8List(0),
            systemPrompt: translatePrompt,
          );
        } else {
          translatedRaw = await _runModelTextFallback(
            prompt: translatePrompt,
            systemPrompt: translateSystemPrompt,
          );
        }
        final translatedCleaned = cleanSummaryOutput(translatedRaw);
        if (translatedCleaned.isNotEmpty) {
          cleaned = translatedCleaned;
        }
      }
    }

    _log.info(
      'summarizeConversation() generated summary: "$cleaned" (from ${messages.length} messages)',
    );
    return cleaned;
  }

  /// Cleans and normalizes raw LLM summary output into a concise 3 to 5 word
  /// description.
  static String cleanSummaryOutput(String rawOutput) {
    final stripped = stripMarkdownFences(rawOutput).trim();
    if (stripped.isEmpty) return '';

    var candidate = stripped;
    if (candidate.startsWith('{') && candidate.endsWith('}')) {
      try {
        final decoded = jsonDecode(candidate);
        if (decoded is Map<String, Object?>) {
          final val =
              decoded['summary'] ??
              decoded['title'] ??
              decoded['description'] ??
              decoded['translated_text'];
          if (val is String && val.trim().isNotEmpty) {
            candidate = val.trim();
          }
        }
      } on Object {
        // Fall through to plain-text cleanup.
      }
    }

    // Take the first non-empty line
    candidate = candidate
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => '');

    // Remove common leading labels like "Summary:" or "3 to 5 word summary in ...:"
    candidate = candidate.replaceFirst(
      RegExp(
        r'^(?:3\s+to\s+5\s+word\s+summary(?:\s+in\s+[^:]+)?|summary|title|description)\s*:\s*',
        caseSensitive: false,
      ),
      '',
    ).trim();

    // Strip surrounding quotes and trailing period
    while (candidate.length >= 2 &&
        ((candidate.startsWith('"') && candidate.endsWith('"')) ||
            (candidate.startsWith("'") && candidate.endsWith("'")))) {
      candidate = candidate.substring(1, candidate.length - 1).trim();
    }
    candidate = candidate.replaceAll(RegExp(r'[.。]+$'), '').trim();

    if (candidate.isEmpty) return '';

    final words = candidate.split(RegExp(r'\s+'));
    if (words.length > 5) {
      return words.take(5).join(' ');
    }
    return words.join(' ');
  }

  Future<String> _executeTextFallback({
    required String prompt,
    required String systemPrompt,
    required String resolvedSourceCode,
    required String originalText,
    void Function(TranslationResult partialResult)? onPartialResult,
  }) async {
    if (_textInferenceRunner != null) {
      final res = await _textInferenceRunner(
        prompt: prompt,
        systemPrompt: systemPrompt,
      );
      if (onPartialResult != null) {
        final cleaned = cleanTextFallbackOutput(
          res,
          fallbackSourceLanguage: resolvedSourceCode,
        );
        if (cleaned.isNotEmpty) {
          onPartialResult(
            TranslationResult(
              sourceLanguage: resolvedSourceCode,
              translatedText: cleaned,
              originalText: originalText,
            ),
          );
        }
      }
      return res;
    }

    if (_inferenceRunner != null) {
      // Only invoke _inferenceRunner for text fallback if it accepts empty wavBytes.
      return _inferenceRunner(
        wavBytes: Uint8List(0),
        systemPrompt: prompt,
      );
    }

    return _runModelTextFallback(
      prompt: prompt,
      systemPrompt: systemPrompt,
      onPartialAccumulated: (accumulated) {
        if (onPartialResult == null) return;
        final cleaned = cleanTextFallbackOutput(
          accumulated,
          fallbackSourceLanguage: resolvedSourceCode,
        );
        if (cleaned.isNotEmpty) {
          onPartialResult(
            TranslationResult(
              sourceLanguage: resolvedSourceCode,
              translatedText: cleaned,
              originalText: originalText,
            ),
          );
        }
      },
    );
  }

  Future<String> _runModelInference({
    required Uint8List wavBytes,
    required String systemPrompt,
    required String userPrompt,
    void Function(String accumulated)? onPartialAccumulated,
  }) async {
    var model = _model;
    if (model == null || model.isClosed) {
      _log.info('Re-acquiring active Gemma 4 model from FlutterEdgeAi...');
      model = await FlutterEdgeAi.getActiveModel(
        maxTokens: 2048,
        supportAudio: true,
        preferredBackend: PreferredBackend.gpu,
        enableSpeculativeDecoding: true,
      );
      _model = model;
    }

    _log.info(
      'Creating Gemma 4 audio session (enableAudioModality=true, enableThinking=false, maxOutputTokens=256)...',
    );
    final session = await model.createSession(
      enableAudioModality: true,
      systemInstruction: systemPrompt,
      enableThinking: false,
      maxOutputTokens: 256,
    );
    try {
      _log.info(
        'Adding audio + prompt query chunk (${wavBytes.length} WAV bytes) to Gemma 4 session...',
      );
      await session.addQueryChunk(
        Message.withAudio(
          text: userPrompt,
          audioBytes: wavBytes,
          isUser: true,
        ),
      );
      _log.info('Streaming tokens from session.getResponseAsync()...');
      final rawStream = session.getResponseAsync().map(TextResponse.new);
      final filteredStream = ModelThinkingFilter.filterThinkingStream(
        rawStream,
        modelType: ModelType.gemma4,
      );

      final buffer = StringBuffer();
      await for (final response in filteredStream) {
        if (response is TextResponse && response.token.isNotEmpty) {
          buffer.write(response.token);
          onPartialAccumulated?.call(buffer.toString());
        }
      }

      try {
        final metrics = session.getSessionMetrics();
        _log.info('Gemma 4 audio session metrics: $metrics');
      } on Object {
        // Ignore if session metrics are unavailable on this backend.
      }
      return buffer.toString();
    } finally {
      await session.close();
    }
  }

  Future<String> _runModelTextFallback({
    required String prompt,
    required String systemPrompt,
    void Function(String accumulated)? onPartialAccumulated,
  }) async {
    var model = _model;
    if (model == null || model.isClosed) {
      model = await FlutterEdgeAi.getActiveModel(
        maxTokens: 2048,
        supportAudio: true,
        preferredBackend: PreferredBackend.gpu,
        enableSpeculativeDecoding: true,
      );
      _model = model;
    }

    _log.info('Creating Gemma 4 text fallback session (maxOutputTokens=256)...');
    final session = await model.createSession(
      enableAudioModality: false,
      systemInstruction: systemPrompt,
      enableThinking: false,
      maxOutputTokens: 256,
    );
    try {
      await session.addQueryChunk(
        Message(
          text: prompt,
          isUser: true,
        ),
      );
      final rawStream = session.getResponseAsync().map(TextResponse.new);
      final filteredStream = ModelThinkingFilter.filterThinkingStream(
        rawStream,
        modelType: ModelType.gemma4,
      );

      final buffer = StringBuffer();
      await for (final response in filteredStream) {
        if (response is TextResponse && response.token.isNotEmpty) {
          buffer.write(response.token);
          onPartialAccumulated?.call(buffer.toString());
        }
      }
      return buffer.toString();
    } finally {
      await session.close();
    }
  }

  /// Offloads trailing silence trimming and 16-bit PCM RIFF/WAV encoding to a
  /// background isolate when the sample buffer is large enough to affect UI
  /// frame budgets.
  static Future<(Uint8List wavBytes, int trimmedSampleCount)>
  encodeAudioChunkInIsolate(
    Float32List samples, {
    int isolateThresholdSamples = 4000,
  }) async {
    if (samples.length < isolateThresholdSamples) {
      final trimmed = trimTrailingSilence(samples);
      return (encodeFloat32PcmToWav(trimmed), trimmed.length);
    }
    final transferableSamples = Float32List.fromList(samples);
    return Isolate.run(() {
      final trimmed = trimTrailingSilence(transferableSamples);
      final wav = encodeFloat32PcmToWav(trimmed);
      return (wav, trimmed.length);
    });
  }

  /// Trims excess trailing silence from a 16kHz PCM audio chunk down to at most
  /// [maxTrailingSilentSamples] (default: 4,000 samples / 250ms) so the Gemma 4
  /// audio encoder does not waste prefill compute on multi-second VAD silence.
  static Float32List trimTrailingSilence(
    Float32List samples, {
    double silenceThreshold = 0.015,
    int maxTrailingSilentSamples = 4000,
  }) {
    if (samples.length <= maxTrailingSilentSamples) {
      return samples;
    }
    var lastActiveIndex = -1;
    for (var i = samples.length - 1; i >= 0; i--) {
      if (samples[i].abs() >= silenceThreshold) {
        lastActiveIndex = i;
        break;
      }
    }
    if (lastActiveIndex == -1) {
      return samples;
    }
    final keepEnd = math.min(
      samples.length,
      lastActiveIndex + 1 + maxTrailingSilentSamples,
    );
    if (keepEnd >= samples.length) {
      return samples;
    }
    return Float32List.sublistView(samples, 0, keepEnd);
  }

  /// Extracts a streaming [TranslationResult] from an in-progress (potentially
  /// incomplete) JSON or text response while suppressing any untranslated
  /// source-language echo.
  static TranslationResult? extractStreamingPartialResult(
    String partialOutput, {
    required String baseLanguage,
    required String targetLanguage,
  }) {
    final trimmed = partialOutput.trim();
    if (trimmed.isEmpty) return null;

    final baseCode = LanguageDetector.normalizeLanguageCode(baseLanguage);

    final translatedMatch = RegExp(
      r'"(?:translated_text|translation)"\s*:\s*"((?:\\.|[^"\\])*)',
    ).firstMatch(trimmed);
    if (translatedMatch == null) {
      return null;
    }

    final rawPartialTranslated = _unescapeJsonPartialString(
      translatedMatch.group(1) ?? '',
    ).trim();
    if (rawPartialTranslated.isEmpty) {
      return null;
    }

    final detectedMatch = RegExp(
      r'"(?:detected_language|source_language)"\s*:\s*"([^"]+)"',
    ).firstMatch(trimmed);
    final reportedSource = detectedMatch?.group(1)?.trim() ?? baseCode;

    final originalMatch = RegExp(
      r'"(?:original_transcript|original_text)"\s*:\s*"((?:\\.|[^"\\])*)"',
    ).firstMatch(trimmed);
    final originalTranscript = originalMatch != null
        ? _unescapeJsonPartialString(originalMatch.group(1) ?? '').trim()
        : null;

    // Suppress streaming if the partial text looks like an untranslated echo of
    // original_transcript or a non-speech/silence hallucination!
    if (isNonSpeechOrHallucination(
      originalText: originalTranscript,
      translatedText: rawPartialTranslated,
    )) {
      return null;
    }
    if (originalTranscript != null && originalTranscript.isNotEmpty) {
      final normOrig = originalTranscript.toLowerCase();
      final normTrans = rawPartialTranslated.toLowerCase();
      if (normOrig.startsWith(normTrans) || normTrans == normOrig) {
        return null;
      }
    }

    final candidateResult = TranslationResult(
      sourceLanguage: reportedSource,
      translatedText: rawPartialTranslated,
      originalText:
          (originalTranscript != null && originalTranscript.isNotEmpty)
          ? originalTranscript
          : null,
    );

    final analysis = LanguageDetector.analyzeTranslation(
      result: candidateResult,
      baseLanguage: baseLanguage,
      targetLanguage: targetLanguage,
    );

    if (analysis.needsFallbackTranslation) {
      // Hold back untranslated source language tokens so the UI never flashes
      // untranslated text before the fallback pass runs.
      return null;
    }

    return candidateResult.copyWith(
      sourceLanguage: analysis.resolvedSourceCode,
    );
  }

  static String _unescapeJsonPartialString(String input) {
    return input
        .replaceAll(r'\"', '"')
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\r', '\r')
        .replaceAll(r'\t', '\t')
        .replaceAll(r'\\', r'\');
  }

  /// Cleans the raw output of the text-to-text fallback pass.
  static String cleanTextFallbackOutput(
    String rawOutput, {
    String fallbackSourceLanguage = 'en',
  }) {
    final stripped = stripMarkdownFences(rawOutput).trim();
    if (stripped.isEmpty) return '';

    if (stripped.startsWith('{')) {
      try {
        final parsed = parseTranslationResponse(
          stripped,
          fallbackSourceLanguage: fallbackSourceLanguage,
        );
        return parsed.translatedText;
      } on Object {
        final partialMatch = RegExp(
          r'"(?:translated_text|translation)"\s*:\s*"((?:\\.|[^"\\])*)',
        ).firstMatch(stripped);
        if (partialMatch != null) {
          return _unescapeJsonPartialString(partialMatch.group(1) ?? '').trim();
        }
        return '';
      }
    }

    var result = stripped;
    if (result.length >= 2 &&
        ((result.startsWith('"') && result.endsWith('"')) ||
            (result.startsWith("'") && result.endsWith("'")))) {
      result = result.substring(1, result.length - 1).trim();
    }
    return result;
  }

  /// Returns `true` when [originalText] or [translatedText] represents silence,
  /// a conversational pause, a meta-refusal about missing/silent audio (e.g.
  /// `"There was no audio file, please provide an audio file."`), or a known
  /// silence hallucination (e.g. `"I am going to the store to buy some milk"`).
  static bool isNonSpeechOrHallucination({
    String? originalText,
    required String translatedText,
  }) {
    final trimmedTrans = translatedText.trim();
    if (trimmedTrans.isEmpty) return true;

    if (_isNonSpeechMarker(trimmedTrans)) return true;
    if (originalText != null && _isNonSpeechMarker(originalText.trim())) {
      return true;
    }

    final combinedLower = '${originalText ?? ''}\n$trimmedTrans'.toLowerCase();

    // 1. Meta-refusals about missing, silent, or inaudible audio
    const refusalSubstrings = <String>[
      'no audio file',
      'provide an audio file',
      'please provide an audio',
      'please provide audio',
      'no audio provided',
      'there was no audio',
      'there is no audio',
      'no speech detected',
      'no speech in the audio',
      'no speech in this audio',
      'no speech in audio',
      'no clear speech',
      'nothing was said',
      'no one is speaking',
      'nobody spoke',
      'cannot hear any',
      "can't hear any",
      "couldn't hear any",
      'unable to hear',
      'audio is silent',
      'audio clip is silent',
      'only background noise',
      'only silence',
      '오디오 파일이 없',
      '오디오 파일을 제공',
      '음성이 감지되지',
      '아무 말도 하지',
      'no había archivo de audio',
      'no hay archivo de audio',
      'proporcione un archivo de audio',
      'no se detectó voz',
      'aucun fichier audio',
      'veuillez fournir un fichier audio',
      'keine audiodatei',
      '音声ファイルがありません',
      'オーディオファイルを提供',
      '没有音频文件',
      '请提供音频文件',
    ];
    for (final phrase in refusalSubstrings) {
      if (combinedLower.contains(phrase)) {
        return true;
      }
    }

    // 2. Classic audio-encoder silence hallucinations ("going to the store to buy some milk")
    const hallucinationSubstrings = <String>[
      'going to the store to buy some milk',
      'going to the store to buy milk',
      'go to the store to buy some milk',
      '우유를 사러 가게에',
      '우유 사러 가게에',
      'voy a la tienda a comprar leche',
      'voy a la tienda a comprar algo de leche',
    ];
    for (final phrase in hallucinationSubstrings) {
      if (combinedLower.contains(phrase)) {
        return true;
      }
    }

    return false;
  }

  static bool _isNonSpeechMarker(String value) {
    if (value.isEmpty) return false;
    final normalized = value.trim().toLowerCase();
    const exactMarkers = <String>{
      '...',
      '…',
      '-',
      '--',
      'n/a',
      'none',
      'null',
      'silence',
      'no speech',
      'inaudible',
      'blank_audio',
      '[silence]',
      '[no speech]',
      '[no_speech]',
      '[blank_audio]',
      '[noise]',
      '[inaudible]',
      '[music]',
      '[pause]',
      '(silence)',
      '(no speech)',
      '(noise)',
      '(inaudible)',
      '(pause)',
      '(무음)',
      '(침묵)',
      '[무음]',
      '[침묵]',
      '(silencio)',
      '[silencio]',
    };
    return exactMarkers.contains(normalized);
  }

  /// Sanitizes and parses the raw LLM output into a [TranslationResult].
  ///
  /// Handles markdown fences (````json ... ````), leading/trailing prose around
  /// a JSON object, and falls back gracefully if the LLM output is plain text.
  static TranslationResult parseTranslationResponse(
    String rawOutput, {
    String fallbackSourceLanguage = 'en',
    bool allowEmptyForSilence = false,
  }) {
    final trimmed = rawOutput.trim();
    if (trimmed.isEmpty) {
      if (allowEmptyForSilence) {
        return TranslationResult(
          sourceLanguage: fallbackSourceLanguage.toLowerCase(),
          translatedText: '',
          originalText: '',
        );
      }
      throw const FormatException('Empty response from translation engine.');
    }

    final stripped = stripMarkdownFences(trimmed);
    final jsonCandidate = _extractJsonObject(stripped) ?? stripped;

    Map<String, Object?>? parsedMap;
    try {
      final decoded = jsonDecode(jsonCandidate);
      if (decoded is Map) {
        parsedMap = decoded.cast<String, Object?>();
      }
    } on Object {
      // Fall through to graceful plain-text fallback if JSON is malformed.
    }

    if (parsedMap != null) {
      final detectedLanguage =
          (parsedMap['detected_language'] as String? ??
                  parsedMap['source_language'] as String? ??
                  fallbackSourceLanguage)
              .trim()
              .toLowerCase();
      final translatedText =
          (parsedMap['translated_text'] as String? ??
                  parsedMap['translation'] as String? ??
                  '')
              .trim();
      final hasOriginalTranscriptKey =
          parsedMap.containsKey('original_transcript') ||
          parsedMap.containsKey('original_text');
      final originalTranscript =
          (parsedMap['original_transcript'] as String? ??
                  parsedMap['original_text'] as String?)
              ?.trim();

      // If translatedText is empty and either allowEmptyForSilence is true or
      // the model explicitly reported empty original_transcript (silence/pause),
      // return an empty pause result instead of throwing FormatException.
      if (translatedText.isEmpty) {
        if (allowEmptyForSilence ||
            (hasOriginalTranscriptKey &&
                (originalTranscript == null || originalTranscript.isEmpty))) {
          return TranslationResult(
            sourceLanguage: detectedLanguage.isEmpty
                ? fallbackSourceLanguage
                : detectedLanguage,
            translatedText: '',
            originalText: '',
          );
        }
        throw const FormatException(
          'JSON response is missing non-empty "translated_text".',
        );
      }

      return TranslationResult(
        sourceLanguage: detectedLanguage.isEmpty
            ? fallbackSourceLanguage
            : detectedLanguage,
        translatedText: translatedText,
        originalText:
            (originalTranscript == null || originalTranscript.isEmpty)
            ? null
            : originalTranscript,
      );
    }

    // Step 14 hardening: if the model returned non-JSON text rather than a
    // valid JSON object, surface the cleaned text as a fallback translation
    // unless it looks like truncated/corrupt JSON braces.
    if (stripped.startsWith('{') || stripped.startsWith('[')) {
      throw FormatException(
        'Malformed JSON output from translation engine: $rawOutput',
      );
    }

    return TranslationResult(
      sourceLanguage: fallbackSourceLanguage.toLowerCase(),
      translatedText: stripped,
    );
  }

  /// Strips ```json ... ``` or ``` ... ``` markdown code fences.
  static String stripMarkdownFences(String input) {
    var result = input.trim();
    final fenceRegex = RegExp(
      r'^```(?:json)?\s*([\s\S]*?)\s*```$',
      multiLine: true,
    );
    final match = fenceRegex.firstMatch(result);
    if (match != null && match.group(1) != null) {
      return match.group(1)!.trim();
    }
    if (result.startsWith('```json')) {
      result = result.substring('```json'.length).trim();
    } else if (result.startsWith('```')) {
      result = result.substring(3).trim();
    }
    if (result.endsWith('```')) {
      result = result.substring(0, result.length - 3).trim();
    }
    return result;
  }

  static String? _extractJsonObject(String input) {
    final start = input.indexOf('{');
    final end = input.lastIndexOf('}');
    if (start != -1 && end != -1 && end > start) {
      return input.substring(start, end + 1);
    }
    return null;
  }

  /// Encodes 16kHz mono 32-bit float PCM samples (`[-1.0, 1.0]`) into a
  /// 16kHz mono 16-bit little-endian RIFF/WAV byte buffer expected by LiteRT-LM.
  static Uint8List encodeFloat32PcmToWav(
    Float32List samples, {
    int sampleRate = 16000,
  }) {
    const channels = 1;
    const bitsPerSample = 16;
    const bytesPerSample = bitsPerSample ~/ 8;
    final byteRate = sampleRate * channels * bytesPerSample;
    const blockAlign = channels * bytesPerSample;
    final pcmDataLength = samples.length * bytesPerSample;

    final wav = Uint8List(44 + pcmDataLength);
    final view = ByteData.sublistView(wav);

    void writeAscii(int offset, String text) {
      for (var i = 0; i < text.length; i++) {
        view.setUint8(offset + i, text.codeUnitAt(i));
      }
    }

    writeAscii(0, 'RIFF');
    view.setUint32(4, 36 + pcmDataLength, Endian.little);
    writeAscii(8, 'WAVE');
    writeAscii(12, 'fmt ');
    view.setUint32(16, 16, Endian.little);
    view.setUint16(20, 1, Endian.little); // PCM = 1
    view.setUint16(22, channels, Endian.little);
    view.setUint32(24, sampleRate, Endian.little);
    view.setUint32(28, byteRate, Endian.little);
    view.setUint16(32, blockAlign, Endian.little);
    view.setUint16(34, bitsPerSample, Endian.little);
    writeAscii(36, 'data');
    view.setUint32(40, pcmDataLength, Endian.little);

    var byteOffset = 44;
    for (var i = 0; i < samples.length; i++) {
      final clamped = samples[i].clamp(-1.0, 1.0);
      final pcm16 = (clamped * 32767.0).round().clamp(-32768, 32767);
      view.setInt16(byteOffset, pcm16, Endian.little);
      byteOffset += 2;
    }

    return wav;
  }

  @override
  Future<void> dispose() async {
    _initializingFuture = null;
    final model = _model;
    _model = null;
    _initialized = false;
    if (model != null) {
      await model.close();
    }
  }
}
