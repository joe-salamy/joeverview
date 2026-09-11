# joeverview

A fullscreen, no-typing window overview for tmux.

`prefix o` opens a 2×2 snapshot grid of your windows — arrows/WASD to move, `Enter` to jump, `q` to cancel. No typing, no session list, no directory scan: it shows the windows you have, at full resolution, and gets out of the way.

Two companions round it out: `prefix O` jumps to an exact pane with live preview, `prefix /` searches scrollback contents across all panes and jumps to the match.

Built for a single-session tmux with `renumber-windows on` and zero-based indexes, but nothing depends on that.

## Install

```sh
git clone <url> ~/Code/joeverview
~/Code/joeverview/install.sh
```

`install.sh` symlinks `bin/*` into `~/.local/bin/`, adds `source-file …/tmux/joeverview.conf` to `~/.tmux.conf` (retiring the three inline binds it supersedes), and reloads tmux. Idempotent — safe to re-run after `git pull`. Backs up `~/.tmux.conf` before touching it.

The repo checkout is the source of truth: `~/.local/bin/tmux-*` are symlinks into `bin/`, so edits here go live the next time a popup opens. Binding changes need `prefix r`.

## Keys

| binding | what |
|---|---|
| `prefix o` | window grid — see `docs/USAGE.md` |
| `prefix O` | pane jumper — see `docs/USAGE.md` |
| `prefix /` | scrollback search — see `docs/USAGE.md` |

Full details in [`docs/USAGE.md`](docs/USAGE.md); design rationale in [`docs/DESIGN.md`](docs/DESIGN.md).

## Requirements

- tmux 3.4+ (`display-popup`)
- `bash`, `python3` (grid truncation helper)
- `fzf` — only for `prefix O` and `prefix /`; the `o` grid needs none

## Layout

```text
bin/                  the three pickers (source of truth)
tmux/joeverview.conf  the three bind-key lines, sourced from ~/.tmux.conf
docs/                 USAGE.md, DESIGN.md
tests/smoke.sh        syntax + symlink + isolated-server binding check
install.sh            symlink + wire + reload, idempotent
```

## License

MIT — see [LICENSE](LICENSE).
