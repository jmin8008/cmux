import Foundation

extension TabManager {
    /// Shared Find/menu/palette routing follows the current group responder.
    var activeAgentWorkspacePresentation: AgentWorkspacePresentation? {
        guard let presentation = selectedWorkspace?.focusedTerminalPanel?.agentWorkspace,
              presentation.routesFindToWebContent else { return nil }
        return presentation
    }
}
