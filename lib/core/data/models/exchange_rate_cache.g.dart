// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'exchange_rate_cache.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_ExchangeRateCache _$ExchangeRateCacheFromJson(Map<String, dynamic> json) =>
    _ExchangeRateCache(
      baseCurrency: json['baseCurrency'] as String,
      targetCurrency: json['targetCurrency'] as String,
      rate: (json['rate'] as num).toDouble(),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      isStale: json['isStale'] as bool? ?? false,
    );

Map<String, dynamic> _$ExchangeRateCacheToJson(_ExchangeRateCache instance) =>
    <String, dynamic>{
      'baseCurrency': instance.baseCurrency,
      'targetCurrency': instance.targetCurrency,
      'rate': instance.rate,
      'updatedAt': instance.updatedAt.toIso8601String(),
      'isStale': instance.isStale,
    };
