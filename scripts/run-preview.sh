#!/bin/zsh
# Builds Backdrop and opens it without needing a signing team or provisioning profile.
#
# Everything works (camera preview, backgrounds, AI generation, live windows, automation, shortcuts)
# except the "Backdrop Camera" virtual camera, which is a system extension and needs real signing.
# See README.md › Running it for real.
#
# Set NO_OPEN=1 to build and sign without launching.
set -euo pipefail
cd "${0:A:h}/.."

xcodegen generate > /dev/null
derived=build/preview
xcodebuild build -quiet -project Backdrop.xcodeproj -scheme Backdrop -destination 'platform=macOS' \
  -derivedDataPath "$derived" CODE_SIGNING_ALLOWED=NO

app="$derived/Build/Products/Debug/Backdrop.app"
# Ad-hoc, with only the entitlements that don't need a provisioning profile. No hardened runtime,
# so the Debug build's helper dylibs can load.
codesign --force --deep --sign - --entitlements scripts/preview.entitlements "$app"

echo "Built $app"
[[ -n "${NO_OPEN:-}" ]] || open "$app"
