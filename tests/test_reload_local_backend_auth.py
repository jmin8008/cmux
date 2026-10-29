#!/usr/bin/env python3
"""Exercise reload's real launch preflight without building or reading credentials."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ReloadLocalBackendAuthTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="cmux-reload-local-auth-")
        self.addCleanup(self.directory.cleanup)
        self.checkout = Path(self.directory.name)
        self.scripts = self.checkout / "scripts"
        library = self.scripts / "lib"
        library.mkdir(parents=True)
        shutil.copy2(ROOT / "scripts/reload.sh", self.scripts / "reload.sh")
        (library / "mobile-attach.sh").symlink_to(ROOT / "scripts/lib/mobile-attach.sh")
        # Keep real argument parsing and auth control flow. These rejecting
        # seams prove validation is still invoked without loading user secrets.
        (library / "dev-secrets.sh").write_text(
            "cmux_dev_secrets_validate_file() { echo file-validation-invoked >&2; return 72; }\n"
            "cmux_dev_secrets_load() { echo profile-validation-invoked >&2; return 73; }\n"
        )
        # The real script takes this lock after auth validation but before tag
        # cleanup, backend resolution, builds, or app lifecycle operations.
        (library / "tagged-reload-lock.py").write_text(
            "print('auth-preflight-passed')\nraise SystemExit(90)\n"
        )
        self.environment = {key: value for key, value in os.environ.items() if not key.startswith("CMUX_")}

    def run_reload(self, mode=None, args=(), **overrides):
        environment = self.environment | overrides
        if mode is not None:
            environment["CMUX_DEV_BACKEND_MODE"] = mode
        return subprocess.run(
            ["bash", str(self.scripts / "reload.sh"), "--tag", "local-auth-probe", "--launch", *args],
            cwd=self.checkout, env=environment, capture_output=True, text=True, timeout=10,
        )

    def assert_auth_required(self, result):
        self.assertNotEqual(result.returncode, 90, result.stdout + result.stderr)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("auth-preflight-passed", result.stdout)

    def test_explicit_unoverridden_local_mode_needs_no_implicit_profile(self):
        result = self.run_reload("local")
        self.assertEqual(result.returncode, 90, result.stdout + result.stderr)
        self.assertIn("auth-preflight-passed", result.stdout)
        self.assertNotIn("validation-invoked", result.stderr)

    def test_default_remote_production_and_unknown_modes_keep_auth_gate(self):
        for mode, args in [(None, ()), ("remote", ()), ("local", ("--prod-auth",)), ("invalid", ())]:
            with self.subTest(mode=mode, args=args):
                self.assert_auth_required(self.run_reload(mode, args))

    def test_local_mode_with_endpoint_override_keeps_auth_gate(self):
        for key in ["CMUX_DEV_API_BASE_URL", "CMUX_DEV_BACKEND_URL"]:
            with self.subTest(override=key):
                self.assert_auth_required(self.run_reload("local", **{key: "https://example.invalid"}))

    def test_explicit_profiles_still_run_the_credential_loader(self):
        for profile in ["personal", "agent"]:
            with self.subTest(profile=profile):
                result = self.run_reload("local", ("--auth-profile", profile))
                self.assertEqual(result.returncode, 73, result.stdout + result.stderr)
                self.assertIn("profile-validation-invoked", result.stderr)

    def test_loader_failure_cannot_reuse_an_inherited_account(self):
        result = self.run_reload("local", ("--auth-profile", "personal"),
                                 CMUX_DEV_AUTH_ACCOUNT="stale@example.invalid")
        self.assertEqual(result.returncode, 73, result.stdout + result.stderr)
        self.assertIn("profile-validation-invoked", result.stderr)
        self.assertNotIn("auth-preflight-passed", result.stdout)

    def test_invalid_explicit_profile_is_rejected(self):
        result = self.run_reload("local", ("--auth-profile", "invalid"))
        self.assert_auth_required(result)
        self.assertIn("--auth-profile must be personal or agent", result.stderr)

    def test_explicit_credentials_file_is_still_validated(self):
        credentials = self.checkout / "fixture.env"
        credentials.write_text("# no credential values are needed by this rejecting seam\n")
        for extra in [(), ("--auth-profile", "agent")]:
            with self.subTest(extra=extra):
                result = self.run_reload("local", ("--credentials-file", str(credentials), *extra))
                self.assertEqual(result.returncode, 72, result.stdout + result.stderr)
                self.assertIn("file-validation-invoked", result.stderr)

    def test_local_launch_environment_drops_inherited_auth_values(self):
        source = (ROOT / "scripts/reload.sh").read_text()
        clean_start = source.index("  OPEN_CLEAN_ENV=(")
        clean_end = source.index("\n  )", clean_start) + len("\n  )")
        launch_start = source.index('  LAUNCH_AUTH_CALLBACK_SCHEME="cmux-dev"')
        launch_end = source.index("\n  LAUNCH_CMD=()", launch_start)
        args_start = source.index("    TAG_LAUNCH_PROGRAM_ARGUMENTS=(")
        args_end_marker = '    TAG_LAUNCH_PROGRAM_ARGUMENTS+=("${TAG_LAUNCH_ENV[@]}" "$APP_EXECUTABLE")'
        args_end = source.index(args_end_marker, args_start) + len(args_end_marker)
        setup = """
set -e
PROD_AUTH=0
AUTH_PROFILE=""
AUTH_CREDENTIALS_FILE=""
TAG_SLUG=local-auth-probe
BUNDLE_ID=com.cmuxterm.app.debug.local.auth.probe
APP_EXECUTABLE=/usr/bin/env
CMUX_AUTH_WWW_ORIGIN_VALUE=http://localhost:4123
CMUX_DEV_API_BASE_URL_VALUE=http://localhost:4123
"""
        inherited = {
            "CMUX_AUTH_ENVIRONMENT": "production", "CMUX_AUTH_CREDENTIALS_FILE": "/fixture/credentials.env",
            "CMUX_DEV_AUTH_PROFILE": "personal", "CMUX_DEV_AUTH_ACCOUNT": "stale@example.invalid",
            "CMUX_DEV_AUTH_REPLACE_SESSION": "1", "CMUX_DOGFOOD_STACK_EMAIL": "fixture@example.invalid",
            "CMUX_DOGFOOD_STACK_PASSWORD": "fixture-not-a-secret", "CMUX_UITEST_STACK_EMAIL": "agent@example.invalid",
            "CMUX_UITEST_STACK_PASSWORD": "fixture-not-a-secret",
        }
        for label, suffix in [
            ("tagged", source[args_start:args_end] + '\n"${TAG_LAUNCH_PROGRAM_ARGUMENTS[@]}"'),
            ("clean-launch", source[clean_start:clean_end] + '\n"${OPEN_CLEAN_ENV[@]}" "${TAG_LAUNCH_ENV[@]}" /usr/bin/env'),
        ]:
            with self.subTest(launch=label):
                result = subprocess.run(
                    ["bash", "-c", setup + source[launch_start:launch_end] + suffix],
                    env=self.environment | inherited, capture_output=True, text=True, timeout=10,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                values = dict(line.split("=", 1) for line in result.stdout.splitlines() if "=" in line)
                self.assertTrue(set(inherited).isdisjoint(values), "inherited auth key reached the launch environment")
                self.assertEqual(values["CMUX_AUTH_WWW_ORIGIN"], "http://localhost:4123")
                self.assertEqual(values["CMUX_API_BASE_URL"], "http://localhost:4123")

    def test_explicit_auth_file_with_real_helper_keeps_validation_and_success(self):
        shutil.copy2(ROOT / "scripts/lib/dev-secrets.sh", self.scripts / "lib/dev-secrets.sh")
        credentials = self.checkout / "explicit-fixture.env"
        credentials.write_text("CMUX_DOGFOOD_STACK_EMAIL=fixture@example.invalid\n"
                               "CMUX_DOGFOOD_STACK_PASSWORD=fixture-not-a-secret\n")
        credentials.chmod(0o600)
        args = ("--credentials-file", str(credentials))
        result = self.run_reload("local", args)
        self.assertEqual(result.returncode, 90, result.stdout + result.stderr)
        self.assertIn("auth-preflight-passed", result.stdout)
        self.assertNotIn("fixture-not-a-secret", result.stdout + result.stderr)

        result = self.run_reload("local", (*args, "--expected-account", "other@example.invalid"))
        self.assert_auth_required(result)
        self.assertIn("expected auth account", result.stderr)

        credentials.chmod(0o644)
        result = self.run_reload("local", args)
        self.assert_auth_required(result)
        self.assertIn("must not grant group or world permissions", result.stderr)

        credentials.chmod(0o600)
        credentials.write_text("CMUX_DOGFOOD_STACK_EMAIL=fixture@example.invalid\n")
        result = self.run_reload("local", args, CMUX_DEV_AUTH_ACCOUNT="stale@example.invalid")
        self.assert_auth_required(result)
        self.assertIn("personal auth profile requires complete", result.stderr)

    def test_expected_account_does_not_become_an_unauthenticated_launch(self):
        self.assert_auth_required(self.run_reload("local", ("--expected-account", "fixture@example.invalid")))


if __name__ == "__main__":
    unittest.main()
