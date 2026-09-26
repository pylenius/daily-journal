#!/usr/bin/env bash
# Builds a Developer ID–signed, notarized Journal-<version>.dmg into mac/out/.
#   ./release.sh            build, sign, notarize, staple
#   ./release.sh --publish  … and attach it to a GitHub Release tagged mac-v<version>
#
# One-time setup:
#   1. Xcode > Settings > Accounts > your team > Manage Certificates > + > Developer ID Application
#   2. xcrun notarytool store-credentials daily-journal-notary --apple-id <you> --team-id <TEAMID>
#      (asks for an app-specific password from account.apple.com)
#   3. DEVELOPMENT_TEAM = <TEAMID> in Signing.xcconfig
set -euo pipefail
cd "$(dirname "$0")"

PROFILE="${NOTARY_PROFILE:-daily-journal-notary}"
TEAM="$(sed -n 's/^DEVELOPMENT_TEAM *= *\([A-Z0-9]*\).*/\1/p' Signing.xcconfig)"
VERSION="$(sed -n 's/.*MARKETING_VERSION: "\(.*\)"/\1/p' project.yml)"
OUT=out
DMG="$OUT/Journal-$VERSION.dmg"

die() { echo "release.sh: $*" >&2; exit 1; }
[ -n "$TEAM" ] || die "set DEVELOPMENT_TEAM in Signing.xcconfig"
IDENTITY="$(security find-identity -v -p codesigning | sed -n "s/.*\"\(Developer ID Application: .*($TEAM)\)\"/\1/p" | head -1)"
[ -n "$IDENTITY" ] || die "no 'Developer ID Application' certificate for team $TEAM (Xcode > Settings > Accounts > Manage Certificates)"
xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1 \
  || die "no notarization credentials; run: xcrun notarytool store-credentials $PROFILE --apple-id <you> --team-id $TEAM"

rm -rf "$OUT"; mkdir -p "$OUT"
echo ">> Archiving Journal $VERSION (team $TEAM)"
xcodegen generate --quiet
xcodebuild -project JournalMac.xcodeproj -scheme Journal -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$OUT/Journal.xcarchive" \
  -allowProvisioningUpdates DEVELOPMENT_TEAM="$TEAM" archive -quiet

echo ">> Exporting with Developer ID"
cat > "$OUT/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$TEAM</string>
  <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
EOF
xcodebuild -exportArchive -archivePath "$OUT/Journal.xcarchive" -exportPath "$OUT/export" \
  -exportOptionsPlist "$OUT/ExportOptions.plist" -allowProvisioningUpdates -quiet

echo ">> Building $DMG"
mkdir "$OUT/dmg"
cp -R "$OUT/export/Journal.app" "$OUT/dmg/"
ln -s /Applications "$OUT/dmg/Applications"
hdiutil create -volname "Journal" -srcfolder "$OUT/dmg" -ov -format UDZO -quiet "$DMG"
codesign --sign "$IDENTITY" --timestamp "$DMG"

echo ">> Notarizing (a few minutes)"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple -q "$DMG"
spctl --assess --type open --context context:primary-signature -v "$DMG"

if [ "${1:-}" = "--publish" ]; then
  TAG="mac-v$VERSION"
  echo ">> Publishing GitHub Release $TAG"
  gh release create "$TAG" "$DMG" --target main --title "Journal for Mac $VERSION" --notes "**Journal for Mac $VERSION**, the daily-journal reader for macOS 15 and later.

Download **Journal-$VERSION.dmg**, open it and drag Journal to Applications. The app is signed with Developer ID and notarized by Apple.

On first launch, choose the journal folder (for example the Journal folder in iCloud Drive)."
fi
echo ">> Done: $DMG"
