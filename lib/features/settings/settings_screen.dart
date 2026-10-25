import 'package:bloc_signals_flutter/bloc_signals_flutter.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:get_it/get_it.dart';
import 'package:material_ui/material_ui.dart';
import 'package:settings_ui/settings_ui.dart';
import 'package:translation_app/core/ai/model_manager.dart';
import 'package:translation_app/core/data/models/app_settings.dart';
import 'package:translation_app/core/routing/routing.dart';
import 'package:translation_app/features/settings/bloc/settings_bloc.dart';
import 'package:translation_app/features/settings/bloc/settings_state.dart';

/// Platform-idiomatic Settings Screen built with `pkg:settings_ui`.
///
/// Uses native grouped cards and `CupertinoPageRoute` nested pages on iOS/macOS,
/// and Material 3 settings rows and `MaterialPageRoute` nested pages on Android/Web.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    this.settingsBloc,
  });

  final SettingsBloc? settingsBloc;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final SettingsBloc _settingsBloc;
  late final TextEditingController _urlController;
  late final TextEditingController _geminiApiKeyController;
  final ValueNotifier<bool> _largeTitleHidden = ValueNotifier<bool>(false);
  bool _obscureGeminiApiKey = true;

  @override
  void initState() {
    super.initState();
    _settingsBloc = widget.settingsBloc ?? GetIt.I<SettingsBloc>();
    _urlController = TextEditingController(
      text: _settingsBloc.stateValue.settings.modelDownloadUrl,
    );
    _geminiApiKeyController = TextEditingController(
      text: _settingsBloc.stateValue.settings.geminiApiKey,
    );
  }

  @override
  void dispose() {
    _urlController.dispose();
    _geminiApiKeyController.dispose();
    _largeTitleHidden.dispose();
    super.dispose();
  }

  void _navigateBack() {
    if (GetIt.I.isRegistered<AppRouter>()) {
      final router = GetIt.I<AppRouter>().config.router;
      if (router.stack.length > 1) {
        router.pop();
        return;
      }
    }
    Navigator.of(context).maybePop();
  }

  bool _isCupertinoPlatform(BuildContext context) {
    final platform = Theme.of(context).platform;
    return platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
  }

  Widget _buildCheckmark(BuildContext context) {
    if (_isCupertinoPlatform(context)) {
      return const Icon(
        CupertinoIcons.checkmark_alt,
        color: CupertinoColors.activeBlue,
        size: 20,
      );
    }
    return Icon(
      Icons.check_rounded,
      color: Theme.of(context).colorScheme.primary,
      size: 20,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCupertino = _isCupertinoPlatform(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iosBackground = isDark
        ? const Color(0xFF000000)
        : const Color(0xFFF2F2F7);

    return Scaffold(
      backgroundColor: isCupertino ? iosBackground : null,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildPlatformHeader(
            context,
            isCupertino: isCupertino,
            isDark: isDark,
          ),
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: NotificationListener<ScrollUpdateNotification>(
                onNotification: (notification) {
                  if (notification.depth == 0) {
                    _largeTitleHidden.value = notification.metrics.pixels > 40;
                  }
                  return false;
                },
                child: BlocSignalBuilder<SettingsBloc, SettingsState>(
                  bloc: _settingsBloc,
                  builder: (context, state) {
                    final settings = state.settings;
                    final rateCache = state.exchangeRate;

                    if (_urlController.text != settings.modelDownloadUrl &&
                        !FocusScope.of(context).hasFocus) {
                      _urlController.text = settings.modelDownloadUrl;
                    }
                    if (_geminiApiKeyController.text != settings.geminiApiKey &&
                        !FocusScope.of(context).hasFocus) {
                      _geminiApiKeyController.text = settings.geminiApiKey;
                    }

                    final isCloudStt =
                        settings.sttEngineMode == TranslationEngineMode.cloud;
                    final isCloudTranslation =
                        settings.translationEngineMode ==
                        TranslationEngineMode.cloud;
                    final anyCloudEnabled = isCloudStt || isCloudTranslation;
                    final bothStepsCloud = isCloudStt && isCloudTranslation;
                    final hasCloudKey = settings.geminiApiKey
                        .trim()
                        .isNotEmpty;

                    final selectedCloudSttModel = AppSettings
                        .supportedCloudModels
                        .firstWhere(
                          (m) => m.id == settings.cloudSttModelId,
                          orElse: () => AppSettings.supportedCloudModels.first,
                        );
                    final selectedCloudTranslationModel = AppSettings
                        .supportedCloudModels
                        .firstWhere(
                          (m) => m.id == settings.cloudModelId,
                          orElse: () => AppSettings.supportedCloudModels.first,
                        );

                    final availableLanguages =
                        _settingsBloc.supportedLanguages.isNotEmpty
                        ? _settingsBloc.supportedLanguages
                        : AppSettings.supportedLanguages;
                    final baseLang = availableLanguages.firstWhere(
                      (l) => l.code == settings.baseLanguage,
                      orElse: () => availableLanguages.first,
                    );
                    final targetLang = availableLanguages.firstWhere(
                      (l) => l.code == settings.targetLanguage,
                      orElse: () => availableLanguages.length > 1
                          ? availableLanguages[1]
                          : availableLanguages.first,
                    );
                    final baseCurr = AppSettings.supportedCurrencies.firstWhere(
                      (c) => c.code == settings.baseCurrency,
                      orElse: () => AppSettings.supportedCurrencies.first,
                    );
                    final targetCurr = AppSettings.supportedCurrencies
                        .firstWhere(
                          (c) => c.code == settings.targetCurrency,
                          orElse: () => AppSettings.supportedCurrencies[1],
                        );

                    final effectivePresets = settings.contextPresets;

                    return BlocSignalBuilder<ModelManager, ModelDownloadState>(
                      bloc: _settingsBloc.modelManager,
                      builder: (context, modelState) {
                        return SettingsList(
                          sections: [
                            if (isCupertino)
                              CustomSettingsSection(
                                child: Padding(
                                  padding: const EdgeInsetsDirectional.only(
                                    start: 20,
                                    end: 20,
                                    top: 3,
                                    bottom: 8,
                                  ),
                                  child: Text(
                                    'Translation Settings',
                                    style: TextStyle(
                                      fontSize: 34,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.4,
                                      height: 41 / 34,
                                      color: isDark
                                          ? Colors.white
                                          : Colors.black,
                                    ),
                                  ),
                                ),
                              ),

                            // 1. Speech-to-Text (Step 1)
                            SettingsSection(
                              key: const ValueKey('settings_step1_stt_card'),
                              title: const Text('Speech-to-Text'),
                              tiles: [
                                SettingsTile.navigation(
                                  key: const ValueKey(
                                    'stt_engine_mode_selector',
                                  ),
                                  leading: const Icon(Icons.mic_rounded),
                                  title: const Text('Speech-to-Text Engine'),
                                  value: Text(
                                    isCloudStt
                                        ? 'Cloud (Gemini)'
                                        : 'On-Device (Gemma 4)',
                                  ),
                                  description: isCloudStt
                                      ? null
                                      : const Text(
                                          'Step 1 (Audio → Text): On-device Gemma 4 E2B transcribes spoken audio offline.',
                                        ),
                                  destination: _buildSttEngineDestination(),
                                ),
                                if (isCloudStt)
                                  SettingsTile.navigation(
                                    key: const ValueKey(
                                      'cloud_stt_model_dropdown',
                                    ),
                                    leading: const Icon(Icons.cloud_outlined),
                                    title: const Text('Cloud STT Model'),
                                    value: Text(selectedCloudSttModel.name),
                                    description: Text(
                                      'Step 1 (Audio → Text): ${selectedCloudSttModel.name} — ${selectedCloudSttModel.description}',
                                    ),
                                    destination:
                                        _buildCloudSttModelDestination(),
                                  ),
                              ],
                            ),

                            // 2. Translation (Step 2)
                            SettingsSection(
                              key: const ValueKey(
                                'settings_step2_translation_card',
                              ),
                              title: const Text('Translation'),
                              tiles: [
                                SettingsTile.navigation(
                                  key: const ValueKey(
                                    'translation_engine_mode_selector',
                                  ),
                                  leading: const Icon(Icons.translate_rounded),
                                  title: const Text('Translation Engine'),
                                  value: Text(
                                    isCloudTranslation
                                        ? 'Cloud (Gemini)'
                                        : 'On-Device (Gemma 4)',
                                  ),
                                  description: isCloudTranslation
                                      ? null
                                      : const Text(
                                          'Step 2 (Source → Target): On-device Gemma 4 E2B translates transcribed text offline (38 languages).',
                                        ),
                                  destination:
                                      _buildTranslationEngineDestination(),
                                ),
                                if (isCloudTranslation)
                                  SettingsTile.navigation(
                                    key: const ValueKey('cloud_model_dropdown'),
                                    leading: const Icon(
                                      Icons.auto_awesome_rounded,
                                    ),
                                    title: const Text(
                                      'Cloud Translation Model',
                                    ),
                                    value: Text(
                                      selectedCloudTranslationModel.name,
                                    ),
                                    description: Text(
                                      'Step 2 (Source → Target): ${selectedCloudTranslationModel.name} — ${selectedCloudTranslationModel.description}',
                                    ),
                                    destination:
                                        _buildCloudTranslationModelDestination(),
                                  ),
                              ],
                            ),

                            // 3. Gemini Cloud API Key (shown when either step uses Cloud)
                            if (anyCloudEnabled)
                              SettingsSection(
                                key: const ValueKey(
                                  'settings_cloud_api_key_card',
                                ),
                                title: const Text('Cloud API'),
                                tiles: [
                                  SettingsTile.navigation(
                                    key: const ValueKey('gemini_api_key_tile'),
                                    leading: const Icon(Icons.key_rounded),
                                    title: const Text('Gemini API Key'),
                                    value: Text(
                                      hasCloudKey ? 'Configured' : 'Not Set',
                                    ),
                                    description: Text(
                                      hasCloudKey
                                          ? 'Shared across Cloud STT and Cloud Translation.'
                                          : 'Required when Cloud (Gemini) is enabled for Speech-to-Text or Translation.',
                                    ),
                                    destination:
                                        _buildGeminiApiKeyDestination(),
                                  ),
                                ],
                              ),

                            // 4. Languages
                            SettingsSection(
                              title: const Text('Languages'),
                              tiles: [
                                SettingsTile.navigation(
                                  key: const ValueKey('base_language_dropdown'),
                                  leading: const Icon(
                                    Icons.record_voice_over_rounded,
                                  ),
                                  title: const Text('Primary Language'),
                                  value: Text(
                                    '${baseLang.flagEmoji} ${baseLang.name}',
                                  ),
                                  destination: _buildLanguageDestination(
                                    id: 'base_language',
                                    title: 'Primary Language',
                                    isBase: true,
                                  ),
                                ),
                                SettingsTile.navigation(
                                  key: const ValueKey(
                                    'target_language_dropdown',
                                  ),
                                  leading: const Icon(Icons.language_rounded),
                                  title: const Text('Target Language'),
                                  value: Text(
                                    '${targetLang.flagEmoji} ${targetLang.name}',
                                  ),
                                  description: Text(
                                    bothStepsCloud
                                        ? 'Cloud Gemini auto-detects which language is spoken and translates to the other.'
                                        : 'Gemma 4 auto-detects which language is spoken and translates to the other.',
                                  ),
                                  destination: _buildLanguageDestination(
                                    id: 'target_language',
                                    title: 'Target Language',
                                    isBase: false,
                                  ),
                                ),
                              ],
                            ),

                            // 5. Currency Conversion
                            SettingsSection(
                              title: const Text('Currency'),
                              tiles: [
                                SettingsTile.navigation(
                                  key: const ValueKey('base_currency_dropdown'),
                                  leading: const Icon(Icons.paid_outlined),
                                  title: const Text('Primary Currency'),
                                  value: Text(
                                    '${baseCurr.code} (${baseCurr.symbol})',
                                  ),
                                  destination: _buildCurrencyDestination(
                                    id: 'base_currency',
                                    title: 'Primary Currency',
                                    isBase: true,
                                  ),
                                ),
                                SettingsTile.navigation(
                                  key: const ValueKey(
                                    'target_currency_dropdown',
                                  ),
                                  leading: const Icon(
                                    Icons.currency_exchange_rounded,
                                  ),
                                  title: const Text('Target Currency'),
                                  value: Text(
                                    '${targetCurr.code} (${targetCurr.symbol})',
                                  ),
                                  destination: _buildCurrencyDestination(
                                    id: 'target_currency',
                                    title: 'Target Currency',
                                    isBase: false,
                                  ),
                                ),
                                SettingsTile(
                                  key: const ValueKey('refresh_rates_button'),
                                  leading: Icon(
                                    rateCache != null && rateCache.isStale
                                        ? Icons.cloud_off_rounded
                                        : Icons.sync_rounded,
                                  ),
                                  title: const Text('Exchange Rate'),
                                  value: Text(
                                    rateCache != null
                                        ? '1 ${settings.baseCurrency} = ${rateCache.rate.toStringAsFixed(2)} ${settings.targetCurrency}'
                                        : '1 ${settings.baseCurrency} = — ${settings.targetCurrency}',
                                  ),
                                  trailing: state.isRefreshingRates
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child:
                                              CircularProgressIndicator.adaptive(
                                                strokeWidth: 2,
                                              ),
                                        )
                                      : const Icon(
                                          Icons.refresh_rounded,
                                          size: 20,
                                        ),
                                  onPressed: state.isRefreshingRates
                                      ? null
                                      : (_) => _settingsBloc
                                            .refreshExchangeRates(),
                                  description: Text(
                                    rateCache != null
                                        ? 'Updated ${_formatDate(rateCache.updatedAt)}${rateCache.isStale ? ' (offline rate)' : ''}. Tap to refresh.'
                                        : 'No cached rate available. Tap to refresh.',
                                  ),
                                ),
                              ],
                            ),

                            // 6. On-Device AI Model (Gemma 4 E2B)
                            SettingsSection(
                              title: const Text('On-Device Model'),
                              tiles: [
                                SettingsTile.navigation(
                                  key: const ValueKey('on_device_model_tile'),
                                  leading: const Icon(Icons.memory_rounded),
                                  title: const Text('Gemma 4 E2B'),
                                  value: Text(
                                    modelState.isInstalled
                                        ? 'Installed'
                                        : (modelState.isDownloading
                                              ? '${(modelState.progress * 100).toStringAsFixed(0)}%'
                                              : 'Not Installed'),
                                  ),
                                  description: Text(
                                    bothStepsCloud
                                        ? 'Optional while both Speech-to-Text and Translation use Cloud (Gemini).'
                                        : 'Required for offline Speech-to-Text and offline Translation.',
                                  ),
                                  destination: _buildOnDeviceModelDestination(),
                                ),
                              ],
                            ),

                            // 7. Display / Text Scaling
                            SettingsSection(
                              title: const Text('Display'),
                              tiles: [
                                SettingsTile(
                                  leading: const Icon(
                                    Icons.format_size_rounded,
                                  ),
                                  title: const Text('Transcript Text Size'),
                                  value: Text(
                                    key: const ValueKey(
                                      'text_scale_value_label',
                                    ),
                                    '${settings.textScaleFactor.toStringAsFixed(2)}x',
                                  ),
                                ),
                                SettingsTile(
                                  title: Slider.adaptive(
                                    key: const ValueKey('text_scale_slider'),
                                    value: settings.textScaleFactor.clamp(
                                      0.8,
                                      2.0,
                                    ),
                                    min: 0.8,
                                    max: 2.0,
                                    divisions: 12,
                                    onChanged: (value) {
                                      final rounded =
                                          (value * 10).round() / 10.0;
                                      _settingsBloc.updateTextScaleFactor(
                                        rounded,
                                      );
                                    },
                                  ),
                                  description: const Text(
                                    'Multiplies your system font size inside active conversation transcripts (0.8x to 2.0x).',
                                  ),
                                ),
                              ],
                            ),

                            // 8. Conversation Context & Rolling History
                            SettingsSection(
                              key: const ValueKey('settings_context_card'),
                              title: const Text('Conversation Context'),
                              tiles: [
                                SettingsTile.navigation(
                                  key: const ValueKey('rolling_turns_tile'),
                                  leading: const Icon(Icons.history_rounded),
                                  title: const Text('Prior Turn Context'),
                                  value: Text(
                                    key: const ValueKey(
                                      'rolling_turn_count_label',
                                    ),
                                    settings.rollingTurnCount == 0
                                        ? 'Off'
                                        : '${settings.rollingTurnCount} turns',
                                  ),
                                  destination: _buildRollingTurnsDestination(),
                                ),
                                SettingsTile.navigation(
                                  key: const ValueKey('topic_presets_tile'),
                                  leading: const Icon(
                                    Icons.auto_awesome_mosaic_rounded,
                                  ),
                                  title: const Text('Topic Presets'),
                                  value: Text(
                                    '${effectivePresets.length} presets',
                                  ),
                                  description: const Text(
                                    'Situational vocabulary hints and prior turn history injected into prompts.',
                                  ),
                                  destination: _buildTopicPresetsDestination(),
                                ),
                              ],
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlatformHeader(
    BuildContext context, {
    required bool isCupertino,
    required bool isDark,
  }) {
    if (isCupertino) {
      final fill = isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF7F7FA);
      final rim = isDark ? const Color(0x33FFFFFF) : const Color(0x14000000);
      final fgColor = isDark ? Colors.white : Colors.black;

      return SafeArea(
        bottom: false,
        child: SizedBox(
          height: 44,
          child: NavigationToolbar(
            leading: Padding(
              padding: const EdgeInsetsDirectional.only(start: 16),
              child: GestureDetector(
                key: const ValueKey('settings_back_button'),
                behavior: HitTestBehavior.opaque,
                onTap: _navigateBack,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: fill,
                    shape: BoxShape.circle,
                    border: Border.all(color: rim, width: 0.5),
                  ),
                  alignment: Alignment.center,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(end: 2),
                    child: Icon(
                      CupertinoIcons.chevron_back,
                      size: 22,
                      color: fgColor,
                    ),
                  ),
                ),
              ),
            ),
            middle: ValueListenableBuilder<bool>(
              valueListenable: _largeTitleHidden,
              builder: (context, hidden, _) => AnimatedOpacity(
                opacity: hidden ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 150),
                child: Text(
                  'Translation Settings',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.4,
                    color: fgColor,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return SafeArea(
      bottom: false,
      child: SizedBox(
        height: 64,
        child: Row(
          children: [
            const SizedBox(width: 4),
            IconButton(
              key: const ValueKey('settings_back_button'),
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: _navigateBack,
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Translation Settings',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w400,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Nested SettingsDestinations
  // ---------------------------------------------------------------------------

  SettingsDestination _buildSttEngineDestination() {
    return SettingsDestination(
      id: 'stt_engine',
      title: const Text('Speech-to-Text Engine'),
      builder: (context) => BlocSignalBuilder<SettingsBloc, SettingsState>(
        bloc: _settingsBloc,
        builder: (context, state) {
          final mode = state.settings.sttEngineMode;
          return SettingsList(
            sections: [
              SettingsSection(
                title: const Text('Step 1: Audio → Text'),
                tiles: [
                  SettingsTile(
                    key: const ValueKey('stt_mode_on_device_tile'),
                    leading: const Icon(Icons.phone_iphone_rounded),
                    title: const Text('On-Device STT (Gemma 4)'),
                    trailing: mode == TranslationEngineMode.onDevice
                        ? _buildCheckmark(context)
                        : null,
                    onPressed: (ctx) {
                      _settingsBloc.updateSttEngineMode(
                        TranslationEngineMode.onDevice,
                      );
                      Navigator.of(ctx).maybePop();
                    },
                  ),
                  SettingsTile(
                    key: const ValueKey('stt_mode_cloud_tile'),
                    leading: const Icon(Icons.cloud_outlined),
                    title: const Text('Cloud STT (Gemini)'),
                    trailing: mode == TranslationEngineMode.cloud
                        ? _buildCheckmark(context)
                        : null,
                    description: const Text(
                      'On-device Gemma 4 E2B transcribes spoken audio offline. Cloud STT sends audio to Google Gemini.',
                    ),
                    onPressed: (ctx) {
                      _settingsBloc.updateSttEngineMode(
                        TranslationEngineMode.cloud,
                      );
                      Navigator.of(ctx).maybePop();
                    },
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  SettingsDestination _buildCloudSttModelDestination() {
    return SettingsDestination(
      id: 'cloud_stt_model',
      title: const Text('Cloud STT Model'),
      builder: (context) => BlocSignalBuilder<SettingsBloc, SettingsState>(
        bloc: _settingsBloc,
        builder: (context, state) {
          final selectedId = state.settings.cloudSttModelId;
          final models = AppSettings.supportedCloudModels;
          return SettingsList(
            sections: [
              SettingsSection(
                title: const Text('Gemini Audio Model'),
                tiles: [
                  for (var i = 0; i < models.length; i++)
                    SettingsTile(
                      key: ValueKey('cloud_stt_model_option_${models[i].id}'),
                      title: Text(
                        '${models[i].name} — ${models[i].description}',
                      ),
                      trailing: selectedId == models[i].id
                          ? _buildCheckmark(context)
                          : null,
                      description: i == models.length - 1
                          ? const Text(
                              'Used for Step 1 audio-to-text transcription when Cloud STT is enabled.',
                            )
                          : null,
                      onPressed: (ctx) {
                        _settingsBloc.updateCloudSttModelId(models[i].id);
                        Navigator.of(ctx).maybePop();
                      },
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  SettingsDestination _buildTranslationEngineDestination() {
    return SettingsDestination(
      id: 'translation_engine',
      title: const Text('Translation Engine'),
      builder: (context) => BlocSignalBuilder<SettingsBloc, SettingsState>(
        bloc: _settingsBloc,
        builder: (context, state) {
          final mode = state.settings.translationEngineMode;
          return SettingsList(
            sections: [
              SettingsSection(
                title: const Text('Step 2: Source → Target'),
                tiles: [
                  SettingsTile(
                    key: const ValueKey('translation_mode_on_device_tile'),
                    leading: const Icon(Icons.phone_iphone_rounded),
                    title: const Text('On-Device (Gemma 4)'),
                    trailing: mode == TranslationEngineMode.onDevice
                        ? _buildCheckmark(context)
                        : null,
                    onPressed: (ctx) {
                      _settingsBloc.updateTranslationEngineMode(
                        TranslationEngineMode.onDevice,
                      );
                      Navigator.of(ctx).maybePop();
                    },
                  ),
                  SettingsTile(
                    key: const ValueKey('translation_mode_cloud_tile'),
                    leading: const Icon(Icons.cloud_outlined),
                    title: const Text('Cloud (Gemini)'),
                    trailing: mode == TranslationEngineMode.cloud
                        ? _buildCheckmark(context)
                        : null,
                    description: const Text(
                      'On-device Gemma 4 E2B translates text offline across 38 languages. Cloud (Gemini) translates via Google Gemini.',
                    ),
                    onPressed: (ctx) {
                      _settingsBloc.updateTranslationEngineMode(
                        TranslationEngineMode.cloud,
                      );
                      Navigator.of(ctx).maybePop();
                    },
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  SettingsDestination _buildCloudTranslationModelDestination() {
    return SettingsDestination(
      id: 'cloud_translation_model',
      title: const Text('Cloud Translation Model'),
      builder: (context) => BlocSignalBuilder<SettingsBloc, SettingsState>(
        bloc: _settingsBloc,
        builder: (context, state) {
          final selectedId = state.settings.cloudModelId;
          final models = AppSettings.supportedCloudModels;
          return SettingsList(
            sections: [
              SettingsSection(
                title: const Text('Gemini Translation Model'),
                tiles: [
                  for (var i = 0; i < models.length; i++)
                    SettingsTile(
                      key: ValueKey(
                        'cloud_translation_model_option_${models[i].id}',
                      ),
                      title: Text(
                        '${models[i].name} — ${models[i].description}',
                      ),
                      trailing: selectedId == models[i].id
                          ? _buildCheckmark(context)
                          : null,
                      description: i == models.length - 1
                          ? const Text(
                              'Used for Step 2 text translation when Cloud (Gemini) is enabled.',
                            )
                          : null,
                      onPressed: (ctx) {
                        _settingsBloc.updateCloudModelId(models[i].id);
                        Navigator.of(ctx).maybePop();
                      },
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  SettingsDestination _buildGeminiApiKeyDestination() {
    return SettingsDestination(
      id: 'gemini_api_key',
      title: const Text('Gemini API Key'),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return SettingsList(
            sections: [
              SettingsSection(
                title: const Text('API Key'),
                tiles: [
                  SettingsTile(
                    leading: const Icon(Icons.key_rounded),
                    title: TextField(
                      key: const ValueKey('gemini_api_key_text_field'),
                      controller: _geminiApiKeyController,
                      obscureText: _obscureGeminiApiKey,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration.collapsed(
                        hintText: 'AIzaSy...',
                      ),
                      onChanged: (value) {
                        _settingsBloc.updateGeminiApiKey(value.trim());
                      },
                      onSubmitted: (value) {
                        _settingsBloc.updateGeminiApiKey(value.trim());
                      },
                    ),
                    trailing: IconButton(
                      key: const ValueKey('gemini_api_key_visibility_button'),
                      icon: Icon(
                        _obscureGeminiApiKey
                            ? Icons.visibility_rounded
                            : Icons.visibility_off_rounded,
                        size: 20,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscureGeminiApiKey = !_obscureGeminiApiKey;
                        });
                        setModalState(() {});
                      },
                    ),
                    description: const Text(
                      'Stored locally on this device and shared across Cloud STT and Cloud Translation.',
                    ),
                  ),
                ],
              ),
              SettingsSection(
                key: const ValueKey('gemini_api_key_help_box'),
                title: const Text('Where to Get an API Key'),
                tiles: [
                  SettingsTile(
                    leading: const Icon(Icons.open_in_new_rounded),
                    title: const Text('1. Visit Google AI Studio'),
                    value: const Text('aistudio.google.com/apikey'),
                  ),
                  SettingsTile(
                    leading: const Icon(Icons.person_outline_rounded),
                    title: const Text('2. Sign in with your Google account'),
                  ),
                  SettingsTile(
                    leading: const Icon(Icons.content_paste_rounded),
                    title: const Text('3. Create API key and paste it above'),
                    description: const Text(
                      'Get a free or paid Gemini API key from aistudio.google.com/apikey.',
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  SettingsDestination _buildLanguageDestination({
    required String id,
    required String title,
    required bool isBase,
  }) {
    return SettingsDestination(
      id: id,
      title: Text(title),
      builder: (context) => BlocSignalBuilder<SettingsBloc, SettingsState>(
        bloc: _settingsBloc,
        builder: (context, state) {
          final settings = state.settings;
          final selectedCode = isBase
              ? settings.baseLanguage
              : settings.targetLanguage;
          final availableLanguages =
              _settingsBloc.supportedLanguages.isNotEmpty
              ? _settingsBloc.supportedLanguages
              : AppSettings.supportedLanguages;
          return SettingsList(
            sections: [
              SettingsSection(
                title: Text(title),
                tiles: [
                  for (final lang in availableLanguages)
                    SettingsTile(
                      key: ValueKey('${id}_option_${lang.code}'),
                      leading: Text(
                        lang.flagEmoji,
                        style: const TextStyle(fontSize: 20),
                      ),
                      title: Text('${lang.name} (${lang.nativeName})'),
                      trailing: selectedCode == lang.code
                          ? _buildCheckmark(context)
                          : null,
                      onPressed: (ctx) {
                        if (isBase) {
                          _settingsBloc.updateBaseLanguage(lang);
                        } else {
                          _settingsBloc.updateTargetLanguage(lang);
                        }
                        Navigator.of(ctx).maybePop();
                      },
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  SettingsDestination _buildCurrencyDestination({
    required String id,
    required String title,
    required bool isBase,
  }) {
    return SettingsDestination(
      id: id,
      title: Text(title),
      builder: (context) => BlocSignalBuilder<SettingsBloc, SettingsState>(
        bloc: _settingsBloc,
        builder: (context, state) {
          final settings = state.settings;
          final selectedCode = isBase
              ? settings.baseCurrency
              : settings.targetCurrency;
          return SettingsList(
            sections: [
              SettingsSection(
                title: Text(title),
                tiles: [
                  for (final curr in AppSettings.supportedCurrencies)
                    SettingsTile(
                      key: ValueKey('${id}_option_${curr.code}'),
                      title: Text(
                        '${curr.code} — ${curr.name} (${curr.symbol})',
                      ),
                      trailing: selectedCode == curr.code
                          ? _buildCheckmark(context)
                          : null,
                      onPressed: (ctx) {
                        if (isBase) {
                          _settingsBloc.updateBaseCurrency(curr);
                        } else {
                          _settingsBloc.updateTargetCurrency(curr);
                        }
                        Navigator.of(ctx).maybePop();
                      },
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  SettingsDestination _buildOnDeviceModelDestination() {
    return SettingsDestination(
      id: 'on_device_model',
      title: const Text('Gemma 4 E2B'),
      builder: (context) => BlocSignalBuilder<ModelManager, ModelDownloadState>(
        bloc: _settingsBloc.modelManager,
        builder: (context, modelState) {
          final pct = (modelState.progress * 100).toStringAsFixed(0);
          return SettingsList(
            sections: [
              SettingsSection(
                title: const Text('Model Status'),
                tiles: [
                  SettingsTile(
                    leading: Icon(
                      modelState.isInstalled
                          ? Icons.check_circle_rounded
                          : (modelState.isDownloading
                                ? Icons.downloading_rounded
                                : Icons.cloud_download_outlined),
                    ),
                    title: Text(
                      modelState.isInstalled
                          ? 'Installed & Ready (gemma-4-E2B-it.litertlm)'
                          : (modelState.isDownloading
                                ? 'Downloading Gemma 4 E2B ($pct%)…'
                                : 'Not installed on device'),
                    ),
                    description: modelState.error != null
                        ? Text(modelState.error!)
                        : null,
                  ),
                  if (modelState.isInstalled)
                    SettingsTile(
                      leading: const Icon(Icons.refresh_rounded),
                      title: const Text('Re-download'),
                      onPressed: (_) =>
                          _settingsBloc.modelManager.markUninstalled(),
                    )
                  else if (modelState.isDownloading)
                    SettingsTile(
                      leading: const Icon(Icons.close_rounded),
                      title: const Text('Cancel'),
                      onPressed: (_) =>
                          _settingsBloc.modelManager.cancelDownload(),
                    )
                  else
                    SettingsTile(
                      key: const ValueKey('settings_download_model_button'),
                      leading: const Icon(Icons.download_rounded),
                      title: const Text('Download Model'),
                      onPressed: (_) => _settingsBloc.downloadModel(),
                    ),
                ],
              ),
              SettingsSection(
                title: const Text('Model Download URL'),
                tiles: [
                  SettingsTile(
                    leading: const Icon(Icons.link_rounded),
                    title: TextField(
                      key: const ValueKey('model_url_text_field'),
                      controller: _urlController,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: const InputDecoration.collapsed(
                        hintText: 'https://...',
                      ),
                      onSubmitted: (value) {
                        if (value.trim().isNotEmpty) {
                          _settingsBloc.updateModelDownloadUrl(value.trim());
                        }
                      },
                      onChanged: (value) {
                        if (value.trim().isNotEmpty) {
                          _settingsBloc.updateModelDownloadUrl(value.trim());
                        }
                      },
                    ),
                    description: const Text(
                      'Override if hosting the .litertlm bundle on an internal mirror or CDN.',
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  SettingsDestination _buildRollingTurnsDestination() {
    return SettingsDestination(
      id: 'rolling_turns',
      title: const Text('Prior Turn Context'),
      builder: (context) => BlocSignalBuilder<SettingsBloc, SettingsState>(
        bloc: _settingsBloc,
        builder: (context, state) {
          final count = state.settings.rollingTurnCount;
          return SettingsList(
            sections: [
              SettingsSection(
                title: const Text('Rolling Turn History'),
                tiles: [
                  SettingsTile(
                    leading: const Icon(Icons.history_rounded),
                    title: const Text('Prior Turns Included'),
                    value: Text(
                      count == 0 ? 'Off (0 turns)' : '$count turns',
                    ),
                  ),
                  SettingsTile(
                    title: Slider.adaptive(
                      key: const ValueKey('rolling_turn_count_slider'),
                      value: count.clamp(0, 10).toDouble(),
                      min: 0,
                      max: 10,
                      divisions: 10,
                      onChanged: (value) {
                        _settingsBloc.updateRollingTurnCount(value.round());
                      },
                    ),
                    description: const Text(
                      'Number of recent translated turns included in each prompt to help resolve pronouns, homophones, and ongoing topics (0 to 10 turns).',
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  SettingsDestination _buildTopicPresetsDestination() {
    return SettingsDestination(
      id: 'topic_presets',
      title: const Text('Topic Presets'),
      builder: (context) => BlocSignalBuilder<SettingsBloc, SettingsState>(
        bloc: _settingsBloc,
        builder: (context, state) {
          final effectivePresets = state.settings.contextPresets;

          return SettingsList(
            sections: [
              SettingsSection(
                title: const Text('Situational Presets'),
                tiles: [
                  for (final preset in effectivePresets)
                    SettingsTile.navigation(
                      key: ValueKey('settings_preset_tile_${preset.id}'),
                      leading: Text(
                        preset.icon,
                        style: const TextStyle(fontSize: 20),
                      ),
                      title: Text(preset.name),
                      value: Text(
                        '${_parseKeywords(preset.keywords).length} terms',
                      ),
                      destination: _buildSinglePresetDestination(preset.id),
                    ),
                ],
              ),
              SettingsSection(
                title: const Text('Manage Presets'),
                tiles: [
                  SettingsTile(
                    key: const ValueKey('settings_add_custom_preset_button'),
                    leading: const Icon(Icons.add_rounded),
                    title: const Text('New Custom Preset…'),
                    onPressed: (ctx) => _showCreatePresetDialog(ctx),
                  ),
                  SettingsTile(
                    key: const ValueKey('settings_reset_presets_button'),
                    leading: const Icon(Icons.restore_rounded),
                    title: const Text('Reset Default Presets'),
                    description: const Text(
                      'Restores the built-in Restaurant, Airport, Taxi, Hotel, Shopping, and Medical presets.',
                    ),
                    onPressed: (_) =>
                        _settingsBloc.resetContextPresetsToDefaults(),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  SettingsDestination _buildSinglePresetDestination(String presetId) {
    return SettingsDestination(
      id: 'preset_$presetId',
      builder: (context) => BlocSignalBuilder<SettingsBloc, SettingsState>(
        bloc: _settingsBloc,
        builder: (context, state) {
          final effectivePresets = state.settings.contextPresets;
          final preset = effectivePresets
              .where((p) => p.id == presetId)
              .firstOrNull;
          if (preset == null) {
            return const SizedBox.shrink();
          }
          final terms = _parseKeywords(preset.keywords);
          final isBuiltIn = AppSettings.defaultContextPresets.any(
            (d) => d.id == preset.id,
          );

          return SettingsList(
            sections: [
              SettingsSection(
                title: Text('${preset.displayLabel} Vocabulary'),
                tiles: [
                  for (final kw in terms)
                    SettingsTile(
                      title: Text(kw),
                      trailing: IconButton(
                        icon: const Icon(
                          Icons.remove_circle_outline_rounded,
                          size: 20,
                        ),
                        onPressed: () {
                          final remaining = terms
                              .where((k) => k != kw)
                              .join(', ');
                          _settingsBloc.saveContextPreset(
                            preset.copyWith(keywords: remaining),
                          );
                        },
                      ),
                    ),
                  SettingsTile(
                    key: ValueKey('settings_add_preset_kw_btn_${preset.id}'),
                    leading: const Icon(Icons.add_rounded),
                    title: const Text('Add Vocabulary Term…'),
                    description: const Text(
                      'Terms are injected into Speech-to-Text and Translation prompts when this topic is active.',
                    ),
                    onPressed: (ctx) =>
                        _showAddVocabularyTermDialog(ctx, preset),
                  ),
                ],
              ),
              if (!isBuiltIn)
                SettingsSection(
                  tiles: [
                    SettingsTile(
                      key: ValueKey('settings_delete_preset_${preset.id}'),
                      leading: const Icon(
                        Icons.delete_outline_rounded,
                        color: CupertinoColors.systemRed,
                      ),
                      title: const Text('Delete Custom Preset'),
                      onPressed: (ctx) {
                        _settingsBloc.deleteContextPreset(preset.id);
                        Navigator.of(ctx).maybePop();
                      },
                    ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }

  static List<String> _parseKeywords(String raw) {
    return raw
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  Future<void> _showAddVocabularyTermDialog(
    BuildContext context,
    ConversationContextPreset preset,
  ) async {
    var termDraft = '';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog.adaptive(
          title: const Text('Add Vocabulary Term'),
          content: Material(
            color: Colors.transparent,
            child: TextFormField(
              key: ValueKey('settings_add_preset_kw_input_${preset.id}'),
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'e.g. bibimbap, Gate B12',
              ),
              onChanged: (value) => termDraft = value,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final trimmed = termDraft.trim();
                if (trimmed.isEmpty) return;
                final existing = _parseKeywords(preset.keywords);
                if (!existing.contains(trimmed)) {
                  final updatedKeywords = [...existing, trimmed].join(', ');
                  _settingsBloc.saveContextPreset(
                    preset.copyWith(keywords: updatedKeywords),
                  );
                }
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showCreatePresetDialog(BuildContext context) async {
    var emojiDraft = '💬';
    var labelDraft = '';
    var keywordsDraft = '';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog.adaptive(
          key: const ValueKey('create_custom_preset_dialog'),
          title: const Text('New Custom Topic Preset'),
          content: Material(
            color: Colors.transparent,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 68,
                        child: TextFormField(
                          key: const ValueKey('custom_preset_emoji_field'),
                          initialValue: emojiDraft,
                          onChanged: (val) => emojiDraft = val,
                          decoration: const InputDecoration(
                            labelText: 'Icon',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          key: const ValueKey('custom_preset_label_field'),
                          onChanged: (val) => labelDraft = val,
                          decoration: const InputDecoration(
                            labelText: 'Preset Name',
                            hintText: 'e.g. Train Station',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const ValueKey('custom_preset_keywords_field'),
                    maxLines: 2,
                    onChanged: (val) => keywordsDraft = val,
                    decoration: const InputDecoration(
                      labelText: 'Vocabulary terms (comma-separated)',
                      hintText: 'platform, express, ticket, seat',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey('custom_preset_save_button'),
              onPressed: () {
                final label = labelDraft.trim();
                if (label.isEmpty) return;
                final emoji = emojiDraft.trim().isEmpty
                    ? '💬'
                    : emojiDraft.trim();
                final id =
                    'custom_${DateTime.now().millisecondsSinceEpoch}_${label.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '_')}';
                _settingsBloc.saveContextPreset(
                  ConversationContextPreset(
                    id: id,
                    name: label,
                    icon: emoji,
                    keywords: keywordsDraft.trim(),
                  ),
                );
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
  }

  static String _formatDate(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
