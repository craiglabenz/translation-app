// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'translation_engine.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_TranslationResult _$TranslationResultFromJson(Map<String, dynamic> json) =>
    _TranslationResult(
      sourceLanguage: json['sourceLanguage'] as String,
      translatedText: json['translatedText'] as String,
      originalText: json['originalText'] as String?,
    );

Map<String, dynamic> _$TranslationResultToJson(_TranslationResult instance) =>
    <String, dynamic>{
      'sourceLanguage': instance.sourceLanguage,
      'translatedText': instance.translatedText,
      'originalText': instance.originalText,
    };
