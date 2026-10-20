import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:translation_app/core/core.dart';
import 'package:translation_app/core/routing/routing.dart';

void main() {
  group('Dependency Injection', () {
    tearDown(() async => GetIt.I.reset());

    test(
      'configureDependencies with AuthPolicy.none configures no-auth environment',
      () {
        configureDependencies(authPolicy: const AuthPolicy.none());

        final policy = GetIt.I<AuthPolicy>();
        expect(policy.isEnabled, isFalse);

        final authCubit = GetIt.I<AuthCubit>();
        expect(authCubit.stateValue.isAuthenticated, isTrue);
        expect(authCubit.stateValue.user?.id, 'local');

        final router = GetIt.I<AppRouter>();
        expect(router.config.router.stack, const [HomeRoute()]);
      },
    );

    test(
      'configureDependencies defaults to AuthPolicy.serverpod',
      () {
        configureDependencies();

        final policy = GetIt.I<AuthPolicy>();
        expect(policy.isEnabled, isTrue);

        final router = GetIt.I<AppRouter>();
        expect(router.config.router.stack, const [LoginRoute()]);
      },
    );
  });
}
