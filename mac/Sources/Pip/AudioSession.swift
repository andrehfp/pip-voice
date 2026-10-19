import Foundation

/// Main-actor orchestration shared by real dictation and hardware-free lifecycle tests.
/// Reservation and stop intent are synchronous, before either startup or finalization can suspend.
@MainActor
final class AudioSession {
	private final class Session {
		let token: UUID
		let freeze: (Bool) -> Void
		let dispose: (Bool) async throws -> String
		var startup: Task<Void, Error>?
		var teardown: Task<String, Error>?
		var failure: Error?
		var cancelled = false
		init(token: UUID, freeze: @escaping (Bool) -> Void, dispose: @escaping (Bool) async throws -> String) {
			self.token = token; self.freeze = freeze; self.dispose = dispose
		}
	}
	private var lifetime = DictationLifetime()
	private var active: Session?

	func start(
		freeze: @escaping (Bool) -> Void,
		dispose: @escaping (Bool) async throws -> String,
		configure: @escaping (UUID) async throws -> Void
	) -> Task<Void, Error>? {
		guard let token = lifetime.begin() else { return nil }
		let session = Session(token: token, freeze: freeze, dispose: dispose)
		active = session
		let task = Task {
			do {
				try check(token)
				// Finish may have arrived before this task's first turn. Do not start a microphone later.
				if !lifetime.stopRequested { try await configure(token) }
				try check(token)
				try lifetime.ready(token)
			} catch {
				if session.failure == nil { session.failure = error }
				_ = try? await teardown(session, cancel: true)
				throw error
			}
		}
		session.startup = task
		return task
	}

	func owns(_ token: UUID) -> Bool { lifetime.owns(token) }
	func acceptsCallbacks(_ token: UUID) -> Bool { lifetime.acceptsCallbacks(token) }
	func check(_ token: UUID) throws {
		if active?.token == token, let error = active?.failure { throw error }
		try lifetime.check(token)
	}

	/// Synchronous capture boundary after permission/assets, before analyzer preparation.
	/// A stop during an earlier await must never be followed by a late tap.
	func activateCapture(_ token: UUID, _ capture: () throws -> Void) throws {
		try check(token)
		guard lifetime.acceptsCallbacks(token) else { return }
		try capture()
		try check(token)
	}

	func requestStop() {
		guard let session = active else { return }
		lifetime.requestStop(session.token)
		session.freeze(false)
	}

	func fail(_ token: UUID, error: Error) {
		guard let session = active, session.token == token else { return }
		if session.failure == nil { session.failure = error }
		// Also applies while asynchronous finalization is in progress.
		requestStop()
	}

	func requestCancel() {
		guard let session = active else { return }
		session.cancelled = true
		lifetime.requestCancel(session.token)
		session.freeze(true)
		session.startup?.cancel()
	}

	func stop() async throws -> String {
		guard let session = active else { return "" }
		requestStop()
		try await session.startup?.value
		return try await teardown(session, cancel: false)
	}

	func cancel() async {
		guard let session = active else { return }
		requestCancel()
		_ = await session.startup?.result
		_ = try? await teardown(session, cancel: true)
	}

	private func teardown(_ session: Session, cancel: Bool) async throws -> String {
		if let task = session.teardown { return try await task.value }
		guard lifetime.beginTeardown(session.token) else { return "" }
		session.freeze(cancel)
		let task = Task<String, Error> {
			defer {
				lifetime.finish(session.token)
				if active === session { active = nil }
				// Break the session/task retention cycle after the final suspension.
				session.startup = nil
				session.teardown = nil
			}
			do {
				let text = try await session.dispose(cancel)
				if let error = session.failure { throw error }
				if session.cancelled { throw CancellationError() }
				return text
			} catch {
				// Cleanup/consumer errors must not erase the recorded interruption or startup cause.
				throw session.failure ?? error
			}
		}
		session.teardown = task
		return try await task.value
	}
}
