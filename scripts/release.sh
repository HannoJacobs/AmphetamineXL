#!/bin/bash
# Local replacement for the old GitHub Actions workflow: build the Release app and DMG in
# a throwaway copy of the working tree, then upload the DMG to the latest GitHub release.
# Run it on a Mac. --no-upload stops after the build and works with uncommitted changes.
set -euo pipefail

UPLOAD=yes
case "${1:-}" in
    "") ;;
    --no-upload) UPLOAD=no ;;
    *) echo "Usage: $0 [--no-upload]" >&2; exit 2 ;;
esac

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

if [ "$UPLOAD" = yes ]; then
    git fetch -q origin main
    if [ -n "$(git status --porcelain)" ] || [ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]; then
        echo "Error: upload needs a clean checkout at origin/main. Commit and push first." >&2
        exit 1
    fi
fi

BASE="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$BASE"' EXIT
# .noindex keeps the temporary app bundle out of Spotlight.
WORK="$BASE/release.noindex"
mkdir "$WORK"
git ls-files -coz --exclude-standard | while IFS= read -r -d '' path; do
    if [ -e "$path" ]; then printf '%s\0' "$path"; fi
done | tar --null -T - -cf - | tar -xf - -C "$WORK"

cd "$WORK"
xcodebuild -scheme AmphetamineXL -configuration Release -destination 'platform=macOS' \
    -derivedDataPath "$BASE/derived" build
BINARY="$(find "$BASE/derived" -path '*/Release/AmphetamineXL' -type f | head -1)"
AMPHETAMINEXL_RELEASE_BINARY="$BINARY" bash create-dmg.sh

if [ "$UPLOAD" = yes ]; then
    cd "$REPO"
    TAG="$(gh release list --limit 1 --json tagName -q '.[0].tagName')"
    gh release upload "$TAG" "$WORK/AmphetamineXL.dmg" --clobber
    echo "==> Uploaded AmphetamineXL.dmg to $TAG"
else
    echo "==> Build passed; upload skipped"
fi
