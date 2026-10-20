import 'user.dart';

/// Defines how authentication is handled in the application.
sealed class AuthPolicy {
  const AuthPolicy();

  /// Serverpod-backed authentication. Requires users to log in.
  const factory AuthPolicy.serverpod() = ServerpodAuthPolicy;

  /// Authentication is disabled. The app immediately signs in as [defaultUser]
  /// and skips all login flows.
  const factory AuthPolicy.none({User defaultUser}) = NoAuthPolicy;

  /// Whether authentication is enabled.
  bool get isEnabled;

  /// The default user when auth is disabled, or null if auth is enabled.
  User? get defaultUser => switch (this) {
    NoAuthPolicy(:final defaultUser) => defaultUser,
    _ => null,
  };
}

/// Policy for applications backed by Serverpod authentication.
class ServerpodAuthPolicy extends AuthPolicy {
  const ServerpodAuthPolicy();

  @override
  bool get isEnabled => true;
}

/// Policy for applications with authentication disabled.
class NoAuthPolicy extends AuthPolicy {
  const NoAuthPolicy({this.defaultUser = const User(id: 'local')});

  /// The user instance automatically provided when auth is disabled.
  @override
  final User defaultUser;

  @override
  bool get isEnabled => false;
}
