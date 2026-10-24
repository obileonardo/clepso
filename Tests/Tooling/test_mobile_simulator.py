import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('mobile', Path(__file__).resolve().parents[2] / 'scripts/test-mobile.py')
mobile = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mobile)


class SimulatorSelectionTests(unittest.TestCase):
    devices = [{'identifier': 'old', 'name': 'iPhone 17 Pro', 'productFamily': 'iPhone'},
               {'identifier': 'new', 'name': 'iPhone 18 Pro', 'productFamily': 'iPhone'}]
    def runtime(self, version, supported, architectures=('arm64',)):
        return {'identifier': 'com.apple.CoreSimulator.SimRuntime.iOS-' + version.replace('.', '-'),
                'version': version, 'isAvailable': True, 'supportedArchitectures': architectures,
                'supportedDeviceTypes': [{'identifier': name} for name in supported]}

    def test_newest_runtime_can_exclude_the_preferred_device(self):
        old = self.runtime('27.0', ['old', 'new'])
        new = self.runtime('27.1', ['new'])
        self.assertEqual(mobile.simulator_pair(self.devices, [old, new], 'arm64'), ('new', new['identifier']))

    def test_incompatible_architecture_and_unavailable_runtime_are_excluded(self):
        old = self.runtime('27.0', ['old'])
        new = self.runtime('27.1', ['new'], ('x86_64',))
        future = self.runtime('28.0', ['new']); future['isAvailable'] = False
        self.assertEqual(mobile.simulator_pair(self.devices, [old, new, future], 'arm64'), ('old', old['identifier']))

    def test_minimum_os_version_and_missing_runtime_do_not_silently_skip_testing(self):
        devices = [dict(self.devices[0], minRuntimeVersion=(28 << 16))]
        with self.assertRaises(ValueError):
            mobile.simulator_pair(devices, [self.runtime('27.0', ['old'])], 'arm64')
        with self.assertRaises(ValueError):
            mobile.simulator_pair(self.devices, [], 'arm64')


if __name__ == '__main__':
    unittest.main()
