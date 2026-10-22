import 'dart:async';

import 'package:data_layer/data_layer.dart';
import 'package:translation_app/core/data/models/conversation.dart';
import 'package:translation_app/core/data/models/message.dart';
import 'package:translation_app/core/logging/app_logger.dart';

/// Repository managing [Conversation] sessions and their [Message] turns
/// persisted in local Hive boxes.
class ConversationRepository extends Repository<Conversation> {
  ConversationRepository({
    required Source<Conversation> conversationSource,
    required Source<Message> messageSource,
    super.getTime,
  }) : _messageRepository = Repository<Message>(
         SourceList<Message>(
           sources: <Source<Message>>[messageSource],
           bindings: Message.bindings,
           getTime: getTime,
         ),
         getTime: getTime,
       ),
       super(
         SourceList<Conversation>(
           sources: <Source<Conversation>>[conversationSource],
           bindings: Conversation.bindings,
           getTime: getTime,
         ),
       );

  static final _log = AppLogger.of('ConversationRepository');

  final Repository<Message> _messageRepository;
  final StreamController<void> _changesController =
      StreamController<void>.broadcast();

  /// Emits whenever conversations or messages are created, updated, or deleted.
  Stream<void> get onConversationsChanged => _changesController.stream;

  @override
  Future<void> performInitialization() async {
    final sw = Stopwatch()..start();
    _log.info('[PERF] ConversationRepository.performInitialization() START');
    await _messageRepository.ready;
    await super.performInitialization();
    sw.stop();
    _log.info(
      '[PERF] ConversationRepository.performInitialization() FINISH '
      '(${sw.elapsedMilliseconds}ms)',
    );
  }

  /// Eagerly warms up both the conversation and message local sources (opening
  /// all underlying Hive boxes on startup so the first chat thread transition
  /// never pays disk box-open overhead).
  Future<void> warmup() async {
    final sw = Stopwatch()..start();
    _log.info(
      '[PERF] ConversationRepository.warmup() START '
      '(opening conversations_box & messages_box)...',
    );
    await ready;
    final convSw = Stopwatch()..start();
    final conversations = await getItems(
      details: RequestDetails.read(requestType: RequestType.allLocal),
    );
    convSw.stop();
    _log.info(
      '[PERF] ConversationRepository.warmup(): conversations_box opened & read '
      '(${conversations.length} conversations in ${convSw.elapsedMilliseconds}ms)',
    );

    final msgSw = Stopwatch()..start();
    final messages = await _messageRepository.getItems(
      details: RequestDetails.read(requestType: RequestType.allLocal),
    );
    msgSw.stop();
    sw.stop();
    _log.info(
      '[PERF] ConversationRepository.warmup() FINISH: messages_box opened & read '
      '(${messages.length} messages in ${msgSw.elapsedMilliseconds}ms; '
      'total warmup=${sw.elapsedMilliseconds}ms)',
    );
  }

  /// Loads a single [Conversation] by [conversationId].
  Future<Conversation?> getConversationById(String conversationId) async {
    final sw = Stopwatch()..start();
    _log.info(
      '[PERF] ConversationRepository.getConversationById($conversationId) START',
    );
    final result = await getById(
      conversationId,
      details: RequestDetails.read(requestType: RequestType.local),
    );
    sw.stop();
    _log.info(
      '[PERF] ConversationRepository.getConversationById($conversationId) FINISH '
      '(${sw.elapsedMilliseconds}ms, found=${result != null})',
    );
    return result;
  }

  /// Returns all persisted conversations sorted newest-first.
  Future<List<Conversation>> getAllConversations() async {
    final sw = Stopwatch()..start();
    _log.info('[PERF] ConversationRepository.getAllConversations() START');
    final items = await getItems(
      details: RequestDetails.read(requestType: RequestType.allLocal),
    );
    final sorted = List<Conversation>.of(items)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    sw.stop();
    _log.info(
      '[PERF] ConversationRepository.getAllConversations() FINISH '
      '(${sw.elapsedMilliseconds}ms, count=${sorted.length})',
    );
    return sorted;
  }

  /// Returns the most recent conversations (defaults to 3) sorted newest-first.
  Future<List<Conversation>> getRecentConversations({int limit = 3}) async {
    final all = await getAllConversations();
    if (all.length <= limit) {
      return all;
    }
    return all.sublist(0, limit);
  }

  /// Creates and persists a new [Conversation] session.
  Future<Conversation> createConversation({
    required String baseLanguage,
    required String targetLanguage,
    String previewText = '',
    String? generatedSummary,
    String? userSummary,
    String? id,
  }) async {
    final sw = Stopwatch()..start();
    _log.info(
      '[PERF] ConversationRepository.createConversation($baseLanguage <-> $targetLanguage) START',
    );
    final draft = Conversation(
      id: id ?? '',
      createdAt: getTime(),
      baseLanguage: baseLanguage,
      targetLanguage: targetLanguage,
      previewText: previewText,
      generatedSummary: generatedSummary,
      userSummary: userSummary,
    );
    final saved = await setItem(
      draft,
      details: RequestDetails.write(requestType: RequestType.local),
    );
    final result = saved ?? Conversation.bindings.save(draft);
    sw.stop();
    _log.info(
      '[PERF] ConversationRepository.createConversation FINISH '
      '(${sw.elapsedMilliseconds}ms, id=${result.id}, '
      '${result.baseLanguage} <-> ${result.targetLanguage})',
    );
    _notifyChanged();
    return result;
  }

  /// Updates an existing [Conversation] in local storage.
  Future<Conversation> updateConversation(Conversation conversation) async {
    final saved = await setItem(
      conversation,
      details: RequestDetails.write(requestType: RequestType.local),
    );
    final result = saved ?? conversation;
    _notifyChanged();
    return result;
  }

  /// Persists a [Message] and updates its parent [Conversation.previewText].
  Future<Message> saveMessage(Message message) async {
    final savedMessage = await _messageRepository.setItem(
      message,
      details: RequestDetails.write(requestType: RequestType.local),
    );
    final result = savedMessage ?? Message.bindings.save(message);
    _log.info(
      'Saved message id=${result.id} in conversation=${result.conversationId}: '
      'isBaseLanguage=${result.isBaseLanguage}, translatedText="${result.translatedText}"',
    );

    final existingConv = await getConversationById(result.conversationId);
    if (existingConv != null && result.translatedText.trim().isNotEmpty) {
      await setItem(
        existingConv.copyWith(previewText: result.translatedText.trim()),
        details: RequestDetails.write(requestType: RequestType.local),
      );
    }

    _notifyChanged();
    return result;
  }

  /// Loads all messages belonging to [conversationId] sorted chronologically
  /// (oldest to newest).
  Future<List<Message>> getMessagesForConversation(
    String conversationId,
  ) async {
    final sw = Stopwatch()..start();
    _log.info(
      '[PERF] ConversationRepository.getMessagesForConversation($conversationId) START',
    );
    final allMessages = await _messageRepository.getItems(
      details: RequestDetails.read(requestType: RequestType.allLocal),
    );
    final matching =
        allMessages.where((m) => m.conversationId == conversationId).toList()
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    sw.stop();
    _log.info(
      '[PERF] ConversationRepository.getMessagesForConversation($conversationId) FINISH '
      '(${sw.elapsedMilliseconds}ms, totalInBox=${allMessages.length}, '
      'matching=${matching.length})',
    );
    return matching;
  }

  /// Deletes a [Conversation] and all of its associated [Message] records.
  Future<void> deleteConversation(String conversationId) async {
    final messages = await getMessagesForConversation(conversationId);
    for (final msg in messages) {
      await _messageRepository.deleteItem(
        msg.id,
        details: RequestDetails.delete(requestType: RequestType.local),
      );
    }
    await deleteItem(
      conversationId,
      details: RequestDetails.delete(requestType: RequestType.local),
    );
    _notifyChanged();
  }

  void _notifyChanged() {
    if (!_changesController.isClosed) {
      _changesController.add(null);
    }
  }

  @override
  void close() {
    _changesController.close();
    _messageRepository.close();
    super.close();
  }
}
