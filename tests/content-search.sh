#!/usr/bin/env bash
# content-search harness: stub-tmux + stub-fzf ordering check for bin/tmux-content-search.
# No live tmux server needed. The stub list-panes requires the -a flag and
# emits rows across two sessions; capture-pane logs its flags; fzf saves its
# stdin (the real pipeline rows) and replays the chosen row, so the row-shape
# asserts below prove list-panes parsing, depth, blank filtering, and the
# separator instead of bypassing them with a canned constant.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T=$(mktemp -d "${TMPDIR:-/tmp}/jv-search.XXXXXX")
trap 'rm -rf "$T"' EXIT

fail() { echo "FAIL $1"; exit 1; }

mkdir -p "$T/bin"
cat > "$T/bin/tmux" <<'STUB'
#!/usr/bin/env bash
# Stub tmux for content-search harness. Env: CALL_LOG, CAPTURE_LOG, FAIL_DISPLAY.
get_t() { local prev="" t="" a; for a in "$@"; do if [[ $prev == "-t" ]]; then t=$a; fi; prev=$a; done; printf '%s' "$t"; }
cmd=${1:-}; shift || true
case "$cmd" in
  list-panes)
    if [[ " $* " != *" -a "* ]]; then printf 'FAIL list-panes -a flag\n' >&2; exit 1; fi
    printf '%s %s\n' '%p1' 'main:0:winA'
    printf '%s %s\n' '%p9' 'other:0:winB'
    ;;
  capture-pane)
    printf '%s\n' "$*" >> "${CAPTURE_LOG:-/dev/null}"
    printf 'hello world\n'
    ;;
  display-message)
    if [[ " $* " == *" -t "* ]]; then
      if [[ -n ${FAIL_DISPLAY:-} ]]; then exit 1; fi
      t=$(get_t "$@")
      if [[ $t == "%p1" ]]; then printf '$s0 @w1\n'; else printf '$s9 @w9\n'; fi
    else
      printf '$s0\n'
    fi
    ;;
  switch-client|select-window|select-pane)
    printf '%s %s\n' "$cmd" "$*" >> "${CALL_LOG:-/dev/null}"
    ;;
  *) exit 0 ;;
esac
STUB
chmod +x "$T/bin/tmux"
cat > "$T/bin/fzf" <<'STUB'
#!/usr/bin/env bash
# Save the real pipeline rows, then replay the chosen row (exits nonzero
# like real fzf when the choice is absent, so the caller exits quietly).
log=${ROWS_LOG:-/dev/null}
cat > "$log"
choice=${FZF_PANE:-%p9}
if grep -qF "$choice" "$log" 2>/dev/null; then
  grep -F -m1 "$choice" "$log"
else
  exit 1
fi
STUB
chmod +x "$T/bin/fzf"

# Static guard for the yank injection fix (load-bearing source-text assert).
grep -qF 'tmux set-buffer -- {3..}' "$REPO/bin/tmux-content-search" || fail "yank unquoted placeholder"
grep -qF '"{3..}"' "$REPO/bin/tmux-content-search" && fail "yank quoted placeholder"

# Cross-session: chosen %p9 lives in $s9, client in $s0.
: > "$T/calls"; : > "$T/capture"; : > "$T/rows"
PATH="$T/bin:$PATH" CALL_LOG="$T/calls" CAPTURE_LOG="$T/capture" ROWS_LOG="$T/rows" FZF_PANE='%p9' \
  bash "$REPO/bin/tmux-content-search" >/dev/null 2>&1 || fail "content-search exit"
grep -qF -- '-S -500' "$T/capture" || fail "capture depth flag"
grep -qF -- '-t %p1' "$T/capture" || fail "capture targets pane 1"
grep -qF -- '-t %p9' "$T/capture" || fail "capture targets pane 9"
grep -qF '%p9' "$T/rows" || fail "rows carry pane id"
grep -qF 'hello world' "$T/rows" || fail "rows carry capture text"
grep -qF "$(printf '\037')" "$T/rows" || fail "rows use unit separator"
grep -qF 'switch-client -t $s9' "$T/calls" || fail "search switch-client log"
grep -qF 'select-window -t @w9' "$T/calls" || fail "search select-window log"
sw=$(grep -nF 'switch-client' "$T/calls" | head -1 | cut -d: -f1)
ww=$(grep -nF 'select-window' "$T/calls" | head -1 | cut -d: -f1)
(( sw < ww )) || fail "search jump order"
tail -1 "$T/calls" | grep -qF 'select-pane -t %p9' || fail "search select-pane last"

# Same-session: chosen %p1 lives in $s0 with the client, so no switch-client.
: > "$T/calls2"; : > "$T/capture2"; : > "$T/rows2"
PATH="$T/bin:$PATH" CALL_LOG="$T/calls2" CAPTURE_LOG="$T/capture2" ROWS_LOG="$T/rows2" FZF_PANE='%p1' \
  bash "$REPO/bin/tmux-content-search" >/dev/null 2>&1 || fail "same-session exit"
grep -qF 'switch-client' "$T/calls2" && fail "same-session switched"
tail -1 "$T/calls2" | grep -qF 'select-pane -t %p1' || fail "same-session select-pane last"

# Dead pane: display-message -t fails; must exit 0 with no output leak.
: > "$T/calls3"; : > "$T/capture3"; : > "$T/rows3"
PATH="$T/bin:$PATH" CALL_LOG="$T/calls3" CAPTURE_LOG="$T/capture3" ROWS_LOG="$T/rows3" FZF_PANE='%p9' FAIL_DISPLAY=1 \
  bash "$REPO/bin/tmux-content-search" >"$T/dead-out" 2>"$T/dead-err" || fail "dead-pane exit"
[ -s "$T/dead-out" ] && fail "dead-pane stdout leak"
[ -s "$T/dead-err" ] && fail "dead-pane stderr leak"

echo "search: PASS"
