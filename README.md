# ICP Identity Manager - Build Guide

Use the Makefile and scripts in `scripts/` to build native libraries and fail fast if missing.

Quickstart
- Linux desktop:
  - `make linux`
  - `cd apps/autorun_flutter && flutter run -d linux`
- Android:
  - `./scripts/bootstrap.sh` (Linux installs Android SDK/NDK/toolchains and rust targets)
  - `make android`
  - `cd apps/autorun_flutter && flutter run -d <your-device-id>`
- macOS:
  - `make macos`
- iOS:
  - `make ios`
- Windows:
  - `make windows`

Fail-fast bundling
- Linux/Windows CMake will abort if the native lib is missing with an actionable message.
- Android Gradle will abort mergeJniLibs if any ABI lib is missing, showing which ones and suggesting `make android`.

Scripts
- `scripts/bootstrap.sh`: Installs rustup and Android SDK/NDK on Linux; sets targets.
- `scripts/build_linux.sh`: Builds `libicp_core.so` and copies into Flutter bundle dirs.
- `scripts/build_android.sh`: Builds all Android ABIs and copies into `jniLibs/`.
- `scripts/build_macos.sh`: Builds `libicp_core.dylib` and copies to common output dirs.
- `scripts/build_ios.sh`: Builds iOS static libs; assemble xcframework as needed.
- `scripts/build_windows.sh`: Builds `icp_core.dll` and copies into runner dirs.

Notes
- For Android, ensure an emulator or device is connected; use `apps/autorun_flutter/tool/run_android.sh` to start a default emulator and run.

Repo layout
- `apps/autorun_flutter`: Flutter application
- `crates/icp_core`: Rust FFI crate (cdylib)
- `scripts/`: Build and bootstrap helpers
- `docs/`: Architecture and build docs
- For iOS/macOS, additional Xcode project copy phases can be added to auto-embed the dylib/xcframework if desired.
