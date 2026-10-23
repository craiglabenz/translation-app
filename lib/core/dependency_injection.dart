import 'package:data_layer/data_layer.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';
import 'package:translation_app/core/ai/local_translation_engine.dart';
import 'package:translation_app/core/ai/model_manager.dart';
import 'package:translation_app/core/ai/network_translation_engine.dart';
import 'package:translation_app/core/ai/switchable_translation_engine.dart';
import 'package:translation_app/core/ai/translation_engine.dart';
import 'package:translation_app/core/audio/native_audio_service.dart';
import 'package:translation_app/core/audio/vad_buffer.dart';
import 'package:translation_app/core/auth/auth.dart';
import 'package:translation_app/core/data/models/app_settings.dart';
import 'package:translation_app/core/data/models/conversation.dart';
import 'package:translation_app/core/data/models/exchange_rate_cache.dart';
import 'package:translation_app/core/data/models/message.dart';
import 'package:translation_app/core/data/repositories/conversation_repository.dart';
import 'package:translation_app/core/data/repositories/settings_repository.dart';
import 'package:translation_app/core/data/sources/frankfurter_api_source.dart';
import 'package:translation_app/core/data/sources/hive_sources.dart';
import 'package:translation_app/core/utils/platform_env.dart';
import 'package:translation_app/features/conversation/bloc/active_conversation_bloc.dart';
import 'package:translation_app/features/settings/bloc/settings_bloc.dart';

import 'dependency_injection.config.dart';

final getIt = GetIt.instance;

@InjectableInit(
  initializerName: 'init', // default
  preferRelativeImports: true, // default
  asExtension: true, // default
)
void configureDependencies({
  AuthPolicy authPolicy = const AuthPolicy.none(),
  bool? useInMemoryStorage,
}) {
  AuthModule.policy = authPolicy;
  getIt.init();

  final inMemory = useInMemoryStorage ?? isFlutterTestEnvironment;

  if (!getIt.isRegistered<SettingsRepository>()) {
    late final Source<AppSettings> settingsSource;
    late final Source<ExchangeRateCache> localRateSource;
    late final Source<Conversation> conversationSource;
    late final Source<Message> messageSource;

    if (inMemory) {
      settingsSource = LocalMemorySource<AppSettings>(
        bindings: AppSettings.bindings,
      );
      localRateSource = LocalMemorySource<ExchangeRateCache>(
        bindings: ExchangeRateCache.bindings,
      );
      conversationSource = LocalMemorySource<Conversation>(
        bindings: Conversation.bindings,
      );
      messageSource = LocalMemorySource<Message>(
        bindings: Message.bindings,
      );
    } else {
      final hiveInitializer = AppHiveInitializer();
      getIt.registerSingleton<AppHiveInitializer>(hiveInitializer);
      settingsSource = HiveSources.createSettingsSource(hiveInitializer);
      localRateSource = HiveSources.createExchangeRateSource(hiveInitializer);
      conversationSource = HiveSources.createConversationSource(
        hiveInitializer,
      );
      messageSource = HiveSources.createMessageSource(hiveInitializer);
    }

    final Source<ExchangeRateCache> remoteRateSource = inMemory
        ? RemoteMemorySource<ExchangeRateCache>(
            bindings: ExchangeRateCache.bindings,
          )
        : FrankfurterApiSource();

    getIt
      ..registerLazySingleton<SettingsRepository>(
        () => SettingsRepository(
          settingsSource: settingsSource,
          localExchangeRateSource: localRateSource,
          remoteExchangeRateSource: remoteRateSource,
        ),
        dispose: (repo) => repo.close(),
      )
      ..registerLazySingleton<ConversationRepository>(
        () => ConversationRepository(
          conversationSource: conversationSource,
          messageSource: messageSource,
        ),
        dispose: (repo) => repo.close(),
      );
  }

  if (!getIt.isRegistered<ModelManager>()) {
    getIt.registerLazySingleton<ModelManager>(
      () => ModelManager(
        initialInstalled: inMemory,
        isInstalledCheck: inMemory ? () async => true : null,
      ),
      dispose: (manager) => manager.close(),
    );
  }

  if (!getIt.isRegistered<TranslationEngine>()) {
    getIt.registerLazySingleton<TranslationEngine>(
      () {
        final localEngine = LocalTranslationEngine(
          modelManager: getIt<ModelManager>(),
        );
        final networkEngine = NetworkTranslationEngine(
          apiKeyProvider: () => getIt.isRegistered<SettingsBloc>()
              ? getIt<SettingsBloc>().stateValue.settings.geminiApiKey
              : '',
          modelIdProvider: () => getIt.isRegistered<SettingsBloc>()
              ? getIt<SettingsBloc>().stateValue.settings.cloudModelId
              : AppSettings.defaultCloudModelId,
        );
        return SwitchableTranslationEngine(
          localEngine: localEngine,
          networkEngine: networkEngine,
          initialMode: kIsWeb
              ? TranslationEngineMode.cloud
              : TranslationEngineMode.onDevice,
        );
      },
      dispose: (engine) => engine.dispose(),
    );
  }

  if (!getIt.isRegistered<NativeAudioService>()) {
    getIt.registerLazySingleton<NativeAudioService>(
      () => NativeAudioService(
        vadBuffer: VadBuffer(
          silenceCutoff: VadBuffer.interactiveSilenceCutoff,
          minSpeechDuration: VadBuffer.interactiveMinSpeechDuration,
          silenceThreshold: VadBuffer.interactiveSilenceThreshold,
        ),
      ),
      dispose: (service) => service.dispose(),
    );
  }

  if (!getIt.isRegistered<SettingsBloc>()) {
    getIt.registerLazySingleton<SettingsBloc>(
      () => SettingsBloc(
        settingsRepository: getIt<SettingsRepository>(),
        modelManager: getIt<ModelManager>(),
        translationEngine: getIt<TranslationEngine>(),
      ),
      dispose: (bloc) => bloc.close(),
    );
  }

  if (!getIt.isRegistered<ActiveConversationBloc>()) {
    getIt.registerFactory<ActiveConversationBloc>(
      () => ActiveConversationBloc(
        conversationRepository: getIt<ConversationRepository>(),
        settingsRepository: getIt<SettingsRepository>(),
        translationEngine: getIt<TranslationEngine>(),
        audioService: getIt<NativeAudioService>(),
      ),
    );
  }
}
