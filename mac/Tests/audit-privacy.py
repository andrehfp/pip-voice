#!/usr/bin/env python3
"""Offline, read-only inventory. Emits categories and locations, never matched values.

Heuristics are not a security certification. Review metadata and false positives;
never send this repository or its contents to an external scanning service.
"""
import collections
import json
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
os.chdir(ROOT)
PATTERNS = {
    "private_key": rb"-----BEGIN (?:[A-Z0-9 ]+ )?PRIVATE KEY-----",
    "provider_token": rb"(?:sk-(?:proj-|ant-)?[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[A-Z0-9]{16}|xox[baprs]-[A-Za-z0-9-]{16,}|AIza[A-Za-z0-9_-]{30,})",
    "jwt": rb"\beyJ[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{12,}",
    "credential_assignment": rb"(?i)(?:api[_-]?key|access[_-]?token|client[_-]?secret|password)\s*[=:]\s*[\"'][^\"'\r\n]{8,}[\"']",
    "home_path": rb"(?:/Users/[^/\x00\s\"'<>]+|/home/[^/\x00\s\"'<>]+)",
    "email": rb"[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+",
    "ipv4": rb"\b(?:\d{1,3}\.){3}\d{1,3}\b",
    "url": rb"(?:https?|wss?|ssh)://[^\s\x00\"'<>]+",
    "network_api": rb"\b(?:URLSession|NWConnection|NSURLConnection|CFStreamCreatePairWithSocketToHost|WKWebView|Process\(|NSTask|dlopen|execve|posix_spawn)\b",
    "original_app_identity": rb"com\.[A-Za-z0-9_-]+\.pip\b|Application Support/Pip/",
}
PATTERNS = {name: re.compile(pattern) for name, pattern in PATTERNS.items()}
COUNTS = collections.Counter()

def git(*args):
    result = subprocess.run(["git", "--no-pager", *args], capture_output=True, check=False)
    if result.returncode:
        raise RuntimeError("Git inventory failed (details suppressed)")
    return result.stdout

def safe_location(location):
    location = re.sub(r"(?:/Users|/home)/[^/\s]+", "/<home>/<redacted>", location)
    location = re.sub(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+", "<email>", location)
    return location

def emit(category, location, count, lines=None):
    COUNTS[category] += count
    finding = {"category": category, "location": safe_location(location), "count": count}
    if lines:
        finding["lines"] = lines[:30]
    print(json.dumps(finding, sort_keys=True))

def scan(data, location):
    text = b"\x00" not in data
    for category, pattern in PATTERNS.items():
        matches = list(pattern.finditer(data))
        if matches:
            lines = sorted({data.count(b"\n", 0, match.start()) + 1 for match in matches}) if text else None
            emit(category, location, len(matches), lines)

files = 0
symlinks = 0
xattrs = 0
xattr_types = collections.Counter()
for directory, dirs, names in os.walk(ROOT, followlinks=False):
    for name in list(dirs) + names:
        path = Path(directory) / name
        relative = path.relative_to(ROOT).as_posix()
        if path.is_symlink():
            symlinks += 1
            emit("symlink_not_followed", relative, 1)
            scan(os.readlink(path).encode(), relative + ":link-target")
            continue
        attributes = subprocess.run(["xattr", "-s", str(path)], capture_output=True, check=True).stdout.splitlines()
        for attr in attributes:
            xattrs += 1
            attr_name = attr.decode()
            xattr_types[attr_name if attr_name in ("com.apple.provenance", "com.apple.quarantine", "com.apple.FinderInfo", "com.apple.ResourceFork") else "other-name-suppressed"] += 1
            encoded = subprocess.run(["xattr", "-s", "-p", "-x", attr.decode(), str(path)], capture_output=True, check=True).stdout
            scan(bytes.fromhex(encoded.decode()), relative + ":xattr-value-suppressed")
        if path.is_file():
            files += 1
            scan(path.read_bytes(), "worktree:" + relative)
            if re.search(r"(?i)(?:^|/)(?:\.env[^/]*|auth[^/]*|[^/]*keychain[^/]*|[^/]*\.(?:p12|p8|key|mobileprovision|wav|m4a|caf|log))$", relative):
                emit("sensitive_filename_review", "worktree:" + relative, 1)

objects = git("cat-file", "--batch-all-objects", "--batch-check=%(objectname) %(objecttype)").splitlines()
object_counts = collections.Counter()
for entry in objects:
    oid, kind = entry.decode().split()
    object_counts[kind] += 1
    if kind in ("blob", "commit", "tag"):
        data = git("cat-file", kind, oid)
        scan(data, "git-object:" + oid[:12] + ":" + kind)
        if kind == "commit":
            header = data.split(b"\n\n", 1)[0]
            for field in (b"author ", b"committer "):
                if any(line.startswith(field) for line in header.splitlines()):
                    emit("git_identity_metadata", "git-object:" + oid[:12] + ":" + field.decode().strip(), 1)

for category, args in (
    ("index_entries", ("ls-files", "-z")),
    ("untracked_entries", ("ls-files", "--others", "--exclude-standard", "-z")),
    ("ignored_entries", ("ls-files", "--others", "--ignored", "--exclude-standard", "-z")),
    ("refs", ("for-each-ref", "--format=%(objectname)")),
    ("remotes", ("remote",)),
):
    output = git(*args)
    separator = b"\x00" if category.endswith("entries") else b"\n"
    print(json.dumps({"inventory": category, "count": len([x for x in output.split(separator) if x])}))
print(json.dumps({"inventory": "summary", "files": files, "symlinks": symlinks, "xattrs": xattrs, "xattr_types": dict(xattr_types),
                  "git_objects": dict(object_counts), "pattern_hits": dict(COUNTS)}, sort_keys=True))
