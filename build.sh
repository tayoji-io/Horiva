#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
HORIVA_VERSION="${HORIVA_VERSION:-$(cat VERSION)}"
HORIVA_BUILD_NUMBER="${HORIVA_BUILD_NUMBER:-7}"
if [[ ! "$HORIVA_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "HORIVA_VERSION must be a numeric version such as 1.4.0" >&2
    exit 1
fi
if [[ ! "$HORIVA_BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
    echo "HORIVA_BUILD_NUMBER must be a positive integer" >&2
    exit 1
fi
HORIVA_ARCH="$(uname -m)"
./scripts/build_icon.sh
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="dist/Horiva.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Horiva" "$APP/Contents/MacOS/Horiva"
cp Assets/Brand/Horiva.icns "$APP/Contents/Resources/Horiva.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Horiva</string>
<key>CFBundleIdentifier</key><string>local.zonebar.clock</string>
<key>CFBundleName</key><string>Horiva</string>
<key>CFBundleDisplayName</key><string>时屿 · Horiva</string>
<key>CFBundleIconFile</key><string>Horiva.icns</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.4.0</string>
<key>CFBundleVersion</key><string>7</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $HORIVA_VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $HORIVA_BUILD_NUMBER" "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
PACKAGE="dist/Horiva-${HORIVA_VERSION}-macOS-${HORIVA_ARCH}.zip"
/usr/bin/ditto -c -k --keepParent "$APP" "$PACKAGE"
cp "$PACKAGE" dist/Horiva.zip
/usr/bin/ditto -c -k --keepParent Assets/Brand dist/Horiva-Brand.zip
printf 'Built %s\n' "$PWD/$APP"
