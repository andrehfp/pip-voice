# Supervised test checklist — not executed automatically

Start with [the install and setup guide](setup.md). Automated checks and known release blockers are recorded in [the security review](security-review.md).

Use a separate installation of Pip Voice and a distinct shortcut. Never stop, replace or operate another running app on the user's behalf to perform these tests.

- [ ] Fresh launch, menu-bar visibility, Settings layout in light/dark modes, VoiceOver labels and reduced motion.
- [ ] Microphone allow/deny/revoke, no input device, unsupported hardware and locale.
- [ ] First language download, offline with/without assets, download failure and cancellation during preparation.
- [ ] First word/last word retention, silence, long speech, repeated sessions and five-minute stop.
- [ ] Immediate stop/cancel after press; stop during preparation; Escape during finalization; no late delivery after cancel.
- [ ] Microphone unplug or sample-rate change while recording and while finalizing: no successful partial delivery.
- [ ] Tap/hold for key combinations and modifiers; AltGr symbol chords, Hyper/fn, keyboard layouts and shortcut conflicts.
- [ ] Shortcut recorder consumes keys; closing Settings restores listeners; modifier shortcuts after Accessibility grant.
- [ ] Paste into native fields, browsers and Electron editors; clipboard fallback when Accessibility is denied.
- [ ] Focus switches before finish; unknown/noneditable targets; paste never submits forms.
- [ ] External clipboard change, rich/opaque/file clipboard contents, delayed clipboard readers and rapid repeated deliveries.
- [ ] Recent history copy, deduplication, clear, neutral vocabulary and separate application preferences/data.
- [ ] Quit during recording and pending asset/finalization work; no microphone remains open after process exit.
- [ ] Build and install on a second clean Mac with supported hardware and macOS 26; stable signing/TCC persistence.
- [ ] Distribution identity, Developer ID signing, hardened runtime/entitlement policy, notarization/stapling and Gatekeeper.
