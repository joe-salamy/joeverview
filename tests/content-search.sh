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
# Stub tmux for content-search harness. Env: CALL_LOG, CAPTURE_LOG, FAIL_SWITCH.
cmd=${1:-}; shift || true
case "$cmd" in
  list-panes)
    if [[ " $* " != *" -a "* ]]; then printf 'FAIL list-panes -a flag\n' >&2; exit 1; fi
    printf '%s %s\n' '%p1' 'main:0:winA'
    printf '%s %s\n' '%p9' 'other:0:winB'
    ;;
  capture-pane)
    printf '%s\n' "$*" >> "${CAPTURE_LOG:-/dev/null}"
    printf 'hello world\n   \n\nback\\slash\n'
    ;;
  switch-client)
    printf '%s %s\n' "$cmd" "$*" >> "${CALL_LOG:-/dev/null}"
    if [[ -n ${FAIL_SWITCH:-} ]]; then printf "can't find pane\n" >&2; exit 1; fi
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

# Jump: the chosen %p9 row targets its pane id in one switch-client.
: > "$T/calls"; : > "$T/capture"; : > "$T/rows"
PATH="$T/bin:$PATH" CALL_LOG="$T/calls" CAPTURE_LOG="$T/capture" ROWS_LOG="$T/rows" FZF_PANE='%p9' \
  bash "$REPO/bin/tmux-content-search" >/dev/null 2>&1 || fail "content-search exit"
grep -qF -- '-S -500' "$T/capture" || fail "capture depth flag"
grep -qF -- '-t %p1' "$T/capture" || fail "capture targets pane 1"
grep -qF -- '-t %p9' "$T/capture" || fail "capture targets pane 9"
grep -qF '%p9' "$T/rows" || fail "rows carry pane id"
grep -qF 'hello world' "$T/rows" || fail "rows carry capture text"
grep -qF "$(printf '\037')" "$T/rows" || fail "rows use unit separator"
[ "$(wc -l < "$T/rows")" -eq 4 ] || fail "blank lines filtered (2 panes x 2 rows)"
grep -qF 'back\slash' "$T/rows" || fail "backslashes kept verbatim"
[ "$(cat "$T/calls")" = 'switch-client -t %p9' ] || fail "search jump targets the pane"

# Dead pane: switch-client fails; must exit 0 with no output leak.
: > "$T/calls3"; : > "$T/capture3"; : > "$T/rows3"
PATH="$T/bin:$PATH" CALL_LOG="$T/calls3" CAPTURE_LOG="$T/capture3" ROWS_LOG="$T/rows3" FZF_PANE='%p9' FAIL_SWITCH=1 \
  bash "$REPO/bin/tmux-content-search" >"$T/dead-out" 2>"$T/dead-err" || fail "dead-pane exit"
[ -s "$T/dead-out" ] && fail "dead-pane stdout leak"
[ -s "$T/dead-err" ] && fail "dead-pane stderr leak"

echo "search: PASS"
