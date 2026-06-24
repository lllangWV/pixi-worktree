#!/usr/bin/env bash
set -euo pipefail

# Authenticate rattler-build to an S3 conda channel so worktree-warden can be
# published.
#
# rattler-build's S3 client does NOT use the AWS_* credential chain or ~/.aws
# profiles. It reads from its own auth store or S3_* env vars. This script
# registers credentials in that auth store (~/.rattler/credentials.json) for the
# channel(s) you pass, so `pixi run -e pkg publish` just works. Nothing secret is
# written into this repo.
#
# Channels: the channel set in pixi.toml ($CHANNEL) by default, plus any extra
# S3 URLs passed as arguments. Credentials come from an AWS profile if one is
# configured (default: AWS_PROFILE or "default"), otherwise you are prompted.

CHANNELS=("${CHANNEL:-}" "$@")
PROFILE="${AWS_PROFILE:-default}"

if ! command -v rattler-build &>/dev/null; then
  echo "Error: rattler-build not found. Run inside the pkg env, e.g.:" >&2
  echo "  pixi run -e pkg -- bash scripts/channel-auth.sh" >&2
  exit 1
fi

KEY_ID=""
SECRET=""
if command -v aws &>/dev/null; then
  KEY_ID="$(aws configure get aws_access_key_id --profile "$PROFILE" 2>/dev/null || true)"
  SECRET="$(aws configure get aws_secret_access_key --profile "$PROFILE" 2>/dev/null || true)"
fi

if [ -n "$KEY_ID" ] && [ -n "$SECRET" ]; then
  echo "Using credentials from AWS profile '$PROFILE'."
else
  echo "No usable AWS profile '$PROFILE' found; enter S3 credentials manually."
  read -rp "S3 Access Key ID: " KEY_ID
  read -rsp "S3 Secret Access Key: " SECRET
  echo
fi

if [ -z "$KEY_ID" ] || [ -z "$SECRET" ]; then
  echo "Error: no credentials provided." >&2
  exit 1
fi

for channel in "${CHANNELS[@]}"; do
  [ -n "$channel" ] || continue
  rattler-build auth login "$channel" \
    --s3-access-key-id "$KEY_ID" \
    --s3-secret-access-key "$SECRET"
  echo "Authenticated: $channel"
done

echo
echo "Done. Publish with: pixi run -e pkg publish"
