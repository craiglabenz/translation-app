import 'package:flutter_test/flutter_test.dart';
import 'package:translation_app/core/ai/translation_annotator.dart';

void main() {
  group('TranslationAnnotator — Price Post-Processing', () {
    test('annotates unannotated USD price in translatedText to EUR', () {
      final annotated = TranslationAnnotator.annotate(
        originalText: r'That costs $10.',
        translatedText: r'Eso cuesta $10.',
        exchangeRate: 0.92,
        baseCurrency: 'USD',
        targetCurrency: 'EUR',
        isBaseLanguage: true,
      );

      expect(annotated, r'Eso cuesta $10 (€9.20 EUR).');
    });

    test('annotates unannotated EUR price in translatedText to USD', () {
      final annotated = TranslationAnnotator.annotate(
        originalText: 'Son 25 euros.',
        translatedText: 'It is €25.',
        exchangeRate: 0.92, // 1 USD = 0.92 EUR -> 25 EUR = 27.17 USD
        baseCurrency: 'USD',
        targetCurrency: 'EUR',
        isBaseLanguage: false,
      );

      expect(annotated, r'It is €25 ($27.17 USD).');
    });

    test('annotates Korean Won (원 / KRW / 만원 / 천원) to USD accurately', () {
      // 1 USD = 1380 KRW -> 15,000 KRW = $10.87 USD
      final annotatedNumeric = TranslationAnnotator.annotate(
        originalText: '이거 15,000원입니다.',
        translatedText: 'This is 15,000 won.',
        exchangeRate: 1380.0,
        baseCurrency: 'USD',
        targetCurrency: 'KRW',
        isBaseLanguage: false,
      );
      expect(annotatedNumeric, r'This is 15,000 won ($10.87 USD).');

      // Korean multiplier in originalText ("1만 5천원") when translatedText omitted the currency
      final annotatedFromKoreanUnits = TranslationAnnotator.annotate(
        originalText: '1만 5천원이에요',
        translatedText: 'It costs fifteen thousand.',
        exchangeRate: 1380.0,
        baseCurrency: 'USD',
        targetCurrency: 'KRW',
        isBaseLanguage: false,
      );
      expect(
        annotatedFromKoreanUnits,
        r'It costs fifteen thousand. ($10.87 USD)',
      );
    });

    test('annotates USD to Korean Won with integer formatting and commas', () {
      final annotated = TranslationAnnotator.annotate(
        originalText: 'The ticket is 20 dollars.',
        translatedText: '티켓은 20달러입니다.',
        exchangeRate: 1380.0,
        baseCurrency: 'USD',
        targetCurrency: 'KRW',
        isBaseLanguage: true,
      );

      expect(annotated, '티켓은 20달러 (₩27,600 KRW)입니다.');
    });

    test('falls back to originalText when price was dropped in translatedText', () {
      final annotated = TranslationAnnotator.annotate(
        originalText: 'It is £50 for two.',
        translatedText: 'Son cincuenta para dos.',
        exchangeRate: 1.17, // 1 GBP = 1.17 EUR
        baseCurrency: 'GBP',
        targetCurrency: 'EUR',
        isBaseLanguage: true,
      );

      expect(annotated, 'Son cincuenta para dos. (€58.50 EUR)');
    });

    test('does NOT add redundant price annotation when LLM already included it', () {
      const alreadyAnnotated1 = r'Eso cuesta $10 (€9.20 EUR).';
      expect(
        TranslationAnnotator.hasExistingPriceAnnotation(alreadyAnnotated1),
        isTrue,
      );
      expect(
        TranslationAnnotator.annotate(
          originalText: r'That costs $10.',
          translatedText: alreadyAnnotated1,
          exchangeRate: 0.92,
          baseCurrency: 'USD',
          targetCurrency: 'EUR',
          isBaseLanguage: true,
        ),
        alreadyAnnotated1,
      );

      const alreadyAnnotated2 = r'이것은 15,000원 ($10.87)입니다.';
      expect(
        TranslationAnnotator.hasExistingPriceAnnotation(alreadyAnnotated2),
        isTrue,
      );
      expect(
        TranslationAnnotator.annotate(
          originalText: '이것은 15,000원입니다.',
          translatedText: alreadyAnnotated2,
          exchangeRate: 1380.0,
          baseCurrency: 'USD',
          targetCurrency: 'KRW',
          isBaseLanguage: false,
        ),
        alreadyAnnotated2,
      );
    });

    test('annotate() is idempotent when called multiple times', () {
      final firstPass = TranslationAnnotator.annotate(
        originalText: r'It costs $15 and starts at 6 PM.',
        translatedText: r'Cuesta $15 y empieza a las 6 PM.',
        exchangeRate: 0.92,
        baseCurrency: 'USD',
        targetCurrency: 'EUR',
        isBaseLanguage: true,
      );
      final secondPass = TranslationAnnotator.annotate(
        originalText: r'It costs $15 and starts at 6 PM.',
        translatedText: firstPass,
        exchangeRate: 0.92,
        baseCurrency: 'USD',
        targetCurrency: 'EUR',
        isBaseLanguage: true,
      );

      expect(secondPass, firstPass);
    });
  });

  group('TranslationAnnotator — Time Post-Processing', () {
    test('annotates 12-hour AM/PM time with 24-hour equivalent', () {
      final annotated = TranslationAnnotator.annotate(
        originalText: 'Let us meet at 6:30 PM.',
        translatedText: 'Nos vemos a las 6:30 PM.',
        exchangeRate: 0.92,
        baseCurrency: 'USD',
        targetCurrency: 'EUR',
        isBaseLanguage: true,
      );

      expect(annotated, 'Nos vemos a las 6:30 PM (18:30).');
    });

    test('annotates 24-hour time with 12-hour AM/PM equivalent', () {
      final annotated = TranslationAnnotator.annotate(
        originalText: 'El tren sale a las 14:45.',
        translatedText: 'The train leaves at 14:45.',
        exchangeRate: 0.92,
        baseCurrency: 'USD',
        targetCurrency: 'EUR',
        isBaseLanguage: false,
      );

      expect(annotated, 'The train leaves at 14:45 (2:45 PM).');
    });

    test('annotates Korean period time (오후 6시 반) with 24-hour and 12-hour format', () {
      final annotated = TranslationAnnotator.annotate(
        originalText: 'Take the bus at 6:30 PM.',
        translatedText: '오후 6시 반에 버스를 타세요.',
        exchangeRate: 1380.0,
        baseCurrency: 'USD',
        targetCurrency: 'KRW',
        isBaseLanguage: true,
      );

      expect(annotated, '오후 6시 반 (18:30 / 6:30 PM)에 버스를 타세요.');
    });

    test('does NOT add redundant time annotation when LLM already included it', () {
      const alreadyAnnotated1 = 'Nos vemos a las 18:00 (6PM).';
      expect(
        TranslationAnnotator.hasExistingTimeAnnotation(alreadyAnnotated1),
        isTrue,
      );
      expect(
        TranslationAnnotator.annotate(
          originalText: 'See you at 6 PM.',
          translatedText: alreadyAnnotated1,
          exchangeRate: 0.92,
          baseCurrency: 'USD',
          targetCurrency: 'EUR',
          isBaseLanguage: true,
        ),
        alreadyAnnotated1,
      );

      const alreadyAnnotated2 = 'The show starts at 7:00 PM (19:00).';
      expect(
        TranslationAnnotator.hasExistingTimeAnnotation(alreadyAnnotated2),
        isTrue,
      );
      expect(
        TranslationAnnotator.annotate(
          originalText: '공연은 오후 7시에 시작합니다.',
          translatedText: alreadyAnnotated2,
          exchangeRate: 1380.0,
          baseCurrency: 'USD',
          targetCurrency: 'KRW',
          isBaseLanguage: false,
        ),
        alreadyAnnotated2,
      );
    });
  });
}
