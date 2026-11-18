#!/usr/bin/env bash
# Evaluates a Lua expression in the game until it returns true, and prints the last result.
# Usage: wait.sh [-t SECONDS] [-i SECONDS] [-p EXPR] [-s SECONDS] EXPR
#   -t SECONDS   give up after this time, default 120. Prints "timeout" and exits 1.
#   -i SECONDS   time between two evaluations, default 3
#   -p EXPR      a status expression to print each time, for example the team of the current turn
#   -s SECONDS   with -p, give up when the status stays the same for this time, default 120, 0 for never.
#                Prints "stall" and exits 3.
# A FAIL result, for example from a debugger that is not up yet, counts as not true.
set -uo pipefail
S="$(dirname "$0")"

timeout=120 interval=3 status="" stall=120
while getopts "t:i:p:s:" opt; do
	case "$opt" in
		t) timeout="$OPTARG" ;;
		i) interval="$OPTARG" ;;
		p) status="$OPTARG" ;;
		s) stall="$OPTARG" ;;
		*) sed -n '2,9p' "$0" >&2; exit 2 ;;
	esac
done
shift $((OPTIND - 1))
[ $# -eq 1 ] || { sed -n '2,9p' "$0" >&2; exit 2; }

end=$((SECONDS + timeout))
last="" since=$SECONDS
while :; do
	r=$("$S/lua.py" -e "$1")
	if [[ "$r" == "OK true" ]]; then
		[ -n "$status" ] && "$S/lua.py" -e "$status"
		echo "$r"
		exit 0
	fi
	if [ -n "$status" ]; then
		st=$("$S/lua.py" -e "$status")
		echo "$st"
		if [[ "$st" != "$last" ]]; then
			last="$st" since=$SECONDS
		elif ((stall > 0 && SECONDS - since >= stall)); then
			echo "stall: status unchanged for $((SECONDS - since)) s: $st"
			exit 3
		fi
	fi
	if ((SECONDS >= end)); then
		echo "timeout: $r"
		exit 1
	fi
	sleep "$interval"
done
