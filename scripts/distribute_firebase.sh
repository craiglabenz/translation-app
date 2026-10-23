#!/usr/bin/env bash
# ==============================================================================
# Upload Release Builds (Android APK/AAB or iOS IPA) to Firebase App Distribution
# ==============================================================================
# Usage:
#   ./scripts/distribute_firebase.sh --platform <android|ios> [options]
#
# Options:
#   --platform <android|ios>    Target platform ("android" or "ios") [required]
#   --artifact <path>           Path to .apk, .aab, or .ipa (defaults to standard Flutter build output)
#   --app-id <firebase_app_id>  Firebase App ID (or set FIREBASE_ANDROID_APP_ID / FIREBASE_IOS_APP_ID)
#   --testers <emails>          Comma-separated tester emails (or set FIREBASE_TESTERS)
#   --groups <groups>           Comma-separated tester group aliases (or set FIREBASE_GROUPS)
#   --release-notes <notes>     Release notes text (defaults to recent git commits if omitted)
#   --release-notes-file <path> Path to release notes file
#   --dry-run                   Print the Firebase CLI command without executing it
#   -h, --help                  Show this help message
#
# Authentication in CI:
#   - Preferred: Set GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
#   - Alternative: Set FIREBASE_TOKEN="<ci_token>" (from `firebase login:ci`)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_ROOT}"

PLATFORM=""
ARTIFACT_PATH=""
APP_ID="${FIREBASE_APP_ID:-}"
TESTERS="${FIREBASE_TESTERS:-}"
GROUPS="${FIREBASE_GROUPS:-}"
RELEASE_NOTES="${RELEASE_NOTES:-}"
RELEASE_NOTES_FILE="${RELEASE_NOTES_FILE:-}"
DRY_RUN=false

usage() {
  sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --platform)
      PLATFORM="$2"
      shift 2
      ;;
    --artifact)
      ARTIFACT_PATH="$2"
      shift 2
      ;;
    --app-id)
      APP_ID="$2"
      shift 2
      ;;
    --testers)
      TESTERS="$2"
      shift 2
      ;;
    --groups)
      GROUPS="$2"
      shift 2
      ;;
    --release-notes)
      RELEASE_NOTES="$2"
      shift 2
      ;;
    --release-notes-file)
      RELEASE_NOTES_FILE="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
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

if [[ -z "${PLATFORM}" ]]; then
  echo "❌ Error: --platform <android|ios> is required." >&2
  usage
  exit 1
fi

case "${PLATFORM}" in
  android)
    APP_ID="${APP_ID:-${FIREBASE_ANDROID_APP_ID:-}}"
    if [[ -z "${ARTIFACT_PATH}" ]]; then
      ARTIFACT_PATH="${PROJECT_ROOT}/build/app/outputs/flutter-apk/app-release.apk"
    fi
    ;;
  ios)
    APP_ID="${APP_ID:-${FIREBASE_IOS_APP_ID:-}}"
    if [[ -z "${ARTIFACT_PATH}" ]]; then
      ARTIFACT_PATH="$(find "${PROJECT_ROOT}/build/ios/ipa" -maxdepth 1 -name "*.ipa" 2>/dev/null | head -n 1 || true)"
    fi
    ;;
  *)
    echo "❌ Error: Unsupported --platform '${PLATFORM}'. Expected 'android' or 'ios'." >&2
    exit 1
    ;;
esac

if [[ -z "${APP_ID}" ]]; then
  if [[ "${PLATFORM}" == "android" ]]; then
    echo "❌ Error: Firebase App ID not set. Pass --app-id or set FIREBASE_ANDROID_APP_ID." >&2
  else
    echo "❌ Error: Firebase App ID not set. Pass --app-id or set FIREBASE_IOS_APP_ID." >&2
  fi
  exit 1
fi

if [[ -z "${ARTIFACT_PATH}" || ! -f "${ARTIFACT_PATH}" ]]; then
  echo "❌ Error: Build artifact not found at '${ARTIFACT_PATH}'." >&2
  echo "   Run ./scripts/build_${PLATFORM}.sh first or pass --artifact <path>." >&2
  exit 1
fi

# Auto-generate release notes from recent git commits if none were supplied
if [[ -z "${RELEASE_NOTES}" && -z "${RELEASE_NOTES_FILE}" ]]; then
  if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    GIT_SHA="$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
    GIT_BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'unknown')"
    RECENT_COMMITS="$(git log -n 5 --pretty=format:'• %s (%h)' 2>/dev/null || true)"
    RELEASE_NOTES="Build from ${GIT_BRANCH} (${GIT_SHA})"$'\n'"${RECENT_COMMITS}"
  else
    RELEASE_NOTES="Automated CI release build"
  fi
fi

FIREBASE_CMD=(
  firebase
  appdistribution:distribute
  "${ARTIFACT_PATH}"
  "--app"
  "${APP_ID}"
)

if [[ -n "${RELEASE_NOTES_FILE}" ]]; then
  FIREBASE_CMD+=("--release-notes-file" "${RELEASE_NOTES_FILE}")
elif [[ -n "${RELEASE_NOTES}" ]]; then
  FIREBASE_CMD+=("--release-notes" "${RELEASE_NOTES}")
fi

# Auto-separate any email addresses (containing '@') accidentally set in
# FIREBASE_GROUPS into TESTERS so '--groups' only receives group aliases and
# '--testers' receives email addresses.
if [[ -n "${GROUPS}" ]]; then
  CLEAN_GROUPS=()
  EXTRACTED_EMAILS=()
  IFS=',' read -ra RAW_GROUP_ITEMS <<< "${GROUPS}"
  for item in "${RAW_GROUP_ITEMS[@]}"; do
    trimmed="$(echo "${item}" | xargs)"
    [[ -z "${trimmed}" ]] && continue
    if [[ "${trimmed}" == *"@"* ]]; then
      EXTRACTED_EMAILS+=("${trimmed}")
    else
      CLEAN_GROUPS+=("${trimmed}")
    fi
  done
  GROUPS="$(IFS=','; echo "${CLEAN_GROUPS[*]:-}")"
  if [[ ${#EXTRACTED_EMAILS[@]} -gt 0 ]]; then
    EMAIL_CSV="$(IFS=','; echo "${EXTRACTED_EMAILS[*]}")"
    echo "ℹ️ Detected email address(es) in FIREBASE_GROUPS; routing to --testers."
    if [[ -n "${TESTERS}" ]]; then
      TESTERS="${TESTERS},${EMAIL_CSV}"
    else
      TESTERS="${EMAIL_CSV}"
    fi
  fi
fi

if [[ -n "${TESTERS}" ]]; then
  FIREBASE_CMD+=("--testers" "${TESTERS}")
fi

if [[ -n "${GROUPS}" ]]; then
  FIREBASE_CMD+=("--groups" "${GROUPS}")
fi

if [[ -n "${FIREBASE_TOKEN:-}" ]]; then
  FIREBASE_CMD+=("--token" "${FIREBASE_TOKEN}")
fi

echo "=============================================================================="
echo "🔥 Uploading ${PLATFORM} build to Firebase App Distribution"
echo "   Artifact : ${ARTIFACT_PATH}"
echo "   App ID   : ${APP_ID}"
[[ -n "${GROUPS}" ]] && echo "   Groups   : ${GROUPS}"
[[ -n "${TESTERS}" ]] && echo "   Testers  : ${TESTERS}"
echo "=============================================================================="

if [[ "${DRY_RUN}" == "true" ]]; then
  echo "🧪 [DRY RUN] Would execute:"
  printf '  %q' "${FIREBASE_CMD[@]}"
  echo ""
  exit 0
fi

if ! command -v firebase >/dev/null 2>&1; then
  echo "❌ Error: 'firebase' CLI not found on PATH." >&2
  echo "   Install it in CI via: npm install -g firebase-tools" >&2
  echo "   or: curl -sL https://firebase.tools | bash" >&2
  exit 1
fi

"${FIREBASE_CMD[@]}"
echo "✅ Successfully distributed ${ARTIFACT_PATH} to Firebase App Distribution!"
