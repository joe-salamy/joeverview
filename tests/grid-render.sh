#!/usr/bin/env bash
# grid-render harness: stub-tmux golden + interaction checks for bin/tmux-window-picker.
# Goldens are byte-exact; bless with UPDATE_GOLDEN=1 CONFIRM_EYEBALL=1 only after eyeballing the diff; never commit a bless alongside a behavior change.
# UPDATE_GOLDEN=1 CONFIRM_EYEBALL=1 re-blesses five q-only goldens (n1-n4, multi) plus two geometry goldens in (t)/(u).
# Label (b) is intentionally skipped. CI fails on a dirty tree so an accidental bless is loud.
# No live tmux server needed. Stub defaults to 30x60 geometry (cell_w=26,
# title_w=24, band_h=10, snap_h=9, vx=29, bot_y=28, mid_y=13); STUB_H/STUB_W
# in the environment override the stub canvas (small-geometry cases (t)/(u)).
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXBASE="$REPO/tests/fixtures"
T=$(mktemp -d "${TMPDIR:-/tmp}/jv-render.XXXXXX")
trap 'rm -rf "$T"' EXIT

fail() { echo "FAIL $1" >&2; exit 1; }

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
get_t() { local prev="" t="" a; for a in "$@"; do if [[ $prev == "-t" ]]; then t=$a; fi; prev=$a; done; printf '%s' "$t"; }
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
    if [[ " $* " == *" -a "* ]]; then
      # Batched query: prefix each session's fixture rows with its sid, in
      # sessions-file order like tmux groups list-windows -a. IFS= keeps
      # the trailing empty alert field byte-identical to the -t path.
      while IFS=$'\t' read -r sid _rest; do
        key=$(printf '%s' "$sid" | tr -cd 'A-Za-z0-9_')
        [[ -f "$FIXDIR/windows_$key" ]] || continue
        while IFS= read -r line; do printf '%s\t%s\n' "$sid" "$line"; done < "$FIXDIR/windows_$key"
      done < "$FIXDIR/sessions"
    else
      sid=$(get_t "$@")
      key=$(printf '%s' "$sid" | tr -cd 'A-Za-z0-9_')
      cat "$FIXDIR/windows_$key"
    fi
    ;;
  capture-pane)
    if [[ -n ${CAP_EMPTY:-} ]]; then printf ''; exit 0; fi
    id=$(get_t "$@")
    key=$(printf '%s' "$id" | tr -cd 'A-Za-z0-9_')
    if [[ -f "$FIXDIR/cap_$key" ]]; then cat "$FIXDIR/cap_$key"
    else printf 'cap-%s-line1\ncap-%s-line2\n' "$id" "$id"
    fi
    ;;
  new-window)
    printf '%s %s\n' "$cmd" "$*" >> "$CALL_LOG"
    if [[ -n ${ON_NEW_WINDOW:-} && -f ${ON_NEW_WINDOW:-} ]]; then
      sid=$(get_t "$@")
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
    tgt=$(get_t "$@")
    if [[ -n $tgt && -f "$FIXDIR/sessions" ]]; then grep -vF "$tgt" "$FIXDIR/sessions" > "$FIXDIR/sessions.tmp" && mv "$FIXDIR/sessions.tmp" "$FIXDIR/sessions"; fi
    ;;
  rename-session)
    printf '%s %s\n' "$cmd" "$*" >> "$CALL_LOG"
    sid=$(get_t "$@")
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
  local r fdir st
  r=$(mktemp -d "$T/run.XXXXXX")
  fdir=$(mktemp -d "$T/fix.XXXXXX")
  cp -r "$FIXBASE/$fix/." "$fdir/"
  mk_stub "$r"
  : > "$r/err"
  STUB_H="${STUB_H:-}" STUB_W="${STUB_W:-}" FIXDIR="$fdir" CALL_LOG="$log" PATH="$r/bin:$PATH" \
    bash -c 'printf "%b" "$0" | bash "$1/bin/tmux-window-picker" > "$2" 2>"$3"' \
    "$input" "$REPO" "$out" "$r/err"
  st=$?; (( st == 0 )) || fail "picker exit $st ($fix)"
  [ -s "$r/err" ] && { cat "$r/err" >&2; fail "picker stderr ($fix)"; }
}

# run_dynamic <tag> <printf-%b-input> <outfile> <call_log> — dynamic-fixture
# runner sharing run_picker's stub/env-run prelude. Caller prepares $T/dyn-<tag>
# contents first; hook env (CUR_SID/CUR_WID/STUB_H/STUB_W/CAP_EMPTY/ON_NEW_*)
# passes through like run_picker's callers set it inline.
run_dynamic() {
  local tag=$1 input=$2 out=$3 log=$4
  local r st
  r=$(mktemp -d "$T/run-$tag.XXXXXX")
  mk_stub "$r"
  : > "$log"; : > "$r/err"
  STUB_H="${STUB_H:-}" STUB_W="${STUB_W:-}" CUR_SID="${CUR_SID:-}" CUR_WID="${CUR_WID:-}" \
  CAP_EMPTY="${CAP_EMPTY:-}" ON_NEW_WINDOW="${ON_NEW_WINDOW:-}" ON_NEW_SESSION="${ON_NEW_SESSION:-}" \
  FIXDIR="$T/dyn-$tag" CALL_LOG="$log" PATH="$r/bin:$PATH" \
    bash -c 'printf "%b" "$0" | bash "$1/bin/tmux-window-picker" > "$2" 2>"$3"' \
    "$input" "$REPO" "$out" "$r/err"
  st=$?; (( st == 0 )) || fail "picker exit $st (dyn-$tag)"
  [ -s "$r/err" ] && { cat "$r/err" >&2; fail "picker stderr (dyn-$tag)"; }
}

# (a) q-only goldens for n1-n4 + multi
for name in n1 n2 n3 n4 multi; do
  if [[ ${UPDATE_GOLDEN:-} == 1 && ${CONFIRM_EYEBALL:-} == 1 ]]; then
    run_picker "$name" 'q' "$FIXBASE/golden-$name.out"
  else
    run_picker "$name" 'q' "$T/out-$name"
    cmp -s "$T/out-$name" "$FIXBASE/golden-$name.out" || fail "golden-$name diff"
  fi
done
check_no_literal_esc() { for f in "$@"; do grep -qF '\x1b' "$f" && fail "literal-x1b in $f"; done; }


# (c) n4 Right-arrow moves selection 0 -> 1 (tail = final repaint state)
run_picker n4 '\x1b[Cq' "$T/out-c"
SEL1=$(printf '\x1b[7m[1]')
SEL0=$(printf '\x1b[7m[0]')
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
grep -qF 'main' "$T/out-i" || fail "single-session medallion missing"
tail -c 2048 "$T/out-i" | grep -qF 'session 1/1' || fail "single-session bar footer"

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
mkdir -p "$T/dyn-p"
cp "$FIXBASE/n1/sessions" "$T/dyn-p/sessions"
cp "$FIXBASE/n1/windows_s0" "$T/dyn-p/windows_s0"
printf '@w9\t0\twin9\tt9\t/tmp/w9\t1\t\n' > "$T/dyn-p/windows_snew"
printf '$snew\tsecond\n' > "$T/dyn-p/on_new_session"
ON_NEW_SESSION="$T/dyn-p/on_new_session" run_dynamic p '\x1b[AN\x1b[Dq' "$T/out-p" "$T/calls-p"
grep -qF 'new-session' "$T/calls-p" || fail "medallion-1to2 new-session"
grep -qF '←  main  →' "$T/out-p" || fail "medallion-1to2 first-session-arrows"

# (q) kill middle session from the bar: Up+X arms, y confirms; pre-switch,
# then kill, land highlighted on C
mkdir -p "$T/dyn-q"
printf '$s0\tA\n$s1\tB\n$s2\tC\n' > "$T/dyn-q/sessions"
printf '@w0\t0\twin0\tt0\t/tmp/w0\t1\t\n' > "$T/dyn-q/windows_s0"
printf '@w1\t0\twin1\tt1\t/tmp/w1\t1\t\n' > "$T/dyn-q/windows_s1"
printf '@w2\t0\twin2\tt2\t/tmp/w2\t1\t\n' > "$T/dyn-q/windows_s2"
CUR_SID='$s1' CUR_WID='@w1' STUB_W=140 run_dynamic q '\x1b[AXyq' "$T/out-q" "$T/calls-q"
grep -qF 'switch-client -t $s2' "$T/calls-q" || fail "kill-preswitch target"
grep -qF 'kill-session -t $s1' "$T/calls-q" || fail "kill-middle log"
sw=$(grep -nF 'switch-client' "$T/calls-q" | head -1 | cut -d: -f1)
kw=$(grep -nF 'kill-session' "$T/calls-q" | head -1 | cut -d: -f1)
(( sw < kw )) || fail "kill-preswitch order"
grep -qF 'select-window' "$T/calls-q" && fail "kill-middle jumped to window"
tail -c 8192 "$T/out-q" | grep -qF '←  C  →' || fail "kill-middle tail on C"
tail -c 8192 "$T/out-q" | grep -qF "$(printf '  \x1b[7m←  C  →\x1b[0m  ')" || fail "kill-middle C highlighted"
tail -c 2048 "$T/out-q" | grep -qF 'session 2/2' || fail "kill-middle session footer"

# (r) rename session from the bar: stay highlighted on the new name
mkdir -p "$T/dyn-r"
printf '$s0\tmain\n$s1\tother\n' > "$T/dyn-r/sessions"
printf '@w0\t0\twin0\tt0\t/tmp/w0\t1\t\n' > "$T/dyn-r/windows_s0"
printf '@w2\t0\twin2\tt2\t/tmp/w2\t1\t\n' > "$T/dyn-r/windows_s1"
CUR_SID='$s0' CUR_WID='@w0' STUB_W=140 run_dynamic r '\x1b[ARnewname\nq' "$T/out-r" "$T/calls-r"
grep -qF 'rename-session -t $s0 newname' "$T/calls-r" || fail "rename-session log"
grep -qF 'select-window' "$T/calls-r" && fail "rename jumped to window"
grep -qF 'switch-client' "$T/calls-r" && fail "rename reattached"
tail -c 8192 "$T/out-r" | grep -qF "$(printf '  \x1b[7m←  newname  →\x1b[0m  ')" || fail "rename new name highlighted"
tail -c 2048 "$T/out-r" | grep -qF 'session 1/2' || fail "rename session footer"

# (s) create with empty capture stays open (fresh shell pre-paint leaves SNAP
# unpinned; draw must tolerate the missing entry instead of aborting under set -u)
mkdir -p "$T/dyn-s"
printf '$s0\tmain\n' > "$T/dyn-s/sessions"
printf '@w0\t0\twin0\tt0\t/tmp/w0\t1\t\n' > "$T/dyn-s/windows_s0"
printf '@wnew\t2\tnew\ttnew\t/tmp/new\t1\t\n' > "$T/dyn-s/on_new_window"
printf '$snew\tsecond\n' > "$T/dyn-s/on_new_session"
printf '@snew0\t0\tfish\tfish\t/tmp\t1\t\n' > "$T/dyn-s/windows_snew"
# (s1) c with empty new-pane capture: stays open, lands highlighted, no attach
CAP_EMPTY=1 ON_NEW_WINDOW="$T/dyn-s/on_new_window" run_dynamic s 'cq' "$T/out-s1" "$T/calls-s1"
grep -qF 'new-window' "$T/calls-s1" || fail "empty-capture c creates"
grep -qF 'select-window' "$T/calls-s1" && fail "empty-capture c jumped"
grep -qF 'switch-client' "$T/calls-s1" && fail "empty-capture c reattached"
grep -qF '[2] new' "$T/out-s1" || fail "empty-capture c lands on new"
tail -c 8192 "$T/out-s1" | grep -qF "$(printf '\x1b[7m[2]')" || fail "empty-capture c highlighted"
# reset state for the session case
printf '$s0\tmain\n' > "$T/dyn-s/sessions"
printf '@w0\t0\twin0\tt0\t/tmp/w0\t1\t\n' > "$T/dyn-s/windows_s0"
# (s2) N with empty new-pane capture: stays open, lands on new session, no attach
CAP_EMPTY=1 ON_NEW_SESSION="$T/dyn-s/on_new_session" STUB_W=140 run_dynamic s '\x1b[ANq' "$T/out-s2" "$T/calls-s2"
grep -qF 'new-session' "$T/calls-s2" || fail "empty-capture N creates"
grep -qF 'select-window' "$T/calls-s2" && fail "empty-capture N jumped"
grep -qF 'switch-client' "$T/calls-s2" && fail "empty-capture N reattached"
grep -qF 'second' "$T/out-s2" || fail "empty-capture N lands on new"
tail -c 8192 "$T/out-s2" | grep -qF "$(printf '  \x1b[7m←  second  →\x1b[0m  ')" || fail "empty-capture N highlighted"
tail -c 2048 "$T/out-s2" | grep -qF 'session 2/2' || fail "empty-capture N footer"
# (s3) empty pane_title does not shift later fields: title keeps
# [index] name │  │ /path and the ⧉ badge survives
mkdir -p "$T/dyn-et"
printf '$s0\tmain\n' > "$T/dyn-et/sessions"
printf '@w0\t0\twin0\t\t/tmp/w0\t2\t\n' > "$T/dyn-et/windows_s0"
STUB_W=140 run_dynamic et 'q' "$T/out-et" "$T/calls-et"
grep -qF '[0] win0 │  │ /tmp/w0 ⧉ 2' "$T/out-et" || fail "empty-title shape"
# (s4) window linked into two sessions: opening from the second session
# highlights its occurrence there and Enter targets that session
mkdir -p "$T/dyn-lw"
printf '$s0\tA\n$s1\tB\n' > "$T/dyn-lw/sessions"
printf '@w0\t0\twin0\tt0\t/tmp/w0\t1\t\n' > "$T/dyn-lw/windows_s0"
printf '@w0\t0\twin0\tt0\t/tmp/w0\t1\t\n' > "$T/dyn-lw/windows_s1"
CUR_SID='$s1' CUR_WID='@w0' STUB_W=140 run_dynamic lw 'q' "$T/out-lw" "$T/calls-lw"
grep -qF '←  B  →' "$T/out-lw" || fail "linked medallion shows viewed session"
grep -qF "$(printf '\x1b[7m[0]')" "$T/out-lw" || fail "linked highlights viewed occurrence"
CUR_SID='$s1' CUR_WID='@w0' STUB_W=140 run_dynamic lw '\n' "$T/out-lw2" "$T/calls-lw2"
grep -qF 'select-window -t @w0' "$T/calls-lw2" || fail "linked enter selects window"
grep -qF 'switch-client -t $s0' "$T/calls-lw2" && fail "linked enter hit other session"
grep -qF 'switch-client' "$T/calls-lw2" && fail "linked enter switched while attached"

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
assert vw <= W, (vw, W, repr(tail[-60:]))
PY
}

# (t) 40x12 n2 q-only: title-only cells (band_h=1, snap_h=0), one-line footer
if [[ ${UPDATE_GOLDEN:-} == 1 && ${CONFIRM_EYEBALL:-} == 1 ]]; then
  STUB_H=12 STUB_W=40 run_picker n2 'q' "$FIXBASE/golden-small40x12-n2.out"
  OUT_T="$FIXBASE/golden-small40x12-n2.out"
else
  STUB_H=12 STUB_W=40 run_picker n2 'q' "$T/out-t"
  cmp -s "$T/out-t" "$FIXBASE/golden-small40x12-n2.out" || fail "golden-small40x12 diff"
  OUT_T="$T/out-t"
fi
bounds_check "$OUT_T" 12 40
grep -qF '╰' "$OUT_T" || fail "small40x12 bottom border"
grep -qF '╯' "$OUT_T" || fail "small40x12 bottom border"

# (u) 70x20 six Right-arrow: footer-wrap regime above the clamp regime
if [[ ${UPDATE_GOLDEN:-} == 1 && ${CONFIRM_EYEBALL:-} == 1 ]]; then
  STUB_H=20 STUB_W=70 run_picker six '\x1b[Cq' "$FIXBASE/golden-mid70x20-six.out"
  OUT_U="$FIXBASE/golden-mid70x20-six.out"
else
  STUB_H=20 STUB_W=70 run_picker six '\x1b[Cq' "$T/out-u"
  cmp -s "$T/out-u" "$FIXBASE/golden-mid70x20-six.out" || fail "golden-mid70x20 diff"
  OUT_U="$T/out-u"
fi
bounds_check "$OUT_U" 20 70
grep -qF "$(printf '\x1b[7m[1]')" "$OUT_U" || fail "mid70x20 arrow-move select"

# (v) wide canvas: footer fits, so paint_footer takes the python-skipping
# fast path. Regression: the fast path appended $'\n' to the bottom-row
# payload, scrolling the popup one line per full draw (top border and
# session medallion lost at start, worse with every move). Narrow
# harnesses never take the fast path, so assert zero raw newline/CR bytes
# over the whole output — one per draw pre-fix — plus bounds + medallion.
STUB_H=30 STUB_W=200 run_picker n1 'q' "$T/out-v"
[ "$(tr -d -c '\n\r' < "$T/out-v" | wc -c)" -eq 0 ] || fail "wide q-only scrolled"
bounds_check "$T/out-v" 30 200
grep -qF 'main' "$T/out-v" || fail "wide medallion missing"
STUB_H=30 STUB_W=200 run_picker n1 '\x1b[A\x1b[Bq' "$T/out-v2"
[ "$(tr -d -c '\n\r' < "$T/out-v2" | wc -c)" -eq 0 ] || fail "wide moves scrolled"
bounds_check "$T/out-v2" 30 200

check_no_literal_esc "$T"/out-* "$OUT_T" "$OUT_U"
# Negative self-test: an over-wide footer must fail bounds_check
printf '\x1b[1;1H\x1b[K%s' '123456' > "$T/out-wide-neg"
if ( bounds_check "$T/out-wide-neg" 1 3 2>/dev/null ); then fail "bounds-negative missed"; fi


echo "render: PASS"
