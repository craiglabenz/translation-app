/// Base exception for audio capture and processing failures.
class AudioCaptureException implements Exception {
  const AudioCaptureException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() =>
      cause == null
          ? 'AudioCaptureException: $message'
          : 'AudioCaptureException: $message ($cause)';
}

/// Thrown when microphone permission is denied or unavailable.
class MicrophonePermissionException extends AudioCaptureException {
  const MicrophonePermissionException([
    super.message = 'Microphone permission was denied.',
  ]);
}
