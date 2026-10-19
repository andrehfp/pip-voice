#!/bin/bash
# Compile only the pure production gesture machine; no app or hardware effects.
set -euo pipefail
cd "$(dirname "$0")/../.."
scratch=$(mktemp -d /tmp/pip-voice-gesture-regression.XXXXXX)
trap 'rm -rf "$scratch"' EXIT
swiftc -swift-version 5 \
  mac/Sources/Pip/RecordingGesture.swift \
  mac/Tests/GestureRegression/main.swift \
  -o "$scratch/gesture-regression"
"$scratch/gesture-regression"
