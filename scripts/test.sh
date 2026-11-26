#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build/ModuleCache
node scripts/reference-vectors.mjs
python3 -m unittest discover -s Tests -p '*Tests.py'
cc -std=c11 -g -O1 -fsanitize=address,undefined -fno-omit-frame-pointer \
  -Wall -Wextra -Wpedantic -Werror Tests/CLICoreTests.c -o .build/cli/core-sanitizers
.build/cli/core-sanitizers
if [ "$(uname -s)" = Darwin ]; then
  swiftc -module-cache-path .build/ModuleCache -parse-as-library \
    src/IOS/PwdHash/Core/LegacyPwdHash.swift src/IOS/PwdHash/Core/IdleDeadline.swift \
    Tests/CompatibilityTests.swift -o .build/compatibility-tests
  .build/compatibility-tests .build/reference-vectors.json
fi
