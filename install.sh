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
if [ -z "$SIGNING_IDENTITY" ]; then
    # 1. 정식 Apple Development 인증서가 있는지 먼저 확인
    APPLE_DEV_CERT=$(security find-identity -v -p codesigning | grep "Apple Development:" | head -n 1 | awk -F'"' '{print $2}')
    
    if [ -n "$APPLE_DEV_CERT" ]; then
        SIGNING_IDENTITY="$APPLE_DEV_CERT"
    else
        # 2. 없다면 개발용 자체 서명 인증서(PriTypeDev) 확인
        if security find-certificate -c "PriTypeDev" > /dev/null 2>&1; then
            SIGNING_IDENTITY="PriTypeDev"
        fi
    fi
fi

if [ -n "$SIGNING_IDENTITY" ]; then
    echo "Signing with identity: $SIGNING_IDENTITY"
    codesign --force --options runtime --entitlements PriType.entitlements --sign "$SIGNING_IDENTITY" "$APP_BUNDLE"
    echo "Signing complete."
else
    echo "No SIGNING_IDENTITY set and 'PriTypeDev' certificate not found."
    echo "Using ad-hoc signing. (Warning: Accessibility permissions will break on every build!)"
    codesign --force --deep --entitlements PriType.entitlements --sign - "$APP_BUNDLE"
fi

echo "Installing to $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALL_DIR/PriType.app"
rm -rf "$INSTALL_DIR/$APP_BUNDLE"
mv "$APP_BUNDLE" "$INSTALL_DIR/"

echo "Installation complete!"
echo "Please log out and log back in, or restart your computer."
echo "Then enable '$APP_NAME' in System Settings > Keyboard > Input Sources."
