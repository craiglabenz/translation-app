// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'message.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$Message {

 String get id; String get conversationId; DateTime get timestamp;/// True when the spoken utterance was in the user's base language (`isUser`).
 bool get isBaseLanguage; String get originalText; String get translatedText; String get annotatedText;/// Time spent in milliseconds on the speech-to-text step.
 int? get speechToTextMs;/// Time spent in milliseconds on the translation step.
 int? get translationMs;/// Total time spent in milliseconds across all steps for this message.
 int? get totalDurationMs;/// Display name of the model that performed Step 1 (Speech-to-Text).
 String? get speechToTextModel;/// Display name of the model that performed Step 2 (Text Translation).
 String? get translationModel;
/// Create a copy of Message
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MessageCopyWith<Message> get copyWith => _$MessageCopyWithImpl<Message>(this as Message, _$identity);

  /// Serializes this Message to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as Message;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Message&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.conversationId, _this.conversationId) || other.conversationId == _this.conversationId)&&(identical(other.timestamp, _this.timestamp) || other.timestamp == _this.timestamp)&&(identical(other.isBaseLanguage, _this.isBaseLanguage) || other.isBaseLanguage == _this.isBaseLanguage)&&(identical(other.originalText, _this.originalText) || other.originalText == _this.originalText)&&(identical(other.translatedText, _this.translatedText) || other.translatedText == _this.translatedText)&&(identical(other.annotatedText, _this.annotatedText) || other.annotatedText == _this.annotatedText)&&(identical(other.speechToTextMs, _this.speechToTextMs) || other.speechToTextMs == _this.speechToTextMs)&&(identical(other.translationMs, _this.translationMs) || other.translationMs == _this.translationMs)&&(identical(other.totalDurationMs, _this.totalDurationMs) || other.totalDurationMs == _this.totalDurationMs)&&(identical(other.speechToTextModel, _this.speechToTextModel) || other.speechToTextModel == _this.speechToTextModel)&&(identical(other.translationModel, _this.translationModel) || other.translationModel == _this.translationModel));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as Message;
  return Object.hash(runtimeType,_this.id,_this.conversationId,_this.timestamp,_this.isBaseLanguage,_this.originalText,_this.translatedText,_this.annotatedText,_this.speechToTextMs,_this.translationMs,_this.totalDurationMs,_this.speechToTextModel,_this.translationModel);
}

@override
String toString() {
  final _this = this as Message;
  return 'Message(id: ${_this.id}, conversationId: ${_this.conversationId}, timestamp: ${_this.timestamp}, isBaseLanguage: ${_this.isBaseLanguage}, originalText: ${_this.originalText}, translatedText: ${_this.translatedText}, annotatedText: ${_this.annotatedText}, speechToTextMs: ${_this.speechToTextMs}, translationMs: ${_this.translationMs}, totalDurationMs: ${_this.totalDurationMs}, speechToTextModel: ${_this.speechToTextModel}, translationModel: ${_this.translationModel})';
}


}

/// @nodoc
abstract mixin class $MessageCopyWith<$Res>  {
  factory $MessageCopyWith(Message value, $Res Function(Message) _then) = _$MessageCopyWithImpl;
@useResult
$Res call({
 String id, String conversationId, DateTime timestamp, bool isBaseLanguage, String originalText, String translatedText, String annotatedText, int? speechToTextMs, int? translationMs, int? totalDurationMs, String? speechToTextModel, String? translationModel
});




}
/// @nodoc
class _$MessageCopyWithImpl<$Res>
    implements $MessageCopyWith<$Res> {
  _$MessageCopyWithImpl(this._self, this._then);

  final Message _self;
  final $Res Function(Message) _then;

/// Create a copy of Message
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? conversationId = null,Object? timestamp = null,Object? isBaseLanguage = null,Object? originalText = null,Object? translatedText = null,Object? annotatedText = null,Object? speechToTextMs = freezed,Object? translationMs = freezed,Object? totalDurationMs = freezed,Object? speechToTextModel = freezed,Object? translationModel = freezed,}) {
  return _then(Message(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,conversationId: null == conversationId ? _self.conversationId : conversationId // ignore: cast_nullable_to_non_nullable
as String,timestamp: null == timestamp ? _self.timestamp : timestamp // ignore: cast_nullable_to_non_nullable
as DateTime,isBaseLanguage: null == isBaseLanguage ? _self.isBaseLanguage : isBaseLanguage // ignore: cast_nullable_to_non_nullable
as bool,originalText: null == originalText ? _self.originalText : originalText // ignore: cast_nullable_to_non_nullable
as String,translatedText: null == translatedText ? _self.translatedText : translatedText // ignore: cast_nullable_to_non_nullable
as String,annotatedText: null == annotatedText ? _self.annotatedText : annotatedText // ignore: cast_nullable_to_non_nullable
as String,speechToTextMs: freezed == speechToTextMs ? _self.speechToTextMs : speechToTextMs // ignore: cast_nullable_to_non_nullable
as int?,translationMs: freezed == translationMs ? _self.translationMs : translationMs // ignore: cast_nullable_to_non_nullable
as int?,totalDurationMs: freezed == totalDurationMs ? _self.totalDurationMs : totalDurationMs // ignore: cast_nullable_to_non_nullable
as int?,speechToTextModel: freezed == speechToTextModel ? _self.speechToTextModel : speechToTextModel // ignore: cast_nullable_to_non_nullable
as String?,translationModel: freezed == translationModel ? _self.translationModel : translationModel // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [Message].
extension MessagePatterns on Message {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Message value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Message() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Message value)  $default,){
final _that = this;
switch (_that) {
case _Message():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Message value)?  $default,){
final _that = this;
switch (_that) {
case _Message() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String conversationId,  DateTime timestamp,  bool isBaseLanguage,  String originalText,  String translatedText,  String annotatedText,  int? speechToTextMs,  int? translationMs,  int? totalDurationMs,  String? speechToTextModel,  String? translationModel)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Message() when $default != null:
return $default(_that.id,_that.conversationId,_that.timestamp,_that.isBaseLanguage,_that.originalText,_that.translatedText,_that.annotatedText,_that.speechToTextMs,_that.translationMs,_that.totalDurationMs,_that.speechToTextModel,_that.translationModel);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String conversationId,  DateTime timestamp,  bool isBaseLanguage,  String originalText,  String translatedText,  String annotatedText,  int? speechToTextMs,  int? translationMs,  int? totalDurationMs,  String? speechToTextModel,  String? translationModel)  $default,) {final _that = this;
switch (_that) {
case _Message():
return $default(_that.id,_that.conversationId,_that.timestamp,_that.isBaseLanguage,_that.originalText,_that.translatedText,_that.annotatedText,_that.speechToTextMs,_that.translationMs,_that.totalDurationMs,_that.speechToTextModel,_that.translationModel);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String conversationId,  DateTime timestamp,  bool isBaseLanguage,  String originalText,  String translatedText,  String annotatedText,  int? speechToTextMs,  int? translationMs,  int? totalDurationMs,  String? speechToTextModel,  String? translationModel)?  $default,) {final _that = this;
switch (_that) {
case _Message() when $default != null:
return $default(_that.id,_that.conversationId,_that.timestamp,_that.isBaseLanguage,_that.originalText,_that.translatedText,_that.annotatedText,_that.speechToTextMs,_that.translationMs,_that.totalDurationMs,_that.speechToTextModel,_that.translationModel);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Message extends Message {
  const _Message({required this.id, required this.conversationId, required this.timestamp, required this.isBaseLanguage, required this.originalText, required this.translatedText, this.annotatedText = '', this.speechToTextMs, this.translationMs, this.totalDurationMs, this.speechToTextModel, this.translationModel}): super._();
  factory _Message.fromJson(Map<String, dynamic> json) => _$MessageFromJson(json);

@override final  String id;
@override final  String conversationId;
@override final  DateTime timestamp;
/// True when the spoken utterance was in the user's base language (`isUser`).
@override final  bool isBaseLanguage;
@override final  String originalText;
@override final  String translatedText;
@override@JsonKey() final  String annotatedText;
/// Time spent in milliseconds on the speech-to-text step.
@override final  int? speechToTextMs;
/// Time spent in milliseconds on the translation step.
@override final  int? translationMs;
/// Total time spent in milliseconds across all steps for this message.
@override final  int? totalDurationMs;
/// Display name of the model that performed Step 1 (Speech-to-Text).
@override final  String? speechToTextModel;
/// Display name of the model that performed Step 2 (Text Translation).
@override final  String? translationModel;

/// Create a copy of Message
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$MessageCopyWith<_Message> get copyWith => __$MessageCopyWithImpl<_Message>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$MessageToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _Message&&(identical(other.id, id) || other.id == id)&&(identical(other.conversationId, conversationId) || other.conversationId == conversationId)&&(identical(other.timestamp, timestamp) || other.timestamp == timestamp)&&(identical(other.isBaseLanguage, isBaseLanguage) || other.isBaseLanguage == isBaseLanguage)&&(identical(other.originalText, originalText) || other.originalText == originalText)&&(identical(other.translatedText, translatedText) || other.translatedText == translatedText)&&(identical(other.annotatedText, annotatedText) || other.annotatedText == annotatedText)&&(identical(other.speechToTextMs, speechToTextMs) || other.speechToTextMs == speechToTextMs)&&(identical(other.translationMs, translationMs) || other.translationMs == translationMs)&&(identical(other.totalDurationMs, totalDurationMs) || other.totalDurationMs == totalDurationMs)&&(identical(other.speechToTextModel, speechToTextModel) || other.speechToTextModel == speechToTextModel)&&(identical(other.translationModel, translationModel) || other.translationModel == translationModel));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,conversationId,timestamp,isBaseLanguage,originalText,translatedText,annotatedText,speechToTextMs,translationMs,totalDurationMs,speechToTextModel,translationModel);
}

@override
String toString() {
    return 'Message(id: $id, conversationId: $conversationId, timestamp: $timestamp, isBaseLanguage: $isBaseLanguage, originalText: $originalText, translatedText: $translatedText, annotatedText: $annotatedText, speechToTextMs: $speechToTextMs, translationMs: $translationMs, totalDurationMs: $totalDurationMs, speechToTextModel: $speechToTextModel, translationModel: $translationModel)';
}


}

/// @nodoc
abstract mixin class _$MessageCopyWith<$Res> implements $MessageCopyWith<$Res> {
  factory _$MessageCopyWith(_Message value, $Res Function(_Message) _then) = __$MessageCopyWithImpl;
@override @useResult
$Res call({
 String id, String conversationId, DateTime timestamp, bool isBaseLanguage, String originalText, String translatedText, String annotatedText, int? speechToTextMs, int? translationMs, int? totalDurationMs, String? speechToTextModel, String? translationModel
});




}
/// @nodoc
class __$MessageCopyWithImpl<$Res>
    implements _$MessageCopyWith<$Res> {
  __$MessageCopyWithImpl(this._self, this._then);

  final _Message _self;
  final $Res Function(_Message) _then;

/// Create a copy of Message
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? conversationId = null,Object? timestamp = null,Object? isBaseLanguage = null,Object? originalText = null,Object? translatedText = null,Object? annotatedText = null,Object? speechToTextMs = freezed,Object? translationMs = freezed,Object? totalDurationMs = freezed,Object? speechToTextModel = freezed,Object? translationModel = freezed,}) {
  return _then(_Message(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,conversationId: null == conversationId ? _self.conversationId : conversationId // ignore: cast_nullable_to_non_nullable
as String,timestamp: null == timestamp ? _self.timestamp : timestamp // ignore: cast_nullable_to_non_nullable
as DateTime,isBaseLanguage: null == isBaseLanguage ? _self.isBaseLanguage : isBaseLanguage // ignore: cast_nullable_to_non_nullable
as bool,originalText: null == originalText ? _self.originalText : originalText // ignore: cast_nullable_to_non_nullable
as String,translatedText: null == translatedText ? _self.translatedText : translatedText // ignore: cast_nullable_to_non_nullable
as String,annotatedText: null == annotatedText ? _self.annotatedText : annotatedText // ignore: cast_nullable_to_non_nullable
as String,speechToTextMs: freezed == speechToTextMs ? _self.speechToTextMs : speechToTextMs // ignore: cast_nullable_to_non_nullable
as int?,translationMs: freezed == translationMs ? _self.translationMs : translationMs // ignore: cast_nullable_to_non_nullable
as int?,totalDurationMs: freezed == totalDurationMs ? _self.totalDurationMs : totalDurationMs // ignore: cast_nullable_to_non_nullable
as int?,speechToTextModel: freezed == speechToTextModel ? _self.speechToTextModel : speechToTextModel // ignore: cast_nullable_to_non_nullable
as String?,translationModel: freezed == translationModel ? _self.translationModel : translationModel // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
