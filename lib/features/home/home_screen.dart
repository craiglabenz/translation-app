import 'dart:async';

import 'package:bloc_signals_flutter/bloc_signals_flutter.dart';
import 'package:flow_ui/flow_ui.dart';
import 'package:get_it/get_it.dart';
import 'package:kaisel/kaisel.dart';
import 'package:material_ui/material_ui.dart';
import 'package:translation_app/core/ai/model_manager.dart';
import 'package:translation_app/core/data/models/app_settings.dart';
import 'package:translation_app/core/data/models/conversation.dart';
import 'package:translation_app/core/data/repositories/conversation_repository.dart';
import 'package:translation_app/core/logging/app_logger.dart';
import 'package:translation_app/core/routing/routing.dart';
import 'package:translation_app/core/theme/tokens.dart';
import 'package:translation_app/features/home/widgets/ripple_start_button.dart';
import 'package:translation_app/features/settings/bloc/settings_bloc.dart';
import 'package:translation_app/features/settings/bloc/settings_state.dart';

/// Home screen featuring the language/currency [FlowPill], on-device Gemma 4
/// model readiness banner, central [RippleStartButton], and a navigation
/// [Drawer] listing past conversations rendered with [FlowThreadList.flat].
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    this.settingsBloc,
    this.conversationRepository,
    super.key,
  });

  final SettingsBloc? settingsBloc;
  final ConversationRepository? conversationRepository;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static final _log = AppLogger.of('HomeScreen');

  late final SettingsBloc _settingsBloc;
  late final ConversationRepository _conversationRepository;
  StreamSubscription<void>? _conversationsSub;
  List<Conversation> _recentConversations = const <Conversation>[];

  @override
  void initState() {
    super.initState();
    _log.info('HomeScreen.initState()');
    _settingsBloc = widget.settingsBloc ?? GetIt.I<SettingsBloc>();
    _conversationRepository =
        widget.conversationRepository ?? GetIt.I<ConversationRepository>();

    Future<void>.microtask(() {
      if (mounted && !_settingsBloc.isClosed) {
        unawaited(_settingsBloc.load());
      }
    });
    unawaited(_loadRecentConversations());
    _conversationsSub = _conversationRepository.onConversationsChanged.listen((
      _,
    ) {
      unawaited(_loadRecentConversations());
    });
  }

  Future<void> _loadRecentConversations() async {
    final recent = await _conversationRepository.getAllConversations();
    _log.fine('Loaded ${recent.length} past conversations for drawer.');
    if (mounted) {
      setState(() {
        _recentConversations = recent;
      });
    }
  }

  @override
  void dispose() {
    unawaited(_conversationsSub?.cancel());
    super.dispose();
  }

  void _navigateTo(AppRoute route) {
    _log.info('HomeScreen navigating to route: $route');
    final scope = RouterScope.maybeOf<AppRoute>(context);
    if (scope != null) {
      unawaited(scope.router.push(route));
    } else if (GetIt.I.isRegistered<AppRouter>()) {
      unawaited(GetIt.I<AppRouter>().config.router.push(route));
    } else {
      _log.warning('No RouterScope or AppRouter found for navigation to $route');
    }
  }

  Future<void> _deleteConversation(String conversationId) async {
    _log.info('HomeScreen deleting conversation id=$conversationId');
    await _conversationRepository.deleteConversation(conversationId);
  }

  Future<void> _showCustomContextStartDialog(BuildContext context) async {
    var keywordsText = '';
    var saveAsPreset = false;
    var presetName = '';
    var presetIcon = '💬';

    final shouldStart = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              key: const ValueKey('home_custom_context_dialog'),
              title: const Text('Start with Custom Context'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Enter topic keywords, names, dishes, or jargon (comma-separated) to boost speech recognition and translation accuracy.',
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const ValueKey('home_custom_keywords_input'),
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Keywords / Vocabulary Hints',
                        hintText: 'e.g., shellfish allergy, Shinjuku, oat milk',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) => keywordsText = value,
                    ),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      key: const ValueKey('home_save_preset_checkbox'),
                      contentPadding: EdgeInsets.zero,
                      value: saveAsPreset,
                      title: const Text('Save as reusable preset'),
                      onChanged: (val) {
                        setDialogState(() {
                          saveAsPreset = val ?? false;
                        });
                      },
                    ),
                    if (saveAsPreset) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          SizedBox(
                            width: 72,
                            child: TextFormField(
                              key: const ValueKey('home_preset_icon_input'),
                              initialValue: presetIcon,
                              decoration: const InputDecoration(
                                labelText: 'Icon',
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (val) => presetIcon = val,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              key: const ValueKey('home_preset_name_input'),
                              decoration: const InputDecoration(
                                labelText: 'Preset Name',
                                hintText: 'e.g., Coffee Shop',
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (val) => presetName = val,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  key: const ValueKey('home_custom_context_cancel_button'),
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  key: const ValueKey('home_custom_context_start_button'),
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  icon: const Icon(Icons.mic_rounded, size: 18),
                  label: const Text('Start Conversation'),
                ),
              ],
            );
          },
        );
      },
    );

    if (shouldStart != true || !mounted) return;

    final parsedKeywords = keywordsText
        .split(RegExp(r'[,;\n]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList(growable: false);

    final initialContextIds = <String>[];
    if (saveAsPreset && presetName.trim().isNotEmpty) {
      final presetId =
          'custom_${DateTime.now().millisecondsSinceEpoch}_${presetName.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_')}';
      final newPreset = ConversationContextPreset(
        id: presetId,
        name: presetName.trim(),
        icon: presetIcon.trim().isEmpty ? '💬' : presetIcon.trim(),
        keywords: parsedKeywords.join(', '),
      );
      await _settingsBloc.saveContextPreset(newPreset);
      initialContextIds.add(presetId);
    }

    if (!mounted) return;
    _navigateTo(
      ChatRoute(
        autoStartListening: true,
        initialContextIds: initialContextIds,
        initialCustomKeywords: initialContextIds.isEmpty
            ? parsedKeywords
            : const <String>[],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;
    final typography = context.flowTypography;

    return BlocSignalBuilder<SettingsBloc, SettingsState>(
      bloc: _settingsBloc,
      builder: (context, settingsState) {
        final settings = settingsState.settings;
        final exchangeRate = settingsState.exchangeRate;

        return Scaffold(
          backgroundColor: colors.surface,
          drawer: _PastConversationsDrawer(
            conversations: _recentConversations,
            onSelectConversation: (id) {
              Navigator.maybeOf(context)?.pop();
              _navigateTo(
                ChatRoute(
                  conversationId: id,
                  autoStartListening: false,
                ),
              );
            },
            onDeleteConversation: _deleteConversation,
            onSeeAll: () {
              Navigator.maybeOf(context)?.pop();
              _navigateTo(const HistoryRoute());
            },
          ),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AppTokens.maxContentWidth,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTokens.pageHorizontalPadding,
                    vertical: 16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Top Header with Drawer button, FlowPill, and Settings / Swap actions
                      Row(
                        children: [
                          Builder(
                            builder: (drawerContext) => IconButton(
                              key: const ValueKey('home_drawer_button'),
                              tooltip: 'Past conversations',
                              icon: Icon(
                                Icons.menu_rounded,
                                color: colors.onSurfaceVariant,
                              ),
                              onPressed: () =>
                                  Scaffold.of(drawerContext).openDrawer(),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: AlignmentDirectional.centerStart,
                                child: FlowPill(
                                  key: const ValueKey('home_language_pill'),
                                  icon: Icons.translate_rounded,
                                  label: settings.pairLabel,
                                  showLabel: true,
                                  tooltip: 'Configure languages and currencies',
                                  onTap: () =>
                                      _navigateTo(const SettingsRoute()),
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            key: const ValueKey('home_swap_pair_button'),
                            tooltip: 'Swap languages and currencies',
                            icon: Icon(
                              Icons.swap_horiz_rounded,
                              color: colors.onSurfaceVariant,
                            ),
                            onPressed: _settingsBloc.swapPair,
                          ),
                          IconButton(
                            key: const ValueKey('home_settings_button'),
                            tooltip: 'Settings',
                            icon: Icon(
                              Icons.settings_outlined,
                              color: colors.onSurfaceVariant,
                            ),
                            onPressed: () => _navigateTo(const SettingsRoute()),
                          ),
                        ],
                      ),

                      if (exchangeRate != null && exchangeRate.isStale) ...[
                        const SizedBox(height: 8),
                        Container(
                          key: const ValueKey('stale_rate_banner'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: AppTokens.warningAmber.withValues(
                              alpha: 0.12,
                            ),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: AppTokens.warningAmber.withValues(
                                alpha: 0.4,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.cloud_off_rounded,
                                size: 16,
                                color: AppTokens.warningAmber,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Offline rate: 1 ${exchangeRate.baseCurrency} = '
                                  '${exchangeRate.rate.toStringAsFixed(2)} '
                                  '${exchangeRate.targetCurrency} (cached)',
                                  style: typography.labelSmall.copyWith(
                                    color: colors.onSurface,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // Active Engine Readiness Banner (On-Device Model or Cloud API Key)
                      if (settings.translationEngineMode ==
                              TranslationEngineMode.cloud ||
                          settings.sttEngineMode ==
                              TranslationEngineMode.cloud) ...[
                        if (settings.geminiApiKey.trim().isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Container(
                              key: const ValueKey('home_cloud_api_key_banner'),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: colors.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: colors.primary.withValues(alpha: 0.4),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.vpn_key_outlined,
                                    color: colors.primary,
                                    size: 22,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Gemini API Key Required for Cloud Translation',
                                          style: typography.labelLarge.copyWith(
                                            color: colors.onSurface,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Enter your key from aistudio.google.com/apikey in Settings, or switch back to On-Device mode.',
                                          style: typography.bodySmall.copyWith(
                                            color: colors.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  FilledButton(
                                    key: const ValueKey(
                                      'home_configure_api_key_button',
                                    ),
                                    onPressed: () =>
                                        _navigateTo(const SettingsRoute()),
                                    child: const Text('Settings'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ] else
                        BlocSignalBuilder<ModelManager, ModelDownloadState>(
                          bloc: _settingsBloc.modelManager,
                          builder: (context, modelState) {
                            if (modelState.isInstalled) {
                              return const SizedBox.shrink();
                            }
                            return Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: _ModelStatusBanner(
                                modelState: modelState,
                                onDownload: _settingsBloc.downloadModel,
                                onCancel:
                                    _settingsBloc.modelManager.cancelDownload,
                              ),
                            );
                          },
                        ),

                      // Center Ripple Start Button
                      Expanded(
                        child: Center(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: RippleStartButton(
                              key: const ValueKey('home_start_button'),
                              label: 'Tap to Translate',
                              subtitle:
                                  '1 ${settings.baseCurrency} = '
                                  '${(exchangeRate?.rate ?? 1.0).toStringAsFixed(2)} '
                                  '${settings.targetCurrency}',
                              onTap: () => _navigateTo(
                                const ChatRoute(autoStartListening: true),
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Bottom Horizontal Scrolling Strip of Quick-Start Topic Pills
                      const SizedBox(height: 8),
                      Column(
                        key: const ValueKey('home_context_presets_strip'),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.auto_awesome_outlined,
                                size: 14,
                                color: colors.onSurfaceVariant,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Quick-Start with Topic Context (1-tap)',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: typography.labelSmall.copyWith(
                                    color: colors.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                for (final preset in settings.contextPresets)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: ActionChip(
                                      key: ValueKey(
                                        'home_context_pill_${preset.id}',
                                      ),
                                      label: Text(preset.displayLabel),
                                      tooltip:
                                          'Start translating with ${preset.name} vocabulary hints',
                                      onPressed: () => _navigateTo(
                                        ChatRoute(
                                          autoStartListening: true,
                                          initialContextIds: <String>[
                                            preset.id,
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ActionChip(
                                  key: const ValueKey(
                                    'home_custom_context_pill',
                                  ),
                                  avatar: const Icon(
                                    Icons.add_rounded,
                                    size: 16,
                                  ),
                                  label: const Text('Custom'),
                                  tooltip:
                                      'Start with custom keywords or save a new preset',
                                  onPressed: () =>
                                      _showCustomContextStartDialog(context),
                                ),
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
          ),
        );
      },
    );
  }
}

class _ModelStatusBanner extends StatelessWidget {
  const _ModelStatusBanner({
    required this.modelState,
    required this.onDownload,
    required this.onCancel,
  });

  final ModelDownloadState modelState;
  final VoidCallback onDownload;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;
    final typography = context.flowTypography;

    return Container(
      key: const ValueKey('home_model_banner'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                Icons.memory_rounded,
                size: 20,
                color: colors.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  modelState.isDownloading
                      ? 'Downloading Gemma 4 E2B (${(modelState.progress * 100).toStringAsFixed(0)}%)…'
                      : 'Gemma 4 E2B On-Device Model Required',
                  style: typography.labelLarge.copyWith(
                    color: colors.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (modelState.isDownloading)
                TextButton(
                  onPressed: onCancel,
                  child: const Text('Cancel'),
                )
              else
                FilledButton.tonalIcon(
                  key: const ValueKey('home_download_model_button'),
                  onPressed: onDownload,
                  icon: const Icon(Icons.download_rounded, size: 16),
                  label: const Text('Download'),
                ),
            ],
          ),
          if (modelState.isDownloading) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: modelState.progress > 0 ? modelState.progress : null,
              borderRadius: BorderRadius.circular(4),
            ),
          ] else if (modelState.error != null) ...[
            const SizedBox(height: 6),
            Text(
              modelState.error!,
              style: typography.bodySmall.copyWith(
                color: AppTokens.errorRed,
              ),
            ),
          ] else ...[
            const SizedBox(height: 4),
            Text(
              'Download the LiteRT-LM weights (~1.6 GB) once for 100% offline speech translation.',
              style: typography.bodySmall.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PastConversationsDrawer extends StatelessWidget {
  const _PastConversationsDrawer({
    required this.conversations,
    required this.onSelectConversation,
    required this.onDeleteConversation,
    required this.onSeeAll,
  });

  final List<Conversation> conversations;
  final ValueChanged<String> onSelectConversation;
  final ValueChanged<String> onDeleteConversation;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;
    final typography = context.flowTypography;

    final threadItems = conversations
        .map(
          (c) => FlowThreadListItem(
            id: c.id,
            title:
                (c.userSummary ?? c.generatedSummary) ??
                (c.previewText.trim().isNotEmpty
                    ? c.previewText
                    : '${AppSettings.languageNameFor(c.baseLanguage)} ⇄ '
                          '${AppSettings.languageNameFor(c.targetLanguage)}'),
            icon: Icons.chat_bubble_outline_rounded,
          ),
        )
        .toList();

    return Drawer(
      key: const ValueKey('home_conversations_drawer'),
      backgroundColor: colors.surface,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Past Conversations',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: typography.titleSmallEmphasised.copyWith(
                        color: colors.onSurface,
                      ),
                    ),
                  ),
                  TextButton(
                    key: const ValueKey('home_see_all_history_button'),
                    onPressed: onSeeAll,
                    child: const Text('See All'),
                  ),
                  IconButton(
                    key: const ValueKey('home_close_drawer_button'),
                    tooltip: 'Close drawer',
                    icon: Icon(
                      Icons.close_rounded,
                      color: colors.onSurfaceVariant,
                    ),
                    onPressed: () => Navigator.maybeOf(context)?.pop(),
                  ),
                ],
              ),
              const Divider(height: 16),
              if (threadItems.isEmpty)
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'No conversations yet. Tap the microphone to start translating.',
                        textAlign: TextAlign.center,
                        style: typography.bodySmall.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                )
              else
                Expanded(
                  child: SingleChildScrollView(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: FlowThreadList.flat(
                            key: const ValueKey('home_recent_threads_list'),
                            items: threadItems,
                            shrinkWrap: true,
                            onThreadSelected: onSelectConversation,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            for (var i = 0; i < conversations.length; i++)
                              Padding(
                                padding: EdgeInsets.only(top: i == 0 ? 0 : 2),
                                child: SizedBox(
                                  height: 36,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        conversations[i].relativeTimeLabel(),
                                        key: ValueKey(
                                          'home_conv_time_${conversations[i].id}',
                                        ),
                                        style: typography.labelSmall.copyWith(
                                          color: colors.onSurfaceMuted,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      SizedBox(
                                        width: 36,
                                        height: 36,
                                        child: IconButton(
                                          key: ValueKey(
                                            'home_delete_conv_${conversations[i].id}',
                                          ),
                                          padding: EdgeInsets.zero,
                                          tooltip: 'Delete conversation',
                                          icon: Icon(
                                            Icons.delete_outline_rounded,
                                            size: 18,
                                            color: colors.onSurfaceMuted,
                                          ),
                                          onPressed: () => onDeleteConversation(
                                            conversations[i].id,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
