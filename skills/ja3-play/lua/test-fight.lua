-- Starts the TestCombat preset PRESET with the fixed party Wolf, Steroid, Fox and Kalyna. Edit GROUP and PRESET.
-- Without a player squad, TestCombatEnterSector picks one of 7 parties at random (GetTestCampaignSquad, Lua/GameSession.lua:817).
local GROUP, PRESET = "Test Encounters", "F10_Skirmish_Maniac_Scout_Marauder"
local def = Presets.TestCombat[GROUP] and Presets.TestCombat[GROUP][PRESET]
if not def then return "no preset " .. GROUP .. "/" .. PRESET end
CreateRealTimeThread(function()
  NewGameSession()
  CreateNewSatelliteSquad({Side = "player1", CurrentSector = def.sector_id, Name = Presets.SquadName.Player[1].Name}, {"Wolf", "Steroid", "Fox", "Kalyna"}, 14, 1234567)
  TestCombatEnterSector(def)
  print("[PROBE] test fight", PRESET)
end)
return "starting " .. PRESET .. " in " .. tostring(def.sector_id)
