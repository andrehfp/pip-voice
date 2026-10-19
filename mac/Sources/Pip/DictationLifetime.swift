import Foundation

/// An operation reserves its session before the first await. Cleanup keeps ownership until its last await returns.
struct DictationLifetime {
	enum Phase { case idle, starting, recording, tearingDown }
	private(set) var phase: Phase = .idle
	private(set) var id: UUID?
	private var cancelled = false
	private(set) var stopRequested = false
	mutating func begin() -> UUID? {
		guard phase == .idle else { return nil }
		let token = UUID()
		id = token; phase = .starting; cancelled = false; stopRequested = false
		return token
	}
	func owns(_ token: UUID) -> Bool { id == token }
	func acceptsCallbacks(_ token: UUID) -> Bool { owns(token) && !cancelled && !stopRequested && (phase == .starting || phase == .recording) }
	func check(_ token: UUID) throws {
		guard owns(token), !cancelled, phase != .tearingDown, !Task.isCancelled else { throw CancellationError() }
	}
	mutating func ready(_ token: UUID) throws { try check(token); phase = .recording }
	mutating func requestStop(_ token: UUID) { if owns(token) { stopRequested = true } }
	mutating func requestCancel(_ token: UUID) { if owns(token) { cancelled = true; stopRequested = true } }
	mutating func beginTeardown(_ token: UUID) -> Bool {
		guard owns(token), phase != .tearingDown else { return false }
		phase = .tearingDown
		return true
	}
	mutating func finish(_ token: UUID) {
		guard owns(token), phase == .tearingDown else { return }
		phase = .idle; id = nil; cancelled = false; stopRequested = false
	}
}
