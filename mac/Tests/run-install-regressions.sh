#!/bin/bash
# Copies only into a disposable directory; never installs in Applications or launches an app.
set -euo pipefail
cd "$(dirname "$0")/../.."
scratch=$(mktemp -d /tmp/pip-voice-install-tests.XXXXXX)
trap 'rm -rf "$scratch"' EXIT
source='mac/build/audit/Pip Voice.app'
bash mac/Tests/verify-package.sh "$source"
mkdir -p "$scratch/Applications/Pip.app"
printf 'assistant sentinel\n' > "$scratch/Applications/Pip.app/untouched"
bash mac/install.sh --audit --destination "$scratch/Applications"
bash mac/Tests/verify-package.sh "$scratch/Applications/Pip Voice.app"
[ "$(cat "$scratch/Applications/Pip.app/untouched")" = 'assistant sentinel' ]
echo 'PASS: installs a verified bundle without touching a separate assistant sentinel'
if bash mac/install.sh --audit --destination "$scratch/Applications" >/dev/null 2>&1; then
    echo 'FAIL: existing application was accepted' >&2; exit 1
fi
echo 'PASS: refuses overwriting an existing app'
ln -s "$scratch/Applications" "$scratch/linked"
if bash mac/install.sh --audit --destination "$scratch/linked" >/dev/null 2>&1; then
    echo 'FAIL: symbolic link destination was accepted' >&2; exit 1
fi
for suffix in / /. /../linked; do
    if bash mac/install.sh --audit --destination "$scratch/linked$suffix" >/dev/null 2>&1; then
        echo 'FAIL: symbolic-link/dot destination variant was accepted' >&2; exit 1
    fi
done
echo 'PASS: refuses symbolic-link destination including trailing slash and dot variants'
if bash mac/install.sh --destination relative-path >/dev/null 2>&1; then
    echo 'FAIL: relative destination was accepted' >&2; exit 1
fi
echo 'PASS: refuses relative destination'
if bash mac/install.sh --unexpected >/dev/null 2>&1; then
    echo 'FAIL: unknown argument was accepted' >&2; exit 1
fi
echo 'PASS: refuses unknown arguments'
printf 'synthetic unexpected resource\n' > "$scratch/Applications/Pip Voice.app/Contents/Resources/extra.txt"
if bash mac/Tests/verify-package.sh "$scratch/Applications/Pip Voice.app" >/dev/null 2>&1; then
    echo 'FAIL: unexpected resource was accepted' >&2; exit 1
fi
echo 'PASS: rejects unexpected bundled resources'
rm "$scratch/Applications/Pip Voice.app/Contents/Resources/extra.txt"
ln -s /dev/null "$scratch/Applications/Pip Voice.app/Contents/Resources/link"
if bash mac/Tests/verify-package.sh "$scratch/Applications/Pip Voice.app" >/dev/null 2>&1; then
    echo 'FAIL: bundled symbolic link was accepted' >&2; exit 1
fi
echo 'PASS: rejects bundled symbolic links'
rm "$scratch/Applications/Pip Voice.app/Contents/Resources/link"
printf '%s%s\n' '/Us' 'ers/synthetic-fixture' >> "$scratch/Applications/Pip Voice.app/Contents/MacOS/PipVoice"
if bash mac/Tests/verify-package.sh "$scratch/Applications/Pip Voice.app" > "$scratch/privacy-result" 2>&1; then
    echo 'FAIL: embedded private path was accepted' >&2; exit 1
fi
grep -q 'Bundle privacy gate failed' "$scratch/privacy-result"
echo 'PASS: rejects private paths in raw executable bytes, before signature verification'
echo 'Installer regressions: 8 groups passed; disposable destination only'
