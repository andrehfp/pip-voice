import Foundation

/// Executes Paster's production route with fake effects, never its live environment.
@MainActor
private final class DeliveryHarness {
    let original: ClipboardSnapshot = [["public.utf8-plain-text": Data("O".utf8)]]
    let board: FakeClipboardBoard
    let scheduler = FakeClipboardScheduler()
    let clipboard: ClipboardTransaction
    var permitted = true
    var target: Paster.Target = .editable
    var targetReads = 0
    var postedContents: [ClipboardSnapshot] = []

    init() {
        board = FakeClipboardBoard(original)
        clipboard = ClipboardTransaction(board: board, schedule: scheduler.schedule)
    }

    var environment: Paster.DeliveryEnvironment {
        Paster.DeliveryEnvironment(clipboard: clipboard, hasPermission: { self.permitted }, focusedTarget: {
            self.targetReads += 1
            return self.target
        }, postPaste: { self.postedContents.append(self.board.items) })
    }

    func deliver(_ text: String) -> Paster.Delivery { Paster.deliver(text, using: environment) }

    func replace(_ text: String, sameOrigin: Bool) -> Paster.Delivery {
        Paster.deliverReplacement(text, originStillFocused: sameOrigin, using: environment)
    }
}

@main
struct PasterDeliveryRegressionTests {
    @MainActor
    static func main() {
        var passed = 0
        func test(_ name: String, _ body: () -> Void) {
            body()
            passed += 1
            print("PASS: \(name)")
        }

        for target in Paster.Target.allCases {
            for destructive in [false, true] {
                test("failed \(target) write (clear=\(destructive)) never posts a paste or reports copied") {
                    let harness = DeliveryHarness()
                    harness.target = target
                    harness.board.writeSucceeds = false
                    harness.board.failedWriteContents = destructive ? [] : harness.original
                    precondition(harness.deliver("A") == .failed)
                    precondition(harness.postedContents.isEmpty && harness.scheduler.jobs.isEmpty)
                    precondition(harness.board.items == (destructive ? [] : harness.original))
                    precondition(harness.board.restores == 0, "Failed writes must not trigger an unsafe rollback")
                }
            }
        }
        for target in Paster.Target.allCases {
            test("successful \(target) delivery posts only after writing and reports the correct policy") {
                let harness = DeliveryHarness()
                harness.target = target
                let expected: Paster.Delivery
                switch target {
                case .editable: expected = .pasted
                case .unknown: expected = .copied
                case .notEditable: expected = .copied
                }
                precondition(harness.deliver("A") == expected)
                precondition(harness.board.text == "A")
                let expectedPosts = target == .editable ? 1 : 0
                precondition(harness.postedContents.count == expectedPosts)
                for posted in harness.postedContents { precondition(posted == harness.board.items) }
                if target == .editable {
                    precondition(harness.scheduler.delays == [0.6])
                    harness.scheduler.run(0)
                    precondition(harness.board.items == harness.original)
                } else {
                    precondition(harness.scheduler.jobs.isEmpty)
                }
            }
        }
        test("unknown target never posts a paste and revokes earlier restoration") {
            let harness = DeliveryHarness()
            precondition(harness.deliver("A") == .pasted)
            harness.target = .unknown
            precondition(harness.deliver("B") == .copied)
            precondition(harness.postedContents.count == 1 && harness.board.text == "B")
            harness.scheduler.run(0)
            precondition(harness.board.text == "B" && harness.board.restores == 0)
        }
        test("successful write with unavailable snapshot still posts once and reports pastedAndCopied") {
            let harness = DeliveryHarness()
            harness.board.snapshotAvailable = false
            precondition(harness.deliver("A") == .pastedAndCopied)
            precondition(harness.postedContents.count == 1 && harness.board.text == "A")
            precondition(harness.scheduler.jobs.isEmpty)
        }
        for writeSucceeds in [false, true] {
            test("missing permission distinguishes failed/copy success (write=\(writeSucceeds)) without focus or key effects") {
                let harness = DeliveryHarness()
                harness.permitted = false
                harness.board.writeSucceeds = writeSucceeds
                precondition(harness.deliver("A") == (writeSucceeds ? .needsPermission : .failed))
                precondition(harness.targetReads == 0 && harness.postedContents.isEmpty && harness.scheduler.jobs.isEmpty)
                precondition(writeSucceeds ? harness.board.text == "A" : harness.board.items.isEmpty)
            }
        }
        for permitted in [false, true] {
            for writeSucceeds in [false, true] {
                test("changed replacement destination (permission=\(permitted), write=\(writeSucceeds)) never posts") {
                    let harness = DeliveryHarness()
                    harness.permitted = permitted
                    harness.board.writeSucceeds = writeSucceeds
                    let expected: Paster.Delivery = writeSucceeds ? (permitted ? .destinationChanged : .needsPermission) : .failed
                    precondition(harness.replace("A", sameOrigin: false) == expected)
                    precondition(harness.postedContents.isEmpty && harness.targetReads == 0 && harness.scheduler.jobs.isEmpty)
                }
            }
        }
        for target in Paster.Target.allCases {
            test("validated replacement with failed \(target) write never posts") {
                let harness = DeliveryHarness()
                harness.target = target
                harness.board.writeSucceeds = false
                precondition(harness.replace("A", sameOrigin: true) == .failed)
                precondition(harness.postedContents.isEmpty && harness.scheduler.jobs.isEmpty)
            }
        }
        for target in Paster.Target.allCases {
            test("failed \(target) delivery after A revokes A restore without another keypost") {
                let harness = DeliveryHarness()
                precondition(harness.deliver("A") == .pasted)
                precondition(harness.postedContents.count == 1)
                harness.target = target
                harness.board.writeSucceeds = false
                precondition(harness.deliver("B") == .failed)
                precondition(harness.postedContents.count == 1 && harness.board.items.isEmpty)
                harness.scheduler.run(0)
                precondition(harness.board.items.isEmpty && harness.board.restores == 0)
            }
        }
        for outcome in [Paster.Delivery.copied, .pastedAndCopied, .destinationChanged, .needsPermission] {
            test("production \(outcome) path revokes an earlier scheduled restore") {
                let harness = DeliveryHarness()
                precondition(harness.deliver("A") == .pasted)
                let result: Paster.Delivery
                switch outcome {
                case .copied:
                    harness.target = .notEditable
                    result = harness.deliver("B")
                case .pastedAndCopied:
                    harness.board.copy("external copy")
                    harness.board.snapshotAvailable = false
                    result = harness.deliver("B")
                case .destinationChanged:
                    result = harness.replace("B", sameOrigin: false)
                case .needsPermission:
                    harness.permitted = false
                    result = harness.deliver("B")
                default:
                    preconditionFailure("Unexpected copy-only outcome")
                }
                precondition(result == outcome && harness.board.text == "B")
                precondition(harness.postedContents.count == (outcome == .pastedAndCopied ? 2 : 1))
                harness.scheduler.run(0)
                precondition(harness.board.text == "B" && harness.board.restores == 0)
            }
        }
        for changedOrigin in [false, true] {
            test("failed copy-only route (changedOrigin=\(changedOrigin)) revokes an earlier restore and never posts") {
                let harness = DeliveryHarness()
                precondition(harness.deliver("A") == .pasted)
                harness.board.writeSucceeds = false
                harness.permitted = changedOrigin
                let result = changedOrigin ? harness.replace("B", sameOrigin: false) : harness.deliver("B")
                precondition(result == .failed && harness.postedContents.count == 1)
                harness.scheduler.run(0)
                precondition(harness.board.items.isEmpty && harness.board.restores == 0)
            }
        }
        print("Paster delivery regressions: \(passed) passed; production routing with fake board, scheduler and keypost only")
    }
}
