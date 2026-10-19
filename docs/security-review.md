# Security and correctness review

This is an offline source/artifact review, not a penetration test, legal certification or promise of zero risk. The public repository is an experimental source-only snapshot; local apps, build outputs, private data and original Git history are not included. The review uses heuristic scans and synthetic regressions, not an external scanning service.

## Corrections included in this snapshot

| Area | Finding and correction |
| --- | --- |
| Menu/history crash | A named UserDefaults suite equal to the main bundle identifier could return nil, and force-unwrapping it crashed the menu. The app now uses the validated bundle's standard domain. A disposable bundled regression exercises the production read/add/clear path without accessing real history. |
| Unknown paste target | An unknown focused element could receive Command-V. Only a positively editable target now receives a keypost; unknown/noneditable targets keep text copied and invalidate earlier clipboard restoration. |
| Developer paths in old builds | Raw Mach-O bytes can retain private paths even when ordinary strings output misses them. The build strips a new staging copy before signing and checks raw bytes. No old binary or original history is included. |
| Diagnostic privacy | Package checks report filenames or generic failures, not matching secret values. The offline inventory reports categories, locations, counts and line numbers only. |
| Installation/setup | The installer validates identity, signature and package contents, refuses root, existing apps and symlinks, and stages a no-clobber copy. Setup explains permissions and an explicit TextEdit test. |

## Runtime boundary

- Imports and linked libraries are Apple system frameworks and Swift system libraries. There are no external Swift package dependencies, bundled fonts, artwork, speech models, credentials or provisioning profiles. See [provenance](provenance.md) for the licensing boundary.
- Speech uses SpeechAnalyzer and SpeechTranscriber with the progressive preset, without SFSpeechRecognizer cloud fallback, telemetry, a provider API or an app network client. macOS manages missing-language model downloads. Live download destinations and actual offline/hardware behavior have not been measured by these tests.
- Audio uses AVAudioEngine, an in-memory bounded stream, fail-closed overflow/conversion/configuration handling and per-operation cleanup ownership. There is no application audio-file or temporary-recording write path. Capture has a five-minute limit. Synthetic tests do not prove that every operating-system permission/download/finalization await is promptly cancellable.
- Accessibility reads focused-element/caret metadata and posts Command-V only for editable targets. The app does not intentionally press Return or submit forms. Delivery targets the field focused at delivery, not necessarily at recording start. A 600 ms clipboard restoration delay is not acknowledgment that another app accepted a paste.
- Clipboard snapshots temporarily materialize potentially large/lazy representations in memory without app-level encryption or a size cap. An external changeCount invalidates restoration, and copy-only delivery invalidates older scheduled restores. A failed clear/set can lose prior clipboard contents and is reported as failure. Clipboard providers and managers remain outside this app's control.
- Up to 20 distinct nonempty outputs persist in standard preferences, without a history-off setting or app-level encryption. History is saved before delivery acknowledgment, which macOS does not provide. Clear history removes the app's saved list, not documents, other apps, clipboard-manager history or backups.
- Bundle identity is org.pipvoice.app. Launch refuses a different or bare-executable identity. Vocabulary uses the dedicated Pip Voice Application Support directory; there is no migration or read of another app's preferences, vocabulary or authentication.
- Microphone access is requested only after the user starts dictation. Accessibility is user-initiated and optional for default/menu capture. No separate Speech Recognition authorization API is called. Setup buttons do not grant permissions; its TextEdit button does not create a document, record speech or paste.

## Automated review coverage

The pre-export audited revision passed a release build, signature/package/raw-byte privacy gates and all regressions: audio 12 groups/64 assertions, clipboard 20 tests, paste delivery 29 tests, keyboard 7 groups, gestures 13 groups/134 assertions, vocabulary 19 checks, production default history in a disposable bundle 4 checks, cancellation ownership 21 checks, asynchronous coordinator 4 groups and installer 8 groups in temporary destinations. See [validation](validation.md) for publication-snapshot checks.

The compiler emits the SDK 27 installTap deprecation warning; the API remains available for the macOS 26 deployment target. The isolated history test deliberately probes named-suite initialization in its disposable bundle and may print the expected same-bundle-suite diagnostic. It never reads real app history.

The optional developer inventory is:

```sh
python3 mac/Tests/audit-privacy.py
```

It scans worktree bytes, Git blobs/commit/tag objects and filesystem extended attributes locally. It prints possible findings for review and intentionally returns success when inventory completes; its exit status is **not** a clean-security verdict. Build caches can contain local paths and scanner expressions can match themselves. Review those findings, and never publish build caches or whole-directory archives. verify-package.sh is a fail-closed package gate, not a comprehensive credential detector.

## Known limitations

Real microphone input, first-use TCC, first asset installation, offline recognition, first/last-word accuracy, cancellation against live Apple services, cross-app insertion, keyboard layouts, VoiceOver/layout, another clean Mac, Intel hardware and macOS 26 runtime behavior remain unvalidated. Ad-hoc signing is development-only; stable Developer ID signing, notarization, Gatekeeper and distribution policy are separate work. No binary release is included. See the [manual checklist](manual-tests.md) and [setup guide](setup.md).
