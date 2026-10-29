#!/usr/bin/env python3
"""Keep a running tag's lazy Foundation resources intact during rebuild cleanup."""

import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


def cleanup_functions():
    source = (ROOT / "scripts/reload.sh").read_text()
    return "\n".join(
        re.search(rf"^{name}\(\) \{{\n.*?^\}}", source, re.M | re.S).group()
        for name in ("remove_app_bundle_output", "cleanup_incomplete_xcodebuild_outputs")
    )


@unittest.skipUnless(sys.platform == "darwin" and shutil.which("xcrun"), "requires macOS Foundation")
class LiveBundleResourcesTests(unittest.TestCase):
    def test_running_tag_can_load_resource_after_normal_and_build_only_cleanup(self):
        with tempfile.TemporaryDirectory(prefix="cmux-reload-resource-test-") as temporary:
            root = Path(temporary)
            source = root / "main.swift"
            source.write_text('''import Foundation
FileHandle.standardOutput.write(Data("ready\\n".utf8))
_ = readLine()
guard let resources = Bundle.main.resourceURL,
      let bundle = Bundle(url: resources.appendingPathComponent("Fixture_Fixture.bundle")),
      let url = bundle.url(forResource: "marker", withExtension: "txt"),
      let value = try? String(contentsOf: url, encoding: .utf8) else { exit(78) }
FileHandle.standardOutput.write(Data(value.utf8))
''')
            binary = root / "Probe"
            subprocess.run(["xcrun", "swiftc", str(source), "-o", str(binary)], check=True, capture_output=True)
            for build_only in (False, True):
                with self.subTest(build_only=build_only):
                    products = root / str(build_only) / "Products"
                    tagged = products / "cmux DEV probe.app"
                    sibling = products / "cmux DEV other.app"
                    untagged = products / "cmux DEV.app"
                    staging = products / ".cmux DEV probe.reload-1.app"
                    executable = tagged / "Contents/MacOS/Probe"
                    executable.parent.mkdir(parents=True)
                    shutil.copy2(binary, executable)
                    info = {"CFBundleExecutable": "Probe", "CFBundleIdentifier": "com.cmux.test.probe", "CFBundlePackageType": "APPL"}
                    (tagged / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
                    bundle = tagged / "Contents/Resources/Fixture_Fixture.bundle/Contents"
                    (bundle / "Resources").mkdir(parents=True)
                    (bundle / "Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": "com.cmux.test.probe", "CFBundlePackageType": "BNDL"}))
                    (bundle / "Resources/marker.txt").write_text("resource survived\n")
                    for path in (sibling, untagged, staging):
                        path.mkdir()
                    process = subprocess.Popen([str(executable)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                    try:
                        self.assertEqual(process.stdout.readline(), "ready\n")
                        environment = dict(os.environ, BUILD_ONLY=str(int(build_only)),
                            BUILD_PRODUCTS_DEBUG_DIR=str(products), XCODEBUILD_CLEANED_OUTPUTS="0",
                            XCODEBUILD_SOURCE_APP_PATH=str(untagged), XCODEBUILD_TAG_APP_PATH=str(tagged),
                            TAG_APP_STAGING_PATH=str(staging))
                        subprocess.run(["bash", "-c", cleanup_functions() + "\ncleanup_incomplete_xcodebuild_outputs"],
                            env=environment, check=True, capture_output=True, text=True)
                        stdout, stderr = process.communicate("load\n", timeout=5)
                        self.assertEqual(process.returncode, 0, "cleanup removed the running tag's lazy resources: " + stderr)
                        self.assertEqual(stdout, "resource survived\n")
                        self.assertTrue(sibling.is_dir(), "shared DerivedData sibling tag must survive")
                        self.assertFalse(untagged.exists())
                        self.assertFalse(staging.exists())
                    finally:
                        if process.poll() is None:
                            process.kill()
                            process.communicate()


if __name__ == "__main__":
    unittest.main()
