import 'dart:typed_data';

import 'package:data_layer/data_layer.dart';
import 'package:flow_ui/flow_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:material_ui/material_ui.dart';
import 'package:translation_app/core/ai/model_manager.dart';
import 'package:translation_app/core/ai/translation_engine.dart';
import 'package:translation_app/core/audio/native_audio_service.dart';
import 'package:translation_app/core/core.dart';
import 'package:translation_app/core/data/models/app_settings.dart';
import 'package:translation_app/core/data/models/exchange_rate_cache.dart';
import 'package:translation_app/core/data/models/message.dart';
import 'package:translation_app/core/data/repositories/conversation_repository.dart';
import 'package:translation_app/core/data/repositories/settings_repository.dart';
import 'package:translation_app/core/routing/routing.dart';
import 'package:translation_app/core/theme/app_theme.dart';
import 'package:translation_app/features/conversation/bloc/active_conversation_bloc.dart';
import 'package:translation_app/features/conversation/widgets/active_chat_view.dart';
import 'package:translation_app/features/conversation/widgets/pulsing_mic_indicator.dart';
import 'package:translation_app/features/history/history_screen.dart';
import 'package:translation_app/features/home/home_screen.dart';
import 'package:translation_app/features/home/widgets/ripple_start_button.dart';
import 'package:translation_app/features/settings/bloc/settings_bloc.dart';
import 'package:translation_app/features/settings/settings_screen.dart';
import 'package:translation_app/main.dart';

class _StubTranslationEngine implements TranslationEngine {
  @override
  Future<void> initialize() async {}

  @override
  Future<TranslationResult> translateAudioChunk({
    required Float32List audioWavChunk,
    required String baseLanguage,
    required String targetLanguage,
    required double exchangeRate,
    required String baseCurrency,
    required String targetCurrency,
    void Function(TranslationResult partialResult)? onPartialResult,
  }) async {
    return const TranslationResult(
      sourceLanguage: 'en',
      originalText: 'Original secret transcript',
      translatedText: 'Texto traducido solamente',
    );
  }

  @override
  Future<String> summarizeConversation({
    required List<Message> messages,
    required String baseLanguage,
    required String targetLanguage,
  }) async {
    return 'Three word summary';
  }

  @override
  Future<void> dispose() async {}
}

Widget _wrapWithTheme(Widget child) {
  return MaterialApp(
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    home: Scaffold(body: child),
  );
}

void main() {
  group('RippleStartButton widget tests', () {
    testWidgets('renders label, subtitle, and triggers onTap when enabled', (
      tester,
    ) async {
      var tapCount = 0;
      await tester.pumpWidget(
        _wrapWithTheme(
          Center(
            child: RippleStartButton(
              label: 'Start Translating',
              subtitle: '1 USD = 0.92 EUR',
              onTap: () => tapCount++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Start Translating'), findsOneWidget);
      expect(find.text('1 USD = 0.92 EUR'), findsOneWidget);
      expect(find.byIcon(Icons.mic_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.mic_rounded));
      await tester.pumpAndSettle();
      expect(tapCount, 1);
    });

    testWidgets('ignores taps when enabled is false', (tester) async {
      var tapCount = 0;
      await tester.pumpWidget(
        _wrapWithTheme(
          Center(
            child: RippleStartButton(
              enabled: false,
              onTap: () => tapCount++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.mic_rounded));
      await tester.pumpAndSettle();
      expect(tapCount, 0);
    });
  });

  group('PulsingMicIndicator widget tests', () {
    testWidgets('renders listening state and invokes callback on mic avatar tap', (
      tester,
    ) async {
      var toggleCount = 0;
      await tester.pumpWidget(
        _wrapWithTheme(
          PulsingMicIndicator(
            isListening: true,
            isLoading: false,
            amplitude: 0.25,
            onToggleListening: () => toggleCount++,
          ),
        ),
      );

      expect(find.text('Listening continuously'), findsOneWidget);
      expect(
        find.text('Pause for 3 seconds to translate • Tap mic to stop'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('mic_action_text_button')), findsNothing);
      expect(find.text('Pause'), findsNothing);
      expect(find.text('Resume'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('mic_toggle_button')));
      expect(toggleCount, 1);
    });

    testWidgets('renders paused state and toggles via microphone avatar', (tester) async {
      var toggleCount = 0;
      await tester.pumpWidget(
        _wrapWithTheme(
          PulsingMicIndicator(
            isListening: false,
            isLoading: false,
            amplitude: 0.0,
            onToggleListening: () => toggleCount++,
          ),
        ),
      );

      expect(find.text('Microphone paused'), findsOneWidget);
      expect(
        find.text('Tap the microphone to resume live translation in this thread'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('mic_action_text_button')), findsNothing);
      expect(find.text('Resume'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('mic_toggle_button')));
      expect(toggleCount, 1);
    });

    testWidgets('renders translating loading copy when isLoading is true', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapWithTheme(
          PulsingMicIndicator(
            isListening: true,
            isLoading: true,
            amplitude: 0.0,
            onToggleListening: () {},
          ),
        ),
      );

      expect(find.text('Translating speech…'), findsOneWidget);
      expect(
        find.text('Gemma 4 is processing audio & currency context'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('mic_translating_spinner')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('mic_translating_thinking_indicator')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('mic_translating_progress_bar')),
        findsOneWidget,
      );
    });
  });

  group('HomeScreen widget tests', () {
    tearDown(() async => GetIt.I.reset());

    testWidgets(
      'shows model download banner when uninstalled and navigates to Settings via FlowPill',
      (tester) async {
        configureDependencies();
        final modelManager = GetIt.I<ModelManager>()..markUninstalled();
        expect(modelManager.stateValue.isInstalled, isFalse);

        await tester.pumpWidget(const MyApp());
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('home_model_banner')), findsOneWidget);
        expect(
          find.text('Gemma 4 E2B On-Device Model Required'),
          findsOneWidget,
        );

        // Tap the language FlowPill to navigate to SettingsRoute
        await tester.tap(find.byKey(const ValueKey('home_language_pill')));
        await tester.pumpAndSettle();

        expect(
          GetIt.I<AppRouter>().config.router.stack.last,
          const SettingsRoute(),
        );
        expect(find.text('Translation Settings'), findsOneWidget);
      },
    );

    testWidgets('hides model banner when model is installed and swaps language pair', (
      tester,
    ) async {
      configureDependencies();

      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();

      // Model is installed by default in test DI
      expect(find.byKey(const ValueKey('home_model_banner')), findsNothing);
      expect(
        find.text('English (USD) ⇄ Spanish (EUR)'),
        findsOneWidget,
      );

      // Tap swap button
      await tester.tap(find.byKey(const ValueKey('home_swap_pair_button')));
      await tester.pumpAndSettle();

      expect(
        find.text('Spanish (EUR) ⇄ English (USD)'),
        findsOneWidget,
      );
    });

    testWidgets('renders stale rate warning banner when exchangeRate.isStale is true', (
      tester,
    ) async {
      configureDependencies();
      final settingsBloc = GetIt.I<SettingsBloc>();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: HomeScreen(settingsBloc: settingsBloc),
        ),
      );
      await tester.pumpAndSettle();

      // Emit a stale rate on SettingsBloc
      settingsBloc.emit(
        settingsBloc.stateValue.copyWith(
          exchangeRate: ExchangeRateCache(
            baseCurrency: 'USD',
            targetCurrency: 'EUR',
            rate: 0.91,
            updatedAt: DateTime.utc(2026, 1, 1),
            isStale: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('stale_rate_banner')), findsOneWidget);
      expect(
        find.textContaining('Offline rate: 1 USD = 0.91 EUR (cached)'),
        findsOneWidget,
      );
    });

    testWidgets('displays recent conversations and navigates to HistoryRoute and ChatRoute', (
      tester,
    ) async {
      configureDependencies();
      final convRepo = GetIt.I<ConversationRepository>();
      final c1 = await convRepo.createConversation(
        baseLanguage: 'en',
        targetLanguage: 'es',
        previewText: '¿Dónde está el hotel?',
      );

      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('home_recent_threads_list')),
        findsOneWidget,
      );
      expect(find.text('¿Dónde está el hotel?'), findsOneWidget);

      // Tap "See All" to navigate to HistoryRoute
      await tester.tap(find.byKey(const ValueKey('home_see_all_history_button')));
      await tester.pumpAndSettle();

      expect(
        GetIt.I<AppRouter>().config.router.stack.last,
        const HistoryRoute(),
      );
      expect(find.text('Conversation History'), findsOneWidget);

      // Navigate back to HomeScreen
      await tester.tap(find.byKey(const ValueKey('history_back_button')));
      await tester.pumpAndSettle();
      expect(
        GetIt.I<AppRouter>().config.router.stack.last,
        const HomeRoute(),
      );

      // Tap recent thread to open ChatRoute in read-only mode
      await tester.tap(find.text('¿Dónde está el hotel?'));
      await tester.pumpAndSettle();

      expect(
        GetIt.I<AppRouter>().config.router.stack.last,
        ChatRoute(conversationId: c1.id, autoStartListening: false),
      );
    });
  });

  group('ActiveChatView widget tests', () {
    tearDown(() async => GetIt.I.reset());

    testWidgets(
      'renders ONLY translatedText in bubbles and supports resuming and pausing past conversations',
      (tester) async {
        configureDependencies();
        final convRepo = GetIt.I<ConversationRepository>();
        final settingsRepo = GetIt.I<SettingsRepository>();
        final settingsBloc = GetIt.I<SettingsBloc>();

        final conv = await convRepo.createConversation(
          baseLanguage: 'en',
          targetLanguage: 'es',
          previewText: 'Hola amigo',
        );
        await convRepo.saveMessage(
          Message(
            id: 'm1',
            conversationId: conv.id,
            timestamp: DateTime.utc(2026, 1, 1, 10),
            isBaseLanguage: true,
            originalText: 'Should NOT appear in bubble',
            translatedText: 'Hola amigo (10 USD = 9.20 EUR)',
          ),
        );
        await convRepo.saveMessage(
          Message(
            id: 'm2',
            conversationId: conv.id,
            timestamp: DateTime.utc(2026, 1, 1, 10, 1),
            isBaseLanguage: false,
            originalText: 'Tampoco debe aparecer',
            translatedText: 'Hello friend, welcome!',
          ),
        );

        final audioService = NativeAudioService();
        final chatBloc = ActiveConversationBloc(
          conversationRepository: convRepo,
          settingsRepository: settingsRepo,
          translationEngine: _StubTranslationEngine(),
          audioService: audioService,
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: ActiveChatView(
              conversationId: conv.id,
              autoStartListening: false,
              conversationBloc: chatBloc,
              settingsBloc: settingsBloc,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Verify ONLY translatedText is rendered and originalText is NOT rendered
        expect(find.text('Hola amigo (10 USD = 9.20 EUR)'), findsOneWidget);
        expect(find.text('Hello friend, welcome!'), findsOneWidget);
        expect(find.text('Should NOT appear in bubble'), findsNothing);
        expect(find.text('Tampoco debe aparecer'), findsNothing);

        // Verify bubble alignment / FlowMessageRole:
        // - Host message (m1, isBaseLanguage: true, English translated to target language)
        //   is placed on the LEFT (FlowMessageRole.assistant).
        // - Guest message (m2, isBaseLanguage: false, target language translated to English)
        //   is placed on the RIGHT (FlowMessageRole.user).
        final threadWidget = tester.widget<FlowThread>(
          find.byKey(const ValueKey('active_flow_thread')),
        );
        expect(threadWidget.messages, hasLength(2));
        expect(threadWidget.messages[0].id, 'm1');
        expect(threadWidget.messages[0].role, FlowMessageRole.assistant);
        expect(threadWidget.messages[1].id, 'm2');
        expect(threadWidget.messages[1].role, FlowMessageRole.user);

        // Verify read-only state shows "Microphone paused" and no separate Resume button
        expect(find.text('Microphone paused'), findsOneWidget);
        expect(find.text('Resume'), findsNothing);

        // Tap microphone avatar to start listening in this historical conversation
        await tester.tap(find.byKey(const ValueKey('mic_toggle_button')));
        await tester.pumpAndSettle();

        expect(chatBloc.stateValue.isListening, isTrue);
        expect(find.text('Listening continuously'), findsOneWidget);

        // Tap microphone avatar to pause listening again
        await tester.tap(find.byKey(const ValueKey('mic_toggle_button')));
        await tester.pumpAndSettle();
        expect(chatBloc.stateValue.isListening, isFalse);

        await chatBloc.close();
        await audioService.dispose();
      },
    );

    testWidgets('displays error banner when state.error is present', (
      tester,
    ) async {
      configureDependencies();
      final convRepo = GetIt.I<ConversationRepository>();
      final settingsRepo = GetIt.I<SettingsRepository>();
      final settingsBloc = GetIt.I<SettingsBloc>();
      final audioService = NativeAudioService();
      final chatBloc = ActiveConversationBloc(
        conversationRepository: convRepo,
        settingsRepository: settingsRepo,
        translationEngine: _StubTranslationEngine(),
        audioService: audioService,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: ActiveChatView(
            conversationId: 'nonexistent_conversation_id',
            autoStartListening: false,
            conversationBloc: chatBloc,
            settingsBloc: settingsBloc,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('chat_error_banner')), findsOneWidget);
      expect(find.text('Conversation not found.'), findsOneWidget);

      // Verify model download progress banner appears inside ActiveChatView when downloading
      GetIt.I<ModelManager>().emit(
        const ModelDownloadState(
          isInstalled: false,
          isDownloading: true,
          progress: 0.35,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('chat_model_download_banner')),
        findsOneWidget,
      );
      expect(
        find.textContaining('Downloading Gemma 4 E2B model (35%)…'),
        findsOneWidget,
      );

      await chatBloc.close();
      await audioService.dispose();
    });

    testWidgets(
      'renders live streaming partial translation on left for Host and on right for Guest',
      (tester) async {
        configureDependencies();
        final convRepo = GetIt.I<ConversationRepository>();
        final settingsRepo = GetIt.I<SettingsRepository>();
        final settingsBloc = GetIt.I<SettingsBloc>();
        final audioService = NativeAudioService();
        final chatBloc = ActiveConversationBloc(
          conversationRepository: convRepo,
          settingsRepository: settingsRepo,
          translationEngine: _StubTranslationEngine(),
          audioService: audioService,
        );

        final conv = await convRepo.createConversation(
          baseLanguage: 'en',
          targetLanguage: 'ko',
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: ActiveChatView(
              conversationId: conv.id,
              autoStartListening: false,
              conversationBloc: chatBloc,
              settingsBloc: settingsBloc,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Emit in-progress Host streaming translation (English -> Korean on LEFT)
        chatBloc.emit(
          chatBloc.stateValue.copyWith(
            isLoading: true,
            amplitude: 0.0,
            streamingTranslatedText: '지하철역이 어디에…',
            streamingIsBaseLanguage: true,
          ),
        );
        await tester.pump();

        expect(find.text('지하철역이 어디에…'), findsOneWidget);
        expect(find.text('Still translating…'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('chat_in_progress_translation_badge')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('mic_translating_spinner')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('mic_translating_progress_bar')),
          findsOneWidget,
        );
        var thread = tester.widget<FlowThread>(
          find.byKey(const ValueKey('active_flow_thread')),
        );
        expect(thread.messages.single.id, '__translating_streaming__');
        expect(thread.messages.single.role, FlowMessageRole.assistant);

        // 2. Emit in-progress Guest streaming translation (Korean -> English on RIGHT)
        chatBloc.emit(
          chatBloc.stateValue.copyWith(
            isLoading: true,
            amplitude: 0.0,
            streamingTranslatedText: 'Go straight two blocks…',
            streamingIsBaseLanguage: false,
          ),
        );
        await tester.pump();

        expect(find.text('Go straight two blocks…'), findsOneWidget);
        expect(find.text('Still translating…'), findsOneWidget);
        thread = tester.widget<FlowThread>(
          find.byKey(const ValueKey('active_flow_thread')),
        );
        expect(thread.messages.single.id, '__translating_streaming__');
        expect(thread.messages.single.role, FlowMessageRole.user);

        // 3. Emit finalized message -> in-progress affordances disappear
        chatBloc.emit(
          chatBloc.stateValue.copyWith(
            isLoading: false,
            streamingTranslatedText: null,
            streamingIsBaseLanguage: null,
            messages: [
              Message(
                id: 'msg_finalized_1',
                conversationId: conv.id,
                timestamp: DateTime.utc(2026, 6, 1, 12),
                isBaseLanguage: false,
                originalText: '두 블록 직진하세요.',
                translatedText: 'Go straight two blocks.',
              ),
            ],
          ),
        );
        await tester.pump();

        expect(find.text('Go straight two blocks.'), findsOneWidget);
        expect(find.text('Still translating…'), findsNothing);
        expect(
          find.byKey(const ValueKey('chat_in_progress_translation_badge')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('mic_translating_spinner')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('mic_translating_progress_bar')),
          findsNothing,
        );

        await chatBloc.close();
        await audioService.dispose();
      },
    );
  });

  group('HistoryScreen widget tests', () {
    tearDown(() async => GetIt.I.reset());

    testWidgets('renders empty state when no conversations exist', (
      tester,
    ) async {
      configureDependencies();
      final convRepo = GetIt.I<ConversationRepository>();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: HistoryScreen(conversationRepository: convRepo),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No past conversations saved yet.'), findsOneWidget);
    });

    testWidgets('lists saved conversations and deletes conversation when delete button is tapped', (
      tester,
    ) async {
      configureDependencies();
      final convRepo = GetIt.I<ConversationRepository>();
      final c1 = await convRepo.createConversation(
        id: 'conv_del_1',
        baseLanguage: 'en',
        targetLanguage: 'es',
        previewText: 'La cuenta, por favor',
      );
      final c2 = await convRepo.createConversation(
        id: 'conv_del_2',
        baseLanguage: 'fr',
        targetLanguage: 'de',
        previewText: '',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: HistoryScreen(conversationRepository: convRepo),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('history_thread_list')), findsOneWidget);
      expect(find.text('La cuenta, por favor'), findsOneWidget);
      // Empty previewText falls back to language pair title
      expect(find.text('French ⇄ German'), findsOneWidget);

      // Delete first conversation
      await tester.tap(find.byKey(ValueKey('delete_conv_${c1.id}')));
      await tester.pumpAndSettle();

      expect(find.text('La cuenta, por favor'), findsNothing);
      expect(await convRepo.getConversationById(c1.id), isNull);
      expect(await convRepo.getConversationById(c2.id), isNotNull);

      // Delete second conversation -> returns to empty state
      await tester.tap(find.byKey(ValueKey('delete_conv_${c2.id}')));
      await tester.pumpAndSettle();

      expect(find.text('No past conversations saved yet.'), findsOneWidget);
    });
  });

  group('SettingsScreen widget tests', () {
    tearDown(() async => GetIt.I.reset());

    testWidgets('updates model download URL and supports model re-download state transitions', (
      tester,
    ) async {
      final now = DateTime.utc(2026, 5, 1);
      final settingsRepo = SettingsRepository(
        settingsSource: LocalMemorySource<AppSettings>(
          bindings: AppSettings.bindings,
          now: () => now,
        ),
        localExchangeRateSource: LocalMemorySource<ExchangeRateCache>(
          bindings: ExchangeRateCache.bindings,
          now: () => now,
        ),
        remoteExchangeRateSource: RemoteMemorySource<ExchangeRateCache>(
          bindings: ExchangeRateCache.bindings,
          now: () => now,
        ),
        getTime: () => now,
      );
      final modelManager = ModelManager(
        initialInstalled: true,
        isInstalledCheck: () async => true,
        installRunner:
            ({
              required downloadUrl,
              required onProgress,
              cancelToken,
            }) async {
              onProgress(1.0);
            },
      );
      final settingsBloc = SettingsBloc(
        settingsRepository: settingsRepo,
        modelManager: modelManager,
      );
      await settingsBloc.load();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: SettingsScreen(settingsBloc: settingsBloc),
        ),
      );
      await tester.pumpAndSettle();

      // Scroll ListView down so the 3rd section card (On-Device AI Model) is built
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();

      expect(
        find.text('Installed & Ready (gemma-4-E2B-it.litertlm)'),
        findsOneWidget,
      );
      expect(find.text('Re-download'), findsOneWidget);

      // Tap "Re-download" to mark uninstalled
      await tester.ensureVisible(find.text('Re-download'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Re-download'));
      await tester.pumpAndSettle();

      expect(find.text('Not installed on device'), findsOneWidget);
      final downloadButton = find.byKey(
        const ValueKey('settings_download_model_button'),
      );
      expect(downloadButton, findsOneWidget);

      // Enter custom URL in TextField and submit
      final urlField = find.byKey(const ValueKey('model_url_text_field'));
      await tester.ensureVisible(urlField);
      await tester.pumpAndSettle();
      await tester.enterText(
        urlField,
        'https://mirror.example.org/gemma-4.litertlm',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(
        settingsBloc.stateValue.settings.modelDownloadUrl,
        'https://mirror.example.org/gemma-4.litertlm',
      );

      // Tap Download Model button to install
      await tester.ensureVisible(downloadButton);
      await tester.pumpAndSettle();
      await tester.tap(downloadButton);
      await tester.pumpAndSettle();

      expect(modelManager.stateValue.isInstalled, isTrue);
      expect(
        find.text('Installed & Ready (gemma-4-E2B-it.litertlm)'),
        findsOneWidget,
      );

      // Tap Refresh Rate button
      final refreshButton = find.byKey(const ValueKey('refresh_rates_button'));
      await tester.ensureVisible(refreshButton);
      await tester.pumpAndSettle();
      await tester.tap(refreshButton);
      await tester.pumpAndSettle();
      expect(settingsBloc.stateValue.isRefreshingRates, isFalse);

      await settingsBloc.close();
      await modelManager.close();
      settingsRepo.close();
    });

    testWidgets('selecting languages and currencies in dropdowns updates SettingsBloc', (
      tester,
    ) async {
      configureDependencies();
      final settingsBloc = GetIt.I<SettingsBloc>();
      await settingsBloc.load();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: SettingsScreen(settingsBloc: settingsBloc),
        ),
      );
      await tester.pumpAndSettle();

      // Change Primary (Base) Language to French -> also updates baseCurrency to EUR
      await tester.tap(find.byKey(const ValueKey('base_language_dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('French (Français)').last);
      await tester.pumpAndSettle();
      expect(settingsBloc.stateValue.settings.baseLanguage, 'fr');
      expect(settingsBloc.stateValue.settings.baseCurrency, 'EUR');

      // Change Target Language to Japanese -> also updates targetCurrency to JPY
      await tester.tap(find.byKey(const ValueKey('target_language_dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Japanese (日本語)').last);
      await tester.pumpAndSettle();
      expect(settingsBloc.stateValue.settings.targetLanguage, 'ja');
      expect(settingsBloc.stateValue.settings.targetCurrency, 'JPY');

      // Change Primary Currency to GBP -> does NOT alter baseLanguage ('fr')
      await tester.tap(find.byKey(const ValueKey('base_currency_dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('GBP — British Pound (£)').last);
      await tester.pumpAndSettle();
      expect(settingsBloc.stateValue.settings.baseCurrency, 'GBP');
      expect(settingsBloc.stateValue.settings.baseLanguage, 'fr');

      // Change Target Currency to CHF -> does NOT alter targetLanguage ('ja')
      await tester.tap(find.byKey(const ValueKey('target_currency_dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CHF — Swiss Franc (CHF)').last);
      await tester.pumpAndSettle();
      expect(settingsBloc.stateValue.settings.targetCurrency, 'CHF');
      expect(settingsBloc.stateValue.settings.targetLanguage, 'ja');
    });

    testWidgets('HomeScreen model banner shows progress percentage and error message states', (
      tester,
    ) async {
      configureDependencies();
      final settingsBloc = GetIt.I<SettingsBloc>();
      final modelManager = GetIt.I<ModelManager>();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: HomeScreen(settingsBloc: settingsBloc),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Emit downloading state (45%)
      modelManager.emit(
        const ModelDownloadState(
          isInstalled: false,
          isDownloading: true,
          progress: 0.45,
        ),
      );
      await tester.pump();
      expect(
        find.text('Downloading Gemma 4 E2B (45%)…'),
        findsOneWidget,
      );
      expect(find.text('Cancel'), findsOneWidget);

      // 2. Emit error state
      modelManager.emit(
        const ModelDownloadState(
          isInstalled: false,
          isDownloading: false,
          error: 'Insufficient storage on device',
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Insufficient storage on device'),
        findsOneWidget,
      );
    });

    testWidgets('ActiveChatView AppBar shows offline rate indicator and navigates to Settings', (
      tester,
    ) async {
      configureDependencies();
      final settingsBloc = GetIt.I<SettingsBloc>();

      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();

      settingsBloc.emit(
        settingsBloc.stateValue.copyWith(
          exchangeRate: ExchangeRateCache(
            baseCurrency: 'USD',
            targetCurrency: 'EUR',
            rate: 0.92,
            updatedAt: DateTime.utc(2026, 1, 1),
            isStale: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap central RippleStartButton on HomeScreen to push ChatRoute
      await tester.tap(find.byIcon(Icons.mic_rounded));
      await tester.pumpAndSettle();

      expect(
        GetIt.I<AppRouter>().config.router.stack.last,
        const ChatRoute(autoStartListening: true),
      );
      expect(find.text('1 USD = 0.92 EUR (offline)'), findsOneWidget);

      // Tap Settings icon in ActiveChatView AppBar
      await tester.tap(find.byKey(const ValueKey('chat_settings_button')));
      await tester.pumpAndSettle();
      expect(
        GetIt.I<AppRouter>().config.router.stack.last,
        const SettingsRoute(),
      );

      // Tap Back button in SettingsScreen AppBar to return to ActiveChatView
      await tester.tap(find.byKey(const ValueKey('settings_back_button')));
      await tester.pumpAndSettle();
      expect(
        GetIt.I<AppRouter>().config.router.stack.last,
        const ChatRoute(autoStartListening: true),
      );

        // Tap Back button in ActiveChatView AppBar to return to HomeRoute
        await tester.tap(find.byKey(const ValueKey('chat_back_button')));
        await tester.pumpAndSettle();
        expect(
          GetIt.I<AppRouter>().config.router.stack.last,
          const HomeRoute(),
        );
      },
    );

    testWidgets(
      'tapping a message bubble shows modal with originalText and tapping anywhere dismisses it',
      (tester) async {
        configureDependencies();
        final convRepo = GetIt.I<ConversationRepository>();
        final settingsRepo = GetIt.I<SettingsRepository>();
        final settingsBloc = GetIt.I<SettingsBloc>();
        final audioService = NativeAudioService();
        final chatBloc = ActiveConversationBloc(
          conversationRepository: convRepo,
          settingsRepository: settingsRepo,
          translationEngine: _StubTranslationEngine(),
          audioService: audioService,
        );

        final conv = await convRepo.createConversation(
          baseLanguage: 'en',
          targetLanguage: 'ko',
        );
        await convRepo.saveMessage(
          Message(
            id: 'msg_tap_1',
            conversationId: conv.id,
            timestamp: DateTime.utc(2026, 6, 1, 12),
            isBaseLanguage: true,
            originalText: 'How much is this souvenir?',
            translatedText: '이 기념품은 얼마인가요?',
            annotatedText: '이 기념품은 얼마인가요?',
          ),
        );
        await convRepo.saveMessage(
          Message(
            id: 'msg_tap_2',
            conversationId: conv.id,
            timestamp: DateTime.utc(2026, 6, 1, 12, 1),
            isBaseLanguage: false,
            originalText: '15,000원입니다.',
            translatedText: 'It is 15,000 won.',
            annotatedText: r'It is 15,000 won ($10.87 USD).',
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: ActiveChatView(
              conversationId: conv.id,
              autoStartListening: false,
              conversationBloc: chatBloc,
              settingsBloc: settingsBloc,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Bubbles display annotatedText, NOT originalText
        expect(find.text('이 기념품은 얼마인가요?'), findsOneWidget);
        expect(find.text(r'It is 15,000 won ($10.87 USD).'), findsOneWidget);
        expect(find.text('How much is this souvenir?'), findsNothing);

        // 1. Tap the first message bubble -> modal opens showing originalText
        await tester.tap(
          find.byKey(const ValueKey('chat_message_bubble_msg_tap_1')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('original_message_modal')),
          findsOneWidget,
        );
        expect(find.text('How much is this souvenir?'), findsOneWidget);

        // Tap directly inside the modal card text -> hides the modal
        await tester.tap(
          find.byKey(const ValueKey('original_message_modal_text')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('original_message_modal')),
          findsNothing,
        );

        // 2. Tap the second message bubble -> modal opens showing Korean originalText
        await tester.tap(
          find.byKey(const ValueKey('chat_message_bubble_msg_tap_2')),
        );
        await tester.pumpAndSettle();
        expect(find.text('15,000원입니다.'), findsOneWidget);

        // Tap outside on the dismiss area -> hides the modal
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('original_message_modal')),
          findsNothing,
        );

        await chatBloc.close();
        await audioService.dispose();
      },
    );

    testWidgets(
      'SettingsScreen text scaling slider updates multiplier and applies ONLY to chat transcripts',
      (tester) async {
        configureDependencies();
        final convRepo = GetIt.I<ConversationRepository>();
        final settingsBloc = GetIt.I<SettingsBloc>();
        await settingsBloc.load();

        final conv = await convRepo.createConversation(
          id: 'conv_scale_1',
          baseLanguage: 'en',
          targetLanguage: 'ko',
          previewText: '안녕하세요',
        );
        await convRepo.saveMessage(
          Message(
            id: 'msg_scale_1',
            conversationId: conv.id,
            timestamp: DateTime.utc(2026, 6, 1, 12),
            isBaseLanguage: true,
            originalText: 'Hello!',
            translatedText: '안녕하세요!',
          ),
        );

        // Verify multiplicative math: OS 1.25x * user 2.0x = 2.5x
        const osScaler = TextScaler.linear(1.25);
        final effective = ActiveChatView.computeEffectiveTextScaler(
          osScaler,
          2.0,
        );
        expect(effective.scale(10.0), closeTo(25.0, 1e-4));

        // Verify default 1.0x preserves OS 1.25x exactly
        final defaultEffective = ActiveChatView.computeEffectiveTextScaler(
          osScaler,
          1.0,
        );
        expect(defaultEffective.scale(10.0), closeTo(12.5, 1e-4));

        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.2)),
            child: const MyApp(),
          ),
        );
        await tester.pumpAndSettle();

        // Update user text scale multiplier to 3.0x (max)
        await settingsBloc.updateTextScaleFactor(3.0);
        await tester.pumpAndSettle();

        // 1. HomeScreen remains at OS textScaler (1.2x), unaffected by user multiplier
        final homeContext = tester.element(
          find.byKey(const ValueKey('home_language_pill')),
        );
        expect(
          MediaQuery.of(homeContext).textScaler.scale(1.0),
          closeTo(1.2, 1e-3),
        );

        // 2. Navigate to SettingsScreen at 3.0x multiplier -> remains at OS 1.2x with no overflow
        await tester.tap(find.byKey(const ValueKey('home_language_pill')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        final settingsContext = tester.element(
          find.byKey(const ValueKey('base_language_dropdown')),
        );
        expect(
          MediaQuery.of(settingsContext).textScaler.scale(1.0),
          closeTo(1.2, 1e-3),
        );

        // Return to HomeScreen and open the saved conversation in ActiveChatView
        await tester.tap(find.byKey(const ValueKey('settings_back_button')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('안녕하세요!'));
        await tester.pumpAndSettle();

        // 3. Inside ActiveChatView, the control bar stays at OS 1.2x while ONLY the chat transcript scales to 1.2 * 3.0 = 3.6x
        final composerContext = tester.element(
          find.byKey(const ValueKey('active_pulsing_mic_indicator')),
        );
        expect(
          MediaQuery.of(composerContext).textScaler.scale(1.0),
          closeTo(1.2, 1e-3),
        );

        final transcriptBubbleContext = tester.element(
          find.byKey(const ValueKey('chat_message_bubble_msg_scale_1')),
        );
        expect(
          MediaQuery.of(transcriptBubbleContext).textScaler.scale(1.0),
          closeTo(1.2 * 3.0, 1e-3),
        );
      },
    );

    testWidgets(
      'supports deleting a past conversation from HomeScreen and ActiveChatView',
      (tester) async {
        configureDependencies();
        final convRepo = GetIt.I<ConversationRepository>();
        final c1 = await convRepo.createConversation(
          id: 'conv_home_del_1',
          baseLanguage: 'en',
          targetLanguage: 'es',
          previewText: 'Delete me from Home',
        );
        final c2 = await convRepo.createConversation(
          id: 'conv_chat_del_2',
          baseLanguage: 'en',
          targetLanguage: 'es',
          previewText: 'Delete me from Chat',
        );

        await tester.pumpWidget(const MyApp());
        await tester.pumpAndSettle();

        expect(find.text('Delete me from Home'), findsOneWidget);
        expect(find.text('Delete me from Chat'), findsOneWidget);

        // 1. Delete c1 directly from HomeScreen recent conversations
        await tester.tap(
          find.byKey(ValueKey('home_delete_conv_${c1.id}')),
        );
        await tester.pumpAndSettle();

        expect(find.text('Delete me from Home'), findsNothing);
        expect(await convRepo.getConversationById(c1.id), isNull);

        // 2. Open c2 in ActiveChatView and delete it via AppBar delete button
        await tester.tap(find.text('Delete me from Chat'));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('chat_delete_conversation_button')),
          findsOneWidget,
        );
        await tester.tap(
          find.byKey(const ValueKey('chat_delete_conversation_button')),
        );
        await tester.pumpAndSettle();

        expect(await convRepo.getConversationById(c2.id), isNull);
        expect(
          GetIt.I<AppRouter>().config.router.stack.last,
          const HomeRoute(),
        );
      },
    );

    testWidgets(
      'ActiveChatView displays the detected source language flag by each message (e.g. American flag for English -> Korean, Korean flag for Korean -> English)',
      (tester) async {
        configureDependencies();
        final convRepo = GetIt.I<ConversationRepository>();
        final settingsRepo = GetIt.I<SettingsRepository>();
        final settingsBloc = GetIt.I<SettingsBloc>();

        await settingsRepo.saveSettings(
          const AppSettings(
            baseLanguage: 'en',
            targetLanguage: 'ko',
            baseCurrency: 'USD',
            targetCurrency: 'KRW',
          ),
        );
        await settingsBloc.load();

        final conv = await convRepo.createConversation(
          baseLanguage: 'en',
          targetLanguage: 'ko',
          previewText: '안녕하세요',
        );
        // 1. English message translated into Korean -> should show American flag (🇺🇸)
        await convRepo.saveMessage(
          Message(
            id: 'msg_en_to_ko',
            conversationId: conv.id,
            timestamp: DateTime.utc(2026, 1, 1, 10),
            isBaseLanguage: true,
            originalText: 'Where is the subway station?',
            translatedText: '지하철역이 어디에 있나요?',
          ),
        );
        // 2. Korean message translated into English -> should show Korean flag (🇰🇷)
        await convRepo.saveMessage(
          Message(
            id: 'msg_ko_to_en',
            conversationId: conv.id,
            timestamp: DateTime.utc(2026, 1, 1, 10, 1),
            isBaseLanguage: false,
            originalText: '저기 모퉁이를 돌면 있어요.',
            translatedText: 'It is just around that corner.',
          ),
        );

        final audioService = NativeAudioService();
        final chatBloc = ActiveConversationBloc(
          conversationRepository: convRepo,
          settingsRepository: settingsRepo,
          translationEngine: _StubTranslationEngine(),
          audioService: audioService,
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: ActiveChatView(
              conversationId: conv.id,
              autoStartListening: false,
              conversationBloc: chatBloc,
              settingsBloc: settingsBloc,
            ),
          ),
        );
        await tester.pumpAndSettle();

        final enBadgeFinder = find.byKey(
          const ValueKey('chat_message_flag_msg_en_to_ko'),
        );
        final koBadgeFinder = find.byKey(
          const ValueKey('chat_message_flag_msg_ko_to_en'),
        );

        expect(enBadgeFinder, findsOneWidget);
        expect(koBadgeFinder, findsOneWidget);

        // Verify the English -> Korean message displays the American flag (🇺🇸)
        expect(
          find.descendant(of: enBadgeFinder, matching: find.text('🇺🇸')),
          findsOneWidget,
        );
        // Verify the Korean -> English message displays the Korean flag (🇰🇷)
        expect(
          find.descendant(of: koBadgeFinder, matching: find.text('🇰🇷')),
          findsOneWidget,
        );

        await chatBloc.close();
        await audioService.dispose();
      },
    );

    testWidgets(
      'automatically deletes a new conversation if it is still empty upon exiting ActiveChatView',
      (tester) async {
        configureDependencies();
        final convRepo = GetIt.I<ConversationRepository>();

        await tester.pumpWidget(const MyApp());
        await tester.pumpAndSettle();

        expect(await convRepo.getAllConversations(), isEmpty);

        // Tap RippleStartButton on HomeScreen to start a new live conversation
        await tester.tap(find.byIcon(Icons.mic_rounded));
        await tester.pumpAndSettle();

        // While inside ActiveChatView, a draft Conversation record exists
        final duringChat = await convRepo.getAllConversations();
        expect(duringChat, hasLength(1));
        final emptyConvId = duringChat.single.id;

        // Exit ActiveChatView via back button without speaking any messages
        await tester.tap(find.byKey(const ValueKey('chat_back_button')));
        await tester.pumpAndSettle();

        // Verify we returned to HomeRoute and the empty conversation was deleted
        expect(
          GetIt.I<AppRouter>().config.router.stack.last,
          const HomeRoute(),
        );
        expect(await convRepo.getConversationById(emptyConvId), isNull);
        expect(await convRepo.getAllConversations(), isEmpty);
      },
    );

    testWidgets(
      'displays (userSummary ?? generatedSummary) on list views instead of last message and supports editing summary on ActiveChatView',
      (tester) async {
        configureDependencies();
        final convRepo = GetIt.I<ConversationRepository>();

        final conv1 = await convRepo.createConversation(
          id: 'conv_sum_1',
          baseLanguage: 'en',
          targetLanguage: 'es',
          previewText: 'Last raw translated message 1',
          generatedSummary: 'Ordering tapas in Madrid',
        );
        await convRepo.saveMessage(
          Message(
            id: 'm_sum_1',
            conversationId: conv1.id,
            timestamp: DateTime.utc(2026, 6, 1, 10),
            isBaseLanguage: true,
            originalText: 'Two tapas please',
            translatedText: 'Last raw translated message 1',
          ),
        );

        final conv2 = await convRepo.createConversation(
          id: 'conv_sum_2',
          baseLanguage: 'en',
          targetLanguage: 'ko',
          previewText: 'Last raw translated message 2',
          generatedSummary: 'Auto generated summary',
          userSummary: 'Seoul subway directions',
        );
        await convRepo.saveMessage(
          Message(
            id: 'm_sum_2',
            conversationId: conv2.id,
            timestamp: DateTime.utc(2026, 6, 1, 11),
            isBaseLanguage: true,
            originalText: 'Subway please',
            translatedText: 'Last raw translated message 2',
          ),
        );

        await tester.pumpWidget(const MyApp());
        await tester.pumpAndSettle();

        // 1. On HomeScreen list view, (userSummary ?? generatedSummary) is shown instead of previewText
        expect(find.text('Ordering tapas in Madrid'), findsOneWidget);
        expect(find.text('Seoul subway directions'), findsOneWidget);
        expect(find.text('Last raw translated message 1'), findsNothing);
        expect(find.text('Last raw translated message 2'), findsNothing);

        // 2. Open HistoryScreen -> also shows (userSummary ?? generatedSummary)
        await tester.tap(
          find.byKey(const ValueKey('home_see_all_history_button')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Ordering tapas in Madrid'), findsOneWidget);
        expect(find.text('Seoul subway directions'), findsOneWidget);

        // 3. Tap conv1 to open ActiveChatView and edit its summary
        await tester.tap(find.text('Ordering tapas in Madrid'));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('chat_appbar_summary_text')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('chat_edit_summary_button')),
          findsOneWidget,
        );

        await tester.tap(
          find.byKey(const ValueKey('chat_edit_summary_button')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('edit_summary_dialog')),
          findsOneWidget,
        );
        await tester.enterText(
          find.byKey(const ValueKey('edit_summary_text_field')),
          'Dinner reservation at eight',
        );
        await tester.tap(
          find.byKey(const ValueKey('edit_summary_save_button')),
        );
        await tester.pumpAndSettle();

        // Verify updated summary is shown in ActiveChatView and saved in generatedSummary
        expect(find.text('Dinner reservation at eight'), findsOneWidget);
        final updatedConv1 = await convRepo.getConversationById(conv1.id);
        expect(
          updatedConv1?.generatedSummary,
          'Dinner reservation at eight',
        );

        // Return to HistoryScreen -> list view now shows the edited summary
        await tester.tap(find.byKey(const ValueKey('chat_back_button')));
        await tester.pumpAndSettle();
        expect(find.text('Dinner reservation at eight'), findsOneWidget);
      },
    );
  });
}
