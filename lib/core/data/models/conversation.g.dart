// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'conversation.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Conversation _$ConversationFromJson(Map<String, dynamic> json) =>
    _Conversation(
      id: json['id'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      baseLanguage: json['baseLanguage'] as String,
      targetLanguage: json['targetLanguage'] as String,
      previewText: json['previewText'] as String? ?? '',
      generatedSummary: json['generatedSummary'] as String?,
      userSummary: json['userSummary'] as String?,
    );

Map<String, dynamic> _$ConversationToJson(_Conversation instance) =>
    <String, dynamic>{
      'id': instance.id,
      'createdAt': instance.createdAt.toIso8601String(),
      'baseLanguage': instance.baseLanguage,
      'targetLanguage': instance.targetLanguage,
      'previewText': instance.previewText,
      'generatedSummary': instance.generatedSummary,
      'userSummary': instance.userSummary,
    };
