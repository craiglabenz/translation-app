import 'dart:async';
import 'dart:ui';

import 'package:bloc_signals_flutter/bloc_signals_flutter.dart';
import 'package:flow_ui/flow_ui.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_edge_ai_litertlm/flutter_edge_ai_litertlm.dart';
import 'package:flutter_edge_ai_speech/flutter_edge_ai_speech.dart';
import 'package:get_it/get_it.dart';
import 'package:material_ui/material_ui.dart';
import 'package:translation_app/core/ai/model_manager.dart';
import 'package:translation_app/core/ai/translation_engine.dart';
import 'package:translation_app/core/data/models/app_settings.dart';
import 'package:translation_app/core/data/repositories/conversation_repository.dart';
import 'package:translation_app/core/data/repositories/settings_repository.dart';
import 'package:translation_app/core/logging/app_logger.dart';
import 'package:translation_app/core/routing/routing.dart';
import 'package:translation_app/core/theme/app_theme.dart';
import 'package:translation_app/features/settings/bloc/settings_bloc.dart';

import 'core/core.dart';

late String serverUrl;

final _log = AppLogger.of('Main');

Future<void> main() async {
  final startupSw = Stopwatch()..start();
  WidgetsFlutterBinding.ensureInitialized();
  AppLogger.initLogging();

  FlutterError.onError = (FlutterErrorDetails details) {
    _log.severe(
      'Uncaught Flutter framework error: ${details.exceptionAsString()}',
      details.exception,
      details.stack,
    );
    FlutterError.presentError(details);
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    _log.severe('Uncaught PlatformDispatcher async error', error, stack);
    return true;
  };

  _log.info('[PERF] Starting Gemma 4 Translator app initialization...');
  try {
    final edgeSw = Stopwatch()..start();
    await FlutterEdgeAi.initialize(
      inferenceEngines: const [LiteRtLmEngine()],
      sttBackends: const [LiteRtSttBackend()],
    );
    FlutterEdgeAi.logLevel = EdgeAiLogLevel.verbose;
    edgeSw.stop();
    _log.info(
      '[PERF] FlutterEdgeAi initialized with LiteRtLmEngine & LiteRtSttBackend '
      '(${edgeSw.elapsedMilliseconds}ms, logLevel=verbose).',
    );
  } on Object catch (e, st) {
    _log.severe('Failed to initialize FlutterEdgeAi', e, st);
  }

  configureDependencies();
  _log.info(
    '[PERF] Dependency injection configured (${startupSw.elapsedMilliseconds}ms since main).',
  );

  // Touch FlowTypography.standard eagerly at startup so all GoogleSans font cuts
  // (including w600 used in ActiveChatView's AppBar) begin loading immediately
  // rather than on the first transition into a chat thread.
  final _ = FlowTypography.standard.titleSmallEmphasised;

  // Eagerly hydrate settings, exchange rates, and Conversation/Message Hive boxes
  // on startup so opening messages_box never blocks the first chat thread transition.
  unawaited(
    GetIt.I<SettingsRepository>().hydrateOnStartup().then(
      (result) {
        final (settings, rate) = result;
        _log.info(
          '[PERF] Startup hydration complete: pair=${settings.pairLabel}, '
          'rate=1 ${rate.baseCurrency} -> ${rate.rate} ${rate.targetCurrency} '
          '(isStale=${rate.isStale})',
        );
      },
      onError: (Object e, StackTrace st) {
        _log.severe('Startup hydration failed', e, st);
      },
    ),
  );

  unawaited(
    GetIt.I<ConversationRepository>().warmup().catchError((
      Object e,
      StackTrace st,
    ) {
      _log.warning('Startup ConversationRepository warmup failed', e, st);
    }),
  );

  // Optimistically preload the Gemma 4 LiteRT-LM model into memory after the
  // initial UI frame renders if the weights are already installed on disk.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(
      GetIt.I<ModelManager>().checkModelReady().then(
        (ready) async {
          if (!ready) {
            _log.info(
              '[PERF] Gemma 4 model not yet installed at startup; skipping eager warmup.',
            );
            return;
          }
          final preloadSw = Stopwatch()..start();
          _log.info(
            '[PERF] Gemma 4 model is installed; optimistically preloading into memory...',
          );
          try {
            await GetIt.I<TranslationEngine>().initialize();
            preloadSw.stop();
            _log.info(
              '[PERF] Startup Gemma 4 model preload complete '
              '(${preloadSw.elapsedMilliseconds}ms)!',
            );
          } on Object catch (e, st) {
            _log.warning('Startup Gemma 4 model preload failed', e, st);
          }
        },
        onError: (Object e, StackTrace st) {
          _log.warning('Startup model readiness check failed', e, st);
        },
      ),
    );
  });

  _log.info(
    '[PERF] Calling runApp(MyApp) (${startupSw.elapsedMilliseconds}ms since main)...',
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  /// Multiplies the user-selected [userMultiplier] (`0.5` to `3.0`) against the
  /// ambient OS-level [osTextScaler] instead of overwriting it.
  static TextScaler computeEffectiveTextScaler(
    TextScaler osTextScaler,
    double userMultiplier,
  ) {
    final clampedMultiplier = userMultiplier.clamp(
      AppSettings.minTextScaleFactor,
      AppSettings.maxTextScaleFactor,
    );
    final osScaleFactor = osTextScaler.scale(1.0);
    return TextScaler.linear(osScaleFactor * clampedMultiplier);
  }

  @override
  Widget build(BuildContext context) {
    final settingsBloc = GetIt.I<SettingsBloc>();
    final modelManager = GetIt.I<ModelManager>();

    return MultiBlocSignalProvider(
      providers: [
        BlocSignalProvider<SettingsBloc>.value(value: settingsBloc),
        BlocSignalProvider<ModelManager>.value(value: modelManager),
      ],
      child: MaterialApp.router(
        title: 'Gemma 4 Translator',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.system,
        routerConfig: GetIt.I<AppRouter>().config,
      ),
    );
  }
}
