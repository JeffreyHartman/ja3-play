-- Returns a compact text view of the game: map, pause reasons, open dialogs, popups, combat turn, and each live unit of the player and enemy teams.
-- `ctl` is Unit:CanBeControlled(), which is correct in a player turn and in a mod interrupt that overrides it, as quickdraw does.
local t = {}
local pauses = {}
for k in pairs(PauseReasons or {}) do pauses[#pauses + 1] = tostring(k) end
local dialogs = {}
for name in pairs(Dialogs or {}) do if type(name) == "string" then dialogs[#dialogs + 1] = name end end
table.sort(dialogs)
t[#t + 1] = string.format("map=%s sector=%s paused=%s", GetMapName(), tostring(gv_CurrentSectorId), table.concat(pauses, ","))
t[#t + 1] = "dialogs=" .. table.concat(dialogs, ",")
if g_ZuluMessagePopup and next(g_ZuluMessagePopup) then
  t[#t + 1] = "popups=" .. tostring(#g_ZuluMessagePopup)
end
if g_Combat then
  local team = g_CurrentTeam and g_Teams[g_CurrentTeam]
  t[#t + 1] = string.format("combat turn=%s team=%s control=%s", tostring(g_Combat.current_turn), tostring(team and team.side), tostring(team and team.control))
else
  t[#t + 1] = "exploration"
end
for _, u in ipairs(g_Units) do
  local side = u.team and u.team.side
  if not u:IsDead() and (side == "player1" or side == "enemy1") then
    local wpn = u:GetActiveWeapons()
    t[#t + 1] = string.format("%-16s %-7s hp=%3d ap=%2d ctl=%-5s pos=%s wpn=%s", u.session_id, side, u.HitPoints, u.ActionPoints // 1000, tostring(u:CanBeControlled()), tostring(u:GetPos()), wpn and wpn.class or "-")
  end
end
return table.concat(t, "\n")
