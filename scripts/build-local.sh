#!/bin/bash
set -euo pipefail
cd -- "$(dirname "$0")/.."

galmuri_configuration="${1:-debug}"
case "$galmuri_configuration" in debug|release) ;; *) echo 'Use debug or release' >&2; exit 1 ;; esac
swift build --configuration "$galmuri_configuration"
galmuri_binary_directory="$(swift build --configuration "$galmuri_configuration" --show-bin-path)"
python3 scripts/package-app.py "$galmuri_configuration" "$galmuri_binary_directory/Galmuri"
