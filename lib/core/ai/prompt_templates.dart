import 'package:translation_app/core/ai/language_detector.dart';
import 'package:translation_app/core/data/models/app_settings.dart';
import 'package:translation_app/core/data/models/message.dart';

/// Prompt templates and JSON schema instructions for Gemma 4 multimodal audio
/// translation and conversation summarization.
class PromptTemplates {
  const PromptTemplates._();

  /// Builds the system prompt for translating spoken audio between
  /// [baseLanguage] and [targetLanguage] with automatic time and price
  /// formatting and graceful silence/pause handling.
  static String buildSystemPrompt({
    required String baseLanguage,
    required String targetLanguage,
    required double exchangeRate,
    required String baseCurrency,
    required String targetCurrency,
  }) {
    final formattedRate = exchangeRate.toStringAsFixed(4);
    final baseCode = LanguageDetector.normalizeLanguageCode(baseLanguage);
    final targetCode = LanguageDetector.normalizeLanguageCode(targetLanguage);
    return '''
You are a real-time translator. The user's base language is "$baseLanguage" and the target is "$targetLanguage".
Listen to the provided audio. Identify which of these two languages is being spoken. Translate the speech into the other language.
Direction Rules (CRITICAL):
- If the audio is spoken in $baseLanguage ($baseCode), set "detected_language" to "$baseCode" and translate the speech into $targetLanguage ($targetCode) in "translated_text".
- If the audio is spoken in $targetLanguage ($targetCode), set "detected_language" to "$targetCode" and translate the speech into $baseLanguage ($baseCode) in "translated_text".
- "translated_text" MUST ALWAYS be in the opposite language from "original_transcript". NEVER repeat or transcribe $baseLanguage as $baseLanguage or $targetLanguage as $targetLanguage in "translated_text".
Silence & Pause Rules (CRITICAL):
- If the audio contains only silence, a conversational pause, breathing, or background noise with no clear human speech, return empty strings: {"detected_language": "$baseCode", "translated_text": "", "original_transcript": ""}.
- NEVER invent, guess, or hallucinate example phrases (such as going to the store to buy milk) when nothing was said, and NEVER output meta-commentary about missing or silent audio files.
Formatting Rules:
1. Convert any spoken times into standard 24-hour and 12-hour format (e.g., '18:00 (6PM)').
2. Convert any spoken prices into $baseCurrency using the exchange rate: 1 $targetCurrency = $formattedRate $baseCurrency. Output format: 'original price (converted price)'.
3. Return ONLY a valid JSON object matching this schema: {"detected_language": "en", "translated_text": "...", "original_transcript": "..."}.''';
  }

  /// Builds the user-turn instruction accompanying the WAV audio clip.
  ///
  /// Places `"original_transcript"` first in the JSON template so autoregressive
  /// decoding transcribes the audio first, identifies its language second, and
  /// translates into the opposite language third.
  static String buildAudioTurnPrompt({
    required String baseLanguage,
    required String targetLanguage,
  }) {
    final baseCode = LanguageDetector.normalizeLanguageCode(baseLanguage);
    final targetCode = LanguageDetector.normalizeLanguageCode(targetLanguage);
    return '''
Listen to the audio and translate between $baseLanguage ($baseCode) and $targetLanguage ($targetCode):
1. "original_transcript": transcribe the exact spoken words in their original language, or "" if no clear speech was spoken.
2. "detected_language": "$baseCode" if $baseLanguage was spoken, or "$targetCode" if $targetLanguage was spoken.
3. "translated_text": translate "original_transcript" into the OTHER language (if "$baseCode" was spoken, "translated_text" MUST be written in $targetLanguage ($targetCode); if "$targetCode" was spoken, "translated_text" MUST be written in $baseLanguage ($baseCode)), or "" if "original_transcript" is empty. NEVER output the same language in "translated_text", NEVER hallucinate example sentences on silence, and NEVER complain about missing audio.
Output ONLY valid JSON:
{"original_transcript": "...", "detected_language": "$baseCode", "translated_text": "..."}''';
  }

  /// Builds a dedicated system prompt for the Speech-to-Text (STT) and
  /// language detection step (Step 1 of the separated pipeline).
  static String buildSpeechToTextSystemPrompt({
    required String baseLanguage,
    required String targetLanguage,
  }) {
    final baseCode = LanguageDetector.normalizeLanguageCode(baseLanguage);
    final targetCode = LanguageDetector.normalizeLanguageCode(targetLanguage);
    return '''
You are an accurate speech-to-text transcriber and language detector for conversations between "$baseLanguage" ($baseCode) and "$targetLanguage" ($targetCode).
Listen to the provided audio, transcribe the exact words spoken in their original language, and identify whether "$baseCode" or "$targetCode" was spoken.
Rules (CRITICAL):
- Do NOT translate the speech. "original_transcript" MUST be written in the exact language spoken in the audio.
- Set "detected_language" to "$baseCode" if $baseLanguage was spoken, or "$targetCode" if $targetLanguage was spoken.
- If the audio contains only silence, a pause, breathing, or background noise with no clear human speech, return empty strings: {"original_transcript": "", "detected_language": "$baseCode"}.
- NEVER invent, guess, or hallucinate example phrases when nothing was said, and NEVER output meta-commentary about missing or silent audio files.
- Return ONLY a valid JSON object: {"original_transcript": "...", "detected_language": "$baseCode"}.''';
  }

  /// Builds the user-turn prompt for the Speech-to-Text (STT) step.
  static String buildSpeechToTextTurnPrompt({
    required String baseLanguage,
    required String targetLanguage,
  }) {
    final baseCode = LanguageDetector.normalizeLanguageCode(baseLanguage);
    final targetCode = LanguageDetector.normalizeLanguageCode(targetLanguage);
    return '''
Transcribe the spoken audio verbatim in its original language ($baseLanguage ($baseCode) or $targetLanguage ($targetCode)) without translating:
1. "original_transcript": exact spoken words in their original language, or "" if no clear speech was spoken.
2. "detected_language": "$baseCode" if $baseLanguage was spoken, or "$targetCode" if $targetLanguage was spoken.
Output ONLY valid JSON:
{"original_transcript": "...", "detected_language": "$baseCode"}''';
  }

  /// Builds a text-only system instruction for the automatic self-correction
  /// fallback pass so the text-only session is never told to "Listen to the
  /// provided audio".
  static String buildTextFallbackSystemPrompt({
    required String sourceLanguage,
    required String targetLanguage,
  }) {
    return '''
You are a text translator between $sourceLanguage and $targetLanguage.
Translate the provided $sourceLanguage text directly into $targetLanguage.
Never ask for an audio file, never repeat the source language, and output nothing if the input is empty or indicates no speech.''';
  }

  /// Builds a focused text-to-text translation prompt used as an automatic
  /// self-correction pass if the multimodal audio pass transcribed the speech
  /// without translating it.
  static String buildTextFallbackPrompt({
    required String textToTranslate,
    required String sourceLanguage,
    required String targetLanguage,
    required double exchangeRate,
    required String baseCurrency,
    required String targetCurrency,
  }) {
    final formattedRate = exchangeRate.toStringAsFixed(4);
    return '''
Translate the following $sourceLanguage text into $targetLanguage.
CRITICAL RULES:
1. Your output MUST be written in $targetLanguage. NEVER repeat or echo the $sourceLanguage text.
2. Format any times as '24-hour (12-hour)' (e.g., '18:00 (6PM)') and any prices using 1 $targetCurrency = $formattedRate $baseCurrency as 'original price (converted price)'.
3. Output ONLY the translated $targetLanguage text, with no JSON, no markdown, and no explanation.

$sourceLanguage text: "$textToTranslate"
$targetLanguage translation:''';
  }

  /// Builds the system instruction for summarizing a chat thread into a
  /// concise 3 to 5 word description in the user's native language
  /// ([baseLanguage]).
  static String buildSummarySystemPrompt({
    required String baseLanguage,
  }) {
    final baseCode = LanguageDetector.normalizeLanguageCode(baseLanguage);
    final baseName = AppSettings.languageNameFor(baseLanguage);
    final nativeName = AppSettings.nativeLanguageNameFor(baseLanguage);
    final nativeLabel = nativeName != baseName && nativeName.isNotEmpty
        ? '$baseName ($nativeName)'
        : baseLanguage;
    return '''
You summarize bilingual conversations into a concise 3 to 5 word description written strictly in the user's native language: $nativeLabel ($baseCode).
CRITICAL LANGUAGE RULE: Always write the summary in $nativeLabel ($baseCode). Do NOT default to English when the user's native language is not English.
Output ONLY a 3 to 5 word summary title in $nativeLabel with no quotes, no markdown, and no trailing period.''';
  }

  /// Builds a prompt asking the translation engine to summarize [messages]
  /// with a 3 to 5 word description in the user's native language
  /// ([baseLanguage]).
  static String buildConversationSummaryPrompt({
    required List<Message> messages,
    required String baseLanguage,
    required String targetLanguage,
  }) {
    final baseCode = LanguageDetector.normalizeLanguageCode(baseLanguage);
    final baseName = AppSettings.languageNameFor(baseLanguage);
    final nativeName = AppSettings.nativeLanguageNameFor(baseLanguage);
    final nativeLabel = nativeName != baseName && nativeName.isNotEmpty
        ? '$baseName ($nativeName)'
        : baseLanguage;

    final transcriptBuffer = StringBuffer();
    for (final msg in messages) {
      final speaker = msg.isBaseLanguage ? baseLanguage : targetLanguage;
      final original = msg.originalText.trim();
      final translated = msg.effectiveTranslatedText.trim();
      final text = original.isNotEmpty && original != translated
          ? '$original -> $translated'
          : translated;
      transcriptBuffer.writeln('- [$speaker]: $text');
    }

    return '''
Summarize the following conversation between $baseLanguage and $targetLanguage with a 3 to 5 word description written strictly in $nativeLabel ($baseCode).
Rules:
1. Must be 3 to 5 words long.
2. CRITICAL: Write the summary ONLY in the user's native language: $nativeLabel ($baseCode). Do NOT use English unless the native language is English, and do NOT use $targetLanguage.
3. Output ONLY the 3 to 5 word description in $nativeLabel, with no quotes, no labels, and no punctuation at the end.

Conversation:
${transcriptBuffer.toString().trimRight()}

3 to 5 word summary in $nativeLabel ($baseCode):''';
  }
}
