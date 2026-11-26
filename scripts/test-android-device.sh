#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
if [ -f .build/android-env.sh ]; then . .build/android-env.sh; fi
node scripts/reference-vectors.mjs
mkdir -p .build/android-test-assets
cp .build/reference-vectors.json .build/android-test-assets/
sh scripts/build-android.sh assembleDebugAndroidTest
ADB="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}/platform-tools/adb"
if [ -z "${ANDROID_DEVICE_ID:-}" ]; then
  ANDROID_DEVICE_ID="$("$ADB" devices | awk 'NR>1 && $2=="device" {print $1}')"
  if [ "$(printf '%s\n' "$ANDROID_DEVICE_ID" | awk 'NF {n++} END {print n+0}')" != 1 ]; then
    echo 'Connect one unlocked Android phone with USB debugging enabled, or set ANDROID_DEVICE_ID.' >&2
    exit 1
  fi
fi
"$ADB" -s "$ANDROID_DEVICE_ID" install -r .build/android/app/outputs/apk/debug/app-debug.apk
"$ADB" -s "$ANDROID_DEVICE_ID" install -r .build/android/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk
"$ADB" -s "$ANDROID_DEVICE_ID" shell am instrument -w -r app.nmic.pwdhash.test/app.nmic.pwdhash.test.PwdHashInstrumentation > .build/android-device-tests.txt
cat .build/android-device-tests.txt
if ! rg -q 'INSTRUMENTATION_RESULT: result=PASS' .build/android-device-tests.txt; then exit 1; fi
"$ADB" -s "$ANDROID_DEVICE_ID" uninstall app.nmic.pwdhash.test >/dev/null
"$ADB" -s "$ANDROID_DEVICE_ID" shell am start -n app.nmic.pwdhash/.MainActivity
