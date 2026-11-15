#!/usr/bin/env bash
# Waits until the loading screen XZuluLoadingScreen reports a loaded save, then clicks its Start button.
# Run it after LoadGame, QuickLoad or a load from the save manager. Prints "clicked", or "timeout" after 120 s.
set -uo pipefail
S="$(dirname "$0")"

for _ in $(seq 1 40); do
	sleep 3
	r=$("$S/lua.py" -e 'tostring(GetDialog("XZuluLoadingScreen") and GetDialog("XZuluLoadingScreen"):GetContext().loaded)')
	if [[ "$r" == "OK true" ]]; then
		# LoadingScreenClose with the reason "loaded" calls LocalPlayerClickedReady, as the Start button does (Lua/UI/LoadingScreen.lua).
		"$S/lua.py" -e 'CreateRealTimeThread(LoadingScreenClose, "idLoadedLoadingScreen", "loaded") and "clicked"'
		sleep 3
		exit 0
	fi
done
echo "timeout"
exit 1
