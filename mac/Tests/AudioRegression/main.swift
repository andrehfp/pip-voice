import Foundation

@MainActor
private final class Gate {
	private var released = false
	private var arrived = false
	private var waiting: CheckedContinuation<Void, Never>?
	private var arrivals: [CheckedContinuation<Void, Never>] = []
	func wait() async {
		arrived = true
		arrivals.forEach { $0.resume() }; arrivals.removeAll()
		if released { return }
		await withCheckedContinuation { waiting = $0 }
	}
	func waitForArrival() async {
		if arrived { return }
		await withCheckedContinuation { arrivals.append($0) }
	}
	func release() { released = true; waiting?.resume(); waiting = nil }
}

private enum TestFailure: Error, Equatable { case prepare, cleanup, interrupted }

@main
struct AudioRegression {
	@MainActor private static var assertions = 0
	@MainActor private static func expect(_ condition: Bool, _ label: String) {
		assertions += 1
		guard condition else { fatalError(label) }
	}
	@MainActor private static func expectError<T>(_ result: Result<T, Error>, _ error: TestFailure, _ label: String) {
		if case .failure(let actual) = result { expect(actual as? TestFailure == error, label) }
		else { expect(false, label) }
	}
	@MainActor private static func expectCancelled<T>(_ result: Result<T, Error>) {
		if case .failure(let error) = result { expect(error is CancellationError, "Expected cancellation") }
		else { expect(false, "Cancellation returned a successful transcript") }
	}
	@MainActor private static func busy(_ session: AudioSession) {
		expect(session.start(freeze: { _ in }, dispose: { _ in "unexpected" }, configure: { _ in }) == nil, "Reservation released before teardown")
	}

	@MainActor static func main() async {
		await stopBeforeStartup()
		await finishBeforeCapture()
		await finishDuringAnalyzerPreparation()
		await startupFailureSurvivesFinish()
		await cancelBeforeStartup()
		await cancelDuringPreparation()
		await normalFinishAndStaleCallbacks()
		await interruptionWhileRecording()
		await interruptionWhileFinishing()
		await cancelWhileFinishing()
		await channelFailures()
		await configurationObservation()
		print("Audio regressions: 12 groups passed, \(assertions) assertions; no audio hardware or live app used.")
	}

	@MainActor private static func stopBeforeStartup() async {
		let session = AudioSession(), teardown = Gate()
		let channel = AudioInputChannel<Int>()
		var configured = false, freezes = 0
		let startup = session.start(freeze: { _ in freezes += 1; channel.finish() }, dispose: { _ in
			await teardown.wait(); return ""
		}, configure: { _ in configured = true })!
		session.requestStop() // Same actor turn as start: task has not run yet.
		expect(freezes == 1, "Stop intent must freeze synchronously")
		let stop = Task { try await session.stop() }
		await teardown.waitForArrival()
		expect(!configured, "Finish before startup must not prepare or install a tap")
		busy(session)
		teardown.release()
		let result = await stop.result
		expect((try? result.get()) == "", "Empty startup stop should succeed without recording")
		_ = await startup.result
		expect(channel.push(1) == nil, "Finished producer must ignore queued audio")
		var values = [Int](); for await value in channel.stream { values.append(value) }
		expect(values.isEmpty, "Audio arrived after synchronous stop")
	}

	@MainActor private static func finishBeforeCapture() async {
		let session = AudioSession(), prerequisites = Gate(), teardown = Gate()
		let channel = AudioInputChannel<Int>()
		var token: UUID?, taps = 0
		let startup = session.start(freeze: { _ in channel.finish() }, dispose: { _ in
			await teardown.wait(); return ""
		}, configure: { id in
			token = id
			await prerequisites.wait()
			try session.activateCapture(id) { taps += 1 }
		})!
		await prerequisites.waitForArrival()
		session.requestStop()
		expect(!session.acceptsCallbacks(token!), "Stop must silence already queued UI callbacks")
		let stop = Task { try await session.stop() }
		busy(session)
		prerequisites.release()
		await teardown.waitForArrival()
		expect(taps == 0, "Production activation seam installed a late tap")
		busy(session)
		teardown.release()
		let value = try! await stop.value
		expect(value.isEmpty, "Pre-capture finish must not synthesize words")
		_ = await startup.result
	}

	@MainActor private static func finishDuringAnalyzerPreparation() async {
		let session = AudioSession(), prepare = Gate(), teardown = Gate()
		let channel = AudioInputChannel<Int>()
		var token: UUID?, taps = 0, capturing = false, preparationReturned = false
		var accepted = [Int]()
		let startup = session.start(freeze: { _ in
			// As in Dictation.stopCapture: finish the producer before stopping the device.
			channel.finish(); capturing = false
		}, dispose: { _ in
			await teardown.wait()
			for await frame in channel.stream { accepted.append(frame) }
			return accepted.map(String.init).joined(separator: " ")
		}, configure: { id in
			token = id
			// Use the production activation seam before a deferred analyzer prepare/start.
			try session.activateCapture(id) {
				taps += 1; capturing = true; _ = channel.push(10)
			}
			await prepare.wait()
			preparationReturned = true
			// Normal finish must permit preparation to complete and drain the frozen input.
			try session.check(id)
		})!
		await prepare.waitForArrival()
		expect(capturing && taps == 1, "Opening audio was not captured while preparation was pending")
		_ = channel.push(20) // Last accepted frame while the analyzer is still loading.
		session.requestStop()
		expect(!capturing, "User stop did not synchronously stop capture during preparation")
		expect(!preparationReturned, "Stop waited for analyzer preparation before freezing capture")
		expect(!session.acceptsCallbacks(token!), "Stopped preparing session still accepts callbacks")
		_ = channel.push(30) // A queued tap must not extend the utterance.
		let stop = Task { try await session.stop() }
		busy(session)
		prepare.release()
		await teardown.waitForArrival()
		expect(preparationReturned && taps == 1 && !capturing, "Preparation completion restarted capture")
		_ = channel.push(40)
		busy(session)
		teardown.release()
		let text = try! await stop.value
		try! await startup.value
		expect(accepted == [10, 20], "Stop lost the last accepted frames or admitted post-stop frames")
		expect(text == "10 20", "Finalization did not preserve the complete accepted prefix")
	}

	@MainActor private static func startupFailureSurvivesFinish() async {
		let session = AudioSession(), prepare = Gate(), teardown = Gate(), stopEntered = Gate()
		let startup = session.start(freeze: { _ in stopEntered.release() }, dispose: { _ in
			await teardown.wait(); throw TestFailure.cleanup
		}, configure: { _ in await prepare.wait(); throw TestFailure.prepare })!
		await prepare.waitForArrival()
		let stop = Task { try await session.stop() }
		// Wait for stop to retain the session, without relying on scheduler ordering or sleeps.
		await stopEntered.wait()
		prepare.release()
		await teardown.waitForArrival()
		busy(session)
		teardown.release()
		expectError(await startup.result, .prepare, "Startup error was erased by cleanup")
		expectError(await stop.result, .prepare, "Finish did not receive original startup error")
	}

	@MainActor private static func cancelBeforeStartup() async {
		let session = AudioSession(), teardown = Gate()
		var configured = false, frozenCancel = false
		let startup = session.start(freeze: { cancel in frozenCancel = frozenCancel || cancel }, dispose: { cancel in
			expect(cancel, "Cancellation must dispose analyzer as cancelled")
			await teardown.wait(); return ""
		}, configure: { _ in configured = true })!
		session.requestCancel()
		expect(frozenCancel, "Cancel must freeze synchronously before its task is scheduled")
		let cancel = Task { await session.cancel() }
		await teardown.waitForArrival()
		expect(!configured, "Cancel before first startup turn still ran configure")
		busy(session)
		teardown.release()
		await cancel.value
		expectCancelled(await startup.result)
	}

	@MainActor private static func cancelDuringPreparation() async {
		let session = AudioSession(), prepare = Gate(), teardown = Gate()
		var taps = 0, token: UUID?
		let startup = session.start(freeze: { _ in }, dispose: { _ in await teardown.wait(); return "" }, configure: { id in
			token = id; await prepare.wait()
			try session.activateCapture(id) { taps += 1 }
		})!
		await prepare.waitForArrival()
		session.requestCancel()
		let cancel = Task { await session.cancel() }
		expect(!session.acceptsCallbacks(token!), "Cancelled startup still accepts callbacks")
		busy(session)
		prepare.release()
		await teardown.waitForArrival()
		expect(taps == 0, "Cancelled deferred startup installed a tap")
		busy(session)
		teardown.release()
		await cancel.value
		expectCancelled(await startup.result)
	}

	@MainActor private static func normalFinishAndStaleCallbacks() async {
		let session = AudioSession(), teardown = Gate()
		let channel = AudioInputChannel<Int>()
		var oldToken: UUID?, taps = 0
		let startup = session.start(freeze: { _ in channel.finish() }, dispose: { _ in
			await teardown.wait()
			var values = [Int](); for await value in channel.stream { values.append(value) }
			expect(values == [1, 2], "Normal finish lost accepted audio or appended late audio")
			return "last volatile words"
		}, configure: { id in
			oldToken = id
			try session.activateCapture(id) { taps += 1; _ = channel.push(1); _ = channel.push(2) }
		})!
		try! await startup.value
		expect(taps == 1 && session.acceptsCallbacks(oldToken!), "Normal session did not activate")
		session.requestStop()
		_ = channel.push(3)
		let stop = Task { try await session.stop() }
		await teardown.waitForArrival()
		busy(session)
		teardown.release()
		let text = try! await stop.value
		expect(text == "last volatile words", "Normal result behavior changed")
		var newToken: UUID?
		let next = session.start(freeze: { _ in }, dispose: { _ in "new session" }, configure: { id in
			newToken = id; try session.activateCapture(id) { taps += 1 }
		})!
		try! await next.value
		session.fail(oldToken!, error: TestFailure.interrupted)
		expect(!session.owns(oldToken!) && !session.acceptsCallbacks(oldToken!), "Old callbacks retained ownership")
		expect(session.acceptsCallbacks(newToken!) && taps == 2, "Stale failure stopped the next session")
		let nextText = try! await session.stop()
		expect(nextText == "new session", "Stale failure leaked into next transcript")
	}

	@MainActor private static func interruptionWhileRecording() async {
		let session = AudioSession(), seen = Gate()
		let channel = AudioInputChannel<Int>(), center = NotificationCenter(), engine = NSObject()
		let name = Notification.Name("AudioRegression.activeEngine")
		var token: UUID?, capturing = false
		let startup = session.start(freeze: { _ in capturing = false; channel.finish() }, dispose: { _ in "truncated prefix" }, configure: { id in
			token = id; try session.activateCapture(id) { capturing = true }
		})!
		try! await startup.value
		let currentToken = token!
		let observer = AudioConfigurationObserver(center: center, name: name, object: engine, channel: channel) {
			Task { @MainActor in
				session.fail(currentToken, error: TestFailure.interrupted)
				seen.release()
			}
		}
		expect(capturing, "Test never reached active capture")
		center.post(name: name, object: engine)
		expect(channel.failure == .configurationChanged, "Failure must persist before UI dispatch")
		await seen.wait()
		expect(!capturing && !session.acceptsCallbacks(currentToken), "Interruption did not freeze capture and callbacks")
		let stop = Task { try await session.stop() }
		expectError(await stop.result, .interrupted, "Recording interruption returned prefix as success")
		observer.invalidate()
	}

	@MainActor private static func interruptionWhileFinishing() async {
		let session = AudioSession(), finalize = Gate()
		var token: UUID?
		let startup = session.start(freeze: { _ in }, dispose: { _ in await finalize.wait(); return "truncated prefix" }, configure: { token = $0 })!
		try! await startup.value
		let stop = Task { try await session.stop() }
		await finalize.waitForArrival()
		session.fail(token!, error: TestFailure.interrupted)
		busy(session)
		finalize.release()
		expectError(await stop.result, .interrupted, "Interruption during finish returned a truncated prefix")
	}

	@MainActor private static func cancelWhileFinishing() async {
		let session = AudioSession(), finalize = Gate()
		let startup = session.start(freeze: { _ in }, dispose: { _ in await finalize.wait(); return "must not deliver" }, configure: { _ in })!
		try! await startup.value
		let stop = Task { try await session.stop() }
		await finalize.waitForArrival()
		session.requestCancel()
		let cancel = Task { await session.cancel() }
		busy(session)
		finalize.release()
		await cancel.value
		expectCancelled(await stop.result)
	}

	@MainActor private static func channelFailures() async {
		let channel = AudioInputChannel<Int>(capacity: 1)
		expect(channel.push(1) == nil, "First buffer rejected")
		expect(channel.push(2) == .overflow, "Bounded stream did not fail closed")
		expect(channel.fail(.configurationChanged) == nil, "First failure must win")
		expect(channel.seal() == .overflow, "Overflow not persistent through completion")
		let stopped = AudioInputChannel<Int>()
		stopped.finish()
		expect(stopped.fail(.conversion) == nil, "Late conversion callback invalidated a normal stop")
		expect(stopped.push(3) == nil, "Late buffer should be ignored")
		expect(stopped.seal() == nil, "Normal finished input acquired a spurious error")
		let conversion = AudioInputChannel<Int>()
		expect(conversion.fail(.conversion) == .conversion, "Conversion did not persist")
		expect(conversion.seal() == .conversion, "Conversion vanished at completion")
	}

	@MainActor private static func configurationObservation() async {
		let center = NotificationCenter(), engine = NSObject(), otherEngine = NSObject()
		let name = Notification.Name("AudioRegression.engineConfiguration")
		let channel = AudioInputChannel<Int>()
		let observer = AudioConfigurationObserver(name: name, object: engine, channel: channel, onFailure: {})
		// A separate center cannot affect the default-center observer.
		center.post(name: name, object: engine)
		expect(channel.failure == nil, "Unrelated center invalidated a session")
		NotificationCenter.default.post(name: name, object: otherEngine)
		expect(channel.failure == nil, "Another engine invalidated a session")
		channel.finish() // Finish input, but results have not completed yet.
		NotificationCenter.default.post(name: name, object: engine)
		expect(channel.failure == .configurationChanged, "Configuration change during finish was lost")
		expect(channel.seal() == .configurationChanged, "Finishing interruption became success")
		observer.invalidate()
		let next = AudioInputChannel<Int>()
		let nextObserver = AudioConfigurationObserver(center: center, name: name, object: engine, channel: next, onFailure: {})
		expect(next.seal() == nil, "Clean final recognition failed")
		center.post(name: name, object: engine)
		expect(next.failure == nil, "Notification after sealed completion changed the result")
		nextObserver.invalidate()
		let disposed = AudioInputChannel<Int>()
		let removed = AudioConfigurationObserver(center: center, name: name, object: engine, channel: disposed, onFailure: {})
		removed.invalidate()
		center.post(name: name, object: engine)
		expect(disposed.failure == nil, "Removed session observer still received events")
	}
}
