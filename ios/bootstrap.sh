#!/bin/sh
# Generate the Xcode project. Requires XcodeGen: brew install xcodegen
set -e
cd "$(dirname "$0")"
[ -f Signing.xcconfig ] || cp Signing.xcconfig.example Signing.xcconfig
xcodegen generate
echo "open ios/Journal.xcodeproj"
