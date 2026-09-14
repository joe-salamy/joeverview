#!/usr/bin/env bash
# joeverview TPM entry point — `set -g @plugin 'joe-salamy/joeverview'`.
# Binds the keys at the plugin checkout, so no symlinks are needed on this
# path. Generated from tmux/joeverview.conf (manual-install source of truth):
# to change a binding, edit the conf and re-run: awk '/^bind-key/ {print "tmux " $0}' tmux/joeverview.conf
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# prefix o: 2x2 snapshot grid (script owns the canvas: -B, no tmux border).
tmux bind-key o display-popup -B -E -w 100% -h 100% "$CURRENT_DIR/bin/tmux-window-picker"
# prefix /: scrollback content search (overrides stock describe-key; prefix ? still lists keys).
tmux bind-key / display-popup -E -w 100% -h 100% -T " Search " "$CURRENT_DIR/bin/tmux-content-search"
