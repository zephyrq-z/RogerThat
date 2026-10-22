#!/bin/sh
set -e
cd "$(dirname "$0")"
APP=dist/RogerThat.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Info.plist "$APP/Contents/Info.plist"
swiftc -O -o "$APP/Contents/MacOS/RogerThat" src/main.swift
codesign --force --deep -s - "$APP" 2>/dev/null
echo "built $APP"