#!/bin/sh
# Build a native iPhone app entirely from the terminal, without launching Xcode.
set -eu
cd "$(dirname "$0")/.."
SDK="${SDK:-iphoneos}"
ARCH="${ARCH:-arm64}"
case "$SDK" in
  iphoneos) TARGET="$ARCH-apple-ios17.0"; PLATFORM=iPhoneOS ;;
  iphonesimulator) TARGET="$ARCH-apple-ios17.0-simulator"; PLATFORM=iPhoneSimulator ;;
  *) echo 'SDK must be iphoneos or iphonesimulator' >&2; exit 1 ;;
esac
BUNDLE_ID="${BUNDLE_ID:-app.nmic.pwdhash}"
IOS=src/IOS/PwdHash
APP=".build/$SDK/PwdHash.app"
mkdir -p "$APP" ".build/$SDK/ModuleCache"
SDK_PATH="$(xcrun --sdk "$SDK" --show-sdk-path)"
SWIFT_FLAGS="-O"
if [ "${CONFIGURATION:-Release}" = Debug ]; then SWIFT_FLAGS="-Onone -g -D DEBUG"; fi
# Deliberate word splitting for the fixed compiler option list above.
xcrun --sdk "$SDK" swiftc -swift-version 6 -module-name PwdHash -sdk "$SDK_PATH" \
  -target "$TARGET" -module-cache-path ".build/$SDK/ModuleCache" \
  $SWIFT_FLAGS -whole-module-optimization -emit-executable \
  -Xlinker -rpath -Xlinker @executable_path/Frameworks \
  "$IOS/main.swift" "$IOS/AppDelegate.swift" "$IOS/SecretField.swift" \
  "$IOS/PasswordViewController.swift" "$IOS"/Core/*.swift -o "$APP/PwdHash"
python3 scripts/make-icons.py
python3 - "$APP" "$BUNDLE_ID" "$PLATFORM" "$IOS/Info.plist" <<'PY'
import pathlib, plistlib, sys
app, bundle, platform = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
p = plistlib.loads(pathlib.Path(sys.argv[4]).read_bytes())
p['CFBundleIdentifier'] = bundle
p['CFBundleExecutable'] = 'PwdHash'
p['MinimumOSVersion'] = '17.0'
p['CFBundleSupportedPlatforms'] = [platform]
p['UIDeviceFamily'] = [1]
p['CFBundleIcons'] = {'CFBundlePrimaryIcon': {'CFBundleIconFiles': ['AppIcon60x60']}}
(app / 'Info.plist').write_bytes(plistlib.dumps(p))
(app / 'PkgInfo').write_bytes(b'APPL????')
PY
cp .build/icons/*.png "$APP/"
cp "$IOS/PrivacyInfo.xcprivacy" "$IOS/ThirdPartyNotices.txt" "$APP/"
if [ "$SDK" = iphonesimulator ]; then codesign --force --sign - "$APP"; fi
echo "Built $APP"
