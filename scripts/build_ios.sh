#!/usr/bin/env bash
# ==============================================================================
# Build iOS Release (.ipa) for Firebase App Distribution & CI
# ==============================================================================
# Usage:
#   ./scripts/build_ios.sh [options]
#
# Options:
#   --export-method <method>        Export method: ad-hoc (default for Firebase),
#                                   development, enterprise, app-store
#   --export-options-plist <path>   Custom ExportOptions.plist path (overrides auto-generation)
#   --team-id <team_id>             Apple Developer Team ID (default: KNK9SM7SLS)
#   --bundle-id <bundle_id>         iOS Bundle ID (default: com.craiglabenz.babble)
#   --provisioning-profile <name>   Provisioning profile name or UUID for manual signing
#   --no-codesign                   Build unsigned iOS archive (`flutter build ios --release --no-codesign`)
#   --build-name <version>          Override version name (e.g. 1.0.0)
#   --build-number <number>         Override build number (defaults to CI run number if present)
#   --dart-define <KEY=VALUE>       Pass additional --dart-define to flutter build (repeatable)
#   --distribute                    Upload the built IPA to Firebase App Distribution after build
#   --testers <emails>              Comma-separated tester emails for Firebase App Distribution
#   --groups <groups>               Comma-separated tester group aliases for Firebase App Distribution
#   --release-notes <notes>         Release notes text for Firebase App Distribution
#   --skip-pub-get                  Skip running `flutter pub get` before building
#   -h, --help                      Show this help message
#
# Environment Variables (CI-friendly):
#   IOS_EXPORT_METHOD               Export method (default: ad-hoc)
#   EXPORT_OPTIONS_PLIST            Path to a custom ExportOptions.plist
#   APPLE_TEAM_ID                   Apple Developer Team ID (default: KNK9SM7SLS)
#   IOS_BUNDLE_ID                   Bundle identifier (default: com.craiglabenz.babble)
#   IOS_PROVISIONING_PROFILE        Provisioning profile name or UUID (optional)
#   IOS_P12_BASE64                  Base64-encoded Apple distribution certificate (.p12) for CI
#   IOS_P12_PASSWORD                Password for the .p12 certificate
#   IOS_PROVISIONING_PROFILE_BASE64 Base64-encoded .mobileprovision file for CI
#   BUILD_NAME                      Version string override (e.g. 1.0.0)
#   BUILD_NUMBER                    Integer CFBundleVersion override (auto-falls back to
#                                   GITHUB_RUN_NUMBER, BITRISE_BUILD_NUMBER, CM_BUILD_ID,
#                                   CI_PIPELINE_IID)
#   DISTRIBUTE                      Set to "true" to upload to Firebase App Distribution
#   FIREBASE_IOS_APP_ID             Firebase iOS App ID (e.g. 1:1234567890:ios:abcdef)
#   FIREBASE_TESTERS                Comma-separated tester emails
#   FIREBASE_GROUPS                 Comma-separated tester group aliases
#   RELEASE_NOTES                   Release notes string
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_ROOT}"

IOS_EXPORT_METHOD="${IOS_EXPORT_METHOD:-ad-hoc}"
EXPORT_OPTIONS_PLIST="${EXPORT_OPTIONS_PLIST:-}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-KNK9SM7SLS}"
IOS_BUNDLE_ID="${IOS_BUNDLE_ID:-com.craiglabenz.babble}"
IOS_PROVISIONING_PROFILE="${IOS_PROVISIONING_PROFILE:-}"
NO_CODESIGN="${NO_CODESIGN:-false}"
SKIP_PUB_GET=false
DISTRIBUTE="${DISTRIBUTE:-false}"
BUILD_NAME="${BUILD_NAME:-}"
BUILD_NUMBER="${BUILD_NUMBER:-${GITHUB_RUN_NUMBER:-${BITRISE_BUILD_NUMBER:-${CM_BUILD_ID:-${CI_PIPELINE_IID:-}}}}}"
FIREBASE_TESTERS="${FIREBASE_TESTERS:-}"
FIREBASE_GROUPS="${FIREBASE_GROUPS:-}"
RELEASE_NOTES="${RELEASE_NOTES:-}"
DART_DEFINES=()

TEMP_KEYCHAIN_NAME=""
TEMP_EXPORT_PLIST=""
TEMP_P12_FILE=""
TEMP_PROFILE_FILE=""

cleanup() {
  if [[ -n "${TEMP_EXPORT_PLIST}" && -f "${TEMP_EXPORT_PLIST}" ]]; then
    rm -f "${TEMP_EXPORT_PLIST}"
  fi
  if [[ -n "${TEMP_P12_FILE}" && -f "${TEMP_P12_FILE}" ]]; then
    rm -f "${TEMP_P12_FILE}"
  fi
  if [[ -n "${TEMP_PROFILE_FILE}" && -f "${TEMP_PROFILE_FILE}" ]]; then
    rm -f "${TEMP_PROFILE_FILE}"
  fi
  if [[ -n "${TEMP_KEYCHAIN_NAME}" ]]; then
    security delete-keychain "${TEMP_KEYCHAIN_NAME}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

usage() {
  sed -n '2,43p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

decode_base64() {
  local input="$1"
  local output_file="$2"
  if base64 --help 2>&1 | grep -q -- "--decode"; then
    echo "${input}" | base64 --decode > "${output_file}"
  else
    echo "${input}" | base64 -D > "${output_file}"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --export-method)
      IOS_EXPORT_METHOD="$2"
      shift 2
      ;;
    --export-options-plist)
      EXPORT_OPTIONS_PLIST="$2"
      shift 2
      ;;
    --team-id)
      APPLE_TEAM_ID="$2"
      shift 2
      ;;
    --bundle-id)
      IOS_BUNDLE_ID="$2"
      shift 2
      ;;
    --provisioning-profile)
      IOS_PROVISIONING_PROFILE="$2"
      shift 2
      ;;
    --no-codesign)
      NO_CODESIGN=true
      shift
      ;;
    --build-name)
      BUILD_NAME="$2"
      shift 2
      ;;
    --build-number)
      BUILD_NUMBER="$2"
      shift 2
      ;;
    --dart-define)
      DART_DEFINES+=("--dart-define=$2")
      shift 2
      ;;
    --distribute)
      DISTRIBUTE=true
      shift
      ;;
    --testers)
      FIREBASE_TESTERS="$2"
      shift 2
      ;;
    --groups)
      FIREBASE_GROUPS="$2"
      shift 2
      ;;
    --release-notes)
      RELEASE_NOTES="$2"
      shift 2
      ;;
    --skip-pub-get)
      SKIP_PUB_GET=true
      shift
      ;;
    -h|--help)
      usage
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
echo "🍎 Building iOS Release Artifact"
echo "=============================================================================="

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "❌ Error: iOS builds require macOS with Xcode installed." >&2
  exit 1
fi

if ! command -v flutter >/dev/null 2>&1; then
  echo "❌ Error: 'flutter' command not found on PATH." >&2
  exit 1
fi

# Optional CI code-signing setup from base64 environment variables
if [[ -n "${IOS_P12_BASE64:-}" ]]; then
  echo "🔐 Setting up temporary CI keychain and importing .p12 certificate..."
  TEMP_KEYCHAIN_NAME="ci-signing-$(date +%s).keychain-db"
  KEYCHAIN_PASSWORD="${IOS_KEYCHAIN_PASSWORD:-ci-temp-keychain-password}"
  TEMP_P12_FILE="$(mktemp "${TMPDIR:-/tmp}/cert.XXXXXX.p12")"

  decode_base64 "${IOS_P12_BASE64}" "${TEMP_P12_FILE}"

  security create-keychain -p "${KEYCHAIN_PASSWORD}" "${TEMP_KEYCHAIN_NAME}"
  security set-keychain-settings -lut 21600 "${TEMP_KEYCHAIN_NAME}"
  security unlock-keychain -p "${KEYCHAIN_PASSWORD}" "${TEMP_KEYCHAIN_NAME}"
  security import "${TEMP_P12_FILE}" \
    -P "${IOS_P12_PASSWORD:-}" \
    -A \
    -t cert \
    -f pkcs12 \
    -k "${TEMP_KEYCHAIN_NAME}"
  security set-key-partition-list \
    -S apple-tool:,apple:,codesign: \
    -s \
    -k "${KEYCHAIN_PASSWORD}" \
    "${TEMP_KEYCHAIN_NAME}"

  EXISTING_KEYCHAINS=()
  while IFS= read -r line; do
    cleaned="$(echo "${line}" | xargs | tr -d '"')"
    [[ -n "${cleaned}" ]] && EXISTING_KEYCHAINS+=("${cleaned}")
  done < <(security list-keychains -d user)
  security list-keychains -d user -s "${TEMP_KEYCHAIN_NAME}" "${EXISTING_KEYCHAINS[@]}"
fi

if [[ -n "${IOS_PROVISIONING_PROFILE_BASE64:-}" ]]; then
  echo "📄 Installing iOS provisioning profile from IOS_PROVISIONING_PROFILE_BASE64..."
  PROFILES_DIR="${HOME}/Library/MobileDevice/Provisioning Profiles"
  mkdir -p "${PROFILES_DIR}"
  TEMP_PROFILE_FILE="$(mktemp "${TMPDIR:-/tmp}/profile.XXXXXX.mobileprovision")"
  decode_base64 "${IOS_PROVISIONING_PROFILE_BASE64}" "${TEMP_PROFILE_FILE}"

  PROFILE_UUID="$(/usr/libexec/PlistBuddy -c "Print UUID" /dev/stdin <<< "$(security cms -D -i "${TEMP_PROFILE_FILE}")")"
  PROFILE_NAME="$(/usr/libexec/PlistBuddy -c "Print Name" /dev/stdin <<< "$(security cms -D -i "${TEMP_PROFILE_FILE}")")"
  cp "${TEMP_PROFILE_FILE}" "${PROFILES_DIR}/${PROFILE_UUID}.mobileprovision"
  echo "   Installed provisioning profile '${PROFILE_NAME}' (${PROFILE_UUID})"
  if [[ -z "${IOS_PROVISIONING_PROFILE}" ]]; then
    IOS_PROVISIONING_PROFILE="${PROFILE_NAME}"
  fi
fi

if [[ "${SKIP_PUB_GET}" != "true" ]]; then
  echo "📦 Running flutter pub get..."
  flutter pub get
fi

FLUTTER_COMMON_ARGS=("--release")

if [[ -n "${BUILD_NAME}" ]]; then
  FLUTTER_COMMON_ARGS+=("--build-name=${BUILD_NAME}")
fi

if [[ -n "${BUILD_NUMBER}" ]]; then
  FLUTTER_COMMON_ARGS+=("--build-number=${BUILD_NUMBER}")
fi

if [[ ${#DART_DEFINES[@]} -gt 0 ]]; then
  FLUTTER_COMMON_ARGS+=("${DART_DEFINES[@]}")
fi

if [[ "${NO_CODESIGN}" == "true" ]]; then
  echo "🔨 Running unsigned iOS release build: flutter build ios --no-codesign ${FLUTTER_COMMON_ARGS[*]}"
  flutter build ios --no-codesign "${FLUTTER_COMMON_ARGS[@]}"
  echo "✅ Unsigned iOS app bundle built at: ${PROJECT_ROOT}/build/ios/iphoneos/Runner.app"
  exit 0
fi

# Build ExportOptions.plist when a custom one isn't supplied and a provisioning profile is specified
if [[ -z "${EXPORT_OPTIONS_PLIST}" && -n "${IOS_PROVISIONING_PROFILE}" ]]; then
  TEMP_EXPORT_PLIST="$(mktemp "${TMPDIR:-/tmp}/ExportOptions.XXXXXX.plist")"
  cat > "${TEMP_EXPORT_PLIST}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>${IOS_EXPORT_METHOD}</string>
  <key>teamID</key>
  <string>${APPLE_TEAM_ID}</string>
  <key>signingStyle</key>
  <string>manual</string>
  <key>provisioningProfiles</key>
  <dict>
    <key>${IOS_BUNDLE_ID}</key>
    <string>${IOS_PROVISIONING_PROFILE}</string>
  </dict>
</dict>
</plist>
EOF
  EXPORT_OPTIONS_PLIST="${TEMP_EXPORT_PLIST}"
fi

IPA_ARGS=("${FLUTTER_COMMON_ARGS[@]}")
if [[ -n "${EXPORT_OPTIONS_PLIST}" ]]; then
  IPA_ARGS+=("--export-options-plist=${EXPORT_OPTIONS_PLIST}")
else
  if [[ "${IOS_EXPORT_METHOD}" == "release-testing" ]]; then
    IOS_EXPORT_METHOD="ad-hoc"
  fi
  IPA_ARGS+=("--export-method=${IOS_EXPORT_METHOD}")
fi

echo "🔨 Running: flutter build ipa ${IPA_ARGS[*]}"
flutter build ipa "${IPA_ARGS[@]}"

IPA_OUTPUT_DIR="${PROJECT_ROOT}/build/ios/ipa"
IPA_FILE="$(find "${IPA_OUTPUT_DIR}" -maxdepth 1 -name "*.ipa" | head -n 1 || true)"

if [[ -z "${IPA_FILE}" || ! -f "${IPA_FILE}" ]]; then
  echo "❌ Error: No .ipa file found in ${IPA_OUTPUT_DIR}. Check Xcode archive & signing logs above." >&2
  exit 1
fi

IPA_SIZE="$(du -h "${IPA_FILE}" | cut -f1 | xargs)"
echo "✅ iOS Release IPA ready: ${IPA_FILE} (${IPA_SIZE})"

if [[ "${DISTRIBUTE}" == "true" ]]; then
  echo "🚀 Distributing ${IPA_FILE} via Firebase App Distribution..."
  FIREBASE_TESTERS="${FIREBASE_TESTERS}" \
  FIREBASE_GROUPS="${FIREBASE_GROUPS}" \
  RELEASE_NOTES="${RELEASE_NOTES}" \
    "${SCRIPT_DIR}/distribute_firebase.sh" \
      --platform ios \
      --artifact "${IPA_FILE}"
fi
