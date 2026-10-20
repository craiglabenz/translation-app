import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';
import 'package:translation_app/core/auth/auth.dart';

import 'dependency_injection.config.dart';

final getIt = GetIt.instance;

@InjectableInit(
  initializerName: 'init', // default
  preferRelativeImports: true, // default
  asExtension: true, // default
)
void configureDependencies({
  AuthPolicy authPolicy = const AuthPolicy.serverpod(),
}) {
  AuthModule.policy = authPolicy;
  getIt.init();
}
