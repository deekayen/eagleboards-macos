#!/usr/bin/env bash
# ------------------------------------------------------------------------
# build-app.sh -- build "Eagle Boards.app" from the Swift package.
#
#   scripts/build-app.sh                  # release build
#   VERSION=2026.09.22 scripts/build-app.sh
#   SIGNING_IDENTITY="Developer ID Application: ..." scripts/build-app.sh
#
# Output: build/Eagle Boards.app, for Apple silicon only. Intel Macs are not
# supported.
#
# Without SIGNING_IDENTITY the app is signed ad hoc. That runs on the Mac that
# built it; on another Mac, Gatekeeper stops it the first time, until it is
# allowed with Open Anyway in System Settings > Privacy & Security (right-click
# > Open also works on macOS 14, not on 15 or later). A Developer ID identity
# (and notarization) removes that step.
#
# Needs Xcode, or its command line tools, with Swift 6.
# ------------------------------------------------------------------------
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-$(date +%Y.%m.%d)}"
BUNDLE_ID="net.deekayen.EagleBoards"
APP="build/Eagle Boards.app"

echo "== building $VERSION for Apple silicon"
swift build -c release --arch arm64
bin_dir=$(swift build -c release --arch arm64 --show-bin-path)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$bin_dir/EagleBoards" "$APP/Contents/MacOS/Eagle Boards"
exe="$APP/Contents/MacOS/Eagle Boards"

# Swift libraries the binary loads through @rpath. SwiftPM leaves an absolute
# rpath into this Mac's Xcode toolchain, which exists on the build machine and
# on no other, so a Mac without it fails at launch with "Library not loaded".
# Copy each such library into Contents/Frameworks, drop the absolute rpaths,
# and point the binary at Frameworks after /usr/lib/swift, where macOS 26 and
# later keep their own copy. Apple: Notarizing macOS software before
# distribution, "Prepare your software for notarization" (every executable
# the app loads is signed and inside the bundle).
rpaths=$(otool -l "$exe" | awk '/cmd LC_RPATH/ {getline; getline; print $2}')
rpath_libs=$(otool -L "$exe" | awk '/@rpath\// {print $1}')
for lib in $rpath_libs; do
    name="${lib#@rpath/}"
    found=""
    while IFS= read -r dir; do
        case "$dir" in /*) [ -f "$dir/$name" ] && { found="$dir/$name"; break; } ;; esac
    done <<< "$rpaths"
    if [ -z "$found" ]; then
        # Resolved from the system (/usr/lib/swift) or beside the binary.
        [ -f "/usr/lib/swift/$name" ] || echo "note: $name is not found in any absolute rpath; the OS must provide it"
        continue
    fi
    mkdir -p "$APP/Contents/Frameworks"
    cp "$found" "$APP/Contents/Frameworks/$name"
    echo "== bundled $name from $found"
done
while IFS= read -r dir; do
    case "$dir" in /Applications/*|/Library/*|/Users/*) install_name_tool -delete_rpath "$dir" "$exe" ;; esac
done <<< "$rpaths"
if [ -d "$APP/Contents/Frameworks" ]; then
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$exe"
fi
# The sign-in pages. CheckInAssets looks here before anywhere else.
cp -R "$bin_dir/EagleBoards_CheckInServer.bundle" "$APP/Contents/Resources/"

# Drawn from Artwork/EagleBoards.svg by scripts/make-icon.sh.
cp Artwork/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# NSUserNotificationAlertStyle asks for Alerts as Eagle Boards' first
# notification style, so an overdue room's notification stays on screen
# behind another app. The style chosen in System Settings > Notifications
# wins, and macOS may ignore the key under the UserNotifications framework.
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
    <key>NSHumanReadableCopyright</key>     <string>Copyright 2026 David Norman. Apache License 2.0.</string>
    <key>NSUserNotificationAlertStyle</key> <string>alert</string>
    <key>NSLocalNetworkUsageDescription</key>
    <string>Eagle Boards serves the sign-in page to tablets at the door over your local network.</string>
    <key>NSDesktopFolderUsageDescription</key>
    <string>Eagle Boards keeps each event's sign-ins and results in the data folder you choose.</string>
    <key>NSDocumentsFolderUsageDescription</key>
    <string>Eagle Boards keeps each event's sign-ins and results in the data folder you choose.</string>
    <key>NSDownloadsFolderUsageDescription</key>
    <string>Eagle Boards keeps each event's sign-ins and results in the data folder you choose.</string>
    <key>NSRemovableVolumesUsageDescription</key>
    <string>Eagle Boards keeps each event's sign-ins and results in the data folder you choose.</string>
    <key>NSNetworkVolumesUsageDescription</key>
    <string>Eagle Boards keeps each event's sign-ins and results in the data folder you choose.</string>
</dict>
</plist>
PLIST

echo "== signing"
# Code inside the bundle is signed before the bundle. With the Hardened
# Runtime, library validation only loads a library signed by the app's own
# team, so the identity must match.
if [ -n "${SIGNING_IDENTITY:-}" ]; then
    for dylib in "$APP"/Contents/Frameworks/*.dylib; do
        [ -e "$dylib" ] || continue
        codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$dylib"
    done
    codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP"
else
    for dylib in "$APP"/Contents/Frameworks/*.dylib; do
        [ -e "$dylib" ] || continue
        codesign --force --sign - "$dylib"
    done
    codesign --force --sign - "$APP"
fi
codesign --verify --deep --strict --verbose=1 "$APP"

echo "== built $APP"
lipo -archs "$APP/Contents/MacOS/Eagle Boards"
