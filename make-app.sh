#!/bin/zsh
# Builds Pinger.app into ./dist
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP=dist/Pinger.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/Pinger "$APP/Contents/MacOS/Pinger"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

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
    <string>com.fruitcc.pinger</string>
    <key>CFBundleExecutable</key>
    <string>Pinger</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.2.1</string>
    <key>CFBundleVersion</key>
    <string>4</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>ITSAppUsesNonExemptEncryption</key>
    <false/>
    <key>NSHumanReadableCopyright</key>
    <string>© 2026 Fruit Cloud Co., LLC</string>
</dict>
</plist>
PLIST

# Ad-hoc signature with the same sandbox entitlements as the App Store build,
# so local runs exercise the sandboxed code paths.
codesign --force --sign - --entitlements Pinger.entitlements "$APP"

echo "Built $APP"
echo "Run it with: open $APP"
