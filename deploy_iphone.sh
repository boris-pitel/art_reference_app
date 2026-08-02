#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Error: iPhone deployment must be run on macOS." >&2
  exit 1
fi

for command_name in flutter xcodebuild; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Error: '$command_name' is not available in PATH." >&2
    exit 1
  fi
done

DEVICE_ID="${1:-}"

if [[ -z "$DEVICE_ID" ]]; then
  echo "Usage: ./deploy_iphone.sh <iphone-device-id>"
  echo
  echo "Connected Flutter devices:"
  flutter devices
  echo
  echo "Run this script again with the iPhone ID shown above."
  exit 2
fi

echo "Preparing Flutter dependencies..."
flutter pub get

echo "Building the signed iOS release..."
flutter build ios --release

echo "Installing the release on device: $DEVICE_ID"
flutter install --release -d "$DEVICE_ID"

echo
echo "Art Reference App release installation completed."
