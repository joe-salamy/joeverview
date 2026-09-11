# Design notes

Why joeverview looks the way it does. Each rule was a live bug.

## Stable IDs for every tmux target

Rows are keyed by `#{window_id}` (`@id`) / `#{pane_id}` (`%id`); every `capture-pane`, `select-window`, `select-pane`, and `kill-pane` uses the ID. Display text (index, name) is a second field, hidden from fzf via `--with-nth=2..` where needed.

Why: bare `-t 0`/`-t 1` resolve against the *active* window/session, not window 0/1 — previews showed the active window's content for unvisited windows. Indexes also shift under `renumber-windows`; IDs survive.

## Snapshot grid, not a live mirror

`prefix o` captures every window once at launch (`capture-pane -pe -t @id`, bottom `tail` at full resolution) and renders statically. Reopen to refresh — there is no way to mirror live panes without moving them.

Captures pipe through `sed 's/[[:space:]]*$//'` (capture pads lines with spaces) and stay visible-only (no `-S`): snapshots identify, jumping renders.

## Visible-width-aware truncation (never `cut -c`)

System `cut -c` counts bytes (uutils 0.8.0 proven: 172×`─` → 173 bytes), splitting UTF-8 mid-character. The grid embeds a ~40-line python helper via `python3 -c "$PY"` (a heredoc would swallow the capture pipe on stdin): strips OSC hyperlinks, keeps SGR sequences atomic, counts `east_asian_width`, appends reset. `LC_ALL=C.UTF-8` does not fix `cut`.

The fzf pickers (`O`, `/`) use `--ansi --preview-window=…:nowrap` instead — same idea, delegated to fzf.

## The script owns the canvas (`-B`)

`prefix o` uses `display-popup -B` (no tmux border) and draws its own rounded frame (`╭╮╰╯`, gutters, mid rule, stamped ` Windows ` title). Earlier the popup had *two* frames — tmux's default single-line border plus the script's inset rounded one — and the mid rule stopped short of the edges. `-T` needs a tmux border, so the script stamps its title into its own top border instead of using `-T`. (`O`/`/` keep the tmux border + `-T`; fzf draws no frame.)

## Flicker-free input

Each full paint is buffered into one string and flushed with a single `printf` (~9.5 KB atomic). Same-page moves repaint only the affected title row(s): one `EL` clear per row, then both cells + gutter + borders rewritten with no-EL moves (per-cell `EL` wiped the sibling title). No-op keys redraw nothing. Cursor hidden (`?25l`) while open, `stty` state restored on exit.

Quoting trap that bit: `'\x1b[K'` in single quotes emits literal text — escapes are built with `printf -v '…\x1b…'`. The smoke test asserts zero literal `\x1b` sequences for this reason.

## Alert colors

Titles carry a launch-time `#{?window_bell_flag,B,}#{?window_activity_flag,A,}` snapshot: bell = bold red, activity = bold yellow, reverse folded in when selected. `monitor-activity` is off by default, so yellow never fires until `setw -g monitor-activity on`; bell red works with stock `monitor-bell on`.

## Session pager + pane badge

`prefix o` shows one session at a time (`list-sessions`, then per-session `list-windows -t $sid`). The switcher (`← name →`) is stamped into the existing top border next to ` Windows `, so grid geometry and the subtractive frame are unchanged; bounds just narrow from global `n` to the visible session's `[s0, send)`. Up from the top grid row focuses the bar, Left/Right pages (reset to the session's first page, full `draw` — the only bar painter, so no partial-repaint desync), Down returns, Enter attaches (`switch-client`) or jumps (`switch-client` + `select-window -t @id` when the window lives elsewhere). Titles carry `⧉N` from `#{window_panes}` when N>1; the body stays the active-pane capture, so exact-pane work stays on `prefix O`.

Field-order trap that bit: `read` with `IFS=$'\t'` treats tab as IFS whitespace, so an empty field collapses and later fields shift left. The bell/activity flag field is empty most of the time, so it must stay last — `#{window_panes}` (never empty) goes before it.
