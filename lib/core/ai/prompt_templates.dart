/// Prompt templates and JSON schema instructions for Gemma 4 multimodal audio
/// translation.
class PromptTemplates {
  const PromptTemplates._();

  /// Builds the system prompt for translating spoken audio between
  /// [baseLanguage] and [targetLanguage] with automatic time and price
  /// formatting.
  static String buildSystemPrompt({
    required String baseLanguage,
    required String targetLanguage,
    required double exchangeRate,
    required String baseCurrency,
    required String targetCurrency,
  }) {
    final formattedRate = exchangeRate.toStringAsFixed(4);
    return '''
You are a real-time translator. The user's base language is "$baseLanguage" and the target is "$targetLanguage".
Listen to the provided audio. Identify which of these two languages is being spoken. Translate the speech into the other language.
Formatting Rules:
1. Convert any spoken times into standard 24-hour and 12-hour format (e.g., '18:00 (6PM)').
2. Convert any spoken prices into $baseCurrency using the exchange rate: 1 $targetCurrency = $formattedRate $baseCurrency. Output format: 'original price (converted price)'.
3. Return ONLY a valid JSON object matching this schema: {"detected_language": "en", "translated_text": "...", "original_transcript": "..."}.''';
  }
}
