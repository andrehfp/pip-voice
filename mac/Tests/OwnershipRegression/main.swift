import Foundation

@MainActor
private final class Gate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    func wait() async {
        if released { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func release() { released = true; continuation?.resume(); continuation = nil }
}

@main
struct OwnershipRegression {
    @MainActor static func main() async {
        var ownership = RecordingOwnership()
        let first = ownership.begin()!
        precondition(ownership.begin() == nil)
        precondition(ownership.mayDeliver(first))
        precondition(ownership.requestCancel(first))
        precondition(!ownership.requestCancel(first))
        precondition(!ownership.mayDeliver(first))
        let oldCallback = Gate()
        // Simulate cancellation resuming after normal finalization has already completed cleanup.
        let lateCancellation = Task { @MainActor in
            await oldCallback.wait()
            precondition(!ownership.complete(first), "Old cancellation must not complete the next operation")
            precondition(!ownership.requestCancel(first), "Old callback must not cancel the next operation")
        }
        precondition(ownership.complete(first))
        let second = ownership.begin()!
        precondition(second != first)
        precondition(ownership.mayDeliver(second))
        precondition(ownership.requestCancel(second), "New cancellation must not be blocked by an old operation's flag")
        oldCallback.release()
        await lateCancellation.value
        precondition(ownership.id == second)
        precondition(!ownership.mayDeliver(second), "Old completion must not undo current cancellation")
        precondition(!ownership.mayDeliver(first))
        precondition(ownership.complete(second))
        precondition(!ownership.complete(second))
        let third = ownership.begin()!
        precondition(ownership.mayDeliver(third))
        precondition(!ownership.mayDeliver(second))
        precondition(ownership.complete(third))
        precondition(ownership.id == nil)
        print("Ownership regressions: 21 checks passed; deferred stale cancellation and delivery guards, no app effects")
    }
}
