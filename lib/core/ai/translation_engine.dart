import 'dart:typed_data';

import 'package:freezed_annotation/freezed_annotation.dart';

part 'translation_engine.freezed.dart';
part 'translation_engine.g.dart';

/// Abstract contract for real-time audio translation engines.
abstract class TranslationEngine {
  Future<void> initialize();

  Future<TranslationResult> translateAudioChunk({
    required Float32List audioWavChunk,
    required String baseLanguage,
    required String targetLanguage,
    required double exchangeRate,
    required String baseCurrency,
    required String targetCurrency,
    void Function(TranslationResult partialResult)? onPartialResult,
  });

  Future<void> dispose();
}

/// Structured result of translating an audio chunk.
@freezed
abstract class TranslationResult with _$TranslationResult {
  const factory TranslationResult({
    required String sourceLanguage,
    required String translatedText,
    String? originalText,
  }) = _TranslationResult;

  factory TranslationResult.fromJson(Map<String, Object?> json) =>
      _$TranslationResultFromJson(json);
}
