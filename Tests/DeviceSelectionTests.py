import copy
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / 'scripts/select-device.py'


def device(udid='SYNTHETIC-USB', transport='wired', state='disconnected', modern=True):
    hardware = {'udid': udid, 'platform': 'iOS'}
    connection = {'transportType': transport, 'pairingState': 'paired'}
    if modern:
        connection['state'] = state
        return {'identifier': 'INTERNAL-IDENTIFIER', 'properties': {'hardware': hardware, 'connection': connection}}
    connection['tunnelState'] = state
    return {'identifier': 'INTERNAL-IDENTIFIER', 'hardwareProperties': hardware, 'connectionProperties': connection}


class DeviceSelectionTests(unittest.TestCase):
    def select(self, devices):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            listing, profile = folder / 'devices.json', folder / 'profile.mobileprovision'
            listing.write_text(json.dumps({'result': {'devices': devices}}))
            profile.write_bytes(plistlib.dumps({'ProvisionedDevices': ['SYNTHETIC-USB', 'SYNTHETIC-SECOND']}))
            return subprocess.run(['python3', str(SCRIPT), str(listing), str(profile)], capture_output=True, text=True)

    def test_paired_usb_without_tunnel(self):
        result = self.select([device()])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), 'SYNTHETIC-USB')

    def test_old_paired_usb_without_tunnel(self):
        result = self.select([device(modern=False)])
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_old_connected_device(self):
        result = self.select([device(state='connected', modern=False)])
        self.assertEqual(result.stdout.strip(), 'SYNTHETIC-USB')

    def test_modern_properties_override_deprecated_fields(self):
        current = device()
        current['hardwareProperties'] = {'udid': 'STALE-DEVICE', 'platform': 'other'}
        current['connectionProperties'] = {'transportType': 'wifi', 'pairingState': 'unpaired'}
        result = self.select([current])
        self.assertEqual(result.stdout.strip(), 'SYNTHETIC-USB')

    def test_usb_preferred_over_connected_wifi(self):
        result = self.select([device('SYNTHETIC-SECOND', 'wifi', 'connected'), device()])
        self.assertEqual(result.stdout.strip(), 'SYNTHETIC-USB')

    def test_rejects_unregistered_phone(self):
        self.assertNotEqual(self.select([device('UNREGISTERED')]).returncode, 0)

    def test_rejects_two_usb_phones(self):
        self.assertNotEqual(self.select([device(), device('SYNTHETIC-SECOND')]).returncode, 0)

    def test_rejects_unreachable_wifi(self):
        self.assertNotEqual(self.select([device(transport='wifi')]).returncode, 0)

    def test_rejects_unpaired_usb(self):
        candidate = copy.deepcopy(device())
        candidate['properties']['connection']['pairingState'] = 'unpaired'
        self.assertNotEqual(self.select([candidate]).returncode, 0)


if __name__ == '__main__':
    unittest.main()
