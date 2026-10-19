import Foundation

// Production state machine only: no AppKit, audio, preferences or synthetic monitors.
private var assertions = 0
private var failures = 0
private var groups = 0

private func expect<T: Equatable>(_ actual: T, _ expected: T, _ label: String, line: Int = #line) {
    assertions += 1
    if actual != expected {
        failures += 1
        print("FAIL line \(line): \(label): expected \(expected), got \(actual)")
    }
}
private func group(_ name: String, _ body: () -> Void) {
    groups += 1
    let before = failures
    body()
    print("\(failures == before ? "PASS" : "FAIL") \(name)")
}

group("Constants preserve the timing contract") {
    expect(RecordingGesture.chordDelay, 0.12, "chord delay")
    expect(RecordingGesture.tapLimit, 0.3, "tap threshold")
    expect(RecordingGesture.maximumDuration, 300, "five-minute safety limit")
}

group("Combination tap latches and next press finishes exactly once") {
    var g = RecordingGesture()
    expect(g.state, .idle, "initial state")
    expect(g.active, false, "initial activity")
    expect(g.press(modifier: false, at: 10), [.begin], "immediate start")
    expect(g.state, .holding, "holding")
    expect(g.active, true, "active")
    expect(g.release(at: 10.1), [.latch], "quick release")
    expect(g.state, .latched, "latched")
    expect(g.release(at: 10.2), [], "duplicate release")
    expect(g.press(modifier: false, at: 11), [.finish], "toggle stop")
    expect(g.state, .finishing, "finishing")
    expect(g.active, false, "no active capture while finishing")
    expect(g.press(modifier: false, at: 11.1), [], "repeat while finishing")
    expect(g.release(at: 11.2), [], "release after toggle")
    expect(g.stop(), [], "duplicate stop")
}

group("Combination holds use a strict 300ms boundary") {
    for duration in [0.299, 0.3, 0.301, 2.0] {
        var g = RecordingGesture()
        expect(g.press(modifier: false, at: 0), [.begin], "start")
        expect(g.release(at: duration), duration < 0.3 ? [.latch] : [.finish], "duration \(duration)")
        expect(g.state, duration < 0.3 ? .latched : .finishing, "boundary state")
    }
}

group("Repeated press does not restart or reset the physical press time") {
    for modifier in [false, true] {
        var g = RecordingGesture()
        expect(g.press(modifier: modifier, at: 100), modifier ? [.delayStart] : [.begin], "first press")
        expect(g.press(modifier: modifier, at: 100.05), [], "repeat before delay")
        if modifier { expect(g.delayElapsed(), [.begin], "delayed begin") }
        expect(g.press(modifier: modifier, at: 100.25), [], "repeat during hold")
        expect(g.release(at: 100.31), [.finish], "repeat must not shorten hold")
    }
}

group("Modifier quick release begins once and rejects the late delay") {
    var g = RecordingGesture()
    expect(g.press(modifier: true, at: 5), [.delayStart], "schedule")
    expect(g.state, .pending, "pending")
    expect(g.active, false, "not active before delay")
    expect(g.release(at: 5.05), [.begin, .latch], "tap before delay")
    expect(g.state, .latched, "latched")
    expect(g.delayElapsed(), [], "late delay cannot begin twice")
    expect(g.release(at: 5.1), [], "duplicate release")
}

group("Modifier delay does not subtract 120ms from hold time") {
    for duration in [0.2, 0.299, 0.3, 0.31, 0.4, 0.5] {
        var g = RecordingGesture()
        expect(g.press(modifier: true, at: 0), [.delayStart], "schedule")
        expect(g.delayElapsed(), [.begin], "120ms elapsed")
        expect(g.delayElapsed(), [], "duplicate timer")
        expect(g.release(at: duration), duration < 0.3 ? [.latch] : [.finish], "physical press duration \(duration)")
    }
    var g = RecordingGesture()
    _ = g.press(modifier: true, at: 800_000)
    _ = g.delayElapsed()
    expect(g.release(at: 800_000.31), [.finish], "large monotonic uptime")
}

group("Chord before delay suppresses capture including late callbacks") {
    var g = RecordingGesture()
    expect(g.press(modifier: true, at: 0), [.delayStart], "schedule")
    expect(g.chord(), [], "suppress pending chord")
    expect(g.state, .idle, "idle after chord")
    expect(g.delayElapsed(), [], "late delay")
    expect(g.release(at: 0.2), [], "late release")
    expect(g.chord(), [], "extra chord")
}

group("Chord after delay cancels and blocks restart until complete") {
    var g = RecordingGesture()
    _ = g.press(modifier: true, at: 0)
    _ = g.delayElapsed()
    expect(g.chord(), [.cancel], "cancel active hold")
    expect(g.state, .finishing, "await cleanup")
    expect(g.chord(), [], "duplicate chord")
    expect(g.release(at: 0.2), [], "release after chord")
    expect(g.delayElapsed(), [], "late timer")
    expect(g.press(modifier: true, at: 1), [], "no overlap")
    g.complete()
    expect(g.press(modifier: true, at: 2), [.delayStart], "new session")
}

group("Latched dictation survives ordinary typing chords") {
    var g = RecordingGesture()
    _ = g.press(modifier: true, at: 0)
    _ = g.release(at: 0.05)
    expect(g.chord(), [], "typing while latched")
    expect(g.state, .latched, "still latched")
    expect(g.stop(), [.finish], "menu or timeout stop")
}

group("Pending cancellation prevents a late begin or release") {
    var g = RecordingGesture()
    expect(g.cancel(), [], "idle cancel")
    _ = g.press(modifier: true, at: 0)
    expect(g.cancel(), [], "pending cancellation requires no audio effect")
    expect(g.state, .idle, "reset pending")
    expect(g.delayElapsed(), [], "late delay after cancellation")
    expect(g.release(at: 0.1), [], "late release after cancellation")
    expect(g.cancel(), [], "duplicate idle cancellation")
    expect(g.press(modifier: false, at: 2), [.begin], "restart")
}

group("Cancellation during finish stays closed until cleanup completes") {
    var g = RecordingGesture()
    _ = g.press(modifier: false, at: 0)
    expect(g.release(at: 1), [.finish], "finish hold")
    expect(g.cancel(), [.cancel], "cancel asynchronous finalization")
    expect(g.state, .finishing, "still awaiting cleanup")
    expect(g.active, false, "not active")
    expect(g.press(modifier: false, at: 2), [], "no concurrent session")
    expect(g.stop(), [], "no extra finish")
    expect(g.delayElapsed(), [], "no late begin")
    expect(g.release(at: 2.1), [], "no late release effect")
    g.complete()
    expect(g.state, .idle, "cleanup complete")
    expect(g.press(modifier: false, at: 3), [.begin], "new session begins")
    expect(g.release(at: 3.05), [.latch], "fresh timing")
    expect(g.cancel(), [.cancel], "new session cancellation")
    g.complete()
    expect(g.state, .idle, "second cleanup complete")
}

group("Completion resets every gesture state") {
    for mode in 0..<5 {
        var g = RecordingGesture()
        if mode == 1 { _ = g.press(modifier: true, at: 0) }
        if mode >= 2 { _ = g.press(modifier: false, at: 0) }
        if mode == 3 { _ = g.release(at: 0.05) }
        if mode == 4 { _ = g.stop() }
        g.complete()
        expect(g.state, .idle, "reset mode \(mode)")
        expect(g.active, false, "inactive after reset")
        expect(g.delayElapsed(), [], "late timer after complete")
        expect(g.release(at: 1), [], "late release after complete")
        expect(g.press(modifier: false, at: 5), [.begin], "new operation after reset")
    }
}


// A busy main queue can deliver key-up before the delayed work item executes.
// Long holds must not turn into latched recording merely because the timer is late.
group("Long pending release must not latch when the timer is late") {
    var g = RecordingGesture()
    _ = g.press(modifier: true, at: 0)
    let effects = g.release(at: 0.5)
    expect(effects.contains(.latch), false, "500ms physical hold is not a tap")
    expect(g.active, false, "released hold must not leave capture active")
    expect(g.delayElapsed(), [], "late timer cannot start capture after release")
}

print("\(groups) groups, \(assertions) assertions, \(failures) failures")
if failures != 0 { exit(1) }
