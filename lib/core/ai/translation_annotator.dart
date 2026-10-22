import 'package:translation_app/core/data/models/app_settings.dart';

/// Deterministic post-processor that scans original and translated message text
/// for price and time expressions and appends conversions when the LLM has not
/// already included them.
class TranslationAnnotator {
  const TranslationAnnotator._();

  static final RegExp _existingPriceAnnotationRegex = RegExp(
    r'\([^)]*(?:'
    r'(?:CA\$|A\$|MX\$|R\$|US\$|\$|€|£|¥|₩|CHF|USD|EUR|GBP|JPY|CAD|AUD|MXN|BRL|KRW|CNY|RMB)\s*\d'
    r'|'
    r'\d[^)]*(?:CA\$|A\$|MX\$|R\$|US\$|\$|€|£|¥|₩|CHF|USD|EUR|GBP|JPY|CAD|AUD|MXN|BRL|KRW|CNY|RMB|'
    r'dollars?|euros?|pounds?|yen|won|yuan|francs?|pesos?|reais|real|d[oó]lares?|d[oó]lar|libras?|'
    r'달러|불|원|유로|엔|위안|파운드|프랑|페소|헤알|ドル|円|ユーロ|ポンド|ウォン|元|块|美元|欧元|日元|韩元)'
    r')[^)]*\)',
    caseSensitive: false,
  );

  static final RegExp _existingTimeAnnotationRegex = RegExp(
    r'\(\s*(?:'
    r'(?:[01]?\d|2[0-3]):[0-5]\d(?:\s*(?:AM|PM|am|pm|a\.m\.|p\.m\.))?'
    r'|'
    r'(?:1[0-2]|0?[1-9])(?::[0-5]\d)?\s*(?:AM|PM|am|pm|a\.m\.|p\.m\.)'
    r')\s*\)',
  );

  static final RegExp _prefixCurrencyPriceRegex = RegExp(
    r'(?<![A-Za-z0-9])'
    r'(CA\$|A\$|MX\$|R\$|US\$|CHF|USD|EUR|GBP|JPY|CAD|AUD|MXN|BRL|KRW|CNY|RMB|\$|€|£|¥|₩)'
    r'\s*'
    r'(\d{1,3}(?:,\d{3})+|\d+)(?:\.(\d{1,2}))?'
    r'(\s*(?:십만|만|천|백|万|千))?'
    r'(?![0-9])',
    caseSensitive: false,
  );

  static final RegExp _suffixCurrencyPriceRegex = RegExp(
    r'(?<![A-Za-z0-9$€£¥₩])'
    r'((?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d{1,2})?(?:\s*(?:십만|만|천|백|万|千)(?:\s*\d+\s*(?:천|백))?)?'
    r'|'
    r'(?:일|이|삼|사|오|육|칠|팔|구|십)?(?:십만|만|천|백)(?:\s*(?:일|이|삼|사|오|육|칠|팔|구)?(?:천|백))?)'
    r'\s*'
    r'(CA\$|A\$|MX\$|R\$|US\$|CHF|USD|EUR|GBP|JPY|CAD|AUD|MXN|BRL|KRW|CNY|RMB|\$|€|£|¥|₩|'
    r'canadian\s+dollars?|australian\s+dollars?|mexican\s+pesos?|us\s+dollars?|'
    r'dollars?|bucks?|euros?|pounds?|yen|yenes|won|yuan|francs?|francos?|pesos?|reais|real|'
    r'd[oó]lares?|d[oó]lar|libras?|'
    r'캐나다\s*달러|호주\s*달러|달러|불|원|유로|엔|위안|파운드|프랑|페소|헤알|'
    r'ドル|円|ユーロ|ポンド|ウォン|元|块|美元|美金|欧元|日元|韩元|韓元|人民元|人民币)'
    r'(?![A-Za-z])',
    caseSensitive: false,
  );

  static final RegExp _twelveHourTimeRegex = RegExp(
    r'(?<![0-9:])'
    r'\b(1[0-2]|0?[1-9])(?::([0-5]\d))?\s*(AM|PM|am|pm|a\.m\.|p\.m\.)'
    r'(?![A-Za-z0-9])',
  );

  static final RegExp _cjkPeriodTimeRegex = RegExp(
    r'(오전|오후|아침|저녁|밤|새벽|午前|午後|上午|下午|晚上|早上)'
    r'\s*'
    r'(1[0-2]|0?[1-9]|한|두|세|네|다섯|여섯|일곱|여덟|아홉|열|열한|열두)'
    r'\s*(?:시|時|点|點)'
    r'(?:\s*(반|[0-5]?\d\s*(?:분|分)))?',
  );

  static final RegExp _twentyFourHourTimeRegex = RegExp(
    r'(?<![0-9:])'
    r'\b([01]?\d|2[0-3]):([0-5]\d)\b'
    r'(?!\s*(?:AM|PM|am|pm|a\.m\.|p\.m\.))',
  );

  /// Returns `true` if [text] already contains a parenthetical price conversion.
  static bool hasExistingPriceAnnotation(String text) {
    return _existingPriceAnnotationRegex.hasMatch(text);
  }

  /// Returns `true` if [text] already contains a parenthetical time conversion.
  static bool hasExistingTimeAnnotation(String text) {
    return _existingTimeAnnotationRegex.hasMatch(text);
  }

  /// Post-processes [translatedText] (consulting [originalText] as a fallback)
  /// to add price and/or time conversion annotations when not already present.
  ///
  /// [exchangeRate] follows the app's standard convention:
  /// `1 [baseCurrency] = [exchangeRate] [targetCurrency]`.
  static String annotate({
    required String originalText,
    required String translatedText,
    required double exchangeRate,
    required String baseCurrency,
    required String targetCurrency,
    bool? isBaseLanguage,
  }) {
    final trimmedTranslated = translatedText.trim();
    if (trimmedTranslated.isEmpty) {
      return translatedText;
    }

    var working = trimmedTranslated;

    // 1. Price post-processing (skip if the model already annotated price)
    if (!hasExistingPriceAnnotation(working)) {
      working = _annotatePrices(
        originalText: originalText,
        translatedText: working,
        exchangeRate: exchangeRate,
        baseCurrency: baseCurrency,
        targetCurrency: targetCurrency,
        isBaseLanguage: isBaseLanguage,
      );
    }

    // 2. Time post-processing (skip if the model already annotated time)
    if (!hasExistingTimeAnnotation(working)) {
      working = _annotateTimes(
        originalText: originalText,
        translatedText: working,
      );
    }

    return working;
  }

  static String _annotatePrices({
    required String originalText,
    required String translatedText,
    required double exchangeRate,
    required String baseCurrency,
    required String targetCurrency,
    required bool? isBaseLanguage,
  }) {
    if (exchangeRate <= 0) {
      return translatedText;
    }
    final normBase = baseCurrency.trim().toUpperCase();
    final normTarget = targetCurrency.trim().toUpperCase();
    if (normBase == normTarget) {
      return translatedText;
    }

    // Try finding price matches in translatedText first.
    final translatedMatches = _findPriceMatches(translatedText);
    if (translatedMatches.isNotEmpty) {
      final buffer = StringBuffer();
      var cursor = 0;
      for (final match in translatedMatches) {
        buffer.write(translatedText.substring(cursor, match.end));
        final conversion = _computeConversionLabel(
          amount: match.amount,
          rawCurrencyToken: match.currencyToken,
          exchangeRate: exchangeRate,
          baseCurrency: normBase,
          targetCurrency: normTarget,
          isBaseLanguage: isBaseLanguage,
        );
        if (conversion != null) {
          buffer.write(' ($conversion)');
        }
        cursor = match.end;
      }
      buffer.write(translatedText.substring(cursor));
      return buffer.toString();
    }

    // Fallback: if the model omitted the price or currency unit in translatedText,
    // check originalText and append the conversion at the end.
    final originalMatches = _findPriceMatches(originalText);
    if (originalMatches.isNotEmpty) {
      final conversions = <String>[];
      for (final match in originalMatches) {
        final conversion = _computeConversionLabel(
          amount: match.amount,
          rawCurrencyToken: match.currencyToken,
          exchangeRate: exchangeRate,
          baseCurrency: normBase,
          targetCurrency: normTarget,
          isBaseLanguage: isBaseLanguage,
        );
        if (conversion != null && !conversions.contains(conversion)) {
          conversions.add(conversion);
        }
      }
      if (conversions.isNotEmpty) {
        return '$translatedText (${conversions.join(', ')})';
      }
    }

    return translatedText;
  }

  static List<_DetectedPriceMatch> _findPriceMatches(String text) {
    if (text.trim().isEmpty) return const <_DetectedPriceMatch>[];

    final matches = <_DetectedPriceMatch>[];

    for (final m in _prefixCurrencyPriceRegex.allMatches(text)) {
      final currencyToken = m.group(1) ?? '';
      final intPart = (m.group(2) ?? '').replaceAll(',', '');
      final decPart = m.group(3);
      final multiplierToken = m.group(4);
      final baseVal = double.tryParse(
        decPart != null ? '$intPart.$decPart' : intPart,
      );
      if (baseVal != null && baseVal > 0) {
        final mult = _parseMultiplier(multiplierToken);
        matches.add(
          _DetectedPriceMatch(
            start: m.start,
            end: m.end,
            amount: baseVal * mult,
            currencyToken: currencyToken,
          ),
        );
      }
    }

    for (final m in _suffixCurrencyPriceRegex.allMatches(text)) {
      final overlapsExisting = matches.any(
        (existing) => m.start < existing.end && m.end > existing.start,
      );
      if (overlapsExisting) continue;

      final numberExpr = m.group(1) ?? '';
      final currencyToken = m.group(2) ?? '';
      final parsedAmount = _parseNumberExpression(numberExpr);
      if (parsedAmount != null && parsedAmount > 0) {
        matches.add(
          _DetectedPriceMatch(
            start: m.start,
            end: m.end,
            amount: parsedAmount,
            currencyToken: currencyToken,
          ),
        );
      }
    }

    matches.sort((a, b) => a.start.compareTo(b.start));
    return matches;
  }

  static double _parseMultiplier(String? token) {
    if (token == null) return 1.0;
    final trimmed = token.trim();
    if (trimmed == '십만') return 100000.0;
    if (trimmed == '만' || trimmed == '万') return 10000.0;
    if (trimmed == '천' || trimmed == '千') return 1000.0;
    if (trimmed == '백') return 100.0;
    return 1.0;
  }

  static double? _parseNumberExpression(String expr) {
    final cleaned = expr.trim().replaceAll(',', '');
    if (cleaned.isEmpty) return null;

    final direct = double.tryParse(cleaned);
    if (direct != null) return direct;

    // Handle compound Korean/CJK expressions like "1만 5천", "2만", "만", "오천", "삼만"
    const koreanDigits = <String, double>{
      '일': 1,
      '이': 2,
      '삼': 3,
      '사': 4,
      '오': 5,
      '육': 6,
      '칠': 7,
      '팔': 8,
      '구': 9,
      '십': 10,
    };

    var total = 0.0;
    var matchedUnit = false;

    final unitPattern = RegExp(
      r'(\d+(?:\.\d+)?|일|이|삼|사|오|육|칠|팔|구|십)?\s*(십만|만|천|백|万|千)',
    );
    for (final match in unitPattern.allMatches(cleaned)) {
      matchedUnit = true;
      final prefix = match.group(1)?.trim();
      final unit = match.group(2)?.trim();
      double digit = 1.0;
      if (prefix != null && prefix.isNotEmpty) {
        digit = double.tryParse(prefix) ?? koreanDigits[prefix] ?? 1.0;
      }
      final mult = _parseMultiplier(unit);
      total += digit * mult;
    }

    if (matchedUnit && total > 0) {
      return total;
    }

    return null;
  }

  static String? _computeConversionLabel({
    required double amount,
    required String rawCurrencyToken,
    required double exchangeRate,
    required String baseCurrency,
    required String targetCurrency,
    required bool? isBaseLanguage,
  }) {
    final detectedCode = _resolveCurrencyCode(
      rawCurrencyToken,
      baseCurrency: baseCurrency,
      targetCurrency: targetCurrency,
      isBaseLanguage: isBaseLanguage,
    );

    final String destinationCurrency;
    final double convertedAmount;

    if (detectedCode == baseCurrency) {
      destinationCurrency = targetCurrency;
      convertedAmount = amount * exchangeRate;
    } else if (detectedCode == targetCurrency) {
      destinationCurrency = baseCurrency;
      convertedAmount = amount / exchangeRate;
    } else if (isBaseLanguage == true) {
      destinationCurrency = targetCurrency;
      convertedAmount = amount * exchangeRate;
    } else {
      destinationCurrency = baseCurrency;
      convertedAmount = amount / exchangeRate;
    }

    return formatCurrencyAmount(convertedAmount, destinationCurrency);
  }

  static String _resolveCurrencyCode(
    String rawToken, {
    required String baseCurrency,
    required String targetCurrency,
    required bool? isBaseLanguage,
  }) {
    final token = rawToken.trim().toLowerCase();

    if (token == 'usd' ||
        token == r'us$' ||
        token.contains('us dollar') ||
        token == '달러' ||
        token == '불' ||
        token == 'ドル' ||
        token == '美元' ||
        token == '美金') {
      return 'USD';
    }
    if (token == 'cad' ||
        token == r'ca$' ||
        token.contains('canadian dollar') ||
        token.contains('캐나다')) {
      return 'CAD';
    }
    if (token == 'aud' ||
        token == r'a$' ||
        token.contains('australian dollar') ||
        token.contains('호주')) {
      return 'AUD';
    }
    if (token == 'mxn' ||
        token == r'mx$' ||
        token.startsWith('peso') ||
        token == '페소' ||
        token == 'ペソ' ||
        token == '比索') {
      return 'MXN';
    }
    if (token == 'brl' ||
        token == r'r$' ||
        token == 'real' ||
        token == 'reais' ||
        token == '헤알' ||
        token == 'レアル' ||
        token == '雷亚尔') {
      return 'BRL';
    }
    if (token == 'eur' ||
        token == '€' ||
        token.startsWith('euro') ||
        token == '유로' ||
        token == 'ユーロ' ||
        token == '欧元') {
      return 'EUR';
    }
    if (token == 'gbp' ||
        token == '£' ||
        token.startsWith('pound') ||
        token.startsWith('libra') ||
        token == '파운드' ||
        token == 'ポンド' ||
        token == '英镑') {
      return 'GBP';
    }
    if (token == 'krw' ||
        token == '₩' ||
        token == 'won' ||
        token == '원' ||
        token == 'ウォン' ||
        token == '韩元' ||
        token == '韓元') {
      return 'KRW';
    }
    if (token == 'jpy' ||
        token == 'yen' ||
        token == 'yenes' ||
        token == '엔' ||
        token == '円' ||
        token == '日元') {
      return 'JPY';
    }
    if (token == 'cny' ||
        token == 'rmb' ||
        token == 'yuan' ||
        token == '위안' ||
        token == '元' ||
        token == '块' ||
        token == '人民元' ||
        token == '人民币') {
      return 'CNY';
    }
    if (token == 'chf' ||
        token.startsWith('franc') ||
        token == '프랑' ||
        token == 'フラン' ||
        token == '法郎') {
      return 'CHF';
    }

    // Ambiguous '$' or 'dollar'/'dólar'
    if (token == r'$' ||
        token.startsWith('dollar') ||
        token.startsWith('buck') ||
        token.startsWith('dólar') ||
        token.startsWith('dolar')) {
      const dollarCurrencies = <String>{'USD', 'CAD', 'AUD', 'MXN'};
      final baseIsDollar = dollarCurrencies.contains(baseCurrency);
      final targetIsDollar = dollarCurrencies.contains(targetCurrency);
      if (baseIsDollar && !targetIsDollar) return baseCurrency;
      if (targetIsDollar && !baseIsDollar) return targetCurrency;
      if (baseIsDollar && targetIsDollar) {
        return (isBaseLanguage ?? true) ? baseCurrency : targetCurrency;
      }
      return 'USD';
    }

    // Ambiguous '¥'
    if (token == '¥') {
      const yenYuanCurrencies = <String>{'JPY', 'CNY'};
      final baseIsYen = yenYuanCurrencies.contains(baseCurrency);
      final targetIsYen = yenYuanCurrencies.contains(targetCurrency);
      if (baseIsYen && !targetIsYen) return baseCurrency;
      if (targetIsYen && !baseIsYen) return targetCurrency;
      if (baseIsYen && targetIsYen) {
        return (isBaseLanguage ?? true) ? baseCurrency : targetCurrency;
      }
      return 'JPY';
    }

    return (isBaseLanguage ?? true) ? baseCurrency : targetCurrency;
  }

  /// Formats a numeric [amount] for [currencyCode] (e.g. `$10.87 USD`, `₩13,800 KRW`).
  static String formatCurrencyAmount(double amount, String currencyCode) {
    final code = currencyCode.trim().toUpperCase();
    final symbol = _symbolForCurrency(code);
    const zeroDecimalCurrencies = <String>{'JPY', 'KRW'};

    if (zeroDecimalCurrencies.contains(code)) {
      final rounded = amount.round();
      final formattedInt = _formatWithCommas(rounded.toString());
      return '$symbol$formattedInt $code';
    }

    final fixed = amount.toStringAsFixed(2);
    final parts = fixed.split('.');
    final formattedInt = _formatWithCommas(parts[0]);
    final formattedNumber = '$formattedInt.${parts[1]}';
    if (symbol == code) {
      return '$formattedNumber $code';
    }
    return '$symbol$formattedNumber $code';
  }

  static String _symbolForCurrency(String code) {
    for (final c in AppSettings.supportedCurrencies) {
      if (c.code.toUpperCase() == code) {
        return c.symbol;
      }
    }
    return code;
  }

  static String _formatWithCommas(String digits) {
    final isNegative = digits.startsWith('-');
    final raw = isNegative ? digits.substring(1) : digits;
    final buffer = StringBuffer();
    for (var i = 0; i < raw.length; i++) {
      if (i > 0 && (raw.length - i) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(raw[i]);
    }
    return isNegative ? '-$buffer' : buffer.toString();
  }

  static String _annotateTimes({
    required String originalText,
    required String translatedText,
  }) {
    // 1. Check 12-hour times in translatedText (e.g. "6 PM", "6:30 pm")
    final twelveMatches = _twelveHourTimeRegex
        .allMatches(translatedText)
        .toList();
    if (twelveMatches.isNotEmpty) {
      final buffer = StringBuffer();
      var cursor = 0;
      for (final m in twelveMatches) {
        buffer.write(translatedText.substring(cursor, m.end));
        final hour12 = int.parse(m.group(1)!);
        final minute = int.tryParse(m.group(2) ?? '0') ?? 0;
        final period = m.group(3)!.toLowerCase();
        final isPm = period.startsWith('p');
        final hour24 = _to24Hour(hour12, isPm: isPm);
        final formatted24 =
            '${hour24.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
        buffer.write(' ($formatted24)');
        cursor = m.end;
      }
      buffer.write(translatedText.substring(cursor));
      return buffer.toString();
    }

    // 2. Check Korean/Japanese/Chinese period times in translatedText (e.g. "오후 6시")
    final cjkMatches = _cjkPeriodTimeRegex.allMatches(translatedText).toList();
    if (cjkMatches.isNotEmpty) {
      final buffer = StringBuffer();
      var cursor = 0;
      for (final m in cjkMatches) {
        buffer.write(translatedText.substring(cursor, m.end));
        final parsed = _parseCjkTimeMatch(m);
        if (parsed != null) {
          final (hour24, minute) = parsed;
          final formatted24 =
              '${hour24.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
          final formatted12 = _format12Hour(hour24, minute);
          buffer.write(' ($formatted24 / $formatted12)');
        }
        cursor = m.end;
      }
      buffer.write(translatedText.substring(cursor));
      return buffer.toString();
    }

    // 3. Check 24-hour times in translatedText (e.g. "18:00", "14:30")
    final twentyFourMatches = _twentyFourHourTimeRegex
        .allMatches(translatedText)
        .toList();
    if (twentyFourMatches.isNotEmpty) {
      final buffer = StringBuffer();
      var cursor = 0;
      for (final m in twentyFourMatches) {
        buffer.write(translatedText.substring(cursor, m.end));
        final hour24 = int.parse(m.group(1)!);
        final minute = int.parse(m.group(2)!);
        final formatted12 = _format12Hour(hour24, minute);
        buffer.write(' ($formatted12)');
        cursor = m.end;
      }
      buffer.write(translatedText.substring(cursor));
      return buffer.toString();
    }

    // 4. Fallback: check originalText for times if translatedText didn't have an explicit format
    final origTwelve = _twelveHourTimeRegex.firstMatch(originalText);
    if (origTwelve != null) {
      final hour12 = int.parse(origTwelve.group(1)!);
      final minute = int.tryParse(origTwelve.group(2) ?? '0') ?? 0;
      final isPm = origTwelve.group(3)!.toLowerCase().startsWith('p');
      final hour24 = _to24Hour(hour12, isPm: isPm);
      final formatted24 =
          '${hour24.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
      final formatted12 = _format12Hour(hour24, minute);
      return '$translatedText ($formatted24 / $formatted12)';
    }

    final origCjk = _cjkPeriodTimeRegex.firstMatch(originalText);
    if (origCjk != null) {
      final parsed = _parseCjkTimeMatch(origCjk);
      if (parsed != null) {
        final (hour24, minute) = parsed;
        final formatted24 =
            '${hour24.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
        final formatted12 = _format12Hour(hour24, minute);
        return '$translatedText ($formatted24 / $formatted12)';
      }
    }

    final orig24 = _twentyFourHourTimeRegex.firstMatch(originalText);
    if (orig24 != null) {
      final hour24 = int.parse(orig24.group(1)!);
      final minute = int.parse(orig24.group(2)!);
      final formatted24 =
          '${hour24.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
      final formatted12 = _format12Hour(hour24, minute);
      return '$translatedText ($formatted24 / $formatted12)';
    }

    return translatedText;
  }

  static (int, int)? _parseCjkTimeMatch(RegExpMatch match) {
    final period = match.group(1) ?? '';
    final hourToken = match.group(2) ?? '';
    final minuteToken = match.group(3);

    const nativeKoreanHours = <String, int>{
      '한': 1,
      '두': 2,
      '세': 3,
      '네': 4,
      '다섯': 5,
      '여섯': 6,
      '일곱': 7,
      '여덟': 8,
      '아홉': 9,
      '열': 10,
      '열한': 11,
      '열두': 12,
    };

    final hour12 = int.tryParse(hourToken) ?? nativeKoreanHours[hourToken];
    if (hour12 == null) return null;

    var minute = 0;
    if (minuteToken != null) {
      if (minuteToken.contains('반')) {
        minute = 30;
      } else {
        final digits = RegExp(r'\d+').firstMatch(minuteToken)?.group(0);
        if (digits != null) {
          minute = int.tryParse(digits) ?? 0;
        }
      }
    }

    final isPm =
        period == '오후' ||
        period == '저녁' ||
        period == '밤' ||
        period == '午後' ||
        period == '下午' ||
        period == '晚上';
    final hour24 = _to24Hour(hour12, isPm: isPm);
    return (hour24, minute);
  }

  static int _to24Hour(int hour12, {required bool isPm}) {
    final normalized = hour12 % 12;
    return isPm ? normalized + 12 : normalized;
  }

  static String _format12Hour(int hour24, int minute) {
    final isPm = hour24 >= 12;
    final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
    final period = isPm ? 'PM' : 'AM';
    final minStr = minute.toString().padLeft(2, '0');
    return '$hour12:$minStr $period';
  }
}

class _DetectedPriceMatch {
  const _DetectedPriceMatch({
    required this.start,
    required this.end,
    required this.amount,
    required this.currencyToken,
  });

  final int start;
  final int end;
  final double amount;
  final String currencyToken;
}
