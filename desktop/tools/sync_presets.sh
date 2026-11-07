#!/usr/bin/env bash
# Presets live in app/assets/presets (source of truth); desktop ships a copy.
set -euo pipefail
cd "$(dirname "$0")/../.."
rm -rf desktop/aigen/presets
cp -r app/assets/presets desktop/aigen/presets
find desktop/aigen/presets -type f | wc -l
