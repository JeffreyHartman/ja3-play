---
name: ja3-play
description: Play Jagged Alliance 3 through the Lua debugger of its debug build. Use to playtest a JA3 mod in the running game, to launch or stop JA3, to run Lua in the live game state, or to read the game log.
---

# JA3 play

`JA3Debug.exe` starts a Lua debugger on `127.0.0.1:8165` that speaks the Debug Adapter Protocol. Its `evaluate` request runs any Lua in the full game state, outside the mod sandbox. You play by sending Lua: read the state, run an action, read the state again. The retail `JA3.exe` has no debugger.

Paths in this file are relative to this skill folder. The engine calls that worked, and the ones found in the source, are in [reference.md](reference.md). Read it before you write Lua for an area that the steps below do not cover.

## Steps

1. **Launch.** On Linux, run `scripts/launch.sh`. It finds the game and Proton in the Steam libraries and starts the debug build through Proton. If the debugger already listens, it starts nothing. On Windows, run `JA3Debug.exe -no_interactive_asserts` from the game folder. Done when the script prints `debugger listening`.
2. **Wait for the main menu.** Run `scripts/lua.py -e 'GetDialog("PreGameMenu") ~= nil'` every 5 s. Done when it prints `OK true`. Before that, the debugger already answers, but the save list is not ready. This took about 20 s after the port opened.
3. **Load a save.** List the saves, load one in a thread, and poll until the map name changes. Then close the satellite view if it is open, because it pauses the game. Done when `PauseReasons` is empty. The calls are in [reference.md](reference.md#load-and-save).
4. **Play.** Repeat this loop:
   - Read the state with `scripts/lua.py lua/state.lua`. The `ctl=true` units are the units that the player controls now.
   - Run one action in a game-time thread. See [Lua in the debugger](#lua-in-the-debugger).
   - Read the state again until the action ends: the AP changed, the team changed, or the combat ended.
   - Read the log with `scripts/log.sh` to see what the game and the mods reported.
5. **Stop and clean up.** Run `scripts/stop.sh`. Delete each screenshot that you wrote. Done when the script prints `stopped`.

Do not forward port 8165 to another machine except through SSH. Any client on the port can run any code with `io` and `os`.

## Lua in the debugger

- `scripts/lua.py FILE` and `scripts/lua.py < FILE` run a block. The script wraps it as a function, so end the block with `return <value>`. `scripts/lua.py -e EXPR` evaluates one expression.
- The result is text, not JSON. Return a short string that you built with `string.format` and `table.concat`, as `lua/state.lua` does. A dump of `g_Units` is far too large.
- `evaluate` cannot wait. `Sleep` fails there with "Not in a thread or within a pcall". Put code that waits in a thread, and return at once:
  - `CreateRealTimeThread(function() ... end)` for loads, saves, screenshots and UI.
  - `CreateGameTimeThread(function() action:Execute({u}, args) end)` for a combat action.
- `print("[PROBE] ...")` from a block or its threads writes to the game log. The game buffers its log, and `FlushLogFile()` writes the buffer to the file. `scripts/log.sh` calls it for you when the game runs.
- The state stays between calls. A global that one block sets, the next block can read.
- Mod globals are in the mod environment, not in `_G`: `table.find_value(ModsLoaded, "id", "<mod id>").env`. That table also has `.version` and `.options`.

## Facts that change results

- `ActionPoints` is in 1/1000 AP. Divide by 1000.
- The AP cost estimate of an action can be wrong when mods change the costs. Read the AP of the unit before and after the action.
- `u.side` is nil. Use `u.team.side`. `control` of a team is `UI` for the player and `AI` for the computer.
- The debug build logs Lua errors that the release build hides, also from other mods. Keep only the errors with a stack line in the mod under test. Give `scripts/log.sh` a tag pattern for the lines of that mod, for example `scripts/log.sh '\[IIS\]|\[PROBE\]'`.
- Hit rolls are random. To compare two versions of a mod, run each one several times from the same save.
- `WriteScreenshot` captures the 3D scene only, with no UI. A desktop screenshot of the UI did not work while the desktop was locked.
- Over SSH, `scripts/launch.sh` sets the display variables of the local desktop. The game opens a real window there.
