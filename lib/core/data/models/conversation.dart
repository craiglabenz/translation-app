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
    DateTime? lastMessageAt,
  }) = _Conversation;

  const Conversation._();

  /// Returns the timestamp of the most recent message in this conversation, or
  /// [createdAt] if no message timestamp has been recorded yet.
  DateTime get effectiveTimestamp => lastMessageAt ?? createdAt;

  /// Formats [timestamp] as a compact, humanized relative time string compared
  /// to [now] (e.g. `'just now'`, `'10m ago'`, `'2h ago'`, `'1d ago'`).
  static String formatRelativeTime(DateTime timestamp, {DateTime? now}) {
    final reference = (now ?? DateTime.now()).toUtc();
    final diff = reference.difference(timestamp.toUtc());
    if (diff.isNegative || diff.inMinutes < 1) {
      return 'just now';
    }
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    }
    if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    }
    if (diff.inDays < 30) {
      return '${diff.inDays}d ago';
    }
    if (diff.inDays < 365) {
      return '${diff.inDays ~/ 30}mo ago';
    }
    return '${diff.inDays ~/ 365}y ago';
  }

  /// Humanized indicator of how long ago this conversation occurred.
  String relativeTimeLabel({DateTime? now}) =>
      formatRelativeTime(effectiveTimestamp, now: now);

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
