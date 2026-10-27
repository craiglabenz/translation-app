import 'dart:async';
import 'dart:typed_data';

import 'package:data_layer/data_layer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:translation_app/core/ai/speech_to_text_engine.dart';
import 'package:translation_app/core/ai/translation_engine.dart';
import 'package:translation_app/core/audio/audio_exceptions.dart';
import 'package:translation_app/core/audio/native_audio_service.dart';
import 'package:translation_app/core/audio/vad_buffer.dart';
import 'package:translation_app/core/data/models/app_settings.dart';
import 'package:translation_app/core/data/models/conversation.dart';
import 'package:translation_app/core/data/models/exchange_rate_cache.dart';
import 'package:translation_app/core/data/models/message.dart';
import 'package:translation_app/core/data/repositories/conversation_repository.dart';
import 'package:translation_app/core/data/repositories/settings_repository.dart';
import 'package:translation_app/features/conversation/bloc/active_conversation_bloc.dart';
import 'package:translation_app/features/conversation/bloc/active_conversation_state.dart';

class _ConfigurableTranslationEngine implements TranslationEngine {
  @override
  List<SupportedLanguage> get supportedLanguages =>
      AppSettings.supportedLanguages;

  TranslationResult nextResult = const TranslationResult(
    sourceLanguage: 'en',
    originalText: 'How much is this?',
    translatedText: '¿Cuánto cuesta esto?',
  );
  Object? initializeError;
  Object? translateError;

  @override
  Future<void> initialize() async {
    if (initializeError != null) {
      throw initializeError!;
    }
  }

  List<TranslationResult> partialResultsToEmit = const <TranslationResult>[];
  int translateCallCount = 0;
  int summarizeCallCount = 0;
  String nextSummary = 'Asking about item price';
  String? lastContextPromptBlock;

  @override
  Future<TranslationResult> translateAudioChunk({
    required Float32List audioWavChunk,
    required String baseLanguage,
    required String targetLanguage,
    required double exchangeRate,
    required String baseCurrency,
    required String targetCurrency,
    String? contextPromptBlock,
    void Function(TranslationResult partialResult)? onPartialResult,
  }) async {
    translateCallCount++;
    lastContextPromptBlock = contextPromptBlock;
    if (translateError != null) {
      throw translateError!;
    }
    for (final partial in partialResultsToEmit) {
      onPartialResult?.call(partial);
    }
    return nextResult;
  }

  @override
  Future<String> summarizeConversation({
    required List<Message> messages,
    required String baseLanguage,
    required String targetLanguage,
  }) async {
    summarizeCallCount++;
    return nextSummary;
  }

  @override
  Future<void> dispose() async {}
}

class _ThrowingAudioService extends NativeAudioService {
  _ThrowingAudioService(this.errorToThrow);

  final Object errorToThrow;

  @override
  Future<void> startCapture() async {
    throw errorToThrow;
  }
}

void main() {
  group('ActiveConversationState', () {
    test('isReadOnly is true only when conversation is loaded and not listening', () {
      const initial = ActiveConversationState();
      expect(initial.isReadOnly, isFalse);

      final loadedPaused = ActiveConversationState(
        conversation: Conversation(
          id: 'c1',
          createdAt: DateTime.utc(2026, 1, 1),
          baseLanguage: 'en',
          targetLanguage: 'es',
        ),
        isListening: false,
      );
      expect(loadedPaused.isReadOnly, isTrue);

      final loadedListening = loadedPaused.copyWith(isListening: true);
      expect(loadedListening.isReadOnly, isFalse);
    });
  });

  group('ActiveConversationBloc', () {
    late SettingsRepository settingsRepo;
    late ConversationRepository conversationRepo;
    late _ConfigurableTranslationEngine fakeEngine;
    late StreamController<Float32List> frameStreamController;
    late NativeAudioService audioService;
    late ActiveConversationBloc bloc;

    setUp(() {
      settingsRepo = SettingsRepository(
        settingsSource: LocalMemorySource<AppSettings>(
          bindings: AppSettings.bindings,
        ),
        localExchangeRateSource: LocalMemorySource<ExchangeRateCache>(
          bindings: ExchangeRateCache.bindings,
        ),
        remoteExchangeRateSource: RemoteMemorySource<ExchangeRateCache>(
          bindings: ExchangeRateCache.bindings,
        ),
      );
      conversationRepo = ConversationRepository(
        conversationSource: LocalMemorySource<Conversation>(
          bindings: Conversation.bindings,
        ),
        messageSource: LocalMemorySource<Message>(
          bindings: Message.bindings,
        ),
      );
      fakeEngine = _ConfigurableTranslationEngine();
      frameStreamController = StreamController<Float32List>.broadcast();
      audioService = NativeAudioService(
        vadBuffer: VadBuffer(
          sampleRate: 1000,
          silenceCutoff: const Duration(seconds: 2),
          maxChunkDuration: const Duration(seconds: 10),
        ),
        customFrameStreamProvider: () => frameStreamController.stream,
      );
      bloc = ActiveConversationBloc(
        conversationRepository: conversationRepo,
        settingsRepository: settingsRepo,
        translationEngine: fakeEngine,
        audioService: audioService,
      );
    });

    tearDown(() async {
      await bloc.close();
      await frameStreamController.close();
      await audioService.dispose();
      conversationRepo.close();
      settingsRepo.close();
    });

    test('initialize with null conversationId and autoStartListening: true starts new session', () async {
      await bloc.initialize(conversationId: null, autoStartListening: true);
      expect(bloc.stateValue.conversation, isNotNull);
      expect(bloc.stateValue.isListening, isTrue);
    });

    test('initialize with null conversationId and autoStartListening: false stays idle', () async {
      await bloc.initialize(conversationId: null, autoStartListening: false);
      expect(bloc.stateValue.conversation, isNull);
      expect(bloc.stateValue.isListening, isFalse);
    });

    test('initialize with existing conversationId loads thread', () async {
      final conv = await conversationRepo.createConversation(
        baseLanguage: 'en',
        targetLanguage: 'es',
      );
      await bloc.initialize(
        conversationId: conv.id,
        autoStartListening: false,
      );
      expect(bloc.stateValue.conversation?.id, conv.id);
      expect(bloc.stateValue.isReadOnly, isTrue);
    });

    test('loadConversation with nonexistent ID sets error message', () async {
      await bloc.loadConversation('missing_id', autoStartListening: false);
      expect(bloc.stateValue.conversation, isNull);
      expect(bloc.stateValue.isListening, isFalse);
      expect(bloc.stateValue.error, 'Conversation not found.');
    });

    test('loadConversation with autoStartListening: true starts listening immediately', () async {
      final conv = await conversationRepo.createConversation(
        baseLanguage: 'en',
        targetLanguage: 'es',
      );
      await bloc.loadConversation(conv.id, autoStartListening: true);
      expect(bloc.stateValue.conversation?.id, conv.id);
      expect(bloc.stateValue.isListening, isTrue);
    });

    test('starts new session, translates base and target speech, and persists messages', () async {
      await bloc.startNewSession();
      expect(bloc.stateValue.conversation, isNotNull);
      expect(bloc.stateValue.isListening, isTrue);

      // 1. User speaks in base language (en -> es)
      await bloc.onAudioChunkReceived(
        Float32List.fromList(<double>[0.2, -0.2, 0.3]),
      );

      expect(bloc.stateValue.messages, hasLength(1));
      expect(bloc.stateValue.messages.first.isBaseLanguage, isTrue);
      expect(
        bloc.stateValue.messages.first.translatedText,
        '¿Cuánto cuesta esto?',
      );
      expect(
        bloc.stateValue.conversation?.previewText,
        '¿Cuánto cuesta esto?',
      );

      // 2. Counterpart replies in target language (es -> en)
      fakeEngine.nextResult = const TranslationResult(
        sourceLanguage: 'es',
        originalText: 'Cuesta diez euros',
        translatedText: 'It costs 10 euros (10.87 USD)',
        speechToTextMs: 340,
        translationMs: 210,
        totalDurationMs: 550,
        speechToTextModel: 'Whisper Base (int8)',
        translationModel: 'Gemini 3.8 Flash',
      );
      await bloc.onAudioChunkReceived(
        Float32List.fromList(<double>[0.25, -0.25, 0.2]),
      );

      expect(bloc.stateValue.messages, hasLength(2));
      expect(bloc.stateValue.messages.last.isBaseLanguage, isFalse);
      expect(
        bloc.stateValue.messages.last.translatedText,
        'It costs 10 euros (10.87 USD)',
      );
      expect(bloc.stateValue.messages.last.speechToTextMs, 340);
      expect(bloc.stateValue.messages.last.translationMs, greaterThanOrEqualTo(210));
      expect(bloc.stateValue.messages.last.totalDurationMs, greaterThanOrEqualTo(550));
      expect(
        bloc.stateValue.messages.last.speechToTextModel,
        'Whisper Base (int8)',
      );
      expect(
        bloc.stateValue.messages.last.translationModel,
        'Gemini 3.8 Flash',
      );
    });

    test('recognizes language names and regional BCP-47 tags for isBaseLanguage', () async {
      await bloc.startNewSession();

      // Full language name "English" -> isBaseLanguage: true
      fakeEngine.nextResult = const TranslationResult(
        sourceLanguage: 'English',
        translatedText: 'Hola',
      );
      await bloc.onAudioChunkReceived(Float32List.fromList(<double>[0.2]));
      expect(bloc.stateValue.messages.last.isBaseLanguage, isTrue);

      // Regional code "en-US" -> isBaseLanguage: true
      fakeEngine.nextResult = const TranslationResult(
        sourceLanguage: 'en-US',
        translatedText: 'Buenos días',
      );
      await bloc.onAudioChunkReceived(Float32List.fromList(<double>[0.2]));
      expect(bloc.stateValue.messages.last.isBaseLanguage, isTrue);

      // Target language full name "Spanish" -> isBaseLanguage: false
      fakeEngine.nextResult = const TranslationResult(
        sourceLanguage: 'Spanish',
        translatedText: 'Good morning',
      );
      await bloc.onAudioChunkReceived(Float32List.fromList(<double>[0.2]));
      expect(bloc.stateValue.messages.last.isBaseLanguage, isFalse);

      // Target regional code "es-MX" -> isBaseLanguage: false
      fakeEngine.nextResult = const TranslationResult(
        sourceLanguage: 'es-MX',
        translatedText: 'Thank you',
      );
      await bloc.onAudioChunkReceived(Float32List.fromList(<double>[0.2]));
      expect(bloc.stateValue.messages.last.isBaseLanguage, isFalse);
    });

    test('loads past conversation in read-only mode and resumes listening when requested', () async {
      final conv = await conversationRepo.createConversation(
        baseLanguage: 'en',
        targetLanguage: 'es',
        previewText: 'Hola mundo',
      );
      await conversationRepo.saveMessage(
        Message(
          id: 'msg_1',
          conversationId: conv.id,
          timestamp: DateTime.utc(2026, 1, 1),
          isBaseLanguage: true,
          originalText: 'Hello world',
          translatedText: 'Hola mundo',
        ),
      );

      await bloc.loadConversation(conv.id, autoStartListening: false);
      expect(bloc.stateValue.conversation?.id, conv.id);
      expect(bloc.stateValue.messages, hasLength(1));
      expect(bloc.stateValue.isListening, isFalse);
      expect(bloc.stateValue.isReadOnly, isTrue);

      // Resume listening in the same thread
      await bloc.startListening();
      expect(bloc.stateValue.isListening, isTrue);
      expect(bloc.stateValue.isReadOnly, isFalse);
      expect(bloc.stateValue.conversation?.id, conv.id);
    });

    test('toggleListening switches between listening and paused states', () async {
      await bloc.toggleListening();
      expect(bloc.stateValue.isListening, isTrue);
      expect(bloc.stateValue.conversation, isNotNull);

      await bloc.toggleListening();
      expect(bloc.stateValue.isListening, isFalse);
      expect(bloc.stateValue.amplitude, 0.0);
    });

    test('onAudioChunkReceived ignores empty chunk and auto-creates conversation if null', () async {
      await bloc.onAudioChunkReceived(Float32List(0));
      expect(bloc.stateValue.conversation, isNull);

      await bloc.onAudioChunkReceived(Float32List.fromList(<double>[0.3, 0.3]));
      expect(bloc.stateValue.conversation, isNotNull);
      expect(bloc.stateValue.messages, hasLength(1));
    });

    test('onAudioChunkReceived captures translation engine errors and clears isLoading', () async {
      await bloc.startNewSession();
      fakeEngine.translateError = const FormatException('Model output invalid');

      await bloc.onAudioChunkReceived(Float32List.fromList(<double>[0.2, 0.2]));

      expect(bloc.stateValue.isLoading, isFalse);
      expect(bloc.stateValue.error, contains('Translation failed:'));
      expect(bloc.stateValue.messages, isEmpty);
    });

    test('startListening handles MicrophonePermissionException and AudioCaptureException gracefully', () async {
      final permService = _ThrowingAudioService(
        const MicrophonePermissionException('Mic permission blocked'),
      );
      final permBloc = ActiveConversationBloc(
        conversationRepository: conversationRepo,
        settingsRepository: settingsRepo,
        translationEngine: fakeEngine,
        audioService: permService,
      );

      await permBloc.startListening();
      expect(permBloc.stateValue.isListening, isFalse);
      expect(permBloc.stateValue.error, 'Mic permission blocked');
      await permBloc.close();
      await permService.dispose();

      final captureService = _ThrowingAudioService(
        const AudioCaptureException('Audio hardware unavailable'),
      );
      final captureBloc = ActiveConversationBloc(
        conversationRepository: conversationRepo,
        settingsRepository: settingsRepo,
        translationEngine: fakeEngine,
        audioService: captureService,
      );

      await captureBloc.startListening();
      expect(captureBloc.stateValue.isListening, isFalse);
      expect(captureBloc.stateValue.error, 'Audio hardware unavailable');
      await captureBloc.close();
      await captureService.dispose();
    });

    test('startListening handles translationEngine.initialize() failure gracefully', () async {
      fakeEngine.initializeError = StateError('Gemma 4 model missing');
      await bloc.startListening();

      expect(bloc.stateValue.isListening, isFalse);
      expect(bloc.stateValue.error, contains('Gemma 4 model missing'));
    });

    test('streams live audio frames through VAD into translated messages and updates amplitude', () async {
      await bloc.startNewSession();

      // Push 1s of speech (1000 samples @ 0.1 -> normalized amplitude 0.5)
      frameStreamController.add(
        Float32List.fromList(List<double>.filled(1000, 0.1)),
      );
      await Future<void>.delayed(Duration.zero);
      expect(bloc.stateValue.amplitude, closeTo(0.5, 1e-5));

      // Push 2s of silence to trigger the 2s VAD cutoff configured in setUp
      frameStreamController.add(Float32List(2000));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(bloc.stateValue.messages, hasLength(1));
      expect(
        bloc.stateValue.messages.first.translatedText,
        '¿Cuánto cuesta esto?',
      );

      await bloc.cancelSession();
      expect(bloc.stateValue.isListening, isFalse);
      expect(bloc.stateValue.amplitude, 0.0);
    });

    test('emits streamingTranslatedText and streamingIsBaseLanguage during live translation', () async {
      await settingsRepo.saveSettings(
        const AppSettings(
          baseLanguage: 'en',
          targetLanguage: 'ko',
          baseCurrency: 'USD',
          targetCurrency: 'KRW',
        ),
      );
      await bloc.startNewSession();

      fakeEngine.partialResultsToEmit = const <TranslationResult>[
        TranslationResult(
          sourceLanguage: 'en',
          originalText: 'Where is the subway?',
          translatedText: '지하철이',
        ),
        TranslationResult(
          sourceLanguage: 'en',
          originalText: 'Where is the subway?',
          translatedText: '지하철이 어디에 있나요?',
        ),
      ];
      fakeEngine.nextResult = const TranslationResult(
        sourceLanguage: 'en',
        originalText: 'Where is the subway?',
        translatedText: '지하철이 어디에 있나요?',
      );

      final observedStreamingTexts = <String?>[];
      final observedStreamingRoles = <bool?>[];
      final unsub = bloc.state.subscribe((s) {
        if (s.streamingTranslatedText != null) {
          observedStreamingTexts.add(s.streamingTranslatedText);
          observedStreamingRoles.add(s.streamingIsBaseLanguage);
        }
      });

      await bloc.onAudioChunkReceived(
        Float32List.fromList(<double>[0.2, -0.2, 0.3]),
      );
      unsub();

      expect(
        observedStreamingTexts,
        <String?>['지하철이', '지하철이 어디에 있나요?'],
      );
      expect(observedStreamingRoles, <bool?>[true, true]);
      // Cleared once final message is saved
      expect(bloc.stateValue.streamingTranslatedText, isNull);
      expect(bloc.stateValue.streamingIsBaseLanguage, isNull);
      expect(bloc.stateValue.messages.single.isBaseLanguage, isTrue);
      expect(
        bloc.stateValue.messages.single.translatedText,
        '지하철이 어디에 있나요?',
      );
    });

    test('accurately classifies Host (en->ko) vs Guest (ko->en) even if sourceLanguage was mislabeled', () async {
      await settingsRepo.saveSettings(
        const AppSettings(
          baseLanguage: 'en',
          targetLanguage: 'ko',
          baseCurrency: 'USD',
          targetCurrency: 'KRW',
        ),
      );
      await bloc.startNewSession();

      // 1. Guest spoke Korean, translated to English, but LLM mislabeled sourceLanguage as 'en'
      fakeEngine.nextResult = const TranslationResult(
        sourceLanguage: 'en',
        originalText: '안녕하세요',
        translatedText: 'Hello there, how are you?',
      );
      await bloc.onAudioChunkReceived(Float32List.fromList(<double>[0.25]));
      expect(bloc.stateValue.messages.last.isBaseLanguage, isFalse);

      // 2. Host spoke English, translated to Korean, but LLM mislabeled sourceLanguage as 'ko'
      fakeEngine.nextResult = const TranslationResult(
        sourceLanguage: 'ko',
        originalText: 'Thank you very much',
        translatedText: '정말 감사합니다',
      );
      await bloc.onAudioChunkReceived(Float32List.fromList(<double>[0.25]));
      expect(bloc.stateValue.messages.last.isBaseLanguage, isTrue);
    });

    test('populates all 3 strings (originalText, translatedText, annotatedText) and avoids redundant annotations', () async {
      await settingsRepo.saveSettings(
        const AppSettings(
          baseLanguage: 'en',
          targetLanguage: 'es',
          baseCurrency: 'USD',
          targetCurrency: 'EUR',
        ),
      );
      await bloc.startNewSession();

      // 1. Model missed price and time conversion -> post-processor populates annotatedText
      fakeEngine.nextResult = const TranslationResult(
        sourceLanguage: 'en',
        originalText: r'Dinner is $20 at 7 PM.',
        translatedText: r'La cena cuesta $20 a las 7 PM.',
      );
      await bloc.onAudioChunkReceived(Float32List.fromList(<double>[0.25]));

      final msg1 = bloc.stateValue.messages.last;
      expect(msg1.originalText, r'Dinner is $20 at 7 PM.');
      expect(msg1.translatedText, r'La cena cuesta $20 a las 7 PM.');
      expect(
        msg1.annotatedText,
        r'La cena cuesta $20 (€20.00 EUR) a las 7 PM (19:00).',
      );
      expect(bloc.stateValue.conversation?.previewText, msg1.annotatedText);

      // 2. Model already annotated price and time -> post-processor does not add redundant annotation
      fakeEngine.nextResult = const TranslationResult(
        sourceLanguage: 'en',
        originalText: r'Dinner is $20 at 7 PM.',
        translatedText: r'La cena cuesta $20 (€18.40 EUR) a las 19:00 (7PM).',
      );
      await bloc.onAudioChunkReceived(Float32List.fromList(<double>[0.25]));

      final msg2 = bloc.stateValue.messages.last;
      expect(
        msg2.translatedText,
        r'La cena cuesta $20 (€18.40 EUR) a las 19:00 (7PM).',
      );
      expect(msg2.annotatedText, msg2.translatedText);
    });

    test('deleteCurrentConversation stops listening and removes conversation from repository', () async {
      await bloc.startNewSession();
      final convId = bloc.stateValue.conversation!.id;
      expect(await conversationRepo.getConversationById(convId), isNotNull);

      final deleted = await bloc.deleteCurrentConversation();
      expect(deleted, isTrue);
      expect(bloc.stateValue.conversation, isNull);
      expect(bloc.stateValue.messages, isEmpty);
      expect(bloc.stateValue.isListening, isFalse);
      expect(await conversationRepo.getConversationById(convId), isNull);
    });

    test('onAudioChunkReceived gracefully ignores silent pauses and hallucinated turns without saving messages or setting errors', () async {
      await bloc.startNewSession();

      // 1. A full-length silent audio chunk (1 second at 16kHz of pure silence) is ignored before inference
      await bloc.onAudioChunkReceived(Float32List(16000));
      expect(bloc.stateValue.messages, isEmpty);
      expect(bloc.stateValue.isLoading, isFalse);
      expect(bloc.stateValue.error, isNull);

      // 2. Engine returns empty translation for a conversational pause
      fakeEngine.nextResult = const TranslationResult(
        sourceLanguage: 'en',
        originalText: '',
        translatedText: '',
      );
      await bloc.onAudioChunkReceived(Float32List.fromList(<double>[0.25, -0.25]));
      expect(bloc.stateValue.messages, isEmpty);
      expect(bloc.stateValue.isLoading, isFalse);
      expect(bloc.stateValue.error, isNull);

      // 3. Engine returns "There was no audio file, please provide an audio file."
      fakeEngine.nextResult = const TranslationResult(
        sourceLanguage: 'en',
        originalText: 'There was no audio file, please provide an audio file.',
        translatedText: 'There was no audio file, please provide an audio file.',
      );
      await bloc.onAudioChunkReceived(Float32List.fromList(<double>[0.25, -0.25]));
      expect(bloc.stateValue.messages, isEmpty);
      expect(bloc.stateValue.isLoading, isFalse);
      expect(bloc.stateValue.error, isNull);

      // 4. Engine returns "I am going to the store to buy some milk"
      fakeEngine.nextResult = const TranslationResult(
        sourceLanguage: 'en',
        originalText: 'I am going to the store to buy some milk.',
        translatedText: 'Voy a la tienda a comprar leche.',
      );
      await bloc.onAudioChunkReceived(Float32List.fromList(<double>[0.25, -0.25]));
      expect(bloc.stateValue.messages, isEmpty);
      expect(bloc.stateValue.isLoading, isFalse);
      expect(bloc.stateValue.error, isNull);
    });

    test('exitSession automatically deletes conversation if it is still empty and preserves non-empty conversations', () async {
      // 1. Start a new session and exit without adding any messages -> deleted automatically
      await bloc.startNewSession();
      final emptyConvId = bloc.stateValue.conversation!.id;
      expect(await conversationRepo.getConversationById(emptyConvId), isNotNull);

      final deletedEmpty = await bloc.exitSession();
      expect(deletedEmpty, isTrue);
      expect(bloc.stateValue.conversation, isNull);
      expect(bloc.stateValue.isListening, isFalse);
      expect(await conversationRepo.getConversationById(emptyConvId), isNull);

      // 2. Start a new session, speak 1 message, and exit -> preserved in storage
      await bloc.startNewSession();
      final nonEmptyConvId = bloc.stateValue.conversation!.id;
      await bloc.onAudioChunkReceived(
        Float32List.fromList(<double>[0.25, -0.25, 0.3]),
      );
      expect(bloc.stateValue.messages, hasLength(1));

      final deletedNonEmpty = await bloc.exitSession();
      expect(deletedNonEmpty, isFalse);
      expect(bloc.stateValue.conversation?.id, nonEmptyConvId);
      expect(bloc.stateValue.isListening, isFalse);
      expect(await conversationRepo.getConversationById(nonEmptyConvId), isNotNull);
    });

    test('begins translating as soon as active speech is detected and reuses result when utterance ends', () async {
      await bloc.startNewSession();
      fakeEngine.translateCallCount = 0;
      fakeEngine.nextResult = const TranslationResult(
        sourceLanguage: 'en',
        originalText: 'Where is the station?',
        translatedText: '¿Dónde está la estación?',
      );

      // Push 700ms of active speech (700 samples @ 1kHz >= 600ms liveSnapshotInterval, < 2s silenceCutoff).
      // The utterance has NOT ended yet, but live snapshot translation begins immediately!
      frameStreamController.add(
        Float32List.fromList(List<double>.filled(700, 0.25)),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(fakeEngine.translateCallCount, 1);
      expect(bloc.stateValue.isLoading, isTrue);
      expect(
        bloc.stateValue.streamingTranslatedText,
        '¿Dónde está la estación?',
      );
      expect(bloc.stateValue.streamingIsBaseLanguage, isTrue);
      // Not finalized into messages yet because the speaker hasn't finished the turn
      expect(bloc.stateValue.messages, isEmpty);

      // Now push 2s of trailing silence to finish the utterance.
      // Because no new speech was added after the 700-sample active speech snapshot,
      // onAudioChunkReceived reuses the completed snapshot result without calling translateAudioChunk again!
      frameStreamController.add(Float32List(2000));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(fakeEngine.translateCallCount, 1);
      expect(bloc.stateValue.isLoading, isFalse);
      expect(bloc.stateValue.streamingTranslatedText, isNull);
      expect(bloc.stateValue.messages, hasLength(1));
      expect(
        bloc.stateValue.messages.single.translatedText,
        '¿Dónde está la estación?',
      );
    });

    test('generates and saves 3 to 5 word generatedSummary after each new message and supports manual summary editing', () async {
      await bloc.startNewSession();
      final convId = bloc.stateValue.conversation!.id;

      // 1. First message -> engine summarizes thread into 3-5 words and saves in generatedSummary
      fakeEngine.nextSummary = 'Buying train ticket downtown';
      await bloc.onAudioChunkReceived(
        Float32List.fromList(<double>[0.25, -0.25, 0.3]),
      );

      expect(fakeEngine.summarizeCallCount, 1);
      expect(
        bloc.stateValue.conversation?.generatedSummary,
        'Buying train ticket downtown',
      );
      expect(bloc.stateValue.conversation?.userSummary, isNull);

      final persistedAfterMsg1 = await conversationRepo.getConversationById(
        convId,
      );
      expect(
        persistedAfterMsg1?.generatedSummary,
        'Buying train ticket downtown',
      );

      // 2. Second message -> engine updates generatedSummary
      fakeEngine.nextSummary = 'Train ticket price inquiry';
      await bloc.onAudioChunkReceived(
        Float32List.fromList(<double>[0.3, -0.3, 0.25]),
      );

      expect(fakeEngine.summarizeCallCount, 2);
      expect(
        bloc.stateValue.conversation?.generatedSummary,
        'Train ticket price inquiry',
      );

      // 3. User edits summary via updateSummary -> persisted in generatedSummary and userSummary
      await bloc.updateSummary('Madrid station ticket chat');
      expect(
        bloc.stateValue.conversation?.generatedSummary,
        'Madrid station ticket chat',
      );
      expect(
        bloc.stateValue.conversation?.userSummary,
        'Madrid station ticket chat',
      );

      final persistedAfterEdit = await conversationRepo.getConversationById(
        convId,
      );
      expect(
        persistedAfterEdit?.generatedSummary,
        'Madrid station ticket chat',
      );
      expect(
        persistedAfterEdit?.userSummary,
        'Madrid station ticket chat',
      );
    });

    test('injects situational context presets, custom keywords, and rolling prior turns into translateAudioChunk and records analytics on Message', () async {
      await settingsRepo.saveSettings(
        const AppSettings(
          baseLanguage: 'en',
          targetLanguage: 'es',
          rollingTurnCount: 2,
        ),
      );

      await bloc.initialize(
        autoStartListening: true,
        initialContextIds: const <String>['restaurant'],
        initialCustomKeywords: const <String>['shellfish allergy'],
      );

      expect(
        bloc.stateValue.conversation?.activeContextIds,
        equals(const <String>['restaurant']),
      );
      expect(
        bloc.stateValue.conversation?.customKeywords,
        equals(const <String>['shellfish allergy']),
      );

      // Turn 1: No prior messages yet -> rollingTurnsUsed == 0, context has Restaurant & shellfish allergy
      fakeEngine.nextResult = const TranslationResult(
        sourceLanguage: 'en',
        originalText: 'Does this soup have shellfish?',
        translatedText: '¿Esta sopa tiene mariscos?',
      );
      await bloc.onAudioChunkReceived(
        Float32List.fromList(<double>[0.25, -0.25, 0.3]),
      );

      expect(fakeEngine.lastContextPromptBlock, isNotNull);
      expect(
        fakeEngine.lastContextPromptBlock,
        contains('Restaurant & Dining'),
      );
      expect(
        fakeEngine.lastContextPromptBlock,
        contains('shellfish allergy'),
      );
      expect(
        fakeEngine.lastContextPromptBlock,
        isNot(contains('Recent Conversation History')),
      );

      final msg1 = bloc.stateValue.messages.single;
      expect(
        msg1.activeContextSummary,
        '🍽️ Restaurant & Dining • shellfish allergy',
      );
      expect(msg1.rollingTurnsUsed, 0);

      // Toggle an additional preset ('medical') and add a keyword ('epipen')
      await bloc.toggleContextPreset('medical');
      await bloc.addCustomKeyword('epipen');
      expect(
        bloc.stateValue.conversation?.activeContextIds,
        equals(const <String>['restaurant', 'medical']),
      );
      expect(
        bloc.stateValue.conversation?.customKeywords,
        equals(const <String>['shellfish allergy', 'epipen']),
      );

      // Turn 2: 1 prior message exists -> rollingTurnsUsed == 1, prompt includes Turn 1 original & translated text
      fakeEngine.nextResult = const TranslationResult(
        sourceLanguage: 'es',
        originalText: 'No, solo tiene verduras.',
        translatedText: 'No, it only has vegetables.',
      );
      await bloc.onAudioChunkReceived(
        Float32List.fromList(<double>[0.3, -0.3, 0.25]),
      );

      expect(
        fakeEngine.lastContextPromptBlock,
        contains('Recent Conversation History'),
      );
      expect(
        fakeEngine.lastContextPromptBlock,
        contains('Does this soup have shellfish?'),
      );
      expect(
        fakeEngine.lastContextPromptBlock,
        contains('¿Esta sopa tiene mariscos?'),
      );
      expect(
        fakeEngine.lastContextPromptBlock,
        contains('Medical & Pharmacy'),
      );
      expect(fakeEngine.lastContextPromptBlock, contains('epipen'));

      final msg2 = bloc.stateValue.messages.last;
      expect(
        msg2.activeContextSummary,
        '🍽️ Restaurant & Dining • ⚕️ Medical & Pharmacy • shellfish allergy, epipen',
      );
      expect(msg2.rollingTurnsUsed, 1);

      // Remove custom keyword
      await bloc.removeCustomKeyword('epipen');
      expect(
        bloc.stateValue.conversation?.customKeywords,
        equals(const <String>['shellfish allergy']),
      );
    });

    test('splits rapid multi-language speech in a single audio chunk into separate Left and Right chat bubbles', () async {
      final segEngine = _ConfigurableSegmentedTranslationEngine();
      final segBloc = ActiveConversationBloc(
        conversationRepository: conversationRepo,
        settingsRepository: settingsRepo,
        translationEngine: segEngine,
        audioService: audioService,
      );
      await segBloc.startNewSession();

      segEngine.nextSttResult = const SpeechToTextResult(
        transcript: 'Excuse me, how much is this? Cuesta diez euros.',
        detectedLanguageCode: 'en',
        durationMs: 240,
        modelName: 'Gemma 4',
        segments: <SpeechSegment>[
          SpeechSegment(
            languageCode: 'en',
            text: 'Excuse me, how much is this?',
          ),
          SpeechSegment(
            languageCode: 'es',
            text: 'Cuesta diez euros.',
          ),
        ],
      );
      segEngine.translationsByTranscript['Excuse me, how much is this?'] =
          'Disculpe, ¿cuánto cuesta esto?';
      segEngine.translationsByTranscript['Cuesta diez euros.'] =
          'It costs ten euros.';

      await segBloc.onAudioChunkReceived(
        Float32List.fromList(<double>[0.25, -0.25, 0.3]),
        speechStartTime: DateTime.utc(2026, 10, 25, 12, 0, 0),
        speechEndTime: DateTime.utc(2026, 10, 25, 12, 0, 2),
      );

      expect(segBloc.stateValue.messages, hasLength(2));
      expect(segBloc.stateValue.messages[0].isBaseLanguage, isTrue);
      expect(
        segBloc.stateValue.messages[0].originalText,
        'Excuse me, how much is this?',
      );
      expect(
        segBloc.stateValue.messages[0].translatedText,
        'Disculpe, ¿cuánto cuesta esto?',
      );

      expect(segBloc.stateValue.messages[1].isBaseLanguage, isFalse);
      expect(
        segBloc.stateValue.messages[1].originalText,
        'Cuesta diez euros.',
      );
      expect(
        segBloc.stateValue.messages[1].translatedText,
        'It costs ten euros.',
      );

      await segBloc.close();
    });

    test('auto-clumps consecutive same-language chunks within 4.0s acoustic window and opens new bubble after >4.0s', () async {
      final segEngine = _ConfigurableSegmentedTranslationEngine();
      final segBloc = ActiveConversationBloc(
        conversationRepository: conversationRepo,
        settingsRepository: settingsRepo,
        translationEngine: segEngine,
        audioService: audioService,
      );
      await segBloc.startNewSession();

      // Chunk 1 (t=0.0s .. t=1.2s): "We have a reservation"
      segEngine.nextSttResult = const SpeechToTextResult(
        transcript: 'We have a reservation',
        detectedLanguageCode: 'en',
        durationMs: 180,
        segments: <SpeechSegment>[
          SpeechSegment(languageCode: 'en', text: 'We have a reservation'),
        ],
      );
      segEngine.translationsByTranscript['We have a reservation'] =
          'Tenemos una reservación';

      await segBloc.onAudioChunkReceived(
        Float32List.fromList(<double>[0.25, -0.25]),
        speechStartTime: DateTime.utc(2026, 10, 25, 12, 0, 0),
        speechEndTime: DateTime.utc(2026, 10, 25, 12, 0, 1, 200),
      );

      expect(segBloc.stateValue.messages, hasLength(1));
      final firstId = segBloc.stateValue.messages.single.id;
      expect(
        segBloc.stateValue.messages.single.originalText,
        'We have a reservation',
      );

      // Chunk 2 (t=2.5s .. t=3.8s -> 1.3s acoustic gap <= 4.0s window): "under the name Smith."
      segEngine.nextSttResult = const SpeechToTextResult(
        transcript: 'under the name Smith.',
        detectedLanguageCode: 'en',
        durationMs: 160,
        segments: <SpeechSegment>[
          SpeechSegment(languageCode: 'en', text: 'under the name Smith.'),
        ],
      );
      segEngine.translationsByTranscript['We have a reservation under the name Smith.'] =
          'Tenemos una reservación a nombre de Smith.';

      await segBloc.onAudioChunkReceived(
        Float32List.fromList(<double>[0.25, -0.25]),
        speechStartTime: DateTime.utc(2026, 10, 25, 12, 0, 2, 500),
        speechEndTime: DateTime.utc(2026, 10, 25, 12, 0, 3, 800),
      );

      // Updated in-place in Bubble 1!
      expect(segBloc.stateValue.messages, hasLength(1));
      expect(segBloc.stateValue.messages.single.id, firstId);
      expect(
        segBloc.stateValue.messages.single.originalText,
        'We have a reservation under the name Smith.',
      );
      expect(
        segBloc.stateValue.messages.single.translatedText,
        'Tenemos una reservación a nombre de Smith.',
      );
      expect(segBloc.stateValue.lastClumpedMessageId, firstId);
      expect(segBloc.stateValue.clumpedUpdateCount, 1);

      // Chunk 3 (t=9.0s .. t=10.0s -> 5.2s acoustic gap > 4.0s window): "Can we get two keys?"
      segEngine.nextSttResult = const SpeechToTextResult(
        transcript: 'Can we get two keys?',
        detectedLanguageCode: 'en',
        durationMs: 150,
        segments: <SpeechSegment>[
          SpeechSegment(languageCode: 'en', text: 'Can we get two keys?'),
        ],
      );
      segEngine.translationsByTranscript['Can we get two keys?'] =
          '¿Podemos obtener dos llaves?';

      await segBloc.onAudioChunkReceived(
        Float32List.fromList(<double>[0.25, -0.25]),
        speechStartTime: DateTime.utc(2026, 10, 25, 12, 0, 9),
        speechEndTime: DateTime.utc(2026, 10, 25, 12, 0, 10),
      );

      expect(segBloc.stateValue.messages, hasLength(2));
      expect(
        segBloc.stateValue.messages[1].originalText,
        'Can we get two keys?',
      );

      await segBloc.close();
    });

    test('resolves movie-script continuation across opposite-language interjection: merges in-place when same_sentence is true and forks when false', () async {
      final segEngine = _ConfigurableSegmentedTranslationEngine();
      final segBloc = ActiveConversationBloc(
        conversationRepository: conversationRepo,
        settingsRepository: settingsRepo,
        translationEngine: segEngine,
        audioService: audioService,
      );
      await segBloc.startNewSession();

      // 1. Host starts speaking in English (t=0.0s .. t=1.0s): "Are we too early"
      segEngine.nextSttResult = const SpeechToTextResult(
        transcript: 'Are we too early',
        detectedLanguageCode: 'en',
        durationMs: 150,
        segments: <SpeechSegment>[
          SpeechSegment(languageCode: 'en', text: 'Are we too early'),
        ],
      );
      segEngine.translationsByTranscript['Are we too early'] =
          '¿Llegamos demasiado temprano';

      await segBloc.onAudioChunkReceived(
        Float32List.fromList(<double>[0.25, -0.25]),
        speechStartTime: DateTime.utc(2026, 10, 25, 12, 0, 0),
        speechEndTime: DateTime.utc(2026, 10, 25, 12, 0, 1),
      );

      // 2. Clerk interjects in Spanish (t=1.2s .. t=1.8s): "¡Hola!"
      segEngine.nextSttResult = const SpeechToTextResult(
        transcript: '¡Hola!',
        detectedLanguageCode: 'es',
        durationMs: 120,
        segments: <SpeechSegment>[
          SpeechSegment(languageCode: 'es', text: '¡Hola!'),
        ],
      );
      segEngine.translationsByTranscript['¡Hola!'] = 'Hello!';

      await segBloc.onAudioChunkReceived(
        Float32List.fromList(<double>[0.25, -0.25]),
        speechStartTime: DateTime.utc(2026, 10, 25, 12, 0, 1, 200),
        speechEndTime: DateTime.utc(2026, 10, 25, 12, 0, 1, 800),
      );

      expect(segBloc.stateValue.messages, hasLength(2));
      final englishBubbleId = segBloc.stateValue.messages[0].id;
      final spanishBubbleId = segBloc.stateValue.messages[1].id;

      // 3. Host finishes sentence in English within 4.0s of Part 1 (t=2.0s .. t=3.0s): "to check in?"
      // Movie-script continuation decides isSameSentence == true -> updates Bubble 1 in-place ABOVE "¡Hola!"
      segEngine.nextSttResult = const SpeechToTextResult(
        transcript: 'to check in?',
        detectedLanguageCode: 'en',
        durationMs: 140,
        segments: <SpeechSegment>[
          SpeechSegment(languageCode: 'en', text: 'to check in?'),
        ],
      );
      segEngine.nextContinuationDecision = const ContinuationDecision(
        isSameSentence: true,
        combinedOriginalText: 'Are we too early to check in?',
        result: TranslationResult(
          sourceLanguage: 'en',
          originalText: 'Are we too early to check in?',
          translatedText: '¿Llegamos demasiado temprano para registrarnos?',
          translationMs: 180,
        ),
      );

      await segBloc.onAudioChunkReceived(
        Float32List.fromList(<double>[0.25, -0.25]),
        speechStartTime: DateTime.utc(2026, 10, 25, 12, 0, 2),
        speechEndTime: DateTime.utc(2026, 10, 25, 12, 0, 3),
      );

      expect(segEngine.continuationCallCount, 1);
      expect(segEngine.lastInterveningTurns, hasLength(1));
      expect(segEngine.lastInterveningTurns.single.originalText, '¡Hola!');

      // Still 2 bubbles! Bubble 0 (above "¡Hola!") was updated in-place!
      expect(segBloc.stateValue.messages, hasLength(2));
      expect(segBloc.stateValue.messages[0].id, englishBubbleId);
      expect(
        segBloc.stateValue.messages[0].originalText,
        'Are we too early to check in?',
      );
      expect(
        segBloc.stateValue.messages[0].translatedText,
        '¿Llegamos demasiado temprano para registrarnos?',
      );
      expect(segBloc.stateValue.messages[1].id, spanishBubbleId);
      expect(segBloc.stateValue.lastClumpedMessageId, englishBubbleId);

      // 4. Clerk answers substantive question (t=3.5s .. t=4.8s): "No, su habitación está lista."
      segEngine.nextSttResult = const SpeechToTextResult(
        transcript: 'No, su habitación está lista.',
        detectedLanguageCode: 'es',
        durationMs: 160,
        segments: <SpeechSegment>[
          SpeechSegment(
            languageCode: 'es',
            text: 'No, su habitación está lista.',
          ),
        ],
      );
      segEngine.nextContinuationDecision = const ContinuationDecision(
        isSameSentence: false,
        combinedOriginalText: 'No, su habitación está lista.',
        result: TranslationResult(
          sourceLanguage: 'es',
          originalText: 'No, su habitación está lista.',
          translatedText: 'No, your room is ready.',
          translationMs: 190,
        ),
      );

      await segBloc.onAudioChunkReceived(
        Float32List.fromList(<double>[0.25, -0.25]),
        speechStartTime: DateTime.utc(2026, 10, 25, 12, 0, 3, 500),
        speechEndTime: DateTime.utc(2026, 10, 25, 12, 0, 4, 800),
      );

      // Because isSameSentence == false, a 3rd bubble was appended at the bottom!
      expect(segBloc.stateValue.messages, hasLength(3));
      expect(
        segBloc.stateValue.messages[2].originalText,
        'No, su habitación está lista.',
      );
      expect(
        segBloc.stateValue.messages[2].translatedText,
        'No, your room is ready.',
      );

      await segBloc.close();
    });
  });
}

class _ConfigurableSegmentedTranslationEngine extends _ConfigurableTranslationEngine
    implements SegmentedTranslationEngine {
  SpeechToTextResult nextSttResult = const SpeechToTextResult(
    transcript: 'Hello',
    detectedLanguageCode: 'en',
    durationMs: 100,
  );

  final Map<String, String> translationsByTranscript = <String, String>{};
  ContinuationDecision? nextContinuationDecision;
  int continuationCallCount = 0;
  List<Message> lastInterveningTurns = const <Message>[];

  @override
  Future<SpeechToTextResult> transcribeAudioChunk({
    required Float32List audioWavChunk,
    required String baseLanguage,
    required String targetLanguage,
    String? contextPromptBlock,
  }) async {
    if (translateError != null) {
      throw translateError!;
    }
    return nextSttResult;
  }

  @override
  Future<TranslationResult> translateText({
    required String transcript,
    required String sourceLanguage,
    required String baseLanguage,
    required String targetLanguage,
    required double exchangeRate,
    required String baseCurrency,
    required String targetCurrency,
    int? speechToTextMs,
    String? speechToTextModel,
    String? contextPromptBlock,
    void Function(TranslationResult partialResult)? onPartialResult,
  }) async {
    translateCallCount++;
    lastContextPromptBlock = contextPromptBlock;
    final translated =
        translationsByTranscript[transcript] ?? nextResult.translatedText;
    return TranslationResult(
      sourceLanguage: sourceLanguage,
      originalText: transcript,
      translatedText: translated,
      speechToTextMs: speechToTextMs,
      translationMs: 120,
      totalDurationMs: (speechToTextMs ?? 0) + 120,
      speechToTextModel: speechToTextModel ?? 'Gemma 4',
      translationModel: 'Gemma 4',
    );
  }

  @override
  Future<ContinuationDecision> resolveContinuationAndTranslate({
    required String part1Transcript,
    required String part2Transcript,
    required List<Message> interveningTurns,
    required String sourceLanguage,
    required String baseLanguage,
    required String targetLanguage,
    required double exchangeRate,
    required String baseCurrency,
    required String targetCurrency,
    int? speechToTextMs,
    String? speechToTextModel,
    String? contextPromptBlock,
  }) async {
    continuationCallCount++;
    lastInterveningTurns = interveningTurns;
    if (nextContinuationDecision != null) {
      return nextContinuationDecision!;
    }
    return ContinuationDecision(
      isSameSentence: true,
      combinedOriginalText: '$part1Transcript $part2Transcript',
      result: TranslationResult(
        sourceLanguage: sourceLanguage,
        originalText: '$part1Transcript $part2Transcript',
        translatedText: nextResult.translatedText,
        speechToTextMs: speechToTextMs,
        translationMs: 150,
      ),
    );
  }
}
