import 'dart:async';

import 'package:bloc_signals_flutter/bloc_signals_flutter.dart';
import 'package:get_it/get_it.dart';
import 'package:material_ui/material_ui.dart';
import 'package:translation_app/core/ai/model_manager.dart';
import 'package:translation_app/core/data/repositories/settings_repository.dart';
import 'package:translation_app/core/routing/routing.dart';
import 'package:translation_app/core/theme/app_theme.dart';
import 'package:translation_app/features/settings/bloc/settings_bloc.dart';

import 'core/core.dart';

late String serverUrl;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  configureDependencies();

  // Eagerly hydrate settings and exchange rates on startup.
  unawaited(GetIt.I<SettingsRepository>().hydrateOnStartup());

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
