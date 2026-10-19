import Foundation

/// Audio-thread producer: bounded buffering is fail-closed, never a partial transcript presented as complete.
final class AudioInputChannel<Value>: @unchecked Sendable {
	enum Failure: Equatable { case overflow, conversion, consumerStopped, configurationChanged }
	let stream: AsyncStream<Value>
	private let continuation: AsyncStream<Value>.Continuation
	private let lock = NSLock()
	private var ended = false
	private var sealed = false
	private var error: Failure?
	init(capacity: Int = 64) {
		(stream, continuation) = AsyncStream.makeStream(of: Value.self, bufferingPolicy: .bufferingOldest(capacity))
	}
	var failure: Failure? { lock.lock(); defer { lock.unlock() }; return error }
	/// Returns the first failure once, so the UI receives one error even if more tap callbacks were queued.
	func push(_ value: Value) -> Failure? {
		lock.lock(); defer { lock.unlock() }
		guard !ended else { return nil }
		switch continuation.yield(value) {
		case .enqueued: return nil
		case .dropped: return failLocked(.overflow)
		case .terminated: return failLocked(.consumerStopped)
		@unknown default: return failLocked(.consumerStopped)
		}
	}
	func fail(_ failure: Failure) -> Failure? {
		lock.lock(); defer { lock.unlock() }
		// A configuration interruption can invalidate buffered audio even after normal input finish.
		guard !sealed, error == nil, !ended || failure == .configurationChanged else { return nil }
		return failLocked(failure)
	}
	private func failLocked(_ failure: Failure) -> Failure {
		error = failure; ended = true; continuation.finish(); return failure
	}
	/// End the session atomically after final recognition. Later notifications belong to no live session.
	func seal() -> Failure? {
		lock.lock(); defer { lock.unlock() }
		sealed = true; ended = true; continuation.finish()
		return error
	}
	func finish() {
		lock.lock(); defer { lock.unlock() }
		ended = true; continuation.finish()
	}
}
