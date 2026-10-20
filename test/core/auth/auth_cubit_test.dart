import 'package:flutter_test/flutter_test.dart';
import 'package:translation_app/core/auth/auth.dart';

void main() {
  group('AuthCubit', () {
    test('AuthCubit.seeded initializes with user and emits updates', () async {
      final cubit = AuthCubit.seeded(user: const User(id: 'user_123'));
      expect(cubit.stateValue.isAuthenticated, isTrue);
      expect(cubit.stateValue.user?.id, 'user_123');

      cubit.emitUser(null);
      expect(cubit.stateValue.isAuthenticated, isFalse);
      expect(cubit.stateValue.user, isNull);

      await cubit.close();
    });

    test(
      'AuthPolicy.none initializes with default user and isAuthenticated',
      () async {
        const policy = AuthPolicy.none();
        expect(policy.isEnabled, isFalse);
        expect(policy.defaultUser?.id, 'local');

        final cubit = AuthCubit.seeded(user: policy.defaultUser);
        expect(cubit.stateValue.isAuthenticated, isTrue);
        expect(cubit.stateValue.user?.id, 'local');

        await cubit.close();
      },
    );
  });
}
