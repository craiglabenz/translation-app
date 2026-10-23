// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'app_settings.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$SupportedCloudModel {

 String get id; String get name; String get description;
/// Create a copy of SupportedCloudModel
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SupportedCloudModelCopyWith<SupportedCloudModel> get copyWith => _$SupportedCloudModelCopyWithImpl<SupportedCloudModel>(this as SupportedCloudModel, _$identity);

  /// Serializes this SupportedCloudModel to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as SupportedCloudModel;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SupportedCloudModel&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.description, _this.description) || other.description == _this.description));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as SupportedCloudModel;
  return Object.hash(runtimeType,_this.id,_this.name,_this.description);
}

@override
String toString() {
  final _this = this as SupportedCloudModel;
  return 'SupportedCloudModel(id: ${_this.id}, name: ${_this.name}, description: ${_this.description})';
}


}

/// @nodoc
abstract mixin class $SupportedCloudModelCopyWith<$Res>  {
  factory $SupportedCloudModelCopyWith(SupportedCloudModel value, $Res Function(SupportedCloudModel) _then) = _$SupportedCloudModelCopyWithImpl;
@useResult
$Res call({
 String id, String name, String description
});




}
/// @nodoc
class _$SupportedCloudModelCopyWithImpl<$Res>
    implements $SupportedCloudModelCopyWith<$Res> {
  _$SupportedCloudModelCopyWithImpl(this._self, this._then);

  final SupportedCloudModel _self;
  final $Res Function(SupportedCloudModel) _then;

/// Create a copy of SupportedCloudModel
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? description = null,}) {
  return _then(SupportedCloudModel(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}

/// @nodoc
@JsonSerializable()

class _SupportedCloudModel implements SupportedCloudModel {
  const _SupportedCloudModel({required this.id, required this.name, required this.description});
  factory _SupportedCloudModel.fromJson(Map<String, dynamic> json) => _$SupportedCloudModelFromJson(json);

@override final  String id;
@override final  String name;
@override final  String description;

/// Create a copy of SupportedCloudModel
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SupportedCloudModelCopyWith<_SupportedCloudModel> get copyWith => __$SupportedCloudModelCopyWithImpl<_SupportedCloudModel>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$SupportedCloudModelToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SupportedCloudModel&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.description, description) || other.description == description));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,name,description);
}

@override
String toString() {
    return 'SupportedCloudModel(id: $id, name: $name, description: $description)';
}


}

/// @nodoc
abstract mixin class _$SupportedCloudModelCopyWith<$Res> implements $SupportedCloudModelCopyWith<$Res> {
  factory _$SupportedCloudModelCopyWith(_SupportedCloudModel value, $Res Function(_SupportedCloudModel) _then) = __$SupportedCloudModelCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, String description
});




}
/// @nodoc
class __$SupportedCloudModelCopyWithImpl<$Res>
    implements _$SupportedCloudModelCopyWith<$Res> {
  __$SupportedCloudModelCopyWithImpl(this._self, this._then);

  final _SupportedCloudModel _self;
  final $Res Function(_SupportedCloudModel) _then;

/// Create a copy of SupportedCloudModel
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? description = null,}) {
  return _then(_SupportedCloudModel(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$SupportedLanguage {

 String get code; String get name; String get nativeName;
/// Create a copy of SupportedLanguage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SupportedLanguageCopyWith<SupportedLanguage> get copyWith => _$SupportedLanguageCopyWithImpl<SupportedLanguage>(this as SupportedLanguage, _$identity);

  /// Serializes this SupportedLanguage to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as SupportedLanguage;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SupportedLanguage&&(identical(other.code, _this.code) || other.code == _this.code)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.nativeName, _this.nativeName) || other.nativeName == _this.nativeName));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as SupportedLanguage;
  return Object.hash(runtimeType,_this.code,_this.name,_this.nativeName);
}

@override
String toString() {
  final _this = this as SupportedLanguage;
  return 'SupportedLanguage(code: ${_this.code}, name: ${_this.name}, nativeName: ${_this.nativeName})';
}


}

/// @nodoc
abstract mixin class $SupportedLanguageCopyWith<$Res>  {
  factory $SupportedLanguageCopyWith(SupportedLanguage value, $Res Function(SupportedLanguage) _then) = _$SupportedLanguageCopyWithImpl;
@useResult
$Res call({
 String code, String name, String nativeName
});




}
/// @nodoc
class _$SupportedLanguageCopyWithImpl<$Res>
    implements $SupportedLanguageCopyWith<$Res> {
  _$SupportedLanguageCopyWithImpl(this._self, this._then);

  final SupportedLanguage _self;
  final $Res Function(SupportedLanguage) _then;

/// Create a copy of SupportedLanguage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? code = null,Object? name = null,Object? nativeName = null,}) {
  return _then(SupportedLanguage(
code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,nativeName: null == nativeName ? _self.nativeName : nativeName // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [SupportedLanguage].
extension SupportedLanguagePatterns on SupportedLanguage {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SupportedLanguage value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SupportedLanguage() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SupportedLanguage value)  $default,){
final _that = this;
switch (_that) {
case _SupportedLanguage():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SupportedLanguage value)?  $default,){
final _that = this;
switch (_that) {
case _SupportedLanguage() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String code,  String name,  String nativeName)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SupportedLanguage() when $default != null:
return $default(_that.code,_that.name,_that.nativeName);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String code,  String name,  String nativeName)  $default,) {final _that = this;
switch (_that) {
case _SupportedLanguage():
return $default(_that.code,_that.name,_that.nativeName);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String code,  String name,  String nativeName)?  $default,) {final _that = this;
switch (_that) {
case _SupportedLanguage() when $default != null:
return $default(_that.code,_that.name,_that.nativeName);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _SupportedLanguage extends SupportedLanguage {
  const _SupportedLanguage({required this.code, required this.name, required this.nativeName}): super._();
  factory _SupportedLanguage.fromJson(Map<String, dynamic> json) => _$SupportedLanguageFromJson(json);

@override final  String code;
@override final  String name;
@override final  String nativeName;

/// Create a copy of SupportedLanguage
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SupportedLanguageCopyWith<_SupportedLanguage> get copyWith => __$SupportedLanguageCopyWithImpl<_SupportedLanguage>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$SupportedLanguageToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SupportedLanguage&&(identical(other.code, code) || other.code == code)&&(identical(other.name, name) || other.name == name)&&(identical(other.nativeName, nativeName) || other.nativeName == nativeName));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,code,name,nativeName);
}

@override
String toString() {
    return 'SupportedLanguage(code: $code, name: $name, nativeName: $nativeName)';
}


}

/// @nodoc
abstract mixin class _$SupportedLanguageCopyWith<$Res> implements $SupportedLanguageCopyWith<$Res> {
  factory _$SupportedLanguageCopyWith(_SupportedLanguage value, $Res Function(_SupportedLanguage) _then) = __$SupportedLanguageCopyWithImpl;
@override @useResult
$Res call({
 String code, String name, String nativeName
});




}
/// @nodoc
class __$SupportedLanguageCopyWithImpl<$Res>
    implements _$SupportedLanguageCopyWith<$Res> {
  __$SupportedLanguageCopyWithImpl(this._self, this._then);

  final _SupportedLanguage _self;
  final $Res Function(_SupportedLanguage) _then;

/// Create a copy of SupportedLanguage
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? code = null,Object? name = null,Object? nativeName = null,}) {
  return _then(_SupportedLanguage(
code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,nativeName: null == nativeName ? _self.nativeName : nativeName // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$SupportedCurrency {

 String get code; String get name; String get symbol;
/// Create a copy of SupportedCurrency
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SupportedCurrencyCopyWith<SupportedCurrency> get copyWith => _$SupportedCurrencyCopyWithImpl<SupportedCurrency>(this as SupportedCurrency, _$identity);

  /// Serializes this SupportedCurrency to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as SupportedCurrency;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SupportedCurrency&&(identical(other.code, _this.code) || other.code == _this.code)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.symbol, _this.symbol) || other.symbol == _this.symbol));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as SupportedCurrency;
  return Object.hash(runtimeType,_this.code,_this.name,_this.symbol);
}

@override
String toString() {
  final _this = this as SupportedCurrency;
  return 'SupportedCurrency(code: ${_this.code}, name: ${_this.name}, symbol: ${_this.symbol})';
}


}

/// @nodoc
abstract mixin class $SupportedCurrencyCopyWith<$Res>  {
  factory $SupportedCurrencyCopyWith(SupportedCurrency value, $Res Function(SupportedCurrency) _then) = _$SupportedCurrencyCopyWithImpl;
@useResult
$Res call({
 String code, String name, String symbol
});




}
/// @nodoc
class _$SupportedCurrencyCopyWithImpl<$Res>
    implements $SupportedCurrencyCopyWith<$Res> {
  _$SupportedCurrencyCopyWithImpl(this._self, this._then);

  final SupportedCurrency _self;
  final $Res Function(SupportedCurrency) _then;

/// Create a copy of SupportedCurrency
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? code = null,Object? name = null,Object? symbol = null,}) {
  return _then(SupportedCurrency(
code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,symbol: null == symbol ? _self.symbol : symbol // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [SupportedCurrency].
extension SupportedCurrencyPatterns on SupportedCurrency {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SupportedCurrency value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SupportedCurrency() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SupportedCurrency value)  $default,){
final _that = this;
switch (_that) {
case _SupportedCurrency():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SupportedCurrency value)?  $default,){
final _that = this;
switch (_that) {
case _SupportedCurrency() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String code,  String name,  String symbol)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SupportedCurrency() when $default != null:
return $default(_that.code,_that.name,_that.symbol);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String code,  String name,  String symbol)  $default,) {final _that = this;
switch (_that) {
case _SupportedCurrency():
return $default(_that.code,_that.name,_that.symbol);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String code,  String name,  String symbol)?  $default,) {final _that = this;
switch (_that) {
case _SupportedCurrency() when $default != null:
return $default(_that.code,_that.name,_that.symbol);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _SupportedCurrency implements SupportedCurrency {
  const _SupportedCurrency({required this.code, required this.name, required this.symbol});
  factory _SupportedCurrency.fromJson(Map<String, dynamic> json) => _$SupportedCurrencyFromJson(json);

@override final  String code;
@override final  String name;
@override final  String symbol;

/// Create a copy of SupportedCurrency
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SupportedCurrencyCopyWith<_SupportedCurrency> get copyWith => __$SupportedCurrencyCopyWithImpl<_SupportedCurrency>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$SupportedCurrencyToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SupportedCurrency&&(identical(other.code, code) || other.code == code)&&(identical(other.name, name) || other.name == name)&&(identical(other.symbol, symbol) || other.symbol == symbol));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,code,name,symbol);
}

@override
String toString() {
    return 'SupportedCurrency(code: $code, name: $name, symbol: $symbol)';
}


}

/// @nodoc
abstract mixin class _$SupportedCurrencyCopyWith<$Res> implements $SupportedCurrencyCopyWith<$Res> {
  factory _$SupportedCurrencyCopyWith(_SupportedCurrency value, $Res Function(_SupportedCurrency) _then) = __$SupportedCurrencyCopyWithImpl;
@override @useResult
$Res call({
 String code, String name, String symbol
});




}
/// @nodoc
class __$SupportedCurrencyCopyWithImpl<$Res>
    implements _$SupportedCurrencyCopyWith<$Res> {
  __$SupportedCurrencyCopyWithImpl(this._self, this._then);

  final _SupportedCurrency _self;
  final $Res Function(_SupportedCurrency) _then;

/// Create a copy of SupportedCurrency
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? code = null,Object? name = null,Object? symbol = null,}) {
  return _then(_SupportedCurrency(
code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,symbol: null == symbol ? _self.symbol : symbol // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$AppSettings {

 String get id; String get baseLanguage; String get targetLanguage; String get baseCurrency; String get targetCurrency; String get modelDownloadUrl; double get textScaleFactor; TranslationEngineMode get translationEngineMode; String get cloudModelId; String get geminiApiKey;
/// Create a copy of AppSettings
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AppSettingsCopyWith<AppSettings> get copyWith => _$AppSettingsCopyWithImpl<AppSettings>(this as AppSettings, _$identity);

  /// Serializes this AppSettings to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as AppSettings;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppSettings&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.baseLanguage, _this.baseLanguage) || other.baseLanguage == _this.baseLanguage)&&(identical(other.targetLanguage, _this.targetLanguage) || other.targetLanguage == _this.targetLanguage)&&(identical(other.baseCurrency, _this.baseCurrency) || other.baseCurrency == _this.baseCurrency)&&(identical(other.targetCurrency, _this.targetCurrency) || other.targetCurrency == _this.targetCurrency)&&(identical(other.modelDownloadUrl, _this.modelDownloadUrl) || other.modelDownloadUrl == _this.modelDownloadUrl)&&(identical(other.textScaleFactor, _this.textScaleFactor) || other.textScaleFactor == _this.textScaleFactor)&&(identical(other.translationEngineMode, _this.translationEngineMode) || other.translationEngineMode == _this.translationEngineMode)&&(identical(other.cloudModelId, _this.cloudModelId) || other.cloudModelId == _this.cloudModelId)&&(identical(other.geminiApiKey, _this.geminiApiKey) || other.geminiApiKey == _this.geminiApiKey));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as AppSettings;
  return Object.hash(runtimeType,_this.id,_this.baseLanguage,_this.targetLanguage,_this.baseCurrency,_this.targetCurrency,_this.modelDownloadUrl,_this.textScaleFactor,_this.translationEngineMode,_this.cloudModelId,_this.geminiApiKey);
}

@override
String toString() {
  final _this = this as AppSettings;
  return 'AppSettings(id: ${_this.id}, baseLanguage: ${_this.baseLanguage}, targetLanguage: ${_this.targetLanguage}, baseCurrency: ${_this.baseCurrency}, targetCurrency: ${_this.targetCurrency}, modelDownloadUrl: ${_this.modelDownloadUrl}, textScaleFactor: ${_this.textScaleFactor}, translationEngineMode: ${_this.translationEngineMode}, cloudModelId: ${_this.cloudModelId}, geminiApiKey: ${_this.geminiApiKey})';
}


}

/// @nodoc
abstract mixin class $AppSettingsCopyWith<$Res>  {
  factory $AppSettingsCopyWith(AppSettings value, $Res Function(AppSettings) _then) = _$AppSettingsCopyWithImpl;
@useResult
$Res call({
 String id, String baseLanguage, String targetLanguage, String baseCurrency, String targetCurrency, String modelDownloadUrl, double textScaleFactor, TranslationEngineMode translationEngineMode, String cloudModelId, String geminiApiKey
});




}
/// @nodoc
class _$AppSettingsCopyWithImpl<$Res>
    implements $AppSettingsCopyWith<$Res> {
  _$AppSettingsCopyWithImpl(this._self, this._then);

  final AppSettings _self;
  final $Res Function(AppSettings) _then;

/// Create a copy of AppSettings
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? baseLanguage = null,Object? targetLanguage = null,Object? baseCurrency = null,Object? targetCurrency = null,Object? modelDownloadUrl = null,Object? textScaleFactor = null,Object? translationEngineMode = null,Object? cloudModelId = null,Object? geminiApiKey = null,}) {
  return _then(AppSettings(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,baseLanguage: null == baseLanguage ? _self.baseLanguage : baseLanguage // ignore: cast_nullable_to_non_nullable
as String,targetLanguage: null == targetLanguage ? _self.targetLanguage : targetLanguage // ignore: cast_nullable_to_non_nullable
as String,baseCurrency: null == baseCurrency ? _self.baseCurrency : baseCurrency // ignore: cast_nullable_to_non_nullable
as String,targetCurrency: null == targetCurrency ? _self.targetCurrency : targetCurrency // ignore: cast_nullable_to_non_nullable
as String,modelDownloadUrl: null == modelDownloadUrl ? _self.modelDownloadUrl : modelDownloadUrl // ignore: cast_nullable_to_non_nullable
as String,textScaleFactor: null == textScaleFactor ? _self.textScaleFactor : textScaleFactor // ignore: cast_nullable_to_non_nullable
as double,translationEngineMode: null == translationEngineMode ? _self.translationEngineMode : translationEngineMode // ignore: cast_nullable_to_non_nullable
as TranslationEngineMode,cloudModelId: null == cloudModelId ? _self.cloudModelId : cloudModelId // ignore: cast_nullable_to_non_nullable
as String,geminiApiKey: null == geminiApiKey ? _self.geminiApiKey : geminiApiKey // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [AppSettings].
extension AppSettingsPatterns on AppSettings {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AppSettings value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AppSettings() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AppSettings value)  $default,){
final _that = this;
switch (_that) {
case _AppSettings():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AppSettings value)?  $default,){
final _that = this;
switch (_that) {
case _AppSettings() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String baseLanguage,  String targetLanguage,  String baseCurrency,  String targetCurrency,  String modelDownloadUrl,  double textScaleFactor,  TranslationEngineMode translationEngineMode,  String cloudModelId,  String geminiApiKey)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AppSettings() when $default != null:
return $default(_that.id,_that.baseLanguage,_that.targetLanguage,_that.baseCurrency,_that.targetCurrency,_that.modelDownloadUrl,_that.textScaleFactor,_that.translationEngineMode,_that.cloudModelId,_that.geminiApiKey);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String baseLanguage,  String targetLanguage,  String baseCurrency,  String targetCurrency,  String modelDownloadUrl,  double textScaleFactor,  TranslationEngineMode translationEngineMode,  String cloudModelId,  String geminiApiKey)  $default,) {final _that = this;
switch (_that) {
case _AppSettings():
return $default(_that.id,_that.baseLanguage,_that.targetLanguage,_that.baseCurrency,_that.targetCurrency,_that.modelDownloadUrl,_that.textScaleFactor,_that.translationEngineMode,_that.cloudModelId,_that.geminiApiKey);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String baseLanguage,  String targetLanguage,  String baseCurrency,  String targetCurrency,  String modelDownloadUrl,  double textScaleFactor,  TranslationEngineMode translationEngineMode,  String cloudModelId,  String geminiApiKey)?  $default,) {final _that = this;
switch (_that) {
case _AppSettings() when $default != null:
return $default(_that.id,_that.baseLanguage,_that.targetLanguage,_that.baseCurrency,_that.targetCurrency,_that.modelDownloadUrl,_that.textScaleFactor,_that.translationEngineMode,_that.cloudModelId,_that.geminiApiKey);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _AppSettings extends AppSettings {
  const _AppSettings({this.id = AppSettings.defaultId, this.baseLanguage = 'en', this.targetLanguage = 'es', this.baseCurrency = 'USD', this.targetCurrency = 'EUR', this.modelDownloadUrl = AppSettings.defaultModelDownloadUrl, this.textScaleFactor = AppSettings.defaultTextScaleFactor, this.translationEngineMode = TranslationEngineMode.onDevice, this.cloudModelId = AppSettings.defaultCloudModelId, this.geminiApiKey = ''}): super._();
  factory _AppSettings.fromJson(Map<String, dynamic> json) => _$AppSettingsFromJson(json);

@override@JsonKey() final  String id;
@override@JsonKey() final  String baseLanguage;
@override@JsonKey() final  String targetLanguage;
@override@JsonKey() final  String baseCurrency;
@override@JsonKey() final  String targetCurrency;
@override@JsonKey() final  String modelDownloadUrl;
@override@JsonKey() final  double textScaleFactor;
@override@JsonKey() final  TranslationEngineMode translationEngineMode;
@override@JsonKey() final  String cloudModelId;
@override@JsonKey() final  String geminiApiKey;

/// Create a copy of AppSettings
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AppSettingsCopyWith<_AppSettings> get copyWith => __$AppSettingsCopyWithImpl<_AppSettings>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$AppSettingsToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AppSettings&&(identical(other.id, id) || other.id == id)&&(identical(other.baseLanguage, baseLanguage) || other.baseLanguage == baseLanguage)&&(identical(other.targetLanguage, targetLanguage) || other.targetLanguage == targetLanguage)&&(identical(other.baseCurrency, baseCurrency) || other.baseCurrency == baseCurrency)&&(identical(other.targetCurrency, targetCurrency) || other.targetCurrency == targetCurrency)&&(identical(other.modelDownloadUrl, modelDownloadUrl) || other.modelDownloadUrl == modelDownloadUrl)&&(identical(other.textScaleFactor, textScaleFactor) || other.textScaleFactor == textScaleFactor)&&(identical(other.translationEngineMode, translationEngineMode) || other.translationEngineMode == translationEngineMode)&&(identical(other.cloudModelId, cloudModelId) || other.cloudModelId == cloudModelId)&&(identical(other.geminiApiKey, geminiApiKey) || other.geminiApiKey == geminiApiKey));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,baseLanguage,targetLanguage,baseCurrency,targetCurrency,modelDownloadUrl,textScaleFactor,translationEngineMode,cloudModelId,geminiApiKey);
}

@override
String toString() {
    return 'AppSettings(id: $id, baseLanguage: $baseLanguage, targetLanguage: $targetLanguage, baseCurrency: $baseCurrency, targetCurrency: $targetCurrency, modelDownloadUrl: $modelDownloadUrl, textScaleFactor: $textScaleFactor, translationEngineMode: $translationEngineMode, cloudModelId: $cloudModelId, geminiApiKey: $geminiApiKey)';
}


}

/// @nodoc
abstract mixin class _$AppSettingsCopyWith<$Res> implements $AppSettingsCopyWith<$Res> {
  factory _$AppSettingsCopyWith(_AppSettings value, $Res Function(_AppSettings) _then) = __$AppSettingsCopyWithImpl;
@override @useResult
$Res call({
 String id, String baseLanguage, String targetLanguage, String baseCurrency, String targetCurrency, String modelDownloadUrl, double textScaleFactor, TranslationEngineMode translationEngineMode, String cloudModelId, String geminiApiKey
});




}
/// @nodoc
class __$AppSettingsCopyWithImpl<$Res>
    implements _$AppSettingsCopyWith<$Res> {
  __$AppSettingsCopyWithImpl(this._self, this._then);

  final _AppSettings _self;
  final $Res Function(_AppSettings) _then;

/// Create a copy of AppSettings
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? baseLanguage = null,Object? targetLanguage = null,Object? baseCurrency = null,Object? targetCurrency = null,Object? modelDownloadUrl = null,Object? textScaleFactor = null,Object? translationEngineMode = null,Object? cloudModelId = null,Object? geminiApiKey = null,}) {
  return _then(_AppSettings(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,baseLanguage: null == baseLanguage ? _self.baseLanguage : baseLanguage // ignore: cast_nullable_to_non_nullable
as String,targetLanguage: null == targetLanguage ? _self.targetLanguage : targetLanguage // ignore: cast_nullable_to_non_nullable
as String,baseCurrency: null == baseCurrency ? _self.baseCurrency : baseCurrency // ignore: cast_nullable_to_non_nullable
as String,targetCurrency: null == targetCurrency ? _self.targetCurrency : targetCurrency // ignore: cast_nullable_to_non_nullable
as String,modelDownloadUrl: null == modelDownloadUrl ? _self.modelDownloadUrl : modelDownloadUrl // ignore: cast_nullable_to_non_nullable
as String,textScaleFactor: null == textScaleFactor ? _self.textScaleFactor : textScaleFactor // ignore: cast_nullable_to_non_nullable
as double,translationEngineMode: null == translationEngineMode ? _self.translationEngineMode : translationEngineMode // ignore: cast_nullable_to_non_nullable
as TranslationEngineMode,cloudModelId: null == cloudModelId ? _self.cloudModelId : cloudModelId // ignore: cast_nullable_to_non_nullable
as String,geminiApiKey: null == geminiApiKey ? _self.geminiApiKey : geminiApiKey // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
