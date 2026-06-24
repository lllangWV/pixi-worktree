#!/usr/bin/env bash
set -euo pipefail

# Authenticate rattler-build to prefix.dev so pixi-worktree can be published.
#
# rattler-build's prefix.dev upload reads PREFIX_API_KEY or its own auth store at
# ~/.rattler/credentials.json. This script registers a token in that auth store
# so `pixi run -e pkg publish` works locally. Nothing secret is written into this
# repo.
#
# Hosts: the host from PREFIX_SERVER_URL by default, plus any extra hosts passed
# as arguments. PREFIX_API_KEY is used when set; otherwise you are prompted.

SERVER="${PREFIX_SERVER_URL:-https://prefix.dev}"
DEFAULT_HOST="${SERVER#http://}"
DEFAULT_HOST="${DEFAULT_HOST#https://}"
DEFAULT_HOST="${DEFAULT_HOST%%/*}"
HOSTS=("${DEFAULT_HOST}" "$@")

if ! command -v rattler-build &>/dev/null; then
  echo "Error: rattler-build not found. Run inside the pkg env, e.g.:" >&2
  echo "  pixi run -e pkg -- bash scripts/channel-auth.sh" >&2
  exit 1
fi

API_KEY="${PREFIX_API_KEY:-}"
if [ -z "$API_KEY" ]; then
  read -rsp "prefix.dev API key: " API_KEY
  echo
fi

if [ -z "$API_KEY" ]; then
  echo "Error: no API key provided." >&2
  exit 1
fi

for host in "${HOSTS[@]}"; do
  [ -n "$host" ] || continue
  rattler-build auth login "$host" --token "$API_KEY"
  echo "Authenticated: $host"
done

echo
echo "Done. Publish with: pixi run -e pkg publish"
