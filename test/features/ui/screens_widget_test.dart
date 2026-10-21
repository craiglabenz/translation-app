import 'dart:typed_data';

import 'package:data_layer/data_layer.dart';
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
  }) async {
    return const TranslationResult(
      sourceLanguage: 'en',
      originalText: 'Original secret transcript',
      translatedText: 'Texto traducido solamente',
    );
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
    testWidgets('renders listening state and invokes callback on mic or Pause tap', (
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
      expect(find.text('Pause'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('mic_toggle_button')));
      expect(toggleCount, 1);

      await tester.tap(find.byKey(const ValueKey('mic_action_text_button')));
      expect(toggleCount, 2);
    });

    testWidgets('renders paused state with Resume action', (tester) async {
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
      expect(find.text('Resume'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('mic_action_text_button')));
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
            amplitude: 0.1,
            onToggleListening: () {},
          ),
        ),
      );

      expect(find.text('Translating speech…'), findsOneWidget);
      expect(
        find.text('Gemma 4 is processing audio & currency context'),
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

        // Verify read-only state shows "Microphone paused" and "Resume" button
        expect(find.text('Microphone paused'), findsOneWidget);
        expect(find.text('Resume'), findsOneWidget);

        // Tap Resume to start listening in this historical conversation
        await tester.tap(find.byKey(const ValueKey('mic_action_text_button')));
        await tester.pumpAndSettle();

        expect(chatBloc.stateValue.isListening, isTrue);
        expect(find.text('Listening continuously'), findsOneWidget);
        expect(find.text('Pause'), findsOneWidget);

        // Tap Pause to pause listening again
        await tester.tap(find.byKey(const ValueKey('mic_action_text_button')));
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

      // Change Primary (Base) Language to French
      await tester.tap(find.byKey(const ValueKey('base_language_dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('French (Français)').last);
      await tester.pumpAndSettle();
      expect(settingsBloc.stateValue.settings.baseLanguage, 'fr');

      // Change Target Language to Japanese
      await tester.tap(find.byKey(const ValueKey('target_language_dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Japanese (日本語)').last);
      await tester.pumpAndSettle();
      expect(settingsBloc.stateValue.settings.targetLanguage, 'ja');

      // Change Primary Currency to GBP
      await tester.tap(find.byKey(const ValueKey('base_currency_dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('GBP — British Pound (£)').last);
      await tester.pumpAndSettle();
      expect(settingsBloc.stateValue.settings.baseCurrency, 'GBP');

      // Change Target Currency to JPY
      await tester.tap(find.byKey(const ValueKey('target_currency_dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('JPY — Japanese Yen (¥)').last);
      await tester.pumpAndSettle();
      expect(settingsBloc.stateValue.settings.targetCurrency, 'JPY');
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
    });
  });
}
