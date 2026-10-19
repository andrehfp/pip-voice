import Foundation

/// Per-operation delivery and cancellation ownership. Late task completions cannot mutate the next operation.
struct RecordingOwnership {
    private(set) var id: UUID?
    private var cancelled = false
    private var cancellationStarted = false

    mutating func begin() -> UUID? {
        guard id == nil else { return nil }
        let token = UUID()
        id = token
        cancelled = false
        cancellationStarted = false
        return token
    }
    func mayDeliver(_ token: UUID) -> Bool { id == token && !cancelled }
    mutating func requestCancel(_ token: UUID) -> Bool {
        guard id == token, !cancellationStarted else { return false }
        cancelled = true
        cancellationStarted = true
        return true
    }
    @discardableResult
    mutating func complete(_ token: UUID) -> Bool {
        guard id == token else { return false }
        id = nil
        cancelled = false
        cancellationStarted = false
        return true
    }
}
