-- Collector: quietly records what you see while you play, for the Forever database.
--   loot     - what each creature / object / container dropped, and how often it was looted
--   vendors  - what each vendor sells (price, stack, limited stock, special costs)
--   quests   - who gives / takes each quest, its rewards
--   npcs     - name, level, rank, reaction
--   spawns   - where creatures, vendors, quest givers and objects are (map + x/y)
--   items    - names and quality of every item seen
-- Saved in its own variable (CommandCenterCollect) so the sync script on your PC can send
-- only this - never your settings or whispers - to the database repository.
local _, S = ...

local VERSION = 1
local function D()
  CommandCenterCollect = type(CommandCenterCollect) == "table" and CommandCenterCollect or {}
  local d = CommandCenterCollect
  d.v = VERSION
  for _, k in ipairs({ "loot", "vend", "qst", "npc", "obj", "sp", "item", "recent" }) do
    if type(d[k]) ~= "table" then d[k] = {} end
  end
  return d
end
S.CollectDB = D

local function secret(v) return issecretvalue and issecretvalue(v) end
local function clean(v) if secret(v) then return nil end return v end
local function on()
  local g = S.db and S.db.global
  return not g or g.collectOn ~= false
end
function S.CollectEnabled() return on() end
function S.SetCollectEnabled(v) if S.db then S.db.global.collectOn = v and true or false end end

-- GUID -> kind ("c" creature, "o" object, "i" item), id
local function parseGUID(guid)
  guid = clean(guid)
  if type(guid) ~= "string" then return nil end
  local typ, _, _, _, _, id = strsplit("-", guid)
  if typ == "Creature" or typ == "Vehicle" then return "c", tonumber(id) end
  if typ == "GameObject" then return "o", tonumber(id) end
  if typ == "Item" then return "i", nil end
end
S.CollectParseGUID = parseGUID

local function idFromLink(link)
  if type(link) ~= "string" then return nil end
  return tonumber(link:match("item:(%d+)"))
end
local function noteItem(link)
  link = clean(link)
  local id = idFromLink(link)
  if not id then return nil end
  local d = D()
  local name = link:match("%[(.-)%]")
  local q
  local hex = link:match("|cff(%x%x%x%x%x%x)")
  if C_Item and C_Item.GetItemQualityByID then local ok, v = pcall(C_Item.GetItemQualityByID, id); if ok then q = clean(v) end end
  if name and name ~= "" then
    local e = d.item[id]
    if not e or e[1] ~= name or (q and e[2] ~= q) then d.item[id] = { name, q or (e and e[2]) } end
  end
  return id
end
S.CollectNoteItem = noteItem

-- where you are now: uiMap, x, y (0-1000)
local function here()
  local ok, m = pcall(function() return C_Map.GetBestMapForUnit("player") end)
  m = ok and clean(m)
  if not m then return nil end
  local ok2, pos = pcall(C_Map.GetPlayerMapPosition, m, "player")
  if not ok2 or not pos or not pos.GetXY then return m end
  local x, y = pos:GetXY()
  if secret(x) or not x or not y or (x == 0 and y == 0) then return m end
  return m, math.floor(x * 1000 + 0.5), math.floor(y * 1000 + 0.5)
end
S.CollectHere = here

local SPOT_NEAR, SPOT_MAX = 15, 40     -- 1.5% of the map counts as the same spot; 40 spots per zone
local function noteSpot(kind, id)
  if not id then return end
  local m, x, y = here()
  if not (m and x) then return end
  local d = D()
  local key = kind .. ":" .. id
  d.sp[key] = d.sp[key] or {}
  local list = d.sp[key][m]
  if not list then list = {}; d.sp[key][m] = list end
  for k = 1, #list, 2 do
    if math.abs(list[k] - x) <= SPOT_NEAR and math.abs(list[k + 1] - y) <= SPOT_NEAR then return end
  end
  if #list >= SPOT_MAX * 2 then return end
  list[#list + 1] = x; list[#list + 1] = y
end
S.CollectNoteSpot = noteSpot

local CLS = { worldboss = 3, rareelite = 2, elite = 1, rare = 4, normal = 0, trivial = 0, minus = 0 }
local function noteUnit(unit)
  if not UnitExists(unit) or UnitIsPlayer(unit) then return nil end
  local kind, id = parseGUID(UnitGUID(unit))
  if kind ~= "c" or not id then return nil end
  local d = D()
  local name, lvl = clean(UnitName(unit)), clean(UnitLevel(unit))
  if not name or name == UNKNOWNOBJECT or name == "" then return id end
  local e = d.npc[id] or {}
  e[1] = name
  if lvl and lvl > 0 then
    e[2] = (e[2] and math.min(e[2], lvl)) or lvl
    e[3] = (e[3] and math.max(e[3], lvl)) or lvl
  elseif lvl == -1 then e[2], e[3] = e[2] or -1, e[3] or -1 end
  local c = clean(UnitClassification(unit)); if c and CLS[c] then e[4] = CLS[c] end
  local r = clean(UnitReaction(unit, "player")); if r then e[5] = r end
  d.npc[id] = e
  return id
end
S.CollectNoteUnit = noteUnit

-- the same corpse / chest is only counted once (also across a /reload)
local RECENT = 15 * 60
local function seen(guid)
  local d = D()
  local now = time()
  if d.recent[guid] and now - d.recent[guid] < RECENT then return true end
  d.recent[guid] = now
  return false
end
local function pruneRecent()
  local d = D(); local now = time()
  for g, t in pairs(d.recent) do if now - t >= RECENT then d.recent[g] = nil end end
end

---------------------------------------------------------------------------
-- Loot
---------------------------------------------------------------------------
local lastContainer, lastContainerAt = nil, 0
-- opening a bag item (a clam, a lockbox...) - remember which one
local function noteUse(bag, slot)
  local ok, i = pcall(C_Container.GetContainerItemInfo, bag, slot)
  if ok and type(i) == "table" and clean(i.hasLoot) and clean(i.itemID) then
    lastContainer, lastContainerAt = i.itemID, GetTime()
    if i.hyperlink then noteItem(i.hyperlink) end
  end
end
if C_Container and C_Container.UseContainerItem then hooksecurefunc(C_Container, "UseContainerItem", noteUse) end

local function onLoot()
  if not on() then return end
  local n = GetNumLootItems and GetNumLootItems() or 0
  if n == 0 then return end
  local d = D()
  local sources = {}     -- key -> { [itemID] = count }
  for slot = 1, n do
    local link = GetLootSlotLink and clean(GetLootSlotLink(slot))
    local id = noteItem(link)
    if id and GetLootSourceInfo then
      local info = { pcall(GetLootSourceInfo, slot) }
      if info[1] then
        for k = 2, #info, 2 do
          local guid, qty = clean(info[k]), clean(info[k + 1])
          local kind, sid = parseGUID(guid)
          if kind == "i" and lastContainer and GetTime() - lastContainerAt < 5 then sid = lastContainer end
          if kind and sid then
            local key = kind .. ":" .. sid
            sources[key] = sources[key] or { guid = guid, items = {} }
            sources[key].items[id] = (sources[key].items[id] or 0) + 1
          end
        end
      end
    end
  end
  for key, s in pairs(sources) do
    if not s.guid or not seen(s.guid .. (key:sub(1, 1) == "i" and tostring(GetTime()) or "")) then
      local e = d.loot[key] or { n = 0, i = {} }
      e.n = e.n + 1
      for id, c in pairs(s.items) do e.i[id] = (e.i[id] or 0) + c end
      d.loot[key] = e
      local kind, sid = key:match("^(%a):(%d+)$")
      if kind == "c" or kind == "o" then noteSpot(kind, tonumber(sid)) end
      if kind == "o" then
        local name = GameTooltipTextLeft1 and GameTooltip:IsShown() and clean(GameTooltipTextLeft1:GetText())
        if name and name ~= "" then d.obj[tonumber(sid)] = d.obj[tonumber(sid)] or {}; d.obj[tonumber(sid)][1] = name end
      end
    end
  end
end

---------------------------------------------------------------------------
-- Vendors
---------------------------------------------------------------------------
local function merchantItem(i)
  if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
    local ok, t = pcall(C_MerchantFrame.GetItemInfo, i)
    if ok and type(t) == "table" then return t.price, t.stackCount, t.numAvailable, t.hasExtendedCost end
  end
  if GetMerchantItemInfo then
    local _, _, price, stack, avail, _, _, ext = GetMerchantItemInfo(i)
    return price, stack, avail, ext
  end
end
local function onMerchant()
  if not on() then return end
  local id = noteUnit("npc")
  if not id then return end
  noteSpot("c", id)
  local d = D()
  local list = {}
  for i = 1, (GetMerchantNumItems and GetMerchantNumItems() or 0) do
    local link = GetMerchantItemLink and clean(GetMerchantItemLink(i))
    local item = noteItem(link)
    if item then
      local price, stack, avail, ext = merchantItem(i)
      local e = { clean(price) or 0, clean(stack) or 1, (clean(avail) or -1) > 0 and avail or nil }
      if clean(ext) and GetMerchantItemCostInfo then
        local costs = {}
        for c = 1, (GetMerchantItemCostInfo(i) or 0) do
          local _, val, clink, cname = GetMerchantItemCostItem(i, c)
          local cid = idFromLink(clink)
          costs[#costs + 1] = (cid and ("i" .. cid) or (cname or "?")) .. "x" .. tostring(val or 0)
        end
        if #costs > 0 then e[4] = table.concat(costs, ",") end
      end
      list[item] = e
    end
  end
  if next(list) then list.t = time(); d.vend[id] = list end
end

---------------------------------------------------------------------------
-- Quests
---------------------------------------------------------------------------
local function questNPC()
  for _, u in ipairs({ "questnpc", "npc" }) do
    if UnitExists(u) then
      local kind, id = parseGUID(UnitGUID(u))
      if kind == "c" then noteUnit(u) end
      if kind and id then return kind .. id, kind, id end
    end
  end
end
local function questEntry(qid)
  local d = D()
  local e = d.qst[qid] or {}
  local t = clean(GetTitleText and GetTitleText())
  if t and t ~= "" then e.n = t end
  d.qst[qid] = e
  return e
end
local function addTo(list, v)
  for _, x in ipairs(list) do if x == v then return end end
  list[#list + 1] = v
end
local function onQuestDetail()
  if not on() then return end
  local qid = clean(GetQuestID and GetQuestID())
  if not qid or qid == 0 then return end
  local e = questEntry(qid)
  local who, kind, id = questNPC()
  if who then e.g = e.g or {}; addTo(e.g, who); noteSpot(kind, id) end
  local lvl = C_QuestLog and C_QuestLog.GetQuestDifficultyLevel and clean(C_QuestLog.GetQuestDifficultyLevel(qid))
  if lvl and lvl > 0 then e.lv = lvl end
end
local function onQuestComplete()
  if not on() then return end
  local qid = clean(GetQuestID and GetQuestID())
  if not qid or qid == 0 then return end
  local e = questEntry(qid)
  local who, kind, id = questNPC()
  if who then e.e = e.e or {}; addTo(e.e, who); noteSpot(kind, id) end
  local r, c = {}, {}
  for i = 1, (GetNumQuestRewards and GetNumQuestRewards() or 0) do local it = noteItem(GetQuestItemLink("reward", i)); if it then r[#r + 1] = it end end
  for i = 1, (GetNumQuestChoices and GetNumQuestChoices() or 0) do local it = noteItem(GetQuestItemLink("choice", i)); if it then c[#c + 1] = it end end
  if #r > 0 then e.r = r end
  if #c > 0 then e.c = c end
end

---------------------------------------------------------------------------
-- Talking to someone / mousing over creatures
---------------------------------------------------------------------------
local function onGossip()
  if not on() then return end
  local id = noteUnit("npc")
  if id then noteSpot("c", id) end
end
local lastMo = 0
local function onMouseover()
  if not on() or GetTime() - lastMo < 0.25 then return end
  lastMo = GetTime()
  noteUnit("mouseover")
end

local lootDone = false
S:On("LOOT_OPENED", function() if lootDone then return end lootDone = true; pcall(onLoot) end)
S:On("LOOT_CLOSED", function() lootDone = false end)
S:On("MERCHANT_SHOW", function() C_Timer.After(0.3, function() pcall(onMerchant) end) end)
S:On("MERCHANT_UPDATE", function() if MerchantFrame and MerchantFrame:IsShown() then pcall(onMerchant) end end)
S:On("QUEST_DETAIL", function() pcall(onQuestDetail) end)
S:On("QUEST_COMPLETE", function() pcall(onQuestComplete) end)
S:On("QUEST_PROGRESS", function() pcall(function() local _, kind, id = questNPC(); if id then noteSpot(kind, id) end end) end)
S:On("GOSSIP_SHOW", function() pcall(onGossip) end)
S:On("PLAYER_TARGET_CHANGED", function() if on() then pcall(noteUnit, "target") end end)
S:On("UPDATE_MOUSEOVER_UNIT", function() pcall(onMouseover) end)
S:On("PLAYER_LOGIN", function()
  local d = D()
  local v, b = GetBuildInfo and GetBuildInfo()
  d.build = tostring(v or "") .. "-" .. tostring(b or "")
  pruneRecent()
end)

-- how much has been recorded (for the settings line)
function S.CollectStats()
  local d = D()
  local function count(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end
  return { loot = count(d.loot), vendors = count(d.vend), quests = count(d.qst), npcs = count(d.npc), items = count(d.item), spots = count(d.sp) }
end
