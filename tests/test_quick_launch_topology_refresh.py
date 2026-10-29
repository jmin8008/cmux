#!/usr/bin/env python3
"""Execute the app's web-open mutation body against the socket refresh boundary."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class QuickLaunchTopologyRefreshTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.build = tempfile.TemporaryDirectory(prefix="cmux-quick-launch-refresh-")
        source = (ROOT / "Sources/QuickLaunch.swift").read_text()
        start = source.index("                    let profile = workspace.quickLaunchProfileID()")
        end = source.index("                }\n            }\n            error = nil", start)
        body = source[start:end]
        main = Path(cls.build.name) / "main.swift"
        main.write_text('''import Foundation
protocol Panel { var id: UUID { get } }
final class BrowserPanel: Panel {
    static let defaultProfile = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let id = UUID()
    let profileID: UUID
    let currentURL: URL?
    init(_ url: URL, profile: UUID) { currentURL = url; profileID = profile }
    static func resolvedProfileID(requested: UUID?) -> UUID { requested ?? defaultProfile }
}
struct BrowserSnapshot { let urlString: String?; let profileID: UUID? }
struct PanelSnapshot { let browser: BrowserSnapshot? }
final class DeferredBrowserPanel: Panel {
    let id = UUID(); let sessionPanelSnapshot = PanelSnapshot(browser: nil)
}
struct Entry { let id = UUID() }
enum QuickLaunchError: Error { case invalidEntry }
@MainActor final class TerminalController {
    static let shared = TerminalController()
    var refreshCount = 0
    func externalTopologyDidChange() { refreshCount += 1 }
}
final class Workspace {
    let id = UUID()
    var panels: [UUID: any Panel] = [:]
    var focusedPanelId: UUID?
    func quickLaunchProfileID() -> UUID { BrowserPanel.defaultProfile }
    func focusPanel(_ id: UUID) { focusedPanelId = id }
    func newBrowserSurface(inPane: UUID, url: URL, focus: Bool, preferredProfileID: UUID,
        allowsExternalBrowserFallback: Bool, bypassRemoteProxy: Bool) -> BrowserPanel? {
        let panel = BrowserPanel(url, profile: preferredProfileID)
        panels[panel.id] = panel
        focusedPanelId = panel.id
        return panel
    }
}
@MainActor func openFixture(workspace: Workspace, url: URL, entry: Entry) throws {
    let pane = UUID()
    var bindings: [UUID: [UUID: UUID]] = [:]
''' + body + '''
}
let workspace = Workspace()
let url = URL(string: "http://localhost:3000/quick-launch")!
let entry = Entry()
try openFixture(workspace: workspace, url: url, entry: entry)
let createdRefreshes = TerminalController.shared.refreshCount
let firstID = workspace.focusedPanelId
try openFixture(workspace: workspace, url: url, entry: entry)
let payload: [String: Int] = [
    "created_refreshes": createdRefreshes,
    "reused_refreshes": TerminalController.shared.refreshCount - createdRefreshes,
    "panel_count": workspace.panels.count,
    "same_identity": workspace.focusedPanelId == firstID ? 1 : 0
]
print(String(decoding: try JSONSerialization.data(withJSONObject: payload), as: UTF8.self))
''')
        binary = Path(cls.build.name) / "probe"
        compiled = subprocess.run(["xcrun", "swiftc", "-swift-version", "6",
            str(ROOT / "Packages/macOS/CmuxSettings/Sources/CmuxSettings/Values/QuickLaunchBrowserReuse.swift"),
            str(main), "-o", str(binary)], capture_output=True, text=True)
        if compiled.returncode:
            raise RuntimeError(compiled.stderr)
        cls.result = json.loads(subprocess.check_output([str(binary)], text=True))

    @classmethod
    def tearDownClass(cls):
        cls.build.cleanup()

    def test_created_browser_invalidates_cached_socket_topology(self):
        self.assertEqual(self.result["created_refreshes"], 1)

    def test_reused_browser_invalidates_cached_socket_focus(self):
        self.assertEqual(self.result["reused_refreshes"], 1)
        self.assertEqual(self.result["panel_count"], 1)
        self.assertEqual(self.result["same_identity"], 1)


if __name__ == "__main__":
    unittest.main()
