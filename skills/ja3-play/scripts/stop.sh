#!/usr/bin/env bash
# Stops JA3 by killing the wineserver of its Proton prefix, which ends every process in that prefix.
set -euo pipefail
source "$(dirname "$0")/env.sh"

WINEPREFIX="$JA3_PREFIX" "$(dirname "$JA3_PROTON")/files/bin/wineserver" -k || true
for _ in $(seq 1 15); do
	if ! ss -ltn | grep -q ":$JA3_PORT "; then
		echo "stopped"
		exit 0
	fi
	sleep 1
done
echo "port $JA3_PORT still open after 15 s" >&2
exit 1
