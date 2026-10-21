// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'settings_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SettingsState {

 AppSettings get settings; ExchangeRateCache? get exchangeRate; bool get isLoading; bool get isRefreshingRates; String? get error;
/// Create a copy of SettingsState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SettingsStateCopyWith<SettingsState> get copyWith => _$SettingsStateCopyWithImpl<SettingsState>(this as SettingsState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SettingsState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SettingsState&&(identical(other.settings, _this.settings) || other.settings == _this.settings)&&(identical(other.exchangeRate, _this.exchangeRate) || other.exchangeRate == _this.exchangeRate)&&(identical(other.isLoading, _this.isLoading) || other.isLoading == _this.isLoading)&&(identical(other.isRefreshingRates, _this.isRefreshingRates) || other.isRefreshingRates == _this.isRefreshingRates)&&(identical(other.error, _this.error) || other.error == _this.error));
}


@override
int get hashCode {
  final _this = this as SettingsState;
  return Object.hash(runtimeType,_this.settings,_this.exchangeRate,_this.isLoading,_this.isRefreshingRates,_this.error);
}

@override
String toString() {
  final _this = this as SettingsState;
  return 'SettingsState(settings: ${_this.settings}, exchangeRate: ${_this.exchangeRate}, isLoading: ${_this.isLoading}, isRefreshingRates: ${_this.isRefreshingRates}, error: ${_this.error})';
}


}

/// @nodoc
abstract mixin class $SettingsStateCopyWith<$Res>  {
  factory $SettingsStateCopyWith(SettingsState value, $Res Function(SettingsState) _then) = _$SettingsStateCopyWithImpl;
@useResult
$Res call({
 AppSettings settings, ExchangeRateCache? exchangeRate, bool isLoading, bool isRefreshingRates, String? error
});


$AppSettingsCopyWith<$Res> get settings;$ExchangeRateCacheCopyWith<$Res>? get exchangeRate;

}
/// @nodoc
class _$SettingsStateCopyWithImpl<$Res>
    implements $SettingsStateCopyWith<$Res> {
  _$SettingsStateCopyWithImpl(this._self, this._then);

  final SettingsState _self;
  final $Res Function(SettingsState) _then;

/// Create a copy of SettingsState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? settings = null,Object? exchangeRate = freezed,Object? isLoading = null,Object? isRefreshingRates = null,Object? error = freezed,}) {
  return _then(SettingsState(
settings: null == settings ? _self.settings : settings // ignore: cast_nullable_to_non_nullable
as AppSettings,exchangeRate: freezed == exchangeRate ? _self.exchangeRate : exchangeRate // ignore: cast_nullable_to_non_nullable
as ExchangeRateCache?,isLoading: null == isLoading ? _self.isLoading : isLoading // ignore: cast_nullable_to_non_nullable
as bool,isRefreshingRates: null == isRefreshingRates ? _self.isRefreshingRates : isRefreshingRates // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}
/// Create a copy of SettingsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AppSettingsCopyWith<$Res> get settings {
  
  return $AppSettingsCopyWith<$Res>(_self.settings, (value) {
    return _then(_self.copyWith(settings: value));
  });
}/// Create a copy of SettingsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ExchangeRateCacheCopyWith<$Res>? get exchangeRate {
    if (_self.exchangeRate == null) {
    return null;
  }

  return $ExchangeRateCacheCopyWith<$Res>(_self.exchangeRate!, (value) {
    return _then(_self.copyWith(exchangeRate: value));
  });
}
}


/// Adds pattern-matching-related methods to [SettingsState].
extension SettingsStatePatterns on SettingsState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SettingsState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SettingsState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SettingsState value)  $default,){
final _that = this;
switch (_that) {
case _SettingsState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SettingsState value)?  $default,){
final _that = this;
switch (_that) {
case _SettingsState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( AppSettings settings,  ExchangeRateCache? exchangeRate,  bool isLoading,  bool isRefreshingRates,  String? error)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SettingsState() when $default != null:
return $default(_that.settings,_that.exchangeRate,_that.isLoading,_that.isRefreshingRates,_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( AppSettings settings,  ExchangeRateCache? exchangeRate,  bool isLoading,  bool isRefreshingRates,  String? error)  $default,) {final _that = this;
switch (_that) {
case _SettingsState():
return $default(_that.settings,_that.exchangeRate,_that.isLoading,_that.isRefreshingRates,_that.error);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( AppSettings settings,  ExchangeRateCache? exchangeRate,  bool isLoading,  bool isRefreshingRates,  String? error)?  $default,) {final _that = this;
switch (_that) {
case _SettingsState() when $default != null:
return $default(_that.settings,_that.exchangeRate,_that.isLoading,_that.isRefreshingRates,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class _SettingsState extends SettingsState {
  const _SettingsState({this.settings = const AppSettings(), this.exchangeRate, this.isLoading = false, this.isRefreshingRates = false, this.error}): super._();
  

@override@JsonKey() final  AppSettings settings;
@override final  ExchangeRateCache? exchangeRate;
@override@JsonKey() final  bool isLoading;
@override@JsonKey() final  bool isRefreshingRates;
@override final  String? error;

/// Create a copy of SettingsState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SettingsStateCopyWith<_SettingsState> get copyWith => __$SettingsStateCopyWithImpl<_SettingsState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SettingsState&&(identical(other.settings, settings) || other.settings == settings)&&(identical(other.exchangeRate, exchangeRate) || other.exchangeRate == exchangeRate)&&(identical(other.isLoading, isLoading) || other.isLoading == isLoading)&&(identical(other.isRefreshingRates, isRefreshingRates) || other.isRefreshingRates == isRefreshingRates)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,settings,exchangeRate,isLoading,isRefreshingRates,error);
}

@override
String toString() {
    return 'SettingsState(settings: $settings, exchangeRate: $exchangeRate, isLoading: $isLoading, isRefreshingRates: $isRefreshingRates, error: $error)';
}


}

/// @nodoc
abstract mixin class _$SettingsStateCopyWith<$Res> implements $SettingsStateCopyWith<$Res> {
  factory _$SettingsStateCopyWith(_SettingsState value, $Res Function(_SettingsState) _then) = __$SettingsStateCopyWithImpl;
@override @useResult
$Res call({
 AppSettings settings, ExchangeRateCache? exchangeRate, bool isLoading, bool isRefreshingRates, String? error
});


@override $AppSettingsCopyWith<$Res> get settings;@override $ExchangeRateCacheCopyWith<$Res>? get exchangeRate;

}
/// @nodoc
class __$SettingsStateCopyWithImpl<$Res>
    implements _$SettingsStateCopyWith<$Res> {
  __$SettingsStateCopyWithImpl(this._self, this._then);

  final _SettingsState _self;
  final $Res Function(_SettingsState) _then;

/// Create a copy of SettingsState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? settings = null,Object? exchangeRate = freezed,Object? isLoading = null,Object? isRefreshingRates = null,Object? error = freezed,}) {
  return _then(_SettingsState(
settings: null == settings ? _self.settings : settings // ignore: cast_nullable_to_non_nullable
as AppSettings,exchangeRate: freezed == exchangeRate ? _self.exchangeRate : exchangeRate // ignore: cast_nullable_to_non_nullable
as ExchangeRateCache?,isLoading: null == isLoading ? _self.isLoading : isLoading // ignore: cast_nullable_to_non_nullable
as bool,isRefreshingRates: null == isRefreshingRates ? _self.isRefreshingRates : isRefreshingRates // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

/// Create a copy of SettingsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AppSettingsCopyWith<$Res> get settings {
  
  return $AppSettingsCopyWith<$Res>(_self.settings, (value) {
    return _then(_self.copyWith(settings: value));
  });
}/// Create a copy of SettingsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ExchangeRateCacheCopyWith<$Res>? get exchangeRate {
    if (_self.exchangeRate == null) {
    return null;
  }

  return $ExchangeRateCacheCopyWith<$Res>(_self.exchangeRate!, (value) {
    return _then(_self.copyWith(exchangeRate: value));
  });
}
}

// dart format on
