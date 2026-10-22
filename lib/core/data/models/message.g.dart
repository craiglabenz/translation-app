// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'message.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Message _$MessageFromJson(Map<String, dynamic> json) => _Message(
  id: json['id'] as String,
  conversationId: json['conversationId'] as String,
  timestamp: DateTime.parse(json['timestamp'] as String),
  isBaseLanguage: json['isBaseLanguage'] as bool,
  originalText: json['originalText'] as String? ?? '',
  translatedText: json['translatedText'] as String? ?? '',
  annotatedText: json['annotatedText'] as String? ?? '',
);

Map<String, dynamic> _$MessageToJson(_Message instance) => <String, dynamic>{
  'id': instance.id,
  'conversationId': instance.conversationId,
  'timestamp': instance.timestamp.toIso8601String(),
  'isBaseLanguage': instance.isBaseLanguage,
  'originalText': instance.originalText,
  'translatedText': instance.translatedText,
  'annotatedText': instance.annotatedText,
};
