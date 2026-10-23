import 'dart:io';

/// Returns `true` when running inside a `flutter test` VM environment.
bool get isFlutterTestEnvironment =>
    Platform.environment.containsKey('FLUTTER_TEST');

/// Creates a temporary directory on native platforms for Hive fallback storage.
Future<String?> createTempHivePath() async {
  final fallbackDir = await Directory.systemTemp.createTemp(
    'translation_app_hive_',
  );
  return fallbackDir.path;
}
