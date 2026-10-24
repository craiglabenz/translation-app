import 'dart:async';
import 'dart:ui' show FrameTiming;

import 'package:bloc_signals_flutter/bloc_signals_flutter.dart';
import 'package:flow_ui/flow_ui.dart';
import 'package:get_it/get_it.dart';
import 'package:kaisel/kaisel.dart';
import 'package:material_ui/material_ui.dart';
import 'package:translation_app/core/ai/model_manager.dart';
import 'package:translation_app/core/data/models/app_settings.dart';
import 'package:translation_app/core/data/models/message.dart';
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
    this.initialContextIds = const <String>[],
    this.initialCustomKeywords = const <String>[],
    this.conversationBloc,
    this.settingsBloc,
    super.key,
  });

  final String? conversationId;
  final bool autoStartListening;
  final List<String> initialContextIds;
  final List<String> initialCustomKeywords;
  final ActiveConversationBloc? conversationBloc;
  final SettingsBloc? settingsBloc;

  /// Multiplies the user-selected [userMultiplier] (`0.5` to `3.0`) against the
  /// ambient OS-level [osTextScaler] instead of overwriting it.
  static TextScaler computeEffectiveTextScaler(
    TextScaler osTextScaler,
    double userMultiplier,
  ) {
    final clampedMultiplier = userMultiplier.clamp(
      AppSettings.minTextScaleFactor,
      AppSettings.maxTextScaleFactor,
    );
    final osScaleFactor = osTextScaler.scale(1.0);
    return TextScaler.linear(osScaleFactor * clampedMultiplier);
  }

  @override
  State<ActiveChatView> createState() => _ActiveChatViewState();
}

class _ActiveChatViewState extends State<ActiveChatView> {
  static final _log = AppLogger.of('ActiveChatView');

  late final ActiveConversationBloc _conversationBloc;
  late final SettingsBloc _settingsBloc;
  late final bool _ownsConversationBloc;
  final ScrollController _scrollController = ScrollController();
  final Stopwatch _mountStopwatch = Stopwatch();
  final List<FrameTiming> _transitionFrameTimings = <FrameTiming>[];

  Animation<double>? _routeAnimation;
  bool _didScheduleInitialize = false;
  bool _didRunInitialize = false;
  bool _isMonitoringFrames = false;
  int _buildCount = 0;

  @override
  void initState() {
    super.initState();
    _mountStopwatch.start();
    final initSw = Stopwatch()..start();
    _log.info(
      '[PERF] ActiveChatView.initState START '
      '(conversationId=${widget.conversationId}, '
      'autoStartListening=${widget.autoStartListening})',
    );
    _ownsConversationBloc = widget.conversationBloc == null;
    _conversationBloc =
        widget.conversationBloc ?? GetIt.I<ActiveConversationBloc>();
    _settingsBloc = widget.settingsBloc ?? GetIt.I<SettingsBloc>();
    initSw.stop();
    _log.info(
      '[PERF] ActiveChatView.initState FINISH (${initSw.elapsedMicroseconds}us)',
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didScheduleInitialize) return;
    _didScheduleInitialize = true;

    final animation = ModalRoute.of(context)?.animation;
    _log.info(
      '[PERF] ActiveChatView.didChangeDependencies '
      '(elapsedSinceMount=${_mountStopwatch.elapsedMilliseconds}ms, '
      'hasRouteAnimation=${animation != null}, '
      'animationStatus=${animation?.status}, '
      'animationValue=${animation?.value.toStringAsFixed(2)})',
    );
    if (animation != null && !animation.isCompleted) {
      _log.info(
        '[PERF] Deferring chat session initialization until page transition completes...',
      );
      _routeAnimation = animation;
      _startFrameTimingMonitor();
      animation.addStatusListener(_onRouteAnimationStatusChanged);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _triggerInitializeIfNeeded();
      });
    }
  }

  void _startFrameTimingMonitor() {
    if (_isMonitoringFrames) return;
    _isMonitoringFrames = true;
    _transitionFrameTimings.clear();
    WidgetsBinding.instance.addTimingsCallback(_onFrameTimings);
  }

  void _stopFrameTimingMonitor() {
    if (!_isMonitoringFrames) return;
    _isMonitoringFrames = false;
    WidgetsBinding.instance.removeTimingsCallback(_onFrameTimings);
    if (_transitionFrameTimings.isEmpty) return;

    var maxBuildUs = 0;
    var maxRasterUs = 0;
    var jankyCount = 0;
    for (final timing in _transitionFrameTimings) {
      final buildUs = timing.buildDuration.inMicroseconds;
      final rasterUs = timing.rasterDuration.inMicroseconds;
      if (buildUs > maxBuildUs) maxBuildUs = buildUs;
      if (rasterUs > maxRasterUs) maxRasterUs = rasterUs;
      if (timing.totalSpan.inMilliseconds > 16) {
        jankyCount++;
      }
    }
    _log.info(
      '[PERF] ActiveChatView route transition frame summary: '
      'frames=${_transitionFrameTimings.length}, '
      'jankyFrames(>16ms)=$jankyCount, '
      'maxBuild=${(maxBuildUs / 1000.0).toStringAsFixed(2)}ms, '
      'maxRaster=${(maxRasterUs / 1000.0).toStringAsFixed(2)}ms',
    );
    _transitionFrameTimings.clear();
  }

  void _onFrameTimings(List<FrameTiming> timings) {
    _transitionFrameTimings.addAll(timings);
    for (final t in timings) {
      if (t.totalSpan.inMilliseconds > 32) {
        _log.warning(
          '[PERF] Slow frame during ActiveChatView transition: '
          'build=${(t.buildDuration.inMicroseconds / 1000.0).toStringAsFixed(2)}ms, '
          'raster=${(t.rasterDuration.inMicroseconds / 1000.0).toStringAsFixed(2)}ms, '
          'total=${(t.totalSpan.inMicroseconds / 1000.0).toStringAsFixed(2)}ms',
        );
      }
    }
  }

  void _onRouteAnimationStatusChanged(AnimationStatus status) {
    _log.info(
      '[PERF] ActiveChatView route animation status -> $status '
      '(elapsedSinceMount=${_mountStopwatch.elapsedMilliseconds}ms)',
    );
    if (status == AnimationStatus.completed ||
        status == AnimationStatus.dismissed) {
      _routeAnimation?.removeStatusListener(_onRouteAnimationStatusChanged);
      _routeAnimation = null;
      _stopFrameTimingMonitor();
      if (status == AnimationStatus.completed) {
        _triggerInitializeIfNeeded();
      }
    }
  }

  void _triggerInitializeIfNeeded() {
    if (_didRunInitialize || !mounted) return;
    _didRunInitialize = true;
    _log.info(
      '[PERF] ActiveChatView._triggerInitializeIfNeeded() START '
      '(elapsedSinceMount=${_mountStopwatch.elapsedMilliseconds}ms)',
    );
    unawaited(
      _conversationBloc
          .initialize(
            conversationId: widget.conversationId,
            autoStartListening: widget.autoStartListening,
            initialContextIds: widget.initialContextIds,
            initialCustomKeywords: widget.initialCustomKeywords,
          )
          .whenComplete(() {
            _log.info(
              '[PERF] ActiveChatView._triggerInitializeIfNeeded() FINISH '
              '(elapsedSinceMount=${_mountStopwatch.elapsedMilliseconds}ms)',
            );
          }),
    );
  }

  @override
  void dispose() {
    _log.info('ActiveChatView.dispose()');
    _stopFrameTimingMonitor();
    _routeAnimation?.removeStatusListener(_onRouteAnimationStatusChanged);
    _routeAnimation = null;
    _scrollController.dispose();
    if (_ownsConversationBloc) {
      unawaited(_conversationBloc.close());
    } else {
      unawaited(_conversationBloc.exitSession());
    }
    super.dispose();
  }

  Future<void> _handleBack() async {
    _log.info('ActiveChatView._handleBack() tapped.');
    await _conversationBloc.exitSession();
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

  Future<void> _handleDeleteConversation() async {
    _log.info('ActiveChatView._handleDeleteConversation() tapped.');
    final deleted = await _conversationBloc.deleteCurrentConversation();
    if (!deleted || !mounted) return;
    await _handleBack();
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

  Future<void> _showEditSummaryDialog(
    BuildContext context, {
    required String? currentSummary,
  }) async {
    _log.info('ActiveChatView._showEditSummaryDialog() tapped.');
    var draftSummary = currentSummary ?? '';
    final newSummary = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return AlertDialog(
          key: const ValueKey('edit_summary_dialog'),
          title: const Text('Edit Conversation Summary'),
          content: TextFormField(
            key: const ValueKey('edit_summary_text_field'),
            initialValue: draftSummary,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              hintText: 'Enter 3 to 5 word summary',
              border: OutlineInputBorder(),
            ),
            onChanged: (value) => draftSummary = value,
            onFieldSubmitted: (value) =>
                Navigator.of(dialogContext).pop(value),
          ),
          actions: [
            TextButton(
              key: const ValueKey('edit_summary_cancel_button'),
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey('edit_summary_save_button'),
              onPressed: () => Navigator.of(dialogContext).pop(draftSummary),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (newSummary != null && newSummary.trim().isNotEmpty && mounted) {
      await _conversationBloc.updateSummary(newSummary);
    }
  }

  Future<void> _showContextEditorDialog(BuildContext context) async {
    _log.info('ActiveChatView._showContextEditorDialog() tapped.');
    var keywordInput = '';
    var showNewPresetForm = false;
    var newPresetIcon = '💬';
    var newPresetName = '';
    var newPresetKeywords = '';

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return BlocSignalBuilder<SettingsBloc, SettingsState>(
              bloc: _settingsBloc,
              builder: (context, settingsState) {
                final settings = settingsState.settings;
                return BlocSignalBuilder<
                  ActiveConversationBloc,
                  ActiveConversationState
                >(
                  bloc: _conversationBloc,
                  builder: (context, convState) {
                    final activeIds =
                        convState.conversation?.activeContextIds ??
                        _conversationBloc.activeContextIds;
                    final activeKeywords =
                        convState.conversation?.customKeywords ??
                        _conversationBloc.customKeywords;

                    return AlertDialog(
                      key: const ValueKey('chat_context_editor_dialog'),
                      title: const Text('Conversation Context'),
                      content: SizedBox(
                        width: 420,
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Topic Presets (Multi-Select)',
                                style: context.flowTypography.labelLarge
                                    .copyWith(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  for (final preset in settings.contextPresets)
                                    FilterChip(
                                      key: ValueKey(
                                        'chat_editor_preset_chip_${preset.id}',
                                      ),
                                      visualDensity: VisualDensity.compact,
                                      label: Text(preset.displayLabel),
                                      selected: activeIds.contains(preset.id),
                                      onSelected: (_) {
                                        unawaited(
                                          _conversationBloc.toggleContextPreset(
                                            preset.id,
                                          ),
                                        );
                                      },
                                    ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Custom Keywords & Names',
                                style: context.flowTypography.labelLarge
                                    .copyWith(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      key: const ValueKey(
                                        'chat_editor_custom_keyword_input',
                                      ),
                                      decoration: const InputDecoration(
                                        hintText:
                                            'e.g., shellfish, Shinjuku, oat milk',
                                        isDense: true,
                                        border: OutlineInputBorder(),
                                      ),
                                      onChanged: (val) => keywordInput = val,
                                      onFieldSubmitted: (val) {
                                        if (val.trim().isNotEmpty) {
                                          unawaited(
                                            _conversationBloc.addCustomKeyword(
                                              val,
                                            ),
                                          );
                                          keywordInput = '';
                                        }
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  FilledButton.tonal(
                                    key: const ValueKey(
                                      'chat_editor_add_keyword_button',
                                    ),
                                    onPressed: () {
                                      if (keywordInput.trim().isNotEmpty) {
                                        unawaited(
                                          _conversationBloc.addCustomKeyword(
                                            keywordInput,
                                          ),
                                        );
                                        keywordInput = '';
                                      }
                                    },
                                    child: const Text('Add'),
                                  ),
                                ],
                              ),
                              if (activeKeywords.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    for (final kw in activeKeywords)
                                      InputChip(
                                        key: ValueKey(
                                          'chat_editor_keyword_chip_$kw',
                                        ),
                                        label: Text(kw),
                                        onDeleted: () {
                                          unawaited(
                                            _conversationBloc
                                                .removeCustomKeyword(kw),
                                          );
                                        },
                                      ),
                                  ],
                                ),
                              ],
                              const Divider(height: 24),
                              if (!showNewPresetForm)
                                OutlinedButton.icon(
                                  key: const ValueKey(
                                    'chat_save_new_preset_button',
                                  ),
                                  onPressed: () {
                                    setDialogState(() {
                                      showNewPresetForm = true;
                                      newPresetKeywords = activeKeywords.join(
                                        ', ',
                                      );
                                    });
                                  },
                                  icon: const Icon(
                                    Icons.bookmark_add_outlined,
                                    size: 16,
                                  ),
                                  label: const Text('Save New Topic Preset'),
                                )
                              else
                                Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      'New Topic Preset',
                                      style: context.flowTypography.labelMedium
                                          .copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        SizedBox(
                                          width: 64,
                                          child: TextFormField(
                                            key: const ValueKey(
                                              'chat_new_preset_icon_input',
                                            ),
                                            initialValue: newPresetIcon,
                                            decoration: const InputDecoration(
                                              labelText: 'Icon',
                                              isDense: true,
                                              border: OutlineInputBorder(),
                                            ),
                                            onChanged: (val) =>
                                                newPresetIcon = val,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: TextFormField(
                                            key: const ValueKey(
                                              'chat_new_preset_name_input',
                                            ),
                                            decoration: const InputDecoration(
                                              labelText: 'Preset Name',
                                              hintText: 'e.g., Coffee Shop',
                                              isDense: true,
                                              border: OutlineInputBorder(),
                                            ),
                                            onChanged: (val) =>
                                                newPresetName = val,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    TextFormField(
                                      key: const ValueKey(
                                        'chat_new_preset_keywords_input',
                                      ),
                                      initialValue: newPresetKeywords,
                                      decoration: const InputDecoration(
                                        labelText: 'Vocabulary Keywords',
                                        hintText:
                                            'espresso, oat milk, croissant',
                                        isDense: true,
                                        border: OutlineInputBorder(),
                                      ),
                                      onChanged: (val) =>
                                          newPresetKeywords = val,
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        TextButton(
                                          onPressed: () {
                                            setDialogState(() {
                                              showNewPresetForm = false;
                                            });
                                          },
                                          child: const Text('Cancel'),
                                        ),
                                        const SizedBox(width: 8),
                                        FilledButton.tonal(
                                          key: const ValueKey(
                                            'chat_confirm_save_preset_button',
                                          ),
                                          onPressed: () async {
                                            if (newPresetName.trim().isEmpty) {
                                              return;
                                            }
                                            final presetId =
                                                'custom_${DateTime.now().millisecondsSinceEpoch}_${newPresetName.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_')}';
                                            final preset =
                                                ConversationContextPreset(
                                                  id: presetId,
                                                  name: newPresetName.trim(),
                                                  icon:
                                                      newPresetIcon
                                                          .trim()
                                                          .isEmpty
                                                      ? '💬'
                                                      : newPresetIcon.trim(),
                                                  keywords: newPresetKeywords
                                                      .trim(),
                                                );
                                            await _settingsBloc
                                                .saveContextPreset(preset);
                                            await _conversationBloc
                                                .toggleContextPreset(presetId);
                                            setDialogState(() {
                                              showNewPresetForm = false;
                                            });
                                          },
                                          child: const Text('Save Preset'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                      actions: [
                        FilledButton(
                          key: const ValueKey('chat_context_editor_done_button'),
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          child: const Text('Done'),
                        ),
                      ],
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _showOriginalMessageModal(
    BuildContext context, {
    required Message message,
    required String baseLanguageName,
    required String targetLanguageName,
    required String baseLanguageFlag,
    required String targetLanguageFlag,
  }) async {
    final spokenLanguageName = message.isBaseLanguage
        ? baseLanguageName
        : targetLanguageName;
    final spokenLanguageFlag = message.isBaseLanguage
        ? baseLanguageFlag
        : targetLanguageFlag;
    final originalDisplay = message.originalText.trim().isNotEmpty
        ? message.originalText.trim()
        : message.translatedText.trim();

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        final colors = dialogContext.flowColors;
        final typography = dialogContext.flowTypography;

        return GestureDetector(
          key: const ValueKey('original_message_modal_dismiss_area'),
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(dialogContext).pop(),
          child: Material(
            type: MaterialType.transparency,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Container(
                    key: const ValueKey('original_message_modal'),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: colors.outline),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              spokenLanguageFlag,
                              style: typography.titleMedium,
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              Icons.record_voice_over_rounded,
                              size: 18,
                              color: colors.primary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Original ($spokenLanguageName)',
                                style: typography.labelLarge.copyWith(
                                  color: colors.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          originalDisplay,
                          key: const ValueKey('original_message_modal_text'),
                          style: typography.titleMedium.copyWith(
                            color: colors.onSurface,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          key: const ValueKey(
                            'original_message_modal_timing_section',
                          ),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colors.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: colors.outline),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.timer_outlined,
                                    size: 15,
                                    color: colors.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Processing Time',
                                    style: typography.labelMedium.copyWith(
                                      color: colors.onSurface,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              _TimingStepRow(
                                label: 'Speech-to-text',
                                modelName: message.speechToTextModel,
                                modelKey: const ValueKey(
                                  'modal_speech_to_text_model',
                                ),
                                value: Message.formatDurationMs(
                                  message.speechToTextMs,
                                ),
                                valueKey: const ValueKey(
                                  'modal_speech_to_text_duration',
                                ),
                              ),
                              const SizedBox(height: 6),
                              _TimingStepRow(
                                label: 'Translation',
                                modelName: message.translationModel,
                                modelKey: const ValueKey(
                                  'modal_translation_model',
                                ),
                                value: Message.formatDurationMs(
                                  message.translationMs,
                                ),
                                valueKey: const ValueKey(
                                  'modal_translation_duration',
                                ),
                              ),
                              const Divider(height: 12),
                              _TimingStepRow(
                                label: 'Total',
                                value: Message.formatDurationMs(
                                  message.totalDurationMs ??
                                      ((message.speechToTextMs != null ||
                                              message.translationMs != null)
                                          ? (message.speechToTextMs ?? 0) +
                                                (message.translationMs ?? 0)
                                          : null),
                                ),
                                valueKey: const ValueKey(
                                  'modal_total_duration',
                                ),
                                isEmphasized: true,
                              ),
                              const Divider(height: 12),
                              _TimingStepRow(
                                label: 'Situational Context',
                                value:
                                    message.activeContextSummary != null &&
                                        message.activeContextSummary!
                                            .trim()
                                            .isNotEmpty
                                    ? message.activeContextSummary!.trim()
                                    : 'General (None)',
                                valueKey: const ValueKey(
                                  'modal_context_summary',
                                ),
                              ),
                              const SizedBox(height: 6),
                              _TimingStepRow(
                                label: 'Rolling History',
                                value: message.rollingTurnsUsed != null
                                    ? '${message.rollingTurnsUsed} prior ${message.rollingTurnsUsed == 1 ? 'turn' : 'turns'}'
                                    : '0 prior turns',
                                valueKey: const ValueKey(
                                  'modal_rolling_turns_used',
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Tap anywhere to close',
                          style: typography.labelSmall.copyWith(
                            color: colors.onSurfaceMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    _buildCount++;
    if (_buildCount == 1) {
      _log.info(
        '[PERF] ActiveChatView first build() START '
        '(elapsedSinceMount=${_mountStopwatch.elapsedMilliseconds}ms)',
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _log.info(
          '[PERF] ActiveChatView first frame rendered '
          '(elapsedSinceMount=${_mountStopwatch.elapsedMilliseconds}ms)',
        );
      });
    }
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
            final messageById = <String, Message>{
              for (final msg in state.messages) msg.id: msg,
            };

            final flowMessages = <FlowMessageData>[
              for (final msg in state.messages)
                FlowMessageData.text(
                  id: msg.id,
                  // Host messages (isBaseLanguage == true, e.g. English translated
                  // into Korean for a guest on the street) are placed on the LEFT
                  // (FlowMessageRole.assistant, the "other party" position).
                  // Guest messages (isBaseLanguage == false, e.g. Korean translated
                  // into English for the host) are placed on the RIGHT
                  // (FlowMessageRole.user, the "your own messages" position).
                  role: msg.isBaseLanguage
                      ? FlowMessageRole.assistant
                      : FlowMessageRole.user,
                  // Displays the post-processed annotated translation (falling
                  // back to translatedText for legacy records).
                  text: msg.effectiveTranslatedText,
                  timestamp: msg.timestamp,
                ),
              if (state.isLoading)
                if (state.streamingTranslatedText != null &&
                    state.streamingTranslatedText!.isNotEmpty)
                  FlowMessageData.text(
                    id: '__translating_streaming__',
                    role: (state.streamingIsBaseLanguage ?? true)
                        ? FlowMessageRole.assistant
                        : FlowMessageRole.user,
                    text: state.streamingTranslatedText!,
                  )
                else
                  const FlowMessageData(
                    id: '__translating_pending__',
                    role: FlowMessageRole.assistant,
                    status: FlowMessageStatus.pending,
                  ),
            ];

            final effectiveBaseLanguage =
                state.conversation?.baseLanguage ?? settings.baseLanguage;
            final effectiveTargetLanguage =
                state.conversation?.targetLanguage ?? settings.targetLanguage;
            final baseName = AppSettings.languageNameFor(effectiveBaseLanguage);
            final targetName = AppSettings.languageNameFor(
              effectiveTargetLanguage,
            );
            final baseFlag = AppSettings.languageFlagFor(effectiveBaseLanguage);
            final targetFlag = AppSettings.languageFlagFor(
              effectiveTargetLanguage,
            );
            final currentSummary = state.conversation?.effectiveSummary;

            return Scaffold(
              backgroundColor: colors.surface,
              appBar: AppBar(
                leading: IconButton(
                  key: const ValueKey('chat_back_button'),
                  tooltip: 'Back to Home',
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: _handleBack,
                ),
                title: GestureDetector(
                  key: const ValueKey('chat_title_summary_tap_area'),
                  behavior: HitTestBehavior.opaque,
                  onTap: state.conversation == null
                      ? null
                      : () => _showEditSummaryDialog(
                          context,
                          currentSummary: currentSummary,
                        ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (currentSummary != null)
                        Text(
                          currentSummary,
                          key: const ValueKey('chat_appbar_summary_text'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: typography.titleSmallEmphasised.copyWith(
                            color: colors.onSurface,
                          ),
                        ),
                      Text(
                        '$baseName ⇄ $targetName',
                        style: (currentSummary != null
                                ? typography.labelSmall
                                : typography.titleSmallEmphasised)
                            .copyWith(
                              color: currentSummary != null
                                  ? colors.onSurfaceVariant
                                  : colors.onSurface,
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
                ),
                actions: [
                  if (state.conversation != null) ...[
                    IconButton(
                      key: const ValueKey('chat_edit_summary_button'),
                      tooltip: 'Edit summary',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => _showEditSummaryDialog(
                        context,
                        currentSummary: currentSummary,
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('chat_delete_conversation_button'),
                      tooltip: 'Delete conversation',
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: _handleDeleteConversation,
                    ),
                  ],
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
                  Builder(
                    builder: (context) {
                      final activeIds =
                          state.conversation?.activeContextIds ??
                          _conversationBloc.activeContextIds;
                      final activePresets = settings.resolveContextPresets(
                        activeIds,
                      );
                      final activeKeywords =
                          state.conversation?.customKeywords ??
                          _conversationBloc.customKeywords;

                      return Container(
                        key: const ValueKey('chat_context_strip'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerLow,
                          border: Border(
                            bottom: BorderSide(
                              color: colors.outline.withValues(alpha: 0.5),
                            ),
                          ),
                        ),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              for (final preset in activePresets)
                                Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: InputChip(
                                    key: ValueKey(
                                      'chat_active_preset_chip_${preset.id}',
                                    ),
                                    label: Text(preset.displayLabel),
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () =>
                                        _showContextEditorDialog(context),
                                    onDeleted: () {
                                      unawaited(
                                        _conversationBloc.toggleContextPreset(
                                          preset.id,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              for (final kw in activeKeywords)
                                Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: InputChip(
                                    key: ValueKey(
                                      'chat_active_keyword_chip_$kw',
                                    ),
                                    label: Text('🏷️ $kw'),
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () =>
                                        _showContextEditorDialog(context),
                                    onDeleted: () {
                                      unawaited(
                                        _conversationBloc.removeCustomKeyword(
                                          kw,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ActionChip(
                                key: const ValueKey('chat_add_context_chip'),
                                avatar: const Icon(Icons.add_rounded, size: 16),
                                label: Text(
                                  activePresets.isEmpty &&
                                          activeKeywords.isEmpty
                                      ? 'Context'
                                      : 'Edit Context',
                                ),
                                visualDensity: VisualDensity.compact,
                                tooltip:
                                    'Add or edit topic context & custom keywords',
                                onPressed: () =>
                                    _showContextEditorDialog(context),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
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
                    child: Builder(
                      builder: (context) {
                        final osMediaQuery = MediaQuery.of(context);
                        final transcriptTextScaler =
                            ActiveChatView.computeEffectiveTextScaler(
                              osMediaQuery.textScaler,
                              settings.textScaleFactor,
                            );
                        return FlowChatView(
                          empty: flowMessages.isEmpty,
                          greeting: FlowGreeting(
                            icon: state.isListening
                                ? Icons.graphic_eq_rounded
                                : Icons.mic_none_rounded,
                            text: state.isListening
                                ? 'Speak in $baseName or $targetName'
                                : 'Tap mic to translate',
                            textStyle: typography.titleLarge.copyWith(
                              color: colors.onSurface,
                            ),
                          ),
                          threadController: _scrollController,
                          thread: MediaQuery(
                            key: const ValueKey('chat_transcript_media_query'),
                            data: osMediaQuery.copyWith(
                              textScaler: transcriptTextScaler,
                            ),
                            child: FlowThread(
                              key: const ValueKey('active_flow_thread'),
                              messages: flowMessages,
                              controller: _scrollController,
                              thinkingLabel: 'Translating…',
                              markdown: false,
                              messageBuilder: (context, flowMessage) {
                                final domainMessage =
                                    messageById[flowMessage.id];
                                final isStreamingTurn =
                                    flowMessage.id ==
                                    '__translating_streaming__';
                                Widget? leadingBadge;
                                Widget? footerBadge;
                                if (domainMessage != null) {
                                  final isBase = domainMessage.isBaseLanguage;
                                  leadingBadge = _DetectedLanguageFlagBadge(
                                    key: ValueKey(
                                      'chat_message_flag_${domainMessage.id}',
                                    ),
                                    flagEmoji: isBase ? baseFlag : targetFlag,
                                    languageName: isBase
                                        ? baseName
                                        : targetName,
                                  );
                                } else if (isStreamingTurn) {
                                  final isBase =
                                      state.streamingIsBaseLanguage ?? true;
                                  leadingBadge = _DetectedLanguageFlagBadge(
                                    key: const ValueKey(
                                      'chat_message_flag_streaming',
                                    ),
                                    flagEmoji: isBase ? baseFlag : targetFlag,
                                    languageName: isBase
                                        ? baseName
                                        : targetName,
                                    isInProgress: true,
                                  );
                                  footerBadge =
                                      const _InProgressTranslationBadge(
                                        key: ValueKey(
                                          'chat_in_progress_translation_badge',
                                        ),
                                      );
                                }

                                final bubble = FlowMessage(
                                  flowMessage,
                                  markdown: false,
                                  thinkingLabel: 'Translating…',
                                  leading: leadingBadge,
                                  footer: footerBadge,
                                );
                                if (domainMessage == null) {
                                  return bubble;
                                }
                                return GestureDetector(
                                  key: ValueKey(
                                    'chat_message_bubble_${domainMessage.id}',
                                  ),
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () => _showOriginalMessageModal(
                                    context,
                                    message: domainMessage,
                                    baseLanguageName: baseName,
                                    targetLanguageName: targetName,
                                    baseLanguageFlag: baseFlag,
                                    targetLanguageFlag: targetFlag,
                                  ),
                                  child: bubble,
                                );
                              },
                            ),
                          ),
                          composer: PulsingMicIndicator(
                            key: const ValueKey('active_pulsing_mic_indicator'),
                            isListening: state.isListening,
                            isLoading: state.isLoading,
                            amplitude: state.amplitude,
                            modelName: settings.activeModelDisplayName,
                            onToggleListening:
                                _conversationBloc.toggleListening,
                          ),
                        );
                      },
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

/// Circular flag badge displayed beside each chat message indicating the
/// detected (spoken) source language of that utterance.
class _DetectedLanguageFlagBadge extends StatelessWidget {
  const _DetectedLanguageFlagBadge({
    required this.flagEmoji,
    required this.languageName,
    this.isInProgress = false,
    super.key,
  });

  final String flagEmoji;
  final String languageName;
  final bool isInProgress;

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;
    final typography = context.flowTypography;

    return SelectionContainer.disabled(
      child: Tooltip(
        message: 'Detected language: $languageName',
        child: Semantics(
          label: 'Detected language: $languageName',
          child: Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              shape: BoxShape.circle,
              border: Border.all(
                color: isInProgress
                    ? AppTokens.listeningAccent
                    : colors.outline,
                width: isInProgress ? 1.5 : 1.0,
              ),
            ),
            child: Text(
              flagEmoji,
              textScaler: TextScaler.noScaling,
              style: typography.bodyMedium.copyWith(height: 1),
            ),
          ),
        ),
      ),
    );
  }
}

/// Animated footer pill displayed beneath an in-progress streaming message
/// while the translation engine is still working on the utterance.
class _InProgressTranslationBadge extends StatelessWidget {
  const _InProgressTranslationBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return SelectionContainer.disabled(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppTokens.listeningAccent.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: AppTokens.listeningAccent.withValues(alpha: 0.35),
          ),
        ),
        child: const FlowThinkingIndicator(
          key: ValueKey('chat_in_progress_thinking_indicator'),
          label: 'Still translating…',
          size: 13,
          color: AppTokens.listeningAccent,
        ),
      ),
    );
  }
}

class _TimingStepRow extends StatelessWidget {
  const _TimingStepRow({
    required this.label,
    required this.value,
    this.modelName,
    this.modelKey,
    this.valueKey,
    this.isEmphasized = false,
  });

  final String label;
  final String value;
  final String? modelName;
  final Key? modelKey;
  final Key? valueKey;
  final bool isEmphasized;

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;
    final typography = context.flowTypography;
    final textStyle = (isEmphasized
            ? typography.labelMedium
            : typography.bodySmall)
        .copyWith(
          color: isEmphasized ? colors.onSurface : colors.onSurfaceVariant,
          fontWeight: isEmphasized ? FontWeight.w600 : FontWeight.w400,
        );
    final trimmedModel = modelName?.trim();
    final hasModel = trimmedModel != null && trimmedModel.isNotEmpty;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: textStyle,
                overflow: TextOverflow.ellipsis,
              ),
              if (hasModel) ...[
                const SizedBox(height: 1),
                Text(
                  trimmedModel,
                  key: modelKey,
                  overflow: TextOverflow.ellipsis,
                  style: typography.labelSmall.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            key: valueKey,
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
            style: textStyle.copyWith(
              color: colors.onSurface,
              fontWeight: isEmphasized ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
