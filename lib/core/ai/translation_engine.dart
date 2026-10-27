import 'dart:typed_data';

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:translation_app/core/ai/speech_to_text_engine.dart';
import 'package:translation_app/core/data/models/app_settings.dart';
import 'package:translation_app/core/data/models/message.dart';

part 'translation_engine.freezed.dart';
part 'translation_engine.g.dart';

/// Result of asking the translation LLM whether `part1Transcript` and
/// `part2Transcript` in the same language (separated by `interveningTurns` in
/// the other language) belong to the same continuous sentence/thought or if
/// the intervening turn forked the conversation into a new message.
@immutable
class ContinuationDecision {
  const ContinuationDecision({
    required this.isSameSentence,
    required this.combinedOriginalText,
    required this.result,
  });

  /// True when Part 1 and Part 2 should be clumped into the existing message
  /// bubble for that language. False when Part 2 is a new response that should
  /// appear as a new bubble below the intervening turn(s).
  final bool isSameSentence;

  /// Combined original transcript (`Part 1 + Part 2`) when [isSameSentence] is
  /// true, or `Part 2` alone when [isSameSentence] is false.
  final String combinedOriginalText;

  /// Translated output for [combinedOriginalText].
  final TranslationResult result;
}

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
    String? contextPromptBlock,
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

/// Extended contract for translation engines that support separated multi-segment
/// Speech-to-Text (Step 1), per-segment Text Translation (Step 2), and
/// LLM-driven continuation clumping across interjections.
abstract class SegmentedTranslationEngine implements TranslationEngine {
  Future<SpeechToTextResult> transcribeAudioChunk({
    required Float32List audioWavChunk,
    required String baseLanguage,
    required String targetLanguage,
    String? contextPromptBlock,
  });

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
  });

  /// Evaluates a "movie script" continuation where a speaker in [sourceLanguage]
  /// said [part1Transcript], the other party spoke [interveningTurns], and the
  /// first speaker followed up with [part2Transcript] within the running clock.
  Future<ContinuationDecision> resolveContinuationAndTranslate({
    required String part1Transcript,
    required String part2Transcript,
    required List<Message> interveningTurns,
    required String sourceLanguage,
    required String baseLanguage,
    required String targetLanguage,
    required double exchangeRate,
    required String baseCurrency,
    required String targetCurrency,
    int? speechToTextMs,
    String? speechToTextModel,
    String? contextPromptBlock,
  });
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
