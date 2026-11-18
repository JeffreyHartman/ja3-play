-- Auto-player for the player1 side: each controllable merc attacks the nearest seen enemy, or moves toward the nearest enemy, then the turn or the interrupt ends.
-- Optional globals:
--   claude_auto_hooks.interrupt_active()  true while a mod interrupt gives control to a merc
--   claude_auto_hooks.note(enemy, merc)   extra text for the AP line of an enemy at the start of each player turn
--   claude_ow_units[session_id] = true    the merc goes into Overwatch in place of a move
-- Stop it with claude_auto_stop = true. claude_auto_status holds the last line that it logged.
if claude_auto and IsValidThread(claude_auto) then DeleteThread(claude_auto) end
claude_auto_stop = false
local hooks = claude_auto_hooks or empty_table
local InterruptActive = hooks.interrupt_active or function() return false end

local function P(fmt, ...)
	local s = string.format(fmt, ...)
	print("[PROBE] auto " .. s)
	claude_auto_status = s
end

local function PlayerTurn()
	local team = g_CurrentTeam and g_Teams[g_CurrentTeam]
	return team and team.side == "player1"
end

local function Busy(u)
	return #(SyncEventsQueue or empty_table) > 0 or (IsValid(u) and not u:IsDead() and not u:IsIdleCommand()) or HasAnyCombatActionInProgress and HasAnyCombatActionInProgress()
end

local function Controllable()
	local list = {}
	for _, m in ipairs(g_Units) do
		if m.team and m.team.side == "player1" and not m:IsDead() and m:CanBeControlled() then list[#list + 1] = m end
	end
	return list
end

-- Returns "interrupt" when an interrupt gives control to another merc, so that the caller can act.
local function WaitDone(u)
	local t0 = GameTime()
	Sleep(300)
	while GameTime() - t0 < 90000 do
		if not Busy(u) and not InterruptActive() then break end
		if InterruptActive() then
			for _, m in ipairs(Controllable()) do
				if m ~= u then return "interrupt" end
			end
		end
		Sleep(200)
	end
	Sleep(300)
end

local function Enemies()
	local list = {}
	for _, e in ipairs(g_Units) do
		if e.team and e.team.side == "enemy1" and not e:IsDead() and not e:IsDowned() then list[#list + 1] = e end
	end
	return list
end

local function Nearest(u, list, need_vis)
	local best, bd
	for _, e in ipairs(list) do
		if not need_vis or HasVisibilityTo(u, e) then
			local d = u:GetDist(e)
			if not bd or d < bd then best, bd = e, d end
		end
	end
	return best, bd
end

local function TryAttack(u)
	local e = Nearest(u, Enemies(), true)
	if not e then return false end
	local a = u:GetDefaultAttackAction()
	if not a then return false end
	-- GetUIState can say "enabled" for a melee target 20 tiles away, and the attack then does not start.
	if a.id == "MeleeAttack" and u:GetDist(e) > 8 * const.SlabSizeX then return false end
	local args = { target = e }
	if a:GetUIState({ u }, args) ~= "enabled" then return false end
	local before = u.ActionPoints
	P("%s %s -> %s ap=%.1f", u.session_id, a.id, e.session_id, u.ActionPoints / 1000.0)
	a:Execute({ u }, args)
	Sleep(1500)
	if u.ActionPoints == before and u:IsIdleCommand() then P("%s %s did not start", u.session_id, a.id) return false end
	return true
end

-- Moves to the reachable tile nearest to the nearest enemy, and keeps the AP for one default attack if it can.
local function TryMove(u)
	local e = Nearest(u, Enemies(), false)
	if not e then return false end
	local a = u:GetDefaultAttackAction()
	local cost = a and a:GetAPCost(u, { target = e }) or (u.ActionPoints // 2)
	if cost < 0 then cost = u.ActionPoints // 2 end
	local budget = u.ActionPoints - cost
	if budget < 2000 then budget = u.ActionPoints end
	local cp = CombatPath:new()
	cp:RebuildPaths(u, budget)
	local epos = e:GetPos()
	local here = u:GetDist(e)
	local best, bd
	for packed in pairs(cp.destinations or empty_table) do
		local p = point(point_unpack(packed))
		local d = p:Dist2D(epos)
		if d > 3 * const.SlabSizeX and (not bd or d < bd) then best, bd = p, d end
	end
	if not best or bd >= here - const.SlabSizeX then return false end
	P("%s Move toward %s %d->%d tiles ap=%.1f", u.session_id, e.session_id, here // const.SlabSizeX, bd // const.SlabSizeX, u.ActionPoints / 1000.0)
	CombatActions.Move:Execute({ u }, { goto_pos = best })
	return true
end

local function TryOverwatch(u)
	local e = Nearest(u, Enemies(), false)
	local a = CombatActions.Overwatch
	if not e or not a then return false end
	local args = { target = e:GetPos() }
	local st = a:GetUIState({ u }, args)
	if st ~= "enabled" then P("%s Overwatch state=%s", u.session_id, tostring(st)) return false end
	P("%s Overwatch toward %s ap=%.1f", u.session_id, e.session_id, u.ActionPoints / 1000.0)
	a:Execute({ u }, args)
	return true
end

local function ActWith(u)
	for i = 1, 5 do
		if claude_auto_stop or not IsValid(u) or u:IsDead() or not u:CanBeControlled() then return end
		local did = TryAttack(u)
		if not did and i <= 2 then
			if (claude_ow_units or empty_table)[u.session_id] and PlayerTurn() then
				did = TryOverwatch(u)
				if did then WaitDone(u) return end
			else
				did = TryMove(u)
			end
		end
		if not did then P("%s no action (try %d) ap=%.1f", u.session_id, i, u.ActionPoints / 1000.0) return end
		if WaitDone(u) == "interrupt" then return "interrupt" end
	end
end

-- EndTurn from a game-time thread did not register, so it goes through a real-time thread.
-- In player turn 1, the first EndTurn can fail to register, so it is sent up to 5 times.
local function EndPlayerTurn(turn)
	for i = 1, 5 do
		CreateRealTimeThread(NetSyncEvent, "EndTurn", netUniqueId)
		Sleep(3000)
		if not g_Combat or g_Combat.current_turn ~= turn or not PlayerTurn() then return end
		P("EndTurn %d not registered, send %d", turn, i + 1)
	end
end

local function LogEnemyAP()
	local list = {}
	for _, e in ipairs(Enemies()) do
		local m = Nearest(e, Controllable(), false)
		local a = e:GetDefaultAttackAction()
		local c = m and a and a:GetAPCost(e, { target = m }) or -1
		local note = hooks.note and m and hooks.note(e, m)
		list[#list + 1] = string.format("%s=%.1f/cost%.1f%s", e.session_id, e.ActionPoints / 1000.0, c / 1000.0, note and ("/" .. tostring(note)) or "")
	end
	P("enemy AP turn %d: %s", g_Combat.current_turn, table.concat(list, " "))
end

claude_auto = CreateGameTimeThread(function()
	-- A restarted auto-player does not end the same turn again. The combat object tells one fight from the next.
	local done_turn = claude_done_turn and claude_done_turn.combat == g_Combat and claude_done_turn.turn
	while not claude_auto_stop do
		if not g_Combat then P("no combat") break end
		local ctl = Controllable()
		if InterruptActive() and #ctl > 0 then
			P("merc interrupt: %d controllable", #ctl)
			for _, m in ipairs(ctl) do ActWith(m) end
			WaitDone()
			if InterruptActive() then
				P("end merc interrupt")
				CreateRealTimeThread(NetSyncEvent, "EndTurn", netUniqueId)
				Sleep(2000)
			end
		elseif PlayerTurn() and not InterruptActive() and #ctl > 0 and done_turn ~= g_Combat.current_turn then
			P("player turn %d start", g_Combat.current_turn)
			Sleep(4000)
			LogEnemyAP()
			for _, m in ipairs(Controllable()) do
				ActWith(m)
				-- After an enemy interrupt, wait until control returns.
				while InterruptActive() and not claude_auto_stop and #Controllable() == 0 do
					Sleep(500)
				end
			end
			WaitDone()
			if not InterruptActive() and PlayerTurn() then
				done_turn = g_Combat.current_turn
				claude_done_turn = { combat = g_Combat, turn = done_turn }
				P("player turn %d end", done_turn)
				EndPlayerTurn(done_turn)
			end
		end
		Sleep(500)
	end
	P("stopped")
end)
return "started"
