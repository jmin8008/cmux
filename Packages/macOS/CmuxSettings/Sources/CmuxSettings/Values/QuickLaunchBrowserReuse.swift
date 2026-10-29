import Foundation

public struct QuickLaunchBrowserCandidate: Sendable {
    public let panelID: UUID
    public let workspaceID: UUID
    public let profileID: UUID
    public let url: String?
    public init(panelID: UUID, workspaceID: UUID, profileID: UUID, url: String?) {
        self.panelID = panelID
        self.workspaceID = workspaceID
        self.profileID = profileID
        self.url = url
    }
}

public enum QuickLaunchBrowserReuse {
    /// Match the full address. A bound tab that navigated elsewhere loses its binding.
    public static func panelID(
        for url: String,
        workspaceID: UUID,
        profileID: UUID,
        boundPanelID: UUID?,
        focusedPanelID: UUID?,
        candidates: [QuickLaunchBrowserCandidate]
    ) -> UUID? {
        let matches = candidates.filter {
            $0.workspaceID == workspaceID && $0.profileID == profileID && $0.url == url
        }
        return matches.first(where: { $0.panelID == boundPanelID })?.panelID
            ?? matches.first(where: { $0.panelID == focusedPanelID })?.panelID
            ?? matches.sorted { $0.panelID.uuidString < $1.panelID.uuidString }.first?.panelID
    }
}
