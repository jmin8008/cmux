import Foundation
import Testing
@testable import CmuxSettings

struct QuickLaunchTests {
    private func entry(_ name: String = "Local") -> QuickLaunchEntry {
        QuickLaunchEntry(name: name, target: .init(kind: .web, url: "http://localhost:3000/settings?a=1"), openMode: .inApp)
    }

    @Test func roundTripPreservesTargetsAndOrder() throws {
        let registry = QuickLaunchRegistry(entries: [entry(), entry("Docs")])
        #expect(try QuickLaunchRegistry.decode(registry.jsonObject()) == registry)
    }

    @Test(arguments: ["javascript:alert(1)", "file:///tmp/a", "https://user:pass@example.com", "http://", "localhost:3000"])
    func rejectsUnsafeOrIncompleteURL(value: String) {
        #expect(QuickLaunchEntry.webURL(value) == nil)
    }

    @Test func keepsExactQueryAndFragment() {
        let address = "http://localhost:3000/settings?a=1&b=2#save"
        #expect(QuickLaunchEntry.webURL(address)?.absoluteString == address)
    }

    @Test func refusesFutureAndLossyDocuments() throws {
        var raw = try QuickLaunchRegistry(entries: [entry()]).jsonObject()
        raw["version"] = 2
        #expect(throws: QuickLaunchError.self) { try QuickLaunchRegistry.decode(raw) }
        raw["version"] = 1
        var rows = raw["entries"] as! [[String: Any]]
        rows[0]["futureField"] = "preserve me"
        raw["entries"] = rows
        #expect(throws: QuickLaunchError.self) { try QuickLaunchRegistry.decode(raw) }
    }

    @Test func duplicateIDsAndStaleEditsFail() throws {
        let a = entry()
        #expect(throws: QuickLaunchError.self) {
            try QuickLaunchRegistry.decode(QuickLaunchRegistry(entries: [a, a]).jsonObject())
        }
        var registry = QuickLaunchRegistry(entries: [a])
        var renamed = a
        renamed.name = "Changed"
        try registry.apply(.save(renamed, replacing: a))
        #expect(throws: QuickLaunchError.conflict) { try registry.apply(.remove(a)) }
        #expect(registry.entries == [renamed])
    }

    @Test func movesByIdentityWithoutDroppingConcurrentAdds() throws {
        let a = entry("A"), b = entry("B"), c = entry("C")
        var registry = QuickLaunchRegistry(entries: [a, b])
        try registry.apply(.save(c, replacing: nil))
        try registry.apply(.move(b.id, before: a.id))
        #expect(registry.entries == [b, a, c])
        try registry.apply(.move(b.id, before: nil))
        #expect(registry.entries == [a, c, b])
    }

    @Test func reusesOnlyExactURLInCurrentWorkspaceAndProfile() {
        let workspace = UUID(), profile = UUID(), matching = UUID(), navigated = UUID()
        let url = "http://localhost:3000/a?view=1"
        let candidates = [
            QuickLaunchBrowserCandidate(panelID: UUID(), workspaceID: UUID(), profileID: profile, url: url),
            QuickLaunchBrowserCandidate(panelID: UUID(), workspaceID: workspace, profileID: UUID(), url: url),
            QuickLaunchBrowserCandidate(panelID: navigated, workspaceID: workspace, profileID: profile, url: "http://localhost:3000/a?view=2"),
            QuickLaunchBrowserCandidate(panelID: matching, workspaceID: workspace, profileID: profile, url: url)
        ]
        #expect(QuickLaunchBrowserReuse.panelID(for: url, workspaceID: workspace, profileID: profile,
            boundPanelID: navigated, focusedPanelID: navigated, candidates: candidates) == matching)
        #expect(QuickLaunchBrowserReuse.panelID(for: url + "#other", workspaceID: workspace, profileID: profile,
            boundPanelID: matching, focusedPanelID: matching, candidates: candidates) == nil)
    }

    @Test func twoStoresPreserveUnrelatedSettingsAndBothEntries() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("cmux.json")
        try Data("{\n  // keep this comment\n  \"app\": {\"appearance\": \"dark\"}\n}\n".utf8).write(to: url)
        let first = JSONConfigStore(fileURL: url), second = JSONConfigStore(fileURL: url)
        let a = entry("A"), b = entry("B")
        async let one: Void = first.applyQuickLaunch(.save(a, replacing: nil))
        async let two: Void = second.applyQuickLaunch(.save(b, replacing: nil))
        _ = try await (one, two)
        guard case let .ready(registry) = await first.quickLaunchState() else { Issue.record("Unreadable configuration"); return }
        #expect(Set(registry.entries.map(\.id)) == Set([a.id, b.id]))
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("// keep this comment"))
        #expect(text.contains("\"appearance\": \"dark\""))
    }

    @Test(arguments: ["{broken", "{\"quickLaunch\":{\"version\":2,\"entries\":[]}}", "{\"quickLaunch\":false}"])
    func damagedFileIsNotOverwritten(source: String) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("cmux.json")
        let original = Data(source.utf8)
        try original.write(to: url)
        let store = JSONConfigStore(fileURL: url)
        #expect(await store.quickLaunchState() == .unreadable)
        do { try await store.applyQuickLaunch(.save(entry(), replacing: nil)); Issue.record("Write should fail") }
        catch { }
        #expect(try Data(contentsOf: url) == original)
    }
}
