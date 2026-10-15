#!/bin/zsh
# Builds the DMG, publishes it as a GitHub release, and updates the Homebrew tap.
# Bump the version in build.sh first. Requires the gh CLI, logged in.
set -euo pipefail
cd "$(dirname "$0")"

REPO=minhchienwikipedia/floating-lyrics
TAP=minhchienwikipedia/homebrew-tap

./make-dmg.sh
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" build/FloatingLyrics.app/Contents/Info.plist)
DMG="build/FloatingLyrics-$VERSION.dmg"
SHA=$(shasum -a 256 "$DMG" | awk '{print $1}')

# Point the cask at this release
sed -i '' -E "s/^  version \".*\"/  version \"$VERSION\"/; s/^  sha256 \".*\"/  sha256 \"$SHA\"/" homebrew/floating-lyrics.rb

gh release create "v$VERSION" "$DMG" --repo "$REPO" --title "Floating Lyrics $VERSION" --generate-notes

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
gh repo clone "$TAP" "$WORK/tap" -- --quiet
mkdir -p "$WORK/tap/Casks"
cp homebrew/floating-lyrics.rb "$WORK/tap/Casks/"
git -C "$WORK/tap" add Casks/floating-lyrics.rb
git -C "$WORK/tap" commit --quiet -m "floating-lyrics $VERSION"
git -C "$WORK/tap" push --quiet

echo "Released $VERSION. Commit the updated homebrew/floating-lyrics.rb too."
