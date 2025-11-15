#!/bin/bash

# Run Flutter app with local development environment
echo "Starting ICP Autorun with local development environment..."
echo "Appwrite Endpoint: http://localhost:48080/v1"

cd "$(dirname "$0")/.."

flutter run -d chrome \
  --dart-define=APPWRITE_ENDPOINT=http://localhost:48080/v1 \
  "$@"