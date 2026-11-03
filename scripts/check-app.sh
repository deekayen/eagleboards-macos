#!/usr/bin/env bash
# ------------------------------------------------------------------------
# check-app.sh -- check a built "Eagle Boards.app", then launch it.
#
#   scripts/check-app.sh "build/Eagle Boards.app"
#   scripts/check-app.sh "build/Eagle Boards.app" 18124   # another port
#   EXPECT_VERSION=2026.11.05 scripts/check-app.sh "$app"
#
# Run by build.yml on the bundle scripts/build-app.sh just built, and by
# release.yml twice: on that bundle, and on a copy unzipped from the zip that
# is about to ship, on the oldest macOS the release claims. Nothing here
# depends on where the app came from, so it works on either.
#
# Part 1 looks inside the bundle: Apple silicon only, a valid Info.plist and
# signature, no library loaded from outside the bundle, the icon, the sign-in
# pages, the third-party notices, and no data files. Part 2 launches the app on
# an empty scratch folder, signs a youth in over HTTP the way a tablet would,
# and reads the result back off disk.
#
# The port is the second argument, else CHECK_APP_PORT, else 18123, so two
# runs on one Mac never share one. EXPECT_VERSION, when set, must equal the
# bundle's CFBundleShortVersionString.
#
# One thing this cannot test: a zip downloaded through a browser carries a
# quarantine mark, and Gatekeeper's Open Anyway path only runs for that. CI's
# copy has none. Open the published zip once on a Mac that did not build it.
# ------------------------------------------------------------------------
set -euo pipefail

# What Info.plist must say; build-app.sh writes it. Change both together, and
# the macOS claim in README.md, CONTRIBUTING.md and the release notes with them.
min_macos="15.0"

app="${1:?usage: scripts/check-app.sh <path to Eagle Boards.app> [port]}"
port="${2:-${CHECK_APP_PORT:-18123}}"
exe="$app/Contents/MacOS/Eagle Boards"
plist="$app/Contents/Info.plist"

app_pid=""
work=""
cleanup() {
    if [ -n "$app_pid" ]; then
        kill "$app_pid" 2>/dev/null || true
        wait "$app_pid" 2>/dev/null || true
    fi
    if [ -n "$work" ]; then
        rm -rf "$work"
    fi
}
trap cleanup EXIT

# An error line GitHub Actions shows on the run; plain text elsewhere. The
# app's output follows once the app has been launched.
fail() {
    if [ -n "${GITHUB_ACTIONS:-}" ]; then
        echo "::error::$1"
    else
        echo "error: $1" >&2
    fi
    if [ -n "$work" ] && [ -f "$work/app.log" ]; then
        echo "---- app output" >&2
        cat "$work/app.log" >&2
    fi
    exit 1
}

[ -d "$app" ] || fail "no app at $app"
[ -x "$exe" ] || fail "no executable at $exe"
work=$(mktemp -d)

echo "== checking $app"

# Apple silicon only; Intel Macs are not supported.
archs=$(lipo -archs "$exe")
echo "architectures: $archs"
[ "$archs" = "arm64" ] || fail "expected arm64 only, found: $archs"

plutil -lint "$plist" >/dev/null || fail "Info.plist is not valid"
min=$(plutil -extract LSMinimumSystemVersion raw -o - "$plist")
[ "$min" = "$min_macos" ] || fail "LSMinimumSystemVersion is $min, expected $min_macos"
if [ -n "${EXPECT_VERSION:-}" ]; then
    version=$(plutil -extract CFBundleShortVersionString raw -o - "$plist")
    [ "$version" = "$EXPECT_VERSION" ] || fail "CFBundleShortVersionString is $version, expected $EXPECT_VERSION"
fi

codesign --verify --deep --strict --verbose=1 "$app" || fail "the code signature does not verify"

# The launch below runs on the machine that built the app, so a library found
# only through that machine's Xcode would pass it and fail on every other Mac.
# Nothing may load from outside the bundle.
if otool -l "$exe" | awk '/cmd LC_RPATH/ {getline; getline; print $2}' | grep -E '^/(Applications|Library|Users)/'; then
    fail "the binary keeps an rpath into the build machine"
fi
for lib in $(otool -L "$exe" | awk '/@rpath\// {print $1}'); do
    [ -f "$app/Contents/Frameworks/${lib#@rpath/}" ] \
        || fail "$lib is loaded through @rpath but is not in Contents/Frameworks"
done

# The icon unpacks, with every size macOS asks for.
iconutil -c iconset "$app/Contents/Resources/AppIcon.icns" -o "$work/AppIcon.iconset" \
    || fail "AppIcon.icns does not unpack"
[ "$(find "$work/AppIcon.iconset" -name '*.png' | wc -l | tr -d ' ')" = 10 ] \
    || fail "AppIcon.icns is missing sizes"

for page in index.html youth_register.html adult_register.html checkin.css checkin.js; do
    find "$app/Contents/Resources/EagleBoards_CheckInServer.bundle" -name "$page" | grep -q . \
        || fail "$page missing from the bundle"
done

# Apache 2.0 section 4: the dependencies' license text travels with the app.
[ -s "$app/Contents/Resources/THIRD-PARTY-NOTICES.txt" ] \
    || fail "Contents/Resources/THIRD-PARTY-NOTICES.txt is missing or empty"

if find "$app" -iname '*.csv' -o -iname '*.properties' -o -iname '*.xls*' | grep .; then
    fail "the app carries data files"
fi
echo "bundle checks passed"

# EAGLEBOARDS_DATA_FOLDER also switches SignUpGenius off, so this run reads no
# keychain item and imports nothing.
echo "== launching on port $port"
data="$work/data"
mkdir "$data"
base="http://127.0.0.1:$port"
if curl -s -m 2 -o /dev/null "$base/"; then
    fail "port $port is already in use; pass another as the second argument"
fi
EAGLEBOARDS_DATA_FOLDER="$data" EAGLEBOARDS_PORT="$port" "$exe" > "$work/app.log" 2>&1 &
app_pid=$!
up=""
for _ in $(seq 1 60); do
    kill -0 "$app_pid" 2>/dev/null || fail "the app exited during launch"
    if curl -sf -m 5 -o /dev/null "$base/"; then
        up=yes
        break
    fi
    sleep 1
done
[ -n "$up" ] || fail "the app did not serve the sign-in page within 60 seconds"

status() { curl -s -m 10 -o /dev/null -w '%{http_code}' "$@"; }
[ "$(status "$base/")" = 200 ] || fail "sign-in page not served"
[ "$(status "$base/admin")" = 404 ] || fail "/admin must not exist"
[ "$(status "$base/adult-history-cells")" = 404 ] || fail "record endpoints must not exist"
[ "$(status --data 'First=Casey&Last=Smoketest&UnitType=Troop&Unit=1&BoardType=Final&Email=NONE' "$base/register-youth")" = 200 ] \
    || fail "registration refused"

scouts=$(find "$data" -name scouts.csv | head -1)
[ -n "$scouts" ] || fail "registration not written to disk"
grep -q 'SCOUT:Smoketest:Casey:1' "$scouts" || fail "registration not written to disk"
head -1 "$scouts" | grep -q '^Type,ID,RegNum,Last,First,' || fail "scouts.csv header changed"

echo "smoke test passed"
