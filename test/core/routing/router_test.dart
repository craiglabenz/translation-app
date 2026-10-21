import 'package:flutter_test/flutter_test.dart';
import 'package:translation_app/core/auth/auth.dart';
import 'package:translation_app/core/routing/routing.dart';

void main() {
  group('AppRoute hierarchy', () {
    test('supports value equality across all route types', () {
      expect(const LoginRoute(), equals(const LoginRoute()));
      expect(const HomeRoute(), equals(const HomeRoute()));
      expect(const HistoryRoute(), equals(const HistoryRoute()));
      expect(const SettingsRoute(), equals(const SettingsRoute()));

      expect(
        const ChatRoute(conversationId: 'c1', autoStartListening: false),
        equals(
          const ChatRoute(conversationId: 'c1', autoStartListening: false),
        ),
      );
      expect(
        const ChatRoute(conversationId: 'c1', autoStartListening: false),
        isNot(
          equals(
            const ChatRoute(conversationId: 'c1', autoStartListening: true),
          ),
        ),
      );
      expect(
        const ChatRoute(conversationId: 'c1'),
        isNot(equals(const ChatRoute(conversationId: 'c2'))),
      );
    });
  });

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

    test('navigates between HomeRoute, ChatRoute, HistoryRoute, and SettingsRoute', () async {
      final cubit = AuthCubit.seeded(user: const User(id: 'local'));
      final redirector = KaiselRedirector.fromPolicy(const AuthPolicy.none());
      final router = AppRouter(const AuthPolicy.none(), cubit, redirector);

      await router.config.router.push(
        const ChatRoute(conversationId: 'conv_42', autoStartListening: false),
      );
      expect(
        router.config.router.stack.last,
        const ChatRoute(conversationId: 'conv_42', autoStartListening: false),
      );

      await router.config.router.push(const HistoryRoute());
      expect(router.config.router.stack.last, const HistoryRoute());

      await router.config.router.push(const SettingsRoute());
      expect(router.config.router.stack.last, const SettingsRoute());

      await router.config.router.pop();
      expect(router.config.router.stack.last, const HistoryRoute());

      router.dispose();
      await cubit.close();
    });

    test('reevaluates stack when AuthCubit emits login/logout state under AuthPolicy.serverpod', () async {
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

      // Attempt to push HomeRoute while unauthenticated -> redirected to LoginRoute
      await router.config.router.push(const HomeRoute());
      expect(router.config.router.stack.last, const LoginRoute());

      router.dispose();
      await cubit.close();
    });
  });
}
