#!/usr/bin/env bash
set -euo pipefail

API_BASE_URL="${API_BASE_URL:-}"
if [[ -z "${API_BASE_URL}" ]]; then
  echo "API_BASE_URL is required for Vercel builds."
  exit 1
fi

API_BASE_URL="${API_BASE_URL%/}"

if ! command -v flutter >/dev/null 2>&1; then
  FLUTTER_ROOT="${HOME}/flutter"
  if [[ ! -d "${FLUTTER_ROOT}" ]]; then
    git clone --depth 1 -b stable https://github.com/flutter/flutter.git "${FLUTTER_ROOT}"
  fi
  export PATH="${FLUTTER_ROOT}/bin:${PATH}"
fi

flutter --version
flutter pub get
flutter build web --release --dart-define="API_BASE_URL=${API_BASE_URL}"

# Apply SPA/static hosting rules expected by this app.
cp deploy/vercel.static.json build/web/vercel.json

