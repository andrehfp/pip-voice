# Pip Voice

A standalone menu-bar app: press a shortcut, speak, and insert text into the currently focused app. Native Apple speech recognition, with no assistant server, account, API key, telemetry or AI cleanup.

**Experimental, source-build only.** No prebuilt download, signed distribution or notarized release is provided. The source is licensed under [MIT](LICENSE); see [provenance and licensing](docs/provenance.md) for Apple system components and the source-only boundary.

## Requirements

- macOS 26 or later, a Swift 6 toolchain and the matching macOS SDK (Xcode or Command Line Tools).
- A Mac and language supported by Apple's `SpeechTranscriber`. The OS version alone does not guarantee availability. Compatibility on other hardware has not been tested.
- Microphone access. Accessibility is optional for the default key combination, but required for automatic pasting, modifier-only shortcuts and global Escape observation.
- The first use of a language may download Apple's speech assets. Once installed, recognition uses the on-device model; offline operation still needs a supervised validation on a clean Mac.

## Build from source

```sh
bash mac/build.sh
```

Output: `mac/build/Pip Voice.app`. The script builds and ad-hoc signs only: it does not install, launch, stop another app, change Login Items or search your keychain for a signing identity. There are no package dependencies and no Bun runtime requirement.

For a local installation into your home Applications folder, run:

```sh
bash mac/install.sh
```

The installer verifies identity, signature and privacy checks, refuses existing apps and symlink destinations, and never launches an app or changes permissions. See the [beginner install and setup guide](docs/setup.md) for first permissions, a safe TextEdit test and troubleshooting. `bash mac/build.sh --audit` creates a separate candidate under `mac/build/audit/` without replacing the current build bundle; use `bash mac/install.sh --audit` for that candidate.

To try it yourself, open the resulting app bundle in Finder. Do not run the bare executable: its bundle identity is required for separate preferences and macOS permissions. After you have tested it, you can manually copy **Pip Voice.app** into Applications. Ad-hoc signing is for development and may require regranting permissions after rebuilds; it is not a Gatekeeper distribution solution. An explicit `PIP_VOICE_SIGN_IDENTITY` can override the development signature; release signing and notarization are not automated.

## Use

1. Open Settings from the menu-bar microphone. Choose your language and shortcut.
2. Default: **Control–Option–Space**, intentionally different from the assistant's right Option shortcut. It can still conflict with system shortcuts or another app; choose another combination if needed.
3. Focus a text field in your destination app. Tap the shortcut once to start and again to finish, or hold it and release to finish. Wait until the overlay says **Listening**, especially on first model preparation.
4. Escape cancels when Accessibility permits global key observation. **Cancel dictation** is always available in the menu, including during preparation/finalization. A forgotten recording stops after five minutes.
5. Without Accessibility, recognition still works with a combination or the menu; text stays copied for manual Command-V. Single modifier shortcuts require Accessibility. Do not configure the same modifier in two running dictation apps.

The overlay does not activate or focus a window. Paste goes to **the field focused at delivery**, not necessarily the field focused at recording start. It does not submit a form or press Return. “Paste shortcut sent” is not proof that another app accepted the paste. Clipboard restoration after 600 ms is best-effort, only when the original contents were captured and clipboard ownership is unchanged. Unknown/noneditable targets keep text copied. Recent dictations can recover the text if a destination did not accept it.

## Vocabulary and history

**Edit vocabulary…** opens `~/Library/Application Support/Pip Voice/vocabulary.txt`. Use one hint per line or `heard phrase => intended phrase` for local whole-word corrections. No personal vocabulary is imported. This initial version supports Apple speech recognition only: no model selector, alternative engine or cloud transcription is implemented. Recognition and corrections are local; there is no cloud polishing step.

The latest 20 distinct nonempty dictations are saved locally in this app's preferences (`org.pipvoice.app`), including text whose paste could not be verified. There is no history-off setting or app-level encryption. **Recent dictations** copies an entry; **Clear history** removes this app's saved list. Clipboard contents and any OS backups are separate. Avoid dictating secrets if you do not want them in local history.

## Development checks

Run from the repository root:

```sh
# Build the separate audit candidate first:
bash mac/build.sh --audit
PIP_VOICE_TEST_BUNDLE="mac/build/audit/Pip Voice.app" bash mac/Tests/run-all.sh
bash mac/Tests/run-install-regressions.sh
```

These compile production components and use fake audio lifecycles, in-memory clipboard effects, synthetic key events and a pure gesture state machine and the actual asynchronous recording coordinator. They do not open a microphone, install live key monitors, post paste events, change the user's preferences (history tests use a disposable suite), operate Pip.app or test real cross-app insertion.

See [security review](docs/security-review.md), [validation](docs/validation.md), [privacy](docs/privacy.md), [provenance](docs/provenance.md) and the [manual test checklist](docs/manual-tests.md). These automated checks do not validate real microphone input, TCC permissions, cross-app pasting, another Mac or Gatekeeper distribution. See the unchecked manual tests before relying on the app.
