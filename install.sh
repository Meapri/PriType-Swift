#!/bin/bash
set -e

# Define variables
APP_NAME="PriTypeV2"
BUILD_DIR=".build/release"
INSTALL_DIR="$HOME/Library/Input Methods"
APP_BUNDLE="${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "Building release..."
swift build -c release

echo "Creating bundle structure..."
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

echo "Copying executable..."
cp "$BUILD_DIR/PriType" "$MACOS_DIR/PriTypeV2"

echo "Copying Info.plist..."
cp Info.plist "$CONTENTS_DIR/"

# Copy menu bar icon
# Copy Resources directory (localization, etc)
cp -R Resources/* "$RESOURCES_DIR/" 2>/dev/null || true

# Copy App Icon
cp "AppIcon.icns" "$RESOURCES_DIR/" 2>/dev/null || echo "No AppIcon.icns found"

# Copy menu bar icon
cp "icon.tiff" "$RESOURCES_DIR/" 2>/dev/null || echo "No icon.tiff found, skipping."

# Copy Swift Package Manager resource bundle (required for Bundle.module / L10n)
if [ -d "$BUILD_DIR/PriType_PriTypeCore.bundle" ]; then
    cp -R "$BUILD_DIR/PriType_PriTypeCore.bundle" "$RESOURCES_DIR/"
    echo "Copied PriType_PriTypeCore.bundle"
else
    echo "Warning: PriType_PriTypeCore.bundle not found"
fi

# Code Signing
if [ -n "$SIGNING_IDENTITY" ]; then
    echo "Signing with identity: $SIGNING_IDENTITY"
    codesign --force --options runtime --sign "$SIGNING_IDENTITY" "$APP_BUNDLE"
    echo "Signing complete."
else
    echo "No SIGNING_IDENTITY set. Skipping signing (Ad-hoc signing may apply automatically locally)."
fi

echo "Installing to $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALL_DIR/PriType.app"
rm -rf "$INSTALL_DIR/$APP_BUNDLE"
mv "$APP_BUNDLE" "$INSTALL_DIR/"

echo "Installation complete!"
echo "Please log out and log back in, or restart your computer."
echo "Then enable '$APP_NAME' in System Settings > Keyboard > Input Sources."
