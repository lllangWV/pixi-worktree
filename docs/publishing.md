# Publishing worktree-warden to a conda channel

`worktree-warden` builds with `rattler-build` and publishes to an S3-backed conda
channel. The recipe lives in `recipe/` and builds from the local working tree
(`source: path: ..`) — no clone, no Git credentials.

## Configure the channel

Set the destination in `pixi.toml` under `[feature.pkg.activation.env]`:

```toml
CHANNEL = "s3://my-conda-channel"
REGION = "us-east-1"
ENDPOINT_URL = "https://s3.us-east-1.amazonaws.com"
```

(Replace the `CHANGEME` placeholder.) You can also override any of these per
invocation, e.g. `CHANNEL=s3://my-staging pixi run -e pkg publish`.

## One-time: authenticate

`rattler-build`'s S3 client does **not** use the `AWS_*` credential chain or
`~/.aws` profiles. It reads from its own auth store or `S3_*` env vars. Register
credentials once:

```bash
pixi run -e pkg channel-auth
```

This pulls credentials from your AWS profile if present (`AWS_PROFILE`, default
`default`), otherwise prompts, and stores them for `$CHANNEL` in
`~/.rattler/credentials.json`. Nothing secret is written to the repo. Pass extra
channel URLs as arguments to authenticate more than one.

Equivalent manual form:

```bash
rattler-build auth login s3://my-conda-channel \
  --s3-access-key-id "$(aws configure get aws_access_key_id)" \
  --s3-secret-access-key "$(aws configure get aws_secret_access_key)"
```

## Build and publish

```bash
pixi run -e pkg build      # build only -> output/noarch/
pixi run -e pkg publish    # build, then upload to $CHANNEL
```

The upload passes `--region` and `--endpoint-url` (both required by
rattler-build's `upload s3`).

## Releasing a new version

1. Bump `WORKTREE_WARDEN_VERSION` in the `worktree-warden` script **and**
   `context.version` in `recipe/recipe.yaml` (reset the build `number` to 0). A
   rebuild of the *same* version+build is a no-op the channel skips — a real
   release needs a version or build-number bump.
2. Tag the source: `git tag vX.Y.Z`.
3. `pixi run -e pkg publish`.
