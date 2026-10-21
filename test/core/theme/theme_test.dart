import 'package:flow_ui/flow_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:translation_app/core/theme/app_theme.dart';
import 'package:translation_app/core/theme/tokens.dart';

void main() {
  group('AppTokens', () {
    test('defines expected color and layout constants', () {
      expect(AppTokens.primarySeed, const Color(0xFF2563EB));
      expect(AppTokens.listeningAccent, const Color(0xFF10B981));
      expect(AppTokens.warningAmber, const Color(0xFFF59E0B));
      expect(AppTokens.errorRed, const Color(0xFFEF4444));
      expect(AppTokens.pageHorizontalPadding, 20.0);
      expect(AppTokens.maxContentWidth, 680.0);
      expect(AppTokens.startButtonDiameter, 104.0);
      expect(
        AppTokens.startButtonRippleOuterDiameter,
        greaterThan(AppTokens.startButtonDiameter),
      );
    });
  });

  group('AppTheme', () {
    test('light() configures Material 3 light theme with FlowTheme extension', () {
      final light = AppTheme.light();
      expect(light.useMaterial3, isTrue);
      expect(light.brightness, Brightness.light);
      expect(light.colorScheme.brightness, Brightness.light);
      expect(light.appBarTheme.elevation, 0);
      expect(light.appBarTheme.centerTitle, isFalse);

      final flowExt = light.extension<FlowTheme>();
      expect(flowExt, isNotNull);
      expect(light.scaffoldBackgroundColor, flowExt!.colors.surface);
    });

    test('dark() configures Material 3 dark theme with FlowTheme extension', () {
      final dark = AppTheme.dark();
      expect(dark.useMaterial3, isTrue);
      expect(dark.brightness, Brightness.dark);
      expect(dark.colorScheme.brightness, Brightness.dark);
      expect(dark.appBarTheme.elevation, 0);
      expect(dark.appBarTheme.centerTitle, isFalse);

      final flowExt = dark.extension<FlowTheme>();
      expect(flowExt, isNotNull);
      expect(dark.scaffoldBackgroundColor, flowExt!.colors.surface);
    });
  });
}
