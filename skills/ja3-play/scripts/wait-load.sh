#!/usr/bin/env bash
# Waits until the loading screen XZuluLoadingScreen reports a loaded save, then clicks its Start button.
# Run it after LoadGame, QuickLoad or a load from the save manager. Prints "clicked", or "timeout" after 120 s.
set -uo pipefail
S="$(dirname "$0")"

sleep 3
"$S/wait.sh" -t 120 'GetDialog("XZuluLoadingScreen") ~= nil and GetDialog("XZuluLoadingScreen"):GetContext().loaded == true' >/dev/null || { echo "timeout"; exit 1; }
# LoadingScreenClose with the reason "loaded" calls LocalPlayerClickedReady, as the Start button does (Lua/UI/LoadingScreen.lua).
"$S/lua.py" -e 'CreateRealTimeThread(LoadingScreenClose, "idLoadedLoadingScreen", "loaded") and "clicked"'
sleep 3
