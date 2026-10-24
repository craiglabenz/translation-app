import 'dart:async';
import 'dart:typed_data';

import 'package:bloc_signals/bloc_signals.dart';
import 'package:translation_app/core/ai/language_detector.dart';
import 'package:translation_app/core/ai/local_translation_engine.dart';
import 'package:translation_app/core/ai/translation_annotator.dart';
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
  StreamSubscription<Float32List>? _activeSpeechSnapshotSub;
  StreamSubscription<double>? _amplitudeSub;
  Future<bool>? _ongoingExitFuture;

  Float32List? _latestPendingSnapshotChunk;
  Float32List? _inFlightSnapshotChunk;
  Future<TranslationResult?>? _inFlightSnapshotFuture;
  Float32List? _lastCompletedSnapshotChunk;
  TranslationResult? _lastCompletedSnapshotResult;
  bool _isFinalChunkTranslating = false;

  /// Initializes the session either for an existing [conversationId] or a new
  /// live translation session.
  Future<void> initialize({
    String? conversationId,
    bool autoStartListening = true,
  }) async {
    final sw = Stopwatch()..start();
    _log.info(
      '[PERF] ActiveConversationBloc.initialize START '
      '(conversationId=$conversationId, autoStartListening=$autoStartListening)',
    );
    if (conversationId != null) {
      await loadConversation(
        conversationId,
        autoStartListening: autoStartListening,
      );
    } else if (autoStartListening) {
      await startNewSession();
    } else {
      _log.info(
        'initialize(): staying idle (no conversationId and autoStartListening=false).',
      );
    }
    sw.stop();
    _log.info(
      '[PERF] ActiveConversationBloc.initialize FINISH '
      '(${sw.elapsedMilliseconds}ms, conversationId=$conversationId)',
    );
  }

  /// Creates a fresh [Conversation] using current settings and starts listening.
  Future<void> startNewSession() async {
    final sw = Stopwatch()..start();
    _log.info('[PERF] ActiveConversationBloc.startNewSession() START');
    emit(stateValue.copyWith(error: null));
    final settings = await _settingsRepository.getSettings();
    final conversation = await _conversationRepository.createConversation(
      baseLanguage: settings.baseLanguage,
      targetLanguage: settings.targetLanguage,
    );
    if (isClosed) return;

    _log.info(
      '[PERF] startNewSession(): created conversation id=${conversation.id} '
      'in ${sw.elapsedMilliseconds}ms (${conversation.baseLanguage} <-> ${conversation.targetLanguage}).',
    );
    emit(
      stateValue.copyWith(
        conversation: conversation,
        messages: const <Message>[],
        streamingTranslatedText: null,
        streamingIsBaseLanguage: null,
        error: null,
      ),
    );

    await startListening(conversation);
    sw.stop();
    _log.info(
      '[PERF] ActiveConversationBloc.startNewSession() FINISH '
      '(${sw.elapsedMilliseconds}ms)',
    );
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
    final sw = Stopwatch()..start();
    _log.info(
      '[PERF] ActiveConversationBloc.loadConversation START '
      '(conversationId=$conversationId, autoStartListening=$autoStartListening)',
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
        '[PERF] ActiveConversationBloc.loadConversation data fetched '
        '(${sw.elapsedMilliseconds}ms, id=$conversationId, '
        'found=${conversation != null}, messages=${messages.length})',
      );
      emit(
        stateValue.copyWith(
          conversation: conversation,
          messages: messages,
          isLoading: false,
          isListening: false,
          streamingTranslatedText: null,
          streamingIsBaseLanguage: null,
          error: conversation == null ? 'Conversation not found.' : null,
        ),
      );

      if (autoStartListening && conversation != null) {
        await startListening(conversation);
      }
      sw.stop();
      _log.info(
        '[PERF] ActiveConversationBloc.loadConversation FINISH '
        '(${sw.elapsedMilliseconds}ms, id=$conversationId)',
      );
    } catch (e, st) {
      sw.stop();
      _log.severe(
        '[PERF] Failed to load conversation $conversationId (${sw.elapsedMilliseconds}ms)',
        e,
        st,
      );
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
    final sw = Stopwatch()..start();
    _log.info(
      '[PERF] ActiveConversationBloc.startListening() START '
      '(currentIsListening=${stateValue.isListening}, '
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
      _log.info(
        'Auto-created conversation id=${conversation.id} for startListening().',
      );
      emit(stateValue.copyWith(conversation: conversation));
    }

    _ensureAudioSubscriptions();

    try {
      final audioSw = Stopwatch()..start();
      _log.info(
        '[PERF] startListening(): NativeAudioService.startCapture() START...',
      );
      await _audioService.startCapture();
      audioSw.stop();
      _log.info(
        '[PERF] startListening(): NativeAudioService.startCapture() FINISH '
        '(${audioSw.elapsedMilliseconds}ms)',
      );
      if (isClosed) return;

      emit(stateValue.copyWith(isListening: true, error: null));

      final engineSw = Stopwatch()..start();
      _log.info(
        '[PERF] startListening(): TranslationEngine.initialize() START...',
      );
      await _translationEngine.initialize();
      engineSw.stop();
      sw.stop();
      _log.info(
        '[PERF] startListening(): TranslationEngine.initialize() FINISH '
        '(${engineSw.elapsedMilliseconds}ms; total startListening=${sw.elapsedMilliseconds}ms)',
      );
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
    _log.info(
      'stopListening() called (isListening=${stateValue.isListening})...',
    );
    _latestPendingSnapshotChunk = null;
    await _audioService.stopCapture();
    if (isClosed) return;
    if (!_isFinalChunkTranslating) {
      _lastCompletedSnapshotChunk = null;
      _lastCompletedSnapshotResult = null;
      emit(
        stateValue.copyWith(
          isListening: false,
          isLoading: false,
          amplitude: 0.0,
          streamingTranslatedText: null,
          streamingIsBaseLanguage: null,
        ),
      );
    } else {
      emit(stateValue.copyWith(isListening: false, amplitude: 0.0));
    }
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

  /// Translates a cumulative live active-speech snapshot while the user is
  /// still speaking (or during a brief pause before the full VAD silence
  /// cutoff expires), streaming the in-progress translation into the UI.
  ///
  /// Concurrent snapshots are coalesced so only the latest snapshot runs next.
  Future<void> onActiveSpeechSnapshotReceived(
    Float32List snapshotChunk,
  ) async {
    if (snapshotChunk.isEmpty ||
        isClosed ||
        _isFinalChunkTranslating) {
      return;
    }

    if (snapshotChunk.length >= 4000 &&
        !VadBuffer.hasMeaningfulSpeech(
          snapshotChunk,
          sampleRate: _audioService.vadBuffer.sampleRate,
        )) {
      return;
    }

    if (_inFlightSnapshotFuture != null) {
      _latestPendingSnapshotChunk = snapshotChunk;
      _log.info(
        'onActiveSpeechSnapshotReceived(): coalescing ${snapshotChunk.length}-sample '
        'snapshot behind in-flight snapshot inference.',
      );
      return;
    }

    _latestPendingSnapshotChunk = snapshotChunk;
    while (_latestPendingSnapshotChunk != null &&
        !isClosed &&
        !_isFinalChunkTranslating) {
      final chunk = _latestPendingSnapshotChunk!;
      _latestPendingSnapshotChunk = null;
      _inFlightSnapshotChunk = chunk;
      final future = _translateLiveSnapshot(chunk);
      _inFlightSnapshotFuture = future;
      try {
        await future;
      } finally {
        if (identical(_inFlightSnapshotFuture, future)) {
          _inFlightSnapshotFuture = null;
          _inFlightSnapshotChunk = null;
        }
      }
    }
  }

  Future<TranslationResult?> _translateLiveSnapshot(
    Float32List snapshotChunk,
  ) async {
    try {
      var conversation = stateValue.conversation;
      final settings = await _settingsRepository.getSettings();
      if (conversation == null) {
        conversation = await _conversationRepository.createConversation(
          baseLanguage: settings.baseLanguage,
          targetLanguage: settings.targetLanguage,
        );
        if (isClosed) return null;
      }

      if (!_isFinalChunkTranslating) {
        emit(
          stateValue.copyWith(
            conversation: conversation,
            isLoading: true,
            error: null,
          ),
        );
      }

      final exchangeRate = await _settingsRepository.getExchangeRate(
        baseCurrency: settings.baseCurrency,
        targetCurrency: settings.targetCurrency,
      );
      if (isClosed) return null;

      final durationSec =
          (snapshotChunk.length / _audioService.vadBuffer.sampleRate)
              .toStringAsFixed(2);
      _log.info(
        '_translateLiveSnapshot(): starting early translation on active speech '
        '(${snapshotChunk.length} samples / ~${durationSec}s)...',
      );

      final result = await _translationEngine.translateAudioChunk(
        audioWavChunk: snapshotChunk,
        baseLanguage: AppSettings.languageNameFor(settings.baseLanguage),
        targetLanguage: AppSettings.languageNameFor(settings.targetLanguage),
        exchangeRate: exchangeRate.rate,
        baseCurrency: settings.baseCurrency,
        targetCurrency: settings.targetCurrency,
        onPartialResult: (partial) {
          if (isClosed || _isFinalChunkTranslating) return;
          if (partial.translatedText.trim().isEmpty) return;
          final partialIsBase = _resolveIsBaseLanguage(
            result: partial,
            baseLanguageCode: settings.baseLanguage,
            targetLanguageCode: settings.targetLanguage,
          );
          emit(
            stateValue.copyWith(
              conversation: conversation,
              isLoading: true,
              streamingTranslatedText: partial.translatedText,
              streamingIsBaseLanguage: partialIsBase,
            ),
          );
        },
      );
      if (isClosed) return null;

      _lastCompletedSnapshotChunk = snapshotChunk;
      _lastCompletedSnapshotResult = result;

      if (result.translatedText.trim().isEmpty ||
          LocalTranslationEngine.isNonSpeechOrHallucination(
            originalText: result.originalText,
            translatedText: result.translatedText,
          )) {
        if (!_isFinalChunkTranslating && _latestPendingSnapshotChunk == null) {
          emit(
            stateValue.copyWith(
              isLoading: false,
              streamingTranslatedText: null,
              streamingIsBaseLanguage: null,
            ),
          );
        }
        return result;
      }

      final isBaseLanguage = _resolveIsBaseLanguage(
        result: result,
        baseLanguageCode: settings.baseLanguage,
        targetLanguageCode: settings.targetLanguage,
      );
      final annotatedText = TranslationAnnotator.annotate(
        originalText: result.originalText?.trim() ?? '',
        translatedText: result.translatedText.trim(),
        exchangeRate: exchangeRate.rate,
        baseCurrency: settings.baseCurrency,
        targetCurrency: settings.targetCurrency,
        isBaseLanguage: isBaseLanguage,
      );

      if (!_isFinalChunkTranslating) {
        emit(
          stateValue.copyWith(
            conversation: conversation,
            isLoading: true,
            streamingTranslatedText: annotatedText,
            streamingIsBaseLanguage: isBaseLanguage,
          ),
        );
      }

      return result;
    } catch (e, st) {
      _log.warning('Live snapshot translation failed (non-fatal): $e', e, st);
      return null;
    }
  }

  /// Returns `true` when [snapshotChunk] is a prefix of [finalChunk] and any
  /// trailing samples in [finalChunk] after [snapshotChunk] contain only
  /// trailing silence (no additional active speech).
  bool _hasSameActiveSpeech(
    Float32List snapshotChunk,
    Float32List finalChunk,
  ) {
    if (snapshotChunk.isEmpty || finalChunk.length < snapshotChunk.length) {
      return false;
    }
    for (var i = 0; i < snapshotChunk.length; i++) {
      if (snapshotChunk[i] != finalChunk[i]) {
        return false;
      }
    }
    if (finalChunk.length == snapshotChunk.length) {
      return true;
    }
    final tail = Float32List.sublistView(finalChunk, snapshotChunk.length);
    final threshold = _audioService.vadBuffer.silenceThreshold;
    if (VadBuffer.computeRms(tail) >= threshold) {
      return false;
    }
    return !VadBuffer.hasMeaningfulSpeech(
      tail,
      silenceThreshold: threshold,
      sampleRate: _audioService.vadBuffer.sampleRate,
    );
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

    if (audioChunk.length >= 4000 &&
        !VadBuffer.hasMeaningfulSpeech(
          audioChunk,
          sampleRate: _audioService.vadBuffer.sampleRate,
        )) {
      _log.info(
        'onAudioChunkReceived(): chunk contains only pause/silence or transient noise -> ignoring gracefully.',
      );
      return;
    }

    _isFinalChunkTranslating = true;
    _latestPendingSnapshotChunk = null;

    try {
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

      final exchangeRate = await _settingsRepository.getExchangeRate(
        baseCurrency: settings.baseCurrency,
        targetCurrency: settings.targetCurrency,
      );

      TranslationResult? result;
      final inFlightFuture = _inFlightSnapshotFuture;
      final inFlightChunk = _inFlightSnapshotChunk;
      final stepSw = Stopwatch()..start();

      if (inFlightFuture != null &&
          inFlightChunk != null &&
          _hasSameActiveSpeech(inFlightChunk, audioChunk)) {
        _log.info(
          'onAudioChunkReceived(): joining in-flight active-speech snapshot '
          '(${inFlightChunk.length} active samples) for final utterance...',
        );
        result = await inFlightFuture;
      } else {
        if (inFlightFuture != null) {
          await inFlightFuture;
        }
        final completedChunk = _lastCompletedSnapshotChunk;
        final completedResult = _lastCompletedSnapshotResult;
        if (completedChunk != null &&
            completedResult != null &&
            _hasSameActiveSpeech(completedChunk, audioChunk)) {
          _log.info(
            'onAudioChunkReceived(): reusing completed active-speech snapshot '
            'result (${completedChunk.length} active samples) with zero extra inference!',
          );
          result = completedResult;
        }
      }

      if (isClosed) return;

      if (result == null) {
        _log.info(
          'onAudioChunkReceived(): invoking translationEngine.translateAudioChunk '
          'for conversation=${conversation.id} '
          '(${settings.baseLanguage}/${settings.baseCurrency} <-> '
          '${settings.targetLanguage}/${settings.targetCurrency}, rate=${exchangeRate.rate})...',
        );

        result = await _translationEngine.translateAudioChunk(
          audioWavChunk: audioChunk,
          baseLanguage: AppSettings.languageNameFor(settings.baseLanguage),
          targetLanguage: AppSettings.languageNameFor(settings.targetLanguage),
          exchangeRate: exchangeRate.rate,
          baseCurrency: settings.baseCurrency,
          targetCurrency: settings.targetCurrency,
          onPartialResult: (partial) {
            if (isClosed || !stateValue.isLoading) return;
            final partialIsBase = _resolveIsBaseLanguage(
              result: partial,
              baseLanguageCode: settings.baseLanguage,
              targetLanguageCode: settings.targetLanguage,
            );
            emit(
              stateValue.copyWith(
                streamingTranslatedText: partial.translatedText,
                streamingIsBaseLanguage: partialIsBase,
              ),
            );
          },
        );
      }
      final engineElapsedMs = stepSw.elapsedMilliseconds;
      if (isClosed) return;

      if (result.translatedText.trim().isEmpty ||
          LocalTranslationEngine.isNonSpeechOrHallucination(
            originalText: result.originalText,
            translatedText: result.translatedText,
          )) {
        _log.info(
          'onAudioChunkReceived(): pause / no speech detected in turn '
          '(original="${result.originalText}", translated="${result.translatedText}") '
          '-> returning to listening state without adding a message.',
        );
        emit(
          stateValue.copyWith(
            isLoading: false,
            streamingTranslatedText: null,
            streamingIsBaseLanguage: null,
            error: null,
          ),
        );
        return;
      }

      final postProcessSw = Stopwatch()..start();
      final isBaseLanguage = _resolveIsBaseLanguage(
        result: result,
        baseLanguageCode: settings.baseLanguage,
        targetLanguageCode: settings.targetLanguage,
      );

      final rawOriginal = result.originalText?.trim() ?? '';
      final rawTranslated = result.translatedText.trim();
      final annotatedText = TranslationAnnotator.annotate(
        originalText: rawOriginal,
        translatedText: rawTranslated,
        exchangeRate: exchangeRate.rate,
        baseCurrency: settings.baseCurrency,
        targetCurrency: settings.targetCurrency,
        isBaseLanguage: isBaseLanguage,
      );
      postProcessSw.stop();
      stepSw.stop();

      final speechToTextMs = result.speechToTextMs ?? engineElapsedMs;
      final translationMs =
          (result.translationMs ?? 0) + postProcessSw.elapsedMilliseconds;
      final totalDurationMs =
          result.totalDurationMs != null
              ? result.totalDurationMs! + postProcessSw.elapsedMilliseconds
              : (speechToTextMs + translationMs);
      final speechToTextModel =
          result.speechToTextModel ?? settings.activeSttModelDisplayName;
      final translationModel =
          result.translationModel ?? settings.activeTranslationModelDisplayName;

      _log.info(
        'onAudioChunkReceived(): translation succeeded! '
        'detectedSource="${result.sourceLanguage}" (isBaseLanguage=$isBaseLanguage -> '
        '${isBaseLanguage ? "Host/LEFT" : "Guest/RIGHT"}), '
        'originalText="$rawOriginal", '
        'translatedText="$rawTranslated", '
        'annotatedText="$annotatedText", '
        'models=(stt=$speechToTextModel, translation=$translationModel), '
        'timing=(stt=${speechToTextMs}ms, translation=${translationMs}ms, total=${totalDurationMs}ms)',
      );

      final draftMessage = Message(
        id: '',
        conversationId: conversation.id,
        timestamp: DateTime.now(),
        isBaseLanguage: isBaseLanguage,
        originalText: rawOriginal,
        translatedText: rawTranslated,
        annotatedText: annotatedText,
        speechToTextMs: speechToTextMs,
        translationMs: translationMs,
        totalDurationMs: totalDurationMs,
        speechToTextModel: speechToTextModel,
        translationModel: translationModel,
      );

      final savedMessage = await _conversationRepository.saveMessage(
        draftMessage,
      );
      if (isClosed) return;

      _log.info(
        'Saved translated message id=${savedMessage.id} to local storage.',
      );

      final updatedConversation = conversation.copyWith(
        previewText: annotatedText,
      );
      final updatedMessages = <Message>[...stateValue.messages, savedMessage];

      emit(
        stateValue.copyWith(
          conversation: updatedConversation,
          messages: updatedMessages,
          isLoading: false,
          streamingTranslatedText: null,
          streamingIsBaseLanguage: null,
        ),
      );

      await _updateGeneratedSummary(
        conversation: updatedConversation,
        messages: updatedMessages,
        settings: settings,
      );
    } catch (e, st) {
      _log.severe('Translation failed in onAudioChunkReceived()', e, st);
      if (isClosed) return;
      emit(
        stateValue.copyWith(
          isLoading: false,
          streamingTranslatedText: null,
          streamingIsBaseLanguage: null,
          error: 'Translation failed: $e',
        ),
      );
    } finally {
      _isFinalChunkTranslating = false;
      _lastCompletedSnapshotChunk = null;
      _lastCompletedSnapshotResult = null;
    }
  }

  Future<void> _updateGeneratedSummary({
    required Conversation conversation,
    required List<Message> messages,
    required AppSettings settings,
  }) async {
    try {
      final effectiveBaseLang = conversation.baseLanguage.trim().isNotEmpty
          ? conversation.baseLanguage
          : settings.baseLanguage;
      final effectiveTargetLang = conversation.targetLanguage.trim().isNotEmpty
          ? conversation.targetLanguage
          : settings.targetLanguage;
      final summary = await _translationEngine.summarizeConversation(
        messages: messages,
        baseLanguage: AppSettings.languageNameFor(effectiveBaseLang),
        targetLanguage: AppSettings.languageNameFor(effectiveTargetLang),
      );
      if (isClosed) return;
      final trimmedSummary = summary.trim();
      if (trimmedSummary.isEmpty) return;

      final currentConv = stateValue.conversation ?? conversation;
      final convWithSummary = currentConv.copyWith(
        generatedSummary: trimmedSummary,
      );
      final savedConv = await _conversationRepository.updateConversation(
        convWithSummary,
      );
      if (isClosed) return;
      emit(stateValue.copyWith(conversation: savedConv));
    } catch (e, st) {
      _log.warning('Failed to generate conversation summary: $e', e, st);
    }
  }

  /// Updates the conversation summary when edited by the user on the chat
  /// detail screen, persisting the new summary in [Conversation.generatedSummary]
  /// and [Conversation.userSummary].
  Future<void> updateSummary(String newSummary) async {
    final trimmed = newSummary.trim();
    if (trimmed.isEmpty) return;
    final currentConv = stateValue.conversation;
    if (currentConv == null || currentConv.id.isEmpty) return;

    _log.info(
      'updateSummary(): updating summary for conversation=${currentConv.id} to "$trimmed"',
    );
    final updated = currentConv.copyWith(
      generatedSummary: trimmed,
      userSummary: trimmed,
    );
    final saved = await _conversationRepository.updateConversation(updated);
    if (!isClosed) {
      emit(stateValue.copyWith(conversation: saved));
    }
  }

  /// Deletes the currently active or loaded conversation from local storage.
  Future<bool> deleteCurrentConversation() async {
    final currentConv = stateValue.conversation;
    if (currentConv == null || currentConv.id.isEmpty) {
      return false;
    }
    _log.info('deleteCurrentConversation(): deleting id=${currentConv.id}...');
    await stopListening();
    await _conversationRepository.deleteConversation(currentConv.id);
    if (!isClosed) {
      emit(
        stateValue.copyWith(
          conversation: null,
          messages: const <Message>[],
          isListening: false,
          isLoading: false,
          amplitude: 0.0,
          streamingTranslatedText: null,
          streamingIsBaseLanguage: null,
        ),
      );
    }
    return true;
  }

  /// Stops audio capture, cleans up active session resources, and automatically
  /// deletes the current [Conversation] if it still has no messages upon exit.
  ///
  /// Returns `true` if an empty conversation was deleted.
  Future<bool> exitSession() {
    final inFlight = _ongoingExitFuture;
    if (inFlight != null) return inFlight;
    final future = _performExitSession();
    _ongoingExitFuture = future;
    return future.whenComplete(() {
      if (identical(_ongoingExitFuture, future)) {
        _ongoingExitFuture = null;
      }
    });
  }

  Future<bool> _performExitSession() async {
    _log.info('exitSession() called.');
    _latestPendingSnapshotChunk = null;
    _lastCompletedSnapshotChunk = null;
    _lastCompletedSnapshotResult = null;
    final chunkSub = _speechChunkSub;
    _speechChunkSub = null;
    final snapSub = _activeSpeechSnapshotSub;
    _activeSpeechSnapshotSub = null;
    final ampSub = _amplitudeSub;
    _amplitudeSub = null;
    if (chunkSub != null) unawaited(chunkSub.cancel());
    if (snapSub != null) unawaited(snapSub.cancel());
    if (ampSub != null) unawaited(ampSub.cancel());
    await _audioService.stopCapture();

    final currentConv = stateValue.conversation;
    var deletedEmpty = false;
    if (currentConv != null &&
        currentConv.id.isNotEmpty &&
        stateValue.messages.isEmpty) {
      final persistedMessages = await _conversationRepository
          .getMessagesForConversation(currentConv.id);
      if (persistedMessages.isEmpty) {
        _log.info(
          'exitSession(): conversation id=${currentConv.id} is empty (0 messages) -> automatically deleting upon exit.',
        );
        await _conversationRepository.deleteConversation(currentConv.id);
        deletedEmpty = true;
      }
    }

    if (!isClosed) {
      emit(
        stateValue.copyWith(
          conversation: deletedEmpty ? null : currentConv,
          isListening: false,
          isLoading: false,
          amplitude: 0.0,
          streamingTranslatedText: null,
          streamingIsBaseLanguage: null,
        ),
      );
    }
    return deletedEmpty;
  }

  /// Stops audio capture and cleans up active session resources, deleting the
  /// conversation if it is still empty.
  Future<void> cancelSession() async {
    _log.info('cancelSession() called.');
    await exitSession();
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

    _activeSpeechSnapshotSub ??= _audioService.activeSpeechSnapshotStream.listen(
      (snapshotChunk) {
        _log.info(
          'activeSpeechSnapshotStream emitted a live speech snapshot (${snapshotChunk.length} samples) -> dispatching to onActiveSpeechSnapshotReceived().',
        );
        unawaited(onActiveSpeechSnapshotReceived(snapshotChunk));
      },
      onError: (Object error, StackTrace st) {
        _log.warning('Error on activeSpeechSnapshotStream', error, st);
      },
    );

    _amplitudeSub ??= _audioService.amplitudeStream.listen((rms) {
      if (!isClosed && stateValue.isListening) {
        emit(stateValue.copyWith(amplitude: rms));
      }
    });
  }

  bool _resolveIsBaseLanguage({
    required TranslationResult result,
    required String baseLanguageCode,
    required String targetLanguageCode,
  }) {
    final analysis = LanguageDetector.analyzeTranslation(
      result: result,
      baseLanguage: baseLanguageCode,
      targetLanguage: targetLanguageCode,
    );
    if (!analysis.needsFallbackTranslation &&
        (analysis.detectedTranslatedCode != null ||
            analysis.detectedOriginalCode != null)) {
      return analysis.isBaseLanguage;
    }
    return _matchesLanguage(
      detectedLanguage: result.sourceLanguage,
      languageCode: baseLanguageCode,
      languageName: AppSettings.languageNameFor(baseLanguageCode),
    );
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
    await exitSession();
    return super.close();
  }
}
