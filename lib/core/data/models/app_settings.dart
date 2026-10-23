import 'package:data_layer/data_layer.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:hive_ce/hive.dart';

part 'app_settings.freezed.dart';
part 'app_settings.g.dart';

/// Represents a language selectable in the translation app.
@freezed
abstract class SupportedLanguage with _$SupportedLanguage {
  const factory SupportedLanguage({
    required String code,
    required String name,
    required String nativeName,
  }) = _SupportedLanguage;

  const SupportedLanguage._();

  factory SupportedLanguage.fromJson(Map<String, Object?> json) =>
      _$SupportedLanguageFromJson(json);

  /// Flag emoji representing this language.
  String get flagEmoji => AppSettings.languageFlagFor(code);

  /// Default ISO 4217 currency code linked to this language.
  String get defaultCurrencyCode =>
      AppSettings.defaultCurrencyForLanguage(code) ?? 'USD';
}

/// Represents a currency selectable in the translation app.
@freezed
abstract class SupportedCurrency with _$SupportedCurrency {
  const factory SupportedCurrency({
    required String code,
    required String name,
    required String symbol,
  }) = _SupportedCurrency;

  factory SupportedCurrency.fromJson(Map<String, Object?> json) =>
      _$SupportedCurrencyFromJson(json);
}

/// Persistent application settings for language pairs, currencies, model URL,
/// and multiplicative text scaling.
@freezed
abstract class AppSettings with _$AppSettings {
  const factory AppSettings({
    @Default(AppSettings.defaultId) String id,
    @Default('en') String baseLanguage,
    @Default('es') String targetLanguage,
    @Default('USD') String baseCurrency,
    @Default('EUR') String targetCurrency,
    @Default(AppSettings.defaultModelDownloadUrl) String modelDownloadUrl,
    @Default(AppSettings.defaultTextScaleFactor) double textScaleFactor,
  }) = _AppSettings;

  const AppSettings._();

  factory AppSettings.fromJson(Map<String, Object?> json) =>
      _$AppSettingsFromJson(json);

  static const String defaultId = 'app_settings';
  static const double defaultTextScaleFactor = 1.0;
  static const double minTextScaleFactor = 0.5;
  static const double maxTextScaleFactor = 3.0;

  static const String defaultHuggingFaceRepo =
      'litert-community/gemma-4-E2B-it-litert-lm';

  static const String defaultModelDownloadUrl =
      'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm';

  /// Full list of Gemma pre-trained supported languages.
  static const List<SupportedLanguage> supportedLanguages = [
    SupportedLanguage(code: 'en', name: 'English', nativeName: 'English'),
    SupportedLanguage(code: 'es', name: 'Spanish', nativeName: 'Español'),
    SupportedLanguage(code: 'fr', name: 'French', nativeName: 'Français'),
    SupportedLanguage(code: 'de', name: 'German', nativeName: 'Deutsch'),
    SupportedLanguage(code: 'it', name: 'Italian', nativeName: 'Italiano'),
    SupportedLanguage(code: 'pt', name: 'Portuguese', nativeName: 'Português'),
    SupportedLanguage(code: 'ja', name: 'Japanese', nativeName: '日本語'),
    SupportedLanguage(code: 'ko', name: 'Korean', nativeName: '한국어'),
    SupportedLanguage(code: 'zh', name: 'Chinese', nativeName: '中文'),
    SupportedLanguage(code: 'ar', name: 'Arabic', nativeName: 'العربية'),
    SupportedLanguage(code: 'bn', name: 'Bengali', nativeName: 'বাংলা'),
    SupportedLanguage(code: 'bg', name: 'Bulgarian', nativeName: 'Български'),
    SupportedLanguage(code: 'hr', name: 'Croatian', nativeName: 'Hrvatski'),
    SupportedLanguage(code: 'cs', name: 'Czech', nativeName: 'Čeština'),
    SupportedLanguage(code: 'da', name: 'Danish', nativeName: 'Dansk'),
    SupportedLanguage(code: 'nl', name: 'Dutch', nativeName: 'Nederlands'),
    SupportedLanguage(code: 'et', name: 'Estonian', nativeName: 'Eesti'),
    SupportedLanguage(code: 'fi', name: 'Finnish', nativeName: 'Suomi'),
    SupportedLanguage(code: 'el', name: 'Greek', nativeName: 'Ελληνικά'),
    SupportedLanguage(code: 'he', name: 'Hebrew', nativeName: 'עברית'),
    SupportedLanguage(code: 'hi', name: 'Hindi', nativeName: 'हिन्दी'),
    SupportedLanguage(code: 'hu', name: 'Hungarian', nativeName: 'Magyar'),
    SupportedLanguage(
      code: 'id',
      name: 'Indonesian',
      nativeName: 'Bahasa Indonesia',
    ),
    SupportedLanguage(code: 'lv', name: 'Latvian', nativeName: 'Latviešu'),
    SupportedLanguage(code: 'lt', name: 'Lithuanian', nativeName: 'Lietuvių'),
    SupportedLanguage(code: 'no', name: 'Norwegian', nativeName: 'Norsk'),
    SupportedLanguage(code: 'pl', name: 'Polish', nativeName: 'Polski'),
    SupportedLanguage(code: 'ro', name: 'Romanian', nativeName: 'Română'),
    SupportedLanguage(code: 'ru', name: 'Russian', nativeName: 'Русский'),
    SupportedLanguage(code: 'sr', name: 'Serbian', nativeName: 'Српски'),
    SupportedLanguage(code: 'sk', name: 'Slovak', nativeName: 'Slovenčina'),
    SupportedLanguage(code: 'sl', name: 'Slovenian', nativeName: 'Slovenščina'),
    SupportedLanguage(code: 'sw', name: 'Swahili', nativeName: 'Kiswahili'),
    SupportedLanguage(code: 'sv', name: 'Swedish', nativeName: 'Svenska'),
    SupportedLanguage(code: 'th', name: 'Thai', nativeName: 'ไทย'),
    SupportedLanguage(code: 'tr', name: 'Turkish', nativeName: 'Türkçe'),
    SupportedLanguage(code: 'uk', name: 'Ukrainian', nativeName: 'Українська'),
    SupportedLanguage(code: 'vi', name: 'Vietnamese', nativeName: 'Tiếng Việt'),
  ];

  /// Curated list of supported currencies linked to [supportedLanguages].
  static const List<SupportedCurrency> supportedCurrencies = [
    SupportedCurrency(code: 'USD', name: 'US Dollar', symbol: r'$'),
    SupportedCurrency(code: 'EUR', name: 'Euro', symbol: '€'),
    SupportedCurrency(code: 'GBP', name: 'British Pound', symbol: '£'),
    SupportedCurrency(code: 'JPY', name: 'Japanese Yen', symbol: '¥'),
    SupportedCurrency(code: 'CHF', name: 'Swiss Franc', symbol: 'CHF'),
    SupportedCurrency(code: 'CAD', name: 'Canadian Dollar', symbol: r'CA$'),
    SupportedCurrency(code: 'AUD', name: 'Australian Dollar', symbol: r'A$'),
    SupportedCurrency(code: 'MXN', name: 'Mexican Peso', symbol: r'MX$'),
    SupportedCurrency(code: 'BRL', name: 'Brazilian Real', symbol: r'R$'),
    SupportedCurrency(code: 'KRW', name: 'South Korean Won', symbol: '₩'),
    SupportedCurrency(code: 'CNY', name: 'Chinese Yuan', symbol: '¥'),
    SupportedCurrency(code: 'SAR', name: 'Saudi Riyal', symbol: 'SAR'),
    SupportedCurrency(code: 'BDT', name: 'Bangladeshi Taka', symbol: '৳'),
    SupportedCurrency(code: 'BGN', name: 'Bulgarian Lev', symbol: 'лв'),
    SupportedCurrency(code: 'CZK', name: 'Czech Koruna', symbol: 'Kč'),
    SupportedCurrency(code: 'DKK', name: 'Danish Krone', symbol: 'kr'),
    SupportedCurrency(code: 'ILS', name: 'Israeli New Shekel', symbol: '₪'),
    SupportedCurrency(code: 'INR', name: 'Indian Rupee', symbol: '₹'),
    SupportedCurrency(code: 'HUF', name: 'Hungarian Forint', symbol: 'Ft'),
    SupportedCurrency(code: 'IDR', name: 'Indonesian Rupiah', symbol: 'Rp'),
    SupportedCurrency(code: 'NOK', name: 'Norwegian Krone', symbol: 'kr'),
    SupportedCurrency(code: 'PLN', name: 'Polish Złoty', symbol: 'zł'),
    SupportedCurrency(code: 'RON', name: 'Romanian Leu', symbol: 'lei'),
    SupportedCurrency(code: 'RUB', name: 'Russian Ruble', symbol: '₽'),
    SupportedCurrency(code: 'RSD', name: 'Serbian Dinar', symbol: 'дин'),
    SupportedCurrency(code: 'KES', name: 'Kenyan Shilling', symbol: 'KSh'),
    SupportedCurrency(code: 'SEK', name: 'Swedish Krona', symbol: 'kr'),
    SupportedCurrency(code: 'THB', name: 'Thai Baht', symbol: '฿'),
    SupportedCurrency(code: 'TRY', name: 'Turkish Lira', symbol: '₺'),
    SupportedCurrency(code: 'UAH', name: 'Ukrainian Hryvnia', symbol: '₴'),
    SupportedCurrency(code: 'VND', name: 'Vietnamese Đồng', symbol: '₫'),
  ];

  /// Canonical mapping from language code (and regional BCP-47 tags) to its
  /// default ISO 4217 currency code.
  static const Map<String, String> languageToCurrencyMap = <String, String>{
    'en': 'USD',
    'en-us': 'USD',
    'en-gb': 'GBP',
    'en-uk': 'GBP',
    'en-ca': 'CAD',
    'en-au': 'AUD',
    'es': 'EUR',
    'es-es': 'EUR',
    'es-mx': 'MXN',
    'fr': 'EUR',
    'fr-fr': 'EUR',
    'fr-ca': 'CAD',
    'fr-ch': 'CHF',
    'de': 'EUR',
    'de-de': 'EUR',
    'de-ch': 'CHF',
    'it': 'EUR',
    'it-it': 'EUR',
    'it-ch': 'CHF',
    'pt': 'EUR',
    'pt-pt': 'EUR',
    'pt-br': 'BRL',
    'ja': 'JPY',
    'ja-jp': 'JPY',
    'ko': 'KRW',
    'ko-kr': 'KRW',
    'zh': 'CNY',
    'zh-cn': 'CNY',
    'zh-hans': 'CNY',
    'ar': 'SAR',
    'ar-sa': 'SAR',
    'bn': 'BDT',
    'bn-bd': 'BDT',
    'bn-in': 'INR',
    'bg': 'BGN',
    'bg-bg': 'BGN',
    'hr': 'EUR',
    'hr-hr': 'EUR',
    'cs': 'CZK',
    'cs-cz': 'CZK',
    'da': 'DKK',
    'da-dk': 'DKK',
    'nl': 'EUR',
    'nl-nl': 'EUR',
    'nl-be': 'EUR',
    'et': 'EUR',
    'et-ee': 'EUR',
    'fi': 'EUR',
    'fi-fi': 'EUR',
    'el': 'EUR',
    'el-gr': 'EUR',
    'he': 'ILS',
    'iw': 'ILS',
    'he-il': 'ILS',
    'hi': 'INR',
    'hi-in': 'INR',
    'hu': 'HUF',
    'hu-hu': 'HUF',
    'id': 'IDR',
    'in': 'IDR',
    'id-id': 'IDR',
    'lv': 'EUR',
    'lv-lv': 'EUR',
    'lt': 'EUR',
    'lt-lt': 'EUR',
    'no': 'NOK',
    'nb': 'NOK',
    'nn': 'NOK',
    'no-no': 'NOK',
    'pl': 'PLN',
    'pl-pl': 'PLN',
    'ro': 'RON',
    'ro-ro': 'RON',
    'ru': 'RUB',
    'ru-ru': 'RUB',
    'sr': 'RSD',
    'sr-rs': 'RSD',
    'sk': 'EUR',
    'sk-sk': 'EUR',
    'sl': 'EUR',
    'sl-si': 'EUR',
    'sw': 'KES',
    'sw-ke': 'KES',
    'sv': 'SEK',
    'sv-se': 'SEK',
    'th': 'THB',
    'th-th': 'THB',
    'tr': 'TRY',
    'tr-tr': 'TRY',
    'uk': 'UAH',
    'uk-ua': 'UAH',
    'vi': 'VND',
    'vi-vn': 'VND',
  };

  /// Returns the default ISO 4217 currency code associated with [languageCode],
  /// or `null` if the language is unrecognized.
  static String? defaultCurrencyForLanguage(String languageCode) {
    final trimmed = languageCode.trim().toLowerCase();
    if (trimmed.isEmpty) return null;

    final normalizedTag = trimmed.replaceAll('_', '-');
    final directMatch = languageToCurrencyMap[normalizedTag];
    if (directMatch != null) return directMatch;

    final primary = normalizedTag.split(RegExp(r'[-\s()]')).first;
    final primaryMatch = languageToCurrencyMap[primary];
    if (primaryMatch != null) return primaryMatch;

    for (final lang in supportedLanguages) {
      if (lang.name.toLowerCase() == trimmed ||
          lang.nativeName.toLowerCase() == trimmed) {
        return languageToCurrencyMap[lang.code];
      }
    }

    return switch (primary) {
      'eng' || 'english' => 'USD',
      'spa' || 'spanish' || 'español' || 'espanol' => 'EUR',
      'fra' || 'fre' || 'french' || 'français' || 'francais' => 'EUR',
      'deu' || 'ger' || 'german' || 'deutsch' => 'EUR',
      'ita' || 'italian' || 'italiano' => 'EUR',
      'por' || 'portuguese' || 'português' || 'portugues' => 'EUR',
      'jp' || 'jpn' || 'japanese' || '日本語' => 'JPY',
      'kr' || 'kor' || 'korean' || '한국어' => 'KRW',
      'cn' || 'zho' || 'chi' || 'chinese' || 'mandarin' || '中文' => 'CNY',
      'ara' || 'arabic' => 'SAR',
      'ben' || 'bengali' => 'BDT',
      'bul' || 'bulgarian' => 'BGN',
      'hrv' || 'croatian' => 'EUR',
      'ces' || 'cze' || 'czech' => 'CZK',
      'dan' || 'danish' => 'DKK',
      'nld' || 'dut' || 'dutch' => 'EUR',
      'est' || 'estonian' => 'EUR',
      'fin' || 'finnish' => 'EUR',
      'ell' || 'gre' || 'greek' => 'EUR',
      'heb' || 'hebrew' => 'ILS',
      'hin' || 'hindi' => 'INR',
      'hun' || 'hungarian' => 'HUF',
      'ind' || 'indonesian' => 'IDR',
      'lav' || 'latvian' => 'EUR',
      'lit' || 'lithuanian' => 'EUR',
      'nor' || 'norwegian' => 'NOK',
      'pol' || 'polish' => 'PLN',
      'ron' || 'rum' || 'romanian' => 'RON',
      'rus' || 'russian' => 'RUB',
      'srp' || 'serbian' => 'RSD',
      'slk' || 'slo' || 'slovak' => 'EUR',
      'slv' || 'slovenian' => 'EUR',
      'swa' || 'swahili' => 'KES',
      'swe' || 'swedish' => 'SEK',
      'tha' || 'thai' => 'THB',
      'tur' || 'turkish' => 'TRY',
      'ukr' || 'ukrainian' => 'UAH',
      'vie' || 'vietnamese' => 'VND',
      _ => null,
    };
  }

  /// Returns the human-readable name for a language [code].
  static String languageNameFor(String code) {
    final trimmed = code.trim();
    if (trimmed.isEmpty) return '';
    final normalized = trimmed.toLowerCase().split(RegExp('[-_]')).first;
    for (final lang in supportedLanguages) {
      if (lang.code.toLowerCase() == normalized ||
          lang.name.toLowerCase() == trimmed.toLowerCase() ||
          lang.nativeName.toLowerCase() == trimmed.toLowerCase()) {
        return lang.name;
      }
    }
    return trimmed.toUpperCase();
  }

  /// Returns the native-script name for a language [code] (e.g. `'ko'` -> `'한국어'`,
  /// `'es'` -> `'Español'`).
  static String nativeLanguageNameFor(String code) {
    final trimmed = code.trim();
    if (trimmed.isEmpty) return '';
    final normalized = trimmed.toLowerCase().split(RegExp(r'[-_\s()]')).first;
    for (final lang in supportedLanguages) {
      if (lang.code.toLowerCase() == normalized ||
          lang.name.toLowerCase() == trimmed.toLowerCase() ||
          lang.nativeName.toLowerCase() == trimmed.toLowerCase()) {
        return lang.nativeName;
      }
    }
    return languageNameFor(code);
  }

  /// Returns the flag emoji for a detected or configured language [code]
  /// (e.g. `'en'` -> `'🇺🇸'`, `'ko'` -> `'🇰🇷'`).
  static String languageFlagFor(String code) {
    final trimmed = code.trim().toLowerCase();
    if (trimmed.isEmpty) return '🌐';
    for (final lang in supportedLanguages) {
      if (lang.name.toLowerCase() == trimmed ||
          lang.nativeName.toLowerCase() == trimmed) {
        return _flagForPrimaryCode(lang.code);
      }
    }
    final primary = trimmed.split(RegExp(r'[-_\s()]')).first;
    return _flagForPrimaryCode(primary);
  }

  static String _flagForPrimaryCode(String primary) {
    return switch (primary) {
      'en' || 'eng' || 'english' => '🇺🇸',
      'es' || 'spa' || 'spanish' || 'español' || 'espanol' => '🇪🇸',
      'fr' || 'fra' || 'fre' || 'french' || 'français' || 'francais' => '🇫🇷',
      'de' || 'deu' || 'ger' || 'german' || 'deutsch' => '🇩🇪',
      'it' || 'ita' || 'italian' || 'italiano' => '🇮🇹',
      'pt' || 'por' || 'portuguese' || 'português' || 'portugues' => '🇵🇹',
      'ja' || 'jp' || 'jpn' || 'japanese' || '日本語' => '🇯🇵',
      'ko' || 'kr' || 'kor' || 'korean' || '한국어' => '🇰🇷',
      'zh' || 'cn' || 'zho' || 'chi' || 'chinese' || 'mandarin' || '中文' =>
        '🇨🇳',
      'ar' || 'ara' || 'arabic' || 'العربية' => '🇸🇦',
      'bn' || 'ben' || 'bengali' || 'বাংলা' => '🇧🇩',
      'bg' || 'bul' || 'bulgarian' || 'български' => '🇧🇬',
      'hr' || 'hrv' || 'croatian' || 'hrvatski' => '🇭🇷',
      'cs' || 'ces' || 'cze' || 'czech' || 'čeština' || 'cestina' => '🇨🇿',
      'da' || 'dan' || 'danish' || 'dansk' => '🇩🇰',
      'nl' || 'nld' || 'dut' || 'dutch' || 'nederlands' => '🇳🇱',
      'et' || 'est' || 'estonian' || 'eesti' => '🇪🇪',
      'fi' || 'fin' || 'finnish' || 'suomi' => '🇫🇮',
      'el' || 'ell' || 'gre' || 'greek' || 'ελληνικά' => '🇬🇷',
      'he' || 'iw' || 'heb' || 'hebrew' || 'עברית' => '🇮🇱',
      'hi' || 'hin' || 'hindi' || 'हिन्दी' => '🇮🇳',
      'hu' || 'hun' || 'hungarian' || 'magyar' => '🇭🇺',
      'id' || 'in' || 'ind' || 'indonesian' => '🇮🇩',
      'lv' || 'lav' || 'latvian' || 'latviešu' => '🇱🇻',
      'lt' || 'lit' || 'lithuanian' || 'lietuvių' => '🇱🇹',
      'no' || 'nb' || 'nn' || 'nor' || 'norwegian' || 'norsk' => '🇳🇴',
      'pl' || 'pol' || 'polish' || 'polski' => '🇵🇱',
      'ro' || 'ron' || 'rum' || 'romanian' || 'română' => '🇷🇴',
      'ru' || 'rus' || 'russian' || 'русский' => '🇷🇺',
      'sr' || 'srp' || 'serbian' || 'српски' => '🇷🇸',
      'sk' || 'slk' || 'slo' || 'slovak' || 'slovenčina' => '🇸🇰',
      'sl' || 'slv' || 'slovenian' || 'slovenščina' => '🇸🇮',
      'sw' || 'swa' || 'swahili' || 'kiswahili' => '🇰🇪',
      'sv' || 'swe' || 'swedish' || 'svenska' => '🇸🇪',
      'th' || 'tha' || 'thai' || 'ไทย' => '🇹🇭',
      'tr' || 'tur' || 'turkish' || 'türkçe' => '🇹🇷',
      'uk' || 'ukr' || 'ukrainian' || 'українська' => '🇺🇦',
      'vi' || 'vie' || 'vietnamese' => '🇻🇳',
      _ => '🌐',
    };
  }

  /// Returns the display pill text (e.g. `English (USD) ⇄ Spanish (EUR)`).
  String get pairLabel =>
      '${languageNameFor(baseLanguage)} ($baseCurrency) ⇄ '
      '${languageNameFor(targetLanguage)} ($targetCurrency)';

  static Bindings<AppSettings> get bindings => Bindings<AppSettings>(
    getId: (obj) => obj.id,
    fromJson: AppSettings.fromJson,
    toJson: (obj) => obj.toJson(),
  );
}

/// Hive [TypeAdapter] for [AppSettings].
class AppSettingsAdapter extends TypeAdapter<AppSettings> {
  @override
  final int typeId = 1;

  @override
  AppSettings read(BinaryReader reader) {
    final map = reader.readMap().cast<String, Object?>();
    return AppSettings.fromJson(map);
  }

  @override
  void write(BinaryWriter writer, AppSettings obj) {
    writer.writeMap(obj.toJson());
  }
}
