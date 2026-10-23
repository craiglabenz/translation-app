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
      speechToTextMs: (json['speechToTextMs'] as num?)?.toInt(),
      translationMs: (json['translationMs'] as num?)?.toInt(),
      totalDurationMs: (json['totalDurationMs'] as num?)?.toInt(),
    );

Map<String, dynamic> _$TranslationResultToJson(_TranslationResult instance) =>
    <String, dynamic>{
      'sourceLanguage': instance.sourceLanguage,
      'translatedText': instance.translatedText,
      'originalText': instance.originalText,
      'speechToTextMs': instance.speechToTextMs,
      'translationMs': instance.translationMs,
      'totalDurationMs': instance.totalDurationMs,
    };
