import 'package:bloc_signals/bloc_signals.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:translation_app/core/data/models/app_settings.dart';
import 'package:translation_app/core/logging/app_logger.dart';

part 'model_manager.freezed.dart';

/// Reactive state of the on-device Gemma 4 E2B model installation.
@freezed
abstract class ModelDownloadState with _$ModelDownloadState {
  const factory ModelDownloadState({
    @Default(false) bool isInstalled,
    @Default(false) bool isDownloading,
    @Default(0.0) double progress,
    @Default('gemma-4-E2B-it.litertlm') String modelId,
    String? error,
  }) = _ModelDownloadState;
}

/// Manages checking, downloading, and activating the Gemma 4 E2B `.litertlm`
/// model weights via `flutter_edge_ai`.
class ModelManager extends CubitSignal<ModelDownloadState> {
  ModelManager({
    this._isInstalledCheck,
    this._installRunner,
    bool initialInstalled = false,
  }) : super(initialState: ModelDownloadState(isInstalled: initialInstalled));

  static const String defaultModelFilename = 'gemma-4-E2B-it.litertlm';
  static final _log = AppLogger.of('ModelManager');

  final Future<bool> Function()? _isInstalledCheck;
  final Future<void> Function({
    required String downloadUrl,
    required void Function(double progress) onProgress,
    CancelToken? cancelToken,
  })?
  _installRunner;

  CancelToken? _activeCancelToken;
  Future<bool>? _activeDownloadFuture;
  bool _markedUninstalled = false;

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
}
