#!/bin/bash
set -e

# Define variables
APP_NAME="PriTypeV2"
BUILD_DIR=".build/debug"
PAYLOAD_DIR="Packaging/Payload"
INSTALL_DIR="/Library/Input Methods"
APP_BUNDLE="${APP_NAME}.app"
CONTENTS_DIR="${PAYLOAD_DIR}/${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
PKG_OUTPUT="PriTypeV2_Debug.pkg"
COMPONENT_PLIST="PriTypeV2_components.plist"
APP_SIGN="Developer ID Application: Chanwoo Park (M4U438VG59)"
PKG_SIGN="Developer ID Installer: Chanwoo Park (M4U438VG59)"
KEYCHAIN_PROFILE="PriTypeNotary"

trap 'rm -f "$COMPONENT_PLIST"' EXIT

echo "=========================================="
echo "    PriType Debug Build & Notarization    "
echo "=========================================="

echo "[1/6] Building debug..."
swift build -c debug

echo "[2/6] Creating bundle structure..."
rm -rf "$PAYLOAD_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy executable and Info.plist
cp "$BUILD_DIR/PriType" "$MACOS_DIR/$APP_NAME"
cp Info.plist "$CONTENTS_DIR/"

# Copy resources
cp -R Resources/* "$RESOURCES_DIR/" 2>/dev/null || true
cp "AppIcon.icns" "$RESOURCES_DIR/" 2>/dev/null || true
cp "icon.tiff" "$RESOURCES_DIR/" 2>/dev/null || true
if [ -d "$BUILD_DIR/PriType_PriTypeCore.bundle" ]; then
    cp -R "$BUILD_DIR/PriType_PriTypeCore.bundle" "$RESOURCES_DIR/"
fi

echo "[3/6] Code Signing the .app bundle..."
codesign --force --options runtime --timestamp \
  --sign "$APP_SIGN" "$PAYLOAD_DIR/$APP_BUNDLE"

echo "Verifying App Signature..."
codesign -vv -d "$PAYLOAD_DIR/$APP_BUNDLE"

APP_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)
PKG_VERSION="${APP_VERSION}-debug"

echo "[4/6] Building the PKG installer..."
pkgbuild --analyze --root "$PAYLOAD_DIR" "$COMPONENT_PLIST"
plutil -replace 0.BundleIsRelocatable -bool NO "$COMPONENT_PLIST"

pkgbuild --root "$PAYLOAD_DIR" \
         --component-plist "$COMPONENT_PLIST" \
         --install-location "$INSTALL_DIR" \
         --scripts "Packaging/scripts" \
         --identifier "com.meapri.PriTypeV2" \
         --version "$PKG_VERSION" \
         --sign "$PKG_SIGN" \
         "$PKG_OUTPUT"

echo "[5/6] Submitting for Notarization..."
xcrun notarytool submit "$PKG_OUTPUT" --keychain-profile "$KEYCHAIN_PROFILE" --wait

echo "[6/6] Stapling Notarization Ticket..."
xcrun stapler staple "$PKG_OUTPUT"
xcrun stapler validate "$PKG_OUTPUT"
pkgutil --check-signature "$PKG_OUTPUT"
spctl -a -vv -t install "$PKG_OUTPUT"

echo "=========================================="
echo "    Done! Debug PKG is ready and notarized."
echo "    File: $PKG_OUTPUT"
echo "=========================================="
