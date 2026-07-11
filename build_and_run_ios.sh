#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

BUNDLE_ID="com.kfurman.SwiftFlac"
MUSIC_DIR="${MUSIC_DIR:-$HOME/Downloads/Music}"

# Pick a booted iPhone simulator if there is one, otherwise the first available iPhone.
UDID=$(xcrun simctl list devices booted | grep -m1 "iPhone" | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' || true)
if [ -z "$UDID" ]; then
    UDID=$(xcrun simctl list devices available | grep -m1 "iPhone" | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}')
fi
echo "Using simulator $UDID"

xcrun simctl boot "$UDID" 2>/dev/null || true
open -a Simulator

xcodebuild -project SwiftFlac.xcodeproj -scheme SwiftFlac -configuration Debug \
    -destination "id=$UDID" -derivedDataPath build build

xcrun simctl install "$UDID" "build/Build/Products/Debug-iphonesimulator/SwiftFlac.app"

# Seed test music into the app's Documents folder (folders become playlists).
if [ -d "$MUSIC_DIR" ]; then
    CONTAINER=$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data)
    rsync -a "$MUSIC_DIR/" "$CONTAINER/Documents/"
    echo "Seeded music from $MUSIC_DIR"
fi

xcrun simctl launch "$UDID" "$BUNDLE_ID"
