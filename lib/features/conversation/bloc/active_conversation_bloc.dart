import 'dart:async';
import 'dart:typed_data';

import 'package:bloc_signals/bloc_signals.dart';
import 'package:translation_app/core/ai/translation_engine.dart';
import 'package:translation_app/core/audio/audio_exceptions.dart';
import 'package:translation_app/core/audio/native_audio_service.dart';
import 'package:translation_app/core/audio/vad_buffer.dart';
import 'package:translation_app/core/data/models/app_settings.dart';
import 'package:translation_app/core/data/models/conversation.dart';
import 'package:translation_app/core/data/models/message.dart';
import 'package:translation_app/core/data/repositories/conversation_repository.dart';
import 'package:translation_app/core/data/repositories/settings_repository.dart';
import 'package:translation_app/core/logging/app_logger.dart';
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

  static final _log = AppLogger.of('ActiveConversationBloc');

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
    _log.info(
      'initialize(conversationId=$conversationId, autoStartListening=$autoStartListening)',
    );
    if (conversationId != null) {
      await loadConversation(
        conversationId,
        autoStartListening: autoStartListening,
      );
    } else if (autoStartListening) {
      await startNewSession();
    } else {
      _log.info('initialize(): staying idle (no conversationId and autoStartListening=false).');
    }
  }

  /// Creates a fresh [Conversation] using current settings and starts listening.
  Future<void> startNewSession() async {
    _log.info('startNewSession() called...');
    emit(stateValue.copyWith(error: null));
    final settings = await _settingsRepository.getSettings();
    final conversation = await _conversationRepository.createConversation(
      baseLanguage: settings.baseLanguage,
      targetLanguage: settings.targetLanguage,
    );
    if (isClosed) return;

    _log.info(
      'Created new conversation id=${conversation.id} '
      '(${conversation.baseLanguage} <-> ${conversation.targetLanguage}).',
    );
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
    _log.info(
      'loadConversation(conversationId=$conversationId, autoStartListening=$autoStartListening)',
    );
    emit(stateValue.copyWith(error: null));
    try {
      final conversation = await _conversationRepository.getConversationById(
        conversationId,
      );
      final messages = await _conversationRepository.getMessagesForConversation(
        conversationId,
      );
      if (isClosed) return;

      _log.info(
        'Loaded conversation id=$conversationId: found=${conversation != null}, '
        'messages=${messages.length}',
      );
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
    } catch (e, st) {
      _log.severe('Failed to load conversation $conversationId', e, st);
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
    _log.info(
      'startListening() called (currentIsListening=${stateValue.isListening}, '
      'targetConversationId=${targetConversation?.id ?? stateValue.conversation?.id})',
    );
    var conversation = targetConversation ?? stateValue.conversation;
    if (conversation == null) {
      final settings = await _settingsRepository.getSettings();
      conversation = await _conversationRepository.createConversation(
        baseLanguage: settings.baseLanguage,
        targetLanguage: settings.targetLanguage,
      );
      if (isClosed) return;
      _log.info('Auto-created conversation id=${conversation.id} for startListening().');
      emit(stateValue.copyWith(conversation: conversation));
    }

    _ensureAudioSubscriptions();

    try {
      _log.info('startListening(): starting NativeAudioService capture...');
      await _audioService.startCapture();
      if (isClosed) return;

      emit(stateValue.copyWith(isListening: true, error: null));
      _log.info(
        'startListening(): microphone capture active (isListening=true). '
        'Initializing TranslationEngine...',
      );

      await _translationEngine.initialize();
      _log.info('startListening(): TranslationEngine initialized and ready.');
    } on MicrophonePermissionException catch (e, st) {
      _log.severe('MicrophonePermissionException in startListening()', e, st);
      await _audioService.stopCapture();
      if (isClosed) return;
      emit(
        stateValue.copyWith(
          isListening: false,
          amplitude: 0.0,
          error: e.message,
        ),
      );
    } on AudioCaptureException catch (e, st) {
      _log.severe('AudioCaptureException in startListening()', e, st);
      await _audioService.stopCapture();
      if (isClosed) return;
      emit(
        stateValue.copyWith(
          isListening: false,
          amplitude: 0.0,
          error: e.message,
        ),
      );
    } catch (e, st) {
      _log.severe('Unexpected error in startListening()', e, st);
      await _audioService.stopCapture();
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
    _log.info('stopListening() called (isListening=${stateValue.isListening})...');
    await _audioService.stopCapture();
    if (isClosed) return;
    emit(stateValue.copyWith(isListening: false, amplitude: 0.0));
    _log.info('stopListening() complete (isListening=false).');
  }

  /// Toggles live microphone capture on or off.
  Future<void> toggleListening() async {
    _log.info(
      'toggleListening() called: current isListening=${stateValue.isListening} -> '
      '${stateValue.isListening ? "stopping" : "starting"}',
    );
    if (stateValue.isListening) {
      await stopListening();
    } else {
      await startListening();
    }
  }

  /// Processes a complete VAD-segmented 16kHz mono PCM audio chunk through
  /// the [TranslationEngine] and saves the resulting [Message].
  Future<void> onAudioChunkReceived(Float32List audioChunk) async {
    if (audioChunk.isEmpty || isClosed) {
      _log.fine(
        'onAudioChunkReceived() ignored (isEmpty=${audioChunk.isEmpty}, isClosed=$isClosed)',
      );
      return;
    }

    final rms = VadBuffer.computeRms(audioChunk);
    final durationSec = (audioChunk.length / 16000.0).toStringAsFixed(2);
    _log.info(
      'onAudioChunkReceived(): received ${audioChunk.length} samples '
      '(~${durationSec}s @ 16kHz, chunkRms=${rms.toStringAsFixed(4)})',
    );

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

      _log.info(
        'onAudioChunkReceived(): invoking translationEngine.translateAudioChunk '
        'for conversation=${conversation.id} '
        '(${settings.baseLanguage}/${settings.baseCurrency} <-> '
        '${settings.targetLanguage}/${settings.targetCurrency}, rate=${exchangeRate.rate})...',
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

      _log.info(
        'onAudioChunkReceived(): translation succeeded! '
        'detectedSource="${result.sourceLanguage}" (isBaseLanguage=$isBaseLanguage), '
        'originalText="${result.originalText}", '
        'translatedText="${result.translatedText}"',
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

      _log.info('Saved translated message id=${savedMessage.id} to local storage.');

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
    } catch (e, st) {
      _log.severe('Translation failed in onAudioChunkReceived()', e, st);
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
    _log.info('cancelSession() called.');
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
        _log.info(
          'audioChunkStream emitted a VAD speech chunk (${chunk.length} samples) -> dispatching to onAudioChunkReceived().',
        );
        unawaited(onAudioChunkReceived(chunk));
      },
      onError: (Object error, StackTrace st) {
        _log.severe('Error on audioChunkStream', error, st);
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
    _log.info('Closing ActiveConversationBloc...');
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
