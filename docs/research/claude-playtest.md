# Claude as a JA3 playtester

Can Claude play JA3 to test the Improved Interrupt System mod (the `quickdraw` repository), what is the best route, what does it cost to build, and how many tokens does it use? Researched and tested on 2026-11-14.

This is the research record. The working instructions and scripts are in the `ja3-play` skill, `skills/ja3-play/`. The MCP server that this doc proposes was not built: a skill does the same job with less code.

Paths:
- `Lua/...` and `CommonLua/...` are relative to `/home/jeff/git/ja3_mods/_reference/game/Lua/`, the extracted vanilla Lua. The same `CommonLua` is also in `<game>/ModTools/Src/CommonLua/`.
- `<game>` is the Steam install folder of JA3. `ModTools/` is `<game>/ModTools/`.
- `logs/` is `AppData/Roaming/Jagged Alliance 3/logs/` in the Proton prefix of the game.
- Mod paths (`mod/`, `tools/`, `tests/`, `docs/DEVELOPMENT.md`) are relative to the mod repository, `/home/jeff/git/ja3_mods/quickdraw/`.
- `poc/` was the folder of the proof-of-concept scripts. They are now `skills/ja3-play/scripts/` and `skills/ja3-play/lua/`.
- `<game>` on this machine is `/mnt/games/SteamLibrary/steamapps/common/Jagged Alliance 3`. The Proton prefix is `/mnt/games/SteamLibrary/steamapps/compatdata/1084160/pfx`. The JA3 Steam app id is `1084160`.

Labels:
- **Verified**: I read it in the source, the docs, or a local file.
- **Unverified**: the source says it, but nobody tested it on this machine.
- **Tested**: Claude ran it in the game on this machine on 2026-11-14.
- **Estimate**: my own number or opinion.

## Summary
- Yes, Claude can play JA3. The best route is not the screen. It is the Lua state of the engine. **Tested**: one full combat round with two interrupts ran through the debugger only.
- A mod cannot open a command channel by itself. The mod sandbox blocks file I/O, sockets, `io` and `os`. **Verified**, `CommonLua/Classes/Mod.lua:1056-1206`.
- The game has a built-in Lua debugger that speaks the Debug Adapter Protocol (DAP) on `127.0.0.1:8165`. Its `evaluate` request runs any Lua expression in the full global table, without the mod sandbox. **Verified in source**, `CommonLua/Libs/DebugAdapter/DebugAdapter.lua:499-505`, `:1124-1170`, `:1227-1229`.
- The debugger loads only in a build with `Platform.debug`. The 21 `JA3.exe` logs in `logs/` have no "DebugAdapter started" line. `JA3Debug.exe` starts the debugger, and the DAP `evaluate` request works from Linux. **Verified** by the probe on 2026-11-14. See [Test results](#test-results-2026-11-14).
- The engine already has the parts for a bot: test combats, AI-controlled teams, cheats, and a direct call to run a combat action. The game's own tests use them. **Verified**, `Lua/GameTests.lua:132-211`, `Lua/Tactical/TestCombat.lua:18-75`.
- Recommended: a small Python MCP server that talks DAP to the game, and a Lua "bot API" that returns compact JSON. Claude writes test scenarios as Lua scripts and reruns them for free. Claude plays turn by turn only for exploratory tests. **Estimate.** The scripts in `poc/` are the tested base.
- Token cost of one test scenario (40 game actions): about 1.4M input tokens with the bridge, about 19.9M with screenshots. With prompt caching, that is about $0.03 (Haiku 5.5), $0.41 (Sonnet 5.5) or $0.83 (Opus 5.5) for the bridge, and about $3 (Sonnet 5.5) for screenshots. **Estimate**, arithmetic below.
- Build effort: the first test is done. A useful bridge is 2 to 4 days more. **Estimate.**
- The debug build shows Lua errors that the release build hides. The first test found a real mod bug that way (fixed in quickdraw commit `b58d259`).
- The closest public tool is [LLM Game Automation MCP](https://www.reddit.com/r/ClaudeAI/comments/1xr3gbs/i_built_an_mcp_with_claude_code_that_lets_claude/) (r/ClaudeAI, "I built an MCP with Claude Code that lets Claude play PC games in the background"). It is MIT, Windows only, and injects a DLL that captures frames and fakes input inside one game process. It cannot drive JA3 under Proton as shipped. Its design ideas carry over: high-level tools with local loops, an observation in each action reply, downscaled captures, and per-game profile data. See [Prior art from Reddit](#prior-art-from-reddit).

## 1. In-engine control

### What a mod can and cannot do
- A mod runs in `LuaModEnv`. A read of a blacklisted global returns nil. **Verified**, `CommonLua/Classes/Mod.lua:1307-1391`.
- The blacklist has all file operations (`AsyncFileToString`, `AsyncStringToFile`, `AsyncFileRead` and more), all sockets (`sockListen`, `sockConnect` and more), `AsyncWebRequest`, `AsyncWebSocket`, `io`, `os`, `debug`, `load`, `dofile` and `rawget` on `_G`. **Verified**, `CommonLua/Classes/Mod.lua:1056-1206`.
- `os` is replaced by `{ time = os.time }`. **Verified**, `CommonLua/Classes/Mod.lua:1386`.
- All globals that start with `Debug` are also blocked. **Verified**, `CommonLua/Classes/Mod.lua:1216-1231`.
- Thus the idea "a mod polls a command file in a `CreateRealTimeThread`" does not work. The mod cannot read the file.
- The output side works. `print` from a mod goes to the game log. This mod writes all its `[IIS]` lines that way, and `tools/log.sh` reads them. **Verified**, `docs/DEVELOPMENT.md` (Log section), `tools/log.sh`.
- `WriteModPersistentData` and `ReadModPersistentData` store 32 KB per mod in the account storage. **Verified**, `CommonLua/Classes/Mod.lua:1233-1240`, `:1398-1412`. The game reads that storage at start, so an outside program cannot use it to send commands. **Estimate.**

### The in-game console
- The console opens with Enter or Alt-Shift-C. The shortcut exists only when `AreCheatsEnabled() or ConsoleEnabled or config.EnableHaerald`. **Verified**, `CommonLua/X/XTemplates/CommonShortcuts.lua:150-158`, `Lua/XTemplates/GameShortcuts.lua:55-62`.
- `AreCheatsEnabled()` is true when the mod tools are active: the Mod Editor is open, the Mod Editor map is loaded, or the game is a mod test game. **Verified**, `Lua/Cheat.lua:6-8`, `CommonLua/Classes/Mod.lua:99-101`.
- In a normal build, the console runs code in a mod environment, with the same blacklist. In a build with `Platform.asserts`, the console runs code in the full `_G`. **Verified**, `CommonLua/console.lua:31-58`.
- The console can call any global that the mod defines, because the mod writes its globals into `_G`. **Verified**, `CommonLua/Classes/Mod.lua:1340-1346`. Thus a mod can define `QD.Act(...)`, and a typed console line can call it.
- An outside program can type into the console only with fake keyboard input. See [Screen-level control](#3-screen-level-control).

### The built-in Lua debugger (DAP)
- The ModTools docs say: "The game has a built-in Lua debugger ... The debugger uses the Debug Adapter Protocol". The steps are: install `ModTools/Src/SolEngineLua.vsix` in VS Code, open the workspace, start the game, run "Attach to SolEngine". **Verified**, `ModTools/Docs/ModItemCode.md.html:14-24`.
- The workspace template connects to `localhost`, port `8165`. **Verified**, `ModTools/Src/ModTools.code-workspace.template`.
- The server listens on `127.0.0.1:8165`. **Verified**, `CommonLua/Libs/DebugAdapter/DebugAdapter.lua:1124-1170`. It starts when the file loads (`Debug(true)`). **Verified**, `:1227-1229`.
- The messages are JSON with a `Content-Length` header, as in the Language Server Protocol. **Verified**, `CommonLua/Libs/DebugAdapter/_JSONSocket.lua:1`.
- `evaluate` with `context = "repl"` runs `load("return " .. expression)` in `GetRawG()`, the real global table, and returns the result as text. **Verified**, `CommonLua/Libs/DebugAdapter/DebugAdapter.lua:499-505`, `:625-668`.
  - Thus `(function() ... end)()` runs a full block of Lua.
  - In the full `_G`, `dofile`, `io` and `AsyncFileToString` are available. Thus the bridge can also write a Lua file and tell the game to run it.
- The server runs `sockProcess` in a real-time thread every 50 ms. **Verified**, `CommonLua/Libs/DebugAdapter/DebugAdapter.lua:1187-1194`. The `evaluate` code itself runs inside a `pcall`, not in a thread that can wait: `Sleep` fails with "Not in a thread or within a pcall". **Tested.** Code that waits must start its own thread.
- The catch: the debugger file loads only when `Platform.pc and Platform.debug`. **Verified**, `Lua/Config/config.lua:104-109`.
  - The 21 logs in `logs/` are all from `JA3.exe`. None has a "DebugAdapter" line. **Verified.**
  - `<game>/JA3Debug.exe` sets `Platform.debug` and starts the debugger. **Tested.**
  - Under Proton, the listener is on the Linux loopback, owned by `wineserver`. **Tested.**

### Engine calls a bot needs
All **Verified** in source. The calls that the test ran are in [Lua calls that worked](#lua-calls-that-worked).

| Need | Call | Source |
|---|---|---|
| Find a unit | `g_Units.Barry` (by session id) | `Lua/GameTests.lua:185` |
| Run a combat action | `CombatActions[action_id]:Execute({unit}, args)`, then wait while `#SyncEventsQueue > 0` and while `not unit:IsIdleCommand()` | `Lua/GameTests.lua:162-173` |
| Move | `exec_action("Move", unit, { goto_pos = pos })` | `Lua/GameTests.lua:194` |
| Queue an action as the UI does | `StartCombatAction(action_id, unit, ap, ...)` | `Lua/CombatActions.lua:149-162` |
| End the turn | `NetSyncEvent("EndTurn", netUniqueId)` | `Lua/XTemplates/GameShortcuts.lua:2139`, handler `Lua/Tactical/Combat.lua:1598` |
| Start combat from exploration | `NetSyncEvent("ExplorationStartCombat")` | `Lua/Tactical/TestAllAttacks.lua:202-205`, `Lua/Exploration.lua:310` |
| Wait for idle units | `WaitUnitsInIdle()` | `Lua/Tactical/Combat.lua:268` |
| Cheats for setup | `NetSyncEvent("CheatEnable", "InfiniteAP", nil, side)`, `"WeakDamage"`, `"GodMode"`, `"FullVisibility"` and more | `Lua/Tactical/TestAllAttacks.lua:94-96`, `Lua/Cheat.lua:10-34`, `:56-80` |
| Load a save | `LoadGame(name, params, metadata)`, `QuickLoad()` | `Lua/_Savegame.lua:34`, `:667` |
| Save | `QuickSave()` | `Lua/_Savegame.lua:635` |
| Set up a test fight | `InitTestCombat(combat, team_defs)` with `TestTeamDef{ mercs, side, ai_control }`, or `TestCombatEnterSector(def, map)` | `Lua/Tactical/TestCombat.lua:18-75`, `:214` |
| Enemies of a unit | `GetAllEnemyUnits(unit)` | `Lua/Tactical/Diplomacy.lua:123` |
| AP for the UI | `unit:GetUIActionPoints()` | `Lua/Tactical/Unit.lua:2265` |
| Close popups during a test | a real-time thread that closes `Dialogs.PopupNotification` | `Lua/Tactical/TestAllAttacks.lua:164-172` |

### Existing automation
- `GameTests.Ladders` builds a 1-vs-1 fight on the `__CombatTest` map, raises the time factor to 10000, moves Barry up and down a ladder with `CombatActions.Move:Execute`, and checks the position. **Verified**, `Lua/GameTests.lua:132-211`.
- `GameTestsNightly.AllAttacks` loads the `__TestCombatOutlook` map, turns on `InfiniteAP` and `WeakDamage`, and runs each AI signature action. **Verified**, `Lua/Tactical/TestAllAttacks.lua:60-258`.
- `GameTests.TestSaveLoadSystem` saves and loads in a test. **Verified**, `Lua/GameTests.lua:331`.
- AI versus AI: a `TestTeamDef` with `ai_control = true` makes a team with `control = "AI"`. **Verified**, `Lua/Tactical/TestCombat.lua:59`. The combat loop runs `AITurn` for each team with `control == "AI"`, whatever its side. **Verified**, `Lua/Tactical/Combat.lua:638-650`.
  - Thus the game can play both sides. That is a crash soak test.
  - It does not test the interrupts. IOS takes only the entries of a merc of a UI-controlled team (`docs/DEVELOPMENT.md`, IOS handler). The IIS winners also act through the player UI. **Estimate.**
- I found no remote console, no autoplay switch and no command file reader in the vanilla Lua, apart from the DAP server. **Verified** by search for `AutoTest`, `GameTest`, `AIvsAI`, `autoplay`, `sockListen`.

## 2. Log-file driven
- `tools/log.sh -f` follows the newest log and prints `[IIS]` lines, `[LUA ERROR]` lines with their stack, and mod load errors. **Verified**, `tools/log.sh`.
- The mod log has the interrupt story: checks, triggers, `INT #N BEGIN` and `END`, refused actions, `TurnEnded` counters. **Verified**, `docs/DEVELOPMENT.md` (Log section).
- One session log (`logs/JA3.exe-20261108-15.16.59-67b4a1dd.log`) is 157 KB. It has 343 `[IIS]` lines with 48 KB of text, about 12,000 tokens at 4 characters per token. **Verified** (size), **Estimate** (tokens).
- The log is enough to check the result of a test: "did an interrupt start, who got it, how much AP was left".
- The log is not enough to play. It has no unit positions, no HP for each unit, no line of sight, no map. Also the game gives the log no input channel.
- Verdict: the log is the assertion channel. The DAP bridge is the control channel. **Estimate.**

## 3. Screen-level control
- Claude computer use is a client-side tool. Your program takes the screenshots and does the clicks. **Verified**, [computer use tool docs](https://platform.claude.com/docs/en/agents-and-tools/tool-use/computer-use-tool).
  - Current version: `computer_toolset_20260801`, with 17 member tools (screenshot, zoom, clicks, drag, scroll, type, key and more).
  - The docs advise 1024x768 or 1280x720 for desktop tasks, and nothing above 1920x1080.
  - The docs say each screenshot costs "roughly 1,000–1,800 input tokens".
- The reference implementation uses `xdotool` for input and `gnome-screenshot` or `scrot` for screenshots in an Xvfb display. **Verified**, [computer.py](https://raw.githubusercontent.com/anthropics/claude-quickstarts/main/computer-use-demo/computer_use_demo/tools/computer.py).
- On this machine: `spectacle` (KDE) and ImageMagick `import` exist. `xdotool`, `ydotool`, `wtype`, `grim` and `scrot` are not installed. **Verified** (`command -v`).
  - `xdotool` works only for X11 and XWayland windows. A Proton game usually runs under XWayland. **Unverified** for this setup.
  - `ydotool` writes to `/dev/uinput`, so it works under Wayland too, but it cannot pick a window. **Unverified.**
  - `gamescope` is installed. A nested gamescope session gives the game its own display. **Unverified** as a capture target.
- JA3 is hard to click. Each attack is several steps: select the merc, open the attack, hover the target, read the hit chance, click, wait for the animation. Isometric tiles and a moving camera make coordinates fragile. **Estimate.**
- Use screenshots for what only the screen shows: the INTERRUPT! banner, the portrait marks, the End Turn label (`mod/Code/UI.lua`). A zoom crop of the banner is cheap. **Estimate.**

### Image token cost
The vision docs give `⌈width / 28⌉ × ⌈height / 28⌉` visual tokens. The high-resolution tier (Claude 4.7 and later models) allows 2,576 px on the long edge and 4,784 tokens. The standard tier allows 1,568 px and 1,568 tokens. **Verified**, [vision docs](https://platform.claude.com/docs/en/build-with-claude/vision).

| Frame | Arithmetic | Tokens (high-res tier) |
|---|---|---|
| 1920x1080 | ⌈68.6⌉ × ⌈38.6⌉ = 69 × 39 | 2,691 |
| 1280x720 | ⌈45.7⌉ × ⌈25.7⌉ = 46 × 26 | 1,196 |
| 960x540 | ⌈34.3⌉ × ⌈19.3⌉ = 35 × 20 | 700 |
| 400x100 banner crop | 15 × 4 | 60 |

On the standard tier, a 1920x1080 frame is resized to 1456x819, which is 1,560 tokens. **Verified**, vision docs table.

## 4. MCP design
- An MCP server exposes tools through `tools/list` and `tools/call` (JSON-RPC 2.0). A tool has `name`, `description`, `inputSchema` and an optional `outputSchema`. A result has `content` (text, image, audio, resource links) and optional `structuredContent`. Errors use `isError: true`. **Verified**, [MCP spec 2025-06-18, tools](https://modelcontextprotocol.io/specification/2025-06-18/server/tools).
- Claude Code adds a local server with `claude mcp add --transport stdio <name> -- <command> [args...]`. It warns above 10,000 tokens of tool output and cuts at 25,000 by default (`MAX_MCP_OUTPUT_TOKENS`). **Verified**, [Claude Code MCP docs](https://code.claude.com/docs/en/mcp).
- Thus the state that a tool returns must stay well below 10,000 tokens. The bot API must send compact JSON, not a dump of `g_Units`.

Proposed server (`ja3-bridge`, Python, stdio). **Estimate.**

| Tool | Input | Output |
|---|---|---|
| `ja3_eval` | Lua expression | result text. Raw access for debugging. Keep it off in play sessions. |
| `ja3_state` | `detail`: `brief` or `full` | turn, team, interrupt state, and for each unit: id, side, tile, HP, AP, stance, Overwatch, visible enemies. About 60 tokens a unit. |
| `ja3_act` | `unit`, `action`, `target` (unit id or tile), `args` | ok or error, then the new `brief` state and the new `[IIS]` log lines |
| `ja3_end_turn` | none | the log lines until the next player control, and the new state |
| `ja3_load` | save name, or a fixture name | ok after `ZuluGameLoaded`, and the state |
| `ja3_run_scenario` | a scenario Lua file in this repository | pass or fail, with the assertion lines and the `[IIS]` lines |
| `ja3_log` | `since` marker, filter | new lines of the newest `JA3Debug.exe-*.log`, filtered like quickdraw `tools/log.sh` |
| `ja3_screenshot` | optional crop region | a PNG at 1280x720 or the crop |

Parts:
1. A DAP client: connect, `initialize`, `attach`, then `evaluate` with `context: "repl"`. `configurationDone` is not necessary. Start from `poc/dap_probe.py`.
2. A Lua bot API in this repository, for example `lua/bot.lua`. The bridge loads it with `dofile` through `evaluate`, or sends its text in an `evaluate`. It is not part of any mod, so no mod ships it. `dofile` needs a path that the game can open, for example a `Z:\\...` path under Proton. **Unverified.**
3. Each action runs in `CreateGameTimeThread` or through `NetSyncEvent`, as the game tests do, and the bridge polls a done flag. Code in `evaluate` cannot wait: `Sleep` fails there. **Tested.**
4. Scenario files use the same calls and write `[QD-TEST] PASS` or `FAIL` lines to the log.

Fallback without DAP: the mod defines `QD.Act(...)` globals, the bridge types `QD.Act("Barry","attack","Grizzly")` into the console with `ydotool`, and reads the reply from the log. This needs the mod tools active (`AreCheatsEnabled`). It is slow and depends on window focus. **Estimate.**

## 5. Prior art
- **Slay the Spire, CommunicationMod.** A mod starts an outside process and talks over stdin and stdout. The mod sends a JSON state when the game is stable, with `available_commands` and `ready_for_command`. Commands are short: `PLAY`, `END`, `POTION`, `CHOOSE`, `PROCEED`, `STATE`. This is the closest model for this bridge. **Verified**, [CommunicationMod README](https://github.com/ForgottenArbiter/CommunicationMod).
- **Balatro, BalatroBot and BalatroLLM.** A Lua mod serves JSON-RPC 2.0 over HTTP on port 12346. BalatroLLM is an LLM client for it with function calling. **Verified** (search summary of the repos), [balatrobot](https://github.com/coder/balatrobot), [balatrollm](https://github.com/coder/balatrollm).
- **Factorio Learning Environment.** The agent writes Python programs. A Python client sends Lua to the Factorio server over RCON. The agent sees the stdout and stderr of its last program. **Verified**, [FLE README](https://github.com/JackHopkins/factorio-learning-environment), [FLE paper](https://arxiv.org/html/2503.09617v1). A separate [factorio-mcp](https://github.com/phiresky/factorio-mcp) uses RCON from MCP.
- **Minecraft, Mindcraft.** LLM bots on top of the Mineflayer bot API. A `code_model` writes new actions as code. **Verified**, [Mindcraft README](https://github.com/kolbytn/mindcraft).
- **Claude Plays Pokemon.** Claude 3.7 Sonnet had "basic memory, screen pixel input, and function calls to press buttons", and played "through tens of thousands of interactions". **Verified**, [Anthropic, visible extended thinking](https://www.anthropic.com/news/visible-extended-thinking). Secondary write-ups say the knowledge base was capped near 8,000 tokens. **Unverified**, [Latent Space](https://latent.space/reading/claude-plays-pokemon/).
- **PC games in general, LLM Game Automation MCP.** A DLL inside the game captures frames and fakes input, and an MCP server with 160 tools sits on top. See [Prior art from Reddit](#prior-art-from-reddit).
- Lesson: the projects that play well read the game state from inside the game and send short commands. Pokemon is the screen-only case, and it needed a large harness and many interactions. **Estimate.**

## 6. Tokens and cost

### Scenario model (Estimate)
A test scenario: load a combat save, play 3 rounds, about 40 game actions. Example: "Barry on Overwatch, two enemies cross the cone, check the IOS pool after each shot".

Bridge, play mode:
- 40 calls, because `ja3_act` returns the new state.
- Fixed context `C0` = 5,000 tokens (system prompt, tool definitions, scenario brief) for a small custom loop.
- Each call adds 1,500 tokens: state 1,000, log lines 200, model text and tool call 300.
- Input over the run: Σ (5,000 + 1,500k) for k = 0..39 = 40 × 5,000 + 1,500 × 780 = 200,000 + 1,170,000 = **1,370,000**.
- Output: 40 × 300 = **12,000**.
- With prompt caching: about 65,000 tokens are cache writes (5,000 + 40 × 1,500), and 1,305,000 are cache reads.
- The context peaks at 5,000 + 1,500 × 39 = 63,500 tokens.

Screenshots, play mode:
- 4 UI steps for each game action: 160 steps.
- Each step adds a 1280x720 screenshot (1,196) and 300 tokens of text: 1,500 tokens.
- Input: 160 × 5,000 + 1,500 × (159 × 160 / 2) = 800,000 + 19,080,000 = **19,880,000**.
- Output: 160 × 300 = **48,000**.
- The context peaks at 243,500 tokens. Removing old screenshots lowers this, but each removal breaks the cache from that point.

Bridge, script mode:
- Claude writes one Lua scenario (3,000 output tokens), runs it, reads a 500-token result, and fixes it 2 or 3 times: about 5 calls and 50,000 input tokens.
- Each later run of the same file costs 0 tokens. It is a regression test.

### Prices
| Model | Input $/1M | Output $/1M | Cache read | Cache write | Source |
|---|---|---|---|---|---|
| Claude Haiku 5.5 (≤100K context) | 0.10 | 0.50 | 0.01 | 0.125 | OpenCode Console page; OpenRouter API (0.10 / 0.50) |
| Claude Haiku 5.5 (>100K context) | 0.50 | 2.50 | 0.05 | 0.625 | OpenCode Console page |
| Claude Sonnet 5.5 | 2.00 | 10.00 | 0.10 | 2.50 | OpenCode Console page; Anthropic list price |
| Claude Opus 5.5 | 4.00 | 20.00 | 0.20 | 5.00 | OpenCode Console page; Anthropic list price |
| DeepSeek V4.1 Flash | 0.0507 | 0.2028 | not used | not used | OpenRouter `/api/v1/models` |
| GLM 5.3 Flash | 0.0399 | 0.0784 | not used | not used | OpenRouter `/api/v1/models` |

**Verified** on 2026-11-14 from [opencode.ai/docs/zen](https://opencode.ai/docs/zen/), [openrouter.ai/api/v1/models](https://openrouter.ai/api/v1/models) and the Anthropic pricing table.

About OpenCode Zen: `opencode.ai/docs/zen/` now redirects to `/docs/console/models/`. The page calls the product "Console", "an AI gateway that gives you access to these models", pay as you go, with a fee of 4.6% + $0.31 on each credit purchase. It also lists free models for a limited time (for example Big Pickle, DeepSeek V4.1 Flash Free, Nemotron 3.5 Super VL Free). **Verified.** Whether a free model can follow the bridge tools well is **Unverified**.

### Cost per scenario (Estimate)
Bridge, play mode, 1.37M input and 12,000 output:

| Model | With cache | Without cache |
|---|---|---|
| Haiku 5.5 | 1.305 × 0.01 + 0.065 × 0.125 + 0.012 × 0.50 = $0.013 + $0.008 + $0.006 = **$0.03** | 1.37 × 0.10 + 0.006 = **$0.14** |
| Sonnet 5.5 | 1.305 × 0.10 + 0.065 × 2.50 + 0.012 × 10 = $0.13 + $0.16 + $0.12 = **$0.41** | 1.37 × 2 + 0.12 = **$2.86** |
| Opus 5.5 | 1.305 × 0.20 + 0.065 × 5 + 0.012 × 20 = $0.26 + $0.33 + $0.24 = **$0.83** | 1.37 × 4 + 0.24 = **$5.72** |
| DeepSeek V4.1 Flash | not used | 1.37 × 0.0507 + 0.012 × 0.2028 = **$0.07** |

Screenshots, play mode, 19.88M input and 48,000 output:

| Model | With cache | Without cache |
|---|---|---|
| Sonnet 5.5 | 19.64 × 0.10 + 0.245 × 2.50 + 0.048 × 10 = $1.96 + $0.61 + $0.48 = **$3.05** | 19.88 × 2 + 0.48 = **$40.24** |
| Opus 5.5 | 19.64 × 0.20 + 0.245 × 5 + 0.048 × 20 = $3.93 + $1.23 + $0.96 = **$6.12** | 19.88 × 4 + 0.96 = **$80.48** |

The screenshot run also passes 100K context, so Haiku 5.5 moves to its higher price for most of the run.

Headline: the bridge uses about 14 times fewer input tokens than screenshots (1.37M against 19.88M), and 4 times fewer steps.

### Pro plan
- Pro costs $20 a month (US). It has a five-hour limit and a weekly limit. Claude, Claude Desktop and Claude Code share the same limits. **Verified**, [What is the Pro plan](https://support.claude.com/en/articles/8325606-what-is-the-pro-plan), [Claude Code with Pro](https://support.claude.com/en/articles/11145838-use-claude-code-with-your-pro-max-or-ultra-plan).
- The support pages give no token or message numbers for these limits. Thus I cannot say how many scenarios fit in a window. **Verified** (absence).
- If `ANTHROPIC_API_KEY` is set, Claude Code bills at API rates and not on the plan. **Verified**, same Claude Code support page.
- One public data point from Reddit: Sonnet 5.5 in Claude Desktop played a 62-minute chess game over MCP on a $20 plan. It used 57.44M cumulative input tokens (99.07% from cache) and 269,076 output tokens. The five-hour display went from 23% to 56%, and the weekly display from 54% to 59%. **Unverified** (self-report), [r/ClaudeAI chess post](https://www.reddit.com/r/ClaudeAI/comments/1wwz9av/i_let_sonnet_55_play_a_full_chess_game_against/).
  - Scaled to the bridge scenario (1.37M input, 12,000 output), that is about 1/42 of the input and 1/22 of the output. Thus a bridge scenario on Sonnet 5.5 uses about 1% to 2% of a five-hour window. A screenshot scenario (19.88M input, 48,000 output: 35% and 18% of the chess game) uses about 6% to 12%. **Estimate**, linear scaling of one sample.
- Claude Code adds its own system prompt and tool definitions to each call. I did not measure their size. They make `C0` larger than 5,000, so a play-mode loop in Claude Code costs more than the table. **Estimate.**
- Plan: use the Pro plan in Claude Code to build the bridge and write scenario scripts. Run long play-mode loops in a small custom loop on a cheap API model (Haiku 5.5 or DeepSeek V4.1 Flash through OpenRouter or OpenCode Console). Then they do not use the Pro limits. **Estimate.**

## 7. Effort (Estimate)

| Step | Work | Size |
|---|---|---|
| 0. Probe | Done on 2026-11-14. See [Test results](#test-results-2026-11-14). | done |
| 1. DAP bridge | DAP client, `ja3_eval`, `ja3_log` as an MCP server. | 0.5 day |
| 2. Bot API | `lua/bot.lua`: compact state, act, end turn, load, done flags. | 1 to 2 days |
| 3. Scenarios | 3 save fixtures (IIS move, JA2 Classic, IOS Overwatch), `[QD-TEST]` assertions, `ja3_run_scenario`. | 1 day |
| 4. Play loop | A custom loop on a cheap model with the same tools, and a turn limit. | 0.5 day |
| Fallback A | Console through `ydotool`, mod globals, log replies. Only if step 0 fails. | 1 day, fragile |
| Fallback B | Screenshots and clicks through a desktop MCP server or the computer use reference code. | 1 to 2 days, fragile and 14 times the tokens |
| Fallback C | Port LLM Game Automation MCP to run in the Proton prefix (see [Prior art from Reddit](#prior-art-from-reddit)). | Unknown. Several parts depend on Windows APIs that Wine does not have. |

Recommended next step: step 1. Port 8165 answers, so the fallbacks are not necessary.

## Test results (2026-11-14)
Claude ran two sessions on this machine through SSH. Every fact in this section is **Tested** unless it has another label. The scripts are in `poc/`.

### Environment
- CachyOS, KDE Plasma on Wayland. The game runs as an XWayland window on display `:0`, on the real desktop and GPU. Nothing is headless.
- Steam was running. Proton Experimental (`11.0-100`) ran the game.
- The desktop was locked during both sessions. The game ran, rendered and took screenshots behind the lock screen.
- The game had 33 mods active, the same list as `JA3.exe`. Many of them change combat: Rato's Gameplay Balance and Overhaul 4 (GBO), Rato's AI Overhaul, Pinned Down, Tons of Guns, and more. Test results depend on this list.
- The second session used mod 0.8.13 of Improved Interrupt System, with IIS on, IOS off, reaction time 25, AP registered 50%, collective interrupts on.

### Launch
`poc/launch.sh` starts the game and waits for the port. The command:

```sh
export DISPLAY=:0 WAYLAND_DISPLAY=wayland-0 XDG_RUNTIME_DIR=/run/user/1000
export XAUTHORITY=/run/user/1000/xauth_*   # the one file that exists
export STEAM_COMPAT_DATA_PATH=/mnt/games/SteamLibrary/steamapps/compatdata/1084160
export STEAM_COMPAT_CLIENT_INSTALL_PATH=$HOME/.local/share/Steam
export SteamAppId=1084160 SteamGameId=1084160
cd "/mnt/games/SteamLibrary/steamapps/common/Jagged Alliance 3"
setsid nohup "$HOME/.local/share/Steam/steamapps/common/Proton - Experimental/proton" \
  run ./JA3Debug.exe -no_interactive_asserts >/dev/null 2>&1 &
```

- Over SSH, the display variables are not set. Set them as above, or the game has no window.
- `-no_interactive_asserts` is necessary. Without it, the first Lua error of any mod opens a modal "Assert failed" window. That window blocks the main thread, and every DAP request times out. The flag comes from the strings of `JA3Debug.exe`. With this mod list, the first error comes from GBO at load (`Attempt to use an undefined global 'GBO_GeneralComponentPatch'`).
- To see the windows of the game from a shell: `xprop -root _NET_CLIENT_LIST`, then `xprop -id <id> WM_NAME` for each id. The main window is "Jagged Alliance 3". A blocking assert is "Assert failed". `xwininfo` and `wmctrl` are not installed.
- Port 8165 opened about 12 s after the launch. The first `evaluate` at the main menu worked about 30 s after the launch.
- The debug build writes its log to `logs/JA3Debug.exe-<date>-<time>-<hash>.log`. `tools/log.sh` in quickdraw reads only `JA3.exe-*.log`, so it does not see this log.
- Log lines to expect: `DebugAdapter started at 127.0.0.1:8165` and `Platform: asserts, debug, desktop, editor, goldmaster, pc, steam, steam_thq_wrapper`.

### Stop and clean up
`poc/stop.sh` runs `wineserver -k` with `WINEPREFIX` set to the Proton prefix. After it, no JA3 process is left, and port 8165 is closed.

What a session changes on disk:
- `LocalStorage.lua` in `AppData/Roaming/Jagged Alliance 3/`. The game rewrites it on each exit, as `JA3.exe` does.
- `Editor/JA3_CommonLib/UI/Icons/warning_button.png`. The JA3_CommonLib mod rewrites it in the debug build.
- A file from `WriteScreenshot`, if a test took one. Delete it.
- No save. Loading a save does not change it. The game did not autosave in these sessions.

### DAP protocol
`poc/dap_probe.py` is the tested client, about 50 lines.

- Framing: `Content-Length: <n>\r\n\r\n` and then `n` bytes of JSON, in both directions.
- Sequence: `initialize` (response, then an `initialized` event), `attach` (response), any number of `evaluate`, `disconnect`. `configurationDone` was not sent, and it was not necessary.
- `evaluate` arguments: `{"expression": "<lua>", "context": "repl"}`. The server runs `load("return " .. expression)`. To run a block, send `(function() <block> end)()`. `poc/ja3.py` does this wrap for a chunk from stdin.
- The reply is `{"success": true, "body": {"result": "<text>"}}`. If the Lua code fails, `success` is false and `message` has the error text.
- The result is `Debugger_ToString` text, not JSON. A string result can end with `" {\n\tmetatable = table: ...}"`, because strings have a metatable in this engine. `poc/ja3.py` cuts that suffix.
- Recommended for the server: return `LuaToJSON(value)` from the Lua side and decode it in Python. `LuaToJSON` is an engine function that returns `err, json`. **Verified** in source (`CommonLua/Libs/DebugAdapter/_JSONSocket.lua:99`). Not tested from `evaluate`.
- The tests opened a new connection for each request, about 60 times in one session, with no problem.
- Events: the server sends `output` events for console lines while its state is `running` (`CommonLua/Libs/DebugAdapter/DebugAdapter.lua:909-916`, `:924`). **Verified** in source. Not tested. A long-lived connection can maybe stream the log this way.
- The server binds to `127.0.0.1` only. `evaluate` can run any code with `io` and `os`. Do not forward the port to another machine without SSH.

### Lua calls that worked
Each call ran through `evaluate`.

| Need | Call | Notes |
|---|---|---|
| Check the build | `Platform.debug` | `true` in `JA3Debug.exe`. |
| Check that the debugger is outside the sandbox | `io ~= nil` | `true`. |
| List saves | `Savegame.ListForTag("savegame")` | Returns `err, list`. Each item has `savename` (for example `K10_ExitGame(2).savegame.sav`), `displayname` and `timestamp`. The list is newest first. 190 saves. |
| Load a save | `CreateRealTimeThread(function() local err = LoadGame(savename) print("[PROBE] LoadGame err:", err) end)` | `LoadGame` waits, so it must run in a thread. The load took less than 60 s. Poll `GetMapName()` and `GetLoadingScreenDialog()`. |
| Read where you are | `GetMapName()`, `gv_CurrentSectorId` | For example `K-10 - Old Diamond` and `K10`. |
| Find a mod | `table.find_value(ModsLoaded, "id", "ImprovedInterruptSystem")` | `.version_major`, `.version_minor`, `.version`, `.options` (the mod options), `.env` (the mod environment). |
| Read mod globals | `mod.env.IIS`, `mod.env.IISControl` | Mod globals are in `mod.env`, not in `_G`. `rawget(_G, "IIS")` is nil. |
| Interrupt state | `mod.env.IISControl.Active()`, `mod.env.IISControl.InterruptCount()` | |
| Turn on verbose mod logs | `mod.env.IIS.Config.log_checks = true` | Only for this session. |
| Check the pause | `PauseReasons` | A table. Its keys are the reasons, for example `pda`. Empty when the game runs. |
| Close the satellite view | `GetDialog("PDADialogSatellite"):Close()` | The save `K10_ExitGame(2)` opens with this view, and the game is paused until it closes. |
| List open dialogs | `GetDialog(name)` for each name | Seen: `PDADialogSatellite`, `InGameInterface`, `IModeExploration`, `IModeCombatMovement`. |
| Spawn an enemy | `local u = SpawnUnit("LegionRaider", "claude_enemy_1", pos) u:SetSide("enemy1")` | The second argument is the session id, so `g_Units.claude_enemy_1` finds it. |
| Find a free tile | `DbgFindFreePassPositions(pos, 1, 20, xxhash(pos))` | Returns a list of points. |
| Offset by tiles | `pos + point(dx * const.SlabSizeX, dy * const.SlabSizeY, 0)` | |
| Start combat | `NetSyncEvent("ExplorationStartCombat")` | The combat starts only when the game is not paused. Combat had started 8 s after the satellite view closed. |
| Read combat state | `g_Combat`, `g_Combat.current_turn`, `g_Teams[g_CurrentTeam].side`, `g_Teams[g_CurrentTeam].control` | `control` is `UI` for the player and `AI` for the enemy. |
| Read a unit | `u.session_id`, `u.team.side`, `u.HitPoints`, `u.ActionPoints // 1000`, `u:GetPos()`, `u:GetActiveWeapons().class`, `u:IsDead()`, `u:IsMerc()` | `u.side` is nil. Use `u.team.side`. `ActionPoints` is in 1/1000 AP. |
| Check line of sight | `HasVisibilityTo(u, target)` | |
| Attack | `local a = u:GetDefaultAttackAction() CreateGameTimeThread(function() a:Execute({u}, {target = enemy}) end)` | `a.id` was `Attack`, and the mod log showed `AutoFire`, the fire mode of the weapon. It works in the player turn and in an interrupt. |
| End the turn | `NetSyncEvent("EndTurn", netUniqueId)` | In an interrupt, it ends the interrupt. Then the enemy turn continues. |
| Write to the log | `print("[PROBE] ...")` | Code from `evaluate`, and threads that it starts, print to the game log. |
| Screenshot | `CreateRealTimeThread(function() WriteScreenshot("AppData/claude_probe.png", 1280, 720) end)` | `AppData/` is `AppData/Roaming/Jagged Alliance 3/` in the prefix. The PNG is 2.5 MB. It has the 3D scene only, with no UI. Convert it to a small JPEG before it goes to a model. |

### The combat test, step by step
1. `LoadGame("K10_ExitGame(2).savegame.sav")`. Exploration mode in sector K10, five mercs.
2. Close `PDADialogSatellite`.
3. Spawn three `LegionRaider` units 11 to 15 tiles from the first merc, side `enemy1`.
4. `NetSyncEvent("ExplorationStartCombat")`. Only Barry and Livewire joined the combat. Spider, Blood and the IMP merc were in `g_Units` before, but not in the combat. **Unverified** why.
5. Barry and Livewire used the default attack on `claude_enemy_3`. Both missed.
6. `EndTurn`. The enemy AI turn started.
7. A raider shot Livewire (HP 49 to 26). IIS triggered `INT #1` with Barry and Livewire. The mod gave control to Barry.
8. Barry attacked `claude_enemy_1` in the interrupt: HP 67 to 20.
9. `EndTurn` ended `INT #1` (`INT #1 END (end_request)`). The enemy turn continued.
10. Another raider shot Barry to HP 1. IIS triggered `INT #2` for Livewire only. Barry was incapacitated, so the collective join skipped him.
11. Livewire attacked in the interrupt and missed. `EndTurn` ended `INT #2`.
12. The combat reached turn 2 of the player team.

How the test waited:
- After each action or `EndTurn`, it slept 3 s and read the state again.
- It stopped at `team=player1`, at a new interrupt (`IISControl.Active()` true), or at the end of combat.
- The enemy turn with one interrupt took about 30 s of real time. An interrupt waits for player input, so the game does not move on alone.
- Recommended for the server: wait in Lua for `WaitMsg("Idle")` or the done flag of an action, as `Lua/GameTests.lua:162-173` does, and not by a fixed sleep. **Estimate.**

### Problems the test found
- The debug build logs Lua errors that the release build hides. One session logged 61 `[LUA ERROR]` lines. Most come from other mods, for example GBO (`EO_Deviation*` globals) and `Trying to use a UserText before AsyncFilterUserTexts`. Filter the log to `[IIS]`, `[PROBE]` and the errors with a stack line in this mod.
- A mod bug found: the interrupt combat log line gave plain strings to `T{}`. The debug build logged `Attempt to use plain text or numbers 'Barry and Livewire' as a localized string`. Fixed in quickdraw commit `b58d259`.
- `IIS = IIS or {}`, `IISControl = IISControl or {}` and `IOS = IOS or {}` log `Attempt to use an undefined global` at load in the debug build. They do no harm.
- `GetAPCost(u, {target = enemy})` of the default attack returned 3 AP, but Barry's `ActionPoints` fell from 16 to 7 after the attack. **Unverified** why. A mod in the list can change the costs. Read the AP from the unit before and after an action, and do not trust the estimate.
- The enemies lost AP when Barry shot at them. A suppression mod (Pinned Down or GBO) is a likely cause. **Unverified.**
- `WriteScreenshot` does not capture the UI. To check the INTERRUPT! banner, take a desktop screenshot of the game window. Spectacle (`spectacle -b -n -f -o <file>`) captured the lock screen, not the game, while the desktop was locked. ImageMagick `import -window <id>` failed with "missing an image filename". Desktop capture of the UI is not solved.

### Not tested yet
- Move actions (`CombatActions.Move:Execute({u}, {goto_pos = pos})`).
- Overwatch and IOS interrupts.
- JA2 Classic mode.
- A save that starts in combat.
- `LuaToJSON` from `evaluate`.
- A long-lived DAP connection with `output` events.
- Many test sessions in a row, and a game crash in the middle of a test.

## Open questions
Answered by the tests:
1. Does `JA3Debug.exe` start the DAP server? Yes.
2. Does it load mods and saves as `JA3.exe` does? Yes, the same 33 mods and 190 saves. It was started with `proton run`, not from the Steam library.
3. Is the port reachable from Linux at `127.0.0.1:8165`? Yes. Over SSH from another machine, forward it with `ssh -L 8165:127.0.0.1:8165`. Not tested.
4. Does `evaluate` work while the game runs? Yes.
5. Does `Execute` from a thread made in `evaluate` trigger the interrupt hooks of the mod as a click does? Yes, for attacks. The IIS registrations, checks and triggers ran.
6. Does the bot see the same rules as the player in an interrupt? Yes, for the tested cases. The mod gave control to the interrupter, accepted its attack, and ended the interrupt on `EndTurn`.
7. Does `print` from `evaluate` go to the game log? Yes.

Still open:
1. Why did three of the five mercs not join the combat?
2. How can the server capture the UI for the banner checks?
3. Can Steam start `JA3Debug.exe` as a launch option, so that Steam shows the game as running?
4. Which fixed combat saves give the same start for each test run? Random hit rolls still change each run.

## Prior art from Reddit
`reddit-read` worked during this research. Reddit posts are self-reports. Each fact below is **Unverified** unless it names a primary source.

### LLM Game Automation MCP (the main find)
- Thread: [I built an MCP with Claude Code that lets Claude play PC games in the background](https://www.reddit.com/r/ClaudeAI/comments/1xr3gbs/i_built_an_mcp_with_claude_code_that_lets_claude/), r/ClaudeAI, u/Wonderful-Ad-8579, 880 points, 223 comments.
- Repository: the GitHub link in the post is down (the author says GitHub suspended the account). The mirror is [gitlab.com/corruptedang3l-group/llm-game-automation-mcp](https://gitlab.com/corruptedang3l-group/llm-game-automation-mcp). The facts below come from its `README.md`, `mcp/README.md`, `docs/AGENT_TIPS.md`, `LICENSE` and `src/vi_acguard.h`, read on 2026-11-14. **Verified** (docs only, no code run).
- Goal, in the post: let agents "create, test, and improve my game mods autonomously by actually playing the games".
- License: MIT, "Copyright (c) 2026 CorruptedAngel". **Verified**, `LICENSE`.

How it works. **Verified**, `README.md` unless marked.
- `vinput`: a DLL injected into one game process, and a CLI (`vinput.exe`) that talks to it over the named pipe `\\.\pipe\vinput_<pid>`, one JSON object per line.
- Capture: from the game's own swapchain. Direct3D 9, 11 and 12, OpenGL, Vulkan (only with `launch --early`) and DirectDraw, with a `PrintWindow` fallback. The game can be behind other windows.
- Input: inside the process, on each channel a game reads: window messages, Raw Input, DirectInput, `GetAsyncKeyState`, a virtual cursor behind `GetCursorPos`, and XInput pad 0. It never calls `SendInput`, so the user keeps the real mouse and keyboard.
- Vision: Windows OCR (`Windows.Media.Ocr`) and template matching run in the CLI, so many tools read text and icons without sending an image to the model.
- MCP server: TypeScript on Node.js 20, 160 tools (`launch`, `capture`, `click_text`, `key_sequence`, `nav_go`, `aim_shoot` and more). The post says "about 100"; the README says 160.
- Game profiles: one JSON file per game with HUD positions and input facts. 37 profiles ship. Fallout 1 and 2 have an `interaction.tactics` block for click-to-move, turn-based combat (`combat_round`, `click_move`). **Verified**, `docs/AGENT_TIPS.md` section 17.
- Anti-cheat: it refuses to inject when it finds a known anti-cheat module, folder or service. The folder check uses exact names, for example a folder named `BattlEye`. **Verified**, `src/vi_acguard.h:104-110`, `:186-200`. JA3 ships no anti-cheat that I know of. **Estimate.**

Token cost, from the author and the docs:
- The model does not steer frame by frame. A tool such as "drive to the waypoint" runs a local loop that reads the minimap "many times a second", and the model gets a summary when it arrives or gets stuck. **Unverified** (author comment).
- Screenshots are on request, "usually every few seconds or when something changes", and downscaled. **Unverified** (author comment). The docs advise `capture max_width:960` or `scale:0.5`, JPEG output, a `region`, and `capture_after` on input tools so one call acts and looks. **Verified**, `docs/AGENT_TIPS.md:52-54`, `mcp/README.md:187-189`.
- The author says Sonnet 5.5 played a full card game (Phantom Rose) from the tutorial to the end for about 1% of a weekly limit. The plan is not named. **Unverified.**
- Another commenter says a screenshot-then-decide loop in an Android emulator used 25% of a weekly Pro limit in "a couple hours". **Unverified.**

Limits that the author and commenters report:
- Model latency: "a few seconds every time it looks at the screen". Real-time aiming and combat must be local loops. **Unverified.**
- Weak indoors and without a minimap: it walks into posts, fences and railings, and searches a long time for doors. **Unverified.**
- Measured in the README: 1 of 12 car legs arrived in GTA Vice City DE, 0 of 12 in Saints Row; Terraria 0 of 10. `card_turn` and `board_turn` "carry out a turn; they do not choose good moves". **Verified**, `README.md`, "Known limits of the play tools".
- Random game state: the agent tests each change 5 or more times on the same save and route, alternating old and new code, and replays recorded frames offline. **Unverified** (author comment).
- Windows only. The requirements are "Windows 10 or 11, x64", Node.js 20, and a windowed or borderless game. The README, the MCP README and the thread never mention Linux, Wine or Proton. **Verified** (by text search).

Can it drive JA3 under Proton as shipped? No. **Estimate**, with these reasons:
- The CLI, the DLL and the named pipe must all run in the Proton prefix of JA3, under the same wineserver. The repository has no instructions for that. **Unverified** whether it works at all.
- JA3 renders with D3D12 (the log says `API d3d12`), and under Proton that is vkd3d-proton on Vulkan (`<game>/vkd3d-proton.cache` exists). Whether the D3D12 present hook finds the vkd3d-proton swapchain is **Unverified**. A `PrintWindow` fallback under Wine is often black. **Estimate.**
- `Windows.Media.Ocr` is a WinRT API. I know of no Wine implementation, so `click_text`, `wait_text` and `ocr` are likely to fail. **Estimate.**
- Even when it works, it reads JA3 only through pixels: no unit ids, no AP numbers except as OCR text, no interrupt state. It has no profile for JA3.

What the in-engine bridge can reuse:
- The tool shape: high-level tools (`combat_round`, `nav_go`) that run a local loop and return a short summary. For JA3: `ja3_act` waits for the action to end in Lua, then returns the result.
- An observation in each reply (`capture_after`). For JA3: `ja3_act` returns the new state and log lines.
- Downscaled captures and region crops for the UI checks. A crop of the INTERRUPT! banner is about 60 tokens (see [Image token cost](#image-token-cost)).
- Per-game data, not code: a JSON profile with the HUD regions of the banner, the portraits and the End Turn button, for `ja3_screenshot`.
- A/B testing on one save with several runs per arm, because the hit rolls are random.
- The MIT license allows reuse of its code. The DLL parts do not fit this case. **Estimate.**

### Other threads
- [Built a mech war game with Claude Code ... Claude also playtested it and recorded this video](https://www.reddit.com/r/ClaudeAI/comments/1xw6kat/built_a_mech_war_game_with_claude_code_where_you/), r/ClaudeAI. A three.js browser game. Claude "wrote an autopilot that plays every mission in a headless browser, found where it got stuck, and fixed both the game and the bot". The author says the autopilot found aiming that broke after a hijack and a mission it was unable to finish. **Unverified.** The game is the author's own code, so the bot can read the game state directly, as the JA3 bridge does. **Estimate.**
- [Claude tested my game with bot players for weeks. Then 219 real players showed up](https://www.reddit.com/r/ClaudeAI/comments/1xedrvq/claude_tested_my_game_with_bot_players_for_weeks/), r/ClaudeAI. Bots predicted 30% to 36% unit loss per raid, real players lost 7.3%. The author's lesson: "Bots play the way you wrote them". They were good to check that rules hold, and useless to predict how careful real people are. For this mod: use bots to test the interrupt rules, not the balance. **Unverified.**
- [I let Sonnet 5.5 play a full chess game against GPT 6.1 Sol over MCP](https://www.reddit.com/r/ClaudeAI/comments/1wwz9av/i_let_sonnet_55_play_a_full_chess_game_against/), r/ClaudeAI. The usage numbers are in [Pro plan](#pro-plan). The MCP server checked move legality and rejected one illegal move from Claude. For this mod: `ja3_act` must reject an action the rules refuse and say why. **Unverified.**
- [Claude Code built my RPG world engine. Now it can also run the game, as the game master, over MCP](https://www.reddit.com/r/ClaudeAI/comments/1wwbv68/claude_code_built_my_rpg_world_engine_now_it_can/), r/ClaudeAI. Lessons from the author: playing in the main conversation "filled about 250k tokens in 3 turns", so each turn now runs in a throwaway Sonnet 5.5 subagent. Tools must not block on work only the agent can do. A large tool list is cut to names plus a `search_tools` call. **Unverified.** For this mod: run each scenario in a subagent, and keep the main conversation for the bug list.
- JA3 subreddits: I searched r/JaggedAlliance and r/JaggedAlliance3 for "console", "lua", "debugger", "debug", "mod editor console" and "cheats mod editor". The results had no facts about the console, the debugger or test automation. One comment says a mod opens in the Mod Editor by a double click in the Mod Manager. [Mod Editor thread](https://www.reddit.com/r/JaggedAlliance3/comments/15z6tb6/mod_editor/). **Unverified.**

Which post fits "someone let Claude Code drive playtesting for his game": the mech game post is the only one where Claude Code playtested the author's own game end to end. The post the user remembered is the MCP post. It is a tool to let Claude play and test mods for other games.

## Silly ideas
- **Merc union rules.** Give Claude a `ja3_bark` tool. Every refused action (`refused by the action limit`) must come with an in-character complaint from Ivan. The complaints go into the bug report.
- **Interrupt bingo.** A scenario fuzzer that loads one save 200 times with different seeds and fills a bingo card: IIS win, JA2 Classic win, collective join, IOS shot, Stop, `STUCK?`. A full card means the release is ready. A `STUCK?` square means it is not.
- **AI versus AI versus Claude.** Set both teams to `ai_control = true`, then let Claude take over one merc only during interrupts. The vanilla AI plays the boring part, and Claude plays the part this mod adds.
- **Haiku plays, Opus judges.** Haiku 5.5 plays 50 cheap scenarios. Opus 5.5 reads only the `[IIS]` logs and writes the bug list. Total cost: less than one cup of the coffee Barry will not drink.
- **Grizzly as the test oracle.** The game tests already put Grizzly next to Barry on a ladder (`Lua/GameTests.lua:191`). Keep the tradition: every scenario has a Grizzly, and he must survive it.
