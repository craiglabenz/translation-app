import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:translation_app/core/ai/local_translation_engine.dart';
import 'package:translation_app/core/ai/model_manager.dart';
import 'package:translation_app/core/ai/network_translation_engine.dart';
import 'package:translation_app/core/ai/prompt_templates.dart';
import 'package:translation_app/core/ai/translation_engine.dart';
import 'package:translation_app/core/data/models/app_settings.dart';

void main() {
  group('PromptTemplates', () {
    test('builds system prompt with languages, 4-decimal rate, and formatting rules', () {
      final prompt = PromptTemplates.buildSystemPrompt(
        baseLanguage: 'English',
        targetLanguage: 'Japanese',
        exchangeRate: 0.00674321,
        baseCurrency: 'USD',
        targetCurrency: 'JPY',
      );

      expect(prompt, contains('base language is "English"'));
      expect(prompt, contains('target is "Japanese"'));
      expect(prompt, contains('1 JPY = 0.0067 USD'));
      expect(prompt, contains("24-hour and 12-hour format (e.g., '18:00 (6PM)')"));
      expect(prompt, contains("original price (converted price)"));
      expect(
        prompt,
        contains(
          '{"detected_language": "en", "translated_text": "...", "original_transcript": "..."}',
        ),
      );
    });
  });

  group('TranslationResult', () {
    test('supports equality, copyWith, and JSON serialization round-trip', () {
      const r1 = TranslationResult(
        sourceLanguage: 'en',
        translatedText: 'Bonjour',
        originalText: 'Hello',
      );
      const r2 = TranslationResult(
        sourceLanguage: 'en',
        translatedText: 'Bonjour',
        originalText: 'Hello',
      );
      expect(r1, equals(r2));
      expect(r1.hashCode, equals(r2.hashCode));

      final modified = r1.copyWith(originalText: null);
      expect(modified.originalText, isNull);

      final restored = TranslationResult.fromJson(r1.toJson());
      expect(restored, equals(r1));
    });
  });

  group('NetworkTranslationEngine', () {
    test('methods throw UnimplementedError for v1 Gemini Socket', () {
      const engine = NetworkTranslationEngine();
      expect(engine.initialize, throwsUnimplementedError);
      expect(
        () => engine.translateAudioChunk(
          audioWavChunk: Float32List.fromList(<double>[0.1]),
          baseLanguage: 'English',
          targetLanguage: 'Spanish',
          exchangeRate: 0.92,
          baseCurrency: 'USD',
          targetCurrency: 'EUR',
        ),
        throwsUnimplementedError,
      );
      expect(engine.dispose, throwsUnimplementedError);
    });
  });

  group('LocalTranslationEngine.encodeFloat32PcmToWav', () {
    test('produces valid 44-byte RIFF WAV header and 16-bit PCM samples', () {
      final samples = Float32List.fromList(<double>[0.0, 0.5, -0.5, 1.0, -1.0]);
      final wav = LocalTranslationEngine.encodeFloat32PcmToWav(
        samples,
        sampleRate: 16000,
      );

      // 44 header bytes + 5 * 2 PCM16 bytes = 54 bytes
      expect(wav.length, 54);
      expect(ascii.decode(wav.sublist(0, 4)), 'RIFF');
      expect(ascii.decode(wav.sublist(8, 12)), 'WAVE');
      expect(ascii.decode(wav.sublist(12, 16)), 'fmt ');
      expect(ascii.decode(wav.sublist(36, 40)), 'data');

      final byteData = ByteData.sublistView(wav);
      expect(byteData.getUint32(4, Endian.little), 36 + 10); // RIFF chunk size
      expect(byteData.getUint32(16, Endian.little), 16); // fmt chunk size
      expect(byteData.getUint16(20, Endian.little), 1); // PCM format
      expect(byteData.getUint16(22, Endian.little), 1); // mono channel
      expect(byteData.getUint32(24, Endian.little), 16000); // sampleRate
      expect(byteData.getUint32(28, Endian.little), 32000); // byteRate (16k * 2)
      expect(byteData.getUint16(32, Endian.little), 2); // blockAlign
      expect(byteData.getUint16(34, Endian.little), 16); // 16-bit PCM
      expect(byteData.getUint32(40, Endian.little), 10); // data chunk size

      // Verify sample values
      expect(byteData.getInt16(44, Endian.little), 0);
      expect(byteData.getInt16(46, Endian.little), 16384);
      expect(byteData.getInt16(48, Endian.little), -16384);
      expect(byteData.getInt16(50, Endian.little), 32767);
      expect(byteData.getInt16(52, Endian.little), -32767);
    });

    test('clamps out-of-range float samples to [-32767, 32767]', () {
      final samples = Float32List.fromList(<double>[3.5, -4.2]);
      final wav = LocalTranslationEngine.encodeFloat32PcmToWav(samples);
      final view = ByteData.sublistView(wav);

      expect(view.getInt16(44, Endian.little), 32767);
      expect(view.getInt16(46, Endian.little), -32767);
    });

    test('encodes empty sample list as valid 44-byte WAV header', () {
      final wav = LocalTranslationEngine.encodeFloat32PcmToWav(Float32List(0));
      expect(wav.length, 44);
      final view = ByteData.sublistView(wav);
      expect(view.getUint32(40, Endian.little), 0);
    });
  });

  group('LocalTranslationEngine.stripMarkdownFences', () {
    test('strips ```json and ``` fences cleanly', () {
      expect(
        LocalTranslationEngine.stripMarkdownFences(
          '```json\n{"a": 1}\n```',
        ),
        '{"a": 1}',
      );
      expect(
        LocalTranslationEngine.stripMarkdownFences(
          '```\n{"a": 1}\n```',
        ),
        '{"a": 1}',
      );
      expect(
        LocalTranslationEngine.stripMarkdownFences('{"a": 1}'),
        '{"a": 1}',
      );
      // Unclosed leading fence
      expect(
        LocalTranslationEngine.stripMarkdownFences('```json\n{"a": 1}'),
        '{"a": 1}',
      );
    });
  });

  group('LocalTranslationEngine.parseTranslationResponse', () {
    test('parses standard JSON schema', () {
      final result = LocalTranslationEngine.parseTranslationResponse(
        '{"detected_language": "en", "original_transcript": "That costs 10 dollars", "translated_text": "Eso cuesta 10 dólares (9.20 EUR)"}',
      );
      expect(result.sourceLanguage, 'en');
      expect(result.originalText, 'That costs 10 dollars');
      expect(result.translatedText, 'Eso cuesta 10 dólares (9.20 EUR)');
    });

    test('parses alternative JSON keys (source_language, translation, original_text)', () {
      final result = LocalTranslationEngine.parseTranslationResponse(
        '{"source_language": "FR", "original_text": "Bonjour", "translation": "Hello"}',
      );
      expect(result.sourceLanguage, 'fr');
      expect(result.originalText, 'Bonjour');
      expect(result.translatedText, 'Hello');
    });

    test('falls back to fallbackSourceLanguage when detected_language is missing or empty', () {
      final missingLang = LocalTranslationEngine.parseTranslationResponse(
        '{"translated_text": "Guten Tag"}',
        fallbackSourceLanguage: 'de',
      );
      expect(missingLang.sourceLanguage, 'de');
      expect(missingLang.originalText, isNull);

      final emptyLang = LocalTranslationEngine.parseTranslationResponse(
        '{"detected_language": "   ", "translated_text": "Guten Tag", "original_transcript": "  "}',
        fallbackSourceLanguage: 'de',
      );
      expect(emptyLang.sourceLanguage, 'de');
      expect(emptyLang.originalText, isNull);
    });

    test('extracts JSON embedded inside markdown fences and surrounding prose', () {
      const messyOutput = '''
Sure! Here is the translation result you requested:
```json
{
  "detected_language": "es",
  "original_transcript": "La reunión es a las seis",
  "translated_text": "The meeting is at 18:00 (6PM)"
}
```
Let me know if you need anything else!
''';
      final result = LocalTranslationEngine.parseTranslationResponse(
        messyOutput,
      );
      expect(result.sourceLanguage, 'es');
      expect(result.originalText, 'La reunión es a las seis');
      expect(result.translatedText, 'The meeting is at 18:00 (6PM)');
    });

    test('falls back to plain text when model returns non-JSON text', () {
      final fallback = LocalTranslationEngine.parseTranslationResponse(
        'Hola, ¿cómo estás?',
        fallbackSourceLanguage: 'EN',
      );
      expect(fallback.sourceLanguage, 'en');
      expect(fallback.translatedText, 'Hola, ¿cómo estás?');
      expect(fallback.originalText, isNull);
    });

    test('throws FormatException on empty or whitespace-only response', () {
      expect(
        () => LocalTranslationEngine.parseTranslationResponse('   \n  '),
        throwsFormatException,
      );
    });

    test('throws FormatException when JSON has empty or missing translated_text', () {
      expect(
        () => LocalTranslationEngine.parseTranslationResponse(
          '{"detected_language": "en", "translated_text": "   "}',
        ),
        throwsFormatException,
      );
      expect(
        () => LocalTranslationEngine.parseTranslationResponse(
          '{"detected_language": "en"}',
        ),
        throwsFormatException,
      );
    });

    test('throws FormatException on truncated or corrupt JSON braces', () {
      expect(
        () => LocalTranslationEngine.parseTranslationResponse(
          '{"detected_language": "en", "translated_text": "unterminated',
        ),
        throwsFormatException,
      );
      expect(
        () => LocalTranslationEngine.parseTranslationResponse('[1, 2, 3]'),
        throwsFormatException,
      );
    });
  });

  group('LocalTranslationEngine execution & lifecycle', () {
    test('throws ArgumentError when audioWavChunk is empty', () async {
      final modelManager = ModelManager(initialInstalled: true);
      final engine = LocalTranslationEngine(
        modelManager: modelManager,
        inferenceRunner: ({required wavBytes, required systemPrompt}) async =>
            '{"translated_text": "Hola"}',
      );

      await expectLater(
        engine.translateAudioChunk(
          audioWavChunk: Float32List(0),
          baseLanguage: 'English',
          targetLanguage: 'Spanish',
          exchangeRate: 0.92,
          baseCurrency: 'USD',
          targetCurrency: 'EUR',
        ),
        throwsArgumentError,
      );

      await engine.dispose();
      await modelManager.close();
    });

    test('translateAudioChunk invokes inference runner with prompt & WAV and disposes cleanly', () async {
      Uint8List? capturedWav;
      String? capturedPrompt;

      final modelManager = ModelManager(initialInstalled: true);
      final engine = LocalTranslationEngine(
        modelManager: modelManager,
        inferenceRunner: ({required wavBytes, required systemPrompt}) async {
          capturedWav = wavBytes;
          capturedPrompt = systemPrompt;
          return '{"detected_language": "en", "original_transcript": "Hello", "translated_text": "Hola"}';
        },
      );

      expect(engine.isInitialized, isFalse);

      final result = await engine.translateAudioChunk(
        audioWavChunk: Float32List.fromList(<double>[0.1, -0.1, 0.2]),
        baseLanguage: 'English',
        targetLanguage: 'Spanish',
        exchangeRate: 0.92,
        baseCurrency: 'USD',
        targetCurrency: 'EUR',
      );

      expect(engine.isInitialized, isTrue);
      expect(result.sourceLanguage, 'en');
      expect(result.translatedText, 'Hola');
      expect(capturedWav, isNotNull);
      expect(capturedWav!.length, 44 + 6);
      expect(capturedPrompt, contains('1 EUR = 0.9200 USD'));

      await engine.dispose();
      expect(engine.isInitialized, isFalse);
      await modelManager.close();
    });

    test('initialize throws StateError when model cannot be downloaded', () async {
      final modelManager = ModelManager(
        initialInstalled: false,
        isInstalledCheck: () async => false,
        installRunner:
            ({
              required downloadUrl,
              required onProgress,
              cancelToken,
            }) async {
              throw Exception('No disk space');
            },
      );
      final engine = LocalTranslationEngine(modelManager: modelManager);

      await expectLater(engine.initialize(), throwsStateError);
      await modelManager.close();
    });
  });

  group('ModelManager', () {
    test('initializes with default ModelDownloadState', () async {
      final manager = ModelManager();
      expect(manager.stateValue.isInstalled, isFalse);
      expect(manager.stateValue.isDownloading, isFalse);
      expect(manager.stateValue.progress, 0.0);
      expect(manager.stateValue.modelId, ModelManager.defaultModelFilename);
      expect(manager.stateValue.error, isNull);
      await manager.close();
    });

    test('checkModelReady updates state from injected check and handles errors', () async {
      var checkResult = true;
      var shouldThrow = false;
      final manager = ModelManager(
        isInstalledCheck: () async {
          if (shouldThrow) throw Exception('Filesystem error');
          return checkResult;
        },
      );

      expect(await manager.checkModelReady(), isTrue);
      expect(manager.stateValue.isInstalled, isTrue);

      checkResult = false;
      expect(await manager.checkModelReady(), isFalse);
      expect(manager.stateValue.isInstalled, isFalse);

      shouldThrow = true;
      expect(await manager.checkModelReady(), isFalse);
      expect(manager.stateValue.isInstalled, isFalse);

      await manager.close();
    });

    test('downloadModel emits progress updates and marks model installed', () async {
      String? capturedUrl;
      final progressValues = <double>[];

      final manager = ModelManager(
        isInstalledCheck: () async => false,
        installRunner:
            ({
              required downloadUrl,
              required onProgress,
              cancelToken,
            }) async {
              capturedUrl = downloadUrl;
              onProgress(0.25);
              onProgress(0.75);
              onProgress(1.5); // Should clamp to 1.0
            },
      );

      final unsubscribe = manager.state.subscribe((state) {
        if (state.isDownloading) {
          progressValues.add(state.progress);
        }
      });

      final success = await manager.ensureModelDownloaded(
        fallbackUrl: 'https://huggingface.co/custom/model.litertlm',
      );
      expect(success, isTrue);
      expect(capturedUrl, 'https://huggingface.co/custom/model.litertlm');
      expect(progressValues, containsAllInOrder(<double>[0.0, 0.25, 0.75, 1.0]));
      expect(manager.stateValue.isInstalled, isTrue);
      expect(manager.stateValue.isDownloading, isFalse);
      expect(manager.stateValue.progress, 1.0);
      expect(manager.stateValue.error, isNull);

      // Calling ensureModelDownloaded again returns true immediately without re-downloading
      capturedUrl = null;
      expect(await manager.ensureModelDownloaded(), isTrue);
      expect(capturedUrl, isNull);

      unsubscribe();
      await manager.close();
    });

    test('prevents concurrent duplicate downloads while isDownloading is true', () async {
      final completer = Completer<void>();
      final manager = ModelManager(
        installRunner:
            ({
              required downloadUrl,
              required onProgress,
              cancelToken,
            }) => completer.future,
      );

      final firstFuture = manager.downloadModel();
      expect(manager.stateValue.isDownloading, isTrue);

      // Second call while downloading returns false immediately
      final secondResult = await manager.downloadModel();
      expect(secondResult, isFalse);

      completer.complete();
      expect(await firstFuture, isTrue);
      await manager.close();
    });

    test('cancelDownload triggers CancelToken and records cancellation error', () async {
      final manager = ModelManager(
        installRunner:
            ({
              required downloadUrl,
              required onProgress,
              cancelToken,
            }) async {
              onProgress(0.4);
              // Wait briefly then check cancellation
              await Future<void>.delayed(const Duration(milliseconds: 10));
              cancelToken?.throwIfCancelled();
            },
      );

      final future = manager.downloadModel();
      manager.cancelDownload();

      final result = await future;
      expect(result, isFalse);
      expect(manager.stateValue.isInstalled, isFalse);
      expect(manager.stateValue.isDownloading, isFalse);
      expect(manager.stateValue.error, 'Model download was cancelled.');

      await manager.close();
    });

    test('markUninstalled resets state and blocks checkModelReady until re-downloaded', () async {
      final manager = ModelManager(
        initialInstalled: true,
        isInstalledCheck: () async => true,
        installRunner:
            ({
              required downloadUrl,
              required onProgress,
              cancelToken,
            }) async {
              onProgress(1.0);
            },
      );

      expect(manager.stateValue.isInstalled, isTrue);
      manager.markUninstalled();
      expect(manager.stateValue.isInstalled, isFalse);
      expect(manager.stateValue.progress, 0.0);

      // Even if underlying disk check says true, markUninstalled keeps it false until downloadModel() runs
      expect(await manager.checkModelReady(), isFalse);
      expect(manager.stateValue.isInstalled, isFalse);

      // Re-downloading clears _markedUninstalled and restores isInstalled: true
      expect(
        await manager.downloadModel(
          fallbackUrl: AppSettings.defaultModelDownloadUrl,
        ),
        isTrue,
      );
      expect(manager.stateValue.isInstalled, isTrue);

      await manager.close();
    });
  });
}
