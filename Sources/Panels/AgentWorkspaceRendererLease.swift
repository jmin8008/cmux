import Foundation
import Bonsplit

/// Presentation ownership only. The terminal remains in its original workspace
/// and Bonsplit tab; its existing surface is lent to exactly one group host.
@MainActor
final class AgentWorkspaceRendererLease {
    let id = UUID()
    let sessionID: String
    let provider: String
    let surfaceGeneration: UInt64
    let rootSurfaceGeneration: UInt64
    weak var presentation: AgentWorkspacePresentation?
    private(set) weak var workspace: Workspace?
    private(set) weak var root: TerminalPanel?
    private(set) weak var panel: TerminalPanel?
    private var revoked = false

    init(workspace: Workspace, root: TerminalPanel, panel: TerminalPanel,
         presentation: AgentWorkspacePresentation, sessionID: String, provider: String) {
        self.workspace = workspace
        self.root = root
        self.panel = panel
        self.presentation = presentation
        self.sessionID = sessionID
        self.provider = provider
        self.surfaceGeneration = panel.surface.portalBindingGeneration()
        self.rootSurfaceGeneration = root.surface.portalBindingGeneration()
    }

    var isCurrent: Bool {
        guard !revoked, let workspace, let root, let panel, let presentation,
              workspace.panels[root.id] === root, workspace.panels[panel.id] === panel,
              root.workspaceId == workspace.id, panel.workspaceId == workspace.id,
              root.agentWorkspace === presentation,
              presentation.rendererLease === self, panel.agentWorkspaceRendererLease === self,
              case .live = root.agentHibernationPhase,
              case .live = panel.agentHibernationPhase else { return false }
        return root.surface.canAcceptPortalBinding(
            expectedSurfaceId: root.id, expectedGeneration: rootSurfaceGeneration
        ) && panel.surface.canAcceptPortalBinding(
            expectedSurfaceId: panel.id, expectedGeneration: surfaceGeneration
        )
    }

    /// Read again by queued portal work: captured SwiftUI values cannot grant
    /// an old group host authority after selection, move, close or hibernation.
    func ownsPortal(in pane: PaneID) -> Bool {
        guard isCurrent, let workspace, let root,
              workspace.isPortalRenderingEnabled,
              workspace.paneId(forPanelId: root.id) == pane,
              workspace.bonsplitController.zoomedPaneId.map({ $0 == pane }) ?? true,
              let tab = workspace.surfaceIdFromPanelId(root.id) else { return false }
        return workspace.bonsplitController.selectedTabId(inPane: pane) == tab
    }

    func revoke() {
        guard !revoked else { return }
        revoked = true // Withdraw old host authority before touching the shared view.
        guard let panel, panel.agentWorkspaceRendererLease === self else { return }
        panel.unfocus()
        panel.hostedView.setVisibleInUI(false)
        TerminalWindowPortalRegistry.hideHostedView(panel.hostedView)
        panel.recordPortalHostOwnershipChange()
        panel.agentWorkspaceRendererLease = nil
        workspace?.scheduleTerminalGeometryReconcile()
    }
}

extension TerminalPanel {
    func agentWorkspacePresentationDidChange(previous: AgentWorkspacePresentation?) {
        guard previous !== agentWorkspace else { return }
        previous?.releaseRenderer()
        if let group = agentWorkspace {
            if let lease = agentWorkspaceRendererLease, lease.presentation !== group {
                lease.presentation?.releaseRenderer()
            }
            unfocus()
            hostedView.setVisibleInUI(false)
            TerminalWindowPortalRegistry.hideHostedView(hostedView)
        }
        recordPortalHostOwnershipChange()
        surface.owningWorkspace()?.scheduleTerminalGeometryReconcile()
    }

    func requestViewReattach() {
        viewReattachToken &+= 1
    }

    /// Monotonic model ownership epoch across container transfers and local
    /// representable reattachments. This takes precedence over host creation
    /// order when a move rolls back to an earlier view.
    var portalHostOwnershipGeneration: UInt64 {
        surface.currentPortalHostOwnershipGeneration() &+ viewReattachToken
    }

    func recordPortalHostOwnershipChange() {
        requestViewReattach()
    }

    var allowsCanonicalAgentWorkspaceRenderer: Bool {
        agentWorkspaceRendererLease?.isCurrent != true
    }

    /// Central lifetime boundary, also used before a panel leaves its workspace.
    func revokeAgentWorkspaceRenderer() {
        agentWorkspace?.releaseRenderer()
        agentWorkspaceRendererLease?.presentation?.releaseRenderer()
        agentWorkspaceRendererLease?.revoke()
    }
}

extension Workspace {
    /// Main UI input has a presentation target; explicit CLI/control IDs retain
    /// their original identities in terminalInputTarget(forPanelID:).
    func agentWorkspaceInputTarget(forRootPanelID panelID: UUID) -> TerminalPanel? {
        (panels[panelID] as? TerminalPanel)?.agentWorkspace?.selectedTerminalPanel
    }

    func agentWorkspaceFocusContainer(forSurfaceID surfaceID: UUID) -> UUID {
        guard let terminal = panels[surfaceID] as? TerminalPanel,
              let lease = terminal.agentWorkspaceRendererLease, lease.isCurrent,
              let root = lease.root else { return surfaceID }
        return root.id
    }

    /// Project visible layout containers to real native renderers. Group web
    /// content has no terminal portal until the user chooses an original terminal.
    func agentWorkspaceRenderedTerminalIDs(_ visiblePanelIDs: Set<UUID>) -> Set<UUID> {
        var result = visiblePanelIDs
        for case let terminal as TerminalPanel in panels.values {
            if terminal.agentWorkspace != nil || !terminal.allowsCanonicalAgentWorkspaceRenderer {
                result.remove(terminal.id)
            }
        }
        for panelID in visiblePanelIDs {
            if let selected = agentWorkspaceInputTarget(forRootPanelID: panelID) {
                result.insert(selected.id)
            }
        }
        return result
    }

    func releaseAgentWorkspaceRenderers() {
        for case let terminal as TerminalPanel in panels.values {
            terminal.agentWorkspace?.releaseRenderer()
        }
    }
}

extension Workspace {
    /// Converges the workspace pane selection when a mounted terminal accepts
    /// user input. Cloud manual-mirror surfaces can receive an input event
    /// while their portal focus callback is still being rebound; keeping this
    /// guard at the workspace boundary makes the active pane border and the
    /// keyboard target follow the same selected workspace.
    @discardableResult
    func focusPanelFromTerminalInput(_ panelId: UUID) -> Bool {
        let containerID = agentWorkspaceFocusContainer(forSurfaceID: panelId)
        guard panels[containerID] != nil,
              (owningTabManager ?? AppDelegate.shared?.tabManagerFor(tabId: id))?.selectedTabId == id,
              focusedPanelId != containerID else {
            return false
        }
        focusPanel(containerID, trigger: .terminalFirstResponder)
        return true
    }

}
