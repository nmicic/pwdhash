#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
if [ -f .build/android-env.sh ]; then . .build/android-env.sh; fi
if [ -z "${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}" ]; then
  echo 'Set ANDROID_HOME to an Android SDK with platforms;android-36 and build-tools;35.0.0.' >&2
  exit 1
fi
if [ -z "${JAVA_HOME:-}" ]; then
  echo 'Set JAVA_HOME to JDK 17.' >&2
  exit 1
fi
if [ -n "${GRADLE_BIN:-}" ]; then
  "$GRADLE_BIN" -p src/Android "$@" assembleDebug
else
  src/Android/gradlew -p src/Android "$@" assembleDebug
fi
