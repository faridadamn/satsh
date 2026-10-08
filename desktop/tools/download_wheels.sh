#!/usr/bin/env bash
# Download the offline wheels install.bat expects.
# Win7 = Python 3.8 only; Win10/11 = whatever Python 3.8–3.14 is installed. 32 & 64-bit.
# (pip evaluates "; python_version" markers for the machine running it, so pick per version here.)
set -euo pipefail
cd "$(dirname "$0")/.."
PIP="${PIP:-python3 -m pip}"
BASE="paramiko==3.4.0 cryptography==42.0.5 bcrypt==4.1.2 pynacl==1.5.0 pycparser==2.23"
for plat in win32 win_amd64; do
  for v in 38 39 310 311 312 313 314; do
    case $v in
      313) extra="cffi==1.17.1 pillow==11.3.0" ;;
      314) extra="cffi==2.0.0 pillow==11.3.0" ;;
      *)   extra="cffi==1.16.0 pillow==10.4.0" ;;
    esac
    $PIP download -q $BASE $extra --only-binary=:all: --python-version "$v" --implementation cp \
      --platform "$plat" -d "wheels/$plat" || echo "  (gagal py$v $plat)"
  done
done
ls wheels/*/ | wc -l
