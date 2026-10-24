#!/usr/bin/env python3
"""Run actual iPhone lifecycle tests on a new disposable simulator, with account configuration empty."""
import json,os,subprocess,uuid
from pathlib import Path
os.umask(0o077)
root=Path(__file__).resolve().parents[1]
def run(args): return subprocess.check_output(args,text=True).strip()
types=json.loads(run(['xcrun','simctl','list','devicetypes','--json']))['devicetypes']
runtimes=json.loads(run(['xcrun','simctl','list','runtimes','--json']))['runtimes']
available=[d for d in runtimes if d.get('isAvailable') and d['identifier'].startswith('com.apple.CoreSimulator.SimRuntime.iOS-')]
if not available: raise SystemExit('An installed iOS simulator runtime is required; this test never downloads one.')
runtime=max(available,key=lambda d:tuple(int(v) for v in d['version'].split('.')))['identifier']
device_type=next(d['identifier'] for d in types if d['name']=='iPhone 17 Pro')
identifier=run(['xcrun','simctl','create','Clepso isolated unit tests',device_type,runtime])
(root/'build').mkdir(exist_ok=True)
try:
    log=root/'.build/ci-logs/mobile_native_tests.log'
    log.parent.mkdir(parents=True,exist_ok=True)
    if log.exists(): log.rename(log.with_name('mobile_native_tests-'+uuid.uuid4().hex+'.log'))
    results=root/'build/mobile-unit-results'
    results.mkdir(parents=True,exist_ok=True)
    with log.open('w') as stream:
        result=subprocess.run(['xcodebuild','-project','Clepso.xcodeproj','-scheme','ClepsoPhone',
            '-destination','platform=iOS Simulator,id='+identifier,'-derivedDataPath','build/mobile-tests',
            '-resultBundlePath',str(results/(uuid.uuid4().hex+'.xcresult')),'CODE_SIGN_IDENTITY=-','CODE_SIGN_STYLE=Manual',
            'DEVELOPMENT_TEAM=','CLEPSO_SYNC_HOST=','CLEPSO_SYNC_PUBLISHABLE_KEY=','test'],
            cwd=root,stdout=stream,stderr=subprocess.STDOUT)
    print('Isolated iPhone model tests:', 'PASS' if result.returncode==0 else 'FAIL (private build/test log)')
    raise SystemExit(result.returncode)
finally:
    subprocess.run(['xcrun','simctl','shutdown',identifier],capture_output=True)
    subprocess.run(['xcrun','simctl','delete',identifier],check=True,capture_output=True)
    print('Removed only the simulator created by this test; physical devices and existing simulators unchanged.')
