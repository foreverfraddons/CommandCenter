-- Radialz: a radial action menu - an extra action bar shaped like a wheel.
--   * put spells, items, saved macros or your own macro text on its slots
--   * a slot can open another wheel (pages), so one key reaches dozens of actions
--   * press the key (default: mouse button 5) to open it at the mouse,
--     left-click a slot to use it (only left-click casts); any other mouse button,
--     click outside or Escape to close; the centre (left-click) goes back a page
--   * everything that casts is a secure button set up out of combat, so the wheel
--     opens, flips pages and casts in combat too (changes wait until combat ends)
-- Settings: S.db.global.radialz (shared by all characters on this PC).
--
-- ONE FILE, TWO HOMES: this same file is CommandCenter\Radialz.lua (built into
-- Command Center) and Radialz\Radialz.lua (the standalone addon, whose Host.lua
-- gives it the bits of Command Center it needs). Change one -> copy it to the
-- other (CRLF) -> raise the revision. When Command Center is installed the
-- standalone sets S.yield and this file stops right here, so it never runs twice.
local ADDON, S = ...
if S.yield then return end
if S.ModuleRev then S:ModuleRev("Radialz", 6) end
S.RADIALZ_REV = 6
local UI = S.UI
local CMD = S.RZ_CMD or "/ccenter radialz"

local MEDIA = "Interface\\AddOns\\" .. tostring(ADDON) .. "\\Media\\UI\\"
local PAGE_ICON = "Interface\\Icons\\INV_Misc_Book_09"
local EMPTY_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local MAX_PAGES, MAX_SLOTS, MIN_SLOTS = 20, 12, 2

local COLORS = {
  { value = "theme", text = "Theme accent" },
  { value = "gold", text = "Gold", c = { 1, 0.82, 0.2 } },
  { value = "orange", text = "Orange", c = { 1, 0.55, 0.1 } },
  { value = "red", text = "Red", c = { 1, 0.3, 0.25 } },
  { value = "pink", text = "Pink", c = { 1, 0.4, 0.8 } },
  { value = "purple", text = "Purple", c = { 0.75, 0.4, 1 } },
  { value = "blue", text = "Blue", c = { 0.3, 0.6, 1 } },
  { value = "cyan", text = "Cyan", c = { 0.2, 0.95, 1 } },
  { value = "green", text = "Green", c = { 0.3, 1, 0.3 } },
  { value = "white", text = "White", c = { 1, 1, 1 } },
}
local KINDS = {
  { value = "none", text = "Empty" },
  { value = "spell", text = "Spell" },
  { value = "item", text = "Item" },
  { value = "macro", text = "Saved macro" },
  { value = "text", text = "Macro text" },
  { value = "page", text = "Open a page" },
}

local function combat() return InCombatLockdown and InCombatLockdown() end
local function clamp(v, lo, hi) v = tonumber(v) or lo; if v < lo then return lo elseif v > hi then return hi end return v end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
local LOOK_DEF = { radius = 110, size = 42, round = 5, wheel = true, wheelAlpha = 0.6, spin = true, color = "theme",
  labels = "center", tips = true, cooldowns = true, counts = true, dim = true, empty = true, anim = "fade", center = true }

local function newPage(c, name, slots)
  c.nextId = (tonumber(c.nextId) or 0) + 1
  return { id = c.nextId, name = name or ("Page " .. c.nextId), slots = slots or 8, items = {} }
end

local function cfg()
  local g = S.db.global
  g.radialz = type(g.radialz) == "table" and g.radialz or {}
  local c = g.radialz
  if c.on == nil then c.on = true end
  if type(c.key) ~= "string" or c.key == "" then c.key = "BUTTON5" end
  if c.openAt ~= "center" then c.openAt = "mouse" end
  if c.closeOnUse == nil then c.closeOnUse = true end
  if c.numKeys == nil then c.numKeys = true end
  if c.sector == nil then c.sector = true end
  c.look = type(c.look) == "table" and c.look or {}
  for k, v in pairs(LOOK_DEF) do if c.look[k] == nil then c.look[k] = v end end
  if type(c.pages) ~= "table" or #c.pages == 0 then
    -- first run: a main wheel with the hearthstone and a second page to show how pages work
    c.pages = {}
    local main = newPage(c, "Main", 8)
    local more = newPage(c, "More", 6)
    main.items[1] = { kind = "item", id = 6948 }
    main.items[5] = { kind = "page", page = more.id }
    c.pages[1], c.pages[2] = main, more
  end
  for _, p in ipairs(c.pages) do
    p.items = type(p.items) == "table" and p.items or {}
    p.slots = clamp(p.slots, MIN_SLOTS, MAX_SLOTS)
    if not p.id then c.nextId = (tonumber(c.nextId) or 0) + 1; p.id = c.nextId end
  end
  return c
end
local function L() return cfg().look end

local function pageIndex(id)
  for i, p in ipairs(cfg().pages) do if p.id == id then return i, p end end
end

local function lookColor()
  local key = L().color
  for _, o in ipairs(COLORS) do if o.value == key and o.c then return o.c[1], o.c[2], o.c[3] end end
  return UI:Accent()
end

---------------------------------------------------------------------------
-- What a slot holds: names, icons, cooldowns (works on old and new game APIs)
---------------------------------------------------------------------------
local function spellName(id)
  if not id then return nil end
  if C_Spell and C_Spell.GetSpellName then local ok, n = pcall(C_Spell.GetSpellName, id); if ok and n then return n end end
  if GetSpellInfo then local ok, n = pcall(GetSpellInfo, id); if ok and n then return n end end
end
local function spellIcon(id)
  if not id then return nil end
  if C_Spell and C_Spell.GetSpellTexture then local ok, t = pcall(C_Spell.GetSpellTexture, id); if ok and t then return t end end
  if GetSpellTexture then local ok, t = pcall(GetSpellTexture, id); if ok and t then return t end end
  if GetSpellInfo then local ok, _, _, t = pcall(GetSpellInfo, id); if ok and t then return t end end
end
local function spellIdByName(name)
  if not name or name == "" then return nil end
  if tonumber(name) then return tonumber(name) end
  if C_Spell and C_Spell.GetSpellInfo then
    local ok, t = pcall(C_Spell.GetSpellInfo, name)
    if ok and type(t) == "table" and t.spellID then return t.spellID end
  end
  if GetSpellInfo then
    local ok, _, _, _, _, _, _, id = pcall(GetSpellInfo, name)
    if ok and id then return id end
  end
end
local function itemName(id)
  if not id then return nil end
  if C_Item and C_Item.GetItemNameByID then local ok, n = pcall(C_Item.GetItemNameByID, id); if ok and n then return n end end
  if GetItemInfo then local ok, n = pcall(GetItemInfo, id); if ok and n then return n end end
end
local function itemIcon(id)
  if not id then return nil end
  if C_Item and C_Item.GetItemIconByID then local ok, t = pcall(C_Item.GetItemIconByID, id); if ok and t then return t end end
  if GetItemIcon then local ok, t = pcall(GetItemIcon, id); if ok and t then return t end end
end
local function itemIdByName(name)
  if not name or name == "" then return nil end
  if tonumber(name) then return tonumber(name) end
  local link = name:match("item:(%d+)")
  if link then return tonumber(link) end
  local f = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  if f then local ok, id = pcall(f, name); if ok and id then return id end end
end
local function macroInfo(name)
  if not name or not GetMacroIndexByName then return nil end
  local idx = GetMacroIndexByName(name)
  if not idx or idx == 0 then return nil end
  local n, icon, body = GetMacroInfo(idx)
  return n, icon, body, idx
end
local function textIcon(text)
  -- "#showtooltip Spell" or the first /cast line decides the icon of a macro text
  if type(text) ~= "string" then return nil end
  local sp = text:match("#showtooltip%s+([^\n;]+)") or text:match("/cast%s+([^\n;]+)") or text:match("/use%s+([^\n;]+)")
  if not sp then return nil end
  sp = S.Trim(sp:gsub("%[.-%]", ""))
  if sp == "" then return nil end
  local sid = spellIdByName(sp)
  if sid then return spellIcon(sid) end
  local iid = itemIdByName(sp)
  if iid then return itemIcon(iid) end
end

-- icon, name of a slot (it = saved record)
local function slotLook(it)
  if type(it) ~= "table" then return nil, nil end
  local icon, name
  if it.kind == "spell" then
    icon, name = spellIcon(it.id or it.name), spellName(it.id) or it.name
  elseif it.kind == "item" then
    icon, name = itemIcon(it.id), itemName(it.id) or it.name or (it.id and ("item " .. it.id))
  elseif it.kind == "macro" then
    local n, ic = macroInfo(it.name)
    icon, name = ic, n or it.name
  elseif it.kind == "text" then
    icon, name = textIcon(it.text), "Macro"
  elseif it.kind == "page" then
    local _, p = pageIndex(it.page)
    icon, name = p and p.icon or PAGE_ICON, p and p.name or "(missing page)"
  end
  if it.icon then icon = it.icon end
  if it.label and it.label ~= "" then name = it.label end
  return icon or EMPTY_ICON, name
end

local function spellCooldown(s)
  if C_Spell and C_Spell.GetSpellCooldown then
    local ok, t = pcall(C_Spell.GetSpellCooldown, s)
    if ok and type(t) == "table" then return t.startTime, t.duration end
  end
  if GetSpellCooldown then local ok, st, du = pcall(GetSpellCooldown, s); if ok then return st, du end end
end
local function itemCooldown(id)
  local f = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
  if f then local ok, st, du = pcall(f, id); if ok then return st, du end end
end
local function itemCount(id)
  local f = (C_Item and C_Item.GetItemCount) or GetItemCount
  if f then local ok, n = pcall(f, id, false, true); if ok then return n end end
end
local function spellUsable(s)
  local f = (C_Spell and C_Spell.IsSpellUsable) or IsUsableSpell
  if f then local ok, u, nomana = pcall(f, s); if ok then return u, nomana end end
  return true
end
local function itemUsable(id)
  local f = (C_Item and C_Item.IsUsableItem) or IsUsableItem
  if f then local ok, u, nomana = pcall(f, id); if ok then return u, nomana end end
  return true
end

-- what to show for cooldown / count / usable: start, duration, count, usable
local function slotState(it)
  if type(it) ~= "table" then return end
  local sid, iid
  if it.kind == "spell" then sid = it.id or it.name
  elseif it.kind == "item" then iid = it.id
  elseif it.kind == "macro" then
    local _, _, _, idx = macroInfo(it.name)
    if idx then
      if GetMacroSpell then local ok, s = pcall(GetMacroSpell, idx); if ok and s then sid = s end end
      if not sid and GetMacroItem then local ok, _, link = pcall(GetMacroItem, idx); if ok and link then iid = itemIdByName(link) end end
    end
  end
  if sid then
    local st, du = spellCooldown(sid)
    local u, nomana = spellUsable(sid)
    return st, du, nil, u or nomana
  elseif iid then
    local st, du = itemCooldown(iid)
    local u = itemUsable(iid)
    return st, du, itemCount(iid), u
  end
end

-- what's on the cursor (spell from the spellbook, item from bags, a macro...) -> a slot record
local function recordFromCursor()
  if not GetCursorInfo then return nil end
  local t, a1, a2, a3 = GetCursorInfo()
  if not t then return nil end
  if t == "spell" then
    local id = tonumber(a3)
    if not id and C_SpellBook and C_SpellBook.GetSpellBookItemInfo then
      local ok, info = pcall(C_SpellBook.GetSpellBookItemInfo, a1, a2)
      if ok and type(info) == "table" then id = info.spellID or info.actionID end
    end
    if not id and GetSpellBookItemInfo then local ok, _, x = pcall(GetSpellBookItemInfo, a1, a2); if ok then id = tonumber(x) end end
    if id then return { kind = "spell", id = id, name = spellName(id) } end
  elseif t == "item" then
    local id = tonumber(a1) or itemIdByName(a2)
    if id then return { kind = "item", id = id } end
  elseif t == "macro" then
    local n = GetMacroInfo and GetMacroInfo(a1)
    if n then return { kind = "macro", name = n } end
  elseif t == "mount" then
    if C_MountJournal and C_MountJournal.GetMountInfoByID then
      local ok, _, sid = pcall(C_MountJournal.GetMountInfoByID, a1)
      if ok and sid then return { kind = "spell", id = sid, name = spellName(sid) } end
    end
  elseif t == "companion" then
    if GetCompanionInfo then
      local ok, _, _, sid = pcall(GetCompanionInfo, a2, a1)
      if ok and sid then return { kind = "spell", id = sid, name = spellName(sid) } end
    end
  elseif t == "equipmentset" then
    return { kind = "text", text = "/equipset " .. tostring(a1), label = tostring(a1) }
  end
end

---------------------------------------------------------------------------
-- The live wheel (secure)
--   CC_RadialzOpen      key target (override binding), toggles the wheel
--   CC_RadialzBackdrop  full screen, catches a click outside = close
--   CC_RadialzRing      the wheel (secure header holding the snippets)
--   CC_RadialzPage<p>   one frame per page, CC_RadialzP<p>S<s> its slots
--   CC_RadialzCenter    left-click = back a page / close, right-click = close
---------------------------------------------------------------------------
local ring, bd, openBtn, center
local pages = {}          -- [p] = page frame { slots = { [s] = button } }
local dirty = false

local SNIP_OPEN = [[
  local bd = self:GetFrameRef("bd")
  bd:Show()
  local W, H = bd:GetWidth(), bd:GetHeight()
  local x, y
  if self:GetAttribute("rz-atmouse") == 1 and bd.GetMousePosition then x, y = bd:GetMousePosition() end
  if not x or not y then x, y = 0.5, 0.5 end
  local px, py = x * W, y * H
  local m = self:GetAttribute("rz-reach") or 150
  if W > m * 2 then
    if px < m then px = m elseif px > W - m then px = W - m end
  end
  if H > m * 2 then
    if py < m then py = m elseif py > H - m then py = H - m end
  end
  self:ClearAllPoints()
  self:SetPoint("CENTER", bd, "BOTTOMLEFT", px, py)
  self:SetAttribute("rz-cx", px)
  self:SetAttribute("rz-cy", py)
  self:SetAttribute("rz-via", 0)
  self:SetAttribute("rz-depth", 1)
  self:SetAttribute("rz-h1", 1)
  self:Show()
  control:RunAttribute("rz-show", 1)
]]

local SNIP_SHOW = [[
  local n = ...
  local np = self:GetAttribute("rz-npages") or 0
  for i = 1, np do
    local p = self:GetFrameRef("p" .. i)
    if p then
      if i == n then p:Show() else p:Hide() end
    end
  end
  self:ClearBindings()
  self:SetBindingClick(true, "ESCAPE", "CC_RadialzCenter", "RightButton")
  if self:GetAttribute("rz-numkeys") == 1 then
    local cnt = self:GetAttribute("rz-n" .. n) or 0
    if cnt > 9 then cnt = 9 end
    for s = 1, cnt do
      self:SetBindingClick(true, "" .. s, "CC_RadialzP" .. n .. "S" .. s, "LeftButton")
    end
  end
  self:SetAttribute("rz-cur", n)
]]

local SNIP_CLOSE = [[
  local np = self:GetAttribute("rz-npages") or 0
  for i = 1, np do
    local p = self:GetFrameRef("p" .. i)
    if p then p:Hide() end
  end
  self:ClearBindings()
  self:Hide()
  self:SetAttribute("rz-cur", 0)
  local bd = self:GetFrameRef("bd")
  if bd then bd:Hide() end
]]

local SNIP_GO = [[
  local n = ...
  local d = (self:GetAttribute("rz-depth") or 1) + 1
  self:SetAttribute("rz-depth", d)
  self:SetAttribute("rz-h" .. d, n)
  control:RunAttribute("rz-show", n)
]]

local SNIP_BACK = [[
  local d = self:GetAttribute("rz-depth") or 1
  if d <= 1 then
    control:RunAttribute("rz-close")
  else
    d = d - 1
    self:SetAttribute("rz-depth", d)
    control:RunAttribute("rz-show", self:GetAttribute("rz-h" .. d) or 1)
  end
]]

-- key target: toggle (registered for key down only)
local PRE_OPEN = [[
  if owner:IsShown() then control:RunAttribute("rz-close") else control:RunAttribute("rz-open") end
  return false
]]
-- a click anywhere off the slots: right-click closes; left-click uses the slot
-- whose direction the mouse is in (sector mode) - the backdrop runs
-- "/click <that slot>" as its own macro, so it works in combat too
local PRE_BACKDROP = [[
  owner:SetAttribute("rz-via", 0)
  if button ~= "LeftButton" or owner:GetAttribute("rz-sector") ~= 1 then
    control:RunAttribute("rz-close")
    return false
  end
  local isDown = down and 1 or 0
  if isDown ~= owner:GetAttribute("rz-keydown") then return false end
  local x, y
  if self.GetMousePosition then x, y = self:GetMousePosition() end
  if not x or not y then return false end
  local dx = x * self:GetWidth() - (owner:GetAttribute("rz-cx") or 0)
  local dy = y * self:GetHeight() - (owner:GetAttribute("rz-cy") or 0)
  if dx * dx + dy * dy < (owner:GetAttribute("rz-dead") or 0) then return false end
  local p = owner:GetAttribute("rz-cur") or 0
  local n = owner:GetAttribute("rz-n" .. p) or 0
  local best, bs = nil, 0
  for s = 1, n do
    local d = dx * (owner:GetAttribute("rz-vx" .. p .. "_" .. s) or 0) + dy * (owner:GetAttribute("rz-vy" .. p .. "_" .. s) or 0)
    if not best or d > best then best, bs = d, s end
  end
  if bs == 0 or owner:GetAttribute("rz-has" .. p .. "_" .. bs) ~= 1 then return false end
  owner:SetAttribute("rz-via", 1)
  self:SetAttribute("type", "macro")
  self:SetAttribute("macrotext", "/click CC_RadialzP" .. p .. "S" .. bs .. " LeftButton" .. (isDown == 1 and " true" or ""))
]]
local PRE_CENTER = [[
  if button == "LeftButton" then control:RunAttribute("rz-back") else control:RunAttribute("rz-close") end
  return false
]]
-- slots are registered for down AND up (the game casts on the one its
-- "cast on key down" setting picks); we act once, on that same one
local PRE_SLOT = [[
  if button ~= "LeftButton" then
    owner:SetAttribute("rz-via", 0)
    control:RunAttribute("rz-close")
    return false
  end
  if owner:GetAttribute("rz-via") == 1 then
    owner:SetAttribute("rz-via", 0)
  else
    local isDown = down and 1 or 0
    if isDown ~= owner:GetAttribute("rz-keydown") then return end
  end
  local pg = self:GetAttribute("rz-page")
  if pg then
    control:RunAttribute("rz-go", pg)
    return false
  end
  if self:GetAttribute("type") then return nil, "used" end
  return false
]]
local POST_SLOT = [[
  if owner:GetAttribute("rz-closeonuse") == 1 then control:RunAttribute("rz-close") end
]]

local refreshVisible, paintAll, onSlotEnter, onSlotLeave, onSlotDrop  -- (below)

local function setMask(tex, mask, round)
  if not mask then return end
  pcall(mask.SetTexture, mask, MEDIA .. "rmask" .. round, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
end

-- visual parts shared by live slots and the editor preview
local function decorate(b)
  b.glow = b:CreateTexture(nil, "BACKGROUND")
  b.glow:SetBlendMode("ADD"); b.glow:SetPoint("CENTER"); b.glow:Hide()
  b.bg = b:CreateTexture(nil, "BACKGROUND", nil, 2)
  b.bg:SetAllPoints(); b.bg:SetTexture(MEDIA .. "rmask5")
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetAllPoints(); b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  if b.CreateMaskTexture then
    b.mask = b:CreateMaskTexture()
    b.mask:SetAllPoints(b.icon)
    setMask(b.icon, b.mask, 5)
    b.icon:AddMaskTexture(b.mask)
    b.bg:AddMaskTexture(b.mask)
  end
  b.edge = b:CreateTexture(nil, "OVERLAY")
  b.edge:SetAllPoints()
  b.count = b:CreateFontString(nil, "OVERLAY")
  b.count:SetFontObject(UI.fSmall); b.count:SetPoint("BOTTOMRIGHT", -2, 2)
  b.num = b:CreateFontString(nil, "OVERLAY")
  b.num:SetFontObject(UI.fSmall); b.num:SetPoint("TOPLEFT", 2, -2)
  b.label = b:CreateFontString(nil, "OVERLAY")
  b.label:SetFontObject(UI.fSmall); b.label:SetPoint("TOP", b, "BOTTOM", 0, -2); b.label:SetWordWrap(false)
end

-- paint a slot button (live or preview) for record `it`, size px, slot number s
local function paintSlot(b, it, px, s, editing)
  local l = L()
  local rd = clamp(l.round, 0, 5)
  local r, g, bl = lookColor()
  b:SetSize(px, px)
  setMask(b.icon, b.mask, rd)
  b.edge:SetTexture(MEDIA .. "rring" .. rd)
  b.glow:SetTexture(MEDIA .. "halo_" .. rd .. "_3")
  b.glow:SetSize(px * 1.7, px * 1.7); b.glow:SetVertexColor(r, g, bl, 0.9)
  b.bg:SetVertexColor(0, 0, 0, 0.55)
  local icon, name = slotLook(it)
  b.rec, b.recName = it, name
  if it then
    b.icon:SetTexture(icon); b.icon:Show(); b.icon:SetDesaturated(false); b.icon:SetVertexColor(1, 1, 1)
    b.edge:SetVertexColor(r, g, bl, 1)
    b:SetAlpha(1)
  else
    b.icon:Hide()
    b.edge:SetVertexColor(r, g, bl, 0.35)
    b:SetAlpha((l.empty or editing) and 1 or 0)
  end
  if it and it.kind == "page" then b.count:SetText(">"); b.count:SetTextColor(r, g, bl) else b.count:SetText("") end
  b.num:SetText((cfg().numKeys and s and s <= 9 and not editing) and tostring(s) or "")
  b.num:SetTextColor(0.85, 0.85, 0.85)
  b.label:SetText((l.labels == "each" and name) or "")
  b.label:SetWidth(px * 1.8)
  b.label:SetTextColor(1, 1, 1)
end

-- cooldown / count / usable on a live slot
local function stateSlot(b)
  local it = b.rec
  if not it or it.kind == "page" or it.kind == "text" then
    if b.cd then b.cd:Hide() end
    return
  end
  local l = L()
  local st, du, cnt, usable = slotState(it)
  if b.cd then
    if l.cooldowns and st and du then
      local ok, long = pcall(function() return du > 1.6 and st > 0 end)
      if ok and long then pcall(b.cd.SetCooldown, b.cd, st, du) else b.cd:Hide() end
    else
      b.cd:Hide()
    end
  end
  if cnt and l.counts then
    b.count:SetText(cnt ~= 1 and tostring(cnt) or "")
    b.count:SetTextColor(1, 1, 1)
  else
    b.count:SetText("")
  end
  local missing = (it.kind == "item" and cnt == 0)
  if l.dim and (missing or not usable) then
    b.icon:SetVertexColor(0.45, 0.45, 0.5); b.icon:SetDesaturated(missing)
  else
    b.icon:SetVertexColor(1, 1, 1); b.icon:SetDesaturated(false)
  end
end

local function newSlot(page, p, s)
  local b = CreateFrame("Button", "CC_RadialzP" .. p .. "S" .. s, page, "SecureActionButtonTemplate")
  b:RegisterForClicks("AnyUp", "AnyDown")
  decorate(b)
  b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
  b.cd:SetAllPoints(b.icon)
  if b.cd.SetDrawEdge then b.cd:SetDrawEdge(false) end
  if b.cd.SetHideCountdownNumbers then b.cd:SetHideCountdownNumbers(false) end
  -- texts on their own layer above the cooldown swipe
  b.over = CreateFrame("Frame", nil, b)
  b.over:SetAllPoints(); b.over:SetFrameLevel(b.cd:GetFrameLevel() + 2)
  b.count:SetParent(b.over); b.num:SetParent(b.over); b.label:SetParent(b.over)
  b:SetScript("OnEnter", function(self) if onSlotEnter then onSlotEnter(self) end end)
  b:SetScript("OnLeave", function(self) if onSlotLeave then onSlotLeave(self) end end)
  b:SetScript("OnReceiveDrag", function(self) if onSlotDrop then onSlotDrop(self) end end)
  SecureHandlerWrapScript(b, "OnClick", ring, PRE_SLOT, POST_SLOT)
  b.p, b.s = p, s
  return b
end

local function newPageFrame(p)
  local f = CreateFrame("Frame", "CC_RadialzPage" .. p, ring, "SecureFrameTemplate")
  f:SetAllPoints(ring)
  f:Hide()
  f.slots = {}
  SecureHandlerSetFrameRef(ring, "p" .. p, f)
  return f
end

local function buildFrames()
  if ring then return end
  bd = CreateFrame("Button", "CC_RadialzBackdrop", UIParent, "SecureActionButtonTemplate")
  bd:SetAllPoints(UIParent)
  bd:SetFrameStrata("FULLSCREEN")
  bd:RegisterForClicks("AnyUp", "AnyDown")
  bd:Hide()

  ring = CreateFrame("Frame", "CC_RadialzRing", UIParent, "SecureHandlerBaseTemplate")
  ring:SetFrameStrata("FULLSCREEN_DIALOG")
  ring:SetSize(300, 300)
  ring:SetPoint("CENTER")
  ring:Hide()
  ring:SetAttribute("rz-open", SNIP_OPEN)
  ring:SetAttribute("rz-show", SNIP_SHOW)
  ring:SetAttribute("rz-close", SNIP_CLOSE)
  ring:SetAttribute("rz-go", SNIP_GO)
  ring:SetAttribute("rz-back", SNIP_BACK)
  SecureHandlerSetFrameRef(ring, "bd", bd)
  SecureHandlerWrapScript(bd, "OnClick", ring, PRE_BACKDROP)

  -- decoration (plain textures, recoloured any time)
  ring.wheel = ring:CreateTexture(nil, "BACKGROUND")
  ring.wheel:SetTexture(MEDIA .. "rz_wheel"); ring.wheel:SetPoint("CENTER")
  ring.spin = ring:CreateTexture(nil, "BORDER")
  ring.spin:SetTexture(MEDIA .. "rz_spin"); ring.spin:SetPoint("CENTER"); ring.spin:SetBlendMode("ADD")
  ring.spinAnim = ring.spin:CreateAnimationGroup()
  local rot = ring.spinAnim:CreateAnimation("Rotation")
  rot:SetDegrees(-360); rot:SetDuration(24)
  if rot.SetOrigin then rot:SetOrigin("CENTER", 0, 0) end
  ring.spinAnim:SetLooping("REPEAT")
  ring.fade = ring:CreateAnimationGroup()
  local fa = ring.fade:CreateAnimation("Alpha")
  fa:SetFromAlpha(0); fa:SetToAlpha(1); fa:SetDuration(0.12)
  if fa.SetSmoothing then fa:SetSmoothing("OUT") end

  center = CreateFrame("Button", "CC_RadialzCenter", ring, "SecureActionButtonTemplate")
  center:SetPoint("CENTER")
  center:RegisterForClicks("AnyUp")
  center:SetFrameLevel(ring:GetFrameLevel() + 20)
  decorate(center)
  center.icon:Hide()
  center.title = center:CreateFontString(nil, "OVERLAY")
  center.title:SetFontObject(UI.fNormal); center.title:SetPoint("CENTER", 0, 0); center.title:SetJustifyH("CENTER")
  center.sub = center:CreateFontString(nil, "OVERLAY")
  center.sub:SetFontObject(UI.fSmall); center.sub:SetPoint("TOP", center.title, "BOTTOM", 0, -2)
  center:SetScript("OnEnter", function(self)
    self.glow:Show()
    if not L().tips then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Radialz", 1, 0.82, 0)
    GameTooltip:AddLine("Left-click: back a page (closes on the main page)", 1, 1, 1)
    GameTooltip:AddLine("Any other click or Escape: close", 1, 1, 1)
    GameTooltip:AddLine(cfg().sector and "Only a left-click uses a slot (anywhere in its direction); right, middle or side buttons anywhere close the wheel." or
      "Only a left-click uses a slot; right, middle or side buttons close the wheel.", 0.7, 0.7, 0.7, true)
    if not combat() then GameTooltip:AddLine("Drop a spell, item or macro on a slot to put it there.", 0.7, 0.7, 0.7, true) end
    GameTooltip:Show()
  end)
  center:SetScript("OnLeave", function(self) self.glow:Hide(); GameTooltip:Hide() end)
  SecureHandlerWrapScript(center, "OnClick", ring, PRE_CENTER)

  openBtn = CreateFrame("Button", "CC_RadialzOpen", UIParent, "SecureActionButtonTemplate")
  openBtn:RegisterForClicks("AnyDown")
  openBtn:SetSize(1, 1); openBtn:SetPoint("TOPLEFT", UIParent, "BOTTOMRIGHT", 10, -10)
  openBtn:Show()
  SecureHandlerWrapScript(openBtn, "OnClick", ring, PRE_OPEN)

  -- visuals follow the secure state
  ring:HookScript("OnAttributeChanged", function(_, name)
    if name == "rz-cur" and refreshVisible then refreshVisible() end
  end)
  ring:HookScript("OnShow", function(self)
    local l = L()
    if l.anim == "fade" then self.fade:Stop(); self.fade:Play() end
    if l.spin and l.anim ~= "none" then self.spinAnim:Play() else self.spinAnim:Stop() end
  end)
  ring:HookScript("OnHide", function(self) self.spinAnim:Stop(); GameTooltip:Hide() end)
  local acc = 0
  local aimed
  local function aim()
    local cur = ring:GetAttribute("rz-cur") or 0
    local p = pages[cur]
    local pick
    if p and cfg().sector then
      local cx, cy = ring:GetCenter()
      if cx then
        local sc = ring:GetEffectiveScale()
        local mx, my = GetCursorPosition()
        local dx, dy = mx / sc - cx, my / sc - cy
        local dead = (center:GetWidth() or 0) / 2
        if dx * dx + dy * dy >= dead * dead then
          local best
          for _, b in ipairs(p.slots) do
            if b:IsShown() and b.vx then
              local d = dx * b.vx + dy * b.vy
              if not best or d > best then best, pick = d, b end
            end
          end
        end
      end
    end
    if pick and not pick.rec then pick = nil end
    if pick == aimed then
      if pick then
        pick.glow:Show()
        if L().labels == "center" and pick.recName then center.title:SetText(pick.recName) end
      end
      return
    end
    if aimed and not aimed:IsMouseOver() then aimed.glow:Hide() end
    aimed = pick
    if pick then
      pick.glow:Show()
      if L().labels == "center" and pick.recName then center.title:SetText(pick.recName) end
    else
      local pg = cfg().pages[cur]
      center.title:SetText((pg and L().center) and pg.name or "")
    end
  end
  ring:HookScript("OnHide", function() if aimed then aimed.glow:Hide(); aimed = nil end end)
  ring:HookScript("OnUpdate", function(_, el)
    pcall(aim)
    acc = acc + el
    if acc < 0.1 then return end
    acc = 0
    local p = pages[ring:GetAttribute("rz-cur") or 0]
    if not p then return end
    for _, b in ipairs(p.slots) do if b:IsShown() and b.rec then pcall(stateSlot, b) end end
  end)
end

-- the key is "cast on key down" in the game's settings? (slots act on that edge)
local function keyDownSetting()
  if GetCVarBool then local ok, v = pcall(GetCVarBool, "ActionButtonUseKeyDown"); if ok then return v and 1 or 0 end end
  return 0
end

local function applySlot(b, it, c)
  for _, a in ipairs({ "type", "spell", "item", "macro", "macrotext", "rz-page" }) do b:SetAttribute(a, nil) end
  if type(it) ~= "table" then return end
  if it.kind == "spell" then
    local v = spellName(it.id) or it.name or it.id
    if v then b:SetAttribute("type", "spell"); b:SetAttribute("spell", v) end
  elseif it.kind == "item" then
    local v = it.id and ("item:" .. it.id) or it.name
    if v then b:SetAttribute("type", "item"); b:SetAttribute("item", v) end
  elseif it.kind == "macro" then
    if it.name then b:SetAttribute("type", "macro"); b:SetAttribute("macro", it.name) end
  elseif it.kind == "text" then
    if it.text and it.text ~= "" then b:SetAttribute("type", "macro"); b:SetAttribute("macrotext", it.text) end
  elseif it.kind == "page" then
    local idx = pageIndex(it.page)
    if idx then b:SetAttribute("rz-page", idx) end
  end
end

-- (re)build everything secure from the settings - out of combat only
local function rebuild()
  if not S.db then return end
  if combat() then dirty = true return end
  dirty = false
  buildFrames()
  local c, l = cfg(), L()
  local R, px = clamp(l.radius, 60, 240), clamp(l.size, 20, 80)
  local reach = R + px / 2 + 8
  ring:SetSize(reach * 2, reach * 2)
  ring:SetAttribute("rz-npages", #c.pages)
  ring:SetAttribute("rz-reach", reach + 4)
  ring:SetAttribute("rz-atmouse", c.openAt == "mouse" and 1 or 0)
  ring:SetAttribute("rz-closeonuse", c.closeOnUse and 1 or 0)
  ring:SetAttribute("rz-numkeys", c.numKeys and 1 or 0)
  ring:SetAttribute("rz-keydown", keyDownSetting())
  ring:SetAttribute("rz-sector", c.sector and 1 or 0)
  local r, g, bl = lookColor()
  -- wheel band: its middle sits on the slot circle
  local half = R / 0.711
  ring.wheel:SetSize(half * 2, half * 2); ring.wheel:SetVertexColor(0.02, 0.02, 0.03, clamp(l.wheelAlpha, 0, 1)); ring.wheel:SetShown(l.wheel)
  ring.spin:SetSize((R + px * 0.62) * 2, (R + px * 0.62) * 2); ring.spin:SetVertexColor(r, g, bl, 0.55); ring.spin:SetShown(l.spin)
  local cs = math.max(40, math.min(R * 0.95, 96))
  center:SetSize(cs, cs)
  paintSlot(center, nil, cs, nil, true)
  center.edge:SetVertexColor(r, g, bl, 0.9); center.bg:SetVertexColor(0, 0, 0, 0.75); center:SetAlpha(1)
  center.icon:Hide()
  center.title:SetWidth(cs - 8); center.sub:SetWidth(cs + 40)
  center.title:SetShown(l.center or l.labels == "center")
  ring:SetAttribute("rz-dead", (cs / 2) * (cs / 2))

  for p, pg in ipairs(c.pages) do
    local f = pages[p] or newPageFrame(p)
    pages[p] = f
    local n = clamp(pg.slots, MIN_SLOTS, MAX_SLOTS)
    ring:SetAttribute("rz-n" .. p, n)
    for s = 1, MAX_SLOTS do
      local b = f.slots[s]
      if s <= n then
        if not b then b = newSlot(f, p, s); f.slots[s] = b end
        local a = math.rad(90 - (s - 1) * 360 / n)
        b:ClearAllPoints()
        b:SetPoint("CENTER", ring, "CENTER", math.cos(a) * R, math.sin(a) * R)
        b.vx, b.vy = math.cos(a), math.sin(a)
        ring:SetAttribute("rz-vx" .. p .. "_" .. s, b.vx)
        ring:SetAttribute("rz-vy" .. p .. "_" .. s, b.vy)
        local it = pg.items[s]
        applySlot(b, it, c)
        ring:SetAttribute("rz-has" .. p .. "_" .. s, (b:GetAttribute("type") or b:GetAttribute("rz-page")) and 1 or 0)
        paintSlot(b, it, px, s)
        b:SetShown(it ~= nil or l.empty)
      elseif b then
        applySlot(b, nil, c); b.rec = nil; b:Hide()
      end
    end
  end
  for p = #c.pages + 1, #pages do pages[p]:Hide() end

  -- the key
  ClearOverrideBindings(openBtn)
  if c.on and c.key then SetOverrideBindingClick(openBtn, true, c.key, "CC_RadialzOpen", "LeftButton") end
end
S.RadialzRebuild = function() rebuild() end

-- repaint the shown page (centre text, slot looks) - safe in combat
function refreshVisible()
  if not ring then return end
  local cur = ring:GetAttribute("rz-cur") or 0
  local pg = cfg().pages[cur]
  if not pg then return end
  local depth = ring:GetAttribute("rz-depth") or 1
  center.title:SetText(L().center and pg.name or "")
  center.sub:SetText("")
  center.hoverName = nil
  local f = pages[cur]
  if f then for _, b in ipairs(f.slots) do if b.rec then pcall(stateSlot, b) end end end
  center.back = depth > 1
end

function onSlotEnter(b)
  local l = L()
  if b.rec then b.glow:Show() end
  if l.labels == "center" and b.recName and center then center.title:SetText(b.recName) end
  if not l.tips or not b.rec then return end
  local it = b.rec
  GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
  local ok = false
  if it.kind == "spell" and it.id and GameTooltip.SetSpellByID then ok = pcall(GameTooltip.SetSpellByID, GameTooltip, it.id)
  elseif it.kind == "item" and it.id and GameTooltip.SetItemByID then ok = pcall(GameTooltip.SetItemByID, GameTooltip, it.id) end
  if not ok then
    GameTooltip:AddLine(b.recName or "", 1, 1, 1)
    if it.kind == "page" then GameTooltip:AddLine("Opens this page", 0.7, 0.7, 0.7) end
    if it.kind == "text" and it.text then GameTooltip:AddLine(it.text, 0.7, 0.7, 0.7, true) end
  end
  GameTooltip:Show()
end
function onSlotLeave(b)
  b.glow:Hide()
  GameTooltip:Hide()
  if center and ring then
    local pg = cfg().pages[ring:GetAttribute("rz-cur") or 0]
    center.title:SetText((pg and L().center) and pg.name or "")
  end
end
-- drop something on a live slot (out of combat)
function onSlotDrop(b)
  if combat() then return end
  local rec = recordFromCursor()
  if not rec then return end
  ClearCursor()
  local pg = cfg().pages[b.p]
  if not pg then return end
  pg.items[b.s] = rec
  rebuild()
  if S.RadialzEditorRefresh then S.RadialzEditorRefresh() end
end

-- open the wheel from Lua (settings "Try it", slash command) - out of combat
function S:RadialzOpen()
  if combat() then S:Print("Radialz: use your key in combat (" .. tostring(cfg().key) .. ").") return end
  rebuild()
  if ring:IsShown() then SecureHandlerExecute(ring, [[ control:RunAttribute("rz-close") ]])
  else SecureHandlerExecute(ring, [[ control:RunAttribute("rz-open") ]]) end
end

S:Listen("LOGIN", function() rebuild() end)
S:On("PLAYER_REGEN_ENABLED", function() if dirty then rebuild() end end)
S:On("CVAR_UPDATE", function() if ring and not combat() then ring:SetAttribute("rz-keydown", keyDownSetting()) end end)
-- names / icons the game hadn't loaded yet (items, macros): repaint the slots
local function repaint()
  if not ring or combat() then dirty = dirty or ring ~= nil; return end
  local c, l = cfg(), L()
  local px = clamp(l.size, 20, 80)
  for p, pg in ipairs(c.pages) do
    local f = pages[p]
    if f then for s, b in ipairs(f.slots) do if s <= pg.slots then paintSlot(b, pg.items[s], px, s) end end end
  end
end
local function usesItem(id)
  for _, pg in ipairs(cfg().pages) do for _, it in pairs(pg.items) do if it.kind == "item" and it.id == id then return true end end end
end
local pendingPaint = false
local function paintSoon()
  if pendingPaint then return end
  pendingPaint = true
  C_Timer.After(0.5, function()
    pendingPaint = false
    repaint()
    if S.RadialzEditorRefresh then S.RadialzEditorRefresh() end
  end)
end
S:On("GET_ITEM_INFO_RECEIVED", function(_, id) if S.db and usesItem(tonumber(id)) then paintSoon() end end)
S:On("UPDATE_MACROS", paintSoon)
S:On("SPELLS_CHANGED", paintSoon)

---------------------------------------------------------------------------
-- Small helpers for the settings window
---------------------------------------------------------------------------
local function keyText(k)
  if type(k) ~= "string" or k == "" then return "(none)" end
  local parts = {}
  for part in k:gmatch("[^%-]+") do parts[#parts + 1] = part end
  if k:sub(-1) == "-" then parts[#parts + 1] = "-" end
  local base = table.remove(parts) or k
  local nice
  if base == "BUTTON3" then nice = "Middle mouse button"
  elseif base:match("^BUTTON%d+$") then nice = "Mouse button " .. base:match("%d+")
  elseif base == "MOUSEWHEELUP" then nice = "Mouse wheel up"
  elseif base == "MOUSEWHEELDOWN" then nice = "Mouse wheel down"
  else nice = (GetBindingText and GetBindingText(base, "KEY_")) or base end
  local out = {}
  for _, m in ipairs(parts) do out[#out + 1] = m:sub(1, 1) .. m:sub(2):lower() end
  out[#out + 1] = nice
  return table.concat(out, " + ")
end

local function changed()
  rebuild()
  if S.RadialzEditorRefresh then S.RadialzEditorRefresh() end
end

-- icon picker (the game's macro icons); onPick(icon or nil for automatic)
local picker
local function pickIcon(title, onPick)
  local COLS, ROWS, SZ = 10, 6, 36
  if not picker then
    picker = UI:Window("CC_RadialzIcons", "Pick an icon", COLS * (SZ + 4) + 32, ROWS * (SZ + 4) + 150)
    picker:SetFrameStrata("FULLSCREEN_DIALOG")
    picker.list = {}
    local function load()
      if #picker.list > 0 then return end
      for _, f in ipairs({ GetLooseMacroIcons, GetMacroIcons, GetLooseMacroItemIcons, GetMacroItemIcons }) do
        if f then pcall(f, picker.list) end
      end
    end
    picker.load = load
    picker.btns = {}
    local function paint()
      local per = COLS * ROWS
      local maxOff = math.max(0, math.ceil(#picker.list / COLS) * COLS - per)
      picker.off = clamp(picker.off or 0, 0, maxOff)
      picker.off = picker.off - picker.off % COLS
      for k, b in ipairs(picker.btns) do
        local v = picker.list[picker.off + k]
        b.v = v
        if v then b.tex:SetTexture(type(v) == "number" and v or ("Interface\\Icons\\" .. tostring(v))); b:Show() else b:Hide() end
      end
      picker.info:SetText(#picker.list == 0 and "The game gave no icon list." or
        string.format("%d-%d of %d   -   or drop a spell or item here to use its icon", picker.off + 1, math.min(#picker.list, picker.off + per), #picker.list))
    end
    picker.paint = paint
    for k = 1, COLS * ROWS do
      local b = CreateFrame("Button", nil, picker)
      b:SetSize(SZ, SZ)
      b:SetPoint("TOPLEFT", 16 + ((k - 1) % COLS) * (SZ + 4), -42 - math.floor((k - 1) / COLS) * (SZ + 4))
      b.tex = b:CreateTexture(nil, "ARTWORK"); b.tex:SetAllPoints(); b.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
      b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
      b:SetScript("OnClick", function(self) if self.v and picker.onPick then picker.onPick(type(self.v) == "number" and self.v or ("Interface\\Icons\\" .. self.v)); picker:Hide() end end)
      picker.btns[k] = b
    end
    picker:EnableMouseWheel(true)
    picker:SetScript("OnMouseWheel", function(_, d) picker.off = (picker.off or 0) - d * COLS * 2; paint() end)
    local function takeDrop()
      local rec = recordFromCursor()
      if not rec then return end
      ClearCursor()
      local icon = slotLook(rec)
      if icon and picker.onPick then picker.onPick(icon); picker:Hide() end
    end
    picker:SetScript("OnReceiveDrag", takeDrop)
    picker:HookScript("OnMouseUp", function() if GetCursorInfo and GetCursorInfo() then takeDrop() end end)
    local by = -42 - ROWS * (SZ + 4) - 6
    picker.info = UI:Text(picker, "", "muted")
    picker.info:SetPoint("TOPLEFT", 16, by - 4)
    local up = UI:Button(picker, "Up", 60, 22, function() picker.off = (picker.off or 0) - COLS * ROWS; paint() end)
    up:SetPoint("BOTTOMLEFT", 16, 16)
    local dn = UI:Button(picker, "Down", 60, 22, function() picker.off = (picker.off or 0) + COLS * ROWS; paint() end)
    dn:SetPoint("LEFT", up, "RIGHT", 6, 0)
    local auto = UI:PrimaryButton(picker, "Automatic", 110, 22, function() if picker.onPick then picker.onPick(nil) end picker:Hide() end,
      "Use the icon of whatever is in the slot (or the page's own icon).")
    auto:SetPoint("BOTTOMRIGHT", -16, 16)
  end
  picker.title:SetText(title or "Pick an icon")
  picker.onPick = onPick
  picker.load()
  picker.paint()
  picker:Show(); picker:Raise()
end

---------------------------------------------------------------------------
-- Preview wheel (plain frames, used in the settings window)
---------------------------------------------------------------------------
-- dragging a slot in the preview: a ghost icon follows the mouse; let go on
-- another slot to move it there (the two swap), on a page in the list to send it
-- to that page; hold Ctrl to copy instead of move
local ghost
local function dragGhost(icon, px)
  if not ghost then
    ghost = CreateFrame("Frame", nil, UIParent)
    ghost:SetFrameStrata("TOOLTIP")
    ghost.icon = ghost:CreateTexture(nil, "ARTWORK"); ghost.icon:SetAllPoints(); ghost.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    if ghost.CreateMaskTexture then
      ghost.mask = ghost:CreateMaskTexture(); ghost.mask:SetAllPoints(ghost.icon); ghost.icon:AddMaskTexture(ghost.mask)
    end
    ghost.edge = ghost:CreateTexture(nil, "OVERLAY"); ghost.edge:SetAllPoints()
    ghost.tag = ghost:CreateFontString(nil, "OVERLAY"); ghost.tag:SetFontObject(UI.fSmall); ghost.tag:SetPoint("TOP", ghost, "BOTTOM", 0, -2)
    ghost:SetScript("OnUpdate", function(self)
      local x, y = GetCursorPosition()
      local sc = UIParent:GetEffectiveScale()
      self:ClearAllPoints(); self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / sc, y / sc)
      self.tag:SetText((self.tagFn and self.tagFn()) or (IsControlKeyDown() and "|cff88ff88+ copy|r" or ""))
      if self.onMove then self.onMove() end
    end)
    ghost:Hide()
  end
  local rd = clamp(L().round, 0, 5)
  local r, g, bl = lookColor()
  ghost:SetSize(px, px)
  ghost.icon:SetTexture(icon or EMPTY_ICON)
  setMask(ghost.icon, ghost.mask, rd)
  ghost.edge:SetTexture(MEDIA .. "rring" .. rd); ghost.edge:SetVertexColor(r, g, bl, 1)
  ghost:SetAlpha(0.85)
  ghost:Show()
  return ghost
end

local function makePreview(parent, size, onSlotClick, onSlotMove)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(size, size)
  f.wheel = f:CreateTexture(nil, "BACKGROUND"); f.wheel:SetTexture(MEDIA .. "rz_wheel"); f.wheel:SetPoint("CENTER")
  f.spin = f:CreateTexture(nil, "BORDER"); f.spin:SetTexture(MEDIA .. "rz_spin"); f.spin:SetPoint("CENTER"); f.spin:SetBlendMode("ADD")
  f.slots = {}
  for s = 1, MAX_SLOTS do
    local b = CreateFrame("Button", nil, f)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    decorate(b)
    b.s = s
    b.sel = b:CreateTexture(nil, "OVERLAY", nil, 2)
    b.sel:SetPoint("CENTER")
    b:SetScript("OnClick", function(self, btn)
      if f.draggedAt and GetTime() - f.draggedAt < 0.3 then return end
      onSlotClick(self.s, btn)
    end)
    b:SetScript("OnDragStart", function(self)
      if not self.rec or not onSlotMove then return end
      f.dragFrom = self.s
      self:SetAlpha(0.35)
      GameTooltip:Hide()
      local gh = dragGhost(self.icon:GetTexture(), self:GetWidth())
      gh.tagFn = function()
        if f:IsMouseOver() then return IsControlKeyDown() and "|cff88ff88+ copy|r" or "" end
        local t = f.offTag and f.offTag(IsControlKeyDown())
        if t then return t end
        return IsControlKeyDown() and "" or "|cffff5555remove|r"
      end
      gh.onMove = function()
        for _, o in ipairs(f.slots) do
          if o:IsShown() then o.glow:SetShown(o.s ~= f.dragFrom and o:IsMouseOver()) end
        end
      end
    end)
    b:SetScript("OnDragStop", function(self)
      if not f.dragFrom then return end
      local from = f.dragFrom
      f.dragFrom = nil
      f.draggedAt = GetTime()
      if ghost then ghost:Hide(); ghost.onMove = nil; ghost.tagFn = nil end
      local to
      for _, o in ipairs(f.slots) do
        o.glow:Hide()
        if o:IsShown() and o:IsMouseOver() then to = o.s end
      end
      self:SetAlpha(1)
      onSlotMove(from, to, IsControlKeyDown(), f:IsMouseOver())
    end)
    b:SetScript("OnReceiveDrag", function(self) onSlotClick(self.s, "drop") end)
    b:SetScript("OnEnter", function(self)
      self.glow:Show()
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine(self.recName or ("Slot " .. self.s .. " (empty)"), 1, 0.82, 0)
      GameTooltip:AddLine("Left-click: edit this slot", 1, 1, 1)
      GameTooltip:AddLine("Right-click: clear it", 1, 1, 1)
      if self.rec then GameTooltip:AddLine("Drag: move it to another slot or a page in the list (Ctrl = copy); drop it off the wheel to remove it", 1, 1, 1, true) end
      GameTooltip:AddLine("Drag a spell, item or macro here to put it on this slot.", 0.7, 0.7, 0.7, true)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self) self.glow:Hide(); GameTooltip:Hide() end)
    f.slots[s] = b
  end
  f.center = CreateFrame("Frame", nil, f)
  f.center:SetPoint("CENTER")
  decorate(f.center)
  f.center.icon:Hide()
  f.center.title = f.center:CreateFontString(nil, "OVERLAY")
  f.center.title:SetFontObject(UI.fNormal); f.center.title:SetPoint("CENTER"); f.center.title:SetJustifyH("CENTER")

  function f:Paint(pi, selSlot)
    local c, l = cfg(), L()
    local pg = c.pages[pi]
    if not pg then return end
    local R, px = clamp(l.radius, 60, 240), clamp(l.size, 20, 80)
    local k = math.min(1, (size / 2 - 6) / (R + px * 0.8))
    local r, g, bl = lookColor()
    local half = R / 0.711 * k
    self.wheel:SetSize(half * 2, half * 2); self.wheel:SetVertexColor(0.02, 0.02, 0.03, clamp(l.wheelAlpha, 0, 1)); self.wheel:SetShown(l.wheel)
    local sp = (R + px * 0.62) * k
    self.spin:SetSize(sp * 2, sp * 2); self.spin:SetVertexColor(r, g, bl, 0.55); self.spin:SetShown(l.spin)
    local n = clamp(pg.slots, MIN_SLOTS, MAX_SLOTS)
    for s, b in ipairs(self.slots) do
      if s <= n then
        local a = math.rad(90 - (s - 1) * 360 / n)
        b:ClearAllPoints(); b:SetPoint("CENTER", self, "CENTER", math.cos(a) * R * k, math.sin(a) * R * k)
        paintSlot(b, pg.items[s], px * k, s, true)
        b.sel:SetTexture(MEDIA .. "rring" .. clamp(l.round, 0, 5))
        b.sel:SetSize(px * k + 8, px * k + 8); b.sel:SetVertexColor(1, 1, 1, 1)
        b.sel:SetShown(s == selSlot)
        b:Show()
      else
        b:Hide()
      end
    end
    local cs = math.max(40, math.min(R * 0.95, 96)) * k
    paintSlot(self.center, nil, cs, nil, true)
    self.center.edge:SetVertexColor(r, g, bl, 0.9); self.center.bg:SetVertexColor(0, 0, 0, 0.75)
    self.center.title:SetWidth(cs - 6)
    self.center.title:SetText(l.center and pg.name or "")
  end
  return f
end

---------------------------------------------------------------------------
-- Settings window: Wheel (pages + slots), Look, Key
---------------------------------------------------------------------------
local win
local sel = { page = 1, slot = 1 }
local W, H = 830, 580

local function curPage() local c = cfg(); sel.page = clamp(sel.page, 1, #c.pages); return c.pages[sel.page], c end
local function curItem() local pg = curPage(); return pg and pg.items[sel.slot] end
local function setItem(rec)
  local pg = curPage()
  if not pg then return end
  pg.items[sel.slot] = rec
  changed()
end

-- slot dragged in the preview: to = slot on this page, or nil (maybe a page row)
local function copyRec(it)
  local out = {}
  for k, v in pairs(it) do out[k] = v end
  return out
end
-- the page row under the mouse while dragging (not the page being edited)
local function pageRowUnderMouse()
  for _, r in ipairs(win.rows or {}) do
    if r:IsShown() and r.idx and r:IsMouseOver() and r.idx ~= sel.page then return r end
  end
end
local function onPreviewMove(from, to, copy, overWheel)
  local pg, c = curPage()
  local it = pg and pg.items[from]
  if not it then return end
  if to then
    if to == from then return end
    if copy then
      pg.items[to] = copyRec(it)
    else
      pg.items[from], pg.items[to] = pg.items[to], it
    end
    sel.slot = to
    changed()
    return
  end
  -- let go on a page in the list: first free slot on that page
  local r = pageRowUnderMouse()
  if r then
    do
      local dest = c.pages[r.idx]
      if it.kind == "page" and it.page == dest.id then UI:Alert("A page can't hold a slot that opens itself.") return end
      local free
      for s = 1, dest.slots do if not dest.items[s] then free = s break end end
      if not free then UI:Alert("The page \"" .. tostring(dest.name) .. "\" has no free slot. Add slots to it or clear one first.") return end
      dest.items[free] = copy and copyRec(it) or it
      if not copy then pg.items[from] = nil end
      sel.page, sel.slot = r.idx, free
      changed()
      return
    end
  end
  -- let go anywhere off the wheel: take it off (Ctrl = copy, so nothing happens)
  if not overWheel and not copy then
    pg.items[from] = nil
    sel.slot = from
    changed()
  end
end

local function onPreviewSlot(s, btn)
  local pg = curPage()
  if not pg then return end
  sel.slot = s
  if btn == "drop" or (GetCursorInfo and GetCursorInfo()) then
    local rec = recordFromCursor()
    if rec then ClearCursor(); setItem(rec) return end
  end
  if btn == "RightButton" then setItem(nil) return end
  if S.RadialzEditorRefresh then S.RadialzEditorRefresh() end
end

local function buildWindow()
  win = UI:Window("CC_Radialz", "Radialz", W, H)
  local panes = {}
  for i = 1, 3 do
    local p = CreateFrame("Frame", nil, win)
    p:SetPoint("TOPLEFT", 0, -70); p:SetPoint("BOTTOMRIGHT", 0, 0)
    p:Hide()
    panes[i] = p
  end
  win.preview = makePreview(win, 320, onPreviewSlot, onPreviewMove)
  win.preview.offTag = function(ctrl)
    local r = pageRowUnderMouse()
    if r then
      local p = cfg().pages[r.idx]
      return "|cff88ff88" .. (ctrl and "copy to " or "to ") .. tostring(p and p.name) .. "|r"
    end
  end
  win.status = UI:Text(win, "", "small")
  win.status:SetPoint("BOTTOMLEFT", 16, 14)

  local tabs = UI:SubTabs(win, { "Wheel", "Look", "Key" }, function(i)
    for j, p in ipairs(panes) do p:SetShown(i == j) end
    win.tab = i
    win.preview:ClearAllPoints()
    if i == 1 then win.preview:SetPoint("TOPLEFT", 214, -86) else win.preview:SetPoint("TOPRIGHT", -40, -96) end
    win.preview:SetShown(i ~= 3)
    if S.RadialzEditorRefresh then S.RadialzEditorRefresh() end
  end)
  tabs:SetPoint("TOPLEFT", 16, -36); tabs:SetPoint("RIGHT", -16, 0)

  -------------------------------------------------------------- Wheel tab
  local pw = panes[1]
  local hp = UI:Header(pw, "Pages"); hp:SetPoint("TOPLEFT", 16, -10)
  local tip = UI:Text(pw, "The first page opens with the key.", "muted"); tip:SetPoint("TOPLEFT", 16, -30); tip:SetWidth(186)
  win.rows = {}
  local ROWS = 11
  for i = 1, ROWS do
    local r = CreateFrame("Button", nil, pw, BackdropTemplateMixin and "BackdropTemplate" or nil)
    r:SetSize(186, 24)
    r:SetPoint("TOPLEFT", 16, -50 - (i - 1) * 26)
    r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(18, 18); r.icon:SetPoint("LEFT", 4, 0); r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    r.text = UI:Text(r, "", "normal"); r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0); r.text:SetPoint("RIGHT", -6, 0); r.text:SetWordWrap(false)
    r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints(); r.bg:SetColorTexture(1, 1, 1, 0.06)
    r.hl = r:CreateTexture(nil, "BORDER"); r.hl:SetPoint("TOPLEFT"); r.hl:SetPoint("BOTTOMLEFT"); r.hl:SetWidth(3)
    r:SetScript("OnClick", function(self) if self.idx then sel.page = self.idx; sel.slot = 1; S.RadialzEditorRefresh() end end)
    r:SetScript("OnEnter", function(self) self.bg:SetColorTexture(1, 1, 1, 0.12) end)
    r:SetScript("OnLeave", function(self) self.bg:SetColorTexture(1, 1, 1, 0.06) end)
    win.rows[i] = r
  end
  pw:EnableMouseWheel(true)
  pw:SetScript("OnMouseWheel", function(_, d) win.rowOff = (win.rowOff or 0) - d; S.RadialzEditorRefresh() end)
  local by = -50 - ROWS * 26 - 6
  local function pbtn(text, x, y, w, fn, tipText)
    local b = UI:Button(pw, text, w, 22, fn, tipText); b:SetPoint("TOPLEFT", x, y); return b
  end
  pbtn("New", 16, by, 60, function()
    local c = cfg()
    if #c.pages >= MAX_PAGES then UI:Alert("Radialz has room for " .. MAX_PAGES .. " pages.") return end
    UI:Prompt("Name of the new page:", "Page " .. (#c.pages + 1), function(name)
      local p = newPage(c, (name ~= "" and name) or nil, 8)
      c.pages[#c.pages + 1] = p
      sel.page, sel.slot = #c.pages, 1
      changed()
    end)
  end, "Add a page. Put an \"Open a page\" slot on another page to reach it.")
  pbtn("Rename", 79, by, 62, function()
    local pg = curPage()
    UI:Prompt("Name of this page:", pg.name or "", function(name) if name ~= "" then pg.name = name; changed() end end)
  end)
  pbtn("Icon", 144, by, 58, function()
    local pg = curPage()
    pickIcon("Icon of the page \"" .. tostring(pg.name) .. "\"", function(icon) pg.icon = icon; changed() end)
  end, "The icon slots that open this page show.")
  pbtn("Up", 16, by - 26, 60, function()
    local pg, c = curPage()
    if sel.page > 1 then c.pages[sel.page], c.pages[sel.page - 1] = c.pages[sel.page - 1], pg; sel.page = sel.page - 1; changed() end
  end, "Move the page up. The top page is the one the key opens.")
  pbtn("Down", 79, by - 26, 62, function()
    local pg, c = curPage()
    if sel.page < #c.pages then c.pages[sel.page], c.pages[sel.page + 1] = c.pages[sel.page + 1], pg; sel.page = sel.page + 1; changed() end
  end)
  pbtn("Delete", 144, by - 26, 58, function()
    local pg, c = curPage()
    if #c.pages <= 1 then UI:Alert("Radialz needs at least one page.") return end
    UI:Confirm("Delete the page \"" .. tostring(pg.name) .. "\"?\nSlots that open it are cleared.", function()
      table.remove(c.pages, sel.page)
      for _, other in ipairs(c.pages) do
        for s, it in pairs(other.items) do if it.kind == "page" and it.page == pg.id then other.items[s] = nil end end
      end
      sel.page, sel.slot = math.max(1, sel.page - 1), 1
      changed()
    end, "Delete")
  end)
  local slotOpts = {}
  for n = MIN_SLOTS, MAX_SLOTS do slotOpts[#slotOpts + 1] = { value = n, text = n .. " slots" } end
  local st = UI:Text(pw, "This page has", "small"); st:SetPoint("TOPLEFT", 16, by - 62)
  win.slotsDD = UI:Dropdown(pw, 96, slotOpts, 8, function(v)
    local pg = curPage(); pg.slots = v; if sel.slot > v then sel.slot = 1 end; changed()
  end)
  win.slotsDD:SetPoint("TOPLEFT", 106, by - 56)

  -- slot editor (right column)
  local X = 556
  win.slotHead = UI:Header(pw, "Slot"); win.slotHead:SetPoint("TOPLEFT", X, -10)
  local kl = UI:Text(pw, "What it does", "small"); kl:SetPoint("TOPLEFT", X, -38)
  win.kind = UI:Dropdown(pw, 250, KINDS, "none", function(v)
    local it = curItem()
    if v == "none" then setItem(nil) return end
    if it and it.kind == v then return end
    if v == "page" then
      local c = cfg()
      local target
      for i, p in ipairs(c.pages) do if i ~= sel.page then target = p.id break end end
      if not target then
        local p = newPage(c, nil, 6); c.pages[#c.pages + 1] = p; target = p.id
      end
      setItem({ kind = "page", page = target })
    elseif v == "text" then
      setItem({ kind = "text", text = "" })
    else
      setItem({ kind = v })
    end
  end)
  win.kind:SetPoint("TOPLEFT", X, -54)

  win.nameL = UI:Text(pw, "", "small"); win.nameL:SetPoint("TOPLEFT", X, -88)
  local function applyName(text)
    local it = curItem()
    if not it then return end
    text = S.Trim(text)
    if it.kind == "spell" then
      local id = spellIdByName(text)
      it.id, it.name = id, (id and spellName(id)) or (text ~= "" and text or nil)
    elseif it.kind == "item" then
      local id = itemIdByName(text)
      it.id, it.name = id, (not id and text ~= "") and text or nil
    elseif it.kind == "macro" then
      it.name = text ~= "" and text or nil
    end
    changed()
  end
  win.nameE = UI:Edit(pw, 250, 24, "", function(_, text) applyName(text) end)
  win.nameE:SetPoint("TOPLEFT", X, -104)
  win.nameE:HookScript("OnEditFocusLost", function(self) if self.dirtyText then self.dirtyText = nil; applyName(self:GetText()) end end)
  win.nameE:HookScript("OnTextChanged", function(self, user) if user then self.dirtyText = true end end)
  win.nameE:SetScript("OnReceiveDrag", function() onPreviewSlot(sel.slot, "drop") end)

  -- macro text
  win.textBox = UI:Panel(pw, 250, 96, { 0, 0, 0, 0.5 })
  win.textBox:SetPoint("TOPLEFT", X, -104)
  win.textE = CreateFrame("EditBox", nil, win.textBox)
  win.textE:SetMultiLine(true); win.textE:SetAutoFocus(false); win.textE:SetFontObject(UI.fSmall)
  win.textE:SetPoint("TOPLEFT", 6, -6); win.textE:SetPoint("BOTTOMRIGHT", -6, 6); win.textE:SetMaxLetters(255)
  win.textE:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  win.textBox:EnableMouse(true)
  win.textBox:SetScript("OnMouseDown", function() win.textE:SetFocus() end)
  local function saveText()
    local it = curItem()
    if it and it.kind == "text" then it.text = win.textE:GetText() or ""; changed() end
  end
  win.textE:SetScript("OnEditFocusLost", saveText)

  -- page target
  win.pageDD = UI:Dropdown(pw, 250, function()
    local out = {}
    for i, p in ipairs(cfg().pages) do if i ~= sel.page then out[#out + 1] = { value = p.id, text = p.name } end end
    return out
  end, nil, function(v) local it = curItem(); if it then it.page = v; changed() end end)
  win.pageDD:SetPoint("TOPLEFT", X, -104)

  local ll = UI:Text(pw, "Label (optional - shown instead of the name)", "small"); ll:SetPoint("TOPLEFT", X, -212)
  win.labelE = UI:Edit(pw, 250, 24, "", function(_, text)
    local it = curItem(); if it then it.label = S.Trim(text) ~= "" and S.Trim(text) or nil; changed() end
  end)
  win.labelE:SetPoint("TOPLEFT", X, -228)
  win.labelE:HookScript("OnEditFocusLost", function(self)
    local it = curItem()
    local t = S.Trim(self:GetText())
    if it and (it.label or "") ~= t then it.label = t ~= "" and t or nil; changed() end
  end)
  win.iconB = UI:Button(pw, "Icon...", 120, 22, function()
    local it = curItem(); if not it then return end
    pickIcon("Icon of slot " .. sel.slot, function(icon) it.icon = icon; changed() end)
  end, "Pick your own icon for this slot (Automatic = the spell's / item's own).")
  win.iconB:SetPoint("TOPLEFT", X, -262)
  win.clearB = UI:Button(pw, "Clear slot", 120, 22, function() setItem(nil) end)
  win.clearB:SetPoint("LEFT", win.iconB, "RIGHT", 10, 0)
  win.slotHelp = UI:Text(pw, "", "muted"); win.slotHelp:SetPoint("TOPLEFT", X, -296); win.slotHelp:SetWidth(250)
  win.slotHelp:SetText("Drag a spell from your spellbook, an item from your bags or a macro from the macro window onto a slot of the wheel. " ..
    "Drag a slot onto another to move it (they swap), or onto a page in the list to send it there. Hold Ctrl to copy. Drop it anywhere off the wheel to take it off.\n\nIn game: press " ..
    "your key to open it, left-click a slot, press the key again (or Escape) to close. Left-click the centre to go back a page.")

  -------------------------------------------------------------- Look tab
  local pl = panes[2]
  local y = -12
  local LW = 400
  local function sl(label, lo, hi, step, key, fmt, scale)
    local s = UI:Slider(pl, LW, label, lo, hi, step, 0, function(v) L()[key] = scale and v / scale or v; changed() end, fmt)
    s:SetPoint("TOPLEFT", 18, y); y = y - 28
    s.key, s.scale = key, scale
    return s
  end
  local function ck(label, key, tipText)
    local b = UI:Check(pl, label, false, function(on) L()[key] = on; changed() end, tipText)
    b:SetPoint("TOPLEFT", 18, y); y = y - 26
    b.key = key
    return b
  end
  local function dd(label, opts, key)
    local t = UI:Text(pl, label, "small"); t:SetPoint("TOPLEFT", 18, y - 5)
    local d = UI:Dropdown(pl, 220, opts, nil, function(v) L()[key] = v; changed() end)
    d:SetPoint("TOPLEFT", 154, y); y = y - 30
    d.key = key
    return d
  end
  local RN = { [0] = "Square", "Slight", "Rounded", "More", "Very round", "Circle" }
  win.lookSl = {
    sl("Wheel size", 60, 220, 5, "radius"),
    sl("Slot size", 24, 72, 2, "size"),
    sl("Slot roundness", 0, 5, 1, "round", function(v) return RN[v] or v end),
    sl("Background opacity", 0, 100, 5, "wheelAlpha", function(v) return v .. "%" end, 100),
  }
  y = y - 4
  win.lookDD = {
    dd("Colour", COLORS, "color"),
    dd("Names", { { value = "center", text = "In the centre on hover" }, { value = "each", text = "Under every slot" }, { value = "none", text = "No names" } }, "labels"),
    dd("Opening", { { value = "fade", text = "Fade in + spinning ring" }, { value = "none", text = "Instant, no animation" } }, "anim"),
  }
  y = y - 4
  win.lookCk = {
    ck("Wheel background", "wheel", "A dark band behind the slots."),
    ck("Spinning ring", "spin", "A thin ring in your colour turning slowly behind the slots."),
    ck("Page name in the centre", "center"),
    ck("Tooltips on hover", "tips"),
    ck("Cooldown swipes", "cooldowns"),
    ck("Item counts", "counts"),
    ck("Dim slots you can't use now", "dim", "Out of mana, no target, item not in your bags..."),
    ck("Show empty slots", "empty", "Empty slots show as a faint ring (handy for dropping spells on them)."),
  }
  local try1 = UI:PrimaryButton(pl, "Try it", 120, 24, function() S:RadialzOpen() end, "Opens the wheel now (close it with your key, Escape or a click outside).")
  try1:SetPoint("BOTTOMRIGHT", -40, 40)

  -------------------------------------------------------------- Key tab
  local pk = panes[3]
  y = -14
  win.onCk = UI:Check(pk, "Use Radialz (your key opens the wheel)", true, function(on) cfg().on = on; changed() end)
  win.onCk:SetPoint("TOPLEFT", 18, y); y = y - 36
  local kt = UI:Text(pk, "Key", "small"); kt:SetPoint("TOPLEFT", 18, y - 5)
  win.keyDD = UI:Dropdown(pk, 220, function()
    local out = { { value = "BUTTON5", text = keyText("BUTTON5") }, { value = "BUTTON4", text = keyText("BUTTON4") }, { value = "BUTTON3", text = keyText("BUTTON3") } }
    local k = cfg().key
    if k ~= "BUTTON5" and k ~= "BUTTON4" and k ~= "BUTTON3" then out[#out + 1] = { value = k, text = keyText(k) } end
    return out
  end, "BUTTON5", function(v) cfg().key = v; changed() end)
  win.keyDD:SetPoint("TOPLEFT", 154, y)
  -- press-a-key catcher
  local cap = CreateFrame("Button", nil, win, BackdropTemplateMixin and "BackdropTemplate" or nil)
  cap:SetAllPoints(win); cap:SetFrameLevel(win:GetFrameLevel() + 50); cap:Hide()
  cap.bg = cap:CreateTexture(nil, "BACKGROUND"); cap.bg:SetAllPoints(); cap.bg:SetColorTexture(0, 0, 0, 0.8)
  cap.text = UI:Text(cap, "Press a key or a mouse button (with Shift / Ctrl / Alt if you like)\n\nEscape cancels", "large", "CENTER")
  cap.text:SetPoint("CENTER")
  cap:RegisterForClicks("AnyUp")
  local function mods()
    return (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "") .. (IsShiftKeyDown() and "SHIFT-" or "")
  end
  local function take(key)
    cap:Hide()
    cap:EnableKeyboard(false)
    if not key then return end
    cfg().key = key
    changed()
  end
  local IGNORE = { LSHIFT = 1, RSHIFT = 1, LCTRL = 1, RCTRL = 1, LALT = 1, RALT = 1, LMETA = 1, RMETA = 1, UNKNOWN = 1 }
  cap:SetScript("OnKeyDown", function(self, key)
    if IGNORE[key] then return end
    if key == "ESCAPE" then take(nil) return end
    take(mods() .. key)
  end)
  cap:SetScript("OnMouseDown", function(self, btn)
    local map = { MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }
    local b = map[btn] or (btn and btn:match("^Button(%d+)$") and ("BUTTON" .. btn:match("%d+")))
    if btn == "LeftButton" or btn == "RightButton" then
      self.text:SetText("Left and right click can't open the wheel - pick another button or key.\n\nEscape cancels")
      return
    end
    if b then take(mods() .. b) end
  end)
  cap:SetScript("OnShow", function(self)
    self.text:SetText("Press a key or a mouse button (with Shift / Ctrl / Alt if you like)\n\nEscape cancels")
    self:EnableKeyboard(true)
    if self.SetPropagateKeyboardInput and not combat() then self:SetPropagateKeyboardInput(false) end
  end)
  local setKey = UI:Button(pk, "Set a key...", 110, 24, function() cap:Show(); cap:Raise() end, "Use any key, mouse button or combination.")
  setKey:SetPoint("LEFT", win.keyDD, "RIGHT", 10, 0)
  y = y - 36
  local ot = UI:Text(pk, "Opens", "small"); ot:SetPoint("TOPLEFT", 18, y - 5)
  win.atDD = UI:Dropdown(pk, 220, { { value = "mouse", text = "At the mouse" }, { value = "center", text = "In the middle of the screen" } }, "mouse",
    function(v) cfg().openAt = v; changed() end)
  win.atDD:SetPoint("TOPLEFT", 154, y); y = y - 38
  win.closeCk = UI:Check(pk, "Close after using a slot", true, function(on) cfg().closeOnUse = on; changed() end,
    "Off: the wheel stays open until you press the key again, so you can use several slots in a row.")
  win.closeCk:SetPoint("TOPLEFT", 18, y); y = y - 26
  win.numCk = UI:Check(pk, "Number keys 1-9 use the slots while it's open", true, function(on) cfg().numKeys = on; changed() end,
    "Slot 1 is at the top, then clockwise. The numbers show on the slots.")
  win.numCk:SetPoint("TOPLEFT", 18, y); y = y - 26
  win.sectorCk = UI:Check(pk, "Click anywhere in a slot's direction (no need to hit the icon)", true, function(on) cfg().sector = on; changed() end,
    "The wheel is cut into slices like a pie, one per slot, reaching out to the edge of the screen. Left-click anywhere in a slice - " ..
    "on or off the wheel - to use that slot; the slot you're aiming at lights up. Any other mouse button closes. " ..
    "Off: you click the icons themselves and a click outside closes the wheel.")
  win.sectorCk:SetPoint("TOPLEFT", 18, y); y = y - 40
  local note = UI:Text(pk, "", "muted")
  note:SetPoint("TOPLEFT", 18, y); note:SetWidth(W - 60)
  note:SetText("While Radialz is on, its key takes over from anything the game has bound to it; turn Radialz off or pick another key " ..
    "and your old binding works again. The key works in combat too - only changes to the wheel wait until combat ends.\n\n" ..
    "Only a left-click uses a slot. Any other mouse button (right, middle, side buttons) closes the wheel - on a slot or anywhere else - " ..
    "and so do Escape and your key. With slices off, a left-click outside the wheel closes it too.")
  local try2 = UI:PrimaryButton(pk, "Try it", 120, 24, function() S:RadialzOpen() end)
  try2:SetPoint("BOTTOMRIGHT", -40, 40)

  win:HookScript("OnShow", function() S.RadialzEditorRefresh() end)
  tabs:Select(1)
end

function S.RadialzEditorRefresh()
  if not win or not win:IsShown() then return end
  local pg, c = curPage()
  if not pg then return end
  local l = L()
  win.status:SetText(combat() and "|cffff9933In combat - your changes apply when combat ends.|r" or
    ("|cff888888Key: " .. keyText(c.key) .. (c.on and "" or "  (Radialz is off)") .. "   -   " .. CMD .. "|r"))
  win.preview:Paint(sel.page, win.tab == 1 and sel.slot or nil)
  if win.tab == 1 then
    -- page list
    local ROWS = #win.rows
    win.rowOff = clamp(win.rowOff or 0, 0, math.max(0, #c.pages - ROWS))
    if sel.page <= win.rowOff then win.rowOff = sel.page - 1 elseif sel.page > win.rowOff + ROWS then win.rowOff = sel.page - ROWS end
    local th = UI:Theme()
    for i, r in ipairs(win.rows) do
      local idx = win.rowOff + i
      local p = c.pages[idx]
      r.idx = p and idx or nil
      if p then
        r.icon:SetTexture(p.icon or PAGE_ICON)
        r.text:SetText((idx == 1 and "|cffe0b04a*|r " or "") .. (p.name or "?") .. "  |cff888888(" .. p.slots .. ")|r")
        r.hl:SetColorTexture(th.gold[1], th.gold[2], th.gold[3], 1); r.hl:SetShown(idx == sel.page)
        r.text:SetTextColor(idx == sel.page and th.gold[1] or th.text[1], idx == sel.page and th.gold[2] or th.text[2], idx == sel.page and th.gold[3] or th.text[3])
        r:Show()
      else
        r:Hide()
      end
    end
    win.slotsDD:SetValue(pg.slots)
    -- slot editor
    sel.slot = clamp(sel.slot, 1, pg.slots)
    local it = pg.items[sel.slot]
    local _, name = slotLook(it)
    win.slotHead:SetText("Slot " .. sel.slot .. " of " .. pg.slots .. (name and ("  |cffffffff" .. name .. "|r") or ""))
    win.kind:SetValue(it and it.kind or "none")
    local k = it and it.kind
    win.nameL:SetShown(k == "spell" or k == "item" or k == "macro" or k == "page" or k == "text")
    win.nameL:SetText((k == "spell" and "Spell name or ID") or (k == "item" and "Item name, ID or link") or (k == "macro" and "Name of a saved macro")
      or (k == "page" and "Page it opens") or (k == "text" and "Macro text (up to 255 letters)") or "")
    win.nameE:SetShown(k == "spell" or k == "item" or k == "macro")
    if not win.nameE:HasFocus() then
      local v = ""
      if k == "spell" then v = (it.id and spellName(it.id)) or it.name or ""
      elseif k == "item" then v = (it.id and (itemName(it.id) or tostring(it.id))) or it.name or ""
      elseif k == "macro" then v = it.name or "" end
      win.nameE:SetText(v); win.nameE.dirtyText = nil
    end
    win.textBox:SetShown(k == "text")
    if k == "text" and not win.textE:HasFocus() then win.textE:SetText(it.text or "") end
    win.pageDD:SetShown(k == "page")
    if k == "page" then win.pageDD:SetValue(it.page) end
    if not win.labelE:HasFocus() then win.labelE:SetText(it and it.label or "") end
    if it then win.labelE:Enable() else win.labelE:Disable() end
    win.iconB:SetEnabled(it ~= nil); win.clearB:SetEnabled(it ~= nil)
  elseif win.tab == 2 then
    for _, s in ipairs(win.lookSl) do s:SetValue((l[s.key] or 0) * (s.scale or 1)) end
    for _, d in ipairs(win.lookDD) do d:SetValue(l[d.key]) end
    for _, b in ipairs(win.lookCk) do b:SetChecked(l[b.key] and true or false) end
  else
    win.onCk:SetChecked(c.on and true or false)
    win.keyDD:SetValue(c.key)
    win.atDD:SetValue(c.openAt)
    win.closeCk:SetChecked(c.closeOnUse and true or false)
    win.numCk:SetChecked(c.numKeys and true or false)
    win.sectorCk:SetChecked(c.sector and true or false)
  end
end

function S:ShowRadialz()
  if not win then buildWindow() end
  win:Show(); win:Raise()
  S.RadialzEditorRefresh()
end
function S:HideRadialz() if win then win:Hide() end end
S:On("PLAYER_REGEN_DISABLED", function() if S.RadialzEditorRefresh then S.RadialzEditorRefresh() end end)
S:On("PLAYER_REGEN_ENABLED", function() if S.RadialzEditorRefresh then S.RadialzEditorRefresh() end end)

S:AddCommand("radialz", "[open]", "Radialz: the radial action menu (open = show the wheel now)", function(rest)
  if S.Trim(rest):lower() == "open" then S:RadialzOpen() else S:ShowRadialz() end
end)
