import 'package:flow_ui/flow_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:translation_app/core/theme/tokens.dart';

/// Builds the light and dark [ThemeData] instances with [FlowTheme] extensions.
abstract final class AppTheme {
  /// Light theme configuration with [FlowTheme.light].
  static ThemeData light() {
    final flowTheme = FlowTheme.light();
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppTokens.primarySeed,
      brightness: Brightness.light,
      surface: flowTheme.colors.surface,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: flowTheme.colors.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: flowTheme.colors.surface,
        foregroundColor: flowTheme.colors.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      extensions: <ThemeExtension<dynamic>>[flowTheme],
    );
  }

  /// Dark theme configuration with [FlowTheme.dark].
  static ThemeData dark() {
    final flowTheme = FlowTheme.dark();
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppTokens.primarySeed,
      brightness: Brightness.dark,
      surface: flowTheme.colors.surface,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: flowTheme.colors.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: flowTheme.colors.surface,
        foregroundColor: flowTheme.colors.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      extensions: <ThemeExtension<dynamic>>[flowTheme],
    );
  }
}
