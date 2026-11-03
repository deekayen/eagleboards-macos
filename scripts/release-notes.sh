#!/usr/bin/env bash
# ------------------------------------------------------------------------
# release-notes.sh: print the notes for a release to standard output.
#
#   scripts/release-notes.sh v2026.11.05 > release-notes.md
#
# The notes are the body of that version's section in CHANGELOG.md, whose
# heading is "## 2026.11.05"; the maintainer renames "## Unreleased" to the
# release date by hand before tagging. A version with no heading, or an empty
# one, fails, so a tag cannot publish without a changelog entry. A paragraph
# for first launch follows the section. release.yml runs this; it checks the
# tag's shape first.
# ------------------------------------------------------------------------
set -euo pipefail
cd "$(dirname "$0")/.."

tag="${1:?usage: scripts/release-notes.sh <tag, like v2026.11.05>}"
version="${tag#v}"
repo="${GITHUB_REPOSITORY:-deekayen/eagleboards-macos}"

fail() {
    if [ -n "${GITHUB_ACTIONS:-}" ]; then
        echo "::error::$1"
    else
        echo "error: $1" >&2
    fi
    exit 1
}

# From the version's heading to the next "## " heading, exclusive.
section=$(awk -v ver="$version" '
    /^## / {
        if (found) exit
        line = $0
        sub(/[[:space:]]+$/, "", line)
        if (line == "## " ver) { found = 1; next }
    }
    found { print }
    END { if (!found) exit 3 }
' CHANGELOG.md) || fail "CHANGELOG.md has no \"## $version\" heading; rename \"## Unreleased\" to it before tagging"
section=$(printf '%s\n' "$section" | sed '/./,$!d')
[ -n "$(printf '%s' "$section" | tr -d '[:space:]')" ] || fail "the \"## $version\" section of CHANGELOG.md is empty"

printf '%s\n\n' "$section"
cat <<NOTES
For Macs with Apple silicon running macOS 15 or later. Intel Macs and macOS 14 are not supported. Signed ad hoc, not notarized, so macOS stops the app the first time: open it, close the warning, then click **Open Anyway** in System Settings › Privacy & Security and confirm. After an update, macOS also asks again for access to the SignUpGenius key in your keychain; click **Always Allow**. Earlier releases are in the [changelog](https://github.com/$repo/blob/$tag/CHANGELOG.md).
NOTES
