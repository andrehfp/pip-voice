# Pip Voice

Native macOS dictation only. English source and UI. No assistant server, chat, AI cleanup, telemetry, account or API keys.

- Build: `bash mac/build.sh` (build only; never installs or launches).
- Test: `bash mac/Tests/run-all.sh` (synthetic effects only).
- Keep identity `org.pipvoice.app` and data `Pip Voice` isolated from other apps.
- Never launch microphones, real key monitors or paste events during automated tests.
- Source-only project: never publish build outputs, personal data or imported private Git history. Binary distribution requires a separate owner decision.
- No third-party runtime dependencies. Apple speech assets are obtained by the OS, never bundled.
