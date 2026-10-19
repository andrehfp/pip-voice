#!/bin/bash
# Run from the repository root. No app launch, permission prompt, hardware, clipboard or network.
set -euo pipefail
scratch=$(mktemp -d /tmp/pip-audio-regression.XXXXXX)
trap 'rm -rf "$scratch"' EXIT
swiftc -swift-version 5 -parse-as-library \
  mac/Sources/Pip/AudioInputChannel.swift \
  mac/Sources/Pip/DictationLifetime.swift \
  mac/Sources/Pip/AudioSession.swift \
  mac/Sources/Pip/AudioConfigurationObserver.swift \
  mac/Tests/AudioRegression/main.swift \
  -o "$scratch/audio-regression"
"$scratch/audio-regression"
