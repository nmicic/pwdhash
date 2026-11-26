#!/bin/sh
# Sign with an existing development certificate/profile, install over USB, launch.
# No Xcode UI, account login, service registration, or App Store submission.
set -eu
cd "$(dirname "$0")/.."
BUNDLE_ID="${BUNDLE_ID:-app.nmic.pwdhash}"
export BUNDLE_ID
if [ "${SKIP_BUILD:-0}" != 1 ]; then sh scripts/build.sh; fi
APP=".build/iphoneos/PwdHash.app"
test -f "$APP/PwdHash"
BUILT_BUNDLE_ID="$(plutil -extract CFBundleIdentifier raw -o - "$APP/Info.plist")"
if [ "$BUILT_BUNDLE_ID" != "$BUNDLE_ID" ]; then
  echo "Built app uses $BUILT_BUNDLE_ID, but the requested ID is $BUNDLE_ID. Run without SKIP_BUILD=1 to rebuild." >&2
  exit 1
fi
mkdir -p .build
security find-identity -v -p codesigning > .build/signing-identities.txt
python3 scripts/prepare-signing.py "$APP"
IDENTITY="$(cat .build/signing-identity.txt)"
codesign --force --sign "$IDENTITY" --entitlements .build/Signing.entitlements \
  --generate-entitlement-der --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"
xcrun devicectl --timeout 30 --json-output .build/devices.json list devices
if [ -z "${DEVICE_ID:-}" ]; then
  DEVICE_ID="$(python3 scripts/select-device.py .build/devices.json "$APP/embedded.mobileprovision")"
fi
xcrun devicectl --timeout 60 device install app --device "$DEVICE_ID" "$APP"
if xcrun devicectl --timeout 30 device process launch --device "$DEVICE_ID" "$BUNDLE_ID"; then
  echo 'PwdHash installed and launched.'
else
  echo 'PwdHash is installed, but iOS did not open it. If the phone is locked, unlock it and tap the PwdHash icon.' >&2
  exit 1
fi
