#!/bin/sh
# Signs the built app for the Mac App Store and wraps it in a signed installer package.
# Uploads nothing. The only server contacted is Apple's signing timestamp service.
#
# Three things from the Apple Developer account are passed as environment variables:
#   PWDHASH_APP_IDENTITY          application certificate, such as "Apple Distribution: NAME (TEAMID)"
#   PWDHASH_INSTALLER_IDENTITY    installer certificate, such as "3rd Party Mac Developer Installer: NAME (TEAMID)"
#   PWDHASH_PROVISIONING_PROFILE  path to the Mac App Store provisioning profile for the app's bundle identifier
# Both certificates need their private keys in a keychain; `security find-identity -v` lists them.
# Run `make macos` first, or use `make macos-appstore`, which does both.
set -eu
case "${PWDHASH_PROVISIONING_PROFILE:-}" in
  ''|/*) PROFILE=${PWDHASH_PROVISIONING_PROFILE:-} ;;
  *) PROFILE=$PWD/$PWDHASH_PROVISIONING_PROFILE ;;
esac
cd "$(dirname "$0")/.."

SOURCE_APP=.build/macos/PwdHash.app
STORE=.build/macos/appstore
STORE_APP=.build/macos/appstore/PwdHash.app
ENTITLEMENTS=.build/macos/appstore/PwdHash-appstore.entitlements

fail() {
  echo "FAIL: $*" >&2
  exit 1
}
info() { /usr/libexec/PlistBuddy -c "Print :$1" "$SOURCE_APP/Contents/Info.plist"; }

MISSING=
[ -n "${PWDHASH_APP_IDENTITY:-}" ] || MISSING="$MISSING PWDHASH_APP_IDENTITY"
[ -n "${PWDHASH_INSTALLER_IDENTITY:-}" ] || MISSING="$MISSING PWDHASH_INSTALLER_IDENTITY"
[ -n "$PROFILE" ] || MISSING="$MISSING PWDHASH_PROVISIONING_PROFILE"
[ -z "$MISSING" ] || fail "set$MISSING (described at the top of scripts/package-macos-appstore.sh)"
[ -f "$PROFILE" ] || fail "no provisioning profile at $PROFILE"
[ -d "$SOURCE_APP" ] || fail "build the app first: make macos"

sh scripts/verify-macos-release.sh "$SOURCE_APP" local
BUNDLE_ID=$(info CFBundleIdentifier)
VERSION=$(info CFBundleShortVersionString)
BUILD=$(info CFBundleVersion)
case "$VERSION$BUILD" in
  ''|*[!0-9.]*) fail "unexpected version '$VERSION' or build '$BUILD' in Info.plist" ;;
esac

PROFILE_FIELDS=$(security cms -D -i "$PROFILE" 2>/dev/null | python3 scripts/check-macos-profile.py "$BUNDLE_ID") \
  || fail "the provisioning profile does not fit $BUNDLE_ID (reasons above)"
APP_ID=$(printf '%s\n' "$PROFILE_FIELDS" | sed -n 's/^application-identifier=//p')
TEAM_ID=$(printf '%s\n' "$PROFILE_FIELDS" | sed -n 's/^team-identifier=//p')
[ -n "$APP_ID" ] && [ -n "$TEAM_ID" ] || fail "the provisioning profile gave no application or team identifier"

security find-identity -v -p codesigning | grep -F -q -- "$PWDHASH_APP_IDENTITY" \
  || fail "no valid application signing identity matching '$PWDHASH_APP_IDENTITY' is in a keychain"
security find-identity -v | grep -F -q -- "$PWDHASH_INSTALLER_IDENTITY" \
  || fail "no valid installer signing identity matching '$PWDHASH_INSTALLER_IDENTITY' is in a keychain"

for path in .build .build/macos "$STORE"; do
  [ ! -L "$path" ] || fail "refusing to use a symbolic-link build path: $path"
done
rm -rf .build/macos/appstore
mkdir -p "$STORE"
ditto "$SOURCE_APP" "$STORE_APP"
cp "$PROFILE" "$STORE_APP/Contents/embedded.provisionprofile"
cp src/MacOS/App/PwdHash.entitlements "$ENTITLEMENTS"
/usr/libexec/PlistBuddy -c "Add :com.apple.application-identifier string $APP_ID" \
  -c "Add :com.apple.developer.team-identifier string $TEAM_ID" "$ENTITLEMENTS" >/dev/null
plutil -lint "$ENTITLEMENTS" >/dev/null
# A downloaded profile carries a quarantine mark, which the App Store rejects inside an app.
xattr -cr "$STORE_APP"
codesign --force --sign "$PWDHASH_APP_IDENTITY" --options runtime --entitlements "$ENTITLEMENTS" --timestamp "$STORE_APP"
sh scripts/verify-macos-release.sh "$STORE_APP" appstore

PACKAGE="$STORE/PwdHash-$VERSION-$BUILD.pkg"
productbuild --component "$STORE_APP" /Applications --sign "$PWDHASH_INSTALLER_IDENTITY" "$PACKAGE"
PACKAGE_SIGNATURE=$(pkgutil --check-signature "$PACKAGE" 2>&1) || fail "the signature of $PACKAGE does not verify:
$PACKAGE_SIGNATURE"
case "$PACKAGE_SIGNATURE" in
  *'3rd Party Mac Developer Installer: '*) ;;
  *) fail "$PACKAGE is not signed with a 3rd Party Mac Developer Installer certificate:
$PACKAGE_SIGNATURE" ;;
esac

echo "Packaged $PACKAGE"
cat <<EOF
Nothing was uploaded. To have App Store Connect check the package, then deliver it:
  xcrun altool --validate-app "$PACKAGE" --api-key KEY_ID --api-issuer ISSUER_ID
  xcrun altool --upload-package "$PACKAGE" --api-key KEY_ID --api-issuer ISSUER_ID
Apple's Transporter app delivers the same package. The altool options differ between
Xcode versions; "xcrun altool --help" shows the ones installed here.
EOF
