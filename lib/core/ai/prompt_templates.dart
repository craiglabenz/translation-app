import 'package:translation_app/core/ai/language_detector.dart';
import 'package:translation_app/core/data/models/app_settings.dart';
import 'package:translation_app/core/data/models/message.dart';

/// Prompt templates and JSON schema instructions for Gemma 4 multimodal audio
/// translation and conversation summarization.
class PromptTemplates {
  const PromptTemplates._();

  /// Formats active situational [presets], ad-hoc [customKeywords], and
  /// [recentTurns] into a concise context block appended to Step 1 (STT) and
  /// Step 2 (Translation) prompts.
  static String buildContextPromptBlock({
    List<ConversationContextPreset> presets =
        const <ConversationContextPreset>[],
    List<String> customKeywords = const <String>[],
    List<Message> recentTurns = const <Message>[],
    required String baseLanguage,
    required String targetLanguage,
  }) {
    final cleanedKeywords = customKeywords
        .map((k) => k.trim())
        .where((k) => k.isNotEmpty)
        .toList();
    final validTurns = recentTurns
        .where(
          (m) =>
              m.originalText.trim().isNotEmpty ||
              m.translatedText.trim().isNotEmpty,
        )
        .toList();

    if (presets.isEmpty && cleanedKeywords.isEmpty && validTurns.isEmpty) {
      return '';
    }

    final baseCode = LanguageDetector.normalizeLanguageCode(baseLanguage);
    final targetCode = LanguageDetector.normalizeLanguageCode(targetLanguage);
    final buffer = StringBuffer();

    if (presets.isNotEmpty || cleanedKeywords.isNotEmpty) {
      buffer.writeln(
        'Conversation Context & Domain Vocabulary (use this to disambiguate noisy/accented speech, homophones, and domain terms):',
      );
      for (final preset in presets) {
        final kw = preset.keywords.trim();
        if (kw.isNotEmpty) {
          buffer.writeln('- Topic: ${preset.name} (expected terms: $kw)');
        } else {
          buffer.writeln('- Topic: ${preset.name}');
        }
      }
      if (cleanedKeywords.isNotEmpty) {
        buffer.writeln(
          '- Custom keywords / names: ${cleanedKeywords.join(', ')}',
        );
      }
    }

    if (validTurns.isNotEmpty) {
      buffer.writeln(
        'Recent Conversation History (for topic and vocabulary continuity ONLY — NEVER repeat, re-transcribe, or re-translate these prior turns; process ONLY the new current utterance):',
      );
      for (final turn in validTurns) {
        final srcCode = turn.isBaseLanguage ? baseCode : targetCode;
        final dstCode = turn.isBaseLanguage ? targetCode : baseCode;
        final orig = turn.originalText.trim();
        final trans = turn.translatedText.trim();
        if (orig.isNotEmpty && trans.isNotEmpty && orig != trans) {
          buffer.writeln('- [$srcCode -> $dstCode]: "$orig" -> "$trans"');
        } else {
          buffer.writeln('- [$srcCode]: "${orig.isNotEmpty ? orig : trans}"');
        }
      }
    }

    return buffer.toString().trimRight();
  }

  /// Builds the system prompt for translating spoken audio between
  /// [baseLanguage] and [targetLanguage] with automatic time and price
  /// formatting and graceful silence/pause handling.
  static String buildSystemPrompt({
    required String baseLanguage,
    required String targetLanguage,
    required double exchangeRate,
    required String baseCurrency,
    required String targetCurrency,
    String? contextPromptBlock,
  }) {
    final formattedRate = exchangeRate.toStringAsFixed(4);
    final baseCode = LanguageDetector.normalizeLanguageCode(baseLanguage);
    final targetCode = LanguageDetector.normalizeLanguageCode(targetLanguage);
    final trimmedContext = contextPromptBlock?.trim() ?? '';
    final contextSuffix = trimmedContext.isEmpty ? '' : '\n$trimmedContext';
    return '''
You are a real-time translator. The user's base language is "$baseLanguage" and the target is "$targetLanguage".
Listen to the provided audio. Identify which of these two languages is being spoken. Translate the speech into the other language.
Direction Rules (CRITICAL):
- Evaluate the ENTIRE audio clip and determine the spoken language from the MAJORITY of the full utterance. Do NOT let a single leading loanword, interjection (e.g., "Okay", "No", "Yes", "Oh", "Wait", "Um"), proper noun, or ambiguous first word override the language of the rest of the sentence.
- If the audio is spoken primarily in $baseLanguage ($baseCode), set "detected_language" to "$baseCode" and translate the speech into $targetLanguage ($targetCode) in "translated_text".
- If the audio is spoken primarily in $targetLanguage ($targetCode), set "detected_language" to "$targetCode" and translate the speech into $baseLanguage ($baseCode) in "translated_text".
- "translated_text" MUST ALWAYS be in the opposite language from "original_transcript". NEVER repeat or transcribe $baseLanguage as $baseLanguage or $targetLanguage as $targetLanguage in "translated_text".
Silence & Pause Rules (CRITICAL):
- If the audio contains only silence, a conversational pause, breathing, or background noise with no clear human speech, return empty strings: {"detected_language": "$baseCode", "translated_text": "", "original_transcript": ""}.
- NEVER invent, guess, or hallucinate example phrases (such as going to the store to buy milk) when nothing was said, and NEVER output meta-commentary about missing or silent audio files.
Formatting Rules:
1. Convert any spoken times into standard 24-hour and 12-hour format (e.g., '18:00 (6PM)').
2. Convert any spoken prices into $baseCurrency using the exchange rate: 1 $targetCurrency = $formattedRate $baseCurrency. Output format: 'original price (converted price)'.
3. Return ONLY a valid JSON object matching this schema: {"detected_language": "en", "translated_text": "...", "original_transcript": "..."}.$contextSuffix''';
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
Listen to the full audio clip and translate between $baseLanguage ($baseCode) and $targetLanguage ($targetCode):
1. "original_transcript": transcribe the exact spoken words in their original language (determine the language from the MAJORITY of the full sentence; do not let an English-sounding first word or interjection make you translate the rest into $baseLanguage), or "" if no clear speech was spoken.
2. "detected_language": "$baseCode" if the majority of the utterance was spoken in $baseLanguage, or "$targetCode" if the majority was spoken in $targetLanguage.
3. "translated_text": translate "original_transcript" into the OTHER language (if "$baseCode" was spoken, "translated_text" MUST be written in $targetLanguage ($targetCode); if "$targetCode" was spoken, "translated_text" MUST be written in $baseLanguage ($baseCode)), or "" if "original_transcript" is empty. NEVER output the same language in "translated_text", NEVER hallucinate example sentences on silence, and NEVER complain about missing audio.
Output ONLY valid JSON:
{"original_transcript": "...", "detected_language": "$baseCode", "translated_text": "..."}''';
  }

  /// Builds a dedicated system prompt for the Speech-to-Text (STT) and
  /// language detection step (Step 1 of the separated pipeline).
  static String buildSpeechToTextSystemPrompt({
    required String baseLanguage,
    required String targetLanguage,
    String? contextPromptBlock,
  }) {
    final baseCode = LanguageDetector.normalizeLanguageCode(baseLanguage);
    final targetCode = LanguageDetector.normalizeLanguageCode(targetLanguage);
    final trimmedContext = contextPromptBlock?.trim() ?? '';
    final contextSuffix = trimmedContext.isEmpty ? '' : '\n$trimmedContext';
    return '''
You are an accurate speech-to-text transcriber and language segmenter for conversations between "$baseLanguage" ($baseCode) and "$targetLanguage" ($targetCode).
Listen to the entire provided audio clip, transcribe the exact words spoken in their original language, and segment the speech by language whenever a speaker switches between "$baseCode" and "$targetCode".
Rules (CRITICAL):
- Do NOT translate the speech. Every segment's "text" MUST be written in the exact language spoken in the audio.
- If the audio contains rapid back-and-forth turns or switches between $baseLanguage ($baseCode) and $targetLanguage ($targetCode), split the transcript chronologically into "segments": [{"lang": "$baseCode", "text": "..."}, {"lang": "$targetCode", "text": "..."}].
- Absorb lone 1–2 word interjections, discourse markers, or shared loanwords (e.g., "Okay", "OK", "No", "Oh", "Ah", "Wait", "Um", "Bueno", "Hotel") into the adjacent clause's language unless they form a standalone utterance.
- If the audio contains only silence, a pause, breathing, or background noise with no clear human speech, return empty segments: {"segments": [], "original_transcript": "", "detected_language": "$baseCode"}.
- NEVER invent, guess, or hallucinate example phrases when nothing was said, and NEVER output meta-commentary about missing or silent audio files.
- Return ONLY a valid JSON object: {"segments": [{"lang": "$baseCode", "text": "..."}], "original_transcript": "...", "detected_language": "$baseCode"}.$contextSuffix''';
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
1. "segments": ordered list of {"lang": "$baseCode" or "$targetCode", "text": "..."} spans. Split into separate segments whenever a clause switches between $baseLanguage ($baseCode) and $targetLanguage ($targetCode), but absorb lone 1-2 word interjections or loanwords ("Okay", "No", "Ah", "Hotel") into the adjacent clause's language. Return [] if no clear speech was spoken.
2. "original_transcript": full verbatim transcript (or "" if no speech).
3. "detected_language": "$baseCode" or "$targetCode" for the primary segment.
Output ONLY valid JSON:
{"segments": [{"lang": "$baseCode", "text": "..."}], "original_transcript": "...", "detected_language": "$baseCode"}''';
  }

  /// Builds the system prompt for deciding whether two same-language speech
  /// chunks separated by an opposite-language interjection belong to the same
  /// sentence or represent a forked conversation, and translating the result.
  static String buildContinuationResolutionSystemPrompt({
    required String sourceLanguage,
    required String targetLanguage,
    String? contextPromptBlock,
  }) {
    final trimmedContext = contextPromptBlock?.trim() ?? '';
    final contextSuffix = trimmedContext.isEmpty ? '' : '\n$trimmedContext';
    return '''
You are a dialogue continuity analyzer and translator between $sourceLanguage and $targetLanguage.
You will be shown a brief dialogue script where Speaker A ($sourceLanguage) spoke Part 1, Speaker B ($targetLanguage) said an intervening line, and Speaker A ($sourceLanguage) immediately spoke Part 2 within a few seconds.
Decide whether Part 1 and Part 2 from Speaker A were actually a single continuous sentence/thought (interrupted by Speaker B's brief interjection), OR whether Speaker B's line forked the conversation so Part 2 is a new, separate message responding to Speaker B.
Return ONLY valid JSON: {"same_sentence": true, "translated_text": "..."}.$contextSuffix''';
  }

  /// Builds the user prompt for the "movie script" continuation and translation
  /// decision.
  static String buildContinuationResolutionPrompt({
    required String part1Transcript,
    required String part2Transcript,
    required String combinedTranscript,
    required List<Message> interveningTurns,
    required String sourceLanguage,
    required String targetLanguage,
    required double exchangeRate,
    required String baseCurrency,
    required String targetCurrency,
    String? contextPromptBlock,
  }) {
    final formattedRate = exchangeRate.toStringAsFixed(4);
    final trimmedContext = contextPromptBlock?.trim() ?? '';
    final contextSection = trimmedContext.isEmpty ? '' : '\n$trimmedContext\n';
    final scriptBuffer = StringBuffer()
      ..writeln('[Speaker A - $sourceLanguage (Part 1)]: "$part1Transcript"');
    for (final turn in interveningTurns) {
      final orig = turn.originalText.trim().isNotEmpty
          ? turn.originalText.trim()
          : turn.translatedText.trim();
      scriptBuffer.writeln('[Speaker B - $targetLanguage (Intervening)]: "$orig"');
    }
    scriptBuffer.writeln(
      '[Speaker A - $sourceLanguage (Part 2)]: "$part2Transcript"',
    );

    return '''
Analyze this live conversation script between Speaker A ($sourceLanguage) and Speaker B ($targetLanguage):
${scriptBuffer.toString().trimRight()}

Instructions:
1. Determine "same_sentence":
   - Set "same_sentence": true if Part 1 ("$part1Transcript") and Part 2 ("$part2Transcript") form a single continuous sentence or thought by Speaker A (e.g., Speaker B only interjected a greeting like "¡Hola!" or brief acknowledgment while Speaker A was finishing their sentence "$combinedTranscript").
   - Set "same_sentence": false if Speaker B's intervening turn answered or forked the conversation and Part 2 ("$part2Transcript") is a new, separate reply from Speaker A.
2. Determine "translated_text" (MUST be written strictly in $targetLanguage):
   - If "same_sentence" is true: translate the full combined sentence "$combinedTranscript" into $targetLanguage.
   - If "same_sentence" is false: translate ONLY Part 2 ("$part2Transcript") into $targetLanguage.
3. Formatting: convert any times as '24-hour (12-hour)' (e.g., '18:00 (6PM)') and any prices using 1 $targetCurrency = $formattedRate $baseCurrency as 'original price (converted price)'.
$contextSection
Output ONLY valid JSON:
{"same_sentence": true, "translated_text": "..."}''';
  }

  /// Builds a text-only system instruction for the automatic self-correction
  /// fallback pass so the text-only session is never told to "Listen to the
  /// provided audio".
  static String buildTextFallbackSystemPrompt({
    required String sourceLanguage,
    required String targetLanguage,
    String? contextPromptBlock,
  }) {
    final trimmedContext = contextPromptBlock?.trim() ?? '';
    final contextSuffix = trimmedContext.isEmpty ? '' : '\n$trimmedContext';
    return '''
You are a text translator between $sourceLanguage and $targetLanguage.
Translate the provided $sourceLanguage text directly into $targetLanguage.
Never ask for an audio file, never repeat the source language, and output nothing if the input is empty or indicates no speech.$contextSuffix''';
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
    String? contextPromptBlock,
  }) {
    final formattedRate = exchangeRate.toStringAsFixed(4);
    final trimmedContext = contextPromptBlock?.trim() ?? '';
    final contextSection = trimmedContext.isEmpty ? '' : '\n$trimmedContext\n';
    return '''
Translate the following $sourceLanguage text into $targetLanguage.
CRITICAL RULES:
1. Your output MUST be written in $targetLanguage. NEVER repeat or echo the $sourceLanguage text.
2. Format any times as '24-hour (12-hour)' (e.g., '18:00 (6PM)') and any prices using 1 $targetCurrency = $formattedRate $baseCurrency as 'original price (converted price)'.
3. Output ONLY the translated $targetLanguage text, with no JSON, no markdown, and no explanation.$contextSection
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
