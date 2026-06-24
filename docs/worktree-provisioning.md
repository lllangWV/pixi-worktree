# Git Worktree Provisioning (`pixi-worktree`)

A design + architecture report for the tool-agnostic git-worktree provisioning
system distributed as the `pixi-worktree` conda package.

- **Source / recipe:** this repo (`pixi-worktree`, builds from the local tree)
- **Channel:** a prefix.dev conda channel (configurable; see `docs/publishing.md`)

---

## 1. The problem

Engineers run multiple AI coding agents (Claude Code, t3code) in parallel, each in
its own **git worktree**. A worktree shares the repo's object store but gets a
fresh working directory, so anything gitignored — `.env`, credentials, the pixi
environment — is **not** present in a new worktree. Each tool also provisions
worktrees differently, so setup was inconsistent and manual.

Goal: a **single, tool-agnostic** way to provision a fresh worktree (bring in the
gitignored config it needs, warm its environment) that works no matter which tool
created it, requires no per-tool configuration, and survives cloning to another
machine.

## 2. Key findings & design decisions

### 2.1 git's `post-checkout` hook is the tool-agnostic seam

`git worktree add` fires the native `post-checkout` hook (unless `--no-checkout`).
Any tool that creates worktrees via the git CLI inherits it. **Verified by binary
inspection and execution:**

| Tool | How it creates worktrees | `post-checkout` fires? |
|------|--------------------------|------------------------|
| t3code | `["worktree","add", …]` via git CLI, no `--no-checkout` | **Yes** |
| Claude Code | `git worktree add`; adds `--no-checkout` **only** if `worktree.sparsePaths` is set | **Yes** (by default) |
| plain `git worktree add` | — | **Yes** |

So one committed hook covers every tool. (Notably, Claude Code has **no** native
post-create setup hook — `WorktreeCreate` *replaces* creation logic and disables
`.worktreeinclude`; it's an open feature request. The git hook sidesteps that.)

### 2.2 Hook guard: fire only on worktree creation

`post-checkout` also fires on ordinary branch switches and `git clone`. The hook
runs its logic only when **both**:

- the previous HEAD is the null ref (`000…0`) — true for `worktree add` / clone; and
- it is a **linked** worktree — `git rev-parse --git-dir` ≠ `--git-common-dir`.

This cleanly isolates "a worktree was just created" from every other checkout event.

### 2.3 Two jobs — and only one is the hook's to do

1. **Symlink gitignored, main-only files** (`.env`, `.dvc/config.local`, …). These
   are never committed, so a fresh worktree can't get them any other way. The hook
   symlinks (not copies) them from the main checkout, so a rotated secret stays
   current in every worktree. *This is the hook's irreplaceable job.*
2. **Pre-warm the environment.** `pixi run`/`pixi shell` already auto-installs the
   env on first use, so a `pixi install` in the hook is **redundant** — kept only as
   an optional pre-warm (worktree is "ready" immediately rather than on first run).

### 2.4 Do **not** symlink the environment (`.pixi`)

Conda environments are not relocatable — the absolute prefix is baked into files at
install time. Symlinking `.pixi` makes `PIXI_PROJECT_ROOT` and `CONDA_PREFIX`
diverge and triggers lockfile-hash revalidation. Instead, each worktree gets its
own `.pixi`, materialized **cheaply from the shared rattler package cache** via
hard links / reflinks (copy-on-write), not copies.

**Filesystem caveat (measured on the dev box):** the repo (`/`) and the rattler
cache (`/home`) are different btrfs subvolumes, so **hardlinks fail across them**
(`Invalid cross-device link`). However **reflinks succeed across subvolumes on the
same btrfs** (verified: `cp --reflink=always` `/home`→`/`), and pixi prefers
reflinks — so per-worktree installs are CoW-cheap, no copy penalty. Moving the repo
would only enable hardlinks (unneeded) while breaking `.pixi`. → left as-is.

### 2.5 Activation does not travel with a clone

git never runs or activates hooks from a clone (RCE protection): `.git/hooks` isn't
cloned and `core.hooksPath` is local config that isn't cloned either. So activation
needs a one-time trigger per clone. Two portability decisions:

- **Relative `core.hooksPath = .githooks`** — machine-independent, and resolves to
  each checkout's own committed copy.
- **Auto-activation via the package** — see §4.3.

## 3. Cross-ecosystem context

The universal principle (confirmed across pnpm, bun, yarn-PnP, uv, conda/pixi,
cargo, Go, Gradle, Maven, ccache, Bazel): **the dependency download cache is global
and shared** (worktrees are free for deps), while the **materialized environment is
per-checkout** (the only real cost). Mechanisms people use, ranked:

1. **Hardlink from a content-addressable store** (pnpm/uv/pixi) — best default.
2. **Reflink / copy-on-write** (uv defaults to `clone`; worktrunk) — instant, ~0 disk.
3. **Symlink the env** — cheapest but breaks tooling and gives no isolation;
   widely warned against.
4. Containers / no-`node_modules` (yarn PnP) — different model.

Dedicated agent tools converge on a "setup script after worktree create" feature
(Conductor's *Setup script*, worktrunk's `post-start`, Cursor/Devin/OpenHands
install commands). `pixi-worktree` is the git-native, tool-agnostic equivalent. No
tool auto-propagates a *new* dependency added mid-task; per-worktree lockfile+env
isolation (what pixi gives) is the safe model.

## 4. The `pixi-worktree` tool

A single, self-contained bash CLI. The canonical generic hook is **embedded** in
the script (so the conda package is one file with no data-dir resolution).

### 4.1 What it installs into a repo

| File | Tracked? | Role |
|------|----------|------|
| `.githooks/post-checkout` | yes | generic provisioner (guards + symlink + setup) |
| `.worktreelinks` | yes | one repo-relative path per line: gitignored main-only files to symlink/copy |
| `.githooks/worktree-setup` | yes (opt-in; `.sample` until enabled) | repo env install (pixi/npm/uv/…); run if executable |
| `core.hooksPath = .githooks` | local config | activates the hook |

The generic hook reads `.worktreelinks` and runs `.githooks/worktree-setup` from
the **main checkout**, so it works before anything is committed and regardless of
which checkout invoked `git worktree add`.

### 4.2 Commands

| Command | Effect |
|---------|--------|
| `pixi-worktree install [--repo DIR]` | write the hook + starters, set `core.hooksPath` |
| `pixi-worktree update [--repo DIR]` | refresh `.githooks/post-checkout` to this version |
| `pixi-worktree setup-global` | install into `~/.git-template`, set global `init.templateDir` |
| `pixi-worktree version` | print version |

### 4.3 Auto-activation via `activate.d` (the key to "just add it as a dependency")

Installing the package only puts the `pixi-worktree` CLI on PATH — it does **not**
touch any repo. To make a dependency entry *enable* the hook, the package ships
`etc/conda/activate.d/pixi-worktree.sh`, which pixi/conda source on env
activation. It idempotently sets `core.hooksPath=.githooks` whenever a committed
`.githooks/post-checkout` is present.

Result:

> **Add `pixi-worktree` to a project's `[dependencies]` + commit `.githooks/`** ⇒
> the hook auto-activates on every `pixi run`, including fresh clones, with **no
> per-repo activation snippet**.

Caveat: this works for **project dependencies** (env activation sources `activate.d`).
`pixi global install pixi-worktree` gives the command everywhere but does not
auto-activate arbitrary repos.

### 4.4 Usage

```bash
# author, once
cd your-repo
pixi-worktree install          # writes hook + starters, sets core.hooksPath
$EDITOR .worktreelinks           # list gitignored main-only files (.env, .dvc/config.local, …)
# (optional) cp .githooks/worktree-setup.sample .githooks/worktree-setup; chmod +x; edit
pixi add pixi-worktree         # so it auto-activates on every clone (pixi repos)
git add .githooks .worktreelinks pixi.toml && git commit -m "chore: worktree provisioning"
```

After that, every `git worktree add` self-provisions, on every clone and for every
teammate.

## 5. Distribution architecture

This repo is **self-contained**: the source (`pixi-worktree`,
`activate.d/pixi-worktree.sh`), the recipe (`recipe/recipe.yaml`), and the
build/publish tasks (`pixi.toml`, `scripts/channel-auth.sh`) all live together. The
recipe builds from the local working tree (`source: path: ..`) — no separate
feedstock, no clone, no git credentials at build time.

### 5.1 The package

`noarch: generic` — a shell CLI, so it sidesteps any per-platform build matrix:
builds locally in seconds. Run deps: `git`, `bash`.

### 5.2 Release flow

1. Run `pixi run publish` and choose the patch/minor/major/no-change release.
2. For version bumps, the script updates both version files, resets the recipe
   build `number` to 0, builds, commits, tags `vX.Y.Z`, and pushes the branch
   and tag.
3. The `Publish` GitHub Action uploads to the `wv-forge` prefix.dev channel.
4. Consume: `pixi global install pixi-worktree`, or add `pixi-worktree` to a
   project's deps.

## 6. Verification log

| Check | Result |
|-------|--------|
| `post-checkout` fires for t3code, Claude Code (`isolation: worktree`), bare `git worktree add` | ✅ |
| `--no-checkout` does **not** fire it (the sparsePaths case) | ✅ confirmed |
| Cross-clone behavior: fresh clone has `core.hooksPath` unset; activation re-enables | ✅ |
| Cross-subvolume reflink works on btrfs; hardlink fails | ✅ measured |
| pixi sources package `activate.d` on activation | ✅ (pixi docs) |
| `install` → hook fires, symlinks gitignored `.env`, runs `worktree-setup` | ✅ |
| `rattler-build` build (`noarch`), recipe tests pass | ✅ |
| **dep in `[dependencies]` + committed `.githooks` + `core.hooksPath` unset → `pixi run` auto-sets it** | ✅ |
