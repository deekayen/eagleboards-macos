#!/usr/bin/env bash
# ------------------------------------------------------------------------
# make-icon.sh -- rebuild Artwork/AppIcon.icns from Artwork/EagleBoards.svg.
#
#   scripts/make-icon.sh
#
# EagleBoards.svg is the cast eagle from the Eagle Scout medal, the same
# drawing as the Windows version's icon; keep the two in step. Its metal
# finish is an SVG lighting filter, which macOS's own SVG support ignores, so
# this renders it with librsvg (brew install librsvg) and commits the .icns:
# building the app needs no drawing tools. Run this after changing the SVG.
#
# Mac icons sit on a rounded tile, so the eagle goes on the olive tile with
# the tan border, the palette of the sign-in pages.
#
# Fine engraving turns to noise when small, so the images of 64 px and less
# use a plainer cut of the same SVG, chosen by a stylesheet added to it: bold
# feather splits instead of the fine texture, and no letters, which can't be
# read that small. From 128 px up, where the Dock and Finder draw it, it's
# the full drawing.
# ------------------------------------------------------------------------
set -euo pipefail
cd "$(dirname "$0")/.."

command -v rsvg-convert >/dev/null || { echo "needs rsvg-convert: brew install librsvg" >&2; exit 1; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

small='.fine,.letters{display:none}.bold{display:inline}.relief{filter:url(#cast-small)}'

# compose STYLE OUT: the tile, then the eagle as a nested <svg> on it. Line 1
# of EagleBoards.svg is its opening <svg> tag, which gains a position, a size
# and the stylesheet.
compose() {
    {
        echo '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">'
        echo '  <rect x="102.4" y="102.4" width="819.2" height="819.2" rx="184.32" fill="#243E2C"/>'
        echo '  <rect x="138.24" y="138.24" width="747.52" height="747.52" rx="153.6" fill="none" stroke="#D6CEBD" stroke-width="12.29"/>'
        sed "1s|<svg |<svg x=\"207\" y=\"206\" width=\"610\" height=\"610\" |; 1s|>|><style>$1</style>|" Artwork/EagleBoards.svg
        echo '</svg>'
    } > "$2"
}
compose "" "$work/full.svg"
compose "$small" "$work/small.svg"

iconset="$work/AppIcon.iconset"
mkdir "$iconset"
for points in 16 32 128 256 512; do
    for scale in 1 2; do
        pixels=$((points * scale))
        svg="$work/full.svg"
        [ "$pixels" -le 64 ] && svg="$work/small.svg"
        name="icon_${points}x${points}.png"
        [ "$scale" = 2 ] && name="icon_${points}x${points}@2x.png"
        rsvg-convert -w "$pixels" -h "$pixels" "$svg" -o "$iconset/$name"
    done
done

iconutil -c icns "$iconset" -o Artwork/AppIcon.icns
echo "wrote Artwork/AppIcon.icns"
