import 'package:freezed_annotation/freezed_annotation.dart';

part 'user.freezed.dart';

/// Represents an authenticated user in the app domain.
@freezed
abstract class User with _$User {
  const factory User({
    required String id,
    @Default(false) bool isAnonymous,
  }) = _User;
}
