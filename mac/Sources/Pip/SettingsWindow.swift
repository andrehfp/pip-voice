import AppKit
import Speech

@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate {
    var current: () -> ShortcutSpec = { .none }
    var change: (ShortcutSpec) -> String? = { _ in nil }
    var pause: (Bool) -> Void = { _ in }
    var localeID: () -> String = { Locale.current.identifier }
    var changeLocale: (String) -> Void = { _ in }
    var requestAccessibility: () -> Void = {}
    var openMicrophoneSettings: () -> Void = {}

    private var window: NSWindow?
    private var recorder: ShortcutRecorder?
    private var languageTask: Task<Void, Never>?
    private let languages = NSPopUpButton()
    private let hint = NSTextField(wrappingLabelWithString: "")
    private let languageHint = NSTextField(wrappingLabelWithString: "")
    private let defaultHint = "Tap to start, tap again to finish. Or hold to speak and release to finish. Global Escape requires Accessibility. Cancel is always available in the menu."

    func show() {
        if window == nil { build() }
        recorder?.spec = current()
        hint.stringValue = defaultHint
        loadLanguages()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        cancelEditing()
        window?.close()
    }

    private func cancelEditing() {
        recorder?.cancel()
        pause(false)
        languageTask?.cancel()
        languageTask = nil
    }

    func windowWillClose(_ notification: Notification) { cancelEditing() }
    func windowDidResignKey(_ notification: Notification) { recorder?.cancel() }

    private func loadLanguages() {
        languageTask?.cancel()
        languages.removeAllItems()
        languages.addItem(withTitle: "Loading languages…")
        languages.isEnabled = false
        languageHint.stringValue = "Checking languages supported on this Mac."
        languageTask = Task { [weak self] in
            let supported = await SpeechTranscriber.supportedLocales
            guard !Task.isCancelled, let self else { return }
            let english = Locale(identifier: "en")
            let locales = supported.sorted {
                (english.localizedString(forIdentifier: $0.identifier) ?? $0.identifier) <
                (english.localizedString(forIdentifier: $1.identifier) ?? $1.identifier)
            }
            self.languages.removeAllItems()
            for locale in locales {
                self.languages.addItem(withTitle: english.localizedString(forIdentifier: locale.identifier) ?? locale.identifier)
                self.languages.lastItem?.representedObject = locale.identifier
            }
            let selected = Locale(identifier: self.localeID()).identifier.replacingOccurrences(of: "_", with: "-")
            let item = self.languages.itemArray.first {
                ($0.representedObject as? String)?.replacingOccurrences(of: "_", with: "-") == selected
            }
            self.languages.select(item)
            self.languages.isEnabled = !locales.isEmpty
            self.languageHint.stringValue = locales.isEmpty
                ? "No supported speech languages are available on this Mac."
                : item == nil ? "Choose a supported language to continue." : "Missing Apple language assets download when dictation starts."
        }
    }

    @objc private func selectLanguage() {
        guard let id = languages.selectedItem?.representedObject as? String else { return }
        changeLocale(id)
        languageHint.stringValue = "Missing Apple language assets download when dictation starts."
    }

    private func build() {
        let rows = NSStackView()
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 16
        rows.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        func label(_ text: String, title: Bool = false) -> NSTextField {
            let field = NSTextField(wrappingLabelWithString: text)
            field.font = .systemFont(ofSize: title ? 15 : 13, weight: title ? .semibold : .regular)
            field.textColor = title ? Rams.ink : Rams.ink2
            field.preferredMaxLayoutWidth = 432
            field.widthAnchor.constraint(equalToConstant: 432).isActive = true
            return field
        }
        rows.addArrangedSubview(label("Pip Voice · quick start", title: true))
        rows.addArrangedSubview(label("Local dictation. No account, server or AI cleanup. Audio is recognized on this Mac using Apple's speech models; the first language download needs internet. Requires supported hardware and macOS 26 or later."))
        rows.addArrangedSubview(label("1 · Choose your shortcut", title: true))
        let recorder = ShortcutRecorder(spec: current())
        recorder.widthAnchor.constraint(equalToConstant: 260).isActive = true
        recorder.setAccessibilityLabel("Dictation shortcut")
        recorder.onChange = { [weak self] in self?.change($0) }
        recorder.onRecording = { [weak self] in self?.pause($0) }
        recorder.onHint = { [weak self] in self?.hint.stringValue = $0 }
        self.recorder = recorder
        rows.addArrangedSubview(recorder)
        for field in [hint, languageHint] {
            field.font = .systemFont(ofSize: 11)
            field.textColor = Rams.ink2
            field.preferredMaxLayoutWidth = 432
            field.widthAnchor.constraint(equalToConstant: 432).isActive = true
        }
        rows.addArrangedSubview(hint)
        rows.addArrangedSubview(label("2 · Choose your language", title: true))
        languages.font = .systemFont(ofSize: 13)
        languages.target = self
        languages.action = #selector(selectLanguage)
        languages.setAccessibilityLabel("Dictation language")
        languages.widthAnchor.constraint(equalToConstant: 432).isActive = true
        rows.addArrangedSubview(languages)
        rows.addArrangedSubview(languageHint)
        rows.addArrangedSubview(label("3 · Allow only what you need", title: true))
        rows.addArrangedSubview(label("Allow Microphone access to dictate. Accessibility enables a modifier-only shortcut, global Escape cancellation and automatic pasting. Without it, use a key combination: your words stay copied so you can paste manually. Automatic insertion is not guaranteed in every app."))
        func button(_ title: String, _ action: @escaping () -> Void) -> NSButton {
            let button = NSButton(title: title, target: nil, action: nil)
            button.bezelStyle = .rounded
            button.font = .systemFont(ofSize: 13)
            button.onClick(action)
            return button
        }
        let permissions = NSStackView(views: [
            button("Microphone settings…") { [weak self] in self?.openMicrophoneSettings() },
            button("Allow Accessibility…") { [weak self] in self?.requestAccessibility() }
        ])
        permissions.spacing = 12
        rows.addArrangedSubview(permissions)
        rows.addArrangedSubview(label("The microphone prompt appears only when you start dictation. The app uses SpeechAnalyzer, not the older cloud speech authorization API; it does not request a separate Speech Recognition permission. Only macOS can grant permissions. These buttons do not grant access."))
        rows.addArrangedSubview(label("4 · Try a harmless sentence", title: true))
        rows.addArrangedSubview(label("Open TextEdit and create a blank document. Close this window and click inside that document. Tap Control–Option–Space (or your chosen shortcut), wait for Listening, say a short non-sensitive sentence, then tap the shortcut again. Do not press Return. No recording begins from this setup window."))
        rows.addArrangedSubview(button("Open TextEdit") {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") else { return }
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        })
        rows.addArrangedSubview(label("Success: the sentence appears in the focused document. If the status says Copied, press Command-V yourself. If nothing happens, use the microphone menu → Start dictation to separate a shortcut conflict from a microphone or language problem. Cancel is always available in the menu. Recent dictations can recover recognized text; it is not proof that a paste was accepted."))
        rows.addArrangedSubview(label("Local vocabulary & history", title: true))
        rows.addArrangedSubview(label("Edit vocabulary from the menu to add terms and corrections. The last 20 distinct dictations are saved locally. Use Recent dictations → Clear history in the menu to erase them."))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 740), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Pip Voice · Setup & settings"
        window.backgroundColor = Rams.bg
        let scroll = NSScrollView(frame: window.contentView?.bounds ?? .zero)
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.autoresizingMask = [.width, .height]
        rows.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = rows
        NSLayoutConstraint.activate([
            rows.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            rows.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            rows.topAnchor.constraint(equalTo: scroll.contentView.topAnchor)
        ])
        window.contentView = scroll
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window
    }
}
