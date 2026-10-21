import 'package:data_layer/data_layer.dart';
import 'package:translation_app/core/data/models/exchange_rate_cache.dart';

/// [RestSource] implementation targeting the Frankfurter currency exchange API
/// (`https://api.frankfurter.app/latest?from={base}&to={target}`).
class FrankfurterApiSource extends RestSource<ExchangeRateCache> {
  FrankfurterApiSource({
    RestApi? restApi,
    DateTime Function()? getTime,
  }) : _getTime = getTime ?? _defaultGetTime,
       super(
         restApi:
             restApi ??
             RestApi(
               apiBaseUrl: 'https://api.frankfurter.app',
               headersBuilder: () => <String, String>{},
             ),
         getListUrl: () => const ApiUrl(path: 'latest'),
         getDetailUrl: (_) => const ApiUrl(path: 'latest'),
         bindings: ExchangeRateCache.bindings,
       );

  static DateTime _defaultGetTime() => DateTime.now().toUtc();

  final DateTime Function() _getTime;

  @override
  Set<SourceOperationType> get supportedOperations => const {
    SourceOperationType.getById,
    SourceOperationType.getByIds,
    SourceOperationType.getItems,
  };

  @override
  Future<ReadResult<ExchangeRateCache>> getById(
    ReadOperation<ExchangeRateCache> operation,
  ) async {
    final parts = operation.itemId.split('_');
    if (parts.length != 2) {
      return ReadFailure<ExchangeRateCache>(
        FailureReason.badRequest,
        'Invalid currency pair ID "${operation.itemId}". Expected BASE_TARGET.',
      );
    }

    final base = parts[0].toUpperCase();
    final target = parts[1].toUpperCase();

    if (base == target) {
      return ReadSuccess<ExchangeRateCache>(
        ExchangeRateCache(
          baseCurrency: base,
          targetCurrency: target,
          rate: 1.0,
          updatedAt: _getTime(),
        ),
        details: operation.details,
      );
    }

    try {
      final apiResult = await api.get(
        ReadApiRequest(
          url: const ApiUrl(path: 'latest'),
          params: <String, String>{
            'from': base,
            'to': target,
          },
        ),
      );

      switch (apiResult) {
        case ApiSuccess(:final body):
          if (body is! JsonApiResultBody || body.data is! Map) {
            return ReadFailure<ExchangeRateCache>(
              FailureReason.serverError,
              'Unexpected non-JSON response from Frankfurter API.',
            );
          }
          final map = (body.data as Map).cast<String, Object?>();
          final rate = _extractRate(map, target);
          if (rate == null) {
            return ReadFailure<ExchangeRateCache>(
              FailureReason.serverError,
              'Missing rate for $target in Frankfurter response: $map',
            );
          }
          return ReadSuccess<ExchangeRateCache>(
            ExchangeRateCache(
              baseCurrency: base,
              targetCurrency: target,
              rate: rate,
              updatedAt: _getTime(),
              isStale: false,
            ),
            details: operation.details,
          );
        case ApiError():
          return ReadResult<ExchangeRateCache>.fromApiError(apiResult);
      }
    } on Object catch (e) {
      return ReadFailure<ExchangeRateCache>(
        FailureReason.connectivity,
        'Failed to fetch exchange rate from Frankfurter: $e',
      );
    }
  }

  double? _extractRate(Map<String, Object?> map, String targetCurrency) {
    final rates = map['rates'];
    if (rates is Map) {
      final raw = rates[targetCurrency] ?? rates[targetCurrency.toLowerCase()];
      if (raw is num) {
        return raw.toDouble();
      }
      if (raw is String) {
        return double.tryParse(raw);
      }
    }
    final directRate = map['rate'];
    if (directRate is num) {
      return directRate.toDouble();
    }
    return null;
  }
}
