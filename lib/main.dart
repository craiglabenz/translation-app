import 'dart:async';
import 'dart:ui';

import 'package:bloc_signals_flutter/bloc_signals_flutter.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_edge_ai_litertlm/flutter_edge_ai_litertlm.dart';
import 'package:get_it/get_it.dart';
import 'package:material_ui/material_ui.dart';
import 'package:translation_app/core/ai/model_manager.dart';
import 'package:translation_app/core/data/repositories/settings_repository.dart';
import 'package:translation_app/core/logging/app_logger.dart';
import 'package:translation_app/core/routing/routing.dart';
import 'package:translation_app/core/theme/app_theme.dart';
import 'package:translation_app/features/settings/bloc/settings_bloc.dart';

import 'core/core.dart';

late String serverUrl;

final _log = AppLogger.of('Main');

Future<void> main() async {
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

  _log.info('Starting Gemma 4 Translator app initialization...');
  try {
    await FlutterEdgeAi.initialize(
      inferenceEngines: const [LiteRtLmEngine()],
    );
    FlutterEdgeAi.logLevel = EdgeAiLogLevel.verbose;
    _log.info('FlutterEdgeAi initialized with LiteRtLmEngine (logLevel=verbose).');
  } on Object catch (e, st) {
    _log.severe('Failed to initialize FlutterEdgeAi', e, st);
  }

  configureDependencies();
  _log.info('Dependency injection configured.');

  // Eagerly hydrate settings and exchange rates on startup.
  unawaited(
    GetIt.I<SettingsRepository>().hydrateOnStartup().then(
      (result) {
        final (settings, rate) = result;
        _log.info(
          'Startup hydration complete: pair=${settings.pairLabel}, '
          'rate=1 ${rate.baseCurrency} -> ${rate.rate} ${rate.targetCurrency} '
          '(isStale=${rate.isStale})',
        );
      },
      onError: (Object e, StackTrace st) {
        _log.severe('Startup hydration failed', e, st);
      },
    ),
  );

  _log.info('Calling runApp(MyApp)...');
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

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
