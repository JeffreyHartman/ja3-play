---
name: ja3-play
description: Play Jagged Alliance 3 through the Lua debugger of its debug build. Use to playtest a JA3 mod in the running game, to start a test fight, to launch or stop JA3, to run Lua in the live game state, or to read the game log.
---

# JA3 play

`JA3Debug.exe` starts a Lua debugger on `127.0.0.1:8165` that speaks the Debug Adapter Protocol. Its `evaluate` request runs any Lua in the full game state, outside the mod sandbox. You play by sending Lua: read the state, run an action, read the state again. The retail `JA3.exe` has no debugger.

Paths in this file are relative to this skill folder. Call each script by its full path: the base directory that Claude Code printed when it loaded this skill, then the path, for example `<base>/scripts/lua.py`. Outside the working directories, the Bash tool does not keep a `cd` from one call to the next. The engine calls that worked, and the ones found in the source, are in [reference.md](reference.md). Read it before you write Lua for an area that the steps below do not cover.

## Where to run

Play in a playtest agent. Each state read, log read and wait of a game test stays in the context of the session that runs it. A playtest of 2 hours filled a session. A new agent writes about 32k tokens to the cache once. After that, each of its turns reads a small context, and the main session gets only the report.

Run the steps inline in this session in these cases only:

- Your brief names you the playtest agent.
- The user said to run it inline.
- The task is a single command: launch, stop, one Lua block, or one log read.

For all other work, start a playtest agent with the Agent tool. This includes a playtest of a ticket, a test fight, and the test of a fix.

The brief of the playtest agent contains:

- The sentence "You are the playtest agent. Run the ja3-play skill inline."
- The build under test, and the command that deploys it. The game loads mod code only at start.
- The save to load, and the setup before the checks.
- Each check, with the log line or Lua value that makes it pass.
- The tag pattern of the mod for `scripts/log.sh`.
- The report: PASS or FAIL for each check, with the log lines and Lua values that show it, in 300 words or fewer. The playtest agent reports bugs and changes no source files.

If a check fails, fix the code in this session, deploy it, and send the retest to the same agent with SendMessage.

## Steps

1. **Launch.** On Linux, run `scripts/launch.sh`. It finds the game and Proton in the Steam libraries and starts the debug build through Proton. If the debugger already listens, it starts nothing. On Windows, run `JA3Debug.exe -no_interactive_asserts` from the game folder. Done when the script prints `debugger listening`.
2. **Wait for the main menu.** Run `scripts/wait.sh 'GetDialog("PreGameMenu") ~= nil'`. Done when it prints `OK true`. Before that, the debugger already answers, but the save list is not ready. This took about 20 s after the port opened.
3. **Load a save or start a test fight.** A test fight needs no save and starts the same party each time. For a combat test, use it unless the user names a save. Its steps are in [reference.md](reference.md#test-fights). To play the fight without a turn-by-turn loop, start the auto-player. See [reference.md](reference.md#auto-player). For a save, list the saves and load one in a thread. The calls are in [reference.md](reference.md#load-and-save). Then run `scripts/wait-load.sh`. After a load, the loading screen stays open and waits for a click on "Start". The script waits for the loaded state and clicks Start. Then close the satellite view and the notification popup if they are open, because they pause the game. Done when `PauseReasons` is empty.
4. **Play.** Repeat this loop:
   - Read the state with `scripts/lua.py lua/state.lua`. The `ctl=true` units are the units that the player controls now.
   - Run one action in a game-time thread. See [Lua in the debugger](#lua-in-the-debugger).
   - Wait until the action ends with `scripts/wait.sh EXPR`: the AP changed, the team changed, or the combat ended.
   - Read the log of the action with `scripts/log.sh -s MARK`. MARK is the text of a `[PROBE]` line that you printed before the action. Then the output starts at that line. `-e MARK` stops it at a later `[PROBE]` line.
5. **Stop and clean up.** Run `scripts/stop.sh`. Delete each screenshot that you wrote. Done when the script prints `stopped`.

Do not forward port 8165 to another machine except through SSH. Any client on the port can run any code with `io` and `os`.

## Lua in the debugger

- `scripts/lua.py FILE` and `scripts/lua.py < FILE` run a block. The script wraps it as a function, so end the block with `return <value>`. `scripts/lua.py -e EXPR` evaluates one expression.
- The result is text, not JSON. Return a string that you built with `string.format` and `table.concat`, as `lua/state.lua` does. A dump of `g_Units` is far too large to read.
- `evaluate` cannot wait. `Sleep` fails there with "Not in a thread or within a pcall". Put code that waits in a thread, and return at once:
  - `CreateRealTimeThread(function() ... end)` for loads, saves, screenshots and UI.
  - `CreateGameTimeThread(function() action:Execute({u}, args) end)` for a combat action.
- `print("[PROBE] ...")` from a block or its threads writes to the game log. The game buffers its log, and `FlushLogFile()` writes the buffer to the file. `scripts/log.sh` calls it for you when the game runs.
- `scripts/wait.sh EXPR` evaluates EXPR every 3 s until it returns `true`. Use it for each wait on the game state, in place of a loop that you write. `-t` sets the timeout, and `-p STATUS_EXPR` prints a status expression on each try. With `-p`, the script stops with exit code 3 and `stall` when the status stays the same for 120 s. `-s SECONDS` changes that time. For an auto-player fight, use `-p claude_auto_status`.
- The state stays between calls. A global that one block sets with a plain assignment (`claude_x = 1`), the next block can read. A global set with `rawset(_G, ...)` was not seen in the next block.
- Mod globals are in the mod environment, not in `_G`: `table.find_value(ModsLoaded, "id", "<mod id>").env`. That table also has `.version` and `.options`.

## Facts that change results

- `ActionPoints` is in 1/1000 AP. Divide by 1000.
- GBO 4 changes `const.Scale.AP`, the AP that the game shows, and keeps raw AP. A mod log that divides by `const.Scale.AP` then shows 10 times the vanilla AP, for example `110` for 11 vanilla AP. Before you report an AP value, say which scale it uses.
- The AP cost estimate of an action can be wrong when mods change the costs. Read the AP of the unit before and after the action.
- In player turn 1, the first `EndTurn` can fail to register. After each `EndTurn`, wait 3 s for the turn to change, and send it again up to 5 times. Other open problems are in [reference.md](reference.md#known-problems-in-combat).
- A merc with 0 AP at the start of a turn has negative morale. This is vanilla behavior.
- To test a mod alone, change the mod list. Back it up first. See [reference.md](reference.md#change-the-mod-list).
- `g_Combat` is `false` outside combat, not `nil`. Test it with `if g_Combat then`.
- `u.side` is nil. Use `u.team.side`. `control` of a team is `UI` for the player and `AI` for the computer.
- The debug build logs Lua errors that the release build hides, also from other mods. Keep only the errors with a stack line in the mod under test. After each load, many `Trying to use a UserText before AsyncFilterUserTexts` errors come through `CommonLua` localization. They are not from the mod under test if no stack line names the mod as the origin. `scripts/log.sh` drops them, unless you give it `-r`. Give it a tag pattern for the lines of that mod, for example `scripts/log.sh '\[IIS\]|\[PROBE\]'`. It also reads the log of the retail build, for a game that the user plays. See the header of the script for its options.
- `QuickSave()` replaces the one quick save of the current campaign. Tell the user before you quick save in their campaign.
- Hit rolls are random. To compare two versions of a mod, run each one several times from the same save.
- `WriteScreenshot` captures the 3D scene only, with no UI. A desktop screenshot of the UI did not work while the desktop was locked.
- Over SSH, `scripts/launch.sh` sets the display variables of the local desktop. The game opens a real window there.
