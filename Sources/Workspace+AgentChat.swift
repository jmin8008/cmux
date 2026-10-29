import AppKit

extension Workspace {
    func performSurfaceTabBarNewAgentChatAction(presentingWindow: NSWindow?) {
        guard let owningTabManager else { return }
        _ = AppDelegate.shared?.executeConfiguredCmuxAction(
            id: CmuxSurfaceTabBarBuiltInAction.newAgentChat.configID,
            tabManager: owningTabManager,
            preferredWindow: presentingWindow
        )
    }

    /// Wait for the hook's real session binding, including first-run sign-in.
    /// Never creates a second panel or switches the user's current selection.
    func openAgentWorkspaceWhenReady(terminalPanelId: UUID) {
        Task { @MainActor [weak self] in
            for _ in 0..<600 {
                guard let self, let panel = self.terminalPanel(for: terminalPanelId),
                      panel.agentWorkspace == nil else { return }
                let service = TerminalController.shared.agentChatTranscriptService
                let ready = service?.sessionRecords(workspaceID: nil).contains {
                        $0.surfaceID.flatMap(UUID.init(uuidString:)) == terminalPanelId
                            && ($0.agentKind.sourceName == "claude" || $0.agentKind.sourceName == "codex")
                            && service?.sessionBindingMatches(surfaceID: terminalPanelId, sessionID: $0.sessionID,
                                                               provider: $0.agentKind.sourceName) == true
                    } ?? false
                if ready {
                    self.openTerminalChatView(terminalPanelId: terminalPanelId, presentingWindow: nil)
                    return
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
                if Task.isCancelled { return }
            }
        }
    }

    /// Presents the existing root agent and its observed children in-place.
    /// The sidecar reads transcripts; the existing terminal owns execution.
    func openTerminalChatView(terminalPanelId: UUID, presentingWindow: NSWindow?) {
        guard let owningTabManager, let appDelegate = AppDelegate.shared else {
            NSSound.beep()
            return
        }
        Task { @MainActor [weak self, weak owningTabManager] in
            guard let owningTabManager,
                  let base = await appDelegate.agentChatBrowserBaseURL(
                      tabManager: owningTabManager,
                      preferredWindow: presentingWindow
                  ),
                  let self,
                  !self.isRemoteWorkspace,
                  ["127.0.0.1", "localhost", "::1"].contains(base.host ?? ""),
                  base.scheme == "http",
                  let panel = self.terminalPanel(for: terminalPanelId),
                  let service = TerminalController.shared.agentChatTranscriptService,
                  let record = service.sessionRecords(workspaceID: nil).first(where: {
                      $0.surfaceID.flatMap(UUID.init(uuidString:)) == terminalPanelId
                          && ($0.agentKind.sourceName == "claude" || $0.agentKind.sourceName == "codex")
                          && $0.state != .ended
                  }),
                  service.sessionBindingMatches(surfaceID: terminalPanelId, sessionID: record.sessionID,
                                                provider: record.agentKind.sourceName),
                  let url = Self.agentWorkspaceURL(base: base, terminalPanelId: terminalPanelId, workspaceID: self.id, sessionID: record.sessionID) else {
                NSSound.beep()
                return
            }
            if let existing = panel.agentWorkspace { existing.focus(); return }
            panel.unfocus()
            panel.agentWorkspace = AgentWorkspacePresentation(
                workspace: self,
                rootPanelID: terminalPanelId,
                rootSessionID: record.sessionID,
                rootProvider: record.agentKind.sourceName,
                url: url
            )
            panel.recordPortalHostOwnershipChange()
        }
    }

    static func agentWorkspaceURL(base: URL, terminalPanelId: UUID, workspaceID: UUID, sessionID: String) -> URL? {
        guard let url = terminalChatViewURL(base: base, terminalPanelId: terminalPanelId) else { return nil }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "group", value: "1"),
            URLQueryItem(name: "surface", value: terminalPanelId.uuidString),
            URLQueryItem(name: "workspace", value: workspaceID.uuidString),
            URLQueryItem(name: "root", value: sessionID)
        ]
        return components?.url
    }

    /// `<sidecar>/terminal/<panel id>?transparent=1`; the sidecar maps the
    /// panel to its agent session through the hook session stores.
    static func terminalChatViewURL(base: URL, terminalPanelId: UUID) -> URL? {
        let path = base
            .appendingPathComponent("terminal", isDirectory: true)
            .appendingPathComponent(terminalPanelId.uuidString)
        var components = URLComponents(url: path, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "transparent", value: "1")]
        return components?.url
    }
}

extension TabManager {
    /// Create a new terminal surface in the focused pane of the selected workspace
    func newSurface() {
        AppDelegate.shared?.leaveChiefHome(in: self)
        // Cmd+T should always focus the newly created surface.
        selectedWorkspace?.clearSplitZoom()
        selectedWorkspace?.newTerminalSurfaceInFocusedPane(focus: true)
    }

    @discardableResult
    func newSurface(initialInput: String) -> UUID? {
        AppDelegate.shared?.leaveChiefHome(in: self)
        selectedWorkspace?.clearSplitZoom()
        return selectedWorkspace?.newTerminalSurfaceInFocusedPane(focus: true, initialInput: initialInput)?.id
    }
}
