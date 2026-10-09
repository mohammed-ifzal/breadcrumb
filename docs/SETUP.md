# Setup: tonight and hour 0

## Tonight, on every laptop

1. Install Flutter **3.47.7** stable (Dart 3.13.5) on all three laptops and compare
   `flutter --version` (D16). Older versions can't resolve the pinned packages. Install the Android SDK and command-line tools and JDK 17.
   Run `flutter doctor` until it's clean.
2. Install git and the GitHub CLI, then run `gh auth login`.
3. Install and sign in to your AI tool:
   - Ifzal: Claude Code
   - Teammate 2: Codex, plus the ChatGPT desktop app for Codex Remote (Mac or Windows
     only)
   - Teammate 3: Antigravity
4. Install the Office Kit PC app from https://pc.vivoglobal.com. It needs x86 Windows
   10+ or macOS 10.14.6+; Windows-on-ARM may not work.
5. Stop the laptop sleeping:
   - **Windows:** Settings > System > Power: screen and sleep "Never" when plugged in.
     Control Panel > Power Options: closing the lid does nothing.
   - **macOS:** run `caffeinate -dis &` in a terminal while working, or turn on
     "Prevent automatic sleeping when the display is off" in Battery options.
6. **Warm the caches.** These are throwaway projects, not project code; they just fill
   the package and Gradle caches so venue Wi-Fi doesn't cost you 30 minutes.

   ```
   flutter create warmup && cd warmup
   flutter pub add flutter_edge_ai:2.1.1 google_mlkit_text_recognition:0.17.1 speech_to_text:7.5.0 flutter_tts:4.2.5 sensors_plus:7.1.1 camera:^0.12.1 path_provider:^2.1.6 permission_handler:12.0.3 vibration:^3.2.1 file_picker:^13.1.0
   flutter build apk --debug
   ```

   If the build fails on minSdk, set `minSdk = 30` in `android/app/build.gradle.kts` and
   build again. Then do the same in a second project, `warmup2`, using
   `flutter_gemma:1.11.4` instead of `flutter_edge_ai`, as the fallback. Delete both
   folders afterwards.
7. Download the Gemma 4 E2B `.litertlm` file (2,583 MB) from
   https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm onto two laptops and
   a USB drive.

## Remote control from the phone (test tonight)

- **Claude Code (Ifzal):** in a folder, run `claude remote-control` and accept the
  prompt. Press space to show the QR code, then scan it with the Claude app. In
  `/config`, turn on "Push when Claude decides" and "Push when actions required".
- **Codex (Teammate 2):** on the phone's ChatGPT app go to Settings > Connections >
  Control this Mac or PC, then scan the QR code from the desktop app.
- **Antigravity (Teammate 3):** on the laptop go to Settings > App > Enable Remote
  Control. On the phone, open antigravity.google.com and add it to the home screen.

## Office Kit (at check-in, with the loaner iQOO)

1. On the phone, check that Settings > Other connections > Office Kit exists.
2. Pair each laptop by QR code, the same Wi-Fi, or a USB cable.
3. For Remote PC: Office Kit > Remote PC, then enter the PC's numeric address and
   password.
4. Test it: move a file in both directions, copy and paste across devices, and mirror
   the phone to the laptop **over USB too**. Aeroplane mode turns Wi-Fi off during the
   demo.

## Hour 0 (captain)

1. Create the private repo, with collaborators added.
2. Create the Flutter project:
   `flutter create --org com.teamgroza --platforms android breadcrumb`.
3. **Make one shared debug key, so every laptop and CI build installs over the others
   without wiping the 2.6 GB model:**

   ```
   keytool -genkeypair -v -keystore android/app/debug.keystore -storepass android -alias androiddebugkey -keypass android -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Android Debug,O=Android,C=US"
   ```

   In `android/app/build.gradle.kts`, point the debug signing config at
   `file("debug.keystore")` and commit the keystore. A debug key is not a secret.
4. In `android/app/build.gradle.kts`:
   - `minSdk = 30`
   - `abiFilters` set to `arm64-v8a` only
   - add the dependency `com.google.mlkit:text-recognition-devanagari:16.0.1`
5. Add every package in one commit (the list in step 6 above). The repo builds with AGP
   9.1.0, Gradle 9.3.1 and Kotlin 2.4.0 (D16).
6. In `AndroidManifest.xml`:
   - permissions: `CAMERA`, `RECORD_AUDIO`, `ACTIVITY_RECOGNITION`, `VIBRATE`
   - `<uses-native-library android:name="libOpenCL.so" android:required="false"/>`
     and the same for `libvndksupport.so`, inside `<application>` (check the
     LiteRT-LM Android docs)
   - inside `<queries>`, intents for `android.intent.action.TTS_SERVICE` and
     `android.speech.RecognitionService`, so text-to-speech and speech recognition are
     visible on Android 11+
7. Copy in this starter pack, which already includes `docs/status/`. Generate `lib/core/contracts.dart`,
   `lib/core/tuning.dart` and the `Fake...` classes from `docs/CONTRACTS.md`.
8. Add the CI workflow below. Push, and confirm the run is green and the APK installs on
   the phone.

### Getting the Gemma file onto the phone (test at hour 0; record what works in DECISIONS.md)

- **Option A,** the pattern Google's on-device LLM guides use:
  `adb shell mkdir -p /data/local/tmp/llm` then
  `adb push gemma-4-E2B-it.litertlm /data/local/tmp/llm/`. Load it by that absolute
  path.
- **Option B:** run the app once, then
  `adb push gemma-4-E2B-it.litertlm /sdcard/Android/data/com.teamgroza.breadcrumb/files/`.
  Load it from the app's external files directory.

Reinstalling with `adb install -r` and the shared key keeps option B's file.
Uninstalling deletes it.

### CI: `.github/workflows/apk.yml` (standard GitHub Actions boilerplate)

```yaml
name: apk
on: [push, workflow_dispatch]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: actions/setup-java@v6
        with: {distribution: temurin, java-version: '17'}
      - uses: subosito/flutter-action@v2
        with: {channel: stable, flutter-version: 3.47.7, cache: true}
      - run: flutter pub get
      - run: flutter analyze
      - run: flutter test
      - run: flutter build apk --debug
      - uses: actions/upload-artifact@v7
        with:
          path: build/app/outputs/flutter-apk/app-debug.apk
          archive: false
          retention-days: 3
```

With `archive: false`, the phone's browser downloads a plain `.apk` from the run page.
Private repos get 2,000 free Actions minutes a month. Java 17 is an assumption; if the
build complains, match what `flutter doctor` reports.
