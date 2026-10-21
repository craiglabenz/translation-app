// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// **************************************************************************
// InjectableConfigGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes

import 'package:get_it/get_it.dart' as _i174;
import 'package:injectable/injectable.dart' as _i526;

import 'auth/auth.dart' as _i930;
import 'auth/auth_cubit.dart' as _i161;
import 'auth/auth_module.dart' as _i621;
import 'auth/auth_policy.dart' as _i427;
import 'routing/redirection.dart' as _i743;
import 'routing/router.dart' as _i823;
import 'routing/routing.dart' as _i883;
import 'serverpod_service.dart' as _i93;

extension GetItInjectableX on _i174.GetIt {
  // initializes the registration of main-scope dependencies inside of GetIt
  _i174.GetIt init({
    String? environment,
    _i526.EnvironmentFilter? environmentFilter,
  }) {
    final gh = _i526.GetItHelper(this, environment, environmentFilter);
    final authModule = _$AuthModule();
    gh.singleton<_i93.ServerpodService>(() => _i93.ServerpodService());
    gh.lazySingleton<_i427.AuthPolicy>(() => authModule.authPolicy);
    gh.singleton<_i161.AuthCubit>(
      () =>
          _i161.AuthCubit(gh<_i427.AuthPolicy>(), gh<_i93.ServerpodService>()),
    );
    gh.factory<_i743.KaiselRedirector>(
      () => _i743.KaiselRedirector.fromPolicy(gh<_i930.AuthPolicy>()),
    );
    gh.lazySingleton<_i823.AppRouter>(
      () => _i823.AppRouter(
        gh<_i930.AuthPolicy>(),
        gh<_i930.AuthCubit>(),
        gh<_i883.KaiselRedirector>(),
      ),
    );
    return this;
  }
}

class _$AuthModule extends _i621.AuthModule {}
