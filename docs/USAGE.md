# Usage

All popups are fullscreen (`-w 100% -h 100%`), like `choose-tree`.

## `prefix o` — window grid

2×2 snapshot grid, one session at a time. Each cell: `[index] name │ task │ path` title (+ `⧉ N` when the window holds N tmux panes) + bottom-left of the window's active pane.

| key | action |
|---|---|
| arrows / WASD | move (Up from the top row focuses the session bar, multiple sessions only) |
| `←`/`→` on the session bar | switch session |
| `0`-`9` | jump to window with that index in this session (no match = ignore) |
| `Enter` | jump to window (on the session bar: attach to session) |
| `q` / `Esc` | cancel |
| `c` | new window in the viewed session (cursor lands on it, grid stays open) |
| `n` | new session (grid lands on it with bar focus) |
| `X` / `Del` | kill selected window (grid focus) or viewed session (bar focus) |
| `,` / `.` (also `<` / `>`) | move selected window left / right within the session (cursor follows) |
| `r` | refresh snapshots |
| down from bottom row | scroll |

Cursor starts on the current window. Selected cell is reverse-highlighted; red title = bell, yellow = activity (needs `setw -g monitor-activity on`; bell red works stock).

## `prefix O` — pane jumper

fzf over `list-panes -s` with content preview. Rows show `W.P │ session │ window │ command │ title │ path` (+ `│ Z` when zoomed). `Enter` jumps (switches session/window as needed), `Ctrl-X` kills the pane and reloads the list.

## `prefix /` — content search

fzf over the last 500 non-blank scrollback lines of every pane, each row tagged `session:window` context. `Enter` jumps to the pane holding the match (switches session/window as needed), `Ctrl-Y` yanks the matched line to the tmux buffer. The thing `prefix w` can't do (names-only).
