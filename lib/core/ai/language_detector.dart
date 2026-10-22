import 'package:translation_app/core/ai/translation_engine.dart';
import 'package:translation_app/core/data/models/app_settings.dart';

/// Deterministic analysis of a [TranslationResult]'s source/target direction
/// and whether the LLM output requires a text-to-text translation fallback.
class TranslationDirectionAnalysis {
  const TranslationDirectionAnalysis({
    required this.resolvedSourceCode,
    required this.targetOutputCode,
    required this.isBaseLanguage,
    required this.needsFallbackTranslation,
    required this.sourceTextForFallback,
    this.detectedOriginalCode,
    this.detectedTranslatedCode,
  });

  /// Canonical 2-letter code of the spoken source language (`baseCode` or `targetCode`).
  final String resolvedSourceCode;

  /// Canonical 2-letter code that `translatedText` must be written in.
  final String targetOutputCode;

  /// True when the host spoke in `baseLanguage` (message should appear on the
  /// LEFT in `targetLanguage` for the guest to read). False when the guest
  /// spoke in `targetLanguage` (message should appear on the RIGHT in
  /// `baseLanguage` for the host).
  final bool isBaseLanguage;

  /// True when the LLM echoed or transcribed the spoken language into
  /// `translatedText` instead of translating it into [targetOutputCode].
  final bool needsFallbackTranslation;

  /// Source transcript to translate when [needsFallbackTranslation] is true.
  final String sourceTextForFallback;

  /// Script/lexicon-detected language code of `originalText`, if determinable.
  final String? detectedOriginalCode;

  /// Script/lexicon-detected language code of `translatedText`, if determinable.
  final String? detectedTranslatedCode;
}

/// Fast, deterministic script and lexicon language detector for verifying
/// translation direction and preventing untranslated source echoes.
class LanguageDetector {
  const LanguageDetector._();

  static final RegExp _hangulRegex = RegExp(
    r'[\uAC00-\uD7AF\u1100-\u11FF\u3130-\u318F]',
  );
  static final RegExp _kanaRegex = RegExp(r'[\u3040-\u309F\u30A0-\u30FF]');
  static final RegExp _cjkRegex = RegExp(r'[\u4E00-\u9FFF\u3400-\u4DBF]');
  static final RegExp _latinLetterRegex = RegExp(r'[a-zA-Z\u00C0-\u024F]');
  static final RegExp _wordTokenRegex = RegExp(r"[a-z\u00C0-\u024F']+");

  /// Parenthetical currency/time annotations like `(18:00 (6PM))`, `(6PM)`,
  /// `(10.87 USD)`, or `(9.20 EUR)` added by formatting rules.
  static final RegExp _conversionParenRegex = RegExp(
    r'\([^)]*(?:\d|USD|EUR|GBP|JPY|CHF|CAD|AUD|MXN|BRL|KRW|CNY|AM|PM)[^)]*\)',
    caseSensitive: false,
  );

  static final RegExp _currencyAndNumberTokenRegex = RegExp(
    r'\b(?:\d+(?:[.,:]\d+)*|USD|EUR|GBP|JPY|CHF|CAD|AUD|MXN|BRL|KRW|CNY|AM|PM)\b',
    caseSensitive: false,
  );

  static const Set<String> _nonLatinLanguageCodes = <String>{'ko', 'ja', 'zh'};

  static const Map<String, Set<String>> _commonWordsByLanguage =
      <String, Set<String>>{
        'en': <String>{
          'the',
          'is',
          'are',
          'am',
          'was',
          'were',
          'be',
          'been',
          'have',
          'has',
          'had',
          'do',
          'does',
          'did',
          'will',
          'would',
          'can',
          'could',
          'should',
          'may',
          'might',
          'must',
          'i',
          'you',
          'he',
          'she',
          'it',
          'we',
          'they',
          'me',
          'my',
          'your',
          'our',
          'their',
          'this',
          'that',
          'these',
          'those',
          'what',
          'where',
          'when',
          'why',
          'how',
          'who',
          'which',
          'hello',
          'hi',
          'hey',
          'good',
          'morning',
          'afternoon',
          'evening',
          'night',
          'thank',
          'thanks',
          'please',
          'sorry',
          'excuse',
          'yes',
          'not',
          'and',
          'or',
          'but',
          'if',
          'because',
          'with',
          'without',
          'for',
          'from',
          'to',
          'in',
          'on',
          'at',
          'by',
          'about',
          'into',
          'over',
          'after',
          'before',
          'under',
          'there',
          'here',
          'all',
          'any',
          'some',
          'very',
          'much',
          'many',
          'cost',
          'costs',
          'price',
          'dollars',
          'dollar',
          'euros',
          'station',
          'train',
          'subway',
          'bus',
          'airport',
          'hotel',
          'bathroom',
          'restroom',
          'water',
          'food',
          'check',
          'bill',
          'help',
          'speak',
          'understand',
          'english',
          'korean',
          'spanish',
          'french',
          'german',
          'japanese',
          'chinese',
          'italian',
          'portuguese',
          'welcome',
          'friend',
          'meeting',
          'world',
          'today',
          'tomorrow',
          'yesterday',
          'time',
          'street',
          'left',
          'right',
          'straight',
          'far',
          'near',
          'open',
          'closed',
          'buy',
          'pay',
          'card',
          'cash',
        },
        'es': <String>{
          'el',
          'la',
          'los',
          'las',
          'un',
          'una',
          'unos',
          'unas',
          'es',
          'son',
          'está',
          'están',
          'estoy',
          'estás',
          'somos',
          'ser',
          'estar',
          'hola',
          'buenos',
          'buenas',
          'días',
          'tardes',
          'noches',
          'gracias',
          'por',
          'favor',
          'perdón',
          'disculpe',
          'sí',
          'qué',
          'dónde',
          'cuándo',
          'cómo',
          'cuánto',
          'cuánta',
          'cuántos',
          'cuántas',
          'quién',
          'cuál',
          'para',
          'con',
          'sin',
          'de',
          'del',
          'al',
          'en',
          'y',
          'pero',
          'porque',
          'yo',
          'tú',
          'usted',
          'ustedes',
          'nosotros',
          'ellos',
          'ellas',
          'mi',
          'mis',
          'tu',
          'tus',
          'su',
          'sus',
          'este',
          'esta',
          'esto',
          'ese',
          'esa',
          'eso',
          'aquí',
          'allí',
          'ahora',
          'hoy',
          'mañana',
          'ayer',
          'cuesta',
          'cuestan',
          'precio',
          'dólares',
          'dólar',
          'cuenta',
          'baño',
          'estación',
          'tren',
          'metro',
          'autobús',
          'aeropuerto',
          'agua',
          'comida',
          'ayuda',
          'habla',
          'hablo',
          'entiendo',
          'amigo',
          'reunión',
          'mundo',
          'tiempo',
          'hora',
          'horas',
          'calle',
          'izquierda',
          'derecha',
          'todo',
          'todos',
          'muy',
          'más',
          'menos',
          'también',
          'tampoco',
          'debe',
          'aparecer',
          'texto',
          'traducido',
          'solamente',
          'diez',
        },
        'fr': <String>{
          'le',
          'la',
          'les',
          'un',
          'une',
          'des',
          'du',
          'au',
          'aux',
          'est',
          'sont',
          'suis',
          'sommes',
          'êtes',
          'bonjour',
          'bonsoir',
          'salut',
          'merci',
          'plaît',
          'pardon',
          'excusez',
          'oui',
          'non',
          'quoi',
          'où',
          'quand',
          'comment',
          'combien',
          'pourquoi',
          'qui',
          'quel',
          'quelle',
          'pour',
          'avec',
          'sans',
          'dans',
          'sur',
          'sous',
          'chez',
          'et',
          'ou',
          'mais',
          'parce',
          'je',
          'tu',
          'il',
          'elle',
          'nous',
          'vous',
          'ils',
          'elles',
          'mon',
          'ma',
          'mes',
          'ton',
          'ta',
          'tes',
          'son',
          'sa',
          'ses',
          'ce',
          'cet',
          'cette',
          'ces',
          'ici',
          'là',
          'maintenant',
          'demain',
          'hier',
          'coûte',
          'prix',
          'addition',
          'toilettes',
          'gare',
          'métro',
          'eau',
          'aide',
          'parlez',
          'comprends',
          'ami',
          'monde',
          'très',
          'plus',
          'moins',
          'aussi',
        },
        'de': <String>{
          'der',
          'die',
          'das',
          'den',
          'dem',
          'des',
          'ein',
          'eine',
          'einen',
          'einem',
          'einer',
          'ist',
          'sind',
          'bin',
          'bist',
          'seid',
          'war',
          'waren',
          'hallo',
          'guten',
          'morgen',
          'tag',
          'abend',
          'nacht',
          'danke',
          'bitte',
          'entschuldigung',
          'ja',
          'nein',
          'nicht',
          'was',
          'wo',
          'wann',
          'wie',
          'warum',
          'wer',
          'viel',
          'viele',
          'für',
          'mit',
          'ohne',
          'von',
          'zu',
          'zum',
          'zur',
          'im',
          'auf',
          'und',
          'oder',
          'aber',
          'weil',
          'ich',
          'du',
          'er',
          'sie',
          'wir',
          'ihr',
          'mein',
          'meine',
          'dein',
          'deine',
          'sein',
          'seine',
          'dieser',
          'diese',
          'dieses',
          'hier',
          'dort',
          'jetzt',
          'heute',
          'gestern',
          'kostet',
          'preis',
          'rechnung',
          'bahnhof',
          'zug',
          'wasser',
          'hilfe',
          'sprechen',
          'verstehe',
          'freund',
          'welt',
          'sehr',
          'mehr',
          'auch',
        },
        'it': <String>{
          'il',
          'lo',
          'gli',
          'uno',
          'una',
          'è',
          'sono',
          'sei',
          'siamo',
          'siete',
          'ciao',
          'buongiorno',
          'buonasera',
          'buonanotte',
          'grazie',
          'prego',
          'favore',
          'scusa',
          'scusi',
          'sì',
          'non',
          'che',
          'cosa',
          'dove',
          'quando',
          'come',
          'quanto',
          'perché',
          'chi',
          'quale',
          'con',
          'senza',
          'della',
          'nel',
          'nella',
          'su',
          'ma',
          'io',
          'lui',
          'lei',
          'noi',
          'voi',
          'loro',
          'mio',
          'mia',
          'tuo',
          'tua',
          'suo',
          'sua',
          'questo',
          'questa',
          'qui',
          'lì',
          'ora',
          'oggi',
          'domani',
          'ieri',
          'costa',
          'prezzo',
          'conto',
          'bagno',
          'stazione',
          'treno',
          'acqua',
          'aiuto',
          'parla',
          'capisco',
          'amico',
          'mondo',
          'molto',
          'più',
          'anche',
        },
        'pt': <String>{
          'os',
          'as',
          'um',
          'uma',
          'uns',
          'umas',
          'é',
          'são',
          'sou',
          'estou',
          'está',
          'estão',
          'olá',
          'oi',
          'bom',
          'boa',
          'dia',
          'tarde',
          'noite',
          'obrigado',
          'obrigada',
          'favor',
          'desculpe',
          'licença',
          'sim',
          'não',
          'onde',
          'quando',
          'como',
          'quanto',
          'quem',
          'qual',
          'para',
          'com',
          'sem',
          'do',
          'da',
          'dos',
          'das',
          'em',
          'na',
          'mas',
          'porque',
          'eu',
          'você',
          'vocês',
          'nós',
          'eles',
          'elas',
          'meu',
          'minha',
          'seu',
          'sua',
          'este',
          'esta',
          'isso',
          'aqui',
          'ali',
          'agora',
          'hoje',
          'amanhã',
          'ontem',
          'custa',
          'preço',
          'conta',
          'banheiro',
          'estação',
          'trem',
          'metrô',
          'água',
          'ajuda',
          'fala',
          'entendo',
          'amigo',
          'mundo',
          'muito',
          'mais',
          'também',
        },
      };

  /// Normalizes a language code (`"en"`, `"en-US"`), English name (`"Korean"`),
  /// or native name (`"한국어"`) into its canonical lowercase 2-letter ISO code.
  static String normalizeLanguageCode(String languageCodeOrName) {
    final raw = languageCodeOrName.trim().toLowerCase();
    if (raw.isEmpty) return 'en';

    // Exact or regional match against supported languages.
    for (final lang in AppSettings.supportedLanguages) {
      final code = lang.code.toLowerCase();
      final name = lang.name.toLowerCase();
      final nativeName = lang.nativeName.toLowerCase();
      if (raw == code ||
          raw == name ||
          raw == nativeName ||
          raw.startsWith('$code-') ||
          raw.startsWith('${code}_')) {
        return code;
      }
    }

    // Substring match for strings like "Korean (ko)" or "English - US".
    for (final lang in AppSettings.supportedLanguages) {
      final code = lang.code.toLowerCase();
      final name = lang.name.toLowerCase();
      final nativeName = lang.nativeName.toLowerCase();
      if (raw.contains(name) || raw.contains(nativeName)) {
        return code;
      }
    }

    if (raw.contains('mandarin') || raw.contains('cantonese')) {
      return 'zh';
    }

    if (raw.length >= 2 && (raw.length == 2 || raw[2] == '-' || raw[2] == '_')) {
      return raw.substring(0, 2);
    }

    return raw;
  }

  /// Detects the canonical 2-letter language code of [text].
  ///
  /// When [candidateA] and [candidateB] are provided, prioritizes distinguishing
  /// between those two languages using Unicode script ranges, language-specific
  /// diacritics, and core vocabulary.
  static String? detectLanguage(
    String text, {
    String? candidateA,
    String? candidateB,
  }) {
    final cleaned = _cleanTextForDetection(text);
    if (cleaned.isEmpty) return null;

    final normA = candidateA != null ? normalizeLanguageCode(candidateA) : null;
    final normB = candidateB != null ? normalizeLanguageCode(candidateB) : null;

    final hangulCount = _hangulRegex.allMatches(cleaned).length;
    final kanaCount = _kanaRegex.allMatches(cleaned).length;
    final cjkCount = _cjkRegex.allMatches(cleaned).length;
    final latinCount = _latinLetterRegex.allMatches(cleaned).length;

    // 1. Deterministic non-Latin script detection.
    if (hangulCount > 0 && hangulCount >= kanaCount) {
      return 'ko';
    }
    if (kanaCount > 0) {
      return 'ja';
    }
    if (cjkCount > 0) {
      if ((normA == 'ja' || normB == 'ja') &&
          normA != 'zh' &&
          normB != 'zh') {
        return 'ja';
      }
      return 'zh';
    }

    // 2. If the text contains Latin letters and zero non-Latin script characters,
    // and one of the candidates is a non-Latin script language ('ko', 'ja', 'zh')
    // while the other is a Latin-script language, it is deterministically the
    // Latin-script candidate!
    if (latinCount > 0) {
      if (normA != null && normB != null && normA != normB) {
        final aIsNonLatin = _nonLatinLanguageCodes.contains(normA);
        final bIsNonLatin = _nonLatinLanguageCodes.contains(normB);
        if (aIsNonLatin && !bIsNonLatin) {
          return normB;
        }
        if (bIsNonLatin && !aIsNonLatin) {
          return normA;
        }
      }

      // 3. Both candidates are Latin-script languages (or no candidates given):
      // score diacritics, punctuation, and high-frequency words.
      final candidates = <String>{
        if (normA != null && !_nonLatinLanguageCodes.contains(normA)) normA,
        if (normB != null && !_nonLatinLanguageCodes.contains(normB)) normB,
      };
      final searchPool = candidates.length >= 2
          ? candidates
          : _commonWordsByLanguage.keys.toSet();

      var bestLang = '';
      var bestScore = 0;
      var secondBestScore = 0;

      for (final lang in searchPool) {
        final score = _scoreLatinLanguage(cleaned, lang);
        if (score > bestScore) {
          secondBestScore = bestScore;
          bestScore = score;
          bestLang = lang;
        } else if (score > secondBestScore) {
          secondBestScore = score;
        }
      }

      if (bestScore > 0 && bestScore > secondBestScore) {
        return bestLang;
      }
    }

    return null;
  }

  /// Analyzes a [TranslationResult] against [baseLanguage] and [targetLanguage]
  /// to determine the true speaker direction (`isBaseLanguage`) and whether
  /// `translatedText` failed to translate (echoed the source language).
  static TranslationDirectionAnalysis analyzeTranslation({
    required TranslationResult result,
    required String baseLanguage,
    required String targetLanguage,
  }) {
    final baseCode = normalizeLanguageCode(baseLanguage);
    final targetCode = normalizeLanguageCode(targetLanguage);
    final reportedSourceCode = normalizeLanguageCode(result.sourceLanguage);

    final hasOriginal =
        result.originalText != null && result.originalText!.trim().isNotEmpty;

    final detectedOriginalCode = hasOriginal
        ? detectLanguage(
            result.originalText!,
            candidateA: baseCode,
            candidateB: targetCode,
          )
        : null;

    final detectedTranslatedCode = detectLanguage(
      result.translatedText,
      candidateA: baseCode,
      candidateB: targetCode,
    );

    final isExactEcho =
        hasOriginal &&
        _normalizeForComparison(result.translatedText).isNotEmpty &&
        _normalizeForComparison(result.translatedText) ==
            _normalizeForComparison(result.originalText!);

    // Determine whether the model echoed/transcribed the spoken language
    // instead of translating it into the opposite language.
    var needsFallback = false;
    String resolvedSourceCode;

    if (isExactEcho) {
      needsFallback = true;
      resolvedSourceCode =
          detectedOriginalCode ??
          detectedTranslatedCode ??
          (reportedSourceCode == targetCode ? targetCode : baseCode);
    } else if (detectedOriginalCode != null &&
        detectedTranslatedCode != null &&
        detectedOriginalCode == detectedTranslatedCode) {
      // Both original_transcript and translated_text are in the SAME language!
      needsFallback = true;
      resolvedSourceCode = detectedOriginalCode;
    } else if (!hasOriginal &&
        detectedTranslatedCode != null &&
        detectedTranslatedCode == reportedSourceCode) {
      // No original_transcript was provided, and translated_text is written in
      // the same language that the model reported as the spoken source language!
      needsFallback = true;
      resolvedSourceCode = detectedTranslatedCode;
    } else {
      // The translation is in the opposite language of the spoken audio.
      // Derive the true spoken source language from the actual text languages:
      // - If translatedText is in targetCode (e.g. Korean), the speaker spoke
      //   baseCode (e.g. English) -> Host message (LEFT).
      // - If translatedText is in baseCode (e.g. English), the speaker spoke
      //   targetCode (e.g. Korean) -> Guest message (RIGHT).
      if (detectedTranslatedCode == targetCode) {
        resolvedSourceCode = baseCode;
      } else if (detectedTranslatedCode == baseCode) {
        resolvedSourceCode = targetCode;
      } else if (detectedOriginalCode == baseCode) {
        resolvedSourceCode = baseCode;
      } else if (detectedOriginalCode == targetCode) {
        resolvedSourceCode = targetCode;
      } else if (reportedSourceCode == targetCode) {
        resolvedSourceCode = targetCode;
      } else {
        resolvedSourceCode = baseCode;
      }
    }

    final isBaseLanguage = resolvedSourceCode == baseCode;
    final targetOutputCode = isBaseLanguage ? targetCode : baseCode;
    final sourceTextForFallback =
        hasOriginal && result.originalText!.trim().isNotEmpty
        ? result.originalText!.trim()
        : result.translatedText.trim();

    return TranslationDirectionAnalysis(
      resolvedSourceCode: resolvedSourceCode,
      targetOutputCode: targetOutputCode,
      isBaseLanguage: isBaseLanguage,
      needsFallbackTranslation: needsFallback && baseCode != targetCode,
      sourceTextForFallback: sourceTextForFallback,
      detectedOriginalCode: detectedOriginalCode,
      detectedTranslatedCode: detectedTranslatedCode,
    );
  }

  static String _cleanTextForDetection(String text) {
    return text
        .replaceAll(_conversionParenRegex, ' ')
        .replaceAll(_currencyAndNumberTokenRegex, ' ')
        .trim();
  }

  static String _normalizeForComparison(String text) {
    return _cleanTextForDetection(text)
        .toLowerCase()
        .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
        .trim();
  }

  static int _scoreLatinLanguage(String text, String langCode) {
    var score = 0;
    final lower = text.toLowerCase();

    switch (langCode) {
      case 'es':
        score += RegExp(r'[¿¡ñ]').allMatches(lower).length * 4;
        score += RegExp(r'[áéíóú]').allMatches(lower).length;
      case 'fr':
        score += RegExp(r'[œæçëï]').allMatches(lower).length * 4;
        score += RegExp(r'[àâéèêîôùû]').allMatches(lower).length;
      case 'de':
        score += RegExp(r'ß').allMatches(lower).length * 5;
        score += RegExp(r'[äöü]').allMatches(lower).length * 2;
      case 'pt':
        score += RegExp(r'[ãõ]').allMatches(lower).length * 5;
        score += RegExp(r'[çáâàéêíóôú]').allMatches(lower).length;
      case 'it':
        score += RegExp(r'[ìòù]').allMatches(lower).length * 2;
        score += RegExp(r'[àèé]').allMatches(lower).length;
    }

    final lexicon = _commonWordsByLanguage[langCode];
    if (lexicon != null) {
      for (final match in _wordTokenRegex.allMatches(lower)) {
        final word = match.group(0);
        if (word != null && lexicon.contains(word)) {
          score += 2;
        }
      }
    }

    return score;
  }
}
