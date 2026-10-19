import Foundation

@MainActor
private final class Gate {
    private var released = false
    private var reached = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var observers: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        reached = true
        observers.forEach { $0.resume() }; observers = []
        if released { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func arrival() async {
        if reached { return }
        await withCheckedContinuation { observers.append($0) }
    }
    func release() {
        released = true
        waiters.forEach { $0.resume() }; waiters = []
    }
}

@main
struct CoordinatorRegression {
    @MainActor static func main() async throws {
        // Old finish resumes after cancellation cleanup and a new reservation: no stop effect.
        let coordinator = RecordingCoordinator()
        let startupGate = Gate()
        let startup = Task<Void, Error> { await startupGate.wait() }
        let first = coordinator.begin()!
        var stopCalls = 0
        var cancelCalls = 0
        let finish = Task { @MainActor in
            try await coordinator.finish(first, startup: startup,
                stop: { stopCalls += 1; return "must not deliver" },
                cancel: { cancelCalls += 1 })
        }
        await startupGate.arrival()
        precondition(coordinator.requestCancel(first))
        precondition(coordinator.complete(first))
        let second = coordinator.begin()!
        startupGate.release()
        let staleText = try await finish.value
        precondition(staleText == nil && stopCalls == 0 && cancelCalls == 0)
        precondition(coordinator.id == second && coordinator.mayDeliver(second))
        await coordinator.cancel(first, cleanup: { cancelCalls += 1 })
        precondition(cancelCalls == 0, "Stale cancellation must not touch new audio")
        print("PASS stale finish and cancellation cannot affect a new session")

        // Cancelled current startup goes through cleanup instead of stop/delivery.
        precondition(coordinator.requestCancel(second))
        let cancelledText = try await coordinator.finish(second, startup: nil,
            stop: { stopCalls += 1; return "must not deliver" }, cancel: { cancelCalls += 1 })
        precondition(cancelledText == nil && stopCalls == 0 && cancelCalls == 1)
        coordinator.complete(second)
        print("PASS current cancellation cleans up without stopping or delivering")

        // Stop has already entered its await: cancellation must suppress the returned words.
        let third = coordinator.begin()!
        let finalization = Gate()
        let pendingFinish = Task { @MainActor in
            try await coordinator.finish(third, startup: nil,
                stop: { stopCalls += 1; await finalization.wait(); return "cancelled words" },
                cancel: { cancelCalls += 1 })
        }
        await finalization.arrival()
        precondition(coordinator.requestCancel(third))
        finalization.release()
        let suppressed = try await pendingFinish.value
        precondition(suppressed == nil && stopCalls == 1)
        coordinator.complete(third)
        print("PASS cancellation during finalization suppresses delivery")

        let fourth = coordinator.begin()!
        let text = try await coordinator.finish(fourth, startup: nil,
            stop: { "complete last words" }, cancel: { preconditionFailure("Unexpected cancel") })
        precondition(text == "complete last words")
        coordinator.complete(fourth)
        print("PASS uncancelled finalization returns complete text")
        print("Coordinator regressions: 4 groups passed; actual async coordinator with fake backend effects")
    }
}
