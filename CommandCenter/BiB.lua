-- BiB (Built-in Bag): optional. All your bags in one window - sorted, grouped into
-- sections, searchable and styled the way you like. When it's on it takes over the
-- game's bag windows (B / Shift-B, the bag buttons, vendors, mail, the bank...).
--
-- Item slots use the game's own bag-slot template, so clicking, right-click to use,
-- drag and drop, tooltips and selling all behave exactly like the game's bags - and
-- work in combat. Sorting only changes how the window shows them - nothing in your
-- real bags is moved.
local _, S = ...
if S.ModuleRev then S:ModuleRev("BiB", 25) end
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
  bankMemory = true,                 -- remember the bank so it can be seen from anywhere
  bankWindow = true,                 -- at the banker: BiB's bank window instead of the game's
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

local function makeButton(bag, slot, parent)
  nextBtn = nextBtn + 1
  local name = "CC_BiBItem" .. nextBtn
  parent = parent or holder(bag)
  local ok, b = pcall(CreateFrame, "ItemButton", name, parent, "ContainerFrameItemButtonTemplate")
  if not ok or not b then ok, b = pcall(CreateFrame, "Button", name, parent, "ContainerFrameItemButtonTemplate") end
  if not ok or not b then
    -- no bag-slot template: a plain button that picks up / uses the item
    -- (using an item is protected, so right-click goes through the game's secure
    -- "use item" action for this bag slot instead of Command Center calling it)
    b = CreateFrame("Button", name, parent, "SecureActionButtonTemplate")
    b.plain = true
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetAttribute("type2", "item")
    b:SetAttribute("item2", bag .. " " .. slot)
    b:HookScript("PreClick", function(self, btn)
      if btn ~= "RightButton" then pickup(self.bag, self.slot) end
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

-- money as gold / silver / copper in their own colours ("79g 50s 55c")
function S.BiBMoney(m)
  m = math.floor(tonumber(m) or 0)
  local neg = m < 0
  if neg then m = -m end
  local g, sv, c = math.floor(m / 10000), math.floor(m / 100) % 100, m % 100
  local out = {}
  local function n(v) return BreakUpLargeNumbers and BreakUpLargeNumbers(v) or tostring(v) end
  if g > 0 then out[#out + 1] = "|cffffd100" .. n(g) .. "g|r" end
  if sv > 0 or (g > 0 and c > 0) then out[#out + 1] = "|cffc7c7cf" .. sv .. "s|r" end
  if c > 0 or #out == 0 then out[#out + 1] = "|cffeda55f" .. c .. "c|r" end
  return (neg and "-" or "") .. table.concat(out, " ")
end
local function moneyText()
  return S.BiBMoney(GetMoney and GetMoney() or 0)
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
  -- a window you sized yourself (corner grip) keeps its size: the columns follow its width
  local sz = c.bagSize
  local sizing = win.sizing
  local W = sizing and win:GetWidth() or (type(sz) == "table" and tonumber(sz[1])) or nil
  local H = sizing and win:GetHeight() or (type(sz) == "table" and tonumber(sz[2])) or nil
  local cols = math.max(4, math.min(40, c.cols))
  if W then cols = math.max(4, math.min(40, math.floor((W - c.pad * 2 + sp) / cell))) end
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
  win.content:SetSize(fullW, math.max(1, y))
  win.inner:SetSize(fullW + 12, math.max(1, y) + 12)
  win.scroll:ClearAllPoints()
  win.scroll:SetPoint("TOPLEFT", c.pad - 6, -(top - 6)); win.scroll:SetPoint("BOTTOMRIGHT", -(c.pad - 6), c.pad + FOOT - 6)
  local bodyH = y
  if W then
    if not sizing then win:SetSize(W, H) end
    bodyH = math.max(20, H - (top + c.pad + FOOT))
  else
    win:SetSize(fullW + c.pad * 2, top + y + c.pad + FOOT)
  end
  win.scrollMax = math.max(0, y - bodyH)
  win.scroll:SetVerticalScroll(math.min(win.scroll:GetVerticalScroll() or 0, win.scrollMax))
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
  -- selling by using each item (UseContainerItem) is protected now and gets "blocked";
  -- the game's own "sell all junk" call is allowed
  local sell = C_MerchantFrame and C_MerchantFrame.SellAllJunkItems
  if not sell then
    if not quiet then S:Print("Use the vendor's own \"Sell junk\" button - the game doesn't let addons sell items one by one.") end
    return
  end
  local ok = pcall(sell)
  if not ok then if not quiet then S:Print("The game didn't let Command Center sell the junk - use the vendor's \"Sell junk\" button.") end return end
  local m = value
  S:Print(string.format("Selling %d junk item%s for %s.", #queue, #queue == 1 and "" or "s",
    S.BiBMoney(m)))
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
  items[#items + 1] = { text = "Currencies to show...", tip = "Pick currencies to show along the bottom, next to your gold.",
    func = function() if S.BiBCurrencyMenu then C_Timer.After(0, function() S.BiBCurrencyMenu(win and win.currBtn or self) end) end end }
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
  win:HeaderButton("chest", "Your bank", "See your bank from anywhere - BiB remembers it every time you visit a banker. Your other characters' banks too.", function()
    S:ToggleBiBBank()
  end)
  win.search = UI:Edit(win, 200, 20, "Search  (name, type, epic, boe, ilvl>100...)")
  win.search:SetPoint("TOPLEFT", 10, -(HEAD + 6)); win.search:SetPoint("RIGHT", -10, 0)
  win.search:HookScript("OnTextChanged", function() dimAll() end)
  win.bagBar = CreateFrame("Frame", nil, win); win.bagBar:SetSize(200, 22)
  -- the slots sit in a scroll frame, so a window you sized yourself can be smaller than the bags
  win.scroll = CreateFrame("ScrollFrame", nil, win)
  win.inner = CreateFrame("Frame", nil, win.scroll); win.inner:SetSize(1, 1)
  win.scroll:SetScrollChild(win.inner)
  win.scroll:EnableMouseWheel(true)
  win.scroll:SetScript("OnMouseWheel", function(self, d)
    self:SetVerticalScroll(math.max(0, math.min(win.scrollMax or 0, self:GetVerticalScroll() - d * (cfg().size + cfg().spacing) * 2)))
  end)
  win.content = CreateFrame("Frame", nil, win.inner)
  win.content:SetPoint("TOPLEFT", win.inner, "TOPLEFT", 6, -6)
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
  if S.BiBOnBuild then pcall(S.BiBOnBuild, win) end
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
  if S.BiBApplyBankTakeover then S.BiBApplyBankTakeover() end
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
  check(p, "bankWindow", "Use BiB's bank window at the banker", "The banker opens BiB's bank window (with your boxes, tabs and sorting) instead of the game's bank. Its \"Game's bank\" button brings the game's window back for one visit (to buy bag slots, say).", function() if S.BiBApplyBankTakeover then S.BiBApplyBankTakeover() end end)
  check(p, "bankMemory", "Remember my bank (see it from anywhere)", "Each time you open the bank BiB keeps a copy, so the bank button / /ccenter bank shows it wherever you are - your other characters' banks too.")
  y = y - 8
  local reset = UI:Button(p, "Reset look and sorting", 170, 22, function()
    UI:Confirm("Put every BiB look and sorting option back to how it started?", function()
      local c = cfg()
      for k, v in pairs(DEF) do if k ~= "on" and k ~= "bankMemory" and k ~= "bankWindow" and not k:find("^open") then c[k] = copy(v) end end
      opts.refresh(); re()
    end, "Reset")
  end)
  reset:SetPoint("TOPLEFT", 0, y)

  opts.refresh = function() for _, f in ipairs(ctl) do pcall(f) end end
  local foot = UI:Text(opts, "|cff888888Changes show straight away. /ccenter bib opens your bags, /ccenter bank your bank.|r", "small")
  foot:SetPoint("BOTTOMLEFT", 18, 16)
  local openB = UI:Button(opts, "Open BiB", 90, 22, function() S:ShowBiB() end)
  openB:SetPoint("BOTTOMRIGHT", -16, 12)
  opts:HookScript("OnShow", function() opts.refresh() end)
  opts.tabs = tabs
  tabs:Select(tab or 1)
  opts:Show(); opts:Raise()
end

S:AddCommand("bib", "", "BiB: all your bags in one window", function() S:ToggleBiB() end)

-- (the bank part is one function of its own, so its locals stay under Lua's 200-per-function limit)
local function bankSection()
---------------------------------------------------------------------------
-- Bank from anywhere: every time you're at the bank BiB remembers what's in it
-- (each character on this account, plus the warband bank if the game has one),
-- and the Bank window shows it wherever you are - read-only, it's a copy.
---------------------------------------------------------------------------
local bankWin
-- the key ring is never part of the bank (it showed every key twice: key ring + "bank")
local KEYRING_ID = KEYRING_CONTAINER or (Enum and Enum.BagIndex and Enum.BagIndex.Keyring) or -2
local bankOpen = false
local bankView                       -- which character the Bank window shows (nil = you)
local BANK_COLS_MIN = 8

local function charKey()
  local n = clean(UnitName and UnitName("player"))
  if not n then return nil end
  local r = clean(GetRealmName and GetRealmName()) or "?"
  return n .. "-" .. r
end
local function bankStore()
  local g = G()
  g.bibBank = type(g.bibBank) == "table" and g.bibBank or {}
  local st = g.bibBank
  st.chars = type(st.chars) == "table" and st.chars or {}
  st.guilds = type(st.guilds) == "table" and st.guilds or {}
  return st
end
S.BiBBankStore = bankStore
S.BiBCharKey = charKey

-- every bag the bank can have, on old and new clients alike
local function bankBags()
  local out, seen = {}, {}
  local BI = Enum and Enum.BagIndex
  local function add(b, kind, name)
    if type(b) == "number" and b ~= KEYRING_ID and not seen[b] then seen[b] = true; out[#out + 1] = { bag = b, kind = kind, name = name } end
  end
  add(BANK_CONTAINER or (BI and BI.Bank) or -1, "char", BANK or "Bank")
  local first = (tonumber(NUM_BAG_SLOTS) or 4) + 1
  if BI and type(BI.ReagentBag) == "number" and BI.ReagentBag >= first then first = BI.ReagentBag + 1 end
  local nb = tonumber(NUM_BANKBAGSLOTS) or 7
  local rb = BI and BI.ReagentBag
  for b = (tonumber(NUM_BAG_SLOTS) or 4) + 1, first + nb - 1 do if b ~= rb then add(b, "char") end end
  add(REAGENTBANK_CONTAINER or (BI and BI.Reagentbank), "char", REAGENT_BANK or "Reagent bank")
  if BI then
    for i = 1, 8 do add(BI["CharacterBankTab_" .. i], "char", "Bank tab " .. i) end
    for i = 1, 8 do add(BI["AccountBankTab_" .. i], "account", "Warband tab " .. i) end
  end
  return out
end
S.BiBBankBags = bankBags

local function recordBank()
  if not bankOpen or not S.db or cfg().bankMemory == false then return end
  local key = charKey(); if not key then return end
  local st = bankStore()
  local mine, acct = { at = time(), bags = {} }, { at = time(), bags = {} }
  for _, e in ipairs(bankBags()) do
    local n = numSlots(e.bag)
    if n > 0 then
      local rec = { bag = e.bag, n = n, name = e.name or bagName(e.bag), items = {} }
      for slot = 1, n do
        local info = slotInfo(e.bag, slot)
        if info and (info.link or info.id or info.icon) then
          rec.items[slot] = { id = info.id, link = info.link, count = tonumber(info.count) or 1, icon = info.icon,
            q = info.quality, b = info.bound and true or nil }
        end
      end
      local into = e.kind == "account" and acct or mine
      into.bags[#into.bags + 1] = rec
    end
  end
  if #mine.bags > 0 then
    local _, cls = UnitClass("player")
    mine.class = clean(cls)
    local old = st.chars[key]
    if old then mine.inv, mine.money, mine.moneyAt, mine.rules = old.inv, old.money, old.moneyAt, old.rules end
    st.chars[key] = mine
  end
  if #acct.bags > 0 then st.account = acct end
  if bankWin and bankWin:IsShown() then S:RefreshBiBBank() end
end
S.BiBRecordBank = recordBank

local recPending = false
local function recordSoon(delay)
  if not bankOpen or recPending then return end
  recPending = true
  C_Timer.After(delay or 0.5, function() recPending = false; recordBank() end)
end
S:On("BANKFRAME_OPENED", function()
  bankOpen = true; recordSoon(0.4); C_Timer.After(2, recordBank)
  if S.BiBBankArrived then S.BiBBankArrived() end
end)
S:On("BANKFRAME_CLOSED", function()               -- nothing is recorded after this (the bank can't be read then)
  bankOpen = false
  if S.BiBBankLeft then S.BiBBankLeft() end
end)
S:On("PLAYERBANKSLOTS_CHANGED", function() recordSoon() end)
S:On("PLAYERREAGENTBANKSLOTS_CHANGED", function() recordSoon() end)
S:On("PLAYERBANKBAGSLOTS_CHANGED", function() recordSoon() end)
S:On("BAG_UPDATE_DELAYED", function() recordSoon() end)

-- Guild bank: remembered the same way each time you're at the guild vault (per guild).
-- Tabs load lazily, so every viewable tab is asked for when the vault opens and the
-- copy is only taken once they've had time to arrive.
local guildOpen, guildLoaded = false, false
local function guildName()
  if not (IsInGuild and IsInGuild()) then return nil end
  local n = clean(GetGuildInfo and GetGuildInfo("player"))
  return n
end
local function guildItemId(link)
  if not link then return nil end
  return tonumber(link:match("item:(%d+)"))
end
local function recordGuild()
  if not guildOpen or not guildLoaded or not S.db or cfg().bankMemory == false then return end
  local gname = guildName()
  if not gname or not GetNumGuildBankTabs then return end
  local okN, ntabs = pcall(GetNumGuildBankTabs)
  ntabs = okN and tonumber(clean(ntabs)) or 0
  local st = bankStore()
  local old = st.guilds[gname]
  local rec = { at = time(), bags = {} }
  -- no tabs (none bought / none you may see): keep what was seen before, but still take the gold
  if ntabs == 0 and old and old.bags then rec.bags = old.bags end
  local per = tonumber(MAX_GUILDBANK_SLOTS_PER_TAB) or 98
  for tab = 1, ntabs do
    local ok, name, _, viewable = pcall(GetGuildBankTabInfo, tab)
    name, viewable = ok and clean(name), ok and clean(viewable)
    local bagRec = { bag = tab, n = per, name = name or ("Tab " .. tab), items = {} }
    if viewable then
      for slot = 1, per do
        local ok2, tex, count, _, _, quality = pcall(GetGuildBankItemInfo, tab, slot)
        local okL, link = pcall(GetGuildBankItemLink, tab, slot)
        tex, link = ok2 and clean(tex), okL and clean(link)
        if tex or link then
          bagRec.items[slot] = { id = guildItemId(link), link = link, count = tonumber(ok2 and clean(count)) or 1, icon = tex, q = ok2 and clean(quality) or nil }
        end
      end
    elseif old and old.bags then
      -- a tab you can't see right now: keep what was seen before
      for _, ob in ipairs(old.bags) do if ob.bag == tab then bagRec = ob end end
    end
    rec.bags[#rec.bags + 1] = bagRec
  end
  if GetGuildBankMoney then local okm, m = pcall(GetGuildBankMoney); rec.money = okm and tonumber(clean(m)) or nil end
  if rec.money == nil and old then rec.money = old.money end
  rec.log = old and old.log
  st.guilds[gname] = rec
  if bankWin and bankWin:IsShown() then S:RefreshBiBBank() end
end
S.BiBRecordGuild = recordGuild
-- the guild bank log (item moves per tab + the gold log), when the game gives it
local MONEY_TAB = (tonumber(MAX_GUILDBANK_TABS) or 8) + 1
local function recordGuildLog()
  if not guildOpen or not S.db or cfg().bankMemory == false then return end
  local gname = guildName()
  if not gname then return end
  local st = bankStore()
  local g = st.guilds[gname]
  if not g then g = { at = time(), bags = {} }; st.guilds[gname] = g end
  if GetGuildBankMoney then local okm, m = pcall(GetGuildBankMoney); m = okm and tonumber(clean(m)); if m then g.money = m end end
  local now = time()
  local function when(y, mo, d, h)
    return now - ((((tonumber(y) or 0) * 12 + (tonumber(mo) or 0)) * 30 + (tonumber(d) or 0)) * 24 + (tonumber(h) or 0)) * 3600
  end
  local oldLog = g.log or {}
  local log = { at = now, tabs = {}, money = oldLog.money or {} }
  local okN, ntabs = pcall(GetNumGuildBankTabs)
  ntabs = okN and tonumber(clean(ntabs)) or 0
  for tab = 1, ntabs do
    local list = {}
    local okc, n = pcall(GetNumGuildBankTransactions, tab)
    n = okc and tonumber(clean(n)) or 0
    for i = 1, n do
      local ok, typ, who, link, count, t1, t2, y, mo, d, h = pcall(GetGuildBankTransaction, tab, i)
      if ok and typ then list[#list + 1] = { t = clean(typ), who = clean(who), link = clean(link), n = tonumber(clean(count)) or 1, from = clean(t1), to = clean(t2), at = when(y, mo, d, h), i = i } end
    end
    log.tabs[tab] = (#list > 0 or not (oldLog.tabs and oldLog.tabs[tab])) and list or oldLog.tabs[tab]
  end
  if GetNumGuildBankMoneyTransactions then
    local okc, n = pcall(GetNumGuildBankMoneyTransactions)
    n = okc and tonumber(clean(n)) or 0
    if n > 0 then
      local list = {}
      for i = 1, n do
        local ok, typ, who, amount, y, mo, d, h = pcall(GetGuildBankMoneyTransaction, i)
        if ok and typ then list[#list + 1] = { t = clean(typ), who = clean(who), money = tonumber(clean(amount)) or 0, at = when(y, mo, d, h), i = i } end
      end
      log.money = list
    end
  end
  g.log = log
  if S.BiBRefreshGuildLog then S.BiBRefreshGuildLog() end
end
local logPending = false
S:On("GUILDBANKLOG_UPDATE", function()
  if not guildOpen or logPending then return end
  logPending = true
  C_Timer.After(0.5, function() logPending = false; pcall(recordGuildLog) end)
end)

local guildPending = false
local function guildSoon()
  if not guildOpen or guildPending then return end
  guildPending = true
  C_Timer.After(0.6, function() guildPending = false; recordGuild() end)
end
local function guildOpened()
  guildOpen, guildLoaded = true, false
  pcall(function()
    local n = GetNumGuildBankTabs and GetNumGuildBankTabs() or 0
    for tab = 1, n do if QueryGuildBankTab then QueryGuildBankTab(tab) end end
  end)
  pcall(function()
    local n = GetNumGuildBankTabs and GetNumGuildBankTabs() or 0
    if QueryGuildBankLog then
      for tab = 1, n do QueryGuildBankLog(tab) end
      QueryGuildBankLog(MONEY_TAB)
    end
  end)
  C_Timer.After(1.5, function() if guildOpen then guildLoaded = true; recordGuild(); pcall(recordGuildLog) end end)
end
S:On("GUILDBANKFRAME_OPENED", guildOpened)
S:On("GUILDBANKFRAME_CLOSED", function() guildOpen = false end)
S:On("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(_, kind)   -- (handlers get the event name first)
  local gb = Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.GuildBanker
  if gb and kind == gb then guildOpened() end
end)
S:On("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(_, kind)
  local gb = Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.GuildBanker
  if gb and kind == gb then guildOpen = false end
end)
S:On("GUILDBANKBAGSLOTS_CHANGED", guildSoon)
S:On("GUILDBANK_UPDATE_MONEY", guildSoon)

-- the records the Bank window shows for one character (or "account")
local function bankRecords(who)
  local st = bankStore()
  local src
  if who == "account" then src = st.account
  elseif type(who) == "string" and who:find("^guild:") then src = st.guilds[who:sub(7)]
  elseif type(who) == "string" and who:find("^bags:") then src = st.chars[who:sub(6)]; src = src and src.inv
  else src = st.chars[who or charKey() or ""]; if src and not src.bags then src = nil end end
  local list, total, used, empties = {}, 0, 0, {}
  if not src then return list, 0, 0, nil, empties end
  for bi, bag in ipairs(src.bags or {}) do
   if bag.bag ~= KEYRING_ID or type(who) == "string" and who:find("^guild:") then
    total = total + (bag.n or 0)
    for slot = 1, bag.n or 0 do
      local it = bag.items and bag.items[slot]
      if not it then
        empties[#empties + 1] = { bag = bi, slot = slot, bagName = bag.name, empty = true, family = 0, kind = "saved" }
      else
        used = used + 1
        local r = { bag = bi, slot = slot, bagName = bag.name, id = it.id, link = it.link, count = it.count or 1, icon = it.icon,
          quality = it.q, bound = it.b }
        itemData(r)
        if not r.icon and r.id and GetItemIcon then local ok, t = pcall(GetItemIcon, r.id); if ok then r.icon = t end end
        r.quality = r.quality or 1
        r.quest = r.classID == 12
        r.cat = category(r, cfg(), true)
        list[#list + 1] = r
      end
    end
   end
  end
  return list, total, used, src, empties
end
S.BiBBankRecords = bankRecords

local function ago(t)
  if not t then return "never" end
  local d = time() - t
  if d < 90 then return "just now" end
  if d < 3600 then return math.floor(d / 60) .. " min ago" end
  if d < 86400 * 2 then return math.floor(d / 3600) .. " h ago" end
  return math.floor(d / 86400) .. " days ago"
end
S.BiBAgo = ago

local function whoLabel(who)
  if who == "account" then return "Warband bank" end
  if type(who) == "string" and who:find("^guild:") then return "|cff40ff40" .. who:sub(7) .. "|r guild bank" end
  if type(who) == "string" and who:find("^bags:") then who = who:sub(6) end
  local r = bankStore().chars[who]
  local hex = S.ClassHex and S.ClassHex(r and r.class) or "ffffff"
  return "|cff" .. hex .. (S.Short and S.Short(who) or who) .. "|r"
end

---------------------------------------------------------------------------
-- Bank view settings (its own sorting, separate from the bags) and boxes:
-- your own groups (sets, mats, collectables...) shown as a bordered box in the
-- bank or on a tab of their own, so they don't mingle with the rest.
---------------------------------------------------------------------------
local TAB_H = 24
local unpack = unpack or table.unpack
local BANK_DEF = { sort = "type", desc = false, group = "sections", tab = "main", free = "one" }
-- guild banks have their own sorting, boxes, tabs and tracked items (separate from yours)
local function isGuildView() return type(bankView) == "string" and bankView:find("^guild:") ~= nil end
S.BiBBankIsGuildView = isGuildView
-- Each character (and the warband bank) has its own boxes, tracked items and bank
-- sorting: cfg().charBank[key] = { view, boxes, track }. The boxes / tracked items made
-- before rev 20 (one set for everyone) went to the character you were playing then.
local function ownerKey()
  local who = bankView
  if who == nil then return charKey() or "?" end
  if who:find("^bags:") then return who:sub(6) end
  return who                                   -- another character's key, or "account"
end
S.BiBBankOwner = ownerKey
local function perChar(key)
  local c = cfg()
  c.charBank = type(c.charBank) == "table" and c.charBank or {}
  local me = charKey()
  if me and not c.charBankMoved then
    c.charBankMoved = true
    if not c.charBank[me] then c.charBank[me] = { view = c.bankView, boxes = c.bankBoxes, track = c.bankTrack } end
  end
  local r = c.charBank[key]
  if type(r) ~= "table" then r = {}; c.charBank[key] = r end
  if type(r.view) ~= "table" then
    -- a character seen for the first time starts with your sorting (not your boxes)
    r.view = {}
    local base = me and c.charBank[me] and c.charBank[me].view
    if type(base) == "table" and base ~= r.view then for k, v in pairs(base) do if k ~= "tabOrder" and k ~= "tab" then r.view[k] = v end end end
  end
  r.boxes = type(r.boxes) == "table" and r.boxes or {}
  r.track = type(r.track) == "table" and r.track or {}
  return r
end
S.BiBPerChar = perChar
local function bcfg()
  local c = cfg()
  local vk, bk = "view", "boxes"
  if isGuildView() then vk, bk = "gbankView", "gbankBoxes" else c = perChar(ownerKey()) end
  c[vk] = type(c[vk]) == "table" and c[vk] or {}
  for k, v in pairs(BANK_DEF) do if c[vk][k] == nil then c[vk][k] = v end end
  c[bk] = type(c[bk]) == "table" and c[bk] or {}
  for _, bx in ipairs(c[bk]) do
    bx.items = type(bx.items) == "table" and bx.items or {}
    bx.out = type(bx.out) == "table" and bx.out or {}
    bx.color = type(bx.color) == "table" and bx.color or { 0.9, 0.75, 0.3 }
    bx.mode = bx.mode == "tab" and "tab" or "box"
  end
  return c[vk], c[bk]
end
S.BiBBankView = bcfg

local BOX_COLORS = {
  { "Gold", { 0.9, 0.75, 0.3 } }, { "Green", { 0.3, 0.8, 0.4 } }, { "Blue", { 0.3, 0.6, 1 } }, { "Purple", { 0.7, 0.4, 1 } },
  { "Red", { 0.95, 0.35, 0.3 } }, { "Orange", { 1, 0.55, 0.15 } }, { "Teal", { 0.2, 0.8, 0.8 } }, { "Grey", { 0.6, 0.6, 0.6 } },
}
local GROUPS = {
  { value = "sections", text = "Sections (equipment, trade goods...)", tip = "The same sections as your bags." },
  { value = "bag", text = "One section per bank bag" },
  { value = "none", text = "No sections - one grid" },
}

-- items that are in one of your equipment sets
local setItems, setItemsAt = {}, 0
local function inSet(id)
  if not id then return false end
  if GetTime() - setItemsAt > 5 then
    setItemsAt = GetTime(); wipe(setItems)
    pcall(function()
      local ES = C_EquipmentSet
      if not (ES and ES.GetEquipmentSetIDs and ES.GetItemIDs) then return end
      for _, sid in ipairs(ES.GetEquipmentSetIDs() or {}) do
        for _, iid in pairs(ES.GetItemIDs(sid) or {}) do if type(iid) == "number" and iid > 0 then setItems[iid] = true end end
      end
    end)
  end
  return setItems[id] and true or false
end
local function isToy(id)
  if not (id and C_ToyBox and C_ToyBox.GetToyInfo) then return false end
  local ok, tid = pcall(C_ToyBox.GetToyInfo, id)
  return ok and tid ~= nil
end

local RULES = {
  { value = "", text = "Only the items I put in" },
  { value = "mats", text = "Crafting materials", tip = "Trade goods and reagents.", test = function(r) return r.classID == 7 or r.classID == 5 end },
  { value = "sets", text = "Gear from my equipment sets", tip = "Items saved in any of your equipment sets (character window).", test = function(r) return inSet(r.id) end },
  { value = "collect", text = "Collectables", tip = "Pets, mounts, toys and cosmetic items.",
    test = function(r) return r.classID == 17 or (r.classID == 15 and (r.subID == 2 or r.subID == 5)) or (r.classID == 4 and r.subID == 5) or isToy(r.id) end },
  { value = "gear", text = "All weapons and armour", test = function(r) return r.classID == 2 or r.classID == 4 end },
  { value = "cons", text = "Consumables", test = function(r) return r.classID == 0 end },
  { value = "quest", text = "Quest items", test = function(r) return r.classID == 12 or r.quest end },
  { value = "recipe", text = "Recipes", test = function(r) return r.classID == 9 end },
  { value = "name", text = "Name contains...", tip = "Every item whose name has the words you type.",
    test = function(r, bx) local t = (bx.text or ""):lower(); return t ~= "" and r.name and r.name:lower():find(t, 1, true) ~= nil end },
}
local RULE = {}
for _, x in ipairs(RULES) do RULE[x.value] = x end
S.BiBBankRules = RULES

local function boxOf(r, boxes)
  if not r.id then return nil end
  for _, bx in ipairs(boxes) do if bx.items[r.id] then return bx end end
  for _, bx in ipairs(boxes) do
    local rule = RULE[bx.rule or ""]
    if rule and rule.test and not bx.out[r.id] then
      local ok, hit = pcall(rule.test, r, bx)
      if ok and hit then return bx end
    end
  end
end
S.BiBBankBoxOf = function(r) local _, boxes = bcfg(); return boxOf(r, boxes) end

local function newBox(name, firstItem)
  local c = cfg(); local _, boxes = bcfg()
  c.bankBoxNext = (tonumber(c.bankBoxNext) or 0) + 1
  local bx = { id = c.bankBoxNext, name = name, color = { unpack(BOX_COLORS[((c.bankBoxNext - 1) % #BOX_COLORS) + 1][2]) }, mode = "box", rule = "", items = {}, out = {} }
  if firstItem then bx.items[firstItem] = true end
  boxes[#boxes + 1] = bx
  return bx
end
S.BiBBankNewBox = newBox
local function putIn(id, bx)
  local _, boxes = bcfg()
  for _, b in ipairs(boxes) do b.items[id] = nil end
  if bx then bx.items[id] = true; bx.out[id] = nil end
end
S.BiBBankPutIn = putIn
local function takeOut(id, bx)
  bx.items[id] = nil
  local rule = RULE[bx.rule or ""]
  if rule and rule.test then bx.out[id] = true end
end
S.BiBBankTakeOut = takeOut

local function hexOf(col) return string.format("%02x%02x%02x", math.floor(col[1] * 255), math.floor(col[2] * 255), math.floor(col[3] * 255)) end
local function boxLabel(bx) return "|cff" .. hexOf(bx.color) .. (bx.name or "Box") .. "|r" end

-- the sections for a list of items, with the bank view's own sorting
local function groupItems(items, v, c)
  local vc = {}
  for k, x in pairs(c) do vc[k] = x end
  vc.sort, vc.desc = v.sort, v.desc
  vc.split, vc.reagentSplit, vc.empty = false, false, "none"
  if v.group == "sections" then vc.group = true; return sections(items, vc) end
  local out, by = {}, {}
  for _, r in ipairs(items) do
    local k = v.group == "bag" and r.bag or 0
    local s = by[k]
    if not s then s = { id = k, name = v.group == "bag" and (r.bagName or "Bank") or "", rank = k, items = {} }; by[k] = s; out[#out + 1] = s end
    s.items[#s.items + 1] = r
  end
  table.sort(out, function(a, b) return a.rank < b.rank end)
  for _, s in ipairs(out) do table.sort(s.items, function(a, b) return less(a, b, vc) end) end
  return out
end

local bankBtns, bankHeads, bankBoxFrames, bankTabs = {}, {}, {}, {}
local itemMenu

-- Dragging items onto boxes and tabs. At the banker the game picks the item up
-- (the cursor holds it); away from the bank BiB drags a picture of it. Either way,
-- dropping it on a box or a tab only files it there - nothing moves in the bank
-- (at the banker the item goes straight back to its slot).
local vdrag, floater, lastDragKey
local function dragId()
  if vdrag then return vdrag.id end
  local kind, id; if GetCursorInfo then kind, id = GetCursorInfo() end
  if kind == "item" and id then return id end
end
S.BiBBankDragId = dragId
local function boxOfId(id)
  if not id then return nil end
  local _, boxes = bcfg()
  local r = { id = id }
  itemData(r); r.quest = r.classID == 12
  return boxOf(r, boxes)
end
local function endDrag()
  vdrag = nil
  if floater then floater:Hide() end
end
local function dropInto(bx, out)
  local id = dragId()
  if not id then return false end
  local _, boxes = bcfg()
  if bx then putIn(id, bx) elseif out then for _, b in ipairs(boxes) do takeOut(id, b) end end
  if not vdrag and ClearCursor then ClearCursor() end      -- the item goes back to its own slot
  endDrag()
  lastDragKey = nil
  S:RefreshBiBBank()
  return true
end
S.BiBBankDropInto = dropInto
local function showFloater(icon)
  if not floater then
    floater = CreateFrame("Frame", nil, UIParent)
    floater:SetFrameStrata("TOOLTIP"); floater:SetSize(34, 34)
    floater.icon = floater:CreateTexture(nil, "ARTWORK"); floater.icon:SetAllPoints(); floater.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    floater:SetScript("OnUpdate", function(self)
      local x, y = GetCursorPosition()
      local sc = UIParent:GetEffectiveScale()
      self:ClearAllPoints(); self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / sc + 10, y / sc - 10)
    end)
  end
  floater.icon:SetTexture(icon or QMARK); floater:SetAlpha(0.85); floater:Show()
end
-- light up the places an item can be dropped while one is being dragged
local function updateDrag(force)
  if not bankWin or not bankWin:IsShown() then return end
  local id = dragId()
  local key = tostring(id)
  if key == lastDragKey and not force then return end
  lastDragKey = key
  local th = UI:Theme()
  for _, f in ipairs(bankBoxFrames) do
    if f.catch then
      if id and f:IsShown() and f.box then
        local col = f.box.color
        f.catch.fill:SetColorTexture(col[1], col[2], col[3], 0.22)
        f.catch.text:SetText("Drop to put it in " .. boxLabel(f.box))
        f.catch:Show()
      else f.catch:Hide() end
    end
  end
  for _, t in ipairs(bankTabs) do
    if t.glow then
      local col = t.tabBox and t.tabBox.color or th.gold
      t.glow:SetColorTexture(col[1], col[2], col[3], 0.3)
      t.glow:SetShown(id ~= nil and t:IsShown())
    end
  end
  local outOn = id ~= nil and boxOfId(id) ~= nil
  local trackOn = id ~= nil and not S.BiBIsTracked(id, isGuildView())
  if bankWin.outCatch then
    local oc = bankWin.outCatch
    oc:ClearAllPoints(); oc:SetPoint("BOTTOMRIGHT", -6, 4); oc:SetHeight(FOOT)
    if trackOn then oc:SetPoint("LEFT", bankWin, "BOTTOM", 2, 0) else oc:SetPoint("LEFT", bankWin, "BOTTOMLEFT", 6, 0) end
    oc:SetShown(outOn)
  end
  if bankWin.trackCatch then
    local tc = bankWin.trackCatch
    tc:ClearAllPoints(); tc:SetPoint("BOTTOMLEFT", 6, 4); tc:SetHeight(FOOT)
    if outOn then tc:SetPoint("RIGHT", bankWin, "BOTTOM", -2, 0) else tc:SetPoint("RIGHT", bankWin, "BOTTOMRIGHT", -6, 0) end
    tc:SetShown(trackOn)
  end
end
local function bankButton(i)
  local b = bankBtns[i]
  if b then return b end
  b = CreateFrame("Button", nil, bankWin.child)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints()
  b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetPoint("TOPLEFT", 1, 1); b.icon:SetPoint("BOTTOMRIGHT", -1, -1)
  b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  b.edge = {}
  for k, pts in pairs({ t = { "TOPLEFT", "TOPRIGHT" }, bo = { "BOTTOMLEFT", "BOTTOMRIGHT" }, l = { "TOPLEFT", "BOTTOMLEFT" }, r = { "TOPRIGHT", "BOTTOMRIGHT" } }) do
    local e = b:CreateTexture(nil, "OVERLAY")
    e:SetPoint(pts[1]); e:SetPoint(pts[2])
    if k == "t" or k == "bo" then e:SetHeight(1) else e:SetWidth(1) end
    b.edge[k] = e
  end
  b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal"); b.count:SetPoint("BOTTOMRIGHT", -2, 2)
  b.dim = b:CreateTexture(nil, "OVERLAY", nil, 2); b.dim:SetAllPoints(); b.dim:SetColorTexture(0, 0, 0, 0.7); b.dim:Hide()
  b.hl = b:CreateTexture(nil, "HIGHLIGHT"); b.hl:SetAllPoints(); b.hl:SetColorTexture(1, 1, 1, 0.15)
  b:SetScript("OnEnter", function(self)
    local r = self.rec; if not r then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if r.empty then
      GameTooltip:AddLine((r.freeCount or 0) > 1 and (r.freeCount .. " free slots") or "Free slot")
      if r.bagName and (r.freeCount or 0) <= 1 then GameTooltip:AddLine("|cff888888" .. r.bagName .. "|r") end
      GameTooltip:Show()
      return
    end
    local ok = r.link and pcall(GameTooltip.SetHyperlink, GameTooltip, r.link)
    if not ok and r.id and GameTooltip.SetItemByID then ok = pcall(GameTooltip.SetItemByID, GameTooltip, r.id) end
    if not ok then GameTooltip:AddLine(r.name or "?") end
    GameTooltip:AddLine("|cff888888In the bank" .. (r.bagName and (" - " .. r.bagName) or "") .. (r.count > 1 and (" - " .. r.count) or "") .. "|r")
    if r.box then GameTooltip:AddLine("|cff888888Box: |r" .. boxLabel(r.box)) end
    GameTooltip:AddLine("|cff888888Drag onto a box or tab - or right-click - to file it|r")
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b:RegisterForDrag("LeftButton")
  b:SetScript("OnDragStart", function(self)
    local r = self.rec; if not (r and r.id) then return end
    vdrag = r; showFloater(r.icon); GameTooltip:Hide(); updateDrag(true)
  end)
  b:SetScript("OnDragStop", function()
    if not vdrag then return end
    local target, out
    for _, f in ipairs(bankBoxFrames) do if f:IsShown() and f.box and f:IsMouseOver() then target = f.box end end
    if not target then
      for _, t in ipairs(bankTabs) do if t:IsShown() and t:IsMouseOver() then if t.tabBox then target = t.tabBox else out = true end end end
    end
    if not target and not out and bankWin.outCatch and bankWin.outCatch:IsShown() and bankWin.outCatch:IsMouseOver() then out = true end
    if target or out then dropInto(target, out) else endDrag(); updateDrag(true) end
  end)
  b:SetScript("OnClick", function(self, btn)
    local r = self.rec; if not r or r.empty then return end
    if btn == "RightButton" then itemMenu(self, r) return end
    if not r.link then return end
    if IsModifiedClick and IsModifiedClick("CHATLINK") and ChatEdit_InsertLink then ChatEdit_InsertLink(r.link)
    elseif IsModifiedClick and IsModifiedClick("DRESSUP") and DressUpItemLink then DressUpItemLink(r.link) end
  end)
  bankBtns[i] = b
  return b
end
-- at the banker: the game's own bag-slot buttons, so items can be moved, dragged,
-- right-clicked into your bags... exactly like the game's bank
local liveBtns, bankHolders = {}, {}
local function bankHolder(bag)
  local h = bankHolders[bag]
  if not h then
    h = CreateFrame("Frame", "CC_BiBBankBag" .. (bag < 0 and ("M" .. -bag) or bag), bankWin.child)
    h:SetID(bag); h:SetSize(1, 1); h:SetPoint("TOPLEFT")
    bankHolders[bag] = h
  end
  return h
end
local function invSlotFor(bag, slot)
  if bag == (BANK_CONTAINER or -1) and BankButtonIDToInvSlotID then return BankButtonIDToInvSlotID(slot) end
  if REAGENTBANK_CONTAINER and bag == REAGENTBANK_CONTAINER and ReagentBankButtonIDToInvSlotID then return ReagentBankButtonIDToInvSlotID(slot) end
end
local function liveButton(bag, slot)
  local key = bag .. ":" .. slot
  local b = liveBtns[key]
  if b then return b end
  b = makeButton(bag, slot, bankHolder(bag))
  b:HookScript("OnEnter", function(self)
    if not self.hasItem then return end
    local inv = invSlotFor(self.bag, self.slot)
    if inv and GameTooltip.SetInventoryItem and (not GameTooltip:IsShown() or (GameTooltip.NumLines and GameTooltip:NumLines() == 0)) then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); pcall(GameTooltip.SetInventoryItem, GameTooltip, "player", inv)
    end
    if GameTooltip:IsShown() and (not GameTooltip.IsOwned or GameTooltip:IsOwned(self)) then
      local r = self.rec
      if r and r.box then GameTooltip:AddLine("|cff888888Box: |r" .. boxLabel(r.box)) end
      GameTooltip:AddLine("|cff888888Drag onto a box or tab - or Ctrl+right-click - to file it|r")
      GameTooltip:Show()
    end
  end)
  b:HookScript("OnClick", function(self, btn)
    if btn == "RightButton" and IsControlKeyDown and IsControlKeyDown() and self.rec and not self.rec.empty then itemMenu(self, self.rec) end
  end)
  liveBtns[key] = b
  return b
end
S.BiBBankLiveButtons = liveBtns

-- what the bank holds right now (only while you're at the banker)
local function liveRecords()
  local c = cfg()
  local list, empties, total, used = {}, {}, 0, 0
  for _, e in ipairs(bankBags()) do
    local n = numSlots(e.bag)
    if n > 0 then
      local fam = bagFamily(e.bag)
      local bname = e.name or bagName(e.bag)
      for slot = 1, n do
        total = total + 1
        local r = { bag = e.bag, slot = slot, family = fam, kind = e.kind, bagName = bname, live = true }
        local info = slotInfo(e.bag, slot)
        if info and (info.link or info.id or info.icon) then
          for k, x in pairs(info) do r[k] = x end
          r.count = tonumber(r.count) or 1
          itemData(r)
          r.quality = r.quality or 1
          r.quest, r.questStart = questInfo(e.bag, slot)
          r.cat = category(r, c, true)
          used = used + 1
          list[#list + 1] = r
        else
          r.empty = true; r.cat = "empty"
          empties[#empties + 1] = r
        end
      end
    end
  end
  return list, empties, total, used
end
S.BiBBankLive = liveRecords

local function bankHeader(i)
  local h = bankHeads[i]
  if not h then h = UI:Text(bankWin.child, "", "small"); bankHeads[i] = h end
  return h
end
local function boxFrame(i)
  local f = bankBoxFrames[i]
  if not f then
    f = CreateFrame("Frame", nil, bankWin.child)
    edgeLines(f)
    f.fill = f:CreateTexture(nil, "BACKGROUND", nil, -8); f.fill:SetAllPoints()
    f.title = UI:Text(f, "", "small"); f.title:SetPoint("TOPLEFT", 6, -4)
    f:SetFrameLevel(bankWin.child:GetFrameLevel())
    -- drop an item from the cursor on a box: it goes in that box (nothing moves in the bank)
    f:EnableMouse(true)
    local function drop(self)
      local kind, id; if GetCursorInfo then kind, id = GetCursorInfo() end
      if kind == "item" and id and self.box then putIn(id, self.box); if ClearCursor then ClearCursor() end; S:RefreshBiBBank() end
    end
    f:SetScript("OnReceiveDrag", drop)
    f:SetScript("OnMouseUp", drop)
    -- while an item is dragged the whole box turns into a drop target (above its slots)
    local cb = CreateFrame("Button", nil, bankWin.child)
    cb:SetAllPoints(f); cb:SetFrameLevel(bankWin.child:GetFrameLevel() + 20)
    cb.fill = cb:CreateTexture(nil, "OVERLAY"); cb.fill:SetAllPoints()
    cb.text = UI:Text(cb, "", "normal", "CENTER"); cb.text:SetPoint("CENTER")
    cb:RegisterForClicks("LeftButtonUp")
    cb:SetScript("OnReceiveDrag", function() dropInto(f.box) end)
    cb:SetScript("OnClick", function() dropInto(f.box) end)
    cb:Hide()
    f.catch = cb
    bankBoxFrames[i] = f
  end
  return f
end
-- Tab order: your own (cfg().bankView.tabOrder = list of "main" / box ids), changed by
-- dragging a tab along the row. Separate from box order (which decides priority).
local function sortTabs(tabs, v)
  local rank = {}
  for i, k in ipairs(type(v.tabOrder) == "table" and v.tabOrder or {}) do rank[k] = i end
  for i, t in ipairs(tabs) do t.pos = i end
  table.sort(tabs, function(a, b)
    local ra, rb = rank[a.key] or (1000 + a.pos), rank[b.key] or (1000 + b.pos)
    if ra ~= rb then return ra < rb end
    return a.pos < b.pos
  end)
end
-- move the tab `key` to place `to` (1 = first) among the tabs shown now (`keys`, in order)
local function moveTab(key, to, keys)
  local v = bcfg()
  local list = {}
  for _, k in ipairs(keys) do if k ~= key then list[#list + 1] = k end end
  to = math.max(1, math.min(#list + 1, to))
  table.insert(list, to, key)
  -- keep the places of tabs that aren't shown right now (boxes switched to "box")
  for _, k in ipairs(type(v.tabOrder) == "table" and v.tabOrder or {}) do
    local seen = false
    for _, x in ipairs(list) do if x == k then seen = true break end end
    if not seen then list[#list + 1] = k end
  end
  v.tabOrder = list
end
S.BiBBankMoveTab = moveTab
S.BiBBankSortTabs = sortTabs

local tabDrag, tabMarker
local function shownTabs()
  local out = {}
  for _, t in ipairs(bankTabs) do if t:IsShown() then out[#out + 1] = t end end
  -- reading order: row by row from the top, left to right
  table.sort(out, function(a, b)
    local ta, tb = math.floor((a:GetTop() or 0) + 0.5), math.floor((b:GetTop() or 0) + 0.5)
    if ta ~= tb then return ta > tb end
    return (a:GetLeft() or 0) < (b:GetLeft() or 0)
  end)
  return out
end
-- where the dragged tab would land, from the mouse position
local function tabDropIndex()
  local cx0, cy0 = GetCursorPosition()
  local sc = bankWin:GetEffectiveScale()
  local x, y = cx0 / sc, cy0 / sc
  local idx = 1
  for _, t in ipairs(shownTabs()) do
    if t ~= tabDrag then
      local cx = t:GetCenter()
      local tp, bt = t:GetTop(), t:GetBottom()
      -- the tab comes before the drop spot if it's on a row above the mouse,
      -- or on the mouse's row and left of it
      if tp and bt and cx then
        if y < bt - 2 then idx = idx + 1
        elseif y <= tp + 2 and x > cx then idx = idx + 1 end
      end
    end
  end
  return idx
end
local function placeMarker()
  if not tabDrag then return end
  local idx, list = tabDropIndex(), {}
  for _, t in ipairs(shownTabs()) do if t ~= tabDrag then list[#list + 1] = t end end
  tabMarker:ClearAllPoints()
  if list[idx] then tabMarker:SetPoint("RIGHT", list[idx], "LEFT", -1, 0)
  elseif list[#list] then tabMarker:SetPoint("LEFT", list[#list], "RIGHT", 1, 0)
  else tabMarker:SetPoint("LEFT", tabDrag, "LEFT", 0, 0) end
end
local function startTabDrag(t)
  if dragId() or not t.tabKey then return end
  tabDrag = t
  t:SetAlpha(0.45)
  if not tabMarker then
    tabMarker = CreateFrame("Frame", nil, bankWin)
    tabMarker:SetSize(3, 24); tabMarker:SetFrameLevel(bankWin:GetFrameLevel() + 40)
    tabMarker.tex = tabMarker:CreateTexture(nil, "OVERLAY"); tabMarker.tex:SetAllPoints()
    tabMarker:SetScript("OnUpdate", function() placeMarker() end)
  end
  local g = UI:Theme().gold
  tabMarker.tex:SetColorTexture(g[1], g[2], g[3], 1)
  tabMarker:Show(); placeMarker()
end
local function stopTabDrag()
  local t = tabDrag
  if not t then return end
  tabDrag = nil
  t:SetAlpha(1)
  t.justDragged = GetTime()
  if tabMarker then tabMarker:Hide() end
  local idx = tabDropIndex()
  local keys = {}
  for _, b in ipairs(shownTabs()) do keys[#keys + 1] = b.tabKey end
  moveTab(t.tabKey, idx, keys)
  S:RefreshBiBBank()
end

---------------------------------------------------------------------------
-- Tracked items: how many you have, along the bottom of the bank window.
-- Added with ItemMenu ("Track in BiB's bank" - only when BiB is on), the bank's own
-- right-click menu, or by dropping an item on the bottom of the window.
---------------------------------------------------------------------------
local TRACK_CELL, TRACK_ROW = 72, 26
-- guild = true: the guild bank's own list (the window passes isGuildView(); ItemMenu = yours)
local function trackList(guild)
  local c = cfg()
  if not guild then
    -- the character whose bank / bags the window shows; you, when it's closed (ItemMenu)
    return perChar((bankWin and bankWin:IsShown()) and ownerKey() or (charKey() or "?")).track
  end
  c.gbankTrack = type(c.gbankTrack) == "table" and c.gbankTrack or {}
  return c.gbankTrack
end
function S.BiBIsTracked(id, guild)
  id = tonumber(id)
  for _, x in ipairs(trackList(guild)) do if x == id then return true end end
  return false
end
function S.BiBTrack(id, on, guild)
  id = tonumber(id); if not id then return end
  local l = trackList(guild)
  for i = #l, 1, -1 do if l[i] == id then table.remove(l, i) end end
  if on ~= false then l[#l + 1] = id end
  if bankWin and bankWin:IsShown() then S:RefreshBiBBank() end
end
local function moveTracked(id, d)
  local l = trackList(isGuildView())
  for i, x in ipairs(l) do
    if x == id then
      local j = math.max(1, math.min(#l, i + d))
      table.remove(l, i); table.insert(l, j, id)
      break
    end
  end
  S:RefreshBiBBank()
end
local function bagCount(id)
  local f = (C_Item and C_Item.GetItemCount) or GetItemCount
  if not f then return 0 end
  local ok, n = pcall(f, id, false)
  return ok and tonumber(clean(n)) or 0
end
-- every saved bank that holds the item: { {label, count} }
local function savedCounts(id)
  local out, st = {}, bankStore()
  local function add(label, src)
    local n = 0
    for _, bag in ipairs(src.bags or {}) do for _, it in pairs(bag.items or {}) do if it.id == id then n = n + (it.count or 1) end end end
    if n > 0 then out[#out + 1] = { label, n } end
  end
  local keys = {}
  for k in pairs(st.chars) do keys[#keys + 1] = k end
  table.sort(keys)
  for _, k in ipairs(keys) do add(whoLabel(k), st.chars[k]) end
  if st.account then add("Warband bank", st.account) end
  for gname, g in pairs(st.guilds) do add("|cff40ff40" .. gname .. "|r guild bank", g) end
  return out
end
S.BiBSavedCounts = savedCounts
local function itemIcon(id)
  if GetItemIcon then local ok, t = pcall(GetItemIcon, id); if ok and t then return t end end
  if GIII then local ok, _, _, _, _, t = pcall(GIII, id); if ok and t then return t end end
  return QMARK
end
local function dropTrack()
  local id = dragId()
  if not id then return end
  S.BiBTrack(id, true, isGuildView())
  if not vdrag and ClearCursor then ClearCursor() end
  endDrag(); lastDragKey = nil
  S:RefreshBiBBank()
end

local trackCells = {}
local function trackCell(i)
  local b = trackCells[i]
  if b then return b end
  b = CreateFrame("Button", nil, bankWin.track)
  b:SetSize(TRACK_CELL - 4, 24)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(22, 22); b.icon:SetPoint("LEFT", 1, 0); b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  b.num = UI:Text(b, "", "normal"); b.num:SetPoint("LEFT", b.icon, "RIGHT", 3, 0)
  b.hl = b:CreateTexture(nil, "HIGHLIGHT"); b.hl:SetAllPoints(); b.hl:SetColorTexture(1, 1, 1, 0.08)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    if not pcall(GameTooltip.SetItemByID, GameTooltip, self.id) then GameTooltip:AddLine("Item " .. self.id) end
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine("In this bank", self.bankN, 1, 0.82, 0, 1, 1, 1)
    if self.bagN then GameTooltip:AddDoubleLine("In your bags", self.bagN, 1, 0.82, 0, 1, 1, 1) end
    for _, x in ipairs(savedCounts(self.id)) do GameTooltip:AddDoubleLine("|cff888888Bank:|r " .. x[1], x[2], 1, 1, 1, 0.8, 0.8, 0.8) end
    GameTooltip:AddLine("|cff888888Right-click: stop tracking / move|r")
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b:SetScript("OnReceiveDrag", function() dropTrack() end)
  b:SetScript("OnClick", function(self, btn)
    if dragId() then dropTrack() return end
    local id = self.id
    if btn == "RightButton" then
      local nm = GII and select(1, GII(id)) or ("Item " .. id)
      UI:Menu(self, {
        { text = nm or ("Item " .. id), title = true },
        { text = "Move left", func = function() moveTracked(id, -1) end },
        { text = "Move right", func = function() moveTracked(id, 1) end },
        { text = "Stop tracking", func = function() S.BiBTrack(id, false, isGuildView()) end },
      })
    elseif IsModifiedClick and IsModifiedClick("CHATLINK") and ChatEdit_InsertLink and GII then
      local _, link = GII(id); if link then ChatEdit_InsertLink(link) end
    end
  end)
  trackCells[i] = b
  return b
end
-- lays out the strip; returns its height (0 when nothing is tracked)
local function layoutTrack(bankCounts, isMe, w)
  local l = trackList(isGuildView())
  local strip = bankWin.track
  for i = #l + 1, #trackCells do trackCells[i]:Hide() end
  if #l == 0 then strip:Hide() return 0 end
  -- each cell is only as wide as its icon + number (so the hover box hugs it)
  local x, row = 0, 0
  for i, id in ipairs(l) do
    local b = trackCell(i)
    b.id, b.bankN = id, bankCounts[id] or 0
    b.bagN = isMe and bagCount(id) or nil
    b.icon:SetTexture(itemIcon(id))
    local total = b.bankN + (b.bagN or 0)
    b.num:SetText(total > 0 and tostring(total) or "|cff7777770|r")
    b.icon:SetDesaturated(total == 0)
    local cw = 22 + 3 + math.ceil(tonumber(b.num:GetStringWidth()) or 12) + 4
    b:SetSize(cw, 24)
    if x > 0 and x + cw > w then x = 0; row = row + 1 end
    b:ClearAllPoints(); b:SetPoint("TOPLEFT", strip, "TOPLEFT", x, -(4 + row * TRACK_ROW))
    x = x + cw + 6
    b:Show()
  end
  local h = (row + 1) * TRACK_ROW + 6
  strip:SetHeight(h); strip:Show()
  return h
end

-- ItemMenu: "Track in BiB's bank" - only offered while BiB is on (ItemMenu calls every
-- function in S.ItemMenuExtras with its add() and the item when it builds its menu)
S.ItemMenuExtras = S.ItemMenuExtras or {}
table.insert(S.ItemMenuExtras, function(add, id)
  id = tonumber(id)
  if not (id and S.BiBIsOn and S:BiBIsOn()) then return end
  local on = S.BiBIsTracked(id)
  add({ text = on and "Stop tracking in BiB's bank" or "Track in BiB's bank", tip = "Shows how many you have (bank + bags) along the bottom of BiB's bank window.",
    func = function() S.BiBTrack(id, not on); S:Print(on and "No longer tracked in BiB's bank." or "Tracked - see the bottom of BiB's bank window (/ccenter bank).") end })
end)

local function bankTab(i)
  local t = bankTabs[i]
  if not t then
    t = UI:Button(bankWin, "", 80, 20, function(self)
      if self.justDragged and GetTime() - self.justDragged < 0.3 then return end   -- the end of a tab drag isn't a click
      -- an item on the cursor dropped on a tab goes in that box (or, on "Bank", out of its box)
      if dragId() then dropInto(self.tabBox, not self.tabBox) return end
      local v = bcfg(); v.tab = self.tabKey; S:RefreshBiBBank()
    end)
    t:SetScript("OnReceiveDrag", function(self) self:Click() end)
    -- drag a tab along the row to change the order
    t:RegisterForDrag("LeftButton")
    t:SetScript("OnDragStart", function(self) startTabDrag(self) end)
    t:SetScript("OnDragStop", function() stopTabDrag() end)
    t:HookScript("OnEnter", function(self)
      if dragId() then return end
      GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
      GameTooltip:AddLine("Drag the tab left or right to change the order", 1, 1, 1)
      GameTooltip:Show()
    end)
    t:HookScript("OnLeave", function() GameTooltip:Hide() end)
    t.line = t:CreateTexture(nil, "OVERLAY"); t.line:SetPoint("BOTTOMLEFT", 2, -1); t.line:SetPoint("BOTTOMRIGHT", -2, -1); t.line:SetHeight(2)
    t.glow = t:CreateTexture(nil, "OVERLAY", nil, 7); t.glow:SetAllPoints(); t.glow:SetBlendMode("ADD"); t.glow:Hide()
    bankTabs[i] = t
  end
  return t
end

local function bankMatch(r)
  local q = bankWin and bankWin.search and bankWin.search:GetText() or ""
  q = q:lower():gsub("^%s+", ""):gsub("%s+$", "")
  return q == "" or matches(r, q)
end

function S:RefreshBiBBank()
  if not bankWin then return end
  local c = cfg()
  local v, boxes = bcfg()
  local th = UI:Theme()
  local who = bankView or charKey()
  -- at the banker, your own bank is live (real slots you can use); anywhere else it's the saved copy
  local live = bankOpen and who == charKey()
  if live and combat() then bankWin.combatPending = true; return end
  local list, total, used, src, empties
  if live then list, empties, total, used = liveRecords(); src = { at = time() }
  else list, total, used, src, empties = bankRecords(who) end
  local pc = {}                          -- the look BiB's own slots are painted with
  for k, x in pairs(c) do pc[k] = x end
  pc.empty = v.free == "all" and "all" or "one"
  local liveUsed = {}
  missing = false
  -- which box each item belongs to
  local inBox, rest = {}, {}
  for _, bx in ipairs(boxes) do inBox[bx] = {} end
  for _, r in ipairs(list) do
    local bx = boxOf(r, boxes)
    r.box = bx
    if bx then table.insert(inBox[bx], r) else rest[#rest + 1] = r end
  end
  -- tabs: Bank + every box shown on its own tab
  local isBags = type(who) == "string" and who:find("^bags:") ~= nil
  local tabs = { { key = "main", text = isBags and "Bags" or "Bank", n = #rest } }
  for _, bx in ipairs(boxes) do
    if bx.mode == "tab" then tabs[#tabs + 1] = { key = bx.id, text = boxLabel(bx), n = #inBox[bx], box = bx } end
  end
  sortTabs(tabs, v)
  local active = tabs[1]
  for _, t in ipairs(tabs) do if t.key == "main" then active = t end end
  for _, t in ipairs(tabs) do if t.key == v.tab then active = t end end
  v.tab = active.key
  local showTabs = #tabs > 1
  local tabBtns = {}                       -- placed further down, once the window width is known
  for i, t in ipairs(tabs) do
    local b = bankTab(i)
    if showTabs then
      b.tabKey = t.key; b.tabBox = t.box
      local label = t.text .. " |cff888888" .. t.n .. "|r"
      if b.SetText then b:SetText(label) end
      local fs = b.GetFontString and b:GetFontString()
      local w = math.max(50, ((fs and fs:GetStringWidth()) or 60) + 18)
      b:SetSize(w, 20); b.tabW = w
      tabBtns[#tabBtns + 1] = b
      local col = t.box and t.box.color or th.gold
      b.line:SetColorTexture(col[1], col[2], col[3], 1)
      b.line:SetShown(t == active)
      b:Show()
    else b:Hide() end
  end
  for i = #tabs + 1, #bankTabs do bankTabs[i]:Hide() end

  local size, sp = c.size, c.spacing
  -- a window you sized yourself keeps its size: the columns follow its width
  local sz = c.bankSize
  local sizing = bankWin.sizing
  local W = sizing and bankWin:GetWidth() or (type(sz) == "table" and tonumber(sz[1])) or nil
  local H = sizing and bankWin:GetHeight() or (type(sz) == "table" and tonumber(sz[2])) or nil
  local cols
  if W then cols = math.max(4, math.floor((W - c.pad * 2 - 6 + sp) / (size + sp)))
  else cols = math.max(BANK_COLS_MIN, c.cols) end
  local fullW = cols * (size + sp) - sp
  local winW = W or (fullW + c.pad * 2 + 6)
  -- tabs wrap onto more rows when they don't fit across the window
  local tabRows, tx = 0, 10
  for _, b in ipairs(tabBtns) do
    local w = b.tabW or 60
    if tabRows == 0 or (tx > 10 and tx + w > winW - 10) then tabRows = tabRows + 1; tx = 10 end
    b:ClearAllPoints(); b:SetPoint("TOPLEFT", bankWin, "TOPLEFT", tx, -(HEAD + SEARCH_H + 8 + (tabRows - 1) * TAB_H))
    tx = tx + w + 4
  end
  local top = HEAD + SEARCH_H + 10 + tabRows * TAB_H
  bankWin.scroll:ClearAllPoints()
  bankWin.scroll:SetPoint("TOPLEFT", c.pad + 3, -top); bankWin.scroll:SetPoint("BOTTOMRIGHT", -(c.pad + 3), FOOT + 4)
  local y, n, hn, bn = 0, 0, 0, 0
  local drawn = 0                        -- every slot drawn (saved copy AND live slots at the banker)
  local function drawGrid(secs, x0, showHeads)
    for _, s in ipairs(secs) do
      if showHeads and c.headers ~= false and s.name and s.name ~= "" and #secs > 1 then
        hn = hn + 1
        local h = bankHeader(hn)
        h:ClearAllPoints(); h:SetPoint("TOPLEFT", x0, -y); h:SetText("|cff" .. hexOf(th.gold) .. s.name .. "|r"); h:Show()
        y = y + HDR_H
      end
      for i, r in ipairs(s.items) do
        local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
        drawn = drawn + 1
        if r.live then
          local b = liveButton(r.bag, r.slot)
          liveUsed[b] = true
          b:SetSize(size, size)
          b:ClearAllPoints(); b:SetPoint("TOPLEFT", bankWin.child, "TOPLEFT", x0 + col * (size + sp), -(y + row * (size + sp)))
          b:SetFrameLevel(bankWin.child:GetFrameLevel() + 3)
          paint(b, r, pc)
          b.bibDim:SetShown((not r.empty) and not bankMatch(r))
          b:Show()
        else
        n = n + 1
        local b = bankButton(n)
        b.rec = r
        b:SetSize(size, size)
        b:ClearAllPoints(); b:SetPoint("TOPLEFT", x0 + col * (size + sp), -(y + row * (size + sp)))
        b.bg:SetColorTexture(th.field[1], th.field[2], th.field[3], 0.85)
        if r.empty then
          -- a free slot (from the saved copy): empty, with a count when they're folded into one
          b.icon:SetTexture(nil)
          b.count:SetText(v.free == "one" and (r.freeCount or 0) > 1 and ("|cff888888" .. r.freeCount .. "|r") or "")
          for _, e in pairs(b.edge) do e:SetColorTexture(th.edge[1], th.edge[2], th.edge[3], 0.5) end
          b.dim:Hide()
        else
        b.icon:SetTexture(r.icon or QMARK)
        b.count:SetText(r.count > 1 and (r.count > 9999 and (math.floor(r.count / 1000) .. "k") or r.count) or "")
        local qr, qg, qb = th.edge[1], th.edge[2], th.edge[3]
        if r.quest and c.questMark then qr, qg, qb = 1, 0.82, 0
        elseif c.quality and (r.quality or 1) >= 2 then qr, qg, qb = qColor(r.quality) end
        for _, e in pairs(b.edge) do e:SetColorTexture(qr or 0.3, qg or 0.3, qb or 0.3, 1) end
        b.dim:SetShown(not bankMatch(r))
        end
        b:Show()
        end
      end
      y = y + math.ceil(#s.items / cols) * (size + sp) + c.gap
    end
  end
  if active.box then
    drawGrid(groupItems(inBox[active.box], v, c), 0, true)
  else
    drawGrid(groupItems(rest, v, c), 0, true)
    -- free slots after the rest: every one (like the game's bank), one per kind of bag
    -- with a count, or none (at the banker they're real slots you can drop things into)
    if v.free ~= "none" and empties and #empties > 0 then
      local free = {}
      if v.free == "all" then
        for _, e in ipairs(empties) do e.freeCount = nil; free[#free + 1] = e end
      else
        local byFam = {}
        for _, e in ipairs(empties) do
          local k = (e.kind or "") .. ":" .. (e.family or 0)
          local f = byFam[k]
          if not f then f = e; f.freeCount = 0; byFam[k] = f; free[#free + 1] = f end
          f.freeCount = f.freeCount + 1
        end
      end
      drawGrid({ { name = "", items = free } }, 0, false)
    end
    -- boxes shown inside the bank: one bordered box each, after the rest
    local inset = 6
    for _, bx in ipairs(boxes) do
      local items = inBox[bx]
      if bx.mode == "box" and #items > 0 then
        bn = bn + 1
        local f = boxFrame(bn)
        local startY = y
        y = y + HDR_H + 2
        drawGrid(groupItems(items, v, c), 0, v.group ~= "sections")
        y = y - c.gap + inset
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", bankWin.child, "TOPLEFT", -inset + 1, -(startY - 2))
        f:SetSize(fullW + inset * 2 - 2, y - startY + 2)
        setEdge(f, bx.color[1], bx.color[2], bx.color[3], 0.9)
        f.fill:SetColorTexture(bx.color[1], bx.color[2], bx.color[3], 0.07)
        f.title:SetText(boxLabel(bx) .. " |cff888888" .. #items .. "|r")
        f.box = bx
        f:Show()
        y = y + c.gap
      end
    end
  end
  for i = n + 1, #bankBtns do bankBtns[i]:Hide(); bankBtns[i].rec = nil end
  for _, b in pairs(liveBtns) do if not liveUsed[b] then b:Hide() end end
  for i = hn + 1, #bankHeads do bankHeads[i]:Hide() end
  for i = bn + 1, #bankBoxFrames do bankBoxFrames[i]:Hide() end
  bankWin.child:SetSize(fullW, math.max(1, y))
  -- tracked items along the bottom
  local bc = {}
  for _, r in ipairs(list) do if r.id then bc[r.id] = (bc[r.id] or 0) + (r.count or 1) end end
  local trackH = layoutTrack(bc, who == charKey(), winW - 20)
  bankWin.scroll:SetPoint("BOTTOMRIGHT", -(c.pad + 3), FOOT + 4 + trackH)
  local bodyH
  if W then
    if not sizing then bankWin:SetWidth(W); bankWin:SetHeight(H) end
    bodyH = math.max(20, H - (top + FOOT + 10 + trackH))
  else
    bankWin:SetWidth(winW)
    local maxH = math.floor((UIParent:GetHeight() or 800) * 0.7)
    bodyH = math.min(math.max(y, 40), maxH - (top + FOOT + 10 + trackH))
    bankWin:SetHeight(top + bodyH + FOOT + 10 + trackH)
  end
  bankWin.scroll:SetVerticalScroll(math.min(bankWin.scroll:GetVerticalScroll(), math.max(0, y - bodyH)))
  bankWin.scrollMax = math.max(0, y - bodyH)
  local isGuild = type(who) == "string" and who:find("^guild:") ~= nil
  local titles = S.BiBTitles()
  local custom = (isGuild and titles.guild[who:sub(7)]) or (who == charKey() and titles.bank) or nil
  bankWin.title:SetText(custom or (who == "account" and "Warband bank") or (isGuild and (who:sub(7) .. " - guild bank"))
    or (isBags and (whoLabel(who) .. "'s bags"))
    or ((who == charKey()) and (live and "Bank" or "Your bank") or (whoLabel(who) .. "'s bank")))
  -- the pencil only where the name is yours to change: your own bank and guild banks
  if bankWin.titleEdit then bankWin.titleEdit:SetShown((isGuild and who ~= "guild:") or who == charKey()) end
  if not src then
    bankWin.empty:SetText((who == "guild:" and "|cff888888You're not in a guild.|r")
      or (isBags and "|cff888888BiB hasn't seen this character's bags yet.\nLog in on them once (with BiB on) and they're remembered.|r")
      or (isGuild and "|cff888888BiB hasn't seen this guild bank yet.\nOpen the guild vault once and it's remembered from then on.|r")
      or (who == charKey() and "|cff888888BiB hasn't seen this character's bank yet.\nVisit a banker once and it's remembered from then on.|r")
      or "|cff888888Nothing remembered for this bank.|r")
    bankWin.empty:Show()
  elseif drawn == 0 and isGuild and total == 0 then
    bankWin.empty:SetText("|cff888888This guild bank has no tabs to show\n(none bought yet, or none you're allowed to see).|r")
    bankWin.empty:Show()
  elseif drawn == 0 then
    bankWin.empty:SetText(active.box and "|cff888888Nothing in this box yet.\nRight-click an item in the bank to put it in.|r" or "|cff888888Everything here is in your boxes.|r")
    bankWin.empty:Show()
  else bankWin.empty:Hide() end
  local foot
  if live then foot = string.format("%d / %d slots used", used, total)
  else foot = src and string.format("%d / %d slots used - seen %s%s", used, total, ago(src.at), bankOpen and " (you're at the bank)" or "") or "" end
  -- how much gold is in the (guild) bank: bottom-right corner
  if bankWin.gold then
    local money = src and tonumber(src.money)
    -- at your guild's vault right now: the gold as it is this moment
    if isGuild and guildOpen and who:sub(7) == guildName() and GetGuildBankMoney then
      local okm, m = pcall(GetGuildBankMoney); m = okm and tonumber(clean(m)); if m then money = m end
    end
    bankWin.gold:SetText(money and S.BiBMoney(money) or "")
    bankWin.gold:SetShown(money and not live and true or false)
  end
  if bankWin.logBtn then bankWin.logBtn:SetShown(isGuild) end
  bankWin.foot:SetText("|cff888888" .. foot .. "|r")
  if bankWin.gameBtn then bankWin.gameBtn:SetShown(live and true or false) end
  updateDrag(true)
  if missing then C_Timer.After(0.6, function() if bankWin:IsShown() then S:RefreshBiBBank() end end) end
end

local function later(fn) C_Timer.After(0, fn) end

-- right-click an item: which box it goes in
itemMenu = function(btn, r)
  local _, boxes = bcfg()
  local items = { { text = r.name or "Item", title = true } }
  if not r.id then UI:Menu(btn, items) return end
  for _, bx in ipairs(boxes) do
    items[#items + 1] = { text = "Put in " .. boxLabel(bx) .. (bx.mode == "tab" and " |cff888888(tab)|r" or ""), checked = r.box == bx,
      func = function() putIn(r.id, bx); S:RefreshBiBBank() end }
  end
  items[#items + 1] = { text = "New box with this item...", func = function()
    later(function() UI:Prompt("Name the new box (sets, mats, collectables...):", "", function(name)
      name = name and name:gsub("^%s+", ""):gsub("%s+$", "") or ""
      if name == "" then return end
      local bx = newBox(name); putIn(r.id, bx); S:RefreshBiBBank()
    end) end)
  end }
  if r.box then
    items[#items + 1] = { text = "Take out of " .. boxLabel(r.box), func = function() takeOut(r.id, r.box); S:RefreshBiBBank() end }
  end
  local gv = isGuildView()
  local tr = S.BiBIsTracked(r.id, gv)
  items[#items + 1] = { text = tr and "Stop tracking" or (gv and "Track how many the guild has (bottom of the window)" or "Track how many I have (bottom of the window)"),
    func = function() S.BiBTrack(r.id, not tr, gv) end }
  UI:Menu(btn, items)
end

local boxMenu
local function boxesMenu(anchor)
  local _, boxes = bcfg()
  local items = { { text = "Boxes", title = true } }
  items[#items + 1] = { text = "New box...", tip = "A box keeps chosen items together - in a bordered box in the bank, or on a tab of their own.", func = function()
    later(function() UI:Prompt("Name the new box (sets, mats, collectables...):", "", function(name)
      name = name and name:gsub("^%s+", ""):gsub("%s+$", "") or ""
      if name == "" then return end
      local bx = newBox(name); S:RefreshBiBBank()
      later(function() boxMenu(anchor, bx) end)
    end) end)
  end }
  for _, bx in ipairs(boxes) do
    local rule = RULE[bx.rule or ""]
    local n = 0; for _ in pairs(bx.items) do n = n + 1 end
    items[#items + 1] = { text = boxLabel(bx) .. "  |cff888888" .. (bx.mode == "tab" and "own tab" or "box") .. ((rule and rule.test) and (", " .. rule.text:lower()) or "") .. "|r",
      func = function() later(function() boxMenu(anchor, bx) end) end }
  end
  if #boxes == 0 then items[#items + 1] = { text = "|cff888888Or right-click any item in the bank.|r", disabled = true } end
  UI:Menu(anchor, items)
end

local function colorMenu(anchor, bx)
  local items = { { text = "Colour of " .. boxLabel(bx), title = true } }
  for _, pc in ipairs(BOX_COLORS) do
    items[#items + 1] = { text = "|cff" .. hexOf(pc[2]) .. pc[1] .. "|r", func = function() bx.color = { unpack(pc[2]) }; S:RefreshBiBBank() end }
  end
  if UI.PickColor then
    items[#items + 1] = { text = "Pick any colour...", func = function() later(function() UI.PickColor(bx.color, function() S:RefreshBiBBank() end) end) end }
  end
  UI:Menu(anchor, items)
end

boxMenu = function(anchor, bx)
  local v, boxes = bcfg()
  local at; for i, b in ipairs(boxes) do if b == bx then at = i end end
  if not at then return end
  local n = 0; for _ in pairs(bx.items) do n = n + 1 end
  local items = { { text = boxLabel(bx), title = true } }
  items[#items + 1] = { text = "Show as a box in the bank", checked = bx.mode == "box", tip = "A bordered box under your other bank items.",
    func = function() bx.mode = "box"; if v.tab == bx.id then v.tab = "main" end; S:RefreshBiBBank() end }
  items[#items + 1] = { text = "Show on its own tab", checked = bx.mode == "tab", tip = "Its items leave the main bank page and get a tab at the top.",
    func = function() bx.mode = "tab"; S:RefreshBiBBank() end }
  items[#items + 1] = { text = "Fill it by itself with", title = true }
  for _, rule in ipairs(RULES) do
    items[#items + 1] = { text = rule.text .. ((rule.value == "name" and bx.rule == "name" and bx.text) and (" |cff888888\"" .. bx.text .. "\"|r") or ""),
      checked = (bx.rule or "") == rule.value, tip = rule.tip, func = function()
        if rule.value == "name" then
          later(function() UI:Prompt("Put items whose name contains:", bx.text or "", function(t)
            t = t and t:gsub("^%s+", ""):gsub("%s+$", "") or ""
            if t == "" then return end
            bx.rule, bx.text = "name", t; S:RefreshBiBBank()
          end) end)
        else bx.rule = rule.value; S:RefreshBiBBank() end
      end }
  end
  items[#items + 1] = { text = "Box", title = true }
  items[#items + 1] = { text = "Rename...", func = function()
    later(function() UI:Prompt("New name for the box:", bx.name or "", function(t)
      t = t and t:gsub("^%s+", ""):gsub("%s+$", "") or ""
      if t ~= "" then bx.name = t; S:RefreshBiBBank() end
    end) end)
  end }
  items[#items + 1] = { text = "Colour...", func = function() later(function() colorMenu(anchor, bx) end) end }
  if at > 1 then items[#items + 1] = { text = "Move up", tip = "Boxes higher up come first - and win when an item fits two boxes.",
    func = function() table.remove(boxes, at); table.insert(boxes, at - 1, bx); S:RefreshBiBBank() end } end
  if at < #boxes then items[#items + 1] = { text = "Move down", func = function() table.remove(boxes, at); table.insert(boxes, at + 1, bx); S:RefreshBiBBank() end } end
  items[#items + 1] = { text = "Empty it (" .. n .. " item" .. (n == 1 and "" or "s") .. " you put in)", disabled = n == 0,
    func = function() wipe(bx.items); wipe(bx.out); S:RefreshBiBBank() end }
  items[#items + 1] = { text = "Delete this box...", func = function()
    later(function() UI:Confirm("Delete the box " .. boxLabel(bx) .. "?\nIts items go back to the bank page.", function()
      for i, b in ipairs(boxes) do if b == bx then table.remove(boxes, i) break end end
      if v.tab == bx.id then v.tab = "main" end
      S:RefreshBiBBank()
    end, "Delete") end)
  end }
  UI:Menu(anchor, items)
end
S.BiBBankBoxMenu = boxMenu

local function bankSortMenu(anchor)
  local v = bcfg()
  local c = cfg()
  local items = { { text = "Sort the bank by", title = true } }
  for _, s in ipairs(SORTS) do
    items[#items + 1] = { text = s.text, tip = s.tip, checked = v.sort == s.value, func = function() v.sort = s.value; S:RefreshBiBBank() end }
  end
  items[#items + 1] = { text = "Reverse the order", checked = v.desc, keep = true, func = function() v.desc = not v.desc; S:RefreshBiBBank() end }
  items[#items + 1] = { text = "Free slots", title = true }
  for _, f in ipairs({ { "all", "Show every free slot", "Like the game's bank: each empty slot on its own." },
                       { "one", "One per kind of bag, with a count", "Saves room: one empty slot shows how many are free." },
                       { "none", "Hide them", "At the banker you can still drop items on your bags or tabs." } }) do
    items[#items + 1] = { text = f[2], tip = f[3], checked = (v.free or "one") == f[1], func = function() v.free = f[1]; S:RefreshBiBBank() end }
  end
  items[#items + 1] = { text = "Group into", title = true }
  for _, g in ipairs(GROUPS) do
    items[#items + 1] = { text = g.text, tip = g.tip, checked = v.group == g.value, func = function() v.group = g.value; S:RefreshBiBBank() end }
  end
  items[#items + 1] = { text = "Use my bags' sorting", tip = "Copy how BiB sorts your bags.", func = function()
    v.sort, v.desc, v.group = c.sort, c.desc, (c.split and "bag") or (c.group and "sections") or "none"; S:RefreshBiBBank()
  end }
  items[#items + 1] = { text = "Boxes...", tip = "Your own boxes for sets, mats, collectables...", func = function() later(function() boxesMenu(anchor) end) end }
  if cfg().bankSize then
    items[#items + 1] = { text = "Fit the window to the bank again", tip = "Forget the size you dragged it to.", func = function() cfg().bankSize = nil; S:RefreshBiBBank() end }
  end
  UI:Menu(anchor, items)
end

-- guild view: only guild banks (the one you're looking at, your own guild, every guild
-- bank remembered from a vault visit)
local function guildMenu(self)
  local st = bankStore()
  local cur = bankView and bankView:sub(7) or ""
  local mine = guildName()
  local names, seen = {}, {}
  for g in pairs(st.guilds) do names[#names + 1] = g; seen[g] = true end
  if mine and not seen[mine] then names[#names + 1] = mine end
  table.sort(names)
  local items = { { text = "Whose guild bank?", title = true } }
  for _, g in ipairs(names) do
    local rec = st.guilds[g]
    local key = "guild:" .. g
    items[#items + 1] = { text = "|cff40ff40" .. g .. "|r" .. (g == mine and "  (your guild)" or "") .. "  |cff888888" .. (rec and ago(rec.at) or "not seen yet") .. "|r",
      checked = cur == g, func = function() bankView = key; S:RefreshBiBBank() end }
  end
  if #names == 0 then items[#items + 1] = { text = "|cff888888No guild bank seen yet - open a guild vault.|r", title = true } end
  if st.guilds[cur] then
    items[#items + 1] = { text = "Forget this guild bank...", func = function()
      C_Timer.After(0, function()
        UI:Confirm("Forget what BiB remembered of " .. cur .. "'s guild bank?\n(It's remembered again next time the guild vault is opened.)", function()
          st.guilds[cur] = nil; S:RefreshBiBBank()
        end, "Forget")
      end)
    end }
  end
  items[#items + 1] = { text = "Your own bank", func = function() bankView = nil; S:RefreshBiBBank() end }
  UI:Menu(self, items)
end

local function charMenu(self)
  if type(bankView) == "string" and bankView:find("^guild:") then guildMenu(self) return end
  local st = bankStore()
  local keys = {}
  local me = charKey()
  for k, r in pairs(st.chars) do if r.bags or k == me then keys[#keys + 1] = k end end
  table.sort(keys, function(a, b) return a < b end)
  local items = { { text = "Whose bank?", title = true } }
  for _, k in ipairs(keys) do
    local r = st.chars[k]
    items[#items + 1] = { text = whoLabel(k) .. (k == me and "  (you)" or "") .. "  |cff888888" .. (r.bags and ago(r.at) or "not seen yet") .. "|r", checked = (bankView or me) == k,
      func = function() bankView = (k ~= me) and k or nil; S:RefreshBiBBank() end }
  end
  if st.account then
    items[#items + 1] = { text = "Warband bank  |cff888888" .. ago(st.account.at) .. "|r", checked = bankView == "account",
      func = function() bankView = "account"; S:RefreshBiBBank() end }
  end
  if #keys == 0 and not st.account then items[#items + 1] = { text = "|cff888888No bank seen yet - visit a banker.|r", title = true } end
  local who = bankView or me
  local isGuild = type(who) == "string" and who:find("^guild:") ~= nil
  if who and ((who == "account" and st.account) or (isGuild and st.guilds[who:sub(7)]) or (st.chars[who] and st.chars[who].bags)) then
    items[#items + 1] = { text = "Forget this bank...", func = function()
      C_Timer.After(0, function()
        UI:Confirm("Forget what BiB remembered of " .. (who == "account" and "the warband bank" or isGuild and (who:sub(7) .. "'s guild bank") or (S.Short(who) .. "'s bank")) .. "?\n(It's remembered again next time that bank is opened.)", function()
          if who == "account" then st.account = nil elseif isGuild then st.guilds[who:sub(7)] = nil else st.chars[who].bags = nil; st.chars[who].at = nil end
          bankView = nil; S:RefreshBiBBank()
        end, "Forget")
      end)
    end }
  end
  UI:Menu(self, items)
end

-- Window titles you can rename: a pencil right of the title opens a box; empty = default.
-- cfg().titles = { bags = "...", bank = "...", guild = { [guild name] = "..." } }
function S.BiBTitles()
  local c = cfg()
  c.titles = type(c.titles) == "table" and c.titles or {}
  c.titles.guild = type(c.titles.guild) == "table" and c.titles.guild or {}
  return c.titles
end
function S.BiBAddTitleEdit(f, onClick)
  local b = CreateFrame("Button", nil, f)
  b:SetSize(16, 16)
  b:SetPoint("LEFT", f.title, "RIGHT", 6, 0)
  b:SetFrameLevel(f:GetFrameLevel() + 5)
  b.icon = UI:Icon(b, "edit", 12); b.icon:SetPoint("CENTER")
  UI:Skin(b, function(self, th) self.icon:SetVertexColor(th.muted[1], th.muted[2], th.muted[3], 1) end)
  b:SetScript("OnEnter", function(self)
    local g = UI:Theme().gold; self.icon:SetVertexColor(g[1], g[2], g[3], 1)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM"); GameTooltip:AddLine("Rename this window"); GameTooltip:AddLine("|cff888888Leave it empty to go back to the usual name.|r"); GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function(self) local m = UI:Theme().muted; self.icon:SetVertexColor(m[1], m[2], m[3], 1); GameTooltip:Hide() end)
  b:SetScript("OnClick", function() if onClick then onClick() end end)
  f.titleEdit = b
  return b
end
function S.BiBAskTitle(current, onSet)
  UI:Prompt("Name this window (leave it empty for the usual name):", current or "", function(t)
    t = (t or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if #t > 40 then t = t:sub(1, 40) end
    onSet(t ~= "" and t or nil)
  end)
end

local function buildBank()
  bankWin = UI:Window("CC_BiBBank", "Your bank", 420, 300, { header = HEAD })
  bankWin:SetFrameStrata("MEDIUM")
  bankWin:HeaderButton("roster", "Whose bank?", "Pick another character (or the warband bank). Every character's bank is remembered after you open it once.", function(self) charMenu(self) end)
  bankWin:HeaderButton("bag", "Your bags", "Open BiB.", function() S:ShowBiB() end)
  bankWin:HeaderButton("box", "Boxes", "Make your own boxes (sets, mats, collectables...) - shown as a bordered box in the bank or on a tab of their own. Right-click an item to put it in one.", function(self) boxesMenu(self) end)
  bankWin:HeaderButton("sort", "Sort the bank", "How the bank view is sorted and grouped (separate from your bags; the guild bank has its own).", function(self) bankSortMenu(self) end)
  bankWin.logBtn = bankWin:HeaderButton("book", "Guild bank log", "Who put in and took out what (and the gold log), from your last visit to the guild vault.", function()
    if S.ToggleBiBGuildLog then S:ToggleBiBGuildLog() end
  end)
  bankWin.logBtn:Hide()
  S.BiBAddTitleEdit(bankWin, function()
    local who = bankView or charKey()
    local titles = S.BiBTitles()
    if type(who) == "string" and who:find("^guild:") then
      local g = who:sub(7)
      S.BiBAskTitle(titles.guild[g] or bankWin.title:GetText(), function(t) titles.guild[g] = t; S:RefreshBiBBank() end)
    else
      S.BiBAskTitle(titles.bank or bankWin.title:GetText(), function(t) titles.bank = t; S:RefreshBiBBank() end)
    end
  end)
  bankWin.search = UI:Edit(bankWin, 200, 20, "Search the bank  (name, type, epic, ilvl>100...)")
  bankWin.search:SetPoint("TOPLEFT", 10, -(HEAD + 6)); bankWin.search:SetPoint("RIGHT", -10, 0)
  bankWin.search:HookScript("OnTextChanged", function()
    for _, b in ipairs(bankBtns) do if b.rec then b.dim:SetShown(not bankMatch(b.rec)) end end
    for _, b in pairs(liveBtns) do if b.rec and b:IsShown() then b.bibDim:SetShown((not b.rec.empty) and not bankMatch(b.rec)) end end
  end)
  -- at the banker: bring the game's own bank window back for this visit (buying slots, bank bags...)
  bankWin.gameBtn = UI:Button(bankWin, "Game's bank", 90, 18, function() if S.BiBUseGameBank then S.BiBUseGameBank() end end,
    "Show the game's own bank window for this visit - to buy bank slots or change bank bags. BiB's window comes back next time.")
  bankWin.gameBtn:SetPoint("BOTTOMRIGHT", -24, 4); bankWin.gameBtn:Hide()
  -- tracked items strip (above the footer)
  local tk = CreateFrame("Frame", nil, bankWin)
  tk:SetPoint("BOTTOMLEFT", 10, FOOT + 2); tk:SetPoint("BOTTOMRIGHT", -10, FOOT + 2); tk:SetHeight(1)
  tk.line = tk:CreateTexture(nil, "ARTWORK"); tk.line:SetPoint("TOPLEFT"); tk.line:SetPoint("TOPRIGHT"); tk.line:SetHeight(1)
  UI:Skin(tk.line, function(self, th) self:SetColorTexture(th.edge[1], th.edge[2], th.edge[3], 1) end)
  tk:EnableMouse(true)
  tk:SetScript("OnReceiveDrag", function() dropTrack() end)
  tk:SetScript("OnMouseUp", function() if dragId() then dropTrack() end end)
  tk:Hide()
  bankWin.track = tk
  -- drop strip: track a dragged item
  local tc = CreateFrame("Button", nil, bankWin)
  tc:SetFrameLevel(bankWin:GetFrameLevel() + 30)
  tc.fill = tc:CreateTexture(nil, "OVERLAY"); tc.fill:SetAllPoints(); tc.fill:SetColorTexture(0.3, 0.6, 1, 0.25)
  tc.text = UI:Text(tc, "Drop here to track how many you have", "small", "CENTER"); tc.text:SetPoint("CENTER")
  tc:RegisterForClicks("LeftButtonUp")
  tc:SetScript("OnReceiveDrag", function() dropTrack() end)
  tc:SetScript("OnClick", function() dropTrack() end)
  tc:Hide()
  bankWin.trackCatch = tc
  -- resize from the bottom-right corner (the columns follow the width)
  bankWin:SetResizable(true)
  if bankWin.SetResizeBounds then bankWin:SetResizeBounds(250, 200, 1800, 1300) elseif bankWin.SetMinResize then bankWin:SetMinResize(250, 200) end
  local grip = CreateFrame("Button", nil, bankWin)
  grip:SetSize(16, 16); grip:SetPoint("BOTTOMRIGHT", -3, 3)
  grip:SetFrameLevel(bankWin:GetFrameLevel() + 35)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  grip:RegisterForClicks("RightButtonUp")
  grip:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine("Drag to resize")
    GameTooltip:AddLine("|cff888888Right-click: fit the window to the bank again|r"); GameTooltip:Show()
  end)
  grip:SetScript("OnLeave", function() GameTooltip:Hide() end)
  grip:SetScript("OnMouseDown", function(_, btn)
    if btn ~= "LeftButton" or (cfg().lock) then return end
    bankWin.sizing = true
    bankWin:StartSizing("BOTTOMRIGHT")
  end)
  grip:SetScript("OnMouseUp", function()
    if not bankWin.sizing then return end
    bankWin:StopMovingOrSizing()
    bankWin.sizing = false
    cfg().bankSize = { math.floor(bankWin:GetWidth() + 0.5), math.floor(bankWin:GetHeight() + 0.5) }
    local l, t = bankWin:GetLeft(), bankWin:GetTop()
    if l and t then cfg().bankAt = { l, t }; bankWin:ClearAllPoints(); bankWin:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t) end
    S:RefreshBiBBank()
  end)
  grip:SetScript("OnClick", function() cfg().bankSize = nil; S:RefreshBiBBank() end)
  bankWin.grip = grip
  bankWin:HookScript("OnSizeChanged", function()
    if bankWin.sizing and not bankWin.sizePending then
      bankWin.sizePending = true
      C_Timer.After(0.05, function() bankWin.sizePending = false; if bankWin:IsShown() then S:RefreshBiBBank() end end)
    end
  end)
  -- drop strip along the bottom: take a dragged item out of its box
  local oc = CreateFrame("Button", nil, bankWin)
  oc:SetPoint("BOTTOMLEFT", 6, 4); oc:SetPoint("BOTTOMRIGHT", -6, 4); oc:SetHeight(FOOT)
  oc:SetFrameLevel(bankWin:GetFrameLevel() + 30)
  oc.fill = oc:CreateTexture(nil, "OVERLAY"); oc.fill:SetAllPoints(); oc.fill:SetColorTexture(0.9, 0.3, 0.25, 0.25)
  oc.text = UI:Text(oc, "Drop here to take it out of its box", "small", "CENTER"); oc.text:SetPoint("CENTER")
  oc:RegisterForClicks("LeftButtonUp")
  oc:SetScript("OnReceiveDrag", function() dropInto(nil, true) end)
  oc:SetScript("OnClick", function() dropInto(nil, true) end)
  oc:Hide()
  bankWin.outCatch = oc
  -- watch the cursor: an item picked up lights up the boxes and tabs
  local acc = 0
  bankWin:HookScript("OnUpdate", function(_, el)
    acc = acc + el
    if acc < 0.08 then return end
    acc = 0
    updateDrag()
  end)
  bankWin.scroll = CreateFrame("ScrollFrame", nil, bankWin)
  bankWin.scroll:SetPoint("TOPLEFT", cfg().pad + 3, -(HEAD + SEARCH_H + 10)); bankWin.scroll:SetPoint("BOTTOMRIGHT", -(cfg().pad + 3), FOOT + 4)
  bankWin.child = CreateFrame("Frame", nil, bankWin.scroll); bankWin.child:SetSize(1, 1)
  bankWin.scroll:SetScrollChild(bankWin.child)
  bankWin.scroll:EnableMouseWheel(true)
  bankWin.scroll:SetScript("OnMouseWheel", function(self, d)
    local val = math.max(0, math.min(bankWin.scrollMax or 0, self:GetVerticalScroll() - d * (cfg().size + cfg().spacing) * 2))
    self:SetVerticalScroll(val)
  end)
  bankWin.empty = UI:Text(bankWin, "", "small", "CENTER"); bankWin.empty:SetPoint("CENTER", 0, -10); bankWin.empty:SetWidth(360)
  bankWin.foot = UI:Text(bankWin, "", "small"); bankWin.foot:SetPoint("BOTTOMLEFT", 12, 8)
  bankWin.gold = UI:Text(bankWin, "", "small", "RIGHT"); bankWin.gold:SetPoint("BOTTOMRIGHT", -24, 8)
  local at = cfg().bankAt
  bankWin:ClearAllPoints()
  if type(at) == "table" and at[1] then bankWin:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", at[1], at[2])
  else bankWin:SetPoint("CENTER", -200, 60) end
  bankWin:SetScript("OnDragStart", function(self) if not cfg().lock then self:StartMoving() end end)
  bankWin:HookScript("OnDragStop", function(self)
    local l, t = self:GetLeft(), self:GetTop(); if l and t then cfg().bankAt = { l, t } end
  end)
  bankWin:HookScript("OnShow", function() S:RefreshBiBBank() end)
  bankWin:HookScript("OnHide", function()
    bankWin.search:SetText(""); bankWin.search:ClearFocus(); bankView = nil
    endDrag()
    if tabDrag then tabDrag:SetAlpha(1); tabDrag = nil; if tabMarker then tabMarker:Hide() end end
    -- closing BiB's bank at the banker ends the visit, like closing the game's bank
    if bankOpen and S.BiBBankTakingOver and S.BiBBankTakingOver() and CloseBankFrame then pcall(CloseBankFrame) end
  end)
end

---------------------------------------------------------------------------
-- At the banker: BiB's bank window instead of the game's. The game's BankFrame is
-- parked under a hidden frame BEFORE the bank opens (hiding it while it's showing
-- would end the visit), so it "opens" without ever being seen.
---------------------------------------------------------------------------
local bankPark = CreateFrame("Frame"); bankPark:Hide()
local gameBankThisVisit = false
local bankAutoOpened = false
local function takingOver() return S.db ~= nil and S:BiBIsOn() and cfg().bankWindow ~= false and not gameBankThisVisit end
S.BiBBankTakingOver = takingOver
local function applyTakeover()
  local f = _G.BankFrame
  if not f or not f.SetParent or combat() then return end
  if takingOver() then
    if f:GetParent() ~= bankPark and not f:IsVisible() then f:SetParent(bankPark) end
  elseif f:GetParent() == bankPark then
    f:SetParent(UIParent)
  end
end
S.BiBApplyBankTakeover = applyTakeover
S.BiBUseGameBank = function()
  gameBankThisVisit = true
  applyTakeover()
  local f = _G.BankFrame
  if f and bankOpen and not f:IsShown() and ShowUIPanel then pcall(ShowUIPanel, f) end
  if bankWin then bankAutoOpened = false; bankWin:Hide() end   -- (taking over is off now, so this doesn't end the visit)
end
S.BiBBankArrived = function()
  applyTakeover()
  if takingOver() then
    bankView = nil
    if not (bankWin and bankWin:IsShown()) then bankAutoOpened = true end
    S:ShowBiBBank()
  elseif bankWin and bankWin:IsShown() then S:RefreshBiBBank() end
end
S.BiBBankLeft = function()
  gameBankThisVisit = false
  if bankWin and bankWin:IsShown() then
    if bankAutoOpened then bankWin:Hide() else S:RefreshBiBBank() end
  end
  bankAutoOpened = false
  C_Timer.After(0, applyTakeover)
end
S:Listen("LOGIN", function() applyTakeover() end)
S:On("PLAYER_REGEN_ENABLED", function()
  applyTakeover()
  if bankWin and bankWin.combatPending then bankWin.combatPending = false; if bankWin:IsShown() then S:RefreshBiBBank() end end
end)
-- live bank: redraw quickly when things move, lock (picked up) or cool down
local livePending = false
local function liveSoon()
  if not (bankOpen and bankWin and bankWin:IsShown()) or livePending then return end
  livePending = true
  C_Timer.After(0.05, function() livePending = false; if bankWin:IsShown() then S:RefreshBiBBank() end end)
end
for _, ev in ipairs({ "BAG_UPDATE_DELAYED", "PLAYERBANKSLOTS_CHANGED", "PLAYERREAGENTBANKSLOTS_CHANGED", "ITEM_LOCK_CHANGED", "BAG_UPDATE_COOLDOWN", "PLAYERBANKBAGSLOTS_CHANGED" }) do
  S:On(ev, liveSoon)
end

-- Guild bank log window: item moves (per tab or all tabs) and the gold log
local logWin
local LOG_ROWS_MAX = 300
local function coins(m) return S.BiBMoney(m or 0) end
local function logLine(e, tabNames)
  local who = e.who or "Someone"
  local t = e.t or ""
  if e.money then
    if t == "deposit" then return who .. " deposited " .. coins(e.money) end
    if t == "withdraw" then return who .. " withdrew " .. coins(e.money) end
    if t == "repair" then return who .. " withdrew " .. coins(e.money) .. " for repairs" end
    if t == "withdrawForTab" then return who .. " withdrew " .. coins(e.money) .. " to buy a tab" end
    if t == "buyTab" then return who .. " bought a bank tab for " .. coins(e.money) end
    if t == "depositSummary" then return "Gold from guild members' sales: " .. coins(e.money) end
    return who .. " " .. t .. " " .. coins(e.money)
  end
  local item = (e.link or "an item") .. ((e.n or 1) > 1 and (" x" .. e.n) or "")
  if t == "deposit" then return who .. " deposited " .. item end
  if t == "withdraw" then return who .. " withdrew " .. item end
  if t == "move" then
    return who .. " moved " .. item .. " from " .. (tabNames[e.from] or ("tab " .. tostring(e.from))) .. " to " .. (tabNames[e.to] or ("tab " .. tostring(e.to)))
  end
  return who .. " " .. t .. " " .. item
end
local function logEntries(g, which)
  local out, tabNames = {}, {}
  for _, b in ipairs(g.bags or {}) do tabNames[b.bag] = b.name end
  local log = g.log or {}
  if which == "money" then
    for _, e in ipairs(log.money or {}) do out[#out + 1] = e end
  else
    for tab, list in pairs(log.tabs or {}) do
      if which == "all" or which == tab then
        for _, e in ipairs(list) do e.tab = tab; out[#out + 1] = e end
      end
    end
  end
  -- newest first (the game numbers each tab's log oldest -> newest)
  table.sort(out, function(a, b)
    if (a.at or 0) ~= (b.at or 0) then return (a.at or 0) > (b.at or 0) end
    if (a.tab or 0) ~= (b.tab or 0) then return (a.tab or 0) < (b.tab or 0) end
    return (a.i or 0) > (b.i or 0)
  end)
  return out, tabNames, log.at
end
S.BiBGuildLogEntries = logEntries
local function refreshLog()
  if not (logWin and logWin:IsShown()) then return end
  local key = (type(bankView) == "string" and bankView:find("^guild:")) and bankView:sub(7) or guildName()
  local g = key and bankStore().guilds[key]
  local which = logWin.which or "all"
  logWin.title:SetText((key or "Guild") .. " - bank log")
  if not g or not g.log then
    for _, r in ipairs(logWin.rows) do r:Hide() end
    logWin.empty:SetText(g and "|cff888888No log yet - open the guild vault (the game sends the log while you're there).|r"
      or "|cff888888BiB hasn't seen this guild bank yet.|r")
    logWin.empty:Show(); logWin.foot:SetText(""); logWin.child:SetHeight(1)
    logWin.whichBtn:SetText("Show: All tabs")
    return
  end
  local list, tabNames, at = logEntries(g, which)
  logWin.whichBtn:SetText("Show: " .. ((which == "all" and "All tabs") or (which == "money" and "Gold") or (tabNames[which] or ("Tab " .. tostring(which)))))
  local y = 0
  local w = logWin.scroll:GetWidth() or 420
  for i = 1, math.min(#list, LOG_ROWS_MAX) do
    local e = list[i]
    local r = logWin.rows[i]
    if not r then
      r = CreateFrame("Button", nil, logWin.child)
      r.text = UI:Text(r, "", "small"); r.text:SetPoint("TOPLEFT", 4, -3); r.text:SetJustifyH("LEFT")
      r.hl = r:CreateTexture(nil, "HIGHLIGHT"); r.hl:SetAllPoints(); r.hl:SetColorTexture(1, 1, 1, 0.06)
      r:SetScript("OnEnter", function(self)
        if self.link then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); pcall(GameTooltip.SetHyperlink, GameTooltip, self.link); GameTooltip:Show() end
      end)
      r:SetScript("OnLeave", function() GameTooltip:Hide() end)
      r:SetScript("OnClick", function(self)
        if self.link and IsModifiedClick and IsModifiedClick("CHATLINK") and ChatEdit_InsertLink then ChatEdit_InsertLink(self.link) end
      end)
      logWin.rows[i] = r
    end
    local tabTag = (which == "all" and e.tab) and ("|cff666666[" .. (tabNames[e.tab] or ("Tab " .. e.tab)) .. "]|r ") or ""
    r.text:SetWidth(w - 8)
    r.text:SetText("|cff888888" .. ago(e.at) .. "|r  " .. tabTag .. logLine(e, tabNames))
    local h = math.max(18, (r.text:GetStringHeight() or 12) + 6)
    r:SetHeight(h); r:SetWidth(w)
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", logWin.child, "TOPLEFT", 0, -y)
    r.link = e.link
    r:Show()
    y = y + h
  end
  for i = math.min(#list, LOG_ROWS_MAX) + 1, #logWin.rows do logWin.rows[i]:Hide() end
  logWin.child:SetSize(w, math.max(1, y))
  logWin.scrollMax = math.max(0, y - (logWin.scroll:GetHeight() or 300))
  logWin.scroll:SetVerticalScroll(math.min(logWin.scroll:GetVerticalScroll(), logWin.scrollMax))
  logWin.empty:SetShown(#list == 0)
  logWin.empty:SetText("|cff888888Nothing in this log.|r")
  logWin.foot:SetText("|cff888888" .. #list .. " entr" .. (#list == 1 and "y" or "ies") .. " - log from " .. ago(at) .. " (times are rounded to the hour)|r")
end
S.BiBRefreshGuildLog = refreshLog
local function logMenu(anchor)
  local key = (type(bankView) == "string" and bankView:find("^guild:")) and bankView:sub(7) or guildName()
  local g = key and bankStore().guilds[key]
  local items = { { text = "Show", title = true },
    { text = "All tabs", checked = (logWin.which or "all") == "all", func = function() logWin.which = "all"; refreshLog() end } }
  for _, b in ipairs(g and g.bags or {}) do
    items[#items + 1] = { text = b.name or ("Tab " .. b.bag), checked = logWin.which == b.bag, func = function() logWin.which = b.bag; refreshLog() end }
  end
  items[#items + 1] = { text = "Gold", checked = logWin.which == "money", func = function() logWin.which = "money"; refreshLog() end }
  UI:Menu(anchor, items)
end
function S:ToggleBiBGuildLog()
  if logWin and logWin:IsShown() then logWin:Hide() return end
  if not logWin then
    logWin = UI:Window("CC_BiBGuildLog", "Guild bank log", 460, 420)
    logWin:SetFrameStrata("HIGH")
    logWin.rows = {}
    logWin.whichBtn = UI:Button(logWin, "Show: All tabs", 160, 20, function(self) logMenu(self) end, "Pick a tab, all tabs, or the gold log.")
    logWin.whichBtn:SetPoint("TOPLEFT", 12, -36)
    logWin.scroll = CreateFrame("ScrollFrame", nil, logWin)
    logWin.scroll:SetPoint("TOPLEFT", 12, -62); logWin.scroll:SetPoint("BOTTOMRIGHT", -12, 30)
    logWin.child = CreateFrame("Frame", nil, logWin.scroll); logWin.child:SetSize(1, 1)
    logWin.scroll:SetScrollChild(logWin.child)
    logWin.scroll:EnableMouseWheel(true)
    logWin.scroll:SetScript("OnMouseWheel", function(self, d)
      self:SetVerticalScroll(math.max(0, math.min(logWin.scrollMax or 0, self:GetVerticalScroll() - d * 40)))
    end)
    logWin.empty = UI:Text(logWin, "", "small", "CENTER"); logWin.empty:SetPoint("CENTER", 0, 0); logWin.empty:SetWidth(400)
    logWin.foot = UI:Text(logWin, "", "small"); logWin.foot:SetPoint("BOTTOMLEFT", 12, 10)
    logWin:ClearAllPoints()
    if bankWin and bankWin:IsShown() then logWin:SetPoint("TOPLEFT", bankWin, "TOPRIGHT", 8, 0) else logWin:SetPoint("CENTER") end
  end
  logWin:Show(); logWin:Raise()
  refreshLog()
end
S:AddCommand("glog", "", "BiB: the guild bank log (from your last visit to the guild vault)", function() S:ToggleBiBGuildLog() end)

function S:ShowBiBBank(who)
  if not S.db then return end
  if not bankWin then buildBank() end
  if who then bankView = who end
  if bankWin:IsShown() then S:RefreshBiBBank() else bankWin:Show(); bankWin:Raise() end
end
function S:ToggleBiBBank() if bankWin and bankWin:IsShown() then bankWin:Hide() else S:ShowBiBBank() end end
-- your guild's bank (the copy from the last visit to the guild vault), in the same window
function S:ShowBiBGuildBank()
  local key = "guild:" .. (guildName() or "")
  if bankWin and bankWin:IsShown() and bankView == key then bankWin:Hide() return end
  S:ShowBiBBank(key)
end
S:AddCommand("gbank", "", "BiB: see your guild bank from anywhere", function() S:ShowBiBGuildBank() end)
S:AddCommand("bank", "", "BiB: see your bank (and your other characters' banks) from anywhere", function() S:ToggleBiBBank() end)
end
bankSection()

---------------------------------------------------------------------------
-- Extras on BiB's bags window (its own function, like the bank part):
--  * key ring button on the bottom edge: every key you own, and where it is
--  * currencies you pick, shown along the bottom next to your gold
--  * a guild bank button in the header, next to "Your bank"
---------------------------------------------------------------------------
local function extrasSection()
  local KEYRING = KEYRING_CONTAINER or (Enum and Enum.BagIndex and Enum.BagIndex.Keyring) or -2
  local KEY_ICON = "Interface\\Icons\\INV_Misc_Key_04"

  -- every key you own: the key ring, keys in your bags (item class 13), keys in your bank
  local function ownedKeys()
    local out, byId = {}, {}
    local function add(r, where, count)
      local k = r.id or r.link
      if not k then return end
      local e = byId[k]
      if not e then
        e = { id = r.id, link = r.link, icon = r.icon, quality = r.quality, name = r.name, bags = 0, ring = 0, bank = 0 }
        byId[k] = e; out[#out + 1] = e
      end
      e[where] = e[where] + (tonumber(count) or 1)
      e.name = e.name or r.name
    end
    for slot = 1, numSlots(KEYRING) do
      local i = slotInfo(KEYRING, slot)
      if i and (i.id or i.link) then local r = { id = i.id, link = i.link, icon = i.icon, quality = i.quality }; itemData(r); add(r, "ring", i.count) end
    end
    for _, bag in ipairs(bagList()) do
      if bag ~= KEYRING then
        for slot = 1, numSlots(bag) do
          local i = slotInfo(bag, slot)
          if i and (i.id or i.link) then
            local r = { id = i.id, link = i.link, icon = i.icon, quality = i.quality }
            itemData(r)
            if r.classID == 13 then add(r, "bags", i.count) end
          end
        end
      end
    end
    if S.BiBBankRecords then
      local ok, list = pcall(S.BiBBankRecords)
      for _, r in ipairs(ok and list or {}) do if r.classID == 13 then add(r, "bank", r.count) end end
    end
    table.sort(out, function(a, b) return (a.name or "") < (b.name or "") end)
    return out
  end
  S.BiBOwnedKeys = ownedKeys

  local kwin
  local function keyRow(i)
    local r = kwin.rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, kwin)
    r:SetHeight(24); r:SetPoint("LEFT", 12, 0); r:SetPoint("RIGHT", -12, 0)
    r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(20, 20); r.icon:SetPoint("LEFT"); r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    r.name = UI:Text(r, "", "normal"); r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
    r.where = UI:Text(r, "", "small", "RIGHT"); r.where:SetPoint("RIGHT", -2, 0)
    r.name:SetPoint("RIGHT", r.where, "LEFT", -6, 0); r.name:SetJustifyH("LEFT")
    r.hl = r:CreateTexture(nil, "HIGHLIGHT"); r.hl:SetAllPoints(); r.hl:SetColorTexture(1, 1, 1, 0.07)
    r:SetScript("OnEnter", function(self)
      local e = self.e; if not e then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      local ok = e.link and pcall(GameTooltip.SetHyperlink, GameTooltip, e.link)
      if not ok and e.id then pcall(GameTooltip.SetItemByID, GameTooltip, e.id) end
      GameTooltip:AddLine(" ")
      if e.ring > 0 then GameTooltip:AddDoubleLine("On your key ring", e.ring, 1, 0.82, 0, 1, 1, 1) end
      if e.bags > 0 then GameTooltip:AddDoubleLine("In your bags", e.bags, 1, 0.82, 0, 1, 1, 1) end
      if e.bank > 0 then GameTooltip:AddDoubleLine("In your bank", e.bank, 0.3, 0.8, 1, 1, 1, 1) end
      GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r:SetScript("OnClick", function(self)
      local e = self.e
      if e and e.link and IsModifiedClick and IsModifiedClick("CHATLINK") and ChatEdit_InsertLink then ChatEdit_InsertLink(e.link) end
    end)
    kwin.rows[i] = r
    return r
  end
  local function refreshKeys()
    if not (kwin and kwin:IsShown()) then return end
    local keys = ownedKeys()
    local y = -40
    for i, e in ipairs(keys) do
      local r = keyRow(i)
      r.e = e
      r:ClearAllPoints(); r:SetPoint("TOPLEFT", 12, y); r:SetPoint("RIGHT", -12, 0)
      r.icon:SetTexture(e.icon or QMARK)
      local qc = ITEM_QUALITY_COLORS and e.quality and ITEM_QUALITY_COLORS[e.quality]
      r.name:SetText((qc and qc.hex or "|cffffffff") .. (e.name or ("Item " .. tostring(e.id))) .. "|r")
      local parts = {}
      if e.ring > 0 then parts[#parts + 1] = "Key ring" end
      if e.bags > 0 then parts[#parts + 1] = "Bags" end
      if e.bank > 0 then parts[#parts + 1] = "|cff4dccffBank|r" end
      local total = e.ring + e.bags + e.bank
      r.where:SetText(table.concat(parts, ", ") .. (total > 1 and ("  |cff888888x" .. total .. "|r") or ""))
      r:Show()
      y = y - 26
    end
    for i = #keys + 1, #kwin.rows do kwin.rows[i]:Hide() end
    kwin.empty:SetShown(#keys == 0)
    kwin.foot:SetText("|cff888888" .. #keys .. " key" .. (#keys == 1 and "" or "s") .. " - bank keys are from your last bank visit|r")
    kwin:SetHeight(math.max(130, -y + 34))
  end
  function S:ToggleBiBKeys()
    if kwin and kwin:IsShown() then kwin:Hide() return end
    if not kwin then
      kwin = UI:Window("CC_BiBKeys", "Keys", 320, 160)
      kwin:SetFrameStrata("HIGH")
      kwin.rows = {}
      kwin.empty = UI:Text(kwin, "|cff888888You don't have any keys.|r", "small", "CENTER"); kwin.empty:SetPoint("TOP", 0, -56)
      kwin.foot = UI:Text(kwin, "", "small"); kwin.foot:SetPoint("BOTTOMLEFT", 12, 10)
    end
    kwin:ClearAllPoints()
    if win and win:IsShown() and win.keyBtn then kwin:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 0, 34) else kwin:SetPoint("CENTER") end
    kwin:Show(); kwin:Raise()
    refreshKeys()
  end
  S:On("BAG_UPDATE_DELAYED", function() refreshKeys() end)

  -- currencies: pick which ones show along the bottom of BiB
  local function currencyList()
    local out = {}
    pcall(function()
      local CI = C_CurrencyInfo
      local n = (CI and CI.GetCurrencyListSize and CI.GetCurrencyListSize()) or (GetCurrencyListSize and GetCurrencyListSize()) or 0
      for i = 1, (tonumber(n) or 0) do
        local name, isHeader, qty, icon, id
        if CI and CI.GetCurrencyListInfo then
          local info = CI.GetCurrencyListInfo(i)
          if info then name, isHeader, qty, icon, id = info.name, info.isHeader, info.quantity, info.iconFileID, info.currencyID end
          if not id and not isHeader and CI.GetCurrencyListLink and CI.GetCurrencyIDFromLink then
            local l = CI.GetCurrencyListLink(i); if l then id = CI.GetCurrencyIDFromLink(l) end
          end
        elseif GetCurrencyListInfo then
          local a, b, _, _, _, c, d = GetCurrencyListInfo(i)
          name, isHeader, qty, icon = a, b, c, d
        end
        if name and not isHeader then out[#out + 1] = { key = id or name, id = id, name = name, qty = tonumber(qty) or 0, icon = icon } end
      end
    end)
    return out
  end
  S.BiBCurrencyList = currencyList
  -- each character picks its own (cfg().charBank[key].currencies); the list picked before
  -- rev 22 (one for everyone) went to the character logged in when rev 22 first ran
  local function tracked()
    local c = cfg()
    local key = S.BiBCharKey and S.BiBCharKey()
    if not key or not S.BiBPerChar then
      c.currencies = type(c.currencies) == "table" and c.currencies or {}
      return c.currencies
    end
    local r = S.BiBPerChar(key)
    if type(r.currencies) ~= "table" then
      if not c.currMoved and type(c.currencies) == "table" then r.currencies = c.currencies else r.currencies = {} end
      c.currMoved = true
    end
    return r.currencies
  end
  local function isTracked(key) for _, k in ipairs(tracked()) do if k == key then return true end end return false end
  function S.BiBTrackCurrency(key, on)
    local l = tracked()
    for i = #l, 1, -1 do if l[i] == key then table.remove(l, i) end end
    if on ~= false then l[#l + 1] = key end
    if S.BiBUpdateCurrencies then S.BiBUpdateCurrencies() end
  end
  local function currencyNow(key, list)
    if type(key) == "number" and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
      local ok, i = pcall(C_CurrencyInfo.GetCurrencyInfo, key)
      if ok and type(i) == "table" and i.name then return tonumber(i.quantity) or 0, i.iconFileID, i.name end
    end
    for _, c in ipairs(list) do if c.key == key then return c.qty, c.icon, c.name end end
  end
  local function updateCurrencies()
    if not (win and win.currBtn) then return end
    local list = currencyList()
    local parts = {}
    for _, key in ipairs(tracked()) do
      local qty, icon, name = currencyNow(key, list)
      if name then parts[#parts + 1] = (icon and ("|T" .. icon .. ":14:14:0:0|t ") or "") .. (BreakUpLargeNumbers and BreakUpLargeNumbers(qty) or qty) end
    end
    local b = win.currBtn
    if #parts > 0 then b.text:SetText(table.concat(parts, "   "))
    elseif #list > 0 then b.text:SetText("|cff666666Currencies|r")
    else b.text:SetText("") end
    b:SetWidth(math.max(10, (b.text:GetStringWidth() or 0) + 4))
    b:SetShown(#parts > 0 or #list > 0)
  end
  S.BiBUpdateCurrencies = updateCurrencies
  local function currencyMenu(anchor)
    local list = currencyList()
    local items = { { text = "Show along the bottom of BiB", title = true } }
    for _, c in ipairs(list) do
      local key = c.key
      items[#items + 1] = { text = (c.icon and ("|T" .. c.icon .. ":14:14:0:0|t ") or "") .. c.name .. "  |cff888888" .. c.qty .. "|r",
        checked = isTracked(key), keep = true, func = function() S.BiBTrackCurrency(key, not isTracked(key)) end }
    end
    if #list == 0 then items[#items + 1] = { text = "|cff888888This character has no currencies yet.|r", disabled = true } end
    UI:Menu(anchor, items)
  end
  S.BiBCurrencyMenu = currencyMenu
  S:On("CURRENCY_DISPLAY_UPDATE", function() if win and win:IsShown() then updateCurrencies() end end)

  -----------------------------------------------------------------------
  -- Your other characters: their gold (per ruleset) and a copy of their bags
  -- from the last time you played them. Kept in G().bibBank.chars[key]:
  --   money, moneyAt, class, rules, inv = { at, money, bags }
  -----------------------------------------------------------------------
  -- a character's ruleset: saved by meRec() each time it logs in (read from the game)
  local function rulesOf(key, rec) return rec and rec.rules or nil end
  -- the logged-in character's ruleset, straight from the game: game rules PvPRuleset /
  -- RPRuleset are 0 or 1 (Normal 0/0, PvP 1/0, Roleplay 0/1, RP-PvP 1/1), Hardcore has its
  -- own check; backup: the Battle.net status text ("Forever - Roleplay PvP - ...")
  local function myRules()
    local ok, hc = pcall(function() return C_GameRules and C_GameRules.IsHardcoreActive and C_GameRules.IsHardcoreActive() end)
    if ok and clean(hc) == true then return "Hardcore" end
    local GR = Enum and Enum.GameRule
    if C_GameRules and C_GameRules.GetGameRuleAsFloat and GR and GR.PvPRuleset and GR.RPRuleset then
      local ok1, pvp = pcall(C_GameRules.GetGameRuleAsFloat, GR.PvPRuleset)
      local ok2, rp = pcall(C_GameRules.GetGameRuleAsFloat, GR.RPRuleset)
      pvp, rp = ok1 and tonumber(clean(pvp)), ok2 and tonumber(clean(rp))
      if pvp and rp then
        if pvp > 0 and rp > 0 then return "RP-PvP" end
        if pvp > 0 then return "PvP" end
        if rp > 0 then return "Roleplay" end
        return "Normal"
      end
    end
    local okb, pres = pcall(function()
      local info = C_BattleNet and C_BattleNet.GetAccountInfoByGUID and UnitGUID and C_BattleNet.GetAccountInfoByGUID(UnitGUID("player"))
      return info and info.gameAccountInfo and info.gameAccountInfo.richPresence
    end)
    pres = okb and clean(pres)
    if type(pres) == "string" then
      local l = pres:lower()
      if l:find("hardcore") then return "Hardcore" end
      if l:find("roleplay pvp") or l:find("rp%-pvp") or l:find("rppvp") then return "RP-PvP" end
      if l:find("roleplay") then return "Roleplay" end
      if l:find("pvp") then return "PvP" end
      if l:find("normal") then return "Normal" end
    end
    return nil
  end
  S.BiBRulesOf = function(key, rec) return rulesOf(key, rec) end
  local function meRec()
    local key = S.BiBCharKey and S.BiBCharKey()
    if not key or not S.db then return nil end
    local st = S.BiBBankStore()
    local rec = st.chars[key] or {}
    st.chars[key] = rec
    local _, cls = UnitClass("player")
    rec.class = clean(cls) or rec.class
    rec.rules = myRules() or rec.rules
    return rec, key, st
  end
  local function recordMoney()
    if not S.db or not S:BiBIsOn() or (S.BiBLeaving and S.BiBLeaving()) then return end
    local rec = meRec(); if not rec then return end
    local m = tonumber(clean(GetMoney and GetMoney()))
    if m then rec.money, rec.moneyAt = m, time(); if rec.inv then rec.inv.money = m end end
  end
  local function recordInv()
    if not S.db or not S:BiBIsOn() or cfg().bankMemory == false or (S.BiBLeaving and S.BiBLeaving()) then return end
    local rec = meRec(); if not rec then return end
    local inv = { at = time(), money = tonumber(clean(GetMoney and GetMoney())), bags = {} }
    for _, bag in ipairs(bagList()) do
      local n = numSlots(bag)
      if n > 0 then
        local b = { bag = bag, n = n, name = bagName(bag), items = {} }
        for slot = 1, n do
          local info = slotInfo(bag, slot)
          if info and (info.link or info.id or info.icon) then
            b.items[slot] = { id = info.id, link = info.link, count = tonumber(info.count) or 1, icon = info.icon, q = info.quality, b = info.bound and true or nil }
          end
        end
        inv.bags[#inv.bags + 1] = b
      end
    end
    if #inv.bags == 0 then return end            -- bags not loaded (yet / any more): keep the last good copy
    rec.inv = inv
    if inv.money then rec.money, rec.moneyAt = inv.money, time() end
  end
  S.BiBRecordInv = recordInv
  local invPending = false
  local function invSoon()
    if invPending then return end
    invPending = true
    C_Timer.After(2, function() invPending = false; pcall(recordInv) end)
  end
  S:On("PLAYER_ENTERING_WORLD", function() C_Timer.After(3, function() pcall(recordInv) end) end)
  S:On("BAG_UPDATE_DELAYED", invSoon)
  S:On("PLAYER_MONEY", function() pcall(recordMoney) end)
  -- (nothing is taken at PLAYER_LOGOUT: by then the game reports 0 gold and empty bags)
  local leaving = false
  S:On("PLAYER_LOGOUT", function() leaving = true end)
  S:On("PLAYER_LEAVING_WORLD", function() leaving = true end)
  S:On("PLAYER_ENTERING_WORLD", function() leaving = false end)
  S.BiBLeaving = function() return leaving end

  -- every other character BiB knows (gold and / or bags), sorted by name
  local function otherChars()
    local st = S.BiBBankStore()
    local me = S.BiBCharKey and S.BiBCharKey()
    local out = {}
    for k, r in pairs(st.chars) do if k ~= me and (r.money or r.inv) then out[#out + 1] = k end end
    table.sort(out)
    return out, st, me
  end
  local function nameOf(k, r)
    local hex = S.ClassHex and S.ClassHex(r and r.class) or "ffffff"
    return "|cff" .. hex .. ((S.Short and S.Short(k)) or k) .. "|r"
  end
  -- hover your gold: your characters' gold on the same ruleset
  local function goldTip(owner)
    local keys, st, me = otherChars()
    local mine = st.chars[me or ""]
    local myR = rulesOf(me, mine)
    local myMoney = tonumber(clean(GetMoney and GetMoney())) or 0
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    GameTooltip:AddLine("Gold" .. (myR and (" - " .. myR) or ""))
    GameTooltip:AddDoubleLine(nameOf(me or "You", mine) .. "  |cff888888(you)|r", S.BiBMoney(myMoney), 1, 1, 1, 1, 1, 1)
    local total, unknown, other = myMoney, {}, 0
    for _, k in ipairs(keys) do
      local r = st.chars[k]
      local rr = rulesOf(k, r)
      if r.money then
        if myR and rr and rr ~= myR then other = other + 1
        elseif myR and not rr then unknown[#unknown + 1] = k
        else
          total = total + r.money
          GameTooltip:AddDoubleLine(nameOf(k, r) .. "  |cff888888" .. S.BiBAgo(r.moneyAt) .. "|r", S.BiBMoney(r.money), 1, 1, 1, 1, 1, 1)
        end
      end
    end
    GameTooltip:AddDoubleLine("Total", S.BiBMoney(total), 1, 0.82, 0, 1, 1, 1)
    if #unknown > 0 then
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine("Ruleset not known yet - log in on them once (not in the total)", 0.6, 0.6, 0.6)
      for _, k in ipairs(unknown) do local r = st.chars[k]; GameTooltip:AddDoubleLine(nameOf(k, r), S.BiBMoney(r.money), 1, 1, 1, 1, 1, 1) end
    end
    if other > 0 then GameTooltip:AddLine("|cff888888" .. other .. " character" .. (other == 1 and "" or "s") .. " on other rulesets not counted|r") end
    if #keys == 0 then GameTooltip:AddLine("|cff888888Log in on your other characters once and their gold shows here.|r", nil, nil, nil, true) end
    GameTooltip:Show()
  end
  -- the characters button: open another character's bags (as last seen)
  local function charsMenu(anchor)
    local keys, st, me = otherChars()
    local myR = rulesOf(me, st.chars[me or ""])
    local items = { { text = "Whose bags?", title = true } }
    local any = false
    for _, k in ipairs(keys) do
      local r = st.chars[k]
      local rr = rulesOf(k, r)
      if r.inv then
        any = true
        items[#items + 1] = { text = nameOf(k, r) .. "  |cff888888" .. S.BiBAgo(r.inv.at) .. ((rr and rr ~= myR) and ("  (" .. rr .. ")") or "") .. "|r",
          tip = r.money and ("Gold: " .. S.BiBMoney(r.money)) or nil,
          func = function() S:ShowBiBBank("bags:" .. k) end }
      end
    end
    if not any then items[#items + 1] = { text = "|cff888888No other characters seen yet - log in on them once with BiB on.|r", title = true } end
    UI:Menu(anchor, items)
  end
  S.BiBCharsMenu = charsMenu
  S.BiBGoldTip = goldTip

  -- tidy up what earlier revisions left behind: the ruleset probe answers (rev 21-24) and
  -- the shared box / tracked / currency lists already moved to each character (rev 20, 22)
  local function tidy()
    local g, c = G(), cfg()
    g.bibRuleProbe = nil
    if c.charBankMoved then c.bankView, c.bankBoxes, c.bankTrack = nil, nil, nil end
    if c.currMoved then c.currencies = nil end
  end
  -- the ruleset is read once the game has settled after logging in
  S:On("PLAYER_ENTERING_WORLD", function() C_Timer.After(4, function() if S.db then pcall(tidy); if S:BiBIsOn() then pcall(meRec) end end end) end)

  -- added to BiB's window when it's built
  S.BiBOnBuild = function(w)
    -- your own name for the bags window
    local function applyTitle() w.title:SetText(S.BiBTitles().bags or "BiB") end
    applyTitle()
    S.BiBAddTitleEdit(w, function()
      S.BiBAskTitle(S.BiBTitles().bags or w.title:GetText(), function(t) S.BiBTitles().bags = t; applyTitle() end)
    end)
    -- guild bank: next to "Your bank" in the header
    w:HeaderButton("vault", "Guild bank", "See your guild bank from anywhere - BiB remembers it every time you open the guild vault.", function()
      if S.ShowBiBGuildBank then S:ShowBiBGuildBank() end
    end)
    -- key ring button on the bottom edge
    local kb = CreateFrame("Button", nil, w)
    kb:SetSize(18, 18); kb:SetPoint("BOTTOMLEFT", 9, 5)
    kb.icon = kb:CreateTexture(nil, "ARTWORK"); kb.icon:SetAllPoints(); kb.icon:SetTexture(KEY_ICON); kb.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    kb.hl = kb:CreateTexture(nil, "HIGHLIGHT"); kb.hl:SetAllPoints(); kb.hl:SetColorTexture(1, 1, 1, 0.2)
    kb:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      local keys = ownedKeys()
      local inBank = 0
      for _, e in ipairs(keys) do if e.bank > 0 then inBank = inBank + 1 end end
      GameTooltip:AddLine("Keys")
      GameTooltip:AddLine(#keys .. " key" .. (#keys == 1 and "" or "s") .. (inBank > 0 and (" (" .. inBank .. " in the bank)") or ""), 1, 1, 1)
      GameTooltip:AddLine("|cff888888Click to see them all|r")
      GameTooltip:Show()
    end)
    kb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    kb:SetScript("OnClick", function() S:ToggleBiBKeys() end)
    w.keyBtn = kb
    w.freeText:ClearAllPoints(); w.freeText:SetPoint("BOTTOMLEFT", 32, 8)
    -- currencies next to the gold
    local cb = CreateFrame("Button", nil, w)
    cb:SetHeight(18); cb:SetPoint("BOTTOMRIGHT", w.gold, "BOTTOMLEFT", -12, -3)
    cb.text = UI:Text(cb, "", "small", "RIGHT"); cb.text:SetPoint("RIGHT")
    cb:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    cb:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:AddLine("Currencies")
      local list = currencyList()
      for _, key in ipairs(tracked()) do
        local qty, icon, name = currencyNow(key, list)
        if name then GameTooltip:AddDoubleLine((icon and ("|T" .. icon .. ":14:14:0:0|t ") or "") .. name, BreakUpLargeNumbers and BreakUpLargeNumbers(qty) or qty, 1, 1, 1, 1, 1, 1) end
      end
      GameTooltip:AddLine("|cff888888Click: choose which currencies show here|r")
      GameTooltip:Show()
    end)
    cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    cb:SetScript("OnClick", function(self) currencyMenu(self) end)
    w.currBtn = cb
    w:HookScript("OnShow", function() updateCurrencies() end)
    updateCurrencies()
    -- characters button in the bottom-right corner (other characters' bags), gold just left of it
    local ch = CreateFrame("Button", nil, w)
    ch:SetSize(18, 18); ch:SetPoint("BOTTOMRIGHT", -22, 5)
    ch:SetFrameLevel(w:GetFrameLevel() + 6)
    ch.icon = UI:Icon(ch, "roster", 14); ch.icon:SetPoint("CENTER")
    UI:Skin(ch, function(self, th) self.icon:SetVertexColor(th.muted[1], th.muted[2], th.muted[3], 1) end)
    ch:SetScript("OnEnter", function(self)
      local g = UI:Theme().gold; self.icon:SetVertexColor(g[1], g[2], g[3], 1)
      GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine("Your other characters")
      GameTooltip:AddLine("|cff888888Click to open one's bags as they were the last time you played them.|r", nil, nil, nil, true); GameTooltip:Show()
    end)
    ch:SetScript("OnLeave", function(self) local m = UI:Theme().muted; self.icon:SetVertexColor(m[1], m[2], m[3], 1); GameTooltip:Hide() end)
    ch:SetScript("OnClick", function(self) charsMenu(self) end)
    w.charsBtn = ch
    w.gold:ClearAllPoints(); w.gold:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", -46, 8)
    -- hover the gold: every character's gold on this ruleset
    local gh = CreateFrame("Frame", nil, w)
    gh:SetPoint("TOPLEFT", w.gold, "TOPLEFT", -3, 4); gh:SetPoint("BOTTOMRIGHT", w.gold, "BOTTOMRIGHT", 3, -4)
    gh:SetFrameLevel(w:GetFrameLevel() + 5)
    gh:EnableMouse(true)
    gh:SetScript("OnEnter", function(self) goldTip(self) end)
    gh:SetScript("OnLeave", function() GameTooltip:Hide() end)
    w.goldHit = gh
    -- resize from the bottom-right corner, like the bank (the columns follow the width)
    w:SetResizable(true)
    if w.SetResizeBounds then w:SetResizeBounds(200, 150, 1800, 1300) elseif w.SetMinResize then w:SetMinResize(200, 150) end
    local grip = CreateFrame("Button", nil, w)
    grip:SetSize(16, 16); grip:SetPoint("BOTTOMRIGHT", -3, 3)
    grip:SetFrameLevel(w:GetFrameLevel() + 35)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:RegisterForClicks("RightButtonUp")
    grip:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine("Drag to resize")
      GameTooltip:AddLine("|cff888888Right-click: fit the window to your bags again|r"); GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", function() GameTooltip:Hide() end)
    grip:SetScript("OnMouseDown", function(_, btn)
      if btn ~= "LeftButton" or cfg().lock or combat() then return end   -- slots can't be moved in combat
      w.sizing = true
      w:StartSizing("BOTTOMRIGHT")
    end)
    grip:SetScript("OnMouseUp", function()
      if not w.sizing then return end
      w:StopMovingOrSizing()
      w.sizing = false
      cfg().bagSize = { math.floor(w:GetWidth() + 0.5), math.floor(w:GetHeight() + 0.5) }
      S:RefreshBiB(true)
    end)
    grip:SetScript("OnClick", function() if combat() then return end cfg().bagSize = nil; S:RefreshBiB(true) end)
    w.grip = grip
    w:HookScript("OnSizeChanged", function()
      if w.sizing and not w.sizePending then
        w.sizePending = true
        C_Timer.After(0.05, function() w.sizePending = false; if w:IsShown() and not combat() then S:RefreshBiB(true) end end)
      end
    end)
  end
end
extrasSection()


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
