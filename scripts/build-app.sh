#!/bin/zsh
set -euo pipefail
ROOT=${0:A:h:h}
cd "$ROOT"
swift build -c release --product Lecture
BIN_DIR=$(swift build -c release --show-bin-path)
APP="$ROOT/dist/Lecture.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Lecture" "$APP/Contents/MacOS/Lecture"
cp -R "$BIN_DIR/Lecture_LectureApp.bundle" "$APP/Contents/Resources/Lecture_LectureApp.bundle"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Lecture</string>
  <key>CFBundleDisplayName</key><string>Lecture</string>
  <key>CFBundleIdentifier</key><string>com.jiyuanyi.Lecture</string>
  <key>CFBundleExecutable</key><string>Lecture</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>26.4</string>
  <key>LSUIElement</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>Lecture 使用麦克风在本机录制课堂并实时识别英文。</string>
  <key>NSSpeechRecognitionUsageDescription</key><string>Lecture 使用 macOS 本地语音识别生成课堂英文逐字稿。</string>
</dict></plist>
PLIST
codesign \
  --force \
  --deep \
  --sign - \
  --requirements '=designated => identifier "com.jiyuanyi.Lecture"' \
  "$APP" >/dev/null
echo "$APP"
