#!/usr/bin/env python3
"""Real CLI + fake providers: grouped Teams never allocate child cmux surfaces."""
from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

from claude_teams_test_utils import (
    FOCUSED_WORKSPACE_ID, canonical_managed_claude_shim_root, focused_cmux_server, resolve_cmux_cli,
)


def main() -> None:
    cli = resolve_cmux_cli()
    bun = shutil.which("bun")
    assert bun, "bun is required for the fixture app-server"
    with (
        tempfile.TemporaryDirectory(prefix="cmux-group-teams-") as temporary,
        canonical_managed_claude_shim_root() as (surface_id, wrapper_shim_bin),
    ):
        root = Path(temporary)
        # A real Teams launch needs the app-owned per-surface shim root (as an in-app terminal has).
        managed_claude = wrapper_shim_bin / "claude"
        bin_dir = root / "bin"
        bin_dir.mkdir()
        fake_claude = bin_dir / "claude"
        fake_claude.write_text('#!/bin/sh\nprintf "%s\\n" "$@" > "$FAKE_ARGV_LOG"\n')
        fake_claude.chmod(0o755)
        # The launcher executes this wrapper, which hands over to the provider (here the argv recorder).
        managed_claude.write_text(f'#!/bin/sh\nexec {fake_claude} "$@"\n')
        managed_claude.chmod(0o755)
        env = os.environ.copy()
        for key in list(env):
            if key.startswith(("CMUX_", "CLAUDE_", "ANTHROPIC_")) or key in {"TMUX", "TMUX_PANE", "NODE_OPTIONS"}:
                env.pop(key)
        env.update({"HOME": str(root), "PATH": f"{bin_dir}:{env.get('PATH', '/usr/bin:/bin')}",
                    "CMUX_WORKSPACE_ID": FOCUSED_WORKSPACE_ID, "CMUX_SURFACE_ID": surface_id,
                    "CMUX_CLAUDE_WRAPPER_SHIM": str(managed_claude),
                    "CMUX_CLAUDE_WRAPPER_SHIM_ROOT": str(wrapper_shim_bin), "TMPDIR": tempfile.gettempdir(),
                    "CMUX_BUNDLE_ID": "com.cmuxterm.app.debug.jmin.agents",
                    "CMUX_AGENT_WORKSPACE": "1", "CMUX_AGENT_WORKSPACE_DIRECTORY": str(root / "group"),
                    "FAKE_ARGV_LOG": str(root / "argv.txt")})
        with focused_cmux_server(root / "socket", surface_id=surface_id) as (socket, requests):
            result = subprocess.run([cli, "--socket", socket, "--password", "fixture", "claude-teams", "group fixture"],
                                    env=env, capture_output=True, text=True, timeout=15)
            assert result.returncode == 0, result.stderr
            argv = (root / "argv.txt").read_text().splitlines()
            assert argv == ["--teammate-mode", "in-process", "group fixture"], argv
            assert "surface.split" not in requests, requests
            # An explicit provider mode remains the caller's choice.
            result = subprocess.run([cli, "--socket", socket, "--password", "fixture", "claude-teams", "--teammate-mode", "tmux"],
                                    env=env, capture_output=True, text=True, timeout=15)
            assert result.returncode == 0, result.stderr
            assert (root / "argv.txt").read_text().splitlines() == ["--teammate-mode", "tmux"]

            fixture = Path(__file__).parent / "fixtures/agent-workspace-codex-server.ts"
            server = subprocess.Popen([bun, str(fixture)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            watcher = None
            try:
                assert server.stdout
                app_server = server.stdout.readline().strip()
                assert app_server.startswith("ws://127.0.0.1:"), app_server
                watcher = subprocess.Popen([cli, "--socket", socket, "--password", "fixture", "__codex-teams-watch",
                    "--workspace-id", FOCUSED_WORKSPACE_ID, "--surface-id", surface_id,
                    "--app-server-url", app_server, "--codex-path", "/usr/bin/false", "--max-auto-depth", "2"],
                    env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                snapshot_path = root / "group/codex" / f"{surface_id.lower()}.json"
                deadline = time.monotonic() + 10
                snapshot = None
                while time.monotonic() < deadline:
                    if snapshot_path.exists():
                        candidate = json.loads(snapshot_path.read_text())
                        if len(candidate.get("threads", [])) == 2:
                            snapshot = candidate
                            break
                    if watcher.poll() is not None:
                        raise AssertionError(watcher.communicate()[1])
                    time.sleep(0.05)
                assert snapshot, "watcher did not export real thread lineage"
                child = next(thread for thread in snapshot["threads"] if thread["id"] == "child-session-456")
                assert child["parentThreadID"] == "root-session-123", child
                assert child["label"] == "Reviewer", child
                assert child["status"] == "active", child
                assert snapshot["workspaceID"] == FOCUSED_WORKSPACE_ID
                time.sleep(0.2)  # Allow any accidental asynchronous pane attachment to arrive.
                assert "surface.split" not in requests, requests
            finally:
                for process in (watcher, server):
                    if process is not None:
                        process.terminate()
                        try:
                            process.wait(timeout=3)
                        except subprocess.TimeoutExpired:
                            process.kill()
                            process.wait()
    print("PASS: grouped Claude argv and Codex lineage without child surfaces")


if __name__ == "__main__":
    main()
