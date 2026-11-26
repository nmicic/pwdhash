#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
# One slice per architecture. The default is a universal app, which the Mac App Store accepts
# for every Mac. ARCHS="arm64" (or the older ARCH=arm64) builds a single slice.
ARCHS="${ARCHS:-${ARCH:-arm64 x86_64}}"
APP=.build/macos/PwdHash.app
ASSET_CATALOG=.build/macos/AppAssets.xcassets
SLICES=.build/macos/Slices
# The signed App Store copy belongs to the build it was made from, so a rebuild discards it.
STORE=.build/macos/appstore
case "$APP:$ASSET_CATALOG:$SLICES:$STORE" in
  .build/macos/PwdHash.app:.build/macos/AppAssets.xcassets:.build/macos/Slices:.build/macos/appstore) ;;
  *) echo "Refusing to clean unexpected build paths." >&2; exit 1 ;;
esac
for path in .build .build/macos "$APP" "$ASSET_CATALOG" "$SLICES" "$STORE"; do
  if [ -L "$path" ]; then
    echo "Refusing to clean a symbolic-link build path: $path" >&2
    exit 1
  fi
done
rm -rf "$APP" "$ASSET_CATALOG" "$SLICES" "$STORE"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$SLICES" .build/macos/ModuleCache
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
SWIFT_FLAGS=-O
if [ "${CONFIGURATION:-Release}" = Debug ]; then SWIFT_FLAGS='-Onone -g -D DEBUG'; fi
BUILT=
SLICE_FILES=
for arch in $ARCHS; do
  case "$arch" in
    arm64|x86_64) ;;
    *) echo "Unsupported architecture: $arch (use arm64, x86_64, or both)." >&2; exit 1 ;;
  esac
  case " $BUILT " in *" $arch "*) continue ;; esac
  xcrun --sdk macosx swiftc -swift-version 6 -module-name PwdHashMac -sdk "$SDK_PATH" \
    -target "$arch-apple-macosx13.0" -module-cache-path .build/macos/ModuleCache \
    $SWIFT_FLAGS -whole-module-optimization -emit-executable \
    src/MacOS/App/*.swift src/IOS/PwdHash/Core/*.swift -o "$SLICES/PwdHash-$arch"
  BUILT="${BUILT:+$BUILT }$arch"
  SLICE_FILES="${SLICE_FILES:+$SLICE_FILES }$SLICES/PwdHash-$arch"
done
case "$BUILT" in
  '') echo "No architecture selected." >&2; exit 1 ;;
  *' '*) xcrun lipo -create $SLICE_FILES -output "$APP/Contents/MacOS/PwdHash" ;;
  *) cp "$SLICE_FILES" "$APP/Contents/MacOS/PwdHash" ;;
esac

# Xcode writes toolchain metadata for its projects. The standalone build reads
# the equivalent values from the installed tools for manual packaging.
INFO="$APP/Contents/Info.plist"
cp src/MacOS/App/Info.plist "$INFO"
XCODE_TEXT="$(xcodebuild -version)"
XCODE_VERSION="$(printf '%s\n' "$XCODE_TEXT" | sed -n 's/^Xcode //p')"
XCODE_BUILD="$(printf '%s\n' "$XCODE_TEXT" | sed -n 's/^Build version //p')"
PLATFORM_PATH="$(xcrun --sdk macosx --show-sdk-platform-path)"
set_key() {
  case "$2" in
    ''|*[!A-Za-z0-9._-]*) echo "Could not read a usable value for $1 from the installed tools." >&2; exit 1 ;;
  esac
  plutil -replace "$1" -string "$2" "$INFO"
}
set_key DTCompiler com.apple.compilers.llvm.clang.1_0
set_key DTPlatformName macosx
set_key DTPlatformVersion "$(xcrun --sdk macosx --show-sdk-platform-version)"
set_key DTPlatformBuild "$(/usr/libexec/PlistBuddy -c 'Print :ProductBuildVersion' "$PLATFORM_PATH/version.plist")"
set_key DTSDKName "$(/usr/libexec/PlistBuddy -c 'Print :CanonicalName' "$SDK_PATH/SDKSettings.plist")"
set_key DTSDKBuild "$(xcrun --sdk macosx --show-sdk-build-version)"
set_key DTXcode "$(printf '%s\n' "$XCODE_VERSION" | awk -F. '{ printf "%02d%d%d", $1, $2, $3 }')"
set_key DTXcodeBuild "$XCODE_BUILD"
set_key BuildMachineOSBuild "$(sw_vers -buildVersion)"
plutil -lint "$INFO" >/dev/null

cp src/IOS/PwdHash/PrivacyInfo.xcprivacy src/IOS/PwdHash/ThirdPartyNotices.txt "$APP/Contents/Resources/"
sh scripts/prepare-macos-assets.sh "$ASSET_CATALOG"
xcrun actool --compile "$APP/Contents/Resources" \
  --platform macosx --target-device mac --minimum-deployment-target 13.0 \
  --app-icon AppIcon --output-partial-info-plist .build/macos/assetcatalog-info.plist \
  "$ASSET_CATALOG" >/dev/null
# Copied files can carry a download quarantine mark, which the App Store rejects.
xattr -cr "$APP"
# Local builds are signed ad hoc. scripts/package-macos-appstore.sh signs for the App Store.
codesign --force --sign - --options runtime --entitlements src/MacOS/App/PwdHash.entitlements --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"
echo "Built $APP ($BUILT)"
