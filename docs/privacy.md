# Privacy boundary

- Audio is consumed in memory by AVAudioEngine and Apple's SpeechAnalyzer/SpeechTranscriber. The app has no audio recording files, network client, assistant server, account, credentials or telemetry path.
- macOS may download speech language assets. These system assets are not shipped in the repository or app bundle.
- Local vocabulary hints enter the on-device recognition context. Local correction rules modify the resulting text without contacting a provider.
- A rolling list of 20 unique dictations is saved in UserDefaults under `org.pipvoice.app`. There is no history-off setting or app-level encryption. Clear history removes that preference; it does not remove copied text from other apps, clipboard managers or backups.
- The clipboard is materialized for best-effort restoration during automatic paste. Copies remain under normal macOS clipboard rules, and any clipboard manager can observe them.
- Accessibility is used to observe modifier/Escape events, locate the focused caret, classify the current destination and post Command-V. It is not used to collect browsing history or upload window contents.
- Preferences, permission identity and Application Support path are separate from the assistant. No migration or reads of that app's private data are performed.
