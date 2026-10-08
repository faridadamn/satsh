#!/usr/bin/env bash
# Build satshd (SSH server for "Mode Server") for every Android ABI and drop it
# into the app as lib*.so so Android allows executing it. Needs Go 1.24+.
set -euo pipefail
cd "$(dirname "$0")"
OUT=../app/android/app/src/main/jniLibs
for pair in "arm64 arm64-v8a" "arm armeabi-v7a" "amd64 x86_64"; do
  set -- $pair
  mkdir -p "$OUT/$2"
  CGO_ENABLED=0 GOOS=linux GOARCH=$1 GOARM=7 go build -trimpath -ldflags "-s -w" -o "$OUT/$2/libsatshd.so" .
  echo "✓ $2"
done
# Host build for the Flutter tests (test/phone_server_test.dart)
go build -o /tmp/satshd-x86 .
echo "✓ /tmp/satshd-x86 (buat test)"
