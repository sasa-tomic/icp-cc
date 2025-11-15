#!/bin/bash

# Run Flutter app with production environment
echo "Starting ICP Autorun with production environment..."
echo "Cloudflare Endpoint: https://icp-marketplace-api.workers.dev"

cd "$(dirname "$0")/.."

flutter run -d chrome \
  --dart-define=CLOUDFLARE_ENDPOINT=https://icp-marketplace-api.workers.dev \
  "$@"