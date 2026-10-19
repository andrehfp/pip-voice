import Foundation

/// The production async boundary, shared by the app and effect-free regression tests.
/// The audio backend must keep its own reservation through cleanup (AudioSession does).
@MainActor
final class RecordingCoordinator {
    private var ownership = RecordingOwnership()
    var id: UUID? { ownership.id }
    func begin() -> UUID? { ownership.begin() }
    func mayDeliver(_ token: UUID) -> Bool { ownership.mayDeliver(token) }
    func requestCancel(_ token: UUID) -> Bool { ownership.requestCancel(token) }
    @discardableResult func complete(_ token: UUID) -> Bool { ownership.complete(token) }

    func finish(
        _ token: UUID,
        startup: Task<Void, Error>?,
        stop: () async throws -> String,
        cancel: () async -> Void
    ) async throws -> String? {
        try await startup?.value
        // Check before the backend effect, not only before delivering its answer.
        guard id == token else { return nil }
        guard mayDeliver(token) else { await cancel(); return nil }
        let text = try await stop()
        return mayDeliver(token) ? text : nil
    }

    func cancel(_ token: UUID, cleanup: () async -> Void) async {
        // A cancellation task may first run after another path has already completed its session.
        guard id == token else { return }
        await cleanup()
    }
}
