# Build & Firebase App Distribution Scripts

This folder contains CI-friendly scripts for building release artifacts of `translation_app` for **Android** and **iOS**, and distributing them to testers via **Firebase App Distribution**.

## Scripts Overview

| Script | Description |
| :--- | :--- |
| `./scripts/test_and_analyze.sh` | Runs `flutter pub get`, `dart analyze --fatal-infos`, and `flutter test` (used by GitHub Actions CI and local verification). |
| `./scripts/build_android.sh` | Builds a release `.apk` (and optionally `.aab`) for Android, with optional keystore signing and direct upload to Firebase App Distribution. |
| `./scripts/build_ios.sh` | Builds a signed release `.ipa` (`ad-hoc` by default for Firebase App Distribution) or unsigned `.app` (`--no-codesign`), with optional temporary CI keychain/provisioning profile installation. |
| `./scripts/distribute_firebase.sh` | Uploads a built Android (`.apk` / `.aab`) or iOS (`.ipa`) artifact to Firebase App Distribution via the `firebase` CLI, auto-populating release notes from recent git commits when not specified. |

## GitHub Actions Workflows

| Workflow File | Trigger | Description |
| :--- | :--- | :--- |
| `.github/workflows/ci.yml` | `push` (`main` / `master`), `pull_request`, `workflow_dispatch` | Runs `./scripts/test_and_analyze.sh` (`dart analyze --fatal-infos` + `flutter test`). |
| `.github/workflows/distribute.yml` | `push` to `main`, `workflow_dispatch` (on `main`) | Runs `test_and_analyze.sh`, builds release Android APK and iOS IPA via `build_android.sh` / `build_ios.sh`, uploads artifacts to GitHub Actions, and distributes to Firebase App Distribution. |

---

## Quick Start (Local & CI)

### 1. Build & Distribute Android Release APK

```bash
# Build release APK only:
./scripts/build_android.sh

# Build release APK and immediately upload to Firebase App Distribution:
FIREBASE_ANDROID_APP_ID="1:1234567890:android:abcdef123456" \
FIREBASE_GROUPS="qa-team" \
./scripts/build_android.sh --distribute
```

### 2. Build & Distribute iOS Release IPA (Ad-Hoc for Tester Devices)

For Firebase App Distribution on physical iOS devices, register your testers' device UDIDs in the Apple Developer Portal and use an **Ad-Hoc** (`ad-hoc`) distribution profile:

```bash
# Build Ad-Hoc release IPA using automatic signing on a configured Mac/runner:
./scripts/build_ios.sh --export-method ad-hoc

# Build Ad-Hoc release IPA and immediately upload to Firebase App Distribution:
FIREBASE_IOS_APP_ID="1:1234567890:ios:abcdef123456" \
FIREBASE_GROUPS="qa-team" \
./scripts/build_ios.sh --export-method ad-hoc --distribute
```

---

## CI Environment Variables Reference

### Shared Version & Firebase Variables

| Variable | Description |
| :--- | :--- |
| `BUILD_NAME` | Semantic version override passed to `--build-name` (e.g., `1.0.0`). |
| `BUILD_NUMBER` | Integer build number passed to `--build-number`. Automatically falls back to `GITHUB_RUN_NUMBER`, `BITRISE_BUILD_NUMBER`, `CM_BUILD_ID`, or `CI_PIPELINE_IID`. |
| `GOOGLE_APPLICATION_CREDENTIALS` | Path to a Google Cloud / Firebase service account JSON key with the **Firebase App Distribution Admin** role (recommended for CI). |
| `FIREBASE_TOKEN` | Alternative CI token generated via `firebase login:ci`. |
| `FIREBASE_ANDROID_APP_ID` | Firebase App ID for Android (`1:...:android:...`). |
| `FIREBASE_IOS_APP_ID` | Firebase App ID for iOS (`1:...:ios:...`). |
| `FIREBASE_GROUPS` | Comma-separated tester group aliases in Firebase App Distribution (e.g., `internal-testers,friends`). |
| `FIREBASE_TESTERS` | Comma-separated tester email addresses. |
| `RELEASE_NOTES` | Custom release notes string (defaults to the last 5 git commits if omitted). |

### Android Code Signing Variables (Optional for APK, Required for Play Store)

If omitted, `android/app/build.gradle.kts` falls back to signing with the debug key so initial Firebase App Distribution APK uploads work immediately. For consistent upgrades across CI runs, configure a release keystore:

| Variable | Description |
| :--- | :--- |
| `ANDROID_KEYSTORE_BASE64` | Base64-encoded `.jks` / `.keystore` file (`base64 -i upload-keystore.jks`). Decoded ephemerally during the CI build and deleted on exit. |
| `ANDROID_KEYSTORE_PATH` | Path to an existing keystore file relative to `android/` (if not using `ANDROID_KEYSTORE_BASE64`). |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore password. |
| `ANDROID_KEY_ALIAS` | Key alias inside the keystore. |
| `ANDROID_KEY_PASSWORD` | Password for the key alias. |

### iOS Code Signing Variables (For Ephemeral CI Runners)

| Variable | Description |
| :--- | :--- |
| `APPLE_TEAM_ID` | Apple Developer Team ID (defaults to `KNK9SM7SLS`). |
| `IOS_BUNDLE_ID` | App bundle identifier (defaults to `com.craiglabenz.babble`). |
| `IOS_EXPORT_METHOD` | Export method for `flutter build ipa` (defaults to `ad-hoc`). |
| `IOS_P12_BASE64` | Base64-encoded Apple Distribution `.p12` certificate. Installed into an ephemeral keychain that is deleted when the script exits. |
| `IOS_P12_PASSWORD` | Password for the `.p12` certificate. |
| `IOS_PROVISIONING_PROFILE_BASE64` | Base64-encoded `.mobileprovision` file (Ad-Hoc profile containing tester UDIDs). |
| `IOS_PROVISIONING_PROFILE` | Provisioning profile name or UUID (auto-detected when `IOS_PROVISIONING_PROFILE_BASE64` is provided). |
