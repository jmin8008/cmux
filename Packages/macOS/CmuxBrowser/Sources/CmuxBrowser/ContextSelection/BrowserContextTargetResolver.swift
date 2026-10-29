import Foundation

/// Chooses the most recently used agent without guessing from browser or shell focus.
public struct BrowserContextTargetResolver: Sendable {
    /// Creates a resolver.
    public init() {}

    /// Resolves an unambiguous agent destination.
    /// - Parameter candidates: Current workspace terminal snapshots.
    /// - Returns: The single agent or uniquely most recently used agent; nil if ambiguous.
    public func resolve(_ candidates: [BrowserContextTarget]) -> BrowserContextTarget? {
        let agents = candidates.filter(\.isAgent)
        if agents.count == 1 { return agents.first }
        let used = agents.filter { $0.lastInput != nil }.sorted { $0.lastInput! > $1.lastInput! }
        guard let latest = used.first else { return nil }
        guard used.count == 1 || latest.lastInput != used[1].lastInput else { return nil }
        return latest
    }
}
