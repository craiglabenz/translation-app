// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_settings.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_SupportedLanguage _$SupportedLanguageFromJson(Map<String, dynamic> json) =>
    _SupportedLanguage(
      code: json['code'] as String,
      name: json['name'] as String,
      nativeName: json['nativeName'] as String,
    );

Map<String, dynamic> _$SupportedLanguageToJson(_SupportedLanguage instance) =>
    <String, dynamic>{
      'code': instance.code,
      'name': instance.name,
      'nativeName': instance.nativeName,
    };

_SupportedCurrency _$SupportedCurrencyFromJson(Map<String, dynamic> json) =>
    _SupportedCurrency(
      code: json['code'] as String,
      name: json['name'] as String,
      symbol: json['symbol'] as String,
    );

Map<String, dynamic> _$SupportedCurrencyToJson(_SupportedCurrency instance) =>
    <String, dynamic>{
      'code': instance.code,
      'name': instance.name,
      'symbol': instance.symbol,
    };

_AppSettings _$AppSettingsFromJson(Map<String, dynamic> json) => _AppSettings(
  id: json['id'] as String? ?? AppSettings.defaultId,
  baseLanguage: json['baseLanguage'] as String? ?? 'en',
  targetLanguage: json['targetLanguage'] as String? ?? 'es',
  baseCurrency: json['baseCurrency'] as String? ?? 'USD',
  targetCurrency: json['targetCurrency'] as String? ?? 'EUR',
  modelDownloadUrl:
      json['modelDownloadUrl'] as String? ??
      AppSettings.defaultModelDownloadUrl,
  textScaleFactor:
      (json['textScaleFactor'] as num?)?.toDouble() ??
      AppSettings.defaultTextScaleFactor,
);

Map<String, dynamic> _$AppSettingsToJson(_AppSettings instance) =>
    <String, dynamic>{
      'id': instance.id,
      'baseLanguage': instance.baseLanguage,
      'targetLanguage': instance.targetLanguage,
      'baseCurrency': instance.baseCurrency,
      'targetCurrency': instance.targetCurrency,
      'modelDownloadUrl': instance.modelDownloadUrl,
      'textScaleFactor': instance.textScaleFactor,
    };
