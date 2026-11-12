#!/bin/bash
# No signing identity, provisioning profile, account configuration or simulator boot is needed for this check.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 -I scripts/check-mobile-icons.py
if [ ! -x .tools/xcodegen/bin/xcodegen ]; then
    echo "Run scripts/bootstrap.sh first to prepare the pinned XcodeGen tool."
    exit 1
fi
.tools/xcodegen/bin/xcodegen generate
mkdir -p .build/ci-logs
log=.build/ci-logs/mobile_companion_bundle.log
if ! xcodebuild -project Clepso.xcodeproj -scheme ClepsoPhone -configuration Debug \
    -destination 'generic/platform=iOS Simulator' -derivedDataPath build/mobile-simulator \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build > "$log" 2>&1; then
    echo "Mobile companion build failed; inspect $log."
    exit 1
fi
echo "iPhone and embedded Watch simulator bundles built; log: $log"
