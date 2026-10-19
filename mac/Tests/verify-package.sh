#!/bin/bash
# Structural packaging/privacy checks. No app launch or personal state reads.
set -euo pipefail
if [ "$#" -gt 1 ]; then echo 'Usage: verify-package.sh [APP_BUNDLE]' >&2; exit 2; fi
cd "$(dirname "$0")/../.."
plist='mac/Resources/Info.plist'
[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$plist")" = 'org.pipvoice.app' ]
[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleExecutable' "$plist")" = 'PipVoice' ]
[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleDisplayName' "$plist")" = 'Pip Voice' ]
[ "$(/usr/libexec/PlistBuddy -c 'Print LSMinimumSystemVersion' "$plist")" = '26.0' ]
# Filenames only: never echo a potential credential or personal value.
if grep -RIlE 'PipClient|Telemetry|ensureServer|URLSession|NWConnection|com\.[a-zA-Z0-9_-]+\.pip|Application Support/Pip/|BEGIN [A-Z ]*PRIVATE KEY|sk-[a-zA-Z0-9]{20,}|gh[pousr]_[a-zA-Z0-9]{20,}|/Users/[a-zA-Z0-9_-]+' mac/Sources mac/Resources mac/Package.swift; then
    echo 'Unexpected coupling, personal path or potential secret in application source' >&2; exit 1
fi
if grep -qE 'NSAppleEventsUsageDescription|NSAllowsLocalNetworking|NSContacts|NSCalendars|NSReminders' "$plist"; then
    echo 'Unexpected assistant permission' >&2; exit 1
fi
if grep -qE 'pkill|pgrep|launchctl|osascript|security find-identity|Pip\.app|(^|[ ;])open ' mac/build.sh; then
    echo 'Build must not operate installed applications or choose credentials' >&2; exit 1
fi
if grep -qE '\.package\(' mac/Package.swift; then echo 'Unexpected external package' >&2; exit 1; fi
bundle="${1:-mac/build/Pip Voice.app}"
if [ "$#" -eq 1 ] && [ ! -d "$bundle" ]; then echo 'Requested bundle is missing' >&2; exit 1; fi
if [ -d "$bundle" ]; then
    [ ! -L "$bundle" ] || { echo 'Bundle must not be a symbolic link' >&2; exit 1; }
    [ -z "$(find "$bundle" -type l -print -quit)" ] || { echo 'Unexpected bundled symbolic link' >&2; exit 1; }
    cmp "$plist" "$bundle/Contents/Info.plist"
    # -a scans the complete file, including Mach-O symbol tables that strings may skip.
    if LC_ALL=C grep -aqE '/Users/|/home/|BEGIN [A-Z ]*PRIVATE KEY|sk-(proj-|ant-)?[a-zA-Z0-9_-]{20,}|gh[pousr]_[a-zA-Z0-9_]{20,}|github_pat_[a-zA-Z0-9_]{20,}|AKIA[A-Z0-9]{16}|xox[baprs]-[a-zA-Z0-9-]{16,}' "$bundle/Contents/MacOS/PipVoice"; then
        echo 'Bundle privacy gate failed: private path or credential pattern in executable (value suppressed)' >&2; exit 1
    fi
    # No embedded models, logs, provisioning profiles, credentials or other resources.
    unexpected=$(find "$bundle" -type f ! -path '*/Contents/MacOS/PipVoice' ! -path '*/Contents/Info.plist' ! -path '*/Contents/_CodeSignature/CodeResources' -print -quit)
    [ -z "$unexpected" ] || { echo 'Unexpected bundled resource (name suppressed)' >&2; exit 1; }
    codesign --verify --strict "$bundle"
fi
echo 'Package boundary checks passed; heuristic scan is not a license or security certification.'
