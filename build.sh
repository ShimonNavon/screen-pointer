#!/bin/sh
# Build, verify the stable local signature, then install Screen Pointer.app.
set -eu
cd "$(dirname "$0")"
APP="$HOME/Applications/Screen Pointer.app"
STAGING=$(mktemp -d "${TMPDIR:-/tmp}/screen-pointer-build.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT HUP INT TERM
BUNDLE="$STAGING/Screen Pointer.app"

swiftc -O -o screen-pointer Sources/*.swift
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp screen-pointer "$BUNDLE/Contents/MacOS/screen-pointer"
cp tools/send_review.py tools/recordings.py "$BUNDLE/Contents/Resources/"
cp Info.plist "$BUNDLE/Contents/Info.plist"
python3 tools/sign_app.py "$BUNDLE"
if pgrep -x screen-pointer >/dev/null; then
  echo 'Quit Screen Pointer before installing, so an active recording is not interrupted.' >&2
  exit 1
fi
mkdir -p "$HOME/Applications"
ditto "$BUNDLE" "$APP"
codesign --verify --strict "$APP"
echo "installed $APP"
