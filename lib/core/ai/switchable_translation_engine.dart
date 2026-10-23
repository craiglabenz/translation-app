import 'dart:typed_data';

import 'package:translation_app/core/ai/local_translation_engine.dart';
import 'package:translation_app/core/ai/network_translation_engine.dart';
import 'package:translation_app/core/ai/translation_engine.dart';
import 'package:translation_app/core/data/models/app_settings.dart';
import 'package:translation_app/core/data/models/message.dart';

/// A [TranslationEngine] proxy that dynamically delegates to either an
/// on-device [LocalTranslationEngine] or a cloud-based
/// [NetworkTranslationEngine] depending on the user's selected
/// [TranslationEngineMode].
class SwitchableTranslationEngine implements TranslationEngine {
  SwitchableTranslationEngine({
    required this.localEngine,
    required this.networkEngine,
    TranslationEngineMode initialMode = TranslationEngineMode.onDevice,
  }) : _mode = initialMode;

  final LocalTranslationEngine localEngine;
  final NetworkTranslationEngine networkEngine;
  TranslationEngineMode _mode;

  /// Current active [TranslationEngineMode].
  TranslationEngineMode get mode => _mode;

  /// Updates the active [TranslationEngineMode].
  void setMode(TranslationEngineMode mode) {
    _mode = mode;
  }

  /// Returns the currently selected [TranslationEngine].
  TranslationEngine get activeEngine =>
      _mode == TranslationEngineMode.cloud ? networkEngine : localEngine;

  @override
  List<SupportedLanguage> get supportedLanguages =>
      activeEngine.supportedLanguages;

  @override
  Future<void> initialize() => activeEngine.initialize();

  @override
  Future<TranslationResult> translateAudioChunk({
    required Float32List audioWavChunk,
    required String baseLanguage,
    required String targetLanguage,
    required double exchangeRate,
    required String baseCurrency,
    required String targetCurrency,
    void Function(TranslationResult partialResult)? onPartialResult,
  }) {
    return activeEngine.translateAudioChunk(
      audioWavChunk: audioWavChunk,
      baseLanguage: baseLanguage,
      targetLanguage: targetLanguage,
      exchangeRate: exchangeRate,
      baseCurrency: baseCurrency,
      targetCurrency: targetCurrency,
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
