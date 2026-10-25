#!/usr/bin/env bash
# ==============================================================================
# Build & Install Standalone Untethered Android Release APK on an Android Phone
# ==============================================================================
# How long does the installed Android build last?
#   • FOREVER (indefinitely, until uninstalled).
#   • Unlike iOS (which enforces 7-day or 12-month provisioning profile
#     expirations), Android has NO provisioning profiles. A signed Ahead-Of-Time
#     (AOT) Release APK (`flutter build apk --release`) is signed with a
#     keystore certificate valid for 25+ years and runs standalone forever.
#
# Usage:
#   ./scripts/install_android.sh [options]
#
# Options:
#   -d, --device <serial>           Target Android device serial (from `adb devices`
#                                   or `flutter devices`; auto-detected if omitted)
#   --setup-guide                   Print the full step-by-step Android phone setup guide
#   --uninstall-first               Uninstall existing app first (useful if switching
#                                   signing certificates / `INSTALL_FAILED_UPDATE_INCOMPATIBLE`)
#   --dart-define <KEY=VALUE>       Pass additional --dart-define to flutter build (repeatable)
#   --no-launch                     Install the APK without launching it afterward
#   --skip-pub-get                  Skip running `flutter pub get`
#   -h, --help                      Show this help message
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_ROOT}"

DEVICE_ID="${ANDROID_DEVICE_ID:-}"
ANDROID_APP_ID="${ANDROID_APP_ID:-com.craiglabenz.babble}"
UNINSTALL_FIRST=false
LAUNCH_AFTER_INSTALL=true
SKIP_PUB_GET=false
DART_DEFINES=()

usage() {
  sed -n '2,25p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

print_android_setup_guide() {
  cat <<'EOF'
==============================================================================
📖 STEP-BY-STEP GUIDE: Preparing Your Android Phone for Installation
==============================================================================

STEP 1 — On Your Android Phone: Unlock "Developer Options" (One-Time Setup)
  1. Open the "Settings" app on your Android phone.
  2. Scroll to the bottom and tap "About phone"
     (on Samsung Galaxy devices: tap "About phone" → "Software information").
  3. Find "Build number" and tap it rapidly 7 TIMES in a row.
  4. Enter your phone's lock-screen PIN/pattern when prompted. You will see a
     toast message: "You are now a developer!"

STEP 2 — On Your Android Phone: Enable USB Debugging
  1. Go back to the main "Settings" screen.
  2. Open "System" → "Developer options"
     (on Samsung: "Settings" → "Developer options" at the very bottom;
      on Xiaomi/OnePlus: "Settings" → "Additional settings" → "Developer options").
  3. Scroll down and toggle "USB debugging" ON, then tap "OK" on the confirmation
     dialog.
     • Optional (Xiaomi/MIUI only): Also toggle "Install via USB" ON.

STEP 3 — Connect via USB & Authorize Your Computer
  1. Plug your Android phone into your Mac/PC using a data-capable USB cable.
  2. Unlock your phone screen.
  3. An alert titled "Allow USB debugging?" (showing your computer's RSA key
     fingerprint) will pop up on your phone:
       • Check the box: "Always allow from this computer"
       • Tap "Allow"
  4. Verify your phone is connected by running:
       flutter devices
     Then re-run:
       ./scripts/install_android.sh
==============================================================================
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--device)
      DEVICE_ID="$2"
      shift 2
      ;;
    --setup-guide|--guide)
      print_android_setup_guide
      exit 0
      ;;
    --uninstall-first)
      UNINSTALL_FIRST=true
      shift
      ;;
    --dart-define)
      DART_DEFINES+=("--dart-define=$2")
      shift 2
      ;;
    --no-launch)
      LAUNCH_AFTER_INSTALL=false
      shift
      ;;
    --skip-pub-get)
      SKIP_PUB_GET=true
      shift
      ;;
    -h|--help)
      usage
      echo ""
      echo "Tip: Run './scripts/install_android.sh --setup-guide' for detailed Android USB debugging instructions."
      exit 0
      ;;
    *)
      echo "❌ Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

echo "=============================================================================="
echo "🤖 Building & Installing Standalone Untethered Android Release APK"
echo "=============================================================================="

if ! command -v flutter >/dev/null 2>&1; then
  echo "❌ Error: 'flutter' command not found on PATH." >&2
  exit 1
fi

# Resolve adb binary from PATH or Android SDK
ADB_BIN=""
if command -v adb >/dev/null 2>&1; then
  ADB_BIN="$(command -v adb)"
elif [[ -n "${ANDROID_HOME:-}" && -x "${ANDROID_HOME}/platform-tools/adb" ]]; then
  ADB_BIN="${ANDROID_HOME}/platform-tools/adb"
elif [[ -n "${ANDROID_SDK_ROOT:-}" && -x "${ANDROID_SDK_ROOT}/platform-tools/adb" ]]; then
  ADB_BIN="${ANDROID_SDK_ROOT}/platform-tools/adb"
elif [[ -x "${HOME}/Library/Android/sdk/platform-tools/adb" ]]; then
  ADB_BIN="${HOME}/Library/Android/sdk/platform-tools/adb"
fi

if [[ -n "${GEMINI_API_KEY:-}" ]]; then
  DART_DEFINES+=("--dart-define=GEMINI_API_KEY=${GEMINI_API_KEY}")
fi

# Check if a device is plugged in but still awaiting the "Allow USB debugging?" prompt
if [[ -z "${DEVICE_ID}" && -n "${ADB_BIN}" ]]; then
  UNAUTHORIZED_DEV="$("${ADB_BIN}" devices | awk 'NR>1 && $2=="unauthorized" {print $1; exit}' || true)"
  if [[ -n "${UNAUTHORIZED_DEV}" ]]; then
    echo "⚠️  Android device (${UNAUTHORIZED_DEV}) is connected via USB but UNAUTHORIZED." >&2
    echo "   👉 Unlock your phone screen now, check 'Always allow from this computer', and tap 'Allow'!" >&2
    echo "" >&2
    print_android_setup_guide >&2
    exit 1
  fi
fi

# 1. Auto-detect a connected physical Android device (prefer physical over emulator)
if [[ -z "${DEVICE_ID}" ]]; then
  echo "🔍 Searching for connected Android device..."
  if [[ -n "${ADB_BIN}" ]]; then
    # Prefer physical USB/Wi-Fi devices (not starting with 'emulator-')
    DEVICE_ID="$("${ADB_BIN}" devices \
      | awk 'NR>1 && $2=="device" && $1 !~ /^emulator-/ {print $1; exit}' || true)"
    if [[ -z "${DEVICE_ID}" ]]; then
      DEVICE_ID="$("${ADB_BIN}" devices \
        | awk 'NR>1 && $2=="device" {print $1; exit}' || true)"
    fi
  fi
  if [[ -z "${DEVICE_ID}" ]]; then
    DEVICE_ID="$(flutter devices 2>/dev/null \
      | grep -E -i "android" \
      | awk -F '•' '{print $2}' \
      | xargs \
      | head -n 1 || true)"
  fi
fi

if [[ -z "${DEVICE_ID}" ]]; then
  echo "❌ No connected Android device detected." >&2
  echo "" >&2
  print_android_setup_guide >&2
  exit 1
fi

echo "📱 Target Android Device: ${DEVICE_ID}"

if [[ "${SKIP_PUB_GET}" != "true" ]]; then
  echo "📦 Running flutter pub get..."
  flutter pub get
fi

# 2. Build the AOT Release APK via scripts/build_android.sh
BUILD_ARGS=("--apk" "--skip-pub-get")
if [[ ${#DART_DEFINES[@]} -gt 0 ]]; then
  for def in "${DART_DEFINES[@]}"; do
    BUILD_ARGS+=("--dart-define" "${def#--dart-define=}")
  done
fi

"${SCRIPT_DIR}/build_android.sh" "${BUILD_ARGS[@]}"

APK_OUTPUT_PATH="${PROJECT_ROOT}/build/app/outputs/flutter-apk/app-release.apk"
if [[ ! -f "${APK_OUTPUT_PATH}" ]]; then
  echo "❌ Error: Release APK not found at ${APK_OUTPUT_PATH}" >&2
  exit 1
fi

# 3. Install onto the connected Android device
if [[ -n "${ADB_BIN}" ]]; then
  if [[ "${UNINSTALL_FIRST}" == "true" ]]; then
    echo "🧹 Uninstalling existing ${ANDROID_APP_ID} from ${DEVICE_ID}..."
    "${ADB_BIN}" -s "${DEVICE_ID}" uninstall "${ANDROID_APP_ID}" >/dev/null 2>&1 || true
  fi

  echo "📲 Installing ${APK_OUTPUT_PATH} onto ${DEVICE_ID} (in-place upgrade '-r')..."
  if ! "${ADB_BIN}" -s "${DEVICE_ID}" install -r "${APK_OUTPUT_PATH}"; then
    echo "⚠️  In-place install failed (likely a signing key mismatch with a previous install)." >&2
    echo "   Re-run with '--uninstall-first' to replace the existing installation:" >&2
    echo "   ./scripts/install_android.sh --uninstall-first" >&2
    exit 1
  fi

  if [[ "${LAUNCH_AFTER_INSTALL}" == "true" ]]; then
    echo "🚀 Launching ${ANDROID_APP_ID} on ${DEVICE_ID}..."
    "${ADB_BIN}" -s "${DEVICE_ID}" shell monkey -p "${ANDROID_APP_ID}" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true
  fi
else
  echo "📲 Installing Release APK via 'flutter install --release -d ${DEVICE_ID}'..."
  flutter install --release -d "${DEVICE_ID}"
fi

echo "=============================================================================="
echo "✅ Standalone Android Release APK installed on ${DEVICE_ID}!"
echo "   • Compiled in AOT Release mode (runs natively without a computer)."
echo "   • Android Release APKs NEVER expire — this build will launch indefinitely."
echo "=============================================================================="
