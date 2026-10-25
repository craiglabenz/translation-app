import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:translation_app/core/ai/language_detector.dart';
import 'package:translation_app/core/ai/local_translation_engine.dart';
import 'package:translation_app/core/ai/model_manager.dart';
import 'package:translation_app/core/ai/network_translation_engine.dart';
import 'package:translation_app/core/ai/prompt_templates.dart';
import 'package:translation_app/core/ai/switchable_translation_engine.dart';
import 'package:translation_app/core/ai/translation_engine.dart';
import 'package:translation_app/core/data/models/app_settings.dart';
import 'package:translation_app/core/data/models/message.dart';

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

    test('builds 3 to 5 word conversation summary prompt from messages', () {
      final sysPrompt = PromptTemplates.buildSummarySystemPrompt(
        baseLanguage: 'English',
      );
      expect(sysPrompt, contains('3 to 5 word'));
      expect(sysPrompt, contains('English'));

      final userPrompt = PromptTemplates.buildConversationSummaryPrompt(
        messages: <Message>[
          Message(
            id: 'm1',
            conversationId: 'c1',
            timestamp: DateTime.utc(2026, 1, 1, 10),
            isBaseLanguage: true,
            originalText: 'Where is the subway?',
            translatedText: '지하철이 어디에 있나요?',
          ),
        ],
        baseLanguage: 'English',
        targetLanguage: 'Korean',
      );
      expect(userPrompt, contains('3 to 5 word description'));
      expect(userPrompt, contains('Where is the subway? -> 지하철이 어디에 있나요?'));
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

  group('NetworkTranslationEngine & SwitchableTranslationEngine', () {
    test('provides expanded cloudSupportedLanguages and throws StateError when API key is missing', () async {
      final engine = NetworkTranslationEngine(apiKeyProvider: () => '');
      expect(
        engine.supportedLanguages,
        equals(NetworkTranslationEngine.cloudSupportedLanguages),
      );
      expect(
        engine.supportedLanguages.length,
        greaterThan(LocalTranslationEngine.gemmaSupportedLanguages.length),
      );
      expect(engine.initialize, throwsStateError);
      await expectLater(
        engine.translateAudioChunk(
          audioWavChunk: Float32List.fromList(<double>[0.25, -0.25, 0.3]),
          baseLanguage: 'English',
          targetLanguage: 'Spanish',
          exchangeRate: 0.92,
          baseCurrency: 'USD',
          targetCurrency: 'EUR',
        ),
        throwsStateError,
      );
      await engine.dispose();
    });

    test('streams audio translation over SSE, discovers languages, and summarizes conversations', () async {
      final mockClient = MockClient.streaming((request, bodyStream) async {
        final url = request.url.toString();
        if (url.contains(':streamGenerateContent')) {
          final sseLines = <String>[
            'data: {"candidates":[{"content":{"parts":[{"text":"{\\"original_transcript\\": \\"Where is the train?\\", \\"detected_language\\": \\"en\\", \\"translated_text\\": \\"¿Dónde "}]}}]}\n\n',
            'data: {"candidates":[{"content":{"parts":[{"text":"está el tren?\\"}"}]}}]}\n\n',
            'data: [DONE]\n\n',
          ];
          return http.StreamedResponse(
            Stream<List<int>>.fromIterable(sseLines.map(utf8.encode)),
            200,
          );
        }
        // Standard :generateContent for language discovery or summary
        final bodyBytes = await bodyStream.toBytes();
        final bodyText = utf8.decode(bodyBytes);
        if (bodyText.contains('JSON array of spoken languages')) {
          final discoveredJson = jsonEncode(<Map<String, String>>[
            <String, String>{
              'code': 'mn',
              'name': 'Mongolian',
              'nativeName': 'Монгол',
            },
          ]);
          final envelope = jsonEncode(<String, Object?>{
            'candidates': <Object?>[
              <String, Object?>{
                'content': <String, Object?>{
                  'parts': <Object?>[
                    <String, Object?>{'text': discoveredJson},
                  ],
                },
              },
            ],
          });
          return http.StreamedResponse(
            Stream<List<int>>.value(utf8.encode(envelope)),
            200,
          );
        }
        final summaryEnvelope = jsonEncode(<String, Object?>{
          'candidates': <Object?>[
            <String, Object?>{
              'content': <String, Object?>{
                'parts': <Object?>[
                  <String, Object?>{'text': 'Asking for train directions'},
                ],
              },
            },
          ],
        });
        return http.StreamedResponse(
          Stream<List<int>>.value(utf8.encode(summaryEnvelope)),
          200,
        );
      });

      final engine = NetworkTranslationEngine(
        apiKeyProvider: () => 'AIzaSyTestKey123',
        modelIdProvider: () => 'gemini-3.8-flash',
        httpClient: mockClient,
      );

      final partials = <String>[];
      final result = await engine.translateAudioChunk(
        audioWavChunk: Float32List.fromList(<double>[0.3, -0.3, 0.25, -0.25]),
        baseLanguage: 'en',
        targetLanguage: 'es',
        exchangeRate: 0.92,
        baseCurrency: 'USD',
        targetCurrency: 'EUR',
        onPartialResult: (partial) => partials.add(partial.translatedText),
      );

      expect(result.sourceLanguage, 'en');
      expect(result.originalText, 'Where is the train?');
      expect(result.translatedText, '¿Dónde está el tren?');
      expect(partials, isNotEmpty);

      // Dynamic language discovery merges 'mn' (Mongolian)
      final discovered = await engine.discoverSupportedLanguages();
      expect(discovered.any((l) => l.code == 'mn'), isTrue);

      // Summarize conversation
      final summary = await engine.summarizeConversation(
        messages: <Message>[
          Message(
            id: 'm1',
            conversationId: 'c1',
            timestamp: DateTime.utc(2026, 6, 1),
            isBaseLanguage: true,
            originalText: 'Where is the train?',
            translatedText: '¿Dónde está el tren?',
          ),
        ],
        baseLanguage: 'en',
        targetLanguage: 'es',
      );
      expect(summary, 'Asking for train directions');

      // SwitchableTranslationEngine switches between local and network engines
      final localEngine = LocalTranslationEngine(
        modelManager: ModelManager(
          initialInstalled: true,
          isInstalledCheck: () async => true,
        ),
      );
      final switchable = SwitchableTranslationEngine(
        localEngine: localEngine,
        networkEngine: engine,
      );
      expect(switchable.mode, TranslationEngineMode.onDevice);
      expect(
        switchable.supportedLanguages.length,
        LocalTranslationEngine.gemmaSupportedLanguages.length,
      );

      switchable.setMode(TranslationEngineMode.cloud);
      expect(switchable.mode, TranslationEngineMode.cloud);
      expect(switchable.supportedLanguages.any((l) => l.code == 'mn'), isTrue);

      await switchable.dispose();
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

      // However, ensureModelDownloaded() joins the in-flight download future instead of failing!
      final joinedFuture = manager.ensureModelDownloaded();

      completer.complete();
      expect(await firstFuture, isTrue);
      expect(await joinedFuture, isTrue);
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

  group('LanguageDetector & Bidirectional Reliability', () {
    test('normalizeLanguageCode normalizes codes, regional tags, English names, and native names', () {
      expect(LanguageDetector.normalizeLanguageCode('en'), 'en');
      expect(LanguageDetector.normalizeLanguageCode('en-US'), 'en');
      expect(LanguageDetector.normalizeLanguageCode('English'), 'en');
      expect(LanguageDetector.normalizeLanguageCode('ko'), 'ko');
      expect(LanguageDetector.normalizeLanguageCode('ko-KR'), 'ko');
      expect(LanguageDetector.normalizeLanguageCode('Korean'), 'ko');
      expect(LanguageDetector.normalizeLanguageCode('한국어'), 'ko');
      expect(LanguageDetector.normalizeLanguageCode('Korean (ko)'), 'ko');
      expect(LanguageDetector.normalizeLanguageCode('Japanese'), 'ja');
      expect(LanguageDetector.normalizeLanguageCode('日本語'), 'ja');
      expect(LanguageDetector.normalizeLanguageCode('Chinese'), 'zh');
      expect(LanguageDetector.normalizeLanguageCode('中文'), 'zh');
      expect(LanguageDetector.normalizeLanguageCode('Mandarin'), 'zh');
      expect(LanguageDetector.normalizeLanguageCode('Español'), 'es');
      expect(LanguageDetector.normalizeLanguageCode('Français'), 'fr');
      expect(LanguageDetector.normalizeLanguageCode('Deutsch'), 'de');
      expect(LanguageDetector.normalizeLanguageCode('Italiano'), 'it');
      expect(LanguageDetector.normalizeLanguageCode('Português'), 'pt');
    });

    test('detectLanguage accurately distinguishes Korean, Japanese, Chinese, and Latin languages', () {
      expect(
        LanguageDetector.detectLanguage(
          '안녕하세요, 지하철역이 어디에 있나요? (10.00 USD)',
          candidateA: 'en',
          candidateB: 'ko',
        ),
        'ko',
      );
      expect(
        LanguageDetector.detectLanguage(
          'Excuse me, where is the subway station?',
          candidateA: 'en',
          candidateB: 'ko',
        ),
        'en',
      );
      expect(
        LanguageDetector.detectLanguage(
          '駅はどこですか？',
          candidateA: 'en',
          candidateB: 'ja',
        ),
        'ja',
      );
      expect(
        LanguageDetector.detectLanguage(
          '请问地铁站在哪里？',
          candidateA: 'en',
          candidateB: 'zh',
        ),
        'zh',
      );
      expect(
        LanguageDetector.detectLanguage(
          '¿Dónde está la estación de tren?',
          candidateA: 'en',
          candidateB: 'es',
        ),
        'es',
      );
      expect(
        LanguageDetector.detectLanguage(
          'Wo ist der Bahnhof bitte?',
          candidateA: 'en',
          candidateB: 'de',
        ),
        'de',
      );
      expect(
        LanguageDetector.detectLanguage(
          'Où est la gare, merci beaucoup',
          candidateA: 'en',
          candidateB: 'fr',
        ),
        'fr',
      );
    });

    test('detectLanguage and resolveSpokenLanguage do not let an English-sounding first word hijack a foreign utterance', () {
      // 1. Spanish sentence starting with an English interjection ("Okay" / "Wait") or shared homographs ("Me", "hotel")
      expect(
        LanguageDetector.detectLanguage(
          'Okay, necesito ir al hospital',
          candidateA: 'en',
          candidateB: 'es',
        ),
        'es',
      );
      expect(
        LanguageDetector.detectLanguage(
          'Me gusta el hotel',
          candidateA: 'en',
          candidateB: 'es',
        ),
        'es',
      );
      expect(
        LanguageDetector.detectLanguage(
          'The quiero pagar la cuenta',
          candidateA: 'en',
          candidateB: 'es',
        ),
        'es',
      );

      // 2. Dutch, Polish, and Indonesian sentences starting with an English-sounding word
      expect(
        LanguageDetector.detectLanguage(
          'Wait, waar is het treinstation?',
          candidateA: 'en',
          candidateB: 'nl',
        ),
        'nl',
      );
      expect(
        LanguageDetector.detectLanguage(
          'Hello, gdzie jest dworzec kolejowy?',
          candidateA: 'en',
          candidateB: 'pl',
        ),
        'pl',
      );
      expect(
        LanguageDetector.detectLanguage(
          'Yes, terima kasih banyak untuk makanan ini',
          candidateA: 'en',
          candidateB: 'id',
        ),
        'id',
      );

      // 3. Even when the audio model mislabels detected_language as "en" because of the first word,
      // resolveSpokenLanguage & parseSpeechToTextResponse classify by the majority of the sentence.
      final sttResult = LocalTranslationEngine.parseSpeechToTextResponse(
        '{"original_transcript": "Wait, necesito pagar la cuenta por favor", "detected_language": "en"}',
        baseLanguage: 'en',
        targetLanguage: 'es',
        durationMs: 250,
      );
      expect(sttResult.detectedLanguageCode, 'es');

      // 4. When the audio model accurately reports the target language (e.g. "es" or "id"),
      // a single English word at the start of an utterance with unlisted foreign nouns never overrides back to "en".
      expect(
        LanguageDetector.resolveSpokenLanguage(
          transcript: 'The makan nasi goreng',
          reportedLanguage: 'id',
          baseLanguage: 'en',
          targetLanguage: 'id',
        ),
        'id',
      );
    });

    test('analyzeTranslation resolves direction accurately even when LLM mislabels detected_language', () {
      // 1. Host spoke English -> translated into Korean, but LLM mislabeled detected_language as "ko"
      final hostAnalysis = LanguageDetector.analyzeTranslation(
        result: const TranslationResult(
          sourceLanguage: 'ko',
          originalText: 'Where is the bathroom?',
          translatedText: '화장실이 어디에 있나요?',
        ),
        baseLanguage: 'English',
        targetLanguage: 'Korean',
      );
      expect(hostAnalysis.isBaseLanguage, isTrue);
      expect(hostAnalysis.resolvedSourceCode, 'en');
      expect(hostAnalysis.targetOutputCode, 'ko');
      expect(hostAnalysis.needsFallbackTranslation, isFalse);

      // 2. Guest spoke Korean -> translated into English, but LLM copied "en" from schema
      final guestAnalysis = LanguageDetector.analyzeTranslation(
        result: const TranslationResult(
          sourceLanguage: 'en',
          originalText: '화장실은 저쪽에 있어요',
          translatedText: 'The bathroom is over there',
        ),
        baseLanguage: 'English',
        targetLanguage: 'Korean',
      );
      expect(guestAnalysis.isBaseLanguage, isFalse);
      expect(guestAnalysis.resolvedSourceCode, 'ko');
      expect(guestAnalysis.targetOutputCode, 'en');
      expect(guestAnalysis.needsFallbackTranslation, isFalse);
    });

    test('analyzeTranslation flags untranslated English echo when Host speaks English', () {
      final echoedEnglish = LanguageDetector.analyzeTranslation(
        result: const TranslationResult(
          sourceLanguage: 'en',
          originalText: 'How much does this cost?',
          translatedText: 'How much does this cost?',
        ),
        baseLanguage: 'English',
        targetLanguage: 'Korean',
      );
      expect(echoedEnglish.needsFallbackTranslation, isTrue);
      expect(echoedEnglish.isBaseLanguage, isTrue);
      expect(echoedEnglish.resolvedSourceCode, 'en');
      expect(echoedEnglish.targetOutputCode, 'ko');
      expect(echoedEnglish.sourceTextForFallback, 'How much does this cost?');

      // Also when originalText is omitted and translatedText is in English
      final omittedOriginalEcho = LanguageDetector.analyzeTranslation(
        result: const TranslationResult(
          sourceLanguage: 'en',
          translatedText: 'Hello, can you help me please?',
        ),
        baseLanguage: 'English',
        targetLanguage: 'Korean',
      );
      expect(omittedOriginalEcho.needsFallbackTranslation, isTrue);
      expect(omittedOriginalEcho.isBaseLanguage, isTrue);
      expect(omittedOriginalEcho.targetOutputCode, 'ko');
    });

    test('translateAudioChunk automatically runs text fallback when audio pass echoes English', () async {
      var textFallbackCalled = false;
      String? capturedFallbackPrompt;

      final modelManager = ModelManager(initialInstalled: true);
      final engine = LocalTranslationEngine(
        modelManager: modelManager,
        // Simulate the bug where the audio pass prints English instead of translating to Korean
        inferenceRunner: ({required wavBytes, required systemPrompt}) async {
          return '{"detected_language": "en", "original_transcript": "Where is the station?", "translated_text": "Where is the station?"}';
        },
        textInferenceRunner: ({required prompt, required systemPrompt}) async {
          textFallbackCalled = true;
          capturedFallbackPrompt = prompt;
          return '역이 어디에 있나요?';
        },
      );

      final streamedPartials = <TranslationResult>[];
      final result = await engine.translateAudioChunk(
        audioWavChunk: Float32List.fromList(<double>[0.2, -0.2, 0.3]),
        baseLanguage: 'English',
        targetLanguage: 'Korean',
        exchangeRate: 0.0007,
        baseCurrency: 'USD',
        targetCurrency: 'KRW',
        onPartialResult: streamedPartials.add,
      );

      expect(textFallbackCalled, isTrue);
      expect(capturedFallbackPrompt, contains('Where is the station?'));
      expect(capturedFallbackPrompt, contains('Korean'));
      expect(result.sourceLanguage, 'en');
      expect(result.originalText, 'Where is the station?');
      expect(result.translatedText, '역이 어디에 있나요?');
      // Verify the untranslated English echo was never streamed to onPartialResult
      expect(
        streamedPartials.map((p) => p.translatedText),
        isNot(contains('Where is the station?')),
      );
      expect(streamedPartials.last.translatedText, '역이 어디에 있나요?');

      await engine.dispose();
      await modelManager.close();
    });

    test('translateAudioChunk streams partial translated tokens in real time', () async {
      final modelManager = ModelManager(initialInstalled: true);
      final engine = LocalTranslationEngine(
        modelManager: modelManager,
        streamingInferenceRunner:
            ({
              required wavBytes,
              required systemPrompt,
              required userPrompt,
            }) async* {
              yield '{"original_transcript": "Hello friend", ';
              yield '"detected_language": "en", ';
              yield '"translated_text": "안녕하';
              yield '세요 친구';
              yield '"}';
            },
      );

      final partials = <TranslationResult>[];
      final result = await engine.translateAudioChunk(
        audioWavChunk: Float32List.fromList(<double>[0.25, -0.25]),
        baseLanguage: 'English',
        targetLanguage: 'Korean',
        exchangeRate: 0.0007,
        baseCurrency: 'USD',
        targetCurrency: 'KRW',
        onPartialResult: partials.add,
      );

      expect(
        partials.map((p) => p.translatedText).toList(),
        <String>['안녕하', '안녕하세요 친구'],
      );
      expect(partials.every((p) => p.sourceLanguage == 'en'), isTrue);
      expect(result.sourceLanguage, 'en');
      expect(result.translatedText, '안녕하세요 친구');

      await engine.dispose();
      await modelManager.close();
    });

    test('trimTrailingSilence trims multi-second trailing silence down to 4000 samples', () {
      final speech = List<double>.filled(8000, 0.25);
      final silence = List<double>.filled(24000, 0.0); // 1.5s silence
      final combined = Float32List.fromList(<double>[...speech, ...silence]);

      final trimmed = LocalTranslationEngine.trimTrailingSilence(combined);
      expect(trimmed.length, 8000 + 4000);
    });

    test('encodeAudioChunkInIsolate offloads silence trimming and WAV encoding to a background isolate', () async {
      final speech = List<double>.filled(8000, 0.25);
      final silence = List<double>.filled(16000, 0.0);
      final samples = Float32List.fromList(<double>[...speech, ...silence]);

      final (wavBytes, trimmedCount) =
          await LocalTranslationEngine.encodeAudioChunkInIsolate(samples);
      expect(trimmedCount, 8000 + 4000);
      expect(wavBytes.length, 44 + trimmedCount * 2);
    });

    test('isNonSpeechOrHallucination detects empty strings, silence markers, meta-refusals, and milk hallucinations', () {
      expect(
        LocalTranslationEngine.isNonSpeechOrHallucination(
          translatedText: '',
        ),
        isTrue,
      );
      expect(
        LocalTranslationEngine.isNonSpeechOrHallucination(
          translatedText: '[silence]',
        ),
        isTrue,
      );
      expect(
        LocalTranslationEngine.isNonSpeechOrHallucination(
          translatedText: 'There was no audio file, please provide an audio file.',
        ),
        isTrue,
      );
      expect(
        LocalTranslationEngine.isNonSpeechOrHallucination(
          originalText: 'There is no speech in this audio clip.',
          translatedText: '이 오디오 클립에는 음성이 없습니다.',
        ),
        isTrue,
      );
      expect(
        LocalTranslationEngine.isNonSpeechOrHallucination(
          originalText: 'I am going to the store to buy some milk.',
          translatedText: '나는 우유를 사러 가게에 간다.',
        ),
        isTrue,
      );
      expect(
        LocalTranslationEngine.isNonSpeechOrHallucination(
          translatedText: 'I am going to the store to buy some milk',
        ),
        isTrue,
      );
      expect(
        LocalTranslationEngine.isNonSpeechOrHallucination(
          originalText: 'Where is the nearest subway station?',
          translatedText: '가장 가까운 지하철역이 어디인가요?',
        ),
        isFalse,
      );
    });

    test('translateAudioChunk suppresses pause hallucinations and missing-audio refusals without streaming or fallback', () async {
      var textFallbackCalled = false;
      var nextModelOutput =
          '{"detected_language": "en", "original_transcript": "", "translated_text": ""}';

      final modelManager = ModelManager(initialInstalled: true);
      final engine = LocalTranslationEngine(
        modelManager: modelManager,
        inferenceRunner: ({required wavBytes, required systemPrompt}) async =>
            nextModelOutput,
        textInferenceRunner: ({required prompt, required systemPrompt}) async {
          textFallbackCalled = true;
          return 'Fallback should not run';
        },
      );

      final partials = <TranslationResult>[];

      // 1. Explicit empty JSON for conversational pause
      final emptyPauseResult = await engine.translateAudioChunk(
        audioWavChunk: Float32List.fromList(<double>[0.1, -0.1]),
        baseLanguage: 'English',
        targetLanguage: 'Korean',
        exchangeRate: 0.0007,
        baseCurrency: 'USD',
        targetCurrency: 'KRW',
        onPartialResult: partials.add,
      );
      expect(emptyPauseResult.translatedText, isEmpty);
      expect(partials, isEmpty);
      expect(textFallbackCalled, isFalse);

      // 2. Classic audio-encoder silence hallucination ("I am going to the store to buy some milk")
      nextModelOutput =
          '{"detected_language": "en", "original_transcript": "I am going to the store to buy some milk.", "translated_text": "저는 우유를 사러 가게에 갑니다."}';
      final milkHallucinationResult = await engine.translateAudioChunk(
        audioWavChunk: Float32List.fromList(<double>[0.1, -0.1]),
        baseLanguage: 'English',
        targetLanguage: 'Korean',
        exchangeRate: 0.0007,
        baseCurrency: 'USD',
        targetCurrency: 'KRW',
        onPartialResult: partials.add,
      );
      expect(milkHallucinationResult.translatedText, isEmpty);
      expect(partials, isEmpty);
      expect(textFallbackCalled, isFalse);

      // 3. Meta-refusal ("There was no audio file, please provide an audio file.")
      nextModelOutput = 'There was no audio file, please provide an audio file.';
      final noAudioRefusalResult = await engine.translateAudioChunk(
        audioWavChunk: Float32List.fromList(<double>[0.1, -0.1]),
        baseLanguage: 'English',
        targetLanguage: 'Korean',
        exchangeRate: 0.0007,
        baseCurrency: 'USD',
        targetCurrency: 'KRW',
        onPartialResult: partials.add,
      );
      expect(noAudioRefusalResult.translatedText, isEmpty);
      expect(partials, isEmpty);
      expect(textFallbackCalled, isFalse);

      await engine.dispose();
      await modelManager.close();
    });

    test('summarizeConversation generates and cleans a 3 to 5 word description', () async {
      String? capturedPrompt;
      String? capturedSystemPrompt;

      final modelManager = ModelManager(initialInstalled: true);
      final engine = LocalTranslationEngine(
        modelManager: modelManager,
        textInferenceRunner: ({required prompt, required systemPrompt}) async {
          capturedPrompt = prompt;
          capturedSystemPrompt = systemPrompt;
          return 'Summary: "Asking for subway directions downtown."';
        },
      );

      final summary = await engine.summarizeConversation(
        messages: <Message>[
          Message(
            id: 'm1',
            conversationId: 'c1',
            timestamp: DateTime.utc(2026, 1, 1, 10),
            isBaseLanguage: true,
            originalText: 'Where is the subway?',
            translatedText: '지하철이 어디에 있나요?',
          ),
        ],
        baseLanguage: 'English',
        targetLanguage: 'Korean',
      );

      expect(capturedSystemPrompt, contains('3 to 5 word'));
      expect(capturedPrompt, contains('Where is the subway?'));
      expect(summary, 'Asking for subway directions downtown');

      // Empty message list returns empty string without invoking runner
      expect(
        await engine.summarizeConversation(
          messages: const <Message>[],
          baseLanguage: 'English',
          targetLanguage: 'Korean',
        ),
        isEmpty,
      );

      // When native language is Korean ('ko') and the first pass accidentally returns English,
      // summarizeConversation automatically translates the summary into Korean (한국어).
      var callIndex = 0;
      final koEngine = LocalTranslationEngine(
        modelManager: modelManager,
        textInferenceRunner: ({required prompt, required systemPrompt}) async {
          callIndex++;
          if (callIndex == 1) {
            expect(systemPrompt, contains('Korean (한국어)'));
            expect(prompt, contains('Korean (한국어)'));
            return 'Asking for subway directions';
          }
          expect(prompt, contains('Korean (한국어)'));
          return '지하철 길 안내 문의';
        },
      );

      final koSummary = await koEngine.summarizeConversation(
        messages: <Message>[
          Message(
            id: 'm1',
            conversationId: 'c1',
            timestamp: DateTime.utc(2026, 1, 1, 10),
            isBaseLanguage: true,
            originalText: '지하철역이 어디에 있나요?',
            translatedText: 'Where is the subway station?',
          ),
        ],
        baseLanguage: 'Korean',
        targetLanguage: 'English',
      );
      expect(callIndex, 2);
      expect(koSummary, '지하철 길 안내 문의');

      await koEngine.dispose();
      await engine.dispose();
      await modelManager.close();
    });

    test('NetworkTranslationEngine resolves v1beta model IDs and retries on 404', () async {
      final parsedModels = NetworkTranslationEngine.parseAvailableModelIdsResponse(
        jsonEncode(<String, Object?>{
          'models': <Object?>[
            <String, Object?>{
              'name': 'models/gemini-3.1-pro-preview',
              'supportedGenerationMethods': <String>['generateContent'],
            },
            <String, Object?>{
              'name': 'models/gemini-2.5-flash',
              'supportedGenerationMethods': <String>['generateContent'],
            },
            <String, Object?>{
              'name': 'models/text-embedding-004',
              'supportedGenerationMethods': <String>['embedContent'],
            },
          ],
        }),
      );

      expect(
        parsedModels,
        equals(<String>{'gemini-3.1-pro-preview', 'gemini-2.5-flash'}),
      );
      expect(
        NetworkTranslationEngine.resolveEffectiveModelId(
          'gemini-3.1-pro',
          parsedModels,
        ),
        'gemini-3.1-pro-preview',
      );
      expect(
        NetworkTranslationEngine.resolveEffectiveModelId(
          'gemini-3.8-flash',
          parsedModels,
        ),
        'gemini-2.5-flash',
      );
    });
  });

  group('Separated Speech-to-Text (Gemma 4 / Cloud) & Translation Pipeline', () {
    test('SwitchableTranslationEngine executes Step 1 (STT) and Step 2 (Translation) across mixed On-Device and Cloud configurations', () async {
      final modelManager = ModelManager(
        initialInstalled: true,
        isInstalledCheck: () async => true,
      );

      var localAudioSttCalls = 0;
      var localTextTranslationCalls = 0;
      var cloudCalls = 0;

      final localEngine = LocalTranslationEngine(
        modelManager: modelManager,
        inferenceRunner: ({required wavBytes, required systemPrompt}) async {
          localAudioSttCalls++;
          if (localAudioSttCalls == 1) {
            return '{"original_transcript": "How much is this train ticket, 20 dollars?", "detected_language": "en"}';
          }
          return '{"original_transcript": "지하철역이 어디에 있나요?", "detected_language": "ko"}';
        },
        textInferenceRunner: ({required prompt, required systemPrompt}) async {
          localTextTranslationCalls++;
          if (prompt.contains('How much is this train ticket')) {
            return '이 기차표는 얼마인가요, 20달러(27600 KRW)인가요?';
          }
          if (prompt.contains('Good morning')) {
            return '좋은 아침입니다';
          }
          return 'Where is the subway station?';
        },
      );

      final mockClient = MockClient.streaming((request, bodyStream) async {
        await bodyStream.toBytes();
        if (request.url.path.contains('models') &&
            request.method == 'GET') {
          return http.StreamedResponse(
            Stream<List<int>>.fromIterable(<List<int>>[
              utf8.encode('{"models":[]}'),
            ]),
            200,
          );
        }
        cloudCalls++;
        if (request.url.path.contains('streamGenerateContent')) {
          // Cloud STT request (SSE)
          const sttPayload =
              '{"candidates":[{"content":{"parts":[{"text":"{\\"original_transcript\\": \\"Good morning\\", \\"detected_language\\": \\"en\\"}"}]}}]}';
          return http.StreamedResponse(
            Stream<List<int>>.fromIterable(<List<int>>[
              utf8.encode('data: $sttPayload\n\n'),
            ]),
            200,
          );
        } else {
          // Cloud Text Translation request (:generateContent JSON)
          const transPayload =
              '{"candidates":[{"content":{"parts":[{"text":"이 기차표는 클라우드에서 번역되었습니다."}]}}]}';
          return http.StreamedResponse(
            Stream<List<int>>.fromIterable(<List<int>>[
              utf8.encode(transPayload),
            ]),
            200,
            headers: const <String, String>{
              'content-type': 'application/json; charset=utf-8',
            },
          );
        }
      });

      final networkEngine = NetworkTranslationEngine(
        apiKeyProvider: () => 'AIzaTestKey',
        modelIdProvider: () => 'gemini-3.8-flash',
        httpClient: mockClient,
      );

      final switchable = SwitchableTranslationEngine(
        localEngine: localEngine,
        networkEngine: networkEngine,
        initialMode: TranslationEngineMode.onDevice,
        initialSttMode: TranslationEngineMode.onDevice,
      );

      final sampleAudio = Float32List.fromList(<double>[0.25, -0.25, 0.3, -0.2]);

      // Case 1: On-Device Gemma 4 STT + On-Device Gemma 4 Text Translation
      final result1 = await switchable.translateAudioChunk(
        audioWavChunk: sampleAudio,
        baseLanguage: 'English',
        targetLanguage: 'Korean',
        exchangeRate: 1380.0,
        baseCurrency: 'USD',
        targetCurrency: 'KRW',
      );
      expect(localAudioSttCalls, 1);
      expect(localTextTranslationCalls, 1);
      expect(result1.sourceLanguage, 'en');
      expect(result1.originalText, 'How much is this train ticket, 20 dollars?');
      expect(
        result1.translatedText,
        '이 기차표는 얼마인가요, 20달러(27600 KRW)인가요?',
      );
      expect(result1.speechToTextModel, 'Gemma 4');
      expect(result1.translationModel, 'Gemma 4');
      expect(result1.speechToTextMs, isNotNull);
      expect(result1.translationMs, isNotNull);

      // Case 2: On-Device Gemma 4 STT + Cloud Gemini Text Translation
      switchable.setMode(TranslationEngineMode.cloud);
      final result2 = await switchable.translateAudioChunk(
        audioWavChunk: sampleAudio,
        baseLanguage: 'English',
        targetLanguage: 'Korean',
        exchangeRate: 1380.0,
        baseCurrency: 'USD',
        targetCurrency: 'KRW',
      );
      expect(localAudioSttCalls, 2);
      expect(cloudCalls, 1);
      expect(result2.translatedText, '이 기차표는 클라우드에서 번역되었습니다.');
      expect(result2.speechToTextModel, 'Gemma 4');
      expect(result2.translationModel, 'Gemini 3.8 Flash');

      // Case 3: Cloud Gemini STT + On-Device Gemma 4 Text Translation
      switchable
        ..setSttMode(TranslationEngineMode.cloud)
        ..setMode(TranslationEngineMode.onDevice);
      final result3 = await switchable.translateAudioChunk(
        audioWavChunk: sampleAudio,
        baseLanguage: 'English',
        targetLanguage: 'Korean',
        exchangeRate: 1380.0,
        baseCurrency: 'USD',
        targetCurrency: 'KRW',
      );
      expect(cloudCalls, 2);
      expect(localTextTranslationCalls, 2);
      expect(result3.originalText, 'Good morning');
      expect(result3.translatedText, '좋은 아침입니다');
      expect(result3.speechToTextModel, 'Gemini 3.8 Flash');
      expect(result3.translationModel, 'Gemma 4');

      // Case 4: On-Device Gemma 4 Audio STT + On-Device Gemma 4 Text Translation
      switchable.setSttMode(TranslationEngineMode.onDevice);
      final result4 = await switchable.translateAudioChunk(
        audioWavChunk: sampleAudio,
        baseLanguage: 'English',
        targetLanguage: 'Korean',
        exchangeRate: 1380.0,
        baseCurrency: 'USD',
        targetCurrency: 'KRW',
      );
      expect(localAudioSttCalls, 3);
      expect(localTextTranslationCalls, 3);
      expect(result4.sourceLanguage, 'ko');
      expect(result4.originalText, '지하철역이 어디에 있나요?');
      expect(result4.translatedText, 'Where is the subway station?');

      await switchable.dispose();
      await modelManager.close();
    });
  });
}
