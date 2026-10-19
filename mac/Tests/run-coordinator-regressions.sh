#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
scratch=$(mktemp -d /tmp/pip-voice-coordinator.XXXXXX)
trap 'rm -rf "$scratch"' EXIT
swiftc -swift-version 5 -parse-as-library mac/Sources/Pip/RecordingOwnership.swift \
  mac/Sources/Pip/RecordingCoordinator.swift mac/Tests/CoordinatorRegression/main.swift -o "$scratch/regression"
"$scratch/regression"
