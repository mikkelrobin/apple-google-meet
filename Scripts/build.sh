#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"
MODE="${MODE:-preview}"
[[ "$MODE" == preview || "$MODE" == signed ]] || { echo 'MODE must be preview or signed'; exit 1; }
if [[ "$MODE" == signed ]]; then
  : "${TEAM_ID:?Set TEAM_ID}" "${SIGN_IDENTITY:?Set Developer ID Application identity}"
  : "${APP_PROFILE:?Set app provisioning profile path}" "${EXT_PROFILE:?Set extension provisioning profile path}"
fi
BUILD="${BUILD_DIR:-$PWD/build}"
APP="$BUILD/Calendar Meet.app"
EXT="$APP/Contents/PlugIns/MeetConference.appex"
mkdir -p "$BUILD" "$APP/Contents/MacOS" "$APP/Contents/Resources" "$EXT/Contents/MacOS" "$EXT/Contents/Resources" "$BUILD/modules"
python3 Scripts/metadata.py "$BUILD" "$MODE"
cp "$BUILD/App-Info.plist" "$APP/Contents/Info.plist"
cp "$BUILD/Extension-Info.plist" "$EXT/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
printf 'XPC!????' > "$EXT/Contents/PkgInfo"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
for ARCH in arm64 x86_64; do
  xcrun swiftc -swift-version 5 -O -sdk "$SDK" -target "$ARCH-apple-macosx13.0" -module-cache-path "$BUILD/modules" \
    -module-name CalendarMeet -parse-as-library Sources/Shared/*.swift Sources/App/*.swift \
    -o "$BUILD/CalendarMeet-$ARCH"
  xcrun swiftc -swift-version 5 -O -sdk "$SDK" -target "$ARCH-apple-macosx13.0" -module-cache-path "$BUILD/modules" \
    -module-name MeetConference -parse-as-library -application-extension \
    -Xlinker -e -Xlinker _NSExtensionMain Sources/Shared/*.swift Sources/Extension/*.swift \
    -o "$BUILD/MeetConference-$ARCH"
done
lipo -create "$BUILD/CalendarMeet-arm64" "$BUILD/CalendarMeet-x86_64" -output "$APP/Contents/MacOS/CalendarMeet"
lipo -create "$BUILD/MeetConference-arm64" "$BUILD/MeetConference-x86_64" -output "$EXT/Contents/MacOS/MeetConference"
# Generate the original icon from source. No downloaded artwork or generators are needed.
xcrun swift -module-cache-path "$BUILD/modules" Scripts/Icon.swift "$BUILD/AppIcon-1024.png"
ICONSET="$BUILD/AppIcon.iconset"; mkdir -p "$ICONSET"
for SIZE in 16 32 128 256 512; do
  sips -z "$SIZE" "$SIZE" "$BUILD/AppIcon-1024.png" --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
  DOUBLE=$((SIZE * 2))
  sips -z "$DOUBLE" "$DOUBLE" "$BUILD/AppIcon-1024.png" --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
cp "$APP/Contents/Resources/AppIcon.icns" "$EXT/Contents/Resources/AppIcon.icns"
if [[ -n "${GOOGLE_CLIENT_JSON:-}" ]]; then
  python3 - "$GOOGLE_CLIENT_JSON" <<'PY'
import json, sys
j=json.load(open(sys.argv[1])); assert 'installed' in j and j['installed']['client_id'].endswith('.apps.googleusercontent.com')
assert not any(k in j for k in ('access_token', 'refresh_token', 'private_key'))
PY
  cp "$GOOGLE_CLIENT_JSON" "$APP/Contents/Resources/GoogleOAuthClient.json"
else
  rm -f "$APP/Contents/Resources/GoogleOAuthClient.json"
fi
if [[ "$MODE" == signed ]]; then
  cp "$APP_PROFILE" "$APP/Contents/embedded.provisionprofile"
  cp "$EXT_PROFILE" "$EXT/Contents/embedded.provisionprofile"
  SIGN="$SIGN_IDENTITY"; OPTIONS=(--options runtime --timestamp)
else
  rm -f "$APP/Contents/embedded.provisionprofile" "$EXT/Contents/embedded.provisionprofile"
  SIGN=-; OPTIONS=(--timestamp=none)
fi
xattr -cr "$APP"
codesign --force --sign "$SIGN" "${OPTIONS[@]}" --entitlements "$BUILD/Extension-Entitlements.plist" "$EXT"
codesign --force --sign "$SIGN" "${OPTIONS[@]}" --entitlements "$BUILD/App-Entitlements.plist" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
python3 Scripts/verify_bundle.py "$APP" "$MODE"
echo "Built $APP ($MODE, universal arm64 + x86_64)"
