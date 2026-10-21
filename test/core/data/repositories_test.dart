import 'dart:io';

import 'package:data_layer/data_layer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:translation_app/core/data/models/app_settings.dart';
import 'package:translation_app/core/data/models/conversation.dart';
import 'package:translation_app/core/data/models/exchange_rate_cache.dart';
import 'package:translation_app/core/data/models/message.dart';
import 'package:translation_app/core/data/repositories/conversation_repository.dart';
import 'package:translation_app/core/data/repositories/settings_repository.dart';
import 'package:translation_app/core/data/sources/hive_sources.dart';

class _OfflineExchangeRateSource extends RemoteMemorySource<ExchangeRateCache> {
  _OfflineExchangeRateSource() : super(bindings: ExchangeRateCache.bindings);

  @override
  Future<ReadResult<ExchangeRateCache>> getById(
    ReadOperation<ExchangeRateCache> operation,
  ) async {
    return const ReadFailure<ExchangeRateCache>(
      FailureReason.connectivity,
      'Simulated offline failure',
    );
  }
}

void main() {
  group('SettingsRepository', () {
    late DateTime now;
    late LocalMemorySource<AppSettings> settingsSource;
    late LocalMemorySource<ExchangeRateCache> localRateSource;
    late RemoteMemorySource<ExchangeRateCache> remoteRateSource;
    late SettingsRepository repo;

    setUp(() {
      now = DateTime.utc(2026, 1, 1, 12);
      settingsSource = LocalMemorySource<AppSettings>(
        bindings: AppSettings.bindings,
        now: () => now,
      );
      localRateSource = LocalMemorySource<ExchangeRateCache>(
        bindings: ExchangeRateCache.bindings,
        now: () => now,
      );
      remoteRateSource = RemoteMemorySource<ExchangeRateCache>(
        bindings: ExchangeRateCache.bindings,
        now: () => now,
      );
      repo = SettingsRepository(
        settingsSource: settingsSource,
        localExchangeRateSource: localRateSource,
        remoteExchangeRateSource: remoteRateSource,
        getTime: () => now,
      );
    });

    tearDown(() {
      repo.close();
    });

    test('getSettings initializes and persists default AppSettings when none exist', () async {
      final initial = await repo.getSettings();
      expect(initial, equals(const AppSettings()));

      // Verify it was saved into settingsSource
      final persisted = await settingsSource.getById(
        ReadOperation<AppSettings>(
          operationId: 'check',
          itemId: AppSettings.defaultId,
          details: RequestDetails.read(requestType: RequestType.local),
          createdAt: now,
        ),
      );
      expect(persisted, isA<ReadSuccess<AppSettings>>());
      expect((persisted as ReadSuccess<AppSettings>).item, equals(initial));
    });

    test('saveSettings persists updated values returned by subsequent getSettings', () async {
      const updated = AppSettings(
        baseLanguage: 'fr',
        targetLanguage: 'de',
        baseCurrency: 'EUR',
        targetCurrency: 'CHF',
        modelDownloadUrl: 'https://example.org/custom.litertlm',
      );
      final saved = await repo.saveSettings(updated);
      expect(saved, equals(updated));

      final fetched = await repo.getSettings();
      expect(fetched, equals(updated));
    });

    test('getExchangeRate returns 1.0 for identical currencies without hitting remote', () async {
      final rate = await repo.getExchangeRate(
        baseCurrency: 'eur',
        targetCurrency: 'EUR',
      );
      expect(rate.baseCurrency, 'EUR');
      expect(rate.targetCurrency, 'EUR');
      expect(rate.rate, 1.0);
      expect(rate.isStale, isFalse);
      expect(repo.lastHydratedRate, equals(rate));
    });

    test('returns cached exchange rate when < 7 days old and refreshes when expired', () async {
      await remoteRateSource.setItem(
        WriteOperation<ExchangeRateCache>(
          operationId: 'seed_1',
          item: ExchangeRateCache(
            baseCurrency: 'USD',
            targetCurrency: 'EUR',
            rate: 0.92,
            updatedAt: now,
          ),
          details: RequestDetails.write(),
          createdAt: now,
        ),
      );

      // 1. First call fetches from remote and caches locally
      final initial = await repo.getExchangeRate(
        baseCurrency: 'USD',
        targetCurrency: 'EUR',
      );
      expect(initial.rate, 0.92);
      expect(initial.isStale, isFalse);
      expect(repo.lastHydratedRate, equals(initial));

      // 2. Update remote to 0.95, advance clock by 3 days (< 7 days TTL)
      now = now.add(const Duration(days: 3));
      await remoteRateSource.setItem(
        WriteOperation<ExchangeRateCache>(
          operationId: 'seed_2',
          item: ExchangeRateCache(
            baseCurrency: 'USD',
            targetCurrency: 'EUR',
            rate: 0.95,
            updatedAt: now,
          ),
          details: RequestDetails.write(),
          createdAt: now,
        ),
      );

      // Should still return 0.92 from local cache without hitting remote
      final cached = await repo.getExchangeRate(
        baseCurrency: 'USD',
        targetCurrency: 'EUR',
      );
      expect(cached.rate, 0.92);
      expect(cached.isStale, isFalse);

      // 3. Advance clock by 4 more days (exact 7 days TTL boundary)
      now = now.add(const Duration(days: 4));
      final refreshed = await repo.getExchangeRate(
        baseCurrency: 'USD',
        targetCurrency: 'EUR',
      );
      expect(refreshed.rate, 0.95);
      expect(refreshed.isStale, isFalse);
    });

    test('forceRefresh: true bypasses fresh local cache and updates from remote', () async {
      await localRateSource.setItem(
        WriteOperation<ExchangeRateCache>(
          operationId: 'local_1',
          item: ExchangeRateCache(
            baseCurrency: 'USD',
            targetCurrency: 'GBP',
            rate: 0.78,
            updatedAt: now,
          ),
          details: RequestDetails.write(requestType: RequestType.local),
          createdAt: now,
        ),
      );
      await remoteRateSource.setItem(
        WriteOperation<ExchangeRateCache>(
          operationId: 'remote_1',
          item: ExchangeRateCache(
            baseCurrency: 'USD',
            targetCurrency: 'GBP',
            rate: 0.81,
            updatedAt: now,
          ),
          details: RequestDetails.write(),
          createdAt: now,
        ),
      );

      // Without forceRefresh -> returns 0.78
      final fromCache = await repo.getExchangeRate(
        baseCurrency: 'USD',
        targetCurrency: 'GBP',
      );
      expect(fromCache.rate, 0.78);

      // With forceRefresh -> fetches 0.81 from remote and updates local cache
      final forced = await repo.getExchangeRate(
        baseCurrency: 'USD',
        targetCurrency: 'GBP',
        forceRefresh: true,
      );
      expect(forced.rate, 0.81);
      expect(forced.isStale, isFalse);

      // Subsequent local read now returns 0.81
      final afterForce = await repo.getExchangeRate(
        baseCurrency: 'USD',
        targetCurrency: 'GBP',
      );
      expect(afterForce.rate, 0.81);
    });

    test('falls back to expired cached rate with isStale: true when offline', () async {
      await localRateSource.setItem(
        WriteOperation<ExchangeRateCache>(
          operationId: 'seed_local',
          item: ExchangeRateCache(
            baseCurrency: 'USD',
            targetCurrency: 'EUR',
            rate: 0.91,
            updatedAt: now,
          ),
          details: RequestDetails.write(requestType: RequestType.local),
          createdAt: now,
        ),
      );

      // Advance 10 days past TTL while offline
      now = now.add(const Duration(days: 10));

      final offlineRepo = SettingsRepository(
        settingsSource: settingsSource,
        localExchangeRateSource: localRateSource,
        remoteExchangeRateSource: _OfflineExchangeRateSource(),
        getTime: () => now,
      );

      final fallback = await offlineRepo.getExchangeRate(
        baseCurrency: 'USD',
        targetCurrency: 'EUR',
      );
      expect(fallback.rate, 0.91);
      expect(fallback.isStale, isTrue);
      expect(offlineRepo.lastHydratedRate, equals(fallback));

      offlineRepo.close();
    });

    test('falls back to 1.0 with isStale: true when offline on first boot with empty cache', () async {
      final offlineRepo = SettingsRepository(
        settingsSource: settingsSource,
        localExchangeRateSource: localRateSource,
        remoteExchangeRateSource: _OfflineExchangeRateSource(),
        getTime: () => now,
      );

      final fallback = await offlineRepo.getExchangeRate(
        baseCurrency: 'USD',
        targetCurrency: 'JPY',
      );
      expect(fallback.baseCurrency, 'USD');
      expect(fallback.targetCurrency, 'JPY');
      expect(fallback.rate, 1.0);
      expect(fallback.isStale, isTrue);

      offlineRepo.close();
    });

    test('hydrateOnStartup loads both settings and exchange rate for configured currencies', () async {
      await repo.saveSettings(
        const AppSettings(
          baseLanguage: 'en',
          targetLanguage: 'ja',
          baseCurrency: 'USD',
          targetCurrency: 'JPY',
        ),
      );
      await remoteRateSource.setItem(
        WriteOperation<ExchangeRateCache>(
          operationId: 'seed_jpy',
          item: ExchangeRateCache(
            baseCurrency: 'USD',
            targetCurrency: 'JPY',
            rate: 151.25,
            updatedAt: now,
          ),
          details: RequestDetails.write(),
          createdAt: now,
        ),
      );

      final (settings, rate) = await repo.hydrateOnStartup();
      expect(settings.targetLanguage, 'ja');
      expect(settings.targetCurrency, 'JPY');
      expect(rate.baseCurrency, 'USD');
      expect(rate.targetCurrency, 'JPY');
      expect(rate.rate, 151.25);
    });
  });

  group('ConversationRepository', () {
    late DateTime clock;
    late LocalMemorySource<Conversation> convSource;
    late LocalMemorySource<Message> msgSource;
    late ConversationRepository repo;

    setUp(() {
      clock = DateTime.utc(2026, 3, 1, 10);
      convSource = LocalMemorySource<Conversation>(
        bindings: Conversation.bindings,
        now: () => clock,
      );
      msgSource = LocalMemorySource<Message>(
        bindings: Message.bindings,
        now: () => clock,
      );
      repo = ConversationRepository(
        conversationSource: convSource,
        messageSource: msgSource,
        getTime: () => clock,
      );
    });

    tearDown(() {
      repo.close();
    });

    test('createConversation generates ID, sets createdAt, and notifies listeners', () async {
      var changeEvents = 0;
      final sub = repo.onConversationsChanged.listen((_) => changeEvents++);

      final conv = await repo.createConversation(
        baseLanguage: 'en',
        targetLanguage: 'es',
        previewText: 'Initial preview',
      );

      expect(conv.id, startsWith('conv_'));
      expect(conv.createdAt, clock);
      expect(conv.baseLanguage, 'en');
      expect(conv.targetLanguage, 'es');
      expect(conv.previewText, 'Initial preview');

      await Future<void>.delayed(Duration.zero);
      expect(changeEvents, 1);
      await sub.cancel();
    });

    test('createConversation preserves explicit ID when provided', () async {
      final conv = await repo.createConversation(
        id: 'explicit_conv_id',
        baseLanguage: 'fr',
        targetLanguage: 'de',
      );
      expect(conv.id, 'explicit_conv_id');
      expect(await repo.getConversationById('explicit_conv_id'), equals(conv));
    });

    test('getConversationById returns null for unknown ID', () async {
      expect(await repo.getConversationById('does_not_exist'), isNull);
    });

    test('updateConversation persists updated fields and emits change event', () async {
      final conv = await repo.createConversation(
        baseLanguage: 'en',
        targetLanguage: 'es',
      );
      final updated = await repo.updateConversation(
        conv.copyWith(previewText: 'Updated preview text'),
      );
      expect(updated.previewText, 'Updated preview text');
      final reloaded = await repo.getConversationById(conv.id);
      expect(reloaded?.previewText, 'Updated preview text');
    });

    test('getAllConversations and getRecentConversations sort newest-first', () async {
      final c1 = await repo.createConversation(
        id: 'c1',
        baseLanguage: 'en',
        targetLanguage: 'es',
      );
      clock = clock.add(const Duration(minutes: 10));
      final c2 = await repo.createConversation(
        id: 'c2',
        baseLanguage: 'en',
        targetLanguage: 'fr',
      );
      clock = clock.add(const Duration(minutes: 10));
      final c3 = await repo.createConversation(
        id: 'c3',
        baseLanguage: 'en',
        targetLanguage: 'de',
      );
      clock = clock.add(const Duration(minutes: 10));
      final c4 = await repo.createConversation(
        id: 'c4',
        baseLanguage: 'en',
        targetLanguage: 'ja',
      );

      final all = await repo.getAllConversations();
      expect(all.map((c) => c.id).toList(), <String>['c4', 'c3', 'c2', 'c1']);

      final top3 = await repo.getRecentConversations(limit: 3);
      expect(top3.map((c) => c.id).toList(), <String>[c4.id, c3.id, c2.id]);

      final top10 = await repo.getRecentConversations(limit: 10);
      expect(top10.map((c) => c.id).toList(), <String>[
        c4.id,
        c3.id,
        c2.id,
        c1.id,
      ]);
    });

    test('saveMessage updates parent conversation previewText only when non-empty', () async {
      final conv = await repo.createConversation(
        baseLanguage: 'en',
        targetLanguage: 'es',
        previewText: 'First preview',
      );

      await repo.saveMessage(
        Message(
          id: '',
          conversationId: conv.id,
          timestamp: clock,
          isBaseLanguage: true,
          originalText: 'Hello',
          translatedText: '  Hola a todos  ',
        ),
      );
      expect(
        (await repo.getConversationById(conv.id))?.previewText,
        'Hola a todos',
      );

      // Saving a message with whitespace-only translatedText preserves previous previewText
      await repo.saveMessage(
        Message(
          id: '',
          conversationId: conv.id,
          timestamp: clock.add(const Duration(seconds: 5)),
          isBaseLanguage: true,
          originalText: '...',
          translatedText: '   ',
        ),
      );
      expect(
        (await repo.getConversationById(conv.id))?.previewText,
        'Hola a todos',
      );
    });

    test('getMessagesForConversation filters by conversationId and sorts oldest-first', () async {
      final convA = await repo.createConversation(
        id: 'conv_A',
        baseLanguage: 'en',
        targetLanguage: 'es',
      );
      final convB = await repo.createConversation(
        id: 'conv_B',
        baseLanguage: 'en',
        targetLanguage: 'fr',
      );

      // Save out of chronological order
      await repo.saveMessage(
        Message(
          id: 'm_late',
          conversationId: convA.id,
          timestamp: clock.add(const Duration(minutes: 5)),
          isBaseLanguage: false,
          originalText: 'Deux',
          translatedText: 'Second message',
        ),
      );
      await repo.saveMessage(
        Message(
          id: 'm_other',
          conversationId: convB.id,
          timestamp: clock.add(const Duration(minutes: 2)),
          isBaseLanguage: true,
          originalText: 'Other',
          translatedText: 'Autre',
        ),
      );
      await repo.saveMessage(
        Message(
          id: 'm_early',
          conversationId: convA.id,
          timestamp: clock.add(const Duration(minutes: 1)),
          isBaseLanguage: true,
          originalText: 'Un',
          translatedText: 'First message',
        ),
      );

      final convAMessages = await repo.getMessagesForConversation(convA.id);
      expect(convAMessages.map((m) => m.id).toList(), <String>[
        'm_early',
        'm_late',
      ]);

      final convBMessages = await repo.getMessagesForConversation(convB.id);
      expect(convBMessages.map((m) => m.id).toList(), <String>['m_other']);
    });

    test('deleteConversation removes target conversation and its messages while preserving others', () async {
      final convA = await repo.createConversation(
        id: 'conv_A',
        baseLanguage: 'en',
        targetLanguage: 'es',
      );
      final convB = await repo.createConversation(
        id: 'conv_B',
        baseLanguage: 'en',
        targetLanguage: 'fr',
      );

      await repo.saveMessage(
        Message(
          id: 'm_a1',
          conversationId: convA.id,
          timestamp: clock,
          isBaseLanguage: true,
          originalText: 'Hi',
          translatedText: 'Hola',
        ),
      );
      await repo.saveMessage(
        Message(
          id: 'm_b1',
          conversationId: convB.id,
          timestamp: clock,
          isBaseLanguage: true,
          originalText: 'Hi',
          translatedText: 'Salut',
        ),
      );

      await repo.deleteConversation(convA.id);

      expect(await repo.getConversationById(convA.id), isNull);
      expect(await repo.getMessagesForConversation(convA.id), isEmpty);

      // convB and its messages remain untouched
      expect(await repo.getConversationById(convB.id), isNotNull);
      expect(await repo.getMessagesForConversation(convB.id), hasLength(1));
    });
  });

  group('End-to-End HiveSources Persistence', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('hive_repo_e2e_test_');
    });

    tearDown(() async {
      await Hive.close();
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('HiveSources persists settings, exchange rates, conversations, and messages', () async {
      final initializer = AppHiveInitializer(storagePath: tempDir.path);
      final settingsSource = HiveSources.createSettingsSource(initializer);
      final rateSource = HiveSources.createExchangeRateSource(initializer);
      final convSource = HiveSources.createConversationSource(initializer);
      final msgSource = HiveSources.createMessageSource(initializer);

      final clock = DateTime.utc(2026, 3, 1, 10);
      final remoteRateSource = RemoteMemorySource<ExchangeRateCache>(
        bindings: ExchangeRateCache.bindings,
        now: () => clock,
      );
      await remoteRateSource.setItem(
        WriteOperation<ExchangeRateCache>(
          operationId: 'seed_rate',
          item: ExchangeRateCache(
            baseCurrency: 'USD',
            targetCurrency: 'EUR',
            rate: 0.94,
            updatedAt: clock,
          ),
          details: RequestDetails.write(),
          createdAt: clock,
        ),
      );

      final settingsRepo = SettingsRepository(
        settingsSource: settingsSource,
        localExchangeRateSource: rateSource,
        remoteExchangeRateSource: remoteRateSource,
        getTime: () => clock,
      );
      final convRepo = ConversationRepository(
        conversationSource: convSource,
        messageSource: msgSource,
        getTime: () => clock,
      );

      await settingsRepo.ready;
      await convRepo.ready;

      await settingsRepo.saveSettings(
        const AppSettings(baseLanguage: 'pt', targetLanguage: 'en'),
      );
      final rate = await settingsRepo.getExchangeRate(
        baseCurrency: 'USD',
        targetCurrency: 'EUR',
      );
      expect(rate.rate, 0.94);

      final conv = await convRepo.createConversation(
        baseLanguage: 'pt',
        targetLanguage: 'en',
      );
      await convRepo.saveMessage(
        Message(
          id: '',
          conversationId: conv.id,
          timestamp: clock,
          isBaseLanguage: true,
          originalText: 'Bom dia',
          translatedText: 'Good morning',
        ),
      );

      final loadedSettings = await settingsRepo.getSettings();
      expect(loadedSettings.baseLanguage, 'pt');

      final loadedMessages = await convRepo.getMessagesForConversation(conv.id);
      expect(loadedMessages, hasLength(1));
      expect(loadedMessages.first.translatedText, 'Good morning');

      settingsRepo.close();
      convRepo.close();
    });
  });
}
