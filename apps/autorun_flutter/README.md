# ICP Autorun

Cross-platform Flutter client that allows easy scripting and provides a marketplace for scripts for the Internet Computer for Android, iOS, and desktop targets.

## Current Features
- Generate Ed25519 or secp256k1 keypairs backed by 24-word BIP-39 seed phrases.
- Persist keypairs locally using a JSON store in the platform application-support directory.
- List existing keypairs with creation timestamps.
- Reveal or copy the mnemonic, public key, and private key (base64) for export.
- Basic rename/delete plumbing in the controller ready for future UI wiring.

## Project Layout
- `lib/main.dart`: Material UI, dialogs, and screen flow.
- `lib/controllers/keypair_controller.dart`: Keypair lifecycle, persistence orchestration, and key generation.
- `lib/services/keypair_repository.dart`: File-backed store using `path_provider`.
- `lib/models/profile_keypair.dart`: Data model for keypair payloads.

## Running The App
1. Ensure Flutter desktop support is enabled (one-time per host):
   ```bash
   flutter config --enable-linux-desktop --enable-windows-desktop --enable-macos-desktop
   ```
2. Fetch dependencies:
   ```bash
   flutter pub get
   ```
3. Launch on your desired platform, for example:
   ```bash
   flutter run -d linux   # Desktop (Linux)
   flutter run -d windows # Desktop (Windows)
   flutter run -d macos   # Desktop (macOS)
   flutter run -d android # Android emulator or device
   ```

The keypair store file is placed in the OS-specific application support directory. Delete the file to clear all keypairs.

### Tests
Run the deterministic keypair tests (including the DFX-derived reference) with:
```bash
flutter test
```

### Android APK Builds
Build a debug APK for smoke-testing on devices or emulators (requires JDK 17 or newer):
```bash
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
export PATH="$JAVA_HOME/bin:$PATH"
flutter build apk --debug
```
The APK is written to `build/app/outputs/flutter-apk/app-debug.apk` and can be installed with `adb install build/app/outputs/flutter-apk/app-debug.apk`.

For a release-signed artifact (after configuring your keystore), run the same environment exports followed by:
```bash
flutter build apk --release
```
The release build lands alongside the debug artifact under `build/app/outputs/flutter-apk/`.

## Next Steps
1. Integrate canister client UI: list methods from fetched Candid and enable calls (anonymous/authenticated) via the existing Rust FFI bridge.
2. Add secure storage options (KeyStore/Keychain on mobile, OS keyrings on desktop) before shipping sensitive data.
3. Extend the keypair generator to support additional algorithms (e.g. Ed448) and hardware-backed keys.
4. Wire rename/delete affordances into the UI and add import flows for existing seed phrases.

## Limitations
- Web is not yet supported because `path_provider` lacks a web implementation for file-backed storage.
- Private keys are stored in plain text JSON strictly for demo purposes—do not ship without hardening.
- No interaction with canisters yet; this focuses on the local keypair lifecycle.
