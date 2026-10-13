#!/usr/bin/env bash
# joeverview TPM entry point — `set -g @plugin 'joe-salamy/joeverview'`.
# Binds the two keys directly at this checkout (no symlinks). Mirrors
# tmux/joeverview.conf command-for-command: tmux 3.4 display-popup passes
# shell-command to job_run unexpanded, so the conf cannot be shared via
# #{@option} — keep both definitions in sync. The popup runs its command
# through a shell, so the paths are shell-quoted (checkouts with spaces).
# @joeverview-refresh is not set here: the script's built-in default (0.5)
# matches the conf, and a user value set before `run tpm` stays untouched.
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
printf -v GRID '%q' "$CURRENT_DIR/bin/tmux-window-picker"
printf -v SEARCH '%q' "$CURRENT_DIR/bin/tmux-content-search"

tmux bind-key o display-popup -B -E -w 100% -h 100% "$GRID"
tmux bind-key / display-popup -E -w 100% -h 100% -T " Search " "$SEARCH"
tmux set-hook -g 'alert-bell[86]' 'set-option -wq @jv_bell 1'
tmux set-hook -g 'session-window-changed[87]' 'set-option -wqu @jv_bell'
