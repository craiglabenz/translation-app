import 'dart:typed_data';

import 'package:freezed_annotation/freezed_annotation.dart';

part 'speech_to_text_engine.freezed.dart';
part 'speech_to_text_engine.g.dart';

/// Structured output of the Speech-to-Text (STT) step (Step 1 of the
/// separated translation pipeline).
@freezed
abstract class SpeechToTextResult with _$SpeechToTextResult {
  const factory SpeechToTextResult({
    required String transcript,
    required String detectedLanguageCode,
    required int durationMs,
    String? modelName,
  }) = _SpeechToTextResult;

  factory SpeechToTextResult.fromJson(Map<String, Object?> json) =>
      _$SpeechToTextResultFromJson(json);
}

/// Abstract contract for Step 1: Speech-to-Text (ASR) and language detection.
abstract class SpeechToTextEngine {
  Future<void> initialize();

  Future<SpeechToTextResult> transcribeAudio({
    required Float32List audioWavChunk,
    required String baseLanguage,
    required String targetLanguage,
  });

  Future<void> dispose();
}
