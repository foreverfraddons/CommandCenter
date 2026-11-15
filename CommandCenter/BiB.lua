-- BiB (Built-in Bag): optional. All your bags in one window - sorted, grouped into
-- sections, searchable and styled the way you like. When it's on it takes over the
-- game's bag windows (B / Shift-B, the bag buttons, vendors, mail, the bank...).
--
-- Item slots use the game's own bag-slot template, so clicking, right-click to use,
-- drag and drop, tooltips and selling all behave exactly like the game's bags - and
-- work in combat. Sorting only changes how the window shows them - nothing in your
-- real bags is moved.
local _, S = ...
local UI = S.UI

local CC = C_Container
local HEAD, SEARCH_H, FOOT, BAGBAR_H, HDR_H = 26, 26, 24, 28, 15
local QMARK = "Interface\\Icons\\INV_Misc_QuestionMark"

local function G() return S.db.global end
local function combat() return InCombatLockdown and InCombatLockdown() end
local function clean(v) if issecretvalue and issecretvalue(v) then return nil end return v end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
local DEF = {
  on = false,
  -- look
  cols = 12, size = 36, spacing = 4, pad = 10, gap = 10, scale = 1,
  bg = "theme", bgColor = { 0.06, 0.06, 0.07 }, bgAlpha = 0.94, edgeColor = { 0.32, 0.32, 0.36 }, edgeTheme = true,
  slot = "theme", slotColor = { 0.13, 0.13, 0.15 }, slotAlpha = 0.9, round = 0,
  -- sorting
  sort = "type", desc = false, group = true, flow = true, headers = true, split = false,
  empty = "one", reagentSplit = true, reagentColor = { 0.25, 0.75, 0.45 }, newFirst = true, junkLast = true, cats = {},
  -- show
  quality = true, ilvl = true, junk = true, newGlow = true, gold = true, free = true, bagBar = false,
  search = true, cool = true, questMark = true,
  -- behaviour
  hold = false, lock = false, autoJunk = false,
  openVendor = true, openMail = true, openBank = true, openAH = true, openTrade = true,
}
local function copy(v) if type(v) ~= "table" then return v end local c = {} for k, x in pairs(v) do c[k] = copy(x) end return c end
local function cfg()
  local g = G()
  g.bib = type(g.bib) == "table" and g.bib or {}
  local b = g.bib
  for k, v in pairs(DEF) do if b[k] == nil then b[k] = copy(v) end end
  return b
end
S.BiBConfig = cfg

function S:BiBIsOn() return S.db ~= nil and cfg().on == true end

---------------------------------------------------------------------------
-- Reading the bags
---------------------------------------------------------------------------
local function numSlots(bag)
  local ok, n = pcall(function()
    return (CC and CC.GetContainerNumSlots and CC.GetContainerNumSlots(bag)) or (GetContainerNumSlots and GetContainerNumSlots(bag)) or 0
  end)
  return ok and tonumber(clean(n)) or 0
end
local function bagFamily(bag)
  local ok, _, fam = pcall(function()
    if CC and CC.GetContainerNumFreeSlots then return CC.GetContainerNumFreeSlots(bag) end
    if GetContainerNumFreeSlots then return GetContainerNumFreeSlots(bag) end
    return 0, 0
  end)
  return ok and tonumber(clean(fam)) or 0
end
local function bagList()
  local out = {}
  local n = tonumber(NUM_BAG_SLOTS) or 4
  for b = 0, n do out[#out + 1] = b end
  local rb = Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag
  if rb and rb > n and numSlots(rb) > 0 then out[#out + 1] = rb end
  return out
end
S.BiBBags = bagList

local function slotInfo(bag, slot)
  local ok, r = pcall(function()
    if CC and CC.GetContainerItemInfo then
      local i = CC.GetContainerItemInfo(bag, slot)
      if type(i) ~= "table" then return nil end
      return { icon = clean(i.iconFileID), count = clean(i.stackCount), locked = clean(i.isLocked), quality = clean(i.quality),
        link = clean(i.hyperlink), id = clean(i.itemID), bound = clean(i.isBound), noValue = clean(i.hasNoValue), lootable = clean(i.hasLoot) }
    elseif GetContainerItemInfo then
      local tex, count, locked, quality, _, lootable, link, _, noValue, id = GetContainerItemInfo(bag, slot)
      if not tex then return nil end
      return { icon = tex, count = count, locked = locked, quality = quality, link = link, id = id, noValue = noValue, lootable = lootable }
    end
  end)
  if ok then return r end
end
local function pickup(bag, slot)
  if CC and CC.PickupContainerItem then CC.PickupContainerItem(bag, slot) elseif PickupContainerItem then PickupContainerItem(bag, slot) end
end
local function useItem(bag, slot)
  if CC and CC.UseContainerItem then CC.UseContainerItem(bag, slot) elseif UseContainerItem then UseContainerItem(bag, slot) end
end
local function isNew(bag, slot)
  local ok, v = pcall(function() return C_NewItems and C_NewItems.IsNewItem and C_NewItems.IsNewItem(bag, slot) end)
  return ok and clean(v) and true or false
end
local function questInfo(bag, slot)
  local ok, q, qid, active = pcall(function()
    if CC and CC.GetContainerItemQuestInfo then
      local t = CC.GetContainerItemQuestInfo(bag, slot)
      if type(t) == "table" then return t.isQuestItem, t.questID, t.isActive end
    elseif GetContainerItemQuestInfo then return GetContainerItemQuestInfo(bag, slot) end
  end)
  if not ok then return false end
  return (clean(q) or clean(qid)) and true or false, clean(qid) and not clean(active)
end

local GII = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GIII = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local GDIL = (C_Item and C_Item.GetDetailedItemLevelInfo) or GetDetailedItemLevelInfo
local missing = false            -- some item info wasn't loaded yet (refresh when it arrives)
local function itemData(r)
  local ok, name, _, _, ilvl, _, typ, sub, maxStack, equipLoc, _, price, classID, subID = pcall(GII, r.link or r.id)
  if not ok or not name then
    missing = true
    if C_Item and C_Item.RequestLoadItemDataByID and r.id then pcall(C_Item.RequestLoadItemDataByID, r.id) end
    ok = false
  end
  if ok then
    r.name, r.ilvl, r.typ, r.sub, r.maxStack, r.equipLoc, r.price, r.classID, r.subID = name, ilvl, typ, sub, maxStack, equipLoc, price, classID, subID
  end
  if (not r.classID) and GIII then
    local ok2, _, t2, s2, el, _, c, sc = pcall(GIII, r.link or r.id)
    if ok2 then r.typ = r.typ or t2; r.sub = r.sub or s2; r.equipLoc = r.equipLoc or el; r.classID = c; r.subID = sc end
  end
  if GDIL and r.link and (r.classID == 2 or r.classID == 4) then
    local ok3, v = pcall(GDIL, r.link); if ok3 and tonumber(v) then r.ilvl = v end
  end
end

---------------------------------------------------------------------------
-- Sections and sorting
---------------------------------------------------------------------------
local CATS = {
  { id = "new", name = "New items", tip = "Things you just picked up." },
  { id = "equip", name = "Equipment", tip = "Weapons and armour you can wear." },
  { id = "cons", name = "Consumables", tip = "Food, drink, potions, scrolls, bandages..." },
  { id = "quest", name = "Quest items" },
  { id = "trade", name = "Trade goods", tip = "Crafting materials and reagents." },
  { id = "recipe", name = "Recipes" },
  { id = "gem", name = "Gems & enchants", tip = "Gems, item enhancements and glyphs." },
  { id = "bags", name = "Bags & ammo", tip = "Bags, quivers, ammo pouches and ammunition." },
  { id = "misc", name = "Everything else" },
  { id = "junk", name = "Junk", tip = "Grey items - sell them." },
}
local CAT_RANK, CAT_NAME = {}, {}
for i, c in ipairs(CATS) do CAT_RANK[c.id] = i; CAT_NAME[c.id] = c.name end
CAT_RANK.empty = 99; CAT_NAME.empty = "Free slots"

-- your section order (Options > Sorting): ids top to bottom
function S.BiBOrder()
  local c = cfg()
  local out, seen = {}, {}
  for _, id in ipairs(type(c.order) == "table" and c.order or {}) do if CAT_NAME[id] and id ~= "empty" and not seen[id] then seen[id] = true; out[#out + 1] = id end end
  for _, cat in ipairs(CATS) do if not seen[cat.id] then out[#out + 1] = cat.id end end
  return out
end
function S.BiBMoveSection(id, how)
  local ord = S.BiBOrder()
  local at; for i, x in ipairs(ord) do if x == id then at = i end end
  if not at then return end
  table.remove(ord, at)
  local to = (how == "top" and 1) or (how == "bottom" and #ord + 1) or math.max(1, math.min(#ord + 1, at + how))
  table.insert(ord, to, id)
  cfg().order = ord
  S:RefreshBiB(true)
end
S.BiBCategories = CATS

local function category(r, c, noNew)
  if r.new and c.newFirst and c.cats.new ~= false and not noNew then return "new" end
  if r.quality == 0 and c.cats.junk ~= false then return "junk" end
  local cl, id = r.classID, "misc"
  if r.quest or cl == 12 then id = "quest"
  elseif cl == 2 or cl == 4 then id = (r.equipLoc and r.equipLoc ~= "" and not tostring(r.equipLoc):find("BAG")) and "equip" or "misc"
  elseif cl == 0 then id = "cons"
  elseif cl == 7 or cl == 5 then id = "trade"
  elseif cl == 9 then id = "recipe"
  elseif cl == 3 or cl == 8 or cl == 16 then id = "gem"
  elseif cl == 1 or cl == 11 or cl == 6 then id = "bags" end
  if c.cats[id] == false then id = "misc" end
  return id
end

local SORTS = {
  { value = "type", text = "Type", tip = "Weapons, armour, consumables, trade goods... then quality and name." },
  { value = "quality", text = "Quality", tip = "Best quality first." },
  { value = "name", text = "Name", tip = "A to Z." },
  { value = "ilvl", text = "Item level", tip = "Highest item level first." },
  { value = "price", text = "Sell value", tip = "What the stack sells for at a vendor - most first." },
  { value = "count", text = "Stack size", tip = "Biggest stacks first." },
  { value = "newest", text = "Newest", tip = "The last things you picked up first." },
  { value = "id", text = "Item ID", tip = "The game's item number." },
  { value = "bag", text = "Bag order", tip = "No sorting - slots in the order your bags hold them." },
}
S.BiBSorts = SORTS
-- item types (the game's item classes), default order
local TYPES = {
  { id = 2, name = "Weapons" }, { id = 4, name = "Armour" }, { id = 0, name = "Consumables" }, { id = 12, name = "Quest items" },
  { id = 7, name = "Trade goods" }, { id = 5, name = "Reagents" }, { id = 3, name = "Gems" }, { id = 8, name = "Item enhancements" },
  { id = 16, name = "Glyphs" }, { id = 9, name = "Recipes" }, { id = 1, name = "Bags" }, { id = 11, name = "Quivers & pouches" },
  { id = 6, name = "Ammo" }, { id = 15, name = "Miscellaneous" }, { id = 13, name = "Keys" }, { id = 17, name = "Battle pets" },
}
local TYPE_NAME = {}
for _, t in ipairs(TYPES) do TYPE_NAME[t.id] = t.name end
S.BiBTypes = TYPES
-- your type order (sort by Type): class ids first to last
function S.BiBTypeOrder()
  local c = cfg()
  local out, seen = {}, {}
  for _, id in ipairs(type(c.typeOrder) == "table" and c.typeOrder or {}) do if TYPE_NAME[id] and not seen[id] then seen[id] = true; out[#out + 1] = id end end
  for _, t in ipairs(TYPES) do if not seen[t.id] then out[#out + 1] = t.id end end
  return out
end
local TYPE_RANK = {}
local function rebuildTypeRank()
  wipe(TYPE_RANK)
  for i, id in ipairs(S.BiBTypeOrder()) do TYPE_RANK[id] = i end
end
function S.BiBMoveType(id, how)
  local ord = S.BiBTypeOrder()
  local at; for i, x in ipairs(ord) do if x == id then at = i end end
  if not at then return end
  table.remove(ord, at)
  local to = (how == "top" and 1) or (how == "bottom" and #ord + 1) or (type(how) == "table" and how[1]) or math.max(1, math.min(#ord + 1, at + how))
  to = math.max(1, math.min(#ord + 1, to))
  table.insert(ord, to, id)
  cfg().typeOrder = ord
  rebuildTypeRank()
  S:RefreshBiB(true)
end
-- types you keep at the bottom of the bag (after the free slots)
local function atBottom(r)
  local b = cfg().typeBottom
  if type(b) ~= "table" or r.empty then return false end
  if b[r.classID or -1] then return true end
  if r.quest and b[12] then return true end
  return false
end
function S.BiBSetTypeBottom(id, on)
  local c = cfg()
  c.typeBottom = type(c.typeBottom) == "table" and c.typeBottom or {}
  c.typeBottom[id] = on and true or nil
  S:RefreshBiB(true)
end

local function seenAt(r)
  local s = cfg().seen
  return (s and r.id and s[r.id]) or 0
end
local function primary(r, mode)
  if mode == "type" then return (TYPE_RANK[r.classID or -1] or 50) * 1000 + (r.subID or 0) end
  if mode == "quality" then return -(r.quality or 0) end
  if mode == "name" then return (r.name or ""):lower() end
  if mode == "ilvl" then return -(r.ilvl or 0) end
  if mode == "price" then return -((r.price or 0) * (r.count or 1)) end
  if mode == "count" then return -(r.count or 1) end
  if mode == "newest" then return -seenAt(r) end
  if mode == "id" then return r.id or 0 end
  return 0
end
local TIES = { "type", "quality", "ilvl", "name", "count", "id" }
-- sort keys are worked out once per item, not on every comparison
local function key(r, mode)
  local k = r._keys
  if not k then k = {}; r._keys = k end
  local v = k[mode]
  if v == nil then v = primary(r, mode); k[mode] = v end
  return v
end
local function less(a, b, c)
  if a.empty ~= b.empty then return b.empty and true or false end
  if not a.empty then
    if c.junkLast and ((a.quality == 0) ~= (b.quality == 0)) then return b.quality == 0 end
    if c.sort ~= "bag" then
      local ka, kb = key(a, c.sort), key(b, c.sort)
      if ka ~= kb then if c.desc then return ka > kb end return ka < kb end
      for _, m in ipairs(TIES) do
        if m ~= c.sort then
          local x, y = key(a, m), key(b, m)
          if x ~= y then return x < y end
        end
      end
      local la, lb = a.link or "", b.link or ""
      if la ~= lb then return la < lb end
    end
  end
  if a.bag ~= b.bag then return a.bag < b.bag end
  return a.slot < b.slot
end
S.BiBLess = less

local function bagName(bag)
  if bag == 0 then return BACKPACK_TOOLTIP or "Backpack" end
  local ok, n = pcall(function()
    return (CC and CC.GetBagName and CC.GetBagName(bag)) or (GetBagName and GetBagName(bag))
  end)
  return (ok and clean(n)) or ("Bag " .. bag)
end

-- everything in the bags, one record per slot
local function scan(noNew)
  local c = cfg()
  local list, total, free = {}, 0, 0
  c.seen = type(c.seen) == "table" and c.seen or {}
  local firstScan = not c.seenInit
  for _, bag in ipairs(bagList()) do
    local fam = bagFamily(bag)
    for slot = 1, numSlots(bag) do
      total = total + 1
      local r = { bag = bag, slot = slot, family = fam }
      local info = slotInfo(bag, slot)
      if info and (info.link or info.id or info.icon) then
        for k, v in pairs(info) do r[k] = v end
        r.count = tonumber(r.count) or 1
        itemData(r)
        r.quality = r.quality or 1
        r.new = isNew(bag, slot)
        r.quest, r.questStart = questInfo(bag, slot)
        if r.id and not c.seen[r.id] then c.seen[r.id] = firstScan and 1 or time() end
        r.cat = category(r, c, noNew)
      else
        free = free + 1
        r.empty = true; r.cat = "empty"
      end
      list[#list + 1] = r
    end
  end
  c.seenInit = true
  return list, total, free
end
S.BiBScan = scan

local REAGENT_NAME = "Reagent bag"

-- the sections to draw, in order: { id, name, items }
local function sections(list, c, onlyBag)
  local out, byId = {}, {}
  local ranks = {}
  for i, id in ipairs(S.BiBOrder()) do ranks[id] = i end
  rebuildTypeRank()
  local reagentBag = Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag
  local function sec(id, name, rank)
    local s = byId[id]
    if not s then s = { id = id, name = name, rank = rank, items = {}, empties = {} }; byId[id] = s; out[#out + 1] = s end
    return s
  end
  for _, r in ipairs(list) do
    if onlyBag == nil or r.bag == onlyBag then
      local s
      if c.reagentSplit and reagentBag and r.bag == reagentBag then s = sec("reagent", REAGENT_NAME, 200)
      elseif c.split then s = sec("bag" .. r.bag, bagName(r.bag), r.bag)
      elseif c.group then
        if r.empty then s = sec("empty", CAT_NAME.empty, 99) else s = sec(r.cat, CAT_NAME[r.cat] or r.cat, ranks[r.cat] or 50) end
      else s = sec("all", "", 1) end
      if r.empty then s.empties[#s.empties + 1] = r else s.items[#s.items + 1] = r end
    end
  end
  table.sort(out, function(a, b) return a.rank < b.rank end)
  for _, s in ipairs(out) do
    table.sort(s.items, function(a, b) return less(a, b, c) end)
    -- "keep at the bottom" types go after the free slots
    local bottom = {}
    for i = #s.items, 1, -1 do if atBottom(s.items[i]) then table.insert(bottom, 1, table.remove(s.items, i)) end end
    s.bottom = bottom
    -- free slots: all of them, one per kind of bag (with a count), or none
    if c.empty == "all" then
      for _, e in ipairs(s.empties) do s.items[#s.items + 1] = e end
    elseif c.empty == "one" then
      local byFam = {}
      for _, e in ipairs(s.empties) do
        local f = byFam[e.family]
        if not f then f = e; f.freeCount = 0; byFam[e.family] = f; s.items[#s.items + 1] = f end
        f.freeCount = f.freeCount + 1
      end
    end
    for _, r in ipairs(s.bottom) do s.items[#s.items + 1] = r end
    -- a section made only of bottom types goes to the end of the window
    if #s.bottom > 0 and #s.bottom == #s.items then s.rank = s.rank + 1000 end
  end
  table.sort(out, function(a, b) return a.rank < b.rank end)
  for i = #out, 1, -1 do if #out[i].items == 0 then table.remove(out, i) end end
  return out
end
S.BiBSections = sections

---------------------------------------------------------------------------
-- Search: name, type, section, quality ("epic"), "boe", "bound", "junk", "new",
-- "quest", "ilvl>100" / "ilvl<50"
---------------------------------------------------------------------------
local QNAMES = { poor = 0, grey = 0, gray = 0, common = 1, white = 1, uncommon = 2, green = 2, rare = 3, blue = 3, epic = 4, purple = 4, legendary = 5, orange = 5, artifact = 6, heirloom = 7 }
local function matches(r, q)
  if r.empty then return false end
  for word in q:gmatch("%S+") do
    local hit = false
    local op, num = word:match("^ilvl([<>=])(%d+)$")
    if op then
      local l = r.ilvl or 0; num = tonumber(num)
      hit = (op == ">" and l > num) or (op == "<" and l < num) or (op == "=" and l == num)
    elseif QNAMES[word] then hit = r.quality == QNAMES[word]
    elseif word == "boe" then hit = (r.classID == 2 or r.classID == 4) and not r.bound
    elseif word == "bound" or word == "soulbound" then hit = r.bound and true or false
    elseif word == "junk" then hit = r.quality == 0
    elseif word == "new" then hit = r.new
    elseif word == "quest" then hit = r.quest
    else
      for _, field in ipairs({ r.name, r.typ, r.sub, CAT_NAME[r.cat] }) do
        if field and tostring(field):lower():find(word, 1, true) then hit = true break end
      end
    end
    if not hit then return false end
  end
  return true
end
S.BiBMatches = matches

---------------------------------------------------------------------------
-- Item buttons (the game's own bag-slot template)
---------------------------------------------------------------------------
local win, opts
local btns, holders, headers = {}, {}, {}
local nextBtn = 0
local layoutDirty, paintDirty = false, false
local onlyBag, hoverBag

local function holder(bag)
  local h = holders[bag]
  if not h then
    h = CreateFrame("Frame", "CC_BiBBag" .. (bag < 0 and ("M" .. -bag) or bag), win.content)
    h:SetID(bag); h:SetSize(1, 1); h:SetPoint("TOPLEFT")
    holders[bag] = h
  end
  return h
end

local function edgeLines(b)
  b.edge = {}
  for i = 1, 4 do b.edge[i] = b:CreateTexture(nil, "OVERLAY", nil, 6) end
  local e, t = b.edge, 1.5
  e[1]:SetPoint("TOPLEFT"); e[1]:SetPoint("TOPRIGHT"); e[1]:SetHeight(t)
  e[2]:SetPoint("BOTTOMLEFT"); e[2]:SetPoint("BOTTOMRIGHT"); e[2]:SetHeight(t)
  e[3]:SetPoint("TOPLEFT"); e[3]:SetPoint("BOTTOMLEFT"); e[3]:SetWidth(t)
  e[4]:SetPoint("TOPRIGHT"); e[4]:SetPoint("BOTTOMRIGHT"); e[4]:SetWidth(t)
end
local function setEdge(b, r, g, bl, a)
  local round = b.bibRing and b.bibRound and b.bibRound > 0
  for _, t in ipairs(b.edge) do
    if r and not round then t:SetColorTexture(r, g, bl, a or 1); t:Show() else t:Hide() end
  end
  if b.bibRing then
    if r and round then b.bibRing:SetVertexColor(r, g, bl, a or 1); b.bibRing:Show() else b.bibRing:Hide() end
  end
end

-- Roundness: 0 = square ... 5 = circle (rounded masks on the icon / slot, a rounded border)
local RMASK = "Interface\\AddOns\\CommandCenter\\Media\\UI\\rmask"
local RRING = "Interface\\AddOns\\CommandCenter\\Media\\UI\\rring"
local function maskable(t) return type(t) == "table" and type(t.AddMaskTexture) == "function" end
local function applyRound(b, lvl)
  lvl = math.max(0, math.min(5, math.floor(tonumber(lvl) or 0)))
  if b.bibRound == lvl then return end
  b.bibRound = lvl
  if not b.bibRing then
    b.bibRing = b:CreateTexture(nil, "OVERLAY", nil, 6); b.bibRing:SetAllPoints(); b.bibRing:Hide()
  end
  b.bibRing:SetTexture(RRING .. lvl)
  if b.CreateMaskTexture then
    if not b.bibMask then
      local ok, m = pcall(b.CreateMaskTexture, b)
      if ok and m then
        b.bibMask = m; m:SetAllPoints()
        local hl = b.GetHighlightTexture and b:GetHighlightTexture()
        local pu = b.GetPushedTexture and b:GetPushedTexture()
        for _, t in ipairs({ b.bibIcon, b.bibBg, b.bibDim, hl, pu }) do if maskable(t) then pcall(t.AddMaskTexture, t, m) end end
      end
    end
    if b.bibMask then
      pcall(b.bibMask.SetTexture, b.bibMask, RMASK .. lvl, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    end
  end
  -- cooldown sweep follows the shape too
  if b.bibCool and b.bibCool.SetSwipeTexture then
    if lvl > 0 then pcall(b.bibCool.SetSwipeTexture, b.bibCool, RMASK .. lvl) else pcall(b.bibCool.SetSwipeTexture, b.bibCool, "Interface\\Buttons\\WHITE8X8") end
  end
end

-- the game's own bag-slot overlays (quality border, new-item glow, junk coin...): ours
-- replace them, and they must never linger on a slot whose item moved away
local TEMPLATE_BITS = { "IconBorder", "IconOverlay", "IconOverlay2", "JunkIcon", "NewItemTexture", "BattlepayItemTexture",
  "ItemContextOverlay", "UpgradeIcon", "ExtendedSlot", "ExtendedOverlay", "ExtendedOverlay2" }
local function quietTemplate(b)
  for _, k in ipairs(TEMPLATE_BITS) do
    local v = b[k]
    if type(v) == "table" and type(v.Hide) == "function" then v:Hide() end
  end
  for _, k in ipairs({ "flashAnim", "newitemglowAnim" }) do
    local a = b[k]
    if type(a) == "table" and type(a.Stop) == "function" then pcall(a.Stop, a) end
  end
end

local function region(b, key, suffix)
  for _, v in ipairs({ rawget(b, key) or b[key], b:GetName() and _G[b:GetName() .. suffix] }) do
    if type(v) == "table" and type(v.Hide) == "function" then return v end
  end
end

local function hideBit(b, k)
  local v = b[k]
  if type(v) == "table" and type(v.Hide) == "function" then v:Hide() end
end

local function makeButton(bag, slot)
  nextBtn = nextBtn + 1
  local name = "CC_BiBItem" .. nextBtn
  local parent = holder(bag)
  local ok, b = pcall(CreateFrame, "ItemButton", name, parent, "ContainerFrameItemButtonTemplate")
  if not ok or not b then ok, b = pcall(CreateFrame, "Button", name, parent, "ContainerFrameItemButtonTemplate") end
  if not ok or not b then
    -- no bag-slot template: a plain button that picks up / uses the item
    b = CreateFrame("Button", name, parent)
    b.plain = true
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnClick", function(self, btn)
      if btn == "RightButton" then pcall(useItem, self.bag, self.slot) else pickup(self.bag, self.slot) end
    end)
    b:SetScript("OnDragStart", function(self) pickup(self.bag, self.slot) end)
    b:SetScript("OnReceiveDrag", function(self) pickup(self.bag, self.slot) end)
    b:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      if GameTooltip.SetBagItem then GameTooltip:SetBagItem(self.bag, self.slot) end
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
  b.bag, b.slot = bag, slot
  b:SetID(slot)
  if b.SetBagID then pcall(b.SetBagID, b, bag) end
  -- the template's pieces (named differently across game versions)
  b.bibIcon = region(b, "icon", "IconTexture") or region(b, "Icon", "Icon")
  if not b.bibIcon then b.bibIcon = b:CreateTexture(nil, "BORDER"); b.bibIcon:SetAllPoints() end
  b.bibCount = region(b, "Count", "Count")
  if not b.bibCount then b.bibCount = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal"); b.bibCount:SetPoint("BOTTOMRIGHT", -2, 2) end
  b.bibCool = region(b, "Cooldown", "Cooldown")
  if not b.bibCool and not b.plain then
    local okc, cd = pcall(CreateFrame, "Cooldown", nil, b, "CooldownFrameTemplate"); if okc then b.bibCool = cd; cd:SetAllPoints() end
  end
  b.bibQuest = region(b, "IconQuestTexture", "IconQuestTexture")
  -- our own pieces
  b.bibBg = b:CreateTexture(nil, "BACKGROUND", nil, -7); b.bibBg:SetAllPoints()
  edgeLines(b)
  b.bibLvl = b:CreateFontString(nil, "OVERLAY"); b.bibLvl:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE"); b.bibLvl:SetPoint("TOPLEFT", 2, -2)
  b.bibFree = b:CreateFontString(nil, "OVERLAY"); b.bibFree:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE"); b.bibFree:SetPoint("CENTER")
  b.bibCoin = b:CreateTexture(nil, "OVERLAY", nil, 7); b.bibCoin:SetTexture("Interface\\Buttons\\UI-GroupLoot-Coin-Up")
  b.bibCoin:SetSize(13, 13); b.bibCoin:SetPoint("TOPLEFT", 1, -1)
  b.bibBang = b:CreateTexture(nil, "OVERLAY", nil, 7); b.bibBang:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
  b.bibBang:SetSize(14, 14); b.bibBang:SetPoint("TOPRIGHT", 0, 0)
  b.bibGlow = b:CreateTexture(nil, "OVERLAY", nil, 5); b.bibGlow:SetTexture(UI.ART.glow); b.bibGlow:SetBlendMode("ADD")
  b.bibGlow:SetPoint("TOPLEFT", -6, 6); b.bibGlow:SetPoint("BOTTOMRIGHT", 6, -6)
  b.bibDim = b:CreateTexture(nil, "OVERLAY", nil, 7); b.bibDim:SetAllPoints(); b.bibDim:SetColorTexture(0, 0, 0, 0.7); b.bibDim:Hide()
  -- hovering a new item makes it old (like the game's bags)
  b:HookScript("OnEnter", function(self)
    if self.rec and self.rec.new then
      pcall(function() if C_NewItems and C_NewItems.RemoveNewItem then C_NewItems.RemoveNewItem(self.bag, self.slot) end end)
      self.rec.new = false; self.bibGlow:Hide()
    end
  end)
  return b
end

local function getButton(bag, slot)
  local key = bag .. ":" .. slot
  local b = btns[key]
  if not b then b = makeButton(bag, slot); btns[key] = b end
  return b
end

local function qColor(q)
  if q == nil then return end
  local qc = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
  if qc then return qc.r, qc.g, qc.b end
  if GetItemQualityColor then local ok, r, g, b = pcall(GetItemQualityColor, q); if ok and r then return r, g, b end end
  local fall = { [0] = { 0.62, 0.62, 0.62 }, { 1, 1, 1 }, { 0.12, 1, 0 }, { 0, 0.44, 0.87 }, { 0.64, 0.21, 0.93 }, { 1, 0.5, 0 }, { 0.9, 0.8, 0.5 }, { 0, 0.8, 1 } }
  local f = fall[q]; if f then return f[1], f[2], f[3] end
end

local function slotLook(b, c)
  local th = UI:Theme()
  local nt = b.GetNormalTexture and b:GetNormalTexture()
  if type(nt) ~= "table" or type(nt.SetAlpha) ~= "function" then nt = nil end
  if c.slot == "blizzard" then
    b.bibBg:SetTexture("Interface\\Buttons\\UI-EmptySlot-Disabled"); b.bibBg:SetTexCoord(0.14, 0.86, 0.14, 0.86); b.bibBg:SetVertexColor(1, 1, 1, 1); b.bibBg:Show()
    if nt then nt:SetAlpha(1); local s = c.size * 64 / 37; nt:ClearAllPoints(); nt:SetPoint("CENTER"); nt:SetSize(s, s) end
  else
    if nt then nt:SetAlpha(0) end
    if c.slot == "none" then b.bibBg:Hide()
    else
      local col = c.slot == "custom" and c.slotColor or th.field
      b.bibBg:SetTexCoord(0, 1, 0, 1)
      b.bibBg:SetColorTexture(col[1], col[2], col[3], c.slot == "custom" and c.slotAlpha or 0.85); b.bibBg:Show()
    end
  end
end

local function paint(b, r, c)
  b.rec = r
  local th = UI:Theme()
  applyRound(b, c.round)
  slotLook(b, c)
  quietTemplate(b)
  if r.empty then
    b.bibIcon:SetTexture(nil); b.bibIcon:Hide()
    b.bibCount:SetText(""); b.bibCount:Hide()
    b.bibLvl:SetText(""); b.bibCoin:Hide(); b.bibBang:Hide(); b.bibGlow:Hide()
    if b.bibQuest then b.bibQuest:Hide() end
    if b.bibCool and b.bibCool.Clear then pcall(b.bibCool.Clear, b.bibCool) elseif b.bibCool then b.bibCool:Hide() end
    b.bibFree:SetText((c.empty == "one" and (r.freeCount or 0) > 1) and ("|cff888888" .. r.freeCount .. "|r") or "")
    setEdge(b)                              -- free slots: no border, nothing lit up
    b.bibDim:Hide()
    b.hasItem = nil
    return
  end
  b.hasItem = true
  b.bibFree:SetText("")
  b.bibIcon:SetTexture(r.icon or QMARK); b.bibIcon:Show()
  b.bibIcon:SetDesaturated(r.locked and true or false)
  if r.count and r.count > 1 then b.bibCount:SetText(r.count > 9999 and (math.floor(r.count / 1000) .. "k") or r.count); b.bibCount:Show()
  else b.bibCount:SetText(""); b.bibCount:Hide() end
  -- quality edge (quest items gold)
  local qr, qg, qb = nil, nil, nil
  if r.quest and c.questMark then qr, qg, qb = 1, 0.82, 0
  elseif c.quality and (r.quality or 1) >= 2 then qr, qg, qb = qColor(r.quality)
  elseif c.slot == "theme" or c.slot == "custom" then qr, qg, qb = th.edge[1], th.edge[2], th.edge[3] end
  setEdge(b, qr, qg, qb, 1)
  b.bibLvl:SetText((c.ilvl and (r.classID == 2 or r.classID == 4) and r.equipLoc and r.equipLoc ~= "" and (r.ilvl or 0) > 1) and r.ilvl or "")
  if c.quality and r.quality then local rr, gg, bb = qColor(r.quality); if rr then b.bibLvl:SetTextColor(rr, gg, bb) end end
  b.bibCoin:SetShown(c.junk and r.quality == 0 and not r.noValue and true or false)
  b.bibBang:SetShown(c.questMark and r.questStart and true or false)
  if b.bibQuest then b.bibQuest:Hide() end
  b.bibGlow:SetShown(c.newGlow and r.new and true or false)
  b.bibGlow:SetVertexColor(th.gold[1], th.gold[2], th.gold[3], 0.6)
  -- cooldown
  if b.bibCool and c.cool then
    local ok, st, du, en = pcall(function()
      if CC and CC.GetContainerItemCooldown then return CC.GetContainerItemCooldown(r.bag, r.slot) end
      if GetContainerItemCooldown then return GetContainerItemCooldown(r.bag, r.slot) end
    end)
    st, du, en = ok and clean(st), ok and clean(du), ok and clean(en)
    if st and du and du > 0 then
      if CooldownFrame_Set then pcall(CooldownFrame_Set, b.bibCool, st, du, en) elseif b.bibCool.SetCooldown then b.bibCool:SetCooldown(st, du) end
      b.bibCool:Show()
    elseif b.bibCool.Clear then pcall(b.bibCool.Clear, b.bibCool) end
  end
end

---------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------
local function header(i)
  local h = headers[i]
  if not h then
    h = win.content:CreateFontString(nil, "OVERLAY")
    h:SetFontObject(UI.fSmall); h:SetJustifyH("LEFT"); h:SetWordWrap(false)
    headers[i] = h
  end
  return h
end

local function applyBackground(c)
  local th = UI:Theme()
  local edge = c.edgeTheme and th.edge or c.edgeColor
  if c.bg == "theme" then
    win.bibTex:Hide()
    UI.Flat(win, th.bg, c.bgAlpha, edge, 1, 2)
  else
    local tex = ({ marble = "Interface\\FrameGeneral\\UI-Background-Marble", rock = "Interface\\FrameGeneral\\UI-Background-Rock",
      dialog = "Interface\\DialogFrame\\UI-DialogBox-Background", dark = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
      tooltip = "Interface\\Tooltips\\UI-Tooltip-Background" })[c.bg]
    UI.Flat(win, c.bg == "solid" and c.bgColor or { 0, 0, 0 }, c.bg == "solid" and c.bgAlpha or 0, edge, 1, 2)
    if tex then
      win.bibTex:SetTexture(tex, true, true)
      if win.bibTex.SetHorizTile then win.bibTex:SetHorizTile(true); win.bibTex:SetVertTile(true) end
      win.bibTex:SetVertexColor(c.bgColor[1], c.bgColor[2], c.bgColor[3], c.bgAlpha)
      win.bibTex:Show()
    else win.bibTex:Hide() end
  end
end

local placed = {}         -- bag:slot -> true for the buttons on screen
local function slotSig()
  local t = {}
  for _, bag in ipairs(bagList()) do t[#t + 1] = bag .. "=" .. numSlots(bag) end
  return table.concat(t, ",")
end

local function searchText() return (win and win.search and win.search:GetText() or ""):lower():gsub("^%s+", ""):gsub("%s+$", "") end

local function dimAll()
  local q = searchText()
  for _, b in pairs(btns) do
    local r = b.rec
    if b:IsShown() and r then
      local dim = false
      if q ~= "" then dim = not matches(r, q) end
      if hoverBag ~= nil and r.bag ~= hoverBag then dim = true end
      b.bibDim:SetShown(dim)
    end
  end
end

-- quick refresh: same buttons, new contents (in combat, or "keep the order while open").
-- false when an item landed in a slot that isn't on screen (then it needs a full layout)
local function repaint()
  local c = cfg()
  local list, total, free = scan()
  for _, r in ipairs(list) do
    local b = btns[r.bag .. ":" .. r.slot]
    if not r.empty and not (b and b:IsShown()) and (onlyBag == nil or onlyBag == r.bag) then return false end
  end
  for _, r in ipairs(list) do
    local b = btns[r.bag .. ":" .. r.slot]
    if b and b:IsShown() then
      if r.empty and b.rec and b.rec.empty then r.freeCount = b.rec.freeCount end
      paint(b, r, c)
    end
  end
  win.freeText:SetText(c.free and (free .. " / " .. total .. " free") or "")
  dimAll()
  return true
end

local function moneyText()
  local m = GetMoney and GetMoney() or 0
  if GetCoinTextureString then local ok, s = pcall(GetCoinTextureString, m); if ok and s then return s end end
  return string.format("%dg %ds %dc", math.floor(m / 10000), math.floor(m / 100) % 100, m % 100)
end

local refreshBagBar

local function layout()
  if not win then return end
  local c = cfg()
  missing = false
  local list, total, free = scan()
  local secs = sections(list, c, onlyBag)
  local size, sp = c.size, c.spacing
  local cell = size + sp
  local cols = math.max(4, math.min(40, c.cols))
  local fullW = cols * cell - sp
  local hdrH = (c.headers and (c.group or c.split)) and HDR_H or 0
  for _, b in pairs(btns) do b:Hide() end
  for _, h in ipairs(headers) do h:Hide() end
  wipe(placed)
  local nh = 0
  local function place(s, x0, y0, bw)
    if hdrH > 0 and s.name ~= "" then
      nh = nh + 1
      local h = header(nh)
      h:ClearAllPoints(); h:SetPoint("TOPLEFT", win.content, "TOPLEFT", x0, -y0)
      h:SetWidth(math.max(size, bw * cell - sp))
      h:SetText(s.name); h:SetTextColor(UI.C(UI:Theme().gold)); h:Show()
    end
    for i, r in ipairs(s.items) do
      local b = getButton(r.bag, r.slot)
      local col, row = (i - 1) % bw, math.floor((i - 1) / bw)
      b:SetSize(size, size)
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", win.content, "TOPLEFT", x0 + col * cell, -(y0 + hdrH + row * cell))
      b:Show()
      paint(b, r, c)
      placed[r.bag .. ":" .. r.slot] = true
    end
    return hdrH + math.ceil(#s.items / bw) * cell - sp
  end
  -- the reagent bag gets its own bordered box at the bottom
  local reagent
  for i = #secs, 1, -1 do if secs[i].id == "reagent" then reagent = table.remove(secs, i) end end
  local y = 0
  if c.flow and (c.group or c.split) then
    -- small sections sit side by side
    local x, shelfH = 0, 0
    for _, s in ipairs(secs) do
      local bw = math.min(cols, math.max(#s.items, hdrH > 0 and 2 or 1))
      local wpx = bw * cell - sp
      if x > 0 and x + wpx > fullW + 0.5 then y = y + shelfH + c.gap; x = 0; shelfH = 0 end
      local h = place(s, x, y, bw)
      shelfH = math.max(shelfH, h)
      x = x + wpx + math.max(c.gap, sp + 4)
    end
    y = y + shelfH
  else
    for i, s in ipairs(secs) do
      y = y + place(s, 0, y, cols)
      if i < #secs then y = y + c.gap end
    end
  end
  if #secs == 0 and not reagent then y = 20 end
  win.emptyText:SetShown(#secs == 0 and not reagent)
  if not win.reagentBox then
    win.reagentBox = CreateFrame("Frame", nil, win.content)
    edgeLines(win.reagentBox)
    win.reagentBox.fill = win.reagentBox:CreateTexture(nil, "BACKGROUND", nil, -8); win.reagentBox.fill:SetAllPoints()
  end
  win.reagentBox:Hide()
  if reagent then
    local inset = 5
    if #secs > 0 then y = y + c.gap end
    y = y + inset
    local h = place(reagent, 0, y, cols)
    local box = win.reagentBox
    box:ClearAllPoints()
    box:SetPoint("TOPLEFT", win.content, "TOPLEFT", -inset, -(y - inset))
    box:SetSize(fullW + inset * 2, h + inset * 2)
    local rc = c.reagentColor
    setEdge(box, rc[1], rc[2], rc[3], 0.9)
    box.fill:SetColorTexture(rc[1], rc[2], rc[3], 0.06)
    box:Show()
    y = y + h + inset
  end
  -- frame around it
  local top = HEAD + 6 + (c.search and SEARCH_H or 0) + (c.bagBar and BAGBAR_H or 0)
  win.content:ClearAllPoints()
  win.content:SetPoint("TOPLEFT", c.pad, -top)
  win.content:SetSize(fullW, math.max(1, y))
  win:SetSize(fullW + c.pad * 2, top + y + c.pad + FOOT)
  win.search:SetShown(c.search)
  win.freeText:SetText(c.free and (free .. " / " .. total .. " free") or "")
  win.gold:SetText(c.gold and moneyText() or "")
  win:SetScale(c.scale)
  applyBackground(c)
  if refreshBagBar then refreshBagBar() end
  dimAll()
  win.slotSig = slotSig()
  win.laidOut = true
  -- remember whether anything is "new", so closing only clears new-item marks when needed
  local anyNew = false
  for _, r in ipairs(list) do if r.new then anyNew = true break end end
  win.anyNew = anyNew
  layoutDirty, paintDirty = false, false
end

function S:RefreshBiB(full)
  if not win or not win:IsShown() then layoutDirty = true return end
  local c = cfg()
  if not full and (combat() or c.hold) and win.slotSig == slotSig() and repaint() then return end
  layout()
end

---------------------------------------------------------------------------
-- Sell junk
---------------------------------------------------------------------------
local atVendor = false
function S:BiBSellJunk(quiet)
  if not atVendor then if not quiet then S:Print("Open a vendor first.") end return end
  local list = scan(true)
  local queue, value = {}, 0
  for _, r in ipairs(list) do
    if not r.empty and r.quality == 0 and not r.noValue and (r.price or 0) > 0 then
      queue[#queue + 1] = r; value = value + r.price * (r.count or 1)
    end
  end
  if #queue == 0 then if not quiet then S:Print("No junk to sell.") end return end
  local i = 0
  local function nextOne()
    i = i + 1
    local r = queue[i]
    if not r or not atVendor then return end
    pcall(useItem, r.bag, r.slot)
    C_Timer.After(0.2, nextOne)
  end
  nextOne()
  local m = value
  S:Print(string.format("Selling %d junk item%s for %s.", #queue, #queue == 1 and "" or "s",
    GetCoinTextureString and GetCoinTextureString(m) or (math.floor(m / 10000) .. "g")))
end

---------------------------------------------------------------------------
-- Bag bar: your bags across the top - hover to light up a bag, click to show just it
---------------------------------------------------------------------------
local bagBtns = {}
function refreshBagBar()
  local c = cfg()
  if not win.bagBar then return end
  win.bagBar:SetShown(c.bagBar)
  if not c.bagBar then return end
  win.bagBar:ClearAllPoints()
  win.bagBar:SetPoint("TOPLEFT", c.pad, -(HEAD + 6 + (c.search and SEARCH_H or 0)))
  local th = UI:Theme()
  for i, bag in ipairs(bagList()) do
    local b = bagBtns[i]
    if not b then
      b = CreateFrame("Button", nil, win.bagBar)
      b:SetSize(22, 22)
      b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetPoint("TOPLEFT", 1, -1); b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
      edgeLines(b)
      b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
      b:RegisterForDrag("LeftButton")
      -- equip a bag: drop it here (or click here while holding it); take one off: drag it out
      local function invSlot(self)
        if self.bag == 0 then return nil end
        local ok, inv = pcall(function()
          return (CC and CC.ContainerIDToInventoryID and CC.ContainerIDToInventoryID(self.bag)) or (ContainerIDToInventoryID and ContainerIDToInventoryID(self.bag))
        end)
        return ok and inv or nil
      end
      local function putBag(self)
        local inv = invSlot(self)
        if not inv or combat() then return false end
        if CursorHasItem and CursorHasItem() and PutItemInBag then pcall(PutItemInBag, inv); C_Timer.After(0.3, function() S:RefreshBiB(true) end) return true end
        return false
      end
      b:SetScript("OnReceiveDrag", function(self) putBag(self) end)
      b:SetScript("OnDragStart", function(self)
        local inv = invSlot(self)
        if not inv or combat() then return end
        if PickupBagFromSlot then pcall(PickupBagFromSlot, inv) elseif PickupInventoryItem then pcall(PickupInventoryItem, inv) end
      end)
      b.invSlot = invSlot
      b:SetScript("OnEnter", function(self)
        hoverBag = self.bag; dimAll()
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        local inv = invSlot(self)
        local hasBag = inv and GetInventoryItemTexture and GetInventoryItemTexture("player", inv)
        if hasBag and GameTooltip.SetInventoryItem then GameTooltip:SetInventoryItem("player", inv); GameTooltip:AddLine(" ") end
        GameTooltip:AddLine(bagName(self.bag), 1, 0.82, 0)
        local n = numSlots(self.bag)
        local free = 0
        for s = 1, n do if not slotInfo(self.bag, s) then free = free + 1 end end
        GameTooltip:AddLine(free .. " of " .. n .. " slots free", 1, 1, 1)
        GameTooltip:AddLine(onlyBag == self.bag and "Click to show all bags again." or "Click to show only this bag.", 0.6, 0.6, 0.6)
        if self.bag ~= 0 then GameTooltip:AddLine("Drop a bag here to equip it. Drag this bag out to take it off.", 0.6, 0.6, 0.6, true) end
        GameTooltip:Show()
      end)
      b:SetScript("OnLeave", function() hoverBag = nil; dimAll(); GameTooltip:Hide() end)
      b:SetScript("OnClick", function(self)
        if putBag(self) then return end           -- holding a bag: equip it here
        onlyBag = (onlyBag ~= self.bag) and self.bag or nil
        layout()
      end)
      bagBtns[i] = b
    end
    b.bag = bag
    b:ClearAllPoints(); b:SetPoint("LEFT", (i - 1) * 26, 0)
    local tex
    if bag == 0 then tex = "Interface\\Buttons\\Button-Backpack-Up"
    else
      local ok, t = pcall(function()
        local inv = (CC and CC.ContainerIDToInventoryID and CC.ContainerIDToInventoryID(bag)) or (ContainerIDToInventoryID and ContainerIDToInventoryID(bag))
        return inv and GetInventoryItemTexture and GetInventoryItemTexture("player", inv)
      end)
      tex = ok and t or "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag"
    end
    b.icon:SetTexture(tex)
    if onlyBag == bag then setEdge(b, th.gold[1], th.gold[2], th.gold[3], 1) else setEdge(b, th.edge[1], th.edge[2], th.edge[3], 1) end
    b:Show()
  end
  for i = #bagList() + 1, #bagBtns do bagBtns[i]:Hide() end
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local function savePos()
  if not win then return end
  win.__fromDock = nil
  local l, t = win:GetLeft(), win:GetTop()
  if l and t then cfg().at = { l * win:GetScale(), t * win:GetScale() }; win.ccOwnSpot = true end
end
local function restorePos()
  local at = cfg().at
  win:ClearAllPoints()
  if type(at) == "table" and at[1] then
    local s = win:GetScale()
    win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", at[1] / s, at[2] / s)
  else
    win:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -80, 110)    -- where the game's bags go
  end
end

local function sortMenu(self)
  local c = cfg()
  local items = { { text = "Sort by", title = true } }
  for _, s in ipairs(SORTS) do
    items[#items + 1] = { text = s.text, tip = s.tip, checked = c.sort == s.value, keep = true,
      func = function() c.sort = s.value; S:RefreshBiB(true) end }
  end
  if c.sort == "type" then
    items[#items + 1] = { text = "   Type order...", tip = "Drag the kinds of items into the order you want, and pick ones to keep at the bottom of the bag.",
      func = function() C_Timer.After(0, function() S:ShowBiBTypeOrder() end) end }
  end
  if c.sort ~= "type" then items[#items + 1] = { text = "Keep at the bottom...", tip = "Put chosen kinds of items (quest items, say) at the bottom of the bag; everything else fills from the top.",
    func = function() C_Timer.After(0, function() S:ShowBiBTypeOrder() end) end } end
  items[#items + 1] = { text = "Reverse the order", checked = c.desc, keep = true, func = function() c.desc = not c.desc; S:RefreshBiB(true) end }
  items[#items + 1] = { text = "Group into sections", checked = c.group and not c.split, keep = true,
    tip = "Equipment, consumables, trade goods, junk... each in its own section.",
    func = function() c.group = not c.group; if c.group then c.split = false end; S:RefreshBiB(true) end }
  items[#items + 1] = { text = "One section per bag", checked = c.split, keep = true,
    func = function() c.split = not c.split; S:RefreshBiB(true) end }
  items[#items + 1] = { text = "Section order...", tip = "Pick which kinds of items come first and which go last.", func = function() S:ShowBiBOptions(2) end }
  items[#items + 1] = { text = "More options...", func = function() S:ShowBiBOptions() end }
  UI:Menu(self, items)
end

local function build()
  local c = cfg()
  win = UI:Window("CC_BiB", "BiB", 400, 300, { header = HEAD })
  win:SetFrameStrata("MEDIUM")
  win.bibTex = win:CreateTexture(nil, "BACKGROUND", nil, -6)
  win.bibTex:SetPoint("TOPLEFT", 3, -3); win.bibTex:SetPoint("BOTTOMRIGHT", -3, 3)
  UI:Skin(win, function() applyBackground(cfg()) end)
  win.title:SetText("BiB")
  win:HeaderButton("settings", "BiB options", "Look, sorting, what to show, when it opens.", function() S:ShowBiBOptions() end)
  win.sortBtn = win:HeaderButton("sort", "Sort", "How BiB sorts and groups your items (nothing is moved in your real bags).", function(self, btn)
    sortMenu(self)
  end)
  win.sortBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  win:HeaderButton("bag", "Your bags", "Show your bags along the top - hover one to light it up, click to see only that bag.", function()
    local cc = cfg(); cc.bagBar = not cc.bagBar
    if not cc.bagBar then onlyBag = nil end
    S:RefreshBiB(true)
  end)
  win.search = UI:Edit(win, 200, 20, "Search  (name, type, epic, boe, ilvl>100...)")
  win.search:SetPoint("TOPLEFT", 10, -(HEAD + 6)); win.search:SetPoint("RIGHT", -10, 0)
  win.search:HookScript("OnTextChanged", function() dimAll() end)
  win.bagBar = CreateFrame("Frame", nil, win); win.bagBar:SetSize(200, 22)
  win.content = CreateFrame("Frame", nil, win)
  win.emptyText = UI:Text(win.content, "|cff888888Nothing here.|r", "small"); win.emptyText:SetPoint("TOPLEFT")
  win.freeText = UI:Text(win, "", "small"); win.freeText:SetPoint("BOTTOMLEFT", 12, 8)
  win.gold = UI:Text(win, "", "small", "RIGHT"); win.gold:SetPoint("BOTTOMRIGHT", -12, 8)
  win.junkBtn = UI:Button(win, "Sell junk", 80, 18, function() S:BiBSellJunk() end, "Sell every grey item to this vendor.")
  win.junkBtn:SetPoint("BOTTOM", 0, 4); win.junkBtn:Hide()
  restorePos()
  win:SetScript("OnDragStart", function(self) if not cfg().lock then self:StartMoving() end end)
  win:HookScript("OnDragStop", function() savePos() end)
  -- opening: only rebuild when something changed while it was closed (bags, settings...)
  win:HookScript("OnShow", function()
    if layoutDirty or not win.laidOut then layout()
    else win.gold:SetText(cfg().gold and moneyText() or "") end
    win.junkBtn:SetShown(atVendor)
  end)
  win:HookScript("OnHide", function()
    if win.search then win.search:SetText(""); win.search:ClearFocus() end
    onlyBag = nil
    -- new items stop being new once you've seen them
    if win.anyNew then
      win.anyNew = false
      pcall(function() if C_NewItems and C_NewItems.ClearAll then C_NewItems.ClearAll() end end)
    end
    if PlaySound and SOUNDKIT and SOUNDKIT.IG_BACKPACK_CLOSE then PlaySound(SOUNDKIT.IG_BACKPACK_CLOSE) end
  end)
  -- new-item glow pulse, and catch-up refreshes
  local acc, t = 0, 0
  win:HookScript("OnUpdate", function(_, el)
    t = t + el
    if win.anyNew then
      local a = 0.35 + 0.3 * math.sin(t * 4)
      for _, b in pairs(btns) do if b.bibGlow:IsShown() then b.bibGlow:SetAlpha(a) end end
    end
    acc = acc + el
    if acc > 0.1 then
      acc = 0
      if layoutDirty then S:RefreshBiB(false) elseif paintDirty then paintDirty = false; if not repaint() then layout() end end
    end
  end)
end
S.BiBBuild = function() if not win then build() end return win end

local function askOn(after)
  UI:Confirm("BiB (Built-in Bag) puts all your bags in one window - sorted, grouped and styled your way.\n\nTurn it on? It takes over the game's bag windows (you can turn it off again in Settings).", function()
    S:SetBiBOn(true); if after then after() end
  end, "Turn it on")
end

function S:ShowBiB()
  if not S.db then return end
  if not S:BiBIsOn() then askOn(function() S:ShowBiB() end) return end
  if not win then build() end
  if win:IsShown() then return end
  if type(cfg().at) == "table" then win.ccOwnSpot = true; win.__fromDock = nil end   -- placed once: always opens there
  if not win.__fromDock then restorePos() end
  win:Show(); win:Raise()
  if PlaySound and SOUNDKIT and SOUNDKIT.IG_BACKPACK_OPEN then PlaySound(SOUNDKIT.IG_BACKPACK_OPEN) end
end
function S:HideBiB() if win and win:IsShown() then win:Hide() end end
function S:ToggleBiB() if win and win:IsShown() then S:HideBiB() else S:ShowBiB() end end

---------------------------------------------------------------------------
-- Taking over the game's bags
---------------------------------------------------------------------------
local function blizzFrames()
  local out = {}
  for i = 1, (tonumber(NUM_CONTAINER_FRAMES) or 13) do local f = _G["ContainerFrame" .. i]; if f then out[#out + 1] = f end end
  if _G.ContainerFrameCombinedBags then out[#out + 1] = _G.ContainerFrameCombinedBags end
  return out
end
local function hideBlizz()
  for _, f in ipairs(blizzFrames()) do if f:IsShown() then pcall(f.Hide, f) end end
end

local intent, resolving
local lastEvt                      -- { key, at }: the vendor / mail / bank... that just opened
local PRI = { open = 1, close = 2, toggle = 3 }
local function want(kind)
  if not S:BiBIsOn() then return end
  if not intent or PRI[kind] > PRI[intent] then intent = kind end
  if resolving then return end
  resolving = true
  C_Timer.After(0, function()
    resolving = false
    local k = intent; intent = nil
    hideBlizz()
    if k == "open" and lastEvt and GetTime() - lastEvt.at < 0.5 and not cfg()[lastEvt.key] then return end
    if k == "toggle" then S:ToggleBiB() elseif k == "open" then S:ShowBiB() else S:HideBiB() end
  end)
end
S.BiBWant = want

local hooked = false
local function hookBlizz()
  if hooked then return end
  hooked = true
  for _, fn in ipairs({ "ToggleAllBags", "ToggleBackpack", "ToggleBag" }) do
    if type(_G[fn]) == "function" then hooksecurefunc(fn, function() want("toggle") end) end
  end
  for _, fn in ipairs({ "OpenAllBags", "OpenBackpack", "OpenBag" }) do
    if type(_G[fn]) == "function" then hooksecurefunc(fn, function() want("open") end) end
  end
  for _, fn in ipairs({ "CloseAllBags", "CloseBackpack", "CloseBag" }) do
    if type(_G[fn]) == "function" then hooksecurefunc(fn, function() want("close") end) end
  end
  for _, f in ipairs(blizzFrames()) do
    f:HookScript("OnShow", function(self) if S:BiBIsOn() then self:Hide() end end)
  end
end

function S:SetBiBOn(on)
  local c = cfg()
  c.on = on and true or false
  if c.on then
    hookBlizz(); hideBlizz()
    S:Print("BiB on - your bags open in BiB now (B, Shift-B, the bag buttons, vendors...).")
  else
    S:HideBiB()
    S:Print("BiB off - the game's own bags are back.")
  end
  if S.RefreshCurrent then pcall(S.RefreshCurrent, S) end
  if S.QuickBarLayout then pcall(S.QuickBarLayout, S) end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local function dirty(full) if full then layoutDirty = true else paintDirty = true end end
S:On("BAG_UPDATE_DELAYED", function() dirty(true) end)
S:On("BAG_UPDATE", function() dirty(true) end)
S:On("BAG_CONTAINER_UPDATE", function() dirty(true) end)       -- a bag was equipped / taken off
S:On("PLAYER_EQUIPMENT_CHANGED", function() dirty(true) end)
S:On("ITEM_LOCK_CHANGED", function() dirty(false) end)
S:On("BAG_UPDATE_COOLDOWN", function() dirty(false) end)
S:On("BAG_NEW_ITEMS_UPDATED", function() dirty(true) end)
S:On("QUEST_ACCEPTED", function() dirty(false) end)
-- item info arriving comes in bursts: rebuild at most twice a second for it
local infoAt = 0
S:On("GET_ITEM_INFO_RECEIVED", function()
  if not missing then return end
  if not (win and win:IsShown()) then layoutDirty = true return end
  local now = GetTime()
  if now - infoAt < 0.5 then
    if not win.infoQueued then
      win.infoQueued = true
      C_Timer.After(0.5 - (now - infoAt), function() win.infoQueued = false; infoAt = GetTime(); dirty(true) end)
    end
    return
  end
  infoAt = now
  dirty(true)
end)
S:On("PLAYER_MONEY", function() if win and win:IsShown() then win.gold:SetText(cfg().gold and moneyText() or "") end end)
S:On("PLAYER_REGEN_ENABLED", function() if win and win:IsShown() then S:RefreshBiB(true) end end)

local autoOpened = false
local function openFor(key)
  lastEvt = { key = key, at = GetTime() }
  if not S:BiBIsOn() or not cfg()[key] then return end
  if not (win and win:IsShown()) then autoOpened = true end
  S:ShowBiB()
end
local function closeFor()
  if autoOpened then autoOpened = false; S:HideBiB() end
end
S:On("MERCHANT_SHOW", function()
  atVendor = true
  if win then win.junkBtn:SetShown(true) end
  openFor("openVendor")
  if S:BiBIsOn() and cfg().autoJunk then C_Timer.After(0.3, function() S:BiBSellJunk(true) end) end
end)
S:On("MERCHANT_CLOSED", function() atVendor = false; if win then win.junkBtn:Hide() end; closeFor() end)
S:On("MAIL_SHOW", function() openFor("openMail") end)
S:On("MAIL_CLOSED", closeFor)
S:On("BANKFRAME_OPENED", function() openFor("openBank") end)
S:On("BANKFRAME_CLOSED", closeFor)
S:On("AUCTION_HOUSE_SHOW", function() openFor("openAH") end)
S:On("AUCTION_HOUSE_CLOSED", closeFor)
S:On("TRADE_SHOW", function() openFor("openTrade") end)
S:On("TRADE_CLOSED", closeFor)

S:Listen("LOGIN", function() if S:BiBIsOn() then hookBlizz() end end)

---------------------------------------------------------------------------
-- Options window
---------------------------------------------------------------------------
local function swatch(parent, label, col, onChange)
  local f = CreateFrame("Button", nil, parent)
  f:SetSize(200, 20)
  f.box = f:CreateTexture(nil, "ARTWORK"); f.box:SetSize(28, 16); f.box:SetPoint("LEFT")
  f.edge = f:CreateTexture(nil, "BACKGROUND"); f.edge:SetPoint("TOPLEFT", f.box, -1, 1); f.edge:SetPoint("BOTTOMRIGHT", f.box, 1, -1); f.edge:SetColorTexture(0, 0, 0, 1)
  f.label = UI:Text(f, label, "small"); f.label:SetPoint("LEFT", f.box, "RIGHT", 8, 0)
  local function show() local c = col(); f.box:SetColorTexture(c[1], c[2], c[3], 1) end
  f:SetScript("OnClick", function() if UI.PickColor then UI.PickColor(col(), function() show(); onChange() end) end end)
  f.Refresh = show
  show()
  return f
end

local OPT_W, OPT_H = 470, 610
function S:ShowBiBOptions(tab)
  if opts then opts:Show(); opts:Raise(); if opts.refresh then opts.refresh() end; if tab and opts.tabs then opts.tabs:Select(tab) end return end
  opts = UI:Window("CC_BiBOptions", "BiB options", OPT_W, OPT_H)
  opts:SetFrameStrata("HIGH")
  local pages, ctl = {}, {}
  local function re(full) S:RefreshBiB(full ~= false) end
  local function page(i)
    local p = CreateFrame("Frame", nil, opts)
    p:SetPoint("TOPLEFT", 18, -76); p:SetPoint("BOTTOMRIGHT", -18, 46)
    pages[i] = p
    return p
  end
  local tabs = UI:SubTabs(opts, { "Look", "Sorting", "Sections", "Show", "Behaviour" }, function(i)
    for j, p in ipairs(pages) do p:SetShown(i == j) end
  end)
  tabs:SetPoint("TOPLEFT", 16, -40); tabs:SetPoint("RIGHT", -16, 0)

  -- Look --------------------------------------------------------------
  local p, y = page(1), 0
  local function slider(pg, key, label, lo, hi, step, fmt)
    local s = UI:Slider(pg, OPT_W - 40, label, lo, hi, step, cfg()[key], function(v) cfg()[key] = v; re() end, fmt)
    s:SetPoint("TOPLEFT", 0, y); y = y - 28
    ctl[#ctl + 1] = function() s:SetValue(cfg()[key]) end
    return s
  end
  slider(p, "cols", "Slots per row", 4, 30, 1)
  slider(p, "size", "Slot size", 24, 60, 1)
  slider(p, "spacing", "Space between slots", 0, 12, 1)
  slider(p, "gap", "Space between sections", 0, 30, 1)
  slider(p, "pad", "Edge padding", 4, 24, 1)
  slider(p, "scale", "Window scale", 0.6, 1.6, 0.05, function(v) return string.format("%d%%", v * 100 + 0.5) end)
  y = y - 6
  local function label(pg, text) local t = UI:Text(pg, text, "small"); t:SetPoint("TOPLEFT", 0, y - 4); return t end
  label(p, "Background")
  local bgDrop = UI:Dropdown(p, 200, {
    { value = "theme", text = "Command Center theme" }, { value = "solid", text = "Solid colour" },
    { value = "dark", text = "Dark dialog" }, { value = "dialog", text = "Dialog" }, { value = "tooltip", text = "Tooltip" },
    { value = "marble", text = "Marble" }, { value = "rock", text = "Rock" },
  }, cfg().bg, function(v) cfg().bg = v; re() end)
  bgDrop:SetPoint("TOPLEFT", 136, y); y = y - 30
  ctl[#ctl + 1] = function() bgDrop:SetValue(cfg().bg) end
  local sw1 = swatch(p, "Background colour (tints textures)", function() return cfg().bgColor end, function() re() end)
  sw1:SetPoint("TOPLEFT", 136, y); y = y - 24
  slider(p, "bgAlpha", "Background opacity", 0, 1, 0.05, function(v) return string.format("%d%%", v * 100 + 0.5) end)
  local eTheme = UI:Check(p, "Border in the theme colour", cfg().edgeTheme, function(v) cfg().edgeTheme = v; re() end)
  eTheme:SetPoint("TOPLEFT", 0, y); y = y - 24
  local sw2 = swatch(p, "Border colour", function() return cfg().edgeColor end, function() cfg().edgeTheme = false; eTheme:SetChecked(false); re() end)
  sw2:SetPoint("TOPLEFT", 136, y); y = y - 28
  label(p, "Slots")
  local slotDrop = UI:Dropdown(p, 200, {
    { value = "theme", text = "Command Center theme" }, { value = "custom", text = "Custom colour" },
    { value = "blizzard", text = "Game style" }, { value = "none", text = "No background" },
  }, cfg().slot, function(v) cfg().slot = v; re() end)
  slotDrop:SetPoint("TOPLEFT", 136, y); y = y - 30
  ctl[#ctl + 1] = function() slotDrop:SetValue(cfg().slot) end
  local sw3 = swatch(p, "Slot colour", function() return cfg().slotColor end, function() cfg().slot = "custom"; slotDrop:SetValue("custom"); re() end)
  sw3:SetPoint("TOPLEFT", 136, y); y = y - 24
  slider(p, "slotAlpha", "Slot opacity", 0, 1, 0.05, function(v) return string.format("%d%%", v * 100 + 0.5) end)
  local RN = { [0] = "Square", "Slight", "Soft", "Round", "Rounder", "Circle" }
  slider(p, "round", "Slot roundness", 0, 5, 1, function(v) return RN[math.floor(v + 0.5)] or "" end)
  ctl[#ctl + 1] = function() sw1.Refresh(); sw2.Refresh(); sw3.Refresh(); eTheme:SetChecked(cfg().edgeTheme) end

  -- Sorting -----------------------------------------------------------
  p, y = page(2), 0
  label(p, "Sort by")
  local typeBtn
  local sortDrop = UI:Dropdown(p, 200, SORTS, cfg().sort, function(v) cfg().sort = v; re(); typeBtn:SetText(v == "type" and "Type order..." or "Keep at bottom...") end)
  sortDrop:SetPoint("TOPLEFT", 136, y); y = y - 30
  typeBtn = UI:Button(p, "Type order...", 130, 22, function() S:ShowBiBTypeOrder() end,
    "Drag the kinds of items into your own order (when sorting by Type), and pick kinds to keep at the bottom of the bag.")
  typeBtn:SetPoint("TOPLEFT", 136, y); y = y - 30
  ctl[#ctl + 1] = function() sortDrop:SetValue(cfg().sort); typeBtn:SetText(cfg().sort == "type" and "Type order..." or "Keep at bottom...") end
  local function check(pg, key, text, tip, after)
    local cb = UI:Check(pg, text, cfg()[key], function(v) cfg()[key] = v; if after then after(v); opts.refresh() end; re() end, tip)
    cb:SetPoint("TOPLEFT", 0, y); y = y - 24
    ctl[#ctl + 1] = function() cb:SetChecked(cfg()[key]) end
    return cb
  end
  check(p, "desc", "Reverse the order")
  check(p, "group", "Group into sections", "Equipment, consumables, trade goods, junk... each in its own section.", function(v) if v then cfg().split = false end end)
  check(p, "split", "One section per bag instead", nil, function(v) if v then cfg().group = false end end)
  check(p, "flow", "Small sections side by side", "Packs little sections next to each other instead of one per row.")
  check(p, "headers", "Section titles")
  check(p, "newFirst", "New items in their own section, first")
  check(p, "junkLast", "Junk always last")
  label(p, "Free slots")
  local emptyDrop = UI:Dropdown(p, 200, {
    { value = "one", text = "One slot with a count" }, { value = "all", text = "Show every free slot" }, { value = "none", text = "Hide them" },
  }, cfg().empty, function(v) cfg().empty = v; re() end)
  emptyDrop:SetPoint("TOPLEFT", 136, y); y = y - 32
  ctl[#ctl + 1] = function() emptyDrop:SetValue(cfg().empty) end
  check(p, "reagentSplit", "Reagent bag in its own box with a border", "Keeps the reagent bag's slots apart from your other bags, inside a coloured border.")
  local sw4 = swatch(p, "Reagent box colour", function() return cfg().reagentColor end, function() re() end)
  sw4:SetPoint("TOPLEFT", 26, y); y = y - 24
  ctl[#ctl + 1] = function() sw4.Refresh() end
  -- Sections ----------------------------------------------------------
  p, y = page(3), 0
  label(p, "Sections used")
  y = y - 20
  local x0 = 0
  for i, cat in ipairs(CATS) do
    if cat.id ~= "misc" then
      local cb = UI:Check(p, cat.name, cfg().cats[cat.id] ~= false, function(v) if v then cfg().cats[cat.id] = nil else cfg().cats[cat.id] = false end; re() end,
        (cat.tip or cat.name) .. " Untick to put these under Everything else.")
      cb:SetPoint("TOPLEFT", x0, y)
      ctl[#ctl + 1] = function() cb:SetChecked(cfg().cats[cat.id] ~= false) end
      if x0 == 0 then x0 = 215 else x0 = 0; y = y - 22 end
    end
  end
  if x0 ~= 0 then y = y - 22 end
  y = y - 8
  y = y - 4
  label(p, "Section order"); y = y - 20
  local secNote = UI:Text(p, "|cff888888Top to bottom - the arrows move a section, Top / Bottom send it straight there.|r", "small")
  secNote:SetPoint("TOPLEFT", 0, y); y = y - 18
  local secRows = {}
  local rowY = y
  local function drawOrder()
    local ord = S.BiBOrder()
    for i, id in ipairs(ord) do
      local row = secRows[i]
      if not row then
        row = CreateFrame("Frame", nil, p); row:SetSize(OPT_W - 40, 20)
        row:SetPoint("TOPLEFT", 0, rowY - (i - 1) * 21)
        row.n = UI:Text(row, "", "small"); row.n:SetPoint("LEFT", 4, 0); row.n:SetWidth(170)
        local function mk(txt, x, fn, tip) local b = UI:Button(row, txt, txt:len() > 2 and 56 or 26, 18, fn, tip); b:SetPoint("LEFT", x, 0); return b end
        row.up = mk("^", 180, function() S.BiBMoveSection(row.id, -1); drawOrder() end, "Move up")
        row.down = mk("v", 210, function() S.BiBMoveSection(row.id, 1); drawOrder() end, "Move down")
        row.top = mk("Top", 244, function() S.BiBMoveSection(row.id, "top"); drawOrder() end, "First in the window")
        row.bot = mk("Bottom", 304, function() S.BiBMoveSection(row.id, "bottom"); drawOrder() end, "Last in the window")
        secRows[i] = row
      end
      row.id = id
      row.n:SetText(i .. ".  " .. (CAT_NAME[id] or id))
      row.up:SetEnabled(i > 1); row.down:SetEnabled(i < #ord)
      row:Show()
    end
  end
  drawOrder()
  ctl[#ctl + 1] = drawOrder
  y = rowY - #CATS * 21 - 6
  local resetOrd = UI:Button(p, "Default order", 110, 20, function() cfg().order = nil; drawOrder(); re() end)
  resetOrd:SetPoint("TOPLEFT", 0, y); y = y - 26

  -- Show --------------------------------------------------------------
  p, y = page(4), 0
  check(p, "search", "Search box")
  check(p, "bagBar", "Your bags along the top", "Hover a bag to light up its slots, click it to see only that bag.")
  check(p, "quality", "Quality colour around items")
  check(p, "ilvl", "Item level on gear")
  check(p, "junk", "Coin on junk")
  check(p, "newGlow", "Glow on new items")
  check(p, "questMark", "Mark quest items (! = starts a quest)")
  check(p, "cool", "Cooldowns on items")
  check(p, "free", "Free slots count")
  check(p, "gold", "Your gold")

  -- Behaviour ---------------------------------------------------------
  p, y = page(5), 0
  ctl.on = UI:Check(p, "Use BiB for my bags", cfg().on, function(v) S:SetBiBOn(v) end,
    "BiB opens instead of the game's bags - B, Shift-B, the bag buttons, vendors, mail, the bank.")
  ctl.on:SetPoint("TOPLEFT", 0, y); y = y - 30
  ctl[#ctl + 1] = function() ctl.on:SetChecked(cfg().on) end
  label(p, "Open BiB by itself at"); y = y - 22
  check(p, "openVendor", "  Vendors")
  check(p, "openMail", "  The mailbox")
  check(p, "openBank", "  The bank")
  check(p, "openAH", "  The auction house")
  check(p, "openTrade", "  Trading with a player")
  y = y - 6
  check(p, "autoJunk", "Sell junk by itself at vendors")
  check(p, "hold", "Don't reshuffle while BiB is open", "Items keep their spot until you close and open BiB again - nothing jumps around under your mouse.")
  check(p, "lock", "Lock the window in place")
  y = y - 8
  local reset = UI:Button(p, "Reset look and sorting", 170, 22, function()
    UI:Confirm("Put every BiB look and sorting option back to how it started?", function()
      local c = cfg()
      for k, v in pairs(DEF) do if k ~= "on" and not k:find("^open") then c[k] = copy(v) end end
      opts.refresh(); re()
    end, "Reset")
  end)
  reset:SetPoint("TOPLEFT", 0, y)

  opts.refresh = function() for _, f in ipairs(ctl) do pcall(f) end end
  local foot = UI:Text(opts, "|cff888888Changes show straight away. /ccenter bib opens your bags.|r", "small")
  foot:SetPoint("BOTTOMLEFT", 18, 16)
  local openB = UI:Button(opts, "Open BiB", 90, 22, function() S:ShowBiB() end)
  openB:SetPoint("BOTTOMRIGHT", -16, 12)
  opts:HookScript("OnShow", function() opts.refresh() end)
  opts.tabs = tabs
  tabs:Select(tab or 1)
  opts:Show(); opts:Raise()
end

S:AddCommand("bib", "", "BiB: all your bags in one window", function() S:ToggleBiB() end)

---------------------------------------------------------------------------
-- Type order window: drag the types (or use the arrows), tick "Bottom" to keep
-- a type at the bottom of the bag
---------------------------------------------------------------------------
local twin
local ROWH = 24
local function drawTypes()
  if not twin then return end
  local ord = S.BiBTypeOrder()
  local bot = type(cfg().typeBottom) == "table" and cfg().typeBottom or {}
  for i, id in ipairs(ord) do
    local row = twin.rows[i]
    row.id = id
    row.n:SetText("|cff888888" .. i .. ".|r  " .. (TYPE_NAME[id] or id))
    row.up:SetEnabled(i > 1); row.down:SetEnabled(i < #ord)
    row.bot:SetChecked(bot[id] and true or false)
    row.n:SetAlpha(bot[id] and 0.6 or 1)
  end
  twin.note:SetText(cfg().sort == "type" and "|cff888888Sorting by type now.|r"
    or "|cffffd100The order only applies when BiB sorts by Type.|r  |cff888888\"Bottom\" always applies.|r")
end
function S:ShowBiBTypeOrder()
  if not twin then
    local n = #TYPES
    twin = UI:Window("CC_BiBTypes", "Type order", 380, n * ROWH + 150)
    twin.note = UI:Text(twin, "", "small"); twin.note:SetPoint("TOPLEFT", 18, -40); twin.note:SetWidth(344)
    local hint = UI:Text(twin, "|cff888888Drag a row to move it.  Bottom = keep at the bottom of the bag, after the free slots.|r", "small")
    hint:SetPoint("TOPLEFT", 18, -56); hint:SetWidth(344)
    twin.list = CreateFrame("Frame", nil, twin); twin.list:SetPoint("TOPLEFT", 14, -86); twin.list:SetSize(352, n * ROWH)
    twin.mark = twin.list:CreateTexture(nil, "OVERLAY"); twin.mark:SetHeight(2); twin.mark:SetColorTexture(1, 0.82, 0, 1); twin.mark:Hide()
    twin.rows = {}
    local function slotAtCursor()
      local _, cy = GetCursorPosition()
      cy = cy / (twin.list:GetEffectiveScale() or 1)
      local top = twin.list:GetTop() or 0
      return math.max(1, math.min(n + 1, math.floor((top - cy) / ROWH + 0.5) + 1))
    end
    for i = 1, n do
      local row = CreateFrame("Button", nil, twin.list)
      row:SetSize(352, ROWH - 2); row:SetPoint("TOPLEFT", 0, -(i - 1) * ROWH)
      local bg = row:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.04 or 0.07)
      row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
      row.grip = UI:Text(row, "|cff777777::|r", "normal"); row.grip:SetPoint("LEFT", 6, 0)
      row.n = UI:Text(row, "", "normal"); row.n:SetPoint("LEFT", 22, 0); row.n:SetWidth(150)
      row.up = UI:Button(row, "^", 24, 18, function() S.BiBMoveType(row.id, -1); drawTypes() end, "Move up"); row.up:SetPoint("LEFT", 178, 0)
      row.down = UI:Button(row, "v", 24, 18, function() S.BiBMoveType(row.id, 1); drawTypes() end, "Move down"); row.down:SetPoint("LEFT", row.up, "RIGHT", 2, 0)
      row.bot = UI:Check(row, "Bottom", false, function(v) S.BiBSetTypeBottom(row.id, v); drawTypes() end,
        "Keep these at the bottom of the bag - everything else fills from the top.")
      row.bot:SetPoint("LEFT", row.down, "RIGHT", 10, 0)
      row:RegisterForDrag("LeftButton")
      row:SetScript("OnDragStart", function(self)
        twin.dragging = self; self:SetAlpha(0.5)
        twin.list:SetScript("OnUpdate", function()
          local at = slotAtCursor()
          twin.mark:ClearAllPoints(); twin.mark:SetPoint("TOPLEFT", 0, -(at - 1) * ROWH + 1); twin.mark:SetPoint("TOPRIGHT", 0, -(at - 1) * ROWH + 1); twin.mark:Show()
        end)
      end)
      row:SetScript("OnDragStop", function(self)
        self:SetAlpha(1); twin.list:SetScript("OnUpdate", nil); twin.mark:Hide()
        if twin.dragging ~= self then return end
        twin.dragging = nil
        local at = slotAtCursor()
        local from = i
        if at > from then at = at - 1 end
        if at ~= from then S.BiBMoveType(self.id, { at }) end
        drawTypes()
      end)
      twin.rows[i] = row
    end
    local byType = UI:Button(twin, "Sort by type", 100, 22, function() cfg().sort = "type"; S:RefreshBiB(true); drawTypes() end, "Switch BiB to sorting by type.")
    byType:SetPoint("BOTTOMLEFT", 16, 16)
    local reset = UI:Button(twin, "Default order", 106, 22, function() cfg().typeOrder = nil; cfg().typeBottom = nil; rebuildTypeRank(); S:RefreshBiB(true); drawTypes() end,
      "Back to the normal order, nothing kept at the bottom.")
    reset:SetPoint("LEFT", byType, "RIGHT", 6, 0)
    local done = UI:Button(twin, "Done", 60, 22, function() twin:Hide() end); done:SetPoint("BOTTOMRIGHT", -16, 16)
    twin:HookScript("OnShow", drawTypes)
  end
  twin:Show(); twin:Raise(); drawTypes()
end
