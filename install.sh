#!/bin/bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: ./install.sh [--as-patchtype]

  (default)          Install as PriTypeV2 using the source-tree identity.
  --as-patchtype     Install as PatchType / 패치타입 with a distinct bundle id
                     and version 2.7.4-patch.1 so it cannot be confused with
                     official PriType 2.7.4. Copies to /Library/Input Methods
                     only (never also ~/Library). A new bundle id usually
                     needs a logout before it appears in Input Sources.
EOF
}

AS_PATCHTYPE=0
for arg in "$@"; do
    case "$arg" in
        --as-patchtype) AS_PATCHTYPE=1 ;;
        -h|--help) usage; exit 0 ;;
        *)
            echo "Unknown argument: $arg" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [ "$AS_PATCHTYPE" -eq 1 ]; then
    APP_NAME="PatchType"
    EXEC_NAME="PatchType"
    SYSTEM_ONLY=1
else
    APP_NAME="PriTypeV2"
    EXEC_NAME="PriTypeV2"
    SYSTEM_ONLY=0
fi

BUILD_DIR=".build/release"
STAGE_DIR=".build/ime-bundle"
APP_BUNDLE="${STAGE_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
USER_INSTALL_DIR="$HOME/Library/Input Methods"
SYSTEM_INSTALL_DIR="/Library/Input Methods"
USER_BUNDLE="${USER_INSTALL_DIR}/${APP_NAME}.app"
SYSTEM_BUNDLE="${SYSTEM_INSTALL_DIR}/${APP_NAME}.app"
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"

apply_patchtype_identity() {
    python3 - "$1" <<'PY'
import plistlib
import sys

path = sys.argv[1]
old = "com.pritype.inputmethod.v2"
new = "com.calvinjkim.patchtype"

with open(path, "rb") as handle:
    info = plistlib.load(handle)

modes = info.get("ComponentInputModeDict", {}).get("tsInputModeListKey", {})
rewritten = {}
for key, value in modes.items():
    rewritten[key.replace(old, new)] = value
info.setdefault("ComponentInputModeDict", {})["tsInputModeListKey"] = rewritten
info["ComponentInputModeDict"]["tsVisibleInputModeOrderedArrayKey"] = [f"{new}.korean"]

info["CFBundleDisplayName"] = "PatchType"
info["CFBundleName"] = "PatchType"
info["CFBundleExecutable"] = "PatchType"
info["CFBundleIdentifier"] = new
info["CFBundleShortVersionString"] = "2.7.4-patch.1"
info["CFBundleVersion"] = "51"
info["InputMethodConnectionName"] = "PatchType_InputString"
info["PriTypeReleaseChannel"] = "local"

with open(path, "wb") as handle:
    plistlib.dump(info, handle, sort_keys=False)
PY

    mkdir -p "$RESOURCES_DIR/en.lproj" "$RESOURCES_DIR/ko.lproj"
    cat > "$RESOURCES_DIR/en.lproj/InfoPlist.strings" <<'EOF'
/* Localized versions of Info.plist keys */
"CFBundleName" = "PatchType";
"CFBundleDisplayName" = "PatchType";
"com.calvinjkim.patchtype" = "PatchType";
"com.calvinjkim.patchtype.korean" = "Patch Korean";
"com.calvinjkim.patchtype.english" = "Patch English";
EOF
    cat > "$RESOURCES_DIR/ko.lproj/InfoPlist.strings" <<'EOF'
/* Localized versions of Info.plist keys */
"CFBundleName" = "패치타입";
"CFBundleDisplayName" = "패치타입";
"com.calvinjkim.patchtype" = "패치타입";
"com.calvinjkim.patchtype.korean" = "패치 한글";
"com.calvinjkim.patchtype.english" = "패치 영어";
EOF
}

copy_to_system() {
    local src="$1"
    local dest="$2"
    if sudo -n true 2>/dev/null; then
        sudo ditto "$src" "$dest"
        sudo rm -rf \
            "/Library/Input Methods/PriTypeV2.app" \
            "/Library/Input Methods/PriType.app" \
            "/tmp/PriTypeV2.app.disabled"
        return 0
    fi

    echo "Administrator access is required to install into /Library/Input Methods."
    echo "A password dialog may appear."
    osascript - "$src" "$dest" <<'APPLESCRIPT'
on run argv
    set src to item 1 of argv
    set dest to item 2 of argv
    do shell script "ditto " & quoted form of src & " " & quoted form of dest & " && rm -rf '/Library/Input Methods/PriTypeV2.app' '/Library/Input Methods/PriType.app' '/tmp/PriTypeV2.app.disabled'" with administrator privileges
end run
APPLESCRIPT
}

echo "Building release..."
swift build -c release --product PriType

echo "Creating bundle structure at $APP_BUNDLE..."
rm -rf "$STAGE_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

echo "Copying executable..."
cp "$BUILD_DIR/PriType" "$MACOS_DIR/$EXEC_NAME"

echo "Copying Info.plist..."
cp Info.plist "$CONTENTS_DIR/"

cp -R Resources/* "$RESOURCES_DIR/" 2>/dev/null || true
cp "AppIcon.icns" "$RESOURCES_DIR/" 2>/dev/null || echo "No AppIcon.icns found"
cp "icon.tiff" "$RESOURCES_DIR/" 2>/dev/null || echo "No icon.tiff found, skipping."
cp "input-ko.tiff" "$RESOURCES_DIR/" 2>/dev/null || echo "No input-ko.tiff found, skipping."
cp "input-en.tiff" "$RESOURCES_DIR/" 2>/dev/null || echo "No input-en.tiff found, skipping."

if [ -d "$BUILD_DIR/PriType_PriTypeCore.bundle" ]; then
    cp -R "$BUILD_DIR/PriType_PriTypeCore.bundle" "$RESOURCES_DIR/"
    echo "Copied PriType_PriTypeCore.bundle"
else
    echo "Warning: PriType_PriTypeCore.bundle not found"
fi

if [ "$AS_PATCHTYPE" -eq 1 ]; then
    echo "Applying PatchType identity (not official PriType 2.7.4)..."
    apply_patchtype_identity "$CONTENTS_DIR/Info.plist"
fi

if [ -z "${SIGNING_IDENTITY:-}" ]; then
    APPLE_DEV_CERT=$(security find-identity -v -p codesigning | grep "Apple Development:" | head -n 1 | awk -F'"' '{print $2}' || true)
    if [ -n "$APPLE_DEV_CERT" ]; then
        SIGNING_IDENTITY="$APPLE_DEV_CERT"
    elif security find-certificate -c "PriTypeDev" > /dev/null 2>&1; then
        SIGNING_IDENTITY="PriTypeDev"
    fi
fi

if [ -n "${SIGNING_IDENTITY:-}" ]; then
    echo "Signing with identity: $SIGNING_IDENTITY"
    codesign --force --sign "$SIGNING_IDENTITY" "$APP_BUNDLE"
    echo "Signing complete."
else
    echo "No SIGNING_IDENTITY set and 'PriTypeDev' certificate not found."
    echo "Using ad-hoc signing. (Warning: Accessibility permissions will break on every build!)"
    codesign --force --deep --sign - "$APP_BUNDLE"
fi

killall PriTypeV2 PatchType PriType 2>/dev/null || true

if [ "$SYSTEM_ONLY" -eq 1 ]; then
    echo "Installing to $SYSTEM_BUNDLE (system copy only)..."
    mkdir -p "$USER_INSTALL_DIR"
    rm -rf \
        "$USER_INSTALL_DIR/PriType.app" \
        "$USER_INSTALL_DIR/PriTypeV2.app" \
        "$USER_INSTALL_DIR/PatchType.app"
    copy_to_system "$APP_BUNDLE" "$SYSTEM_BUNDLE"
    INSTALL_PATH="$SYSTEM_BUNDLE"
else
    echo "Installing to $USER_BUNDLE..."
    mkdir -p "$USER_INSTALL_DIR"
    rm -rf "$USER_INSTALL_DIR/PriType.app"
    rm -rf "$USER_INSTALL_DIR/PriTypeV2.app"
    rm -rf "$USER_BUNDLE"
    ditto "$APP_BUNDLE" "$USER_BUNDLE"
    INSTALL_PATH="$USER_BUNDLE"

    if [ -d "$SYSTEM_INSTALL_DIR/${APP_NAME}.app" ] && [ -d "$USER_BUNDLE" ]; then
        echo ""
        echo "WARNING: ${APP_NAME} is installed in TWO places:"
        echo "  $USER_BUNDLE"
        echo "  $SYSTEM_INSTALL_DIR/${APP_NAME}.app"
        echo "macOS then lists the IME many times in Input Sources (one row per"
        echo "copy × parent/Korean/English). Keep a single copy."
    fi
fi

xattr -cr "$INSTALL_PATH" 2>/dev/null || true
killall TextInputMenuAgent TextInputSwitcher keyboardservicesd imklaunchagent PriTypeV2 PatchType 2>/dev/null || true

echo "Installation complete: $INSTALL_PATH"
if [ "$AS_PATCHTYPE" -eq 1 ]; then
    echo "Name: PatchType / 패치타입"
    echo "Version: 2.7.4-patch.1 (local patch)  — not official PriType 2.7.4"
    echo "Bundle ID: com.calvinjkim.patchtype"
    echo "Log out and back in, then enable '패치 한글' (Patch Korean) under"
    echo "System Settings > Keyboard > Input Sources. Do not add every row"
    echo "from '모든 입력 소스'. Apple 2-Set Korean can stay as a fallback."
else
    echo "Please log out and log back in, or restart your computer."
    echo "Then enable '$APP_NAME' in System Settings > Keyboard > Input Sources."
fi
