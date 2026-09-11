# joeverview — agent notes

Fullscreen tmux window/pane/content pickers on `prefix o/O//`. Single-session optimized, zero daemons.

## Layout

- `bin/` — SSOT for the three pickers (`tmux-window-picker`, `tmux-pane-picker`, `tmux-content-search`). No extensions, `bash`, `set -u`.
- `tmux/joeverview.conf` — the three `bind-key` lines. `~/.tmux.conf` loads it via `source-file`; never duplicate the binds inline.
- `install.sh` — symlinks `bin/*` → `~/.local/bin/`, wires the `source-file` line, reloads tmux. Idempotent; backs up `~/.tmux.conf` before editing.
- `docs/` — `USAGE.md` (keys), `DESIGN.md` (why: stable IDs, truncation, border ownership).
- `tests/smoke.sh` — `bash -n`, symlink check, isolated-server `list-keys` check.

## Invariants

- `~/.local/bin/tmux-*` are symlinks into `bin/`. Never copy; never edit the installed path directly — edit here, live on next popup open (scripts are read at launch; no reload needed for script changes, `prefix r` only for binding changes).
- tmux targets must use stable IDs (`@window_id`, `%pane_id`), never bare `W.P` or indexes — indexes shift under `renumber-windows`, bare targets resolve against the active window/session. See `docs/DESIGN.md`.
- Truncation must be visible-width-aware (`east_asian_width`, SGR kept atomic, OSC stripped). System `cut -c` counts bytes and splits UTF-8 — never use it on pane captures.
- `prefix o` popup uses `display-popup -B` (no tmux border); the grid script owns the whole canvas including its own frame. `-T` needs a tmux border, so the script stamps its title into its own top border instead.

## Verify

```sh
./tests/smoke.sh
```

`bash -n` on change, isolated-server key check after binding change, live `prefix o` eyeball for grid rendering (literal `\x1b` text on screen = EL quoting bug — see `docs/DESIGN.md`).
