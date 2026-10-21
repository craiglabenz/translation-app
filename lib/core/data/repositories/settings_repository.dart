import 'package:data_layer/data_layer.dart';
import 'package:translation_app/core/data/models/app_settings.dart';
import 'package:translation_app/core/data/models/exchange_rate_cache.dart';

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
    final existing = await getById(
      AppSettings.defaultId,
      details: RequestDetails.read(requestType: RequestType.local),
    );
    if (existing != null) {
      return existing;
    }
    const defaults = AppSettings();
    await saveSettings(defaults);
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
      final freshCached = cached.copyWith(isStale: false);
      _lastHydratedRate = freshCached;
      return freshCached;
    }

    final refreshed = await _exchangeRateRepository.getById(
      pairId,
      details: RequestDetails.read(requestType: RequestType.refresh),
    );

    if (refreshed != null) {
      final cleanRefreshed = refreshed.copyWith(isStale: false);
      await _exchangeRateRepository.setItem(
        cleanRefreshed,
        details: RequestDetails.write(requestType: RequestType.local),
      );
      _lastHydratedRate = cleanRefreshed;
      return cleanRefreshed;
    }

    if (cached != null) {
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
    final settings = await getSettings();
    final rate = await getExchangeRate(
      baseCurrency: settings.baseCurrency,
      targetCurrency: settings.targetCurrency,
    );
    return (settings, rate);
  }
}
