#!/bin/bash

# Run Flutter app with production environment
echo "Starting ICP Autorun with production environment..."
echo "Appwrite Endpoint: https://fra.cloud.appwrite.io/v1"

cd "$(dirname "$0")/.."

flutter run -d chrome \
  --dart-define=APPWRITE_ENDPOINT=https://fra.cloud.appwrite.io/v1 \
  "$@"