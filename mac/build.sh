#!/bin/bash
# Build only. Never install, launch, quit another app or select a keychain identity.
set -euo pipefail
cd "$(dirname "$0")"
OUTPUT=build
if [ "${1:-}" = '--audit' ] && [ "$#" -eq 1 ]; then
    OUTPUT=build/audit
elif [ "$#" -ne 0 ]; then
    echo 'Usage: bash mac/build.sh [--audit]' >&2; exit 2
fi
# Audit builds use a separate output, leaving the currently tested bundle untouched.
swift build -c release --jobs 4
mkdir -p "$OUTPUT"
STAGING=$(mktemp -d "$OUTPUT/staging.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
APP="$STAGING/Pip Voice.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp -X .build/release/PipVoice "$APP/Contents/MacOS/PipVoice"
cp -X Resources/Info.plist "$APP/Contents/Info.plist"
# Mach-O debug/symbol metadata can retain absolute developer paths even in release builds.
# Strip the new staging copy BEFORE signing, never the running or installed executable.
strip -S "$APP/Contents/MacOS/PipVoice"
xattr -cr "$APP"
plutil -lint "$APP/Contents/Info.plist"
codesign --force --sign "${PIP_VOICE_SIGN_IDENTITY:--}" "$APP"
cd ..
bash mac/Tests/verify-package.sh "mac/$APP"
cd mac
# Replace only this local build output after all structural/privacy/signature checks pass.
rm -rf "$OUTPUT/Pip Voice.app"
mv "$APP" "$OUTPUT/Pip Voice.app"
printf 'Built mac/%s/Pip Voice.app; not installed or launched.\n' "$OUTPUT"
