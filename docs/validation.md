# Validation record

## Audited source revision

The source includes the menu/history crash correction, copy-only delivery for unknown targets, protected local installation and guided setup. The original local review passed a release build and the full synthetic regression suite. The standalone app and its private Git history are not part of this source-only export.

| Suite | Audited result |
| --- | --- |
| Audio lifecycle/channel/configuration | 12 groups, 64 assertions |
| Clipboard transactions | 20 tests |
| Production paste delivery with injected effects | 29 tests |
| Keyboard routing/recorder | 7 groups |
| Recording gestures | 13 groups, 134 assertions |
| Vocabulary and disposable-suite history | 19 checks |
| Production default history in a disposable bundle | 4 checks |
| Per-operation cancellation ownership | 21 checks |
| Actual async recording coordinator with fake backend | 4 groups |
| Installer/package negative cases | 8 groups, temporary destinations only |
| Package identity, signature and raw-byte privacy checks | Passed |

The asynchronous tests cover a stale finish continuation after a new operation begins, stale cancellation effects, cancellation during finalization and normal final text. Cancellation state is per operation; backend effects are guarded before and after awaits. Replacing shortcut listeners cancels the active gesture so a physical release is not silently lost.

## Separate publication export

The build and regression results above were reproduced in a separate allowlisted export, without operating the original app, modifying its repository/history or reading its live preferences. The source snapshot contains 62 text files including the MIT license, the audited fixes, installer and setup documentation. Only the new installer test script's trailing whitespace was normalized; implementation and test logic match the audited working source.

Publication validation compares working bytes, staged blobs and the final commit, scans those contents and Git metadata offline, checks the explicit file allowlist, verifies a single fresh root commit and uses the GitHub-provided noreply identity. Build products are test artifacts only and are ignored, not committed or attached. Scanner-rule matches and Apple's standard plist DTD are reviewed false positives, not application network destinations. Heuristic checks are not proof that every possible secret format has been excluded.

## Reproduce locally

```sh
bash -n mac/*.sh mac/Tests/*.sh
bash mac/build.sh --audit
PIP_VOICE_TEST_BUNDLE='mac/build/audit/Pip Voice.app' bash mac/Tests/run-all.sh
bash mac/Tests/run-install-regressions.sh
python3 mac/Tests/audit-privacy.py
git diff --check
```

The offline inventory reports heuristic matches for manual review; exit zero alone is not a clean-security verdict. Do not upload the generated build directory or caches. These tests do not launch the app, open a microphone, post real paste events, grant TCC access or install into the user's Applications directory.

## Environment and limitations

The audited build environment was Apple Swift 6.4 and macOS SDK 27 on Apple Silicon with Command Line Tools. Deployment target is macOS 26; the local build is arm64, not universal. The existing installTap deprecation warning in SDK 27 remains. No external package dependency or model asset is bundled.

These results do **not** validate real microphones, TCC prompts, clean-machine asset installation/cancellation, offline recognition, first/last-word accuracy, actual cross-app paste, UI layout, VoiceOver, keyboard layouts, another Mac, Intel hardware, macOS 26 runtime behavior, stable signed installations or Gatekeeper distribution. Production AppKit wiring is compiled but not end-to-end exercised. See the [manual checklist](manual-tests.md), [security review](security-review.md) and [setup guide](setup.md).
