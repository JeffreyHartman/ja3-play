-- Starts the TestCombat preset named by the global claude_test_fight, default F10_Skirmish_Sniper_Grenadier_Goon, with the fixed party Wolf, Steroid, Fox and Kalyna.
-- Without a player squad, TestCombatEnterSector picks one of 7 parties at random (GetTestCampaignSquad, Lua/GameSession.lua:817).
local PRESET = claude_test_fight or "F10_Skirmish_Sniper_Grenadier_Goon"
local def
for _, group in pairs(Presets.TestCombat) do
  def = def or table.find_value(group, "id", PRESET)
end
if not def then return "no preset " .. PRESET end
CreateRealTimeThread(function()
  NewGameSession()
  CreateNewSatelliteSquad({Side = "player1", CurrentSector = def.sector_id, Name = Presets.SquadName.Player[1].Name}, {"Wolf", "Steroid", "Fox", "Kalyna"}, 14, 1234567)
  TestCombatEnterSector(def)
  print("[PROBE] test fight", PRESET)
end)
return "starting " .. PRESET .. " in " .. tostring(def.sector_id)
