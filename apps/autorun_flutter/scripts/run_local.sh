#!/bin/bash

# Run Flutter app with local development environment
echo "Starting ICP Autorun with local development environment..."
echo "Backend API Endpoint: http://localhost:58000"

cd "$(dirname "$0")/.."

flutter run -d chrome \
  --dart-define=PUBLIC_API_ENDPOINT=http://localhost:58000 \
  "$@"
