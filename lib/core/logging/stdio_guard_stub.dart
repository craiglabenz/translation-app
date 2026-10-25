import 'dart:isolate';

/// No-op on web platforms where POSIX file descriptors do not exist.
void saveOriginalStdioFds() {}

/// No-op on web platforms where POSIX file descriptors do not exist.
void restoreOriginalStdioFds() {}

/// Registers the main isolate's log [SendPort] in the process-wide lookup table.
void registerMainLogPort(String portName, SendPort sendPort) {}

/// Looks up the main isolate's log [SendPort] from a background isolate.
SendPort? lookupMainLogPort(String portName) => null;

/// Returns a short debug label for the current isolate.
String currentIsolateDebugName() => 'main';
