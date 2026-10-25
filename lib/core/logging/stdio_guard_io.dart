import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:translation_app/core/utils/platform_env.dart';

typedef _DupNative = Int32 Function(Int32 fd);
typedef _DupDart = int Function(int fd);
typedef _Dup2Native = Int32 Function(Int32 from, Int32 to);
typedef _Dup2Dart = int Function(int from, int to);

int _savedStdoutFd = -1;
int _savedStderrFd = -1;
_DupDart? _dupFn;
_Dup2Dart? _dup2Fn;
bool _posixInitTried = false;

void _ensurePosixFunctions() {
  if (_posixInitTried) return;
  _posixInitTried = true;
  if (!(Platform.isIOS || Platform.isMacOS || Platform.isLinux)) {
    return;
  }
  try {
    final libc = DynamicLibrary.process();
    _dupFn = libc.lookupFunction<_DupNative, _DupDart>('dup');
    _dup2Fn = libc.lookupFunction<_Dup2Native, _Dup2Dart>('dup2');
  } on Object {
    _dupFn = null;
    _dup2Fn = null;
  }
}

/// Saves duplicates of the original stdout (fd 1) and stderr (fd 2) file
/// descriptors at app startup before native libraries (such as
/// `flutter_edge_ai_litertlm`'s `stream_proxy_redirect_stderr`) redirect fd 2
/// to `/tmp/litertlm_native.log`.
///
/// On iOS with Xcode 26 (`devicectl --console`), `OS_ACTIVITY_DT_MODE=enable`
/// causes `os_log`/`NSLog` (used by Flutter's `print`/`debugPrint`) to write to
/// stderr (fd 2). Saving fd 2 before model load allows [restoreOriginalStdioFds]
/// to put stderr back onto the console pipe after native model initialization.
void saveOriginalStdioFds() {
  if (isFlutterTestEnvironment) return;
  _ensurePosixFunctions();
  final dup = _dupFn;
  if (dup == null) return;
  try {
    if (_savedStdoutFd < 0) {
      _savedStdoutFd = dup(1);
    }
    if (_savedStderrFd < 0) {
      _savedStderrFd = dup(2);
    }
  } on Object {
    // Best-effort only.
  }
}

/// Restores stdout (fd 1) and stderr (fd 2) to the descriptors saved by
/// [saveOriginalStdioFds].
void restoreOriginalStdioFds() {
  if (isFlutterTestEnvironment) return;
  final dup2 = _dup2Fn;
  if (dup2 == null) return;
  try {
    if (_savedStdoutFd >= 0) {
      dup2(_savedStdoutFd, 1);
    }
    if (_savedStderrFd >= 0) {
      dup2(_savedStderrFd, 2);
    }
  } on Object {
    // Best-effort only.
  }
}

/// Registers the main isolate's log [SendPort] in [IsolateNameServer] so any
/// spawned background isolate can look it up by [portName] and forward log
/// records back to the main thread.
void registerMainLogPort(String portName, SendPort sendPort) {
  try {
    IsolateNameServer.removePortNameMapping(portName);
    IsolateNameServer.registerPortWithName(sendPort, portName);
  } on Object {
    // Ignore if IsolateNameServer is unavailable in a non-Flutter Dart VM test.
  }
}

/// Looks up the main isolate's log [SendPort] from a background isolate.
SendPort? lookupMainLogPort(String portName) {
  try {
    return IsolateNameServer.lookupPortByName(portName);
  } on Object {
    return null;
  }
}

/// Returns a short debug label for the current isolate.
String currentIsolateDebugName() => Isolate.current.debugName ?? 'isolate';
