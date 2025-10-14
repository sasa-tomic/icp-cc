#!/usr/bin/env bash
set -euo pipefail

# Ensure Android emulator is running, then run flutter on it.

AVD_NAME="Medium_Phone_API_35"

if ! command -v flutter >/dev/null 2>&1; then
  echo "flutter not found on PATH" >&2
  exit 1
fi

if ! command -v adb >/dev/null 2>&1; then
  echo "adb not found on PATH" >&2
  exit 1
fi

# Start emulator if not running
if ! adb devices | grep -q "emulator-"; then
  if command -v emulator >/dev/null 2>&1; then
    echo "Starting Android emulator ${AVD_NAME}..."
    nohup emulator -avd "${AVD_NAME}" -netdelay none -netspeed full >/dev/null 2>&1 &
    # Wait for device
    echo "Waiting for device to boot..."
    adb wait-for-device
    # Give it a bit more time
    sleep 15
  else
    echo "Android emulator not found. Please install Android SDK emulator tools." >&2
    exit 1
  fi
fi

# Now run flutter on the first emulator device
flutter run -d emulator-5554
