import 'package:data_layer/data_layer.dart';
import 'package:injectable/injectable.dart';

@singleton
/// This is nothing more than a placeholder in case we ever add back in
/// server-side functionality and thus need Serverpod again.
class ServerpodService with ReadinessMixin<void> {
  @override
  Future<void> performInitialization() async {
    markReady(null);
  }
}
