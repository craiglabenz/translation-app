import 'dart:async';

import 'package:bloc_signals/bloc_signals.dart';
import 'package:translation_app/core/ai/model_manager.dart';
import 'package:translation_app/core/ai/translation_engine.dart';
import 'package:translation_app/core/data/models/app_settings.dart';
import 'package:translation_app/core/data/repositories/settings_repository.dart';
import 'package:translation_app/core/logging/app_logger.dart';
import 'package:translation_app/features/settings/bloc/settings_state.dart';

/// Manages user preferences, language/currency pairs, and exchange rate status.
class SettingsBloc extends CubitSignal<SettingsState> {
  SettingsBloc({
    required this._settingsRepository,
    required this.modelManager,
    this._translationEngine,
  }) : super(initialState: const SettingsState());

  static final _log = AppLogger.of('SettingsBloc');

  final SettingsRepository _settingsRepository;
  final ModelManager modelManager;
  final TranslationEngine? _translationEngine;

  /// Loads persisted settings and exchange rates, refreshing expired rates.
  Future<void> load() async {
    _log.info('SettingsBloc.load() called...');
    emit(stateValue.copyWith(isLoading: true, error: null));
    try {
      final settings = await _settingsRepository.getSettings();
      final modelReady = await modelManager.checkModelReady();
      if (isClosed) return;

      if (modelReady) {
        _warmupEngineOptimistically();
      }

      emit(stateValue.copyWith(settings: settings, isLoading: false));

      final rate = await _settingsRepository.getExchangeRate(
        baseCurrency: settings.baseCurrency,
        targetCurrency: settings.targetCurrency,
      );
      if (isClosed) return;

      _log.info(
        'SettingsBloc.load() complete: pair=${settings.pairLabel}, '
        'rate=${rate.rate} (isStale=${rate.isStale}), '
        'modelInstalled=${modelManager.stateValue.isInstalled}',
      );
      emit(stateValue.copyWith(exchangeRate: rate));
    } catch (e, st) {
      _log.severe('SettingsBloc.load() failed', e, st);
      if (isClosed) return;
      emit(
        stateValue.copyWith(
          isLoading: false,
          error: 'Failed to load settings: $e',
        ),
      );
    }
  }

  /// Updates the primary (base) language and automatically updates
  /// [AppSettings.baseCurrency] to match the language's default currency.
  Future<void> updateBaseLanguage(SupportedLanguage language) async {
    final current = stateValue.settings;
    final matchedCurrency =
        AppSettings.defaultCurrencyForLanguage(language.code) ??
        current.baseCurrency;
    final currencyChanged = matchedCurrency != current.baseCurrency;
    final updated = current.copyWith(
      baseLanguage: language.code,
      baseCurrency: matchedCurrency,
    );
    await _persistSettings(updated, refreshRate: currencyChanged);
  }

  /// Updates the target language and automatically updates
  /// [AppSettings.targetCurrency] to match the language's default currency.
  Future<void> updateTargetLanguage(SupportedLanguage language) async {
    final current = stateValue.settings;
    final matchedCurrency =
        AppSettings.defaultCurrencyForLanguage(language.code) ??
        current.targetCurrency;
    final currencyChanged = matchedCurrency != current.targetCurrency;
    final updated = current.copyWith(
      targetLanguage: language.code,
      targetCurrency: matchedCurrency,
    );
    await _persistSettings(updated, refreshRate: currencyChanged);
  }

  /// Updates the primary (base) currency and refreshes its exchange rate.
  Future<void> updateBaseCurrency(SupportedCurrency currency) async {
    final updated = stateValue.settings.copyWith(baseCurrency: currency.code);
    await _persistSettings(updated, refreshRate: true);
  }

  /// Updates the target currency and refreshes its exchange rate.
  Future<void> updateTargetCurrency(SupportedCurrency currency) async {
    final updated = stateValue.settings.copyWith(targetCurrency: currency.code);
    await _persistSettings(updated, refreshRate: true);
  }

  /// Swaps the base and target languages and currencies.
  Future<void> swapPair() async {
    final current = stateValue.settings;
    final updated = current.copyWith(
      baseLanguage: current.targetLanguage,
      targetLanguage: current.baseLanguage,
      baseCurrency: current.targetCurrency,
      targetCurrency: current.baseCurrency,
    );
    await _persistSettings(updated, refreshRate: true);
  }

  /// Updates the model download URL in settings.
  Future<void> updateModelDownloadUrl(String url) async {
    final normalized = url.trim().isEmpty
        ? AppSettings.defaultModelDownloadUrl
        : url.trim();
    final updated = stateValue.settings.copyWith(modelDownloadUrl: normalized);
    await _persistSettings(updated);
  }

  /// Updates the user text scale multiplier (clamped between 0.5 and 3.0).
  Future<void> updateTextScaleFactor(double scaleFactor) async {
    final clamped = scaleFactor.clamp(
      AppSettings.minTextScaleFactor,
      AppSettings.maxTextScaleFactor,
    );
    final rounded = (clamped * 100).round() / 100.0;
    final updated = stateValue.settings.copyWith(textScaleFactor: rounded);
    await _persistSettings(updated);
  }

  /// Forces an immediate refresh of the exchange rate from Frankfurter.
  Future<void> refreshExchangeRates() async {
    emit(stateValue.copyWith(isRefreshingRates: true, error: null));
    try {
      final rate = await _settingsRepository.getExchangeRate(
        baseCurrency: stateValue.settings.baseCurrency,
        targetCurrency: stateValue.settings.targetCurrency,
        forceRefresh: true,
      );
      if (isClosed) return;
      emit(
        stateValue.copyWith(
          exchangeRate: rate,
          isRefreshingRates: false,
        ),
      );
    } catch (e) {
      if (isClosed) return;
      emit(
        stateValue.copyWith(
          isRefreshingRates: false,
          error: 'Failed to refresh exchange rate: $e',
        ),
      );
    }
  }

  /// Downloads the Gemma 4 E2B model using the configured URL.
  Future<bool> downloadModel() async {
    final success = await modelManager.downloadModel(
      fallbackUrl: stateValue.settings.modelDownloadUrl,
    );
    if (success && !isClosed) {
      _warmupEngineOptimistically();
    }
    return success;
  }

  void _warmupEngineOptimistically() {
    final engine = _translationEngine;
    if (engine == null) return;
    _log.info('Optimistically warming up TranslationEngine in memory...');
    unawaited(
      engine.initialize().then(
        (_) => _log.info('Optimistic TranslationEngine warmup complete.'),
        onError: (Object e, StackTrace st) {
          _log.fine(
            'Optimistic TranslationEngine warmup deferred: $e',
            e,
            st,
          );
        },
      ),
    );
  }

  Future<void> _persistSettings(
    AppSettings updated, {
    bool refreshRate = false,
  }) async {
    emit(stateValue.copyWith(settings: updated, error: null));
    await _settingsRepository.saveSettings(updated);
    if (refreshRate && !isClosed) {
      final rate = await _settingsRepository.getExchangeRate(
        baseCurrency: updated.baseCurrency,
        targetCurrency: updated.targetCurrency,
      );
      if (!isClosed) {
        emit(stateValue.copyWith(exchangeRate: rate));
      }
    }
  }
}
