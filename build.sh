#!/bin/sh
# Compile Sources/*.swift and install Screen Pointer.app into ~/Applications.
set -e
cd "$(dirname "$0")"
APP="$HOME/Applications/Screen Pointer.app"

swiftc -O -o screen-pointer Sources/*.swift
mkdir -p "$APP/Contents/MacOS"
cp screen-pointer "$APP/Contents/MacOS/screen-pointer"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "installed $APP"
