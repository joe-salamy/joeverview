# joeverview

Mission Control for tmux — a better `prefix w`.

`prefix o` opens a fullscreen 2×2 snapshot grid of your windows — arrows/WASD to move, `Enter` to jump, `q` to cancel. No typing, no session list, no directory scan: it shows the windows you have, at full resolution, and gets out of the way. Window and session management (`c`/`X`/`R`, move, rename, kill-confirm) happens inline, without leaving the overview.

One companion rounds it out: `prefix /` searches scrollback contents across all panes and jumps to the pane holding the match (the thing `prefix w` can't do — names only).

Built for a single-session tmux with `renumber-windows on` and zero-based indexes, but nothing depends on that.

## Demo

![window grid overview](docs/demo.gif)

## Install

```sh
git clone https://github.com/joe-salamy/joeverview.git ~/Code/joeverview
~/Code/joeverview/install.sh
```

`install.sh` checks dependencies, symlinks `bin/*` into `~/.local/bin/`, adds `source-file …/tmux/joeverview.conf` to `~/.tmux.conf` (retiring the two inline binds it supersedes), and reloads tmux. Idempotent — safe to re-run after `git pull`. Backs up `~/.tmux.conf` before touching it.

The repo checkout is the source of truth: `~/.local/bin/tmux-*` are symlinks into `bin/`, so edits here go live the next time a popup opens. Binding changes need `prefix r`.

### TPM alternative

```tmux
set -g @plugin 'joe-salamy/joeverview'
```

No symlinks needed on this path — `joeverview.tmux` binds the keys straight at the repo checkout. Keep the checkout where you cloned it; moving it means re-running TPM's install step.

## Keys

| binding | what |
|---|---|
| `prefix o` | window grid — see `docs/USAGE.md` |
| `prefix /` | scrollback search — see `docs/USAGE.md` |

Full details in [`docs/USAGE.md`](docs/USAGE.md); design rationale in [`docs/DESIGN.md`](docs/DESIGN.md).

## Requirements

- tmux 3.4+ (`display-popup`)
- `bash`, `python3` (grid truncation helper)
- `fzf` — only for `prefix /`; the `o` grid needs none

## Uninstall

```sh
~/Code/joeverview/uninstall.sh
```

Removes the `~/.local/bin` symlinks only if they still point at this checkout, drops the `source-file` line from `~/.tmux.conf` (backing it up first), and reloads tmux. Your windows, sessions, and the repo itself are untouched — delete the clone afterwards if you want it gone.

## Layout

```text
bin/                  the two pickers (source of truth)
tmux/joeverview.conf  the two bind-key lines, sourced from ~/.tmux.conf
joeverview.tmux       TPM entry point (binds keys at the checkout, no symlinks)
docs/                 USAGE.md, DESIGN.md
tests/smoke.sh        syntax + symlink + bindings + grid-render (single entry point)
tests/grid-render.sh  stub-tmux goldens + interactions (also run via smoke)
install.sh            deps + symlink + wire + reload, idempotent
uninstall.sh          unlink + unwire + reload, idempotent
```

## License

MIT — see [LICENSE](LICENSE).
