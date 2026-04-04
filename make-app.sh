#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "[niri-mac] Building..."
swift build 2>&1

BINARY=".build/debug/NiriMac"
APP="NiriMac.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"

echo "[niri-mac] Creating .app bundle..."
rm -rf "$APP"
mkdir -p "$MACOS"

cp "$BINARY" "$MACOS/NiriMac"

cat > "$CONTENTS/Info.plist" << 'EOF'
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
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSAccessibilityUsageDescription</key>
    <string>NiriMac needs Accessibility access to manage window positions.</string>
    <key>NSInputMonitoringUsageDescription</key>
    <string>NiriMac needs Input Monitoring access to capture keyboard shortcuts.</string>
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
