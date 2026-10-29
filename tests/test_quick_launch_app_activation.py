#!/usr/bin/env python3
"""Run the actual app-open body with a refused activation and a scoped app bundle."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class AppActivationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.build = tempfile.TemporaryDirectory(prefix="cmux-quick-launch-app-")
        source = (ROOT / "Sources/QuickLaunch.swift").read_text()
        start = source.index("    private func openApp(")
        end = source.index("\n    }", start) + len("\n    }")
        main = Path(cls.build.name) / "main.swift"
        main.write_text('''import Foundation
struct QuickLaunchEntry {
    struct Target { let url: String; let bundleIdentifier: String?; let bookmark: Data? }
    let target: Target
}
enum QuickLaunchError: Error { case invalidEntry }
@MainActor final class NSRunningApplication {
    static var applications: [NSRunningApplication] = []
    let bundleURL: URL?
    let activates: Bool
    var calls = 0
    init(_ url: URL, activates: Bool) { bundleURL = url; self.activates = activates }
    static func runningApplications(withBundleIdentifier: String) -> [NSRunningApplication] { applications }
    func activate() -> Bool { calls += 1; return activates }
}
@MainActor final class NSWorkspace {
    static let shared = NSWorkspace()
    final class OpenConfiguration { var activates = false; var createsNewApplicationInstance = false }
    var requests: [URL] = []
    var duplicates = false
    func openApplication(at url: URL, configuration: OpenConfiguration) async throws -> Bool {
        requests.append(url); duplicates = configuration.createsNewApplicationInstance
        return true
    }
}
@MainActor struct Harness {
''' + source[start:end] + '''
    func run(_ entry: QuickLaunchEntry) async throws { try await openApp(entry) }
}
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let app = root.appendingPathComponent("Fixture.app", isDirectory: true)
let contents = app.appendingPathComponent("Contents", isDirectory: true)
try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
let info = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier":"test.cmux.quicklaunch", "CFBundlePackageType":"APPL"], format: .xml, options: 0)
try info.write(to: contents.appendingPathComponent("Info.plist"))
let entry = QuickLaunchEntry(target: .init(url: app.absoluteString, bundleIdentifier: "test.cmux.quicklaunch", bookmark: nil))
let refused = NSRunningApplication(app, activates: false)
NSRunningApplication.applications = [refused]
var hadError = false
do { try await Harness().run(entry) } catch { hadError = true }
let fallback = NSWorkspace.shared.requests == [app]
NSWorkspace.shared.requests = []
let accepted = NSRunningApplication(app, activates: true)
NSRunningApplication.applications = [accepted]
try await Harness().run(entry)
let reused = NSWorkspace.shared.requests.isEmpty && accepted.calls == 1
NSWorkspace.shared.requests = []
let foreign = NSRunningApplication(root.appendingPathComponent("Other.app"), activates: true)
NSRunningApplication.applications = [foreign]
try await Harness().run(entry)
let scoped = NSWorkspace.shared.requests == [app] && foreign.calls == 0
print(String(decoding: try JSONSerialization.data(withJSONObject: ["fallback":fallback, "error":hadError, "reused":reused, "scoped":scoped, "duplicates":NSWorkspace.shared.duplicates]), as: UTF8.self))
''')
        binary = Path(cls.build.name) / "probe"
        compiled = subprocess.run(["xcrun", "swiftc", "-swift-version", "6", str(main), "-o", str(binary)], capture_output=True, text=True)
        if compiled.returncode:
            raise RuntimeError(compiled.stderr)
        cls.result = json.loads(subprocess.check_output([str(binary), cls.build.name], text=True))

    @classmethod
    def tearDownClass(cls):
        cls.build.cleanup()

    def test_refused_activation_reopens_verified_app_without_new_instance(self):
        self.assertFalse(self.result["error"])
        self.assertTrue(self.result["fallback"])
        self.assertFalse(self.result["duplicates"])

    def test_successful_activation_keeps_existing_process(self):
        self.assertTrue(self.result["reused"])

    def test_different_bundle_path_does_not_capture_shortcut(self):
        self.assertTrue(self.result["scoped"])


if __name__ == "__main__":
    unittest.main()
