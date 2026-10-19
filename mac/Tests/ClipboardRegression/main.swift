import Foundation

/// Production coordinator tests with fake dependencies only.
@main
struct ClipboardRegressionTests {
    @MainActor
    static func main() {
        var passed = 0
        func test(_ name: String, _ body: () -> Void) {
            body()
            passed += 1
            print("PASS: \(name)")
        }
        let original: ClipboardSnapshot = [
            ["public.utf8-plain-text": Data("O".utf8), "private.opaque-type": Data([0, 255, 1, 0]), "public.rtf": Data([123, 92, 125])],
            ["public.file-url": Data("file:///example".utf8), "private.empty-type": Data()],
        ]
        func setup(_ items: ClipboardSnapshot? = nil) -> (FakeClipboardBoard, FakeClipboardScheduler, ClipboardTransaction) {
            let board = FakeClipboardBoard(items ?? original)
            let clock = FakeClipboardScheduler()
            return (board, clock, ClipboardTransaction(board: board, schedule: clock.schedule))
        }

        test("full opaque multi-item snapshot survives a single delivery") {
            let (board, clock, transaction) = setup()
            precondition(transaction.write("A", restoreAfter: 0.6) == .restoreScheduled)
            precondition(board.text == "A" && clock.delays == [0.6])
            clock.run(0)
            precondition(board.items == original && board.restores == 1)
        }
        test("O -> A -> B restores O; stale A completion cannot erase B") {
            let (board, clock, transaction) = setup()
            transaction.write("A", restoreAfter: 0.6)
            transaction.write("B", restoreAfter: 0.6)
            clock.run(0)
            precondition(board.text == "B" && board.restores == 0)
            clock.run(1)
            precondition(board.items == original && board.restores == 1 && board.snapshots == 1)
        }
        test("out-of-order and duplicate callbacks restore only the current generation once") {
            let (board, clock, transaction) = setup()
            transaction.write("A", restoreAfter: 0.6)
            transaction.write("B", restoreAfter: 0.6)
            clock.run(1)
            clock.run(0)
            clock.run(1)
            precondition(board.items == original && board.restores == 1)
        }
        test("three overlapping deliveries retain the first snapshot") {
            let (board, clock, transaction) = setup()
            for text in ["A", "B", "C"] { transaction.write(text, restoreAfter: 0.6) }
            clock.run(1)
            clock.run(0)
            precondition(board.text == "C")
            clock.run(2)
            precondition(board.items == original && board.snapshots == 1)
        }
        test("external copy after paste revokes restore ownership") {
            let (board, clock, transaction) = setup()
            transaction.write("A", restoreAfter: 0.6)
            board.copy("external")
            clock.run(0)
            precondition(board.text == "external" && board.restores == 0)
        }
        test("external copy between deliveries becomes the new original") {
            let (board, clock, transaction) = setup()
            transaction.write("A", restoreAfter: 0.6)
            board.copy("external")
            transaction.write("B", restoreAfter: 0.6)
            clock.run(0)
            precondition(board.text == "B")
            clock.run(1)
            precondition(board.text == "external" && board.restores == 1)
        }
        test("external copy after overlapping deliveries survives every stale callback") {
            let (board, clock, transaction) = setup()
            transaction.write("A", restoreAfter: 0.6)
            transaction.write("B", restoreAfter: 0.6)
            board.copy("external")
            clock.run(1)
            clock.run(0)
            clock.run(1)
            precondition(board.text == "external" && board.restores == 0)
        }
        test("same-byte external copy still revokes ownership") {
            let (board, clock, transaction) = setup()
            transaction.write("A", restoreAfter: 0.6)
            board.copy("A")
            clock.run(0)
            precondition(board.text == "A" && board.restores == 0)
        }
        // These Paster outcomes all take the same production copy-only transaction path.
        for outcome in ["copied", "pastedAndCopied", "destinationChanged", "needsPermission"] {
            test("\(outcome) delivery cannot be erased by an older paste restore") {
                let (board, clock, transaction) = setup()
                transaction.write("A", restoreAfter: 0.6)
                precondition(transaction.write("B") == .copied)
                clock.run(0)
                precondition(board.text == "B" && board.restores == 0 && clock.jobs.count == 1)
            }
        }
        test("a later paste restores deliberately copied B, not the abandoned O chain") {
            let (board, clock, transaction) = setup()
            transaction.write("A", restoreAfter: 0.6)
            transaction.write("B")
            transaction.write("C", restoreAfter: 0.6)
            clock.run(0)
            precondition(board.text == "C")
            clock.run(1)
            precondition(board.text == "B")
        }
        test("an empty clipboard is restored as empty") {
            let (board, clock, transaction) = setup([])
            transaction.write("A", restoreAfter: 0.6)
            clock.run(0)
            precondition(board.items.isEmpty && board.restores == 1)
        }
        test("an incomplete snapshot leaves the delivered text copied, never partially restores") {
            let (board, clock, transaction) = setup()
            board.snapshotAvailable = false
            precondition(transaction.write("A", restoreAfter: 0.6) == .copied)
            precondition(board.text == "A" && clock.jobs.isEmpty)
        }
        test("provider mutation during snapshot prevents restoring a stale snapshot") {
            let (board, clock, transaction) = setup()
            board.mutateDuringSnapshot = true
            precondition(transaction.write("A", restoreAfter: 0.6) == .copied)
            precondition(board.text == "A" && clock.jobs.isEmpty)
        }
        test("failed later write still invalidates earlier completion") {
            let (board, clock, transaction) = setup()
            transaction.write("A", restoreAfter: 0.6)
            board.writeSucceeds = false
            precondition(transaction.write("B", restoreAfter: 0.6) == .failed)
            clock.run(0)
            precondition(board.items.isEmpty && board.restores == 0 && clock.jobs.count == 1)
        }
        test("completed chain does not leak its original into a fresh delivery") {
            let (board, clock, transaction) = setup()
            transaction.write("A", restoreAfter: 0.6)
            clock.run(0)
            board.copy("new original")
            transaction.write("B", restoreAfter: 0.6)
            clock.run(0)
            precondition(board.text == "B")
            clock.run(1)
            precondition(board.text == "new original")
        }
        test("deallocated coordinator makes delayed callbacks harmless") {
            let board = FakeClipboardBoard(original)
            let clock = FakeClipboardScheduler()
            var transaction: ClipboardTransaction? = ClipboardTransaction(board: board, schedule: clock.schedule)
            weak var released: ClipboardTransaction?
            released = transaction
            transaction!.write("A", restoreAfter: 0.6)
            transaction = nil
            precondition(released == nil)
            clock.run(0)
            precondition(board.text == "A" && board.restores == 0)
        }
        test("a late reader can see B instead of A: ownership is not a paste ACK") {
            let (board, clock, transaction) = setup()
            transaction.write("A", restoreAfter: 0.6)
            transaction.write("B", restoreAfter: 0.6)
            precondition(board.text == "B", "The coordinator does not promise clipboard-read isolation")
            clock.run(1)
            precondition(board.items == original)
        }
        print("Clipboard regressions: \(passed) passed; fake board and deterministic scheduler only")
    }
}
