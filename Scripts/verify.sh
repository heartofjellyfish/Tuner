#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Verification /tmp/clean-tuner-modules
swiftc -module-cache-path /tmp/clean-tuner-modules -O TheTuner/Pitch.swift Tests/PitchBenchmark.swift -o /tmp/clean-tuner-benchmark
/tmp/clean-tuner-benchmark | tee Verification/pitch-benchmark.txt
swiftc -module-cache-path /tmp/clean-tuner-modules -O TheTuner/Pitch.swift Tests/FeatureAudit.swift -o /tmp/clean-feature-audit
/tmp/clean-feature-audit | tee Verification/feature-audit-tests.txt
if [[ -n "${TUNER_SIMULATOR_ID:-}" ]]; then
  xcodebuild -project TheTuner.xcodeproj -scheme TheTuner \
    -destination "platform=iOS Simulator,id=$TUNER_SIMULATOR_ID" \
    -derivedDataPath build -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test
fi
