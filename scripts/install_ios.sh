#!/usr/bin/env bash
# ==============================================================================
# Build & Install Standalone Untethered iOS Release / Ad-Hoc App on an iPhone
# ==============================================================================
# How long does the installed iOS build last?
#   • Paid Apple Developer Program account ($99/yr, e.g. Team KNK9SM7SLS):
#       - Ad-Hoc build (`--ad-hoc`): lasts up to 12 MONTHS (365 days)
#         (specifically, until the Apple Distribution certificate or Ad-Hoc
#         provisioning profile expires, whichever comes first).
#       - Automatic Release build (default): also lasts up to 12 MONTHS (365 days)
#         when signed with a paid Apple Developer Team in Xcode.
#   • Free Apple ID ("Personal Team"):
#       - Provisioning profile expires after 7 DAYS (hard Apple limit for free
#         accounts; after 7 days iOS shows "Babble is no longer available").
#
# Why not just `flutter run`?
#   Standard `flutter run` installs a Debug (JIT) build. On iOS 14+, Apple's
#   kernel blocks JIT execution as soon as the Xcode debugger disconnects, so
#   a Debug build crashes immediately if tapped on the iPhone home screen while
#   unplugged. This script compiles an Ahead-Of-Time (AOT) `--release` binary.
#
# Usage:
#   ./scripts/install_ios.sh [options]
#
# Options:
#   -d, --device <id>               Target iPhone device ID / UDID or name
#                                   (auto-detects connected iPhone if omitted)
#   --ad-hoc                        Build an Ad-Hoc signed .ipa (`--export-method ad-hoc`)
#                                   before installing (requires Apple Distribution cert)
#   --open-xcode                    Open `ios/Runner.xcworkspace` in Xcode to configure
#                                   signing / register device, then exit
#   --setup-guide                   Print the full step-by-step iPhone + Xcode setup guide
#   --team-id <team_id>             Apple Developer Team ID (default: KNK9SM7SLS)
#   --dart-define <KEY=VALUE>       Pass additional --dart-define to flutter build (repeatable)
#   --no-launch                     Install the app without launching it afterward
#   --skip-pub-get                  Skip running `flutter pub get`
#   -h, --help                      Show this help message
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_ROOT}"

DEVICE_ID="${IOS_DEVICE_ID:-}"
USE_ADHOC=false
APPLE_TEAM_ID="${APPLE_TEAM_ID:-KNK9SM7SLS}"
IOS_BUNDLE_ID="${IOS_BUNDLE_ID:-com.craiglabenz.babble}"
LAUNCH_AFTER_INSTALL=true
SKIP_PUB_GET=false
DART_DEFINES=()

usage() {
  sed -n '2,38p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

print_ios_setup_guide() {
  cat <<'EOF'
==============================================================================
📖 STEP-BY-STEP GUIDE: Preparing Your iPhone & Xcode for Long-Lived Installs
==============================================================================

STEP 1 — On Your iPhone: Enable Developer Mode (Required on iOS 16+)
  1. Plug your iPhone into your Mac using a USB-C / Lightning data cable.
  2. On your iPhone, open:
       Settings → Privacy & Security → scroll to the bottom → Developer Mode
  3. Toggle "Developer Mode" ON and tap "Restart".
  4. After your iPhone finishes restarting, unlock it, tap "Turn On" on the
     popup alert, and enter your iPhone passcode.

STEP 2 — On Your iPhone: Trust This Computer
  1. With your iPhone unlocked and plugged into your Mac, look for the
     "Trust This Computer?" alert on your iPhone screen.
  2. Tap "Trust" and enter your iPhone passcode.

STEP 3 — In Xcode: Sign In & Select Your Apple Developer Team (One-Time Setup)
  1. Open the iOS workspace in Xcode by running:
       open ios/Runner.xcworkspace
     (or run `./scripts/install_ios.sh --open-xcode`)
  2. Add your Apple ID to Xcode (if not already added):
       • In the top menu bar, click: Xcode → Settings… (⌘,) → Accounts tab
       • Click the "+" button (bottom-left) → choose "Apple ID" → sign in.
  3. Select your Signing Team on the Runner target:
       • In Xcode's left sidebar (Project Navigator), click "Runner" (top blue icon).
       • Select the "Runner" target under TARGETS, then click the
         "Signing & Capabilities" tab at the top.
       • Ensure "Automatically manage signing" is CHECKED.
       • In the "Team" dropdown:
           - Select your PAID Apple Developer Team (lasts up to 12 MONTHS).
           - Avoid "Your Name (Personal Team)" if possible (free accounts
             expire after 7 DAYS).
  4. Register your iPhone's UDID (automatic):
       • Select your connected iPhone in Xcode's top toolbar device selector.
       • If Xcode shows a "Register Device" button under Signing & Capabilities,
         click "Register Device" so Xcode adds your iPhone to your provisioning
         profile.

STEP 4 — On Your iPhone: Trust Developer Certificate (If Prompted on First Launch)
  • Paid Apple Developer accounts usually do not require this step.
  • If iOS shows an "Untrusted Developer" popup when opening the app:
      Open Settings → General → VPN & Device Management → tap your Developer
      App certificate → tap "Trust".
==============================================================================
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--device)
      DEVICE_ID="$2"
      shift 2
      ;;
    --ad-hoc|--adhoc)
      USE_ADHOC=true
      shift
      ;;
    --open-xcode)
      echo "🛠️  Opening ios/Runner.xcworkspace in Xcode..."
      open "${PROJECT_ROOT}/ios/Runner.xcworkspace"
      exit 0
      ;;
    --setup-guide|--guide)
      print_ios_setup_guide
      exit 0
      ;;
    --team-id)
      APPLE_TEAM_ID="$2"
      shift 2
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
      echo "Tip: Run './scripts/install_ios.sh --setup-guide' for detailed iPhone & Xcode setup instructions."
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
echo "🍎 Building & Installing Standalone Untethered iOS Release App"
echo "=============================================================================="

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "❌ Error: iOS builds and device installation require macOS with Xcode." >&2
  exit 1
fi

if ! command -v flutter >/dev/null 2>&1; then
  echo "❌ Error: 'flutter' command not found on PATH." >&2
  exit 1
fi

if [[ -n "${GEMINI_API_KEY:-}" ]]; then
  DART_DEFINES+=("--dart-define=GEMINI_API_KEY=${GEMINI_API_KEY}")
fi

# 1. Auto-detect a connected physical iOS device if --device was not specified
if [[ -z "${DEVICE_ID}" ]]; then
  echo "🔍 Searching for connected physical iPhone / iPad..."
  if command -v xcrun >/dev/null 2>&1; then
    DEVICE_ID="$(xcrun xctrace list devices 2>/dev/null \
      | awk '/^== Devices ==/{flag=1; next} /^==/{flag=0} flag' \
      | grep -E -i "iPhone|iPad" \
      | grep -v -i "Simulator" \
      | sed -E 's/.*\(([0-9A-Fa-f-]+)\)[[:space:]]*$/\1/' \
      | head -n 1 || true)"
  fi
  if [[ -z "${DEVICE_ID}" ]]; then
    DEVICE_ID="$(flutter devices 2>/dev/null \
      | grep -E "ios" \
      | grep -v -i "simulator" \
      | awk -F '•' '{print $2}' \
      | xargs \
      | head -n 1 || true)"
  fi
fi

if [[ -z "${DEVICE_ID}" ]]; then
  echo "❌ No connected physical iPhone or iPad detected." >&2
  echo "" >&2
  print_ios_setup_guide >&2
  exit 1
fi

echo "📱 Target iOS Device ID: ${DEVICE_ID}"

if [[ "${SKIP_PUB_GET}" != "true" ]]; then
  echo "📦 Running flutter pub get..."
  flutter pub get
fi

FLUTTER_BUILD_ARGS=("--release")
if [[ ${#DART_DEFINES[@]} -gt 0 ]]; then
  FLUTTER_BUILD_ARGS+=("${DART_DEFINES[@]}")
fi

APP_BUNDLE_PATH="${PROJECT_ROOT}/build/ios/iphoneos/Runner.app"
INSTALL_ARTIFACT="${APP_BUNDLE_PATH}"

if [[ "${USE_ADHOC}" == "true" ]]; then
  echo "🔨 Building Ad-Hoc Release IPA (flutter build ipa --release --export-method=ad-hoc)..."
  if flutter build ipa "${FLUTTER_BUILD_ARGS[@]}" --export-method=ad-hoc; then
    IPA_FILE="$(find "${PROJECT_ROOT}/build/ios/ipa" -maxdepth 1 -name "*.ipa" | head -n 1 || true)"
    if [[ -n "${IPA_FILE}" && -f "${IPA_FILE}" ]]; then
      INSTALL_ARTIFACT="${IPA_FILE}"
      echo "✅ Built Ad-Hoc IPA: ${INSTALL_ARTIFACT}"
    fi
  else
    echo "⚠️  Ad-Hoc IPA export failed (usually means no 'Apple Distribution' cert or Ad-Hoc profile is in Keychain)."
    echo "   Falling back to automatic-signed AOT Release build ('flutter build ios --release')..."
    if ! flutter build ios "${FLUTTER_BUILD_ARGS[@]}"; then
      echo "" >&2
      echo "❌ iOS Release build failed. If this is a signing error, follow the Xcode setup guide below:" >&2
      print_ios_setup_guide >&2
      exit 1
    fi
  fi
else
  echo "🔨 Building AOT Release iOS bundle: flutter build ios ${FLUTTER_BUILD_ARGS[*]}"
  if ! flutter build ios "${FLUTTER_BUILD_ARGS[@]}"; then
    echo "" >&2
    echo "❌ iOS Release build failed. If this is a signing error, follow the Xcode setup guide below:" >&2
    print_ios_setup_guide >&2
    exit 1
  fi
fi

if [[ ! -d "${APP_BUNDLE_PATH}" && ! -f "${INSTALL_ARTIFACT}" ]]; then
  echo "❌ Error: Expected iOS build output not found at ${INSTALL_ARTIFACT}" >&2
  exit 1
fi

# 2. Inspect provisioning profile expiration so the developer knows exact days remaining
PROVISION_FILE="${APP_BUNDLE_PATH}/embedded.mobileprovision"
if [[ -f "${PROVISION_FILE}" ]]; then
  echo "------------------------------------------------------------------------------"
  echo "🔐 Inspecting Embedded Provisioning Profile:"
  PROFILE_PLIST="$(security cms -D -i "${PROVISION_FILE}" 2>/dev/null || true)"
  if [[ -n "${PROFILE_PLIST}" ]]; then
    PROFILE_NAME="$(/usr/libexec/PlistBuddy -c "Print :Name" /dev/stdin <<< "${PROFILE_PLIST}" 2>/dev/null || echo "Unknown")"
    TEAM_NAME="$(/usr/libexec/PlistBuddy -c "Print :TeamName" /dev/stdin <<< "${PROFILE_PLIST}" 2>/dev/null || echo "Unknown")"
    EXPIRATION_RAW="$(/usr/libexec/PlistBuddy -c "Print :ExpirationDate" /dev/stdin <<< "${PROFILE_PLIST}" 2>/dev/null || echo "Unknown")"
    DAYS_REMAINING=""
    if command -v python3 >/dev/null 2>&1 && [[ "${EXPIRATION_RAW}" != "Unknown" ]]; then
      DAYS_REMAINING="$(python3 - "${EXPIRATION_RAW}" <<'PY' 2>/dev/null || true
import datetime, sys
from email.utils import parsedate_to_datetime
raw = sys.argv[1].strip()
for fmt in ("%a %b %d %H:%M:%S %Z %Y", "%Y-%m-%dT%H:%M:%SZ"):
    try:
        dt = datetime.datetime.strptime(raw, fmt)
        now = datetime.datetime.now()
        days = (dt - now).days
        print(f"{days} days remaining")
        sys.exit(0)
    except Exception:
        pass
PY
)"
    fi
    echo "   • Profile Name : ${PROFILE_NAME}"
    echo "   • Team Name    : ${TEAM_NAME} (${APPLE_TEAM_ID})"
    if [[ -n "${DAYS_REMAINING}" ]]; then
      echo "   • Expires On   : ${EXPIRATION_RAW} (${DAYS_REMAINING})"
    else
      echo "   • Expires On   : ${EXPIRATION_RAW}"
    fi
    if echo "${PROFILE_NAME} ${TEAM_NAME}" | grep -qi "Personal Team"; then
      echo "   ⚠️  WARNING: Signed with a Free 'Personal Team' — Apple expires free profiles after 7 DAYS."
      echo "      To get a 12-month (365-day) build, select your paid Apple Developer Team in Xcode:"
      echo "      Run: ./scripts/install_ios.sh --open-xcode"
    fi
  fi
  echo "------------------------------------------------------------------------------"
fi

# 3. Install onto the physical iPhone preserving existing app documents/models when possible
echo "📲 Installing Release build onto device (${DEVICE_ID})..."
INSTALLED=false

if command -v xcrun >/dev/null 2>&1; then
  if xcrun devicectl device install app --device "${DEVICE_ID}" "${INSTALL_ARTIFACT}"; then
    INSTALLED=true
  else
    echo "ℹ️  xcrun devicectl install did not complete; falling back to 'flutter install --release'..."
  fi
fi

if [[ "${INSTALLED}" != "true" ]]; then
  flutter install --release -d "${DEVICE_ID}"
fi

if [[ "${LAUNCH_AFTER_INSTALL}" == "true" ]] && command -v xcrun >/dev/null 2>&1; then
  echo "🚀 Launching ${IOS_BUNDLE_ID} on device..."
  xcrun devicectl device process launch --device "${DEVICE_ID}" "${IOS_BUNDLE_ID}" >/dev/null 2>&1 || true
fi

echo "=============================================================================="
echo "✅ Standalone iOS Release build installed on ${DEVICE_ID}!"
echo "   • Compiled in AOT Release mode (no Xcode/debugger connection needed)."
echo "   • You can unplug your iPhone and launch 'Babble' anytime."
echo "=============================================================================="
