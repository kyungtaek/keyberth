#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${SIGN_IDENTITY:?Set a Developer ID Application identity}"
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  notary_auth=(--keychain-profile "$NOTARY_PROFILE")
else
  : "${NOTARY_KEY_PATH:?Set NOTARY_PROFILE or NOTARY_KEY_PATH and NOTARY_ISSUER}"
  : "${NOTARY_ISSUER:?Set the App Store Connect issuer}"
  key_name="$(basename "$NOTARY_KEY_PATH" .p8)"
  notary_auth=(--key "$NOTARY_KEY_PATH" --key-id "${key_name#AuthKey_}" --issuer "$NOTARY_ISSUER")
fi
version="$(node -p 'require("./package.json").version')"
arch="$(node -p 'process.arch')"
[[ "$arch" == arm64 ]] || { echo "This release target requires Apple Silicon." >&2; exit 1; }
npm ci
swift test
bash scripts/package.sh -c release
stage="$(mktemp -d "$PWD/dist/.release.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
mkdir "$stage/layout" "$stage/assets"
bundle="$stage/layout/Keyberth.app"
ditto dist/MicroCompanion.app "$bundle"
node --input-type=module - "$bundle" <<'JS'
import {sign} from '@electron/osx-sign';
import {createRequire} from 'node:module';
const require=createRequire(import.meta.url);
await sign({app:process.argv[2],identity:process.env.SIGN_IDENTITY,platform:'darwin',version:require('electron/package.json').version,preAutoEntitlements:false});
JS
notarize() {
  xcrun notarytool submit "$1" "${notary_auth[@]}" --wait --output-format json > "$stage/notary.json"
  [[ "$(plutil -extract status raw "$stage/notary.json")" == Accepted ]] || { cat "$stage/notary.json" >&2; return 1; }
}
ditto -c -k --sequesterRsrc --keepParent "$bundle" "$stage/notary.zip"
notarize "$stage/notary.zip"
xcrun stapler staple "$bundle"
codesign --verify --deep --strict "$bundle"
spctl -a -t exec "$bundle"
name="Keyberth-$version-macOS-$arch"
ditto -c -k --sequesterRsrc --keepParent "$bundle" "$stage/assets/$name.zip"
ln -s /Applications "$stage/layout/Applications"
hdiutil create -quiet -srcfolder "$stage/layout" -volname "Keyberth $version" -format UDZO -fs HFS+ "$stage/assets/$name.dmg"
codesign --sign "$SIGN_IDENTITY" --timestamp "$stage/assets/$name.dmg"
notarize "$stage/assets/$name.dmg"
xcrun stapler staple "$stage/assets/$name.dmg"
spctl -a -t open --context context:primary-signature "$stage/assets/$name.dmg"
node scripts/update-feed.cjs "$stage/assets" "$version" "$arch"
mkdir -p "dist/releases/$version"
cp "$stage/assets/"* "dist/releases/$version/"
