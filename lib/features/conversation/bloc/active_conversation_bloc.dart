import 'dart:async';
import 'dart:typed_data';

import 'package:bloc_signals/bloc_signals.dart';
import 'package:translation_app/core/ai/translation_engine.dart';
import 'package:translation_app/core/audio/audio_exceptions.dart';
import 'package:translation_app/core/audio/native_audio_service.dart';
import 'package:translation_app/core/data/models/app_settings.dart';
import 'package:translation_app/core/data/models/conversation.dart';
import 'package:translation_app/core/data/models/message.dart';
import 'package:translation_app/core/data/repositories/conversation_repository.dart';
import 'package:translation_app/core/data/repositories/settings_repository.dart';
import 'package:translation_app/features/conversation/bloc/active_conversation_state.dart';

/// Orchestrates live audio capture, VAD speech segmentation, on-device
/// translation via [TranslationEngine], and local conversation persistence.
class ActiveConversationBloc extends CubitSignal<ActiveConversationState> {
  ActiveConversationBloc({
    required this._conversationRepository,
    required this._settingsRepository,
    required this._translationEngine,
    required this._audioService,
  }) : super(initialState: const ActiveConversationState());

  final ConversationRepository _conversationRepository;
  final SettingsRepository _settingsRepository;
  final TranslationEngine _translationEngine;
  final NativeAudioService _audioService;

  StreamSubscription<Float32List>? _speechChunkSub;
  StreamSubscription<double>? _amplitudeSub;

  /// Initializes the session either for an existing [conversationId] or a new
  /// live translation session.
  Future<void> initialize({
    String? conversationId,
    bool autoStartListening = true,
  }) async {
    if (conversationId != null) {
      await loadConversation(
        conversationId,
        autoStartListening: autoStartListening,
      );
    } else if (autoStartListening) {
      await startNewSession();
    }
  }

  /// Creates a fresh [Conversation] using current settings and starts listening.
  Future<void> startNewSession() async {
    emit(stateValue.copyWith(error: null));
    final settings = await _settingsRepository.getSettings();
    final conversation = await _conversationRepository.createConversation(
      baseLanguage: settings.baseLanguage,
      targetLanguage: settings.targetLanguage,
    );
    if (isClosed) return;

    emit(
      stateValue.copyWith(
        conversation: conversation,
        messages: const <Message>[],
        error: null,
      ),
    );

    await startListening(conversation);
  }

  /// Loads an existing [Conversation] and its messages from local storage.
  ///
  /// When [autoStartListening] is `false` (e.g. opened from History or recent
  /// threads), the thread starts in read-only mode until the user taps the
  /// resume microphone button.
  Future<void> loadConversation(
    String conversationId, {
    bool autoStartListening = false,
  }) async {
    emit(stateValue.copyWith(error: null));
    try {
      final conversation = await _conversationRepository.getConversationById(
        conversationId,
      );
      final messages = await _conversationRepository.getMessagesForConversation(
        conversationId,
      );
      if (isClosed) return;

      emit(
        stateValue.copyWith(
          conversation: conversation,
          messages: messages,
          isLoading: false,
          isListening: false,
          error: conversation == null ? 'Conversation not found.' : null,
        ),
      );

      if (autoStartListening && conversation != null) {
        await startListening(conversation);
      }
    } catch (e) {
      if (isClosed) return;
      emit(
        stateValue.copyWith(
          isLoading: false,
          error: 'Failed to load conversation: $e',
        ),
      );
    }
  }

  /// Starts or resumes microphone capture and VAD speech segmentation.
  Future<void> startListening([Conversation? targetConversation]) async {
    var conversation = targetConversation ?? stateValue.conversation;
    if (conversation == null) {
      final settings = await _settingsRepository.getSettings();
      conversation = await _conversationRepository.createConversation(
        baseLanguage: settings.baseLanguage,
        targetLanguage: settings.targetLanguage,
      );
      if (isClosed) return;
      emit(stateValue.copyWith(conversation: conversation));
    }

    _ensureAudioSubscriptions();

    try {
      await _translationEngine.initialize();
      await _audioService.startCapture();
      if (isClosed) return;
      emit(stateValue.copyWith(isListening: true, error: null));
    } on MicrophonePermissionException catch (e) {
      if (isClosed) return;
      emit(
        stateValue.copyWith(
          isListening: false,
          amplitude: 0.0,
          error: e.message,
        ),
      );
    } on AudioCaptureException catch (e) {
      if (isClosed) return;
      emit(
        stateValue.copyWith(
          isListening: false,
          amplitude: 0.0,
          error: e.message,
        ),
      );
    } catch (e) {
      if (isClosed) return;
      emit(
        stateValue.copyWith(
          isListening: false,
          amplitude: 0.0,
          error: 'Microphone error: $e',
        ),
      );
    }
  }

  /// Pauses microphone capture and flushes any buffered speech.
  Future<void> stopListening() async {
    await _audioService.stopCapture();
    if (isClosed) return;
    emit(stateValue.copyWith(isListening: false, amplitude: 0.0));
  }

  /// Toggles live microphone capture on or off.
  Future<void> toggleListening() async {
    if (stateValue.isListening) {
      await stopListening();
    } else {
      await startListening();
    }
  }

  /// Processes a complete VAD-segmented 16kHz mono PCM audio chunk through
  /// the [TranslationEngine] and saves the resulting [Message].
  Future<void> onAudioChunkReceived(Float32List audioChunk) async {
    if (audioChunk.isEmpty || isClosed) return;

    var conversation = stateValue.conversation;
    final settings = await _settingsRepository.getSettings();
    if (conversation == null) {
      conversation = await _conversationRepository.createConversation(
        baseLanguage: settings.baseLanguage,
        targetLanguage: settings.targetLanguage,
      );
      if (isClosed) return;
    }

    emit(
      stateValue.copyWith(
        conversation: conversation,
        isLoading: true,
        error: null,
      ),
    );

    try {
      final exchangeRate = await _settingsRepository.getExchangeRate(
        baseCurrency: settings.baseCurrency,
        targetCurrency: settings.targetCurrency,
      );

      final result = await _translationEngine.translateAudioChunk(
        audioWavChunk: audioChunk,
        baseLanguage: AppSettings.languageNameFor(settings.baseLanguage),
        targetLanguage: AppSettings.languageNameFor(settings.targetLanguage),
        exchangeRate: exchangeRate.rate,
        baseCurrency: settings.baseCurrency,
        targetCurrency: settings.targetCurrency,
      );
      if (isClosed) return;

      final isBaseLanguage = _matchesLanguage(
        detectedLanguage: result.sourceLanguage,
        languageCode: settings.baseLanguage,
        languageName: AppSettings.languageNameFor(settings.baseLanguage),
      );

      final draftMessage = Message(
        id: '',
        conversationId: conversation.id,
        timestamp: DateTime.now(),
        isBaseLanguage: isBaseLanguage,
        originalText: result.originalText ?? '',
        translatedText: result.translatedText,
      );

      final savedMessage = await _conversationRepository.saveMessage(
        draftMessage,
      );
      if (isClosed) return;

      final updatedConversation = conversation.copyWith(
        previewText: result.translatedText,
      );
      final updatedMessages = <Message>[...stateValue.messages, savedMessage];

      emit(
        stateValue.copyWith(
          conversation: updatedConversation,
          messages: updatedMessages,
          isLoading: false,
        ),
      );
    } catch (e) {
      if (isClosed) return;
      emit(
        stateValue.copyWith(
          isLoading: false,
          error: 'Translation failed: $e',
        ),
      );
    }
  }

  /// Stops audio capture and cleans up active session resources.
  Future<void> cancelSession() async {
    await _speechChunkSub?.cancel();
    _speechChunkSub = null;
    await _amplitudeSub?.cancel();
    _amplitudeSub = null;
    await _audioService.stopCapture();
    if (!isClosed) {
      emit(
        stateValue.copyWith(
          isListening: false,
          isLoading: false,
          amplitude: 0.0,
        ),
      );
    }
  }

  void _ensureAudioSubscriptions() {
    _speechChunkSub ??= _audioService.audioChunkStream.listen(
      (chunk) {
        unawaited(onAudioChunkReceived(chunk));
      },
      onError: (Object error) {
        if (!isClosed) {
          emit(
            stateValue.copyWith(
              isListening: false,
              amplitude: 0.0,
              error: error.toString(),
            ),
          );
        }
      },
    );

    _amplitudeSub ??= _audioService.amplitudeStream.listen((rms) {
      if (!isClosed && stateValue.isListening) {
        emit(stateValue.copyWith(amplitude: rms));
      }
    });
  }

  bool _matchesLanguage({
    required String detectedLanguage,
    required String languageCode,
    required String languageName,
  }) {
    final normalized = detectedLanguage.trim().toLowerCase();
    return normalized == languageCode.toLowerCase() ||
        normalized == languageName.toLowerCase() ||
        normalized.startsWith('${languageCode.toLowerCase()}-');
  }

  @override
  Future<void> close() async {
    final chunkSub = _speechChunkSub;
    _speechChunkSub = null;
    final ampSub = _amplitudeSub;
    _amplitudeSub = null;
    if (chunkSub != null) unawaited(chunkSub.cancel());
    if (ampSub != null) unawaited(ampSub.cancel());
    await _audioService.stopCapture();
    return super.close();
  }
}
