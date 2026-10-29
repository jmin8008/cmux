import AppKit
import CmuxBrowser
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@MainActor
@Suite("Agent workspace presentation", .serialized)
struct AgentWorkspacePresentationTests {
    @MainActor
    @Test func groupedAgentLauncherOptsIntoPresentationWithoutChangingProviderArguments() {
        let command = ContentView.commandPaletteAgentLauncherShellInput(
            cliURL: URL(fileURLWithPath: "/tmp/cmux"), subcommand: "codex-teams", groupPresentation: true
        )
        #expect(command == "CMUX_AGENT_WORKSPACE=1 /tmp/cmux codex-teams\n")
    }


    @Test
    func groupFindDoesNotOpenHiddenTerminalSearch() throws {
        let manager = TabManager()
        let workspace = manager.addWorkspace(select: true, eagerLoadTerminal: false)
        defer { workspace.teardownAllPanels() }
        let panel = try #require(workspace.focusedTerminalPanel)
        let panelIDs = Set(workspace.panels.keys)
        let surface = panel.surface
        let suite = "cmux-agent-workspace-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let url = try #require(Workspace.agentWorkspaceURL(
            base: URL(string: "http://127.0.0.1:1/test-token/")!,
            terminalPanelId: panel.id,
            workspaceID: workspace.id,
            sessionID: "test-session"
        ))
        let presentation = AgentWorkspacePresentation(
            workspace: workspace,
            rootPanelID: panel.id,
            rootSessionID: "test-session",
            rootProvider: "claude",
            url: url,
            defaults: defaults
        )
        panel.agentWorkspace = presentation
        #expect(manager.startSearch())
        #expect(presentation.showsFind)
        #expect(manager.isFindVisible)
        #expect(panel.searchState == nil)
        manager.hideFind()
        #expect(!presentation.showsFind)
        #expect(!manager.isFindVisible)
        presentation.hide()
        #expect(panel.agentWorkspace == nil)
        #expect(panel.surface === surface)
        #expect(Set(workspace.panels.keys) == panelIDs)
    }

    @Test
    func movingRootRestoresTerminalWithoutChangingItsIdentity() throws {
        let workspace = Workspace(title: "Group move test")
        defer { workspace.teardownAllPanels() }
        let panel = try #require(workspace.focusedTerminalPanel)
        let surface = panel.surface
        panel.agentWorkspace = AgentWorkspacePresentation(
            workspace: workspace,
            rootPanelID: panel.id,
            rootSessionID: "test-session",
            rootProvider: "codex",
            url: URL(string: "http://127.0.0.1:1/token/terminal/\(panel.id.uuidString)")!
        )
        let destination = UUID()
        panel.updateWorkspaceId(destination)
        #expect(panel.agentWorkspace == nil)
        #expect(panel.workspaceId == destination)
        #expect(panel.surface === surface)
    }

    @Test
    func groupURLPinsOriginalSessionAndWorkspace() throws {
        let panel = UUID(), workspace = UUID()
        let url = try #require(Workspace.agentWorkspaceURL(
            base: URL(string: "http://127.0.0.1:7739/token/")!,
            terminalPanelId: panel,
            workspaceID: workspace,
            sessionID: "original-session"
        ))
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(url.path == "/token/terminal/\(panel.uuidString)")
        #expect(query.first(where: { $0.name == "root" })?.value == "original-session")
        #expect(query.first(where: { $0.name == "workspace" })?.value == workspace.uuidString)
        #expect(query.first(where: { $0.name == "group" })?.value == "1")
    }
}
