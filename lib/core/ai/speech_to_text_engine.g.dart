// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'speech_to_text_engine.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_SpeechToTextResult _$SpeechToTextResultFromJson(Map<String, dynamic> json) =>
    _SpeechToTextResult(
      transcript: json['transcript'] as String,
      detectedLanguageCode: json['detectedLanguageCode'] as String,
      durationMs: (json['durationMs'] as num).toInt(),
      modelName: json['modelName'] as String?,
      segments:
          (json['segments'] as List<dynamic>?)
              ?.map((e) => SpeechSegment.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const <SpeechSegment>[],
    );

Map<String, dynamic> _$SpeechToTextResultToJson(
  _SpeechToTextResult instance,
) => <String, dynamic>{
  'transcript': instance.transcript,
  'detectedLanguageCode': instance.detectedLanguageCode,
  'durationMs': instance.durationMs,
  'modelName': instance.modelName,
  'segments': instance.segments.map((e) => e.toJson()).toList(),
};
