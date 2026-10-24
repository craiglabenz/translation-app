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
  bool _expandPresetManager = false;

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

  Future<void> _showEditPresetDialog(
    BuildContext context, {
    ConversationContextPreset? preset,
  }) async {
    var iconText = preset?.icon ?? '💬';
    var nameText = preset?.name ?? '';
    var keywordsText = preset?.keywords ?? '';

    final saved = await showDialog<ConversationContextPreset>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          key: const ValueKey('settings_preset_editor_dialog'),
          title: Text(preset == null ? 'Add Topic Preset' : 'Edit Topic Preset'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 72,
                        child: TextFormField(
                          key: const ValueKey('settings_preset_icon_input'),
                          initialValue: iconText,
                          decoration: const InputDecoration(
                            labelText: 'Icon',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (val) => iconText = val,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          key: const ValueKey('settings_preset_name_input'),
                          initialValue: nameText,
                          autofocus: true,
                          decoration: const InputDecoration(
                            labelText: 'Preset Name',
                            hintText: 'e.g., Coffee Shop',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (val) => nameText = val,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const ValueKey('settings_preset_keywords_input'),
                    initialValue: keywordsText,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Vocabulary Keywords (comma-separated)',
                      hintText: 'espresso, oat milk, croissant, decaf',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (val) => keywordsText = val,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              key: const ValueKey('settings_preset_cancel_button'),
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey('settings_preset_save_button'),
              onPressed: () {
                if (nameText.trim().isEmpty) return;
                final id =
                    preset?.id ??
                    'custom_${DateTime.now().millisecondsSinceEpoch}_${nameText.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_')}';
                Navigator.of(dialogContext).pop(
                  ConversationContextPreset(
                    id: id,
                    name: nameText.trim(),
                    icon: iconText.trim().isEmpty ? '💬' : iconText.trim(),
                    keywords: keywordsText.trim(),
                  ),
                );
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (saved != null && mounted) {
      await _settingsBloc.saveContextPreset(saved);
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
        final selectedCloudSttModel = AppSettings.supportedCloudModels
            .firstWhere(
              (m) => m.id == settings.cloudSttModelId,
              orElse: () => AppSettings.supportedCloudModels.first,
            );
        final selectedOnDeviceSttModel = settings.selectedOnDeviceSttModel;
        final activeWhisperVariant = selectedOnDeviceSttModel.isWhisper
            ? selectedOnDeviceSttModel
            : AppSettings.whisperVariants.first;
        final isCloudMode =
            settings.translationEngineMode == TranslationEngineMode.cloud;
        final isSttCloudMode =
            settings.sttEngineMode == TranslationEngineMode.cloud;
        final anyCloudEnabled = isCloudMode || isSttCloudMode;

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
                    vertical: 8,
                  ),
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Step 1: Speech-to-Text (Transcription) Card
                    _SectionCard(
                      key: const ValueKey('settings_step1_stt_card'),
                      title: 'Step 1: Speech-to-Text (Audio → Text)',
                      subtitle: isSttCloudMode
                          ? 'Cloud Gemini transcribes spoken audio into text.'
                          : 'On-device model (${selectedOnDeviceSttModel.name}) transcribes spoken audio offline.',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SegmentedButton<TranslationEngineMode>(
                            key: const ValueKey('stt_engine_mode_selector'),
                            style: SegmentedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                            ),
                            segments:
                                const <ButtonSegment<TranslationEngineMode>>[
                                  ButtonSegment<TranslationEngineMode>(
                                    value: TranslationEngineMode.onDevice,
                                    icon: Icon(Icons.mic_rounded, size: 16),
                                    label: Text('On-Device STT'),
                                  ),
                                  ButtonSegment<TranslationEngineMode>(
                                    value: TranslationEngineMode.cloud,
                                    icon: Icon(Icons.cloud_outlined, size: 16),
                                    label: Text('Cloud STT'),
                                  ),
                                ],
                            selected: <TranslationEngineMode>{
                              settings.sttEngineMode,
                            },
                            onSelectionChanged: (selection) {
                              if (selection.isNotEmpty) {
                                unawaited(
                                  _settingsBloc.updateSttEngineMode(
                                    selection.first,
                                  ),
                                );
                              }
                            },
                          ),
                          const SizedBox(height: 8),
                          if (!isSttCloudMode)
                            DropdownButtonFormField<SupportedOnDeviceSttModel>(
                              key: const ValueKey(
                                'on_device_stt_model_dropdown',
                              ),
                              isExpanded: true,
                              isDense: true,
                              initialValue: selectedOnDeviceSttModel,
                              decoration: const InputDecoration(
                                labelText: 'On-Device STT Model',
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                border: OutlineInputBorder(),
                              ),
                              items: AppSettings.supportedOnDeviceSttModels
                                  .map(
                                    (model) =>
                                        DropdownMenuItem<
                                          SupportedOnDeviceSttModel
                                        >(
                                          value: model,
                                          child: Text(
                                            '${model.name} (${model.sizeLabel}) — ${model.description}',
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                  )
                                  .toList(),
                              onChanged: (model) {
                                if (model != null) {
                                  unawaited(
                                    _settingsBloc.updateOnDeviceSttModelId(
                                      model.id,
                                    ),
                                  );
                                }
                              },
                            )
                          else
                            DropdownButtonFormField<SupportedCloudModel>(
                              key: const ValueKey('cloud_stt_model_dropdown'),
                              isExpanded: true,
                              isDense: true,
                              initialValue: selectedCloudSttModel,
                              decoration: const InputDecoration(
                                labelText: 'Cloud STT Model (Gemini)',
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
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
                                    _settingsBloc.updateCloudSttModelId(
                                      model.id,
                                    ),
                                  );
                                }
                              },
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Step 2: Text Translation Engine Card
                    _SectionCard(
                      key: const ValueKey('settings_step2_translation_card'),
                      title: 'Step 2: Text Translation (Source → Target)',
                      subtitle: isCloudMode
                          ? 'Cloud Gemini translates transcribed text across ${availableLanguages.length} languages.'
                          : 'On-device Gemma 4 E2B translates transcribed text offline (${availableLanguages.length} languages).',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SegmentedButton<TranslationEngineMode>(
                            key: const ValueKey(
                              'translation_engine_mode_selector',
                            ),
                            style: SegmentedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                            ),
                            segments:
                                const <ButtonSegment<TranslationEngineMode>>[
                                  ButtonSegment<TranslationEngineMode>(
                                    value: TranslationEngineMode.onDevice,
                                    icon: Icon(
                                      Icons.translate_rounded,
                                      size: 16,
                                    ),
                                    label: Text('On-Device (Gemma 4)'),
                                  ),
                                  ButtonSegment<TranslationEngineMode>(
                                    value: TranslationEngineMode.cloud,
                                    icon: Icon(Icons.cloud_outlined, size: 16),
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
                            const SizedBox(height: 8),
                            DropdownButtonFormField<SupportedCloudModel>(
                              key: const ValueKey('cloud_model_dropdown'),
                              isExpanded: true,
                              isDense: true,
                              initialValue: selectedCloudModel,
                              decoration: const InputDecoration(
                                labelText: 'Cloud Translation Model (Gemini)',
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
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
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Shared Gemini Cloud API Key Card (shown when Step 1 or Step 2 uses Cloud)
                    if (anyCloudEnabled) ...[
                      _SectionCard(
                        key: const ValueKey('settings_cloud_api_key_card'),
                        title: 'Gemini Cloud API Key',
                        subtitle:
                            'Used by Cloud Speech-to-Text (Step 1) and Cloud Translation (Step 2).',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              key: const ValueKey('gemini_api_key_text_field'),
                              controller: _apiKeyController,
                              obscureText: _obscureApiKey,
                              autocorrect: false,
                              enableSuggestions: false,
                              decoration: InputDecoration(
                                labelText: 'Gemini API Key',
                                hintText: 'AIzaSy...',
                                isDense: true,
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
                            const SizedBox(height: 8),
                            Container(
                              key: const ValueKey('gemini_api_key_help_box'),
                              padding: const EdgeInsets.all(10),
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
                                  const SizedBox(height: 4),
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
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],

                    // Language Pair Card
                    _SectionCard(
                      title: 'Languages',
                      subtitle:
                          '${settings.activeModelDisplayName} auto-detects which language is spoken and translates to the other.',
                      child: Column(
                        children: [
                          DropdownButtonFormField<SupportedLanguage>(
                            key: const ValueKey('base_language_dropdown'),
                            isExpanded: true,
                            isDense: true,
                            initialValue: selectedBaseLang,
                            decoration: const InputDecoration(
                              labelText: 'Primary (Base) Language',
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              border: OutlineInputBorder(),
                            ),
                            items: availableLanguages
                                .map(
                                  (lang) => DropdownMenuItem<SupportedLanguage>(
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
                          const SizedBox(height: 10),
                          DropdownButtonFormField<SupportedLanguage>(
                            key: const ValueKey('target_language_dropdown'),
                            isExpanded: true,
                            isDense: true,
                            initialValue: selectedTargetLang,
                            decoration: const InputDecoration(
                              labelText: 'Target Language',
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              border: OutlineInputBorder(),
                            ),
                            items: availableLanguages
                                .map(
                                  (lang) => DropdownMenuItem<SupportedLanguage>(
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
                    const SizedBox(height: 12),

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
                            isDense: true,
                            initialValue: selectedBaseCurrency,
                            decoration: const InputDecoration(
                              labelText: 'Primary (Base) Currency',
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
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
                          const SizedBox(height: 8),
                          DropdownButtonFormField<SupportedCurrency>(
                            key: const ValueKey('target_currency_dropdown'),
                            isExpanded: true,
                            isDense: true,
                            initialValue: selectedTargetCurrency,
                            decoration: const InputDecoration(
                              labelText: 'Target Currency',
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
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
                          const SizedBox(height: 6),
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
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                ),
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
                    const SizedBox(height: 8),

                    // On-Device AI Model Management Card (Gemma 4 + Edge Whisper Variants)
                    BlocSignalBuilder<ModelManager, ModelDownloadState>(
                      bloc: _settingsBloc.modelManager,
                      builder: (context, modelState) {
                        return _SectionCard(
                          title: 'On-Device AI Models (Gemma 4 & Whisper)',
                          subtitle:
                              'Download Gemma 4 E2B (~1.6 GB) and Edge Whisper STT variants.',
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
                                const SizedBox(height: 8),
                                LinearProgressIndicator(
                                  value: modelState.progress > 0
                                      ? modelState.progress
                                      : null,
                                ),
                              ],
                              if (modelState.error != null) ...[
                                const SizedBox(height: 6),
                                Text(
                                  modelState.error!,
                                  style: typography.bodySmall.copyWith(
                                    color: AppTokens.errorRed,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 8),
                              TextField(
                                key: const ValueKey('model_url_text_field'),
                                controller: _urlController,
                                decoration: InputDecoration(
                                  labelText: 'Model Download URL Override',
                                  helperText:
                                      'Default: Hugging Face (${AppSettings.defaultHuggingFaceRepo})',
                                  isDense: true,
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
                              const SizedBox(height: 8),
                              _WhisperVariantRow(
                                variant: activeWhisperVariant,
                                isSelected: selectedOnDeviceSttModel.isWhisper,
                                isInstalled: modelState.isSttModelInstalled(
                                  activeWhisperVariant.id,
                                ),
                                isDownloadingThis:
                                    modelState.isWhisperDownloading &&
                                    modelState.whisperModelId ==
                                        activeWhisperVariant.id,
                                isAnyWhisperDownloading:
                                    modelState.isWhisperDownloading,
                                progress: modelState.whisperProgress,
                                onDownload: () => unawaited(
                                  _settingsBloc.downloadWhisperModel(
                                    activeWhisperVariant.id,
                                  ),
                                ),
                                onCancel: _settingsBloc
                                    .modelManager
                                    .cancelWhisperDownload,
                                onRedownload: () => _settingsBloc.modelManager
                                    .markWhisperUninstalled(
                                      activeWhisperVariant.id,
                                    ),
                              ),
                              if (modelState.whisperError != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  modelState.whisperError!,
                                  key: const ValueKey('whisper_download_error'),
                                  style: typography.bodySmall.copyWith(
                                    color: AppTokens.errorRed,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 8),

                    // Multiplicative Text Scaling Card
                    _SectionCard(
                      title: 'Text Scaling',
                      subtitle:
                          'Multiplies OS text size (0.5x – 3.0x, default 1.0x).',
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
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
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
                          SizedBox(
                            height: 32,
                            child: Slider(
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
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Situational Context Presets & Rolling Turn History Card
                    _SectionCard(
                      key: const ValueKey('settings_context_card'),
                      title: 'Conversation Context & Rolling History',
                      subtitle:
                          'Injects prior turns and situational vocabulary hints into both Speech-to-Text and Translation.',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  settings.rollingTurnCount <= 0
                                      ? 'Rolling History: Off (0 turns)'
                                      : 'Rolling History: Last ${settings.rollingTurnCount} ${settings.rollingTurnCount == 1 ? 'turn' : 'turns'}',
                                  key: const ValueKey(
                                    'rolling_turn_count_label',
                                  ),
                                  style: typography.labelLarge.copyWith(
                                    color: colors.onSurface,
                                  ),
                                ),
                              ),
                              TextButton(
                                key: const ValueKey(
                                  'rolling_turn_count_reset_button',
                                ),
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                ),
                                onPressed:
                                    settings.rollingTurnCount ==
                                        AppSettings.defaultRollingTurnCount
                                    ? null
                                    : () => unawaited(
                                        _settingsBloc.updateRollingTurnCount(
                                          AppSettings.defaultRollingTurnCount,
                                        ),
                                      ),
                                child: const Text('Default (3)'),
                              ),
                            ],
                          ),
                          SizedBox(
                            height: 32,
                            child: Slider(
                              key: const ValueKey('rolling_turn_count_slider'),
                              value: settings.rollingTurnCount
                                  .clamp(
                                    AppSettings.minRollingTurnCount,
                                    AppSettings.maxRollingTurnCount,
                                  )
                                  .toDouble(),
                              min: AppSettings.minRollingTurnCount.toDouble(),
                              max: AppSettings.maxRollingTurnCount.toDouble(),
                              divisions: AppSettings.maxRollingTurnCount,
                              label: '${settings.rollingTurnCount} turns',
                              onChanged: (value) {
                                unawaited(
                                  _settingsBloc.updateRollingTurnCount(
                                    value.round(),
                                  ),
                                );
                              },
                            ),
                          ),
                          const Divider(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  'Topic Presets (${settings.contextPresets.length})',
                                  style: typography.labelMedium.copyWith(
                                    color: colors.onSurface,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              TextButton(
                                key: const ValueKey(
                                  'settings_toggle_manage_presets_button',
                                ),
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _expandPresetManager =
                                        !_expandPresetManager;
                                  });
                                },
                                child: Text(
                                  _expandPresetManager ? 'Hide' : 'Manage',
                                ),
                              ),
                              TextButton(
                                key: const ValueKey(
                                  'settings_reset_context_presets_button',
                                ),
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                ),
                                onPressed: _settingsBloc
                                    .resetContextPresetsToDefaults,
                                child: const Text('Reset'),
                              ),
                              FilledButton.tonalIcon(
                                key: const ValueKey(
                                  'settings_add_context_preset_button',
                                ),
                                style: FilledButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                ),
                                onPressed: () =>
                                    _showEditPresetDialog(context),
                                icon: const Icon(Icons.add_rounded, size: 14),
                                label: const Text('Add'),
                              ),
                            ],
                          ),
                          if (!_expandPresetManager)
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  for (final preset in settings.contextPresets)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 6),
                                      child: ActionChip(
                                        key: ValueKey(
                                          'settings_preset_chip_${preset.id}',
                                        ),
                                        visualDensity: VisualDensity.compact,
                                        label: Text(preset.displayLabel),
                                        onPressed: () => _showEditPresetDialog(
                                          context,
                                          preset: preset,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            )
                          else ...[
                            const SizedBox(height: 6),
                            for (
                              var i = 0;
                              i < settings.contextPresets.length;
                              i++
                            )
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Container(
                                  key: ValueKey(
                                    'settings_preset_row_${settings.contextPresets[i].id}',
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colors.surface,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: colors.outline),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              settings
                                                  .contextPresets[i]
                                                  .displayLabel,
                                              style: typography.labelMedium
                                                  .copyWith(
                                                    color: colors.onSurface,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                            ),
                                            if (settings
                                                .contextPresets[i]
                                                .keywords
                                                .trim()
                                                .isNotEmpty)
                                              Text(
                                                settings
                                                    .contextPresets[i]
                                                    .keywords,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: typography.bodySmall
                                                    .copyWith(
                                                      color: colors
                                                          .onSurfaceVariant,
                                                    ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        key: ValueKey(
                                          'settings_move_up_preset_${settings.contextPresets[i].id}',
                                        ),
                                        tooltip: 'Move up',
                                        visualDensity: VisualDensity.compact,
                                        icon: const Icon(
                                          Icons.arrow_upward_rounded,
                                          size: 18,
                                        ),
                                        onPressed: i == 0
                                            ? null
                                            : () => unawaited(
                                                _settingsBloc
                                                    .reorderContextPresets(
                                                      i,
                                                      i - 1,
                                                    ),
                                              ),
                                      ),
                                      IconButton(
                                        key: ValueKey(
                                          'settings_move_down_preset_${settings.contextPresets[i].id}',
                                        ),
                                        tooltip: 'Move down',
                                        visualDensity: VisualDensity.compact,
                                        icon: const Icon(
                                          Icons.arrow_downward_rounded,
                                          size: 18,
                                        ),
                                        onPressed:
                                            i ==
                                                settings.contextPresets.length -
                                                    1
                                            ? null
                                            : () => unawaited(
                                                _settingsBloc
                                                    .reorderContextPresets(
                                                      i,
                                                      i + 2,
                                                    ),
                                              ),
                                      ),
                                      IconButton(
                                        key: ValueKey(
                                          'settings_edit_preset_${settings.contextPresets[i].id}',
                                        ),
                                        tooltip: 'Edit preset',
                                        visualDensity: VisualDensity.compact,
                                        icon: const Icon(
                                          Icons.edit_outlined,
                                          size: 18,
                                        ),
                                        onPressed: () => _showEditPresetDialog(
                                          context,
                                          preset: settings.contextPresets[i],
                                        ),
                                      ),
                                      IconButton(
                                        key: ValueKey(
                                          'settings_delete_preset_${settings.contextPresets[i].id}',
                                        ),
                                        tooltip: 'Delete preset',
                                        visualDensity: VisualDensity.compact,
                                        icon: const Icon(
                                          Icons.delete_outline_rounded,
                                          size: 18,
                                        ),
                                        onPressed: () => unawaited(
                                          _settingsBloc.deleteContextPreset(
                                            settings.contextPresets[i].id,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                      ],
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

class _WhisperVariantRow extends StatelessWidget {
  const _WhisperVariantRow({
    required this.variant,
    required this.isSelected,
    required this.isInstalled,
    required this.isDownloadingThis,
    required this.isAnyWhisperDownloading,
    required this.progress,
    required this.onDownload,
    required this.onCancel,
    required this.onRedownload,
  });

  final SupportedOnDeviceSttModel variant;
  final bool isSelected;
  final bool isInstalled;
  final bool isDownloadingThis;
  final bool isAnyWhisperDownloading;
  final double progress;
  final VoidCallback onDownload;
  final VoidCallback onCancel;
  final VoidCallback onRedownload;

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;
    final typography = context.flowTypography;

    return Container(
      key: ValueKey('whisper_variant_row_${variant.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSelected ? colors.primary : colors.outline,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                isInstalled
                    ? Icons.check_circle_rounded
                    : Icons.graphic_eq_rounded,
                size: 18,
                color: isInstalled ? AppTokens.listeningAccent : colors.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isInstalled
                      ? 'Whisper Installed & Ready (${variant.filename})'
                      : isDownloadingThis
                      ? 'Downloading ${variant.name} (${(progress * 100).toStringAsFixed(0)}%)…'
                      : '${variant.name} (${variant.sizeLabel})',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: typography.labelMedium.copyWith(
                    color: colors.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (isDownloadingThis)
                OutlinedButton(
                  key: ValueKey('settings_cancel_whisper_${variant.id}'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: onCancel,
                  child: const Text('Cancel'),
                )
              else if (isInstalled)
                TextButton(
                  key: ValueKey('settings_redownload_whisper_${variant.id}'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: onRedownload,
                  child: const Text('Re-download Whisper'),
                )
              else
                FilledButton.tonalIcon(
                  key: ValueKey('settings_download_whisper_${variant.id}'),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: isAnyWhisperDownloading ? null : onDownload,
                  icon: const Icon(Icons.download_rounded, size: 16),
                  label: const Text('Download Whisper'),
                ),
            ],
          ),
          if (isDownloadingThis) ...[
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: progress > 0 ? progress : null,
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
    super.key,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;
    final typography = context.flowTypography;

    return Container(
      padding: const EdgeInsets.all(12),
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
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: typography.titleSmallEmphasised.copyWith(
              color: colors.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: typography.bodySmall.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}
