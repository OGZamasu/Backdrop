#!/bin/zsh
# Builds Backdrop, signs it with a Developer ID certificate, has Apple notarize it, and packages it for download.
#
# Needs a paid Apple Developer Program team, and Xcode signed in to it (Xcode › Settings › Accounts).
# Signing, the Developer ID provisioning profiles and notarization all go through that account, so there is no
# certificate to export and no password to store. The first run registers the App IDs and an app group on your team.
#
#   DEVELOPMENT_TEAM=YOURTEAMID scripts/release.sh
#
# Optional: BACKDROP_BUNDLE_ID (default com.zamasu.backdrop).
#
# The result is build/release/Backdrop-<version>.zip and a .sha256 next to it.
set -euo pipefail
cd "${0:A:h}/.."

team="${DEVELOPMENT_TEAM:?Set DEVELOPMENT_TEAM to your Apple Developer team ID}"
bundle_id="${BACKDROP_BUNDLE_ID:-com.zamasu.backdrop}"
version="$(sed -n 's/^ *MARKETING_VERSION: "\(.*\)"/\1/p' project.yml | head -1)"
out="build/release"

options() {  # options <export|upload> writes the export options for that destination
  cat > "$out/ExportOptions-$1.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>signingStyle</key><string>automatic</string>
  <key>teamID</key><string>$team</string>
  <key>destination</key><string>$1</string>
</dict></plist>
EOF
}

echo "==> Building Backdrop $version ($bundle_id, team $team)"
xcodegen generate > /dev/null
rm -rf "$out" && mkdir -p "$out"

# arm64 only: that is what the app is developed and tested on.
xcodebuild archive -quiet \
  -project Backdrop.xcodeproj -scheme Backdrop -configuration Release -destination 'generic/platform=macOS' \
  -archivePath "$out/Backdrop.xcarchive" -allowProvisioningUpdates \
  BACKDROP_BUNDLE_ID="$bundle_id" DEVELOPMENT_TEAM="$team" ARCHS=arm64 ONLY_ACTIVE_ARCH=NO

echo "==> Signing with Developer ID"
options export
xcodebuild -exportArchive -quiet -archivePath "$out/Backdrop.xcarchive" -exportPath "$out/signed" \
  -exportOptionsPlist "$out/ExportOptions-export.plist" -allowProvisioningUpdates
codesign --verify --deep --strict "$out/signed/Backdrop.app"

echo "==> Submitting to Apple for notarization"
options upload
xcodebuild -exportArchive -quiet -archivePath "$out/Backdrop.xcarchive" -exportPath "$out/upload" \
  -exportOptionsPlist "$out/ExportOptions-upload.plist" -allowProvisioningUpdates

echo "==> Waiting for Apple (usually under a few minutes)"
for attempt in {1..40}; do
  if result="$(xcodebuild -exportNotarizedApp -archivePath "$out/Backdrop.xcarchive" -exportPath "$out/notarized" 2>&1)"; then
    break
  fi
  # Still being scanned: wait. Anything else, such as a rejection, is a real failure.
  if ! print -r -- "$result" | grep -q "processing and not ready"; then
    print -r -- "$result" >&2
    exit 1
  fi
  (( attempt == 40 )) && { echo "Gave up waiting for notarization." >&2; exit 1; }
  sleep 30
done

app="$out/notarized/Backdrop.app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=2 "$app"

echo "==> Packaging"
zip="$out/Backdrop-$version.zip"
ditto -c -k --keepParent "$app" "$zip"
(cd "$out" && shasum -a 256 "Backdrop-$version.zip" > "Backdrop-$version.zip.sha256")
echo
echo "Done: $zip"
cat "$zip.sha256"
