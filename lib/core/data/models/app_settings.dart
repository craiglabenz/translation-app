import 'package:data_layer/data_layer.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:hive_ce/hive.dart';
import 'package:translation_app/core/ai/local_translation_engine.dart';
import 'package:translation_app/core/ai/network_translation_engine.dart';

part 'app_settings.freezed.dart';
part 'app_settings.g.dart';

/// Selects whether audio translation runs locally on-device or in the cloud via
/// Google Gemini.
enum TranslationEngineMode {
  /// On-device Gemma 4 E2B model via LiteRT-LM (offline, 38 languages).
  onDevice,

  /// Cloud-based Google Gemini API (online, 100+ languages, requires API key).
  cloud,
}

/// Represents a selectable cloud Gemini model in Settings.
@freezed
abstract class SupportedCloudModel with _$SupportedCloudModel {
  const factory SupportedCloudModel({
    required String id,
    required String name,
    required String description,
  }) = _SupportedCloudModel;

  factory SupportedCloudModel.fromJson(Map<String, Object?> json) =>
      _$SupportedCloudModelFromJson(json);
}

/// Represents a selectable on-device speech-to-text (STT) model in Settings,
/// including Edge Whisper variants (`flutter_edge_ai_speech`) and Gemma 4 E2B.
@freezed
abstract class SupportedOnDeviceSttModel with _$SupportedOnDeviceSttModel {
  const factory SupportedOnDeviceSttModel({
    required String id,
    required String name,
    required String sizeLabel,
    required String description,
    required bool isWhisper,
    required String filename,
    String? modelUrl,
    String? tokenizerUrl,
  }) = _SupportedOnDeviceSttModel;

  factory SupportedOnDeviceSttModel.fromJson(Map<String, Object?> json) =>
      _$SupportedOnDeviceSttModelFromJson(json);
}

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
/// multiplicative text scaling, and independent speech-to-text (STT) and
/// translation engine configurations (on-device vs cloud).
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
    @Default(TranslationEngineMode.onDevice)
    TranslationEngineMode sttEngineMode,
    @Default(AppSettings.defaultOnDeviceSttModelId) String onDeviceSttModelId,
    @Default(AppSettings.defaultCloudModelId) String cloudSttModelId,
    @Default(TranslationEngineMode.onDevice)
    TranslationEngineMode translationEngineMode,
    @Default(AppSettings.defaultCloudModelId) String cloudModelId,
    @Default('') String geminiApiKey,
  }) = _AppSettings;

  const AppSettings._();

  factory AppSettings.fromJson(Map<String, Object?> json) =>
      _$AppSettingsFromJson(json);

  static const String defaultId = 'app_settings';
  static const double defaultTextScaleFactor = 1.0;
  static const double minTextScaleFactor = 0.5;
  static const double maxTextScaleFactor = 3.0;
  static const String defaultCloudModelId = 'gemini-3.8-flash';
  static const String defaultOnDeviceSttModelId = 'whisper-base-int8';

  /// Available on-device Speech-to-Text (STT) models selectable in Settings,
  /// including downloadable Edge Whisper variants alongside Gemma 4 E2B.
  static const List<SupportedOnDeviceSttModel> supportedOnDeviceSttModels = [
    SupportedOnDeviceSttModel(
      id: 'whisper-base-int8',
      name: 'Whisper Base (int8)',
      sizeLabel: '73 MB',
      description: 'Recommended multilingual edge Whisper ASR',
      isWhisper: true,
      filename: 'whisper_base_30s_i8.tflite',
      modelUrl:
          'https://huggingface.co/litert-community/whisper-base/resolve/main/whisper_base_30s_i8.tflite',
      tokenizerUrl:
          'https://huggingface.co/openai/whisper-base/resolve/main/tokenizer.json',
    ),
    SupportedOnDeviceSttModel(
      id: 'whisper-tiny-int8',
      name: 'Whisper Tiny (int8)',
      sizeLabel: '39 MB',
      description: 'Ultra-compact, fastest on-device Whisper ASR',
      isWhisper: true,
      filename: 'whisper_tiny_30s_i8.tflite',
      modelUrl:
          'https://huggingface.co/litert-community/whisper-tiny/resolve/main/whisper_tiny_30s_i8.tflite',
      tokenizerUrl:
          'https://huggingface.co/openai/whisper-tiny/resolve/main/tokenizer.json',
    ),
    SupportedOnDeviceSttModel(
      id: 'whisper-tiny-f32',
      name: 'Whisper Tiny (f32)',
      sizeLabel: '151 MB',
      description: 'Full-precision float32 Whisper Tiny ASR',
      isWhisper: true,
      filename: 'whisper_tiny_30s_f32.tflite',
      modelUrl:
          'https://huggingface.co/litert-community/whisper-tiny/resolve/main/whisper_tiny_30s_f32.tflite',
      tokenizerUrl:
          'https://huggingface.co/openai/whisper-tiny/resolve/main/tokenizer.json',
    ),
    SupportedOnDeviceSttModel(
      id: 'gemma-4',
      name: 'Gemma 4 E2B Audio',
      sizeLabel: '1.6 GB',
      description: 'Uses on-device Gemma 4 multimodal audio encoder',
      isWhisper: false,
      filename: 'gemma-4-E2B-it.litertlm',
    ),
  ];

  /// Only the downloadable Edge Whisper variants from [supportedOnDeviceSttModels].
  static List<SupportedOnDeviceSttModel> get whisperVariants =>
      supportedOnDeviceSttModels.where((m) => m.isWhisper).toList();

  /// Resolves the [SupportedOnDeviceSttModel] for [modelId], falling back to
  /// the first Whisper variant (`whisper-base-int8`).
  static SupportedOnDeviceSttModel onDeviceSttModelFor(String modelId) {
    final trimmed = modelId.trim();
    for (final model in supportedOnDeviceSttModels) {
      if (model.id == trimmed || model.filename == trimmed) {
        return model;
      }
    }
    return supportedOnDeviceSttModels.first;
  }

  /// Available cloud Gemini models selectable in Settings.
  static const List<SupportedCloudModel> supportedCloudModels = [
    SupportedCloudModel(
      id: 'gemini-3.8-flash',
      name: 'Gemini 3.8 Flash',
      description: 'Ultra-low latency for live conversation (Recommended)',
    ),
    SupportedCloudModel(
      id: 'gemini-3.1-pro',
      name: 'Gemini 3.1 Pro',
      description: 'Maximum accuracy & nuance for complex idioms',
    ),
  ];

  static const String defaultHuggingFaceRepo =
      'litert-community/gemma-4-E2B-it-litert-lm';

  static const String defaultModelDownloadUrl =
      'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm';

  /// Default catalog of on-device supported languages (delegating to
  /// [LocalTranslationEngine.gemmaSupportedLanguages]).
  ///
  /// For active engine-specific language lists, prefer reading
  /// `TranslationEngine.supportedLanguages` (or `SettingsBloc.supportedLanguages`).
  static const List<SupportedLanguage> supportedLanguages =
      LocalTranslationEngine.gemmaSupportedLanguages;

  /// Combined catalog of all known languages (on-device + cloud) used for
  /// resolving display names, native names, flags, and currencies.
  static const List<SupportedLanguage> allKnownLanguages =
      NetworkTranslationEngine.cloudSupportedLanguages;

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
    SupportedCurrency(code: 'HKD', name: 'Hong Kong Dollar', symbol: r'HK$'),
    SupportedCurrency(code: 'TWD', name: 'New Taiwan Dollar', symbol: r'NT$'),
    SupportedCurrency(code: 'SGD', name: 'Singapore Dollar', symbol: r'S$'),
    SupportedCurrency(code: 'MYR', name: 'Malaysian Ringgit', symbol: 'RM'),
    SupportedCurrency(code: 'PHP', name: 'Philippine Peso', symbol: '₱'),
    SupportedCurrency(code: 'ZAR', name: 'South African Rand', symbol: 'R'),
    SupportedCurrency(code: 'ISK', name: 'Icelandic Króna', symbol: 'kr'),
    SupportedCurrency(code: 'PKR', name: 'Pakistani Rupee', symbol: '₨'),
    SupportedCurrency(code: 'IRR', name: 'Iranian Rial', symbol: '﷼'),
    SupportedCurrency(code: 'NGN', name: 'Nigerian Naira', symbol: '₦'),
    SupportedCurrency(code: 'ETB', name: 'Ethiopian Birr', symbol: 'Br'),
    SupportedCurrency(code: 'EGP', name: 'Egyptian Pound', symbol: 'E£'),
    SupportedCurrency(code: 'AED', name: 'UAE Dirham', symbol: 'د.إ'),
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
    'yue': 'HKD',
    'zh-hk': 'HKD',
    'zh-tw': 'TWD',
    'zh-hant': 'TWD',
    'ms': 'MYR',
    'tl': 'PHP',
    'fil': 'PHP',
    'af': 'ZAR',
    'zu': 'ZAR',
    'is': 'ISK',
    'ur': 'PKR',
    'fa': 'IRR',
    'ta': 'INR',
    'te': 'INR',
    'mr': 'INR',
    'gu': 'INR',
    'kn': 'INR',
    'ml': 'INR',
    'pa': 'INR',
    'ca': 'EUR',
    'eu': 'EUR',
    'gl': 'EUR',
    'ga': 'EUR',
    'cy': 'GBP',
    'ha': 'NGN',
    'yo': 'NGN',
    'am': 'ETB',
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

    for (final lang in allKnownLanguages) {
      if (lang.name.toLowerCase() == trimmed ||
          lang.nativeName.toLowerCase() == trimmed) {
        return languageToCurrencyMap[lang.code] ?? 'USD';
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
    for (final lang in allKnownLanguages) {
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
    for (final lang in allKnownLanguages) {
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
    for (final lang in allKnownLanguages) {
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
      'yue' || 'cantonese' => '🇭🇰',
      'ms' || 'msa' || 'may' || 'malay' => '🇲🇾',
      'tl' || 'fil' || 'tagalog' || 'filipino' => '🇵🇭',
      'af' || 'afr' || 'afrikaans' => '🇿🇦',
      'zu' || 'zul' || 'zulu' => '🇿🇦',
      'is' || 'isl' || 'ice' || 'icelandic' => '🇮🇸',
      'ur' || 'urd' || 'urdu' => '🇵🇰',
      'fa' || 'fas' || 'per' || 'persian' || 'farsi' => '🇮🇷',
      'ta' || 'tam' || 'tamil' => '🇮🇳',
      'te' || 'tel' || 'telugu' => '🇮🇳',
      'mr' || 'mar' || 'marathi' => '🇮🇳',
      'gu' || 'guj' || 'gujarati' => '🇮🇳',
      'kn' || 'kan' || 'kannada' => '🇮🇳',
      'ml' || 'mal' || 'malayalam' => '🇮🇳',
      'pa' || 'pan' || 'punjabi' => '🇮🇳',
      'ca' || 'cat' || 'catalan' => '🇪🇸',
      'eu' || 'eus' || 'baq' || 'basque' => '🇪🇸',
      'gl' || 'glg' || 'galician' => '🇪🇸',
      'ga' || 'gle' || 'irish' => '🇮🇪',
      'cy' || 'cym' || 'wel' || 'welsh' => '🏴󠁧󠁢󠁷󠁬󠁳󠁿',
      'ha' || 'hau' || 'hausa' => '🇳🇬',
      'yo' || 'yor' || 'yoruba' => '🇳🇬',
      'am' || 'amh' || 'amharic' => '🇪🇹',
      _ => '🌐',
    };
  }

  /// Returns the display pill text (e.g. `English (USD) ⇄ Spanish (EUR)`).
  String get pairLabel =>
      '${languageNameFor(baseLanguage)} ($baseCurrency) ⇄ '
      '${languageNameFor(targetLanguage)} ($targetCurrency)';

  /// Returns the currently selected [SupportedOnDeviceSttModel].
  SupportedOnDeviceSttModel get selectedOnDeviceSttModel =>
      onDeviceSttModelFor(onDeviceSttModelId);

  /// Returns the human-readable name of a cloud model ID.
  static String cloudModelDisplayNameFor(String id) {
    final trimmed = id.trim();
    if (trimmed == 'gemini-4') {
      return 'Gemini 3.1 Pro';
    }
    for (final model in supportedCloudModels) {
      if (model.id == trimmed || trimmed.startsWith('${model.id}-')) {
        return model.name;
      }
    }
    return trimmed.isEmpty ? 'Gemini' : trimmed;
  }

  /// Returns the human-readable name of the currently active Speech-to-Text
  /// model (e.g. `'Whisper Base (int8)'`, `'Gemma 4'`, or `'Gemini 3.8 Flash'`).
  String get activeSttModelDisplayName {
    if (sttEngineMode == TranslationEngineMode.onDevice) {
      final sttModel = selectedOnDeviceSttModel;
      return sttModel.id == 'gemma-4' ? 'Gemma 4' : sttModel.name;
    }
    return cloudModelDisplayNameFor(cloudSttModelId);
  }

  /// Returns the human-readable name of the currently active text translation
  /// model (e.g. `'Gemma 4'`, `'Gemini 3.8 Flash'`, or `'Gemini 3.1 Pro'`).
  String get activeTranslationModelDisplayName {
    if (translationEngineMode == TranslationEngineMode.onDevice) {
      return 'Gemma 4';
    }
    return cloudModelDisplayNameFor(cloudModelId);
  }

  /// Returns the human-readable name of the active STT + Translation pipeline
  /// (e.g. `'Gemma 4'`, `'Gemini 3.8 Flash'`, or `'Whisper Base (int8) → Gemma 4'`).
  String get activeModelDisplayName {
    final sttName = activeSttModelDisplayName;
    final transName = activeTranslationModelDisplayName;
    if (sttName == transName) {
      return transName;
    }
    return '$sttName → $transName';
  }

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
