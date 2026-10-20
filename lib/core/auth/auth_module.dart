import 'package:injectable/injectable.dart';

import 'auth_policy.dart';

@module
abstract class AuthModule {
  static AuthPolicy _policy = const AuthPolicy.serverpod();

  /// Sets the global [AuthPolicy] used when dependency injection is initialized.
  static set policy(AuthPolicy value) => _policy = value;

  @lazySingleton
  AuthPolicy get authPolicy => _policy;
}
