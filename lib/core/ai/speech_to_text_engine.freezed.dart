// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'speech_to_text_engine.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$SpeechToTextResult {

 String get transcript; String get detectedLanguageCode; int get durationMs; String? get modelName; List<SpeechSegment> get segments;
/// Create a copy of SpeechToTextResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SpeechToTextResultCopyWith<SpeechToTextResult> get copyWith => _$SpeechToTextResultCopyWithImpl<SpeechToTextResult>(this as SpeechToTextResult, _$identity);

  /// Serializes this SpeechToTextResult to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as SpeechToTextResult;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SpeechToTextResult&&(identical(other.transcript, _this.transcript) || other.transcript == _this.transcript)&&(identical(other.detectedLanguageCode, _this.detectedLanguageCode) || other.detectedLanguageCode == _this.detectedLanguageCode)&&(identical(other.durationMs, _this.durationMs) || other.durationMs == _this.durationMs)&&(identical(other.modelName, _this.modelName) || other.modelName == _this.modelName)&&const DeepCollectionEquality().equals(other.segments, _this.segments));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as SpeechToTextResult;
  return Object.hash(runtimeType,_this.transcript,_this.detectedLanguageCode,_this.durationMs,_this.modelName,const DeepCollectionEquality().hash(_this.segments));
}

@override
String toString() {
  final _this = this as SpeechToTextResult;
  return 'SpeechToTextResult(transcript: ${_this.transcript}, detectedLanguageCode: ${_this.detectedLanguageCode}, durationMs: ${_this.durationMs}, modelName: ${_this.modelName}, segments: ${_this.segments})';
}


}

/// @nodoc
abstract mixin class $SpeechToTextResultCopyWith<$Res>  {
  factory $SpeechToTextResultCopyWith(SpeechToTextResult value, $Res Function(SpeechToTextResult) _then) = _$SpeechToTextResultCopyWithImpl;
@useResult
$Res call({
 String transcript, String detectedLanguageCode, int durationMs, String? modelName, List<SpeechSegment> segments
});




}
/// @nodoc
class _$SpeechToTextResultCopyWithImpl<$Res>
    implements $SpeechToTextResultCopyWith<$Res> {
  _$SpeechToTextResultCopyWithImpl(this._self, this._then);

  final SpeechToTextResult _self;
  final $Res Function(SpeechToTextResult) _then;

/// Create a copy of SpeechToTextResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? transcript = null,Object? detectedLanguageCode = null,Object? durationMs = null,Object? modelName = freezed,Object? segments = null,}) {
  return _then(SpeechToTextResult(
transcript: null == transcript ? _self.transcript : transcript // ignore: cast_nullable_to_non_nullable
as String,detectedLanguageCode: null == detectedLanguageCode ? _self.detectedLanguageCode : detectedLanguageCode // ignore: cast_nullable_to_non_nullable
as String,durationMs: null == durationMs ? _self.durationMs : durationMs // ignore: cast_nullable_to_non_nullable
as int,modelName: freezed == modelName ? _self.modelName : modelName // ignore: cast_nullable_to_non_nullable
as String?,segments: null == segments ? _self.segments : segments // ignore: cast_nullable_to_non_nullable
as List<SpeechSegment>,
  ));
}

}

/// @nodoc
@JsonSerializable()

class _SpeechToTextResult extends SpeechToTextResult {
  const _SpeechToTextResult({required this.transcript, required this.detectedLanguageCode, required this.durationMs, this.modelName, List<SpeechSegment> segments = const <SpeechSegment>[]}): _segments = segments,super._();
  factory _SpeechToTextResult.fromJson(Map<String, dynamic> json) => _$SpeechToTextResultFromJson(json);

@override final  String transcript;
@override final  String detectedLanguageCode;
@override final  int durationMs;
@override final  String? modelName;
 final  List<SpeechSegment> _segments;
@override@JsonKey() List<SpeechSegment> get segments {
  if (_segments is EqualUnmodifiableListView) return _segments;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_segments);
}

/// Create a copy of SpeechToTextResult
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SpeechToTextResultCopyWith<_SpeechToTextResult> get copyWith => __$SpeechToTextResultCopyWithImpl<_SpeechToTextResult>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$SpeechToTextResultToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SpeechToTextResult&&(identical(other.transcript, transcript) || other.transcript == transcript)&&(identical(other.detectedLanguageCode, detectedLanguageCode) || other.detectedLanguageCode == detectedLanguageCode)&&(identical(other.durationMs, durationMs) || other.durationMs == durationMs)&&(identical(other.modelName, modelName) || other.modelName == modelName)&&const DeepCollectionEquality().equals(other._segments, _segments));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,transcript,detectedLanguageCode,durationMs,modelName,const DeepCollectionEquality().hash(_segments));
}

@override
String toString() {
    return 'SpeechToTextResult(transcript: $transcript, detectedLanguageCode: $detectedLanguageCode, durationMs: $durationMs, modelName: $modelName, segments: $segments)';
}


}

/// @nodoc
abstract mixin class _$SpeechToTextResultCopyWith<$Res> implements $SpeechToTextResultCopyWith<$Res> {
  factory _$SpeechToTextResultCopyWith(_SpeechToTextResult value, $Res Function(_SpeechToTextResult) _then) = __$SpeechToTextResultCopyWithImpl;
@override @useResult
$Res call({
 String transcript, String detectedLanguageCode, int durationMs, String? modelName, List<SpeechSegment> segments
});




}
/// @nodoc
class __$SpeechToTextResultCopyWithImpl<$Res>
    implements _$SpeechToTextResultCopyWith<$Res> {
  __$SpeechToTextResultCopyWithImpl(this._self, this._then);

  final _SpeechToTextResult _self;
  final $Res Function(_SpeechToTextResult) _then;

/// Create a copy of SpeechToTextResult
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? transcript = null,Object? detectedLanguageCode = null,Object? durationMs = null,Object? modelName = freezed,Object? segments = null,}) {
  return _then(_SpeechToTextResult(
transcript: null == transcript ? _self.transcript : transcript // ignore: cast_nullable_to_non_nullable
as String,detectedLanguageCode: null == detectedLanguageCode ? _self.detectedLanguageCode : detectedLanguageCode // ignore: cast_nullable_to_non_nullable
as String,durationMs: null == durationMs ? _self.durationMs : durationMs // ignore: cast_nullable_to_non_nullable
as int,modelName: freezed == modelName ? _self.modelName : modelName // ignore: cast_nullable_to_non_nullable
as String?,segments: null == segments ? _self._segments : segments // ignore: cast_nullable_to_non_nullable
as List<SpeechSegment>,
  ));
}


}

// dart format on
