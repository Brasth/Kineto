#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_ROOT="${BUILD_ROOT:-$ROOT/build/release}"
ARCHIVE="$BUILD_ROOT/Kineto.xcarchive"
EXPORT="$BUILD_ROOT/export"
STAGE="$BUILD_ROOT/dmg-root"
DMG="$BUILD_ROOT/Kineto.dmg"
NOTARY_PROFILE="${KINETO_NOTARY_PROFILE:-}"

USE_CREATE_DMG=0
if command -v create-dmg >/dev/null 2>&1; then
  USE_CREATE_DMG=1
  echo "Using create-dmg for nicer DMG (local preference)"
else
  echo "create-dmg not found; falling back to hdiutil (install with: brew install create-dmg)"
fi

[[ -n "$NOTARY_PROFILE" ]] || {
  echo "Set KINETO_NOTARY_PROFILE to a notarytool Keychain profile." >&2
  exit 1
}
command -v xcodebuild >/dev/null
command -v xcrun >/dev/null
"$ROOT/scripts/verify-model-artifacts.sh"
rm -rf "$BUILD_ROOT"
mkdir -p "$EXPORT" "$STAGE"

xcodebuild \
  -project "$ROOT/Kineto.xcodeproj" \
  -scheme Kineto \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE" \
  archive

xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT" \
  -exportOptionsPlist "$ROOT/Config/ExportOptions.plist"

APP="$EXPORT/Kineto.app"
[[ -d "$APP" ]] || { echo "Export did not produce Kineto.app" >&2; exit 1; }
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -d --entitlements :- "$APP" > "$BUILD_ROOT/app-entitlements.plist"
[[ "$(plutil -extract com.apple.security.app-sandbox raw "$BUILD_ROOT/app-entitlements.plist")" == "true" ]]
[[ "$(plutil -extract com.apple.security.device.audio-input raw "$BUILD_ROOT/app-entitlements.plist")" == "true" ]]
[[ "$(plutil -extract com.apple.security.files.user-selected.read-write raw "$BUILD_ROOT/app-entitlements.plist")" == "true" ]]
if plutil -extract com.apple.security.network.client raw "$BUILD_ROOT/app-entitlements.plist" >/dev/null 2>&1; then
  echo "Offline release unexpectedly has network-client entitlement" >&2
  exit 1
fi
codesign -dvv "$APP" 2> "$BUILD_ROOT/codesign-details.txt"
grep 'flags=.*runtime' "$BUILD_ROOT/codesign-details.txt" >/dev/null || {
  echo "Hardened runtime is not enabled" >&2
  exit 1
}
cp -R "$APP" "$STAGE/Kineto.app"
cp "$ROOT/THIRD_PARTY_NOTICES" "$STAGE/THIRD_PARTY_NOTICES.txt"
ln -s /Applications "$STAGE/Applications"
find "$STAGE" -exec touch -h -t 202607180000 {} +

if [[ $USE_CREATE_DMG -eq 1 ]]; then
  printf 'Creating polished DMG with create-dmg (local preference per article)\n'
  CREATE_DMG_DIR="$BUILD_ROOT/create-dmg-out"
  mkdir -p "$CREATE_DMG_DIR"
  create-dmg \
    --volname "Kineto" \
    --window-pos 200 120 \
    --window-size 600 300 \
    --icon-size 100 \
    --icon "Kineto.app" 175 120 \
    --hide-extension "Kineto.app" \
    --app-drop-link 425 120 \
    --overwrite \
    "$STAGE/Kineto.app" \
    "$CREATE_DMG_DIR"
  shopt -s nullglob
  GENERATED=("$CREATE_DMG_DIR"/*.dmg)
  shopt -u nullglob
  if [[ ${#GENERATED[@]} -eq 1 ]]; then
    mv -f "${GENERATED[0]}" "$DMG"
  else
    echo "create-dmg did not produce exactly one DMG" >&2
    exit 1
  fi
  rm -rf "$CREATE_DMG_DIR"
else
  printf 'Creating DMG with hdiutil (fallback)\n'
  hdiutil create \
    -volname Kineto \
    -srcfolder "$STAGE" \
    -format UDZO \
    -ov \
    "$DMG"
fi

[[ -f "$DMG" ]] || { echo "DMG was not created at $DMG" >&2; exit 1; }
codesign --sign "${DEVELOPER_ID_APPLICATION:?Set DEVELOPER_ID_APPLICATION}" \
  --timestamp \
  "$DMG"
xcrun notarytool submit "$DMG" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait \
  --output-format json > "$BUILD_ROOT/notarization.json"
cat "$BUILD_ROOT/notarization.json"
[[ "$(plutil -extract status raw "$BUILD_ROOT/notarization.json")" == "Accepted" ]] || {
  echo "Apple notarization did not accept the DMG" >&2
  exit 1
}
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"

shasum -a 256 "$DMG" | tee "$DMG.sha256"
printf 'Release artifact: %s\n' "$DMG"
