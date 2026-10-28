#!/bin/bash
# Package only the local GUI. No engine, keys, accounts or user settings are bundled.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="${1:-$PROJECT_DIR/dist/NX Port Studio Local.app}"
case "$OUTPUT" in
    *.app) ;;
    *) printf '%s\n' 'The output must end in .app.' >&2; exit 1 ;;
esac
mkdir -p "$(dirname "$OUTPUT")"
OUTPUT="$(cd "$(dirname "$OUTPUT")" && pwd)/$(basename "$OUTPUT")"
if [ -e "$OUTPUT" ] || [ -L "$OUTPUT" ]; then
    printf '%s\n' 'Output exists; choose a new app path.' >&2
    exit 1
fi
# No remote Swift packages are declared. Refuse dependency resolution updates.
swift build --package-path "$PROJECT_DIR" -c release --arch arm64 --disable-automatic-resolution
BIN_DIR="$(swift build --package-path "$PROJECT_DIR" -c release --arch arm64 --show-bin-path)"
STAGING="$(mktemp -d "$(dirname "$OUTPUT")/.nx-port-studio.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
APP="$STAGING/NX Port Studio Local.app"
CONTENTS="$APP/Contents"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BIN_DIR/NXPortStudio" "$CONTENTS/MacOS/NXPortStudio"
cp "$PROJECT_DIR/../../LICENSE" "$CONTENTS/Resources/LICENSE"
xcrun swift "$PROJECT_DIR/scripts/GenerateIcon.swift" "$STAGING/AppIcon.iconset"
/usr/bin/iconutil -c icns "$STAGING/AppIcon.iconset" -o "$CONTENTS/Resources/AppIcon.icns"
cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>NX Port Studio Local</string>
<key>CFBundleDisplayName</key><string>NX Port Studio Local</string>
<key>CFBundleIdentifier</key><string>org.nxnative.portstudio.local</string>
<key>CFBundleExecutable</key><string>NXPortStudio</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSArchitecturePriority</key><array><string>arm64</string></array>
<key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
# Always local ad-hoc signing: never select an Apple identity from the user's Keychain.
/usr/bin/codesign --force --sign - "$APP"
/usr/bin/codesign --verify --strict "$APP"
mv "$APP" "$OUTPUT"
printf 'Created %s\nSelect your trusted local checkout in the app.\n' "$OUTPUT"
