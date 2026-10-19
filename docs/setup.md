# Install and first setup

This is an experimental, source-build-only project, not a notarized download or a stable binary release. See [provenance and licensing](provenance.md).

## What you need

- macOS 26 or newer and hardware/language supported by Apple's `SpeechTranscriber`. An OS version check alone is not a compatibility guarantee.
- To build: Swift 6 and a matching macOS SDK through Xcode or Command Line Tools. The locally validated build is Apple Silicon (arm64), built with Swift 6.4 / SDK 27; Intel, universal binaries and another Mac are not validated.
- A microphone. Internet is needed for a missing Apple language model; recognition itself uses the on-device transcriber. No cloud fallback, account or API key is implemented.

## Build and install locally

Open Terminal in this repository, then run:

```sh
bash mac/build.sh
bash mac/install.sh
```

The installer copies the verified bundle into **your home folder → Applications → Pip Voice.app**, not the system-wide Applications folder. If that home Applications folder does not exist, it creates it. Nothing is automatically launched. No sudo is used; running as root is refused. The target name is always Pip Voice.app, never Pip.app, and the bundle ID must be `org.pipvoice.app`.

The installer will **not overwrite** an existing Pip Voice.app, stop a running app, modify another app, migrate preferences, enable Login Items or grant permissions. To update, first quit only Pip Voice through its own menu, then move the old installed copy aside yourself and rerun the installer. This preserves preferences; do not delete preference files as an update step. An explicit `--destination /absolute/directory` selects another containing directory, while keeping the app name fixed.

For a separate candidate without changing the current build bundle:

```sh
bash mac/build.sh --audit
bash mac/Tests/verify-package.sh 'mac/build/audit/Pip Voice.app'
bash mac/install.sh --audit
```

Both build modes strip private debug paths **before** signing and check the resulting signature and package. Ad-hoc signing is development-only and can change macOS permission identity after rebuilds. There is no notarization, Developer ID distribution workflow or Gatekeeper bypass here. If macOS blocks this preview, do not disable protections or remove quarantine; a properly signed/notarized release is a separate task.

## Open it and find it

1. In Finder, choose Go → Home, open Applications, then open **Pip Voice.app**. Or open the local build candidate yourself.
2. It is a **menu-bar app**, not a regular Dock window. Find the microphone icon at the top of the screen. A crowded/hidden menu bar can conceal it.
3. **Setup & settings…** opens automatically the first time. You can always reopen it from the microphone menu; a previous preview may already have marked the first launch as completed.
4. Choose a supported language and shortcut. Default: **Control–Option–Space**. The shortcut recorder accepts combinations or supported single right-side modifiers; Escape keeps the old value and Delete clears it. A conflicting combination is rejected. Single modifiers also need Accessibility.

## Permissions: what is actually used

- **Microphone:** macOS asks when you explicitly start dictation, not when this guide opens. Allow it to speak. If denied, use the app's Microphone settings button, then change only Pip Voice's entry in System Settings → Privacy & Security → Microphone.
- **Accessibility:** optional for the default combination and menu recording; needed for automatic Command-V, modifier-only shortcuts, global Escape and caret location. Use **Allow Accessibility…**, then enable Pip Voice yourself in System Settings. The app polls for this grant for up to five minutes or you can click its menu's refresh action. Do not alter another app's permissions.
- **Speech Recognition:** this implementation uses `SpeechAnalyzer` / `SpeechTranscriber`, not `SFSpeechRecognizer.requestAuthorization`. It does not request a separate Speech Recognition authorization; do not troubleshoot it by granting permissions to unrelated apps.
- No automation/Apple Events, contacts, calendar, files-library, login-item or network permission is requested by the app. Apple manages model asset downloads.

## A safe first test in TextEdit

1. Open TextEdit yourself (the setup has a button) and create a **new blank document**. Do not use a password field, terminal, chat composer or important document for your first test.
2. Close setup and click in the blank document. Tap **Control–Option–Space** once. Wait for **Listening**; initial preparation can show a permission prompt or model download.
3. Say a short, non-sensitive sentence. Tap the shortcut again to finish. Alternatively hold the shortcut, wait for Listening, speak and release it. Do not press Return.
4. Success with Accessibility: text appears at the currently focused editable field. “Paste shortcut sent” means only that Command-V was posted, not that TextEdit accepted it. Without permission or with uncertain focus, **Copied** means you must press Command-V yourself. Recent dictations can recover recognized text.
5. Cancel any preparation/recording/finalization using **Cancel dictation** in the microphone menu. Escape works globally only with Accessibility and no key settings window. A recording has a five-minute limit.
6. Dictated text is saved in the local 20-entry history, with no history-off setting or app-level encryption. Use **Recent dictations → Clear history** after this test if desired. That does not erase TextEdit documents, the clipboard, clipboard-manager history or backups.

Paste uses the field focused **at delivery**, not the field focused when recording began. No form is intentionally submitted; the app never posts Return. Clipboard restoration after 600 ms is best-effort and can be too soon for a slow destination.

## If the test fails

| Symptom | What to check |
| --- | --- |
| No window / no Dock icon | Expected for a menu-bar app. Use the microphone → Setup & settings… |
| Default shortcut does nothing | Use microphone → Start dictation. If that works, choose another shortcut; another app or macOS may own the combination. |
| Preparing / downloading | Finish the OS prompt or download; cancellation remains in the menu. Do not assume it is listening until Listening appears. |
| Microphone denied / no device | Inspect only Pip Voice's Microphone setting and select/connect a working input in macOS. No recording test runs automatically. |
| Unsupported Mac or language | Pick a language in setup. If SpeechTranscriber is unavailable, this app has no server fallback. |
| Copied, but nothing inserted | Focus TextEdit and press Command-V yourself. For automatic insertion, explicitly grant Accessibility. Unknown fields are copy-only. |
| Paste shortcut sent, but no text | A keypost is not an acknowledgment. Recover from Recent dictations; slow apps may read after clipboard restoration. |
| Permissions stopped after rebuilding | Ad-hoc rebuilds may lose TCC identity. Quit only Pip Voice and follow System Settings for its entry; do not reset global privacy databases. |
| Menu crashes in an earlier preview | The reviewed revision fixes a named-suite initialization crash. Use the new verified bundle; do not erase history or other preferences to work around it. |
| Works on this Mac, fails elsewhere | Hardware, macOS 26, first asset download, offline behavior and stable signing still require supervised clean-Mac tests. |

There is no hidden automatic installer, microphone test, permission grant or cross-app paste in these setup steps.
