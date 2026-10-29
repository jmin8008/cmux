#!/usr/bin/env python3
"""Compile and exercise the CLI's actual optional fallback consumers in isolation."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def method(relative_path, signature):
    source = (ROOT / relative_path).read_text()
    start = source.index("    " + signature)
    end = source.index("\n    }", start) + len("\n    }")
    return source[start:end]


class CLIOptionalConfigPathTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.build = tempfile.TemporaryDirectory(prefix="cmux-cli-config-paths-")
        cls.binary = Path(cls.build.name) / "probe"
        main = Path(cls.build.name) / "main.swift"
        # The method bodies are copied verbatim from production, not reimplemented.
        # Only CLI composition (home/identity and unrelated project lookup) is stubbed.
        methods = [
            method("CLI/CMUXCLI+ConfigValidation.swift", "private func defaultConfigDoctorTargets()"),
            method("CLI/CMUXCLI+ConfigValidation.swift", "private func configSemanticScope(for path:"),
            method("CLI/CMUXCLI+ConfigValidation.swift", "private static func absoluteConfigPath("),
            method("CLI/CMUXCLI+DiffViewerPreferences.swift", "private func diffViewerDefaultSettingsPaths()"),
            method("CLI/cmux_open.swift", "private func diffViewerShortcutSettingsPaths()"),
            method("CLI/cmux_open.swift", "static func absoluteDiffViewerSettingsPath("),
        ]
        main.write_text('''import Foundation
enum CmuxConfigSemanticScope: String { case global, project }
struct CMUXCLI {
    static let location = CmuxConfigLocation(home: URL(fileURLWithPath: CommandLine.arguments[1]), bundleIdentifier: CommandLine.arguments[2], environment: [:])
    static var primarySettingsDisplayPath: String { location.userConfigFile.path }
    static var legacySettingsDisplayPath: String { location.legacyFallbackFile.path }
    static var fallbackSettingsDisplayPath: String? { location.legacyApplicationSupportFile?.path }
    struct ConfigDoctorTarget {
        let label: String
        let displayPath: String
        let path: String
        let missingIsError: Bool
        let scope: CmuxConfigSemanticScope
    }
    private func findProjectConfigPath() -> String? { nil }
    static func tildePath(_ path: String) -> String { path }
''' + "\n".join(methods) + '''
    func payload() -> [String: Any] {
        ["doctor": defaultConfigDoctorTargets().map(\\.path),
         "layout": diffViewerDefaultSettingsPaths(),
         "shortcuts": diffViewerShortcutSettingsPaths(),
         "primary_scope": configSemanticScope(for: Self.primarySettingsDisplayPath).rawValue,
         "fallback": Self.fallbackSettingsDisplayPath as Any? ?? NSNull()]
    }
}
let data = try JSONSerialization.data(withJSONObject: CMUXCLI().payload())
print(String(decoding: data, as: UTF8.self))
''')
        result = subprocess.run([
            "xcrun", "swiftc", "-swift-version", "6",
            str(ROOT / "Packages/macOS/CmuxSettings/Sources/CmuxSettings/Stores/CmuxConfigLocation.swift"),
            str(main), "-o", str(cls.binary),
        ], capture_output=True, text=True)
        if result.returncode:
            raise RuntimeError(result.stderr)

    @classmethod
    def tearDownClass(cls):
        cls.build.cleanup()

    def probe(self, directory, identity):
        result = subprocess.run([str(self.binary), str(directory), identity], capture_output=True, text=True, check=True)
        return json.loads(result.stdout)

    def test_development_omits_unavailable_legacy_fallback_everywhere(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            stable = home / "Library/Application Support/com.cmuxterm.app/settings.json"
            stable.parent.mkdir(parents=True)
            stable.write_text('{"diffViewer":{"defaultLayout":"split"}}')
            dev = home / ".config/cmux-dev/probe"
            dev.mkdir(parents=True)
            (dev / "settings.json").write_text("{}")
            result = self.probe(home, "com.cmuxterm.app.debug.probe")
            self.assertIsNone(result["fallback"])
            self.assertEqual(result["doctor"], [str(dev / "cmux.json"), str(dev / "settings.json")])
            self.assertEqual(result["layout"], result["doctor"])
            self.assertEqual(result["shortcuts"], [str(dev / "settings.json")])
            self.assertEqual(result["primary_scope"], "global")
            self.assertNotIn(str(stable), json.dumps(result))

    def test_stable_identity_keeps_its_existing_fallback(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            stable = home / "Library/Application Support/com.cmuxterm.app/settings.json"
            stable.parent.mkdir(parents=True)
            stable.write_text("{}")
            result = self.probe(home, "com.cmuxterm.app")
            self.assertEqual(result["fallback"], str(stable))
            self.assertIn(str(stable), result["doctor"])
            self.assertIn(str(stable), result["layout"])
            self.assertIn(str(stable), result["shortcuts"])

    def test_missing_dev_files_keep_the_primary_target_without_a_substitute(self):
        with tempfile.TemporaryDirectory() as directory:
            result = self.probe(directory, "com.cmuxterm.app.debug.empty")
            primary = str(Path(directory) / ".config/cmux-dev/empty/cmux.json")
            self.assertEqual(result["doctor"], [primary])
            self.assertEqual(result["layout"][0], primary)
            self.assertIsNone(result["fallback"])


if __name__ == "__main__":
    unittest.main()
