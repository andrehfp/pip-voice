# Provenance and licensing

## Source license

The first-party source and documentation in this repository are published under the [MIT License](../LICENSE). Before publication, the owner explicitly confirmed rights to publish the reused components and artwork under MIT and confirmed that no incompatible third-party material was included. This records the owner's confirmation, not an independent legal certification.

## Extraction and adaptations

The initial extraction used a finite allowlist: 25 individually copied implementation/test/runner files and 10 source files inspected only as adaptation references from the owner's private assistant project. [source-manifest.json](source-manifest.json) records hashes of those inspected bytes **before** standalone adaptations. Those hashes describe provenance inputs, not the final public source or an imported Git history.

The reused implementation provides native audio lifecycle, clipboard transactions, paste safety, keyboard handling and presentation helpers. The standalone coordinator, gesture state machine, bootstrap, package, bundle metadata, build flow, settings and overlay replace assistant integration. Vocabulary uses a separate path and neutral examples; preferences use an isolated identity and nonconflicting default shortcut. Unused chat/command defaults and legacy migration are removed. The old dot-matrix artwork is reduced to a color helper; no assistant icon is bundled. Presentation uses system fonts and native drawing, with no redistributed third-party font or artwork files.

The public snapshot also includes the audited menu/history crash correction, copy-only policy for unknown paste targets, local installer, setup guide and regression tests. It was exported by explicit source-file allowlist to a separate repository with fresh history. Original Git objects, local preferences, vocabulary, recordings, logs, authentication, build caches, executable bundles and filesystem metadata are not included.

## Third-party boundary

The Swift package has no third-party package dependencies. Application imports and linked libraries are Apple system frameworks and Swift system libraries. Apple frameworks, system fonts, SF Symbols supplied by macOS and Apple speech model assets are **not relicensed by this project**; their respective terms continue to apply. Speech assets are acquired by the operating system, never bundled in this repository. Review found no third-party license headers or incompatible dependency assets in the selected source.

## Distribution scope

This is an experimental source-build-only publication. No prebuilt executable, release attachment, model download, Developer ID signature, notarization or Gatekeeper certification is provided. Local ad-hoc signing is for development, not a distribution guarantee. Real hardware, microphone/TCC, cross-app insertion and clean-machine checks remain listed in the [manual test checklist](manual-tests.md).
