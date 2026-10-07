# Design notes

Why joeverview looks the way it does. Each rule was a live bug.

## Stable IDs for every tmux target

Rows are keyed by `#{window_id}` (`@id`) / `#{pane_id}` (`%id`); every `capture-pane`,
`select-window`, and `select-pane` uses the ID. Display text (index, name) is a second field, hidden
from fzf via `--with-nth=2..` where needed (the grid uses no fzf; its search script hides nothing).

Why: bare `-t 0`/`-t 1` resolve against the *active* window/session, not window 0/1 — previews
showed the active window's content for unvisited windows. Indexes also shift under
`renumber-windows`; IDs survive.

## Snapshot grid, refreshed on a tick

`prefix o` reads window metadata (`list-sessions` + one batched `list-windows -a`), truncates
all titles in one `python3` pass, and captures only the visible page (≤4 cells, `capture-pane -pe -t
@id`, bottom `tail` at full resolution). Scrolls and session switches fault missing cells in
synchronously. There is no way to mirror live panes without moving them, so the grid re-snapshots
instead: `r` on demand, and an auto-refresh every `@joeverview-refresh` seconds (default `1`,
decimals allowed, `0` = off; read once per popup open).

Auto-refresh is the same reload as `r` (`refresh_view`), driven from the main loop's existing 0.25 s
read timeout — no timer process, so the tick has 0.25 s granularity. Rules it follows:

- Timed by the clock (`EPOCHREALTIME`), not by counting timeouts: every key restarts the read
  timeout. Any action that already reloaded (`c`, `X`, `R`, `r`, …) postpones the next tick; a
  backward clock step fires instead of stalling.
- Reseats by stable ID: the selected window stays selected; if it died elsewhere the cursor keeps
  its offset; bar focus and the hidden grid selection behind it are kept.
- Skips the flush when the new frame is byte-identical to the one on screen (`SHOWN`). Direct
  writes that bypass the frame buffer (`at`, `paint_row`) void `SHOWN` so the next tick flushes.
- Never ticks while the session-kill `y/N` confirm is armed (a redraw would hide the prompt while
  `y` still kills). The rename prompt runs its own blocking read, so it cannot tick at all.

Cost per tick: ~5 forks plus one `python3` spawn — measured ~43 ms CPU per 1 s tick (~4 % of one
core) with 4 windows on a 172×42 canvas.

Captures stay visible-only (no `-S`): snapshots identify, jumping renders. Trailing capture padding
is trimmed inside the trunc helper (no `sed` stage) — grid only; the fzf search still strips with
sed.

## Visible-width-aware truncation (never `cut -c`)

System `cut -c` counts bytes (uutils 0.8.0 proven: 172×`─` → 173 bytes), splitting UTF-8
mid-character. The grid embeds a ~40-line python helper via `python3 -c "$PY"` (a heredoc would
swallow the capture pipe on stdin): strips OSC hyperlinks, keeps SGR sequences atomic, counts
`east_asian_width`, appends reset. `LC_ALL=C.UTF-8` does not fix `cut`.

The fzf search (`/`) delegates to fzf instead: rows are plain text (`capture-pane` without `-e`), and the colored preview uses `--preview-window=…:nowrap`.

## The script owns the canvas (`-B`)

`prefix o` uses `display-popup -B` (no tmux border) and draws its own rounded frame (`╭╮╰╯`,
gutters, mid rule, stamped ` Windows ` title). Earlier the popup had *two* frames — tmux's default
single-line border plus the script's inset rounded one — and the mid rule stopped short of the
edges. `-T` needs a tmux border, so the script stamps its title into its own top border instead of
using `-T`. (`/` keeps the tmux border + `-T`; fzf draws no frame.)

Owning the canvas means owning resizes too. tmux shrinks the popup when the client loses rows (a
Ghostty tab bar appearing) and grows it back after, sending `SIGWINCH`; tmux trims rows off the
*top* on shrink, so an unhandled resize cuts off the title border. The `WINCH` trap only sets a
flag — on a tty bash resumes a blocking `read` after a trap — so the main loop polls with
`read -t 0.25` and, on a flagged tick, recomputes geometry, drops size-dependent caches (captures,
titles, medallion — all truncated to the old cell size) and does a full redraw.

## Flicker-free input

Each full paint is buffered into one string and flushed with a single `printf` (~9.5 KB atomic).
Gutters and borders are drawn once per paint; each cell row is cleared with `ECH` (`CSI n X`,
erase n chars in place) over just that cell's span, never `EL` — clear-to-end-of-line wiped the
sibling cell, the column divider and the right border, which then had to be repainted. Same-page
moves repaint only the affected title(s) the same way. No-op keys redraw nothing. Cursor hidden (`?25l`) while open, `stty` state restored on exit.

Nothing in the per-row paint loops forks: empty cells are just an `ECH`, border runs are built
with `printf -v`, and the footer is sliced in pure bash (all its glyphs are width 1). A command
substitution or `python3` spawn per row or per keypress visibly delays frames.

Quoting trap that bit: `'\x1b[K'` in single quotes emits literal text — escapes are built with
`printf -v '…\x1b…'`. tests/grid-render.sh asserts zero literal `\x1b` sequences over rendered
output for this reason.

## Alert colors

Titles carry a per-load `#{?window_bell_flag,B,}#{?window_activity_flag,A,}` snapshot (refreshed by each tick): bell =
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
or jumps (`switch-client` when the window lives elsewhere, then `select-window -t $sid:@id` —
session-qualified so a window linked into several sessions resolves in the one being viewed). Titles carry `⧉
N` from `#{window_panes}` when N>1; the body stays the active-pane capture, so exact-pane work stays
on jumping to the pane.

Field-separator trap that bit: `read` with `IFS=$'\t'` treats tab as IFS whitespace, so an empty
field (`#{pane_title}`, the bell/activity flags) collapses and later fields shift left. The picker
rewrites each row's tabs to `\x1f` and reads with that non-whitespace `IFS`, which keeps empty fields
in place. (Asking tmux for `\x1f` directly does not work: `-F` output octal-escapes control
characters, so the separator arrives as the literal text `\037`.)

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
the client. Killing a session's last window from the grid destroys the session, so it follows the same rules:
refused for the sole window of the sole session (and dropped from the footer), and the client is
moved to the neighbour session first when it is attached there. Session kill arms a footer-inline `y/N` confirm (same row rename uses): `X` paints the
prompt with no `draw` and no cache drop, `y` commits through `do_kill_session`, anything else
(arrows included — their escape bytes are consumed) redraws unchanged, and lone `Esc` aborts instead
of quitting. Rename drops out of raw nav mode into a char-by-char `read_name` loop on the footer row
(never in `$()` so the prompt reaches the popup tty); empty input or `Esc` redraws unchanged. Any
escape sequence (arrows, Delete…) also aborts, and `drain_esc` consumes its tail — otherwise the
`C` of a Right arrow would run as `c` (new window) and the `3` of Delete as a digit jump.
Session rename also drops the cached medallion (`SESS_MED`); window rename keeps the snapshot cache
(keyed by stable `@id`) while titles rebuild in `refresh_to`.
