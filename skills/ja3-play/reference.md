# JA3 engine calls

Labels: **Tested** means that a call ran through the debugger in a game on 2026-11-14. **Source** means that it was read in the game Lua and did not run. Source paths are relative to the extracted game Lua (`Lua/`, `CommonLua/`). The same `CommonLua` is in `<game>/ModTools/Src/CommonLua/`.

## Load and save

| Need | Call | Label |
|---|---|---|
| List saves | `Savegame.ListForTag("savegame")` returns `err, list`, newest first. Each item has `savename`, `displayname` and `timestamp`. | Tested |
| Load a save | `CreateRealTimeThread(function() local err = LoadGame(savename) print("[PROBE] LoadGame err:", err) end)`. Poll `GetMapName()` and `GetLoadingScreenDialog()`. | Tested |
| Quick save and load | `QuickSave()`, `QuickLoad()` (`Lua/_Savegame.lua:635-667`) | Source |
| Start a campaign without menus | `QuickStartCampaign(campaign_id, params, sector)` (`Lua/GameSession.lua:787`) | Source |
| Main menu ready | `GetDialog("PreGameMenu") ~= nil`. `Savegame.ListForTag` returns no list before this. | Tested |
| Check the pause | `PauseReasons`. Its keys are the reasons, for example `pda`. Empty when the game runs. | Tested |
| Close the satellite view | `GetDialog("PDADialogSatellite"):Close()` | Tested |

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
| Any combat action | `CombatActions[action_id]:Execute({u}, args)`, then wait while `#SyncEventsQueue > 0` and while `not u:IsIdleCommand()` (`Lua/GameTests.lua:162-173`) | Source |
| Move | `CombatActions.Move:Execute({u}, {goto_pos = pos})` (`Lua/GameTests.lua:194`) | Source |
| Queue an action as the UI does | `StartCombatAction(action_id, u, ap, ...)` (`Lua/CombatActions.lua:149`) | Source |
| End the turn | `NetSyncEvent("EndTurn", netUniqueId)`. In a quickdraw interrupt, it ends the interrupt. | Tested |
| Start combat | `NetSyncEvent("ExplorationStartCombat")`. Only when the game is not paused. In the test, only 2 of 5 mercs joined, and nobody found why. | Tested |
| Wait for idle units | `WaitUnitsInIdle()`, in a thread (`Lua/Tactical/Combat.lua:268`) | Source |

## Set up a test

| Need | Call | Label |
|---|---|---|
| Spawn a unit | `local u = SpawnUnit("LegionRaider", "claude_enemy_1", pos) u:SetSide("enemy1")`. The second argument is the session id. See `lua/spawn.lua`. | Tested |
| Find a free tile | `DbgFindFreePassPositions(pos, 1, 20, xxhash(pos))` returns a list of points. | Tested |
| Offset by tiles | `pos + point(dx * const.SlabSizeX, dy * const.SlabSizeY, 0)` | Tested |
| Cheats | `NetSyncEvent("CheatEnable", "InfiniteAP", nil, side)`, also `"WeakDamage"`, `"GodMode"`, `"FullVisibility"` (`Lua/Cheat.lua:10-80`) | Source |
| A test fight | `InitTestCombat(combat, team_defs)` with `TestTeamDef{ mercs, side, ai_control }` (`Lua/Tactical/TestCombat.lua:18-75`). With `ai_control = true` on both teams, the game plays both sides. | Source |
| Screenshot of the 3D scene | `CreateRealTimeThread(function() WriteScreenshot("AppData/claude_probe.png", 1280, 720) end)`. `AppData/` is `AppData/Roaming/Jagged Alliance 3/`. The PNG is about 2.5 MB, so make a small JPEG before you read it. | Tested |

## Popups and the strategic layer

All **Source**, from `Lua/` unless the path starts with `CommonLua/`. Nothing here ran.

| Area | Calls | Size of the work |
|---|---|---|
| Message and question boxes | `g_ZuluMessagePopup` (`Tactical/Utility.lua:1962`), `g_OpenMessageBoxes` (`CommonLua/UI/StdDialogs.lua:2`). Each box has `idMain.idTitle`, `idMain.idText`, and actions with `ActionName` and `OnActionParam`. Close one with `box:Close(param)`. `Dialogs.PopupNotification:Close()`. | Small |
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
