#!/usr/bin/env bash
# Prints Lua errors with their stack lines, mod load errors, and the lines that match a tag pattern, from the newest game log.
# Usage: log.sh [-f | -a] [-r] [-s MARK] [-e MARK] [-b debug|retail] [-w WIDTH] [-x REGEX] [tag-regex]
#   -f          follow the log while the game runs
#   -a          print all lines, not only the tag, error and mod load lines
#   -r          raw: keep the UserText errors and the -x lines, keep long unit ids, do not cut lines
#   -s MARK     start at the last log line that contains the text MARK, for example a [PROBE] line that you printed
#   -e MARK     stop at the first line after the start that contains the text MARK
#   -b BUILD    read the newest log of this build only: debug (JA3Debug.exe) or retail (JA3.exe). Default: the newest of both.
#   -w WIDTH    cut each line to WIDTH characters, default 260, 0 for no cut
#   -x REGEX    also drop the lines that match REGEX, for example 'collective=' for the quickdraw option dumps
#   tag-regex   extra lines to keep, default '\[PROBE\]'. For quickdraw: '\[IIS\]|\[PROBE\]'
set -euo pipefail
source "$(dirname "$0")/env.sh"

mode="" raw=0 mark="" endmark="" build="" width=260 drop=""
while getopts "fars:e:b:w:x:" opt; do
	case "$opt" in
		f | a) mode="-$opt" ;;
		r) raw=1 ;;
		s) mark="$OPTARG" ;;
		e) endmark="$OPTARG" ;;
		b) build="$OPTARG" ;;
		w) width="$OPTARG" ;;
		x) drop="$OPTARG" ;;
		*) sed -n '2,13p' "$0" >&2; exit 2 ;;
	esac
done
shift $((OPTIND - 1))

case "$build" in
	"") glob="JA3*.exe-*.log" ;;
	debug) glob="JA3Debug.exe-*.log" ;;
	retail) glob="JA3.exe-*.log" ;;
	*) echo "-b takes debug or retail" >&2; exit 2 ;;
esac
# shellcheck disable=SC2086 # The glob must expand.
newest="$(ls -t "$JA3_LOGS"/$glob 2>/dev/null | head -1 || true)"
if [ -z "$newest" ]; then
	echo "no log $glob in $JA3_LOGS" >&2
	exit 1
fi

# The game buffers its log, so the newest lines are not in the file until a flush.
# Only the debug build has the debugger that can call FlushLogFile.
if [[ "$(basename "$newest")" == JA3Debug.exe-* ]]; then
	if ss -ltn | grep -q ":$JA3_PORT "; then
		"$(dirname "$0")/lua.py" -e 'FlushLogFile()' >/dev/null || true
	fi
else
	echo "note: a retail game buffers its log, so the newest lines can be missing until the game writes them" >&2
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

# Values go through ENVIRON because awk -v drops their backslashes.
# Stack lines after [LUA ERROR] start with two spaces. A mod load error puts its message on the next line.
# CommonLua localization logs the UserText error, with a stack, after each load.
export JA3_TAGS="${1:-\[PROBE\]}" JA3_END="$endmark" JA3_DROP="$drop"
filter='
	function out(line) {
		if (!raw) {
			gsub(/[A-Za-z0-9_]+:[A-Z][0-9]+:/, "", line)
			gsub(/#[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]/, "", line)
			if (width > 0 && length(line) > width) line = substr(line, 1, width)
		}
		print line; fflush()
	}
	NR > 1 && ENVIRON["JA3_END"] != "" && index($0, ENVIRON["JA3_END"]) { out($0); exit }
	!raw && /\[LUA ERROR\]/ && /UserText before/ { stack = 0; skip = 1; next }
	skip == 1 && !/^  / { skip = 2; next }
	skip && /^  / { next }
	{ skip = 0 }
	!raw && ENVIRON["JA3_DROP"] != "" && $0 ~ ENVIRON["JA3_DROP"] { stack = 0; next }
	all { out($0); next }
	$0 ~ ENVIRON["JA3_TAGS"] { out($0); stack = 0; next }
	/\[LUA ERROR\]/ { out($0); stack = 1; next }
	/Errors while loading mod/ { out($0); stack = 0; modline = 1; next }
	modline { out($0); modline = 0; next }
	stack && /^  / { out($0); next }
	{ stack = 0 }
'
all=0
[ "$mode" = "-a" ] && all=1

echo "== $newest from line $start" >&2
if [ "$mode" = "-f" ]; then
	tail -n "+$start" -F "$newest" | awk -v raw="$raw" -v all="$all" -v width="$width" "$filter"
else
	tail -n "+$start" "$newest" | awk -v raw="$raw" -v all="$all" -v width="$width" "$filter"
fi
