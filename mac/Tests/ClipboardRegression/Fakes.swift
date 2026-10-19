import Foundation

/// Shared in-memory fixtures. No AppKit, pasteboards, key events, preferences or disk I/O.
@MainActor
final class FakeClipboardBoard: ClipboardTransactionBoard {
    var changeCount = 0
    var items: ClipboardSnapshot
    var snapshotAvailable = true
    var mutateDuringSnapshot = false
    var writeSucceeds = true
    /// Simulates clear-then-set failure by default, or an unrelated retained value when requested.
    var failedWriteContents: ClipboardSnapshot = []
    var restores = 0
    var snapshots = 0

    init(_ items: ClipboardSnapshot) { self.items = items }

    func snapshot() -> ClipboardSnapshot? {
        snapshots += 1
        let result = items
        if mutateDuringSnapshot { copy("provider mutation") }
        return snapshotAvailable ? result : nil
    }

    func writeText(_ text: String) -> Bool {
        guard writeSucceeds else {
            changeCount += 1
            items = failedWriteContents
            return false
        }
        copy(text)
        return true
    }

    func restore(_ snapshot: ClipboardSnapshot) {
        restores += 1
        changeCount += 1
        items = snapshot
    }

    func copy(_ text: String) {
        changeCount += 1
        items = [["public.utf8-plain-text": Data(text.utf8)]]
    }

    var text: String? {
        items.first?["public.utf8-plain-text"].flatMap { String(data: $0, encoding: .utf8) }
    }
}

@MainActor
final class FakeClipboardScheduler {
    var jobs: [@MainActor @Sendable () -> Void] = []
    var delays: [TimeInterval] = []
    func schedule(_ delay: TimeInterval, _ job: @escaping @MainActor @Sendable () -> Void) {
        delays.append(delay)
        jobs.append(job)
    }
    // Intentionally allow callbacks out of order and more than once.
    func run(_ index: Int) { jobs[index]() }
}
