import 'dart:async';

import 'package:bloc_signals_flutter/bloc_signals_flutter.dart';
import 'package:flow_ui/flow_ui.dart';
import 'package:get_it/get_it.dart';
import 'package:kaisel/kaisel.dart';
import 'package:material_ui/material_ui.dart';
import 'package:translation_app/core/ai/model_manager.dart';
import 'package:translation_app/core/data/models/app_settings.dart';
import 'package:translation_app/core/logging/app_logger.dart';
import 'package:translation_app/core/routing/routing.dart';
import 'package:translation_app/core/theme/tokens.dart';
import 'package:translation_app/features/conversation/bloc/active_conversation_bloc.dart';
import 'package:translation_app/features/conversation/bloc/active_conversation_state.dart';
import 'package:translation_app/features/conversation/widgets/pulsing_mic_indicator.dart';
import 'package:translation_app/features/settings/bloc/settings_bloc.dart';
import 'package:translation_app/features/settings/bloc/settings_state.dart';

/// Live and historical translation conversation screen powered by `flow_ui`'s
/// [FlowChatView], [FlowThread], and [FlowMessage].
class ActiveChatView extends StatefulWidget {
  const ActiveChatView({
    this.conversationId,
    this.autoStartListening = true,
    this.conversationBloc,
    this.settingsBloc,
    super.key,
  });

  final String? conversationId;
  final bool autoStartListening;
  final ActiveConversationBloc? conversationBloc;
  final SettingsBloc? settingsBloc;

  @override
  State<ActiveChatView> createState() => _ActiveChatViewState();
}

class _ActiveChatViewState extends State<ActiveChatView> {
  static final _log = AppLogger.of('ActiveChatView');

  late final ActiveConversationBloc _conversationBloc;
  late final SettingsBloc _settingsBloc;
  late final bool _ownsConversationBloc;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _log.info(
      'ActiveChatView.initState(conversationId=${widget.conversationId}, '
      'autoStartListening=${widget.autoStartListening})',
    );
    _ownsConversationBloc = widget.conversationBloc == null;
    _conversationBloc =
        widget.conversationBloc ?? GetIt.I<ActiveConversationBloc>();
    _settingsBloc = widget.settingsBloc ?? GetIt.I<SettingsBloc>();

    unawaited(
      _conversationBloc.initialize(
        conversationId: widget.conversationId,
        autoStartListening: widget.autoStartListening,
      ),
    );
  }

  @override
  void dispose() {
    _log.info('ActiveChatView.dispose()');
    _scrollController.dispose();
    if (_ownsConversationBloc) {
      unawaited(_conversationBloc.close());
    }
    super.dispose();
  }

  Future<void> _handleBack() async {
    _log.info('ActiveChatView._handleBack() tapped.');
    await _conversationBloc.stopListening();
    if (!mounted) return;
    final scope = RouterScope.maybeOf<AppRoute>(context);
    if (scope != null) {
      final popped = await scope.router.pop();
      if (!popped) {
        await scope.router.replaceTop(const HomeRoute());
      }
    } else if (GetIt.I.isRegistered<AppRouter>()) {
      final router = GetIt.I<AppRouter>().config.router;
      final popped = await router.pop();
      if (!popped) {
        await router.replaceTop(const HomeRoute());
      }
    } else {
      await Navigator.maybeOf(context)?.maybePop();
    }
  }

  void _openSettings() {
    _log.info('ActiveChatView._openSettings() tapped.');
    final scope = RouterScope.maybeOf<AppRoute>(context);
    if (scope != null) {
      unawaited(scope.router.push(const SettingsRoute()));
    } else if (GetIt.I.isRegistered<AppRouter>()) {
      unawaited(GetIt.I<AppRouter>().config.router.push(const SettingsRoute()));
    }
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

        return BlocSignalBuilder<
          ActiveConversationBloc,
          ActiveConversationState
        >(
          bloc: _conversationBloc,
          builder: (context, state) {
            final flowMessages = <FlowMessageData>[
              for (final msg in state.messages)
                FlowMessageData.text(
                  id: msg.id,
                  role: msg.isBaseLanguage
                      ? FlowMessageRole.user
                      : FlowMessageRole.assistant,
                  // Per user specification, chat bubbles display ONLY translatedText.
                  text: msg.translatedText,
                  timestamp: msg.timestamp,
                ),
              if (state.isLoading)
                const FlowMessageData(
                  id: '__translating_pending__',
                  role: FlowMessageRole.assistant,
                  status: FlowMessageStatus.pending,
                ),
            ];

            final baseName = AppSettings.languageNameFor(settings.baseLanguage);
            final targetName = AppSettings.languageNameFor(
              settings.targetLanguage,
            );

            return Scaffold(
              backgroundColor: colors.surface,
              appBar: AppBar(
                leading: IconButton(
                  key: const ValueKey('chat_back_button'),
                  tooltip: 'Back to Home',
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: _handleBack,
                ),
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$baseName ⇄ $targetName',
                      style: typography.titleSmallEmphasised.copyWith(
                        color: colors.onSurface,
                      ),
                    ),
                    Text(
                      '1 ${settings.baseCurrency} = '
                      '${(exchangeRate?.rate ?? 1.0).toStringAsFixed(2)} '
                      '${settings.targetCurrency}'
                      '${(exchangeRate?.isStale ?? false) ? ' (offline)' : ''}',
                      style: typography.labelSmall.copyWith(
                        color: (exchangeRate?.isStale ?? false)
                            ? AppTokens.warningAmber
                            : colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                actions: [
                  IconButton(
                    key: const ValueKey('chat_settings_button'),
                    tooltip: 'Settings',
                    icon: const Icon(Icons.tune_rounded),
                    onPressed: _openSettings,
                  ),
                ],
              ),
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  BlocSignalBuilder<ModelManager, ModelDownloadState>(
                    bloc: _settingsBloc.modelManager,
                    builder: (context, modelState) {
                      if (!modelState.isDownloading) {
                        return const SizedBox.shrink();
                      }
                      return Container(
                        key: const ValueKey('chat_model_download_banner'),
                        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: colors.outline),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.cloud_download_rounded,
                                  size: 18,
                                  color: colors.primary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Downloading Gemma 4 E2B model '
                                    '(${(modelState.progress * 100).toStringAsFixed(0)}%)… '
                                    'Microphone is active and buffering speech.',
                                    style: typography.bodySmall.copyWith(
                                      color: colors.onSurface,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            LinearProgressIndicator(
                              value: modelState.progress.clamp(0.02, 1.0),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  if (state.error != null)
                    Container(
                      key: const ValueKey('chat_error_banner'),
                      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: AppTokens.errorRed.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppTokens.errorRed.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            size: 18,
                            color: AppTokens.errorRed,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              state.error!,
                              style: typography.bodySmall.copyWith(
                                color: colors.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: FlowChatView(
                      empty: flowMessages.isEmpty,
                      greeting: FlowGreeting(
                        icon: state.isListening
                            ? Icons.graphic_eq_rounded
                            : Icons.mic_none_rounded,
                        text: state.isListening
                            ? 'Speak in $baseName or $targetName'
                            : 'Tap Resume to translate',
                        textStyle: typography.titleLarge.copyWith(
                          color: colors.onSurface,
                        ),
                      ),
                      threadController: _scrollController,
                      thread: FlowThread(
                        key: const ValueKey('active_flow_thread'),
                        messages: flowMessages,
                        controller: _scrollController,
                        thinkingLabel: 'Translating…',
                        markdown: false,
                      ),
                      composer: PulsingMicIndicator(
                        key: const ValueKey('active_pulsing_mic_indicator'),
                        isListening: state.isListening,
                        isLoading: state.isLoading,
                        amplitude: state.amplitude,
                        onToggleListening: _conversationBloc.toggleListening,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
