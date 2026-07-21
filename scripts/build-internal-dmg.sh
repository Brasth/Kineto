#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

MARKETING_VERSION="${MARKETING_VERSION:-0.1.0}"
CURRENT_PROJECT_VERSION="${CURRENT_PROJECT_VERSION:-1}"
CHANNEL="${CHANNEL:-internal}"
BUILD_ROOT="${BUILD_ROOT:-$ROOT/build/internal-dmg}"

validate_version() {
  local name="$1"
  local value="$2"

  [[ "$value" =~ ^[0-9]+([.][0-9]+){0,2}$ ]] || {
    echo "Invalid $name '$value': expected one to three numeric components" >&2
    exit 1
  }
}

validate_component() {
  local name="$1"
  local value="$2"

  [[ "$value" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || {
    echo "Invalid $name '$value': use only letters, numbers, '.', '_' or '-'" >&2
    exit 1
  }
}

validate_version "MARKETING_VERSION" "$MARKETING_VERSION"
validate_version "CURRENT_PROJECT_VERSION" "$CURRENT_PROJECT_VERSION"
validate_component "CHANNEL" "$CHANNEL"

DEFAULT_DMG_NAME="Kineto-${CHANNEL}-unsigned-${MARKETING_VERSION}-build-${CURRENT_PROJECT_VERSION}.dmg"
DMG_NAME="${DMG_NAME:-$DEFAULT_DMG_NAME}"
[[ "$DMG_NAME" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*[.]dmg$ ]] || {
  echo "Invalid DMG_NAME '$DMG_NAME': expected a safe .dmg filename" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required tool: $1" >&2
    exit 1
  }
}

[[ "$(uname -s)" == "Darwin" ]] || {
  echo "This script requires macOS (Darwin)" >&2
  exit 1
}
[[ "$(uname -m)" == "arm64" ]] || {
  echo "This script requires an arm64 runner; found $(uname -m)" >&2
  exit 1
}

require_command xcodebuild
require_command create-dmg
require_command shasum
require_command node

NODE_VERSION="$(node --version 2>/dev/null || true)"
[[ "$NODE_VERSION" =~ ^v([0-9]+)[.] ]] || {
  echo "Unable to determine Node.js version (reported '$NODE_VERSION')" >&2
  exit 1
}
NODE_MAJOR="${BASH_REMATCH[1]}"
(( NODE_MAJOR >= 20 )) || {
  echo "Node.js >=20 is required; found $NODE_VERSION" >&2
  exit 1
}

NOTICES="$ROOT/THIRD_PARTY_NOTICES"
[[ -f "$NOTICES" ]] || {
  echo "Missing required third-party notices: $NOTICES" >&2
  exit 1
}
# For internal unsigned builds (no Apple Developer account / no notarization):
# Verify model bytes + SHA, whisper.cpp commit provenance, framework presence,
# architecture, and required symbols. Do NOT require exact byte match on the
# compiled CWhisper archive (the XCFramework build from pinned source is not
# bit-reproducible across toolchains).
"$ROOT/scripts/verify-model-artifacts.sh" --internal


DERIVED_DATA="$BUILD_ROOT/DerivedData"
STAGING_ROOT="$BUILD_ROOT/dmg-staging"
GENERATED_ROOT="$BUILD_ROOT/generated-dmg"
FINAL_DMG="$BUILD_ROOT/$DMG_NAME"
CHECKSUM="$FINAL_DMG.sha256"
APP="$DERIVED_DATA/Build/Products/Release/Kineto.app"
STAGED_APP="$STAGING_ROOT/Kineto.app"

rm -rf "$DERIVED_DATA" "$STAGING_ROOT" "$GENERATED_ROOT"
rm -f "$FINAL_DMG" "$CHECKSUM"
mkdir -p "$BUILD_ROOT" "$GENERATED_ROOT" "$STAGING_ROOT"

printf 'Building unsigned arm64 Release app (channel %s, version %s, build %s)\n' \
  "$CHANNEL" "$MARKETING_VERSION" "$CURRENT_PROJECT_VERSION"
xcodebuild \
  -project "$ROOT/Kineto.xcodeproj" \
  -scheme Kineto \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  MARKETING_VERSION="$MARKETING_VERSION" \
  CURRENT_PROJECT_VERSION="$CURRENT_PROJECT_VERSION" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY= \
  build

[[ -d "$APP" ]] || {
  echo "Release build did not produce Kineto.app: $APP" >&2
  exit 1
}

APP_EXECUTABLE="$APP/Contents/MacOS/Kineto"
[[ -f "$APP_EXECUTABLE" ]] || {
  echo "Built Kineto.app is missing its executable: $APP_EXECUTABLE" >&2
  exit 1
}

# The host and explicit Xcode ARCHS setting are arm64 gates. lipo is available
# on the supported macOS toolchain; verify the actual executable as well.
require_command lipo
APP_ARCHS="$(lipo -archs "$APP_EXECUTABLE")"
[[ " $APP_ARCHS " == *" arm64 "* ]] || {
  echo "Built Kineto executable is not arm64 (architectures: $APP_ARCHS)" >&2
  exit 1
}

# create-dmg accepts one app and creates its own temporary disk-image root.
# Copying the unsigned app first lets us preserve notices inside the bundle
# without mutating the Xcode output or attempting to re-sign it.
cp -R "$APP" "$STAGED_APP"
mkdir -p "$STAGED_APP/Contents/Resources"
cp "$NOTICES" "$STAGED_APP/Contents/Resources/THIRD_PARTY_NOTICES"
[[ -f "$STAGED_APP/Contents/Resources/THIRD_PARTY_NOTICES" ]] || {
  echo "Failed to stage third-party notices in Kineto.app" >&2
  exit 1
}

printf 'Creating unsigned DMG with create-dmg; notices are bundled at Kineto.app/Contents/Resources/THIRD_PARTY_NOTICES\n'
create-dmg \
  --no-code-sign \
  --overwrite \
  "$STAGED_APP" \
  "$GENERATED_ROOT"

shopt -s nullglob
GENERATED_DMGS=("$GENERATED_ROOT"/*.dmg)
shopt -u nullglob
[[ "${#GENERATED_DMGS[@]}" -eq 1 ]] || {
  echo "Expected exactly one generated versioned DMG in $GENERATED_ROOT; found ${#GENERATED_DMGS[@]}" >&2
  exit 1
}
GENERATED_DMG="${GENERATED_DMGS[0]}"

mv -f "$GENERATED_DMG" "$FINAL_DMG"
[[ -f "$FINAL_DMG" ]] || {
  echo "Failed to create deterministic DMG: $FINAL_DMG" >&2
  exit 1
}

shasum -a 256 "$FINAL_DMG" > "$CHECKSUM"
[[ -s "$CHECKSUM" ]] || {
  echo "Failed to write SHA-256 sidecar: $CHECKSUM" >&2
  exit 1
}

printf 'Internal unsigned artifact (not notarized and not a public release): %s\n' "$FINAL_DMG"
printf 'SHA-256 sidecar: %s\n' "$CHECKSUM"
