import AppKit

/// The production adapter. Tests inject an in-memory board instead of accessing any pasteboard.
@MainActor
final class AppKitClipboardBoard: ClipboardTransactionBoard {
    private let board: NSPasteboard

    init(_ board: NSPasteboard) { self.board = board }

    var changeCount: Int { board.changeCount }

    func snapshot() -> ClipboardSnapshot? {
        guard let source = board.pasteboardItems else {
            // An advertised representation with no readable items is not an empty snapshot.
            return board.types?.isEmpty == false ? nil : []
        }
        var items: ClipboardSnapshot = []
        for item in source {
            var representations: [String: Data] = [:]
            for type in item.types {
                guard let data = item.data(forType: type) else { return nil }
                representations[type.rawValue] = data
            }
            items.append(representations)
        }
        return items
    }

    @discardableResult
    func writeText(_ text: String) -> Bool {
        // Clearing and setting are not atomic. A failed set can leave the original lost;
        // report failure without claiming copied text or triggering a paste/unsafe rollback.
        board.clearContents()
        return board.setString(text, forType: .string)
    }

    func restore(_ snapshot: ClipboardSnapshot) {
        let items = snapshot.map { entry in
            let item = NSPasteboardItem()
            for (type, data) in entry { item.setData(data, forType: NSPasteboard.PasteboardType(type)) }
            return item
        }
        board.clearContents()
        if !items.isEmpty { board.writeObjects(items) }
    }
}
