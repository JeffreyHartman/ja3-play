#!/usr/bin/env bash
# Starts JA3Debug.exe through Proton on the local desktop and waits until the Lua debugger listens.
# If the debugger already listens, it starts nothing. Steam must be running.
set -euo pipefail
source "$(dirname "$0")/env.sh"

if ss -ltn | grep -q ":$JA3_PORT "; then
	echo "debugger already listening on 127.0.0.1:$JA3_PORT"
	exit 0
fi
if [ -z "${JA3_PROTON:-}" ]; then
	echo "Proton - Experimental not found. Set JA3_PROTON to a proton script." >&2
	exit 1
fi

# Over SSH these are not set, and the game then has no window.
export DISPLAY="${DISPLAY:-:0}" WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}" XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export XAUTHORITY="${XAUTHORITY:-$(ls "/run/user/$(id -u)"/xauth_* 2>/dev/null | head -1)}"
export STEAM_COMPAT_DATA_PATH="$JA3_COMPAT" STEAM_COMPAT_CLIENT_INSTALL_PATH="$steam_root"
export SteamAppId=1084160 SteamGameId=1084160

cd "$JA3_DIR"
# Without -no_interactive_asserts, the first Lua error opens a modal window that blocks every debugger request.
setsid nohup "$JA3_PROTON" run ./JA3Debug.exe -no_interactive_asserts >/dev/null 2>&1 &
for _ in $(seq 1 60); do
	if ss -ltn | grep -q ":$JA3_PORT "; then
		echo "debugger listening on 127.0.0.1:$JA3_PORT"
		exit 0
	fi
	sleep 2
done
echo "debugger did not start in 120 s" >&2
exit 1
