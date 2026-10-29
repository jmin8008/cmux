import CmuxMobileHost
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@MainActor
@Suite("Agent workspace input binding", .serialized)
struct AgentWorkspaceInputBindingTests {
    @Test(arguments: [false, true])
    func composerRejectsEndedOrReplacedSessionOnSurvivingSurface(ended: Bool) async throws {
        let fixture = TerminalPortalTestWorkspace()
        defer { fixture.tearDown() }
        let panel = try #require(fixture.workspace.focusedTerminalPanel)
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let old = AgentChatSessionRecord(
            sessionID: "old-\(UUID().uuidString)", agentKind: .claude,
            workspaceID: fixture.workspace.id.uuidString, surfaceID: panel.id.uuidString,
            workingDirectory: nil, transcriptPath: nil, state: ended ? .ended : .idle,
            lastActivityAt: Date(timeIntervalSince1970: 100), title: nil, pid: nil
        )
        let replacement = AgentChatSessionRecord(
            sessionID: "replacement-\(UUID().uuidString)", agentKind: .claude,
            workspaceID: old.workspaceID, surfaceID: old.surfaceID,
            workingDirectory: nil, transcriptPath: nil, state: .idle,
            lastActivityAt: Date(timeIntervalSince1970: 200), title: nil, pid: nil
        )
        let registry = AgentChatSessionRegistry(hookStore: AgentChatHookSessionStore(homeDirectory: home),
            restoredRecords: ended ? [old] : [old, replacement])
        let service = AgentChatTranscriptService(registry: registry,
            resolver: AgentChatTranscriptResolver(homeDirectory: home, environment: [:]),
            hasEventSubscribers: { false }, emitEventPayload: { _ in }, fallbackTranscriptPathResolver: { _, _ in nil })
        let previous = TerminalController.shared.agentChatTranscriptService
        TerminalController.shared.agentChatTranscriptService = service
        defer {
            TerminalController.shared.agentChatTranscriptService = previous
            service.shutdown()
        }
        #expect(!service.sessionBindingMatches(record: old))
        let result = await TerminalController.shared.v2MobileChatSend(params: [
            "session_id": old.sessionID, "text": "must not enter the surviving PTY"
        ])
        guard case .err(let code, _, _) = result else {
            Issue.record("Stale main composer input was accepted")
            return
        }
        #expect(code == "not_found")
        #expect(fixture.workspace.terminalPanel(for: panel.id) === panel)
    }
}
