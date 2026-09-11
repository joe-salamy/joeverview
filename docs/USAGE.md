# Usage

All popups are fullscreen (`-w 100% -h 100%`), like `choose-tree`.

## `prefix o` — window grid

2×2 snapshot grid, one session at a time. Each cell: `[index] name │ task │ path` title (+ `⧉N` when the window holds N tmux panes) + bottom-left of the window's active pane.

| key | action |
|---|---|
| arrows / WASD | move (Up from the top row focuses the session bar) |
| `←`/`→` on the session bar | switch session |
| `0`-`9` | jump to window with that index in this session (no match = ignore) |
| `Enter` | jump to window (on the session bar: attach to session) |
| `q` / `Esc` | cancel |
| down from bottom row | scroll |

Cursor starts on the current window. `●` selected / `○` unselected; red title = bell, yellow = activity (needs `setw -g monitor-activity on`; bell red works stock).

## `prefix O` — pane jumper

fzf over `list-panes -s` with content preview. `Enter` jumps (auto-switches window), `Ctrl-X` kills the pane and reloads the list.

## `prefix /` — content search

fzf over the last 500 non-blank scrollback lines of every pane (`paneid:line`). `Enter` jumps to the pane holding the match. The thing `prefix w` can't do (names-only).
