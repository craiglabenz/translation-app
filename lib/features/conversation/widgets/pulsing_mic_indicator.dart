import 'dart:math' as math;

import 'package:flow_ui/flow_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:translation_app/core/logging/app_logger.dart';
import 'package:translation_app/core/theme/tokens.dart';

/// Bottom voice control bar for [FlowChatView.composer].
///
/// When [isListening] is `true`, renders an RMS-reactive pulsing microphone
/// indicator with a pause action. When [isListening] is `false` (for example,
/// when viewing a historical conversation in read-only mode), renders a
/// prominent "Resume Listening" microphone button to continue the thread.
class PulsingMicIndicator extends StatelessWidget {
  const PulsingMicIndicator({
    required this.isListening,
    required this.isLoading,
    required this.amplitude,
    required this.onToggleListening,
    super.key,
  });

  static final _log = AppLogger.of('PulsingMicIndicator');

  final bool isListening;
  final bool isLoading;
  final double amplitude;
  final VoidCallback onToggleListening;

  void _handleTap(String source) {
    _log.info(
      'PulsingMicIndicator tapped via $source '
      '(current isListening=$isListening, isLoading=$isLoading)',
    );
    onToggleListening();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;
    final typography = context.flowTypography;

    // Normalize RMS amplitude (typically 0.0 .. 0.35 in speech) to 0.0 .. 1.0
    final normalizedLevel = math.min(1.0, math.max(0.0, amplitude * 4.0));
    final haloScale = isListening ? (1.0 + normalizedLevel * 0.45) : 1.0;

    final accentColor = isListening
        ? AppTokens.listeningAccent
        : colors.primary;

    final statusTitle = isLoading
        ? 'Translating speech…'
        : isListening
        ? 'Listening continuously'
        : 'Microphone paused';

    final statusSubtitle = isLoading
        ? 'Gemma 4 is processing audio & currency context'
        : isListening
        ? 'Pause for 3 seconds to translate • Tap mic to stop'
        : 'Tap the microphone to resume live translation in this thread';

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
              onTap: () => _handleTap('mic_icon_button'),
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
                        isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
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
                        key: const ValueKey('mic_translating_thinking_indicator'),
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
        ],
      ),
    );
  }
}
