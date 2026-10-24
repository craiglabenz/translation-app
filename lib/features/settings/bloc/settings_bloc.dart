import 'dart:async';

import 'package:bloc_signals/bloc_signals.dart';
import 'package:translation_app/core/ai/local_translation_engine.dart';
import 'package:translation_app/core/ai/model_manager.dart';
import 'package:translation_app/core/ai/network_translation_engine.dart';
import 'package:translation_app/core/ai/switchable_translation_engine.dart';
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
  TranslationEngine? _translationEngine;

  /// Returns the currently active [TranslationEngine], if attached.
  TranslationEngine? get translationEngine => _translationEngine;

  /// Returns the list of [SupportedLanguage] entries provided by the active
  /// [TranslationEngine], falling back to mode-appropriate defaults.
  List<SupportedLanguage> get supportedLanguages {
    final engine = _translationEngine;
    if (engine is SwitchableTranslationEngine) {
      engine.setMode(stateValue.settings.translationEngineMode);
      return engine.supportedLanguages;
    }
    final engineLanguages = engine?.supportedLanguages;
    if (engineLanguages != null && engineLanguages.isNotEmpty) {
      if (engine is LocalTranslationEngine &&
          stateValue.settings.translationEngineMode ==
              TranslationEngineMode.cloud) {
        return NetworkTranslationEngine.cloudSupportedLanguages;
      }
      return engineLanguages;
    }
    return stateValue.settings.translationEngineMode ==
            TranslationEngineMode.cloud
        ? NetworkTranslationEngine.cloudSupportedLanguages
        : LocalTranslationEngine.gemmaSupportedLanguages;
  }

  /// Switches the active [TranslationEngine] (e.g. toggling between
  /// [LocalTranslationEngine] and a cloud-based [NetworkTranslationEngine])
  /// and reconciles selected languages if needed.
  Future<void> setTranslationEngine(TranslationEngine engine) async {
    _translationEngine = engine;
    await _reconcileSupportedLanguages(stateValue.settings);
  }

  Future<void> _reconcileSupportedLanguages(AppSettings baseSettings) async {
    final available = supportedLanguages;
    if (available.isEmpty) return;

    var current = baseSettings;
    var changed = false;

    if (!available.any((l) => l.code == current.baseLanguage)) {
      final fallbackBase = available.first;
      current = current.copyWith(
        baseLanguage: fallbackBase.code,
        baseCurrency:
            AppSettings.defaultCurrencyForLanguage(fallbackBase.code) ??
            current.baseCurrency,
      );
      changed = true;
    }

    if (!available.any((l) => l.code == current.targetLanguage)) {
      final fallbackTarget = available.length > 1
          ? available[1]
          : available.first;
      current = current.copyWith(
        targetLanguage: fallbackTarget.code,
        targetCurrency:
            AppSettings.defaultCurrencyForLanguage(fallbackTarget.code) ??
            current.targetCurrency,
      );
      changed = true;
    }

    if (changed) {
      await _persistSettings(current, refreshRate: true);
    } else {
      await _persistSettings(current);
    }
  }

  /// Updates the active [TranslationEngineMode] (`onDevice` vs `cloud`),
  /// synchronizes [SwitchableTranslationEngine] if attached, and reconciles
  /// selected languages if the newly active engine does not support them.
  Future<void> updateTranslationEngineMode(TranslationEngineMode mode) async {
    final engine = _translationEngine;
    if (engine is SwitchableTranslationEngine) {
      engine.setMode(mode);
    }
    final updated = stateValue.settings.copyWith(translationEngineMode: mode);
    emit(stateValue.copyWith(settings: updated, error: null));
    await _reconcileSupportedLanguages(updated);
    if (mode == TranslationEngineMode.cloud &&
        updated.geminiApiKey.trim().isNotEmpty) {
      unawaited(discoverCloudLanguages());
    } else if (mode == TranslationEngineMode.onDevice &&
        modelManager.stateValue.isInstalled) {
      _warmupEngineOptimistically();
    }
  }

  /// Updates the active Speech-to-Text engine mode (`onDevice` vs `cloud`)
  /// independently of the translation engine mode.
  Future<void> updateSttEngineMode(TranslationEngineMode mode) async {
    final engine = _translationEngine;
    if (engine is SwitchableTranslationEngine) {
      engine.setSttMode(mode);
    }
    final updated = stateValue.settings.copyWith(sttEngineMode: mode);
    await _persistSettings(updated);
    if (mode == TranslationEngineMode.cloud &&
        updated.geminiApiKey.trim().isNotEmpty) {
      unawaited(discoverCloudLanguages());
    } else if (mode == TranslationEngineMode.onDevice) {
      unawaited(
        modelManager.checkWhisperModelReady(updated.onDeviceSttModelId),
      );
      _warmupEngineOptimistically();
    }
  }

  /// Updates the selected on-device STT model ID (`whisper-base-int8`,
  /// `whisper-tiny-int8`, `whisper-tiny-f32`, or `gemma-4`).
  Future<void> updateOnDeviceSttModelId(String modelId) async {
    final trimmed = modelId.trim();
    if (trimmed.isEmpty) return;
    final engine = _translationEngine;
    if (engine is SwitchableTranslationEngine) {
      engine.setOnDeviceSttModelId(trimmed);
    }
    final updated = stateValue.settings.copyWith(onDeviceSttModelId: trimmed);
    await _persistSettings(updated);
    await modelManager.checkWhisperModelReady(trimmed);
    if (updated.sttEngineMode == TranslationEngineMode.onDevice &&
        modelManager.stateValue.isSttModelInstalled(trimmed)) {
      _warmupEngineOptimistically();
    }
  }

  /// Updates the selected cloud Gemini STT model ID.
  Future<void> updateCloudSttModelId(String modelId) async {
    final trimmed = modelId.trim();
    if (trimmed.isEmpty) return;
    final updated = stateValue.settings.copyWith(cloudSttModelId: trimmed);
    await _persistSettings(updated);
  }

  /// Updates the selected cloud Gemini model ID (`gemini-3.8-flash` or `gemini-4`).
  Future<void> updateCloudModelId(String modelId) async {
    final trimmed = modelId.trim();
    if (trimmed.isEmpty) return;
    final updated = stateValue.settings.copyWith(cloudModelId: trimmed);
    await _persistSettings(updated);
    if (updated.translationEngineMode == TranslationEngineMode.cloud &&
        updated.geminiApiKey.trim().isNotEmpty) {
      unawaited(discoverCloudLanguages());
    }
  }

  /// Updates and persists the user's Gemini API key.
  Future<void> updateGeminiApiKey(String apiKey) async {
    final trimmed = apiKey.trim();
    final updated = stateValue.settings.copyWith(geminiApiKey: trimmed);
    await _persistSettings(updated);
    if (trimmed.isNotEmpty) {
      unawaited(discoverCloudLanguages());
    }
  }

  /// Queries the active [NetworkTranslationEngine] (if attached) to discover
  /// any additional model-supported languages.
  Future<List<SupportedLanguage>> discoverCloudLanguages() async {
    final engine = _translationEngine;
    NetworkTranslationEngine? netEngine;
    if (engine is NetworkTranslationEngine) {
      netEngine = engine;
    } else if (engine is SwitchableTranslationEngine) {
      netEngine = engine.networkEngine;
    }
    if (netEngine == null) {
      return supportedLanguages;
    }
    final discovered = await netEngine.discoverSupportedLanguages();
    if (!isClosed) {
      emit(stateValue.copyWith(error: null));
    }
    return discovered;
  }

  /// Loads persisted settings and exchange rates, refreshing expired rates.
  Future<void> load() async {
    _log.info('SettingsBloc.load() called...');
    emit(stateValue.copyWith(isLoading: true, error: null));
    try {
      final settings = await _settingsRepository.getSettings();
      final engine = _translationEngine;
      if (engine is SwitchableTranslationEngine) {
        engine.syncWithSettings(settings);
      }
      final modelReady = await modelManager.checkModelReady();
      if (isClosed) return;
      await modelManager.checkWhisperModelReady(settings.onDeviceSttModelId);
      if (isClosed) return;

      final isTranslationReady =
          settings.translationEngineMode == TranslationEngineMode.onDevice
          ? modelReady
          : settings.geminiApiKey.trim().isNotEmpty;
      final isSttReady =
          settings.sttEngineMode == TranslationEngineMode.onDevice
          ? modelManager.stateValue.isSttModelInstalled(
              settings.onDeviceSttModelId,
            )
          : settings.geminiApiKey.trim().isNotEmpty;

      if (isTranslationReady && isSttReady) {
        _warmupEngineOptimistically();
      }
      if ((settings.translationEngineMode == TranslationEngineMode.cloud ||
              settings.sttEngineMode == TranslationEngineMode.cloud) &&
          settings.geminiApiKey.trim().isNotEmpty) {
        unawaited(discoverCloudLanguages());
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

  /// Updates the rolling prior-turn context count (clamped between 0 and 10).
  Future<void> updateRollingTurnCount(int count) async {
    final clamped = count.clamp(
      AppSettings.minRollingTurnCount,
      AppSettings.maxRollingTurnCount,
    );
    final updated = stateValue.settings.copyWith(rollingTurnCount: clamped);
    await _persistSettings(updated);
  }

  /// Adds a new [ConversationContextPreset] or updates an existing preset with
  /// the same [ConversationContextPreset.id].
  Future<void> saveContextPreset(ConversationContextPreset preset) async {
    final trimmedId = preset.id.trim();
    final trimmedName = preset.name.trim();
    if (trimmedId.isEmpty || trimmedName.isEmpty) return;

    final normalized = preset.copyWith(
      id: trimmedId,
      name: trimmedName,
      icon: preset.icon.trim().isEmpty ? '💬' : preset.icon.trim(),
      keywords: preset.keywords.trim(),
    );

    final currentList = List<ConversationContextPreset>.of(
      stateValue.settings.contextPresets,
    );
    final existingIdx = currentList.indexWhere((p) => p.id == normalized.id);
    if (existingIdx >= 0) {
      currentList[existingIdx] = normalized;
    } else {
      currentList.add(normalized);
    }

    final updated = stateValue.settings.copyWith(contextPresets: currentList);
    await _persistSettings(updated);
  }

  /// Deletes a [ConversationContextPreset] by [presetId].
  Future<void> deleteContextPreset(String presetId) async {
    final currentList = stateValue.settings.contextPresets
        .where((p) => p.id != presetId)
        .toList();
    final updated = stateValue.settings.copyWith(contextPresets: currentList);
    await _persistSettings(updated);
  }

  /// Reorders [AppSettings.contextPresets] from [oldIndex] to [newIndex].
  Future<void> reorderContextPresets(int oldIndex, int newIndex) async {
    final currentList = List<ConversationContextPreset>.of(
      stateValue.settings.contextPresets,
    );
    if (oldIndex < 0 ||
        oldIndex >= currentList.length ||
        newIndex < 0 ||
        newIndex > currentList.length) {
      return;
    }
    var targetIndex = newIndex;
    if (oldIndex < targetIndex) {
      targetIndex -= 1;
    }
    if (oldIndex == targetIndex ||
        targetIndex < 0 ||
        targetIndex >= currentList.length) {
      return;
    }
    final moved = currentList.removeAt(oldIndex);
    currentList.insert(targetIndex, moved);
    final updated = stateValue.settings.copyWith(contextPresets: currentList);
    await _persistSettings(updated);
  }

  /// Resets [AppSettings.contextPresets] to [AppSettings.defaultContextPresets].
  Future<void> resetContextPresetsToDefaults() async {
    final updated = stateValue.settings.copyWith(
      contextPresets: AppSettings.defaultContextPresets,
    );
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

  /// Downloads an on-device Whisper STT model variant.
  Future<bool> downloadWhisperModel([String? modelId]) async {
    final targetId = modelId ?? stateValue.settings.onDeviceSttModelId;
    final success = await modelManager.downloadWhisperModel(targetId);
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
