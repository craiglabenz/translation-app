import 'package:bloc_signals/bloc_signals.dart';
import 'package:translation_app/core/ai/model_manager.dart';
import 'package:translation_app/core/data/models/app_settings.dart';
import 'package:translation_app/core/data/repositories/settings_repository.dart';
import 'package:translation_app/features/settings/bloc/settings_state.dart';

/// Manages user preferences, language/currency pairs, and exchange rate status.
class SettingsBloc extends CubitSignal<SettingsState> {
  SettingsBloc({
    required this._settingsRepository,
    required this.modelManager,
  }) : super(initialState: const SettingsState());

  final SettingsRepository _settingsRepository;
  final ModelManager modelManager;

  /// Loads persisted settings and exchange rates, refreshing expired rates.
  Future<void> load() async {
    emit(stateValue.copyWith(isLoading: true, error: null));
    try {
      final settings = await _settingsRepository.getSettings();
      await modelManager.checkModelReady();
      if (isClosed) return;

      emit(stateValue.copyWith(settings: settings, isLoading: false));

      final rate = await _settingsRepository.getExchangeRate(
        baseCurrency: settings.baseCurrency,
        targetCurrency: settings.targetCurrency,
      );
      if (isClosed) return;

      emit(stateValue.copyWith(exchangeRate: rate));
    } catch (e) {
      if (isClosed) return;
      emit(
        stateValue.copyWith(
          isLoading: false,
          error: 'Failed to load settings: $e',
        ),
      );
    }
  }

  /// Updates the primary (base) language.
  Future<void> updateBaseLanguage(SupportedLanguage language) async {
    final updated = stateValue.settings.copyWith(baseLanguage: language.code);
    await _persistSettings(updated);
  }

  /// Updates the target language.
  Future<void> updateTargetLanguage(SupportedLanguage language) async {
    final updated = stateValue.settings.copyWith(targetLanguage: language.code);
    await _persistSettings(updated);
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
  Future<bool> downloadModel() {
    return modelManager.downloadModel(
      fallbackUrl: stateValue.settings.modelDownloadUrl,
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
