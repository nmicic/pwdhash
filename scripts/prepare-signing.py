#!/usr/bin/env python3
"""Select an existing matching profile and certificate, never import a key."""
import datetime
import fnmatch
import hashlib
import os
from pathlib import Path
import plistlib
import re
import shutil
import sys

root = Path(__file__).resolve().parents[1]
app = Path(sys.argv[1]).resolve()
bundle = plistlib.loads((app / 'Info.plist').read_bytes())['CFBundleIdentifier']
identities = set(re.findall(r'\b[0-9A-F]{40}\b', (root / '.build/signing-identities.txt').read_text()))
if not identities:
    sys.exit('No accessible Apple Development signing identity. Run this command from a terminal with access to your login keychain.')

override = os.environ.get('PROVISIONING_PROFILE')
profiles = [Path(override).expanduser()] if override else [
    *Path('~/Library/Developer/Xcode/UserData/Provisioning Profiles').expanduser().glob('*.mobileprovision'),
    *Path('~/Library/MobileDevice/Provisioning Profiles').expanduser().glob('*.mobileprovision'),
]
matches = []
for path in profiles:
    raw = path.read_bytes()
    start, end = raw.find(b'<?xml'), raw.find(b'</plist>')
    if start < 0 or end < start:
        continue
    profile = plistlib.loads(raw[start:end + len(b'</plist>')])
    entitlements = profile.get('Entitlements', {})
    team = profile.get('ApplicationIdentifierPrefix', profile.get('TeamIdentifier', []))
    if not team or not profile.get('ProvisionedDevices') or not entitlements.get('get-task-allow'):
        continue
    if profile['ExpirationDate'] <= datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None):
        continue
    if not fnmatch.fnmatchcase(f'{team[0]}.{bundle}', entitlements.get('application-identifier', '')):
        continue
    certs = {hashlib.sha1(cert).hexdigest().upper() for cert in profile.get('DeveloperCertificates', [])}
    usable = identities & certs
    if usable:
        matches.append((profile['ExpirationDate'], path, profile, sorted(usable)[0]))
if not matches:
    sys.exit('No existing development profile matches this bundle ID and an accessible certificate. Set PROVISIONING_PROFILE to a matching .mobileprovision file.')
_, path, profile, identity = max(matches, key=lambda item: item[0])
prefix = profile.get('ApplicationIdentifierPrefix', profile['TeamIdentifier'])[0]
entitlements = {
    'application-identifier': f'{prefix}.{bundle}',
    'com.apple.developer.team-identifier': profile['TeamIdentifier'][0],
    'get-task-allow': True,
}
shutil.copyfile(path, app / 'embedded.mobileprovision')
(root / '.build/Signing.entitlements').write_bytes(plistlib.dumps(entitlements))
(root / '.build/signing-identity.txt').write_text(identity)
print('Using existing development profile:', profile.get('Name', path.name))
