// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'translation_engine.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$TranslationResult {

 String get sourceLanguage; String get translatedText; String? get originalText; int? get speechToTextMs; int? get translationMs; int? get totalDurationMs; String? get speechToTextModel; String? get translationModel;
/// Create a copy of TranslationResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TranslationResultCopyWith<TranslationResult> get copyWith => _$TranslationResultCopyWithImpl<TranslationResult>(this as TranslationResult, _$identity);

  /// Serializes this TranslationResult to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as TranslationResult;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TranslationResult&&(identical(other.sourceLanguage, _this.sourceLanguage) || other.sourceLanguage == _this.sourceLanguage)&&(identical(other.translatedText, _this.translatedText) || other.translatedText == _this.translatedText)&&(identical(other.originalText, _this.originalText) || other.originalText == _this.originalText)&&(identical(other.speechToTextMs, _this.speechToTextMs) || other.speechToTextMs == _this.speechToTextMs)&&(identical(other.translationMs, _this.translationMs) || other.translationMs == _this.translationMs)&&(identical(other.totalDurationMs, _this.totalDurationMs) || other.totalDurationMs == _this.totalDurationMs)&&(identical(other.speechToTextModel, _this.speechToTextModel) || other.speechToTextModel == _this.speechToTextModel)&&(identical(other.translationModel, _this.translationModel) || other.translationModel == _this.translationModel));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as TranslationResult;
  return Object.hash(runtimeType,_this.sourceLanguage,_this.translatedText,_this.originalText,_this.speechToTextMs,_this.translationMs,_this.totalDurationMs,_this.speechToTextModel,_this.translationModel);
}

@override
String toString() {
  final _this = this as TranslationResult;
  return 'TranslationResult(sourceLanguage: ${_this.sourceLanguage}, translatedText: ${_this.translatedText}, originalText: ${_this.originalText}, speechToTextMs: ${_this.speechToTextMs}, translationMs: ${_this.translationMs}, totalDurationMs: ${_this.totalDurationMs}, speechToTextModel: ${_this.speechToTextModel}, translationModel: ${_this.translationModel})';
}


}

/// @nodoc
abstract mixin class $TranslationResultCopyWith<$Res>  {
  factory $TranslationResultCopyWith(TranslationResult value, $Res Function(TranslationResult) _then) = _$TranslationResultCopyWithImpl;
@useResult
$Res call({
 String sourceLanguage, String translatedText, String? originalText, int? speechToTextMs, int? translationMs, int? totalDurationMs, String? speechToTextModel, String? translationModel
});




}
/// @nodoc
class _$TranslationResultCopyWithImpl<$Res>
    implements $TranslationResultCopyWith<$Res> {
  _$TranslationResultCopyWithImpl(this._self, this._then);

  final TranslationResult _self;
  final $Res Function(TranslationResult) _then;

/// Create a copy of TranslationResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? sourceLanguage = null,Object? translatedText = null,Object? originalText = freezed,Object? speechToTextMs = freezed,Object? translationMs = freezed,Object? totalDurationMs = freezed,Object? speechToTextModel = freezed,Object? translationModel = freezed,}) {
  return _then(TranslationResult(
sourceLanguage: null == sourceLanguage ? _self.sourceLanguage : sourceLanguage // ignore: cast_nullable_to_non_nullable
as String,translatedText: null == translatedText ? _self.translatedText : translatedText // ignore: cast_nullable_to_non_nullable
as String,originalText: freezed == originalText ? _self.originalText : originalText // ignore: cast_nullable_to_non_nullable
as String?,speechToTextMs: freezed == speechToTextMs ? _self.speechToTextMs : speechToTextMs // ignore: cast_nullable_to_non_nullable
as int?,translationMs: freezed == translationMs ? _self.translationMs : translationMs // ignore: cast_nullable_to_non_nullable
as int?,totalDurationMs: freezed == totalDurationMs ? _self.totalDurationMs : totalDurationMs // ignore: cast_nullable_to_non_nullable
as int?,speechToTextModel: freezed == speechToTextModel ? _self.speechToTextModel : speechToTextModel // ignore: cast_nullable_to_non_nullable
as String?,translationModel: freezed == translationModel ? _self.translationModel : translationModel // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [TranslationResult].
extension TranslationResultPatterns on TranslationResult {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TranslationResult value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TranslationResult() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TranslationResult value)  $default,){
final _that = this;
switch (_that) {
case _TranslationResult():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TranslationResult value)?  $default,){
final _that = this;
switch (_that) {
case _TranslationResult() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String sourceLanguage,  String translatedText,  String? originalText,  int? speechToTextMs,  int? translationMs,  int? totalDurationMs,  String? speechToTextModel,  String? translationModel)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TranslationResult() when $default != null:
return $default(_that.sourceLanguage,_that.translatedText,_that.originalText,_that.speechToTextMs,_that.translationMs,_that.totalDurationMs,_that.speechToTextModel,_that.translationModel);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String sourceLanguage,  String translatedText,  String? originalText,  int? speechToTextMs,  int? translationMs,  int? totalDurationMs,  String? speechToTextModel,  String? translationModel)  $default,) {final _that = this;
switch (_that) {
case _TranslationResult():
return $default(_that.sourceLanguage,_that.translatedText,_that.originalText,_that.speechToTextMs,_that.translationMs,_that.totalDurationMs,_that.speechToTextModel,_that.translationModel);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String sourceLanguage,  String translatedText,  String? originalText,  int? speechToTextMs,  int? translationMs,  int? totalDurationMs,  String? speechToTextModel,  String? translationModel)?  $default,) {final _that = this;
switch (_that) {
case _TranslationResult() when $default != null:
return $default(_that.sourceLanguage,_that.translatedText,_that.originalText,_that.speechToTextMs,_that.translationMs,_that.totalDurationMs,_that.speechToTextModel,_that.translationModel);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _TranslationResult implements TranslationResult {
  const _TranslationResult({required this.sourceLanguage, required this.translatedText, this.originalText, this.speechToTextMs, this.translationMs, this.totalDurationMs, this.speechToTextModel, this.translationModel});
  factory _TranslationResult.fromJson(Map<String, dynamic> json) => _$TranslationResultFromJson(json);

@override final  String sourceLanguage;
@override final  String translatedText;
@override final  String? originalText;
@override final  int? speechToTextMs;
@override final  int? translationMs;
@override final  int? totalDurationMs;
@override final  String? speechToTextModel;
@override final  String? translationModel;

/// Create a copy of TranslationResult
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TranslationResultCopyWith<_TranslationResult> get copyWith => __$TranslationResultCopyWithImpl<_TranslationResult>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$TranslationResultToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _TranslationResult&&(identical(other.sourceLanguage, sourceLanguage) || other.sourceLanguage == sourceLanguage)&&(identical(other.translatedText, translatedText) || other.translatedText == translatedText)&&(identical(other.originalText, originalText) || other.originalText == originalText)&&(identical(other.speechToTextMs, speechToTextMs) || other.speechToTextMs == speechToTextMs)&&(identical(other.translationMs, translationMs) || other.translationMs == translationMs)&&(identical(other.totalDurationMs, totalDurationMs) || other.totalDurationMs == totalDurationMs)&&(identical(other.speechToTextModel, speechToTextModel) || other.speechToTextModel == speechToTextModel)&&(identical(other.translationModel, translationModel) || other.translationModel == translationModel));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,sourceLanguage,translatedText,originalText,speechToTextMs,translationMs,totalDurationMs,speechToTextModel,translationModel);
}

@override
String toString() {
    return 'TranslationResult(sourceLanguage: $sourceLanguage, translatedText: $translatedText, originalText: $originalText, speechToTextMs: $speechToTextMs, translationMs: $translationMs, totalDurationMs: $totalDurationMs, speechToTextModel: $speechToTextModel, translationModel: $translationModel)';
}


}

/// @nodoc
abstract mixin class _$TranslationResultCopyWith<$Res> implements $TranslationResultCopyWith<$Res> {
  factory _$TranslationResultCopyWith(_TranslationResult value, $Res Function(_TranslationResult) _then) = __$TranslationResultCopyWithImpl;
@override @useResult
$Res call({
 String sourceLanguage, String translatedText, String? originalText, int? speechToTextMs, int? translationMs, int? totalDurationMs, String? speechToTextModel, String? translationModel
});




}
/// @nodoc
class __$TranslationResultCopyWithImpl<$Res>
    implements _$TranslationResultCopyWith<$Res> {
  __$TranslationResultCopyWithImpl(this._self, this._then);

  final _TranslationResult _self;
  final $Res Function(_TranslationResult) _then;

/// Create a copy of TranslationResult
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? sourceLanguage = null,Object? translatedText = null,Object? originalText = freezed,Object? speechToTextMs = freezed,Object? translationMs = freezed,Object? totalDurationMs = freezed,Object? speechToTextModel = freezed,Object? translationModel = freezed,}) {
  return _then(_TranslationResult(
sourceLanguage: null == sourceLanguage ? _self.sourceLanguage : sourceLanguage // ignore: cast_nullable_to_non_nullable
as String,translatedText: null == translatedText ? _self.translatedText : translatedText // ignore: cast_nullable_to_non_nullable
as String,originalText: freezed == originalText ? _self.originalText : originalText // ignore: cast_nullable_to_non_nullable
as String?,speechToTextMs: freezed == speechToTextMs ? _self.speechToTextMs : speechToTextMs // ignore: cast_nullable_to_non_nullable
as int?,translationMs: freezed == translationMs ? _self.translationMs : translationMs // ignore: cast_nullable_to_non_nullable
as int?,totalDurationMs: freezed == totalDurationMs ? _self.totalDurationMs : totalDurationMs // ignore: cast_nullable_to_non_nullable
as int?,speechToTextModel: freezed == speechToTextModel ? _self.speechToTextModel : speechToTextModel // ignore: cast_nullable_to_non_nullable
as String?,translationModel: freezed == translationModel ? _self.translationModel : translationModel // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
