# Usage

All popups are fullscreen (`-w 100% -h 100%`), like `choose-tree`.

## `prefix o` — window grid

2×2 snapshot grid with two focuses. The footer always shows exactly the keys that work right now — unlisted keys do nothing (letter keys accept either case except `x`, and `r`≠`R` (refresh vs rename); `x` never kills).

The popup takes every key, so tmux prefix bindings (e.g. `prefix C-s` for resurrect save) don't fire while it's open: `C-b` and the key after it are ignored, and `C-s`/`C-q`/`C-v` are plain ignored keys (no flow-control freeze). Close the overview first to use them.

The grid **auto-refreshes** every half second, like pressing `r`: new or closed windows, pane output, titles and alert colors update without a key, and the selection stays on the same window (if that window closes elsewhere, the cursor keeps its slot). Nothing repaints when nothing changed, and the refresh pauses while the session-kill `y/N` prompt or a rename prompt is open. Set the period in `tmux/joeverview.conf` (or anywhere in `~/.tmux.conf` after it, or before `run tpm` on the TPM path):

```tmux
set -g @joeverview-refresh 0.5    # seconds; decimals ok; 0 = off
```

Read when the popup opens — reopen it after changing the value (`prefix r` reloads a conf edit).

### Window focus (the grid)

Each cell: `[index] name │ task │ path` title (+ `⧉ N` when the window holds N tmux panes) + bottom-left of the window's active pane. Cursor starts on the current window. Selected cell is reverse-highlighted; red title = bell, yellow = activity (needs `setw -g monitor-activity on`; bell red works stock). Bell red is sticky — it also marks the window you were on when it rang, and stays until you jump to that window from this grid.

| key | action |
|---|---|
| arrows / WASD | move selection |
| Up from the top row | focus the session bar (always available, even with one session) |
| down from the bottom row | scroll |
| `0`-`9` | jump to the window with that index in this session (no match = ignore) |
| `Enter` | jump to the selected window |
| `c` | **new window** in the viewed session (cursor lands on it, grid stays open) |
| `R` | rename the selected window (empty input, `Esc`, or any arrow/special key keeps the old name) |
| `<` / `>` | **move** the selected window one slot left / right within the session (cursor follows the moved window) |
| `X` | kill the selected window (a session's last window takes the session with it: the client moves to the neighbour session first; refused — and unlisted — for the sole window of the sole session) |
| `r` | refresh snapshots now (auto-refresh does the same on a timer) |
| `q` / `Esc` | cancel |

### Session-bar focus (the `← name →` medallion)

Session ops only — window keys (`c`, `0`-`9`, `<>`) do nothing here. `↓`/`s` returns to the grid.

| key | action |
|---|---|
| `←`/`→` (or `a`/`d`) | switch session (several sessions only) |
| `Enter` | attach to the viewed session |
| `N` | **new session** (grid lands on it, bar stays focused) |
| `R` | rename the viewed session (empty input, `Esc`, or any arrow/special key keeps the old name) |
| `X` | kill the viewed session: asks `Kill session <name> (N windows)? y/N` on the footer row — `y` kills, anything else (including `Esc`) cancels and stays open (disabled when it's the only session — that would strand the client) |
| `r` | refresh snapshots now (keeps the bar focused and the grid selection behind it) |
| `q` / `Esc` | cancel |

## `prefix /` — content search

fzf over the last 500 lines per pane, blank lines skipped, each row tagged `session:window` context. `Enter` jumps to the pane holding the match (switches session/window as needed), `Ctrl-Y` yanks the matched line to the tmux buffer. The thing `prefix w` can't do (names-only).
