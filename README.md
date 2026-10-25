# Babble (`translation_app`)

A real-time bilingual speech translation app built with Flutter. Babble separates **Step 1: Speech-to-Text (ASR & Language Detection)** from **Step 2: Text Translation**, allowing each stage to run **100% On-Device** (Edge Whisper variants + Gemma 4 E2B via `flutter_edge_ai`) or in the **Cloud** (Google Gemini), with automatic currency, measurement unit, and time format annotations.

---

## Installing a Standalone Build on Your Phone from Source

### Why Not Just `flutter run`?

By default, `flutter run` installs a **Debug (JIT)** build. On **iOS 14+**, Apple's kernel blocks Just-In-Time (JIT) execution whenever Xcode's debugger is not attached—meaning a Debug app will **immediately crash on launch** if you unplug your iPhone and tap the app icon on your home screen.

To install an Ahead-Of-Time (AOT) **Release** build that runs untethered on your phone for months or years without needing a computer attached, use [`./scripts/install_ios.sh`](scripts/install_ios.sh) or [`./scripts/install_android.sh`](scripts/install_android.sh).

### How Long Do Installed Builds Last?

| Platform & Signing Type | Standalone Lifespan | Details |
| :--- | :--- | :--- |
| **iOS — Paid Apple Developer Account ($99/yr)** | **Up to 12 months (365 days)** | Both default automatic Release signing and `--ad-hoc` distribution profiles last up to 1 year (until the provisioning profile or signing certificate expires). [`install_ios.sh`](scripts/install_ios.sh) prints the exact expiration date and days remaining during installation. |
| **iOS — Free Apple ID ("Personal Team")** | **7 days** | Apple enforces a strict 7-day provisioning profile limit on free personal accounts. After 7 days, iOS will show *"Babble is no longer available"* until re-installed. |
| **Android — Release APK** | **Forever (Never expires)** | Android has no provisioning profile expiration. Once installed, a signed Release APK launches indefinitely until uninstalled. |

---

## 🍎 Installing on iPhone / iPad (macOS + Xcode Required)

### 1. One-Time iPhone & Xcode Setup

You can view this checklist in your terminal at any time by running `./scripts/install_ios.sh --setup-guide`.

1. **Enable Developer Mode on your iPhone (Required on iOS 16+):**
   - Plug your iPhone into your Mac with a data-capable USB-C / Lightning cable.
   - On your iPhone, go to **Settings → Privacy & Security**, scroll to the bottom, and tap **Developer Mode**.
   - Toggle **Developer Mode** **ON** and tap **Restart**.
   - After the phone reboots, unlock it, tap **Turn On** on the popup alert, and enter your iPhone passcode.
2. **Trust Your Mac:**
   - With your iPhone unlocked and plugged into your Mac, tap **Trust** on the *"Trust This Computer?"* prompt on your iPhone and enter your passcode.
3. **Configure Signing & Register Your Device in Xcode:**
   - Open the iOS workspace in Xcode:
     ```bash
     ./scripts/install_ios.sh --open-xcode
     ```
   - In Xcode's top menu bar, open **Xcode → Settings… (`⌘,`) → Accounts**, click **`+`** (bottom-left) → **Apple ID**, and sign in with your Apple account.
   - In Xcode's left sidebar (Project Navigator), click **Runner** (top blue icon) → select the **Runner** target → open the **Signing & Capabilities** tab:
     - Ensure **"Automatically manage signing"** is checked.
     - Set **Team** to your **Paid Apple Developer Team** (for **12-month** validity) or your **Personal Team** (for **7-day** validity).
     - Select your connected iPhone in Xcode's top toolbar device dropdown. If Xcode displays a **"Register Device"** button under Signing & Capabilities, click it so Xcode adds your iPhone's UDID to your provisioning profile.

### 2. Build & Install the Standalone iOS App

```bash
# Build AOT Release, inspect provisioning profile expiration, and install onto connected iPhone:
./scripts/install_ios.sh

# Or build an Ad-Hoc signed IPA (--export-method=ad-hoc) and install onto connected iPhone:
./scripts/install_ios.sh --ad-hoc
```

> **Note for Free "Personal Team" Accounts:** If iOS displays *"Untrusted Developer"* the first time you launch the app on your iPhone, open **Settings → General → VPN & Device Management**, tap your developer certificate, and tap **Trust**.

---

## 🤖 Installing on an Android Phone

### 1. One-Time Android Phone Setup

You can view this checklist in your terminal at any time by running `./scripts/install_android.sh --setup-guide`.

1. **Unlock Developer Options:**
   - Open **Settings → About phone** (on Samsung Galaxy devices: **Settings → About phone → Software information**).
   - Find **Build number** and tap it rapidly **7 times** until you see *"You are now a developer!"* (enter your lock-screen PIN if prompted).
2. **Enable USB Debugging:**
   - Open **Settings → System → Developer options** (on Samsung: **Settings → Developer options**; on Xiaomi/OnePlus: **Settings → Additional settings → Developer options**).
   - Toggle **USB debugging** **ON** and tap **OK**. *(On Xiaomi/MIUI devices, also toggle **Install via USB** ON.)*
3. **Connect & Authorize Your Computer:**
   - Plug your Android phone into your computer via USB and unlock the screen.
   - When the *"Allow USB debugging?"* prompt appears on your phone, check **"Always allow from this computer"** and tap **Allow**.

### 2. Build & Install the Standalone Android Release APK

```bash
# Build AOT Release APK and install in-place (preserving downloaded on-device models & chat history):
./scripts/install_android.sh

# If switching computers/signing keys (INSTALL_FAILED_UPDATE_INCOMPATIBLE), replace existing install:
./scripts/install_android.sh --uninstall-first
```

---

## Development, Testing & CI Scripts

All build, test, and Firebase deployment scripts live in [`scripts/`](scripts/README.md):

| Command | Description |
| :--- | :--- |
| `./scripts/test_and_analyze.sh` | Runs `flutter pub get`, `dart analyze --fatal-infos`, and all unit & widget tests (`flutter test`). |
| `./scripts/install_ios.sh` | Builds an AOT `--release` (or `--ad-hoc`) iOS app and installs it onto a connected iPhone. |
| `./scripts/install_android.sh` | Builds an AOT `--release` Android APK and installs it onto a connected Android phone. |
| `./scripts/build_ios.sh` | Builds a release `.ipa` for CI / Firebase App Distribution. |
| `./scripts/build_android.sh` | Builds a release `.apk` / `.aab` for CI / Firebase App Distribution. |
| `./scripts/build_web.sh` | Builds a release Flutter Web bundle (`build/web`) and optionally deploys to Firebase Hosting. |

See [`scripts/README.md`](scripts/README.md) for full CLI flags and CI environment variables.
