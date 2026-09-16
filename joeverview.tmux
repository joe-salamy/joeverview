#!/usr/bin/env bash
# joeverview TPM entry point — `set -g @plugin 'joe-salamy/joeverview'`.
# Binds the two keys directly at this checkout (no symlinks). Mirrors
# tmux/joeverview.conf command-for-command: tmux 3.4 display-popup passes
# shell-command to job_run unexpanded, so the conf cannot be shared via
# #{@option} — keep both definitions in sync.
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

tmux bind-key o display-popup -B -E -w 100% -h 100% "$CURRENT_DIR/bin/tmux-window-picker"
tmux bind-key / display-popup -E -w 100% -h 100% -T " Search " "$CURRENT_DIR/bin/tmux-content-search"
