import 'dart:io';

import 'package:data_layer_hive/data_layer_hive.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:translation_app/core/data/models/app_settings.dart';
import 'package:translation_app/core/data/models/conversation.dart';
import 'package:translation_app/core/data/models/exchange_rate_cache.dart';
import 'package:translation_app/core/data/models/message.dart';

/// Initializes Hive and registers all domain [TypeAdapter]s.
class AppHiveInitializer extends HiveInitializer {
  AppHiveInitializer({
    HiveInterface? hive,
    this.storagePath,
  }) : _hive = hive ?? Hive;

  final HiveInterface _hive;
  final String? storagePath;

  HiveInterface get hive => _hive;

  @override
  Future<void> performInitialization() async {
    if (storagePath != null) {
      _hive.init(storagePath);
    } else {
      try {
        await _hive.initFlutter();
      } on Object {
        final fallbackDir = await Directory.systemTemp.createTemp(
          'translation_app_hive_',
        );
        _hive.init(fallbackDir.path);
      }
    }

    registerAdapters(_hive);
    markReady(null);
  }

  /// Registers all Hive adapters on [hive] idempotently.
  static void registerAdapters(HiveInterface hive) {
    final appSettingsAdapter = AppSettingsAdapter();
    if (!hive.isAdapterRegistered(appSettingsAdapter.typeId)) {
      hive.registerAdapter<AppSettings>(appSettingsAdapter);
    }

    final exchangeRateAdapter = ExchangeRateCacheAdapter();
    if (!hive.isAdapterRegistered(exchangeRateAdapter.typeId)) {
      hive.registerAdapter<ExchangeRateCache>(exchangeRateAdapter);
    }

    final conversationAdapter = ConversationAdapter();
    if (!hive.isAdapterRegistered(conversationAdapter.typeId)) {
      hive.registerAdapter<Conversation>(conversationAdapter);
    }

    final messageAdapter = MessageAdapter();
    if (!hive.isAdapterRegistered(messageAdapter.typeId)) {
      hive.registerAdapter<Message>(messageAdapter);
    }
  }
}

/// Factory helpers and box names for the app's [HiveSource] instances.
class HiveSources {
  const HiveSources._();

  static const String settingsBoxName = 'settings_box';
  static const String exchangeRatesBoxName = 'exchange_rates_box';
  static const String conversationsBoxName = 'conversations_box';
  static const String messagesBoxName = 'messages_box';

  static HiveSource<AppSettings> createSettingsSource(
    AppHiveInitializer initializer,
  ) {
    return HiveSource<AppSettings>(
      bindings: AppSettings.bindings,
      boxName: settingsBoxName,
      hiveInit: initializer.ready,
      hive: initializer.hive,
    );
  }

  static HiveSource<ExchangeRateCache> createExchangeRateSource(
    AppHiveInitializer initializer,
  ) {
    return HiveSource<ExchangeRateCache>(
      bindings: ExchangeRateCache.bindings,
      boxName: exchangeRatesBoxName,
      hiveInit: initializer.ready,
      hive: initializer.hive,
    );
  }

  static HiveSource<Conversation> createConversationSource(
    AppHiveInitializer initializer,
  ) {
    return HiveSource<Conversation>(
      bindings: Conversation.bindings,
      boxName: conversationsBoxName,
      hiveInit: initializer.ready,
      hive: initializer.hive,
    );
  }

  static HiveSource<Message> createMessageSource(
    AppHiveInitializer initializer,
  ) {
    return HiveSource<Message>(
      bindings: Message.bindings,
      boxName: messagesBoxName,
      hiveInit: initializer.ready,
      hive: initializer.hive,
    );
  }
}
