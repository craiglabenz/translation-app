import 'dart:typed_data';

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:translation_app/core/data/models/app_settings.dart';
import 'package:translation_app/core/data/models/message.dart';

part 'translation_engine.freezed.dart';
part 'translation_engine.g.dart';

/// Abstract contract for real-time audio translation engines.
abstract class TranslationEngine {
  /// The list of languages supported by this translation engine.
  List<SupportedLanguage> get supportedLanguages;

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

  /// Summarizes the chat thread [messages] into a concise 3 to 5 word
  /// description.
  Future<String> summarizeConversation({
    required List<Message> messages,
    required String baseLanguage,
    required String targetLanguage,
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

    /// Time spent in milliseconds on the speech-to-text step (audio encoding,
    /// prefill, language detection, and source transcript generation).
    int? speechToTextMs,

    /// Time spent in milliseconds on the translation step (target language
    /// token generation and any text-to-text fallback pass).
    int? translationMs,

    /// Total time spent in milliseconds across all steps.
    int? totalDurationMs,

    /// Display name of the model that performed Step 1 (Speech-to-Text).
    String? speechToTextModel,

    /// Display name of the model that performed Step 2 (Text Translation).
    String? translationModel,
  }) = _TranslationResult;

  factory TranslationResult.fromJson(Map<String, Object?> json) =>
      _$TranslationResultFromJson(json);
}
