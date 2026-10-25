#!/bin/bash
# builds TalkType.app with the endpoint + token baked in, zips it into the worker's private downloads.
set -euo pipefail
cd "$(dirname "$0")"
TOKEN="${FLOW_TOKEN:?set FLOW_TOKEN}"
ENDPOINT="${FLOW_ENDPOINT:?set FLOW_ENDPOINT, e.g. https://talktype.<you>.workers.dev/api/dictate}"
ORIGIN="${ENDPOINT%/api/dictate}"
APP_ID="${APP_ID:-com.example.talktype}"
VERSION="${VERSION:-1.0}"
OUT=build; APP="$OUT/TalkType.app"
rm -rf "$OUT"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$OUT/gen"
cat > "$OUT/gen/Config.swift" <<SW
enum Config {
    static let endpoint = "$ENDPOINT"
    static let token = "$TOKEN"
}
SW
swiftc -O -target arm64-apple-macos13.0 -o "$OUT/TalkType-arm64" Sources/main.swift "$OUT/gen/Config.swift"
swiftc -O -target x86_64-apple-macos13.0 -o "$OUT/TalkType-x86" Sources/main.swift "$OUT/gen/Config.swift"
lipo -create "$OUT/TalkType-arm64" "$OUT/TalkType-x86" -output "$APP/Contents/MacOS/TalkType"
cat > "$APP/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>TalkType</string>
  <key>CFBundleDisplayName</key><string>TalkType</string>
  <key>CFBundleIdentifier</key><string>$APP_ID</string>
  <key>CFBundleExecutable</key><string>TalkType</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>TalkType listens while you hold the hotkey so it can type what you say.</string>
</dict></plist>
PL
codesign --force --deep --sign - --identifier $APP_ID "$APP"
DEST=../worker/public/files; mkdir -p "$DEST"
(cd "$OUT" && ditto -c -k --keepParent "TalkType.app" TalkType.zip)
cp "$OUT/TalkType.zip" "$DEST/TalkType.zip"
cat > "$DEST/install-mac.sh" <<SH
#!/bin/bash
# TalkType installer: downloads the app, puts it in /Applications, opens it.
set -e
pkill -x TalkType 2>/dev/null || true
TMP=\$(mktemp -d)
curl -fsSL "$ORIGIN/dl/$TOKEN/TalkType.zip" -o "\$TMP/TalkType.zip"
rm -rf "/Applications/TalkType.app"
ditto -x -k "\$TMP/TalkType.zip" /Applications
xattr -dr com.apple.quarantine "/Applications/TalkType.app" 2>/dev/null || true
tccutil reset Accessibility $APP_ID >/dev/null 2>&1 || true
open "/Applications/TalkType.app"
echo "talktype installed. allow microphone + accessibility when macOS asks, then hold right option and talk."
SH
echo built; ls -la "$DEST"
