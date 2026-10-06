#!/usr/bin/env bash
#
# make-app.sh — build + assemble a distributable BleWidget.app, then emit .zip/.dmg + checksums.
#
# Copyright (c) 2026 The TOTEM ZMK Contributors / KeyBeacon Contributors
# SPDX-License-Identifier: MIT
#
# Signing/notarization is INERT this iteration: if the ZMK-Studio-aligned Developer ID secrets
# are absent, the artifact is produced UNSIGNED (Gatekeeper will prompt on download). If
# APPLE_SIGNING_IDENTITY is present, the bundle is codesigned here; notarization is performed by
# release.yml via notarytool. A signing failure is fatal (never ship a half-signed artifact).
#
# Usage: packaging/make-app.sh [version]
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT/app/macos"
NAME="BleWidget"
VERSION="${1:-dev}"
DIST="$ROOT/dist"
BUNDLE="$DIST/$NAME.app"

echo "==> swift build -c release"
swift build --package-path "$APP_DIR" -c release
BIN_DIR="$(swift build --package-path "$APP_DIR" -c release --show-bin-path)"

echo "==> assemble $NAME.app"
rm -rf "$DIST"
mkdir -p "$BUNDLE/Contents/MacOS"
cp "$BIN_DIR/$NAME" "$BUNDLE/Contents/MacOS/$NAME"
cp "$APP_DIR/Info.plist" "$BUNDLE/Contents/Info.plist"
printf 'APPL????' > "$BUNDLE/Contents/PkgInfo"

echo "==> signing (inert unless Developer ID secrets present)"
if [[ -n "${APPLE_SIGNING_IDENTITY:-}" ]]; then
  echo "    codesign as: $APPLE_SIGNING_IDENTITY"
  codesign --force --deep --options runtime --sign "$APPLE_SIGNING_IDENTITY" "$BUNDLE"
  codesign --verify --strict "$BUNDLE"
else
  echo "    APPLE_SIGNING_IDENTITY not set → UNSIGNED (Gatekeeper will prompt on download)"
fi

echo "==> package .zip / .dmg + checksums"
( cd "$DIST" && ditto -c -k --keepParent "$NAME.app" "$NAME-$VERSION.zip" )
hdiutil create -quiet -volname "$NAME" -srcfolder "$BUNDLE" -ov -format UDZO "$DIST/$NAME-$VERSION.dmg"
( cd "$DIST" && shasum -a 256 "$NAME-$VERSION.zip" "$NAME-$VERSION.dmg" > "$NAME-$VERSION.sha256" )

echo "==> artifacts:"
ls -1 "$DIST"
