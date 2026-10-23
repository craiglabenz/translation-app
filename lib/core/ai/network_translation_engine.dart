import 'dart:typed_data';

import 'package:translation_app/core/ai/local_translation_engine.dart';
import 'package:translation_app/core/ai/translation_engine.dart';
import 'package:translation_app/core/data/models/app_settings.dart';
import 'package:translation_app/core/data/models/message.dart';

/// Stubbed cloud translation engine reserved for v1 Gemini Socket support.
class NetworkTranslationEngine implements TranslationEngine {
  const NetworkTranslationEngine();

  /// Languages supported by the cloud-based translation engine.
  static const List<SupportedLanguage> cloudSupportedLanguages =
      LocalTranslationEngine.gemmaSupportedLanguages;

  @override
  List<SupportedLanguage> get supportedLanguages => cloudSupportedLanguages;

  @override
  Future<void> initialize() {
    throw UnimplementedError('TODO: v1 Gemini Socket');
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
  }) {
    throw UnimplementedError('TODO: v1 Gemini Socket');
  }

  @override
  Future<String> summarizeConversation({
    required List<Message> messages,
    required String baseLanguage,
    required String targetLanguage,
  }) {
    throw UnimplementedError('TODO: v1 Gemini Socket');
  }

  @override
  Future<void> dispose() {
    throw UnimplementedError('TODO: v1 Gemini Socket');
  }
}
