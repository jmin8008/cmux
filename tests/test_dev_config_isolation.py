#!/usr/bin/env python3
"""Exercise the real Swift path resolver without an Xcode app build."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class DevConfigIsolationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.build = tempfile.TemporaryDirectory(prefix="cmux-config-probe-")
        cls.binary = Path(cls.build.name) / "probe"
        main = Path(cls.build.name) / "main.swift"
        main.write_text('''import Foundation
// The password store only needs this unrelated settings constant in this harness.
struct SocketControlSettings { static let socketPasswordEnvKey = "CMUX_SOCKET_PASSWORD" }
let environment = ProcessInfo.processInfo.environment
let home = URL(fileURLWithPath: CommandLine.arguments[1])
let location = CmuxConfigLocation(home: home, bundleIdentifier: environment["CMUX_TEST_NATIVE_ID"], environment: environment)
if CommandLine.arguments.contains("--write") {
    try FileManager.default.createDirectory(at: location.userConfigFile.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("development".utf8).write(to: location.userConfigFile)
}
let passwordURL = SocketControlPasswordStore.defaultPasswordFileURL(fileManager: .default, configLocation: location)!
if CommandLine.arguments.contains("--password") {
    let store = SocketControlPasswordStore(environment: environment, fileURL: passwordURL,
        loadKeychainPassword: { fatalError("development accessed stable keychain") },
        deleteKeychainPassword: { fatalError("development deleted stable keychain") })
    precondition(store.configuredPassword(allowLazyKeychainFallback: true) == nil)
    let suite = "cmux-config-probe-" + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    store.migrateLegacyKeychainPasswordIfNeeded(defaults: defaults)
    defaults.removePersistentDomain(forName: suite)
    try store.savePassword("development-password")
    let savedPassword = try store.loadPassword()
    precondition(savedPassword == "development-password")
}
let appSupport = home.appendingPathComponent("Library/Application Support")
let identity = environment["CMUX_TEST_NATIVE_ID"] ?? environment["CMUX_BUNDLE_ID"]
let ghostty = CmuxGhosttyConfigPathResolver()
let data = try JSONSerialization.data(withJSONObject: [
    "primary": location.userConfigFile.path,
    "legacy": location.legacyFallbackFile.path,
    "fallback": location.legacyApplicationSupportFile?.path as Any? ?? NSNull(),
    "display": location.userConfigDisplayPath,
    "password": passwordURL.path,
    "ghostty": ghostty.loadConfigURLs(currentBundleIdentifier: identity, appSupportDirectory: appSupport).map(\\.path),
    "ghostty_editable": ghostty.activeOrEditableConfigURL(currentBundleIdentifier: identity, appSupportDirectory: appSupport).path
] as [String: Any])
print(String(decoding: data, as: UTF8.self))
''')
        settings = ROOT / "Packages/macOS/CmuxSettings/Sources/CmuxSettings"
        sources = [settings / "Stores/CmuxConfigLocation.swift",
                   settings / "SocketControl/CmuxStateDirectory.swift",
                   settings / "SocketControl/SocketControlPasswordStore.swift",
                   ROOT / "Packages/macOS/CmuxFoundation/Sources/CmuxFoundation/ConfigPaths/CmuxGhosttyConfigPathResolver.swift"]
        result = subprocess.run(["xcrun", "swiftc", *map(str, sources), str(main), "-o", str(cls.binary)], capture_output=True, text=True)
        if result.returncode:
            raise RuntimeError(result.stderr)

    @classmethod
    def tearDownClass(cls):
        cls.build.cleanup()

    def resolve(self, home, identity, write=False, native=None, password=False):
        env = dict(os.environ, CMUX_BUNDLE_ID=identity)
        env.pop("CMUX_TEST_NATIVE_ID", None)
        env.pop("CMUX_SOCKET_PASSWORD", None)
        if native is not None:
            env["CMUX_TEST_NATIVE_ID"] = native
        args = [str(self.binary), str(home)] + (["--write"] if write else []) + (["--password"] if password else [])
        return json.loads(subprocess.check_output(args, env=env, text=True))

    def test_tagged_writes_do_not_change_stable_settings(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            stable = home / ".config/cmux/cmux.json"
            stable.parent.mkdir(parents=True)
            stable.write_text("stable")
            result = self.resolve(home, "com.cmuxterm.app.debug.jmin", write=True)
            self.assertEqual(stable.read_text(), "stable")
            self.assertEqual(result["primary"], str(home / ".config/cmux-dev/jmin/cmux.json"))
            self.assertEqual(Path(result["primary"]).read_text(), "development")
            self.assertEqual(result["legacy"], str(home / ".config/cmux-dev/jmin/settings.json"))
            self.assertIsNone(result["fallback"])
            self.assertEqual(result["display"], "~/.config/cmux-dev/jmin/cmux.json")

    def test_stable_settings_keep_their_location(self):
        with tempfile.TemporaryDirectory() as directory:
            result = self.resolve(directory, "com.cmuxterm.app")
            self.assertEqual(result["primary"], str(Path(directory) / ".config/cmux/cmux.json"))

    def test_native_identity_overrides_inherited_terminal(self):
        with tempfile.TemporaryDirectory() as directory:
            stable = self.resolve(directory, "com.cmuxterm.app.debug.jmin", native="com.cmuxterm.app")
            dev = self.resolve(directory, "com.cmuxterm.app", native="com.cmuxterm.app.debug.jmin")
            self.assertEqual(stable["primary"], str(Path(directory) / ".config/cmux/cmux.json"))
            self.assertEqual(dev["primary"], str(Path(directory) / ".config/cmux-dev/jmin/cmux.json"))

    def test_tags_have_separate_settings_and_legacy_paths(self):
        with tempfile.TemporaryDirectory() as directory:
            first = self.resolve(directory, "com.cmuxterm.app.debug.jmin")
            second = self.resolve(directory, "com.cmuxterm.app.debug.other")
            self.assertNotEqual(first["primary"], second["primary"])
            self.assertNotEqual(first["legacy"], second["legacy"])

    def test_malformed_tag_stays_under_development_root(self):
        with tempfile.TemporaryDirectory() as directory:
            result = self.resolve(directory, "com.cmuxterm.app.debug.../../../cmux")
            self.assertTrue(Path(result["primary"]).resolve().is_relative_to(Path(directory).resolve() / ".config/cmux-dev"))

    def test_development_password_does_not_read_or_migrate_stable_secret(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            stable = home / ".local/state/cmux/socket-control-password"
            stable.parent.mkdir(parents=True)
            stable.write_text("stable-password")
            result = self.resolve(home, "com.cmuxterm.app.debug.jmin", password=True)
            self.assertEqual(stable.read_text(), "stable-password")
            self.assertEqual(Path(result["password"]).read_text(), "development-password")
            self.assertEqual(Path(result["password"]).stat().st_mode & 0o777, 0o600)

    def test_ghostty_development_config_does_not_fall_back_to_stable(self):
        with tempfile.TemporaryDirectory() as directory:
            support = Path(directory) / "Library/Application Support"
            stable = support / "com.cmuxterm.app/config.ghostty"
            stable.parent.mkdir(parents=True)
            stable.write_text("font-size = 13\n")
            dev = self.resolve(directory, "com.cmuxterm.app.debug.jmin")
            self.assertEqual(dev["ghostty"], [])
            self.assertEqual(dev["ghostty_editable"], str(support / "com.cmuxterm.app.debug.jmin/config.ghostty"))
            nightly = self.resolve(directory, "com.cmuxterm.app.nightly")
            self.assertEqual(nightly["ghostty"], [str(stable)])

    def test_settings_helper_agrees_with_swift_cli(self):
        helper = ROOT / "skills/cmux-settings/scripts/cmux-settings"
        for identity in ("com.cmuxterm.app", "com.cmuxterm.app.debug.jmin", "com.cmuxterm.app.debug"):
            with self.subTest(identity=identity):
                result = subprocess.check_output(["python3", str(helper), "path"], env=dict(os.environ, CMUX_BUNDLE_ID=identity), text=True).strip()
                self.assertEqual(result, self.resolve(Path.home(), identity)["primary"])

    def test_build_wrapper_pins_identity_and_preserves_build_options(self):
        with tempfile.TemporaryDirectory() as directory:
            scripts = Path(directory) / "scripts"
            scripts.mkdir()
            shutil.copy(ROOT / "scripts/dev-jmin.sh", scripts)
            reload = scripts / "reload.sh"
            reload.write_text('#!/bin/bash\nprintf "%s\\n" "$CMUX_DEV_BACKEND_MODE" "$@"\n')
            reload.chmod(0o755)
            result = subprocess.check_output([str(scripts / "dev-jmin.sh"), "--build-only"], text=True)
            self.assertEqual(result.splitlines(), ["local", "--tag", "jmin", "--build-only"])
            for option in ("--tag", "--name=cmux", "--bundle-id=com.cmuxterm.app"):
                rejected = subprocess.run([str(scripts / "dev-jmin.sh"), option], capture_output=True)
                self.assertEqual(rejected.returncode, 2)


if __name__ == "__main__":
    unittest.main()
