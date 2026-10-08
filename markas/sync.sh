#!/usr/bin/env bash
# markas/ is the source of truth; the app and desktop ship copies.
set -euo pipefail
cd "$(dirname "$0")/.."
for d in app/assets/markas desktop/satsh/markas; do
  rm -rf "$d"; mkdir -p "$d"
  cp markas/markas.py markas/hermes-SKILL.md markas/install.sh "$d/"
done
echo synced
