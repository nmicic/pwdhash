#!/usr/bin/env python3
"""Verify the actual Java core with the unmodified JS compatibility corpus."""
import base64
import json
import os
from pathlib import Path
import shutil
import subprocess

root = Path(__file__).resolve().parents[1]
build = root / '.build/android-core-tests'
build.mkdir(parents=True, exist_ok=True)
java_home = os.environ.get('JAVA_HOME')
javac = str(Path(java_home) / 'bin/javac') if java_home else shutil.which('javac')
java = str(Path(java_home) / 'bin/java') if java_home else shutil.which('java')
if not javac or not java:
    raise SystemExit('Set JAVA_HOME to JDK 17 to run the Android core tests.')
core = root / 'src/Android/app/src/main/java/app/nmic/pwdhash'
subprocess.run([javac, '-encoding', 'UTF-8', '-d', str(build), str(core / 'LegacyPwdHash.java'), str(core / 'IdleDeadline.java'), str(root / 'Tests/Android/CompatibilityProbe.java')], check=True)
vectors = json.loads((root / '.build/reference-vectors.json').read_text())
def encode(text):
    return base64.b64encode(text.encode('utf-8')).decode('ascii')
input_text = ''.join(encode(v['address']) + '\t' + encode(v['password']) + '\n' for v in vectors)
result = subprocess.run([java, '-cp', str(build), 'app.nmic.pwdhash.CompatibilityProbe'], input=input_text, capture_output=True, text=True, check=True)
lines = result.stdout.splitlines()
assert len(lines) == len(vectors), 'Missing Java reference results'
for index, (line, vector) in enumerate(zip(lines, vectors)):
    if vector['domain'] is None:
        assert line == 'ERROR', f'Java invalid-domain mismatch in synthetic case {index}'
    else:
        domain, password = line.split('\t')
        assert base64.b64decode(domain).decode('utf-8') == vector['domain'], f'Java domain mismatch in synthetic case {index}'
        assert base64.b64decode(password).decode('utf-8') == vector['result'], f'Java output mismatch in synthetic case {index}'
print(f'PASS: Android Java matches all {len(vectors)} original-website cases and idle deadline boundaries')
