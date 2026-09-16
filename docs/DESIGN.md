# Design notes

Why joeverview looks the way it does. Each rule was a live bug.

## Stable IDs for every tmux target

Rows are keyed by `#{window_id}` (`@id`) / `#{pane_id}` (`%id`); every `capture-pane`,
`select-window`, and `select-pane` uses the ID. Display text (index, name) is a second field, hidden
from fzf via `--with-nth=2..` where needed (the grid uses no fzf; its search script hides nothing).

Why: bare `-t 0`/`-t 1` resolve against the *active* window/session, not window 0/1 — previews
showed the active window's content for unvisited windows. Indexes also shift under
`renumber-windows`; IDs survive.

## Snapshot grid, not a live mirror

`prefix o` reads window metadata at launch (`list-sessions` + one batched `list-windows -a`), truncates
all titles in one `python3` pass, and captures only the visible page (≤4 cells, `capture-pane -pe -t
@id`, bottom `tail` at full resolution). Scrolls and session switches fault missing cells in
synchronously. `r` (or reopen) refreshes after out-of-band changes — there is no way to mirror live
panes without moving them.

Captures stay visible-only (no `-S`): snapshots identify, jumping renders. Trailing capture padding
is trimmed inside the trunc helper (no `sed` stage) — grid only; the fzf search still strips with
sed.

## Visible-width-aware truncation (never `cut -c`)

System `cut -c` counts bytes (uutils 0.8.0 proven: 172×`─` → 173 bytes), splitting UTF-8
mid-character. The grid embeds a ~40-line python helper via `python3 -c "$PY"` (a heredoc would
swallow the capture pipe on stdin): strips OSC hyperlinks, keeps SGR sequences atomic, counts
`east_asian_width`, appends reset. `LC_ALL=C.UTF-8` does not fix `cut`.

The fzf search (`/`) uses `--ansi --preview-window=…:nowrap` instead — same idea, delegated to fzf.

## The script owns the canvas (`-B`)

`prefix o` uses `display-popup -B` (no tmux border) and draws its own rounded frame (`╭╮╰╯`,
gutters, mid rule, stamped ` Windows ` title). Earlier the popup had *two* frames — tmux's default
single-line border plus the script's inset rounded one — and the mid rule stopped short of the
edges. `-T` needs a tmux border, so the script stamps its title into its own top border instead of
using `-T`. (`/` keeps the tmux border + `-T`; fzf draws no frame.)

## Flicker-free input

Each full paint is buffered into one string and flushed with a single `printf` (~9.5 KB atomic).
Same-page moves repaint only the affected title row(s): one `EL` clear per row, then both cells +
gutter + borders rewritten with no-EL moves (per-cell `EL` wiped the sibling title). No-op keys
redraw nothing. Cursor hidden (`?25l`) while open, `stty` state restored on exit.

Quoting trap that bit: `'\x1b[K'` in single quotes emits literal text — escapes are built with
`printf -v '…\x1b…'`. tests/grid-render.sh asserts zero literal `\x1b` sequences over rendered
output for this reason.

## Alert colors

Titles carry a launch-time `#{?window_bell_flag,B,}#{?window_activity_flag,A,}` snapshot: bell =
bold red, activity = bold yellow, reverse folded in when selected. `monitor-activity` is off by
default, so yellow never fires until `setw -g monitor-activity on`; bell red works with stock
`monitor-bell on`.

## Session pager + pane badge

`prefix o` shows one session at a time (`list-sessions` + batched `list-windows -a`, regrouped in session order).
The switcher (`← name →`) is stamped into the existing top border next to ` Windows `, so grid
geometry and the arm-aware frame (junctions close with corners) are unchanged; bounds just narrow
from global `n` to the visible session's `[s0, send)`. Up from the top grid row focuses the bar
(always, even single-session), Left/Right pages (reset to the session's first page, full `draw` —
the only bar painter, so no partial-repaint desync), Down returns, Enter attaches (`switch-client`)
or jumps (`switch-client` + `select-window -t @id` when the window lives elsewhere). Titles carry `⧉
N` from `#{window_panes}` when N>1; the body stays the active-pane capture, so exact-pane work stays
on jumping to the pane.

Field-order trap that bit: `read` with `IFS=$'\t'` treats tab as IFS whitespace, so an empty field
collapses and later fields shift left. The bell/activity flag field is empty most of the time, so it
must stay last — `#{window_panes}` (never empty) goes before it.

The switcher renders as a padded medallion (`  ←  name  →  `, `  name  ` when single)
so the arrows clear the border dashes. With a single session Left/Right and kill are hidden —
and ignored — the bar still focuses (session ops live there and nowhere else). The mid divider
is notched for the one row passing under the medallion, so the column border never touches the
session name.

## Strict focus modes + rename

Grid focus runs window ops only (`c` new window, `X` window, `<>` move, `R` rename window); bar
focus runs session ops only (`N` new session, `X` session, `R` rename session). The footer is the
contract — every key it lists works, every working key is listed (per-focus; letter case is folded
except `x`, and `r`≠`R`). `X` on a sole session is refused: killing the last session would strand
the client. Session kill arms a footer-inline `y/N` confirm (same row rename uses): `X` paints the
prompt with no `draw` and no cache drop, `y` commits through `do_kill_session`, anything else
(arrows included — their escape bytes are consumed) redraws unchanged, and lone `Esc` aborts instead
of quitting. Rename drops out of raw nav mode into a char-by-char `read_name` loop on the footer row
(never in `$()` so the prompt reaches the popup tty); empty input or `Esc` redraws unchanged.
Session rename also drops the cached medallion (`SESS_MED`); window rename keeps the snapshot cache
(keyed by stable `@id`) while titles rebuild in `refresh_to`.
