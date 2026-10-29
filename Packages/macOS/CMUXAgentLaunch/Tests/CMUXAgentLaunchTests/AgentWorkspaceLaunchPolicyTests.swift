import Foundation
import Testing
@testable import CMUXAgentLaunch

@Suite("Agent workspace presentation launch")
struct AgentWorkspaceLaunchPolicyTests {
    @Test func groupModeDoesNotChangeOrdinaryTeamsLaunches() {
        #expect(!AgentWorkspaceLaunchPolicy.isEnabled(environment: [:]))
        #expect(!AgentWorkspaceLaunchPolicy.isEnabled(environment: ["CMUX_AGENT_WORKSPACE": "true"]))
        #expect(AgentWorkspaceLaunchPolicy.defaultClaudeTeammateMode(environment: [:]) == "auto")
        #expect(AgentWorkspaceLaunchPolicy.isEnabled(environment: ["CMUX_AGENT_WORKSPACE": "1"]))
        #expect(AgentWorkspaceLaunchPolicy.defaultClaudeTeammateMode(environment: ["CMUX_AGENT_WORKSPACE": "1"]) == "in-process")
    }

    @Test func restoreKeepsOnlyTheBooleanGroupPresentationMarker() {
        let policy = AgentLaunchEnvironmentPolicy()
        #expect(policy.selectedRestoreEnvironment(from: ["CMUX_AGENT_WORKSPACE": "1"], kind: "codex")["CMUX_AGENT_WORKSPACE"] == "1")
        #expect(policy.selectedRestoreEnvironment(from: ["CMUX_AGENT_WORKSPACE": "true"], kind: "codex")["CMUX_AGENT_WORKSPACE"] == nil)
        #expect(policy.selectedRestoreEnvironment(from: ["CMUX_AGENT_WORKSPACE_DIRECTORY": "/foreign/config"], kind: "codex")["CMUX_AGENT_WORKSPACE_DIRECTORY"] == nil)
    }

    @Test func watcherPreservesGroupEnvironment() {
        let invocation = CodexTeamsWatcherInvocation(socketPath: "/tmp/test.sock", workspaceID: "workspace",
            surfaceID: "surface", appServerURL: "ws://127.0.0.1:1234", codexPath: "/test/codex", launchPath: "/usr/bin:/bin",
            maxAutoDepth: 2, ownerPID: 1, socketPassword: nil,
            environment: ["CMUX_AGENT_WORKSPACE": "1", "CMUX_BUNDLE_ID": "com.cmuxterm.app.debug.jmin.agents"])
        #expect(AgentWorkspaceLaunchPolicy.isEnabled(environment: invocation.environment))
        #expect(invocation.environment["CMUX_BUNDLE_ID"] == "com.cmuxterm.app.debug.jmin.agents")
    }

    @Test func lineageSnapshotWritesOnlyToCanonicalSurfaceFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let surface = UUID(), workspace = UUID()
        let snapshot = AgentWorkspaceCodexSnapshot(workspaceID: workspace.uuidString, surfaceID: surface.uuidString,
            threads: [.init(id: "child-session", parentThreadID: "root-session", label: "Reviewer", status: "active")],
            now: Date(timeIntervalSince1970: 123))
        try snapshot.write(directory: directory)
        let path = directory.appendingPathComponent("codex/\(surface.uuidString.lowercased()).json")
        let json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any])
        #expect(json["version"] as? Int == 1)
        #expect(json["updatedAt"] as? Double == 123_000)
        let threads = try #require(json["threads"] as? [[String: Any]])
        #expect(threads.first?["parentThreadID"] as? String == "root-session")
        #expect(threads.first?["id"] as? String == "child-session")
        let attributes = try FileManager.default.attributesOfItem(atPath: path.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        try AgentWorkspaceCodexSnapshot(workspaceID: workspace.uuidString, surfaceID: "../../escape", threads: []).write(directory: directory)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.appendingPathComponent("codex").path).count == 1)
    }
}
