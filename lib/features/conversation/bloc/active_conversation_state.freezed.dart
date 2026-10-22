// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'active_conversation_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ActiveConversationState {

 Conversation? get conversation; List<Message> get messages; bool get isListening; bool get isLoading; double get amplitude; String? get streamingTranslatedText; bool? get streamingIsBaseLanguage; String? get error;
/// Create a copy of ActiveConversationState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ActiveConversationStateCopyWith<ActiveConversationState> get copyWith => _$ActiveConversationStateCopyWithImpl<ActiveConversationState>(this as ActiveConversationState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ActiveConversationState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ActiveConversationState&&(identical(other.conversation, _this.conversation) || other.conversation == _this.conversation)&&const DeepCollectionEquality().equals(other.messages, _this.messages)&&(identical(other.isListening, _this.isListening) || other.isListening == _this.isListening)&&(identical(other.isLoading, _this.isLoading) || other.isLoading == _this.isLoading)&&(identical(other.amplitude, _this.amplitude) || other.amplitude == _this.amplitude)&&(identical(other.streamingTranslatedText, _this.streamingTranslatedText) || other.streamingTranslatedText == _this.streamingTranslatedText)&&(identical(other.streamingIsBaseLanguage, _this.streamingIsBaseLanguage) || other.streamingIsBaseLanguage == _this.streamingIsBaseLanguage)&&(identical(other.error, _this.error) || other.error == _this.error));
}


@override
int get hashCode {
  final _this = this as ActiveConversationState;
  return Object.hash(runtimeType,_this.conversation,const DeepCollectionEquality().hash(_this.messages),_this.isListening,_this.isLoading,_this.amplitude,_this.streamingTranslatedText,_this.streamingIsBaseLanguage,_this.error);
}

@override
String toString() {
  final _this = this as ActiveConversationState;
  return 'ActiveConversationState(conversation: ${_this.conversation}, messages: ${_this.messages}, isListening: ${_this.isListening}, isLoading: ${_this.isLoading}, amplitude: ${_this.amplitude}, streamingTranslatedText: ${_this.streamingTranslatedText}, streamingIsBaseLanguage: ${_this.streamingIsBaseLanguage}, error: ${_this.error})';
}


}

/// @nodoc
abstract mixin class $ActiveConversationStateCopyWith<$Res>  {
  factory $ActiveConversationStateCopyWith(ActiveConversationState value, $Res Function(ActiveConversationState) _then) = _$ActiveConversationStateCopyWithImpl;
@useResult
$Res call({
 Conversation? conversation, List<Message> messages, bool isListening, bool isLoading, double amplitude, String? streamingTranslatedText, bool? streamingIsBaseLanguage, String? error
});


$ConversationCopyWith<$Res>? get conversation;

}
/// @nodoc
class _$ActiveConversationStateCopyWithImpl<$Res>
    implements $ActiveConversationStateCopyWith<$Res> {
  _$ActiveConversationStateCopyWithImpl(this._self, this._then);

  final ActiveConversationState _self;
  final $Res Function(ActiveConversationState) _then;

/// Create a copy of ActiveConversationState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? conversation = freezed,Object? messages = null,Object? isListening = null,Object? isLoading = null,Object? amplitude = null,Object? streamingTranslatedText = freezed,Object? streamingIsBaseLanguage = freezed,Object? error = freezed,}) {
  return _then(ActiveConversationState(
conversation: freezed == conversation ? _self.conversation : conversation // ignore: cast_nullable_to_non_nullable
as Conversation?,messages: null == messages ? _self.messages : messages // ignore: cast_nullable_to_non_nullable
as List<Message>,isListening: null == isListening ? _self.isListening : isListening // ignore: cast_nullable_to_non_nullable
as bool,isLoading: null == isLoading ? _self.isLoading : isLoading // ignore: cast_nullable_to_non_nullable
as bool,amplitude: null == amplitude ? _self.amplitude : amplitude // ignore: cast_nullable_to_non_nullable
as double,streamingTranslatedText: freezed == streamingTranslatedText ? _self.streamingTranslatedText : streamingTranslatedText // ignore: cast_nullable_to_non_nullable
as String?,streamingIsBaseLanguage: freezed == streamingIsBaseLanguage ? _self.streamingIsBaseLanguage : streamingIsBaseLanguage // ignore: cast_nullable_to_non_nullable
as bool?,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}
/// Create a copy of ActiveConversationState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConversationCopyWith<$Res>? get conversation {
    if (_self.conversation == null) {
    return null;
  }

  return $ConversationCopyWith<$Res>(_self.conversation!, (value) {
    return _then(_self.copyWith(conversation: value));
  });
}
}


/// Adds pattern-matching-related methods to [ActiveConversationState].
extension ActiveConversationStatePatterns on ActiveConversationState {
@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ActiveConversationState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ActiveConversationState() when $default != null:
return $default(_that);case _:
  return orElse();

}
}

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ActiveConversationState value)  $default,){
final _that = this;
switch (_that) {
case _ActiveConversationState():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ActiveConversationState value)?  $default,){
final _that = this;
switch (_that) {
case _ActiveConversationState() when $default != null:
return $default(_that);case _:
  return null;

}
}

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( Conversation? conversation,  List<Message> messages,  bool isListening,  bool isLoading,  double amplitude,  String? streamingTranslatedText,  bool? streamingIsBaseLanguage,  String? error)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ActiveConversationState() when $default != null:
return $default(_that.conversation,_that.messages,_that.isListening,_that.isLoading,_that.amplitude,_that.streamingTranslatedText,_that.streamingIsBaseLanguage,_that.error);case _:
  return orElse();

}
}

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( Conversation? conversation,  List<Message> messages,  bool isListening,  bool isLoading,  double amplitude,  String? streamingTranslatedText,  bool? streamingIsBaseLanguage,  String? error)  $default,) {final _that = this;
switch (_that) {
case _ActiveConversationState():
return $default(_that.conversation,_that.messages,_that.isListening,_that.isLoading,_that.amplitude,_that.streamingTranslatedText,_that.streamingIsBaseLanguage,_that.error);case _:
  throw StateError('Unexpected subclass');

}
}

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( Conversation? conversation,  List<Message> messages,  bool isListening,  bool isLoading,  double amplitude,  String? streamingTranslatedText,  bool? streamingIsBaseLanguage,  String? error)?  $default,) {final _that = this;
switch (_that) {
case _ActiveConversationState() when $default != null:
return $default(_that.conversation,_that.messages,_that.isListening,_that.isLoading,_that.amplitude,_that.streamingTranslatedText,_that.streamingIsBaseLanguage,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class _ActiveConversationState extends ActiveConversationState {
  const _ActiveConversationState({this.conversation,  List<Message> messages = const <Message>[], this.isListening = false, this.isLoading = false, this.amplitude = 0.0, this.streamingTranslatedText, this.streamingIsBaseLanguage, this.error}): _messages = messages,super._();
  

@override final  Conversation? conversation;
 final  List<Message> _messages;
@override@JsonKey() List<Message> get messages {
  if (_messages is EqualUnmodifiableListView) return _messages;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_messages);
}

@override@JsonKey() final  bool isListening;
@override@JsonKey() final  bool isLoading;
@override@JsonKey() final  double amplitude;
@override final  String? streamingTranslatedText;
@override final  bool? streamingIsBaseLanguage;
@override final  String? error;

/// Create a copy of ActiveConversationState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ActiveConversationStateCopyWith<_ActiveConversationState> get copyWith => __$ActiveConversationStateCopyWithImpl<_ActiveConversationState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ActiveConversationState&&(identical(other.conversation, conversation) || other.conversation == conversation)&&const DeepCollectionEquality().equals(other._messages, _messages)&&(identical(other.isListening, isListening) || other.isListening == isListening)&&(identical(other.isLoading, isLoading) || other.isLoading == isLoading)&&(identical(other.amplitude, amplitude) || other.amplitude == amplitude)&&(identical(other.streamingTranslatedText, streamingTranslatedText) || other.streamingTranslatedText == streamingTranslatedText)&&(identical(other.streamingIsBaseLanguage, streamingIsBaseLanguage) || other.streamingIsBaseLanguage == streamingIsBaseLanguage)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,conversation,const DeepCollectionEquality().hash(_messages),isListening,isLoading,amplitude,streamingTranslatedText,streamingIsBaseLanguage,error);
}

@override
String toString() {
    return 'ActiveConversationState(conversation: $conversation, messages: $messages, isListening: $isListening, isLoading: $isLoading, amplitude: $amplitude, streamingTranslatedText: $streamingTranslatedText, streamingIsBaseLanguage: $streamingIsBaseLanguage, error: $error)';
}


}

/// @nodoc
abstract mixin class _$ActiveConversationStateCopyWith<$Res> implements $ActiveConversationStateCopyWith<$Res> {
  factory _$ActiveConversationStateCopyWith(_ActiveConversationState value, $Res Function(_ActiveConversationState) _then) = __$ActiveConversationStateCopyWithImpl;
@override @useResult
$Res call({
 Conversation? conversation, List<Message> messages, bool isListening, bool isLoading, double amplitude, String? streamingTranslatedText, bool? streamingIsBaseLanguage, String? error
});


@override $ConversationCopyWith<$Res>? get conversation;

}
/// @nodoc
class __$ActiveConversationStateCopyWithImpl<$Res>
    implements _$ActiveConversationStateCopyWith<$Res> {
  __$ActiveConversationStateCopyWithImpl(this._self, this._then);

  final _ActiveConversationState _self;
  final $Res Function(_ActiveConversationState) _then;

/// Create a copy of ActiveConversationState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? conversation = freezed,Object? messages = null,Object? isListening = null,Object? isLoading = null,Object? amplitude = null,Object? streamingTranslatedText = freezed,Object? streamingIsBaseLanguage = freezed,Object? error = freezed,}) {
  return _then(_ActiveConversationState(
conversation: freezed == conversation ? _self.conversation : conversation // ignore: cast_nullable_to_non_nullable
as Conversation?,messages: null == messages ? _self._messages : messages // ignore: cast_nullable_to_non_nullable
as List<Message>,isListening: null == isListening ? _self.isListening : isListening // ignore: cast_nullable_to_non_nullable
as bool,isLoading: null == isLoading ? _self.isLoading : isLoading // ignore: cast_nullable_to_non_nullable
as bool,amplitude: null == amplitude ? _self.amplitude : amplitude // ignore: cast_nullable_to_non_nullable
as double,streamingTranslatedText: freezed == streamingTranslatedText ? _self.streamingTranslatedText : streamingTranslatedText // ignore: cast_nullable_to_non_nullable
as String?,streamingIsBaseLanguage: freezed == streamingIsBaseLanguage ? _self.streamingIsBaseLanguage : streamingIsBaseLanguage // ignore: cast_nullable_to_non_nullable
as bool?,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

/// Create a copy of ActiveConversationState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConversationCopyWith<$Res>? get conversation {
    if (_self.conversation == null) {
    return null;
  }

  return $ConversationCopyWith<$Res>(_self.conversation!, (value) {
    return _then(_self.copyWith(conversation: value));
  });
}
}

// dart format on
