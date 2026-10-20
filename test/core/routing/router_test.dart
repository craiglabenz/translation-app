import 'package:flutter_test/flutter_test.dart';
import 'package:translation_app/core/auth/auth.dart';
import 'package:translation_app/core/routing/routing.dart';

void main() {
  group('AppRouter', () {
    test('initial route is LoginRoute when AuthPolicy.serverpod', () async {
      final cubit = AuthCubit.seeded();
      final redirector = KaiselRedirector.fromPolicy(
        const AuthPolicy.serverpod(),
      );
      final router = AppRouter(
        const AuthPolicy.serverpod(),
        cubit,
        redirector,
      );

      expect(router.config.router.stack, const [LoginRoute()]);
      router.dispose();
      await cubit.close();
    });

    test('initial route is HomeRoute when AuthPolicy.none', () async {
      final cubit = AuthCubit.seeded(user: const User(id: 'local'));
      final redirector = KaiselRedirector.fromPolicy(const AuthPolicy.none());
      final router = AppRouter(const AuthPolicy.none(), cubit, redirector);

      expect(router.config.router.stack, const [HomeRoute()]);
      router.dispose();
      await cubit.close();
    });
  });
}
