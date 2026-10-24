import 'package:bloc_signals/bloc_signals.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:translation_app/core/data/models/app_settings.dart';
import 'package:translation_app/core/logging/app_logger.dart';

part 'model_manager.freezed.dart';

/// Reactive state of the on-device Gemma 4 E2B and Edge Whisper STT model
/// installations.
@freezed
abstract class ModelDownloadState with _$ModelDownloadState {
  const factory ModelDownloadState({
    @Default(false) bool isInstalled,
    @Default(false) bool isDownloading,
    @Default(0.0) double progress,
    @Default('gemma-4-E2B-it.litertlm') String modelId,
    String? error,
    @Default(<String, bool>{}) Map<String, bool> installedWhisperModels,
    @Default(false) bool isWhisperDownloading,
    @Default(0.0) double whisperProgress,
    @Default(AppSettings.defaultOnDeviceSttModelId) String whisperModelId,
    String? whisperError,
  }) = _ModelDownloadState;

  const ModelDownloadState._();

  /// Returns `true` if the specified on-device STT [sttModelId] is installed
  /// on disk (either a downloaded Edge Whisper variant or the Gemma 4 model
  /// when `sttModelId == 'gemma-4'`).
  bool isSttModelInstalled(String sttModelId) {
    if (sttModelId == 'gemma-4') {
      return isInstalled;
    }
    final variant = AppSettings.onDeviceSttModelFor(sttModelId);
    return installedWhisperModels[variant.id] == true ||
        installedWhisperModels[variant.filename] == true;
  }
}

/// Manages checking, downloading, and activating the Gemma 4 E2B `.litertlm`
/// model weights as well as on-device Edge Whisper STT variants via
/// `flutter_edge_ai`.
class ModelManager extends CubitSignal<ModelDownloadState> {
  ModelManager({
    this._isInstalledCheck,
    this._installRunner,
    this._isWhisperInstalledCheck,
    this._whisperInstallRunner,
    bool initialInstalled = false,
    bool initialWhisperInstalled = false,
  }) : super(
         initialState: ModelDownloadState(
           isInstalled: initialInstalled,
           installedWhisperModels: initialWhisperInstalled
               ? <String, bool>{
                   for (final v in AppSettings.whisperVariants) v.id: true,
                 }
               : const <String, bool>{},
         ),
       );

  static const String defaultModelFilename = 'gemma-4-E2B-it.litertlm';
  static final _log = AppLogger.of('ModelManager');

  final Future<bool> Function()? _isInstalledCheck;
  final Future<void> Function({
    required String downloadUrl,
    required void Function(double progress) onProgress,
    CancelToken? cancelToken,
  })?
  _installRunner;
  final Future<bool> Function(String modelId)? _isWhisperInstalledCheck;
  final Future<void> Function({
    required SupportedOnDeviceSttModel variant,
    required void Function(double progress) onProgress,
    CancelToken? cancelToken,
  })?
  _whisperInstallRunner;

  CancelToken? _activeCancelToken;
  Future<bool>? _activeDownloadFuture;
  bool _markedUninstalled = false;

  CancelToken? _activeWhisperCancelToken;
  Future<bool>? _activeWhisperDownloadFuture;
  final Set<String> _markedWhisperUninstalled = <String>{};

  /// Checks whether the Gemma 4 E2B model is already present on device.
  Future<bool> checkModelReady() async {
    if (_markedUninstalled) {
      _log.info('checkModelReady(): model was marked uninstalled -> false');
      if (!isClosed) {
        emit(stateValue.copyWith(isInstalled: false, error: null));
      }
      return false;
    }
    try {
      final bool installed;
      if (_isInstalledCheck != null) {
        installed = await _isInstalledCheck();
      } else {
        final hasActive = FlutterEdgeAi.hasActiveModel();
        final fileInstalled = await FlutterEdgeAi.isModelInstalled(
          defaultModelFilename,
        );
        installed = hasActive || fileInstalled;
        _log.info(
          'checkModelReady(): hasActiveModel=$hasActive, '
          'isModelInstalled($defaultModelFilename)=$fileInstalled -> installed=$installed',
        );
      }
      if (!isClosed) {
        emit(stateValue.copyWith(isInstalled: installed, error: null));
      }
      return installed;
    } on Object catch (e, st) {
      _log.warning('checkModelReady() threw an error; treating as not installed', e, st);
      if (!isClosed) {
        emit(stateValue.copyWith(isInstalled: false));
      }
      return false;
    }
  }

  /// Downloads and activates the Gemma 4 E2B `.litertlm` model weights.
  ///
  /// If a download is already in progress, awaits the in-flight download
  /// rather than failing or starting a duplicate transfer.
  Future<bool> ensureModelDownloaded({
    String fallbackUrl = AppSettings.defaultModelDownloadUrl,
  }) async {
    _log.info(
      'ensureModelDownloaded() called (state.isInstalled=${stateValue.isInstalled}, '
      'state.isDownloading=${stateValue.isDownloading})',
    );
    if (stateValue.isInstalled) {
      return true;
    }
    final inFlight = _activeDownloadFuture;
    if (inFlight != null) {
      _log.info(
        'ensureModelDownloaded(): joining in-progress model download future...',
      );
      return inFlight;
    }
    final alreadyReady = await checkModelReady();
    if (alreadyReady) {
      _log.info('ensureModelDownloaded(): model is already installed on disk.');
      return true;
    }
    _log.info('ensureModelDownloaded(): model not on disk; starting download...');
    return downloadModel(fallbackUrl: fallbackUrl);
  }

  /// Forces a download of the Gemma 4 E2B model weights, emitting progress.
  Future<bool> downloadModel({
    String fallbackUrl = AppSettings.defaultModelDownloadUrl,
  }) {
    if (stateValue.isDownloading) {
      _log.warning(
        'downloadModel() ignored because a download is already in progress.',
      );
      return Future<bool>.value(false);
    }

    final future = _performDownload(fallbackUrl: fallbackUrl);
    _activeDownloadFuture = future;
    return future;
  }

  Future<bool> _performDownload({
    required String fallbackUrl,
  }) async {
    final cancelToken = CancelToken();
    _activeCancelToken = cancelToken;
    _markedUninstalled = false;

    _log.info('Starting Gemma 4 E2B model download from: $fallbackUrl');
    emit(
      stateValue.copyWith(
        isDownloading: true,
        progress: 0.0,
        error: null,
      ),
    );

    var lastLoggedBucket = -1;

    try {
      if (_installRunner != null) {
        await _installRunner(
          downloadUrl: fallbackUrl,
          onProgress: (progress) {
            final clamped = progress.clamp(0.0, 1.0);
            final bucket = (clamped * 20).floor();
            if (bucket != lastLoggedBucket) {
              lastLoggedBucket = bucket;
              _log.info(
                'Model download progress: ${(clamped * 100).toStringAsFixed(1)}%',
              );
            }
            if (!isClosed) {
              emit(
                stateValue.copyWith(
                  progress: clamped,
                ),
              );
            }
          },
          cancelToken: cancelToken,
        );
      } else {
        await _defaultInstall(
          fallbackUrl: fallbackUrl,
          cancelToken: cancelToken,
          onProgress: (percent) {
            final clamped = (percent / 100.0).clamp(0.0, 1.0);
            final bucket = percent ~/ 5;
            if (bucket != lastLoggedBucket) {
              lastLoggedBucket = bucket;
              _log.info('Model download progress: $percent%');
            }
            if (!isClosed) {
              emit(
                stateValue.copyWith(
                  progress: clamped,
                ),
              );
            }
          },
        );
      }

      _log.info('Gemma 4 E2B model download & activation complete!');
      if (!isClosed) {
        emit(
          stateValue.copyWith(
            isInstalled: true,
            isDownloading: false,
            progress: 1.0,
            error: null,
          ),
        );
      }
      return true;
    } on DownloadCancelledException catch (e) {
      _log.warning('Gemma 4 E2B model download was cancelled: $e');
      if (!isClosed) {
        emit(
          stateValue.copyWith(
            isDownloading: false,
            error: 'Model download was cancelled.',
          ),
        );
      }
      return false;
    } on Object catch (e, st) {
      _log.severe('Gemma 4 E2B model download failed', e, st);
      if (!isClosed) {
        emit(
          stateValue.copyWith(
            isDownloading: false,
            error: 'Model download failed: $e',
          ),
        );
      }
      return false;
    } finally {
      _activeCancelToken = null;
      _activeDownloadFuture = null;
    }
  }

  Future<void> _defaultInstall({
    required String fallbackUrl,
    required CancelToken cancelToken,
    required void Function(int percent) onProgress,
  }) async {
    final trimmedUrl = fallbackUrl.trim();
    final effectiveUrl = trimmedUrl.isNotEmpty
        ? trimmedUrl
        : AppSettings.defaultModelDownloadUrl;

    _log.info(
      'Installing ModelType.gemma4 (ModelFileType.litertlm) via network URL: $effectiveUrl',
    );
    await FlutterEdgeAi.installModel(
          modelType: ModelType.gemma4,
          fileType: ModelFileType.litertlm,
        )
        .fromNetwork(effectiveUrl)
        .withProgress(onProgress)
        .withCancelToken(cancelToken)
        .install();
  }

  /// Cancels an in-progress model download.
  void cancelDownload() {
    _log.info('Cancelling in-progress model download...');
    _activeCancelToken?.cancel('Cancelled by user');
  }

  /// Marks the model as uninstalled in state (e.g., to re-download from Settings).
  void markUninstalled() {
    _log.info('Marking model as uninstalled.');
    _markedUninstalled = true;
    emit(
      stateValue.copyWith(
        isInstalled: false,
        isDownloading: false,
        progress: 0.0,
        error: null,
      ),
    );
  }

  /// Checks whether the specified Edge Whisper STT model (and all other catalog
  /// Whisper variants) are installed on device.
  Future<bool> checkWhisperModelReady([
    String modelId = AppSettings.defaultOnDeviceSttModelId,
  ]) async {
    final targetVariant = AppSettings.onDeviceSttModelFor(modelId);
    if (!targetVariant.isWhisper) {
      return checkModelReady();
    }

    final updatedMap = Map<String, bool>.of(stateValue.installedWhisperModels);

    for (final variant in AppSettings.whisperVariants) {
      if (_markedWhisperUninstalled.contains(variant.id)) {
        updatedMap[variant.id] = false;
        continue;
      }
      try {
        final bool installed;
        if (_isWhisperInstalledCheck != null) {
          installed = await _isWhisperInstalledCheck(variant.id);
        } else if (updatedMap[variant.id] == true && _isInstalledCheck != null) {
          // Preserve initialWhisperInstalled in in-memory test mode
          installed = true;
        } else {
          final fileInstalled = await FlutterEdgeAi.isModelInstalled(
            variant.filename,
          );
          final activeSpec = FlutterEdgeAi.activeSttSpec;
          final isActiveVariant =
              activeSpec != null &&
              variant.filename.startsWith(activeSpec.name);
          installed = fileInstalled || isActiveVariant;
        }
        updatedMap[variant.id] = installed;
      } on Object catch (e, st) {
        _log.fine(
          'checkWhisperModelReady(${variant.id}) threw an error; treating as not installed',
          e,
          st,
        );
        updatedMap[variant.id] = updatedMap[variant.id] ?? false;
      }
    }

    final isTargetReady = updatedMap[targetVariant.id] ?? false;
    if (!isClosed) {
      emit(
        stateValue.copyWith(
          installedWhisperModels: Map<String, bool>.unmodifiable(updatedMap),
          whisperModelId: targetVariant.id,
          whisperError: null,
        ),
      );
    }
    return isTargetReady;
  }

  /// Ensures the specified Edge Whisper STT model is downloaded and activated.
  Future<bool> ensureWhisperModelDownloaded([
    String modelId = AppSettings.defaultOnDeviceSttModelId,
  ]) async {
    final variant = AppSettings.onDeviceSttModelFor(modelId);
    if (!variant.isWhisper) {
      return ensureModelDownloaded();
    }
    if (stateValue.isSttModelInstalled(variant.id)) {
      return true;
    }
    final inFlight = _activeWhisperDownloadFuture;
    if (inFlight != null) {
      return inFlight;
    }
    final alreadyReady = await checkWhisperModelReady(variant.id);
    if (alreadyReady) {
      return true;
    }
    return downloadWhisperModel(variant.id);
  }

  /// Downloads and activates the specified Edge Whisper STT variant.
  Future<bool> downloadWhisperModel([
    String modelId = AppSettings.defaultOnDeviceSttModelId,
  ]) {
    final variant = AppSettings.onDeviceSttModelFor(modelId);
    if (!variant.isWhisper) {
      return downloadModel();
    }
    if (stateValue.isWhisperDownloading) {
      _log.warning(
        'downloadWhisperModel() ignored because a Whisper download is already in progress.',
      );
      return Future<bool>.value(false);
    }

    final future = _performWhisperDownload(variant: variant);
    _activeWhisperDownloadFuture = future;
    return future;
  }

  Future<bool> _performWhisperDownload({
    required SupportedOnDeviceSttModel variant,
  }) async {
    final cancelToken = CancelToken();
    _activeWhisperCancelToken = cancelToken;
    _markedWhisperUninstalled.remove(variant.id);

    _log.info(
      'Starting Edge Whisper STT download (${variant.name}, ${variant.sizeLabel}) '
      'from: ${variant.modelUrl}',
    );
    emit(
      stateValue.copyWith(
        isWhisperDownloading: true,
        whisperProgress: 0.0,
        whisperModelId: variant.id,
        whisperError: null,
      ),
    );

    try {
      if (_whisperInstallRunner != null) {
        await _whisperInstallRunner(
          variant: variant,
          onProgress: (progress) {
            final clamped = progress.clamp(0.0, 1.0);
            if (!isClosed) {
              emit(stateValue.copyWith(whisperProgress: clamped));
            }
          },
          cancelToken: cancelToken,
        );
      } else if (_installRunner != null) {
        await _installRunner(
          downloadUrl: variant.modelUrl ?? variant.filename,
          onProgress: (progress) {
            final clamped = progress.clamp(0.0, 1.0);
            if (!isClosed) {
              emit(stateValue.copyWith(whisperProgress: clamped));
            }
          },
          cancelToken: cancelToken,
        );
      } else {
        var modelPct = 0;
        var tokenizerPct = 0;
        void emitCombinedProgress() {
          // Model is ~98% of bytes, tokenizer is ~2%
          final combined = ((modelPct * 0.95) + (tokenizerPct * 0.05)) / 100.0;
          if (!isClosed) {
            emit(
              stateValue.copyWith(
                whisperProgress: combined.clamp(0.0, 1.0),
              ),
            );
          }
        }

        await FlutterEdgeAi.installStt()
            .modelFromNetwork(variant.modelUrl!)
            .tokenizerFromNetwork(variant.tokenizerUrl!)
            .ofType(SttModelType.whisper)
            .withModelProgress((p) {
              modelPct = p;
              emitCombinedProgress();
            })
            .withTokenizerProgress((p) {
              tokenizerPct = p;
              emitCombinedProgress();
            })
            .withCancelToken(cancelToken)
            .install();
      }

      _log.info('Edge Whisper (${variant.name}) download & activation complete!');
      if (!isClosed) {
        final updatedMap = <String, bool>{
          ...stateValue.installedWhisperModels,
          variant.id: true,
        };
        emit(
          stateValue.copyWith(
            installedWhisperModels: Map<String, bool>.unmodifiable(updatedMap),
            isWhisperDownloading: false,
            whisperProgress: 1.0,
            whisperModelId: variant.id,
            whisperError: null,
          ),
        );
      }
      return true;
    } on DownloadCancelledException catch (e) {
      _log.warning('Whisper model download was cancelled: $e');
      if (!isClosed) {
        emit(
          stateValue.copyWith(
            isWhisperDownloading: false,
            whisperError: 'Whisper model download was cancelled.',
          ),
        );
      }
      return false;
    } on Object catch (e, st) {
      _log.severe('Whisper model download failed', e, st);
      if (!isClosed) {
        emit(
          stateValue.copyWith(
            isWhisperDownloading: false,
            whisperError: 'Whisper download failed: $e',
          ),
        );
      }
      return false;
    } finally {
      _activeWhisperCancelToken = null;
      _activeWhisperDownloadFuture = null;
    }
  }

  /// Cancels an in-progress Whisper STT model download.
  void cancelWhisperDownload() {
    _log.info('Cancelling in-progress Whisper STT download...');
    _activeWhisperCancelToken?.cancel('Cancelled by user');
  }

  /// Marks a Whisper STT variant as uninstalled in state so it can be re-downloaded.
  void markWhisperUninstalled([
    String modelId = AppSettings.defaultOnDeviceSttModelId,
  ]) {
    final variant = AppSettings.onDeviceSttModelFor(modelId);
    _log.info('Marking Whisper model (${variant.id}) as uninstalled.');
    _markedWhisperUninstalled.add(variant.id);
    final updatedMap = <String, bool>{
      ...stateValue.installedWhisperModels,
      variant.id: false,
    };
    emit(
      stateValue.copyWith(
        installedWhisperModels: Map<String, bool>.unmodifiable(updatedMap),
        isWhisperDownloading: false,
        whisperProgress: 0.0,
        whisperModelId: variant.id,
        whisperError: null,
      ),
    );
  }
}
