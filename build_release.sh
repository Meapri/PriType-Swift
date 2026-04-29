#!/bin/bash
set -e

# Define variables
APP_NAME="PriTypeV2"
BUILD_DIR=".build/release"
PAYLOAD_DIR="Packaging/Payload"
INSTALL_DIR="/Library/Input Methods"
APP_BUNDLE="${APP_NAME}.app"
CONTENTS_DIR="${PAYLOAD_DIR}/${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
PKG_OUTPUT="PriTypeV2_Release.pkg"

echo "=========================================="
echo "    PriType Release Build & Packaging     "
echo "=========================================="

echo "[1/4] Building release..."
swift build -c release

echo "[2/4] Creating bundle structure..."
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

# Code Signing the App
echo "[3/4] Code Signing the .app bundle..."
APP_SIGN_IDENTITY=""
# Try to find Developer ID Application first
DEV_ID_APP=$(security find-identity -v -p codesigning | grep "Developer ID Application:" | head -n 1 | awk -F'"' '{print $2}')
if [ -n "$DEV_ID_APP" ]; then
    APP_SIGN_IDENTITY="$DEV_ID_APP"
else
    # Fallback to Apple Development
    APPLE_DEV_CERT=$(security find-identity -v -p codesigning | grep "Apple Development:" | head -n 1 | awk -F'"' '{print $2}')
    if [ -n "$APPLE_DEV_CERT" ]; then
        APP_SIGN_IDENTITY="$APPLE_DEV_CERT"
    fi
fi

if [ -n "$APP_SIGN_IDENTITY" ]; then
    echo "Using App Identity: $APP_SIGN_IDENTITY"
    codesign --force --options runtime --timestamp --sign "$APP_SIGN_IDENTITY" "$PAYLOAD_DIR/$APP_BUNDLE"
else
    echo "Warning: No valid Developer ID Application or Apple Development certificate found."
    echo "Using ad-hoc signing for the .app (Not suitable for external distribution)."
    codesign --force --deep --sign - "$PAYLOAD_DIR/$APP_BUNDLE"
fi

# Building the PKG
echo "[4/4] Building the PKG installer..."

# Disable relocation by generating a component plist
echo "Generating component plist to disable relocation..."
pkgbuild --analyze --root "$PAYLOAD_DIR" "PriTypeV2_components.plist"
# Use plutil to change BundleIsRelocatable to false for the first item
plutil -replace 0.BundleIsRelocatable -bool NO "PriTypeV2_components.plist"

PKG_SIGN_IDENTITY=""
# Try to find Developer ID Installer first
DEV_ID_INSTALLER=$(security find-identity -v | grep "Developer ID Installer:" | head -n 1 | awk -F'"' '{print $2}')
if [ -n "$DEV_ID_INSTALLER" ]; then
    PKG_SIGN_IDENTITY="$DEV_ID_INSTALLER"
else
    # Mac Installer Distribution (Mac App Store) could also be checked, but usually it's Developer ID
    MAC_INSTALLER=$(security find-identity -v | grep "Mac Installer Distribution:" | head -n 1 | awk -F'"' '{print $2}')
    if [ -n "$MAC_INSTALLER" ]; then
        PKG_SIGN_IDENTITY="$MAC_INSTALLER"
    fi
fi

if [ -n "$PKG_SIGN_IDENTITY" ]; then
    echo "Using Installer Identity: $PKG_SIGN_IDENTITY"
    pkgbuild --root "$PAYLOAD_DIR" \
             --component-plist "PriTypeV2_components.plist" \
             --install-location "$INSTALL_DIR" \
             --scripts "Packaging/scripts" \
             --identifier "com.meapri.PriTypeV2" \
             --version "2.1.2" \
             --sign "$PKG_SIGN_IDENTITY" \
             "$PKG_OUTPUT"
else
    echo "Warning: No valid Developer ID Installer certificate found."
    echo "Building unsigned PKG."
    pkgbuild --root "$PAYLOAD_DIR" \
             --component-plist "PriTypeV2_components.plist" \
             --install-location "$INSTALL_DIR" \
             --scripts "Packaging/scripts" \
             --identifier "com.meapri.PriTypeV2" \
             --version "2.1.2" \
             "$PKG_OUTPUT"
fi

rm "PriTypeV2_components.plist"

echo "=========================================="
echo "    Done! PKG created: $PKG_OUTPUT"
echo "=========================================="
echo "Note: To distribute this PKG outside the Mac App Store without Gatekeeper warnings,"
echo "you MUST sign it with 'Developer ID Application' and 'Developer ID Installer' certs,"
echo "and notarize it using 'xcrun notarytool'."
echo "For now, the installer is ready for local testing."
