#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

echo "Building release binary..."
swift build -c release

APP_DIR="dist/OneBigFile.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
cp ".build/release/OneBigFile" "$APP_DIR/Contents/MacOS/OneBigFile"

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>OneBigFile</string>
    <key>CFBundleIdentifier</key>
    <string>com.obf.OneBigFile</string>
    <key>CFBundleName</key>
    <string>OneBigFile</string>
    <key>CFBundleDisplayName</key>
    <string>One Big File</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP_DIR"
echo "Done: $APP_DIR"
