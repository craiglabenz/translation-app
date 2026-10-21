// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'exchange_rate_cache.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$ExchangeRateCache {

 String get baseCurrency; String get targetCurrency; double get rate; DateTime get updatedAt; bool get isStale;
/// Create a copy of ExchangeRateCache
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ExchangeRateCacheCopyWith<ExchangeRateCache> get copyWith => _$ExchangeRateCacheCopyWithImpl<ExchangeRateCache>(this as ExchangeRateCache, _$identity);

  /// Serializes this ExchangeRateCache to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as ExchangeRateCache;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ExchangeRateCache&&(identical(other.baseCurrency, _this.baseCurrency) || other.baseCurrency == _this.baseCurrency)&&(identical(other.targetCurrency, _this.targetCurrency) || other.targetCurrency == _this.targetCurrency)&&(identical(other.rate, _this.rate) || other.rate == _this.rate)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt)&&(identical(other.isStale, _this.isStale) || other.isStale == _this.isStale));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as ExchangeRateCache;
  return Object.hash(runtimeType,_this.baseCurrency,_this.targetCurrency,_this.rate,_this.updatedAt,_this.isStale);
}

@override
String toString() {
  final _this = this as ExchangeRateCache;
  return 'ExchangeRateCache(baseCurrency: ${_this.baseCurrency}, targetCurrency: ${_this.targetCurrency}, rate: ${_this.rate}, updatedAt: ${_this.updatedAt}, isStale: ${_this.isStale})';
}


}

/// @nodoc
abstract mixin class $ExchangeRateCacheCopyWith<$Res>  {
  factory $ExchangeRateCacheCopyWith(ExchangeRateCache value, $Res Function(ExchangeRateCache) _then) = _$ExchangeRateCacheCopyWithImpl;
@useResult
$Res call({
 String baseCurrency, String targetCurrency, double rate, DateTime updatedAt, bool isStale
});




}
/// @nodoc
class _$ExchangeRateCacheCopyWithImpl<$Res>
    implements $ExchangeRateCacheCopyWith<$Res> {
  _$ExchangeRateCacheCopyWithImpl(this._self, this._then);

  final ExchangeRateCache _self;
  final $Res Function(ExchangeRateCache) _then;

/// Create a copy of ExchangeRateCache
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? baseCurrency = null,Object? targetCurrency = null,Object? rate = null,Object? updatedAt = null,Object? isStale = null,}) {
  return _then(ExchangeRateCache(
baseCurrency: null == baseCurrency ? _self.baseCurrency : baseCurrency // ignore: cast_nullable_to_non_nullable
as String,targetCurrency: null == targetCurrency ? _self.targetCurrency : targetCurrency // ignore: cast_nullable_to_non_nullable
as String,rate: null == rate ? _self.rate : rate // ignore: cast_nullable_to_non_nullable
as double,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,isStale: null == isStale ? _self.isStale : isStale // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [ExchangeRateCache].
extension ExchangeRateCachePatterns on ExchangeRateCache {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ExchangeRateCache value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ExchangeRateCache() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ExchangeRateCache value)  $default,){
final _that = this;
switch (_that) {
case _ExchangeRateCache():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ExchangeRateCache value)?  $default,){
final _that = this;
switch (_that) {
case _ExchangeRateCache() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String baseCurrency,  String targetCurrency,  double rate,  DateTime updatedAt,  bool isStale)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ExchangeRateCache() when $default != null:
return $default(_that.baseCurrency,_that.targetCurrency,_that.rate,_that.updatedAt,_that.isStale);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String baseCurrency,  String targetCurrency,  double rate,  DateTime updatedAt,  bool isStale)  $default,) {final _that = this;
switch (_that) {
case _ExchangeRateCache():
return $default(_that.baseCurrency,_that.targetCurrency,_that.rate,_that.updatedAt,_that.isStale);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String baseCurrency,  String targetCurrency,  double rate,  DateTime updatedAt,  bool isStale)?  $default,) {final _that = this;
switch (_that) {
case _ExchangeRateCache() when $default != null:
return $default(_that.baseCurrency,_that.targetCurrency,_that.rate,_that.updatedAt,_that.isStale);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ExchangeRateCache extends ExchangeRateCache {
  const _ExchangeRateCache({required this.baseCurrency, required this.targetCurrency, required this.rate, required this.updatedAt, this.isStale = false}): super._();
  factory _ExchangeRateCache.fromJson(Map<String, dynamic> json) => _$ExchangeRateCacheFromJson(json);

@override final  String baseCurrency;
@override final  String targetCurrency;
@override final  double rate;
@override final  DateTime updatedAt;
@override@JsonKey() final  bool isStale;

/// Create a copy of ExchangeRateCache
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ExchangeRateCacheCopyWith<_ExchangeRateCache> get copyWith => __$ExchangeRateCacheCopyWithImpl<_ExchangeRateCache>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ExchangeRateCacheToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ExchangeRateCache&&(identical(other.baseCurrency, baseCurrency) || other.baseCurrency == baseCurrency)&&(identical(other.targetCurrency, targetCurrency) || other.targetCurrency == targetCurrency)&&(identical(other.rate, rate) || other.rate == rate)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.isStale, isStale) || other.isStale == isStale));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,baseCurrency,targetCurrency,rate,updatedAt,isStale);
}

@override
String toString() {
    return 'ExchangeRateCache(baseCurrency: $baseCurrency, targetCurrency: $targetCurrency, rate: $rate, updatedAt: $updatedAt, isStale: $isStale)';
}


}

/// @nodoc
abstract mixin class _$ExchangeRateCacheCopyWith<$Res> implements $ExchangeRateCacheCopyWith<$Res> {
  factory _$ExchangeRateCacheCopyWith(_ExchangeRateCache value, $Res Function(_ExchangeRateCache) _then) = __$ExchangeRateCacheCopyWithImpl;
@override @useResult
$Res call({
 String baseCurrency, String targetCurrency, double rate, DateTime updatedAt, bool isStale
});




}
/// @nodoc
class __$ExchangeRateCacheCopyWithImpl<$Res>
    implements _$ExchangeRateCacheCopyWith<$Res> {
  __$ExchangeRateCacheCopyWithImpl(this._self, this._then);

  final _ExchangeRateCache _self;
  final $Res Function(_ExchangeRateCache) _then;

/// Create a copy of ExchangeRateCache
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? baseCurrency = null,Object? targetCurrency = null,Object? rate = null,Object? updatedAt = null,Object? isStale = null,}) {
  return _then(_ExchangeRateCache(
baseCurrency: null == baseCurrency ? _self.baseCurrency : baseCurrency // ignore: cast_nullable_to_non_nullable
as String,targetCurrency: null == targetCurrency ? _self.targetCurrency : targetCurrency // ignore: cast_nullable_to_non_nullable
as String,rate: null == rate ? _self.rate : rate // ignore: cast_nullable_to_non_nullable
as double,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,isStale: null == isStale ? _self.isStale : isStale // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
