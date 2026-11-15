#!/usr/bin/env bash
# Prints Lua errors with their stack lines, mod load errors, and the lines that match a tag pattern, from the newest debug build log.
# Usage: log.sh [-f | -a] [tag-regex]
#   -f          follow the log while the game runs
#   -a          print the whole log, unfiltered
#   tag-regex   extra lines to keep, default '\[PROBE\]'. For quickdraw: '\[IIS\]|\[PROBE\]'
set -euo pipefail
source "$(dirname "$0")/env.sh"

mode=""
case "${1:-}" in -f | -a) mode="$1"; shift ;; esac
export JA3_TAGS="${1:-\[PROBE\]}"

newest="$(ls -t "$JA3_LOGS"/JA3Debug.exe-*.log | head -1)"

# The game buffers its log, so the newest lines are not in the file until a flush.
if ss -ltn | grep -q ":$JA3_PORT "; then
	"$(dirname "$0")/lua.py" -e 'FlushLogFile()' >/dev/null || true
fi

# The tag pattern goes through ENVIRON because awk -v drops its backslashes.
# Stack lines after [LUA ERROR] start with two spaces. A mod load error puts its message on the next line.
filter='
	$0 ~ ENVIRON["JA3_TAGS"] { print; fflush(); stack = 0; next }
	/\[LUA ERROR\]/ { print; fflush(); stack = 1; next }
	/Errors while loading mod/ { print; fflush(); stack = 0; modline = 1; next }
	modline { print; fflush(); modline = 0; next }
	stack && /^  / { print; fflush(); next }
	{ stack = 0 }
'

echo "== $newest" >&2
case "$mode" in
	-f) tail -n +1 -F "$newest" | awk "$filter" ;;
	-a) cat "$newest" ;;
	*) awk "$filter" "$newest" ;;
esac
