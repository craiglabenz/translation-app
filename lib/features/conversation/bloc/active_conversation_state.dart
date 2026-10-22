import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:translation_app/core/data/models/conversation.dart';
import 'package:translation_app/core/data/models/message.dart';

part 'active_conversation_state.freezed.dart';

/// Immutable state for an active or historical translation session.
@freezed
abstract class ActiveConversationState with _$ActiveConversationState {
  const ActiveConversationState._();

  const factory ActiveConversationState({
    Conversation? conversation,
    @Default(<Message>[]) List<Message> messages,
    @Default(false) bool isListening,
    @Default(false) bool isLoading,
    @Default(0.0) double amplitude,
    String? streamingTranslatedText,
    bool? streamingIsBaseLanguage,
    String? error,
  }) = _ActiveConversationState;

  /// True when viewing a past conversation in read-only mode (not listening).
  bool get isReadOnly => conversation != null && !isListening;
}
