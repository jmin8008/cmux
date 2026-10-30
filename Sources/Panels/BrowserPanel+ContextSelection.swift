import CmuxBrowser
import Foundation

extension BrowserPanel {
    /// Composition seam: candidate snapshots contain actual terminal IDs, not focus-dependent containers.
    func contextSelectionTargets() -> [BrowserContextTarget] {
        guard let workspace = AppDelegate.shared?.tabManagerFor(tabId: workspaceId)?.tabs.first(where: { $0.id == workspaceId }) else { return [] }
        var seen: Set<UUID> = []
        return workspace.panels.keys.flatMap { containerID in
            workspace.terminalPanels(projectedFromPanelID: containerID).compactMap { terminal -> BrowserContextTarget? in
                guard seen.insert(terminal.id).inserted else { return nil }
                let hasPID = !(workspace.agentPIDKeysByPanelId[terminal.id] ?? []).isEmpty
                    || !(workspace.agentPIDKeysByPanelId[containerID] ?? []).isEmpty
                let states = (workspace.agentLifecycleStatesByPanelId[terminal.id] ?? [:])
                    .merging(workspace.agentLifecycleStatesByPanelId[containerID] ?? [:]) { first, _ in first }
                let hasLifecycle = states.contains { AgentHibernationLifecycleStatusKeys.isAllowed($0.key) && $0.value != .unknown }
                return BrowserContextTarget(id: terminal.id, title: terminal.title, isAgent: hasPID || (workspace.showsRelayHostAgentStatus && hasLifecycle), lastInput: terminal.lastContextInputAt)
            }
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// Validates membership again at the write boundary and never synthesizes Enter.
    func pasteSelectedContext(_ text: String, to terminalID: UUID) -> Bool {
        guard contextSelectionTargets().contains(where: { $0.id == terminalID && $0.isAgent }),
              let workspace = AppDelegate.shared?.tabManagerFor(tabId: workspaceId)?.tabs.first(where: { $0.id == workspaceId }),
              let terminal = workspace.controlTerminalPanel(for: terminalID),
              terminal.id == terminalID,
              terminal.surface.surface != nil else { return false }
        return terminal.sendText(text)
    }

    func prepareForContextSelection() async -> Bool {
        guard shouldRenderWebView, !isMainFrameProvisionalNavigationActive else { return false }
        if designModeController.isActive, !(await designModeController.setEnabled(false, reason: "contextSelection")) { return false }
        if isReactGrabActive {
            do {
                _ = try await designModeController.evaluatePageJavaScript("window.__REACT_GRAB__?.deactivate(); true", in: webView)
                isReactGrabActive = false
                clearReactGrabRoundTrip(reason: "contextSelection")
            } catch { return false }
        }
        clearBrowserFocusMode(reason: "contextSelection")
        return true
    }
}
