import Foundation

/// Pure shortcut state machine. Time is monotonic and supplied by the caller.
struct RecordingGesture {
    enum State: Equatable { case idle, pending, holding, latched, finishing }
    enum Effect: Equatable { case delayStart, begin, latch, finish, cancel }
    private(set) var state: State = .idle
    private var pressedAt: TimeInterval = 0
    static let chordDelay: TimeInterval = 0.12
    static let tapLimit: TimeInterval = 0.3
    static let maximumDuration: TimeInterval = 300
    var active: Bool { state == .holding || state == .latched }

    mutating func press(modifier: Bool, at time: TimeInterval) -> [Effect] {
        if state == .latched { state = .finishing; return [.finish] }
        guard state == .idle else { return [] }
        pressedAt = time
        state = modifier ? .pending : .holding
        return modifier ? [.delayStart] : [.begin]
    }
    mutating func delayElapsed() -> [Effect] {
        guard state == .pending else { return [] }
        state = .holding
        return [.begin]
    }
    mutating func release(at time: TimeInterval) -> [Effect] {
        if state == .pending {
            // A delayed main queue must not turn an already released hold into latched capture.
            guard time - pressedAt < Self.tapLimit else { state = .idle; return [] }
            state = .latched
            return [.begin, .latch]
        }
        guard state == .holding else { return [] }
        if time - pressedAt < Self.tapLimit { state = .latched; return [.latch] }
        state = .finishing
        return [.finish]
    }
    mutating func chord() -> [Effect] {
        if state == .pending { state = .idle; return [] }
        guard state == .holding else { return [] }
        state = .finishing
        return [.cancel]
    }
    mutating func stop() -> [Effect] {
        guard active else { return [] }
        state = .finishing
        return [.finish]
    }
    mutating func cancel() -> [Effect] {
        if state == .pending { state = .idle; return [] }
        guard state != .idle else { return [] }
        state = .finishing
        return [.cancel]
    }
    mutating func complete() { state = .idle }
}
