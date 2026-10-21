import 'package:material_ui/material_ui.dart';

/// Application design tokens complementing `flow_ui`'s [FlowTheme] tokens.
abstract final class AppTokens {
  /// Accent seed color for the translation workspace.
  static const Color primarySeed = Color(0xFF2563EB);

  /// Active microphone / live listening accent.
  static const Color listeningAccent = Color(0xFF10B981);

  /// Stale exchange rate / offline warning amber.
  static const Color warningAmber = Color(0xFFF59E0B);

  /// Error crimson.
  static const Color errorRed = Color(0xFFEF4444);

  /// Standard page horizontal padding.
  static const double pageHorizontalPadding = 20.0;

  /// Maximum content width for centered layouts.
  static const double maxContentWidth = 680.0;

  /// Core diameter of the home screen's [RippleStartButton].
  static const double startButtonDiameter = 104.0;

  /// Outer ripple diameter of the home screen's [RippleStartButton].
  static const double startButtonRippleOuterDiameter = 168.0;
}
