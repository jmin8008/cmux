import Foundation

/// Presentation opt-in. The provider continues to own every agent process.
public enum AgentWorkspaceLaunchPolicy {
    public static let environmentKey = "CMUX_AGENT_WORKSPACE"

    public static func isEnabled(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        environment[environmentKey] == "1"
    }

    public static func defaultClaudeTeammateMode(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        isEnabled(environment: environment) ? "in-process" : "auto"
    }
}

/// Read-only lineage exported by the existing Codex Teams watcher. No transcript
/// path, command, or credential is accepted by this format.
public struct AgentWorkspaceCodexThread: Codable, Sendable {
    public let id: String
    public let parentThreadID: String?
    public let label: String?
    public let status: String?

    public init(id: String, parentThreadID: String?, label: String?, status: String?) {
        self.id = id
        self.parentThreadID = parentThreadID
        self.label = label
        self.status = status
    }
}

public struct AgentWorkspaceCodexSnapshot: Encodable, Sendable {
    public let version = 1
    public let workspaceID: String
    public let surfaceID: String
    public let updatedAt: Double
    public let threads: [AgentWorkspaceCodexThread]

    public init(workspaceID: String, surfaceID: String, threads: [AgentWorkspaceCodexThread], now: Date = Date()) {
        self.workspaceID = workspaceID
        self.surfaceID = surfaceID
        self.updatedAt = now.timeIntervalSince1970 * 1000
        self.threads = Array(threads.prefix(2000))
    }

    public func write(directory: URL) throws {
        guard let surface = UUID(uuidString: surfaceID), UUID(uuidString: workspaceID) != nil else { return }
        let folder = directory.appendingPathComponent("codex", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let target = folder.appendingPathComponent(surface.uuidString.lowercased() + ".json")
        try JSONEncoder().encode(self).write(to: target, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
    }
}
