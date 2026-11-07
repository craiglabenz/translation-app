import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bloc_signals/bloc_signals.dart';
import 'package:translation_app/core/ai/language_detector.dart';
import 'package:translation_app/core/ai/local_translation_engine.dart';
import 'package:translation_app/core/ai/prompt_templates.dart';
import 'package:translation_app/core/ai/speech_to_text_engine.dart';
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
    Duration? languageClumpingWindow,
  }) : languageClumpingWindow =
           languageClumpingWindow ?? defaultLanguageClumpingWindow,
       super(initialState: const ActiveConversationState());

  static final _log = AppLogger.of('ActiveConversationBloc');

  /// Maximum acoustic gap between the end of one speech chunk in Language A
  /// and the start of the next speech chunk in Language A for the two chunks
  /// to be considered candidates for same-sentence clumping or continuation.
  static const Duration defaultLanguageClumpingWindow = Duration(seconds: 4);

  final ConversationRepository _conversationRepository;
  final SettingsRepository _settingsRepository;
  final TranslationEngine _translationEngine;
  final NativeAudioService _audioService;
  final Duration languageClumpingWindow;

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

  final List<_LockedClauseSegment> _lockedClauses = <_LockedClauseSegment>[];
  int _clauseStartSampleOffset = 0;
  int _lastTranslatedSampleOffset = 0;
  Float32List? _utteranceAnchorSamples;
  Float32List? _activeClauseChunk;
  TranslationResult? _activeClauseResult;
  String? _activeClauseAnnotatedText;
  bool? _activeClauseIsBaseLanguage;
  String? _currentClauseStreamingPartialText;

  List<String> _pendingContextIds = const <String>[];
  List<String> _pendingCustomKeywords = const <String>[];

  final Queue<_QueuedAudioChunk> _pendingChunkQueue =
      Queue<_QueuedAudioChunk>();
  bool _isDrainingChunkQueue = false;
  int _cancelEpoch = 0;

  final _LanguageRunningClockState _baseLanguageClock =
      _LanguageRunningClockState();
  final _LanguageRunningClockState _targetLanguageClock =
      _LanguageRunningClockState();

  static final RegExp _terminalClausePunctuation = RegExp(
    r'[.?!。？！;:)）\]"' "'" r']\s*$',
  );

  bool get _hasRenderedUtteranceText =>
      _lockedClauses.isNotEmpty ||
      (_activeClauseAnnotatedText != null &&
          _activeClauseAnnotatedText!.trim().isNotEmpty) ||
      (stateValue.streamingTranslatedText != null &&
          stateValue.streamingTranslatedText!.trim().isNotEmpty);

  void _resetLanguageClocks() {
    _baseLanguageClock.reset();
    _targetLanguageClock.reset();
  }

  void _resetUtteranceClauseState() {
    _lockedClauses.clear();
    _clauseStartSampleOffset = 0;
    _lastTranslatedSampleOffset = 0;
    _utteranceAnchorSamples = null;
    _activeClauseChunk = null;
    _activeClauseResult = null;
    _activeClauseAnnotatedText = null;
    _activeClauseIsBaseLanguage = null;
    _currentClauseStreamingPartialText = null;
    _lastCompletedSnapshotChunk = null;
    _lastCompletedSnapshotResult = null;
  }

  /// Initializes the session either for an existing [conversationId] or a new
  /// live translation session.
  Future<void> initialize({
    String? conversationId,
    bool autoStartListening = true,
    List<String> initialContextIds = const <String>[],
    List<String> initialCustomKeywords = const <String>[],
  }) async {
    final sw = Stopwatch()..start();
    _log.info(
      '[PERF] ActiveConversationBloc.initialize START '
      '(conversationId=$conversationId, autoStartListening=$autoStartListening, '
      'initialContextIds=$initialContextIds, initialCustomKeywords=$initialCustomKeywords)',
    );
    _pendingContextIds = List<String>.unmodifiable(initialContextIds);
    _pendingCustomKeywords = List<String>.unmodifiable(initialCustomKeywords);
    if (conversationId != null) {
      await loadConversation(
        conversationId,
        autoStartListening: autoStartListening,
      );
    } else if (autoStartListening) {
      await startNewSession(
        initialContextIds: initialContextIds,
        initialCustomKeywords: initialCustomKeywords,
      );
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
  Future<void> startNewSession({
    List<String>? initialContextIds,
    List<String>? initialCustomKeywords,
  }) async {
    final sw = Stopwatch()..start();
    _log.info('[PERF] ActiveConversationBloc.startNewSession() START');
    _resetLanguageClocks();
    emit(stateValue.copyWith(error: null));
    final settings = await _settingsRepository.getSettings();
    final effectiveContextIds = initialContextIds ?? _pendingContextIds;
    final effectiveCustomKeywords =
        initialCustomKeywords ?? _pendingCustomKeywords;
    final conversation = await _conversationRepository.createConversation(
      baseLanguage: settings.baseLanguage,
      targetLanguage: settings.targetLanguage,
      activeContextIds: effectiveContextIds,
      customKeywords: effectiveCustomKeywords,
    );
    if (isClosed) return;

    _log.info(
      '[PERF] startNewSession(): created conversation id=${conversation.id} '
      'in ${sw.elapsedMilliseconds}ms (${conversation.baseLanguage} <-> ${conversation.targetLanguage}, '
      'contexts=${conversation.activeContextIds}, keywords=${conversation.customKeywords}).',
    );
    _resetUtteranceClauseState();
    emit(
      stateValue.copyWith(
        conversation: conversation,
        messages: const <Message>[],
        streamingTranslatedText: null,
        streamingIsBaseLanguage: null,
        lastClumpedMessageId: null,
        error: null,
      ),
    );

    if (settings.micControlMode == MicControlMode.pushToTalk) {
      await startStandby(conversation);
    } else {
      await startListening(conversation);
    }
    sw.stop();
    _log.info(
      '[PERF] ActiveConversationBloc.startNewSession() FINISH '
      '(${sw.elapsedMilliseconds}ms, mode=${settings.micControlMode})',
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
    _resetLanguageClocks();
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
      _resetUtteranceClauseState();
      emit(
        stateValue.copyWith(
          conversation: conversation,
          messages: messages,
          isLoading: false,
          isListening: false,
          streamingTranslatedText: null,
          streamingIsBaseLanguage: null,
          lastClumpedMessageId: null,
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
  ///
  /// When [bypassOnsetGate] is `true` (e.g. during an explicit Push-to-Talk
  /// gesture), promotes the 1.5–2.0s rolling pre-roll buffer and bypasses
  /// strict near-field onset hysteresis for the turn.
  Future<void> startListening([
    Conversation? targetConversation,
    bool bypassOnsetGate = false,
  ]) async {
    final sw = Stopwatch()..start();
    _log.info(
      '[PERF] ActiveConversationBloc.startListening() START '
      '(currentIsListening=${stateValue.isListening}, bypassOnsetGate=$bypassOnsetGate, '
      'targetConversationId=${targetConversation?.id ?? stateValue.conversation?.id})',
    );
    var conversation = targetConversation ?? stateValue.conversation;
    if (conversation == null) {
      final settings = await _settingsRepository.getSettings();
      conversation = await _conversationRepository.createConversation(
        baseLanguage: settings.baseLanguage,
        targetLanguage: settings.targetLanguage,
        activeContextIds: _pendingContextIds,
        customKeywords: _pendingCustomKeywords,
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
      if (bypassOnsetGate) {
        await _audioService.startPushToTalkCapture();
      } else {
        await _audioService.startCapture();
      }
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

  /// Starts hardware microphone capture in Standby mode (maintaining only the
  /// 2.0s rolling pre-roll buffer while `isListening` remains `false`).
  Future<void> startStandby([Conversation? targetConversation]) async {
    var conversation = targetConversation ?? stateValue.conversation;
    if (conversation == null) {
      final settings = await _settingsRepository.getSettings();
      conversation = await _conversationRepository.createConversation(
        baseLanguage: settings.baseLanguage,
        targetLanguage: settings.targetLanguage,
        activeContextIds: _pendingContextIds,
        customKeywords: _pendingCustomKeywords,
      );
      if (isClosed) return;
      emit(stateValue.copyWith(conversation: conversation));
    }

    _ensureAudioSubscriptions();

    try {
      await _audioService.startStandbyCapture();
      if (isClosed) return;
      emit(
        stateValue.copyWith(
          conversation: conversation,
          isListening: false,
          amplitude: 0.0,
          error: null,
        ),
      );
      await _translationEngine.initialize();
    } on MicrophonePermissionException catch (e, st) {
      _log.severe('MicrophonePermissionException in startStandby()', e, st);
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
      _log.severe('AudioCaptureException in startStandby()', e, st);
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
      _log.severe('Unexpected error in startStandby()', e, st);
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

  /// Starts or resumes microphone capture for a Push-to-Talk gesture, promoting
  /// the 1.5–2.0s rolling pre-roll buffer and bypassing strict onset gating.
  Future<void> startPushToTalk([Conversation? targetConversation]) {
    return startListening(targetConversation, true);
  }

  /// Pauses active microphone listening into 2.0s pre-roll Standby mode and
  /// flushes any buffered speech so the current utterance finishes translating.
  Future<void> stopListening() async {
    _log.info(
      'stopListening() called (isListening=${stateValue.isListening})...',
    );
    _latestPendingSnapshotChunk = null;
    await _audioService.pauseToStandby();
    if (isClosed) return;
    if (!_isFinalChunkTranslating && _pendingChunkQueue.isEmpty) {
      _resetUtteranceClauseState();
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
    _log.info('stopListening() complete (isListening=false, standby=true).');
  }

  /// Hard-kills any buffered audio and in-flight translation without saving a
  /// message, clears the rolling pre-roll buffer, and puts the microphone into
  /// Standby/Paused state.
  Future<void> discardCurrentUtteranceAndPause() async {
    _log.info(
      'discardCurrentUtteranceAndPause() called '
      '(isListening=${stateValue.isListening}, isLoading=${stateValue.isLoading})...',
    );
    _cancelEpoch++;
    _latestPendingSnapshotChunk = null;
    while (_pendingChunkQueue.isNotEmpty) {
      final item = _pendingChunkQueue.removeFirst();
      if (!item.completer.isCompleted) {
        item.completer.complete();
      }
    }
    _isFinalChunkTranslating = false;
    _resetUtteranceClauseState();
    await _audioService.discardAndEnterStandby();
    if (isClosed) return;
    emit(
      stateValue.copyWith(
        isListening: false,
        isLoading: false,
        amplitude: 0.0,
        streamingTranslatedText: null,
        streamingIsBaseLanguage: null,
        error: null,
      ),
    );
    _log.info('discardCurrentUtteranceAndPause() complete.');
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

  /// Returns the currently active context preset IDs for this session.
  List<String> get activeContextIds =>
      stateValue.conversation?.activeContextIds ?? _pendingContextIds;

  /// Returns the currently active ad-hoc custom keywords for this session.
  List<String> get customKeywords =>
      stateValue.conversation?.customKeywords ?? _pendingCustomKeywords;

  /// Updates the active situational context presets and/or custom keywords
  /// for the current conversation, persisting to storage.
  Future<void> updateConversationContext({
    List<String>? activeContextIds,
    List<String>? customKeywords,
  }) async {
    final normalizedIds = activeContextIds != null
        ? activeContextIds
              .map((id) => id.trim())
              .where((id) => id.isNotEmpty)
              .toSet()
              .toList(growable: false)
        : this.activeContextIds;
    final normalizedKeywords = customKeywords != null
        ? customKeywords
              .map((kw) => kw.trim())
              .where((kw) => kw.isNotEmpty)
              .toSet()
              .toList(growable: false)
        : this.customKeywords;

    _pendingContextIds = normalizedIds;
    _pendingCustomKeywords = normalizedKeywords;

    var conversation = stateValue.conversation;
    if (conversation == null) {
      final settings = await _settingsRepository.getSettings();
      conversation = await _conversationRepository.createConversation(
        baseLanguage: settings.baseLanguage,
        targetLanguage: settings.targetLanguage,
        activeContextIds: normalizedIds,
        customKeywords: normalizedKeywords,
      );
      if (isClosed) return;
      emit(stateValue.copyWith(conversation: conversation));
      return;
    }

    final updated = conversation.copyWith(
      activeContextIds: normalizedIds,
      customKeywords: normalizedKeywords,
    );
    final saved = await _conversationRepository.updateConversation(updated);
    if (isClosed) return;
    emit(stateValue.copyWith(conversation: saved));
  }

  /// Toggles a single situational context preset ID on or off for this session.
  Future<void> toggleContextPreset(String presetId) async {
    final trimmed = presetId.trim();
    if (trimmed.isEmpty) return;
    final current = List<String>.of(activeContextIds);
    if (current.contains(trimmed)) {
      current.remove(trimmed);
    } else {
      current.add(trimmed);
    }
    await updateConversationContext(activeContextIds: current);
  }

  /// Adds one or more comma-separated custom keywords to this session.
  Future<void> addCustomKeyword(String rawInput) async {
    final parts = rawInput
        .split(RegExp(r'[,;\n]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (parts.isEmpty) return;
    final current = List<String>.of(customKeywords);
    for (final part in parts) {
      if (!current.contains(part)) {
        current.add(part);
      }
    }
    await updateConversationContext(customKeywords: current);
  }

  /// Removes a single custom keyword from this session.
  Future<void> removeCustomKeyword(String keyword) async {
    final current = customKeywords
        .where((kw) => kw != keyword)
        .toList(growable: false);
    await updateConversationContext(customKeywords: current);
  }

  ({String? promptBlock, int rollingTurnsUsed, String? contextSummary})
  _buildTurnContextMetadata({
    required AppSettings settings,
    required Conversation conversation,
    required List<Message> priorMessages,
  }) {
    final activePresets = settings.resolveContextPresets(
      conversation.activeContextIds,
    );
    final maxTurns = settings.rollingTurnCount.clamp(
      AppSettings.minRollingTurnCount,
      AppSettings.maxRollingTurnCount,
    );
    final recentTurns = maxTurns > 0 && priorMessages.isNotEmpty
        ? priorMessages.sublist(math.max(0, priorMessages.length - maxTurns))
        : const <Message>[];
    final block = PromptTemplates.buildContextPromptBlock(
      presets: activePresets,
      customKeywords: conversation.customKeywords,
      recentTurns: recentTurns,
      baseLanguage: settings.baseLanguage,
      targetLanguage: settings.targetLanguage,
    );
    final summary = settings.formatContextSummary(
      contextIds: conversation.activeContextIds,
      customKeywords: conversation.customKeywords,
    );
    return (
      promptBlock: block.isEmpty ? null : block,
      rollingTurnsUsed: recentTurns.length,
      contextSummary: summary,
    );
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
      _log.info(
        '[SNAPSHOT IGNORED] onActiveSpeechSnapshotReceived(): '
        'isEmpty=${snapshotChunk.isEmpty}, isClosed=$isClosed, '
        'isFinalChunkTranslating=$_isFinalChunkTranslating',
      );
      return;
    }

    final snapRms = VadBuffer.computeRms(snapshotChunk);
    final snapDurationSec =
        (snapshotChunk.length / _audioService.vadBuffer.sampleRate)
            .toStringAsFixed(2);

    if (snapshotChunk.length >= 4000 &&
        !VadBuffer.hasMeaningfulSpeech(
          snapshotChunk,
          sampleRate: _audioService.vadBuffer.sampleRate,
          minSpeechDuration: VadBuffer.interactiveMinSpeechDuration,
        )) {
      _log.info(
        '[SNAPSHOT SKIPPED] onActiveSpeechSnapshotReceived(): '
        '${snapshotChunk.length} samples (~${snapDurationSec}s, rms=${snapRms.toStringAsFixed(4)}) '
        'lacks meaningful speech energy.',
      );
      return;
    }

    if (_inFlightSnapshotFuture != null) {
      _latestPendingSnapshotChunk = snapshotChunk;
      _log.info(
        '[SNAPSHOT COALESCED] onActiveSpeechSnapshotReceived(): '
        'queued ${snapshotChunk.length} samples (~${snapDurationSec}s, rms=${snapRms.toStringAsFixed(4)}) '
        'behind in-flight snapshot (${_inFlightSnapshotChunk?.length ?? 0} samples).',
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

  void _ensureUtteranceContinuity(Float32List chunk) {
    if (chunk.isEmpty) return;
    final anchorLen = math.min(64, chunk.length);
    final existingAnchor = _utteranceAnchorSamples;
    if (existingAnchor == null) {
      _utteranceAnchorSamples = Float32List.fromList(
        chunk.sublist(0, anchorLen),
      );
      return;
    }
    final checkLen = math.min(existingAnchor.length, anchorLen);
    var prefixMatches =
        chunk.length >= _clauseStartSampleOffset &&
        chunk.length >= _lastTranslatedSampleOffset;
    if (prefixMatches) {
      for (var i = 0; i < checkLen; i++) {
        if (existingAnchor[i] != chunk[i]) {
          prefixMatches = false;
          break;
        }
      }
    }
    if (!prefixMatches) {
      _log.info(
        '[CLAUSE STATE RESET] New utterance audio prefix detected '
        '(chunk=${chunk.length} samples, prevOffset=$_clauseStartSampleOffset).',
      );
      _resetUtteranceClauseState();
      _utteranceAnchorSamples = Float32List.fromList(
        chunk.sublist(0, anchorLen),
      );
    }
  }

  void _promoteActiveClauseToLocked([int? nextClauseStartOffset]) {
    final activeResult = _activeClauseResult;
    final activeAnnotated = _activeClauseAnnotatedText;
    if (activeResult == null ||
        activeAnnotated == null ||
        activeAnnotated.trim().isEmpty) {
      return;
    }
    _lockedClauses.add(
      _LockedClauseSegment(
        result: activeResult,
        originalText: activeResult.originalText?.trim() ?? '',
        translatedText: activeResult.translatedText.trim(),
        annotatedText: activeAnnotated.trim(),
        isBaseLanguage: _activeClauseIsBaseLanguage ?? true,
      ),
    );
    if (nextClauseStartOffset != null &&
        nextClauseStartOffset > _clauseStartSampleOffset) {
      _clauseStartSampleOffset = nextClauseStartOffset;
    } else if (_activeClauseChunk != null &&
        _activeClauseChunk!.length > _clauseStartSampleOffset) {
      _clauseStartSampleOffset = _activeClauseChunk!.length;
    }
    _activeClauseChunk = null;
    _activeClauseResult = null;
    _activeClauseAnnotatedText = null;
    _activeClauseIsBaseLanguage = null;
    _currentClauseStreamingPartialText = null;
  }

  bool _hasTrailingSilentPause(Float32List clauseAudio) {
    final vad = _audioService.vadBuffer;
    if (vad.livePauseSnapshotSamples > 0 &&
        vad.trailingSilenceSamples >= vad.livePauseSnapshotSamples) {
      return true;
    }
    final pauseSamples = vad.livePauseSnapshotSamples > 0
        ? vad.livePauseSnapshotSamples
        : (vad.sampleRate * 3) ~/ 10;
    final minSpeechBeforePause = math.max(1, vad.sampleRate ~/ 5);
    if (clauseAudio.length < pauseSamples + minSpeechBeforePause) {
      return false;
    }
    final tail = Float32List.sublistView(
      clauseAudio,
      clauseAudio.length - pauseSamples,
    );
    return VadBuffer.computeRms(tail) < vad.effectiveSilenceThreshold;
  }

  int? _findSilentPauseEndAfterOffset(Float32List chunk, int startOffset) {
    final vad = _audioService.vadBuffer;
    final pauseSamples = vad.livePauseSnapshotSamples > 0
        ? vad.livePauseSnapshotSamples
        : (vad.sampleRate * 3) ~/ 10;
    if (pauseSamples <= 0 || chunk.length - startOffset < pauseSamples) {
      return null;
    }
    final threshold = vad.effectiveSilenceThreshold;
    final windowSize = math.max(1, vad.sampleRate ~/ 50);
    var silentRunSamples = 0;
    var pauseFound = false;

    for (var offset = startOffset; offset < chunk.length; offset += windowSize) {
      final end = math.min(offset + windowSize, chunk.length);
      final window = Float32List.sublistView(chunk, offset, end);
      final rms = VadBuffer.computeRms(window);
      if (rms < threshold) {
        silentRunSamples += (end - offset);
        if (silentRunSamples >= pauseSamples) {
          pauseFound = true;
        }
      } else {
        if (pauseFound) {
          return offset;
        }
        silentRunSamples = 0;
      }
    }
    return pauseFound ? chunk.length : null;
  }

  int _advancePastLeadingSilence(Float32List chunk, int startOffset) {
    if (startOffset <= 0 || startOffset >= chunk.length) return startOffset;
    final vad = _audioService.vadBuffer;
    final threshold = vad.effectiveSilenceThreshold;
    final windowSize = math.max(1, vad.sampleRate ~/ 50);
    var offset = startOffset;
    while (offset < chunk.length) {
      final end = math.min(offset + windowSize, chunk.length);
      final window = Float32List.sublistView(chunk, offset, end);
      if (VadBuffer.computeRms(window) >= threshold) {
        break;
      }
      offset = end;
    }
    return offset;
  }

  void _maybePromoteActiveClauseBeforeSlicing(Float32List cumulativeChunk) {
    final vad = _audioService.vadBuffer;
    final pauseSamples = vad.livePauseSnapshotSamples > 0
        ? vad.livePauseSnapshotSamples
        : (vad.sampleRate * 3) ~/ 10;
    final minClauseSamples = math.max(1, vad.sampleRate ~/ 5);

    if (_activeClauseResult != null && _activeClauseAnnotatedText != null) {
      final searchStart = math.max(
        _clauseStartSampleOffset + minClauseSamples,
        _lastTranslatedSampleOffset - pauseSamples,
      );
      if (searchStart < cumulativeChunk.length) {
        final pauseEndOffset = _findSilentPauseEndAfterOffset(
          cumulativeChunk,
          searchStart,
        );
        if (pauseEndOffset != null &&
            pauseEndOffset >= _lastTranslatedSampleOffset) {
          _log.info(
            '[CLAUSE LOCKED ON PAUSE] Promoting active clause '
            '("$_activeClauseAnnotatedText") at sample offset $pauseEndOffset.',
          );
          _promoteActiveClauseToLocked(pauseEndOffset);
        }
      }
    }

    if (_activeClauseResult == null && _clauseStartSampleOffset > 0) {
      _clauseStartSampleOffset = _advancePastLeadingSilence(
        cumulativeChunk,
        _clauseStartSampleOffset,
      );
    }
  }

  bool _shouldLockCompletedClause({
    required Float32List clauseAudio,
    required String originalText,
    required String annotatedText,
  }) {
    if (_hasTrailingSilentPause(clauseAudio)) {
      return true;
    }
    final vad = _audioService.vadBuffer;
    final intervalSamples = vad.liveSnapshotIntervalSamples > 0
        ? vad.liveSnapshotIntervalSamples
        : vad.sampleRate ~/ 2;
    if (clauseAudio.length >= intervalSamples * 3) {
      return true;
    }
    if (clauseAudio.length >= intervalSamples * 2) {
      return _terminalClausePunctuation.hasMatch(annotatedText) ||
          _terminalClausePunctuation.hasMatch(originalText);
    }
    return false;
  }

  String _joinClauseTexts(Iterable<String> parts) {
    final buffer = StringBuffer();
    var lastPart = '';
    for (final raw in parts) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) continue;
      if (buffer.isEmpty) {
        buffer.write(trimmed);
        lastPart = trimmed;
        continue;
      }
      if (lastPart == trimmed || buffer.toString().endsWith(trimmed)) {
        continue;
      }
      if (RegExp(r'^[,.;:?!。，、？！;:)）\]"]').hasMatch(trimmed)) {
        buffer.write(trimmed);
      } else {
        buffer.write(' ');
        buffer.write(trimmed);
      }
      lastPart = trimmed;
    }
    return buffer.toString();
  }

  String _buildCombinedUtteranceText({String? activeTailText}) {
    return _joinClauseTexts(<String>[
      ..._lockedClauses.map((c) => c.annotatedText),
      if (activeTailText != null && activeTailText.trim().isNotEmpty)
        activeTailText.trim(),
    ]);
  }

  bool _resolveUtteranceDirection({
    required TranslationResult latestResult,
    required String baseLanguageCode,
    required String targetLanguageCode,
  }) {
    if (_lockedClauses.isEmpty && _activeClauseResult == null) {
      return _resolveIsBaseLanguage(
        result: latestResult,
        baseLanguageCode: baseLanguageCode,
        targetLanguageCode: targetLanguageCode,
      );
    }
    final combinedOriginal = _joinClauseTexts(<String>[
      ..._lockedClauses.map((c) => c.originalText),
      if (_activeClauseResult?.originalText != null)
        _activeClauseResult!.originalText!,
      if (latestResult.originalText != null) latestResult.originalText!,
    ]);
    final combinedTranslated = _joinClauseTexts(<String>[
      ..._lockedClauses.map((c) => c.translatedText),
      if (_activeClauseResult != null) _activeClauseResult!.translatedText,
      latestResult.translatedText,
    ]);
    return _resolveIsBaseLanguage(
      result: TranslationResult(
        sourceLanguage: latestResult.sourceLanguage,
        originalText: combinedOriginal,
        translatedText: combinedTranslated,
      ),
      baseLanguageCode: baseLanguageCode,
      targetLanguageCode: targetLanguageCode,
    );
  }

  Future<TranslationResult?> _translateLiveSnapshot(
    Float32List snapshotChunk,
  ) async {
    final startEpoch = _cancelEpoch;
    try {
      _ensureUtteranceContinuity(snapshotChunk);
      _maybePromoteActiveClauseBeforeSlicing(snapshotChunk);

      final clauseAudio = _clauseStartSampleOffset > 0
          ? Float32List.sublistView(snapshotChunk, _clauseStartSampleOffset)
          : snapshotChunk;
      if (clauseAudio.isEmpty) {
        return _activeClauseResult ??
            (_lockedClauses.isNotEmpty ? _lockedClauses.last.result : null);
      }

      final minCheckSamples = math.max(
        1,
        _audioService.vadBuffer.sampleRate ~/ 4,
      );
      if (_clauseStartSampleOffset > 0 &&
          clauseAudio.length >= minCheckSamples &&
          !VadBuffer.hasMeaningfulSpeech(
            clauseAudio,
            silenceThreshold:
                _audioService.vadBuffer.effectiveSilenceThreshold,
            sampleRate: _audioService.vadBuffer.sampleRate,
            minSpeechDuration: VadBuffer.interactiveMinSpeechDuration,
          )) {
        _log.info(
          '[SNAPSHOT CLAUSE SILENT] _translateLiveSnapshot(): slice after offset '
          '$_clauseStartSampleOffset (${clauseAudio.length} samples) has no new speech yet.',
        );
        return _activeClauseResult ??
            (_lockedClauses.isNotEmpty ? _lockedClauses.last.result : null);
      }

      var conversation = stateValue.conversation;
      final settings = await _settingsRepository.getSettings();
      if (conversation == null) {
        conversation = await _conversationRepository.createConversation(
          baseLanguage: settings.baseLanguage,
          targetLanguage: settings.targetLanguage,
          activeContextIds: _pendingContextIds,
          customKeywords: _pendingCustomKeywords,
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

      final turnContext = _buildTurnContextMetadata(
        settings: settings,
        conversation: conversation,
        priorMessages: stateValue.messages,
      );

      final isInitialPassForClause = _activeClauseAnnotatedText == null;
      if (isInitialPassForClause) {
        _currentClauseStreamingPartialText = null;
      }

      final durationSec =
          (clauseAudio.length / _audioService.vadBuffer.sampleRate)
              .toStringAsFixed(2);
      final snapRms = VadBuffer.computeRms(clauseAudio).toStringAsFixed(4);
      _log.info(
        '[SNAPSHOT START] _translateLiveSnapshot(): translating clause slice '
        '[offset=$_clauseStartSampleOffset..${snapshotChunk.length}] '
        '(${clauseAudio.length} samples / ~${durationSec}s, rms=$snapRms, '
        'lockedClauses=${_lockedClauses.length}, isInitialPass=$isInitialPassForClause, '
        'pair=${settings.baseLanguage}<->${settings.targetLanguage})...',
      );

      final result = await _translationEngine.translateAudioChunk(
        audioWavChunk: clauseAudio,
        baseLanguage: AppSettings.languageNameFor(settings.baseLanguage),
        targetLanguage: AppSettings.languageNameFor(settings.targetLanguage),
        exchangeRate: exchangeRate.rate,
        baseCurrency: settings.baseCurrency,
        targetCurrency: settings.targetCurrency,
        contextPromptBlock: turnContext.promptBlock,
        onPartialResult: (partial) {
          if (isClosed ||
              _isFinalChunkTranslating ||
              _cancelEpoch != startEpoch) {
            return;
          }
          if (!isInitialPassForClause || _activeClauseAnnotatedText != null) {
            // Keep the already-rendered clause stable on screen while refining;
            // swap atomically once this snapshot pass completes.
            return;
          }
          final trimmedPartial = partial.translatedText.trim();
          if (trimmedPartial.isEmpty) return;
          final prevPartial = _currentClauseStreamingPartialText;
          if (prevPartial != null &&
              trimmedPartial.length < prevPartial.length) {
            return;
          }
          _currentClauseStreamingPartialText = trimmedPartial;
          final partialIsBase = _resolveUtteranceDirection(
            latestResult: partial,
            baseLanguageCode: settings.baseLanguage,
            targetLanguageCode: settings.targetLanguage,
          );
          final combinedPreview = _buildCombinedUtteranceText(
            activeTailText: trimmedPartial,
          );
          if (combinedPreview.isEmpty) return;
          _log.info(
            '[SNAPSHOT STREAMING TOKEN] direction=${partialIsBase ? "Host/LEFT (${settings.baseLanguage})" : "Guest/RIGHT (${settings.targetLanguage})"}, '
            'combinedPreview="$combinedPreview"',
          );
          emit(
            stateValue.copyWith(
              conversation: conversation,
              isLoading: true,
              streamingTranslatedText: combinedPreview,
              streamingIsBaseLanguage: partialIsBase,
            ),
          );
        },
      );
      if (isClosed || _cancelEpoch != startEpoch) return null;

      _lastCompletedSnapshotChunk = snapshotChunk;
      _lastCompletedSnapshotResult = result;

      if (result.translatedText.trim().isEmpty ||
          LocalTranslationEngine.isNonSpeechOrHallucination(
            originalText: result.originalText,
            translatedText: result.translatedText,
          )) {
        _log.info(
          '[SNAPSHOT EMPTY/NON-SPEECH] _translateLiveSnapshot() (${clauseAudio.length} samples / ~${durationSec}s): '
          'original="${result.originalText}", translated="${result.translatedText}" '
          '(hasRenderedText=$_hasRenderedUtteranceText).',
        );
        if (!_hasRenderedUtteranceText &&
            !_isFinalChunkTranslating &&
            _latestPendingSnapshotChunk == null) {
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

      final isBaseLanguage = _resolveUtteranceDirection(
        latestResult: result,
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

      _currentClauseStreamingPartialText = null;
      _lastTranslatedSampleOffset = snapshotChunk.length;

      final lockClause = _shouldLockCompletedClause(
        clauseAudio: clauseAudio,
        originalText: rawOriginal,
        annotatedText: annotatedText,
      );
      if (lockClause) {
        _lockedClauses.add(
          _LockedClauseSegment(
            result: result,
            originalText: rawOriginal,
            translatedText: rawTranslated,
            annotatedText: annotatedText,
            isBaseLanguage: isBaseLanguage,
          ),
        );
        _clauseStartSampleOffset = _advancePastLeadingSilence(
          snapshotChunk,
          snapshotChunk.length,
        );
        _activeClauseChunk = null;
        _activeClauseResult = null;
        _activeClauseAnnotatedText = null;
        _activeClauseIsBaseLanguage = null;
      } else {
        _activeClauseChunk = snapshotChunk;
        _activeClauseResult = result;
        _activeClauseAnnotatedText = annotatedText;
        _activeClauseIsBaseLanguage = isBaseLanguage;
      }

      final combinedText = _buildCombinedUtteranceText(
        activeTailText: _activeClauseAnnotatedText,
      );

      _log.info(
        '[SNAPSHOT DONE] _translateLiveSnapshot() (${clauseAudio.length} samples / ~${durationSec}s, locked=$lockClause, totalLocked=${_lockedClauses.length}): '
        'taggedSource="${result.sourceLanguage}" -> ${isBaseLanguage ? "Host/LEFT" : "Guest/RIGHT"}, '
        'clauseAnnotated="$annotatedText", combinedPreview="$combinedText" '
        '(stt=${result.speechToTextMs}ms, trans=${result.translationMs}ms)',
      );

      if (!_isFinalChunkTranslating && combinedText.isNotEmpty) {
        emit(
          stateValue.copyWith(
            conversation: conversation,
            isLoading: true,
            streamingTranslatedText: combinedText,
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

  /// Returns `true` when [finalChunk] matches the current utterance prefix up
  /// to [translatedOffset] and any trailing samples after [translatedOffset]
  /// contain only silence (no additional active speech).
  bool _hasSameActiveSpeechUpTo(
    int translatedOffset,
    Float32List finalChunk,
  ) {
    if (translatedOffset <= 0 || finalChunk.length < translatedOffset) {
      return false;
    }
    final anchor = _utteranceAnchorSamples;
    if (anchor != null) {
      final checkLen = math.min(anchor.length, finalChunk.length);
      for (var i = 0; i < checkLen; i++) {
        if (anchor[i] != finalChunk[i]) {
          return false;
        }
      }
    }
    if (finalChunk.length == translatedOffset) {
      return true;
    }
    final tail = Float32List.sublistView(finalChunk, translatedOffset);
    return !_sliceHasActiveSpeech(tail);
  }

  bool _sliceHasActiveSpeech(Float32List slice) {
    if (slice.isEmpty) return false;
    final threshold = _audioService.vadBuffer.effectiveSilenceThreshold;
    final sliceRms = VadBuffer.computeRms(slice);
    if (sliceRms < threshold) {
      return false;
    }
    final minWindowSamples = math.max(
      1,
      _audioService.vadBuffer.sampleRate ~/ 20,
    );
    if (slice.length < minWindowSamples) {
      return sliceRms >= threshold;
    }
    return VadBuffer.hasMeaningfulSpeech(
      slice,
      silenceThreshold: threshold,
      sampleRate: _audioService.vadBuffer.sampleRate,
      minSpeechDuration: VadBuffer.interactiveMinSpeechDuration,
    );
  }

  /// Processes a timed VAD-segmented speech chunk with acoustic start and end
  /// timestamps through the [TranslationEngine].
  Future<void> onTimedAudioChunkReceived(VadSpeechChunk timedChunk) {
    return onAudioChunkReceived(
      timedChunk.samples,
      speechStartTime: timedChunk.speechStartTime,
      speechEndTime: timedChunk.speechEndTime,
    );
  }

  /// Processes a complete VAD-segmented 16kHz mono PCM audio chunk through
  /// the [TranslationEngine] and saves or updates the resulting [Message]s.
  ///
  /// Rapid micro-chunks are enqueued in FIFO order so each chunk observes the
  /// updated message list and per-language 4.0s running clocks from prior
  /// chunks. Acoustic [speechStartTime] and [speechEndTime] ensure inference
  /// latency never causes a missed same-sentence clump.
  Future<void> onAudioChunkReceived(
    Float32List audioChunk, {
    DateTime? speechStartTime,
    DateTime? speechEndTime,
  }) async {
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

    if (!_hasRenderedUtteranceText &&
        audioChunk.length >= 4000 &&
        !VadBuffer.hasMeaningfulSpeech(
          audioChunk,
          sampleRate: _audioService.vadBuffer.sampleRate,
          minSpeechDuration: VadBuffer.interactiveMinSpeechDuration,
        )) {
      _log.info(
        'onAudioChunkReceived(): chunk contains only pause/silence or transient noise -> ignoring gracefully.',
      );
      return;
    }

    final effectiveSampleRate = _audioService.vadBuffer.sampleRate > 0
        ? _audioService.vadBuffer.sampleRate
        : 16000;
    final estimatedDurationUs =
        (audioChunk.length * 1000000) ~/ effectiveSampleRate;
    final effectiveEnd = speechEndTime ?? DateTime.now();
    final effectiveStart =
        speechStartTime ??
        effectiveEnd.subtract(Duration(microseconds: estimatedDurationUs));

    final completer = Completer<void>();
    _pendingChunkQueue.add(
      _QueuedAudioChunk(
        samples: audioChunk,
        speechStartTime: effectiveStart,
        speechEndTime: effectiveEnd,
        completer: completer,
      ),
    );
    _log.info(
      '[CHUNK QUEUE] Enqueued chunk (${audioChunk.length} samples, '
      'speechStart=${effectiveStart.toIso8601String()}, '
      'speechEnd=${effectiveEnd.toIso8601String()}, '
      'queueDepth=${_pendingChunkQueue.length})',
    );

    unawaited(_drainChunkQueue());
    return completer.future;
  }

  Future<void> _drainChunkQueue() async {
    if (_isDrainingChunkQueue) return;
    _isDrainingChunkQueue = true;
    _latestPendingSnapshotChunk = null;
    try {
      while (_pendingChunkQueue.isNotEmpty && !isClosed) {
        final item = _pendingChunkQueue.removeFirst();
        try {
          await _processSingleQueuedChunk(item);
          if (!item.completer.isCompleted) {
            item.completer.complete();
          }
        } catch (e, st) {
          if (!item.completer.isCompleted) {
            item.completer.completeError(e, st);
          }
        }
      }
    } finally {
      _isFinalChunkTranslating = false;
      _isDrainingChunkQueue = false;
    }
  }

  Future<void> _processSingleQueuedChunk(_QueuedAudioChunk item) async {
    if (isClosed) return;
    final startEpoch = _cancelEpoch;

    // Prevent any queued (not yet started) snapshot from starting, and allow
    // any currently in-flight snapshot to finish recording its clause state.
    _latestPendingSnapshotChunk = null;
    final inFlightFuture = _inFlightSnapshotFuture;
    if (inFlightFuture != null) {
      await inFlightFuture;
    }
    if (isClosed || _cancelEpoch != startEpoch) return;

    _isFinalChunkTranslating = true;

    try {
      _ensureUtteranceContinuity(item.samples);

      var conversation = stateValue.conversation;
      final settings = await _settingsRepository.getSettings();
      if (conversation == null) {
        conversation = await _conversationRepository.createConversation(
          baseLanguage: settings.baseLanguage,
          targetLanguage: settings.targetLanguage,
          activeContextIds: _pendingContextIds,
          customKeywords: _pendingCustomKeywords,
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
      if (isClosed || _cancelEpoch != startEpoch) return;

      final engine = _translationEngine;
      if (engine is SegmentedTranslationEngine) {
        await _processSegmentedChunk(
          engine: engine,
          item: item,
          conversation: conversation,
          settings: settings,
          exchangeRate: exchangeRate.rate,
          startEpoch: startEpoch,
        );
      } else {
        await _processLegacySingleTurnChunk(
          item: item,
          conversation: conversation,
          settings: settings,
          exchangeRate: exchangeRate.rate,
          startEpoch: startEpoch,
        );
      }
    } catch (e, st) {
      if (_cancelEpoch != startEpoch) return;
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
      _resetUtteranceClauseState();
    }
  }

  Future<int> _finalizeIncrementalClausesForChunk({
    required Float32List audioChunk,
    required AppSettings settings,
    required double exchangeRate,
    required String? contextPromptBlock,
    required String conversationId,
    required int startEpoch,
  }) async {
    final stepSw = Stopwatch()..start();
    var engineElapsedMs = 0;

    final allSpeechAlreadyTranslated =
        _lastTranslatedSampleOffset > 0 &&
        (_lockedClauses.isNotEmpty || _activeClauseResult != null) &&
        _hasSameActiveSpeechUpTo(_lastTranslatedSampleOffset, audioChunk);

    if (allSpeechAlreadyTranslated) {
      _log.info(
        'onAudioChunkReceived(): reusing completed incremental clause translations '
        '(translatedOffset=$_lastTranslatedSampleOffset, locked=${_lockedClauses.length}, '
        'hasActiveClause=${_activeClauseResult != null}) with zero extra inference!',
      );
      _promoteActiveClauseToLocked(audioChunk.length);
      return 0;
    }

    _maybePromoteActiveClauseBeforeSlicing(audioChunk);

    final remainingAudio = _clauseStartSampleOffset > 0
        ? Float32List.sublistView(audioChunk, _clauseStartSampleOffset)
        : audioChunk;

    final shouldTranslateRemaining =
        remainingAudio.isNotEmpty &&
        (_lockedClauses.isEmpty ||
            _activeClauseResult != null ||
            _sliceHasActiveSpeech(remainingAudio));

    if (shouldTranslateRemaining) {
      final isInitialPassForClause = _activeClauseAnnotatedText == null;
      if (isInitialPassForClause) {
        _currentClauseStreamingPartialText = null;
      }

      _log.info(
        'onAudioChunkReceived(): invoking translationEngine.translateAudioChunk '
        'on slice [offset=$_clauseStartSampleOffset..${audioChunk.length}] '
        '(${remainingAudio.length} samples, lockedClauses=${_lockedClauses.length}, '
        'isInitialPass=$isInitialPassForClause) for conversation=$conversationId...',
      );

      final tailResult = await _translationEngine.translateAudioChunk(
        audioWavChunk: remainingAudio,
        baseLanguage: AppSettings.languageNameFor(settings.baseLanguage),
        targetLanguage: AppSettings.languageNameFor(settings.targetLanguage),
        exchangeRate: exchangeRate,
        baseCurrency: settings.baseCurrency,
        targetCurrency: settings.targetCurrency,
        contextPromptBlock: contextPromptBlock,
        onPartialResult: (partial) {
          if (isClosed ||
              !stateValue.isLoading ||
              _cancelEpoch != startEpoch) {
            return;
          }
          if (!isInitialPassForClause || _activeClauseAnnotatedText != null) {
            return;
          }
          final trimmedPartial = partial.translatedText.trim();
          if (trimmedPartial.isEmpty) return;
          final prevPartial = _currentClauseStreamingPartialText;
          if (prevPartial != null &&
              trimmedPartial.length < prevPartial.length) {
            return;
          }
          _currentClauseStreamingPartialText = trimmedPartial;
          final partialIsBase = _resolveUtteranceDirection(
            latestResult: partial,
            baseLanguageCode: settings.baseLanguage,
            targetLanguageCode: settings.targetLanguage,
          );
          final combinedPreview = _buildCombinedUtteranceText(
            activeTailText: trimmedPartial,
          );
          if (combinedPreview.isEmpty) return;
          emit(
            stateValue.copyWith(
              streamingTranslatedText: combinedPreview,
              streamingIsBaseLanguage: partialIsBase,
            ),
          );
        },
      );
      engineElapsedMs = stepSw.elapsedMilliseconds;
      if (isClosed || _cancelEpoch != startEpoch) return engineElapsedMs;

      if (tailResult.translatedText.trim().isNotEmpty &&
          !LocalTranslationEngine.isNonSpeechOrHallucination(
            originalText: tailResult.originalText,
            translatedText: tailResult.translatedText,
          )) {
        final isBase = _resolveUtteranceDirection(
          latestResult: tailResult,
          baseLanguageCode: settings.baseLanguage,
          targetLanguageCode: settings.targetLanguage,
        );
        final rawOrig = tailResult.originalText?.trim() ?? '';
        final rawTrans = tailResult.translatedText.trim();
        final annotated = TranslationAnnotator.annotate(
          originalText: rawOrig,
          translatedText: rawTrans,
          exchangeRate: exchangeRate,
          baseCurrency: settings.baseCurrency,
          targetCurrency: settings.targetCurrency,
          isBaseLanguage: isBase,
        );
        _lockedClauses.add(
          _LockedClauseSegment(
            result: tailResult,
            originalText: rawOrig,
            translatedText: rawTrans,
            annotatedText: annotated,
            isBaseLanguage: isBase,
          ),
        );
        _activeClauseChunk = null;
        _activeClauseResult = null;
        _activeClauseAnnotatedText = null;
        _activeClauseIsBaseLanguage = null;
      } else {
        _promoteActiveClauseToLocked(audioChunk.length);
      }
    } else {
      _promoteActiveClauseToLocked(audioChunk.length);
    }

    return engineElapsedMs;
  }

  TranslationResult? _buildCombinedResultFromLockedClauses({
    required AppSettings settings,
    int fallbackElapsedMs = 0,
  }) {
    if (_lockedClauses.isEmpty) return null;
    final rawOriginal = _joinClauseTexts(
      _lockedClauses.map((c) => c.originalText),
    );
    final rawTranslated = _joinClauseTexts(
      _lockedClauses.map((c) => c.translatedText),
    );
    final lastResult = _lockedClauses.last.result;
    var summedSttMs = 0;
    var hasSttMs = false;
    var summedTransMs = 0;
    var summedTotalMs = 0;
    var hasTotalMs = false;
    for (final clause in _lockedClauses) {
      if (clause.result.speechToTextMs != null) {
        summedSttMs += clause.result.speechToTextMs!;
        hasSttMs = true;
      }
      if (clause.result.translationMs != null) {
        summedTransMs += clause.result.translationMs!;
      }
      if (clause.result.totalDurationMs != null) {
        summedTotalMs += clause.result.totalDurationMs!;
        hasTotalMs = true;
      }
    }
    final speechToTextMs = hasSttMs ? summedSttMs : fallbackElapsedMs;
    final translationMs = summedTransMs;
    final totalDurationMs = hasTotalMs
        ? summedTotalMs
        : (speechToTextMs + translationMs);
    return TranslationResult(
      sourceLanguage: lastResult.sourceLanguage,
      originalText: rawOriginal,
      translatedText: rawTranslated,
      speechToTextMs: speechToTextMs,
      translationMs: translationMs,
      totalDurationMs: totalDurationMs,
      speechToTextModel:
          lastResult.speechToTextModel ?? settings.activeSttModelDisplayName,
      translationModel:
          lastResult.translationModel ??
          settings.activeTranslationModelDisplayName,
    );
  }

  /// Segmented multi-language pipeline for [SegmentedTranslationEngine]:
  /// 1. Reuses an in-flight or completed live active-speech snapshot when it
  ///    covers the same active speech, or runs Step 1 STT to produce an ordered
  ///    list of language-tagged [SpeechSegment]s (absorbing lone interjections
  ///    and splitting rapid language switches).
  /// 2. Checks each segment against that language's 4.0s acoustic running clock:
  ///    - Consecutive same-language within 4.0s (no intervening opposite turn):
  ///      auto-clumps and re-translates in-place.
  ///    - Interrupted same-language within 4.0s (with intervening opposite
  ///      turn(s)): runs LLM "movie script" continuation resolution; merges
  ///      in-place above the interjection when `same_sentence == true` or
  ///      forks into a new bottom bubble when `same_sentence == false`.
  ///    - Otherwise: appends a new bubble and opens/resets that language's
  ///      4.0s running clock.
  Future<void> _processSegmentedChunk({
    required SegmentedTranslationEngine engine,
    required _QueuedAudioChunk item,
    required Conversation conversation,
    required AppSettings settings,
    required double exchangeRate,
    required int startEpoch,
  }) async {
    TranslationResult? matchedSnapshotResult;

    if (_lockedClauses.isNotEmpty || _activeClauseResult != null) {
      final turnContext = _buildTurnContextMetadata(
        settings: settings,
        conversation: conversation,
        priorMessages: stateValue.messages,
      );
      final elapsedMs = await _finalizeIncrementalClausesForChunk(
        audioChunk: item.samples,
        settings: settings,
        exchangeRate: exchangeRate,
        contextPromptBlock: turnContext.promptBlock,
        conversationId: conversation.id,
        startEpoch: startEpoch,
      );
      if (isClosed || _cancelEpoch != startEpoch) return;
      matchedSnapshotResult = _buildCombinedResultFromLockedClauses(
        settings: settings,
        fallbackElapsedMs: elapsedMs,
      );
    } else {
      final completedChunk = _lastCompletedSnapshotChunk;
      final completedResult = _lastCompletedSnapshotResult;
      if (completedChunk != null &&
          completedResult != null &&
          _hasSameActiveSpeechUpTo(completedChunk.length, item.samples)) {
        _log.info(
          'onAudioChunkReceived(): reusing completed active-speech snapshot '
          'result (${completedChunk.length} active samples) with zero extra inference!',
        );
        matchedSnapshotResult = completedResult;
      }
    }
    if (isClosed || _cancelEpoch != startEpoch) return;

    final baseLanguageName = AppSettings.languageNameFor(settings.baseLanguage);
    final targetLanguageName = AppSettings.languageNameFor(
      settings.targetLanguage,
    );

    if (matchedSnapshotResult != null &&
        (matchedSnapshotResult.translatedText.trim().isEmpty ||
            LocalTranslationEngine.isNonSpeechOrHallucination(
              originalText: matchedSnapshotResult.originalText,
              translatedText: matchedSnapshotResult.translatedText,
            ))) {
      _log.info(
        '[SEGMENTED SNAPSHOT EMPTY] Reused snapshot indicated pause / no speech '
        '(original="${matchedSnapshotResult.originalText}", translated="${matchedSnapshotResult.translatedText}") '
        '-> reporting non-speech audio and returning to listening state.',
      );
      _audioService.reportNonSpeechAudio(item.samples);
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

    late final List<SpeechSegment> validSegments;
    late final int perSegmentSttMs;
    late final String sttModelName;

    final snapshotOriginal = matchedSnapshotResult?.originalText?.trim() ?? '';
    if (matchedSnapshotResult != null && snapshotOriginal.isNotEmpty) {
      final baseCode = LanguageDetector.normalizeLanguageCode(baseLanguageName);
      final targetCode = LanguageDetector.normalizeLanguageCode(
        targetLanguageName,
      );
      final resolvedFromSnapshot =
          LanguageDetector.segmentAndResolveTranscript(
            rawSegments: <SpeechSegment>[
              SpeechSegment(
                text: snapshotOriginal,
                languageCode: matchedSnapshotResult.sourceLanguage,
              ),
            ],
            baseLanguage: baseCode,
            targetLanguage: targetCode,
          );
      validSegments = resolvedFromSnapshot
          .where(
            (seg) =>
                seg.text.trim().isNotEmpty &&
                !LocalTranslationEngine.isNonSpeechOrHallucination(
                  translatedText: seg.text,
                ),
          )
          .toList(growable: false);
      perSegmentSttMs = validSegments.isEmpty
          ? 0
          : (matchedSnapshotResult.speechToTextMs ?? 0) ~/ validSegments.length;
      sttModelName =
          matchedSnapshotResult.speechToTextModel ??
          settings.activeSttModelDisplayName;
    } else {
      final initialContext = _buildTurnContextMetadata(
        settings: settings,
        conversation: conversation,
        priorMessages: stateValue.messages,
      );

      final sttSw = Stopwatch()..start();
      _log.info(
        '[SEGMENTED STT START] Transcribing ${item.samples.length} samples '
        '(speechStart=${item.speechStartTime.toIso8601String()}, '
        'speechEnd=${item.speechEndTime.toIso8601String()})...',
      );
      final sttResult = await engine.transcribeAudioChunk(
        audioWavChunk: item.samples,
        baseLanguage: baseLanguageName,
        targetLanguage: targetLanguageName,
        contextPromptBlock: initialContext.promptBlock,
      );
      sttSw.stop();
      if (isClosed || _cancelEpoch != startEpoch) return;

      validSegments = sttResult.effectiveSegments
          .where(
            (seg) =>
                seg.text.trim().isNotEmpty &&
                !LocalTranslationEngine.isNonSpeechOrHallucination(
                  translatedText: seg.text,
                ),
          )
          .toList(growable: false);
      perSegmentSttMs = validSegments.isEmpty
          ? 0
          : (sttResult.durationMs > 0
                    ? sttResult.durationMs
                    : sttSw.elapsedMilliseconds) ~/
                validSegments.length;
      sttModelName =
          sttResult.modelName ?? settings.activeSttModelDisplayName;
    }

    if (validSegments.isEmpty) {
      _log.info(
        '[SEGMENTED STT EMPTY] No speech segments found '
        '-> reporting non-speech audio and returning to listening state.',
      );
      _audioService.reportNonSpeechAudio(item.samples);
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

    _log.info(
      '[SEGMENTED STT RESULT] Extracted ${validSegments.length} segment(s): '
      '${validSegments.map((s) => '[${s.languageCode}] "${s.text}"').join(' | ')}',
    );

    var currentConversation = stateValue.conversation ?? conversation;
    var currentMessages = List<Message>.of(stateValue.messages);

    for (var i = 0; i < validSegments.length; i++) {
      if (isClosed || _cancelEpoch != startEpoch) return;
      final segment = validSegments[i];
      final isBaseLanguage = _matchesLanguage(
        detectedLanguage: segment.languageCode,
        languageCode: settings.baseLanguage,
        languageName: baseLanguageName,
      );
      final speakerLangCode = isBaseLanguage
          ? settings.baseLanguage
          : settings.targetLanguage;
      final ownClock = isBaseLanguage
          ? _baseLanguageClock
          : _targetLanguageClock;
      final oppositeClock = isBaseLanguage
          ? _targetLanguageClock
          : _baseLanguageClock;

      final canClump = ownClock.isOpenWithin(
        speechStartTime: item.speechStartTime,
        window: languageClumpingWindow,
      );
      final existingIndex = canClump
          ? currentMessages.indexWhere((m) => m.id == ownClock.openMessageId)
          : -1;

      if (existingIndex != -1) {
        final existingMsg = currentMessages[existingIndex];
        final acousticGapMs = item.speechStartTime
            .difference(ownClock.lastSpeechEndTime!)
            .inMilliseconds;

        if (ownClock.interveningOppositeTurns.isEmpty) {
          // Case A: Consecutive same-language chunk within 4.0s with no intervening turn.
          final combinedOriginal = LanguageDetector.joinTranscriptParts(
            existingMsg.originalText,
            segment.text,
          );
          _log.info(
            '[CLUMP SAME-LANG] Segment ${i + 1}/${validSegments.length} ($speakerLangCode) '
            'arrived ${acousticGapMs}ms after open message id=${existingMsg.id} '
            '(<= ${languageClumpingWindow.inMilliseconds}ms, 0 intervening turns) -> '
            'auto-clumping: "${existingMsg.originalText}" + "${segment.text}" => "$combinedOriginal"',
          );

          final clumpContext = _buildTurnContextMetadata(
            settings: settings,
            conversation: currentConversation,
            priorMessages: currentMessages.sublist(0, existingIndex),
          );

          final transSw = Stopwatch()..start();
          final translationResult = await engine.translateText(
            transcript: combinedOriginal,
            sourceLanguage: speakerLangCode,
            baseLanguage: baseLanguageName,
            targetLanguage: targetLanguageName,
            exchangeRate: exchangeRate,
            baseCurrency: settings.baseCurrency,
            targetCurrency: settings.targetCurrency,
            contextPromptBlock: clumpContext.promptBlock,
            speechToTextMs: perSegmentSttMs,
            speechToTextModel: sttModelName,
          );
          transSw.stop();
          if (isClosed || _cancelEpoch != startEpoch) return;

          final rawTranslated = translationResult.translatedText.trim();
          if (rawTranslated.isNotEmpty) {
            final annotatedText = TranslationAnnotator.annotate(
              originalText: combinedOriginal,
              translatedText: rawTranslated,
              exchangeRate: exchangeRate,
              baseCurrency: settings.baseCurrency,
              targetCurrency: settings.targetCurrency,
              isBaseLanguage: isBaseLanguage,
            );
            final updatedSpeechToTextMs =
                (existingMsg.speechToTextMs ?? 0) + perSegmentSttMs;
            final stepTransMs =
                translationResult.translationMs ?? transSw.elapsedMilliseconds;
            final updatedTranslationMs =
                (existingMsg.translationMs ?? 0) + stepTransMs;
            final updatedTotalMs = updatedSpeechToTextMs + updatedTranslationMs;

            final updatedDraft = existingMsg.copyWith(
              originalText: combinedOriginal,
              translatedText: rawTranslated,
              annotatedText: annotatedText,
              speechToTextMs: updatedSpeechToTextMs,
              translationMs: updatedTranslationMs,
              totalDurationMs: updatedTotalMs,
              speechToTextModel: sttModelName,
              translationModel:
                  translationResult.translationModel ??
                  settings.activeTranslationModelDisplayName,
            );
            final savedMsg = await _conversationRepository.saveMessage(
              updatedDraft,
            );
            if (isClosed) return;

            currentMessages[existingIndex] = savedMsg;
            ownClock.lastSpeechEndTime = item.speechEndTime;
            if (oppositeClock.openMessageId != null) {
              oppositeClock.recordInterveningTurn(savedMsg);
            }
            currentConversation = currentConversation.copyWith(
              previewText: currentMessages.last.effectiveTranslatedText,
            );

            emit(
              stateValue.copyWith(
                conversation: currentConversation,
                messages: List<Message>.unmodifiable(currentMessages),
                isLoading: i < validSegments.length - 1,
                streamingTranslatedText: null,
                streamingIsBaseLanguage: null,
                lastClumpedMessageId: savedMsg.id,
                clumpedUpdateCount: stateValue.clumpedUpdateCount + 1,
              ),
            );
          }
          continue;
        } else {
          // Case B: Intervening opposite-language turn(s) occurred while this
          // language's 4.0s clock was still open -> run Movie-Script Continuation!
          final interveningSnapshot = List<Message>.unmodifiable(
            ownClock.interveningOppositeTurns,
          );
          _log.info(
            '[MOVIE-SCRIPT CHECK] Segment ${i + 1}/${validSegments.length} ($speakerLangCode) '
            'arrived ${acousticGapMs}ms after open message id=${existingMsg.id} '
            'with ${interveningSnapshot.length} intervening opposite-language turn(s) '
            '(${interveningSnapshot.map((m) => '"${m.originalText}"').join(', ')}) -> '
            'asking LLM whether Part 1 ("${existingMsg.originalText}") and Part 2 ("${segment.text}") '
            'are the same sentence...',
          );

          final continuationContext = _buildTurnContextMetadata(
            settings: settings,
            conversation: currentConversation,
            priorMessages: currentMessages.sublist(0, existingIndex),
          );

          final contSw = Stopwatch()..start();
          final decision = await engine.resolveContinuationAndTranslate(
            part1Transcript: existingMsg.originalText,
            part2Transcript: segment.text,
            interveningTurns: interveningSnapshot,
            sourceLanguage: speakerLangCode,
            baseLanguage: baseLanguageName,
            targetLanguage: targetLanguageName,
            exchangeRate: exchangeRate,
            baseCurrency: settings.baseCurrency,
            targetCurrency: settings.targetCurrency,
            speechToTextMs: perSegmentSttMs,
            speechToTextModel: sttModelName,
            contextPromptBlock: continuationContext.promptBlock,
          );
          contSw.stop();
          if (isClosed) return;

          if (decision.isSameSentence) {
            final combinedOriginal =
                decision.combinedOriginalText.trim().isNotEmpty
                ? decision.combinedOriginalText.trim()
                : LanguageDetector.joinTranscriptParts(
                    existingMsg.originalText,
                    segment.text,
                  );
            final rawTranslated = decision.result.translatedText.trim();
            final annotatedText = TranslationAnnotator.annotate(
              originalText: combinedOriginal,
              translatedText: rawTranslated,
              exchangeRate: exchangeRate,
              baseCurrency: settings.baseCurrency,
              targetCurrency: settings.targetCurrency,
              isBaseLanguage: isBaseLanguage,
            );
            final updatedSpeechToTextMs =
                (existingMsg.speechToTextMs ?? 0) + perSegmentSttMs;
            final stepTransMs =
                decision.result.translationMs ?? contSw.elapsedMilliseconds;
            final updatedTranslationMs =
                (existingMsg.translationMs ?? 0) + stepTransMs;
            final updatedTotalMs = updatedSpeechToTextMs + updatedTranslationMs;

            final updatedDraft = existingMsg.copyWith(
              originalText: combinedOriginal,
              translatedText: rawTranslated,
              annotatedText: annotatedText,
              speechToTextMs: updatedSpeechToTextMs,
              translationMs: updatedTranslationMs,
              totalDurationMs: updatedTotalMs,
              speechToTextModel: sttModelName,
              translationModel:
                  decision.result.translationModel ??
                  settings.activeTranslationModelDisplayName,
            );
            final savedMsg = await _conversationRepository.saveMessage(
              updatedDraft,
            );
            if (isClosed) return;

            _log.info(
              '[MOVIE-SCRIPT MERGED IN-PLACE] Updated bubble id=${savedMsg.id} '
              'at index $existingIndex (above interjection): '
              'original="$combinedOriginal", translated="$rawTranslated"',
            );

            currentMessages[existingIndex] = savedMsg;
            ownClock.lastSpeechEndTime = item.speechEndTime;
            ownClock.interveningOppositeTurns.clear();
            if (oppositeClock.openMessageId != null) {
              oppositeClock.recordInterveningTurn(savedMsg);
            }
            currentConversation = currentConversation.copyWith(
              previewText: currentMessages.last.effectiveTranslatedText,
            );

            emit(
              stateValue.copyWith(
                conversation: currentConversation,
                messages: List<Message>.unmodifiable(currentMessages),
                isLoading: i < validSegments.length - 1,
                streamingTranslatedText: null,
                streamingIsBaseLanguage: null,
                lastClumpedMessageId: savedMsg.id,
                clumpedUpdateCount: stateValue.clumpedUpdateCount + 1,
              ),
            );
            continue;
          } else {
            // Conversation forked! Append Part 2 as a brand new bubble at the bottom.
            final rawOriginal = segment.text.trim();
            var rawTranslated = decision.result.translatedText.trim();
            var stepTransMs =
                decision.result.translationMs ?? contSw.elapsedMilliseconds;
            var transModelName =
                decision.result.translationModel ??
                settings.activeTranslationModelDisplayName;

            if (rawTranslated.isEmpty) {
              final fallbackContext = _buildTurnContextMetadata(
                settings: settings,
                conversation: currentConversation,
                priorMessages: currentMessages,
              );
              final fallbackRes = await engine.translateText(
                transcript: rawOriginal,
                sourceLanguage: speakerLangCode,
                baseLanguage: baseLanguageName,
                targetLanguage: targetLanguageName,
                exchangeRate: exchangeRate,
                baseCurrency: settings.baseCurrency,
                targetCurrency: settings.targetCurrency,
                contextPromptBlock: fallbackContext.promptBlock,
                speechToTextMs: perSegmentSttMs,
                speechToTextModel: sttModelName,
              );
              if (isClosed) return;
              rawTranslated = fallbackRes.translatedText.trim();
              stepTransMs += fallbackRes.translationMs ?? 0;
              transModelName =
                  fallbackRes.translationModel ?? transModelName;
            }

            if (rawTranslated.isEmpty) {
              continue;
            }

            final annotatedText = TranslationAnnotator.annotate(
              originalText: rawOriginal,
              translatedText: rawTranslated,
              exchangeRate: exchangeRate,
              baseCurrency: settings.baseCurrency,
              targetCurrency: settings.targetCurrency,
              isBaseLanguage: isBaseLanguage,
            );
            final forkContext = _buildTurnContextMetadata(
              settings: settings,
              conversation: currentConversation,
              priorMessages: currentMessages,
            );

            final draftMessage = Message(
              id: '',
              conversationId: currentConversation.id,
              timestamp: DateTime.now(),
              isBaseLanguage: isBaseLanguage,
              originalText: rawOriginal,
              translatedText: rawTranslated,
              annotatedText: annotatedText,
              speechToTextMs: perSegmentSttMs,
              translationMs: stepTransMs,
              totalDurationMs: perSegmentSttMs + stepTransMs,
              speechToTextModel: sttModelName,
              translationModel: transModelName,
              activeContextSummary: forkContext.contextSummary,
              rollingTurnsUsed: forkContext.rollingTurnsUsed,
            );
            final savedMessage = await _conversationRepository.saveMessage(
              draftMessage,
            );
            if (isClosed) return;

            _log.info(
              '[MOVIE-SCRIPT FORKED NEW BUBBLE] Created new bubble id=${savedMessage.id} '
              'at bottom: original="$rawOriginal", translated="$rawTranslated"',
            );

            currentMessages.add(savedMessage);
            ownClock
              ..openMessageId = savedMessage.id
              ..lastSpeechEndTime = item.speechEndTime
              ..interveningOppositeTurns.clear();
            if (oppositeClock.openMessageId != null) {
              oppositeClock.interveningOppositeTurns.add(savedMessage);
            }
            currentConversation = currentConversation.copyWith(
              previewText: annotatedText,
            );

            emit(
              stateValue.copyWith(
                conversation: currentConversation,
                messages: List<Message>.unmodifiable(currentMessages),
                isLoading: i < validSegments.length - 1,
                streamingTranslatedText: null,
                streamingIsBaseLanguage: null,
              ),
            );
            continue;
          }
        }
      }

      // Case C: No open message within 4.0s for this language -> translate and append new bubble.
      final segmentContext = _buildTurnContextMetadata(
        settings: settings,
        conversation: currentConversation,
        priorMessages: currentMessages,
      );
      final rawOriginal = segment.text.trim();
      final transSw = Stopwatch()..start();
      final TranslationResult translationResult;
      if (matchedSnapshotResult != null &&
          validSegments.length == 1 &&
          matchedSnapshotResult.translatedText.trim().isNotEmpty) {
        _log.info(
          '[SNAPSHOT REUSED FOR FINAL BUBBLE] Reusing live snapshot translation '
          'for single-segment turn with zero extra inference!',
        );
        translationResult = matchedSnapshotResult;
      } else {
        translationResult = await engine.translateText(
          transcript: rawOriginal,
          sourceLanguage: speakerLangCode,
          baseLanguage: baseLanguageName,
          targetLanguage: targetLanguageName,
          exchangeRate: exchangeRate,
          baseCurrency: settings.baseCurrency,
          targetCurrency: settings.targetCurrency,
          contextPromptBlock: segmentContext.promptBlock,
          speechToTextMs: perSegmentSttMs,
          speechToTextModel: sttModelName,
          onPartialResult: (partial) {
            if (isClosed || !stateValue.isLoading) return;
            emit(
              stateValue.copyWith(
                streamingTranslatedText: partial.translatedText,
                streamingIsBaseLanguage: isBaseLanguage,
              ),
            );
          },
        );
      }
      transSw.stop();
      if (isClosed || _cancelEpoch != startEpoch) return;

      final rawTranslated = translationResult.translatedText.trim();
      if (rawTranslated.isEmpty ||
          LocalTranslationEngine.isNonSpeechOrHallucination(
            originalText: rawOriginal,
            translatedText: rawTranslated,
          )) {
        _log.info(
          '[SEGMENT SKIPPED] Segment ${i + 1}/${validSegments.length} produced empty/non-speech translation -> skipping.',
        );
        continue;
      }

      final annotatedText = TranslationAnnotator.annotate(
        originalText: rawOriginal,
        translatedText: rawTranslated,
        exchangeRate: exchangeRate,
        baseCurrency: settings.baseCurrency,
        targetCurrency: settings.targetCurrency,
        isBaseLanguage: isBaseLanguage,
      );
      final stepTransMs =
          translationResult.translationMs ?? transSw.elapsedMilliseconds;
      final totalDurationMs = perSegmentSttMs + stepTransMs;
      final translationModel =
          translationResult.translationModel ??
          settings.activeTranslationModelDisplayName;

      final draftMessage = Message(
        id: '',
        conversationId: currentConversation.id,
        timestamp: DateTime.now(),
        isBaseLanguage: isBaseLanguage,
        originalText: rawOriginal,
        translatedText: rawTranslated,
        annotatedText: annotatedText,
        speechToTextMs: perSegmentSttMs,
        translationMs: stepTransMs,
        totalDurationMs: totalDurationMs,
        speechToTextModel: sttModelName,
        translationModel: translationModel,
        activeContextSummary: segmentContext.contextSummary,
        rollingTurnsUsed: segmentContext.rollingTurnsUsed,
      );
      final savedMessage = await _conversationRepository.saveMessage(
        draftMessage,
      );
      if (isClosed) return;

      _log.info(
        '[NEW SEGMENT BUBBLE] Saved segment ${i + 1}/${validSegments.length} '
        'id=${savedMessage.id} (${isBaseLanguage ? "Host/LEFT" : "Guest/RIGHT"}, lang=$speakerLangCode): '
        'original="$rawOriginal", translated="$rawTranslated"',
      );

      currentMessages.add(savedMessage);
      ownClock
        ..openMessageId = savedMessage.id
        ..lastSpeechEndTime = item.speechEndTime
        ..interveningOppositeTurns.clear();
      if (oppositeClock.openMessageId != null) {
        oppositeClock.interveningOppositeTurns.add(savedMessage);
      }

      currentConversation = currentConversation.copyWith(
        previewText: annotatedText,
      );

      emit(
        stateValue.copyWith(
          conversation: currentConversation,
          messages: List<Message>.unmodifiable(currentMessages),
          isLoading: i < validSegments.length - 1,
          streamingTranslatedText: null,
          streamingIsBaseLanguage: null,
        ),
      );
    }

    if (stateValue.isLoading) {
      emit(
        stateValue.copyWith(
          isLoading: false,
          streamingTranslatedText: null,
          streamingIsBaseLanguage: null,
        ),
      );
    }

    _isFinalChunkTranslating = false;
    _resetUtteranceClauseState();

    if (_pendingChunkQueue.isEmpty && currentMessages.isNotEmpty) {
      await _updateGeneratedSummary(
        conversation: currentConversation,
        messages: currentMessages,
        settings: settings,
      );
    }
  }

  /// Legacy single-turn fallback for test stubs that implement
  /// [TranslationEngine] without [SegmentedTranslationEngine].
  Future<void> _processLegacySingleTurnChunk({
    required _QueuedAudioChunk item,
    required Conversation conversation,
    required AppSettings settings,
    required double exchangeRate,
    required int startEpoch,
  }) async {
    final audioChunk = item.samples;
    final turnContext = _buildTurnContextMetadata(
      settings: settings,
      conversation: conversation,
      priorMessages: stateValue.messages,
    );

    final stepSw = Stopwatch()..start();
    final engineElapsedMs = await _finalizeIncrementalClausesForChunk(
      audioChunk: audioChunk,
      settings: settings,
      exchangeRate: exchangeRate,
      contextPromptBlock: turnContext.promptBlock,
      conversationId: conversation.id,
      startEpoch: startEpoch,
    );
    if (isClosed || _cancelEpoch != startEpoch) return;

    if (_lockedClauses.isEmpty) {
      _log.info(
        'onAudioChunkReceived(): pause / no speech detected in turn '
        '-> returning to listening state without adding a message.',
      );
      _audioService.reportNonSpeechAudio(audioChunk);
      _isFinalChunkTranslating = false;
      _resetUtteranceClauseState();
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
    final rawOriginal = _joinClauseTexts(
      _lockedClauses.map((c) => c.originalText),
    );
    final rawTranslated = _joinClauseTexts(
      _lockedClauses.map((c) => c.translatedText),
    );
    final annotatedText = _joinClauseTexts(
      _lockedClauses.map((c) => c.annotatedText),
    );
    final isBaseLanguage = _lockedClauses.last.isBaseLanguage;
    final lastResult = _lockedClauses.last.result;
    postProcessSw.stop();
    stepSw.stop();

    var summedSttMs = 0;
    var hasSttMs = false;
    var summedTransMs = 0;
    var summedTotalMs = 0;
    var hasTotalMs = false;
    for (final clause in _lockedClauses) {
      if (clause.result.speechToTextMs != null) {
        summedSttMs += clause.result.speechToTextMs!;
        hasSttMs = true;
      }
      if (clause.result.translationMs != null) {
        summedTransMs += clause.result.translationMs!;
      }
      if (clause.result.totalDurationMs != null) {
        summedTotalMs += clause.result.totalDurationMs!;
        hasTotalMs = true;
      }
    }

    final speechToTextMs = hasSttMs ? summedSttMs : engineElapsedMs;
    final translationMs = summedTransMs + postProcessSw.elapsedMilliseconds;
    final totalDurationMs = hasTotalMs
        ? summedTotalMs + postProcessSw.elapsedMilliseconds
        : (speechToTextMs + translationMs);
    final speechToTextModel =
        lastResult.speechToTextModel ?? settings.activeSttModelDisplayName;
    final translationModel =
        lastResult.translationModel ??
        settings.activeTranslationModelDisplayName;

    _log.info(
      'onAudioChunkReceived(): translation succeeded (${_lockedClauses.length} clauses)! '
      'detectedSource="${lastResult.sourceLanguage}" (isBaseLanguage=$isBaseLanguage -> '
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
      activeContextSummary: turnContext.contextSummary,
      rollingTurnsUsed: turnContext.rollingTurnsUsed,
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

    _isFinalChunkTranslating = false;
    _resetUtteranceClauseState();

    emit(
      stateValue.copyWith(
        conversation: updatedConversation,
        messages: updatedMessages,
        isLoading: false,
        streamingTranslatedText: null,
        streamingIsBaseLanguage: null,
      ),
    );

    if (_pendingChunkQueue.isEmpty) {
      await _updateGeneratedSummary(
        conversation: updatedConversation,
        messages: updatedMessages,
        settings: settings,
      );
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
    _resetLanguageClocks();
    _pendingChunkQueue.clear();
    await stopListening();
    _resetUtteranceClauseState();
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
          lastClumpedMessageId: null,
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
    _resetLanguageClocks();
    _pendingChunkQueue.clear();
    _latestPendingSnapshotChunk = null;
    _resetUtteranceClauseState();
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
          lastClumpedMessageId: null,
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
        final timed = _audioService.vadBuffer.lastEmittedTimedChunk;
        final hasMatchingTimed =
            timed != null && identical(timed.samples, chunk);
        _log.info(
          'audioChunkStream emitted a VAD speech chunk (${chunk.length} samples, '
          'hasTimedMetadata=$hasMatchingTimed) -> dispatching to onAudioChunkReceived().',
        );
        unawaited(
          onAudioChunkReceived(
            chunk,
            speechStartTime: hasMatchingTimed ? timed.speechStartTime : null,
            speechEndTime: hasMatchingTimed ? timed.speechEndTime : null,
          ),
        );
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

class _QueuedAudioChunk {
  _QueuedAudioChunk({
    required this.samples,
    required this.speechStartTime,
    required this.speechEndTime,
    required this.completer,
  });

  final Float32List samples;
  final DateTime speechStartTime;
  final DateTime speechEndTime;
  final Completer<void> completer;
}

class _LanguageRunningClockState {
  String? openMessageId;
  DateTime? lastSpeechEndTime;
  final List<Message> interveningOppositeTurns = <Message>[];

  void reset() {
    openMessageId = null;
    lastSpeechEndTime = null;
    interveningOppositeTurns.clear();
  }

  void recordInterveningTurn(Message message) {
    final existingIdx = interveningOppositeTurns.indexWhere(
      (m) => m.id == message.id,
    );
    if (existingIdx != -1) {
      interveningOppositeTurns[existingIdx] = message;
    } else {
      interveningOppositeTurns.add(message);
    }
  }

  bool isOpenWithin({
    required DateTime speechStartTime,
    required Duration window,
  }) {
    final end = lastSpeechEndTime;
    if (openMessageId == null || end == null) return false;
    final gap = speechStartTime.difference(end);
    return gap <= window;
  }
}

class _LockedClauseSegment {
  const _LockedClauseSegment({
    required this.result,
    required this.originalText,
    required this.translatedText,
    required this.annotatedText,
    required this.isBaseLanguage,
  });

  final TranslationResult result;
  final String originalText;
  final String translatedText;
  final String annotatedText;
  final bool isBaseLanguage;
}
