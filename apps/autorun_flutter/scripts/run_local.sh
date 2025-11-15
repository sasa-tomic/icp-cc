#!/bin/bash

# Run Flutter app with local development environment
echo "Starting ICP Autorun with local development environment..."
echo "Marketplace API: http://localhost:48080/v1"

cd "$(dirname "$0")/.."

flutter run -d chrome \
  --dart-define=MARKETPLACE_API_URL=http://localhost:48080/v1 \
  "$@"