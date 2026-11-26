#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
if [ -f .build/android-env.sh ]; then . .build/android-env.sh; fi
if [ "${SKIP_BUILD:-0}" != 1 ]; then sh scripts/build-android.sh; fi
ADB="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}/platform-tools/adb"
if [ -z "${ANDROID_DEVICE_ID:-}" ]; then
  ANDROID_DEVICE_ID="$("$ADB" devices | awk 'NR>1 && $2=="device" {print $1}')"
  if [ "$(printf '%s\n' "$ANDROID_DEVICE_ID" | awk 'NF {n++} END {print n+0}')" != 1 ]; then
    echo 'Connect one Android phone with USB debugging enabled, or set ANDROID_DEVICE_ID.' >&2
    exit 1
  fi
fi
"$ADB" -s "$ANDROID_DEVICE_ID" install -r .build/android/app/outputs/apk/debug/app-debug.apk
"$ADB" -s "$ANDROID_DEVICE_ID" shell am start -n app.nmic.pwdhash/.MainActivity
