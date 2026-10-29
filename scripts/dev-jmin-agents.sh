#!/usr/bin/env bash
# Build or launch this fork using a fixed identity, separate from installed cmux.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
for arg in "$@"; do
  case "$arg" in
    --tag|--tag=*|--name|--name=*|--bundle-id|--bundle-id=*)
      echo "dev-jmin-agents.sh fixes the jmin-agents identity; use reload.sh directly for another tag." >&2
      exit 2
      ;;
  esac
done

cd "$ROOT_DIR"
export CMUX_DEV_BACKEND_MODE=local
# Enable the existing gated entrypoint only for this isolated development app.
defaults write com.cmuxterm.app.debug.jmin.agents cmux.flags.override.agent-chat-ui-enabled-release -bool true
BUN_PATH="$(command -v bun)"
python3 - "$ROOT_DIR" "$BUN_PATH" <<'PYCONFIG'
import json
import os
import pathlib
import shlex
import sys
root = pathlib.Path(sys.argv[1])
path = pathlib.Path.home() / ".config/cmux-dev/jmin.agents/cmux.json"
config = json.loads(path.read_text()) if path.exists() else {}
chat = config.setdefault("agentChat", {})
if "url" not in chat and "startCommand" not in chat:
    chat["startCommand"] = "exec " + shlex.join([sys.argv[2], str(root / "agent-chat/server.ts")])
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(".json.tmp")
    temporary.write_text(json.dumps(config, ensure_ascii=False, indent=2) + "\n")
    os.replace(temporary, path)
PYCONFIG
exec ./scripts/reload.sh --tag jmin-agents --no-global-cli-links "$@"
