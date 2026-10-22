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

  /// Curated list of supported languages.
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
  ];

  /// Curated list of supported currencies (supported by Frankfurter API).
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

  /// Returns the flag emoji for a detected or configured language [code]
  /// (e.g. `'en'` -> `'🇺🇸'`, `'ko'` -> `'🇰🇷'`).
  static String languageFlagFor(String code) {
    final trimmed = code.trim().toLowerCase();
    if (trimmed.isEmpty) return '🌐';
    final primary = trimmed.split(RegExp(r'[-_\s()]')).first;
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
