#!/usr/bin/env python3
"""Run actual iPhone lifecycle tests on a disposable compatible simulator with account configuration empty."""
import json
import os
from pathlib import Path
import platform
import subprocess
import uuid


def simulator_pair(types, runtimes, architecture):
    available = [runtime for runtime in runtimes if runtime.get('isAvailable') and
                 runtime['identifier'].startswith('com.apple.CoreSimulator.SimRuntime.iOS-') and
                 (not runtime.get('supportedArchitectures') or architecture in runtime['supportedArchitectures'])]
    for runtime in sorted(available, key=lambda item: tuple(int(v) for v in item['version'].split('.')), reverse=True):
        parts = [int(v) for v in runtime['version'].split('.')]
        parts += [0] * (3 - len(parts))
        version = (parts[0] << 16) + (parts[1] << 8) + parts[2]
        supported = {device['identifier'] for device in runtime.get('supportedDeviceTypes', [])}
        compatible = [device for device in types if device.get('productFamily') == 'iPhone' and
                      (not supported or device['identifier'] in supported) and
                      device.get('minRuntimeVersion', 0) <= version <= device.get('maxRuntimeVersion', 0xffffffff)]
        if compatible:
            device = next((device for device in compatible if device['name'] == 'iPhone 17 Pro'), compatible[0])
            return device['identifier'], runtime['identifier']
    raise ValueError('An installed compatible iPhone simulator runtime is required; no runtime will be downloaded.')


def main():
    os.umask(0o077)
    root = Path(__file__).resolve().parents[1]
    def run(args):
        return subprocess.check_output(args, text=True).strip()
    types = json.loads(run(['xcrun', 'simctl', 'list', 'devicetypes', '--json']))['devicetypes']
    runtimes = json.loads(run(['xcrun', 'simctl', 'list', 'runtimes', '--json']))['runtimes']
    device_type, runtime = simulator_pair(types, runtimes, platform.machine())
    identifier = run(['xcrun', 'simctl', 'create', 'Clepso isolated unit tests', device_type, runtime])
    try:
        log = root / '.build/ci-logs/mobile_native_tests.log'
        log.parent.mkdir(parents=True, exist_ok=True)
        if log.exists():
            log.rename(log.with_name('mobile_native_tests-' + uuid.uuid4().hex + '.log'))
        results = root / 'build/mobile-unit-results'
        results.mkdir(parents=True, exist_ok=True)
        with log.open('w') as stream:
            result = subprocess.run(['xcodebuild', '-project', 'Clepso.xcodeproj', '-scheme', 'ClepsoPhone',
                '-destination', 'platform=iOS Simulator,id=' + identifier, '-derivedDataPath', 'build/mobile-tests',
                '-resultBundlePath', str(results / (uuid.uuid4().hex + '.xcresult')), 'CODE_SIGN_IDENTITY=-', 'CODE_SIGN_STYLE=Manual',
                'DEVELOPMENT_TEAM=', 'CLEPSO_SYNC_HOST=', 'CLEPSO_SYNC_PUBLISHABLE_KEY=', 'test'],
                cwd=root, stdout=stream, stderr=subprocess.STDOUT)
        print('Isolated iPhone model tests:', 'PASS' if result.returncode == 0 else 'FAIL (private build/test log)')
        return result.returncode
    finally:
        subprocess.run(['xcrun', 'simctl', 'shutdown', identifier], capture_output=True)
        subprocess.run(['xcrun', 'simctl', 'delete', identifier], check=True, capture_output=True)
        print('Removed only this test simulator; physical devices and existing simulators unchanged.')


if __name__ == '__main__':
    raise SystemExit(main())
