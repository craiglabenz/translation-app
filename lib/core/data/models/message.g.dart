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
  speechToTextMs: (json['speechToTextMs'] as num?)?.toInt(),
  translationMs: (json['translationMs'] as num?)?.toInt(),
  totalDurationMs: (json['totalDurationMs'] as num?)?.toInt(),
  speechToTextModel: json['speechToTextModel'] as String?,
  translationModel: json['translationModel'] as String?,
);

Map<String, dynamic> _$MessageToJson(_Message instance) => <String, dynamic>{
  'id': instance.id,
  'conversationId': instance.conversationId,
  'timestamp': instance.timestamp.toIso8601String(),
  'isBaseLanguage': instance.isBaseLanguage,
  'originalText': instance.originalText,
  'translatedText': instance.translatedText,
  'annotatedText': instance.annotatedText,
  'speechToTextMs': instance.speechToTextMs,
  'translationMs': instance.translationMs,
  'totalDurationMs': instance.totalDurationMs,
  'speechToTextModel': instance.speechToTextModel,
  'translationModel': instance.translationModel,
};
