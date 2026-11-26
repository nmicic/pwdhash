#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
if [ -f .build/android-env.sh ]; then . .build/android-env.sh; fi
if [ -z "${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}" ] || [ -z "${JAVA_HOME:-}" ]; then
  echo 'Set ANDROID_HOME and JAVA_HOME, or configure .build/android-env.sh.' >&2
  exit 1
fi
if [ -z "${PWDHASH_ANDROID_SIGNING_PROPERTIES:-}" ] || [ ! -f "$PWDHASH_ANDROID_SIGNING_PROPERTIES" ]; then
  echo 'Set PWDHASH_ANDROID_SIGNING_PROPERTIES to the path of your signing properties file.' >&2
  echo 'Configure storeFile, storePassword, keyAlias, keyPassword, and storeType for your upload key.' >&2
  exit 1
fi
export PWDHASH_ANDROID_SIGNING_PROPERTIES
if [ -n "${GRADLE_BIN:-}" ]; then
  "$GRADLE_BIN" -p src/Android :app:bundleRelease :app:lintRelease --console=plain "$@"
else
  src/Android/gradlew -p src/Android :app:bundleRelease :app:lintRelease --console=plain "$@"
fi
BUNDLE=.build/android/app/outputs/bundle/release/app-release.aab
VERIFY_LOG=.build/android/release-signature.txt
"$JAVA_HOME/bin/jarsigner" -J-Duser.language=en -J-Duser.country=US -verify "$BUNDLE" > "$VERIFY_LOG" 2>&1
python3 - "$BUNDLE" "$VERIFY_LOG" <<'PY'
import hashlib
import re
import shutil
import sys
import zipfile
from pathlib import Path

bundle = Path(sys.argv[1])
verification = Path(sys.argv[2]).read_text()
if 'jar verified.' not in verification:
    raise SystemExit('Bundle signature was not verified; inspect .build/android/release-signature.txt.')
with zipfile.ZipFile(bundle) as package:
    names = package.namelist()
    if not any(re.fullmatch(r'META-INF/[^/]+\.(RSA|DSA|EC)', name) for name in names):
        raise SystemExit('Release bundle has no signing certificate.')
config = Path('src/Android/app/build.gradle').read_text()
version = re.search(r"versionName\s+'([^']+)'", config).group(1)
code = re.search(r'versionCode\s+(\d+)', config).group(1)
filename_version = re.sub(r'[^A-Za-z0-9._-]', '_', version)
destination = Path('dist/android') / f'PwdHash-{filename_version}-{code}.aab'
destination.parent.mkdir(parents=True, exist_ok=True)
shutil.copy2(bundle, destination)
print(f'Signed bundle: {destination.resolve()}')
print(f'Version {version}, version code {code}')
print(f'SHA-256: {hashlib.sha256(destination.read_bytes()).hexdigest()}')
PY
