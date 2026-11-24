#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
APP="$PWD/build/Time Master.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/TimeMaster.icns "$APP/Contents/Resources/TimeMaster.icns"
xcrun swiftc -parse-as-library -swift-version 5 -target arm64-apple-macosx26.0 -O Sources/*.swift -o "$APP/Contents/MacOS/TimeMaster" -framework SwiftUI -framework AppKit
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleExecutable</key><string>TimeMaster</string><key>CFBundleIdentifier</key><string>local.timemaster.prototype</string><key>CFBundleName</key><string>Time Master</string><key>CFBundleIconFile</key><string>TimeMaster</string><key>CFBundleVersion</key><string>5</string><key>CFBundleShortVersionString</key><string>0.4.0</string><key>LSMinimumSystemVersion</key><string>26.0</string><key>LSUIElement</key><true/><key>NSHighResolutionCapable</key><true/></dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "$APP"
