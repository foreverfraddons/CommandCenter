-- ItemDB: Command Center's own WoW Forever database, used by "Where it comes from".
-- Two layers, merged on the fly:
--   1. the shared ForeverDB addon (its own CurseForge project, a required dependency; LoadOnDemand,
--      loaded the first time it's needed), built by the forever-db repository from the open
--      vanilla database + everyone's recordings. Older installs may still have the
--      CommandCenter_ForeverDB folder (global CC_ForeverDB) - used if ForeverDB isn't there.
--   2. what you recorded yourself (Collector.lua) - so new finds show up right away
-- Data format (all ids are numbers, chances are per 10000):
--   ForeverDB = { meta, npc = {[id] = {name, sub, minLv, maxLv, rank}}, obj = {[id] = {name}},
--     quest = {[id] = {title, level, minLevel}}, qg = {[qid] = {"c123", "o45"}}, item = {[id] = {name, q}},
--     drop / odrop / idrop = {[item] = {sourceId, chance, ...}} (chance 0 = rate unknown), vend = {[item] = {npc, ...}},
--     rew = {[item] = {qid, ...}}, start = {[item] = qid}, world = {[item] = minLv},
--     spw = {["c123"] = {{continent, x, y, x, y, ...}, ...}}   (world coordinates)
--     spm = {["c123"] = {[uiMap] = {x, y, ...}}}                (0-1000 map coordinates)
--     vp = {[npc] = {[item] = {price, stack, limited, costs}}} }
local _, S = ...
local IDB = {}
S.IDB = IDB

-- data addons in order of preference: {addon folder, global it fills}
local SOURCES = { { "ForeverDB", "ForeverDB" }, { "CommandCenter_ForeverDB", "CC_ForeverDB" } }
local tried = false
local function found()
  for _, s in ipairs(SOURCES) do
    local d = _G[s[2]]
    if type(d) == "table" and type(d.meta) == "table" then return d end
  end
end
local function shipped()
  local d = found()
  if d or tried then return d end
  tried = true
  local load = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
  if load then
    for _, s in ipairs(SOURCES) do
      pcall(load, s[1])
      d = found()
      if d then return d end
    end
  end
  return nil
end
function IDB.Shipped() return shipped() end
local function rec() return S.CollectDB and S.CollectDB() or nil end
function IDB.Available() return shipped() ~= nil or (rec() and next(rec().loot) ~= nil) end
function IDB.Meta() local d = shipped(); return d and d.meta end

local function T(d, k) return d and type(d[k]) == "table" and d[k] or nil end

---------------------------------------------------------------------------
-- Things
---------------------------------------------------------------------------
function IDB.NPC(id)
  local d, r = shipped(), rec()
  local s = T(d, "npc") and d.npc[id]
  local c = r and r.npc[id]
  if not s and not c then return nil end
  s, c = s or {}, c or {}
  return { name = c[1] or s[1], sub = s[2], minLv = s[3] or c[2], maxLv = s[4] or c[3], rank = s[5] or c[4], react = c[5] }
end
function IDB.Object(id)
  local d, r = shipped(), rec()
  local s = T(d, "obj") and d.obj[id]
  local c = r and r.obj[id]
  if not s and not c then return nil end
  return { name = (c and c[1]) or (s and s[1]) }
end
local function parseWho(w)
  local k, id = tostring(w):match("^(%a)(%d+)$")
  if not k then k, id = tostring(w):match("^(%a):(%d+)$") end
  return k, tonumber(id)
end
IDB.ParseWho = parseWho
function IDB.Quest(id)
  local d, r = shipped(), rec()
  local s = T(d, "quest") and d.quest[id]
  local c = r and r.qst[id]
  if not s and not c then return nil end
  s, c = s or {}, c or {}
  local givers = {}
  local seen = {}
  for _, list in ipairs({ T(d, "qg") and d.qg[id] or {}, c.g or {} }) do
    for _, w in ipairs(list) do if not seen[w] then seen[w] = true; givers[#givers + 1] = w end end
  end
  return { name = c.n or s[1], level = s[2] or c.lv, minLevel = s[3], givers = givers }
end
function IDB.ItemName(id)
  local d, r = shipped(), rec()
  local c = r and r.item[id]
  local s = T(d, "item") and d.item[id]
  return (c and c[1]) or (s and s[1]), (c and c[2]) or (s and s[2])
end

---------------------------------------------------------------------------
-- Where an item comes from
---------------------------------------------------------------------------
-- returns { drops = {{id, chance, seen, of}}, objects = {...}, containers = {...},
--           vendors = {id...}, rewards = {qid...}, start = qid, world = minLv }
function IDB.Sources(item)
  local d, r = shipped(), rec()
  local out = { drops = {}, objects = {}, containers = {}, vendors = {}, rewards = {} }
  local idx = { drops = {}, objects = {}, containers = {} }
  local function addChance(list, key, id, chance, seenN, ofN)
    local e = idx[key][id]
    if e then
      if seenN then e.seen, e.of = seenN, ofN; if not e.chance then e.chance = chance end end
      return
    end
    e = { id = id, chance = chance, seen = seenN, of = ofN }
    idx[key][id] = e
    list[#list + 1] = e
  end
  local function fromShipped(field, key, list)
    local t = T(d, field) and d[field][item]
    if not t then return end
    -- a chance of 0 means "drops here, rate unknown" (a source that lists drops without rates)
    for k = 1, #t, 2 do addChance(list, key, t[k], (t[k + 1] or 0) > 0 and t[k + 1] or nil) end
  end
  fromShipped("drop", "drops", out.drops)
  fromShipped("odrop", "objects", out.objects)
  fromShipped("idrop", "containers", out.containers)
  -- your own recordings
  if r then
    for key, e in pairs(r.loot) do
      local got = e.i and e.i[item]
      if got and e.n and e.n > 0 then
        local kind, id = parseWho(key)
        local list, k2 = (kind == "c" and out.drops) or (kind == "o" and out.objects) or (kind == "i" and out.containers), (kind == "c" and "drops") or (kind == "o" and "objects") or "containers"
        if list and id then addChance(list, k2, id, math.floor(math.min(1, got / e.n) * 10000 + 0.5), got, e.n) end
      end
    end
  end
  local vseen = {}
  for _, v in ipairs(T(d, "vend") and d.vend[item] or {}) do if not vseen[v] then vseen[v] = true; out.vendors[#out.vendors + 1] = v end end
  if r then for npc, list in pairs(r.vend) do if list[item] and not vseen[npc] then vseen[npc] = true; out.vendors[#out.vendors + 1] = npc end end end
  local qseen = {}
  for _, q in ipairs(T(d, "rew") and d.rew[item] or {}) do if not qseen[q] then qseen[q] = true; out.rewards[#out.rewards + 1] = q end end
  if r then
    for qid, e in pairs(r.qst) do
      for _, list in ipairs({ e.r or {}, e.c or {} }) do
        for _, it in ipairs(list) do if it == item and not qseen[qid] then qseen[qid] = true; out.rewards[#out.rewards + 1] = qid end end
      end
    end
  end
  out.start = T(d, "start") and d.start[item] or nil
  out.world = T(d, "world") and d.world[item] or nil
  local function byChance(a, b) return (a.chance or 0) > (b.chance or 0) end
  table.sort(out.drops, byChance); table.sort(out.objects, byChance); table.sort(out.containers, byChance)
  return out
end
-- what a vendor charges for an item (from your recordings): price, stack, limited, costs
function IDB.VendorPrice(npc, item)
  local r, d = rec(), shipped()
  local v = r and r.vend[npc] and r.vend[npc][item]
  if type(v) ~= "table" then v = T(d, "vp") and d.vp[npc] and d.vp[npc][item] end
  if type(v) == "table" then return v[1], v[2], v[3], v[4] end
end

---------------------------------------------------------------------------
-- Map spots: { ["m<uiMap>"] = { {x, y}, ... } } with x/y 0-100
---------------------------------------------------------------------------
local spawnCache = {}
local function worldToMap(cont, x, y)
  if not (C_Map and C_Map.GetMapPosFromWorldPos and CreateVector2D) then return nil end
  local ok, m, pos = pcall(C_Map.GetMapPosFromWorldPos, cont, CreateVector2D(x, y))
  if ok and m and pos and pos.GetXY then
    local px, py = pos:GetXY()
    if px and py and px >= 0 and px <= 1 and py >= 0 and py <= 1 then return m, px * 100, py * 100 end
  end
end
IDB.WorldToMap = worldToMap
function IDB.Spawns(kind, id)
  local key = kind .. id
  if spawnCache[key] then return spawnCache[key] end
  local d, r = shipped(), rec()
  local out, n = {}, 0
  local function add(m, x, y)
    local k = "m" .. m
    out[k] = out[k] or {}
    if #out[k] < 60 then out[k][#out[k] + 1] = { x, y }; n = n + 1 end
  end
  for _, grp in ipairs(T(d, "spw") and d.spw[key] or {}) do
    local cont = grp[1]
    for k = 2, #grp - 1, 2 do
      local m, x, y = worldToMap(cont, grp[k], grp[k + 1])
      if m then add(m, x, y) end
    end
  end
  local srcs = { T(d, "spm") and d.spm[key] or false, r and r.sp[kind .. ":" .. id] or false }
  for _, src in ipairs(srcs) do
    for m, list in pairs(src or {}) do
      for k = 1, #list - 1, 2 do add(tonumber(m) or m, list[k] / 10, list[k + 1] / 10) end
    end
  end
  spawnCache[key] = out
  return out, n
end
-- the zone name of the first known spot (for list lines)
function IDB.ZoneOf(kind, id)
  local sp = IDB.Spawns(kind, id)
  local best, bestN
  for k, list in pairs(sp) do if not best or #list > bestN then best, bestN = k, #list end end
  if best and C_Map and C_Map.GetMapInfo then
    local ok, info = pcall(C_Map.GetMapInfo, tonumber(best:sub(2)))
    if ok and info then return info.name end
  end
end
S:On("LOOT_CLOSED", function() wipe(spawnCache) end)
S:On("MERCHANT_CLOSED", function() wipe(spawnCache) end)
