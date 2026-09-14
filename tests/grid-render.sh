#!/usr/bin/env bash
# grid-render harness: stub-tmux golden + interaction checks for bin/tmux-window-picker.
# No live tmux server needed. Stub defaults to 30x60 geometry (cell_w=26,
# title_w=24, band_h=10, snap_h=9, vx=29, bot_y=28, mid_y=13); STUB_H/STUB_W
# in the environment override the stub canvas (small-geometry cases (t)/(u)).
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXBASE="$REPO/tests/fixtures"
T=$(mktemp -d "${TMPDIR:-/tmp}/jv-render.XXXXXX")
trap 'rm -rf "$T"' EXIT

fail() { echo "FAIL $1"; exit 1; }

# Write stub tmux into $1/bin/tmux (executable). Reads $FIXDIR + $CALL_LOG.
# Hooks: CAP_EMPTY=1 prints empty captures (test s); ON_NEW_WINDOW/ON_NEW_SESSION
# point at files appended on new-window/new-session (tests p/s1/s2).
# kill-session/rename-session mutate $FIXDIR generically; run_picker copies
# fixtures to temp so the repo never dirties.
mk_stub() {
  mkdir -p "$1/bin"
  cat > "$1/bin/tmux" <<'STUB'
#!/usr/bin/env bash
# Stub tmux for grid-render harness. Env: FIXDIR (fixture dir), CALL_LOG,
# CAP_EMPTY, ON_NEW_WINDOW, ON_NEW_SESSION.
cmd=${1:-}; shift || true
case "$cmd" in
  display-message)
    case "$*" in
      *client_height*) printf '%s %s\n' "${STUB_H:-30}" "${STUB_W:-60}" ;;
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
    if [[ -n ${CAP_EMPTY:-} ]]; then printf ''; exit 0; fi
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
  new-window)
    printf '%s %s\n' "$cmd" "$*" >> "$CALL_LOG"
    if [[ -n ${ON_NEW_WINDOW:-} && -f ${ON_NEW_WINDOW:-} ]]; then
      sid=""; prev=""
      for a in "$@"; do
        if [[ $prev == "-t" ]]; then sid=$a; fi
        prev=$a
      done
      key=$(printf '%s' "$sid" | tr -cd 'A-Za-z0-9_')
      grep -qF '@wnew' "$FIXDIR/windows_$key" 2>/dev/null || cat "$ON_NEW_WINDOW" >> "$FIXDIR/windows_$key"
    fi
    printf '@wnew\n'
    ;;
  new-session)
    printf '%s %s\n' "$cmd" "$*" >> "$CALL_LOG"
    if [[ -n ${ON_NEW_SESSION:-} && -f ${ON_NEW_SESSION:-} ]]; then
      if ! grep -qF '$snew' "$FIXDIR/sessions" 2>/dev/null; then cat "$ON_NEW_SESSION" >> "$FIXDIR/sessions"; fi
    fi
    printf '$snew\n'
    ;;
  kill-session)
    printf '%s %s\n' "$cmd" "$*" >> "$CALL_LOG"
    tgt=""; prev=""
    for a in "$@"; do
      if [[ $prev == "-t" ]]; then tgt=$a; fi
      prev=$a
    done
    if [[ -n $tgt && -f "$FIXDIR/sessions" ]]; then grep -vF "$tgt" "$FIXDIR/sessions" > "$FIXDIR/sessions.tmp" && mv "$FIXDIR/sessions.tmp" "$FIXDIR/sessions"; fi
    ;;
  rename-session)
    printf '%s %s\n' "$cmd" "$*" >> "$CALL_LOG"
    sid=""; new=""; prev=""
    for a in "$@"; do
      if [[ $prev == "-t" ]]; then sid=$a; fi
      prev=$a
    done
    new="${@: -1}"
    if [[ -n $sid && -n $new && -f "$FIXDIR/sessions" ]]; then
      awk -v sid="$sid" -v new="$new" 'BEGIN{FS=OFS="\t"} $1==sid{$2=new} {print}' "$FIXDIR/sessions" > "$FIXDIR/sessions.tmp" && mv "$FIXDIR/sessions.tmp" "$FIXDIR/sessions"
    fi
    ;;
  select-window|switch-client|kill-window|swap-window|select-pane|rename-window)
    printf '%s %s\n' "$cmd" "$*" >> "$CALL_LOG"
    ;;
  *) exit 0 ;;
esac
STUB
  chmod +x "$1/bin/tmux"
}

# run_picker <fixture> <printf-%b-input> <outfile> [call_log]
# Copies the fixture to temp so stub mutations (new/kill/rename) never dirty the repo.
run_picker() {
  local fix=$1 input=$2 out=$3 log=${4:-/dev/null}
  local r fdir
  r=$(mktemp -d "$T/run.XXXXXX")
  fdir=$(mktemp -d "$T/fix.XXXXXX")
  cp -r "$FIXBASE/$fix/." "$fdir/"
  mk_stub "$r"
  : > "$r/err"
  STUB_H="${STUB_H:-}" STUB_W="${STUB_W:-}" FIXDIR="$fdir" CALL_LOG="$log" PATH="$r/bin:$PATH" \
    bash -c 'printf "%b" "$0" | bash "$1/bin/tmux-window-picker" > "$2" 2>"$3"' \
    "$input" "$REPO" "$out" "$r/err"
}

# (a) q-only goldens for n1-n4 + multi
for name in n1 n2 n3 n4 multi; do
  [[ -f "$FIXBASE/golden-$name.out" ]] || fail "golden-$name missing"
  if [[ ${UPDATE_GOLDEN:-} == 1 ]]; then
    run_picker "$name" 'q' "$FIXBASE/golden-$name.out"
  else
    run_picker "$name" 'q' "$T/out-$name"
    cmp -s "$T/out-$name" "$FIXBASE/golden-$name.out" || fail "golden-$name diff"
  fi
done

check_no_literal_esc() { for f in "$@"; do grep -qF '\x1b' "$f" && fail "literal-x1b in $f"; done; }
check_no_literal_esc "$T"/out-* "$FIXBASE"/golden-*.out

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

# (f) n2 fed > swaps selected window right (@w0 <-> @w1)
: > "$T/calls-f"
run_picker n2 '>q' "$T/out-f" "$T/calls-f"
grep -qF 'swap-window -s @w0 -t @w1' "$T/calls-f" || fail "move-right log"

# (g) multi fed Up+n creates a session from the bar (grid n is ignored)
: > "$T/calls-g"
run_picker multi '\x1b[Anq' "$T/out-g" "$T/calls-g"
grep -qF 'new-session' "$T/calls-g" || fail "new-session log"
: > "$T/calls-g2"
run_picker n2 'nq' "$T/out-g2" "$T/calls-g2"
grep -qF 'new-session' "$T/calls-g2" && fail "grid-n creates session"

# (h) multi fed Up+X+y confirms and kills the viewed session from the bar
: > "$T/calls-h"
run_picker multi '\x1b[AXyq' "$T/out-h" "$T/calls-h"
grep -qF 'kill-session -t $s0' "$T/calls-h" || fail "kill-session log"
grep -qF 'Kill session' "$T/out-h" || fail "kill confirm prompt"
grep -qF 'y/N' "$T/out-h" || fail "kill confirm hint"

# (h2) multi fed Up+X+n aborts the confirm (no kill)
: > "$T/calls-h2"
run_picker multi '\x1b[AXnq' "$T/out-h2" "$T/calls-h2"
grep -qF 'kill-session' "$T/calls-h2" && fail "confirm-n killed"
grep -qF 'Kill session' "$T/out-h2" || fail "confirm-n prompt missing"

# (h3) multi fed Up+X+Esc+Esc+N: first Esc is eaten as the abort's b-byte,
# the picker stays open (no quit) and N still creates a session, no kill
: > "$T/calls-h3"
run_picker multi '\x1b[AX\x1b\x1bNq' "$T/out-h3" "$T/calls-h3"
grep -qF 'kill-session' "$T/calls-h3" && fail "confirm-esc killed"
grep -qF 'new-session' "$T/calls-h3" || fail "confirm-esc quit instead of abort"

# (i) n1 (single session) fed Up focuses the bar anyway (STUB_W=140: the
# bar footer carries its trailing session counter only when it fits)
STUB_W=140 run_picker n1 '\x1b[Aq' "$T/out-i"

# (j) n1 fed Up+X must NOT kill the sole session (never even prompts)
: > "$T/calls-j"
run_picker n1 '\x1b[AXq' "$T/out-j" "$T/calls-j"
grep -qF 'kill-session' "$T/calls-j" && fail "sole-session killed"
grep -qF 'Kill session' "$T/out-j" && fail "sole-session prompted"

# (k) n2 fed Rname+Enter renames the selected window
: > "$T/calls-k"
run_picker n2 'Rwin-new\nq' "$T/out-k" "$T/calls-k"
grep -qF 'rename-window -t @w0 win-new' "$T/calls-k" || fail "rename-window log"

# (l) multi fed Up+Rname+Enter renames the viewed session
: > "$T/calls-l"
run_picker multi '\x1b[ARsess-new\nq' "$T/out-l" "$T/calls-l"
grep -qF 'rename-session -t $s0 sess-new' "$T/calls-l" || fail "rename-session log"

# (m) n2 fed R+Esc aborts the rename (no rename-window call, q quits)
: > "$T/calls-m"
run_picker n2 'R\x1bq' "$T/out-m" "$T/calls-m"
grep -qF 'rename-window' "$T/calls-m" && fail "esc-abort renamed"

# (n) n2 fed ,/. do nothing (move is < > only)
: > "$T/calls-n"
run_picker n2 ',.q' "$T/out-n" "$T/calls-n"
grep -qF 'swap-window' "$T/calls-n" && fail "comma-dot moved"

# (o) n2 fed Del does nothing (kill is X only)
: > "$T/calls-o"
run_picker n2 '\x7fq' "$T/out-o" "$T/calls-o"
grep -qF 'kill-window' "$T/calls-o" && fail "del killed"

# (p) 1->2 sessions: first session gains arrows after N + paging back
DYN="$T/dyn-p"; mkdir -p "$DYN"
cp "$FIXBASE/n1/sessions" "$DYN/sessions"
cp "$FIXBASE/n1/windows_s0" "$DYN/windows_s0"
printf '@w9\t0\twin9\tt9\t/tmp/w9\t1\t\n' > "$DYN/windows_snew"
printf '$snew\tsecond\n' > "$DYN/on_new_session"
RP=$(mktemp -d "$T/run-p.XXXXXX"); mk_stub "$RP"
: > "$T/calls-p"; : > "$RP/err"
ON_NEW_SESSION="$DYN/on_new_session" FIXDIR="$DYN" CALL_LOG="$T/calls-p" PATH="$RP/bin:$PATH" \
  bash -c 'printf "%b" "$0" | bash "$1/bin/tmux-window-picker" > "$2" 2>"$3"' \
  '\x1b[AN\x1b[Dq' "$REPO" "$T/out-p" "$RP/err"
grep -qF 'new-session' "$T/calls-p" || fail "medallion-1to2 new-session"
grep -qF '←  main  →' "$T/out-p" || fail "medallion-1to2 first-session-arrows"

# (q) kill middle session from the bar: Up+X arms, y confirms; pre-switch,
# then kill, land highlighted on C
QYN="$T/dyn-q"; mkdir -p "$QYN"
printf '$s0\tA\n$s1\tB\n$s2\tC\n' > "$QYN/sessions"
printf '@w0\t0\twin0\tt0\t/tmp/w0\t1\t\n' > "$QYN/windows_s0"
printf '@w1\t0\twin1\tt1\t/tmp/w1\t1\t\n' > "$QYN/windows_s1"
printf '@w2\t0\twin2\tt2\t/tmp/w2\t1\t\n' > "$QYN/windows_s2"
RQ=$(mktemp -d "$T/run-q.XXXXXX"); mk_stub "$RQ"
: > "$T/calls-q"; : > "$RQ/err"
CUR_SID='$s1' CUR_WID='@w1' STUB_W=140 FIXDIR="$QYN" CALL_LOG="$T/calls-q" PATH="$RQ/bin:$PATH" \
  bash -c 'printf "%b" "$0" | bash "$1/bin/tmux-window-picker" > "$2" 2>"$3"' \
  '\x1b[AXyq' "$REPO" "$T/out-q" "$RQ/err"
grep -qF 'switch-client -t $s2' "$T/calls-q" || fail "kill-preswitch target"
grep -qF 'kill-session -t $s1' "$T/calls-q" || fail "kill-middle log"
sw=$(grep -nF 'switch-client' "$T/calls-q" | head -1 | cut -d: -f1)
kw=$(grep -nF 'kill-session' "$T/calls-q" | head -1 | cut -d: -f1)
(( sw < kw )) || fail "kill-preswitch order"
grep -qF 'select-window' "$T/calls-q" && fail "kill-middle jumped to window"
grep -qF '←  C  →' "$T/out-q" || fail "kill-middle lands on C"
tail -c 8192 "$T/out-q" | grep -qF '←  C  →' || fail "kill-middle tail on C"
tail -c 8192 "$T/out-q" | grep -qF "$(printf '  \x1b[7m←  C  →\x1b[0m  ')" || fail "kill-middle C highlighted"
tail -c 2048 "$T/out-q" | grep -qF 'session 2/2' || fail "kill-middle session footer"

# (r) rename session from the bar: stay highlighted on the new name
RYN="$T/dyn-r"; mkdir -p "$RYN"
printf '$s0\tmain\n$s1\tother\n' > "$RYN/sessions"
printf '@w0\t0\twin0\tt0\t/tmp/w0\t1\t\n' > "$RYN/windows_s0"
printf '@w2\t0\twin2\tt2\t/tmp/w2\t1\t\n' > "$RYN/windows_s1"
RR=$(mktemp -d "$T/run-r.XXXXXX"); mk_stub "$RR"
: > "$T/calls-r"; : > "$RR/err"
CUR_SID='$s0' CUR_WID='@w0' STUB_W=140 FIXDIR="$RYN" CALL_LOG="$T/calls-r" PATH="$RR/bin:$PATH" \
  bash -c 'printf "%b" "$0" | bash "$1/bin/tmux-window-picker" > "$2" 2>"$3"' \
  '\x1b[ARnewname\nq' "$REPO" "$T/out-r" "$RR/err"
grep -qF 'rename-session -t $s0 newname' "$T/calls-r" || fail "rename-session log"
grep -qF 'select-window' "$T/calls-r" && fail "rename jumped to window"
grep -qF 'switch-client' "$T/calls-r" && fail "rename reattached"
grep -qF '←  newname  →' "$T/out-r" || fail "rename lands on new name"
tail -c 8192 "$T/out-r" | grep -qF "$(printf '  \x1b[7m←  newname  →\x1b[0m  ')" || fail "rename new name highlighted"
tail -c 2048 "$T/out-r" | grep -qF 'session 1/2' || fail "rename session footer"

# (s) create with empty capture stays open (fresh shell pre-paint leaves SNAP
# unpinned; draw must tolerate the missing entry instead of aborting under set -u)
SYN="$T/dyn-s"; mkdir -p "$SYN"
printf '$s0\tmain\n' > "$SYN/sessions"
printf '@w0\t0\twin0\tt0\t/tmp/w0\t1\t\n' > "$SYN/windows_s0"
printf '@wnew\t2\tnew\ttnew\t/tmp/new\t1\t\n' > "$SYN/on_new_window"
printf '$snew\tsecond\n' > "$SYN/on_new_session"
printf '@snew0\t0\tfish\tfish\t/tmp\t1\t\n' > "$SYN/windows_snew"
RS=$(mktemp -d "$T/run-s.XXXXXX"); mk_stub "$RS"
# (s1) c with empty new-pane capture: stays open, lands highlighted, no attach
: > "$T/calls-s1"; : > "$RS/err-s1"
CAP_EMPTY=1 ON_NEW_WINDOW="$SYN/on_new_window" FIXDIR="$SYN" CALL_LOG="$T/calls-s1" PATH="$RS/bin:$PATH" \
  bash -c 'printf "%b" "$0" | bash "$1/bin/tmux-window-picker" > "$2" 2>"$3"' \
  'cq' "$REPO" "$T/out-s1" "$RS/err-s1"
grep -qF 'new-window' "$T/calls-s1" || fail "empty-capture c creates"
grep -qF 'select-window' "$T/calls-s1" && fail "empty-capture c jumped"
grep -qF 'switch-client' "$T/calls-s1" && fail "empty-capture c reattached"
grep -qF '[2] new' "$T/out-s1" || fail "empty-capture c lands on new"
tail -c 8192 "$T/out-s1" | grep -qF "$(printf '\x1b[7m[2]')" || fail "empty-capture c highlighted"
# reset state for the session case
printf '$s0\tmain\n' > "$SYN/sessions"
printf '@w0\t0\twin0\tt0\t/tmp/w0\t1\t\n' > "$SYN/windows_s0"
# (s2) N with empty new-pane capture: stays open, lands on new session, no attach
: > "$T/calls-s2"; : > "$RS/err-s2"
CAP_EMPTY=1 ON_NEW_SESSION="$SYN/on_new_session" STUB_W=140 FIXDIR="$SYN" CALL_LOG="$T/calls-s2" PATH="$RS/bin:$PATH" \
  bash -c 'printf "%b" "$0" | bash "$1/bin/tmux-window-picker" > "$2" 2>"$3"' \
  '\x1b[ANq' "$REPO" "$T/out-s2" "$RS/err-s2"
grep -qF 'new-session' "$T/calls-s2" || fail "empty-capture N creates"
grep -qF 'select-window' "$T/calls-s2" && fail "empty-capture N jumped"
grep -qF 'switch-client' "$T/calls-s2" && fail "empty-capture N reattached"
grep -qF 'second' "$T/out-s2" || fail "empty-capture N lands on new"
tail -c 8192 "$T/out-s2" | grep -qF "$(printf '  \x1b[7m←  second  →\x1b[0m  ')" || fail "empty-capture N highlighted"
tail -c 2048 "$T/out-s2" | grep -qF 'session 2/2' || fail "empty-capture N footer"

# bounds_check <file> <H> <W>: every CUP address is inside the canvas and the
# final footer payload (bytes after the last footer-row EL) is one line <= W.
bounds_check() {
  python3 - "$1" "$2" "$3" <<'PY' || fail "bounds $1 ($2x$3)"
import re, sys, unicodedata
f, H, W = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
data = open(f, 'rb').read().decode('utf-8', 'replace')
for m in re.finditer(r'\x1b\[(\d+);(\d+)H', data):
    r, c = int(m.group(1)), int(m.group(2))
    assert r <= H and c <= W, (r, c, H, W)
tail = data.rsplit('\x1b[%d;1H\x1b[K' % H, 1)[-1]
tail = re.sub(r'\x1b\[[0-9;?]*[A-Za-z]', '', tail)
assert '\n' not in tail, repr(tail[-20:])
vw = sum(2 if unicodedata.east_asian_width(ch) in ('W', 'F') else (0 if unicodedata.combining(ch) else 1) for ch in tail)
PY
}

# (t) 40x12 n2 q-only: title-only cells (band_h=1, snap_h=0), one-line footer
STUB_H=12 STUB_W=40 run_picker n2 'q' "$T/out-t"
cmp -s "$T/out-t" "$FIXBASE/golden-small40x12-n2.out" || fail "golden-small40x12 diff"
grep -qF '\x1b' "$T/out-t" && fail "literal-x1b in out-t"
bounds_check "$T/out-t" 12 40
grep -qF '╰' "$T/out-t" || fail "small40x12 bottom border"
grep -qF '╯' "$T/out-t" || fail "small40x12 bottom border"

# (u) 70x20 six Right-arrow: footer-wrap regime above the clamp regime
STUB_H=20 STUB_W=70 run_picker six '\x1b[Cq' "$T/out-u"
cmp -s "$T/out-u" "$FIXBASE/golden-mid70x20-six.out" || fail "golden-mid70x20 diff"
grep -qF '\x1b' "$T/out-u" && fail "literal-x1b in out-u"
bounds_check "$T/out-u" 20 70
grep -qF "$(printf '\x1b[7m[1]')" "$T/out-u" || fail "mid70x20 arrow-move select"

check_no_literal_esc "$T"/out-*

echo "render: PASS"
