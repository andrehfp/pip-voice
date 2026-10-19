#!/bin/bash
# Local development installer. Never opens an app, stops a process or changes permissions.
set -euo pipefail
cd "$(dirname "$0")/.."
destination="$HOME/Applications"
source='mac/build/Pip Voice.app'
while [ "$#" -gt 0 ]; do
    case "$1" in
        --audit) source='mac/build/audit/Pip Voice.app'; shift ;;
        --destination)
            [ "$#" -ge 2 ] || { echo 'Missing destination directory' >&2; exit 2; }
            destination="$2"; shift 2 ;;
        *) echo 'Usage: bash mac/install.sh [--audit] [--destination DIRECTORY]' >&2; exit 2 ;;
    esac
done
[ "$(id -u)" -ne 0 ] || { echo 'Do not run this installer with sudo or as root' >&2; exit 1; }
case "$destination" in /*) ;; *) echo 'Destination must be an absolute directory path' >&2; exit 1 ;; esac
# Normalize trailing slashes before the symlink check; reject ambiguous dot components.
while [ "$destination" != / ] && [ "${destination%/}" != "$destination" ]; do destination="${destination%/}"; done
case "$destination" in */./*|*/../*|*/.|*/..) echo 'Destination must not contain dot path components' >&2; exit 1 ;; esac
[ ! -L "$destination" ] || { echo 'Destination directory must not be a symbolic link' >&2; exit 1; }
# The output name is fixed and distinct from any assistant application.
target="$destination/Pip Voice.app"
[ ! -e "$target" ] && [ ! -L "$target" ] || {
    echo 'Pip Voice.app already exists there. Nothing was changed. Quit that copy and move it aside yourself before installing again.' >&2; exit 1;
}
[ -d "$source" ] && [ ! -L "$source" ] || { echo 'Build Pip Voice first; a real local bundle is required' >&2; exit 1; }
# Fail closed on private paths, credential patterns, identity mismatch or invalid signatures.
bash mac/Tests/verify-package.sh "$source"
mkdir -p "$destination"
# Resolve the existing directory so subsequent operations do not follow a changed leaf symlink.
destination=$(cd "$destination" && pwd -P)
staging=$(mktemp -d "$destination/.pip-voice-install.XXXXXX")
trap 'rm -rf "$staging"' EXIT
# Preserve quarantine if present: this installer is not a Gatekeeper bypass.
ditto "$source" "$staging/Pip Voice.app"
bash mac/Tests/verify-package.sh "$staging/Pip Voice.app"
# Passing the parent directory plus -n avoids overwrites and accidental nested app copies.
mv -n "$staging/Pip Voice.app" "$destination/"
[ ! -d "$staging/Pip Voice.app" ] || { echo 'Destination appeared during installation; existing app was not overwritten' >&2; exit 1; }
echo 'Installed Pip Voice.app in the selected directory. Nothing was launched; permissions are unchanged.'
echo 'Open it in Finder, then use its menu-bar microphone → Setup & settings…'
