#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
if [ -f .build/android-env.sh ]; then . .build/android-env.sh; fi
node scripts/reference-vectors.mjs
python3 scripts/test-android-core.py
