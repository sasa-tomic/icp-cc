#!/usr/bin/env bash
set -euo pipefail
# Bootstrap system deps for Android builds (tested path), and Rust targets
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)

OS=$(uname -s)

if [[ "$OS" != "Linux" ]]; then
  echo "This bootstrap script currently targets Linux hosts."
fi

sudo apt-get update
sudo apt-get install -y openjdk-17-jdk unzip curl git build-essential pkg-config

ANDROID_HOME="$HOME/Android/Sdk"
mkdir -p "$ANDROID_HOME"
cd "$ANDROID_HOME"
if [ ! -d cmdline-tools/latest ]; then
  echo "Installing Android cmdline-tools..."
  curl -sL https://dl.google.com/android/repository/commandlinetools-linux-10406996_latest.zip -o cmdline-tools.zip
  mkdir -p cmdline-tools
  unzip -q cmdline-tools.zip -d cmdline-tools
  mv cmdline-tools/cmdline-tools cmdline-tools/latest
  rm -f cmdline-tools.zip
fi
export ANDROID_HOME
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"
yes | sdkmanager --licenses >/dev/null || true
sdkmanager --install "platform-tools" "platforms;android-35" "build-tools;35.0.0" "emulator" "ndk;27.0.12077973"

# Rust toolchain
if ! command -v rustup >/dev/null 2>&1; then
  echo "Installing rustup..."
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
  source "$HOME/.cargo/env"
fi
rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android

# Done
echo "Android SDK/NDK installed at ${ANDROID_HOME}. Ensure to re-source shell if needed."
