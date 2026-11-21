#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build "$@" --product MicroCompanion
bin="$(swift build "$@" --show-bin-path)"
if [[ ! -d node_modules/electron || ! -d node_modules/electron-liquid-glass ]]; then npm ci; fi
node -e 'require("electron")'
mkdir -p dist
temp="$(mktemp -d "$PWD/dist/.package.XXXXXX")"
trap 'rm -rf -- "$temp"' EXIT
app="$temp/MicroCompanion.app"
ditto node_modules/electron/dist/Electron.app "$app"
res="$app/Contents/Resources"
mkdir -p "$res/app"
bash scripts/build-firmware-manager.sh "$res/firmware"
cp -R electron package.json package-lock.json "$res/app/"
(cd "$res/app" && npm ci --omit=dev --ignore-scripts --no-audit --no-fund)
rm -f "$res/default_app.asar"
install -m 755 "$bin/MicroCompanion" "$res/KeyberthBridge"
install -m 644 scripts/Keyberth.icns "$res/Keyberth.icns"
mv "$app/Contents/MacOS/Electron" "$app/Contents/MacOS/MicroCompanion"
plist="$app/Contents/Info.plist"
plutil -replace CFBundleExecutable -string MicroCompanion "$plist"
plutil -replace CFBundleIdentifier -string local.kent.microcmux "$plist"
plutil -replace CFBundleName -string Keyberth "$plist"
plutil -replace CFBundleDisplayName -string Keyberth "$plist"
plutil -replace CFBundleIconFile -string Keyberth.icns "$plist"
version="$(node -p 'require("./package.json").version')"
plutil -replace CFBundleShortVersionString -string "$version" "$plist"
plutil -replace CFBundleVersion -string "$version" "$plist"
plutil -replace LSUIElement -bool NO "$plist"
dest="$PWD/dist/MicroCompanion.app"
if [[ -e "$dest" ]]; then mv "$dest" "$temp/previous.app"; fi
if ! mv "$app" "$dest"; then
    if [[ -e "$temp/previous.app" ]]; then mv "$temp/previous.app" "$dest"; fi
    exit 1
fi
