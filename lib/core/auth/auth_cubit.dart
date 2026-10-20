import 'dart:async';

import 'package:bloc_signals/bloc_signals.dart';
import 'package:flutter/foundation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:injectable/injectable.dart';
import 'package:translation_app/core/serverpod_service.dart';

import 'auth_policy.dart';
import 'user.dart';

part 'auth_cubit.freezed.dart';

/// Manages the authentication state of the application.
@singleton
class AuthCubit extends CubitSignal<AuthState> {
  /// Resolves the appropriate [AuthCubit] configuration based on [AuthPolicy].
  @factoryMethod
  factory AuthCubit(AuthPolicy policy, ServerpodService serverpod) {
    return switch (policy) {
      ServerpodAuthPolicy() => AuthCubit._serverpod(serverpod),
      NoAuthPolicy(:final defaultUser) => AuthCubit.seeded(user: defaultUser),
    };
  }

  /// Internal constructor: connects directly to Serverpod auth session manager.
  AuthCubit._serverpod(ServerpodService serverpod)
    : _serverpod = serverpod,
      super(initialState: AuthState.initial()) {
    _init();
  }

  /// Seeded constructor: creates an [AuthCubit] with an initial [user],
  /// completely free from Serverpod dependencies.
  ///
  /// Used for testing and for [NoAuthPolicy].
  AuthCubit.seeded({User? user})
    : _serverpod = null,
      super(initialState: AuthState(user: user));

  // ignore: unused_field
  final ServerpodService? _serverpod;

  Future<void> _init() async {
    // final pod = _serverpod;
    // if (pod == null) return;
    // await pod.ready;
    // if (isClosed) return;
    // pod.client.auth.authInfoListenable.addListener(_onAuthChanged);
    // _onAuthChanged();
  }

  // void _onAuthChanged() {
  // final info = _serverpod?.client.auth.authInfoListenable.value;
  // emit(
  //   stateValue.copyWith(
  //     user: info == null
  //         ? null
  //         : User(
  //             id: info.authUserId.toString(),
  //             isAnonymous: info.authStrategy == 'anonymous',
  //           ),
  //   ),
  // );
  // }

  /// Helper for tests to simulate login/logout transitions without mocks.
  @visibleForTesting
  void emitUser(User? user) {
    emit(stateValue.copyWith(user: user));
  }

  /// Signs the user out from the current device.
  Future<void> signOut() async {
    // final pod = _serverpod;
    // if (pod != null) {
    //   await pod.ready;
    //   await pod.client.auth.signOutDevice();
    // } else {
    //   emitUser(null);
    // }
  }

  @override
  Future<void> close() {
    // _serverpod?.client.auth.authInfoListenable.removeListener(_onAuthChanged);
    return super.close();
  }
}

/// The state of the authentication system.
@freezed
abstract class AuthState with _$AuthState {
  const factory AuthState({User? user}) = _AuthState;
  const AuthState._();

  /// Whether a user is currently signed in.
  bool get isAuthenticated => user != null;

  factory AuthState.initial() => const AuthState();
}
