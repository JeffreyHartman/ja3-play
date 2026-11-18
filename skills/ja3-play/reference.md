# JA3 engine calls

Labels: **Tested** means that a call ran through the debugger in a game from 2026-11-14 to 2026-11-16. **Source** means that it was read in the game Lua and did not run. Source paths are relative to the extracted game Lua (`Lua/`, `CommonLua/`). The same `CommonLua` is in `<game>/ModTools/Src/CommonLua/`.

## Load and save

| Need | Call | Label |
|---|---|---|
| List saves | `Savegame.ListForTag("savegame")` returns `err, list`, newest first. Each item has `savename`, `displayname` and `timestamp`. | Tested |
| Load a save | `CreateRealTimeThread(function() local err = LoadGame(savename) print("[PROBE] LoadGame err:", err) end)`. Then wait for the loading screen. See [After a load](#after-a-load). | Tested |
| Load a save as the load menu does | `CreateRealTimeThread(function() local mgr = g_SaveGameObj or SaveLoadObjectCreateAndLoad() mgr:WaitGetSaveItems() mgr:Load(GetInGameInterface(), table.find_value(mgr.items, "savename", NAME), "skip_confirm") end)` | Tested |
| Quick save and load | `QuickSave()`, `QuickLoad()` (`Lua/_Savegame.lua:635-667`). Both run from `evaluate`, because they make their own threads. `QuickSave` overwrites the one quick save slot of the current game, `QuickSave<Game.id>.savegame.sav`. Tell the user before you quick save in their campaign, because it replaces their quick save. `QuickLoad` loads `LastQuicksaveName`. | Tested |
| Start a campaign without menus | `QuickStartCampaign(campaign_id, params, sector)` (`Lua/GameSession.lua:787`) | Source |
| Main menu ready | `GetDialog("PreGameMenu") ~= nil`. `Savegame.ListForTag` returns no list before this. | Tested |
| Check the pause | `PauseReasons`. Its keys are the reasons, for example `pda`. A key can be a dialog object, which prints as `table: 0x...`. Empty when the game runs. | Tested |
| Close the satellite view | `GetDialog("PDADialogSatellite"):Close()` | Tested |
| Close the notification popup | `Dialogs.PopupNotification:Close()`. The popup opens after a defeat and after a load. | Tested |

### After a load

`LoadGame`, `QuickLoad` and the save manager all end on the loading screen dialog `XZuluLoadingScreen`. It stays open until a click on "Start". Until that click:

- The game stays paused. `PauseReasons` has the `ZuluLoadingScreen` dialog object as a key.
- All units have `ctl=false`.
- `CanLoadGame()` blocks a new load. `QuickLoad()` does nothing and gives no error.
- `GetLoadingScreenDialog() ~= nil` stays true. Do not poll it to find the end of a load.

The save is ready when `GetDialog("XZuluLoadingScreen") and GetDialog("XZuluLoadingScreen"):GetContext().loaded` is true. To click Start, run `CreateRealTimeThread(LoadingScreenClose, "idLoadedLoadingScreen", "loaded")` (`Lua/UI/LoadingScreen.lua`). The reason `"loaded"` calls `LocalPlayerClickedReady`. After the click, `PauseReasons` was empty and the units were controllable. `scripts/wait-load.sh` does the wait and the click.

## Read the state

| Need | Call | Label |
|---|---|---|
| Where you are | `GetMapName()`, `gv_CurrentSectorId` | Tested |
| Open dialogs | `Dialogs` maps a name to a dialog. `GetDialog(name)`. Seen: `PDADialogSatellite`, `InGameInterface`, `IModeExploration`, `IModeCombatMovement`. | Tested |
| Combat | `g_Combat`, `g_Combat.current_turn`, `g_Teams[g_CurrentTeam].side`, `.control` | Tested |
| A unit | `g_Units.<session_id>`, `u.team.side`, `u.HitPoints`, `u.ActionPoints // 1000`, `u:GetPos()`, `u:GetActiveWeapons().class`, `u:IsDead()`, `u:IsMerc()` | Tested |
| Who the player controls now | `u:CanBeControlled()` for units with `u.team.control == "UI"`. Correct also in a quickdraw interrupt, because quickdraw overrides it. `g_CurrentTeam` stays on the enemy team during that interrupt. (`Lua/Tactical/Unit.lua:3024`) | Source |
| Line of sight | `HasVisibilityTo(u, target)` | Tested |
| Enemies of a unit | `GetAllEnemyUnits(u)` (`Lua/Tactical/Diplomacy.lua:123`) | Source |
| Quests and notes | `gv_Quests`, `QuestGetState`, `GetQuestVar` (`Lua/Quests.lua:47-71`), `gv_HistoryOccurences` | Source |
| Money | `Game.Money` (`Lua/Money.lua:21`) | Source |

## Act

| Need | Call | Label |
|---|---|---|
| Attack | `local a = u:GetDefaultAttackAction() CreateGameTimeThread(function() a:Execute({u}, {target = enemy}) end)`. Works in a player turn and in a quickdraw interrupt. See `lua/attack.lua`. | Tested |
| Check an attack before you send it | `a:GetUIState({u}, {target = enemy})` returns `"enabled"` when the UI would allow it. A `MeleeAttack` showed `enabled` for a target 20 tiles away and then did not start. Read the AP before and after the attack. | Tested |
| Overwatch | `CombatActions.Overwatch:Execute({u}, {target = enemy:GetPos()})`. `g_Overwatch[u]` is set while the unit is on Overwatch. | Tested |
| Any combat action | `CombatActions[action_id]:Execute({u}, args)`, then wait while `#SyncEventsQueue > 0` and while `not u:IsIdleCommand()` (`Lua/GameTests.lua:162-173`) | Source |
| Move | `CreateGameTimeThread(function() CombatActions.Move:Execute({u}, {goto_pos = SnapToPassSlab(point(x, y))}) end)` (`Lua/GameTests.lua:194`). Works in exploration and in combat. `IModeExploration:MoveUnitsTo` moved the units once and then did nothing. | Tested |
| Tiles that a unit can reach | `local cp = CombatPath:new() cp:RebuildPaths(u, ap)`. The keys of `cp.destinations` are packed points. Unpack one with `point(point_unpack(p))`, and give it to `Move` as `goto_pos`. | Tested |
| Queue an action as the UI does | `StartCombatAction(action_id, u, ap, ...)` (`Lua/CombatActions.lua:149`) | Source |
| End the turn | `NetSyncEvent("EndTurn", netUniqueId)` from `evaluate`, or `CreateRealTimeThread(NetSyncEvent, "EndTurn", netUniqueId)` from a thread. A send from a game-time thread did not register: `g_Combat.player_end_turn` stayed nil. In a quickdraw interrupt, it ends the interrupt. In player turn 1, the first send can fail. See [Known problems in combat](#known-problems-in-combat). | Tested |
| Wait for a mod event | Poll a state function of the mod every 3 s, and send `EndTurn` on each `player1` turn. For quickdraw: `table.find_value(ModsLoaded, "id", "ImprovedInterruptSystem").env.IISControl.Active()`. | Tested |
| Start combat | Move a merc toward the enemies until `g_Combat` is set. In `F10_Skirmish_Sniper_Grenadier_Goon`, a move of Fox to `point(118*1200, 140*1200)` started combat. No other preset was tested with this point. | Tested |
| Start combat at once | `NetSyncEvent("ExplorationStartCombat")`. Only when the game is not paused. In the test, only 2 of 5 mercs joined, and nobody found why. Use the move above. | Tested |
| Wait for idle units | `WaitUnitsInIdle()`, in a thread (`Lua/Tactical/Combat.lua:268`) | Source |

## Set up a test

| Need | Call | Label |
|---|---|---|
| Spawn a unit | `local u = SpawnUnit("LegionRaider", "claude_enemy_1", pos) u:SetSide("enemy1")`. The second argument is the session id. See `lua/spawn.lua`. | Tested |
| Find a free tile | `DbgFindFreePassPositions(pos, 1, 20, xxhash(pos))` returns a list of points. | Tested |
| Offset by tiles | `pos + point(dx * const.SlabSizeX, dy * const.SlabSizeY, 0)` | Tested |
| Cheats | `NetSyncEvent("CheatEnable", "InfiniteAP", nil, side)`, also `"WeakDamage"`, `"GodMode"`, `"FullVisibility"` (`Lua/Cheat.lua:10-80`) | Source |
| Keep the mercs alive | `NetSyncEvent("CheatEnable", "GodMode", nil, "player1")`. The mercs lived through many enemy turns. It also raised their AP. | Tested |
| A test fight | See [Test fights](#test-fights). | Tested |
| A test fight with AI on both sides | `InitTestCombat(combat, team_defs)` with `TestTeamDef{ mercs, side, ai_control }` (`Lua/Tactical/TestCombat.lua:18-75`). With `ai_control = true` on both teams, the game plays both sides. | Source |
| Screenshot of the 3D scene | `CreateRealTimeThread(function() WriteScreenshot("AppData/claude_probe.png", 1280, 720) end)`. `AppData/` is `AppData/Roaming/Jagged Alliance 3/`. The PNG is about 2.5 MB, so make a small JPEG before you read it. | Tested |

## Test fights

A test fight starts a `TestCombat` preset on its map with a new game session. It needs no save. Three runs on 2026-11-16 used it, two in vanilla and one with GBO 4. The presets are in `Data/TestCombat.lua` of the extracted game, under `Presets.TestCombat[group][id]`. The group `Test Encounters` has three F10 skirmishes: `F10_Skirmish_Sniper_Grenadier_Goon`, `F10_Skirmish_RaidLeader_Medic_Marauder` and `F10_Skirmish_Maniac_Scout_Marauder`. To list all presets, loop `for _, list in pairs(Presets.TestCombat) do for _, p in ipairs(list) do ... end end` and return `p.id`.

1. Run `scripts/lua.py lua/test-fight.lua`. It starts `F10_Skirmish_Sniper_Grenadier_Goon` with the fixed party Wolf, Steroid, Fox and Kalyna. For another preset, first set its id: `echo 'claude_test_fight = "<id>" return claude_test_fight' | scripts/lua.py`. Without a player squad, `TestCombatEnterSector` picks one of 7 parties at random (`Lua/GameSession.lua:817`). Then `g_Units.Fox` can be nil.
2. Run `scripts/wait-load.sh`.
3. Run `scripts/wait.sh 'IsKindOf(GetInGameInterfaceModeDlg(), "IModeDeployment")'`.
4. End the deployment with `CreateRealTimeThread(function() GetInGameInterfaceModeDlg():StartExploration() end)` (`Lua/GameTests.lua:544`). The game goes to `IModeExploration`, not to combat.
5. If the mod under test has a log level option, set it again: `m.options.LogLevel = "Info"`, then `Msg("ApplyModOptions", m.id)`. `m` is the entry of the mod in `ModsLoaded`. Do this after each fight start.
6. Start combat with a move of a merc toward the enemies. See [Act](#act).

## Auto-player

`lua/autoplay.lua` plays the `player1` side in a game-time thread. Each controllable merc attacks the nearest enemy that it sees. If it sees none, it moves toward the nearest enemy and keeps the AP for one attack. Then the auto-player sends `EndTurn`, and sends it again up to 5 times if the turn does not change. At the start of each player turn, it logs the AP of each enemy.

1. Start combat. See [Test fights](#test-fights).
2. If a mod adds its own interrupts, run its hook file first. For quickdraw, run `tools/autoplay-iis.lua` of that repo. The file sets `claude_auto_hooks`, which the header of `lua/autoplay.lua` describes.
3. To put mercs on Overwatch in place of a move, set `claude_ow_units = {Fox = true}`.
4. Run `scripts/lua.py lua/autoplay.lua`. It returns `started`.
5. Run `scripts/wait.sh -t 1800 -s 300 -p claude_auto_status 'not g_Combat'`. The status is the last line that the auto-player logged. An enemy turn logs no line, so `-s 300` gives it 5 minutes. On a `stall`, read the log from the last `[PROBE] auto player turn` line, and read the state.
6. Read the log with `scripts/log.sh -s '[PROBE] auto player turn 1 start'`.

To stop it, set `claude_auto_stop = true`. A new run of `lua/autoplay.lua` deletes the thread of the run before it. The auto-player skips a turn that it ended in the same fight, so a restart does not end a turn twice.

## Change the mod list

`AccountStorage.LoadMods` is the list of mods that the game loads at start, in load order. This procedure ran on 2026-11-16, and all 33 mods loaded again in the same order after the restore.

1. Write a backup: `local f = io.open(path, "w") f:write(TableToLuaCode(AccountStorage.LoadMods)) f:close()`. Read it back with `dofile(path)` and compare it to the live list.
2. Run `AllModsOff()`, then `TurnModOn("<mod id>")` for each mod of the test, then `SaveAccountStorage()`.
3. Run `scripts/wait.sh 'not SaveAccountStorageSaving and not SaveAccountStorageRequestTime and not IsValidThread(SaveAccountStorageThread)'`.
4. Run `scripts/stop.sh`, then `scripts/launch.sh`.
5. To restore, run `AccountStorage.LoadMods = table.copy(dofile(path))` and `SaveAccountStorage()`. Then do steps 3 and 4 again.

## Known problems in combat

These came from runs of the [auto-player](#auto-player).

- In player turn 1 of three runs, the first `EndTurn` did not register. `g_Combat.player_end_turn[netUniqueId]` stayed nil. In one run, the fourth send worked. In the other two runs, five sends failed, and one `EndTurn` from a separate `scripts/lua.py` call worked at once. In later turns, the first send worked. The cause is not known. After each `EndTurn`, wait 3 s for the turn to change, and send it again up to 5 times.
- In player turn 1 of three runs, only the first merc acted. The other mercs logged no line. The cause is not known. Read the AP of each merc after turn 1.
- In a merc interrupt with one controllable merc, the wait of the auto-player for the interrupt to end ran its full 90 s limit (JeffreyHartman/ja3-improved-interrupt-system#7).
- A merc that starts a turn with 0 AP has negative personal morale. `Unit:BeginTurn` removes 1 AP for each point below 0 (`Lua/Tactical/Unit.lua:2752-2756`). This is vanilla behavior, not a bug.

## Popups and the strategic layer

All **Source**, from `Lua/` unless the path starts with `CommonLua/`. Nothing here ran.

| Area | Calls | Size of the work |
|---|---|---|
| Message and question boxes | `g_ZuluMessagePopup` (`Tactical/Utility.lua:1962`), `g_OpenMessageBoxes` (`CommonLua/UI/StdDialogs.lua:2`). Each box has `idMain.idTitle`, `idMain.idText`, and actions with `ActionName` and `OnActionParam`. Close one with `box:Close(param)`. | Small |
| Satellite view and time | `OpenSatelliteView`, `CloseSatelliteView` (`Satellite/SatelliteView.lua:98, 203`). `PauseCampaignTime`, `ResumeCampaignTime`, `SetCampaignSpeed`, `IsCampaignPaused` (`GameSession.lua:136-181`). | Large |
| Squad travel | `GenerateRouteDijkstra` (`Satellite/SatelliteSquad.lua:2595`), then `NetSyncEvents.AssignSatelliteSquadRoute(squad_id, {route}, ...)` (`:737`). `UIEnterSector(id, force)` (`UI/SatelliteCabinet.lua:8`). State in `gv_Squads`, `gv_Sectors`. | Large |
| Conversations | `GetDialog("ConversationDialog")`. The line is in `dlg.idCharacterName` and `dlg.idPhrase`. The choices are `dlg.choice1` to `dlg.choice6`, with the keyword in `OnPressParam`. Pick with `dlg:PhraseChoice(keyword)`. The text is `T{}` and needs `_InternalTranslate`. (`Conversation.lua:763-790`, `XTemplates/ConversationDialog.lua:361-433`) | Medium |
| Hiring and money | `NetSyncEvents.HireMerc(merc_id, price, medical, days, player_id)` (`Satellite/SatelliteSquad.lua:1652`), `GetMercPrice` (`Mercenary.lua:1748`), `NetSyncEvents.ReleaseMerc`. A direct hire skips the AIM chat. | Medium |
| Bobby Ray's | `g_BobbyRayStore`, `g_BobbyRayCart`, `NetSyncEvents.BobbyRayCartAdd`, `BobbyRayShopFinishPurchase` (`BobbyRayGuns.lua:81-891`) | Medium |
| Inventory | `MoveItem(args)` (`UI/Inventory_MoveItem.lua:451`). Items go on a grid, so you must choose the slots. | Large |
| Combat conflicts | `NetSyncEvents.UIAutoResolveConflict` (`Satellite/SatelliteConflict.lua:1526`), `SatelliteRetreat` | Medium |

## The DAP protocol

`scripts/lua.py` does all of this. Read it only to change the script.

- Framing: `Content-Length: <n>\r\n\r\n`, then `n` bytes of JSON, in both directions.
- Sequence: `initialize`, `attach`, any number of `evaluate`, `disconnect`. `configurationDone` is not necessary.
- `evaluate` with `context: "repl"` runs `load("return " .. expression)` in the real global table (`CommonLua/Libs/DebugAdapter/DebugAdapter.lua:499-505`).
- The reply is `{"success": true, "body": {"result": "<text>"}}`, or `success: false` with the error in `message`.
- A new connection for each request worked about 60 times in one session.
- `LuaToJSON(value)` returns `err, json` (`CommonLua/Libs/DebugAdapter/_JSONSocket.lua:99`). It did not run from `evaluate`.
