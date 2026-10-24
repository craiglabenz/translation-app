import 'dart:typed_data';

import 'package:translation_app/core/ai/language_detector.dart';
import 'package:translation_app/core/ai/local_translation_engine.dart';
import 'package:translation_app/core/ai/network_translation_engine.dart';
import 'package:translation_app/core/ai/speech_to_text_engine.dart';
import 'package:translation_app/core/ai/translation_engine.dart';
import 'package:translation_app/core/data/models/app_settings.dart';
import 'package:translation_app/core/data/models/message.dart';

/// A two-stage [TranslationEngine] coordinator that separates Step 1
/// (Speech-to-Text & Language Detection) from Step 2 (Text Translation),
/// allowing each step to be independently configured as On-Device
/// (Gemma 4 E2B) or Cloud (Google Gemini).
class SwitchableTranslationEngine implements TranslationEngine {
  SwitchableTranslationEngine({
    required this.localEngine,
    required this.networkEngine,
    TranslationEngineMode initialMode = TranslationEngineMode.onDevice,
    TranslationEngineMode initialSttMode = TranslationEngineMode.onDevice,
    String initialCloudSttModelId = AppSettings.defaultCloudModelId,
  }) : _mode = initialMode,
       _sttMode = initialSttMode,
       _cloudSttModelId = initialCloudSttModelId;

  final LocalTranslationEngine localEngine;
  final NetworkTranslationEngine networkEngine;

  TranslationEngineMode _mode;
  TranslationEngineMode _sttMode;
  String _cloudSttModelId;

  /// Current active [TranslationEngineMode] for Step 2 (Translation).
  TranslationEngineMode get mode => _mode;

  /// Current active [TranslationEngineMode] for Step 1 (Speech-to-Text).
  TranslationEngineMode get sttMode => _sttMode;

  /// Selected cloud Gemini STT model ID (`gemini-3.8-flash` or `gemini-3.1-pro`).
  String get cloudSttModelId => _cloudSttModelId;

  /// Updates the active [TranslationEngineMode] for Step 2 (Translation).
  void setMode(TranslationEngineMode mode) {
    _mode = mode;
  }

  /// Updates the active [TranslationEngineMode] for Step 1 (Speech-to-Text).
  void setSttMode(TranslationEngineMode mode) {
    _sttMode = mode;
  }

  /// Updates the selected cloud Gemini STT model ID.
  void setCloudSttModelId(String modelId) {
    final trimmed = modelId.trim();
    if (trimmed.isNotEmpty) {
      _cloudSttModelId = trimmed;
    }
  }

  /// Synchronizes all STT and Translation settings from [settings].
  void syncWithSettings(AppSettings settings) {
    _mode = settings.translationEngineMode;
    _sttMode = settings.sttEngineMode;
    _cloudSttModelId = settings.cloudSttModelId;
  }

  /// Returns the currently selected [TranslationEngine] for Step 2 (Translation).
  TranslationEngine get activeEngine =>
      _mode == TranslationEngineMode.cloud ? networkEngine : localEngine;

  @override
  List<SupportedLanguage> get supportedLanguages =>
      activeEngine.supportedLanguages;

  @override
  Future<void> initialize() async {
    await activeEngine.initialize();
    if (_sttMode == TranslationEngineMode.onDevice &&
        _mode == TranslationEngineMode.cloud) {
      await localEngine.initialize();
    }
  }

  /// Executes Step 1 (Speech-to-Text & Language Detection) using the
  /// configured STT engine (`On-Device Gemma 4 Audio` or `Cloud Gemini STT`).
  Future<SpeechToTextResult> transcribeAudioChunk({
    required Float32List audioWavChunk,
    required String baseLanguage,
    required String targetLanguage,
    String? contextPromptBlock,
  }) async {
    if (_sttMode == TranslationEngineMode.cloud) {
      return networkEngine.transcribeAudioChunk(
        audioWavChunk: audioWavChunk,
        baseLanguage: baseLanguage,
        targetLanguage: targetLanguage,
        overrideModelId: _cloudSttModelId,
        contextPromptBlock: contextPromptBlock,
      );
    }

    return localEngine.transcribeAudioChunk(
      audioWavChunk: audioWavChunk,
      baseLanguage: baseLanguage,
      targetLanguage: targetLanguage,
      contextPromptBlock: contextPromptBlock,
    );
  }

  /// Executes Step 2 (Text Translation) using the configured Translation engine
  /// (`On-Device Gemma 4` or `Cloud Gemini`).
  Future<TranslationResult> translateText({
    required String transcript,
    required String sourceLanguage,
    required String baseLanguage,
    required String targetLanguage,
    required double exchangeRate,
    required String baseCurrency,
    required String targetCurrency,
    int? speechToTextMs,
    String? speechToTextModel,
    String? contextPromptBlock,
    void Function(TranslationResult partialResult)? onPartialResult,
  }) {
    if (_mode == TranslationEngineMode.cloud) {
      return networkEngine.translateText(
        transcript: transcript,
        sourceLanguage: sourceLanguage,
        baseLanguage: baseLanguage,
        targetLanguage: targetLanguage,
        exchangeRate: exchangeRate,
        baseCurrency: baseCurrency,
        targetCurrency: targetCurrency,
        speechToTextMs: speechToTextMs,
        speechToTextModel: speechToTextModel,
        contextPromptBlock: contextPromptBlock,
        onPartialResult: onPartialResult,
      );
    }
    return localEngine.translateText(
      transcript: transcript,
      sourceLanguage: sourceLanguage,
      baseLanguage: baseLanguage,
      targetLanguage: targetLanguage,
      exchangeRate: exchangeRate,
      baseCurrency: baseCurrency,
      targetCurrency: targetCurrency,
      speechToTextMs: speechToTextMs,
      speechToTextModel: speechToTextModel,
      contextPromptBlock: contextPromptBlock,
      onPartialResult: onPartialResult,
    );
  }

  @override
  Future<TranslationResult> translateAudioChunk({
    required Float32List audioWavChunk,
    required String baseLanguage,
    required String targetLanguage,
    required double exchangeRate,
    required String baseCurrency,
    required String targetCurrency,
    String? contextPromptBlock,
    void Function(TranslationResult partialResult)? onPartialResult,
  }) async {
    final fallbackSourceCode = LanguageDetector.normalizeLanguageCode(
      baseLanguage,
    );

    // Step 1: Speech-to-Text (ASR) & Language Detection
    final sttResult = await transcribeAudioChunk(
      audioWavChunk: audioWavChunk,
      baseLanguage: baseLanguage,
      targetLanguage: targetLanguage,
      contextPromptBlock: contextPromptBlock,
    );

    final activeTransModel = _mode == TranslationEngineMode.cloud
        ? AppSettings.cloudModelDisplayNameFor(networkEngine.modelId)
        : 'Gemma 4';

    if (sttResult.transcript.trim().isEmpty) {
      return TranslationResult(
        sourceLanguage: fallbackSourceCode,
        translatedText: '',
        originalText: '',
        speechToTextMs: sttResult.durationMs,
        translationMs: 0,
        totalDurationMs: sttResult.durationMs,
        speechToTextModel: sttResult.modelName,
        translationModel: activeTransModel,
      );
    }

    // Step 2: Text Translation
    return translateText(
      transcript: sttResult.transcript,
      sourceLanguage: sttResult.detectedLanguageCode,
      baseLanguage: baseLanguage,
      targetLanguage: targetLanguage,
      exchangeRate: exchangeRate,
      baseCurrency: baseCurrency,
      targetCurrency: targetCurrency,
      speechToTextMs: sttResult.durationMs,
      speechToTextModel: sttResult.modelName,
      contextPromptBlock: contextPromptBlock,
      onPartialResult: onPartialResult,
    );
  }

  @override
  Future<String> summarizeConversation({
    required List<Message> messages,
    required String baseLanguage,
    required String targetLanguage,
  }) {
    return activeEngine.summarizeConversation(
      messages: messages,
      baseLanguage: baseLanguage,
      targetLanguage: targetLanguage,
    );
  }

  @override
  Future<void> dispose() async {
    await localEngine.dispose();
    await networkEngine.dispose();
  }
}
