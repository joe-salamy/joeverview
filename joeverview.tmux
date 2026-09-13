#!/usr/bin/env bash
# joeverview TPM entry point — `set -g @plugin 'joe-salamy/joeverview'`.
# Binds the keys at the plugin checkout, so no symlinks are needed on this
# path. Mirrors tmux/joeverview.conf (the manual-install source of truth):
# keep the two in sync when bindings change.
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# prefix o: 2x2 snapshot grid (script owns the canvas: -B, no tmux border).
tmux bind-key o display-popup -B -E -w 100% -h 100% "$CURRENT_DIR/bin/tmux-window-picker"
# prefix O: exact-pane jumper (fzf + preview).
tmux bind-key O display-popup -E -w 100% -h 100% -T " Panes " "$CURRENT_DIR/bin/tmux-pane-picker"
# prefix /: scrollback content search (overrides stock describe-key; prefix ? still lists keys).
tmux bind-key / display-popup -E -w 100% -h 100% -T " Search " "$CURRENT_DIR/bin/tmux-content-search"
