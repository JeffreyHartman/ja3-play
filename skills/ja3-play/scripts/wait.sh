#!/usr/bin/env bash
# Evaluates a Lua expression in the game until it returns true, and prints the last result.
# Usage: wait.sh [-t SECONDS] [-i SECONDS] [-p EXPR] EXPR
#   -t SECONDS   give up after this time, default 120. Prints "timeout" and exits 1.
#   -i SECONDS   time between two evaluations, default 3
#   -p EXPR      a status expression to print each time, for example the team of the current turn
# A FAIL result, for example from a debugger that is not up yet, counts as not true.
set -uo pipefail
S="$(dirname "$0")"

timeout=120 interval=3 status=""
while getopts "t:i:p:" opt; do
	case "$opt" in
		t) timeout="$OPTARG" ;;
		i) interval="$OPTARG" ;;
		p) status="$OPTARG" ;;
		*) sed -n '2,7p' "$0" >&2; exit 2 ;;
	esac
done
shift $((OPTIND - 1))
[ $# -eq 1 ] || { sed -n '2,7p' "$0" >&2; exit 2; }

end=$((SECONDS + timeout))
while :; do
	r=$("$S/lua.py" -e "$1")
	[ -n "$status" ] && "$S/lua.py" -e "$status"
	if [[ "$r" == "OK true" ]]; then
		echo "$r"
		exit 0
	fi
	if ((SECONDS >= end)); then
		echo "timeout: $r"
		exit 1
	fi
	sleep "$interval"
done
