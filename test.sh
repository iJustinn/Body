#!/bin/zsh
# Run BodyTests on one pinned simulator.
# Body and BodySerial are complementary halves of the suite, so both run by default.
# Narrow a focused run to the plan that owns the class: PLANS=Body ./test.sh -only-testing:...
# Override SCHEME to run another scheme's plan, such as the watch tests:
# SCHEME=BodyWatchTests PLANS=BodyWatch DEST='platform=watchOS Simulator,name=...,OS=27.0' ./test.sh -only-testing:...
# All test plans are serial, so no simulator clones are created.
# The worker cap is belt-and-braces in case parallel testing is enabled later.
set -euo pipefail
cd "$(dirname "$0")"

DEST=${DEST:-'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0'}
WORKERS=${WORKERS:-2}
PLANS=${PLANS:-'Body BodySerial'}
SCHEME=${SCHEME:-Body}

for plan in ${=PLANS}; do
  xcodebuild test \
    -project body.xcodeproj \
    -scheme "$SCHEME" \
    -testPlan "$plan" \
    -destination "$DEST" \
    -maximum-parallel-testing-workers "$WORKERS" \
    "$@"
done

# Sweep any clones a crashed or interrupted run left behind.
xcrun simctl --set ~/Library/Developer/XCTestDevices delete all >/dev/null 2>&1 || true
