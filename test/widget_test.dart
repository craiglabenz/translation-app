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
      expect(find.text('Recent Conversations'), findsOneWidget);
      expect(
        find.text('English (USD) ⇄ Spanish (EUR)'),
        findsOneWidget,
      );
    });
  });
}
