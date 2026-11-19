#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
args=()
if [[ "${1:-}" == "--disable-sandbox" ]]; then args+=(--disable-sandbox); fi
swift build "${args[@]}" -c debug
bin="$(swift build "${args[@]}" -c debug --show-bin-path)"
mkdir -p dist
temp="$(mktemp -d "$PWD/dist/.package.XXXXXX")"
trap 'rm -rf -- "$temp"' EXIT
app="$temp/MicroCompanion.app"
mkdir -p "$app/Contents/MacOS"
mkdir -p "$app/Contents/Resources"
install -m 644 Sources/MicroCompanion/Resources/keypad.png "$app/Contents/Resources/keypad.png"
install -m 644 scripts/Keyberth.icns "$app/Contents/Resources/Keyberth.icns"
install -m 644 scripts/MicroCompanion-Info.plist "$app/Contents/Info.plist"
install -m 755 "$bin/MicroCompanion" "$app/Contents/MacOS/MicroCompanion"
plutil -lint "$app/Contents/Info.plist"
# Preserve previous bundle in the staging directory until replacement is in place.
dest="$PWD/dist/MicroCompanion.app"
if [[ -e "$dest" ]]; then mv "$dest" "$temp/previous.app"; fi
if ! mv "$app" "$dest"; then
    if [[ -e "$temp/previous.app" ]]; then mv "$temp/previous.app" "$dest"; fi
    exit 1
fi
