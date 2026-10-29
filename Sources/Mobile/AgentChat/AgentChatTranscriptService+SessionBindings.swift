import CMUXAgentLaunch
import CmuxAgentChat
import CmuxMobileHost
import Foundation

extension AgentChatTranscriptService {
    static let sessionBindingsDidChange = Notification.Name("cmux.agentChat.sessionBindingsDidChange")

    /// Main-actor registry mutation has already updated its live-surface index.
    /// Synchronous delivery revokes a mounted renderer before another key event.
    func notifySessionBindingsChanged() {
        NotificationCenter.default.post(name: Self.sessionBindingsDidChange, object: self)
    }

    func sessionBindingMatches(record: AgentChatSessionRecord) -> Bool {
        guard let surfaceID = record.surfaceID.flatMap(UUID.init(uuidString:)) else { return false }
        return sessionBindingMatches(surfaceID: surfaceID, sessionID: record.sessionID, provider: record.agentKind.sourceName)
    }

    func sessionBindingMatches(surfaceID: UUID, sessionID: String, provider: String) -> Bool {
        guard !didShutdown,
              let record = registry.liveSessionSnapshot(surfaceID: surfaceID.uuidString),
              record.sessionID == sessionID, record.agentKind.sourceName == provider,
              record.state != .ended else { return false }
        guard let pid = record.pid else { return true }
        return kill(pid_t(pid), 0) == 0 || errno == EPERM
    }

    /// Lists chat-capable sessions.
    ///
    /// - Parameter workspaceID: Workspace UUID string filter, or `nil`.
    /// - Returns: Wire descriptors, most recent first.
    func sessionDescriptors(workspaceID: String?) -> [ChatSessionDescriptor] {
        registry.sessions(workspaceID: workspaceID).map(\.descriptor)
    }

    /// Lists raw session records for callers that must validate live
    /// terminal bindings before exposing descriptors.
    ///
    /// - Parameter workspaceID: Workspace UUID string filter, or `nil`.
    /// - Returns: Matching records, most recent first.
    func sessionRecords(workspaceID: String?) -> [AgentChatSessionRecord] {
        registry.sessions(workspaceID: workspaceID)
    }
}
