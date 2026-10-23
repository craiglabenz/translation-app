import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:translation_app/core/data/models/app_settings.dart';
import 'package:translation_app/core/data/models/conversation.dart';
import 'package:translation_app/core/data/models/exchange_rate_cache.dart';
import 'package:translation_app/core/data/models/message.dart';
import 'package:translation_app/core/data/sources/hive_sources.dart';

void main() {
  group('SupportedLanguage', () {
    test('supports value equality, copyWith, and JSON round-trip', () {
      const lang1 = SupportedLanguage(
        code: 'en',
        name: 'English',
        nativeName: 'English',
      );
      const lang2 = SupportedLanguage(
        code: 'en',
        name: 'English',
        nativeName: 'English',
      );
      expect(lang1, equals(lang2));
      expect(lang1.hashCode, equals(lang2.hashCode));

      final modified = lang1.copyWith(nativeName: 'English (US)');
      expect(modified.code, 'en');
      expect(modified.nativeName, 'English (US)');
      expect(modified, isNot(equals(lang1)));

      final json = lang1.toJson();
      final restored = SupportedLanguage.fromJson(json);
      expect(restored, equals(lang1));
    });

    test('AppSettings.supportedLanguages contains expected languages', () {
      final codes = AppSettings.supportedLanguages.map((l) => l.code).toList();
      expect(codes, containsAll(<String>['en', 'es', 'fr', 'de', 'it', 'pt', 'ja', 'ko', 'zh']));
      expect(codes.toSet().length, codes.length);
      for (final lang in AppSettings.supportedLanguages) {
        expect(lang.code, isNotEmpty);
        expect(lang.name, isNotEmpty);
        expect(lang.nativeName, isNotEmpty);
        expect(lang.flagEmoji, isNot('🌐'));
      }
      expect(AppSettings.languageFlagFor('en'), '🇺🇸');
      expect(AppSettings.languageFlagFor('en-US'), '🇺🇸');
      expect(AppSettings.languageFlagFor('English'), '🇺🇸');
      expect(AppSettings.languageFlagFor('ko'), '🇰🇷');
      expect(AppSettings.languageFlagFor('ko-KR'), '🇰🇷');
      expect(AppSettings.languageFlagFor('Korean'), '🇰🇷');
      expect(AppSettings.languageFlagFor('es'), '🇪🇸');
      expect(AppSettings.languageFlagFor('ja'), '🇯🇵');
      expect(AppSettings.languageFlagFor('zh'), '🇨🇳');

      // Verify every supported language maps to a supported currency
      final currencyCodes = AppSettings.supportedCurrencies
          .map((c) => c.code)
          .toSet();
      for (final lang in AppSettings.supportedLanguages) {
        expect(
          currencyCodes,
          contains(lang.defaultCurrencyCode),
          reason: '${lang.code} should map to a valid SupportedCurrency',
        );
      }
      expect(AppSettings.defaultCurrencyForLanguage('en'), 'USD');
      expect(AppSettings.defaultCurrencyForLanguage('en-GB'), 'GBP');
      expect(AppSettings.defaultCurrencyForLanguage('en-CA'), 'CAD');
      expect(AppSettings.defaultCurrencyForLanguage('en-AU'), 'AUD');
      expect(AppSettings.defaultCurrencyForLanguage('es'), 'EUR');
      expect(AppSettings.defaultCurrencyForLanguage('es-MX'), 'MXN');
      expect(AppSettings.defaultCurrencyForLanguage('fr'), 'EUR');
      expect(AppSettings.defaultCurrencyForLanguage('fr-CH'), 'CHF');
      expect(AppSettings.defaultCurrencyForLanguage('de'), 'EUR');
      expect(AppSettings.defaultCurrencyForLanguage('it'), 'EUR');
      expect(AppSettings.defaultCurrencyForLanguage('pt'), 'EUR');
      expect(AppSettings.defaultCurrencyForLanguage('pt-BR'), 'BRL');
      expect(AppSettings.defaultCurrencyForLanguage('ja'), 'JPY');
      expect(AppSettings.defaultCurrencyForLanguage('ko'), 'KRW');
      expect(AppSettings.defaultCurrencyForLanguage('zh'), 'CNY');
      expect(AppSettings.defaultCurrencyForLanguage('unknown'), isNull);
    });
  });

  group('SupportedCurrency', () {
    test('supports value equality, copyWith, and JSON round-trip', () {
      const curr1 = SupportedCurrency(
        code: 'USD',
        name: 'US Dollar',
        symbol: r'$',
      );
      const curr2 = SupportedCurrency(
        code: 'USD',
        name: 'US Dollar',
        symbol: r'$',
      );
      expect(curr1, equals(curr2));
      expect(curr1.hashCode, equals(curr2.hashCode));

      final modified = curr1.copyWith(symbol: r'US$');
      expect(modified.symbol, r'US$');

      final json = curr1.toJson();
      final restored = SupportedCurrency.fromJson(json);
      expect(restored, equals(curr1));
    });

    test('AppSettings.supportedCurrencies contains expected ISO currencies', () {
      final codes = AppSettings.supportedCurrencies.map((c) => c.code).toList();
      expect(
        codes,
        containsAll(<String>[
          'USD',
          'EUR',
          'GBP',
          'JPY',
          'CHF',
          'CAD',
          'AUD',
          'MXN',
          'BRL',
          'KRW',
          'CNY',
        ]),
      );
      expect(codes.toSet().length, codes.length);
      for (final curr in AppSettings.supportedCurrencies) {
        expect(curr.code, hasLength(3));
        expect(curr.name, isNotEmpty);
        expect(curr.symbol, isNotEmpty);
      }
    });
  });

  group('AppSettings', () {
    test('provides sensible defaults', () {
      const settings = AppSettings();
      expect(settings.id, AppSettings.defaultId);
      expect(settings.baseLanguage, 'en');
      expect(settings.targetLanguage, 'es');
      expect(settings.baseCurrency, 'USD');
      expect(settings.targetCurrency, 'EUR');
      expect(settings.modelDownloadUrl, AppSettings.defaultModelDownloadUrl);
    });

    test('languageNameFor resolves known codes case-insensitively', () {
      expect(AppSettings.languageNameFor('en'), 'English');
      expect(AppSettings.languageNameFor('EN'), 'English');
      expect(AppSettings.languageNameFor('  es  '), 'Spanish');
      expect(AppSettings.languageNameFor('FR'), 'French');
      expect(AppSettings.languageNameFor('de'), 'German');
      expect(AppSettings.languageNameFor('it'), 'Italian');
      expect(AppSettings.languageNameFor('pt'), 'Portuguese');
      expect(AppSettings.languageNameFor('ja'), 'Japanese');
      expect(AppSettings.languageNameFor('ko'), 'Korean');
      expect(AppSettings.languageNameFor('zh'), 'Chinese');
      expect(AppSettings.languageNameFor('sv'), 'Swedish');
      expect(AppSettings.languageNameFor('nl'), 'Dutch');
      expect(AppSettings.languageNameFor('ar'), 'Arabic');
      expect(AppSettings.languageNameFor('hi'), 'Hindi');
      expect(AppSettings.languageNameFor('tr'), 'Turkish');
      expect(AppSettings.languageNameFor('vi'), 'Vietnamese');
    });

    test('languageNameFor falls back to uppercase code for unknown languages', () {
      expect(AppSettings.languageNameFor('xx'), 'XX');
      expect(AppSettings.languageNameFor('zz'), 'ZZ');
      expect(AppSettings.languageNameFor('tlh'), 'TLH');
    });

    test('pairLabel formats language names and currency codes', () {
      const defaults = AppSettings();
      expect(defaults.pairLabel, 'English (USD) ⇄ Spanish (EUR)');

      const custom = AppSettings(
        baseLanguage: 'ja',
        targetLanguage: 'fr',
        baseCurrency: 'JPY',
        targetCurrency: 'CHF',
      );
      expect(custom.pairLabel, 'Japanese (JPY) ⇄ French (CHF)');
    });

    test('bindings and JSON serialization round-trip accurately', () {
      const settings = AppSettings(
        id: 'custom_id',
        baseLanguage: 'de',
        targetLanguage: 'it',
        baseCurrency: 'CHF',
        targetCurrency: 'EUR',
        modelDownloadUrl: 'https://example.com/model.litertlm',
      );

      final bindings = AppSettings.bindings;
      expect(bindings.getId(settings), 'custom_id');

      final json = bindings.toJson(settings);
      final restored = bindings.fromJson(json);
      expect(restored, equals(settings));
    });
  });

  group('ExchangeRateCache', () {
    test('idForPair normalizes currency codes to uppercase', () {
      expect(ExchangeRateCache.idForPair('usd', 'eur'), 'USD_EUR');
      expect(ExchangeRateCache.idForPair('jpy', 'gbp'), 'JPY_GBP');

      final cache = ExchangeRateCache(
        baseCurrency: 'cad',
        targetCurrency: 'mxn',
        rate: 12.5,
        updatedAt: DateTime.utc(2026, 1, 1),
      );
      expect(cache.id, 'CAD_MXN');
      expect(cache.isStale, isFalse);
    });

    test('isExpired enforces 7-day TTL boundary accurately', () {
      final updatedAt = DateTime.utc(2026, 5, 1, 12, 0, 0);
      final cache = ExchangeRateCache(
        baseCurrency: 'USD',
        targetCurrency: 'EUR',
        rate: 0.92,
        updatedAt: updatedAt,
      );

      // Immediately after creation -> not expired
      expect(cache.isExpired(now: updatedAt), isFalse);

      // 6 days, 23 hours, 59 minutes, 59 seconds later -> not expired
      final justBeforeExpiry = updatedAt.add(
        const Duration(days: 7) - const Duration(seconds: 1),
      );
      expect(cache.isExpired(now: justBeforeExpiry), isFalse);

      // Exactly 7 days later -> expired
      final exactExpiry = updatedAt.add(const Duration(days: 7));
      expect(cache.isExpired(now: exactExpiry), isTrue);

      // 10 days later -> expired
      final wellAfterExpiry = updatedAt.add(const Duration(days: 10));
      expect(cache.isExpired(now: wellAfterExpiry), isTrue);

      // Custom shorter TTL (1 hour)
      expect(
        cache.isExpired(
          now: updatedAt.add(const Duration(minutes: 59)),
          ttl: const Duration(hours: 1),
        ),
        isFalse,
      );
      expect(
        cache.isExpired(
          now: updatedAt.add(const Duration(hours: 1)),
          ttl: const Duration(hours: 1),
        ),
        isTrue,
      );
    });

    test('bindings and JSON serialization round-trip accurately', () {
      final cache = ExchangeRateCache(
        baseCurrency: 'GBP',
        targetCurrency: 'JPY',
        rate: 192.45,
        updatedAt: DateTime.utc(2026, 4, 15, 8, 30),
        isStale: true,
      );

      final bindings = ExchangeRateCache.bindings;
      expect(bindings.getId(cache), 'GBP_JPY');

      final json = bindings.toJson(cache);
      final restored = bindings.fromJson(json);
      expect(restored, equals(cache));
    });
  });

  group('Conversation', () {
    test('CreationBindings generates unique IDs when empty and preserves existing IDs', () {
      final createdAt = DateTime.utc(2026, 6, 1, 9);
      final unpersisted = Conversation(
        id: '',
        createdAt: createdAt,
        baseLanguage: 'en',
        targetLanguage: 'es',
      );

      final bindings = Conversation.bindings;
      expect(bindings.getId(unpersisted), isNull);

      final saved1 = bindings.save(unpersisted);
      final saved2 = bindings.save(unpersisted);
      expect(saved1.id, startsWith('conv_'));
      expect(saved2.id, startsWith('conv_'));
      expect(saved1.id, isNot(equals(saved2.id)));
      expect(bindings.getId(saved1), saved1.id);

      // Calling save on a Conversation that already has an ID preserves it
      final savedAgain = bindings.save(saved1);
      expect(savedAgain.id, saved1.id);

      final json = bindings.toJson(saved1);
      final restored = bindings.fromJson(json);
      expect(restored, equals(saved1));
    });
  });

  group('Message', () {
    test('CreationBindings generates unique IDs when empty and preserves existing IDs', () {
      final timestamp = DateTime.utc(2026, 6, 1, 9, 5);
      final unpersisted = Message(
        id: '',
        conversationId: 'conv_123',
        timestamp: timestamp,
        isBaseLanguage: false,
        originalText: 'Bonjour',
        translatedText: 'Hello',
      );

      final bindings = Message.bindings;
      expect(bindings.getId(unpersisted), isNull);

      final saved1 = bindings.save(unpersisted);
      final saved2 = bindings.save(unpersisted);
      expect(saved1.id, startsWith('msg_'));
      expect(saved2.id, startsWith('msg_'));
      expect(saved1.id, isNot(equals(saved2.id)));
      expect(bindings.getId(saved1), saved1.id);

      // Calling save on a Message that already has an ID preserves it
      final savedAgain = bindings.save(saved1);
      expect(savedAgain.id, saved1.id);

      final json = bindings.toJson(saved1);
      final restored = bindings.fromJson(json);
      expect(restored, equals(saved1));
    });

    test('stores 3 strings (originalText, translatedText, annotatedText) and resolves effectiveTranslatedText', () {
      final timestamp = DateTime.utc(2026, 6, 1, 9, 10);
      final msgWithAnnotation = Message(
        id: 'msg_3_strings',
        conversationId: 'conv_123',
        timestamp: timestamp,
        isBaseLanguage: true,
        originalText: 'It costs 10 dollars at 6 PM.',
        translatedText: 'Cuesta 10 dólares a las 6 PM.',
        annotatedText: r'Cuesta 10 dólares (€9.20 EUR) a las 6 PM (18:00).',
      );

      expect(msgWithAnnotation.originalText, 'It costs 10 dollars at 6 PM.');
      expect(msgWithAnnotation.translatedText, 'Cuesta 10 dólares a las 6 PM.');
      expect(
        msgWithAnnotation.annotatedText,
        r'Cuesta 10 dólares (€9.20 EUR) a las 6 PM (18:00).',
      );
      expect(
        msgWithAnnotation.effectiveTranslatedText,
        r'Cuesta 10 dólares (€9.20 EUR) a las 6 PM (18:00).',
      );

      final json = msgWithAnnotation.toJson();
      final restored = Message.fromJson(json);
      expect(restored, equals(msgWithAnnotation));

      // Legacy message without annotatedText falls back to translatedText
      final legacyMsg = Message(
        id: 'msg_legacy',
        conversationId: 'conv_123',
        timestamp: timestamp,
        isBaseLanguage: false,
        originalText: 'Hola',
        translatedText: 'Hello',
      );
      expect(legacyMsg.annotatedText, isEmpty);
      expect(legacyMsg.effectiveTranslatedText, 'Hello');
    });
  });

  group('Hive TypeAdapters & AppHiveInitializer', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('hive_adapters_test_');
    });

    tearDown(() async {
      await Hive.close();
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('typeIds are distinct for all 4 domain adapters', () {
      final typeIds = <int>{
        AppSettingsAdapter().typeId,
        ExchangeRateCacheAdapter().typeId,
        ConversationAdapter().typeId,
        MessageAdapter().typeId,
      };
      expect(typeIds, equals(<int>{1, 2, 3, 4}));
    });

    test('AppHiveInitializer.registerAdapters is idempotent', () async {
      final initializer = AppHiveInitializer(storagePath: tempDir.path);
      await initializer.ready;

      // Calling registerAdapters again should not throw
      expect(
        () => AppHiveInitializer.registerAdapters(initializer.hive),
        returnsNormally,
      );
    });

    test('Binary TypeAdapters round-trip all 4 models through Hive boxes', () async {
      final initializer = AppHiveInitializer(storagePath: tempDir.path);
      await initializer.ready;

      final settingsBox = await Hive.openBox<AppSettings>('raw_settings_test');
      final ratesBox = await Hive.openBox<ExchangeRateCache>('raw_rates_test');
      final convBox = await Hive.openBox<Conversation>('raw_conv_test');
      final msgBox = await Hive.openBox<Message>('raw_msg_test');

      const settings = AppSettings(
        baseLanguage: 'ja',
        targetLanguage: 'en',
        baseCurrency: 'JPY',
        targetCurrency: 'USD',
      );
      final rate = ExchangeRateCache(
        baseCurrency: 'JPY',
        targetCurrency: 'USD',
        rate: 0.0067,
        updatedAt: DateTime.utc(2026, 7, 1),
        isStale: true,
      );
      final conv = Conversation(
        id: 'conv_bin_1',
        createdAt: DateTime.utc(2026, 7, 1, 10),
        baseLanguage: 'ja',
        targetLanguage: 'en',
        previewText: 'Where is the train station?',
      );
      final msg = Message(
        id: 'msg_bin_1',
        conversationId: 'conv_bin_1',
        timestamp: DateTime.utc(2026, 7, 1, 10, 1),
        isBaseLanguage: true,
        originalText: '駅はどこですか？',
        translatedText: 'Where is the train station?',
      );

      await settingsBox.put(settings.id, settings);
      await ratesBox.put(rate.id, rate);
      await convBox.put(conv.id, conv);
      await msgBox.put(msg.id, msg);

      // Flush and reopen boxes from disk to force binary reader/writer execution
      await settingsBox.close();
      await ratesBox.close();
      await convBox.close();
      await msgBox.close();

      final reopenedSettings = await Hive.openBox<AppSettings>(
        'raw_settings_test',
      );
      final reopenedRates = await Hive.openBox<ExchangeRateCache>(
        'raw_rates_test',
      );
      final reopenedConv = await Hive.openBox<Conversation>('raw_conv_test');
      final reopenedMsg = await Hive.openBox<Message>('raw_msg_test');

      expect(reopenedSettings.get(settings.id), equals(settings));
      expect(reopenedRates.get(rate.id), equals(rate));
      expect(reopenedConv.get(conv.id), equals(conv));
      expect(reopenedMsg.get(msg.id), equals(msg));
    });
  });
}
