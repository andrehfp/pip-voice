#!/bin/bash
# Run from the repository root. No package build or live clipboard, events, permissions or app UI.
set -euo pipefail
binary="$(mktemp /tmp/pip-clipboard-regression.XXXXXX)"
trap 'rm -f "$binary"' EXIT
swiftc -swift-version 5 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  mac/Sources/Pip/ClipboardTransaction.swift \
  mac/Tests/ClipboardRegression/Fakes.swift \
  mac/Tests/ClipboardRegression/main.swift \
  -o "$binary"
"$binary"
# Execute Paster's production route with injected fake effects, never its live environment.
# AppKit/AX/CGEvent code is compiled but no real pasteboard, permission or keypost APIs run.
swiftc -swift-version 5 -warnings-as-errors -parse-as-library \
  mac/Sources/Pip/ClipboardTransaction.swift \
  mac/Sources/Pip/AppKitClipboardBoard.swift \
  mac/Sources/Pip/ReplacementSafety.swift \
  mac/Sources/Pip/Paster.swift \
  mac/Tests/ClipboardRegression/Fakes.swift \
  mac/Tests/PasterDeliveryRegression/main.swift \
  -o "$binary"
"$binary"
