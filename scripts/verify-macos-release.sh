#!/bin/sh
# Checks a built PwdHash.app. Usage: verify-macos-release.sh [APP] [local|appstore]
#   local     the ad hoc build from scripts/build-macos.sh (the default)
#   appstore  the distribution-signed copy from scripts/package-macos-appstore.sh
# EXPECTED_ARCHS (default "arm64 x86_64") names the architectures the executable must hold.
set -eu
cd "$(dirname "$0")/.."

APP=${1:-.build/macos/PwdHash.app}
MODE=${2:-local}
EXPECTED_ARCHS="${EXPECTED_ARCHS:-${ARCHS:-${ARCH:-arm64 x86_64}}}"
EXECUTABLE="$APP/Contents/MacOS/PwdHash"
INFO="$APP/Contents/Info.plist"
PRIVACY="$APP/Contents/Resources/PrivacyInfo.xcprivacy"
PROFILE="$APP/Contents/embedded.provisionprofile"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}
info() { /usr/libexec/PlistBuddy -c "Print :$1" "$INFO" 2>/dev/null || true; }
sorted() { printf '%s\n' $1 | sort | tr '\n' ' ' | sed 's/ $//'; }
signing() { printf '%s\n' "$SIGNING" | sed -n "s/^$1=//p" | head -1; }

case "$MODE" in
  local|appstore) ;;
  *) fail "unknown mode: $MODE (use local or appstore)" ;;
esac
[ -x "$EXECUTABLE" ] || fail "missing app executable"
codesign --verify --deep --strict "$APP"

SIGNING=$(codesign -d --verbose=4 "$APP" 2>&1)
case "$SIGNING" in
  *flags=*runtime*) ;;
  *) fail "Hardened Runtime is not enabled" ;;
esac

plutil -lint "$INFO" "$PRIVACY" >/dev/null
[ "$(info ITSAppUsesNonExemptEncryption)" = false ] || fail "ITSAppUsesNonExemptEncryption must be false"
BUNDLE_ID=$(info CFBundleIdentifier)
[ -n "$BUNDLE_ID" ] || fail "CFBundleIdentifier is missing"
[ "$(signing Identifier)" = "$BUNDLE_ID" ] || fail "the signature names '$(signing Identifier)', not the bundle identifier $BUNDLE_ID"
case "$(info LSApplicationCategoryType)" in
  public.app-category.?*) ;;
  *) fail "LSApplicationCategoryType is missing; the App Store rejects an upload without a category" ;;
esac
[ "$(info CFBundleSupportedPlatforms:0)" = MacOSX ] || fail "CFBundleSupportedPlatforms must name MacOSX"
for key in DTCompiler DTPlatformBuild DTPlatformName DTPlatformVersion DTSDKBuild DTSDKName DTXcode DTXcodeBuild BuildMachineOSBuild; do
  [ -n "$(info "$key")" ] || fail "$key is missing from Info.plist"
done

ACTUAL_ARCHS=$(xcrun lipo -archs "$EXECUTABLE")
[ "$(sorted "$ACTUAL_ARCHS")" = "$(sorted "$EXPECTED_ARCHS")" ] \
  || fail "the executable holds '$ACTUAL_ARCHS' but '$EXPECTED_ARCHS' is expected (EXPECTED_ARCHS changes the expectation)"
MINIMUM=$(info LSMinimumSystemVersion)
for arch in $ACTUAL_ARCHS; do
  SLICE_MINIMUM=$(xcrun vtool -arch "$arch" -show-build "$EXECUTABLE" | sed -n 's/^ *minos //p')
  [ -n "$MINIMUM" ] && [ "$SLICE_MINIMUM" = "$MINIMUM" ] \
    || fail "the $arch slice needs macOS '$SLICE_MINIMUM' but Info.plist says '$MINIMUM'"
  case "$(xcrun nm -arch "$arch" -u "$EXECUTABLE")" in
    *_setrlimit*) ;;
    *) fail "core-file suppression is missing from the $arch slice" ;;
  esac
done

if xattr -lr "$APP" 2>/dev/null | grep -q 'com\.apple\.quarantine'; then
  fail "a file in the app carries com.apple.quarantine, which the App Store rejects"
fi

# The signed entitlements must be exactly the expected set: nothing missing and nothing extra.
ENTITLEMENTS=$(codesign -d --entitlements - --xml "$APP" 2>/dev/null | python3 -c '
import plistlib, sys
data = sys.stdin.buffer.read()
for key, value in sorted((plistlib.loads(data) if data.strip() else {}).items()):
    print(key + "=" + (str(value).lower() if isinstance(value, bool) else str(value)))
') || fail "could not read the signed entitlements"
EXPECTED_ENTITLEMENTS="com.apple.security.app-sandbox=true"

if [ "$MODE" = appstore ]; then
  case "$SIGNING" in
    *Signature=adhoc*) fail "the app is signed ad hoc; the App Store needs a distribution signature" ;;
  esac
  TEAM=$(signing TeamIdentifier)
  case "$TEAM" in
    ''|'not set') fail "the signature has no team identifier" ;;
  esac
  AUTHORITY=$(signing Authority)
  case "$AUTHORITY" in
    'Apple Distribution: '*|'3rd Party Mac Developer Application: '*) ;;
    *) fail "signed by '$AUTHORITY'; the App Store needs an Apple Distribution or 3rd Party Mac Developer Application certificate" ;;
  esac
  # The certificate name alone proves nothing; this checks the chain back to Apple's own root.
  codesign --verify --strict -R='anchor apple generic' "$APP" 2>/dev/null \
    || fail "the signing certificate was not issued by Apple"
  [ -f "$PROFILE" ] || fail "Contents/embedded.provisionprofile is missing"
  PROFILE_FIELDS=$(security cms -D -i "$PROFILE" 2>/dev/null | python3 scripts/check-macos-profile.py "$BUNDLE_ID") \
    || fail "the embedded provisioning profile does not fit $BUNDLE_ID (reasons above)"
  PROFILE_APP_ID=$(printf '%s\n' "$PROFILE_FIELDS" | sed -n 's/^application-identifier=//p')
  PROFILE_TEAM=$(printf '%s\n' "$PROFILE_FIELDS" | sed -n 's/^team-identifier=//p')
  [ "$PROFILE_TEAM" = "$TEAM" ] || fail "the profile belongs to team $PROFILE_TEAM but the app is signed by team $TEAM"
  EXPECTED_ENTITLEMENTS="com.apple.application-identifier=$PROFILE_APP_ID
com.apple.developer.team-identifier=$PROFILE_TEAM
com.apple.security.app-sandbox=true"
fi

[ "$ENTITLEMENTS" = "$EXPECTED_ENTITLEMENTS" ] || fail "unexpected signed entitlements:
$ENTITLEMENTS
expected exactly:
$EXPECTED_ENTITLEMENTS"

echo "PASS: macOS signature, Hardened Runtime, sandbox-only entitlements, $(sorted "$ACTUAL_ARCHS") slices for macOS $MINIMUM, App Store metadata keys, no quarantine marks, privacy metadata, and core-file suppression"
if [ "$MODE" = appstore ]; then
  echo "PASS: distribution signature, team and application identifiers matching the embedded Mac App Store profile"
fi
