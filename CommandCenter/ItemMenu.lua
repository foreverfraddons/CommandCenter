-- ItemMenu: right-click an item (with your chosen modifier key) for a menu:
--   bags: open all, preview, copy link, Wowhead link, where it comes from, link in chat,
--         mark as unwanted (deleted automatically whenever it lands in your bags), delete
--   chat: the same minus the bag things
-- Bag clicks are caught through the game's own modified-click handler, so the item
-- isn't used when you open the menu (unless you pick "no modifier").
local _, S = ...
if S.ModuleRev then S:ModuleRev("ItemMenu", 3) end
local UI = S.UI

local function G() return S.db.global end
local function combat() return InCombatLockdown and InCombatLockdown() end
local CC = C_Container

local MODS = {
  { value = "alt", text = "Alt" }, { value = "ctrl", text = "Ctrl" }, { value = "shift", text = "Shift" },
  { value = "altctrl", text = "Alt + Ctrl" }, { value = "altshift", text = "Alt + Shift" },
  { value = "ctrlshift", text = "Ctrl + Shift" }, { value = "none", text = "No key (right-click only; the item is still used)" },
}
local BUTTONS = { { value = "right", text = "Right-click" }, { value = "left", text = "Left-click" }, { value = "either", text = "Left or right click" } }
-- Command Center is for WoW Forever only: links always go to Wowhead's Forever database
local WOWHEAD = "https://www.wowhead.com/forever/item="

local function cfg()
  local g = G()
  g.itemMenu = type(g.itemMenu) == "table" and g.itemMenu or {}
  local c = g.itemMenu
  if c.on == nil then c.on = true end
  c.mod = c.mod or "alt"
  c.button = c.button or "right"
  if not c.chatModV2 then c.chatMod = true; c.chatModV2 = true end   -- chat links need the key (Alt) too
  if c.autoDelete == nil then c.autoDelete = true end
  if c.tellDelete == nil then c.tellDelete = true end
  c.unwanted = type(c.unwanted) == "table" and c.unwanted or {}
  return c
end
S.ItemMenuCfg = cfg
function S:ItemMenuIsOn() return S.db and cfg().on ~= false end

-- was it the mouse button you picked? (b = "LeftButton" / "RightButton")
local function buttonOK(b)
  local want = cfg().button or "right"
  if want == "either" then return b == "LeftButton" or b == "RightButton" end
  return b == (want == "left" and "LeftButton" or "RightButton")
end
local function modsMatch(m)
  local a, c, s = IsAltKeyDown(), IsControlKeyDown(), IsShiftKeyDown()
  if m == "none" then return not a and not c and not s end
  return (a == (m:find("alt") ~= nil)) and (c == (m:find("ctrl") ~= nil)) and (s == (m:find("shift") ~= nil))
end

---------------------------------------------------------------------------
-- Item helpers
---------------------------------------------------------------------------
local function idFromLink(link)
  if type(link) ~= "string" then return nil end
  return tonumber(link:match("item:(%d+)"))
end
local function itemInfo(x)
  local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  local ok, name, link, quality, ilvl, req, typ, sub, maxStack, equipLoc, icon, price = pcall(f, x)
  if ok then return name, link, quality, equipLoc, icon, price end
end
local function slotInfo(bag, slot)
  local ok, i = pcall(function() return CC and CC.GetContainerItemInfo and CC.GetContainerItemInfo(bag, slot) end)
  if ok and type(i) == "table" then return i end
end
local function bagList()
  local out = {}
  for b = 0, (NUM_BAG_SLOTS or 4) do out[#out + 1] = b end
  local rb = Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag
  if rb then out[#out + 1] = rb end
  return out
end
local function numSlots(bag)
  local ok, n = pcall(function() return CC and CC.GetContainerNumSlots and CC.GetContainerNumSlots(bag) end)
  return ok and tonumber(n) or 0
end
-- every bag slot holding this item: { {bag, slot, count, loot}, ... }
local function slotsOf(id)
  local out = {}
  for _, bag in ipairs(bagList()) do
    for slot = 1, numSlots(bag) do
      local i = slotInfo(bag, slot)
      if i and i.itemID == id then out[#out + 1] = { bag = bag, slot = slot, count = i.stackCount or 1, loot = i.hasLoot } end
    end
  end
  return out
end
local function totalCount(id)
  local n = 0
  for _, s in ipairs(slotsOf(id)) do n = n + (s.count or 1) end
  return n
end
local function wowheadURL(id) return WOWHEAD .. tostring(id) end
local function dressable(link)
  if C_Item and C_Item.IsDressableItemByID then
    local ok, v = pcall(C_Item.IsDressableItemByID, idFromLink(link)); if ok then return v end
  end
  local _, _, _, equipLoc = itemInfo(link)
  return equipLoc and equipLoc ~= "" and equipLoc ~= "INVTYPE_BAG" and equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE"
end

---------------------------------------------------------------------------
-- Open all: a click button that opens one stack per click
---------------------------------------------------------------------------
-- Using a bag item is protected: an addon calling UseContainerItem itself gets
-- "blocked" (BugGrabber blames Command Center). So "Open all" shows a small secure
-- button (the game's own secure "use item" action, set to that bag slot): each click
-- opens the next one, and the button moves on to the next stack after the loot closes.
local openBtn, openID
local function nextLootSlot(id)
  for _, sl in ipairs(slotsOf(id)) do
    if sl.loot then
      local i = slotInfo(sl.bag, sl.slot)
      if i and not i.isLocked then return sl end
    end
  end
end
local function openLeft(id)
  local n = 0
  for _, sl in ipairs(slotsOf(id)) do if sl.loot then local i = slotInfo(sl.bag, sl.slot); n = n + ((i and i.stackCount) or 1) end end
  return n
end
local function refreshOpen()
  if not openBtn or not openID then return end
  if combat() then openBtn:Hide() return end            -- secure buttons can't change in a fight
  local sl = nextLootSlot(openID)
  if not sl then
    if openBtn.opened and openBtn.opened > 0 then S:Print("Opened " .. openBtn.opened .. ".") end
    openBtn:Hide(); openID = nil
    return
  end
  openBtn:SetAttribute("type", "item")
  openBtn:SetAttribute("item", sl.bag .. " " .. sl.slot)
  local name, _, _, _, icon = itemInfo(openID)
  openBtn.icon:SetTexture(icon or 134400)
  openBtn.text:SetText("|cff55ff55Open:|r " .. (name or ("item " .. openID)) .. "  |cff888888(" .. openLeft(openID) .. " left - click)|r")
  openBtn:Show()
end
local function getOpenBtn()
  if openBtn then return openBtn end
  local b = CreateFrame("Button", "CC_OpenAllButton", UIParent, "SecureActionButtonTemplate" .. (BackdropTemplateMixin and ", BackdropTemplate" or ""))
  b:SetSize(260, 34); b:SetFrameStrata("HIGH"); b:SetClampedToScreen(true)
  b:RegisterForClicks("LeftButtonUp", "LeftButtonDown")
  UI:Skin(b, function(self, th) UI.Flat(self, th.bg, 0.95, { 0.3, 0.9, 0.4 }, 1, 1) end)
  b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(26, 26); b.icon:SetPoint("LEFT", 4, 0); b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  b.text = UI:Text(b, "", "normal"); b.text:SetPoint("LEFT", b.icon, "RIGHT", 8, 0); b.text:SetPoint("RIGHT", -24, 0); b.text:SetWordWrap(false)
  -- a plain close button on top (not part of the secure button's click)
  local x = CreateFrame("Button", nil, b); x:SetSize(18, 18); x:SetPoint("RIGHT", -3, 0)
  x.t = UI:Text(x, "|cffaaaaaax|r", "normal"); x.t:SetPoint("CENTER")
  x:SetScript("OnClick", function() if not combat() then b:Hide() end; openID = nil end)
  b:SetPoint("TOP", 0, -220)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("Open all", 0.3, 1, 0.4)
    GameTooltip:AddLine("Click to open one. The game only lets addons open items from your own click, so it's one per click.", 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  openBtn = b
  return b
end
local function openAll(id)
  if combat() then S:Print("Can't open items in a fight - try again after.") return end
  openID = id
  local b = getOpenBtn()
  b.opened = 0
  -- put it under the mouse, so the first click is right there
  local scale = b:GetEffectiveScale() or 1
  local cx, cy = GetCursorPosition()
  b:ClearAllPoints(); b:SetPoint("CENTER", UIParent, "BOTTOMLEFT", (cx or 0) / scale, (cy or 0) / scale)
  refreshOpen()
end
S:On("LOOT_OPENED", function() if openID and openBtn then openBtn.opened = (openBtn.opened or 0) + 1 end end)
S:On("LOOT_CLOSED", function() if openID then C_Timer.After(0.4, refreshOpen) end end)
S:On("BAG_UPDATE_DELAYED", function() if openID then C_Timer.After(0.2, refreshOpen) end end)
S:On("PLAYER_REGEN_DISABLED", function() if openBtn then openBtn:Hide() end end)
S:On("PLAYER_REGEN_ENABLED", function() if openID then C_Timer.After(0.5, refreshOpen) end end)

---------------------------------------------------------------------------
-- Delete / unwanted
---------------------------------------------------------------------------
-- returns true when deleted, "cursor" when the game wouldn't let us (it's left on your
-- cursor so you can drop it on the ground and confirm the game's own delete), or false
local function deleteSlot(bag, slot)
  if combat() then return false end
  if CursorHasItem and CursorHasItem() then ClearCursor() end
  pcall(CC.PickupContainerItem, bag, slot)
  if not (CursorHasItem and CursorHasItem()) then return false end
  local unmute = S.MuteBlockedReports and S.MuteBlockedReports()
  pcall(DeleteCursorItem)
  if unmute then C_Timer.After(1.5, unmute) end
  if not CursorHasItem() then return true end
  -- hand it over to the game's own delete
  local tip = "Click the ground (outside your bags) to delete it - the game asks to confirm."
  if UIErrorsFrame then UIErrorsFrame:AddMessage(tip, 1, 0.82, 0) end
  S:Print("The game wants to confirm this one - it's on your cursor: " .. tip)
  return "cursor"
end
-- Delete queue ("Delete multiple" in the menu, or Ctrl+Alt+Left-click an item in your
-- bags): queued items go on the unwanted button, first in line; each click deletes one
local delQueue = {}
local function queueIndex(bag, slot)
  for k, q in ipairs(delQueue) do if q.bag == bag and q.slot == slot then return k end end
end
function S.ItemMenuIsQueued(bag, slot) return queueIndex(bag, slot) ~= nil end
function S.ItemMenuQueueDelete(bag, slot, on)
  local i = slotInfo(bag, slot)
  if not i or not i.itemID then return end
  local k = queueIndex(bag, slot)
  if on == nil then on = not k end
  local nm = i.hyperlink or ("item " .. i.itemID)
  if on and not k then
    if combat() then S:Print("Can't delete items in a fight - try again after.") return end
    delQueue[#delQueue + 1] = { bag = bag, slot = slot, id = i.itemID, link = i.hyperlink }
    S:Print("Added " .. nm .. " to the delete queue (" .. #delQueue .. ") - click the red button to delete.")
  elseif not on and k then
    table.remove(delQueue, k)
    S:Print("Took " .. nm .. " out of the delete queue.")
  end
  if S.ItemMenuSweep then S.ItemMenuSweep(true) end
end
local function askDelete(id, link, bag, slot) S.ItemMenuQueueDelete(bag, slot) end
function S.ItemMenuSetUnwanted(id, on)
  if not id then return end
  cfg().unwanted[id] = on and true or nil
  if S.RefreshItemMenu then S:RefreshItemMenu() end
end
local function markUnwanted(id, link)
  local _, _, q = itemInfo(id)
  local strong = (q or 0) >= 3
  UI:Confirm((strong and "|cffff7777Careful - this is a good item.|r\n" or "") .. "Mark " .. (link or "this item") .. " as unwanted?\n\n|cff888888Whenever one lands in your bags, a button pops up - each click deletes one (the game only allows one delete per click). Undo it in ItemMenu's settings.|r", function()
    S.ItemMenuSetUnwanted(id, true)
    if S.ItemMenuSweep then C_Timer.After(0.2, S.ItemMenuSweep) end
  end, "Mark unwanted")
end
-- Unwanted items: the game only lets addons delete an item straight from a click
-- (doing it on its own is "blocked"), so when one lands in your bags a small button
-- pops up - one click deletes every unwanted item you're carrying.
local function unwantedInBags()
  local c = cfg()
  local out = {}
  -- the delete queue goes first (an entry is dropped if that slot no longer holds the item)
  local queued = {}
  for k = #delQueue, 1, -1 do
    local q = delQueue[k]
    local i = slotInfo(q.bag, q.slot)
    if not (i and i.itemID == q.id) then table.remove(delQueue, k) end
  end
  for _, q in ipairs(delQueue) do
    local i = slotInfo(q.bag, q.slot)
    out[#out + 1] = { bag = q.bag, slot = q.slot, link = i.hyperlink or q.link, id = i.itemID, count = i.stackCount or 1, locked = i.isLocked, manual = true }
    queued[q.bag .. ":" .. q.slot] = true
  end
  local auto = c.on ~= false and c.autoDelete ~= false
  for _, bag in ipairs(auto and bagList() or {}) do
    for slot = 1, numSlots(bag) do
      local i = slotInfo(bag, slot)
      if i and i.itemID and c.unwanted[i.itemID] and not queued[bag .. ":" .. slot] then out[#out + 1] = { bag = bag, slot = slot, link = i.hyperlink, id = i.itemID, count = i.stackCount or 1, locked = i.isLocked } end
    end
  end
  return out
end
local trashBtn
local dismissedSig
-- one stack per click: the game allows one delete per click, so each click deletes
-- the next unwanted item and the button moves on to the one after
local function deleteAllUnwanted()
  if combat() then S:Print("Can't delete items in a fight - try again after.") return end
  local c = cfg()
  for _, it in ipairs(unwantedInBags()) do
    if not it.locked then
      local r = deleteSlot(it.bag, it.slot)
      if it.manual then local k = queueIndex(it.bag, it.slot); if k then table.remove(delQueue, k) end end
      if r == "cursor" then
        -- (the game asks for this one; it's on your cursor)
      elseif r then
        if it.manual then S:Print("Deleted " .. (it.link or ("item " .. it.id)) .. (it.count > 1 and (" x" .. it.count) or "") .. ".")
        elseif c.tellDelete then S:Print("Deleted unwanted " .. (it.link or ("item " .. it.id)) .. (it.count > 1 and (" x" .. it.count) or "") .. ".") end
      else
        S:Print("Couldn't delete it right now (something on your cursor, or the item is busy).")
      end
      break
    end
  end
  C_Timer.After(0.3, function() if S.ItemMenuSweep then S.ItemMenuSweep() end end)
end
local function getTrashBtn()
  if trashBtn then return trashBtn end
  local b = CreateFrame("Button", "CC_UnwantedButton", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  b:SetSize(250, 34); b:SetFrameStrata("HIGH")
  local at = cfg().trashAt
  if type(at) == "table" then b:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", at[1], at[2]) else b:SetPoint("TOP", 0, -180) end
  UI:Skin(b, function(self, th) UI.Flat(self, th.bg, 0.95, { 1, 0.3, 0.25 }, 1, 1) end)
  b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(26, 26); b.icon:SetPoint("LEFT", 4, 0); b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  b.text = UI:Text(b, "", "normal"); b.text:SetPoint("LEFT", b.icon, "RIGHT", 8, 0); b.text:SetPoint("RIGHT", -6, 0); b.text:SetWordWrap(false)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:SetMovable(true); b:SetClampedToScreen(true); b:RegisterForDrag("LeftButton")
  b:SetScript("OnDragStart", function(self) if IsShiftKeyDown() then self:StartMoving() end end)
  b:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    cfg().trashAt = { math.floor((self:GetLeft() or 0) + 0.5), math.floor((self:GetTop() or 0) + 0.5) }
  end)
  b:SetScript("OnClick", function(self, button)
    if button == "RightButton" then
      if #delQueue > 0 then wipe(delQueue); S:Print("Delete queue cleared."); C_Timer.After(0, function() S.ItemMenuSweep(true) end); self:Hide() return end
      dismissedSig = self.sig; self:Hide() return
    end
    deleteAllUnwanted()                      -- a real click: the game allows deleting now
  end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("Queue and Click", 1, 0.4, 0.3)
    for _, it in ipairs(unwantedInBags()) do GameTooltip:AddLine((it.link or ("item " .. it.id)) .. (it.count > 1 and (" x" .. it.count) or ""), 1, 1, 1) end
    GameTooltip:AddLine("Click: delete the first one (each click deletes the next).  Right-click: clear the delete queue / not now.  Shift-drag: move.  Add more: Ctrl+Alt+Left-click items in your bags.", 0.6, 0.6, 0.6, true)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b:SetScript("OnUpdate", function(self, el)
    self.t = (self.t or 0) + el
    self.icon:SetAlpha(0.65 + 0.35 * math.sin(self.t * 5))
  end)
  trashBtn = b
  return b
end
-- look for unwanted items and offer the button
function S.ItemMenuSweep(force)
  if not S.db then return end
  local c = cfg()
  local list = ((#delQueue > 0) or (c.on ~= false and c.autoDelete ~= false and next(c.unwanted))) and unwantedInBags() or {}
  if #list == 0 or combat() then if trashBtn then trashBtn:Hide() end return end
  if force then dismissedSig = nil end
  local sig = {}
  for _, it in ipairs(list) do sig[#sig + 1] = it.bag .. ":" .. it.slot .. ":" .. it.count end
  sig = table.concat(sig, ",")
  if sig == dismissedSig then return end
  local b = getTrashBtn()
  b.sig = sig
  local first = list[1]
  local _, _, _, _, icon = itemInfo(first.id)
  b.icon:SetTexture(icon or (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(first.id)) or 134400)
  local nm = first.link and first.link:match("%[(.-)%]") or ("item " .. first.id)
  b.text:SetText((first.manual and "|cffff7777Delete queue:|r " or "|cffff7777Delete unwanted:|r ") .. nm .. (first.count > 1 and (" x" .. first.count) or "") .. (#list > 1 and ("  |cff888888+" .. (#list - 1) .. " more|r") or ""))
  b:Show()
end
S:On("PLAYER_REGEN_DISABLED", function() if trashBtn then trashBtn:Hide() end end)
S:On("BAG_UPDATE_DELAYED", function() C_Timer.After(0.2, S.ItemMenuSweep) end)
S:On("PLAYER_REGEN_ENABLED", function() C_Timer.After(0.5, S.ItemMenuSweep) end)

---------------------------------------------------------------------------
-- Where does it come from? (Command Center's own Forever database + your recordings, plus Questie's when installed)
---------------------------------------------------------------------------
local function questie()
  if not QuestieLoader or not QuestieLoader.ImportModule then return nil end
  local ok, db = pcall(QuestieLoader.ImportModule, QuestieLoader, "QuestieDB")
  if ok and type(db) == "table" and db.QueryItemSingle then return db end
end
local function q1(db, fn, id, key)
  local ok, v = pcall(db[fn], id, key)
  if ok then return v end
end
-- everything we can find out about where an item comes from:
-- { { title, icon, rows = { { name, sub, kind, copy } } }, ... }
local function areaName(z)
  if not z or z == 0 then return nil end
  if type(z) == "string" and z:sub(1, 1) == "m" then
    local ok, info = pcall(C_Map.GetMapInfo, tonumber(z:sub(2)))
    return ok and info and info.name or nil
  end
  local ok, n = pcall(function() return C_Map and C_Map.GetAreaInfo and C_Map.GetAreaInfo(z) end)
  if ok and type(n) == "string" and n ~= "" then return n end
end
local IDB = S.IDB
local function pct(ch)
  if not ch then return nil end
  local p = ch / 100
  if p >= 10 then return string.format("%d%%", math.floor(p + 0.5)) end
  if p >= 1 then return string.format("%.1f%%", p) end
  return string.format("%.2f%%", p)
end
local function chanceText(e)
  local t = {}
  if e.chance then t[#t + 1] = "|cff55ff55" .. pct(e.chance) .. "|r" end
  if e.seen then t[#t + 1] = "|cff888888you saw " .. e.seen .. " in " .. e.of .. "|r" end
  return table.concat(t, " ")
end
local function lvText(lo, hi)
  if not lo or lo == 0 then return nil end
  if lo == -1 then return "Level ??" end
  return "Level " .. lo .. ((hi and hi ~= lo) and ("-" .. hi) or "")
end
local function npcRow(db, npc, kind, e)
  local own = IDB.NPC(npc)
  local nm = (own and own.name) or (db and q1(db, "QueryNPCSingle", npc, "name")) or ("NPC " .. tostring(npc))
  local lo, hi = own and own.minLv, own and own.maxLv
  if not lo and db then lo, hi = q1(db, "QueryNPCSingle", npc, "minLevel"), q1(db, "QueryNPCSingle", npc, "maxLevel") end
  local zone = IDB.ZoneOf("c", npc) or (db and areaName(q1(db, "QueryNPCSingle", npc, "zoneID")))
  local sub = {}
  if e then local c = chanceText(e); if c ~= "" then sub[#sub + 1] = c end end
  sub[#sub + 1] = lvText(lo, hi)
  if zone then sub[#sub + 1] = zone end
  return { name = nm, sub = table.concat(sub, "  -  "), copy = nm, kind = kind or "npc", id = npc, chance = e and e.chance, seen = e and e.seen, of = e and e.of }
end
-- merges Command Center's own database (shipped + your recordings) with Questie's when present
local function sourceData(id)
  local out = {}
  local db = questie()
  local own = IDB.Sources(id)
  local hasOwn = IDB.Available()
  if not db and not hasOwn then return out, false end
  -- list of ids from both, own first (own entries carry chances)
  local function merged(ownList, qList, getId)
    local res, seen = {}, {}
    for _, e in ipairs(ownList or {}) do local k = getId and getId(e) or e; if not seen[k] then seen[k] = true; res[#res + 1] = e end end
    if type(qList) == "table" then for _, k in ipairs(qList) do if not seen[k] then seen[k] = true; res[#res + 1] = getId and { id = k } or k end end end
    return res
  end
  local function section(title, icon, list, make, max)
    if type(list) ~= "table" or #list == 0 then return end
    local sec = { title = title, icon = icon, rows = {}, total = #list }
    for k = 1, math.min(max or 25, #list) do sec.rows[#sec.rows + 1] = make(list[k]) end
    out[#out + 1] = sec
  end
  local Qi = function(k) return db and q1(db, "QueryItemSingle", id, k) end
  local idOf = function(e) return e.id end
  section("Dropped by", "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01", merged(own.drops, Qi("npcDrops"), idOf), function(e) return npcRow(db, e.id, "npc", e) end)
  section("Skinned from", "Interface\\Icons\\INV_Misc_Pelt_Wolf_01", own.skins, function(e)
    local r = npcRow(db, e.id, "skin", e)
    return r
  end)
  if own.world then
    out[#out + 1] = { title = "World drop", icon = "Interface\\Icons\\INV_Misc_Map_01", total = 1, rows = { { name = "Can drop from many creatures", sub = (own.world > 0 and ("Around level " .. own.world .. " and up") or "Anywhere in the world"), kind = "info", copy = "World drop" } } }
  end
  section("Sold by", "Interface\\Icons\\INV_Misc_Coin_02", merged(own.vendors, Qi("vendors")), function(n)
    local r = npcRow(db, n, "vendor"); r.item = id
    local price, _, limited, costs = IDB.VendorPrice(n, id)
    local extra = {}
    if price and price > 0 and GetCoinTextureString then extra[#extra + 1] = GetCoinTextureString(price) end
    if costs then extra[#extra + 1] = "|cffffd100special cost|r" end
    if limited then extra[#extra + 1] = "|cffff9933limited stock|r" end
    if #extra > 0 then r.sub = table.concat(extra, " ") .. (r.sub ~= "" and ("  -  " .. r.sub) or "") end
    return r
  end)
  section("Found in", "Interface\\Icons\\INV_Box_01", merged(own.objects, Qi("objectDrops"), idOf), function(e)
    local o = e.id
    local ownO = IDB.Object(o)
    local nm = (ownO and ownO.name) or (db and q1(db, "QueryObjectSingle", o, "name")) or ("Object " .. tostring(o))
    local sub = {}
    local c = chanceText(e); if c ~= "" then sub[#sub + 1] = c end
    local z = IDB.ZoneOf("o", o) or (db and areaName(q1(db, "QueryObjectSingle", o, "zoneID")))
    if z then sub[#sub + 1] = z end
    return { name = nm, sub = table.concat(sub, "  -  "), copy = nm, kind = "object", id = o, chance = e.chance, seen = e.seen, of = e.of }
  end)
  section("Inside", "Interface\\Icons\\INV_Misc_Bag_10", merged(own.containers, Qi("itemDrops"), idOf), function(e)
    local it = e.id
    local nm = itemInfo(it) or IDB.ItemName(it) or (db and q1(db, "QueryItemSingle", it, "name")) or ("Item " .. tostring(it))
    local c = chanceText(e)
    return { name = nm, sub = (c ~= "" and (c .. "  -  ") or "") .. "Open it to find this", copy = nm, item = it, kind = "item", id = it, chance = e.chance }
  end)
  section("Quest reward", "Interface\\GossipFrame\\AvailableQuestIcon", merged(own.rewards, Qi("questRewards")), function(qid)
    local oq = IDB.Quest(qid)
    local nm = (oq and oq.name) or (db and q1(db, "QueryQuestSingle", qid, "name")) or ("Quest " .. tostring(qid))
    local lvl = (oq and oq.level) or (db and q1(db, "QueryQuestSingle", qid, "questLevel"))
    return { name = nm, sub = (lvl and lvl > 0) and ("Level " .. lvl .. " quest") or "Quest", copy = nm, kind = "quest", id = qid }
  end)
  local sq = own.start or Qi("startQuest")
  section("Starts a quest", "Interface\\GossipFrame\\ActiveQuestIcon", (sq and sq ~= 0) and { sq } or nil, function(qid)
    local oq = IDB.Quest(qid)
    local nm = (oq and oq.name) or (db and q1(db, "QueryQuestSingle", qid, "name")) or ("Quest " .. tostring(qid))
    return { name = nm, sub = "Right-click the item to start it", copy = nm, kind = "quest", id = qid }
  end)
  return out, true
end

---------------------------------------------------------------------------
-- One source in detail: where, levels, map pins, Wowhead
---------------------------------------------------------------------------
local spanel, spRows, spHeads            -- the source list panel (built further down)
local WH = "https://www.wowhead.com/forever/"
local WH_KIND = { npc = "npc=", vendor = "npc=", skin = "npc=", object = "object=", quest = "quest=", item = "item=" }
-- Questie's zone numbers -> the map the game uses for pins
local function uiMapFor(areaId)
  if not areaId then return nil end
  if type(areaId) == "string" and areaId:sub(1, 1) == "m" then return tonumber(areaId:sub(2)) end
  if QuestieLoader and QuestieLoader.ImportModule then
    local ok, z = pcall(QuestieLoader.ImportModule, QuestieLoader, "ZoneDB")
    if ok and type(z) == "table" and z.GetUiMapIdByAreaId then
      local ok2, m = pcall(z.GetUiMapIdByAreaId, z, areaId)
      if ok2 and tonumber(m) then return tonumber(m) end
    end
  end
  -- by name: look through the world's zones for one with the same name
  local nm = areaName(areaId)
  if nm and C_Map and C_Map.GetMapChildrenInfo then
    for _, root in ipairs({ 946, 947, 1414, 1415, 12, 13 }) do
      local ok, kids = pcall(C_Map.GetMapChildrenInfo, root, nil, true)
      if ok and type(kids) == "table" then
        for _, k in ipairs(kids) do if k.name == nm then return k.mapID end end
      end
    end
  end
end
local function playerSpot()
  local ok, m = pcall(function() return C_Map.GetBestMapForUnit("player") end)
  if not ok or not m then return nil end
  local ok2, pos = pcall(C_Map.GetPlayerMapPosition, m, "player")
  if ok2 and pos and pos.GetXY then local x, y = pos:GetXY(); return m, x * 100, y * 100 end
  return m
end
-- put a pin on the map (and the arrow on screen) at x, y (0-100) in that zone
function S.ItemMenuPin(areaId, x, y, label)
  local map = uiMapFor(areaId)
  if not map or not (C_Map and C_Map.SetUserWaypoint and UiMapPoint) then
    S:Print("Couldn't find that place on the game's map" .. (areaName(areaId) and (" (" .. areaName(areaId) .. ")") or "") .. ".")
    return false
  end
  if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(map) then
    S:Print("The game doesn't allow map pins in " .. (areaName(areaId) or "that zone") .. ".")
    return false
  end
  local ok = pcall(function()
    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(map, x / 100, y / 100))
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
  end)
  if ok then S:Print(string.format("Pinned |cffffd100%s|r on your map: %s %.1f, %.1f.", label or "it", areaName(areaId) or "", x, y)) end
  return ok
end
function S.ItemMenuShowMap(areaId)
  local map = uiMapFor(areaId)
  if map and OpenWorldMap then pcall(OpenWorldMap, map) elseif ToggleWorldMap then ToggleWorldMap() end
end
-- spawns: { [areaId] = { {x, y}, ... } } -> sorted list of zones, the best spot first
local function spawnZones(spawns)
  local out = {}
  if type(spawns) ~= "table" then return out end
  local pm, px, py = playerSpot()
  for area, pts in pairs(spawns) do
    if type(pts) == "table" and #pts > 0 then
      local best, bestD = nil, nil
      for _, pt in ipairs(pts) do
        if type(pt) == "table" and tonumber(pt[1]) and pt[1] >= 0 then
          local d = 0
          if px and pm and uiMapFor(area) == pm then d = (pt[1] - px) ^ 2 + (pt[2] - py) ^ 2 end
          if not best or d < bestD then best, bestD = pt, d end
        end
      end
      if best then out[#out + 1] = { area = area, x = best[1], y = best[2], count = #pts, here = px and pm and uiMapFor(area) == pm } end
    end
  end
  table.sort(out, function(a, b) if (a.here and 1 or 0) ~= (b.here and 1 or 0) then return a.here end return a.count > b.count end)
  return out
end

local dpanel, dLines, dLocs = nil, {}, {}
local function dLine(i)
  local l = dLines[i]
  if l then return l end
  l = CreateFrame("Frame", nil, dpanel.child); l:SetSize(dpanel.child:GetWidth(), 18)
  l.k = UI:Text(l, "", "small"); l.k:SetPoint("LEFT", 2, 0); l.k:SetWidth(110); l.k:SetJustifyH("LEFT")
  l.v = UI:Text(l, "", "normal"); l.v:SetPoint("LEFT", 116, 0); l.v:SetPoint("RIGHT", -4, 0); l.v:SetJustifyH("LEFT"); l.v:SetWordWrap(true)
  dLines[i] = l
  return l
end
local function dLoc(i)
  local r = dLocs[i]
  if r then return r end
  r = CreateFrame("Frame", nil, dpanel.child); r:SetSize(dpanel.child:GetWidth(), 26)
  r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints(); r.bg:SetColorTexture(1, 1, 1, 0.05)
  r.text = UI:Text(r, "", "normal"); r.text:SetPoint("LEFT", 6, 0); r.text:SetPoint("RIGHT", -120, 0); r.text:SetWordWrap(false)
  r.pin = UI:Button(r, "Pin", 50, 20, function(self) local d = self:GetParent().loc; if d then S.ItemMenuPin(d.area, d.x, d.y, dpanel.title:GetText()) end end,
    "Put a pin on your map here (and the arrow on screen).")
  r.pin:SetPoint("RIGHT", -60, 0)
  r.map = UI:Button(r, "Map", 50, 20, function(self) local d = self:GetParent().loc; if d then S.ItemMenuPin(d.area, d.x, d.y, dpanel.title:GetText()); S.ItemMenuShowMap(d.area) end end,
    "Pin it and open the map there.")
  r.map:SetPoint("RIGHT", -4, 0)
  dLocs[i] = r
  return r
end
function S.ItemMenuShowDetail(row)
  if not row then return end
  if not dpanel then
    dpanel = UI:Window("CC_ItemSourceDetail", "Details", 420, 520)
    dpanel:SetFrameStrata("DIALOG")
    dpanel.title = UI:Text(dpanel, "", "title"); dpanel.title:SetPoint("TOPLEFT", 18, -42); dpanel.title:SetPoint("RIGHT", -16, 0); dpanel.title:SetWordWrap(false)
    dpanel.kind = UI:Text(dpanel, "", "small"); dpanel.kind:SetPoint("TOPLEFT", dpanel.title, "BOTTOMLEFT", 0, -4)
    dpanel.sf, dpanel.child = UI:Scroll(dpanel, 400, 370)
    dpanel.sf:SetPoint("TOPLEFT", 10, -84)
    dpanel.wh = UI:Button(dpanel, "Wowhead link", 120, 24, function()
      if dpanel.row and UI.CopyBox then UI:CopyBox("Wowhead link - copy it (Ctrl+C) and open it in your browser", WH .. (WH_KIND[dpanel.row.kind] or "item=") .. tostring(dpanel.row.id)) end
    end)
    dpanel.wh:SetPoint("BOTTOMLEFT", 16, 14)
    dpanel.copy = UI:Button(dpanel, "Copy name", 96, 24, function() if dpanel.row and UI.CopyBox then UI:CopyBox("Copy it (Ctrl+C)", dpanel.row.name) end end)
    dpanel.copy:SetPoint("LEFT", dpanel.wh, "RIGHT", 6, 0)
    dpanel.src = UI:Button(dpanel, "Where it comes from", 150, 24, function() if dpanel.row and dpanel.row.kind == "item" then S.ItemMenuShowSource(dpanel.row.id) end end)
    dpanel.src:SetPoint("LEFT", dpanel.copy, "RIGHT", 6, 0)
  end
  dpanel.row = row
  -- sit next to the source list
  dpanel:ClearAllPoints()
  if spanel and spanel:IsShown() then
    if (spanel:GetRight() or 0) + 430 < (UIParent:GetWidth() or 1920) then dpanel:SetPoint("TOPLEFT", spanel, "TOPRIGHT", 6, 0)
    else dpanel:SetPoint("TOPRIGHT", spanel, "TOPLEFT", -6, 0) end
  else dpanel:SetPoint("CENTER") end
  local db = questie()
  local function Q(fn, k) return db and q1(db, fn, row.id, k) end
  local KINDS = { npc = "Creature - drops the item", skin = "Creature - skin it for the item", vendor = "Vendor - sells the item", object = "Object - the item is inside", quest = "Quest - gives the item", item = "Item - open it to find the item" }
  dpanel.title:SetText(row.name or "?")
  dpanel.kind:SetText("|cffaaaaaa" .. (KINDS[row.kind] or "") .. "|r")
  dpanel.src:SetShown(row.kind == "item")
  local lines, spawns = {}, nil
  local function add(k, v) if v and v ~= "" then lines[#lines + 1] = { k, v } end end
  -- map spots from both databases: own ones are keyed "m<uiMap>", Questie's by zone number
  local function allSpawns(kind, id, qs)
    local t = {}
    for k, v in pairs((IDB.Spawns(kind, id))) do t[k] = v end
    if type(qs) == "table" then for k, v in pairs(qs) do if not t["m" .. tostring(uiMapFor(k) or "")] then t[k] = v end end end
    return t
  end
  local RANKS = { [1] = "|cffffd100Elite|r", [2] = "|cffff9933Rare elite|r", [3] = "|cffff3333Boss|r", [4] = "|cffcccccc Rare|r" }
  if row.kind == "npc" or row.kind == "vendor" or row.kind == "skin" then
    local own = IDB.NPC(row.id) or {}
    local lo, hi = own.minLv, own.maxLv
    if not lo then lo, hi = Q("QueryNPCSingle", "minLevel"), Q("QueryNPCSingle", "maxLevel") end
    add("Level", lo == -1 and "??" or (lo and lo > 0 and (lo .. ((hi and hi ~= lo) and (" - " .. hi) or ""))) or nil)
    add("Type", RANKS[own.rank or Q("QueryNPCSingle", "rank") or 0])
    add("Title", own.sub or Q("QueryNPCSingle", "subName"))
    add("Zone", IDB.ZoneOf("c", row.id) or areaName(Q("QueryNPCSingle", "zoneID")))
    local fr = Q("QueryNPCSingle", "friendlyToFaction")
    add("Friendly to", fr == "AH" and "Alliance and Horde" or fr == "A" and "|cff3399ffAlliance|r" or fr == "H" and "|cffff3333Horde|r" or nil)
    add("Health", (function() local h = Q("QueryNPCSingle", "minLevelHealth"); return h and h > 0 and tostring(h) end)())
    if row.kind == "npc" then
      if row.chance or row.seen then
        add("Drop rate", (row.chance and ("|cff55ff55" .. pct(row.chance) .. "|r") or "") ..
          (row.seen and ("  |cff888888(you looted it " .. row.seen .. " times from " .. row.of .. " corpses)|r") or ""))
      else
        add("Drop rate", "|cff888888Not known yet - it fills in as you (and others) loot it.|r")
      end
    end
    if row.kind == "skin" then
      add("Skinning", row.chance and ("|cff55ff55" .. pct(row.chance) .. "|r of skinned corpses give it") or nil)
    end
    if row.kind ~= "vendor" then
      -- money and skinning from Drop Tables (real WoW Forever counts)
      local avg, lo2, hi2, kills = IDB.Gold and IDB.Gold(row.id)
      if avg and avg > 0 and GetCoinTextureString then
        local range = (lo2 and hi2) and ("  |cff888888(" .. GetCoinTextureString(lo2) .. " - " .. GetCoinTextureString(hi2) .. ")|r") or ""
        add("Money", GetCoinTextureString(avg) .. " per kill" .. range .. ((kills and kills > 0) and ("  |cff888888" .. kills .. " kills counted|r") or ""))
      end
      if row.kind == "npc" and IDB.SkinsOf then
        local sk, names = IDB.SkinsOf(row.id), {}
        for k = 1, math.min(4, #sk) do
          names[#names + 1] = (itemInfo(sk[k].item) or IDB.ItemName(sk[k].item) or ("Item " .. sk[k].item)) .. " |cff55ff55" .. pct(sk[k].chance) .. "|r"
        end
        if #names > 0 then add("Skinning", table.concat(names, ", ")) end
      end
    end
    if row.kind == "vendor" and row.item then
      local price, stack, limited, costs = IDB.VendorPrice(row.id, row.item)
      if price and price > 0 and GetCoinTextureString then add("Price", GetCoinTextureString(price) .. ((stack and stack > 1) and (" for " .. stack) or "")) end
      if costs then add("Also costs", costs) end
      if limited then add("Stock", "Limited (" .. limited .. " when you saw it)") end
    end
    spawns = allSpawns("c", row.id, Q("QueryNPCSingle", "spawns"))
  elseif row.kind == "object" then
    add("Zone", IDB.ZoneOf("o", row.id) or areaName(Q("QueryObjectSingle", "zoneID")))
    if row.chance then add("Chance inside", "|cff55ff55" .. pct(row.chance) .. "|r" .. (row.seen and ("  |cff888888(found " .. row.seen .. " times in " .. row.of .. " opened)|r") or "")) end
    spawns = allSpawns("o", row.id, Q("QueryObjectSingle", "spawns"))
  elseif row.kind == "quest" then
    local oq = IDB.Quest(row.id) or {}
    local lvl, req = oq.level or Q("QueryQuestSingle", "questLevel"), oq.minLevel or Q("QueryQuestSingle", "requiredLevel")
    if lvl and lvl > 0 then add("Quest level", tostring(lvl)) end
    if req and req > 0 then add("Needs level", tostring(req)) end
    local zone = Q("QueryQuestSingle", "zoneOrSort")
    if zone and zone > 0 then add("Zone", areaName(zone)) end
    local obj = Q("QueryQuestSingle", "objectivesText")
    if type(obj) == "table" then obj = table.concat(obj, " ") end
    if type(obj) == "string" and obj ~= "" then add("Objective", obj) end
    -- who gives it: their place is where to go
    local gk, gid = nil, nil
    for _, w in ipairs(oq.givers or {}) do gk, gid = IDB.ParseWho(w); if gid then break end end
    if gid then
      local nm = gk == "c" and (IDB.NPC(gid) or {}).name or gk == "o" and (IDB.Object(gid) or {}).name
      add("Given by", nm or (db and gk == "c" and q1(db, "QueryNPCSingle", gid, "name")))
      spawns = allSpawns(gk, gid, db and gk == "c" and q1(db, "QueryNPCSingle", gid, "spawns"))
    else
      local by = Q("QueryQuestSingle", "startedBy")
      local giverNPC = type(by) == "table" and type(by[1]) == "table" and by[1][1]
      if giverNPC then
        add("Given by", (IDB.NPC(giverNPC) or {}).name or (db and q1(db, "QueryNPCSingle", giverNPC, "name")))
        spawns = allSpawns("c", giverNPC, db and q1(db, "QueryNPCSingle", giverNPC, "spawns"))
      end
    end
  elseif row.kind == "item" then
    local _, l2 = itemInfo(row.id)
    add("Item", l2 or row.name)
    if row.chance then add("Chance", "|cff55ff55" .. pct(row.chance) .. "|r") end
    add("Find it", "Click \"Where it comes from\" below")
  elseif row.kind == "info" then
    add("About", row.sub)
  end
  -- lay it out
  for _, l in ipairs(dLines) do l:Hide() end
  for _, l in ipairs(dLocs) do l:Hide() end
  local y, w = 0, dpanel.child:GetWidth()
  for i, kv in ipairs(lines) do
    local l = dLine(i); l:SetWidth(w)
    l:ClearAllPoints(); l:SetPoint("TOPLEFT", 0, -y)
    l.k:SetText("|cffffd100" .. kv[1] .. "|r"); l.v:SetText(kv[2])
    local h = math.max(18, (l.v:GetStringHeight() or 14) + 4); l:SetHeight(h)
    l:Show(); y = y + h + 2
  end
  local zones = spawnZones(spawns)
  if not dpanel.locHead then
    dpanel.locHead = UI:Text(dpanel.child, "", "large")
    dpanel.noLoc = UI:Text(dpanel.child, "", "small")
  end
  y = y + 10
  dpanel.locHead:ClearAllPoints(); dpanel.locHead:SetPoint("TOPLEFT", 2, -y); y = y + 24
  dpanel.locHead:SetText(row.kind == "quest" and "Where to pick it up" or "Where it is")
  dpanel.locHead:SetShown(row.kind ~= "item" and row.kind ~= "info")
  for i = 1, math.min(8, #zones) do
    local z = zones[i]
    local r = dLoc(i); r:SetWidth(w)
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -y)
    r.loc = z
    r.text:SetText(string.format("%s  |cffaaaaaa%.1f, %.1f|r%s%s", areaName(z.area) or ("zone " .. z.area), z.x, z.y,
      z.count > 1 and ("  |cff888888(" .. z.count .. " spots)|r") or "", z.here and "  |cff55ff55nearest to you|r" or ""))
    r:Show(); y = y + 30
  end
  dpanel.noLoc:ClearAllPoints(); dpanel.noLoc:SetPoint("TOPLEFT", 2, -y)
  dpanel.noLoc:SetText((row.kind ~= "item" and row.kind ~= "info") and #zones == 0 and "|cff888888No map spots known yet (it may be inside a dungeon) - they fill in as you play.|r" or "")
  y = y + 20
  dpanel.child:SetHeight(math.max(10, y))
  dpanel:Show(); dpanel:Raise()
end

-- the "Where it comes from" panel
spRows, spHeads = {}, {}
local function spRow(i)
  local r = spRows[i]
  if r then return r end
  r = CreateFrame("Button", nil, spanel.child)
  r:SetSize(spanel.child:GetWidth(), 32)
  r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  r.name = UI:Text(r, "", "normal"); r.name:SetPoint("TOPLEFT", 26, -3); r.name:SetPoint("RIGHT", -60, 0); r.name:SetWordWrap(false)
  r.sub = UI:Text(r, "", "small"); r.sub:SetPoint("BOTTOMLEFT", 26, 3); r.sub:SetPoint("RIGHT", -60, 0); r.sub:SetWordWrap(false); r.sub:SetTextColor(0.65, 0.65, 0.65)
  r.copy = UI:Button(r, "Copy", 50, 20, function(self) local p = self:GetParent(); if p.data and UI.CopyBox then UI:CopyBox("Copy it (Ctrl+C)", p.data.copy or p.data.name) end end)
  r.copy:SetPoint("RIGHT", -4, 0)
  r.arrow = UI:Text(r, "|cff888888>|r", "large"); r.arrow:SetPoint("RIGHT", r.copy, "LEFT", -6, 0)
  r:SetScript("OnClick", function(self) if self.data and S.ItemMenuShowDetail then S.ItemMenuShowDetail(self.data) end end)
  UI:Tip(r, "Details", "Click for everything about it: where, levels, map pins, Wowhead.")
  spRows[i] = r
  return r
end
local function spHead(i)
  local h = spHeads[i]
  if h then return h end
  h = CreateFrame("Frame", nil, spanel.child); h:SetSize(spanel.child:GetWidth(), 26)
  h.icon = h:CreateTexture(nil, "ARTWORK"); h.icon:SetSize(18, 18); h.icon:SetPoint("LEFT", 2, 0); h.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  h.text = UI:Text(h, "", "large"); h.text:SetPoint("LEFT", h.icon, "RIGHT", 6, 0)
  h.line = h:CreateTexture(nil, "ARTWORK"); h.line:SetHeight(1); h.line:SetPoint("BOTTOMLEFT", 0, 1); h.line:SetPoint("BOTTOMRIGHT", 0, 1); h.line:SetColorTexture(1, 0.82, 0, 0.35)
  spHeads[i] = h
  return h
end
local function showSource(id, link)
  if not spanel then
    spanel = UI:Window("CC_ItemSource", "Where it comes from", 460, 520)
    spanel:SetFrameStrata("DIALOG")
    spanel.icon = spanel:CreateTexture(nil, "ARTWORK"); spanel.icon:SetSize(44, 44); spanel.icon:SetPoint("TOPLEFT", 18, -42)
    spanel.name = UI:Text(spanel, "", "title"); spanel.name:SetPoint("TOPLEFT", spanel.icon, "TOPRIGHT", 10, -2); spanel.name:SetPoint("RIGHT", -16, 0); spanel.name:SetWordWrap(false)
    spanel.info = UI:Text(spanel, "", "small"); spanel.info:SetPoint("TOPLEFT", spanel.name, "BOTTOMLEFT", 0, -6); spanel.info:SetPoint("RIGHT", -16, 0)
    spanel.sf, spanel.child = UI:Scroll(spanel, 440, 350)
    spanel.sf:SetPoint("TOPLEFT", 10, -100)
    spanel.empty = UI:Text(spanel, "", "normal", "CENTER"); spanel.empty:SetPoint("TOP", 0, -180); spanel.empty:SetWidth(400)
    spanel.wh = UI:Button(spanel, "Wowhead link", 120, 24, function() if spanel.id and UI.CopyBox then UI:CopyBox("Wowhead link - copy it (Ctrl+C) and open it in your browser", wowheadURL(spanel.id)) end end)
    spanel.wh:SetPoint("BOTTOMLEFT", 16, 14)
    spanel.chat = UI:Button(spanel, "Link it in chat", 120, 24, function() if spanel.link then S.ItemMenuChatLink(spanel.link) end end)
    spanel.chat:SetPoint("LEFT", spanel.wh, "RIGHT", 6, 0)
    local done = UI:Button(spanel, "Close", 70, 24, function() spanel:Hide() end); done:SetPoint("BOTTOMRIGHT", -16, 14)
  end
  spanel.id, spanel.link = id, link
  local name, l2, q, equipLoc, icon, price = itemInfo(link or id)
  spanel.icon:SetTexture(icon or (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or 134400)
  spanel.name:SetText(l2 or link or name or ("item " .. id))
  local info = {}
  local ok, n2, _, _, il, rq, ty, st = pcall(C_Item and C_Item.GetItemInfo or GetItemInfo, id)
  if ok then
    if st and st ~= "" then info[#info + 1] = st elseif ty then info[#info + 1] = ty end
    if il and il > 1 then info[#info + 1] = "item level " .. il end
    if rq and rq > 1 then info[#info + 1] = "requires level " .. rq end
  end
  if price and price > 0 then info[#info + 1] = "sells for " .. (GetCoinTextureString and GetCoinTextureString(price) or price) end
  local have = totalCount(id); if have > 0 then info[#info + 1] = "you have " .. have end
  spanel.info:SetText("|cffaaaaaa" .. table.concat(info, "  -  ") .. "|r")
  local data, hasDB = sourceData(id)
  for _, r in ipairs(spRows) do r:Hide() end
  for _, h in ipairs(spHeads) do h:Hide() end
  local y, ri, hi = 0, 0, 0
  local w = spanel.child:GetWidth()
  for _, sec in ipairs(data) do
    hi = hi + 1
    local h = spHead(hi); h:SetWidth(w)
    h:ClearAllPoints(); h:SetPoint("TOPLEFT", 0, -y)
    h.icon:SetTexture(sec.icon)
    h.text:SetText(sec.title .. ((sec.total or 0) > #sec.rows and (" |cff888888(" .. #sec.rows .. " of " .. sec.total .. ")|r") or ""))
    h:Show(); y = y + 30
    for _, row in ipairs(sec.rows) do
      ri = ri + 1
      local r = spRow(ri); r:SetWidth(w)
      r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -y)
      r.data = row
      r.name:SetText(row.name or "?"); r.sub:SetText(row.sub or "")
      r:Show(); y = y + 34
    end
    y = y + 8
  end
  spanel.child:SetHeight(math.max(10, y))
  spanel.empty:SetShown(#data == 0)
  spanel.empty:SetText(hasDB and "|cff888888Nothing known yet about where this comes from - it fills in as you loot, shop and quest.\nThe Wowhead link below always works.|r"
    or "|cff888888The Forever database isn't installed (ForeverDB addon) and nothing is recorded yet.\nThe Wowhead link below always works.|r")
  spanel:Show(); spanel:Raise()
end
S.ItemMenuShowSource = showSource

---------------------------------------------------------------------------
-- The menu
---------------------------------------------------------------------------
-- put a real (clickable) item link into the chat box: the open one, or open it first
function S.ItemMenuChatLink(link)
  if not link then return end
  -- Messenger open on a chat: put it in the message box
  if S.MsgInsertLink and S.MsgInsertLink(link, not (ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow())) then return end
  local box = (ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow())
  if box then
    if ChatEdit_InsertLink then ChatEdit_InsertLink(link) else box:Insert(link) end
    return
  end
  if ChatFrame_OpenChat then ChatFrame_OpenChat("") end
  C_Timer.After(0, function()
    local b = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
    if b then b:Insert(link) elseif ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
  end)
end
local function showMenu(link, bag, slot)
  local id = idFromLink(link)
  if not id then return end
  local name, _, q = itemInfo(link)
  local inBags = bag ~= nil and slot ~= nil
  local n = inBags and totalCount(id) or 0
  local items = { { text = (link or name or ("item " .. id)) .. (n > 1 and ("  |cffaaaaaax" .. n .. "|r") or ""), title = true } }
  local function add(t) items[#items + 1] = t end
  if inBags then
    local i = slotInfo(bag, slot)
    if i and i.hasLoot then
      add({ text = n > 1 and ("Open all (" .. n .. ")") or "Open", func = function() openAll(id) end, disabled = combat() })
    end
  end
  if dressable(link) then add({ text = "Preview", func = function() if DressUpItemLink then DressUpItemLink(link) end end }) end
  -- a link only stays clickable when the game puts it into the chat box itself
  -- (pasting copied link text turns it into plain text), so this inserts it directly
  add({ text = "Link it in chat", func = function() S.ItemMenuChatLink(link) end })
  add({ text = "Copy name", func = function()
    local nm = (link and link:match("%[(.-)%]")) or name or ("item " .. id)
    if UI.CopyBox then UI:CopyBox("Item name - copy it (Ctrl+C)", nm) end
  end })
  add({ text = "Wowhead link", func = function() if UI.CopyBox then UI:CopyBox("Wowhead link - copy it (Ctrl+C) and open it in your browser", wowheadURL(id)) end end })
  add({ text = "Where it comes from...", func = function() C_Timer.After(0, function() showSource(id, link) end) end })
  if not inBags then
    -- (chat links: no unwanted / delete - those are for your bags)
  elseif cfg().unwanted[id] then
    add({ text = "Unmark unwanted", func = function() S.ItemMenuSetUnwanted(id, false); S:Print((link or "It") .. " is no longer auto-deleted.") end })
  else
    add({ text = "Mark as unwanted (auto delete)", func = function() C_Timer.After(0, function() markUnwanted(id, link) end) end })
  end
  if inBags then
    if S.ItemMenuIsQueued(bag, slot) then
      add({ text = "Take out of delete queue", func = function() S.ItemMenuQueueDelete(bag, slot, false) end })
    else
      add({ text = "|cffff5555Delete multiple|r  |cff888888(Ctrl+Alt+Left-click)|r", disabled = combat(), func = function() askDelete(id, link, bag, slot) end })
    end
  end
  -- other tools add their own lines here (BiB: "Track in BiB's bank")
  for _, fn in ipairs(S.ItemMenuExtras or {}) do pcall(fn, add, id, link, bag, slot) end
  UI:Menu(nil, items)
end
S.ItemMenuShow = showMenu

---------------------------------------------------------------------------
-- Catching the clicks
---------------------------------------------------------------------------
local lastShown = 0
local function fromLocation(loc)
  if type(loc) == "table" and loc.IsBagAndSlot and loc:IsBagAndSlot() then return loc:GetBagAndSlot() end
end
local function tryShow(link, bag, slot, isChat)
  if not S:ItemMenuIsOn() or type(link) ~= "string" or not link:find("item:") then return end
  if GetTime() - lastShown < 0.15 then return end     -- one click can reach us twice
  lastShown = GetTime()
  C_Timer.After(0, function() showMenu(link, bag, slot) end)
end
-- modified clicks on items anywhere (bags, BiB, chat links...): the game calls this
if type(HandleModifiedItemClick) == "function" then
  hooksecurefunc("HandleModifiedItemClick", function(link, itemLocation)
    if not S.db or not S:ItemMenuIsOn() then return end
    local bag, slot = fromLocation(itemLocation)
    -- Ctrl+Alt+Left-click a bag item: add it to (or take it out of) the delete queue
    if bag and GetMouseButtonClicked and GetMouseButtonClicked() == "LeftButton"
       and IsControlKeyDown() and IsAltKeyDown() and not IsShiftKeyDown() then
      if GetTime() - lastShown < 0.15 then return end
      lastShown = GetTime()
      S.ItemMenuQueueDelete(bag, slot)
      return
    end
    if not buttonOK(GetMouseButtonClicked and GetMouseButtonClicked()) then return end
    local c = cfg()
    if bag then
      if c.mod ~= "none" and modsMatch(c.mod) then tryShow(link, bag, slot) end
    else
      -- chat (and other) links with a modifier
      if (c.chatMod and modsMatch(c.mod)) or (not c.chatMod and c.mod ~= "none" and modsMatch(c.mod)) then tryShow(link, nil, nil, true) end
    end
  end)
end
-- plain right-click on a chat link
hooksecurefunc("SetItemRef", function(link, text, button)
  if not S.db or not S:ItemMenuIsOn() or not buttonOK(button) then return end
  if type(link) ~= "string" or not link:find("^item:") then return end
  local c = cfg()
  if c.chatMod then
    -- chat links need the key: with it held this opens the menu (the modified-click
    -- path may not fire for every key, so it's caught here too; one click shows it once)
    if c.mod == "none" or not modsMatch(c.mod) then return end
  elseif IsModifiedClick and IsModifiedClick() then return end      -- handled above
  if ItemRefTooltip and ItemRefTooltip:IsShown() then ItemRefTooltip:Hide() end
  local full = text and text:find("|Hitem:") and text or link
  if type(full) == "string" and not full:find("|H") then
    local _, l2 = itemInfo(idFromLink(link)); full = l2 or ("item:" .. tostring(idFromLink(link)))
  end
  tryShow(full, nil, nil, true)
end)
-- "no modifier": plain right-click in bags (the item is used as normal too)
if C_Container and C_Container.UseContainerItem then
  hooksecurefunc(C_Container, "UseContainerItem", function(bag, slot)
    if not S.db or not S:ItemMenuIsOn() or cfg().mod ~= "none" or openID then return end
    if (GetMouseButtonClicked and GetMouseButtonClicked()) ~= "RightButton" or cfg().button == "left" then return end
    local i = slotInfo(bag, slot)
    if i and i.hyperlink then tryShow(i.hyperlink, bag, slot) end
  end)
end

---------------------------------------------------------------------------
-- Settings window
---------------------------------------------------------------------------
local win
local W, H = 480, 590
function S:RefreshItemMenu()
  if not win or not win:IsShown() then return end
  local c = cfg()
  win.on:SetChecked(c.on ~= false)
  win.mod:SetValue(c.mod); win.mod.value = c.mod
  win.btn:SetValue(c.button or "right"); win.btn.value = c.button or "right"
  win.chatMod:SetChecked(c.chatMod and true or false)
  win.auto:SetChecked(c.autoDelete ~= false); win.tell:SetChecked(c.tellDelete ~= false)
  if win.rec and S.CollectEnabled then
    win.rec:SetChecked(S.CollectEnabled())
    local st = S.CollectStats and S.CollectStats() or {}
    local meta = S.IDB and S.IDB.Meta and S.IDB.Meta()
    win.recInfo:SetText(string.format("|cffaaaaaaRecorded: %d loot sources, %d vendors, %d quests, %d creatures, %d items.  Database: %s|r",
      st.loot or 0, st.vendors or 0, st.quests or 0, st.npcs or 0, st.items or 0, (meta and meta.build ~= "empty" and meta.build) or "not installed yet"))
  end
  local rows = {}
  for id in pairs(c.unwanted) do rows[#rows + 1] = { id = id } end
  table.sort(rows, function(a, b) return (itemInfo(a.id) or "") < (itemInfo(b.id) or "") end)
  win.tbl:SetData(rows)
end
local function build()
  win = UI:Window("CC_ItemMenu", "ItemMenu", W, H)
  win:SetFrameStrata("HIGH")
  local y = -40
  local hint = UI:Text(win, "|cffaaaaaaClick an item in your bags or in chat (with the button and key below) for a menu: open all, preview, links, where it comes from, mark as unwanted, delete multiple. Ctrl+Alt+Left-click a bag item adds it to the delete queue.|r", "small")
  hint:SetPoint("TOPLEFT", 16, y); hint:SetWidth(W - 32); hint:SetJustifyH("LEFT"); y = y - 36
  win.on = UI:Check(win, "ItemMenu on", true, function(v) cfg().on = v end); win.on:SetPoint("TOPLEFT", 16, y); y = y - 30
  local bl = UI:Text(win, "Mouse button", "small"); bl:SetPoint("TOPLEFT", 18, y - 5)
  win.btn = UI:Dropdown(win, 250, BUTTONS, cfg().button, function(v) cfg().button = v end); win.btn:SetPoint("TOPLEFT", 170, y)
  UI:Tip(bl, "Mouse button", "Left-click with a key can clash with the game's own: Shift + left links the item, Ctrl + left previews it.")
  y = y - 30
  local ml = UI:Text(win, "Hold this key", "small"); ml:SetPoint("TOPLEFT", 18, y - 5)
  win.mod = UI:Dropdown(win, 250, MODS, cfg().mod, function(v) cfg().mod = v end); win.mod:SetPoint("TOPLEFT", 170, y); y = y - 30
  win.chatMod = UI:Check(win, "Chat links need the key too", true, function(v) cfg().chatMod = v end,
    "Off: a plain click (the mouse button above) on an item link in chat opens the menu.")
  win.chatMod:SetPoint("TOPLEFT", 16, y); y = y - 30
  y = y - 4
  local h = UI:Header(win, "Unwanted items"); h:SetPoint("TOPLEFT", 16, y); y = y - 26
  win.auto = UI:Check(win, "Offer to delete them (a button pops up) when they land in my bags", true, function(v) cfg().autoDelete = v; if v then S.ItemMenuSweep() end end)
  win.auto:SetPoint("TOPLEFT", 16, y); y = y - 24
  win.tell = UI:Check(win, "Tell me in chat when something is deleted", true, function(v) cfg().tellDelete = v end)
  win.tell:SetPoint("TOPLEFT", 16, y); y = y - 30
  win.tbl = UI:Table(win, W - 32, 150, {
    { title = "Item", w = 300, get = function(r)
        local name, _, q, _, icon = itemInfo(r.id)
        local hex = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q] and ITEM_QUALITY_COLORS[q].hex or "|cffffffff"
        return "|T" .. (icon or 134400) .. ":16:16:0:0:64:64:5:59:5:59|t  " .. hex .. (name or ("item " .. r.id)) .. "|r"
      end },
    { title = "In bags", w = 80, get = function(r) return tostring(totalCount(r.id)) end },
  }, { selectable = true, emptyText = "Nothing marked. Right-click an item > Mark as unwanted." })
  win.tbl:SetPoint("TOPLEFT", 16, y); y = y - 156
  local rm = UI:Button(win, "Unmark selected", 130, 22, function()
    local s = win.tbl.selected
    if s then S.ItemMenuSetUnwanted(s.id, false); win.tbl.selected = nil end
  end)
  rm:SetPoint("TOPLEFT", 16, y); y = y - 34
  local h2 = UI:Header(win, "Forever database"); h2:SetPoint("TOPLEFT", 16, y); y = y - 26
  win.rec = UI:Check(win, "Record what I loot, buy and quest (fills in drop rates, vendors and map spots)", true,
    function(v) if S.SetCollectEnabled then S.SetCollectEnabled(v) end end,
    "Saved separately from your settings (no whispers or personal info) so it can be added to the shared Forever database.")
  win.rec:SetPoint("TOPLEFT", 16, y); y = y - 24
  win.recInfo = UI:Text(win, "", "small"); win.recInfo:SetPoint("TOPLEFT", 20, y); win.recInfo:SetWidth(W - 40); win.recInfo:SetJustifyH("LEFT")
  win:HookScript("OnShow", function() S:RefreshItemMenu() end)
end
function S:ShowItemMenu()
  if not win then build() end
  win:Show(); win:Raise()
  S:RefreshItemMenu()
end
function S:HideItemMenu() if win then win:Hide() end end
S:AddCommand("itemmenu", "", "ItemMenu: right-click menu for items (settings)", function() S:ShowItemMenu() end)
