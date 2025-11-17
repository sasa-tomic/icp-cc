#!/bin/bash

# Run Flutter app with production environment
echo "Starting ICP Autorun with production environment..."
echo "Cloudflare Endpoint: https://icp-mp.kalaj.org"

cd "$(dirname "$0")/.."

flutter run -d chrome \
  --dart-define=PUBLIC_API_ENDPOINT=https://icp-mp.kalaj.org \
  "$@"
