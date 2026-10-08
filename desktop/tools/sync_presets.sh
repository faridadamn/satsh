#!/usr/bin/env bash
# Presets live in app/assets/presets (source of truth); desktop ships a copy.
set -euo pipefail
cd "$(dirname "$0")/../.."
rm -rf desktop/satsh/presets
cp -r app/assets/presets desktop/satsh/presets
find desktop/satsh/presets -type f | wc -l
