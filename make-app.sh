#!/bin/zsh
# Builds Pinger.app into ./dist
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP=dist/Pinger.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cp .build/release/Pinger "$APP/Contents/MacOS/Pinger"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Pinger</string>
    <key>CFBundleDisplayName</key>
    <string>Pinger</string>
    <key>CFBundleIdentifier</key>
    <string>com.local.pinger</string>
    <key>CFBundleExecutable</key>
    <string>Pinger</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string></string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"

echo "Built $APP"
echo "Run it with: open $APP"
