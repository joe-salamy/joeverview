#!/usr/bin/env bash
# content-search harness: stub-tmux + stub-fzf ordering check for bin/tmux-content-search.
# No live tmux server needed. The canned fzf match lives in another session,
# so the jump must switch-client before select-window, ending on select-pane.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T=$(mktemp -d "${TMPDIR:-/tmp}/jv-search.XXXXXX")
trap 'rm -rf "$T"' EXIT

fail() { echo "FAIL $1"; exit 1; }

mkdir -p "$T/bin"
cat > "$T/bin/tmux" <<'STUB'
#!/usr/bin/env bash
# Stub tmux for content-search harness. Env: CALL_LOG.
cmd=${1:-}; shift || true
case "$cmd" in
  list-panes)
    printf '%s\x1f%s\n' '%p9' 'main:0:win'
    ;;
  capture-pane)
    printf 'hello world\n'
    ;;
  display-message)
    if [[ " $* " == *" -t "* ]]; then
      printf '$s9 @w9\n'
    else
      printf '$s0\n'
    fi
    ;;
  switch-client|select-window|select-pane)
    printf '%s %s\n' "$cmd" "$*" >> "$CALL_LOG"
    ;;
  *) exit 0 ;;
esac
STUB
chmod +x "$T/bin/tmux"
cat > "$T/bin/fzf" <<'STUB'
#!/usr/bin/env bash
# Canned single match: field 1 is the %pane_id, fields split on \x1f.
printf '%s\x1f%s\x1f%s\n' '%p9' 'ctx' 'line'
STUB
chmod +x "$T/bin/fzf"

: > "$T/calls"
PATH="$T/bin:$PATH" CALL_LOG="$T/calls" bash "$REPO/bin/tmux-content-search" >/dev/null 2>&1 || fail "content-search exit"
grep -qF 'switch-client -t $s9' "$T/calls" || fail "search switch-client log"
grep -qF 'select-window -t @w9' "$T/calls" || fail "search select-window log"
sw=$(grep -nF 'switch-client' "$T/calls" | head -1 | cut -d: -f1)
ww=$(grep -nF 'select-window' "$T/calls" | head -1 | cut -d: -f1)
(( sw < ww )) || fail "search jump order"
tail -1 "$T/calls" | grep -qF 'select-pane -t %p9' || fail "search select-pane last"

echo "search: PASS"
