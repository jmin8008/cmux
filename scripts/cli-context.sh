#!/usr/bin/env bash
# Route development commands only to the jmin-context app and its settings.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export CMUX_TAG=jmin-context
exec "$ROOT_DIR/scripts/cmux-debug-cli.sh" "$@"
