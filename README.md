# ja3-play

A Claude Code skill that lets Claude play Jagged Alliance 3 through the Lua debugger of the game's debug build. Use it to playtest a mod in the running game, or just to let Claude play.

## How it works

`JA3Debug.exe` ships with the game and starts a Lua debugger on `127.0.0.1:8165`. The debugger speaks the Debug Adapter Protocol (DAP). Its `evaluate` request runs any Lua in the full game state, outside the mod sandbox. Claude reads the state, runs an action, and reads the state again, all as Lua. The retail `JA3.exe` does not start the debugger.

The skill has instructions, a table of engine calls, and small scripts:

| File | Purpose |
|---|---|
| `skills/ja3-play/SKILL.md` | The steps: launch, load a save, play, stop. |
| `skills/ja3-play/reference.md` | Engine calls that worked in a test, and calls found in the game source. |
| `skills/ja3-play/scripts/launch.sh` | Linux: starts `JA3Debug.exe` through Proton and waits for the debugger. |
| `skills/ja3-play/scripts/stop.sh` | Linux: stops the game. |
| `skills/ja3-play/scripts/lua.py` | Runs Lua in the game and prints the result. Python 3, standard library only. |
| `skills/ja3-play/scripts/log.sh` | Linux: prints the errors and tagged lines of the newest debug log, from the start or from a marker line. |
| `skills/ja3-play/scripts/wait.sh` | Evaluates a Lua expression until it returns true. |
| `skills/ja3-play/scripts/wait-load.sh` | Waits for a save load to finish, and clicks Start on the loading screen. |
| `skills/ja3-play/lua/*.lua` | Example blocks: the state, an attack, enemy spawns. |

## Install

Link or copy the skill folder into your Claude Code skills:

```sh
ln -s "$PWD/skills/ja3-play" ~/.claude/skills/ja3-play
```

Requirements:

- JA3 from Steam.
- On Linux: Proton Experimental, and Steam running. The scripts find the game in your Steam libraries. Set `JA3_DIR` or `JA3_PROTON` if they do not.
- On Windows: start `JA3Debug.exe -no_interactive_asserts` from the game folder yourself. `lua.py` works as is. The log is in `%APPDATA%\Jagged Alliance 3\logs`.
- Python 3.10 or later.

macOS is not supported, because JA3 has no macOS version.

## Example

```sh
cd skills/ja3-play
scripts/launch.sh
scripts/lua.py -e 'GetMapName()'
scripts/lua.py lua/state.lua
scripts/stop.sh
```

## Safety

The debugger listens on `127.0.0.1` only, and any client on the port can run any code with `io` and `os`. Do not forward the port to another machine except through SSH.

## Background

The research and the first test, on 2026-11-14, are in `docs/research/claude-playtest.md`.

## License

MIT.
