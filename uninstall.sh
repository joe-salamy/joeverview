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
    /^[[:space:]]*#?[[:space:]]*(set -g @joeverview_bin|source-file).*joeverview/ { next }
    /^# superseded by joeverview \(see source-file below\): / { sub(/^# superseded by joeverview \(see source-file below\): /, ""); print; next }
    { print }
  ' "$TMUX_CONF" > "$TMUX_CONF.tmp" && mv "$TMUX_CONF.tmp" "$TMUX_CONF"
  echo "unwired source-file from $TMUX_CONF (restored superseded binds)"
else
  echo "nothing wired in $TMUX_CONF, skipping edit"
fi

if tmux info >/dev/null 2>&1; then
  tmux source-file "$TMUX_CONF" && echo "tmux reloaded"
  tmux unbind-key -T prefix o 2>/dev/null || true
  tmux unbind-key -T prefix / 2>/dev/null || true
  tmux set -gu @joeverview_bin 2>/dev/null || true
fi
