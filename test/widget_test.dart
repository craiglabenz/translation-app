import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:translation_app/core/core.dart';
import 'package:translation_app/main.dart';

void main() {
  group('MyApp', () {
    tearDown(() async => GetIt.I.reset());

    testWidgets('pumps app and loads HomeScreen when AuthPolicy.none', (
      tester,
    ) async {
      configureDependencies(authPolicy: const AuthPolicy.none());

      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();

      expect(find.text('Tap to Translate'), findsOneWidget);
      expect(find.byKey(const ValueKey('home_drawer_button')), findsOneWidget);
      expect(
        find.text('English (USD) ⇄ Spanish (EUR)'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('home_drawer_button')));
      await tester.pumpAndSettle();
      expect(find.text('Past Conversations'), findsOneWidget);
    });
  });
}
