import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:translation_app/core/auth/auth.dart';

import 'routes.dart';

@injectable
class KaiselRedirector {
  /// Resolves the redirect rules based on [AuthPolicy].
  @factoryMethod
  factory KaiselRedirector.fromPolicy(AuthPolicy authPolicy) {
    if (!authPolicy.isEnabled) {
      return const KaiselRedirector._(<Redirector>[]);
    }
    return const KaiselRedirector._(
      <Redirector>[
        UnknownUsersToLogin(),
        LoggedInUsersToHome(),
      ],
    );
  }

  /// Default constructor with standard auth redirects.
  const KaiselRedirector()
    : _redirects = const <Redirector>[
        UnknownUsersToLogin(),
        LoggedInUsersToHome(),
      ];

  const KaiselRedirector._(this._redirects);

  final List<Redirector> _redirects;

  FutureOr<List<AppRoute>> redirect(
    List<AppRoute> current,
    List<AppRoute> proposed,
    AuthState authState,
  ) async {
    for (final redirect in _redirects) {
      if (redirect.predicate(current, proposed, authState)) {
        final newProposed = await redirect.getNewRouteState(
          current,
          proposed,
          authState,
        );

        if (listEquals(proposed, newProposed)) {
          continue;
        }

        return newProposed;
      }
    }
    return proposed;
  }
}

/// Individual utility within a [KaiselRedirector] to enforce a single rule.
abstract class Redirector {
  /// Const constructor.
  const Redirector();

  /// Determines whether this redirection should take place.
  bool predicate(
    List<AppRoute> current,
    List<AppRoute> proposed,
    AuthState authState,
  );

  /// Returns the desired route stack to send the user based on current app state.
  FutureOr<List<AppRoute>> getNewRouteState(
    List<AppRoute> current,
    List<AppRoute> proposed,
    AuthState authState,
  );

  @override
  String toString() => '$runtimeType()';
}

class UnknownUsersToLogin extends Redirector {
  const UnknownUsersToLogin();

  @override
  bool predicate(
    List<AppRoute> current,
    List<AppRoute> proposed,
    AuthState authState,
  ) {
    final isLoggedOut = !authState.isAuthenticated;
    final isHeadingToProtected = proposed.any((r) => r is! LoginRoute);
    return isLoggedOut && isHeadingToProtected;
  }

  @override
  FutureOr<List<AppRoute>> getNewRouteState(
    List<AppRoute> current,
    List<AppRoute> proposed,
    AuthState authState,
  ) => const [LoginRoute()];
}

class LoggedInUsersToHome extends Redirector {
  const LoggedInUsersToHome();

  @override
  bool predicate(
    List<AppRoute> current,
    List<AppRoute> proposed,
    AuthState authState,
  ) {
    final isLoggedIn = authState.isAuthenticated;
    final isHeadingToAuth = proposed.any((r) => r is LoginRoute);
    return isLoggedIn && isHeadingToAuth;
  }

  @override
  FutureOr<List<AppRoute>> getNewRouteState(
    List<AppRoute> current,
    List<AppRoute> proposed,
    AuthState authState,
  ) => const [HomeRoute()];
}
