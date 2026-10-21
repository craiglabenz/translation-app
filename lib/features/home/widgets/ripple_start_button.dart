import 'package:flow_ui/flow_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:translation_app/core/logging/app_logger.dart';
import 'package:translation_app/core/theme/tokens.dart';

/// Prominent circular CTA button surrounded by concentric ripple rings
/// to launch a live translation session from the Home screen.
class RippleStartButton extends StatefulWidget {
  const RippleStartButton({
    required this.onTap,
    this.label = 'Tap to Translate',
    this.subtitle,
    this.icon = Icons.mic_rounded,
    this.enabled = true,
    super.key,
  });

  final VoidCallback onTap;
  final String label;
  final String? subtitle;
  final IconData icon;
  final bool enabled;

  @override
  State<RippleStartButton> createState() => _RippleStartButtonState();
}

class _RippleStartButtonState extends State<RippleStartButton>
    with SingleTickerProviderStateMixin {
  static final _log = AppLogger.of('RippleStartButton');

  late final AnimationController _controller;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _pulseAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    // Run an entrance ripple once on mount so the button feels alive while
    // allowing widget tests using pumpAndSettle() to settle deterministically.
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap() {
    _log.info('RippleStartButton tapped (enabled=${widget.enabled}, label="${widget.label}")');
    if (!widget.enabled) return;
    _controller
      ..reset()
      ..forward();
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;
    final typography = context.flowTypography;
    final accentColor = widget.enabled
        ? colors.primary
        : colors.onSurfaceDisabled;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          enabled: widget.enabled,
          label: widget.label,
          child: GestureDetector(
            onTap: widget.enabled ? _handleTap : null,
            child: AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                final t = _pulseAnimation.value;
                final outerDiameter =
                    AppTokens.startButtonRippleOuterDiameter *
                    (0.88 + 0.12 * t);
                final middleDiameter =
                    (AppTokens.startButtonDiameter + 46) * (0.92 + 0.08 * t);

                return SizedBox(
                  width: AppTokens.startButtonRippleOuterDiameter,
                  height: AppTokens.startButtonRippleOuterDiameter,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Outer ripple ring
                      Container(
                        width: outerDiameter,
                        height: outerDiameter,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: accentColor.withValues(alpha: 0.08),
                          border: Border.all(
                            color: accentColor.withValues(alpha: 0.16),
                            width: 1.5,
                          ),
                        ),
                      ),
                      // Middle ripple ring
                      Container(
                        width: middleDiameter,
                        height: middleDiameter,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: accentColor.withValues(alpha: 0.15),
                          border: Border.all(
                            color: accentColor.withValues(alpha: 0.28),
                            width: 1.5,
                          ),
                        ),
                      ),
                      child!,
                    ],
                  ),
                );
              },
              child: Container(
                width: AppTokens.startButtonDiameter,
                height: AppTokens.startButtonDiameter,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accentColor,
                  boxShadow: [
                    BoxShadow(
                      color: accentColor.withValues(alpha: 0.35),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Icon(
                  widget.icon,
                  size: 48,
                  color: colors.onPrimary,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          widget.label,
          style: typography.titleMediumEmphasised.copyWith(
            color: colors.onSurface,
          ),
        ),
        if (widget.subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            widget.subtitle!,
            textAlign: TextAlign.center,
            style: typography.bodySmall.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}
