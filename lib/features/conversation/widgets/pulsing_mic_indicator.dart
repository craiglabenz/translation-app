import 'dart:async';
import 'dart:math' as math;

import 'package:flow_ui/flow_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:translation_app/core/data/models/app_settings.dart';
import 'package:translation_app/core/logging/app_logger.dart';
import 'package:translation_app/core/theme/tokens.dart';

/// Bottom voice control bar for [FlowChatView.composer].
///
/// Supports both Continuous Listening and Push-to-Talk (PTT) via a unified
/// gesture model on [mic_toggle_button]:
/// - From Standby (`isListening == false`):
///   - Pressing down immediately starts capture and promotes the 1.5–2.0s
///     rolling speech-onset pre-roll buffer.
///   - Holding for `>= 300ms` and releasing finishes the turn, translates it,
///     and returns to Standby (`isListening == false`).
///   - A quick tap (`< 300ms`) latches Continuous Listening ON until tapped
///     again to pause.
/// - Includes a dedicated Hard-Kill / Discard (`✕`) button (`mic_discard_button`)
///   that wipes buffered audio, cancels in-flight translation, clears the
///   pre-roll buffer, and pauses the microphone.
class PulsingMicIndicator extends StatefulWidget {
  const PulsingMicIndicator({
    required this.isListening,
    required this.isLoading,
    required this.amplitude,
    required this.onToggleListening,
    this.onStartPushToTalk,
    this.onFinishPushToTalk,
    this.onDiscardUtterance,
    this.onToggleMicControlMode,
    this.micControlMode = MicControlMode.continuous,
    this.hasBufferedSpeech = false,
    this.modelName = 'Gemma 4',
    super.key,
  });

  /// Minimum press duration for a gesture from Standby to act as hold-to-talk
  /// (releasing automatically finishes and translates the turn) rather than a
  /// quick tap that latches listening on.
  static const Duration holdToTalkThreshold = Duration(milliseconds: 300);

  final bool isListening;
  final bool isLoading;
  final double amplitude;
  final VoidCallback onToggleListening;
  final VoidCallback? onStartPushToTalk;
  final VoidCallback? onFinishPushToTalk;
  final VoidCallback? onDiscardUtterance;
  final VoidCallback? onToggleMicControlMode;
  final MicControlMode micControlMode;
  final bool hasBufferedSpeech;
  final String modelName;

  @override
  State<PulsingMicIndicator> createState() => _PulsingMicIndicatorState();
}

class _PulsingMicIndicatorState extends State<PulsingMicIndicator> {
  static final _log = AppLogger.of('PulsingMicIndicator');

  DateTime? _pressDownTime;
  bool _wasListeningOnPressDown = false;
  bool _isHoldingPtt = false;
  Timer? _holdIndicatorTimer;

  @override
  void dispose() {
    _holdIndicatorTimer?.cancel();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    _pressDownTime = DateTime.now();
    _wasListeningOnPressDown = widget.isListening;
    _holdIndicatorTimer?.cancel();

    if (!_wasListeningOnPressDown) {
      // Immediately start capturing (promoting the 1.5–2.0s pre-roll buffer)
      // on finger down so zero syllables are lost.
      _log.info(
        'PulsingMicIndicator press-down from Standby -> starting capture with pre-roll.',
      );
      if (widget.onStartPushToTalk != null) {
        widget.onStartPushToTalk!();
      } else {
        widget.onToggleListening();
      }
      _holdIndicatorTimer = Timer(PulsingMicIndicator.holdToTalkThreshold, () {
        if (mounted && _pressDownTime != null) {
          setState(() {
            _isHoldingPtt = true;
          });
        }
      });
    }
  }

  void _handleTapUp(TapUpDetails details) {
    _finishPointerGesture();
  }

  void _handleTapCancel() {
    _finishPointerGesture();
  }

  void _finishPointerGesture() {
    _holdIndicatorTimer?.cancel();
    final downTime = _pressDownTime;
    _pressDownTime = null;
    final wasHoldingPtt = _isHoldingPtt;
    if (_isHoldingPtt && mounted) {
      setState(() {
        _isHoldingPtt = false;
      });
    }

    if (downTime == null) {
      return;
    }

    if (_wasListeningOnPressDown) {
      _log.info(
        'PulsingMicIndicator tapped while listening -> pausing to standby.',
      );
      widget.onToggleListening();
      return;
    }

    final heldDuration = DateTime.now().difference(downTime);
    if (wasHoldingPtt ||
        heldDuration >= PulsingMicIndicator.holdToTalkThreshold) {
      _log.info(
        'PulsingMicIndicator PTT hold released after ${heldDuration.inMilliseconds}ms -> finishing turn & returning to standby.',
      );
      if (widget.onFinishPushToTalk != null) {
        widget.onFinishPushToTalk!();
      } else {
        widget.onToggleListening();
      }
    } else {
      _log.info(
        'PulsingMicIndicator quick-tap (${heldDuration.inMilliseconds}ms < 300ms) -> staying latched in listening mode.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;
    final typography = context.flowTypography;

    final isListening = widget.isListening;
    final isLoading = widget.isLoading;
    final modelName = widget.modelName;

    // Normalize RMS amplitude (typically 0.0 .. 0.35 in speech) to 0.0 .. 1.0
    final normalizedLevel = math.min(
      1.0,
      math.max(0.0, widget.amplitude * 4.0),
    );
    final haloScale = isListening ? (1.0 + normalizedLevel * 0.45) : 1.0;

    final accentColor = isListening
        ? AppTokens.listeningAccent
        : colors.primary;

    final statusTitle = isLoading
        ? 'Translating speech…'
        : _isHoldingPtt
        ? 'Push-to-Talk active'
        : isListening
        ? 'Listening continuously'
        : widget.micControlMode == MicControlMode.pushToTalk
        ? 'Push-to-Talk standby (2s pre-roll)'
        : 'Microphone paused';

    final statusSubtitle = isLoading
        ? '$modelName is processing audio & currency context'
        : _isHoldingPtt
        ? 'Release mic to translate • Tap ✕ to discard'
        : isListening
        ? 'Pause for 3 seconds to translate • Tap mic to stop'
        : widget.micControlMode == MicControlMode.pushToTalk
        ? 'Hold mic to speak or quick-tap to latch'
        : 'Tap the microphone to resume live translation in this thread';

    final showDiscardButton =
        widget.onDiscardUtterance != null &&
        (isListening || isLoading || widget.hasBufferedSpeech);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isListening
              ? AppTokens.listeningAccent.withValues(alpha: 0.45)
              : colors.outline,
        ),
      ),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: isListening ? 'Pause microphone' : 'Resume listening',
            child: GestureDetector(
              key: const ValueKey('mic_toggle_button'),
              behavior: HitTestBehavior.opaque,
              onTapDown: _handleTapDown,
              onTapUp: _handleTapUp,
              onTapCancel: _handleTapCancel,
              child: SizedBox(
                width: 64,
                height: 64,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      width: 48 * haloScale,
                      height: 48 * haloScale,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: accentColor.withValues(
                          alpha: isListening ? 0.22 : 0.10,
                        ),
                      ),
                    ),
                    if (isLoading)
                      SizedBox(
                        key: const ValueKey('mic_translating_spinner'),
                        width: 56,
                        height: 56,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: accentColor,
                        ),
                      ),
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: accentColor,
                      ),
                      child: Icon(
                        isListening
                            ? Icons.mic_rounded
                            : Icons.mic_none_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    if (isLoading) ...[
                      FlowThinkingIndicator(
                        key: const ValueKey(
                          'mic_translating_thinking_indicator',
                        ),
                        size: 14,
                        color: accentColor,
                      ),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: Text(
                        statusTitle,
                        style: typography.labelLarge.copyWith(
                          color: colors.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (widget.onToggleMicControlMode != null) ...[
                      const SizedBox(width: 6),
                      GestureDetector(
                        key: const ValueKey('mic_mode_toggle_pill'),
                        behavior: HitTestBehavior.opaque,
                        onTap: widget.onToggleMicControlMode,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color:
                                widget.micControlMode ==
                                    MicControlMode.pushToTalk
                                ? colors.primary.withValues(alpha: 0.14)
                                : colors.surface,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color:
                                  widget.micControlMode ==
                                      MicControlMode.pushToTalk
                                  ? colors.primary
                                  : colors.outline,
                            ),
                          ),
                          child: Text(
                            widget.micControlMode == MicControlMode.pushToTalk
                                ? 'PTT'
                                : 'Auto',
                            style: typography.labelSmall.copyWith(
                              color:
                                  widget.micControlMode ==
                                      MicControlMode.pushToTalk
                                  ? colors.primary
                                  : colors.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  statusSubtitle,
                  style: typography.bodySmall.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                if (isLoading) ...[
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      key: const ValueKey('mic_translating_progress_bar'),
                      minHeight: 3,
                      color: accentColor,
                      backgroundColor: accentColor.withValues(alpha: 0.16),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (showDiscardButton) ...[
            const SizedBox(width: 8),
            Tooltip(
              message: 'Discard audio & pause microphone',
              child: Semantics(
                button: true,
                label: 'Discard audio and pause microphone',
                child: GestureDetector(
                  key: const ValueKey('mic_discard_button'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    _log.info(
                      'PulsingMicIndicator discard (✕) button tapped -> hard-killing buffered/in-flight audio and pausing.',
                    );
                    widget.onDiscardUtterance?.call();
                  },
                  child: Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTokens.errorRed.withValues(alpha: 0.12),
                      border: Border.all(
                        color: AppTokens.errorRed.withValues(alpha: 0.45),
                      ),
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      color: AppTokens.errorRed,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
