import 'package:translation_app/core/ai/translation_engine.dart';
import 'package:translation_app/core/data/models/app_settings.dart';
import 'package:translation_app/core/logging/app_logger.dart';

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

  static final _log = AppLogger.of('LanguageDetector');

  static final RegExp _hangulRegex = RegExp(
    r'[\uAC00-\uD7AF\u1100-\u11FF\u3130-\u318F]',
  );
  static final RegExp _kanaRegex = RegExp(r'[\u3040-\u309F\u30A0-\u30FF]');
  static final RegExp _cjkRegex = RegExp(r'[\u4E00-\u9FFF\u3400-\u4DBF]');
  static final RegExp _arabicRegex = RegExp(r'[\u0600-\u06FF\u0750-\u077F]');
  static final RegExp _hebrewRegex = RegExp(r'[\u0590-\u05FF]');
  static final RegExp _devanagariRegex = RegExp(r'[\u0900-\u097F]');
  static final RegExp _bengaliRegex = RegExp(r'[\u0980-\u09FF]');
  static final RegExp _thaiRegex = RegExp(r'[\u0E00-\u0E7F]');
  static final RegExp _greekRegex = RegExp(r'[\u0370-\u03FF]');
  static final RegExp _cyrillicRegex = RegExp(r'[\u0400-\u04FF]');
  static final RegExp _latinLetterRegex = RegExp(r'[a-zA-Z\u00C0-\u024F\u1E00-\u1EFF]');
  static final RegExp _wordTokenRegex = RegExp(r"[a-z\u00C0-\u024F\u1E00-\u1EFF']+");

  /// Parenthetical currency/time annotations like `(18:00 (6PM))`, `(6PM)`,
  /// `(10.87 USD)`, or `(9.20 EUR)` added by formatting rules.
  static final RegExp _conversionParenRegex = RegExp(
    r'\([^)]*(?:\d|USD|EUR|GBP|JPY|CHF|CAD|AUD|MXN|BRL|KRW|CNY|SAR|BDT|BGN|CZK|DKK|ILS|INR|HUF|IDR|NOK|PLN|RON|RUB|RSD|KES|SEK|THB|TRY|UAH|VND|AM|PM)[^)]*\)',
    caseSensitive: false,
  );

  static final RegExp _currencyAndNumberTokenRegex = RegExp(
    r'\b(?:\d+(?:[.,:]\d+)*|USD|EUR|GBP|JPY|CHF|CAD|AUD|MXN|BRL|KRW|CNY|SAR|BDT|BGN|CZK|DKK|ILS|INR|HUF|IDR|NOK|PLN|RON|RUB|RSD|KES|SEK|THB|TRY|UAH|VND|AM|PM)\b',
    caseSensitive: false,
  );

  static const Set<String> _nonLatinLanguageCodes = <String>{
    'ko',
    'ja',
    'zh',
    'ar',
    'bn',
    'bg',
    'el',
    'he',
    'hi',
    'ru',
    'sr',
    'th',
    'uk',
  };
  static const Set<String> _cyrillicLanguageCodes = <String>{
    'ru',
    'uk',
    'bg',
    'sr',
  };

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
          'me',
          'te',
          'se',
          'nos',
          'lo',
          'le',
          'les',
          'quiero',
          'necesito',
          'puedo',
          'puede',
          'tengo',
          'tiene',
          'hay',
          'gusta',
          'vamos',
          'voy',
          'ir',
          'hacer',
          'comer',
          'beber',
          'pagar',
          'comprar',
          'boleto',
          'billete',
          'mesa',
          'habitación',
          'farmacia',
          'médico',
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
          'me',
          'te',
          'se',
          'ne',
          'pas',
          'voudrais',
          'veux',
          'peux',
          'peut',
          'besoin',
          'aller',
          'payer',
          'billet',
          'chambre',
          'table',
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
          'möchte',
          'will',
          'kann',
          'muss',
          'brauche',
          'gehen',
          'zahlen',
          'bezahlen',
          'zimmer',
          'tisch',
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
          'mi',
          'ti',
          'si',
          'ci',
          'vorrei',
          'voglio',
          'posso',
          'può',
          'devo',
          'andare',
          'pagare',
          'biglietto',
          'camera',
          'tavolo',
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
          'me',
          'te',
          'se',
          'quero',
          'preciso',
          'posso',
          'pode',
          'tenho',
          'tem',
          'ir',
          'pagar',
          'passagem',
          'quarto',
          'mesa',
        },
        'nl': <String>{
          'de',
          'het',
          'een',
          'en',
          'van',
          'ik',
          'je',
          'jij',
          'u',
          'wij',
          'we',
          'zij',
          'ze',
          'niet',
          'geen',
          'waar',
          'wat',
          'hoe',
          'hoeveel',
          'wanneer',
          'waarom',
          'met',
          'voor',
          'naar',
          'op',
          'aan',
          'uit',
          'dank',
          'bedankt',
          'alsjeblieft',
          'alstublieft',
          'goedemorgen',
          'goedenavond',
          'trein',
          'station',
          'rekening',
          'water',
          'hulp',
        },
        'sv': <String>{
          'och',
          'att',
          'det',
          'som',
          'en',
          'ett',
          'är',
          'jag',
          'du',
          'vi',
          'de',
          'inte',
          'för',
          'med',
          'på',
          'till',
          'från',
          'var',
          'vad',
          'hur',
          'när',
          'tack',
          'hej',
          'snälla',
          'ursäkta',
          'station',
          'tåg',
          'vatten',
          'nota',
        },
        'da': <String>{
          'og',
          'det',
          'som',
          'en',
          'et',
          'er',
          'jeg',
          'du',
          'vi',
          'de',
          'ikke',
          'for',
          'med',
          'på',
          'til',
          'fra',
          'hvor',
          'hvad',
          'hvordan',
          'hvornår',
          'tak',
          'hej',
          'undskyld',
          'tog',
          'vand',
        },
        'no': <String>{
          'og',
          'det',
          'som',
          'en',
          'et',
          'er',
          'jeg',
          'du',
          'vi',
          'de',
          'ikke',
          'for',
          'med',
          'på',
          'til',
          'fra',
          'hvor',
          'hva',
          'hvordan',
          'når',
          'takk',
          'hei',
          'unnskyld',
          'tog',
          'vann',
        },
        'fi': <String>{
          'ja',
          'on',
          'ei',
          'se',
          'minä',
          'sinä',
          'hän',
          'me',
          'te',
          'he',
          'missä',
          'mitä',
          'kuinka',
          'milloin',
          'paljonko',
          'kiitos',
          'anteeksi',
          'hei',
          'huomenta',
          'asema',
          'juna',
          'vesi',
          'lasku',
        },
        'pl': <String>{
          'i',
          'w',
          'na',
          'z',
          'do',
          'nie',
          'to',
          'jest',
          'są',
          'ja',
          'ty',
          'my',
          'wy',
          'oni',
          'gdzie',
          'co',
          'jak',
          'kiedy',
          'ile',
          'dziękuję',
          'proszę',
          'przepraszam',
          'dzień',
          'dobry',
          'cześć',
          'dworzec',
          'pociąg',
          'woda',
          'rachunek',
        },
        'cs': <String>{
          'a',
          'v',
          'na',
          'se',
          'je',
          'jsou',
          'jsem',
          'ne',
          'kde',
          'co',
          'jak',
          'kdy',
          'kolik',
          'děkuji',
          'prosím',
          'promiňte',
          'dobrý',
          'den',
          'ahoj',
          'nádraží',
          'vlak',
          'voda',
          'účet',
        },
        'tr': <String>{
          've',
          'bir',
          'bu',
          'şu',
          'o',
          'ben',
          'sen',
          'biz',
          'siz',
          'onlar',
          'için',
          'ile',
          'değil',
          'mi',
          'mı',
          'mu',
          'mü',
          'nerede',
          'ne',
          'nasıl',
          'kaç',
          'neزمان',
          'merhaba',
          'teşekkür',
          'teşekkürler',
          'lütfen',
          'pardon',
          'evet',
          'hayır',
          'istasyon',
          'tren',
          'su',
          'hesap',
        },
        'vi': <String>{
          'và',
          'là',
          'của',
          'có',
          'không',
          'tôi',
          'bạn',
          'chúng',
          'ở',
          'đâu',
          'gì',
          'như',
          'thế',
          'nào',
          'bao',
          'nhiêu',
          'xin',
          'chào',
          'cảm',
          'ơn',
          'làm',
          'nhà',
          'ga',
          'tàu',
          'nước',
          'hóa',
          'đơn',
        },
        'id': <String>{
          'dan',
          'yang',
          'di',
          'ke',
          'dari',
          'ini',
          'itu',
          'saya',
          'aku',
          'kamu',
          'anda',
          'kami',
          'mereka',
          'tidak',
          'bukan',
          'apa',
          'dimana',
          'mana',
          'kapan',
          'bagaimana',
          'berapa',
          'untuk',
          'dengan',
          'terima',
          'kasih',
          'tolong',
          'permisi',
          'selamat',
          'pagi',
          'siang',
          'malam',
          'stasiun',
          'kereta',
          'air',
        },
        'ms': <String>{
          'dan',
          'yang',
          'di',
          'ke',
          'dari',
          'ini',
          'itu',
          'saya',
          'awak',
          'anda',
          'kami',
          'mereka',
          'tidak',
          'bukan',
          'apa',
          'mana',
          'bila',
          'bagaimana',
          'berapa',
          'untuk',
          'dengan',
          'terima',
          'kasih',
          'tolong',
          'selamat',
          'pagi',
          'stesen',
          'air',
        },
        'ro': <String>{
          'și',
          'în',
          'la',
          'de',
          'cu',
          'pe',
          'este',
          'sunt',
          'eu',
          'tu',
          'noi',
          'voi',
          'nu',
          'unde',
          'ce',
          'cum',
          'când',
          'cât',
          'mulțumesc',
          'vă',
          'rog',
          'scuzați',
          'bună',
          'ziua',
          'gară',
          'tren',
          'apă',
          'notă',
        },
        'hu': <String>{
          'és',
          'a',
          'az',
          'egy',
          'van',
          'nem',
          'én',
          'te',
          'mi',
          'ti',
          'ők',
          'hol',
          'hogyan',
          'mikor',
          'mennyi',
          'köszönöm',
          'kérem',
          'elnézést',
          'jó',
          'napot',
          'szia',
          'állomás',
          'vonat',
          'víz',
          'számla',
        },
        'sw': <String>{
          'na',
          'ya',
          'wa',
          'kwa',
          'ni',
          'si',
          'mimi',
          'wewe',
          'sisi',
          'wao',
          'wapi',
          'nini',
          'vipi',
          'lini',
          'ngapi',
          'asante',
          'tafadhali',
          'habari',
          'jambo',
          'kituo',
          'maji',
          'chakula',
        },
        'tl': <String>{
          'ang',
          'ng',
          'sa',
          'mga',
          'at',
          'ay',
          'ako',
          'ikaw',
          'ka',
          'kami',
          'tayo',
          'sila',
          'hindi',
          'saan',
          'ano',
          'paano',
          'kailan',
          'magkano',
          'salamat',
          'pakiusap',
          'paumanhin',
          'magandang',
          'umaga',
          'tubig',
          'pagkain',
        },
      };

  /// Words that are frequently used as leading conversational interjections or
  /// international travel loanwords across languages. When one of these appears
  /// as the first word of a multi-word sentence whose remaining words belong to
  /// another language, it is discounted so it does not hijack language detection.
  static const Set<String> _leadingInterjectionsAndLoanwords = <String>{
    'ok',
    'okay',
    'oh',
    'ah',
    'uh',
    'um',
    'hmm',
    'hm',
    'mm',
    'no',
    'hey',
    'hi',
    'hello',
    'yes',
    'yeah',
    'wait',
    'well',
    'so',
    'sorry',
    'please',
    'taxi',
    'hotel',
    'bus',
    'train',
    'station',
    'metro',
    'wifi',
    'menu',
    'cafe',
    'bar',
    'euro',
    'euros',
    'dollar',
    'dollars',
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
    if (_arabicRegex.hasMatch(cleaned)) {
      return 'ar';
    }
    if (_hebrewRegex.hasMatch(cleaned)) {
      return 'he';
    }
    if (_devanagariRegex.hasMatch(cleaned)) {
      return 'hi';
    }
    if (_bengaliRegex.hasMatch(cleaned)) {
      return 'bn';
    }
    if (_thaiRegex.hasMatch(cleaned)) {
      return 'th';
    }
    if (_greekRegex.hasMatch(cleaned)) {
      return 'el';
    }
    if (_cyrillicRegex.hasMatch(cleaned)) {
      if (normA != null &&
          _cyrillicLanguageCodes.contains(normA) &&
          (normB == null || !_cyrillicLanguageCodes.contains(normB))) {
        return normA;
      }
      if (normB != null &&
          _cyrillicLanguageCodes.contains(normB) &&
          (normA == null || !_cyrillicLanguageCodes.contains(normA))) {
        return normB;
      }
      if (RegExp(r'[іїєґІЇЄҐ]').hasMatch(cleaned)) return 'uk';
      if (RegExp(r'[ђјљњћџЂЈЉЊЋЏ]').hasMatch(cleaned)) return 'sr';
      if (RegExp(r'[ыэъЫЭЪ]').hasMatch(cleaned) && normA != 'bg' && normB != 'bg') {
        return 'ru';
      }
      return normA != null && _cyrillicLanguageCodes.contains(normA)
          ? normA
          : (normB != null && _cyrillicLanguageCodes.contains(normB)
                ? normB
                : 'ru');
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
      // score diacritics, punctuation, and high-frequency words, while
      // discounting any lone first-word match on multi-word utterances.
      final candidates = <String>{
        if (normA != null && !_nonLatinLanguageCodes.contains(normA)) normA,
        if (normB != null && !_nonLatinLanguageCodes.contains(normB)) normB,
      };
      final searchPool = candidates.length >= 2
          ? candidates
          : _commonWordsByLanguage.keys.toSet();
      final peerMap = <String, String?>{};
      if (candidates.length == 2) {
        final list = candidates.toList(growable: false);
        peerMap[list[0]] = list[1];
        peerMap[list[1]] = list[0];
      }

      var bestLang = '';
      var bestScore = 0;
      var secondBestScore = 0;

      for (final lang in searchPool) {
        final score = _scoreLatinLanguage(
          cleaned,
          lang,
          peerLangCode: peerMap[lang],
        );
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

  /// Resolves the spoken source language (`baseCode` or `targetCode`) from
  /// [transcript] and the model's [reportedLanguage], preventing a single
  /// leading loanword or English-sounding first word from overriding the
  /// true language of the utterance.
  static String resolveSpokenLanguage({
    required String transcript,
    required String reportedLanguage,
    required String baseLanguage,
    required String targetLanguage,
  }) {
    final baseCode = normalizeLanguageCode(baseLanguage);
    final targetCode = normalizeLanguageCode(targetLanguage);
    final normalizedReported = normalizeLanguageCode(reportedLanguage);
    final fallbackReported = normalizedReported == targetCode
        ? targetCode
        : baseCode;

    final cleaned = _cleanTextForDetection(transcript);
    if (cleaned.isEmpty) {
      _log.info(
        '[TAG] resolveSpokenLanguage: empty cleaned transcript -> falling back to model reported="$reportedLanguage" ($fallbackReported).',
      );
      return fallbackReported;
    }

    final detected = detectLanguage(
      cleaned,
      candidateA: baseCode,
      candidateB: targetCode,
    );
    if (detected == null) {
      _log.info(
        '[TAG] resolveSpokenLanguage: text detector inconclusive for "$transcript" '
        '(pair=$baseCode<->$targetCode) -> trusting model reported="$reportedLanguage" ($fallbackReported).',
      );
      return fallbackReported;
    }

    // If one candidate uses a non-Latin script and the other uses Latin script,
    // script detection is deterministic.
    final baseIsNonLatin = _nonLatinLanguageCodes.contains(baseCode);
    final targetIsNonLatin = _nonLatinLanguageCodes.contains(targetCode);
    if (baseIsNonLatin != targetIsNonLatin) {
      _log.info(
        '[TAG] resolveSpokenLanguage: deterministic script match for "$transcript" '
        '-> resolved="$detected" (modelReported="$reportedLanguage"/$fallbackReported, pair=$baseCode<->$targetCode).',
      );
      return detected;
    }

    // If both the audio model and text detector agree, return immediately.
    if (detected == fallbackReported) {
      final baseScore = _scoreLatinLanguage(
        cleaned,
        baseCode,
        peerLangCode: targetCode,
      );
      final targetScore = _scoreLatinLanguage(
        cleaned,
        targetCode,
        peerLangCode: baseCode,
      );
      _log.info(
        '[TAG] resolveSpokenLanguage: model and text detector AGREE on "$detected" '
        'for "$transcript" (scores: $baseCode=$baseScore, $targetCode=$targetScore).',
      );
      return detected;
    }

    final baseScore = _scoreLatinLanguage(
      cleaned,
      baseCode,
      peerLangCode: targetCode,
    );
    final targetScore = _scoreLatinLanguage(
      cleaned,
      targetCode,
      peerLangCode: baseCode,
    );

    // When both candidates are Latin-script languages and the audio model
    // reported `targetCode`, only allow overriding back to `baseCode` if
    // `baseCode` has strong multi-word evidence (score >= targetScore + 4)
    // and `targetCode` has zero diacritic or vocabulary hits.
    if (fallbackReported == targetCode && detected == baseCode) {
      if (targetScore > 0 || baseScore < 4) {
        _log.info(
          '[TAG] resolveSpokenLanguage: keeping model-reported "$targetCode" over text-detected "$baseCode" '
          'for "$transcript" (scores: $baseCode=$baseScore, $targetCode=$targetScore -> insufficient $baseCode evidence to override audio model).',
        );
        return targetCode;
      }
    }

    _log.info(
      '[TAG] resolveSpokenLanguage: text detector OVERRODE model-reported "$fallbackReported" -> "$detected" '
      'for "$transcript" (scores: $baseCode=$baseScore, $targetCode=$targetScore).',
    );
    return detected;
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

  static int _scoreLatinLanguage(
    String text,
    String langCode, {
    String? peerLangCode,
  }) {
    final lower = text.toLowerCase();
    final diacriticScore = _scoreLatinDiacritics(lower, langCode);

    final lexicon = _commonWordsByLanguage[langCode];
    if (lexicon == null) {
      return diacriticScore;
    }

    final peerLexicon = peerLangCode != null
        ? _commonWordsByLanguage[peerLangCode]
        : null;
    final words = _wordTokenRegex
        .allMatches(lower)
        .map((m) => m.group(0))
        .whereType<String>()
        .toList(growable: false);

    if (words.isEmpty) {
      return diacriticScore;
    }

    var firstWordScore = 0;
    var bodyWordScore = 0;

    for (var i = 0; i < words.length; i++) {
      final word = words[i];
      if (!lexicon.contains(word)) {
        continue;
      }
      // Shared homographs present in both candidate lexicons (e.g. "me", "in",
      // "de", "la", "con") are neutral between the two languages.
      if (peerLexicon != null && peerLexicon.contains(word)) {
        continue;
      }
      if (i == 0) {
        if (words.length >= 3 &&
            _leadingInterjectionsAndLoanwords.contains(word)) {
          continue;
        }
        firstWordScore += 2;
      } else {
        bodyWordScore += 2;
      }
    }

    // If the utterance has 3+ words and the ONLY lexical match for `langCode`
    // was the very first word (`words[0]`) with zero matches in the rest of the
    // sentence (`words.sublist(1)`) and zero language-specific diacritics,
    // discount the lone first-word match so an English-sounding first word
    // never hijacks a multi-word sentence in another language.
    if (words.length >= 3 &&
        firstWordScore > 0 &&
        bodyWordScore == 0 &&
        diacriticScore == 0) {
      _log.fine(
        '[TAG] _scoreLatinLanguage($langCode): discounting lone first-word match '
        '"${words.first}" in ${words.length}-word utterance "$text" (bodyScore=0, diacritics=0).',
      );
      return 0;
    }

    return diacriticScore + firstWordScore + bodyWordScore;
  }

  static int _scoreLatinDiacritics(String lower, String langCode) {
    var score = 0;
    switch (langCode) {
      case 'es':
        score += RegExp(r'[¿¡ñ]').allMatches(lower).length * 4;
        score += RegExp(r'[áéíóúü]').allMatches(lower).length;
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
      case 'pl':
        score += RegExp(r'[ąćęłńśźż]').allMatches(lower).length * 4;
      case 'cs':
      case 'sk':
        score += RegExp(r'[čďěňřšťůžĺľŕ]').allMatches(lower).length * 4;
      case 'tr':
        score += RegExp(r'[ğışçöü]').allMatches(lower).length * 3;
      case 'vi':
        score +=
            RegExp(
              r'[ăâđêôơưạảấầẩẫậắằẳẵặẹẻẽếềểễệỉịọỏốồổỗộớờởỡợụủứừửữựỳỵỷỹ]',
            ).allMatches(lower).length *
            4;
      case 'ro':
        score += RegExp(r'[ăâîșțşţ]').allMatches(lower).length * 4;
      case 'hu':
        score += RegExp(r'[őű]').allMatches(lower).length * 5;
        score += RegExp(r'[áéíóöúü]').allMatches(lower).length;
      case 'sv':
      case 'fi':
        score += RegExp(r'[åäö]').allMatches(lower).length * 3;
      case 'da':
      case 'no':
        score += RegExp(r'[æøå]').allMatches(lower).length * 4;
      case 'hr':
      case 'sl':
        score += RegExp(r'[čćđšž]').allMatches(lower).length * 4;
      case 'lv':
      case 'lt':
        score += RegExp(r'[āčēģīķļņšūžąęėįų]').allMatches(lower).length * 4;
    }
    return score;
  }
}
