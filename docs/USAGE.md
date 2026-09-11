# Usage

All popups are fullscreen (`-w 100% -h 100%`), like `choose-tree`.

## `prefix o` — window grid

2×2 snapshot grid with two focuses. The footer always shows exactly the keys that work right now — unlisted keys do nothing (letter keys accept either case, except `x`, which never kills).

### Window focus (the grid)

Each cell: `[index] name │ task │ path` title (+ `⧉ N` when the window holds N tmux panes) + bottom-left of the window's active pane. Cursor starts on the current window. Selected cell is reverse-highlighted; red title = bell, yellow = activity (needs `setw -g monitor-activity on`; bell red works stock).

| key | action |
|---|---|
| arrows / WASD | move selection |
| Up from the top row | focus the session bar (always available, even with one session) |
| down from the bottom row | scroll |
| `0`-`9` | jump to the window with that index in this session (no match = ignore) |
| `Enter` | jump to the selected window |
| `c` | **new window** in the viewed session (cursor lands on it, grid stays open) |
| `R` | rename the selected window (empty input keeps the old name) |
| `,` / `<` and `.` / `>` | **move** the selected window one slot left / right within the session (cursor follows the moved window) |
| `X` / `Del` | kill the selected window |
| `r` | refresh snapshots |
| `q` / `Esc` | cancel |

### Session-bar focus (the `← name →` medallion)

Session ops only — window keys (`c`, `0`-`9`, `,/.`) do nothing here. `↓`/`s` returns to the grid.

| key | action |
|---|---|
| `←`/`→` (or `a`/`d`) | switch session (several sessions only) |
| `Enter` | attach to the viewed session |
| `N` | **new session** (grid lands on it, bar stays focused) |
| `R` | rename the viewed session (empty input keeps the old name) |
| `X` / `Del` | kill the viewed session (disabled when it's the only one — that would strand the client) |
| `r` | refresh snapshots |
| `q` / `Esc` | cancel |

## `prefix O` — pane jumper

fzf over `list-panes -s` with content preview. Rows show `W.P │ session │ window │ command │ title │ path` (+ `│ Z` when zoomed). `Enter` jumps (switches session/window as needed), `Ctrl-X` kills the pane and reloads the list.

## `prefix /` — content search

fzf over the last 500 non-blank scrollback lines of every pane, each row tagged `session:window` context. `Enter` jumps to the pane holding the match (switches session/window as needed), `Ctrl-Y` yanks the matched line to the tmux buffer. The thing `prefix w` can't do (names-only).
