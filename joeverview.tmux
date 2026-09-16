#!/usr/bin/env bash
# joeverview TPM entry point — `set -g @plugin 'joe-salamy/joeverview'`.
# Binds keys by sourcing tmux/joeverview.conf (single source of truth; do not duplicate bind-key lines here).
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

tmux source-file "$CURRENT_DIR/tmux/joeverview.conf"
