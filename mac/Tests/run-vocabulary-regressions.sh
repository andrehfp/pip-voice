#!/bin/bash
# Pure parsing/fixes and an injected disposable preference suite.
# Never reads or changes the user's real preferences; no app or input access.
set -euo pipefail
cd "$(dirname "$0")/../.."
work=$(mktemp -d /tmp/pip-voice-vocabulary.XXXXXX)
trap 'rm -rf "$work"' EXIT
swiftc mac/Sources/Pip/Vocabulary.swift mac/Tests/VocabularyRegression/main.swift \
  -framework AppKit -o "$work/regressions"
"$work/regressions"
# Exercise the production defaults path with a disposable main-bundle identifier.
bundle="$work/HistoryRegression.app"
mkdir -p "$bundle/Contents/MacOS"
cat > "$bundle/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>org.pipvoice.tests.history.${work##*.}</string>
<key>CFBundleExecutable</key><string>HistoryRegression</string>
</dict></plist>
PLIST
swiftc mac/Sources/Pip/Vocabulary.swift mac/Tests/HistoryBundleRegression/main.swift \
  -framework AppKit -o "$bundle/Contents/MacOS/HistoryRegression"
"$bundle/Contents/MacOS/HistoryRegression"
