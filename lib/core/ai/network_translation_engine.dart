import 'dart:typed_data';

import 'package:translation_app/core/ai/translation_engine.dart';

/// Stubbed cloud translation engine reserved for v1 Gemini Socket support.
class NetworkTranslationEngine implements TranslationEngine {
  const NetworkTranslationEngine();

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
  Future<void> dispose() {
    throw UnimplementedError('TODO: v1 Gemini Socket');
  }
}
