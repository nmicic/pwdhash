#!/bin/sh
# Build the macOS icon catalog from the committed 1024-pixel source icon.
set -eu
asset_catalog=${1:?Usage: sh scripts/prepare-macos-assets.sh ASSET_CATALOG}
repo_dir=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
icon_set="$asset_catalog/AppIcon.appiconset"
source_icon="$repo_dir/src/IOS/PwdHash/Assets.xcassets/AppIcon.appiconset/AppIcon.png"

mkdir -p "$icon_set"
cp "$repo_dir/src/MacOS/Assets.xcassets/Contents.json" "$asset_catalog/Contents.json"
cp "$repo_dir/src/MacOS/Assets.xcassets/AppIcon.appiconset/Contents.json" "$icon_set/Contents.json"
while read -r filename pixels; do
    sips --resampleHeightWidth "$pixels" "$pixels" "$source_icon" --out "$icon_set/$filename" >/dev/null
done <<'SIZES'
icon_16x16.png 16
icon_16x16@2x.png 32
icon_32x32.png 32
icon_32x32@2x.png 64
icon_128x128.png 128
icon_128x128@2x.png 256
icon_256x256.png 256
icon_256x256@2x.png 512
icon_512x512.png 512
icon_512x512@2x.png 1024
SIZES
