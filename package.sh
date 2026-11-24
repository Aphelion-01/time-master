#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
APP="$PWD/build/Time Master.app"
OUTPUT_DIR="${1:-$PWD/build/releases}"
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="${OUTPUT_DIR:A}"
STAGE_DIR=$(mktemp -d)
trap 'rm -rf "$STAGE_DIR"' EXIT
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
NAME="Time-Master-${VERSION}-arm64.dmg"
codesign --verify --deep --strict "$APP"
ditto "$APP" "$STAGE_DIR/Time Master.app"
ln -s /Applications "$STAGE_DIR/Applications"
cp 安装说明.txt "$STAGE_DIR/安装说明.txt"
hdiutil create -volname "Time Master $VERSION" -srcfolder "$STAGE_DIR" -format UDZO -imagekey zlib-level=9 -ov "$OUTPUT_DIR/$NAME"
hdiutil verify "$OUTPUT_DIR/$NAME"
(cd "$OUTPUT_DIR" && shasum -a 256 "$NAME" > "$NAME.sha256")
echo "$OUTPUT_DIR/$NAME"
