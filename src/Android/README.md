# PwdHash for Android

Native Java/Android-framework app. Application ID: `app.nmic.pwdhash`.
Android 10/API 29 or later; built against API 36. No third-party runtime
dependencies, Internet permission, accounts, saved fields, preferences, or history.

From the repository root:

```sh
export JAVA_HOME=/path/to/jdk-17
export ANDROID_HOME=/path/to/android-sdk
make android
make install-android
```

The Gradle wrapper pins Gradle 8.13 and its checksum. AGP is pinned to 8.13.2.
Install SDK `platforms;android-36`, `build-tools;35.0.0`, and `platform-tools`.
An optional `GRADLE_BIN` can select an existing Gradle 8.13 executable.
Machine-specific exports may go in ignored `.build/android-env.sh`.

The debug APK is `.build/android/app/outputs/apk/debug/app-debug.apk`.

## Google Play release bundle

```sh
PWDHASH_ANDROID_SIGNING_PROPERTIES=/path/to/keystore.properties make android-release
```

This builds the upload-signed AAB, runs release lint, verifies the JAR signature,
and copies the bundle to `dist/android/PwdHash-VERSION-CODE.aab`. Set
`PWDHASH_ANDROID_SIGNING_PROPERTIES` to an absolute path outside the checkout.
The signing properties are `storeFile`, `storeType`, `storePassword`,
`keyAlias`, and `keyPassword`. The debug build uses the Android debug key.

## App behaviour

The screen has a hidden editable password, hold/release eye buttons,
explicit Generate, stale-result invalidation, Copy, Clear, a background option,
and inline credits/contact/license. Password masking includes the last character.
Screenshots and recording are blocked with `FLAG_SECURE`. Rotation resizes the
same screen; process/activity recreation starts with empty inputs. Backup and
state restoration of credentials are disabled.

For store and website screenshots using synthetic inputs, connect and unlock an
Android phone, then run `sh scripts/capture-android-screenshots.sh`. The script
uses test-only instrumentation, restores screenshot protection and display size,
and removes the test APK. Captures go to `.build/android/store-screenshots/`.

Five idle minutes clears the current fields. Background clearing starts on and
clears immediately when the Activity stops. Turning it off retains the current
session while switching apps, with expiry enforced before it can be used again.
Android may freeze a background process, so that mode does not guarantee erasure
at exactly five minutes while suspended.

Copy marks the item sensitive and sets an in-memory 60-second cleanup deadline.
Android restricts background clipboard access: this app clears its expired copy
while it has focus and checks again on returning. Android's own clipboard expiry
is controlled by the OS. The screen states that limitation. A newer copy from
another app is preserved. Keyboard password/privacy flags are set, but Android
controls which keyboard the user has enabled.

Checks:

```sh
make test-android-core
sh scripts/build-android.sh lintDebug assembleDebugAndroidTest
make test-android-device
```

The host and device suites compare all 6,111 synthetic cases with the original
website JavaScript. Device tests also exercise masks, reveal/edit/release,
Copy/Clear, expiry, actual app switching, and empty saved state. They use synthetic
inputs and replace the phone's clipboard with synthetic test copies.
Connect one unlocked phone with USB debugging, or set `ANDROID_DEVICE_ID`.

Personal hobby project by Nenad Micic, based on Stanford PwdHash.
Contact: [pwdhash@nmic.app](mailto:pwdhash@nmic.app).
