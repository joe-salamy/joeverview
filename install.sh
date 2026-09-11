#!/usr/bin/env bash
# joeverview installer — symlinks bin/* into ~/.local/bin and wires
# `source-file .../tmux/joeverview.conf` into ~/.tmux.conf. Idempotent.
set -euo pipefail
[[ "$(uname)" == Linux ]] || { echo "joeverview install.sh supports Linux only (GNU sed)" >&2; exit 1; }

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/.local/bin"
TMUX_CONF="$HOME/.tmux.conf"
SNIPPET="$REPO/tmux/joeverview.conf"

mkdir -p "$BIN_DIR"

# 1. Pickers: repo bin/ is the source of truth, installed paths are symlinks.
for src in "$REPO"/bin/*; do
  name="$(basename "$src")"
  dst="$BIN_DIR/$name"
  chmod +x "$src"
  if [ -e "$dst" ] && [ ! -L "$dst" ]; then
    bak="$dst.bak-$(date +%Y%m%d%H%M%S)"
    mv "$dst" "$bak"
    echo "backed up $dst -> $bak"
  fi
  ln -sfn "$src" "$dst"
  echo "linked $dst -> $src"
done

# 2. Bindings: source the snippet from ~/.tmux.conf (before TPM's run line,
#    which must stay last). Retire superseded inline binds as comments.
if [ -f "$TMUX_CONF" ]; then
  if ! grep -qF "joeverview.conf" "$TMUX_CONF"; then
    cp -p "$TMUX_CONF" "$TMUX_CONF.bak-$(date +%Y%m%d%H%M%S)"
    sed -i -E 's|^(bind-key +[oO/] +display-popup.*tmux-[-a-z]+.*)$|# superseded by joeverview (see source-file below): \1|' "$TMUX_CONF"
    if grep -qE '^run .*tpm/tpm' "$TMUX_CONF"; then
      sed -i "\|^run .*tpm/tpm|isource-file \"$SNIPPET\"" "$TMUX_CONF"
    else
      printf 'source-file "%s"\n' "$SNIPPET" >> "$TMUX_CONF"
    fi
    echo "wired source-file into $TMUX_CONF"
  else
      if grep -qF "source-file \"$SNIPPET\"" "$TMUX_CONF"; then
        echo "source-file already wired, skipping edit"
      else
        cp -p "$TMUX_CONF" "$TMUX_CONF.bak-$(date +%Y%m%d%H%M%S)"
        grep -vF "joeverview.conf" "$TMUX_CONF" > "$TMUX_CONF.tmp" || true
        mv "$TMUX_CONF.tmp" "$TMUX_CONF"
        printf 'source-file "%s"\n' "$SNIPPET" >> "$TMUX_CONF"
        echo "rewired stale source-file to $SNIPPET"
      fi
  fi
else
  printf 'source-file "%s"\n' "$SNIPPET" > "$TMUX_CONF"
  echo "created $TMUX_CONF"
fi

# 3. Reload the live server if there is one.
if tmux info >/dev/null 2>&1; then
  tmux source-file "$TMUX_CONF" && echo "tmux reloaded"
fi
