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

# Optional: Icon
cp icon.png "$RESOURCES_DIR/" 2>/dev/null || echo "No icon found, skipping."

echo "Installing to $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALL_DIR/PriType.app"
rm -rf "$INSTALL_DIR/$APP_BUNDLE"
mv "$APP_BUNDLE" "$INSTALL_DIR/"

echo "Installation complete!"
echo "Please log out and log back in, or restart your computer."
echo "Then enable '$APP_NAME' in System Settings > Keyboard > Input Sources."
