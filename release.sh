#!/bin/zsh
# Cut a Folio release: bump the version, build + notarize, zip, update the
# Sparkle appcast, commit, tag, push, and publish a GitHub release.
#
# Usage: ./release.sh <version> [release notes]
#   ./release.sh 1.0.1
#   ./release.sh 1.0.1 "Fixes the sidebar collapsing when a tab is added."
#
# Needs, all on this Mac's login keychain: the Developer ID Application
# certificate, the "notary" notarytool profile, and the Sparkle EdDSA private
# key. Also `gh` logged in. The GitHub repo must be public or the release
# asset will not be downloadable by Sparkle.
set -euo pipefail
ROOT="${0:A:h}"
REPO="danepps/pdfreader"

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  echo "usage: ${0:t} <version> [release notes]" >&2
  exit 1
fi
if [[ ! "$VERSION" =~ '^[0-9]+(\.[0-9]+)+$' ]]; then
  echo "version should look like 1.0.1, got: $VERSION" >&2
  exit 1
fi
NOTES="${2:-Folio $VERSION.}"

# --- Preflight -----------------------------------------------------------
BRANCH="$(git -C "$ROOT" rev-parse --abbrev-ref HEAD)"
if [[ "$BRANCH" != main ]]; then
  echo "releases are cut from main; currently on $BRANCH" >&2
  exit 1
fi

# The only files allowed to be dirty are the two this script rewrites.
DIRTY="$(git -C "$ROOT" status --porcelain -- "$ROOT" \
  ':(exclude)Support/Info.plist' ':(exclude)appcast.xml')"
if [[ -n "$DIRTY" ]]; then
  echo "working tree is not clean:" >&2
  echo "$DIRTY" >&2
  exit 1
fi

if git -C "$ROOT" rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null; then
  echo "tag v$VERSION already exists" >&2
  exit 1
fi

GENERATE_APPCAST=( "$ROOT"/.build/artifacts/*/Sparkle/bin/generate_appcast(N) )
if (( ${#GENERATE_APPCAST} == 0 )); then
  echo "generate_appcast not found; run ./build.sh once to resolve Sparkle" >&2
  exit 1
fi

# --- Version -------------------------------------------------------------
# CFBundleShortVersionString is what people see; CFBundleVersion is what
# Sparkle compares, so it only ever goes up.
PLIST="$ROOT/Support/Info.plist"
BUILD_NUMBER=$(( $(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST") + 1 ))
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$PLIST"
echo "==> Folio $VERSION (build $BUILD_NUMBER)"

# --- Build, notarize, archive -------------------------------------------
"$ROOT/build.sh" --notarize

APP="$ROOT/build/Folio.app"
RELEASES="$ROOT/build/releases"
ZIP="$RELEASES/Folio-$VERSION.zip"
mkdir -p "$RELEASES"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "==> $ZIP"

# --- Appcast -------------------------------------------------------------
# generate_appcast writes into the directory it is given and merges with any
# appcast.xml already there, so stage a directory holding just the new zip and
# a copy of the live feed. It signs entries with the EdDSA key in the keychain.
STAGE="$ROOT/build/appcast-stage"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp "$ZIP" "$STAGE/"
cp "$ROOT/appcast.xml" "$STAGE/appcast.xml"
"${GENERATE_APPCAST[1]}" \
  --download-url-prefix "https://github.com/$REPO/releases/download/v$VERSION/" \
  --link "https://github.com/$REPO" \
  "$STAGE"
cp "$STAGE/appcast.xml" "$ROOT/appcast.xml"
echo "==> appcast.xml updated"

# --- Publish -------------------------------------------------------------
# Order matters: the feed goes live the moment main is pushed (raw
# githubusercontent), so the release asset must already be downloadable.
# Push only the tag first, publish the release against it, then push main.
git -C "$ROOT" add "$ROOT/Support/Info.plist" "$ROOT/appcast.xml"
git -C "$ROOT" commit -m "Release v$VERSION"
git -C "$ROOT" tag "v$VERSION"
git -C "$ROOT" push origin "v$VERSION"

gh release create "v$VERSION" "$ZIP" \
  --repo "$REPO" \
  --title "Folio $VERSION" \
  --notes "$NOTES"

git -C "$ROOT" push origin main

echo
echo "Released: https://github.com/$REPO/releases/tag/v$VERSION"
