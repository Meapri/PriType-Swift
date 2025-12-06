#!/bin/bash
set -e

# Configuration
APP_NAME="PriTypeV2"
APP_BUNDLE="${APP_NAME}.app"
ZIP_NAME="${APP_NAME}.zip"
SIGNING_IDENTITY="Developer ID Application: Chanwoo Park (M4U438VG59)"
TEAM_ID="M4U438VG59" # Extracted from cert

# Credentials (Set these securely in env, or script will prompt)
# KEYCHAIN_PROFILE="PriTypeNotary" 

echo "==== 1. Clean & Build ===="
./install.sh # This builds and copies to ./Resources/PriTypeV2.app locally first? No, install.sh installs to ~/Library...
# Let's extract build logic or just use swift build
swift build -c release -Xswiftc -DNDEBUG
mkdir -p build_dist/Contents/MacOS
mkdir -p build_dist/Contents/Resources
cp .build/release/PriType build_dist/Contents/MacOS/PriTypeV2
cp Info.plist build_dist/Contents/
cp -R Resources/* build_dist/Contents/Resources/ || true
cp "AppIcon.icns" build_dist/Contents/Resources/ 2>/dev/null || true
cp "icon.tiff" build_dist/Contents/Resources/ 2>/dev/null || true


# Rename to .app
rm -rf "$APP_BUNDLE"
mv build_dist "$APP_BUNDLE"

echo "==== 2. Code Signing ===="
echo "Signing with $SIGNING_IDENTITY..."
codesign --force --options runtime --timestamp --entitlements "PriType.entitlements" --sign "$SIGNING_IDENTITY" "$APP_BUNDLE"

echo "==== 3. Verifying Signature ===="
codesign -vv -d "$APP_BUNDLE"

echo "==== 4. Archiving for Notarization ===="
# Must use zip or dmg for notary service
ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_NAME"
echo "Created $ZIP_NAME"

echo "==== 5. Notarization ===="
echo "To notarize, you need an App-Specific Password."
echo "1. Go to appleid.apple.com -> Sign-In and Security -> App-Specific Passwords -> Generate."
echo "2. Create a keychain profile (one-time setup):"
echo "   xcrun notarytool store-credentials \"PriTypeNotary\" --apple-id \"YOUR_EMAIL\" --team-id \"$TEAM_ID\" --password \"YOUR_APP_SPECIFIC_PASSWORD\""
echo "3. Run this script again with NOTARIZE=true"

if [ "$NOTARIZE" = "true" ]; then
    echo "Submitting to Apple Notary Service..."
    xcrun notarytool submit "$ZIP_NAME" --keychain-profile "PriTypeNotary" --wait
    
    echo "Stapling ticket..."
    xcrun stapler staple "$APP_BUNDLE"
    
    echo "Done! You can now verify standard Gatekeeper acceptance:"
    spctl --assess --type execute --verbose --ignore-cache "$APP_BUNDLE"
    
    # Re-zip stapled app
    ditto -c -k --keepParent "$APP_BUNDLE" "PriType_Notarized.zip"
    echo "Final distribution file: PriType_Notarized.zip"
fi
