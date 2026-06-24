# Shipped by the worktree-warden conda package to $PREFIX/etc/conda/activate.d/.
# pixi/conda source this on every environment activation. It idempotently
# activates a repo's committed worktree hooks so that adding `worktree-warden` to
# a project's [dependencies] is enough to enable provisioning on every clone.
#
# Sourced into the user's shell — so NO `set -e/-u`, NO `exit`/`return`, and stay
# quiet. Only acts when a committed .githooks/post-checkout is present.
if command -v git >/dev/null 2>&1; then
  _wtw_root="${PIXI_PROJECT_ROOT:-}"
  [ -n "${_wtw_root}" ] || _wtw_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -n "${_wtw_root}" ] && [ -f "${_wtw_root}/.githooks/post-checkout" ]; then
    if [ "$(git -C "${_wtw_root}" config --local --get core.hooksPath 2>/dev/null)" != ".githooks" ]; then
      git -C "${_wtw_root}" config --local core.hooksPath .githooks 2>/dev/null || true
    fi
  fi
  unset _wtw_root
fi
