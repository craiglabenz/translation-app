import 'package:data_layer/data_layer.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:hive_ce/hive.dart';

part 'conversation.freezed.dart';
part 'conversation.g.dart';

int _conversationIdCounter = 0;

String _nextConversationId() =>
    'conv_${DateTime.now().microsecondsSinceEpoch}_${++_conversationIdCounter}';

/// Represents a translation conversation session.
@freezed
abstract class Conversation with _$Conversation {
  const factory Conversation({
    required String id,
    required DateTime createdAt,
    required String baseLanguage,
    required String targetLanguage,
    @Default('') String previewText,
    String? generatedSummary,
    String? userSummary,
  }) = _Conversation;

  const Conversation._();

  /// Returns `userSummary ?? generatedSummary` (ignoring empty/whitespace-only
  /// values), or `null` if neither summary is present.
  String? get effectiveSummary {
    final user = userSummary?.trim();
    if (user != null && user.isNotEmpty) {
      return user;
    }
    final generated = generatedSummary?.trim();
    if (generated != null && generated.isNotEmpty) {
      return generated;
    }
    return null;
  }

  factory Conversation.fromJson(Map<String, Object?> json) =>
      _$ConversationFromJson(json);

  static CreationBindings<Conversation> get bindings =>
      CreationBindings<Conversation>(
        getId: (obj) => obj.id.isEmpty ? null : obj.id,
        fromJson: Conversation.fromJson,
        toJson: (obj) => obj.toJson(),
        save: (obj) =>
            obj.id.isEmpty ? obj.copyWith(id: _nextConversationId()) : obj,
      );
}

/// Hive [TypeAdapter] for [Conversation].
class ConversationAdapter extends TypeAdapter<Conversation> {
  @override
  final int typeId = 3;

  @override
  Conversation read(BinaryReader reader) {
    final map = reader.readMap().cast<String, Object?>();
    return Conversation.fromJson(map);
  }

  @override
  void write(BinaryWriter writer, Conversation obj) {
    writer.writeMap(obj.toJson());
  }
}
