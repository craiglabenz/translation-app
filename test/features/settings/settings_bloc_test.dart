import 'dart:typed_data';

import 'package:data_layer/data_layer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:translation_app/core/ai/model_manager.dart';
import 'package:translation_app/core/ai/translation_engine.dart';
import 'package:translation_app/core/data/models/app_settings.dart';
import 'package:translation_app/core/data/models/exchange_rate_cache.dart';
import 'package:translation_app/core/data/models/message.dart';
import 'package:translation_app/core/data/repositories/settings_repository.dart';
import 'package:translation_app/features/settings/bloc/settings_bloc.dart';
import 'package:translation_app/features/settings/bloc/settings_state.dart';

class _TrackingTranslationEngine implements TranslationEngine {
  _TrackingTranslationEngine({this._customLanguages});

  final List<SupportedLanguage>? _customLanguages;
  int initializeCallCount = 0;

  @override
  List<SupportedLanguage> get supportedLanguages =>
      _customLanguages ?? AppSettings.supportedLanguages;

  @override
  Future<void> initialize() async {
    initializeCallCount++;
  }

  @override
  Future<TranslationResult> translateAudioChunk({
    required Float32List audioWavChunk,
    required String baseLanguage,
    required String targetLanguage,
    required double exchangeRate,
    required String baseCurrency,
    required String targetCurrency,
    void Function(TranslationResult partialResult)? onPartialResult,
  }) async {
    return const TranslationResult(
      sourceLanguage: 'en',
      translatedText: 'Hola',
    );
  }

  @override
  Future<String> summarizeConversation({
    required List<Message> messages,
    required String baseLanguage,
    required String targetLanguage,
  }) async {
    return 'Quick test summary';
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  group('SettingsState', () {
    test('provides expected defaults and supports copyWith/equality', () {
      const s1 = SettingsState();
      const s2 = SettingsState();
      expect(s1, equals(s2));
      expect(s1.settings, equals(const AppSettings()));
      expect(s1.exchangeRate, isNull);
      expect(s1.isLoading, isFalse);
      expect(s1.isRefreshingRates, isFalse);
      expect(s1.error, isNull);

      final modified = s1.copyWith(isLoading: true, error: 'Network error');
      expect(modified.isLoading, isTrue);
      expect(modified.error, 'Network error');
    });
  });

  group('SettingsBloc', () {
    late DateTime now;
    late LocalMemorySource<AppSettings> settingsSource;
    late LocalMemorySource<ExchangeRateCache> localRateSource;
    late RemoteMemorySource<ExchangeRateCache> remoteRateSource;
    late SettingsRepository settingsRepo;
    late ModelManager modelManager;
    late SettingsBloc bloc;
    String? lastDownloadedUrl;

    Future<void> seedRemoteRate(
      String base,
      String target,
      double rate,
    ) async {
      await remoteRateSource.setItem(
        WriteOperation<ExchangeRateCache>(
          operationId: 'seed_${base}_$target',
          item: ExchangeRateCache(
            baseCurrency: base,
            targetCurrency: target,
            rate: rate,
            updatedAt: now,
          ),
          details: RequestDetails.write(),
          createdAt: now,
        ),
      );
    }

    setUp(() async {
      now = DateTime.utc(2026, 4, 1, 12);
      settingsSource = LocalMemorySource<AppSettings>(
        bindings: AppSettings.bindings,
        now: () => now,
      );
      localRateSource = LocalMemorySource<ExchangeRateCache>(
        bindings: ExchangeRateCache.bindings,
        now: () => now,
      );
      remoteRateSource = RemoteMemorySource<ExchangeRateCache>(
        bindings: ExchangeRateCache.bindings,
        now: () => now,
      );

      await seedRemoteRate('USD', 'EUR', 0.92);
      await seedRemoteRate('EUR', 'USD', 1.087);
      await seedRemoteRate('GBP', 'EUR', 1.17);
      await seedRemoteRate('USD', 'JPY', 153.4);

      settingsRepo = SettingsRepository(
        settingsSource: settingsSource,
        localExchangeRateSource: localRateSource,
        remoteExchangeRateSource: remoteRateSource,
        getTime: () => now,
      );

      lastDownloadedUrl = null;
      modelManager = ModelManager(
        isInstalledCheck: () async => true,
        installRunner:
            ({
              required downloadUrl,
              required onProgress,
              cancelToken,
            }) async {
              lastDownloadedUrl = downloadUrl;
              onProgress(1.0);
            },
      );

      bloc = SettingsBloc(
        settingsRepository: settingsRepo,
        modelManager: modelManager,
      );
    });

    tearDown(() async {
      await bloc.close();
      await modelManager.close();
      settingsRepo.close();
    });

    test('load() populates settings, checks model readiness, and fetches exchange rate', () async {
      await bloc.load();

      expect(bloc.stateValue.isLoading, isFalse);
      expect(bloc.stateValue.error, isNull);
      expect(bloc.stateValue.settings.baseLanguage, 'en');
      expect(bloc.stateValue.settings.targetLanguage, 'es');
      expect(bloc.stateValue.exchangeRate?.rate, 0.92);
      expect(modelManager.stateValue.isInstalled, isTrue);
    });

    test('updateBaseLanguage and updateTargetLanguage persist to repository and link currencies one-way', () async {
      await seedRemoteRate('EUR', 'KRW', 1480.0);
      await seedRemoteRate('CHF', 'KRW', 1520.0);
      await bloc.load();

      const french = SupportedLanguage(
        code: 'fr',
        name: 'French',
        nativeName: 'Français',
      );
      const korean = SupportedLanguage(
        code: 'ko',
        name: 'Korean',
        nativeName: '한국어',
      );

      // Changing baseLanguage to French ('fr') automatically updates baseCurrency to 'EUR'
      await bloc.updateBaseLanguage(french);
      expect(bloc.stateValue.settings.baseLanguage, 'fr');
      expect(bloc.stateValue.settings.baseCurrency, 'EUR');
      expect((await settingsRepo.getSettings()).baseLanguage, 'fr');
      expect((await settingsRepo.getSettings()).baseCurrency, 'EUR');

      // Changing targetLanguage to Korean ('ko') automatically updates targetCurrency to 'KRW'
      // and refreshes the exchange rate (EUR -> KRW = 1480.0)
      await bloc.updateTargetLanguage(korean);
      expect(bloc.stateValue.settings.targetLanguage, 'ko');
      expect(bloc.stateValue.settings.targetCurrency, 'KRW');
      expect((await settingsRepo.getSettings()).targetLanguage, 'ko');
      expect((await settingsRepo.getSettings()).targetCurrency, 'KRW');
      expect(bloc.stateValue.exchangeRate?.baseCurrency, 'EUR');
      expect(bloc.stateValue.exchangeRate?.targetCurrency, 'KRW');
      expect(bloc.stateValue.exchangeRate?.rate, 1480.0);

      // Changing currency does NOT change the language (e.g. French & Korean speakers in Switzerland)
      const chf = SupportedCurrency(
        code: 'CHF',
        name: 'Swiss Franc',
        symbol: 'CHF',
      );
      await bloc.updateBaseCurrency(chf);
      expect(bloc.stateValue.settings.baseCurrency, 'CHF');
      expect(bloc.stateValue.settings.baseLanguage, 'fr');
      expect(bloc.stateValue.settings.targetLanguage, 'ko');
      expect(bloc.stateValue.exchangeRate?.rate, 1520.0);
    });

    test('updateBaseCurrency and updateTargetCurrency refresh the exchange rate', () async {
      await bloc.load();
      expect(bloc.stateValue.exchangeRate?.rate, 0.92);

      const gbp = SupportedCurrency(
        code: 'GBP',
        name: 'British Pound',
        symbol: '£',
      );
      await bloc.updateBaseCurrency(gbp);
      expect(bloc.stateValue.settings.baseCurrency, 'GBP');
      expect(bloc.stateValue.exchangeRate?.baseCurrency, 'GBP');
      expect(bloc.stateValue.exchangeRate?.targetCurrency, 'EUR');
      expect(bloc.stateValue.exchangeRate?.rate, 1.17);

      const usd = SupportedCurrency(
        code: 'USD',
        name: 'US Dollar',
        symbol: r'$',
      );
      const jpy = SupportedCurrency(
        code: 'JPY',
        name: 'Japanese Yen',
        symbol: '¥',
      );
      await bloc.updateBaseCurrency(usd);
      await bloc.updateTargetCurrency(jpy);
      expect(bloc.stateValue.settings.targetCurrency, 'JPY');
      expect(bloc.stateValue.exchangeRate?.rate, 153.4);
    });

    test('swapPair swaps languages and currencies and updates exchange rate', () async {
      await bloc.load();
      expect(bloc.stateValue.settings.baseLanguage, 'en');
      expect(bloc.stateValue.settings.targetLanguage, 'es');
      expect(bloc.stateValue.settings.baseCurrency, 'USD');
      expect(bloc.stateValue.settings.targetCurrency, 'EUR');
      expect(bloc.stateValue.exchangeRate?.rate, 0.92);

      await bloc.swapPair();
      expect(bloc.stateValue.settings.baseLanguage, 'es');
      expect(bloc.stateValue.settings.targetLanguage, 'en');
      expect(bloc.stateValue.settings.baseCurrency, 'EUR');
      expect(bloc.stateValue.settings.targetCurrency, 'USD');
      expect(bloc.stateValue.exchangeRate?.rate, 1.087);

      final persisted = await settingsRepo.getSettings();
      expect(persisted.baseLanguage, 'es');
      expect(persisted.baseCurrency, 'EUR');
    });

    test('updateModelDownloadUrl trims custom URL and restores default when blank', () async {
      await bloc.load();

      await bloc.updateModelDownloadUrl(
        '  https://mirror.example.com/gemma4.litertlm  ',
      );
      expect(
        bloc.stateValue.settings.modelDownloadUrl,
        'https://mirror.example.com/gemma4.litertlm',
      );

      // Blank/whitespace input reverts to defaultModelDownloadUrl
      await bloc.updateModelDownloadUrl('   ');
      expect(
        bloc.stateValue.settings.modelDownloadUrl,
        AppSettings.defaultModelDownloadUrl,
      );
    });

    test('refreshExchangeRates forces remote rate update', () async {
      await bloc.load();
      expect(bloc.stateValue.exchangeRate?.rate, 0.92);

      // Update remote rate while local cache is still fresh
      await seedRemoteRate('USD', 'EUR', 0.965);

      await bloc.refreshExchangeRates();
      expect(bloc.stateValue.isRefreshingRates, isFalse);
      expect(bloc.stateValue.exchangeRate?.rate, 0.965);
    });

    test('downloadModel forwards configured modelDownloadUrl to ModelManager', () async {
      await bloc.load();
      await bloc.updateModelDownloadUrl('https://custom.host/model.litertlm');

      final success = await bloc.downloadModel();
      expect(success, isTrue);
      expect(lastDownloadedUrl, 'https://custom.host/model.litertlm');
    });

    test('optimistically warms up TranslationEngine on load() and downloadModel()', () async {
      final trackingEngine = _TrackingTranslationEngine();
      final warmupBloc = SettingsBloc(
        settingsRepository: settingsRepo,
        modelManager: modelManager,
        translationEngine: trackingEngine,
      );

      await warmupBloc.load();
      await Future<void>.delayed(Duration.zero);
      expect(trackingEngine.initializeCallCount, 1);

      await warmupBloc.downloadModel();
      await Future<void>.delayed(Duration.zero);
      expect(trackingEngine.initializeCallCount, 2);

      await warmupBloc.close();
    });

    test('updateTextScaleFactor clamps between 0.5 and 3.0 and persists to SettingsRepository', () async {
      await bloc.load();
      expect(bloc.stateValue.settings.textScaleFactor, 1.0);

      await bloc.updateTextScaleFactor(1.75);
      expect(bloc.stateValue.settings.textScaleFactor, 1.75);
      expect((await settingsRepo.getSettings()).textScaleFactor, 1.75);

      // Below minimum (0.5) clamps to 0.5
      await bloc.updateTextScaleFactor(0.1);
      expect(bloc.stateValue.settings.textScaleFactor, 0.5);
      expect((await settingsRepo.getSettings()).textScaleFactor, 0.5);

      // Above maximum (3.0) clamps to 3.0
      await bloc.updateTextScaleFactor(5.0);
      expect(bloc.stateValue.settings.textScaleFactor, 3.0);
      expect((await settingsRepo.getSettings()).textScaleFactor, 3.0);
    });

    test('supportedLanguages delegates to active TranslationEngine and setTranslationEngine reconciles languages', () async {
      await bloc.load();
      expect(bloc.supportedLanguages, equals(AppSettings.supportedLanguages));

      // Switch to an engine that only supports French and German
      const cloudSubset = <SupportedLanguage>[
        SupportedLanguage(code: 'fr', name: 'French', nativeName: 'Français'),
        SupportedLanguage(code: 'de', name: 'German', nativeName: 'Deutsch'),
      ];
      final customEngine = _TrackingTranslationEngine(
        customLanguages: cloudSubset,
      );

      await bloc.setTranslationEngine(customEngine);
      expect(bloc.translationEngine, same(customEngine));
      expect(bloc.supportedLanguages, equals(cloudSubset));
      // Because 'en' and 'es' were not in cloudSubset, they reconcile to 'fr' and 'de'
      expect(bloc.stateValue.settings.baseLanguage, 'fr');
      expect(bloc.stateValue.settings.targetLanguage, 'de');
      expect(bloc.stateValue.settings.baseCurrency, 'EUR');
      expect(bloc.stateValue.settings.targetCurrency, 'EUR');
    });
  });
}
