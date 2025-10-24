#!/bin/bash

# Run Flutter app with production environment
echo "Starting ICP Autorun with production environment..."
echo "Marketplace API: https://fra.cloud.appwrite.io/v1"

cd "$(dirname "$0")/.."

flutter run -d chrome \
  --dart-define=MARKETPLACE_API_URL=https://fra.cloud.appwrite.io/v1 \
  "$@"