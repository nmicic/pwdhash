#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
if [ -f .build/android-env.sh ]; then . .build/android-env.sh; fi
ADB="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}/platform-tools/adb"
if [ ! -x "$ADB" ]; then echo 'Set ANDROID_HOME to an Android SDK with platform-tools.' >&2; exit 1; fi
if [ -z "${ANDROID_DEVICE_ID:-}" ]; then
  ANDROID_DEVICE_ID="$("$ADB" devices | awk 'NR>1 && $2=="device" {print $1}')"
  if [ "$(printf '%s\n' "$ANDROID_DEVICE_ID" | awk 'NF {n++} END {print n+0}')" != 1 ]; then
    echo 'Connect one unlocked Android phone with USB debugging, or set ANDROID_DEVICE_ID.' >&2
    exit 1
  fi
fi
sh scripts/build-android.sh assembleDebugAndroidTest --console=plain
"$ADB" -s "$ANDROID_DEVICE_ID" install -r .build/android/app/outputs/apk/debug/app-debug.apk
"$ADB" -s "$ANDROID_DEVICE_ID" install -r -t .build/android/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk
ORIGINAL_SIZE="$("$ADB" -s "$ANDROID_DEVICE_ID" shell wm size | sed -n 's/^Override size: //p' | tr -d '\r')"
cleanup() {
  "$ADB" -s "$ANDROID_DEVICE_ID" shell am force-stop app.nmic.pwdhash >/dev/null 2>&1 || :
  "$ADB" -s "$ANDROID_DEVICE_ID" shell run-as app.nmic.pwdhash rm -rf cache/store-screenshots >/dev/null 2>&1 || :
  "$ADB" -s "$ANDROID_DEVICE_ID" shell wm size "${ORIGINAL_SIZE:-reset}" >/dev/null 2>&1 || :
  "$ADB" -s "$ANDROID_DEVICE_ID" uninstall app.nmic.pwdhash.test >/dev/null 2>&1 || :
  "$ADB" -s "$ANDROID_DEVICE_ID" shell am start -n app.nmic.pwdhash/.MainActivity >/dev/null 2>&1 || :
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
# A real 9:16 Android viewport meets Play's screenshot aspect-ratio requirements.
# Restore the phone's original display override on exit, including on failure.
"$ADB" -s "$ANDROID_DEVICE_ID" shell wm size 1080x1920
mkdir -p .build/android
"$ADB" -s "$ANDROID_DEVICE_ID" shell am instrument -w -r -e screenshots true \
  app.nmic.pwdhash.test/app.nmic.pwdhash.test.PwdHashInstrumentation > .build/android/screenshot-capture.txt
cat .build/android/screenshot-capture.txt
if ! rg -q 'INSTRUMENTATION_RESULT: result=PASS' .build/android/screenshot-capture.txt; then exit 1; fi
DESTINATION=.build/android/store-screenshots
mkdir -p "$DESTINATION"
for name in 01-generated-hidden.png 02-hold-to-reveal.png 03-keep-while-switching.png; do
  "$ADB" -s "$ANDROID_DEVICE_ID" exec-out run-as app.nmic.pwdhash cat "cache/store-screenshots/$name" > "$DESTINATION/$name"
done
printf 'Saved Android screenshots to %s\n' "$DESTINATION"
