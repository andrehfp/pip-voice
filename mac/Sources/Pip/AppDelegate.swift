import AppKit
import Carbon

/// Dictation only: no server, account, telemetry or cloud cleanup.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let dictation = Dictation()
    private let overlay = VoiceOverlay()
    private let settings = SettingsWindow()
    private let trigger = ModifierTrigger()
    private var statusItem: NSStatusItem!
    private var gesture = RecordingGesture()
    private var spec = ShortcutSpec.load("shortcut.dictate", default: .dictateDefault)
    private var pending: DispatchWorkItem?
    private var timeout: DispatchWorkItem?
    private var startup: Task<Void, Error>?
    private let ownership = RecordingCoordinator()
    private var operation: UUID? { ownership.id }
    private var paused = false
    private var permissionTimer: Timer?
    private var shortcutProblem: String?
    private var lastStatus = "Ready"
    private var terminating = false

    private var localeID: String {
        get { UserDefaults.standard.string(forKey: "dictationLocale") ?? Locale.current.identifier }
        set { UserDefaults.standard.set(newValue, forKey: "dictationLocale") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A generic development identity, intentionally unrelated to the assistant app.
        guard Bundle.main.bundleIdentifier == "org.pipvoice.app" else {
            let alert = NSAlert()
            alert.messageText = "Open Pip Voice.app instead"
            alert.informativeText = "Build with bash mac/build.sh, then open the app bundle. Running the bare executable cannot provide isolated permissions and preferences."
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "Pip Voice")
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        trigger.onPress = { [weak self] in self?.press(modifier: true) }
        trigger.onRelease = { [weak self] in self?.release() }
        trigger.onChord = { [weak self] in
            guard let self else { return }
            self.clearPending()
            self.apply(self.gesture.chord())
        }
        trigger.onEscape = { [weak self] in
            guard NSApp.keyWindow == nil else { return }
            self?.cancel()
        }
        settings.current = { [weak self] in self?.spec ?? .none }
        settings.change = { [weak self] in self?.changeShortcut($0) }
        settings.pause = { [weak self] in self?.pauseShortcuts($0) }
        settings.localeID = { [weak self] in self?.localeID ?? "en-US" }
        settings.changeLocale = { [weak self] in self?.localeID = $0 }
        settings.requestAccessibility = { [weak self] in self?.allowAccessibility() }
        settings.openMicrophoneSettings = { [weak self] in self?.openMicrophone() }
        configureShortcuts()
        updateStatus("Ready")
        if !UserDefaults.standard.bool(forKey: "welcomed") {
            settings.show()
            UserDefaults.standard.set(true, forKey: "welcomed")
        }
    }

    private func configureShortcuts() {
        // Replacing listeners can lose the physical key-up; close any gesture first.
        cancel()
        trigger.stop()
        trigger.key = nil
        HotKeys.shared.unregister(id: 1)
        shortcutProblem = nil
        guard !paused else { return }
        switch spec {
        case let .combo(key, modifiers, _):
            if !HotKeys.shared.register(id: 1, keyCode: Int(key), modifiers: Int(modifiers), handler: { [weak self] pressed in
                if pressed { self?.press(modifier: false) } else { self?.release() }
            }) { shortcutProblem = "\(spec.label) is in use. Choose another shortcut in Settings."
            }
        case let .modifier(key):
            if Paster.allowed { trigger.key = key }
            else { shortcutProblem = "Allow Accessibility to use a modifier-only shortcut, or choose a key combination." }
        case .none: break
        }
        // Global Escape/modifier observation needs Accessibility; do not prompt automatically.
        if Paster.allowed { trigger.start() }
    }

    private func changeShortcut(_ new: ShortcutSpec) -> String? {
        if case let .combo(key, modifiers, _) = new {
            guard HotKeys.shared.register(id: 1, keyCode: Int(key), modifiers: Int(modifiers), handler: { _ in }) else {
                return "That combination is already in use. Choose another."
            }
            HotKeys.shared.unregister(id: 1)
        }
        spec = new
        new.save("shortcut.dictate")
        return nil
    }

    private func pauseShortcuts(_ pause: Bool) {
        paused = pause
        if pause { cancel() }
        configureShortcuts()
    }
    private func clearPending() { pending?.cancel(); pending = nil }
    private func press(modifier: Bool) {
        guard !paused else { return }
        apply(gesture.press(modifier: modifier, at: ProcessInfo.processInfo.systemUptime))
    }
    private func release() {
        clearPending()
        apply(gesture.release(at: ProcessInfo.processInfo.systemUptime))
    }
    private func apply(_ effects: [RecordingGesture.Effect]) {
        for effect in effects {
            switch effect {
            case .delayStart:
                clearPending()
                let work = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    self.pending = nil
                    self.apply(self.gesture.delayElapsed())
                }
                pending = work
                DispatchQueue.main.asyncAfter(deadline: .now() + RecordingGesture.chordDelay, execute: work)
            case .begin: begin()
            case .latch: break // Startup status must not falsely claim the microphone is ready.
            case .finish: finish()
            case .cancel: cancelAudio()
            }
        }
    }

    private func begin() {
        guard let token = ownership.begin() else { return }
        let terms = Vocabulary.load().terms
        updateStatus("Preparing microphone and language model…")
        overlay.show("Preparing… A missing language model may need a download.")
        let limit = DispatchWorkItem { [weak self] in
            guard let self, self.operation == token else { return }
            self.apply(self.gesture.stop())
        }
        timeout = limit
        DispatchQueue.main.asyncAfter(deadline: .now() + RecordingGesture.maximumDuration, execute: limit)
        do {
            let task = try dictation.start(locale: Locale(identifier: localeID), terms: terms,
                onStatus: { [weak self] status in
                    guard let self, self.operation == token, self.gesture.active else { return }
                    self.updateStatus(status)
                    self.overlay.show(status)
                }, onLevel: { [weak self] value in
                    guard let self, self.operation == token, self.gesture.active else { return }
                    self.overlay.level(value)
                }, onPartial: { [weak self] text in
                    guard let self, self.operation == token, self.gesture.active, !text.isEmpty else { return }
                    self.overlay.show(text, listening: true)
                }, onFailure: { [weak self] error in
                    guard let self, self.operation == token, self.gesture.active else { return }
                    self.cancel()
                    self.report(error.localizedDescription, error: true)
                })
            startup = task
            Task {
                do {
                    try await task.value
                    guard operation == token, gesture.active else { return }
                    updateStatus("Listening")
                    overlay.show("Listening · tap to stop, hold and release, or Esc to cancel", listening: true)
                } catch {
                    guard operation == token, gesture.active else { return }
                    complete(token)
                    report(error.localizedDescription, error: true)
                }
            }
        } catch {
            complete(token)
            report(error.localizedDescription, error: true)
        }
    }

    private func finish() {
        guard let token = operation else { gesture.complete(); return }
        timeout?.cancel()
        dictation.requestStop()
        updateStatus("Finishing")
        overlay.show("Finishing…")
        let starting = startup
        Task {
            defer { complete(token) }
            do {
                guard let raw = try await ownership.finish(token, startup: starting,
                    stop: { try await self.dictation.stop() },
                    cancel: { await self.dictation.cancel() }) else { return }
                guard ownership.mayDeliver(token) else { return }
                let text = Vocabulary.fix(raw, with: Vocabulary.load())
                guard !text.isEmpty else { report("No speech recognized. Nothing was pasted."); return }
                DictationHistory.add(text)
                deliver(text)
            } catch {
                guard ownership.mayDeliver(token) else { return }
                report(error.localizedDescription, error: true)
            }
        }
    }

    private func cancel() {
        clearPending()
        apply(gesture.cancel())
    }
    private func cancelAudio() {
        guard let token = operation, ownership.requestCancel(token) else { return }
        timeout?.cancel()
        dictation.requestCancel()
        report("Cancelled. Nothing was pasted.")
        Task {
            await ownership.cancel(token, cleanup: { await self.dictation.cancel() })
            complete(token)
        }
    }
    private func complete(_ token: UUID) {
        guard ownership.complete(token) else { return }
        timeout?.cancel(); timeout = nil
        startup = nil
        gesture.complete()
        if terminating { NSApp.reply(toApplicationShouldTerminate: true) }
    }
    private func updateStatus(_ text: String) {
        lastStatus = text
        statusItem?.button?.toolTip = "Pip Voice · \(text)"
    }
    private func report(_ text: String, error: Bool = false) {
        updateStatus(text)
        overlay.flash(text, needsAttention: error)
    }
    private func deliver(_ text: String) {
        switch Paster.deliver(text) {
        case .pasted: report("Paste shortcut sent")
        case .pastedAndCopied: report("Paste shortcut sent · text also kept on clipboard")
        case .copied, .destinationChanged: report("Copied · no editable field was identified")
        case .needsPermission: report("Copied · allow Accessibility to paste automatically", error: true)
        case .failed: report("Clipboard write failed. No paste shortcut was sent. Text is in Recent dictations.", error: true)
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        func item(_ title: String, _ action: Selector? = nil, enabled: Bool = true) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.isEnabled = action != nil && enabled
            return item
        }
        menu.addItem(item("Pip Voice · \(lastStatus)"))
        menu.addItem(item("\(spec.label) · tap or hold"))
        if let problem = shortcutProblem { menu.addItem(item(problem)) }
        menu.addItem(.separator())
        menu.addItem(item(gesture.active ? "Stop dictation" : "Start dictation", #selector(toggleDictation), enabled: gesture.active || gesture.state == .idle))
        menu.addItem(item("Cancel dictation", #selector(cancelFromMenu), enabled: operation != nil))
        menu.addItem(item("Setup & settings…", #selector(openSettings)))
        menu.addItem(item("Edit vocabulary…", #selector(editVocabulary)))
        let recent = NSMenu()
        recent.autoenablesItems = false
        for text in DictationHistory.items {
            let entry = item(String(text.prefix(70)), #selector(copyRecent(_:)))
            entry.representedObject = text
            entry.toolTip = "Copy this dictation"
            recent.addItem(entry)
        }
        if recent.items.isEmpty { recent.addItem(item("No recent dictations")) }
        recent.addItem(.separator())
        recent.addItem(item("Clear history", #selector(clearHistory), enabled: !DictationHistory.items.isEmpty))
        let history = item("Recent dictations · click to copy", #selector(noop))
        history.submenu = recent
        menu.addItem(history)
        menu.addItem(.separator())
        menu.addItem(item(Paster.allowed ? "Accessibility allowed · refresh shortcuts" : "Allow Accessibility…", #selector(allowAccessibility)))
        menu.addItem(item("Microphone permissions…", #selector(openMicrophone)))
        menu.addItem(.separator())
        menu.addItem(item("Quit Pip Voice", #selector(quit)))
    }
    @objc private func noop() {}
    @objc private func toggleDictation() {
        if gesture.active { apply(gesture.stop()); return }
        // Let the menu close before recording; never activate the app or refocus a destination.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.gesture.state == .idle else { return }
            self.apply(self.gesture.press(modifier: false, at: ProcessInfo.processInfo.systemUptime))
            self.apply(self.gesture.release(at: ProcessInfo.processInfo.systemUptime))
        }
    }
    @objc private func cancelFromMenu() { cancel() }
    @objc private func openSettings() { cancel(); settings.show() }
    @objc private func editVocabulary() { cancel(); Vocabulary.edit() }
    @objc private func clearHistory() { DictationHistory.clear() }
    @objc private func copyRecent(_ item: NSMenuItem) {
        guard let text = item.representedObject as? String else { return }
        // Copy through the same ownership coordinator, revoking any pending restore.
        report(Paster.copy(text) ? "Copied to clipboard" : "Clipboard write failed", error: false)
    }
    @objc private func allowAccessibility() {
        if !Paster.allowed { Paster.requestPermission() }
        configureShortcuts()
        permissionTimer?.invalidate()
        var checks = 0
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                checks += 1
                guard let self else { timer.invalidate(); return }
                if Paster.allowed { timer.invalidate(); self.configureShortcuts() }
                else if checks >= 150 { timer.invalidate() }
            }
        }
    }
    @objc private func openMicrophone() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
    }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard operation != nil else { return .terminateNow }
        terminating = true
        cancel()
        return .terminateLater
    }
    func applicationWillTerminate(_ notification: Notification) {
        clearPending(); timeout?.cancel(); permissionTimer?.invalidate()
        trigger.stop(); HotKeys.shared.unregister(id: 1)
    }
}
