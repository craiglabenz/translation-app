#!/usr/bin/env bash
# ==============================================================================
# Run `dart analyze` and all Flutter unit & widget tests
# ==============================================================================
# Usage:
#   ./scripts/test_and_analyze.sh [options]
#
# Options:
#   --analyze-only    Only run `dart analyze`
#   --test-only       Only run `flutter test`
#   --coverage        Collect test coverage (`flutter test --coverage`)
#   --skip-pub-get    Skip running `flutter pub get`
#   -h, --help        Show this help message
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_ROOT}"

RUN_ANALYZE=true
RUN_TESTS=true
COLLECT_COVERAGE=false
SKIP_PUB_GET=false

usage() {
  sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --analyze-only)
      RUN_ANALYZE=true
      RUN_TESTS=false
      shift
      ;;
    --test-only)
      RUN_ANALYZE=false
      RUN_TESTS=true
      shift
      ;;
    --coverage)
      COLLECT_COVERAGE=true
      shift
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

if ! command -v flutter >/dev/null 2>&1; then
  echo "❌ Error: 'flutter' command not found on PATH." >&2
  exit 1
fi

if ! command -v dart >/dev/null 2>&1; then
  echo "❌ Error: 'dart' command not found on PATH." >&2
  exit 1
fi

if [[ "${SKIP_PUB_GET}" != "true" ]]; then
  echo "=============================================================================="
  echo "📦 Resolving dependencies (flutter pub get)"
  echo "=============================================================================="
  flutter pub get
fi

if [[ "${RUN_ANALYZE}" == "true" ]]; then
  echo "=============================================================================="
  echo "🔍 Running static analysis (dart analyze --fatal-infos)"
  echo "=============================================================================="
  dart analyze --fatal-infos
fi

if [[ "${RUN_TESTS}" == "true" ]]; then
  echo "=============================================================================="
  echo "🧪 Running all tests (flutter test)"
  echo "=============================================================================="
  TEST_ARGS=()
  if [[ "${COLLECT_COVERAGE}" == "true" ]]; then
    TEST_ARGS+=("--coverage")
  fi
  if [[ ${#TEST_ARGS[@]} -gt 0 ]]; then
    flutter test "${TEST_ARGS[@]}"
  else
    flutter test
  fi
fi

echo "✅ All checks passed!"
