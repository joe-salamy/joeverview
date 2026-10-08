#!/usr/bin/env bash
# joeverview uninstaller — removes the ~/.local/bin symlinks (only if they
# still point at this checkout) and drops the source-file line from
# ~/.tmux.conf. Idempotent. Windows, sessions, and this repo are untouched.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/.local/bin"
TMUX_CONF="$HOME/.tmux.conf"

for src in "$REPO"/bin/*; do
  name="$(basename "$src")"
  dst="$BIN_DIR/$name"
  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
    rm "$dst"
    echo "removed $dst"
  else
    echo "kept $dst (not a joeverview symlink)"
  fi
done

if [ -f "$TMUX_CONF" ] && grep -qE "source-file.*joeverview|superseded by joeverview" "$TMUX_CONF"; then
  cp -p "$TMUX_CONF" "$TMUX_CONF.bak-$(date +%Y%m%d%H%M%S)"
  awk '
    /^[[:space:]]*#?[[:space:]]*source-file.*joeverview/ { next }
    /^# superseded by joeverview \(see source-file below\): / { sub(/^# superseded by joeverview \(see source-file below\): /, ""); print; next }
    { print }
  ' "$TMUX_CONF" > "$TMUX_CONF.tmp"
  # Write through (not mv): keeps a dotfiles symlink and the file's mode.
  cat "$TMUX_CONF.tmp" > "$TMUX_CONF" && rm -f "$TMUX_CONF.tmp"
  echo "unwired source-file from $TMUX_CONF (restored superseded binds)"
else
  echo "nothing wired in $TMUX_CONF, skipping edit"
fi

# Live server: drop joeverview's binds, put tmux's stock o and / back (read
# from a throwaway server with no config), then re-source ~/.tmux.conf last
# so any binds of yours restored above win over the stock ones.
if tmux has-session >/dev/null 2>&1; then
  tmux unbind-key -T prefix o 2>/dev/null || true
  tmux unbind-key -T prefix / 2>/dev/null || true
  tmux set-hook -gu 'alert-bell[86]' 2>/dev/null || true
  tmux set-hook -gu 'session-window-changed[87]' 2>/dev/null || true
  stock=$(tmux -L "joeverview-stock-$$" -f /dev/null new-session -d \; \
    list-keys -T prefix o \; list-keys -T prefix / \; kill-server 2>/dev/null) || stock=""
  if [ -n "$stock" ]; then printf '%s\n' "$stock" | tmux source-file - || true; fi
  tmux source-file "$TMUX_CONF" && echo "tmux reloaded"
fi
