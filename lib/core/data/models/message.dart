import 'package:data_layer/data_layer.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:hive_ce/hive.dart';

part 'message.freezed.dart';
part 'message.g.dart';

int _messageIdCounter = 0;

String _nextMessageId() =>
    'msg_${DateTime.now().microsecondsSinceEpoch}_${++_messageIdCounter}';

/// Represents a single translated speech turn inside a [Conversation].
@freezed
abstract class Message with _$Message {
  const factory Message({
    required String id,
    required String conversationId,
    required DateTime timestamp,

    /// True when the spoken utterance was in the user's base language (`isUser`).
    required bool isBaseLanguage,
    required String originalText,
    required String translatedText,
  }) = _Message;

  const Message._();

  factory Message.fromJson(Map<String, Object?> json) =>
      _$MessageFromJson(json);

  static CreationBindings<Message> get bindings => CreationBindings<Message>(
    getId: (obj) => obj.id.isEmpty ? null : obj.id,
    fromJson: Message.fromJson,
    toJson: (obj) => obj.toJson(),
    save: (obj) => obj.id.isEmpty ? obj.copyWith(id: _nextMessageId()) : obj,
  );
}

/// Hive [TypeAdapter] for [Message].
class MessageAdapter extends TypeAdapter<Message> {
  @override
  final int typeId = 4;

  @override
  Message read(BinaryReader reader) {
    final map = reader.readMap().cast<String, Object?>();
    return Message.fromJson(map);
  }

  @override
  void write(BinaryWriter writer, Message obj) {
    writer.writeMap(obj.toJson());
  }
}
