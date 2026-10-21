import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:translation_app/core/ai/model_manager.dart';
import 'package:translation_app/core/ai/prompt_templates.dart';
import 'package:translation_app/core/ai/translation_engine.dart';

/// Signature for executing multimodal audio + prompt inference.
typedef AudioInferenceRunner =
    Future<String> Function({
      required Uint8List wavBytes,
      required String systemPrompt,
    });

/// On-device translation engine powered by Gemma 4 (E2B) on `LiteRtLmEngine`.
class LocalTranslationEngine implements TranslationEngine {
  LocalTranslationEngine({
    required this._modelManager,
    this._inferenceRunner,
  });

  final ModelManager _modelManager;
  final AudioInferenceRunner? _inferenceRunner;

  InferenceModel? _model;
  bool _initialized = false;

  bool get isInitialized => _initialized;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    if (_inferenceRunner != null) {
      _initialized = true;
      return;
    }

    final ready = await _modelManager.ensureModelDownloaded();
    if (!ready) {
      throw StateError(
        _modelManager.stateValue.error ??
            'Gemma 4 E2B model is not installed on device.',
      );
    }

    try {
      _model = await FlutterEdgeAi.getActiveModel(
        maxTokens: 4096,
        supportAudio: true,
        preferredBackend: PreferredBackend.gpu,
      );
      _initialized = true;
    } on Object catch (e) {
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
  }) async {
    if (audioWavChunk.isEmpty) {
      throw ArgumentError('Audio chunk cannot be empty.');
    }

    if (!_initialized) {
      await initialize();
    }

    final systemPrompt = PromptTemplates.buildSystemPrompt(
      baseLanguage: baseLanguage,
      targetLanguage: targetLanguage,
      exchangeRate: exchangeRate,
      baseCurrency: baseCurrency,
      targetCurrency: targetCurrency,
    );

    final wavBytes = encodeFloat32PcmToWav(audioWavChunk);

    final String rawResponse;
    if (_inferenceRunner != null) {
      rawResponse = await _inferenceRunner(
        wavBytes: wavBytes,
        systemPrompt: systemPrompt,
      );
    } else {
      rawResponse = await _runModelInference(
        wavBytes: wavBytes,
        systemPrompt: systemPrompt,
      );
    }

    return parseTranslationResponse(
      rawResponse,
      fallbackSourceLanguage: baseLanguage,
    );
  }

  Future<String> _runModelInference({
    required Uint8List wavBytes,
    required String systemPrompt,
  }) async {
    final model =
        _model ??
        await FlutterEdgeAi.getActiveModel(
          maxTokens: 4096,
          supportAudio: true,
          preferredBackend: PreferredBackend.gpu,
        );
    _model = model;

    final session = await model.openSession(
      enableAudioModality: true,
      systemInstruction: systemPrompt,
      enableThinking: false,
      maxOutputTokens: 512,
    );
    try {
      await session.addQueryChunk(
        Message.withAudio(
          text: systemPrompt,
          audioBytes: wavBytes,
          isUser: true,
        ),
      );
      return await session.getResponse();
    } finally {
      await session.close();
    }
  }

  /// Sanitizes and parses the raw LLM output into a [TranslationResult].
  ///
  /// Handles markdown fences (````json ... ````), leading/trailing prose around
  /// a JSON object, and falls back gracefully if the LLM output is plain text.
  static TranslationResult parseTranslationResponse(
    String rawOutput, {
    String fallbackSourceLanguage = 'en',
  }) {
    final trimmed = rawOutput.trim();
    if (trimmed.isEmpty) {
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
      final originalTranscript =
          (parsedMap['original_transcript'] as String? ??
                  parsedMap['original_text'] as String?)
              ?.trim();

      if (translatedText.isEmpty) {
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
    final model = _model;
    _model = null;
    _initialized = false;
    if (model != null) {
      await model.close();
    }
  }
}
