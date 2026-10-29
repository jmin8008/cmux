import Foundation

/// NotificationCenter tokens can be removed from any thread. Keeping the token
/// in a Sendable owner also makes cleanup safe from an actor-isolated host deinit.
final class AgentWorkspaceSessionObservation: @unchecked Sendable {
    private let token: NSObjectProtocol

    @MainActor
    init(service: AgentChatTranscriptService, onChange: @escaping @MainActor @Sendable () -> Void) {
        token = NotificationCenter.default.addObserver(
            forName: AgentChatTranscriptService.sessionBindingsDidChange, object: nil, queue: nil
        ) { [weak service] notification in
            guard let service, (notification.object as? AgentChatTranscriptService) === service else { return }
            MainActor.assumeIsolated { onChange() }
        }
    }

    deinit { NotificationCenter.default.removeObserver(token) }
}
