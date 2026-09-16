#!/usr/bin/env bash
# joeverview smoke test: syntax, symlinks, bindings on an isolated server.
# NOTE: tmux 3.4 column-aligns list-keys with multiple spaces — greps below
# use +-flexible whitespace for that reason.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0

for s in tmux-window-picker tmux-content-search; do
  if bash -n "$REPO/bin/$s"; then echo "OK   bash -n $s"; else echo "FAIL bash -n $s"; fail=1; fi
  link=$(readlink "$HOME/.local/bin/$s" 2>/dev/null || true); if [ "$link" = "$REPO/bin/$s" ]; then
    echo "OK   symlink $s"
  else
    echo "FAIL symlink $s"; fail=1
  fi
done

T="$(mktemp -d "${TMPDIR:-/tmp}/jv-smoke.XXXXXX")"
trap 'rm -rf "$T"' EXIT
SMOKE_CONF="$T/smoke-tmux.conf"
printf 'source-file "%s"\n' "$REPO/tmux/joeverview.conf" > "$SMOKE_CONF"
KEYS="$(tmux -L joeverview-smoke -f "$SMOKE_CONF" new-session -d -x 172 -y 41 \; list-keys \; kill-server 2>/dev/null)"
echo "$KEYS" | grep -qE 'bind-key +-T prefix +o +.*display-popup +-BE?.*tmux-window-picker' \
  && echo "OK   prefix o (borderless grid)" || { echo "FAIL prefix o"; fail=1; }
echo "$KEYS" | grep -qE 'bind-key +-T prefix +/ +.*tmux-content-search' \
  && echo "OK   prefix /" || { echo "FAIL prefix /"; fail=1; }

# Grid render goldens + interactions (stub-tmux, no live server).
if bash "$REPO/tests/grid-render.sh"; then echo "OK   grid-render"; else echo "FAIL grid-render"; fail=1; fi
if bash "$REPO/tests/content-search.sh"; then echo "OK   content-search"; else echo "FAIL content-search"; fail=1; fi
if [ "$fail" -eq 0 ]; then echo "smoke: PASS"; else echo "smoke: FAIL"; fi
exit "$fail"
