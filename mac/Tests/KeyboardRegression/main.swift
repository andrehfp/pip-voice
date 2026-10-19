import AppKit

/// Synthetic NSEvents only. No live monitors, event posting, windows, preferences, network or microphone.
@main
struct KeyboardRegressionTests {
    @MainActor
    static func main() {
        testRecorderConsumption()
        testModifierRouting()
        for key in [ModifierKey.fn, .rightOption] {
            testConsecutiveHyperSessions(next: key, cancelFirst: false)
            testConsecutiveHyperSessions(next: key, cancelFirst: true)
        }
        testMonitorLifecycle()
        print("Keyboard regressions: 7 groups passed; synthetic events and offscreen controls only")
    }

    static func event(_ type: NSEvent.EventType = .keyDown, key: UInt16, flags: NSEvent.ModifierFlags = [], text: String = "", repeatKey: Bool = false) -> NSEvent {
        NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: 1,
            windowNumber: 0, context: nil, characters: text, charactersIgnoringModifiers: text,
            isARepeat: repeatKey, keyCode: key)!
    }

    @MainActor
    static func testRecorderConsumption() {
        var handler: ((NSEvent) -> NSEvent?)!
        weak var released: ShortcutRecorder?
        let letter = event(key: 0, text: "a")
        autoreleasepool {
            var recorder: ShortcutRecorder? = ShortcutRecorder(spec: .none, installMonitor: { _ in nil })
            var changes: [ShortcutSpec] = []
            recorder!.onChange = { changes.append($0); return nil }
            handler = recorder!.makeMonitorHandler()
            precondition(handler(letter) === letter, "An inactive recorder must pass the original event through")
            recorder!.start()
            precondition(handler(letter) == nil, "Plain keys must not leak out of the shortcut recorder")
            precondition(changes.isEmpty)
            precondition(handler(event(key: 53)) == nil, "Escape must not reach the underlying window")
            precondition(!recorder!.isRecording)
            recorder!.start()
            precondition(handler(event(key: 51)) == nil, "Delete must not reach the underlying field")
            precondition(changes == [.none])
            recorder!.start()
            let combo = event(key: 35, flags: [.command, .shift], text: "p")
            precondition(handler(combo) == nil, "A saved shortcut must not also run as a menu shortcut")
            precondition(changes.last == ShortcutSpec.combo(from: combo))
            recorder!.start()
            precondition(handler(event(.flagsChanged, key: 61, flags: NSEvent.ModifierFlags(rawValue: ModifierKey.rightOption.mask))) == nil)
            precondition(handler(event(.flagsChanged, key: 61)) == nil)
            precondition(changes == [.none, ShortcutSpec.combo(from: combo)!, .modifier(.rightOption)],
                "Each consumed save must commit exactly once")
            precondition(handler(letter) === letter, "Stopped sessions must not consume events")
            released = recorder
            recorder = nil
        }
        precondition(released == nil, "The monitor callback must not retain its owner")
        precondition(handler(letter) === letter, "A missing owner must pass the original event through")
        print("PASS: recorder consumes plain/combo/Escape/Delete/modifier events; weak-owner fallback preserves identity")
    }

    /// The real start/stop and installed monitor callback, with no live monitor or window.
    @MainActor
    static func testConsecutiveHyperSessions(next key: ModifierKey, cancelFirst: Bool) {
        let monitor = FakeRecorderMonitor()
        let recorder = ShortcutRecorder(spec: .none, installMonitor: monitor.install, removeMonitor: monitor.remove)
        var changes: [ShortcutSpec] = []
        recorder.onChange = { changes.append($0); return nil }
        recorder.start()
        precondition(monitor.route(event(.flagsChanged, key: 55, flags: ModifierKey.hyperFlags)) == nil)
        if cancelFirst {
            recorder.cancel()
            precondition(changes.isEmpty)
        } else {
            precondition(monitor.route(event(.flagsChanged, key: 55)) == nil)
            precondition(changes == [.modifier(.hyper)])
        }
        precondition(!recorder.isRecording && monitor.removals == 1)
        recorder.start()
        let flags = NSEvent.ModifierFlags(rawValue: key.mask)
        precondition(monitor.route(event(.flagsChanged, key: key.keyCode, flags: flags)) == nil)
        precondition(monitor.route(event(.flagsChanged, key: key.keyCode)) == nil)
        let expected: [ShortcutSpec] = cancelFirst ? [.modifier(key)] : [.modifier(.hyper), .modifier(key)]
        precondition(changes == expected, "A previous Hyper candidate must not contaminate the next session")
        precondition(!recorder.isRecording && monitor.installations == 2 && monitor.removals == 2)
        print("PASS: \(cancelFirst ? "cancelled" : "saved") Hyper -> \(key.label) uses two clean production recorder sessions")
    }

    @MainActor
    static func testMonitorLifecycle() {
        let monitor = FakeRecorderMonitor()
        let recorder = ShortcutRecorder(spec: .none, installMonitor: monitor.install, removeMonitor: monitor.remove)
        var recording: [Bool] = []
        var changes: [ShortcutSpec] = []
        recorder.onRecording = { recording.append($0) }
        recorder.onChange = { changes.append($0); return nil }
        recorder.start()
        recorder.start()
        precondition(monitor.installations == 1, "Starting twice must not leak a second monitor")
        precondition(monitor.route(event(.flagsChanged, key: 61,
            flags: NSEvent.ModifierFlags(rawValue: ModifierKey.rightOption.mask))) == nil)
        recorder.cancel()
        recorder.cancel()
        let letter = event(key: 0, text: "a")
        precondition(monitor.route(letter) === letter)
        recorder.start()
        precondition(monitor.route(event(.flagsChanged, key: 61)) == nil)
        precondition(changes.isEmpty, "Cancelled single-modifier candidates must not carry into another session")
        recorder.cancel()
        precondition(recording == [true, false, true, false] && monitor.removals == 2)
        print("PASS: repeated start/cancel is balanced; stopped callbacks preserve identity and candidates reset")
    }

    @MainActor
    static func testModifierRouting() {
        let trigger = ModifierTrigger()
        trigger.key = .rightOption
        var presses = 0
        var releases = 0
        var chords = 0
        var escapes = 0
        trigger.onPress = { presses += 1 }
        trigger.onRelease = { releases += 1 }
        trigger.onChord = { chords += 1 }
        trigger.onEscape = { escapes += 1 }
        for _ in 0..<20 { trigger.handle(event(key: 0, text: "a")) }
        precondition(presses == 0 && releases == 0 && chords == 0 && escapes == 0)
        let down = event(.flagsChanged, key: 61, flags: NSEvent.ModifierFlags(rawValue: ModifierKey.rightOption.mask))
        trigger.handle(down)
        trigger.handle(down)
        precondition(presses == 1 && trigger.isDown)
        trigger.handle(event(key: 0, text: "a"))
        precondition(chords == 1)
        trigger.handle(event(.flagsChanged, key: 61))
        trigger.handle(event(.flagsChanged, key: 61))
        precondition(releases == 1 && !trigger.isDown)
        trigger.handle(event(key: 53))
        precondition(escapes == 1)
        trigger.handle(down)
        trigger.stop()
        precondition(!trigger.isDown)
        trigger.handle(event(key: 0, text: "a"))
        precondition(chords == 1)
        print("PASS: plain typing has no trigger action; modifier edges are single-shot; stop resets state")
    }
}

/// Records the production-installed callback, but never calls NSEvent's monitor APIs.
@MainActor
private final class FakeRecorderMonitor {
    private var handler: ShortcutRecorder.MonitorHandler?
    private let token = NSObject()
    private(set) var installations = 0
    private(set) var removals = 0

    func install(_ handler: @escaping ShortcutRecorder.MonitorHandler) -> Any? {
        installations += 1
        self.handler = handler
        return token
    }

    func remove(_ token: Any) {
        precondition((token as AnyObject) === self.token)
        removals += 1
        // Keep a reference to simulate a callback already in flight when a monitor is removed.
    }

    func route(_ event: NSEvent) -> NSEvent? { handler!(event) }
}
