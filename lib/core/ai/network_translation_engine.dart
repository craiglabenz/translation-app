import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:translation_app/core/ai/language_detector.dart';
import 'package:translation_app/core/ai/local_translation_engine.dart';
import 'package:translation_app/core/ai/prompt_templates.dart';
import 'package:translation_app/core/ai/translation_engine.dart';
import 'package:translation_app/core/audio/vad_buffer.dart';
import 'package:translation_app/core/data/models/app_settings.dart';
import 'package:translation_app/core/data/models/message.dart';
import 'package:translation_app/core/logging/app_logger.dart';

/// Cloud-based translation engine powered by Google Gemini
/// (`gemini-3.8-flash` and `gemini-3.1-pro`) over low-latency SSE streaming.
class NetworkTranslationEngine implements TranslationEngine {
  NetworkTranslationEngine({
    this._apiKeyProvider,
    this._modelIdProvider,
    http.Client? httpClient,
    List<SupportedLanguage>? initialDiscoveredLanguages,
  }) : _httpClient = httpClient,
       _ownsHttpClient = httpClient == null,
       _discoveredLanguages = List<SupportedLanguage>.of(
         initialDiscoveredLanguages ?? const <SupportedLanguage>[],
       );

  static final _log = AppLogger.of('NetworkTranslationEngine');

  static const String _baseApiUrl =
      'https://generativelanguage.googleapis.com/v1beta/models';

  /// Built-in cloud language catalog (includes all 38 on-device Gemma languages
  /// plus additional cloud-supported languages).
  static const List<SupportedLanguage> cloudSupportedLanguages = [
    ...LocalTranslationEngine.gemmaSupportedLanguages,
    SupportedLanguage(
      code: 'af',
      name: 'Afrikaans',
      nativeName: 'Afrikaans',
    ),
    SupportedLanguage(code: 'am', name: 'Amharic', nativeName: 'አማርኛ'),
    SupportedLanguage(code: 'ca', name: 'Catalan', nativeName: 'Català'),
    SupportedLanguage(code: 'cy', name: 'Welsh', nativeName: 'Cymraeg'),
    SupportedLanguage(code: 'eu', name: 'Basque', nativeName: 'Euskara'),
    SupportedLanguage(code: 'fa', name: 'Persian', nativeName: 'فارسی'),
    SupportedLanguage(code: 'ga', name: 'Irish', nativeName: 'Gaeilge'),
    SupportedLanguage(code: 'gl', name: 'Galician', nativeName: 'Galego'),
    SupportedLanguage(code: 'gu', name: 'Gujarati', nativeName: 'ગુજરાતી'),
    SupportedLanguage(code: 'ha', name: 'Hausa', nativeName: 'Hausa'),
    SupportedLanguage(code: 'is', name: 'Icelandic', nativeName: 'Íslenska'),
    SupportedLanguage(code: 'kn', name: 'Kannada', nativeName: 'ಕನ್ನಡ'),
    SupportedLanguage(code: 'ml', name: 'Malayalam', nativeName: 'മലയാളം'),
    SupportedLanguage(code: 'mr', name: 'Marathi', nativeName: 'मराठी'),
    SupportedLanguage(
      code: 'ms',
      name: 'Malay',
      nativeName: 'Bahasa Melayu',
    ),
    SupportedLanguage(code: 'pa', name: 'Punjabi', nativeName: 'ਪੰਜਾਬੀ'),
    SupportedLanguage(code: 'ta', name: 'Tamil', nativeName: 'தமிழ்'),
    SupportedLanguage(code: 'te', name: 'Telugu', nativeName: 'తెలుగు'),
    SupportedLanguage(code: 'tl', name: 'Tagalog', nativeName: 'Tagalog'),
    SupportedLanguage(code: 'ur', name: 'Urdu', nativeName: 'اردو'),
    SupportedLanguage(code: 'yo', name: 'Yoruba', nativeName: 'Yorùbá'),
    SupportedLanguage(code: 'yue', name: 'Cantonese', nativeName: '粵語'),
    SupportedLanguage(code: 'zu', name: 'Zulu', nativeName: 'isiZulu'),
  ];

  final String Function()? _apiKeyProvider;
  final String Function()? _modelIdProvider;
  http.Client? _httpClient;
  final bool _ownsHttpClient;
  final List<SupportedLanguage> _discoveredLanguages;
  final Set<String> _availableApiModelIds = <String>{};
  bool _initialized = false;

  bool get isInitialized => _initialized;

  /// Resolves the configured Gemini API key.
  String get apiKey => (_apiKeyProvider?.call() ?? '').trim();

  /// Resolves the active Gemini model ID (defaults to `gemini-3.8-flash`, and
  /// normalizes legacy `gemini-4` to `gemini-3.1-pro`).
  String get modelId {
    final configured = (_modelIdProvider?.call() ?? '').trim();
    if (configured.isEmpty) {
      return resolveEffectiveModelId(
        AppSettings.defaultCloudModelId,
        _availableApiModelIds,
      );
    }
    final normalized = configured == 'gemini-4' ? 'gemini-3.1-pro' : configured;
    return resolveEffectiveModelId(normalized, _availableApiModelIds);
  }

  /// Resolves [requestedId] against the set of [availableIds] returned by
  /// `v1beta/models` (`ListModels`) that support `generateContent`.
  ///
  /// Handles `-preview` / `-latest` suffixes (e.g. `gemini-3.1-pro-preview`)
  /// and falls back to the newest available model in the same tier (`flash` or
  /// `pro`) if the bare alias is not directly registered on `v1beta`.
  static String resolveEffectiveModelId(
    String requestedId,
    Set<String> availableIds,
  ) {
    final normalized = requestedId.trim() == 'gemini-4'
        ? 'gemini-3.1-pro'
        : requestedId.trim();
    if (availableIds.isEmpty || availableIds.contains(normalized)) {
      return normalized;
    }

    // 1. Direct preview / latest variants of the requested model
    for (final suffix in const <String>['-preview', '-latest', '-exp']) {
      final candidate = '$normalized$suffix';
      if (availableIds.contains(candidate)) {
        return candidate;
      }
    }

    bool isGeneralTextAudioModel(String id) {
      return !id.contains('tts') &&
          !id.contains('image') &&
          !id.contains('embedding') &&
          !id.contains('vision') &&
          !id.contains('computer-use') &&
          !id.contains('robotics');
    }

    final prefixMatches =
        availableIds
            .where(
              (id) =>
                  id.startsWith('$normalized-') && isGeneralTextAudioModel(id),
            )
            .toList()
          ..sort((a, b) => b.compareTo(a));
    if (prefixMatches.isNotEmpty) {
      return prefixMatches.first;
    }

    // 2. Same tier fallback (e.g., newest available gemini-*-pro* or gemini-*-flash*)
    final wantsPro = normalized.contains('pro');
    final tierKeyword = wantsPro ? 'pro' : 'flash';
    final tierMatches =
        availableIds
            .where(
              (id) =>
                  id.startsWith('gemini-') &&
                  id.contains(tierKeyword) &&
                  !id.contains('lite') &&
                  isGeneralTextAudioModel(id),
            )
            .toList()
          ..sort((a, b) => b.compareTo(a));
    if (tierMatches.isNotEmpty) {
      return tierMatches.first;
    }

    return normalized;
  }

  static Map<String, Object?> _buildGenerationConfig({
    required String effectiveModelId,
    required double temperature,
    String? responseMimeType,
  }) {
    final isFlash = effectiveModelId.toLowerCase().contains('flash');
    return <String, Object?>{
      'temperature': temperature,
      'responseMimeType': ?responseMimeType,
      // Pro models on v1beta often require thinking mode and reject thinkingBudget: 0
      if (isFlash) 'thinkingConfig': const <String, Object?>{'thinkingBudget': 0},
    };
  }

  /// Queries `GET /v1beta/models` to discover exact model IDs that support
  /// `generateContent`.
  Future<Set<String>> refreshAvailableModels() async {
    final currentKey = apiKey;
    if (currentKey.isEmpty) return _availableApiModelIds;
    try {
      final uri = Uri.parse('$_baseApiUrl?key=$currentKey');
      final response = await _client.get(uri);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final parsed = parseAvailableModelIdsResponse(response.body);
        if (parsed.isNotEmpty) {
          _availableApiModelIds
            ..clear()
            ..addAll(parsed);
          _log.info(
            'refreshAvailableModels(): found ${parsed.length} generateContent '
            'models -> resolved active modelId="$modelId".',
          );
        }
      }
    } on Object catch (e, st) {
      _log.fine('refreshAvailableModels() skipped: $e', e, st);
    }
    return _availableApiModelIds;
  }

  /// Parses the JSON response from `GET /v1beta/models` and returns the set of
  /// model IDs (without the `models/` prefix) that support `generateContent`.
  static Set<String> parseAvailableModelIdsResponse(String rawBody) {
    final result = <String>{};
    try {
      final decoded = jsonDecode(rawBody);
      if (decoded is Map<String, Object?> &&
          decoded['models'] is List<Object?>) {
        for (final entry in decoded['models']! as List<Object?>) {
          if (entry is Map<String, Object?>) {
            final name = (entry['name']?.toString() ?? '').trim();
            final methods = entry['supportedGenerationMethods'];
            final supportsGenerate =
                methods is List<Object?> &&
                methods.any((m) => m?.toString() == 'generateContent');
            if (name.isNotEmpty && supportsGenerate) {
              final shortId = name.startsWith('models/')
                  ? name.substring('models/'.length)
                  : name;
              result.add(shortId);
            }
          }
        }
      }
    } on Object {
      // Ignore malformed responses
    }
    return result;
  }

  http.Client get _client => _httpClient ??= http.Client();

  @override
  List<SupportedLanguage> get supportedLanguages {
    if (_discoveredLanguages.isEmpty) {
      return cloudSupportedLanguages;
    }
    final byCode = <String, SupportedLanguage>{
      for (final lang in cloudSupportedLanguages) lang.code.toLowerCase(): lang,
    };
    for (final lang in _discoveredLanguages) {
      final key = lang.code.trim().toLowerCase();
      if (key.isNotEmpty) {
        byCode[key] = lang;
      }
    }
    return List<SupportedLanguage>.unmodifiable(byCode.values);
  }

  @override
  Future<void> initialize() async {
    if (apiKey.isEmpty) {
      throw StateError(
        'Gemini API key is not configured. Please enter your Gemini API key in Settings.',
      );
    }
    // Ensure persistent HTTP client is created for low-latency connection reuse.
    _client;
    _initialized = true;
    _log.info('initialize(): NetworkTranslationEngine ready (model=$modelId).');
  }

  /// Queries the active Gemini model to discover any additional languages it
  /// supports and merges them into [supportedLanguages].
  Future<List<SupportedLanguage>> discoverSupportedLanguages() async {
    if (apiKey.isEmpty) {
      return supportedLanguages;
    }
    try {
      await refreshAvailableModels();
      final activeModel = modelId;
      final uri = Uri.parse(
        '$_baseApiUrl/$activeModel:generateContent?key=$apiKey',
      );
      final requestBody = <String, Object?>{
        'contents': <Object?>[
          <String, Object?>{
            'role': 'user',
            'parts': <Object?>[
              <String, Object?>{
                'text':
                    'Return a JSON array of spoken languages you can accurately translate '
                    'from speech/text. Each item must have "code" (ISO 639-1 or BCP-47 lowercase code), '
                    '"name" (English name), and "nativeName" (native script name).',
              },
            ],
          },
        ],
        'generationConfig': _buildGenerationConfig(
          effectiveModelId: activeModel,
          temperature: 0.0,
          responseMimeType: 'application/json',
        ),
      };

      final response = await _client.post(
        uri,
        headers: const <String, String>{'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final rawText = _extractCandidateTextFromGenerateResponse(
          response.body,
        );
        final parsedList = parseDiscoveredLanguagesResponse(rawText);
        if (parsedList.isNotEmpty) {
          _discoveredLanguages
            ..clear()
            ..addAll(parsedList);
          _log.info(
            'discoverSupportedLanguages(): merged ${parsedList.length} languages '
            '(total=${supportedLanguages.length}).',
          );
        }
      } else {
        _log.warning(
          'discoverSupportedLanguages(): HTTP ${response.statusCode} -> keeping baseline catalog.',
        );
      }
    } on Object catch (e, st) {
      _log.warning(
        'discoverSupportedLanguages() failed -> keeping baseline catalog: $e',
        e,
        st,
      );
    }
    return supportedLanguages;
  }

  /// Parses a JSON array of discovered languages returned by Gemini.
  static List<SupportedLanguage> parseDiscoveredLanguagesResponse(
    String rawResponse,
  ) {
    final cleaned = LocalTranslationEngine.stripMarkdownFences(rawResponse);
    if (cleaned.isEmpty) return const <SupportedLanguage>[];
    try {
      final decoded = jsonDecode(cleaned);
      final List<Object?> items;
      if (decoded is List<Object?>) {
        items = decoded;
      } else if (decoded is Map<String, Object?> &&
          decoded['languages'] is List<Object?>) {
        items = decoded['languages']! as List<Object?>;
      } else {
        return const <SupportedLanguage>[];
      }

      final result = <SupportedLanguage>[];
      for (final entry in items) {
        if (entry is Map<String, Object?>) {
          final code = (entry['code']?.toString() ?? '').trim().toLowerCase();
          final name = (entry['name']?.toString() ?? '').trim();
          final nativeName = (entry['nativeName']?.toString() ?? name).trim();
          if (code.isNotEmpty && name.isNotEmpty) {
            result.add(
              SupportedLanguage(
                code: code,
                name: name,
                nativeName: nativeName.isEmpty ? name : nativeName,
              ),
            );
          }
        }
      }
      return result;
    } on Object {
      return const <SupportedLanguage>[];
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

    final totalStopwatch = Stopwatch()..start();

    if (!_initialized) {
      await initialize();
    } else if (apiKey.isEmpty) {
      throw StateError(
        'Gemini API key is not configured. Please enter your Gemini API key in Settings.',
      );
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

    final (wavBytes, trimmedLength) =
        await LocalTranslationEngine.encodeAudioChunkInIsolate(audioWavChunk);
    final durationSec = (trimmedLength / 16000.0).toStringAsFixed(2);
    _log.info(
      'translateAudioChunk() [Cloud:$modelId] started: samples=$trimmedLength '
      '(~${durationSec}s @ 16kHz, wavBytes=${wavBytes.length}), '
      'pair=$baseLanguage <-> $targetLanguage',
    );

    final stopwatch = Stopwatch()..start();
    var lastEmittedPartialText = '';
    int? sttCompletedElapsedMs;
    var streamedChunkCount = 0;

    void handleStreamingAccumulatedOutput(String accumulatedRaw) {
      streamedChunkCount++;
      if (sttCompletedElapsedMs == null &&
          RegExp(r'"translated_text"\s*:').hasMatch(accumulatedRaw)) {
        sttCompletedElapsedMs = totalStopwatch.elapsedMilliseconds;
      }
      if (onPartialResult == null) return;
      final partial = LocalTranslationEngine.extractStreamingPartialResult(
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

    final rawResponse = await _streamAudioTranslationRequest(
      wavBytes: wavBytes,
      systemPrompt: systemPrompt,
      userPrompt: userTurnPrompt,
      onPartialAccumulated: handleStreamingAccumulatedOutput,
    );
    stopwatch.stop();
    final firstPassElapsedMs = totalStopwatch.elapsedMilliseconds;

    _log.info(
      'Cloud Gemini ($modelId) inference finished in ${stopwatch.elapsedMilliseconds}ms. '
      'Raw output:\n$rawResponse',
    );

    final TranslationResult parsed;
    try {
      parsed = LocalTranslationEngine.parseTranslationResponse(
        rawResponse,
        fallbackSourceLanguage: fallbackSourceCode,
        allowEmptyForSilence: true,
      );
    } on FormatException catch (e) {
      if (LocalTranslationEngine.isNonSpeechOrHallucination(
        translatedText: rawResponse,
      )) {
        _log.info(
          'Cloud output indicated silence or no speech ($e); returning empty pause result.',
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
        LocalTranslationEngine.isNonSpeechOrHallucination(
          originalText: parsed.originalText,
          translatedText: parsed.translatedText,
        )) {
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

    if (analysis.needsFallbackTranslation) {
      final sourceLangName = AppSettings.languageNameFor(
        analysis.resolvedSourceCode,
      );
      final desiredTargetName = AppSettings.languageNameFor(
        analysis.targetOutputCode,
      );
      final sourceTranscript = analysis.sourceTextForFallback;

      final fallbackText = await _runTextFallbackRequest(
        sourceTranscript: sourceTranscript,
        sourceLanguage: sourceLangName,
        targetLanguage: desiredTargetName,
        exchangeRate: exchangeRate,
        baseCurrency: baseCurrency,
        targetCurrency: targetCurrency,
      );

      if (fallbackText != null && fallbackText.trim().isNotEmpty) {
        totalStopwatch.stop();
        final totalMs = totalStopwatch.elapsedMilliseconds;
        final sttMs = firstPassElapsedMs;
        final transMs = totalMs >= sttMs ? totalMs - sttMs : 0;
        return TranslationResult(
          sourceLanguage: analysis.resolvedSourceCode,
          originalText: sourceTranscript,
          translatedText: fallbackText.trim(),
          speechToTextMs: sttMs,
          translationMs: transMs,
          totalDurationMs: totalMs,
        );
      }
    }

    totalStopwatch.stop();
    final totalMs = totalStopwatch.elapsedMilliseconds;
    final int sttMs;
    if (sttCompletedElapsedMs != null && streamedChunkCount > 1) {
      sttMs = sttCompletedElapsedMs!.clamp(0, totalMs);
    } else {
      sttMs = firstPassElapsedMs.clamp(0, totalMs);
    }
    final transMs = totalMs >= sttMs ? totalMs - sttMs : 0;

    return parsed.copyWith(
      sourceLanguage: analysis.resolvedSourceCode,
      speechToTextMs: sttMs,
      translationMs: transMs,
      totalDurationMs: totalMs,
    );
  }

  Future<String> _streamAudioTranslationRequest({
    required Uint8List wavBytes,
    required String systemPrompt,
    required String userPrompt,
    required void Function(String accumulatedRaw) onPartialAccumulated,
    bool allowModelRefreshRetry = true,
  }) async {
    final activeModel = modelId;
    final uri = Uri.parse(
      '$_baseApiUrl/$activeModel:streamGenerateContent?alt=sse&key=$apiKey',
    );
    final payload = <String, Object?>{
      'systemInstruction': <String, Object?>{
        'parts': <Object?>[
          <String, Object?>{'text': systemPrompt},
        ],
      },
      'contents': <Object?>[
        <String, Object?>{
          'role': 'user',
          'parts': <Object?>[
            <String, Object?>{
              'inlineData': <String, Object?>{
                'mimeType': 'audio/wav',
                'data': base64Encode(wavBytes),
              },
            },
            <String, Object?>{'text': userPrompt},
          ],
        },
      ],
      'generationConfig': _buildGenerationConfig(
        effectiveModelId: activeModel,
        temperature: 0.1,
        responseMimeType: 'application/json',
      ),
    };

    final request = http.Request('POST', uri)
      ..headers['Content-Type'] = 'application/json'
      ..headers['Accept'] = 'text/event-stream'
      ..body = jsonEncode(payload);

    final streamedResponse = await _client.send(request);
    if (streamedResponse.statusCode < 200 ||
        streamedResponse.statusCode >= 300) {
      final errorBody = await streamedResponse.stream.bytesToString();
      if (allowModelRefreshRetry &&
          (streamedResponse.statusCode == 404 ||
              streamedResponse.statusCode == 400)) {
        await refreshAvailableModels();
        if (modelId != activeModel) {
          _log.info(
            'Retrying audio translation with auto-resolved modelId=$modelId '
            '(previous=$activeModel)',
          );
          return _streamAudioTranslationRequest(
            wavBytes: wavBytes,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            onPartialAccumulated: onPartialAccumulated,
            allowModelRefreshRetry: false,
          );
        }
      }
      throw StateError(
        'Gemini API error (${streamedResponse.statusCode}): '
        '${_extractApiErrorMessage(errorBody)}',
      );
    }

    final accumulatedText = StringBuffer();
    final rawLines = streamedResponse.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    var receivedSseDataLine = false;
    final nonSseBuffer = StringBuffer();

    await for (final line in rawLines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (trimmed.startsWith('data:')) {
        receivedSseDataLine = true;
        final dataPayload = trimmed.substring(5).trim();
        if (dataPayload == '[DONE]' || dataPayload.isEmpty) continue;
        final chunkText = _extractCandidateTextFromGenerateResponse(
          dataPayload,
        );
        if (chunkText.isNotEmpty) {
          accumulatedText.write(chunkText);
          onPartialAccumulated(accumulatedText.toString());
        }
      } else {
        nonSseBuffer.writeln(line);
      }
    }

    if (!receivedSseDataLine && nonSseBuffer.isNotEmpty) {
      final fallbackText = _extractCandidateTextFromGenerateResponse(
        nonSseBuffer.toString(),
      );
      if (fallbackText.isNotEmpty) {
        accumulatedText.write(fallbackText);
        onPartialAccumulated(accumulatedText.toString());
      }
    }

    return accumulatedText.toString();
  }

  Future<String?> _runTextFallbackRequest({
    required String sourceTranscript,
    required String sourceLanguage,
    required String targetLanguage,
    required double exchangeRate,
    required String baseCurrency,
    required String targetCurrency,
  }) async {
    try {
      final activeModel = modelId;
      final uri = Uri.parse(
        '$_baseApiUrl/$activeModel:generateContent?key=$apiKey',
      );
      final systemPrompt = PromptTemplates.buildTextFallbackSystemPrompt(
        sourceLanguage: sourceLanguage,
        targetLanguage: targetLanguage,
      );
      final fallbackPrompt = PromptTemplates.buildTextFallbackPrompt(
        textToTranslate: sourceTranscript,
        sourceLanguage: sourceLanguage,
        targetLanguage: targetLanguage,
        exchangeRate: exchangeRate,
        baseCurrency: baseCurrency,
        targetCurrency: targetCurrency,
      );
      final response = await _client.post(
        uri,
        headers: const <String, String>{'Content-Type': 'application/json'},
        body: jsonEncode(<String, Object?>{
          'systemInstruction': <String, Object?>{
            'parts': <Object?>[
              <String, Object?>{'text': systemPrompt},
            ],
          },
          'contents': <Object?>[
            <String, Object?>{
              'role': 'user',
              'parts': <Object?>[
                <String, Object?>{'text': fallbackPrompt},
              ],
            },
          ],
          'generationConfig': _buildGenerationConfig(
            effectiveModelId: activeModel,
            temperature: 0.1,
          ),
        }),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      final rawText = _extractCandidateTextFromGenerateResponse(response.body);
      final cleaned = LocalTranslationEngine.stripMarkdownFences(rawText).trim();
      return cleaned.isEmpty ? null : cleaned;
    } on Object catch (e, st) {
      _log.warning('Cloud text fallback translation failed: $e', e, st);
      return null;
    }
  }

  @override
  Future<String> summarizeConversation({
    required List<Message> messages,
    required String baseLanguage,
    required String targetLanguage,
  }) async {
    if (messages.isEmpty) {
      return '';
    }
    if (apiKey.isEmpty) {
      throw StateError(
        'Gemini API key is not configured. Please enter your Gemini API key in Settings.',
      );
    }

    final systemPrompt = PromptTemplates.buildSummarySystemPrompt(
      baseLanguage: baseLanguage,
    );
    final prompt = PromptTemplates.buildConversationSummaryPrompt(
      messages: messages,
      baseLanguage: baseLanguage,
      targetLanguage: targetLanguage,
    );

    try {
      final activeModel = modelId;
      final uri = Uri.parse(
        '$_baseApiUrl/$activeModel:generateContent?key=$apiKey',
      );
      final response = await _client.post(
        uri,
        headers: const <String, String>{'Content-Type': 'application/json'},
        body: jsonEncode(<String, Object?>{
          'systemInstruction': <String, Object?>{
            'parts': <Object?>[
              <String, Object?>{'text': systemPrompt},
            ],
          },
          'contents': <Object?>[
            <String, Object?>{
              'role': 'user',
              'parts': <Object?>[
                <String, Object?>{'text': prompt},
              ],
            },
          ],
          'generationConfig': _buildGenerationConfig(
            effectiveModelId: activeModel,
            temperature: 0.2,
          ),
        }),
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final rawText = _extractCandidateTextFromGenerateResponse(
          response.body,
        );
        return LocalTranslationEngine.cleanSummaryOutput(rawText);
      }
    } on Object catch (e, st) {
      _log.warning('Cloud summarizeConversation() failed: $e', e, st);
    }

    return '';
  }

  static String _extractCandidateTextFromGenerateResponse(String rawJson) {
    final trimmed = rawJson.trim();
    if (trimmed.isEmpty) return '';
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, Object?>) {
        return _extractTextFromResponseMap(decoded);
      }
      if (decoded is List<Object?>) {
        final buffer = StringBuffer();
        for (final item in decoded) {
          if (item is Map<String, Object?>) {
            buffer.write(_extractTextFromResponseMap(item));
          }
        }
        return buffer.toString();
      }
    } on Object {
      // Fall back to returning raw string if not wrapped in standard Gemini envelope
    }
    return trimmed;
  }

  static String _extractTextFromResponseMap(Map<String, Object?> map) {
    final candidates = map['candidates'];
    if (candidates is List<Object?> && candidates.isNotEmpty) {
      final first = candidates.first;
      if (first is Map<String, Object?>) {
        final content = first['content'];
        if (content is Map<String, Object?>) {
          final parts = content['parts'];
          if (parts is List<Object?>) {
            final buffer = StringBuffer();
            for (final part in parts) {
              if (part is Map<String, Object?> && part['text'] is String) {
                buffer.write(part['text']! as String);
              }
            }
            return buffer.toString();
          }
        }
      }
    }
    return '';
  }

  static String _extractApiErrorMessage(String rawBody) {
    try {
      final decoded = jsonDecode(rawBody);
      if (decoded is Map<String, Object?> &&
          decoded['error'] is Map<String, Object?>) {
        final err = decoded['error']! as Map<String, Object?>;
        final msg = err['message']?.toString();
        if (msg != null && msg.isNotEmpty) {
          return msg;
        }
      }
    } on Object {
      // Ignore JSON parse failure on error body
    }
    return rawBody.trim().isEmpty ? 'Unknown network error' : rawBody.trim();
  }

  @override
  Future<void> dispose() async {
    _initialized = false;
    if (_ownsHttpClient) {
      _httpClient?.close();
    }
    _httpClient = null;
  }
}
