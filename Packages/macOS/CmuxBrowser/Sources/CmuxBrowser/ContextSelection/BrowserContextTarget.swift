public import Foundation

/// An immutable, same-workspace terminal candidate derived from app-owned state.
public struct BrowserContextTarget: Identifiable, Equatable, Sendable {
    /// The actual terminal surface ID, never a dynamic container ID.
    public let id: UUID
    /// A title suitable for the destination picker.
    public let title: String
    /// Whether current agent ownership evidence exists for this terminal.
    public let isAgent: Bool
    /// The latest accepted input time; focus changes do not affect this value.
    public let lastInput: Date?

    /// Creates a destination snapshot.
    /// - Parameters:
    ///   - id: The exact terminal surface ID.
    ///   - title: The user-visible terminal title.
    ///   - isAgent: Whether current agent ownership evidence exists.
    ///   - lastInput: The latest accepted terminal input, if known.
    public init(id: UUID, title: String, isAgent: Bool, lastInput: Date?) {
        self.id = id
        self.title = title
        self.isAgent = isAgent
        self.lastInput = lastInput
    }
}
