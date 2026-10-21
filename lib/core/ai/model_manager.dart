import 'package:bloc_signals/bloc_signals.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:translation_app/core/data/models/app_settings.dart';

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

  final Future<bool> Function()? _isInstalledCheck;
  final Future<void> Function({
    required String downloadUrl,
    required void Function(double progress) onProgress,
    CancelToken? cancelToken,
  })?
  _installRunner;

  CancelToken? _activeCancelToken;
  bool _markedUninstalled = false;

  /// Checks whether the Gemma 4 E2B model is already present on device.
  Future<bool> checkModelReady() async {
    if (_markedUninstalled) {
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
        installed =
            FlutterEdgeAi.hasActiveModel() ||
            await FlutterEdgeAi.isModelInstalled(defaultModelFilename);
      }
      if (!isClosed) {
        emit(stateValue.copyWith(isInstalled: installed, error: null));
      }
      return installed;
    } on Object {
      if (!isClosed) {
        emit(stateValue.copyWith(isInstalled: false));
      }
      return false;
    }
  }

  /// Downloads and activates the Gemma 4 E2B `.litertlm` model weights.
  ///
  /// Uses `flutter_edge_ai`'s built-in Hugging Face manifest resolver first,
  /// falling back to the configured [fallbackUrl] if manifest resolution fails
  /// or if a custom URL was configured in Settings.
  Future<bool> ensureModelDownloaded({
    String fallbackUrl = AppSettings.defaultModelDownloadUrl,
  }) async {
    if (stateValue.isInstalled) {
      return true;
    }
    final alreadyReady = await checkModelReady();
    if (alreadyReady) {
      return true;
    }
    return downloadModel(fallbackUrl: fallbackUrl);
  }

  /// Forces a download of the Gemma 4 E2B model weights, emitting progress.
  Future<bool> downloadModel({
    String fallbackUrl = AppSettings.defaultModelDownloadUrl,
  }) async {
    if (stateValue.isDownloading) {
      return false;
    }

    final cancelToken = CancelToken();
    _activeCancelToken = cancelToken;
    _markedUninstalled = false;

    emit(
      stateValue.copyWith(
        isDownloading: true,
        progress: 0.0,
        error: null,
      ),
    );

    try {
      if (_installRunner != null) {
        await _installRunner(
          downloadUrl: fallbackUrl,
          onProgress: (progress) {
            if (!isClosed) {
              emit(
                stateValue.copyWith(
                  progress: progress.clamp(0.0, 1.0),
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
            if (!isClosed) {
              emit(
                stateValue.copyWith(
                  progress: (percent / 100.0).clamp(0.0, 1.0),
                ),
              );
            }
          },
        );
      }

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
    } on DownloadCancelledException {
      if (!isClosed) {
        emit(
          stateValue.copyWith(
            isDownloading: false,
            error: 'Model download was cancelled.',
          ),
        );
      }
      return false;
    } on Object catch (e) {
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
    }
  }

  Future<void> _defaultInstall({
    required String fallbackUrl,
    required CancelToken cancelToken,
    required void Function(int percent) onProgress,
  }) async {
    final trimmedUrl = fallbackUrl.trim();
    final isDefaultUrl =
        trimmedUrl.isEmpty || trimmedUrl == AppSettings.defaultModelDownloadUrl;

    if (isDefaultUrl) {
      try {
        await FlutterEdgeAi.installModel(
              modelType: ModelType.gemma4,
              fileType: ModelFileType.litertlm,
            )
            .fromHuggingFace(AppSettings.defaultHuggingFaceRepo)
            .withProgress(onProgress)
            .withCancelToken(cancelToken)
            .install();
        return;
      } on DownloadCancelledException {
        rethrow;
      } on Object {
        // Fall through to direct network URL download below.
      }
    }

    final effectiveUrl = trimmedUrl.isNotEmpty
        ? trimmedUrl
        : AppSettings.defaultModelDownloadUrl;

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
    _activeCancelToken?.cancel('Cancelled by user');
  }

  /// Marks the model as uninstalled in state (e.g., to re-download from Settings).
  void markUninstalled() {
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
