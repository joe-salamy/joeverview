#!/usr/bin/env bash
# grid-render harness: stub-tmux golden + interaction checks for bin/tmux-window-picker.
# No live tmux server needed. Stub answers fixed 30x60 geometry (cell_w=26,
# title_w=24, band_h=10, snap_h=9, vx=29, bot_y=28, mid_y=13).
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXBASE="$REPO/tests/fixtures"
T=$(mktemp -d "${TMPDIR:-/tmp}/jv-render.XXXXXX")
trap 'rm -rf "$T"' EXIT

fail() { echo "FAIL $1"; exit 1; }

# Write stub tmux into $1/bin/tmux (executable). Reads $FIXDIR + $CALL_LOG.
mk_stub() {
  mkdir -p "$1/bin"
  cat > "$1/bin/tmux" <<'STUB'
#!/usr/bin/env bash
# Stub tmux for grid-render harness. Env: FIXDIR (fixture dir), CALL_LOG.
cmd=${1:-}; shift || true
case "$cmd" in
  display-message)
    case "$*" in
      *client_height*) printf '30 60\n' ;;
      *session_id*) printf '%s %s\n' "${CUR_SID:-\$s0}" "${CUR_WID:-@w0}" ;;
      *pane_current_path*) printf '/tmp\n' ;;
    esac
    exit 0
    ;;
  list-sessions)
    cat "$FIXDIR/sessions"
    ;;
  list-windows)
    sid=""; prev=""
    for a in "$@"; do
      if [[ $prev == "-t" ]]; then sid=$a; fi
      prev=$a
    done
    key=$(printf '%s' "$sid" | tr -cd 'A-Za-z0-9_')
    cat "$FIXDIR/windows_$key"
    ;;
  capture-pane)
    id=""; prev=""
    for a in "$@"; do
      if [[ $prev == "-t" ]]; then id=$a; fi
      prev=$a
    done
    key=$(printf '%s' "$id" | tr -cd 'A-Za-z0-9_')
    if [[ -f "$FIXDIR/cap_$key" ]]; then cat "$FIXDIR/cap_$key"
    else printf 'cap-%s-line1\ncap-%s-line2\n' "$id" "$id"
    fi
    ;;
  select-window|switch-client|kill-window|new-window|kill-session|new-session|swap-window|select-pane)
    printf '%s %s\n' "$cmd" "$*" >> "$CALL_LOG"
    if [[ $cmd == new-window ]]; then printf '@wnew\n'; fi
    if [[ $cmd == new-session ]]; then printf '$snew\n'; fi
    ;;
  *) exit 0 ;;
esac
STUB
  chmod +x "$1/bin/tmux"
}

# run_picker <fixture> <printf-%b-input> <outfile> [call_log]
run_picker() {
  local fix=$1 input=$2 out=$3 log=${4:-/dev/null}
  local r
  r=$(mktemp -d "$T/run.XXXXXX")
  mk_stub "$r"
  : > "$r/err"
  FIXDIR="$FIXBASE/$fix" CALL_LOG="$log" PATH="$r/bin:$PATH" \
    bash -c 'printf "%b" "$0" | bash "$1/bin/tmux-window-picker" > "$2" 2>"$3"' \
    "$input" "$REPO" "$out" "$r/err"
}

# (a) q-only goldens for n1-n4 + multi
for name in n1 n2 n3 n4 multi; do
  [[ -f "$FIXBASE/golden-$name.out" ]] || fail "golden-$name missing"
  run_picker "$name" 'q' "$T/out-$name"
  cmp -s "$T/out-$name" "$FIXBASE/golden-$name.out" || fail "golden-$name diff"
done

# (b) zero literal \x1b sequences over rendered output
for f in "$T"/out-* "$FIXBASE"/golden-*.out; do
  grep -qF '\x1b' "$f" && fail "literal-x1b in $f"
done

# (c) n4 Right-arrow moves selection 0 -> 1 (tail = final repaint state)
run_picker n4 '\x1b[Cq' "$T/out-c"
SEL1=$(printf '\x1b[7m[1]')
SEL0=$(printf '\x1b[7m[0]')
grep -qF "$SEL1" "$T/out-c" || fail "arrow-move select"
tail -c 1024 "$T/out-c" | grep -qF "$SEL1" || fail "arrow-move tail-select"
tail -c 1024 "$T/out-c" | grep -qF "$SEL0" && fail "arrow-move stale-select"

# (d) six fed 2 selects @w2
: > "$T/calls-d"
run_picker six '2' "$T/out-d" "$T/calls-d"
grep -qF 'select-window -t @w2' "$T/calls-d" || fail "digit-jump log"

# (e) six fed 4x Down pages to index 5
run_picker six '\x1b[B\x1b[B\x1b[B\x1b[Bq' "$T/out-e"
grep -qF '[5] win5' "$T/out-e" || fail "page-follow content"

# (f) n2 fed . swaps selected window right (@w0 <-> @w1)
: > "$T/calls-f"
run_picker n2 '.q' "$T/out-f" "$T/calls-f"
grep -qF 'swap-window -s @w0 -t @w1' "$T/calls-f" || fail "move-right log"

# (g) n2 fed n creates a session
: > "$T/calls-g"
run_picker n2 'nq' "$T/out-g" "$T/calls-g"
grep -qF 'new-session' "$T/calls-g" || fail "new-session log"

# (h) multi fed Up+X kills the viewed session from the bar
: > "$T/calls-h"
run_picker multi '\x1b[AXq' "$T/out-h" "$T/calls-h"
grep -qF 'kill-session -t $s0' "$T/calls-h" || fail "kill-session log"

# (b) again over scenario outputs
for f in "$T"/out-c "$T"/out-d "$T"/out-e "$T"/out-f "$T"/out-g "$T"/out-h; do
  grep -qF '\x1b' "$f" && fail "literal-x1b in $f"
done

echo "render: PASS"
