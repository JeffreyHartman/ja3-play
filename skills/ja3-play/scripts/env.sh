# Sets JA3_DIR, JA3_PREFIX, JA3_PROTON, JA3_LOGS and JA3_PORT for the other scripts. Source it, do not run it.
# Each variable that is already set in the environment wins over the search.

steam_root="${STEAM_ROOT:-$HOME/.local/share/Steam}"
[ -d "$steam_root" ] || steam_root="$HOME/.steam/steam"

ja3_libraries() {
	local vdf="$steam_root/steamapps/libraryfolders.vdf"
	[ -f "$vdf" ] && sed -n 's/^[[:space:]]*"path"[[:space:]]*"\(.*\)"/\1/p' "$vdf"
	echo "$steam_root"
}

if [ -z "${JA3_DIR:-}" ]; then
	while read -r lib; do
		if [ -f "$lib/steamapps/common/Jagged Alliance 3/JA3Debug.exe" ]; then
			JA3_DIR="$lib/steamapps/common/Jagged Alliance 3"
			break
		fi
	done < <(ja3_libraries)
fi
if [ -z "${JA3_DIR:-}" ]; then
	echo "JA3Debug.exe not found in the Steam libraries. Set JA3_DIR to the game folder." >&2
	exit 1
fi

# The Proton prefix is in the same library as the game. 1084160 is the Steam app id of JA3.
JA3_COMPAT="${JA3_COMPAT:-$(dirname "$(dirname "$JA3_DIR")")/compatdata/1084160}"
JA3_PREFIX="${JA3_PREFIX:-$JA3_COMPAT/pfx}"
JA3_LOGS="${JA3_LOGS:-$JA3_PREFIX/drive_c/users/steamuser/AppData/Roaming/Jagged Alliance 3/logs}"
JA3_PORT="${JA3_PORT:-8165}"

if [ -z "${JA3_PROTON:-}" ]; then
	while read -r lib; do
		if [ -x "$lib/steamapps/common/Proton - Experimental/proton" ]; then
			JA3_PROTON="$lib/steamapps/common/Proton - Experimental/proton"
			break
		fi
	done < <(ja3_libraries)
fi

export JA3_DIR JA3_COMPAT JA3_PREFIX JA3_LOGS JA3_PORT JA3_PROTON
