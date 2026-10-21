import 'package:data_layer/data_layer.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:hive_ce/hive.dart';

part 'exchange_rate_cache.freezed.dart';
part 'exchange_rate_cache.g.dart';

/// Cached exchange rate between [baseCurrency] and [targetCurrency].
///
/// [rate] represents how many units of [baseCurrency] equal 1 unit of
/// [targetCurrency] (`1 targetCurrency = rate baseCurrency`).
@freezed
abstract class ExchangeRateCache with _$ExchangeRateCache {
  const factory ExchangeRateCache({
    required String baseCurrency,
    required String targetCurrency,
    required double rate,
    required DateTime updatedAt,
    @Default(false) bool isStale,
  }) = _ExchangeRateCache;

  const ExchangeRateCache._();

  factory ExchangeRateCache.fromJson(Map<String, Object?> json) =>
      _$ExchangeRateCacheFromJson(json);

  static const Duration defaultTtl = Duration(days: 7);

  static String idForPair(String baseCurrency, String targetCurrency) =>
      '${baseCurrency.toUpperCase()}_${targetCurrency.toUpperCase()}';

  String get id => idForPair(baseCurrency, targetCurrency);

  /// Returns `true` if this rate was fetched more than [ttl] ago.
  bool isExpired({DateTime? now, Duration ttl = defaultTtl}) {
    final reference = (now ?? DateTime.now()).toUtc();
    return reference.difference(updatedAt.toUtc()) >= ttl;
  }

  static Bindings<ExchangeRateCache> get bindings =>
      Bindings<ExchangeRateCache>(
        getId: (obj) => obj.id,
        fromJson: ExchangeRateCache.fromJson,
        toJson: (obj) => obj.toJson(),
      );
}

/// Hive [TypeAdapter] for [ExchangeRateCache].
class ExchangeRateCacheAdapter extends TypeAdapter<ExchangeRateCache> {
  @override
  final int typeId = 2;

  @override
  ExchangeRateCache read(BinaryReader reader) {
    final map = reader.readMap().cast<String, Object?>();
    return ExchangeRateCache.fromJson(map);
  }

  @override
  void write(BinaryWriter writer, ExchangeRateCache obj) {
    writer.writeMap(obj.toJson());
  }
}
