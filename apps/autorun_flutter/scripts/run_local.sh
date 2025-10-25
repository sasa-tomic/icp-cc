#!/bin/bash

# Run Flutter app with local development environment
echo "Starting ICP Autorun with local development environment..."
echo "Cloudflare Endpoint: http://localhost:8787"

cd "$(dirname "$0")/.."

flutter run -d chrome \
  --dart-define=CLOUDFLARE_ENDPOINT=http://localhost:8787 \
  "$@"