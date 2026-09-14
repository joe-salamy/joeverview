#!/usr/bin/env bash
# joeverview installer — symlinks bin/* into ~/.local/bin and wires
# `source-file .../tmux/joeverview.conf` into ~/.tmux.conf. Idempotent.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/.local/bin"
TMUX_CONF="$HOME/.tmux.conf"
SNIPPET="$REPO/tmux/joeverview.conf"

# 0. Dependencies: fail fast with a clear message instead of dying in a popup.
for cmd in tmux python3; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "joeverview: needs '$cmd' — please install it first" >&2; exit 1; }
done
tmux_v="$(tmux -V | awk '{print $2}')"
# Portable >=3.4 check (no GNU sort -V): numeric compare on major/minor.
# shellcheck disable=SC2086 # unquoted $tmux_v intended for word-splitting
set -- $tmux_v; tmux_maj=${1%%.*}; tmux_min=${1#*.}; tmux_min=${tmux_min%%[^0-9]*}
if ! { [ "${tmux_maj:-0}" -gt 3 ] || { [ "${tmux_maj:-0}" -eq 3 ] && [ "${tmux_min:-0}" -ge 4 ]; }; } 2>/dev/null; then
  echo "joeverview: needs tmux 3.4+ (display-popup) — found: $(tmux -V)" >&2
  exit 1
fi
if ! command -v fzf >/dev/null 2>&1; then
  echo "joeverview: note: 'fzf' not found — prefix / needs it; the o grid works without it" >&2
fi

mkdir -p "$BIN_DIR"

# 1. Pickers: repo bin/ is the source of truth, installed paths are symlinks.
for src in "$REPO"/bin/*; do
  name="$(basename "$src")"
  dst="$BIN_DIR/$name"
  if [ -e "$dst" ] && [ ! -L "$dst" ]; then
    bak="$dst.bak-$(date +%Y%m%d%H%M%S)"
    mv "$dst" "$bak"
    echo "backed up $dst -> $bak"
  fi
  ln -sfn "$src" "$dst"
  echo "linked $dst -> $src"
done

## (retired 2026-09: the prefix-O pane-picker is gone since 59b6bc0; a
## surviving ~/.local/bin/tmux-pane-picker symlink is user-owned — left alone)

# 2. Bindings: source the snippet from ~/.tmux.conf (before TPM's run line,
#    which must stay last). Retire superseded inline binds as comments.
if [ -f "$TMUX_CONF" ]; then
  if grep -qF "source-file \"$SNIPPET\"" "$TMUX_CONF"; then
    echo "source-file already wired, skipping edit"
  else
    cp -p "$TMUX_CONF" "$TMUX_CONF.bak-$(date +%Y%m%d%H%M%S)"
    awk -v snippet="$SNIPPET" '
      BEGIN { inserted=0 }
      /joeverview\.conf/ { next }
      /^bind-key +[o\/] +display-popup.*tmux-(window-picker|content-search)/ { print "# superseded by joeverview (see source-file below): " $0; next }
      /^run .*tpm\/tpm/ && !inserted { print "source-file \"" snippet "\""; inserted=1 }
      { print }
      END { if (!inserted) print "source-file \"" snippet "\"" }
    ' "$TMUX_CONF" > "$TMUX_CONF.tmp" && mv "$TMUX_CONF.tmp" "$TMUX_CONF"
    echo "wired source-file into $TMUX_CONF"
  fi
else
  printf 'source-file "%s"\n' "$SNIPPET" > "$TMUX_CONF"
  echo "created $TMUX_CONF"
fi

# 3. Reload the live server if there is one.
if tmux info >/dev/null 2>&1; then
  tmux source-file "$TMUX_CONF" && echo "tmux reloaded"
fi
