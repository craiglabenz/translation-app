// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'model_manager.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ModelDownloadState {

 bool get isInstalled; bool get isDownloading; double get progress; String get modelId; String? get error; Map<String, bool> get installedWhisperModels; bool get isWhisperDownloading; double get whisperProgress; String get whisperModelId; String? get whisperError;
/// Create a copy of ModelDownloadState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelDownloadStateCopyWith<ModelDownloadState> get copyWith => _$ModelDownloadStateCopyWithImpl<ModelDownloadState>(this as ModelDownloadState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModelDownloadState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelDownloadState&&(identical(other.isInstalled, _this.isInstalled) || other.isInstalled == _this.isInstalled)&&(identical(other.isDownloading, _this.isDownloading) || other.isDownloading == _this.isDownloading)&&(identical(other.progress, _this.progress) || other.progress == _this.progress)&&(identical(other.modelId, _this.modelId) || other.modelId == _this.modelId)&&(identical(other.error, _this.error) || other.error == _this.error)&&const DeepCollectionEquality().equals(other.installedWhisperModels, _this.installedWhisperModels)&&(identical(other.isWhisperDownloading, _this.isWhisperDownloading) || other.isWhisperDownloading == _this.isWhisperDownloading)&&(identical(other.whisperProgress, _this.whisperProgress) || other.whisperProgress == _this.whisperProgress)&&(identical(other.whisperModelId, _this.whisperModelId) || other.whisperModelId == _this.whisperModelId)&&(identical(other.whisperError, _this.whisperError) || other.whisperError == _this.whisperError));
}


@override
int get hashCode {
  final _this = this as ModelDownloadState;
  return Object.hash(runtimeType,_this.isInstalled,_this.isDownloading,_this.progress,_this.modelId,_this.error,const DeepCollectionEquality().hash(_this.installedWhisperModels),_this.isWhisperDownloading,_this.whisperProgress,_this.whisperModelId,_this.whisperError);
}

@override
String toString() {
  final _this = this as ModelDownloadState;
  return 'ModelDownloadState(isInstalled: ${_this.isInstalled}, isDownloading: ${_this.isDownloading}, progress: ${_this.progress}, modelId: ${_this.modelId}, error: ${_this.error}, installedWhisperModels: ${_this.installedWhisperModels}, isWhisperDownloading: ${_this.isWhisperDownloading}, whisperProgress: ${_this.whisperProgress}, whisperModelId: ${_this.whisperModelId}, whisperError: ${_this.whisperError})';
}


}

/// @nodoc
abstract mixin class $ModelDownloadStateCopyWith<$Res>  {
  factory $ModelDownloadStateCopyWith(ModelDownloadState value, $Res Function(ModelDownloadState) _then) = _$ModelDownloadStateCopyWithImpl;
@useResult
$Res call({
 bool isInstalled, bool isDownloading, double progress, String modelId, String? error, Map<String, bool> installedWhisperModels, bool isWhisperDownloading, double whisperProgress, String whisperModelId, String? whisperError
});




}
/// @nodoc
class _$ModelDownloadStateCopyWithImpl<$Res>
    implements $ModelDownloadStateCopyWith<$Res> {
  _$ModelDownloadStateCopyWithImpl(this._self, this._then);

  final ModelDownloadState _self;
  final $Res Function(ModelDownloadState) _then;

/// Create a copy of ModelDownloadState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? isInstalled = null,Object? isDownloading = null,Object? progress = null,Object? modelId = null,Object? error = freezed,Object? installedWhisperModels = null,Object? isWhisperDownloading = null,Object? whisperProgress = null,Object? whisperModelId = null,Object? whisperError = freezed,}) {
  return _then(ModelDownloadState(
isInstalled: null == isInstalled ? _self.isInstalled : isInstalled // ignore: cast_nullable_to_non_nullable
as bool,isDownloading: null == isDownloading ? _self.isDownloading : isDownloading // ignore: cast_nullable_to_non_nullable
as bool,progress: null == progress ? _self.progress : progress // ignore: cast_nullable_to_non_nullable
as double,modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as String,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,installedWhisperModels: null == installedWhisperModels ? _self.installedWhisperModels : installedWhisperModels // ignore: cast_nullable_to_non_nullable
as Map<String, bool>,isWhisperDownloading: null == isWhisperDownloading ? _self.isWhisperDownloading : isWhisperDownloading // ignore: cast_nullable_to_non_nullable
as bool,whisperProgress: null == whisperProgress ? _self.whisperProgress : whisperProgress // ignore: cast_nullable_to_non_nullable
as double,whisperModelId: null == whisperModelId ? _self.whisperModelId : whisperModelId // ignore: cast_nullable_to_non_nullable
as String,whisperError: freezed == whisperError ? _self.whisperError : whisperError // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [ModelDownloadState].
extension ModelDownloadStatePatterns on ModelDownloadState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ModelDownloadState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ModelDownloadState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ModelDownloadState value)  $default,){
final _that = this;
switch (_that) {
case _ModelDownloadState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ModelDownloadState value)?  $default,){
final _that = this;
switch (_that) {
case _ModelDownloadState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( bool isInstalled,  bool isDownloading,  double progress,  String modelId,  String? error,  Map<String, bool> installedWhisperModels,  bool isWhisperDownloading,  double whisperProgress,  String whisperModelId,  String? whisperError)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ModelDownloadState() when $default != null:
return $default(_that.isInstalled,_that.isDownloading,_that.progress,_that.modelId,_that.error,_that.installedWhisperModels,_that.isWhisperDownloading,_that.whisperProgress,_that.whisperModelId,_that.whisperError);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( bool isInstalled,  bool isDownloading,  double progress,  String modelId,  String? error,  Map<String, bool> installedWhisperModels,  bool isWhisperDownloading,  double whisperProgress,  String whisperModelId,  String? whisperError)  $default,) {final _that = this;
switch (_that) {
case _ModelDownloadState():
return $default(_that.isInstalled,_that.isDownloading,_that.progress,_that.modelId,_that.error,_that.installedWhisperModels,_that.isWhisperDownloading,_that.whisperProgress,_that.whisperModelId,_that.whisperError);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( bool isInstalled,  bool isDownloading,  double progress,  String modelId,  String? error,  Map<String, bool> installedWhisperModels,  bool isWhisperDownloading,  double whisperProgress,  String whisperModelId,  String? whisperError)?  $default,) {final _that = this;
switch (_that) {
case _ModelDownloadState() when $default != null:
return $default(_that.isInstalled,_that.isDownloading,_that.progress,_that.modelId,_that.error,_that.installedWhisperModels,_that.isWhisperDownloading,_that.whisperProgress,_that.whisperModelId,_that.whisperError);case _:
  return null;

}
}

}

/// @nodoc


class _ModelDownloadState extends ModelDownloadState {
  const _ModelDownloadState({this.isInstalled = false, this.isDownloading = false, this.progress = 0.0, this.modelId = 'gemma-4-E2B-it.litertlm', this.error, Map<String, bool> installedWhisperModels = const <String, bool>{}, this.isWhisperDownloading = false, this.whisperProgress = 0.0, this.whisperModelId = AppSettings.defaultOnDeviceSttModelId, this.whisperError}): _installedWhisperModels = installedWhisperModels,super._();
  

@override@JsonKey() final  bool isInstalled;
@override@JsonKey() final  bool isDownloading;
@override@JsonKey() final  double progress;
@override@JsonKey() final  String modelId;
@override final  String? error;
 final  Map<String, bool> _installedWhisperModels;
@override@JsonKey() Map<String, bool> get installedWhisperModels {
  if (_installedWhisperModels is EqualUnmodifiableMapView) return _installedWhisperModels;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_installedWhisperModels);
}

@override@JsonKey() final  bool isWhisperDownloading;
@override@JsonKey() final  double whisperProgress;
@override@JsonKey() final  String whisperModelId;
@override final  String? whisperError;

/// Create a copy of ModelDownloadState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModelDownloadStateCopyWith<_ModelDownloadState> get copyWith => __$ModelDownloadStateCopyWithImpl<_ModelDownloadState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModelDownloadState&&(identical(other.isInstalled, isInstalled) || other.isInstalled == isInstalled)&&(identical(other.isDownloading, isDownloading) || other.isDownloading == isDownloading)&&(identical(other.progress, progress) || other.progress == progress)&&(identical(other.modelId, modelId) || other.modelId == modelId)&&(identical(other.error, error) || other.error == error)&&const DeepCollectionEquality().equals(other._installedWhisperModels, _installedWhisperModels)&&(identical(other.isWhisperDownloading, isWhisperDownloading) || other.isWhisperDownloading == isWhisperDownloading)&&(identical(other.whisperProgress, whisperProgress) || other.whisperProgress == whisperProgress)&&(identical(other.whisperModelId, whisperModelId) || other.whisperModelId == whisperModelId)&&(identical(other.whisperError, whisperError) || other.whisperError == whisperError));
}


@override
int get hashCode {
    return Object.hash(runtimeType,isInstalled,isDownloading,progress,modelId,error,const DeepCollectionEquality().hash(_installedWhisperModels),isWhisperDownloading,whisperProgress,whisperModelId,whisperError);
}

@override
String toString() {
    return 'ModelDownloadState(isInstalled: $isInstalled, isDownloading: $isDownloading, progress: $progress, modelId: $modelId, error: $error, installedWhisperModels: $installedWhisperModels, isWhisperDownloading: $isWhisperDownloading, whisperProgress: $whisperProgress, whisperModelId: $whisperModelId, whisperError: $whisperError)';
}


}

/// @nodoc
abstract mixin class _$ModelDownloadStateCopyWith<$Res> implements $ModelDownloadStateCopyWith<$Res> {
  factory _$ModelDownloadStateCopyWith(_ModelDownloadState value, $Res Function(_ModelDownloadState) _then) = __$ModelDownloadStateCopyWithImpl;
@override @useResult
$Res call({
 bool isInstalled, bool isDownloading, double progress, String modelId, String? error, Map<String, bool> installedWhisperModels, bool isWhisperDownloading, double whisperProgress, String whisperModelId, String? whisperError
});




}
/// @nodoc
class __$ModelDownloadStateCopyWithImpl<$Res>
    implements _$ModelDownloadStateCopyWith<$Res> {
  __$ModelDownloadStateCopyWithImpl(this._self, this._then);

  final _ModelDownloadState _self;
  final $Res Function(_ModelDownloadState) _then;

/// Create a copy of ModelDownloadState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? isInstalled = null,Object? isDownloading = null,Object? progress = null,Object? modelId = null,Object? error = freezed,Object? installedWhisperModels = null,Object? isWhisperDownloading = null,Object? whisperProgress = null,Object? whisperModelId = null,Object? whisperError = freezed,}) {
  return _then(_ModelDownloadState(
isInstalled: null == isInstalled ? _self.isInstalled : isInstalled // ignore: cast_nullable_to_non_nullable
as bool,isDownloading: null == isDownloading ? _self.isDownloading : isDownloading // ignore: cast_nullable_to_non_nullable
as bool,progress: null == progress ? _self.progress : progress // ignore: cast_nullable_to_non_nullable
as double,modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as String,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,installedWhisperModels: null == installedWhisperModels ? _self._installedWhisperModels : installedWhisperModels // ignore: cast_nullable_to_non_nullable
as Map<String, bool>,isWhisperDownloading: null == isWhisperDownloading ? _self.isWhisperDownloading : isWhisperDownloading // ignore: cast_nullable_to_non_nullable
as bool,whisperProgress: null == whisperProgress ? _self.whisperProgress : whisperProgress // ignore: cast_nullable_to_non_nullable
as double,whisperModelId: null == whisperModelId ? _self.whisperModelId : whisperModelId // ignore: cast_nullable_to_non_nullable
as String,whisperError: freezed == whisperError ? _self.whisperError : whisperError // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
