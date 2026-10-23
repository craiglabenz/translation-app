#!/usr/bin/env bash
# ==============================================================================
# Build Flutter Web Release Bundle for Firebase Hosting & CI
# ==============================================================================
# Usage:
#   ./scripts/build_web.sh [options]
#
# Options:
#   --base-href <path>          Override base href (must start and end with '/', default: '/')
#   --wasm                      Compile to WebAssembly (--wasm)
#   --build-name <version>      Override version name (e.g. 1.0.0)
#   --build-number <number>     Override build number (defaults to CI run number if present)
#   --dart-define <KEY=VALUE>   Pass additional --dart-define to flutter build (repeatable)
#   --distribute                Deploy the built web bundle to Firebase Hosting after build
#   --project <project_id>      Firebase Project ID for Hosting deploy (or set FIREBASE_PROJECT_ID)
#   --channel <channel_id>      Deploy to a Firebase Hosting preview channel instead of live
#   --skip-pub-get              Skip running `flutter pub get` before building
#   -h, --help                  Show this help message
#
# Environment Variables (CI-friendly):
#   BUILD_NAME                  Version string override (e.g. 1.0.0)
#   BUILD_NUMBER                Integer build number override (auto-falls back to
#                               GITHUB_RUN_NUMBER, BITRISE_BUILD_NUMBER, CM_BUILD_ID,
#                               CI_PIPELINE_IID)
#   WEB_BASE_HREF               Base href path override (e.g. "/")
#   GEMINI_API_KEY              If set, automatically passed via --dart-define=GEMINI_API_KEY=...
#   DISTRIBUTE                  Set to "true" to deploy to Firebase Hosting after building
#   FIREBASE_PROJECT_ID         Firebase Project ID (defaults to .firebaserc default project)
#   FIREBASE_HOSTING_CHANNEL    Optional Firebase Hosting preview channel ID (defaults to live)
#   FIREBASE_TOKEN              CI token from `firebase login:ci`
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_ROOT}"

BASE_HREF="${WEB_BASE_HREF:-}"
BUILD_WASM="${BUILD_WASM:-false}"
SKIP_PUB_GET=false
DISTRIBUTE="${DISTRIBUTE:-false}"
BUILD_NAME="${BUILD_NAME:-}"
BUILD_NUMBER="${BUILD_NUMBER:-${GITHUB_RUN_NUMBER:-${BITRISE_BUILD_NUMBER:-${CM_BUILD_ID:-${CI_PIPELINE_IID:-}}}}}"
FIREBASE_PROJECT_ID="${FIREBASE_PROJECT_ID:-}"
FIREBASE_HOSTING_CHANNEL="${FIREBASE_HOSTING_CHANNEL:-}"
DART_DEFINES=()

usage() {
  sed -n '2,32p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-href)
      BASE_HREF="$2"
      shift 2
      ;;
    --wasm)
      BUILD_WASM=true
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
    --project)
      FIREBASE_PROJECT_ID="$2"
      shift 2
      ;;
    --channel)
      FIREBASE_HOSTING_CHANNEL="$2"
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
echo "🌐 Building Flutter Web Release Artifact"
echo "=============================================================================="

if ! command -v flutter >/dev/null 2>&1; then
  echo "❌ Error: 'flutter' command not found on PATH." >&2
  exit 1
fi

if [[ "${SKIP_PUB_GET}" != "true" ]]; then
  echo "📦 Running flutter pub get..."
  flutter pub get
fi

FLUTTER_BUILD_ARGS=("--release")

if [[ "${BUILD_WASM}" == "true" ]]; then
  FLUTTER_BUILD_ARGS+=("--wasm")
fi

if [[ -n "${BASE_HREF}" ]]; then
  FLUTTER_BUILD_ARGS+=("--base-href=${BASE_HREF}")
fi

if [[ -n "${BUILD_NAME}" ]]; then
  FLUTTER_BUILD_ARGS+=("--build-name=${BUILD_NAME}")
fi

if [[ -n "${BUILD_NUMBER}" ]]; then
  FLUTTER_BUILD_ARGS+=("--build-number=${BUILD_NUMBER}")
fi

if [[ -n "${GEMINI_API_KEY:-}" ]]; then
  DART_DEFINES+=("--dart-define=GEMINI_API_KEY=${GEMINI_API_KEY}")
fi

if [[ ${#DART_DEFINES[@]} -gt 0 ]]; then
  FLUTTER_BUILD_ARGS+=("${DART_DEFINES[@]}")
fi

WEB_OUTPUT_DIR="${PROJECT_ROOT}/build/web"

echo "🔨 Running: flutter build web ${FLUTTER_BUILD_ARGS[*]}"
flutter build web "${FLUTTER_BUILD_ARGS[@]}"

if [[ ! -f "${WEB_OUTPUT_DIR}/index.html" ]]; then
  echo "❌ Expected web build output not found at ${WEB_OUTPUT_DIR}/index.html" >&2
  exit 1
fi

WEB_SIZE="$(du -sh "${WEB_OUTPUT_DIR}" | cut -f1 | xargs)"
echo "✅ Flutter Web Release bundle ready: ${WEB_OUTPUT_DIR} (${WEB_SIZE})"

if [[ "${DISTRIBUTE}" == "true" ]]; then
  echo "🚀 Deploying ${WEB_OUTPUT_DIR} to Firebase Hosting..."
  FIREBASE_PROJECT_ID="${FIREBASE_PROJECT_ID}" \
  FIREBASE_HOSTING_CHANNEL="${FIREBASE_HOSTING_CHANNEL}" \
    "${SCRIPT_DIR}/distribute_firebase.sh" \
      --platform web \
      --artifact "${WEB_OUTPUT_DIR}"
fi
