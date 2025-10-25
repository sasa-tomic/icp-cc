# ICP Autorun - Build Guide

Use Just (modern build tool) and scripts in `scripts/` to build native libraries and fail fast if missing.

## 🚀 Quick Start

First, install all dependencies for local development (one-time setup):
```bash
./scripts/bootstrap.sh
```

Then install Just (one-time setup):
```bash
./install-just.sh
```

Then build for your platform:

### Platform Builds
- **Linux desktop**:
  ```bash
  just linux
  cd apps/autorun_flutter && flutter run -d linux
  ```
- **Android**:
  ```bash
  ./scripts/bootstrap.sh  # Install Android SDK/NDK/toolchains and rust targets
  just android
  cd apps/autorun_flutter && flutter run -d <your-device-id>
  ```
- **macOS**:
  ```bash
  just macos
  ```
- **iOS**:
  ```bash
  just ios
  ```
- **Windows**:
  ```bash
  just windows
  ```

### Development Commands
```bash
just                    # Show all available commands
just test               # Run all tests with linting
just clean              # Clean build artifacts
just all                # Build all platforms
```

### Cloudflare Workers Development
```bash
just cloudflare-dev                 # Start local development server
just cloudflare-deploy              # Deploy to production
```

## ⚡ Features

### Fail-fast Build System
- Linux/Windows builds abort if native lib is missing with actionable messages
- Android builds abort if any ABI lib is missing, showing which ones and suggesting fixes

### Just Benefits
- **Cross-platform**: Works consistently on Linux, macOS, Windows
- **Better arguments**: Natural syntax: `just cmd -- --args`
- **Smart caching**: Intelligent build optimization
- **Clear errors**: Better error messages and debugging

## 📁 Repository Layout

- `apps/autorun_flutter`: Flutter application
- `crates/icp_core`: Rust FFI crate (cdylib)
- `cloudflare-api/`: Cloudflare Workers API implementation
- `justfile`: Modern build configuration (replaces Makefile)
- `scripts/`: Build and bootstrap helpers
- `docs/`: Architecture and build documentation
- `server-deploy/`: Deployment tools for Cloudflare Workers

## 🔧 Scripts

- `scripts/bootstrap.sh`: Installs rustup and Android SDK/NDK on Linux; sets targets
- `scripts/build_linux.sh`: Builds `libicp_core.so` and copies into Flutter bundle dirs
- `scripts/build_android.sh`: Builds all Android ABIs and copies into `jniLibs/`
- `scripts/build_macos.sh`: Builds `libicp_core.dylib` and copies to common output dirs
- `scripts/build_ios.sh`: Builds iOS static libs; assemble xcframework as needed
- `scripts/build_windows.sh`: Builds `icp_core.dll` and copies into runner dirs

## 📖 Help

### Getting Started
```bash
just                           # Show help
just --list                     # List all commands
just cloudflare-deploy -- --help   # Show command-specific help
```

### Advanced Usage
- **Parallel builds**: `just all` builds all platforms concurrently when possible
- **Flexible arguments**: `just cloudflare-deploy -- --dry-run --verbose`
- **Platform detection**: Just automatically detects your OS and architecture

## 📖 Command Reference

| Common Task | Command |
|-------------|---------|
| Show help | `just` |
| Run tests | `just test` |
| Build Linux | `just linux` |
| Build Android | `just android` |
| Clean artifacts | `just clean` |
| Deploy with dry-run | `just cloudflare-deploy -- --dry-run` |

## ⚠️ Notes

- For Android, ensure an emulator or device is connected
- Use `apps/autorun_flutter/tool/run_android.sh` to start a default emulator and run
- For iOS/macOS, additional Xcode project copy phases can be added to auto-embed the dylib/xcframework
- Just provides better error handling and cross-platform compatibility with enhanced features
