#!/usr/bin/env python3
"""Exercise the actual app candidate projection and reuse policy without launching WebKit.

The projection is compiled verbatim from QuickLaunchModel.open. Lightweight panel
records stand in for app composition; the reuse policy is the production source.
Native acceptance additionally verifies that focusing the chosen placeholder
materializes it with the same tab identity.
"""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class RestoredBrowserReuseTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.build = tempfile.TemporaryDirectory(prefix="cmux-quick-launch-restored-")
        cls.binary = Path(cls.build.name) / "probe"
        source = (ROOT / "Sources/QuickLaunch.swift").read_text()
        start = source.index("                    let candidates = workspace.panels.values")
        end = source.index("                    let match =", start)
        projection = source[start:end]
        main = Path(cls.build.name) / "main.swift"
        main.write_text('''import Foundation
protocol Panel { var id: UUID { get } }
final class BrowserPanel: Panel {
    static let defaultProfile = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let id = UUID()
    let profileID: UUID
    let currentURL: URL?
    init(_ url: String, profile: UUID) { currentURL = URL(string: url); profileID = profile }
    static func resolvedProfileID(requested: UUID?) -> UUID { requested ?? defaultProfile }
}
struct BrowserSnapshot { let urlString: String?; let profileID: UUID? }
struct PanelSnapshot { let browser: BrowserSnapshot? }
final class DeferredBrowserPanel: Panel {
    let id = UUID()
    let sessionPanelSnapshot: PanelSnapshot
    init(_ url: String?, profile: UUID?) {
        sessionPanelSnapshot = PanelSnapshot(browser: BrowserSnapshot(urlString: url, profileID: profile))
    }
}
struct TerminalPanel: Panel { let id = UUID() }
struct Workspace { let id = UUID(); let panels: [UUID: any Panel] }
let url = "http://localhost:3000/settings?view=1#save"
let profile = BrowserPanel.defaultProfile
let foreignProfile = UUID()
let restored = DeferredBrowserPanel(url, profile: profile)
let legacy = DeferredBrowserPanel("http://localhost:3000/legacy", profile: nil)
let foreign = DeferredBrowserPanel("http://localhost:3000/foreign", profile: foreignProfile)
let live = BrowserPanel("http://localhost:3000/live", profile: profile)
let terminal = TerminalPanel()
let workspace = Workspace(panels: [restored.id: restored, legacy.id: legacy,
    foreign.id: foreign, live.id: live, terminal.id: terminal])
''' + projection + '''
@MainActor func reused(_ address: String, expected: UUID) -> Bool {
    QuickLaunchBrowserReuse.panelID(for: address, workspaceID: workspace.id, profileID: profile,
        boundPanelID: nil, focusedPanelID: nil, candidates: candidates) == expected
}
let payload: [String: Bool] = [
    "restored": reused(url, expected: restored.id),
    "legacy": reused("http://localhost:3000/legacy", expected: legacy.id),
    "live": reused("http://localhost:3000/live", expected: live.id),
    "query_fence": !reused(url + "-other", expected: restored.id),
    "profile_fence": !reused("http://localhost:3000/foreign", expected: foreign.id),
    "no_terminal": !candidates.contains { $0.panelID == terminal.id }
]
print(String(decoding: try JSONSerialization.data(withJSONObject: payload), as: UTF8.self))
''')
        compiled = subprocess.run(["xcrun", "swiftc", "-swift-version", "6",
            str(ROOT / "Packages/macOS/CmuxSettings/Sources/CmuxSettings/Values/QuickLaunchBrowserReuse.swift"),
            str(main), "-o", str(cls.binary)], capture_output=True, text=True)
        if compiled.returncode:
            raise RuntimeError(compiled.stderr)
        cls.result = json.loads(subprocess.check_output([str(cls.binary)], text=True))

    @classmethod
    def tearDownClass(cls):
        cls.build.cleanup()

    def test_restored_browser_is_reused(self):
        self.assertTrue(self.result["restored"], "Unselected restored browser was omitted from reuse candidates")

    def test_old_snapshot_uses_the_same_profile_resolution_as_materialization(self):
        self.assertTrue(self.result["legacy"])

    def test_live_browser_still_reuses(self):
        self.assertTrue(self.result["live"])

    def test_profile_and_full_address_fences_remain(self):
        self.assertTrue(self.result["query_fence"])
        self.assertTrue(self.result["profile_fence"])

    def test_terminal_is_not_a_browser_candidate(self):
        self.assertTrue(self.result["no_terminal"])


if __name__ == "__main__":
    unittest.main()
