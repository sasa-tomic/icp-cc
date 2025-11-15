#!/usr/bin/env bash
set -euo pipefail

# Start Android emulator if needed, then run the Flutter app on it.
# AVD name can be overridden via env AVD_NAME.

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)
APP_DIR="$ROOT/icp_identity_manager"
# Default AVD and system image; override via env if desired
# Use the stock AVD name that usually ships with Android Studio
AVD_NAME=${AVD_NAME:-Medium_Phone_API_35}
ANDROID_API_LEVEL=${ANDROID_API_LEVEL:-35}
ANDROID_SYSIMG=${ANDROID_SYSIMG:-system-images;android-${ANDROID_API_LEVEL};google_apis;x86_64}

# Ensure Android tools on PATH
: "${ANDROID_HOME:=${HOME}/Android/Sdk}"
: "${ANDROID_SDK_ROOT:=${ANDROID_HOME}}"
export PATH="$ANDROID_HOME/emulator:$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"

# Build apk and native libs first
make -C "$ROOT" android

# Ensure target AVD exists; create if missing
if ! emulator -list-avds 2>/dev/null | grep -Fxq "$AVD_NAME"; then
  echo "AVD $AVD_NAME not found. Creating it..."
  if ! command -v sdkmanager >/dev/null 2>&1 || ! command -v avdmanager >/dev/null 2>&1; then
    echo "ERROR: sdkmanager/avdmanager not found on PATH. Run ./scripts/bootstrap.sh first." >&2
    exit 2
  fi
  yes | sdkmanager --licenses >/dev/null || true
  sdkmanager --install "platforms;android-${ANDROID_API_LEVEL}" "$ANDROID_SYSIMG"
  # Try to select a reasonable device; fallback to default if device not recognized
  ( echo no ) | avdmanager create avd -n "$AVD_NAME" -k "$ANDROID_SYSIMG" --abi x86_64 --device "pixel_7" || \
  ( echo no ) | avdmanager create avd -n "$AVD_NAME" -k "$ANDROID_SYSIMG" --abi x86_64
fi

# Start emulator if none running
if ! adb devices | awk 'NR>1 {print $1}' | grep -q '^emulator-'; then
  if ! command -v emulator >/dev/null 2>&1; then
    echo "ERROR: Android emulator binary not found on PATH. Run ./scripts/bootstrap.sh first." >&2
    exit 2
  fi
  echo "Starting Android emulator: $AVD_NAME"
  nohup emulator -avd "$AVD_NAME" -netdelay none -netspeed full >/dev/null 2>&1 &
  echo "Waiting for device to boot..."
  adb wait-for-device
  # Wait for boot complete
  until adb shell getprop sys.boot_completed 2>/dev/null | grep -q '1'; do sleep 2; done
  # Extra settle time
  sleep 5
fi

# Pick first emulator device
DEVICE_ID=$(adb devices | awk 'NR>1 && $1 ~ /^emulator-/ {print $1; exit}')
if [[ -z "${DEVICE_ID}" ]]; then
  echo "ERROR: No emulator device found after startup." >&2
  exit 3
fi

cd "$APP_DIR"
# Run in debug mode (hot reload available in this session)
flutter run -d "$DEVICE_ID"
