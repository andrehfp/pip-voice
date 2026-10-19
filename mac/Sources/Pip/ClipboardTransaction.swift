import Foundation

/// Ordered pasteboard items, retaining every materialized representation as opaque bytes.
typealias ClipboardSnapshot = [[String: Data]]

@MainActor
protocol ClipboardTransactionBoard: AnyObject {
    var changeCount: Int { get }
    /// nil means a representation could not be materialized; never promise a partial restore.
    func snapshot() -> ClipboardSnapshot?
    @discardableResult func writeText(_ text: String) -> Bool
    func restore(_ snapshot: ClipboardSnapshot)
}

/// One ownership chain across overlapping deliveries, not one independent restore per paste.
/// This coordinates clipboard ownership only: neither a key post nor the grace period is a paste ACK.
@MainActor
final class ClipboardTransaction {
    typealias Schedule = (TimeInterval, @escaping @MainActor @Sendable () -> Void) -> Void

    enum WriteOutcome: Equatable {
        /// The requested text was not successfully written; clipboard contents are unspecified.
        case failed
        /// Text was written successfully, without a pending restore.
        case copied
        /// Text was written successfully, with a best-effort restore scheduled.
        case restoreScheduled
    }

    private struct Pending {
        let generation: UUID
        let original: ClipboardSnapshot
        let changeCount: Int
    }

    private let board: any ClipboardTransactionBoard
    private let schedule: Schedule
    private var pending: Pending?

    init(board: any ClipboardTransactionBoard, schedule: @escaping Schedule) {
        self.board = board
        self.schedule = schedule
    }

    /// Reports write success separately from restoration policy, never a paste acknowledgment.
    /// Every write, including copy-only delivery, revokes all older delayed completions.
    @discardableResult
    func write(_ text: String, restoreAfter delay: TimeInterval? = nil) -> WriteOutcome {
        let previous = pending
        pending = nil
        let original: ClipboardSnapshot?
        if delay == nil {
            original = nil
        } else if let previous, board.changeCount == previous.changeCount {
            // O -> A -> B still belongs to the same chain: B must restore O, never A.
            original = previous.original
        } else {
            let count = board.changeCount
            let snapshot = board.snapshot()
            // Materializing a lazy representation can itself change the board.
            original = board.changeCount == count ? snapshot : nil
        }
        guard board.writeText(text) else { return .failed }
        guard let delay, let original else { return .copied }
        let generation = UUID()
        pending = Pending(generation: generation, original: original, changeCount: board.changeCount)
        schedule(delay) { [weak self] in self?.complete(generation) }
        return .restoreScheduled
    }

    private func complete(_ generation: UUID) {
        guard let current = pending, current.generation == generation else { return }
        pending = nil
        // An external copy revokes ownership, even if its bytes happen to equal our text.
        guard board.changeCount == current.changeCount else { return }
        board.restore(current.original)
    }
}
