import 'package:injectable/injectable.dart';
import 'package:kaisel/kaisel.dart';
import 'package:translation_app/core/auth/auth.dart';
import 'package:translation_app/core/logging/app_logger.dart';
import 'package:translation_app/features/conversation/widgets/active_chat_view.dart';
import 'package:translation_app/features/history/history_screen.dart';
import 'package:translation_app/features/settings/settings_screen.dart';

import '../../screens/screens.dart';
import 'routing.dart';

@lazySingleton
class AppRouter {
  AppRouter(
    this._authPolicy,
    this._authCubit,
    this._redirector,
  ) {
    _unsubscribe = _authCubit.state.subscribe((AuthState state) {
      config.router.reevaluate();
    });
  }

  static final _log = AppLogger.of('AppRouter');

  final AuthPolicy _authPolicy;
  final AuthCubit _authCubit;
  final KaiselRedirector _redirector;

  late final void Function() _unsubscribe;

  void dispose() {
    _unsubscribe();
  }

  late final config = KaiselRouterConfig<AppRoute>(
    initial: _authPolicy.isEnabled ? const LoginRoute() : const HomeRoute(),
    builder: (context, route) {
      _log.info('AppRouter building route: $route');
      return switch (route) {
        LoginRoute() => const LoginScreen(),
        HomeRoute() => const HomeScreen(),
        ChatRoute(
          :final conversationId,
          :final autoStartListening,
          :final initialContextIds,
          :final initialCustomKeywords,
        ) =>
          ActiveChatView(
            conversationId: conversationId,
            autoStartListening: autoStartListening,
            initialContextIds: initialContextIds,
            initialCustomKeywords: initialCustomKeywords,
          ),
        HistoryRoute() => const HistoryScreen(),
        SettingsRoute() => const SettingsScreen(),
      };
    },
    guards: [
      (current, proposed) {
        final redirected = _redirector.redirect(
          current,
          proposed,
          _authCubit.stateValue,
        );
        if (redirected != proposed) {
          _log.info('AppRouter guard redirected $proposed -> $redirected');
        }
        return redirected;
      },
    ],
  );
}
