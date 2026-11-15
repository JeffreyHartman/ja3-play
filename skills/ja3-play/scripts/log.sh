#!/usr/bin/env bash
# Prints Lua errors with their stack lines, mod load errors, and the lines that match a tag pattern, from the newest debug build log.
# Usage: log.sh [-f | -a] [-s MARK] [tag-regex]
#   -f          follow the log while the game runs
#   -a          print the whole log, unfiltered
#   -s MARK     start after the last log line that contains the text MARK, for example a [PROBE] line that you printed
#   tag-regex   extra lines to keep, default '\[PROBE\]'. For quickdraw: '\[IIS\]|\[PROBE\]'
set -euo pipefail
source "$(dirname "$0")/env.sh"

mode="" mark=""
while getopts "fas:" opt; do
	case "$opt" in
		f | a) mode="-$opt" ;;
		s) mark="$OPTARG" ;;
		*) sed -n '2,7p' "$0" >&2; exit 2 ;;
	esac
done
shift $((OPTIND - 1))
export JA3_TAGS="${1:-\[PROBE\]}"

newest="$(ls -t "$JA3_LOGS"/JA3Debug.exe-*.log | head -1)"

# The game buffers its log, so the newest lines are not in the file until a flush.
if ss -ltn | grep -q ":$JA3_PORT "; then
	"$(dirname "$0")/lua.py" -e 'FlushLogFile()' >/dev/null || true
fi

start=1
if [ -n "$mark" ]; then
	n="$(grep -nF -- "$mark" "$newest" | tail -1 | cut -d: -f1 || true)"
	if [ -z "$n" ]; then
		echo "mark not found: $mark" >&2
		exit 1
	fi
	start="$n"
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

echo "== $newest from line $start" >&2
case "$mode" in
	-f) tail -n "+$start" -F "$newest" | awk "$filter" ;;
	-a) tail -n "+$start" "$newest" ;;
	*) tail -n "+$start" "$newest" | awk "$filter" ;;
esac
