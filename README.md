# pixi-worktree

Generic, tool-agnostic git-worktree provisioning. Installs a `post-checkout` hook
that fires whenever a worktree is created (Claude Code, t3code, or a plain
`git worktree add`) and:

1. **symlinks or copies** the gitignored, main-only files listed in `.worktreelinks`
   (secrets/creds that are never committed, e.g. `.env`, `.dvc/config.local`) from
   the main checkout into the new worktree; and
2. runs `.githooks/worktree-setup` if it is executable — your repo's own env
   install (pixi / npm / uv / cargo …).

Why a hook and not the tool's own feature? Git fires `post-checkout` for *every*
tool that creates a worktree via the git CLI, so one committed hook covers them
all. (Claude Code, notably, has no native post-create setup hook.)

It pairs especially well with **pixi**: add `pixi-worktree` to a project's
`[dependencies]` and the package's `activate.d` script auto-activates the hook on
every `pixi run` — including fresh clones — with no per-repo snippet.

## Install

Distributed as a `noarch` conda package:

```bash
pixi global install pixi-worktree
```

## Use

```bash
cd your-repo
pixi-worktree install   # writes .githooks/post-checkout, a starter .worktreelinks,
                          # a worktree-setup.sample, and sets core.hooksPath=.githooks
# edit .worktreelinks to list your gitignored main-only files
git add .githooks .worktreelinks && git commit -m "chore: worktree provisioning"
```

Then every `git worktree add` self-provisions. Commit `.githooks/` + `.worktreelinks`
so it travels to every clone and teammate.

### Activating on a fresh clone

`core.hooksPath` is never cloned (git won't auto-run hooks from a clone — RCE
protection), so each clone needs it set once. Options:

- **pixi repos (recommended): add `pixi-worktree` to `[dependencies]`.** The
  package ships an `activate.d` script that idempotently sets
  `core.hooksPath=.githooks` on env activation whenever a committed
  `.githooks/post-checkout` is present. So one dependency line + committed
  `.githooks` = the hook auto-activates on every `pixi run`, including fresh
  clones — no per-repo activation snippet.
- **anything:** `git config core.hooksPath .githooks`, or `pixi-worktree install` again.
- **machine-wide:** `pixi-worktree setup-global` drops the hook into
  `~/.git-template` so every future clone/init on that machine gets it automatically
  (it's a no-op in repos without a `.worktreelinks`).

> Note: the `activate.d` auto-activation works when `pixi-worktree` is a **project
> dependency** (its `activate.d` is sourced on env activation). `pixi global install
> pixi-worktree` gives you the `pixi-worktree` command everywhere but does not
> auto-activate in arbitrary repos.

## Commands

| Command | Effect |
|---------|--------|
| `pixi-worktree install [--repo DIR]` | Write the hook + starters, set `core.hooksPath` |
| `pixi-worktree update [--repo DIR]` | Refresh `.githooks/post-checkout` to this version |
| `pixi-worktree setup-global` | Install into `~/.git-template`, set global `init.templateDir` |
| `pixi-worktree version` | Print version |

## Notes

- **Symlink vs copy (`.worktreelinks` mode):** a bare `PATH` is **symlinked** —
  use for read-only shared state (secrets stay current, large channels aren't
  duplicated). `copy PATH` makes an **independent per-worktree copy** — use for
  mutable state like a lockfile, so a worktree's `pixi add` (or any re-solve)
  doesn't write through to the shared file and race other worktrees. Example:
  `copy pixi.lock`.
- On Windows, symlinks need Developer Mode/admin — this tool targets Linux/macOS
  (and Git Bash) first.
- The packaged hook is self-contained (embedded in the `pixi-worktree` script),
  so the conda package is a single file with no data-dir resolution.

## Building & publishing

See [`docs/publishing.md`](docs/publishing.md). The design rationale is documented
in [`docs/worktree-provisioning.md`](docs/worktree-provisioning.md).

## License

MIT — see [`LICENSE`](LICENSE).
