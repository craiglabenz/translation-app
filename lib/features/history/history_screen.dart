import 'dart:async';

import 'package:flow_ui/flow_ui.dart';
import 'package:get_it/get_it.dart';
import 'package:kaisel/kaisel.dart';
import 'package:material_ui/material_ui.dart';
import 'package:translation_app/core/data/models/app_settings.dart';
import 'package:translation_app/core/data/models/conversation.dart';
import 'package:translation_app/core/data/repositories/conversation_repository.dart';
import 'package:translation_app/core/routing/routing.dart';
import 'package:translation_app/core/theme/tokens.dart';

/// Full-screen history view displaying all past conversations via
/// [FlowThreadList.flat] and supporting deletion.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({
    this.conversationRepository,
    super.key,
  });

  final ConversationRepository? conversationRepository;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late final ConversationRepository _conversationRepository;
  StreamSubscription<void>? _conversationsSub;
  List<Conversation> _conversations = const <Conversation>[];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _conversationRepository =
        widget.conversationRepository ?? GetIt.I<ConversationRepository>();
    unawaited(_loadConversations());
    _conversationsSub = _conversationRepository.onConversationsChanged.listen((
      _,
    ) {
      unawaited(_loadConversations());
    });
  }

  Future<void> _loadConversations() async {
    final items = await _conversationRepository.getAllConversations();
    if (mounted) {
      setState(() {
        _conversations = items;
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    unawaited(_conversationsSub?.cancel());
    super.dispose();
  }

  void _handleBack() {
    final scope = RouterScope.maybeOf<AppRoute>(context);
    if (scope != null) {
      unawaited(scope.router.pop());
    } else if (GetIt.I.isRegistered<AppRouter>()) {
      unawaited(GetIt.I<AppRouter>().config.router.pop());
    } else {
      Navigator.maybeOf(context)?.maybePop();
    }
  }

  void _openConversation(String conversationId) {
    final route = ChatRoute(
      conversationId: conversationId,
      autoStartListening: false,
    );
    final scope = RouterScope.maybeOf<AppRoute>(context);
    if (scope != null) {
      unawaited(scope.router.push(route));
    } else if (GetIt.I.isRegistered<AppRouter>()) {
      unawaited(GetIt.I<AppRouter>().config.router.push(route));
    }
  }

  Future<void> _deleteConversation(String conversationId) async {
    await _conversationRepository.deleteConversation(conversationId);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;
    final typography = context.flowTypography;

    final threadItems = _conversations
        .map(
          (c) => FlowThreadListItem(
            id: c.id,
            title: c.previewText.trim().isNotEmpty
                ? c.previewText
                : '${AppSettings.languageNameFor(c.baseLanguage)} ⇄ '
                      '${AppSettings.languageNameFor(c.targetLanguage)}',
            icon: Icons.forum_outlined,
          ),
        )
        .toList();

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        leading: IconButton(
          key: const ValueKey('history_back_button'),
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: _handleBack,
        ),
        title: Text(
          'Conversation History',
          style: typography.titleMediumEmphasised.copyWith(
            color: colors.onSurface,
          ),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppTokens.maxContentWidth,
            ),
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _conversations.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'No past conversations saved yet.',
                        style: typography.bodyMedium.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTokens.pageHorizontalPadding,
                      vertical: 16,
                    ),
                    children: [
                      Text(
                        'Tap a conversation to read or resume translating',
                        style: typography.labelMedium.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: colors.outline),
                        ),
                        child: FlowThreadList.flat(
                          key: const ValueKey('history_thread_list'),
                          items: threadItems,
                          shrinkWrap: true,
                          onThreadSelected: _openConversation,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ..._conversations.map(
                        (conv) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${AppSettings.languageNameFor(conv.baseLanguage)} ⇄ '
                                  '${AppSettings.languageNameFor(conv.targetLanguage)} • '
                                  '${conv.previewText.isEmpty ? "Empty thread" : conv.previewText}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: typography.labelSmall.copyWith(
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              IconButton(
                                key: ValueKey('delete_conv_${conv.id}'),
                                tooltip: 'Delete conversation',
                                icon: Icon(
                                  Icons.delete_outline_rounded,
                                  size: 18,
                                  color: colors.onSurfaceMuted,
                                ),
                                onPressed: () => _deleteConversation(conv.id),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
