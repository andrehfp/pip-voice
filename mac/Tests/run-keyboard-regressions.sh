#!/bin/bash
# Synthetic events and offscreen controls; no live monitors or permission prompts.
set -euo pipefail
scratch=$(mktemp -d /tmp/pip-voice-keyboard.XXXXXX)
trap 'rm -rf "$scratch"' EXIT
swiftc -parse-as-library \
  mac/Sources/Pip/Shortcuts.swift \
  mac/Sources/Pip/ShortcutRecorder.swift \
  mac/Sources/Pip/ModifierTrigger.swift \
  mac/Tests/KeyboardRegression/main.swift \
  -framework Carbon -o "$scratch/regression"
"$scratch/regression"
