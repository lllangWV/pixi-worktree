# Shipped by the pixi-worktree conda package to $PREFIX/etc/conda/activate.d/.
# pixi/conda source this on every environment activation. It idempotently
# activates a repo's committed worktree hooks so that adding `pixi-worktree` to
# a project's [dependencies] is enough to enable provisioning on every clone.
#
# Sourced into the user's shell — so NO `set -e/-u`, NO `exit`/`return`, and stay
# quiet. Only acts when a committed .githooks/post-checkout is present.
if command -v git >/dev/null 2>&1; then
  _pwt_root="${PIXI_PROJECT_ROOT:-}"
  [ -n "${_pwt_root}" ] || _pwt_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -n "${_pwt_root}" ] && [ -f "${_pwt_root}/.githooks/post-checkout" ]; then
    if [ "$(git -C "${_pwt_root}" config --local --get core.hooksPath 2>/dev/null)" != ".githooks" ]; then
      git -C "${_pwt_root}" config --local core.hooksPath .githooks 2>/dev/null || true
    fi
  fi
  unset _pwt_root
fi
