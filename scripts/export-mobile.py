#!/usr/bin/env python3
"""Build and verify a production APNs App Store Connect export; never uploads or accepts agreements."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile
import zipfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build', required=True, type=int)
    parser.add_argument('--team-id', required=True)
    args = parser.parse_args()
    if args.build < 1 or not re.fullmatch(r'[A-Z0-9]{10}', args.team_id):
        parser.error('Use a positive build number and explicit Apple Team ID')
    root = Path(__file__).resolve().parents[1]
    os.chdir(root)
    os.umask(0o077)
    folder = root / 'build/mobile-distribution' / str(args.build)
    if folder.exists():
        parser.error('This build output already exists; review it and choose a fresh build number')
    folder.mkdir(parents=True)
    def run(arguments, label):
        with (folder / (label + '.log')).open('w') as log:
            result = subprocess.run(arguments, stdout=log, stderr=subprocess.STDOUT)
        if result.returncode:
            raise SystemExit(label + ' failed; private log retained under build/mobile-distribution/' + str(args.build))
    run(['.tools/xcodegen/bin/xcodegen', 'generate'], 'generate')
    archive = folder / 'ClepsoPhone.xcarchive'
    run(['xcodebuild', '-project', 'Clepso.xcodeproj', '-scheme', 'ClepsoPhone', '-configuration', 'Release',
         '-destination', 'generic/platform=iOS', '-archivePath', str(archive), '-derivedDataPath', 'build/mobile-distribution-derived',
         '-allowProvisioningUpdates', 'DEVELOPMENT_TEAM=' + args.team_id, 'CURRENT_PROJECT_VERSION=' + str(args.build),
         'CLEPSO_PUSH_ENVIRONMENT=production', 'archive'], 'archive')
    options = folder / 'ExportOptions.plist'
    options.write_bytes(plistlib.dumps({'method': 'app-store-connect', 'destination': 'export', 'signingStyle': 'automatic',
                                      'teamID': args.team_id, 'manageAppVersionAndBuildNumber': False, 'uploadSymbols': True}))
    exported = folder / 'export'
    run(['xcodebuild', '-exportArchive', '-archivePath', str(archive), '-exportPath', str(exported),
         '-exportOptionsPlist', str(options), '-allowProvisioningUpdates'], 'export')
    packages = list(exported.glob('*.ipa'))
    if len(packages) != 1:
        raise SystemExit('Expected exactly one exported IPA')
    package = packages[0]
    with tempfile.TemporaryDirectory(prefix='clepso-mobile-export-') as temporary:
        base = Path(temporary)
        with zipfile.ZipFile(package) as source:
            for member in source.infolist():
                if not (base / member.filename).resolve().is_relative_to(base.resolve()):
                    raise SystemExit('Unexpected path in export')
        # ditto preserves executable bits and framework links in Apple's exported package.
        run(['/usr/bin/ditto', '-x', '-k', str(package), str(base)], 'unpack')
        apps = list((base / 'Payload').glob('*.app'))
        if len(apps) != 1:
            raise SystemExit('Unexpected app count in export')
        app = apps[0]
        run(['codesign', '--verify', '--deep', '--strict', str(app)], 'signature')
        watch_apps = list((app / 'Watch').glob('*.app'))
        if len(watch_apps) != 1:
            raise SystemExit('Expected the paired Watch app in the export')
        for bundle in [app, *watch_apps]:
            privacy = plistlib.loads((bundle / 'PrivacyInfo.xcprivacy').read_bytes())
            if privacy.get('NSPrivacyTracking') is not False:
                raise SystemExit('Expected the reviewed non-tracking privacy manifest')
        info = plistlib.loads((app / 'Info.plist').read_bytes())
        entitlements = plistlib.loads(subprocess.check_output(['codesign', '-d', '--entitlements', ':-', str(app)], stderr=subprocess.DEVNULL))
        if (info.get('CFBundleIdentifier') != 'com.elvisobi.clepso.mobile' or
            info.get('ClepsoPushEnvironment') != 'production' or entitlements.get('aps-environment') != 'production' or
            entitlements.get('application-identifier') != args.team_id + '.com.elvisobi.clepso.mobile' or
            entitlements.get('get-task-allow') is True or str(info.get('CFBundleVersion')) != str(args.build)):
            raise SystemExit('Exported app identity, build or production push configuration does not agree')
        receipt = {'bundle_identifier': info['CFBundleIdentifier'], 'version': info['CFBundleShortVersionString'],
                   'build': str(args.build), 'method': 'app-store-connect', 'aps_environment': 'production',
                   'strict_signature_verified': True, 'watch_embedded': bool(list((app / 'Watch').glob('*.app'))),
                   'sha256': hashlib.sha256(package.read_bytes()).hexdigest(), 'uploaded': False}
    (folder / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print('Production export verified. No upload performed; review build/mobile-distribution/' + str(args.build) + '/receipt.json.')


if __name__ == '__main__':
    main()
