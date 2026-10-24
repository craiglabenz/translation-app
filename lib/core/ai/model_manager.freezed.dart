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

 bool get isInstalled; bool get isDownloading; double get progress; String get modelId; String? get error;
/// Create a copy of ModelDownloadState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelDownloadStateCopyWith<ModelDownloadState> get copyWith => _$ModelDownloadStateCopyWithImpl<ModelDownloadState>(this as ModelDownloadState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModelDownloadState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelDownloadState&&(identical(other.isInstalled, _this.isInstalled) || other.isInstalled == _this.isInstalled)&&(identical(other.isDownloading, _this.isDownloading) || other.isDownloading == _this.isDownloading)&&(identical(other.progress, _this.progress) || other.progress == _this.progress)&&(identical(other.modelId, _this.modelId) || other.modelId == _this.modelId)&&(identical(other.error, _this.error) || other.error == _this.error));
}


@override
int get hashCode {
  final _this = this as ModelDownloadState;
  return Object.hash(runtimeType,_this.isInstalled,_this.isDownloading,_this.progress,_this.modelId,_this.error);
}

@override
String toString() {
  final _this = this as ModelDownloadState;
  return 'ModelDownloadState(isInstalled: ${_this.isInstalled}, isDownloading: ${_this.isDownloading}, progress: ${_this.progress}, modelId: ${_this.modelId}, error: ${_this.error})';
}


}

/// @nodoc
abstract mixin class $ModelDownloadStateCopyWith<$Res>  {
  factory $ModelDownloadStateCopyWith(ModelDownloadState value, $Res Function(ModelDownloadState) _then) = _$ModelDownloadStateCopyWithImpl;
@useResult
$Res call({
 bool isInstalled, bool isDownloading, double progress, String modelId, String? error
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
@pragma('vm:prefer-inline') @override $Res call({Object? isInstalled = null,Object? isDownloading = null,Object? progress = null,Object? modelId = null,Object? error = freezed,}) {
  return _then(ModelDownloadState(
isInstalled: null == isInstalled ? _self.isInstalled : isInstalled // ignore: cast_nullable_to_non_nullable
as bool,isDownloading: null == isDownloading ? _self.isDownloading : isDownloading // ignore: cast_nullable_to_non_nullable
as bool,progress: null == progress ? _self.progress : progress // ignore: cast_nullable_to_non_nullable
as double,modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as String,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( bool isInstalled,  bool isDownloading,  double progress,  String modelId,  String? error)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ModelDownloadState() when $default != null:
return $default(_that.isInstalled,_that.isDownloading,_that.progress,_that.modelId,_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( bool isInstalled,  bool isDownloading,  double progress,  String modelId,  String? error)  $default,) {final _that = this;
switch (_that) {
case _ModelDownloadState():
return $default(_that.isInstalled,_that.isDownloading,_that.progress,_that.modelId,_that.error);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( bool isInstalled,  bool isDownloading,  double progress,  String modelId,  String? error)?  $default,) {final _that = this;
switch (_that) {
case _ModelDownloadState() when $default != null:
return $default(_that.isInstalled,_that.isDownloading,_that.progress,_that.modelId,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class _ModelDownloadState extends ModelDownloadState {
  const _ModelDownloadState({this.isInstalled = false, this.isDownloading = false, this.progress = 0.0, this.modelId = 'gemma-4-E2B-it.litertlm', this.error}): super._();
  

@override@JsonKey() final  bool isInstalled;
@override@JsonKey() final  bool isDownloading;
@override@JsonKey() final  double progress;
@override@JsonKey() final  String modelId;
@override final  String? error;

/// Create a copy of ModelDownloadState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModelDownloadStateCopyWith<_ModelDownloadState> get copyWith => __$ModelDownloadStateCopyWithImpl<_ModelDownloadState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModelDownloadState&&(identical(other.isInstalled, isInstalled) || other.isInstalled == isInstalled)&&(identical(other.isDownloading, isDownloading) || other.isDownloading == isDownloading)&&(identical(other.progress, progress) || other.progress == progress)&&(identical(other.modelId, modelId) || other.modelId == modelId)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,isInstalled,isDownloading,progress,modelId,error);
}

@override
String toString() {
    return 'ModelDownloadState(isInstalled: $isInstalled, isDownloading: $isDownloading, progress: $progress, modelId: $modelId, error: $error)';
}


}

/// @nodoc
abstract mixin class _$ModelDownloadStateCopyWith<$Res> implements $ModelDownloadStateCopyWith<$Res> {
  factory _$ModelDownloadStateCopyWith(_ModelDownloadState value, $Res Function(_ModelDownloadState) _then) = __$ModelDownloadStateCopyWithImpl;
@override @useResult
$Res call({
 bool isInstalled, bool isDownloading, double progress, String modelId, String? error
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
@override @pragma('vm:prefer-inline') $Res call({Object? isInstalled = null,Object? isDownloading = null,Object? progress = null,Object? modelId = null,Object? error = freezed,}) {
  return _then(_ModelDownloadState(
isInstalled: null == isInstalled ? _self.isInstalled : isInstalled // ignore: cast_nullable_to_non_nullable
as bool,isDownloading: null == isDownloading ? _self.isDownloading : isDownloading // ignore: cast_nullable_to_non_nullable
as bool,progress: null == progress ? _self.progress : progress // ignore: cast_nullable_to_non_nullable
as double,modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as String,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
