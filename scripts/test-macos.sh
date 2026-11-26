#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
APP=.build/macos-tests/PwdHashTests.app
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" .build/macos/ModuleCache
xcrun --sdk macosx swiftc -swift-version 6 -parse-as-library -module-name PwdHashMacTests \
  -module-cache-path .build/macos/ModuleCache \
  src/MacOS/App/SecretField.swift src/MacOS/App/PasswordViewController.swift \
  src/MacOS/App/AddressCaution.swift src/MacOS/App/AppDelegate.swift \
  src/IOS/PwdHash/Core/*.swift Tests/MacOS/UITests.swift -o "$APP/Contents/MacOS/PwdHashTests"
python3 - "$APP" <<'PY'
import pathlib, plistlib, sys
app=pathlib.Path(sys.argv[1])
p=plistlib.loads(pathlib.Path('src/MacOS/App/Info.plist').read_bytes())
p['CFBundleIdentifier']='app.nmic.pwdhash.tests'
p['CFBundleExecutable']='PwdHashTests'
(app/'Contents/Info.plist').write_bytes(plistlib.dumps(p))
PY
cp src/IOS/PwdHash/ThirdPartyNotices.txt "$APP/Contents/Resources/"
codesign --force --sign - "$APP"
"$APP/Contents/MacOS/PwdHashTests" "$PWD/.build/macos-tests/preview.png"
