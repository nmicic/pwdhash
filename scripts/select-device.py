#!/usr/bin/env python3
import json
from pathlib import Path
import plistlib
import sys

devices = json.loads(Path(sys.argv[1]).read_text())['result']['devices']
raw = Path(sys.argv[2]).read_bytes()
profile = plistlib.loads(raw[raw.index(b'<?xml'):raw.index(b'</plist>') + 8])
registered = set(profile.get('ProvisionedDevices', []))
matches = []
for device in devices:
    # Xcode 27 moves these under properties. Keep older devicectl support.
    properties = device.get('properties', {})
    hardware = {**device.get('hardwareProperties', {}), **properties.get('hardware', {})}
    connection = {**device.get('connectionProperties', {}), **properties.get('connection', {})}
    if hardware.get('udid') not in registered:
        continue
    if hardware.get('platform') not in ('iOS', 'iPhoneOS'):
        continue
    state = connection.get('state', connection.get('tunnelState'))
    transport = connection.get('transportType')
    # A paired USB phone is available before its developer tunnel is opened.
    # install app establishes that tunnel; requiring it here rejects the phone.
    usb_available = transport in ('wired', 'usb') and connection.get('pairingState') == 'paired'
    if state != 'connected' and not usb_available:
        continue
    matches.append((hardware['udid'], transport))
wired = [d for d in matches if d[1] in ('wired', 'usb')]
matches = wired or matches
if len(matches) != 1:
    sys.exit('Could not select one connected, registered iPhone. Set DEVICE_ID to its identifier from xcrun devicectl list devices.')
print(matches[0][0])
