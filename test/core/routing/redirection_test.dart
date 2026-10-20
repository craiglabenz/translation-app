import 'package:flutter_test/flutter_test.dart';
import 'package:translation_app/core/auth/auth.dart';
import 'package:translation_app/core/routing/routing.dart';

void main() {
  group('KaiselRedirector', () {
    test('with AuthPolicy.serverpod enforces auth redirects', () async {
      final redirector = KaiselRedirector.fromPolicy(
        const AuthPolicy.serverpod(),
      );

      // Logged-out user navigating to protected route is redirected to LoginRoute
      final redirectedToLogin = await redirector.redirect(
        const [LoginRoute()],
        const [HomeRoute()],
        const AuthState(),
      );
      expect(redirectedToLogin, const [LoginRoute()]);

      // Logged-in user navigating to LoginRoute is redirected to HomeRoute
      final redirectedToHome = await redirector.redirect(
        const [HomeRoute()],
        const [LoginRoute()],
        const AuthState(user: User(id: '123')),
      );
      expect(redirectedToHome, const [HomeRoute()]);
    });

    test(
      'with AuthPolicy.none allows all navigation without redirecting',
      () async {
        final redirector = KaiselRedirector.fromPolicy(const AuthPolicy.none());

        // No redirection to login even if user has null in AuthState
        final result1 = await redirector.redirect(
          const [HomeRoute()],
          const [HomeRoute()],
          const AuthState(),
        );
        expect(result1, const [HomeRoute()]);

        // No redirection to home if navigating to login
        final result2 = await redirector.redirect(
          const [HomeRoute()],
          const [LoginRoute()],
          const AuthState(user: User(id: 'local')),
        );
        expect(result2, const [LoginRoute()]);
      },
    );
  });
}
