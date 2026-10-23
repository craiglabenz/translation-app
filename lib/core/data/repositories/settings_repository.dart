import 'package:data_layer/data_layer.dart';
import 'package:translation_app/core/data/models/app_settings.dart';
import 'package:translation_app/core/data/models/exchange_rate_cache.dart';
import 'package:translation_app/core/logging/app_logger.dart';

/// Repository managing persistent [AppSettings] and cached [ExchangeRateCache]
/// records with a 7-day TTL and offline fallback.
class SettingsRepository extends Repository<AppSettings> {
  SettingsRepository({
    required Source<AppSettings> settingsSource,
    required Source<ExchangeRateCache> localExchangeRateSource,
    required Source<ExchangeRateCache> remoteExchangeRateSource,
    this.ttl = ExchangeRateCache.defaultTtl,
    super.getTime,
  }) : _exchangeRateRepository = Repository<ExchangeRateCache>(
         SourceList<ExchangeRateCache>(
           sources: <Source<ExchangeRateCache>>[
             localExchangeRateSource,
             remoteExchangeRateSource,
           ],
           bindings: ExchangeRateCache.bindings,
           getTime: getTime,
         ),
         getTime: getTime,
       ),
       super(
         SourceList<AppSettings>(
           sources: <Source<AppSettings>>[settingsSource],
           bindings: AppSettings.bindings,
           getTime: getTime,
         ),
       );

  static final _log = AppLogger.of('SettingsRepository');

  final Repository<ExchangeRateCache> _exchangeRateRepository;

  /// Time-to-live for cached exchange rates (defaults to 7 days).
  final Duration ttl;

  ExchangeRateCache? _lastHydratedRate;

  /// Most recently hydrated exchange rate, if available.
  ExchangeRateCache? get lastHydratedRate => _lastHydratedRate;

  @override
  Future<void> performInitialization() async {
    await _exchangeRateRepository.ready;
    await super.performInitialization();
  }

  /// Loads the persisted [AppSettings], initializing defaults if none exist.
  Future<AppSettings> getSettings() async {
    final sw = Stopwatch()..start();
    _log.info('[PERF] SettingsRepository.getSettings() START');
    final existing = await getById(
      AppSettings.defaultId,
      details: RequestDetails.read(requestType: RequestType.local),
    );
    if (existing != null) {
      final normalized = existing.cloudModelId == 'gemini-4'
          ? existing.copyWith(cloudModelId: 'gemini-3.1-pro')
          : existing;
      if (normalized != existing) {
        await saveSettings(normalized);
      }
      sw.stop();
      _log.info(
        '[PERF] SettingsRepository.getSettings() FINISH '
        '(${sw.elapsedMilliseconds}ms, cached=true)',
      );
      return normalized;
    }
    const defaults = AppSettings();
    await saveSettings(defaults);
    sw.stop();
    _log.info(
      '[PERF] SettingsRepository.getSettings() FINISH '
      '(${sw.elapsedMilliseconds}ms, initializedDefaults=true)',
    );
    return defaults;
  }

  /// Persists the updated [settings] locally.
  Future<AppSettings> saveSettings(AppSettings settings) async {
    final saved = await setItem(
      settings,
      details: RequestDetails.write(requestType: RequestType.local),
    );
    return saved ?? settings;
  }

  /// Retrieves the exchange rate for [baseCurrency] and [targetCurrency]
  /// enforcing the 7-day TTL policy:
  /// 1. If cached rate is < 7 days old (and [forceRefresh] is false), returns
  ///    immediately from local storage.
  /// 2. If older or missing, fetches from Frankfurter API and updates Hive.
  /// 3. If offline and cache is expired, falls back to the expired cached rate
  ///    with `isStale: true`.
  Future<ExchangeRateCache> getExchangeRate({
    required String baseCurrency,
    required String targetCurrency,
    bool forceRefresh = false,
  }) async {
    final base = baseCurrency.toUpperCase();
    final target = targetCurrency.toUpperCase();
    final now = getTime();

    if (base == target) {
      final identityRate = ExchangeRateCache(
        baseCurrency: base,
        targetCurrency: target,
        rate: 1.0,
        updatedAt: now,
        isStale: false,
      );
      _lastHydratedRate = identityRate;
      return identityRate;
    }

    final pairId = ExchangeRateCache.idForPair(base, target);

    final cached = await _exchangeRateRepository.getById(
      pairId,
      details: RequestDetails.read(requestType: RequestType.local),
    );

    if (!forceRefresh &&
        cached != null &&
        !cached.isExpired(now: now, ttl: ttl)) {
      _log.fine('Using fresh cached exchange rate for $pairId: ${cached.rate}');
      final freshCached = cached.copyWith(isStale: false);
      _lastHydratedRate = freshCached;
      return freshCached;
    }

    _log.info('Refreshing exchange rate for $pairId from remote Frankfurter API...');
    final refreshed = await _exchangeRateRepository.getById(
      pairId,
      details: RequestDetails.read(requestType: RequestType.refresh),
    );

    if (refreshed != null) {
      _log.info('Refreshed exchange rate for $pairId: ${refreshed.rate}');
      final cleanRefreshed = refreshed.copyWith(isStale: false);
      await _exchangeRateRepository.setItem(
        cleanRefreshed,
        details: RequestDetails.write(requestType: RequestType.local),
      );
      _lastHydratedRate = cleanRefreshed;
      return cleanRefreshed;
    }

    if (cached != null) {
      _log.warning(
        'Remote refresh failed for $pairId; falling back to stale cached rate ${cached.rate}',
      );
      final staleFallback = cached.copyWith(isStale: true);
      _lastHydratedRate = staleFallback;
      return staleFallback;
    }

    final offlineDefault = ExchangeRateCache(
      baseCurrency: base,
      targetCurrency: target,
      rate: 1.0,
      updatedAt: now,
      isStale: true,
    );
    _lastHydratedRate = offlineDefault;
    return offlineDefault;
  }

  /// Eagerly loads settings and hydrates current exchange rates on app startup.
  Future<(AppSettings, ExchangeRateCache)> hydrateOnStartup() async {
    final sw = Stopwatch()..start();
    _log.info('[PERF] SettingsRepository.hydrateOnStartup() START');
    final settings = await getSettings();
    final rate = await getExchangeRate(
      baseCurrency: settings.baseCurrency,
      targetCurrency: settings.targetCurrency,
    );
    sw.stop();
    _log.info(
      '[PERF] SettingsRepository.hydrateOnStartup() FINISH '
      '(${sw.elapsedMilliseconds}ms)',
    );
    return (settings, rate);
  }
}
