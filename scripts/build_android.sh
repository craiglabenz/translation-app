#!/usr/bin/env bash
# ==============================================================================
# Build Android Release (APK / AAB) for Firebase App Distribution & CI
# ==============================================================================
# Usage:
#   ./scripts/build_android.sh [options]
#
# Options:
#   --apk                       Build release APK (default; best for Firebase App Distribution)
#   --aab                       Also build release App Bundle (.aab)
#   --build-name <version>      Override version name (e.g. 1.0.0)
#   --build-number <number>     Override build number (defaults to CI run number if present)
#   --dart-define <KEY=VALUE>   Pass additional --dart-define to flutter build (repeatable)
#   --distribute                Upload the built APK to Firebase App Distribution after build
#   --testers <emails>          Comma-separated tester emails for Firebase App Distribution
#   --groups <groups>           Comma-separated tester group aliases for Firebase App Distribution
#   --release-notes <notes>     Release notes text for Firebase App Distribution
#   --skip-pub-get              Skip running `flutter pub get` before building
#   -h, --help                  Show this help message
#
# Environment Variables (CI-friendly):
#   BUILD_NAME                  Version string override (e.g. 1.0.0)
#   BUILD_NUMBER                Integer versionCode override (auto-falls back to
#                               GITHUB_RUN_NUMBER, BITRISE_BUILD_NUMBER, CM_BUILD_ID,
#                               CI_PIPELINE_IID)
#   ANDROID_KEYSTORE_BASE64     Base64-encoded release keystore (.jks / .keystore).
#                               If set, decoded to android/app/upload-keystore.jks
#                               for the duration of the build.
#   ANDROID_KEYSTORE_PATH       Path to release keystore (relative to android/)
#   ANDROID_KEYSTORE_PASSWORD   Keystore password
#   ANDROID_KEY_ALIAS           Key alias
#   ANDROID_KEY_PASSWORD        Key password
#   DISTRIBUTE                  Set to "true" to upload to Firebase App Distribution
#   FIREBASE_ANDROID_APP_ID     Firebase Android App ID (e.g. 1:1234567890:android:abcdef)
#   FIREBASE_TESTERS            Comma-separated tester emails
#   FIREBASE_GROUPS             Comma-separated tester group aliases
#   RELEASE_NOTES               Release notes string
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_ROOT}"

BUILD_APK=true
BUILD_AAB="${BUILD_AAB:-false}"
SKIP_PUB_GET=false
DISTRIBUTE="${DISTRIBUTE:-false}"
BUILD_NAME="${BUILD_NAME:-}"
BUILD_NUMBER="${BUILD_NUMBER:-${GITHUB_RUN_NUMBER:-${BITRISE_BUILD_NUMBER:-${CM_BUILD_ID:-${CI_PIPELINE_IID:-}}}}}"
FIREBASE_TESTERS="${FIREBASE_TESTERS:-}"
FIREBASE_GROUPS="${FIREBASE_GROUPS:-}"
RELEASE_NOTES="${RELEASE_NOTES:-}"
DART_DEFINES=()

TEMP_KEYSTORE_FILE=""

cleanup() {
  if [[ -n "${TEMP_KEYSTORE_FILE}" && -f "${TEMP_KEYSTORE_FILE}" ]]; then
    rm -f "${TEMP_KEYSTORE_FILE}"
  fi
}
trap cleanup EXIT

usage() {
  sed -n '2,38p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apk)
      BUILD_APK=true
      shift
      ;;
    --aab)
      BUILD_AAB=true
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
echo "🤖 Building Android Release Artifact"
echo "=============================================================================="

if ! command -v flutter >/dev/null 2>&1; then
  echo "❌ Error: 'flutter' command not found on PATH." >&2
  exit 1
fi

# Decode ephemeral keystore from ANDROID_KEYSTORE_BASE64 if running in CI
if [[ -n "${ANDROID_KEYSTORE_BASE64:-}" ]]; then
  TEMP_KEYSTORE_FILE="${PROJECT_ROOT}/android/app/ci-release-keystore.jks"
  echo "🔐 Decoding ANDROID_KEYSTORE_BASE64 to ${TEMP_KEYSTORE_FILE}..."
  if base64 --help 2>&1 | grep -q -- "--decode"; then
    echo "${ANDROID_KEYSTORE_BASE64}" | base64 --decode > "${TEMP_KEYSTORE_FILE}"
  else
    echo "${ANDROID_KEYSTORE_BASE64}" | base64 -D > "${TEMP_KEYSTORE_FILE}"
  fi
  export ANDROID_KEYSTORE_PATH="app/ci-release-keystore.jks"
fi

if [[ "${SKIP_PUB_GET}" != "true" ]]; then
  echo "📦 Running flutter pub get..."
  flutter pub get
fi

FLUTTER_BUILD_ARGS=("--release")

if [[ -n "${BUILD_NAME}" ]]; then
  FLUTTER_BUILD_ARGS+=("--build-name=${BUILD_NAME}")
fi

if [[ -n "${BUILD_NUMBER}" ]]; then
  FLUTTER_BUILD_ARGS+=("--build-number=${BUILD_NUMBER}")
fi

if [[ ${#DART_DEFINES[@]} -gt 0 ]]; then
  FLUTTER_BUILD_ARGS+=("${DART_DEFINES[@]}")
fi

APK_OUTPUT_PATH="${PROJECT_ROOT}/build/app/outputs/flutter-apk/app-release.apk"
AAB_OUTPUT_PATH="${PROJECT_ROOT}/build/app/outputs/bundle/release/app-release.aab"

if [[ "${BUILD_APK}" == "true" ]]; then
  echo "🔨 Running: flutter build apk ${FLUTTER_BUILD_ARGS[*]}"
  flutter build apk "${FLUTTER_BUILD_ARGS[@]}"

  if [[ ! -f "${APK_OUTPUT_PATH}" ]]; then
    echo "❌ Expected APK not found at ${APK_OUTPUT_PATH}" >&2
    exit 1
  fi
  APK_SIZE="$(du -h "${APK_OUTPUT_PATH}" | cut -f1 | xargs)"
  echo "✅ Android Release APK ready: ${APK_OUTPUT_PATH} (${APK_SIZE})"
fi

if [[ "${BUILD_AAB}" == "true" ]]; then
  echo "🔨 Running: flutter build appbundle ${FLUTTER_BUILD_ARGS[*]}"
  flutter build appbundle "${FLUTTER_BUILD_ARGS[@]}"

  if [[ ! -f "${AAB_OUTPUT_PATH}" ]]; then
    echo "❌ Expected AAB not found at ${AAB_OUTPUT_PATH}" >&2
    exit 1
  fi
  AAB_SIZE="$(du -h "${AAB_OUTPUT_PATH}" | cut -f1 | xargs)"
  echo "✅ Android Release AAB ready: ${AAB_OUTPUT_PATH} (${AAB_SIZE})"
fi

if [[ "${DISTRIBUTE}" == "true" ]]; then
  ARTIFACT_TO_UPLOAD="${APK_OUTPUT_PATH}"
  if [[ "${BUILD_APK}" != "true" && "${BUILD_AAB}" == "true" ]]; then
    ARTIFACT_TO_UPLOAD="${AAB_OUTPUT_PATH}"
  fi
  echo "🚀 Distributing ${ARTIFACT_TO_UPLOAD} via Firebase App Distribution..."
  FIREBASE_TESTERS="${FIREBASE_TESTERS}" \
  FIREBASE_GROUPS="${FIREBASE_GROUPS}" \
  RELEASE_NOTES="${RELEASE_NOTES}" \
    "${SCRIPT_DIR}/distribute_firebase.sh" \
      --platform android \
      --artifact "${ARTIFACT_TO_UPLOAD}"
fi
