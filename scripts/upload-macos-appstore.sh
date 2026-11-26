#!/bin/sh
# Archive, cloud-sign, and verify PwdHash for the Mac App Store.
# Sign in to Xcode Settings > Accounts with the developer team for this app.
set -eu

usage() {
    printf 'Usage: sh scripts/upload-macos-appstore.sh [--export | --upload]\n'
    printf '  --export  Create and verify a signed installer package (default).\n'
    printf '  --upload  Also deliver the archived build to App Store Connect.\n'
    printf 'Set PWDHASH_DEVELOPMENT_TEAM to your Apple Developer team ID.\n'
}

if [ "$#" -gt 1 ]; then usage >&2; exit 2; fi
action=${1:---export}
case "$action" in
    --export|--upload) ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
esac

cd "$(dirname "$0")/.."
info_plist=src/MacOS/App/Info.plist
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist")
build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info_plist")
team_id=${PWDHASH_DEVELOPMENT_TEAM:?Set PWDHASH_DEVELOPMENT_TEAM to your Apple Developer team ID}
case "$version:$build" in
    :*|*:|*[!0-9.:]*) printf 'Invalid macOS version or build in %s\n' "$info_plist" >&2; exit 1 ;;
esac

output_root="$PWD/.build/macos-upload"
mkdir -p "$output_root"
run_dir=$(mktemp -d "$output_root/PwdHash-$version-$build.XXXXXX")
archive="$run_dir/PwdHash.xcarchive"
sh scripts/prepare-macos-assets.sh "$run_dir/AppAssets.xcassets"

printf 'Archiving PwdHash for macOS %s (build %s) in %s\n' "$version" "$build" "$run_dir"
xcodebuild -project src/MacOS/PwdHash.xcodeproj -scheme PwdHash -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath "$run_dir/DerivedData" \
    -archivePath "$archive" -allowProvisioningUpdates -quiet \
    "DEVELOPMENT_TEAM=$team_id" "PWDHASH_MACOS_ASSET_DIR=$run_dir" \
    "MARKETING_VERSION=$version" "CURRENT_PROJECT_VERSION=$build" archive

distribute() {
    destination=$1
    export_path=$2
    options="$run_dir/$destination.plist"
    plutil -create xml1 "$options"
    plutil -insert method -string app-store-connect "$options"
    plutil -insert destination -string "$destination" "$options"
    plutil -insert signingStyle -string automatic "$options"
    plutil -insert teamID -string "$team_id" "$options"
    plutil -insert manageAppVersionAndBuildNumber -bool false "$options"
    plutil -insert uploadSymbols -bool true "$options"
    xcodebuild -exportArchive -archivePath "$archive" -exportPath "$export_path" \
        -exportOptionsPlist "$options" -allowProvisioningUpdates
}

distribute export "$run_dir/Export"
package="$run_dir/Export/PwdHash.pkg"
signature=$(pkgutil --check-signature "$package")
case "$signature" in
    *'3rd Party Mac Developer Installer: '*"($team_id)"*) ;;
    *) printf 'The installer certificate is not for the PwdHash developer team.\n%s\n' "$signature" >&2; exit 1 ;;
esac

pkgutil --expand-full "$package" "$run_dir/Inspection"
app=$(find "$run_dir/Inspection" -type d -name PwdHash.app -prune -print)
EXPECTED_ARCHS='arm64 x86_64' sh scripts/verify-macos-release.sh "$app" appstore
printf 'Verified installer: %s\n' "$package"

if [ "$action" = --upload ]; then
    distribute upload "$run_dir/Delivery"
    printf 'Delivered PwdHash for macOS %s (build %s) to App Store Connect.\n' "$version" "$build"
fi
