import 'dart:typed_data';

import 'package:freezed_annotation/freezed_annotation.dart';

part 'speech_to_text_engine.freezed.dart';
part 'speech_to_text_engine.g.dart';

/// A contiguous language-tagged transcript span within a spoken audio chunk.
@immutable
class SpeechSegment {
  const SpeechSegment({
    required this.text,
    required this.languageCode,
  });

  factory SpeechSegment.fromJson(Map<String, Object?> json) {
    return SpeechSegment(
      text: (json['text'] as String? ?? json['transcript'] as String? ?? '')
          .trim(),
      languageCode:
          (json['languageCode'] as String? ??
                  json['lang'] as String? ??
                  json['detected_language'] as String? ??
                  '')
              .trim(),
    );
  }

  /// Transcribed text in its original spoken language.
  final String text;

  /// Canonical 2-letter language code (`baseCode` or `targetCode`).
  final String languageCode;

  Map<String, Object?> toJson() => <String, Object?>{
    'text': text,
    'languageCode': languageCode,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SpeechSegment &&
          other.text == text &&
          other.languageCode == languageCode);

  @override
  int get hashCode => Object.hash(text, languageCode);

  @override
  String toString() =>
      'SpeechSegment(languageCode: $languageCode, text: $text)';
}

/// Structured output of the Speech-to-Text (STT) step (Step 1 of the
/// separated translation pipeline).
@freezed
abstract class SpeechToTextResult with _$SpeechToTextResult {
  const SpeechToTextResult._();

  const factory SpeechToTextResult({
    required String transcript,
    required String detectedLanguageCode,
    required int durationMs,
    String? modelName,
    @Default(<SpeechSegment>[]) List<SpeechSegment> segments,
  }) = _SpeechToTextResult;

  factory SpeechToTextResult.fromJson(Map<String, Object?> json) =>
      _$SpeechToTextResultFromJson(json);

  /// Ordered language-tagged segments for this STT pass, falling back to a
  /// single segment from [transcript] and [detectedLanguageCode] when
  /// [segments] was not explicitly populated.
  List<SpeechSegment> get effectiveSegments {
    if (segments.isNotEmpty) {
      return segments;
    }
    final trimmed = transcript.trim();
    if (trimmed.isEmpty) {
      return const <SpeechSegment>[];
    }
    return <SpeechSegment>[
      SpeechSegment(
        text: trimmed,
        languageCode: detectedLanguageCode,
      ),
    ];
  }
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
