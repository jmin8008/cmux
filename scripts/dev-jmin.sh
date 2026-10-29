#!/usr/bin/env bash
# Build or launch this fork using a fixed identity, separate from installed cmux.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
for arg in "$@"; do
  case "$arg" in
    --tag|--tag=*|--name|--name=*|--bundle-id|--bundle-id=*)
      echo "dev-jmin.sh fixes the jmin identity; use reload.sh directly for another tag." >&2
      exit 2
      ;;
  esac
done

cd "$ROOT_DIR"
export CMUX_DEV_BACKEND_MODE=local
exec ./scripts/reload.sh --tag jmin "$@"
