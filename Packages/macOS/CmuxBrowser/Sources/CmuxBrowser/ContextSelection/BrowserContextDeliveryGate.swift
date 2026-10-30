public import Foundation

/// Pins one destination and rejects stale or duplicate browser capture messages.
public struct BrowserContextDeliveryGate: Sendable {
    /// The current browser interaction revision, absent while disabled.
    public private(set) var revision: UUID?
    /// The fixed destination of the active revision.
    public private(set) var targetID: UUID?
    private var consumed: Set<UUID> = []

    /// Creates a disabled delivery gate.
    public init() {}

    /// Starts a new selection revision and pins its target.
    /// - Parameters:
    ///   - targetID: The actual destination surface ID.
    ///   - revision: A fresh app-generated revision token.
    public mutating func arm(targetID: UUID, revision: UUID) {
        self.targetID = targetID
        self.revision = revision
        consumed.removeAll()
    }

    /// Cancels all pending captures after navigation, teardown, or disabling.
    public mutating func invalidate() {
        revision = nil
        targetID = nil
        consumed.removeAll()
    }

    /// Claims a capture before attempting its one permitted paste.
    /// - Parameters:
    ///   - capture: The document capture received from the isolated picker.
    ///   - availableTargetIDs: Live agent terminals in the original workspace.
    /// - Returns: The pinned target if the capture is current and not already attempted.
    public mutating func claim(_ capture: BrowserContextCapture, availableTargetIDs: Set<UUID>) -> UUID? {
        guard capture.revision == revision, let targetID else { return nil }
        // A target that closed or moved while a capture was in flight disarms the
        // revision. It must not receive later captures if it reappears.
        guard availableTargetIDs.contains(targetID) else {
            invalidate()
            return nil
        }
        guard consumed.insert(capture.id).inserted else { return nil }
        return targetID
    }
}
