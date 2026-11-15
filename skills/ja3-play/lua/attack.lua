-- Fires the default attack of Barry at claude_enemy_3 and returns the estimated cost and line of sight. Edit the two unit ids.
local u, target = g_Units.Barry, g_Units.claude_enemy_3
local action = u:GetDefaultAttackAction()
local cost = action:GetAPCost(u, {target = target})
local vis = HasVisibilityTo(u, target)
CreateGameTimeThread(function()
  action:Execute({u}, {target = target})
  print("[PROBE] Barry", action.id, "->", target.session_id)
end)
return string.format("action=%s cost=%s visible=%s", action.id, tostring(cost and cost//1000), tostring(vis))
