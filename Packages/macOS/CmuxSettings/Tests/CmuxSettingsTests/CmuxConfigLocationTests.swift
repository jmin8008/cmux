import Foundation
import Testing
@testable import CmuxSettings

@Suite("Development configuration isolation")
struct CmuxConfigLocationTests {
    @Test func taggedWritesLeaveStableSettingsUntouched() async throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-config-isolation-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let stableFile = home.appendingPathComponent(".config/cmux/cmux.json")
        try FileManager.default.createDirectory(
            at: stableFile.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let original = Data(#"{"app":{"appearance":"light"}}"#.utf8)
        try original.write(to: stableFile)

        let locations = CmuxConfigLocation(
            home: home, bundleIdentifier: "com.cmuxterm.app.debug.jmin", environment: [:]
        )
        let store = JSONConfigStore(fileURL: locations.userConfigFile)
        let key = JSONKey<String>(id: "app.appearance", defaultValue: "system")
        #expect(await store.value(for: key) == "system")
        try await store.set("dark", for: key)
        #expect(await JSONConfigStore(fileURL: locations.userConfigFile).value(for: key) == "dark")
        #expect(try Data(contentsOf: stableFile) == original)
        #expect(locations.userConfigFile.path == home.appendingPathComponent(".config/cmux-dev/jmin/cmux.json").path)
    }
}
