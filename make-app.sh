#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

CONFIG="${1:-release}"
if [[ "$CONFIG" != "debug" && "$CONFIG" != "release" ]]; then
    echo "Usage: $0 [debug|release]"
    exit 1
fi

echo "[niri-mac] Building ($CONFIG)..."
swift build -c "$CONFIG" 2>&1

BINARY=".build/$CONFIG/NiriMac"
APP="NiriMac.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "[niri-mac] Creating .app bundle..."
rm -rf "$APP"
mkdir -p "$MACOS" "$RESOURCES"

cp "$BINARY" "$MACOS/NiriMac"

if [[ -f "NiriMac.icns" ]]; then
    cp "NiriMac.icns" "$RESOURCES/NiriMac.icns"
fi

BUILD_DATE=$(date '+%Y-%m-%d %H:%M:%S')

cat > "$CONTENTS/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.fscoward.niri-mac</string>
    <key>CFBundleName</key>
    <string>NiriMac</string>
    <key>CFBundleExecutable</key>
    <string>NiriMac</string>
    <key>CFBundleVersion</key>
    <string>0.1.4</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.4</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <true/>
    <key>BuildDate</key>
    <string>${BUILD_DATE} (${CONFIG})</string>
    <key>NSAccessibilityUsageDescription</key>
    <string>NiriMac needs Accessibility access to manage window positions.</string>
    <key>NSInputMonitoringUsageDescription</key>
    <string>NiriMac needs Input Monitoring access to capture keyboard shortcuts.</string>
    <key>CFBundleIconFile</key>
    <string>NiriMac</string>
</dict>
</plist>
EOF

echo "[niri-mac] Signing .app bundle..."
codesign --force --deep --sign - "$APP"
echo "[niri-mac] ✅ NiriMac.app を作成しました"
echo ""
echo "初回起動前に以下を行ってください:"
echo "  1. open NiriMac.app  で起動"
echo "  2. システム設定 > プライバシー > アクセシビリティ に NiriMac.app を追加"
echo "  3. システム設定 > プライバシー > 入力監視 に NiriMac.app を追加"
echo "  4. アプリを再起動"
echo ""
echo "起動するには: open NiriMac.app"
