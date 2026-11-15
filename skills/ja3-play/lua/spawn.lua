-- Spawns three LegionRaider enemies 11 to 15 tiles from the first live merc, on free tiles, as claude_enemy_1 to claude_enemy_3.
local mercs = {}
for _,u in ipairs(g_Units) do if u:IsMerc() and not u:IsDead() then mercs[#mercs+1]=u end end
local c = mercs[1]:GetPos()
local out = {}
for i, off in ipairs{ point(12,2,0), point(13,-3,0), point(11,6,0) } do
  local p = c + point(off:x()*const.SlabSizeX, off:y()*const.SlabSizeY, 0)
  local free = DbgFindFreePassPositions(p, 1, 20, xxhash(p))
  if free and free[1] then
    local u = SpawnUnit("LegionRaider", "claude_enemy_"..i, free[1])
    u:SetSide("enemy1")
    out[#out+1] = u.session_id.."@"..tostring(free[1]).." d="..(free[1]:Dist2D(c)//const.SlabSizeX).."t"
  end
end
return table.concat(out, "; ")
