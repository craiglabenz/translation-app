import 'dart:io';

import 'package:data_layer/data_layer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:translation_app/core/data/models/exchange_rate_cache.dart';
import 'package:translation_app/core/data/sources/frankfurter_api_source.dart';

void main() {
  final fixedNow = DateTime.utc(2026, 2, 15, 14, 30);

  ReadOperation<ExchangeRateCache> buildReadOp(String itemId) {
    return ReadOperation<ExchangeRateCache>(
      operationId: 'op_$itemId',
      itemId: itemId,
      details: RequestDetails.read(requestType: RequestType.refresh),
      createdAt: fixedNow,
    );
  }

  FrankfurterApiSource buildSource({
    required Future<http.Response> Function(Uri url, {Map<String, String>? headers})
        handler,
  }) {
    final restApi = RestApi(
      apiBaseUrl: 'https://api.frankfurter.app',
      headersBuilder: () => <String, String>{},
      delegate: RequestDelegate.fake(readHandler: handler),
    );
    return FrankfurterApiSource(
      restApi: restApi,
      getTime: () => fixedNow,
    );
  }

  group('FrankfurterApiSource', () {
    test('declares read-only supportedOperations', () {
      final source = FrankfurterApiSource(getTime: () => fixedNow);
      expect(
        source.supportedOperations,
        equals(const <SourceOperationType>{
          SourceOperationType.getById,
          SourceOperationType.getByIds,
          SourceOperationType.getItems,
        }),
      );
    });

    test('rejects malformed currency pair IDs with badRequest failure', () async {
      final source = FrankfurterApiSource(getTime: () => fixedNow);

      for (final invalidId in <String>['USD', 'USD_EUR_GBP', 'ONLYONE']) {
        final result = await source.getById(buildReadOp(invalidId));
        expect(result, isA<ReadFailure<ExchangeRateCache>>());
        final failure = result as ReadFailure<ExchangeRateCache>;
        expect(failure.reason, FailureReason.badRequest);
        expect(failure.message, contains(invalidId));
      }
    });

    test('returns 1.0 immediately for identical base and target currencies without network call', () async {
      var networkCalled = false;
      final source = buildSource(
        handler: (url, {headers}) async {
          networkCalled = true;
          throw StateError('Should not hit network for identical currencies');
        },
      );

      final result = await source.getById(buildReadOp('usd_usd'));
      expect(networkCalled, isFalse);
      expect(result, isA<ReadSuccess<ExchangeRateCache>>());
      final item = (result as ReadSuccess<ExchangeRateCache>).item!;
      expect(item.baseCurrency, 'USD');
      expect(item.targetCurrency, 'USD');
      expect(item.rate, 1.0);
      expect(item.isStale, isFalse);
      expect(item.updatedAt, fixedNow);
    });

    test('normalizes lowercase pair IDs to uppercase in query parameters and model', () async {
      Uri? capturedUri;
      final source = buildSource(
        handler: (url, {headers}) async {
          capturedUri = url;
          return http.Response(
            '{"amount":1.0,"base":"USD","rates":{"JPY":154.32}}',
            200,
            headers: <String, String>{'content-type': 'application/json'},
          );
        },
      );

      final result = await source.getById(buildReadOp('usd_jpy'));
      expect(capturedUri?.queryParameters['from'], 'USD');
      expect(capturedUri?.queryParameters['to'], 'JPY');
      expect(result, isA<ReadSuccess<ExchangeRateCache>>());
      final item = (result as ReadSuccess<ExchangeRateCache>).item!;
      expect(item.baseCurrency, 'USD');
      expect(item.targetCurrency, 'JPY');
      expect(item.rate, 154.32);
    });

    test('parses integer rate in JSON payload as double', () async {
      final source = buildSource(
        handler: (url, {headers}) async => http.Response(
          '{"amount":1,"base":"USD","rates":{"KRW":1350}}',
          200,
          headers: <String, String>{'content-type': 'application/json'},
        ),
      );

      final result = await source.getById(buildReadOp('USD_KRW'));
      final item = (result as ReadSuccess<ExchangeRateCache>).item!;
      expect(item.rate, 1350.0);
    });

    test('parses numeric string rate in JSON payload', () async {
      final source = buildSource(
        handler: (url, {headers}) async => http.Response(
          '{"amount":1,"base":"USD","rates":{"EUR":"0.9185"}}',
          200,
          headers: <String, String>{'content-type': 'application/json'},
        ),
      );

      final result = await source.getById(buildReadOp('USD_EUR'));
      final item = (result as ReadSuccess<ExchangeRateCache>).item!;
      expect(item.rate, 0.9185);
    });

    test('parses lowercase currency key inside rates map', () async {
      final source = buildSource(
        handler: (url, {headers}) async => http.Response(
          '{"amount":1,"base":"USD","rates":{"eur":0.895}}',
          200,
          headers: <String, String>{'content-type': 'application/json'},
        ),
      );

      final result = await source.getById(buildReadOp('USD_EUR'));
      final item = (result as ReadSuccess<ExchangeRateCache>).item!;
      expect(item.rate, 0.895);
    });

    test('supports direct top-level rate field in JSON response', () async {
      final source = buildSource(
        handler: (url, {headers}) async => http.Response(
          '{"base":"GBP","target":"USD","rate":1.275}',
          200,
          headers: <String, String>{'content-type': 'application/json'},
        ),
      );

      final result = await source.getById(buildReadOp('GBP_USD'));
      final item = (result as ReadSuccess<ExchangeRateCache>).item!;
      expect(item.rate, 1.275);
    });

    test('returns serverError when target currency is missing from rates map', () async {
      final source = buildSource(
        handler: (url, {headers}) async => http.Response(
          '{"amount":1,"base":"USD","rates":{"GBP":0.79}}',
          200,
          headers: <String, String>{'content-type': 'application/json'},
        ),
      );

      final result = await source.getById(buildReadOp('USD_EUR'));
      expect(result, isA<ReadFailure<ExchangeRateCache>>());
      final failure = result as ReadFailure<ExchangeRateCache>;
      expect(failure.reason, FailureReason.serverError);
      expect(failure.message, contains('Missing rate for EUR'));
    });

    test('returns serverError when rate string is not a valid number', () async {
      final source = buildSource(
        handler: (url, {headers}) async => http.Response(
          '{"amount":1,"base":"USD","rates":{"EUR":"invalid_rate"}}',
          200,
          headers: <String, String>{'content-type': 'application/json'},
        ),
      );

      final result = await source.getById(buildReadOp('USD_EUR'));
      expect(result, isA<ReadFailure<ExchangeRateCache>>());
      expect(
        (result as ReadFailure<ExchangeRateCache>).reason,
        FailureReason.serverError,
      );
    });

    test('returns serverError when response body is JSON list instead of map', () async {
      final source = buildSource(
        handler: (url, {headers}) async => http.Response(
          '[1, 2, 3]',
          200,
          headers: <String, String>{'content-type': 'application/json'},
        ),
      );

      final result = await source.getById(buildReadOp('USD_EUR'));
      expect(result, isA<ReadFailure<ExchangeRateCache>>());
      expect(
        (result as ReadFailure<ExchangeRateCache>).reason,
        FailureReason.serverError,
      );
    });

    test('returns serverError when response is plain text instead of JSON', () async {
      final source = buildSource(
        handler: (url, {headers}) async => http.Response(
          ' Plain text gateway response ',
          200,
          headers: <String, String>{'content-type': 'text/plain'},
        ),
      );

      final result = await source.getById(buildReadOp('USD_EUR'));
      expect(result, isA<ReadFailure<ExchangeRateCache>>());
      expect(
        (result as ReadFailure<ExchangeRateCache>).reason,
        FailureReason.serverError,
      );
    });

    test('maps HTTP 500 error status to ReadFailure', () async {
      final source = buildSource(
        handler: (url, {headers}) async => http.Response(
          '{"message":"Internal Server Error"}',
          500,
          headers: <String, String>{'content-type': 'application/json'},
        ),
      );

      final result = await source.getById(buildReadOp('USD_EUR'));
      expect(result, isA<ReadFailure<ExchangeRateCache>>());
    });

    test('maps SocketException / network exceptions to connectivity ReadFailure', () async {
      final source = buildSource(
        handler: (url, {headers}) async {
          throw const SocketException('No route to host');
        },
      );

      final result = await source.getById(buildReadOp('USD_EUR'));
      expect(result, isA<ReadFailure<ExchangeRateCache>>());
      final failure = result as ReadFailure<ExchangeRateCache>;
      expect(failure.reason, FailureReason.connectivity);
      expect(failure.message, contains('Failed to fetch exchange rate'));
    });
  });
}
