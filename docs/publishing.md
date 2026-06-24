# Publishing pixi-worktree to a conda channel

`pixi-worktree` builds with `rattler-build` and publishes to a prefix.dev conda
channel. The recipe lives in `recipe/` and builds from the local working tree
(`source: path: ..`) -- no clone, no Git credentials.

## Configure the channel

Set the destination in `pixi.toml` under `[feature.pkg.activation.env]`:

```toml
PREFIX_CHANNEL = "wv-forge"
PREFIX_SERVER_URL = "https://prefix.dev"
```

You can override the channel per invocation, e.g.
`PREFIX_CHANNEL=my-staging pixi run -e pkg publish`.

## GitHub Actions publishing

The workflow in `.github/workflows/publish.yml` publishes to the `wv-forge`
prefix.dev channel when you push a `v*` tag or run it manually from GitHub
Actions.

Add the API key as a GitHub repository secret:

1. Go to the GitHub repository.
2. Open **Settings** -> **Secrets and variables** -> **Actions**.
3. Click **New repository secret**.
4. Name it `PREFIX_API_KEY`.
5. Paste the prefix.dev API key as the value.

```text
PREFIX_API_KEY
```

The workflow maps that secret to the `PREFIX_API_KEY` environment variable that
`rattler-build upload prefix` understands. No credentials are stored in the repo.

## One-time: authenticate

For local publishing, `rattler-build` reads `PREFIX_API_KEY` or its own auth
store at `~/.rattler/credentials.json`. Register credentials once:

```bash
pixi run -e pkg channel-auth
```

This prompts for a prefix.dev API key and stores it for `prefix.dev` in
`~/.rattler/credentials.json`. Nothing secret is written to the repo.

Equivalent manual form:

```bash
rattler-build auth login prefix.dev --token "$PREFIX_API_KEY"
```

## Build and publish

```bash
pixi run -e pkg build      # build only -> output/noarch/
pixi run -e pkg publish    # build, then upload to $PREFIX_CHANNEL
```

The publish task uses `rattler-build upload prefix --skip-existing`.

## Releasing a new version

1. Bump `PIXI_WORKTREE_VERSION` in the `pixi-worktree` script **and**
   `context.version` in `recipe/recipe.yaml` (reset the build `number` to 0). A
   rebuild of the *same* version+build is a no-op the channel skips — a real
   release needs a version or build-number bump.
2. Tag the source: `git tag vX.Y.Z`.
3. Push the tag: `git push origin vX.Y.Z`.
4. The `Publish` GitHub Action builds the package and uploads it to the
   `wv-forge` prefix.dev channel.

For a local publish, run `pixi run -e pkg publish` after authenticating with
`pixi run -e pkg channel-auth`.
