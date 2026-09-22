#!/usr/bin/env bash
# ------------------------------------------------------------------------
# build-app.sh -- build "Eagle Boards.app" from the Swift package.
#
#   scripts/build-app.sh                  # universal (Apple silicon + Intel), release
#   ARCHS=arm64 scripts/build-app.sh      # this Mac's architecture only, faster
#   VERSION=2026.09.22 scripts/build-app.sh
#   SIGNING_IDENTITY="Developer ID Application: ..." scripts/build-app.sh
#
# Output: build/Eagle Boards.app
#
# Without SIGNING_IDENTITY the app is signed ad hoc. That runs on the Mac that
# built it; on another Mac, Gatekeeper asks for a right-click > Open the first
# time. A Developer ID identity (and notarization) removes that step.
#
# Needs Xcode, or its command line tools, with Swift 6.
# ------------------------------------------------------------------------
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-$(date +%Y.%m.%d)}"
ARCHS="${ARCHS:-arm64 x86_64}"
BUNDLE_ID="net.deekayen.EagleBoards"
APP="build/Eagle Boards.app"

arch_flags=()
for arch in $ARCHS; do
    arch_flags+=(--arch "$arch")
done

echo "== building $VERSION for: $ARCHS"
swift build -c release "${arch_flags[@]}"
bin_dir=$(swift build -c release "${arch_flags[@]}" --show-bin-path)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$bin_dir/EagleBoards" "$APP/Contents/MacOS/Eagle Boards"
# The sign-in pages. CheckInAssets looks here before anywhere else.
cp -R "$bin_dir/EagleBoards_CheckInServer.bundle" "$APP/Contents/Resources/"

echo "== drawing the icon"
iconset="build/AppIcon.iconset"
rm -rf "$iconset"
swift scripts/make-icon.swift "$iconset"
iconutil -c icns "$iconset" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>                 <string>Eagle Boards</string>
    <key>CFBundleDisplayName</key>          <string>Eagle Boards</string>
    <key>CFBundleExecutable</key>           <string>Eagle Boards</string>
    <key>CFBundleIdentifier</key>           <string>$BUNDLE_ID</string>
    <key>CFBundleIconFile</key>             <string>AppIcon</string>
    <key>CFBundlePackageType</key>          <string>APPL</string>
    <key>CFBundleShortVersionString</key>   <string>$VERSION</string>
    <key>CFBundleVersion</key>              <string>$VERSION</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>LSMinimumSystemVersion</key>       <string>14.0</string>
    <key>LSApplicationCategoryType</key>    <string>public.app-category.productivity</string>
    <key>NSHighResolutionCapable</key>      <true/>
    <key>NSHumanReadableCopyright</key>     <string>Licensed under the Apache License, Version 2.0.</string>
    <key>NSLocalNetworkUsageDescription</key>
    <string>Eagle Boards serves the sign-in page to tablets at the door over your local network.</string>
</dict>
</plist>
PLIST

echo "== signing"
if [ -n "${SIGNING_IDENTITY:-}" ]; then
    codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP"
else
    codesign --force --sign - "$APP"
fi
codesign --verify --strict --verbose=1 "$APP"

echo "== built $APP"
lipo -archs "$APP/Contents/MacOS/Eagle Boards"
