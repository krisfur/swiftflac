#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

xcodebuild -project SwiftFlac.xcodeproj -scheme SwiftFlac -configuration Debug \
    -destination 'platform=macOS' -derivedDataPath build build

open "build/Build/Products/Debug/SwiftFlac.app"
