#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
MODE="${MODE:-preview}"
BUILD="${BUILD_DIR:-$PWD/build}"
APP="$BUILD/Calendar Meet.app"
OUT="${OUTPUT_DIR:-$PWD/dist}"
mkdir -p "$OUT"
[[ "$MODE" == preview || "$MODE" == signed ]] || { echo "MODE must be preview or signed"; exit 1; }
if [[ "$MODE" == preview ]]; then SUFFIX=UNSIGNED-PREVIEW; else SUFFIX=SIGNED; fi
NAME="CalendarMeet-0.4.0-$SUFFIX"
# Stage outside cloud-synced Documents: file providers may add Finder metadata
# to .app/.appex bundles after they were signed.
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/CalendarMeet-dmg.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
ditto --norsrc --noextattr "$APP" "$STAGE/Calendar Meet.app"
xattr -cr "$STAGE/Calendar Meet.app"
codesign --verify --deep --strict "$STAGE/Calendar Meet.app"
ln -sfn /Applications "$STAGE/Applications"
cp docs/INSTALL.txt "$STAGE/READ ME FIRST.txt"
if [[ "$MODE" == preview ]]; then
  printf '\nUNSIGNED DEVELOPER PREVIEW: no Developer ID, no notarization. No Developer ID signature or notarization. Google login is enabled; this experimental build uses the containing app login Keychain and a one-time local callback. Choose Google Meet in Calendar to create and attach the meeting automatically.\n' >> "$STAGE/READ ME FIRST.txt"
fi
hdiutil create -ov -volname "Calendar Meet" -srcfolder "$STAGE" -format UDZO "$OUT/$NAME.dmg"
if [[ "$MODE" == signed ]]; then
  : "${NOTARY_PROFILE:?Set a notarytool Keychain profile; signed releases must be notarized}"
  codesign --sign "$SIGN_IDENTITY" --timestamp "$OUT/$NAME.dmg"
  NOTARY_ARGS=(--keychain-profile "$NOTARY_PROFILE")
  if [[ -n "${NOTARY_KEYCHAIN:-}" ]]; then NOTARY_ARGS+=(--keychain "$NOTARY_KEYCHAIN"); fi
  xcrun notarytool submit "$OUT/$NAME.dmg" "${NOTARY_ARGS[@]}" --wait --output-format json > "$BUILD/notary-result.json"
  python3 -c 'import json,sys; assert json.load(open(sys.argv[1]))["status"] == "Accepted"' "$BUILD/notary-result.json"
  xcrun stapler staple "$OUT/$NAME.dmg"
  xcrun stapler validate "$OUT/$NAME.dmg"
  spctl --assess --type open --context context:primary-signature --verbose "$OUT/$NAME.dmg"
fi
(cd "$OUT" && shasum -a 256 "$NAME.dmg" > "$NAME.sha256")
echo "Installer: $OUT/$NAME.dmg"
