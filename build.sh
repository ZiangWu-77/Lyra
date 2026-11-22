#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_PATH="${1:-$PROJECT_DIR/../Lyra.app}"
BUILD_DIR="$PROJECT_DIR/.build"
mkdir -p "$BUILD_DIR" "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
xcrun clang -O2 -Wno-deprecated-declarations -c "$PROJECT_DIR/Sources/OfflineGate.c" -o "$BUILD_DIR/OfflineGate.o"
xcrun swiftc -O -swift-version 5 -import-objc-header "$PROJECT_DIR/Sources/OfflineGate.h" \
  "$PROJECT_DIR/Sources/main.swift" "$PROJECT_DIR/Sources/InputRouting.swift" "$PROJECT_DIR/Sources/TypingMusicPlayer.swift" "$BUILD_DIR/OfflineGate.o" \
  -framework AppKit -framework AVFoundation -framework CoreGraphics -framework ServiceManagement \
  -o "$APP_PATH/Contents/MacOS/Lyra"
cp -R "$PROJECT_DIR/Resources/." "$APP_PATH/Contents/Resources/"
cat > "$APP_PATH/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Lyra</string>
<key>CFBundleDisplayName</key><string>Lyra · 天琴座</string>
<key>CFBundleIdentifier</key><string>local.luka.keytone</string>
<key>CFBundleExecutable</key><string>Lyra</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.4.3</string>
<key>CFBundleVersion</key><string>9</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSInputMonitoringUsageDescription</key><string>仅在本机根据物理按键及启用后的鼠标点击播放声音，不保存输入，不联网。</string>
<key>NSHumanReadableCopyright</key><string>Lyra local project. Bundled sounds: Mechvibes, MIT; see Resources/Mechvibes-LICENSE.txt.</string>
</dict></plist>
PLIST
codesign --force --sign - --options runtime "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"
xcrun clang -O2 -Wno-deprecated-declarations "$PROJECT_DIR/Tests/NetworkProbe.c" "$BUILD_DIR/OfflineGate.o" -o "$BUILD_DIR/network-probe"
xcrun swiftc -swift-version 5 "$PROJECT_DIR/Sources/InputRouting.swift" "$PROJECT_DIR/Tests/InputRoutingTests.swift" -framework CoreGraphics -o "$BUILD_DIR/input-routing-tests"
"$BUILD_DIR/input-routing-tests"
"$BUILD_DIR/network-probe"
"$APP_PATH/Contents/MacOS/Lyra" --verify-assets
xcrun swiftc -swift-version 5 -import-objc-header "$PROJECT_DIR/Sources/OfflineGate.h" \
  "$PROJECT_DIR/Sources/TypingMusicPlayer.swift" "$PROJECT_DIR/Tests/MusicPlaybackTests.swift" \
  "$BUILD_DIR/OfflineGate.o" -framework AVFoundation -o "$BUILD_DIR/music-playback-tests"
"$BUILD_DIR/music-playback-tests" "$APP_PATH/Contents/Resources/Music/beethoven5.wav"
printf 'Built and verified: %s\n' "$APP_PATH"
