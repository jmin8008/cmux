import Foundation
import Testing
@testable import CmuxBrowser

struct BrowserContextBoundaryTests {
    private func capture(revision: UUID) throws -> BrowserContextCapture {
        let value: [String: Any] = [
            "id": UUID().uuidString, "revision": revision.uuidString, "url": "http://localhost:3000/",
            "kind": "element", "text": "Save", "tag": "button", "selector": "#save",
            "bounds": ["x": 1.5, "y": -20.25, "width": 80, "height": 24],
            "viewport": ["width": 1000, "height": 800, "scroll_x": 0.5, "scroll_y": 300.75],
        ]
        return try JSONDecoder().decode(BrowserContextCapture.self, from: JSONSerialization.data(withJSONObject: value))
    }

    private func agent(_ title: String, input: TimeInterval?) -> BrowserContextTarget {
        BrowserContextTarget(id: UUID(), title: title, isAgent: true, lastInput: input.map { Date(timeIntervalSince1970: $0) })
    }

    @Test func gateFailsClosedWhenTargetDisappearsInFlightEvenIfItReturns() throws {
        let target = UUID(), revision = UUID()
        var gate = BrowserContextDeliveryGate()
        gate.arm(targetID: target, revision: revision)
        #expect(gate.claim(try capture(revision: revision), availableTargetIDs: []) == nil)
        // A terminal that was closed or moved and later reappears must not receive the older capture stream.
        #expect(gate.claim(try capture(revision: revision), availableTargetIDs: [target]) == nil)
        #expect(gate.targetID == nil)
    }

    @Test func gateIgnoresStaleRevisionWithoutDisarmingTheCurrentOne() throws {
        let target = UUID(), revision = UUID()
        var gate = BrowserContextDeliveryGate()
        gate.arm(targetID: target, revision: revision)
        #expect(gate.claim(try capture(revision: UUID()), availableTargetIDs: []) == nil)
        #expect(gate.claim(try capture(revision: revision), availableTargetIDs: [target]) == target)
    }

    @Test func gateRearmedForNewTargetRejectsCapturesPinnedToThePreviousTarget() throws {
        let first = UUID(), second = UUID(), oldRevision = UUID(), newRevision = UUID()
        var gate = BrowserContextDeliveryGate()
        gate.arm(targetID: first, revision: oldRevision)
        gate.arm(targetID: second, revision: newRevision)
        #expect(gate.claim(try capture(revision: oldRevision), availableTargetIDs: [first, second]) == nil)
        #expect(gate.claim(try capture(revision: newRevision), availableTargetIDs: [first, second]) == second)
    }

    @Test func automaticTargetIsReresolvedEachTimeButManualChoiceSticksWhileAvailable() {
        let first = agent("First", input: 50), second = agent("Second", input: nil)
        var selection = BrowserContextTargetSelection()
        #expect(selection.resolve([first, second]) == first)
        let newer = BrowserContextTarget(id: second.id, title: "Second", isAgent: true, lastInput: Date(timeIntervalSince1970: 100))
        #expect(selection.resolve([first, newer]) == newer)
        selection.choose(first.id)
        #expect(selection.resolve([first, newer]) == first)
        #expect(selection.resolve([newer]) == newer)
        #expect(selection.manualID == nil)
        #expect(selection.resolve([first, newer]) == newer)
    }

    @Test func ambiguousAgentsRequireManualChoiceAndNonAgentsCannotBeChosen() {
        let a = agent("A", input: 70), b = agent("B", input: 70)
        let shell = BrowserContextTarget(id: UUID(), title: "Dev server", isAgent: false, lastInput: Date(timeIntervalSince1970: 90))
        var selection = BrowserContextTargetSelection()
        #expect(selection.resolve([a, b, shell]) == nil)
        selection.choose(shell.id)
        #expect(selection.resolve([a, b, shell]) == nil)
        selection.choose(b.id)
        #expect(selection.resolve([a, b, shell]) == b)
    }

    @Test func fractionalAndNegativeScrollAndBoundsDecodeAndFormatWithoutRounding() throws {
        let result = try #require(BrowserContextFormatter().format(capture(revision: UUID())))
        #expect(result.contains("-20.25"))
        #expect(result.contains("300.75"))
        #expect(result.contains("1.5"))
    }
}
