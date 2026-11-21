#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
dest="${1:-$PWD/dist/firmware}"
mkdir -p "$dest"
temp="$(mktemp -d)"
trap 'rm -rf "$temp"' EXIT
sign_args=()
if [[ -n "${SIGN_IDENTITY:-}" ]]; then sign_args=(--codesign-identity "$SIGN_IDENTITY"); fi
uv run --isolated --python 3.12 --with 'pyinstaller==6.16.0' --with 'esptool==4.14.0' pyinstaller \
  ${sign_args[@]+"${sign_args[@]}"} --clean --noconfirm --onefile --name keyberth-firmware --collect-data esptool \
  --workpath "$temp/work" --specpath "$temp" --distpath "$dest" firmware/tools/manage.py
cp "firmware/images/keyberth-$(cat firmware/VERSION).bin" "$dest/"
