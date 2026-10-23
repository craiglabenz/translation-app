import 'dart:async';

import 'package:bloc_signals_flutter/bloc_signals_flutter.dart';
import 'package:flow_ui/flow_ui.dart';
import 'package:get_it/get_it.dart';
import 'package:kaisel/kaisel.dart';
import 'package:material_ui/material_ui.dart';
import 'package:translation_app/core/ai/model_manager.dart';
import 'package:translation_app/core/data/models/app_settings.dart';
import 'package:translation_app/core/routing/routing.dart';
import 'package:translation_app/core/theme/tokens.dart';
import 'package:translation_app/features/settings/bloc/settings_bloc.dart';
import 'package:translation_app/features/settings/bloc/settings_state.dart';

/// Settings screen for configuring the active language pair, currency pair,
/// cached exchange rate refresh, and on-device Gemma 4 E2B model management.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    this.settingsBloc,
    super.key,
  });

  final SettingsBloc? settingsBloc;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final SettingsBloc _settingsBloc;
  late final TextEditingController _urlController;
  late final TextEditingController _apiKeyController;
  bool _obscureApiKey = true;

  @override
  void initState() {
    super.initState();
    _settingsBloc = widget.settingsBloc ?? GetIt.I<SettingsBloc>();
    _urlController = TextEditingController(
      text: _settingsBloc.stateValue.settings.modelDownloadUrl,
    );
    _apiKeyController = TextEditingController(
      text: _settingsBloc.stateValue.settings.geminiApiKey,
    );
  }

  @override
  void dispose() {
    _urlController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  void _handleBack() {
    final scope = RouterScope.maybeOf<AppRoute>(context);
    if (scope != null) {
      unawaited(scope.router.pop());
    } else if (GetIt.I.isRegistered<AppRouter>()) {
      unawaited(GetIt.I<AppRouter>().config.router.pop());
    } else {
      Navigator.maybeOf(context)?.maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;
    final typography = context.flowTypography;

    return BlocSignalBuilder<SettingsBloc, SettingsState>(
      bloc: _settingsBloc,
      builder: (context, state) {
        final settings = state.settings;
        final exchangeRate = state.exchangeRate;
        final availableLanguages = _settingsBloc.supportedLanguages;

        final selectedBaseLang = availableLanguages.firstWhere(
          (l) => l.code == settings.baseLanguage,
          orElse: () => availableLanguages.first,
        );
        final selectedTargetLang = availableLanguages.firstWhere(
          (l) => l.code == settings.targetLanguage,
          orElse: () => availableLanguages.length > 1
              ? availableLanguages[1]
              : availableLanguages.first,
        );
        final selectedBaseCurrency = AppSettings.supportedCurrencies.firstWhere(
          (c) => c.code == settings.baseCurrency,
          orElse: () => AppSettings.supportedCurrencies.first,
        );
        final selectedTargetCurrency = AppSettings.supportedCurrencies
            .firstWhere(
              (c) => c.code == settings.targetCurrency,
              orElse: () => AppSettings.supportedCurrencies[1],
            );
        final selectedCloudModel = AppSettings.supportedCloudModels.firstWhere(
          (m) => m.id == settings.cloudModelId,
          orElse: () => AppSettings.supportedCloudModels.first,
        );
        final isCloudMode =
            settings.translationEngineMode == TranslationEngineMode.cloud;

        return Scaffold(
          backgroundColor: colors.surface,
          appBar: AppBar(
            leading: IconButton(
              key: const ValueKey('settings_back_button'),
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: _handleBack,
            ),
            title: Text(
              'Translation Settings',
              style: typography.titleMediumEmphasised.copyWith(
                color: colors.onSurface,
              ),
            ),
          ),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AppTokens.maxContentWidth,
                ),
                child: ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTokens.pageHorizontalPadding,
                    vertical: 16,
                  ),
                  children: [
                    // Translation Engine Selector Card
                    _SectionCard(
                      title: 'Translation Engine',
                      subtitle: isCloudMode
                          ? 'Cloud Gemini provides higher accuracy and ${availableLanguages.length} supported languages.'
                          : 'On-device Gemma 4 E2B runs 100% offline with ${availableLanguages.length} supported languages.',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SegmentedButton<TranslationEngineMode>(
                            key: const ValueKey('translation_engine_mode_selector'),
                            segments: const <ButtonSegment<TranslationEngineMode>>[
                              ButtonSegment<TranslationEngineMode>(
                                value: TranslationEngineMode.onDevice,
                                icon: Icon(Icons.phone_android_rounded, size: 18),
                                label: Text('On-Device (Gemma 4)'),
                              ),
                              ButtonSegment<TranslationEngineMode>(
                                value: TranslationEngineMode.cloud,
                                icon: Icon(Icons.cloud_outlined, size: 18),
                                label: Text('Cloud (Gemini)'),
                              ),
                            ],
                            selected: <TranslationEngineMode>{
                              settings.translationEngineMode,
                            },
                            onSelectionChanged: (selection) {
                              if (selection.isNotEmpty) {
                                unawaited(
                                  _settingsBloc.updateTranslationEngineMode(
                                    selection.first,
                                  ),
                                );
                              }
                            },
                          ),
                          if (isCloudMode) ...[
                            const SizedBox(height: 14),
                            DropdownButtonFormField<SupportedCloudModel>(
                              key: const ValueKey('cloud_model_dropdown'),
                              isExpanded: true,
                              initialValue: selectedCloudModel,
                              decoration: const InputDecoration(
                                labelText: 'Gemini Cloud Model',
                                border: OutlineInputBorder(),
                              ),
                              items: AppSettings.supportedCloudModels
                                  .map(
                                    (model) =>
                                        DropdownMenuItem<SupportedCloudModel>(
                                          value: model,
                                          child: Text(
                                            '${model.name} — ${model.description}',
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                  )
                                  .toList(),
                              onChanged: (model) {
                                if (model != null) {
                                  unawaited(
                                    _settingsBloc.updateCloudModelId(model.id),
                                  );
                                }
                              },
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              key: const ValueKey('gemini_api_key_text_field'),
                              controller: _apiKeyController,
                              obscureText: _obscureApiKey,
                              autocorrect: false,
                              enableSuggestions: false,
                              decoration: InputDecoration(
                                labelText: 'Gemini API Key',
                                hintText: 'AIzaSy...',
                                border: const OutlineInputBorder(),
                                suffixIcon: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      key: const ValueKey(
                                        'gemini_api_key_visibility_button',
                                      ),
                                      tooltip: _obscureApiKey
                                          ? 'Show API key'
                                          : 'Hide API key',
                                      icon: Icon(
                                        _obscureApiKey
                                            ? Icons.visibility_outlined
                                            : Icons.visibility_off_outlined,
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          _obscureApiKey = !_obscureApiKey;
                                        });
                                      },
                                    ),
                                    IconButton(
                                      key: const ValueKey(
                                        'gemini_api_key_save_button',
                                      ),
                                      tooltip: 'Save API Key',
                                      icon: const Icon(Icons.save_outlined),
                                      onPressed: () {
                                        unawaited(
                                          _settingsBloc.updateGeminiApiKey(
                                            _apiKeyController.text,
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                              onChanged: (value) {
                                unawaited(
                                  _settingsBloc.updateGeminiApiKey(value),
                                );
                              },
                              onSubmitted: (value) {
                                unawaited(
                                  _settingsBloc.updateGeminiApiKey(value),
                                );
                              },
                            ),
                            const SizedBox(height: 10),
                            Container(
                              key: const ValueKey('gemini_api_key_help_box'),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: colors.surface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: colors.outline),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.help_outline_rounded,
                                        size: 16,
                                        color: colors.primary,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'How to get a Gemini API key',
                                        style: typography.labelMedium.copyWith(
                                          color: colors.onSurface,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '1. Go to Google AI Studio at aistudio.google.com/apikey\n'
                                    '2. Sign in with your Google account and click "Create API key".\n'
                                    '3. Copy the generated key (starts with "AIza...") and paste it above.\n'
                                    'Your API key is stored locally on this device and sent only to Google\'s Gemini API.',
                                    style: typography.bodySmall.copyWith(
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Language Pair Card
                    _SectionCard(
                      title: 'Languages',
                      subtitle: isCloudMode
                          ? '${selectedCloudModel.name} auto-detects which language is spoken and translates to the other.'
                          : 'Gemma 4 auto-detects which language is spoken and translates to the other.',
                      child: Column(
                        children: [
                          DropdownButtonFormField<SupportedLanguage>(
                            key: const ValueKey('base_language_dropdown'),
                            isExpanded: true,
                            initialValue: selectedBaseLang,
                            decoration: const InputDecoration(
                              labelText: 'Primary (Base) Language',
                              border: OutlineInputBorder(),
                            ),
                            items: availableLanguages
                                .map(
                                  (lang) =>
                                      DropdownMenuItem<SupportedLanguage>(
                                        value: lang,
                                        child: Text(
                                          '${lang.name} (${lang.nativeName})',
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                )
                                .toList(),
                            onChanged: (lang) {
                              if (lang != null) {
                                unawaited(
                                  _settingsBloc.updateBaseLanguage(lang),
                                );
                              }
                            },
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<SupportedLanguage>(
                            key: const ValueKey('target_language_dropdown'),
                            isExpanded: true,
                            initialValue: selectedTargetLang,
                            decoration: const InputDecoration(
                              labelText: 'Target Language',
                              border: OutlineInputBorder(),
                            ),
                            items: availableLanguages
                                .map(
                                  (lang) =>
                                      DropdownMenuItem<SupportedLanguage>(
                                        value: lang,
                                        child: Text(
                                          '${lang.name} (${lang.nativeName})',
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                )
                                .toList(),
                            onChanged: (lang) {
                              if (lang != null) {
                                unawaited(
                                  _settingsBloc.updateTargetLanguage(lang),
                                );
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Currency & Exchange Rate Card
                    _SectionCard(
                      title: 'Currency Conversion',
                      subtitle:
                          'Spoken monetary amounts are converted inline using cached Frankfurter rates (7-day TTL).',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          DropdownButtonFormField<SupportedCurrency>(
                            key: const ValueKey('base_currency_dropdown'),
                            isExpanded: true,
                            initialValue: selectedBaseCurrency,
                            decoration: const InputDecoration(
                              labelText: 'Primary (Base) Currency',
                              border: OutlineInputBorder(),
                            ),
                            items: AppSettings.supportedCurrencies
                                .map(
                                  (curr) =>
                                      DropdownMenuItem<SupportedCurrency>(
                                        value: curr,
                                        child: Text(
                                          '${curr.code} — ${curr.name} (${curr.symbol})',
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                )
                                .toList(),
                            onChanged: (curr) {
                              if (curr != null) {
                                unawaited(
                                  _settingsBloc.updateBaseCurrency(curr),
                                );
                              }
                            },
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<SupportedCurrency>(
                            key: const ValueKey('target_currency_dropdown'),
                            isExpanded: true,
                            initialValue: selectedTargetCurrency,
                            decoration: const InputDecoration(
                              labelText: 'Target Currency',
                              border: OutlineInputBorder(),
                            ),
                            items: AppSettings.supportedCurrencies
                                .map(
                                  (curr) =>
                                      DropdownMenuItem<SupportedCurrency>(
                                        value: curr,
                                        child: Text(
                                          '${curr.code} — ${curr.name} (${curr.symbol})',
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                )
                                .toList(),
                            onChanged: (curr) {
                              if (curr != null) {
                                unawaited(
                                  _settingsBloc.updateTargetCurrency(curr),
                                );
                              }
                            },
                          ),
                          const SizedBox(height: 14),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  exchangeRate != null
                                      ? 'Current rate: 1 ${exchangeRate.baseCurrency} = '
                                            '${exchangeRate.rate.toStringAsFixed(4)} '
                                            '${exchangeRate.targetCurrency}'
                                            '${exchangeRate.isStale ? " (offline cached)" : ""}'
                                      : 'No exchange rate cached yet.',
                                  style: typography.labelMedium.copyWith(
                                    color: colors.onSurface,
                                  ),
                                ),
                              ),
                              TextButton.icon(
                                key: const ValueKey('refresh_rates_button'),
                                onPressed: state.isRefreshingRates
                                    ? null
                                    : _settingsBloc.refreshExchangeRates,
                                icon: const Icon(
                                  Icons.refresh_rounded,
                                  size: 18,
                                ),
                                label: Text(
                                  state.isRefreshingRates
                                      ? 'Refreshing…'
                                      : 'Refresh Rate',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                      // On-Device AI Model Management Card
                      BlocSignalBuilder<ModelManager, ModelDownloadState>(
                        bloc: _settingsBloc.modelManager,
                        builder: (context, modelState) {
                          return _SectionCard(
                            title: 'On-Device AI Model (Gemma 4 E2B)',
                            subtitle:
                                'Powered by flutter_edge_ai & LiteRT-LM (~1.6 GB).',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      modelState.isInstalled
                                          ? Icons.check_circle_rounded
                                          : Icons.cloud_download_outlined,
                                      color: modelState.isInstalled
                                          ? AppTokens.listeningAccent
                                          : colors.primary,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        modelState.isInstalled
                                            ? 'Installed & Ready (${modelState.modelId})'
                                            : modelState.isDownloading
                                            ? 'Downloading (${(modelState.progress * 100).toStringAsFixed(0)}%)…'
                                            : 'Not installed on device',
                                        style: typography.labelLarge.copyWith(
                                          color: colors.onSurface,
                                        ),
                                      ),
                                    ),
                                    if (modelState.isDownloading)
                                      OutlinedButton(
                                        onPressed: _settingsBloc
                                            .modelManager
                                            .cancelDownload,
                                        child: const Text('Cancel'),
                                      )
                                    else if (modelState.isInstalled)
                                      TextButton(
                                        onPressed: _settingsBloc
                                            .modelManager
                                            .markUninstalled,
                                        child: const Text('Re-download'),
                                      )
                                    else
                                      FilledButton.icon(
                                        key: const ValueKey(
                                          'settings_download_model_button',
                                        ),
                                        onPressed: _settingsBloc.downloadModel,
                                        icon: const Icon(
                                          Icons.download_rounded,
                                          size: 18,
                                        ),
                                        label: const Text('Download Model'),
                                      ),
                                  ],
                                ),
                                if (modelState.isDownloading) ...[
                                  const SizedBox(height: 12),
                                  LinearProgressIndicator(
                                    value: modelState.progress > 0
                                        ? modelState.progress
                                        : null,
                                  ),
                                ],
                                if (modelState.error != null) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    modelState.error!,
                                    style: typography.bodySmall.copyWith(
                                      color: AppTokens.errorRed,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 12),
                                TextField(
                                  key: const ValueKey('model_url_text_field'),
                                  controller: _urlController,
                                  decoration: InputDecoration(
                                    labelText: 'Model Download URL Override',
                                    helperText:
                                        'Default: Hugging Face (${AppSettings.defaultHuggingFaceRepo})',
                                    border: const OutlineInputBorder(),
                                    suffixIcon: IconButton(
                                      tooltip: 'Save URL',
                                      icon: const Icon(Icons.save_outlined),
                                      onPressed: () {
                                        unawaited(
                                          _settingsBloc.updateModelDownloadUrl(
                                            _urlController.text,
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  onSubmitted: (value) {
                                    unawaited(
                                      _settingsBloc.updateModelDownloadUrl(
                                        value,
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 16),

                      // Multiplicative Text Scaling Card
                      _SectionCard(
                        title: 'Text Scaling',
                        subtitle:
                            'Multiplies against your OS-level text size (0.5x – 3.0x, default 1.0x).',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    'Multiplier: ${settings.textScaleFactor.toStringAsFixed(1)}x',
                                    key: const ValueKey(
                                      'text_scale_value_label',
                                    ),
                                    style: typography.labelLarge.copyWith(
                                      color: colors.onSurface,
                                    ),
                                  ),
                                ),
                                TextButton(
                                  key: const ValueKey(
                                    'text_scale_reset_button',
                                  ),
                                  onPressed: settings.textScaleFactor ==
                                          AppSettings.defaultTextScaleFactor
                                      ? null
                                      : () => unawaited(
                                            _settingsBloc.updateTextScaleFactor(
                                              AppSettings.defaultTextScaleFactor,
                                            ),
                                          ),
                                  child: const Text('Reset (1.0x)'),
                                ),
                              ],
                            ),
                            Slider(
                              key: const ValueKey('text_scale_slider'),
                              value: settings.textScaleFactor.clamp(
                                AppSettings.minTextScaleFactor,
                                AppSettings.maxTextScaleFactor,
                              ),
                              min: AppSettings.minTextScaleFactor,
                              max: AppSettings.maxTextScaleFactor,
                              divisions: 25,
                              label:
                                  '${settings.textScaleFactor.toStringAsFixed(1)}x',
                              onChanged: (value) {
                                unawaited(
                                  _settingsBloc.updateTextScaleFactor(value),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;
    final typography = context.flowTypography;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: typography.titleSmallEmphasised.copyWith(
              color: colors.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: typography.bodySmall.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}
