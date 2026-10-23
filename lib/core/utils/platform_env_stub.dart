/// Returns `true` when running inside a `flutter test` environment (always
/// `false` in compiled web builds unless overridden via `--dart-define`).
bool get isFlutterTestEnvironment =>
    const bool.fromEnvironment('FLUTTER_TEST');

/// Returns `null` on web, where Hive uses IndexedDB rather than filesystem paths.
Future<String?> createTempHivePath() async => null;
