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

  factory SupportedLanguage.fromJson(Map<String, Object?> json) =>
      _$SupportedLanguageFromJson(json);
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

/// Persistent application settings for language pairs, currencies, and model URL.
@freezed
abstract class AppSettings with _$AppSettings {
  const factory AppSettings({
    @Default(AppSettings.defaultId) String id,
    @Default('en') String baseLanguage,
    @Default('es') String targetLanguage,
    @Default('USD') String baseCurrency,
    @Default('EUR') String targetCurrency,
    @Default(AppSettings.defaultModelDownloadUrl) String modelDownloadUrl,
  }) = _AppSettings;

  const AppSettings._();

  factory AppSettings.fromJson(Map<String, Object?> json) =>
      _$AppSettingsFromJson(json);

  static const String defaultId = 'app_settings';

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

  /// Returns the human-readable name for a language [code].
  static String languageNameFor(String code) {
    final normalized = code.trim().toLowerCase();
    for (final lang in supportedLanguages) {
      if (lang.code.toLowerCase() == normalized) {
        return lang.name;
      }
    }
    return code.toUpperCase();
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
