public import Foundation

/// Keeps an explicit user destination separate from automatic agent resolution.
///
/// An automatically chosen agent is never remembered: each activation resolves
/// again from current input recency. Only a destination the user picked sticks,
/// and only while it remains a current agent candidate.
public struct BrowserContextTargetSelection: Sendable {
    /// The destination explicitly chosen by the user, if still current.
    public private(set) var manualID: UUID?

    /// Creates a selection with no manual destination.
    public init() {}

    /// Pins a user-chosen destination until it stops being a candidate.
    /// - Parameter id: The actual terminal surface ID.
    public mutating func choose(_ id: UUID) {
        manualID = id
    }

    /// Resolves the destination for a new activation.
    /// - Parameter candidates: Current same-workspace terminal snapshots.
    /// - Returns: The manual agent choice, else the unambiguous automatic agent; nil if neither.
    public mutating func resolve(_ candidates: [BrowserContextTarget]) -> BrowserContextTarget? {
        let agents = candidates.filter(\.isAgent)
        if let manualID {
            if let chosen = agents.first(where: { $0.id == manualID }) { return chosen }
            self.manualID = nil
        }
        return BrowserContextTargetResolver().resolve(agents)
    }
}
