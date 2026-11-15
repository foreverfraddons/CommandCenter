-- BuffWatcher: the buffs and weapon enchants you want to keep up.
--   * a missing one shows in a small movable tracker and (optionally) glows softly
--     on your action bars, so you put it up before the pull
--   * buffs marked "keep up in combat" are handed to Rotational as top priority
-- Lists belong to your class (every character of that class shares them).
local _, S = ...
local UI = S.UI

local function G() return S.db.global end
local function K() return S.RotKit end              -- spell helpers shared with Rotational
local function now() return GetTime() end
local function combat() return (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) end

local COLORS = { blue = { 0.3, 0.6, 1 }, cyan = { 0.2, 0.95, 1 }, green = { 0.3, 1, 0.3 }, gold = { 1, 0.82, 0.2 }, orange = { 1, 0.55, 0.1 },
  red = { 1, 0.3, 0.25 }, purple = { 0.75, 0.4, 1 }, pink = { 1, 0.4, 0.8 }, white = { 1, 1, 1 } }

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
local function myClass() local _, cls = UnitClass("player"); return cls or "UNKNOWN" end
local function store()
  local g = G()
  g.buffWatch = type(g.buffWatch) == "table" and g.buffWatch or {}
  local w = g.buffWatch
  w.look = type(w.look) == "table" and w.look or { on = true, tracker = true, glow = true, color = "blue", strength = 0.45, size = 36, anim = "pulse", speed = 3 }
  w.classes = type(w.classes) == "table" and w.classes or {}
  local cls = myClass()
  local c = w.classes[cls]
  if type(c) ~= "table" then
    c = { list = {} }
    w.classes[cls] = c
  end
  c.list = c.list or {}
  -- once: bring over the buffs from your Rotational setups
  if not c.imported and S.RotClassStore then
    c.imported = true
    local ok, rc = pcall(S.RotClassStore)
    if ok and type(rc) == "table" then
      local seen = {}
      for _, e in ipairs(c.list) do seen[(e.spell or 0) .. ":" .. (e.kind or "aura")] = true end
      for _, name in ipairs(rc.order or {}) do
        local prof = rc.profiles and rc.profiles[name]
        for _, b in ipairs(type(prof) == "table" and prof.buffs or {}) do
          local key = (b.spell or 0) .. ":" .. (b.kind or "aura")
          if b.spell and not seen[key] then seen[key] = true; c.list[#c.list + 1] = { spell = b.spell, kind = b.kind or "aura", combat = b.combat } end
        end
      end
    end
  end
  return c, w.look
end
S.BuffWatchStore = store
function S.BuffWatchAddItem(item, kind, cond)
  if not item then return end
  local c = store()
  for _, e in ipairs(c.list) do if e.item == item and e.kind == kind then return end end
  c.list[#c.list + 1] = { item = item, kind = kind, bar = true, cond = (cond ~= "always") and cond or nil }
  if S.RefreshBuffWatcher then S:RefreshBuffWatcher() end
end
function S.BuffWatchAdd(spell, kind, inCombat, cond)
  if not spell then return end
  local c = store()
  for _, e in ipairs(c.list) do if e.spell == spell and (e.kind or "aura") == (kind or "aura") then return end end
  c.list[#c.list + 1] = { spell = spell, kind = kind or "aura", combat = inCombat or nil, bar = true, cond = (cond and cond ~= "always") and cond or nil }
  if S.RefreshBuffWatcher then S:RefreshBuffWatcher() end
end

---------------------------------------------------------------------------
-- Consumables: food (Well Fed), elixirs, flasks, potions - watched by the buff
-- their item gives, clicked to use the item
---------------------------------------------------------------------------
local ITEM_KINDS = { food = "Food (Well Fed)", elixir = "Elixir", flask = "Flask", potion = "Potion buff" }
S.BuffWatchItemKinds = ITEM_KINDS
local function itemName(id)
  local n = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
  if not n and GetItemInfo then n = GetItemInfo(id) end
  return n
end
local function itemIcon(id)
  local ic = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)
  if not ic and GetItemIcon then ic = GetItemIcon(id) end
  return ic or "Interface\\Icons\\INV_Misc_QuestionMark"
end
local function itemCount(id)
  local n = (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(id)) or (GetItemCount and GetItemCount(id)) or 0
  return tonumber(n) or 0
end
-- the buff an item gives (its "Use:" spell)
local function itemSpell(id)
  local f = (C_Item and C_Item.GetItemSpell) or GetItemSpell
  if not f then return nil end
  local ok, name, sid = pcall(f, id)
  if ok then return name, sid end
end
local function isItem(b) return ITEM_KINDS[b.kind or ""] ~= nil end
local function entryKey(b) return b.spell or ("item" .. tostring(b.item)) end
local function entryName(b)
  if isItem(b) then return itemName(b.item) or ("item " .. tostring(b.item)) end
  return K().spellName(b.spell)
end
local function entryIcon(b)
  if isItem(b) then return itemIcon(b.item) end
  return K().spellIcon(b.spell)
end
S.BuffWatchEntryName, S.BuffWatchEntryIcon = entryName, entryIcon
-- do you have this kind of buff on? (food = Well Fed; others = the item's own buff)
local function anyAuraNamed(names)
  local found
  pcall(function()
    for i = 1, 40 do
      local a = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex and C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
      if not a then break end
      local n = a.name
      if n and not K().secret(n) and names[n] then found = a; break end
    end
  end)
  if not found and AuraUtil and AuraUtil.FindAuraByName then
    for n in pairs(names) do local x = AuraUtil.FindAuraByName(n, "player", "HELPFUL"); if x then found = { name = x }; break end end
  end
  return found
end
local function itemAura(b)
  if b.kind == "food" then
    local names = { ["Well Fed"] = true }
    if WELL_FED then names[WELL_FED] = true end
    if b.aura then names[b.aura] = true end
    return anyAuraNamed(names)
  end
  local nm, sid = itemSpell(b.item)
  if sid then local a = K().myAura(sid); if a then return a end end
  if nm then return K().myAura(nm) end
  return nil
end

---------------------------------------------------------------------------
-- Is it up?
---------------------------------------------------------------------------
local auraSeenInCombat = false
local buffAtStart, buffUpOOC, buffCast = {}, {}, {}
S:On("PLAYER_REGEN_DISABLED", function()
  auraSeenInCombat = false
  wipe(buffAtStart)
  for k, v in pairs(buffUpOOC) do buffAtStart[k] = v end
end)
-- you cast something (from Rotational's cast tracking)
function S.BuffWatchCast(id, nm)
  if not S.db then return end
  local c = store()
  local k = K()
  for _, b in ipairs(c.list) do
    if b.spell and (b.spell == id or (k and nm and k.spellName(b.spell) == nm)) then buffCast[entryKey(b)] = now() end
    if isItem(b) then local inm, isid = itemSpell(b.item); if (isid and isid == id) or (inm and inm == nm) then buffCast[entryKey(b)] = now() end end
  end
end
-- true when the buff is missing
local function missing(b)
  local k = K()
  if not k then return false end
  if b.kind == "main" then return not k.hasEnchant("main") end
  if b.kind == "off" then return not k.hasEnchant("off") end
  local key = entryKey(b)
  local a
  if isItem(b) then a = itemAura(b) else a = k.myAura(b.aura or b.spell) end
  if not combat() then buffUpOOC[key] = a ~= nil end
  if a then if combat() then auraSeenInCombat = true end return false end
  if not combat() or auraSeenInCombat then return true end
  -- in a fight the game may hide buffs: can we see any at all?
  local visible = false
  pcall(function()
    local any = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex and C_UnitAuras.GetAuraDataByIndex("player", 1, "HELPFUL")
    if any and any.spellId ~= nil and not k.secret(any.spellId) then visible = true end
  end)
  if visible then auraSeenInCombat = true; return true end
  local cast = buffCast[key]
  if cast and now() - cast < (tonumber(b.lasts) or (isItem(b) and 3600) or 600) then return false end
  return not buffAtStart[key]
end
S.BuffWatchMissing = missing
S.RotBuffMissing = missing          -- older callers

-- the missing ones you know: { spellIDs }
local function watchable(b)
  if isItem(b) then return b.item ~= nil end
  return b.spell and K().known(b.spell)
end
local function missingList(onlyCombat)
  local out = {}
  if not S.db or not K() then return out end
  local c, look = store()
  if look.on == false then return out end
  for _, b in ipairs(c.list) do
    local inSituation = not b.cond or b.cond == "always" or (S.BuffWatchCondMet and S.BuffWatchCondMet(b))
    if inSituation and b.spell and not isItem(b) and K().known(b.spell) and (not onlyCombat or b.combat) and missing(b) then out[#out + 1] = b.spell end
  end
  return out
end
S.BuffWatchMissingList = missingList
-- for Rotational: "keep up in combat" buffs that have dropped
function S.BuffWatchCombatPicks()
  if not combat() then return {} end
  return missingList(true)
end

---------------------------------------------------------------------------
-- Showing it: soft glow on the action bar buttons, and the tracker
---------------------------------------------------------------------------
local glows = {}
local function getGlow(btn)
  local g = glows[btn]
  if g then return g end
  g = CreateFrame("Frame", nil, UIParent)
  g:SetAllPoints(btn)
  g.outer = g:CreateTexture(nil, "OVERLAY"); g.outer:SetTexture(UI.ART.glow); g.outer:SetBlendMode("ADD")
  g.outer:SetPoint("TOPLEFT", -10, 10); g.outer:SetPoint("BOTTOMRIGHT", 10, -10)
  g:Hide()
  g:SetScript("OnUpdate", function(self, el)
    self.t = (self.t or 0) + el
    local f = S.RotAnimAlpha and S.RotAnimAlpha(self.anim or "pulse", self.t, self.speed or 3) or (0.55 + 0.45 * math.sin(self.t * 3))
    self.outer:SetAlpha((self.power or 0.45) * f)
  end)
  glows[btn] = g
  return g
end

-- the tracker: missing buffs as icons you can click to cast / use (secure buttons,
-- so it only changes out of combat; in a fight it tucks itself away)
local tracker
local function savePos(self)
  local _, l = store()
  l.at = { math.floor((self:GetLeft() or 0) + 0.5), math.floor((self:GetTop() or 0) + 0.5) }
end
local function getTracker()
  if tracker then return tracker end
  local f = CreateFrame("Frame", "CC_BuffWatchTracker", UIParent)
  f:SetSize(40, 40); f:SetFrameStrata("MEDIUM")
  local _, look = store()
  if type(look.at) == "table" then f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", look.at[1], look.at[2]) else f:SetPoint("CENTER", 0, -230) end
  f:SetMovable(true); f:SetClampedToScreen(true)
  -- the title bar is the handle: drag it to move (unless locked)
  f.bar = CreateFrame("Frame", nil, f)
  f.bar:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, 1); f.bar:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 0, 1); f.bar:SetHeight(14)
  f.bar:EnableMouse(true); f.bar:RegisterForDrag("LeftButton")
  f.bar.bg = f.bar:CreateTexture(nil, "BACKGROUND"); f.bar.bg:SetAllPoints(); f.bar.bg:SetColorTexture(0, 0, 0, 0.45)
  f.title = f.bar:CreateFontString(nil, "OVERLAY"); f.title:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE"); f.title:SetPoint("LEFT", 3, 0)
  f.title:SetText("|cff66bbffMissing buffs|r")
  f.bar:SetScript("OnDragStart", function() local _, l = store(); if not l.lock and not combat() then f:StartMoving() end end)
  f.bar:SetScript("OnDragStop", function() f:StopMovingOrSizing(); savePos(f) end)
  f.bar:SetScript("OnMouseUp", function(_, b) if b == "RightButton" then S:ShowBuffWatcher() end end)
  UI:Tip(f.bar, "BuffWatcher", "Click an icon to put that buff up. Drag this bar to move the box, right-click it for settings.")
  f.icons = {}
  tracker = f
  return f
end
local function trackerIcon(i)
  local f = getTracker()
  local b = f.icons[i]
  if b then return b end
  b = CreateFrame("Button", "CC_BuffWatchIcon" .. i, f, "SecureActionButtonTemplate")
  b:RegisterForClicks("AnyUp", "AnyDown")
  -- rounded-corner icon with a glow around the outside edge
  b.tex = b:CreateTexture(nil, "ARTWORK"); b.tex:SetAllPoints(); b.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  b.glow = b:CreateTexture(nil, "BACKGROUND"); b.glow:SetTexture("Interface\\AddOns\\CommandCenter\\Media\\UI\\halo_r"); b.glow:SetBlendMode("ADD")
  b.glow:SetPoint("CENTER")
  b.ring = b:CreateTexture(nil, "OVERLAY"); b.ring:SetAllPoints(); b.ring:SetTexture("Interface\\AddOns\\CommandCenter\\Media\\UI\\rring2")
  b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  if b.CreateMaskTexture then
    local ok, m = pcall(b.CreateMaskTexture, b)
    if ok and m then
      m:SetAllPoints(); b.mask = m
      pcall(b.tex.AddMaskTexture, b.tex, m)
      local hl = b:GetHighlightTexture(); if hl then pcall(hl.AddMaskTexture, hl, m) end
    end
  end
  b.count = b:CreateFontString(nil, "OVERLAY"); b.count:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE"); b.count:SetPoint("BOTTOMRIGHT", -1, 2)
  b:SetScript("OnUpdate", function(self, el)
    self.t = (self.t or 0) + el
    local _, look = store()
    local a = S.RotAnimAlpha and S.RotAnimAlpha(look.anim or "pulse", self.t, look.speed or 3) or 1
    self.glow:SetAlpha((look.strength or 0.45) * a + 0.2)
  end)
  -- dragging an icon moves the box too
  b:RegisterForDrag("LeftButton")
  b:SetScript("OnDragStart", function() local _, l = store(); if not l.lock and not combat() then f:StartMoving() end end)
  b:SetScript("OnDragStop", function() f:StopMovingOrSizing(); savePos(f) end)
  b:SetScript("OnEnter", function(self)
    if not self.entry then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    local e = self.entry
    GameTooltip:AddLine(entryName(e), 1, 1, 1)
    local what = e.kind == "main" and "Main-hand weapon" or e.kind == "off" and "Off-hand weapon" or ITEM_KINDS[e.kind or ""] or "Missing"
    GameTooltip:AddLine(what, 0.6, 0.8, 1)
    if isItem(e) then
      local n = itemCount(e.item)
      GameTooltip:AddLine(n > 0 and ("Click to use (" .. n .. " in your bags)") or "|cffff5555None in your bags|r", 0.8, 0.8, 0.8)
    else GameTooltip:AddLine("Click to cast", 0.8, 0.8, 0.8) end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  f.icons[i] = b
  return b
end
S:On("PLAYER_REGEN_DISABLED", function() if tracker then tracker:Hide() end end)   -- before the fight locks it

-- situations: some buffs only matter now and then (Water Breathing when the breath bar
-- shows, Slow Fall when you fall...). Those are only watched while it's happening.
local CONDS = {
  { value = "always", text = "Always" },
  { value = "breath", text = "Underwater (breath bar)" },
  { value = "swim", text = "Swimming" },
  { value = "fall", text = "Falling" },
  { value = "instance", text = "In a dungeon / raid" },
  { value = "group", text = "In a group" },
}
local CONDNAME = {}
for _, c in ipairs(CONDS) do CONDNAME[c.value] = c.text end
S.BuffWatchConds = CONDS
local function breathing()
  for i = 1, (MIRRORTIMER_NUMTIMERS or 3) do
    local ok, timer, _, _, scale = pcall(GetMirrorTimerInfo, i)
    if ok and timer == "BREATH" and (scale == nil or (not K().secret(scale) and scale < 0)) then return true end
  end
  return false
end
local fallStart
local function condMet(b)
  local c = b.cond or "always"
  if c == "always" then return true end
  if c == "breath" then return breathing() end
  if c == "swim" then return IsSwimming and IsSwimming() or false end
  if c == "fall" then
    local f = IsFalling and IsFalling()
    if f then fallStart = fallStart or now() else fallStart = nil end
    return f and now() - fallStart > 0.6 or false
  end
  if c == "instance" then local inI, t = IsInInstance(); return inI and (t == "party" or t == "raid") or false end
  if c == "group" then return (IsInGroup and IsInGroup()) or false end
  return true
end
S.BuffWatchCondMet = condMet
-- tell you once each time a situation starts and its buff is missing
local alerted, lastAlertAt = {}, {}
-- warning settings (BuffWatcher > Warnings...)
local WARN_DEFAULT = { on = true, style = "raid", sound = "raid", color = "orange", text = "{when}: put up {buff}!",
  cd = { breath = 25, swim = 25, fall = 0, instance = 0, group = 0 } }
local function warnCfg()
  local _, look = store()
  local w = look.warn
  if type(w) ~= "table" then w = {}; look.warn = w end
  for k, v in pairs(WARN_DEFAULT) do if w[k] == nil then w[k] = type(v) == "table" and {} or v end end
  for k, v in pairs(WARN_DEFAULT.cd) do if w.cd[k] == nil then w.cd[k] = v end end
  return w
end
S.BuffWatchWarnCfg = warnCfg
local SOUNDS = {
  { value = "raid", text = "Raid warning", kit = "RAID_WARNING" },
  { value = "ready", text = "Ready check", kit = "READY_CHECK" },
  { value = "alarm", text = "Alarm clock", kit = "ALARM_CLOCK_WARNING_3" },
  { value = "whisper", text = "Whisper ping", kit = "TELL_MESSAGE" },
  { value = "quest", text = "Quest done", kit = "IG_QUEST_LIST_COMPLETE" },
  { value = "none", text = "No sound" },
}
local STYLES = {
  { value = "raid", text = "Raid warning (across the screen)" },
  { value = "big", text = "Big text, top of the screen" },
  { value = "center", text = "Red error text (middle)" },
  { value = "chat", text = "Chat message only" },
  { value = "none", text = "No message (tracker only)" },
}
S.BuffWatchWarnSounds, S.BuffWatchWarnStyles = SOUNDS, STYLES
-- the big text: our own fading line near the top of the screen
local bigText
local function showBig(text, c)
  if not bigText then
    bigText = CreateFrame("Frame", nil, UIParent); bigText:SetSize(800, 60); bigText:SetPoint("TOP", 0, -140); bigText:SetFrameStrata("HIGH")
    bigText.fs = bigText:CreateFontString(nil, "OVERLAY"); bigText.fs:SetFont("Fonts\\FRIZQT__.TTF", 30, "THICKOUTLINE"); bigText.fs:SetAllPoints()
    bigText:SetScript("OnUpdate", function(self)
      local age = GetTime() - (self.at or 0)
      if age > 3.5 then self:Hide() return end
      self:SetAlpha(age < 2.5 and 1 or (3.5 - age))
    end)
  end
  bigText.fs:SetText(text); bigText.fs:SetTextColor(c[1], c[2], c[3])
  bigText.at = GetTime(); bigText:SetAlpha(1); bigText:Show()
end
local function warn(text, w)
  w = w or warnCfg()
  local c = COLORS[w.color or "orange"] or COLORS.orange
  if w.style == "raid" and RaidNotice_AddMessage and RaidWarningFrame then
    pcall(RaidNotice_AddMessage, RaidWarningFrame, text, { r = c[1], g = c[2], b = c[3] })
  elseif w.style == "big" or (w.style == "raid") then showBig(text, c)
  elseif w.style == "center" and UIErrorsFrame then UIErrorsFrame:AddMessage(text, c[1], c[2], c[3])
  elseif w.style == "chat" then S:Print(text) end
  if w.sound ~= "none" and PlaySound and SOUNDKIT then
    for _, snd in ipairs(SOUNDS) do
      if snd.value == w.sound and snd.kit and SOUNDKIT[snd.kit] then pcall(PlaySound, SOUNDKIT[snd.kit]) end
    end
  end
end
local function warnText(b, w)
  local t = (w.text and w.text ~= "") and w.text or WARN_DEFAULT.text
  local when = (CONDNAME[b.cond] or "Now"):gsub(" %b()", "")
  t = t:gsub("{when}", when):gsub("{buff}", entryName(b))
  return t
end
function S.BuffWatchTestWarning()
  local w = warnCfg()
  local t = warnText({ cond = "breath", spell = 131 }, w)
  warn(t, w)
end
-- what we've already warned about is saved, so a /reload or logging back in (in a
-- dungeon, underwater, mid-fight...) doesn't repeat it: { key = { at = server time, on = still going } }
local function warnMemory()
  local _, look = store()
  look.warned = type(look.warned) == "table" and look.warned or {}
  return look.warned
end
local function stime() return (GetServerTime and GetServerTime()) or time() end
local loadedAt = GetTime()
local function alertSituation(b)
  local key = entryKey(b)
  if alerted[key] then return end
  alerted[key] = true
  local mem = warnMemory()
  local m = mem[key]
  -- still the same situation as before the reload / logout (we told you then): stay quiet
  if m and m.on and (stime() - (m.at or 0)) < 4 * 3600 then return end
  local w = warnCfg()
  if w.on == false or b.warn == false then return end              -- off (the tracker still shows it)
  local cd = tonumber(w.cd[b.cond or ""]) or 0
  local last = m and m.at or nil
  if cd > 0 and last and stime() - last < cd then return end
  mem[key] = { at = stime(), on = true }
  warn(warnText(b, w), w)
end
-- the situation is over: next time it starts you'll be told again
local function situationEnded(key)
  alerted[key] = nil
  local m = warnMemory()[key]
  if m then m.on = nil end
end

local function apply()
  for _, g in pairs(glows) do g:Hide() end
  if not S.db or not K() then return end
  local c, look = store()
  local list = {}
  local fighting = combat()
  if look.on ~= false then
    for _, b in ipairs(c.list) do
      local situational = b.cond and b.cond ~= "always"
      if situational then
        if condMet(b) and watchable(b) and missing(b) then
          alertSituation(b)
          if not fighting then list[#list + 1] = b end
        else
          situationEnded(entryKey(b))      -- ready to warn again next time
        end
      elseif watchable(b) and (not fighting or b.combat) and missing(b) then list[#list + 1] = b end
    end
  end
  -- glow on the bars (spells only)
  if look.glow ~= false and not fighting then
    local col = COLORS[look.color or "blue"] or COLORS.blue
    for _, b in ipairs(list) do
      if b.spell and not isItem(b) then
        for _, btn in ipairs(K().buttonsFor(b.spell)) do
          local g = getGlow(btn)
          g.outer:SetVertexColor(col[1], col[2], col[3])
          g.power, g.anim, g.speed = look.strength or 0.45, look.anim or "pulse", look.speed or 3
          g:SetFrameStrata(btn:GetFrameStrata() or "MEDIUM"); g:SetFrameLevel((btn:GetFrameLevel() or 1) + 7)
          g:Show()
        end
      end
    end
  end
  -- the tracker (secure buttons: never touched in a fight)
  if fighting then return end
  if look.tracker ~= false and #list > 0 then
    local f = getTracker()
    local sz = look.size or 36
    local gap = math.floor(sz * 0.3)
    local col = COLORS[look.color or "blue"] or COLORS.blue
    for i, b in ipairs(list) do
      local ic = trackerIcon(i)
      ic:SetSize(sz, sz); ic:ClearAllPoints(); ic:SetPoint("TOPLEFT", (i - 1) * (sz + gap), 0)
      ic.tex:SetTexture(entryIcon(b)); ic.entry = b
      -- glow size 1-5: a wider halo (each texture's hole matches the icon)
      local gs = math.max(1, math.min(5, look.glowSize or 3))
      local GF = { 1.25, 1.45, 1.7, 2.0, 2.4 }
      -- roundness 0 (square) - 5 (circle): mask, edge ring and halo all match
      local rd = math.max(0, math.min(5, look.round or 2))
      if ic.gs ~= gs or ic.rd ~= rd then
        ic.gs, ic.rd = gs, rd
        ic.glow:SetTexture("Interface\\AddOns\\CommandCenter\\Media\\UI\\halo_" .. rd .. "_" .. gs)
        ic.ring:SetTexture("Interface\\AddOns\\CommandCenter\\Media\\UI\\rring" .. rd)
        if ic.mask then pcall(ic.mask.SetTexture, ic.mask, "Interface\\AddOns\\CommandCenter\\Media\\UI\\rmask" .. rd, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE") end
      end
      ic.glow:SetVertexColor(col[1], col[2], col[3]); ic.glow:SetSize(sz * GF[gs], sz * GF[gs])
      ic.ring:SetVertexColor(col[1], col[2], col[3])
      if isItem(b) then
        local n = itemCount(b.item)
        ic.count:SetText(n > 0 and n or "|cffff55550|r"); ic.tex:SetDesaturated(n == 0)
        if ic.what ~= "item:" .. tostring(b.item) then
          ic.what = "item:" .. tostring(b.item)
          ic:SetAttribute("type", "item"); ic:SetAttribute("item", "item:" .. b.item); ic:SetAttribute("spell", nil)
        end
      else
        ic.count:SetText(""); ic.tex:SetDesaturated(false)
        local nm = K().spellName(b.spell)
        if ic.what ~= "spell:" .. tostring(b.spell) then
          ic.what = "spell:" .. tostring(b.spell)
          ic:SetAttribute("type", "spell"); ic:SetAttribute("spell", nm); ic:SetAttribute("item", nil)
        end
      end
      ic:Show()
    end
    for i = #list + 1, #f.icons do f.icons[i]:Hide() end
    f:SetSize(#list * (sz + gap) - gap, sz)
    f:Show()
  elseif tracker then
    tracker:Hide()
  end
end
S.BuffWatchApply = apply

---------------------------------------------------------------------------
-- Timer bars: how long each buff (with "Timer bar" ticked) has left
---------------------------------------------------------------------------
local lastExp, lastTotal = {}, {}       -- entry key -> expiry (GetTime) / full length, from the last time it was readable
local function readable(v) return v ~= nil and not K().secret(v) end
-- seconds left and full length, or nil when the buff is down / unknown
local function timeLeft(b)
  local key = entryKey(b)
  local t = now()
  local left, total
  if b.kind == "main" or b.kind == "off" then
    local ok, hasM, expM, _, _, hasO, expO = pcall(function() return GetWeaponEnchantInfo() end)
    if ok then
      local has, exp = hasM, expM
      if b.kind == "off" then has, exp = hasO, expO end
      if readable(has) and has and readable(exp) and exp then
        left = exp / 1000
        total = math.max(lastTotal[key] or 0, left)
      elseif readable(has) and not has then return nil end
    end
  else
    local a
    if isItem(b) then a = itemAura(b) else a = K().myAura(b.aura or b.spell) end
    if type(a) == "table" then
      local exp, dur = a.expirationTime, a.duration
      if readable(exp) and readable(dur) and exp and exp > 0 then left = exp - t; total = dur > 0 and dur or nil
      elseif readable(exp) and exp == 0 then return 0, 0 end        -- no time limit
    elseif a == nil and not combat() then return nil end
  end
  if left then
    lastExp[key] = t + left; lastTotal[key] = total or lastTotal[key] or left
    return left, lastTotal[key]
  end
  -- hidden right now (in a fight): carry on from what we last saw
  local e = lastExp[key]
  if e and e > t then return e - t, lastTotal[key] end
  return nil
end
S.BuffWatchTimeLeft = timeLeft

local bars
local function getBars()
  if bars then return bars end
  local f = CreateFrame("Frame", "CC_BuffWatchBars", UIParent)
  f:SetSize(200, 20); f:SetFrameStrata("MEDIUM")
  local _, look = store()
  if type(look.barsAt) == "table" then f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", look.barsAt[1], look.barsAt[2]) else f:SetPoint("CENTER", 0, -300) end
  f:SetMovable(true); f:SetClampedToScreen(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) local _, l = store(); if not l.lock then self:StartMoving() end end)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local _, l = store()
    l.barsAt = { math.floor((self:GetLeft() or 0) + 0.5), math.floor((self:GetTop() or 0) + 0.5) }
  end)
  f:SetScript("OnMouseUp", function(_, b) if b == "RightButton" then S:ShowBuffWatcher() end end)
  UI:Tip(f, "BuffWatcher timers", "Drag to move, right-click for settings.")
  f.rows = {}
  -- smooth fill between the checks
  f:SetScript("OnUpdate", function(self)
    local t = now()
    for _, r in ipairs(self.rows) do
      if r:IsShown() and r.exp then
        local left = math.max(0, r.exp - t)
        local pct = (r.total and r.total > 0) and math.min(1, left / r.total) or 1
        r.fill:SetWidth(math.max(1, (r.bw or 150) * pct))
        local m = math.floor(left / 60)
        r.time:SetText(left >= 3600 and string.format("%dh", math.floor(left / 3600) + 1) or left >= 60 and string.format("%d:%02d", m, math.floor(left % 60)) or string.format("%.0f", left))
        local warn = left < 60 or pct < 0.1
        if warn then r.fill:SetVertexColor(1, 0.3, 0.25, 0.9) else r.fill:SetVertexColor(r.c[1], r.c[2], r.c[3], 0.85) end
      end
    end
  end)
  bars = f
  return f
end
local function barRow(i)
  local f = getBars()
  local r = f.rows[i]
  if r then return r end
  r = CreateFrame("Frame", nil, f)
  r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetPoint("LEFT"); r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetColorTexture(0, 0, 0, 0.55)
  r.fill = r:CreateTexture(nil, "BORDER"); r.fill:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
  r.name = r:CreateFontString(nil, "OVERLAY"); r.name:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE"); r.name:SetJustifyH("LEFT"); r.name:SetWordWrap(false)
  r.time = r:CreateFontString(nil, "OVERLAY"); r.time:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE"); r.time:SetJustifyH("RIGHT")
  f.rows[i] = r
  return r
end
local function applyBars(c, look)
  local list = {}
  if look.on ~= false and look.bars ~= false then
    for _, b in ipairs(c.list) do
      if b.bar and (isItem(b) and b.item or b.spell) then   -- (also buffs others put on you)
        local left, total = timeLeft(b)
        if left and left > 0 then list[#list + 1] = { b = b, left = left, total = total } end
      end
    end
  end
  if #list == 0 then if bars then bars:Hide() end return end
  table.sort(list, function(x, y) return x.left < y.left end)
  local f = getBars()
  local w, h = look.barW or 200, look.barH or 18
  local col = COLORS[look.barColor or look.color or "blue"] or COLORS.blue
  for i, it in ipairs(list) do
    local r = barRow(i)
    r:SetSize(w, h); r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -(i - 1) * (h + 3))
    r.icon:SetSize(h, h); r.icon:SetTexture(entryIcon(it.b))
    r.bg:ClearAllPoints(); r.bg:SetPoint("TOPLEFT", h + 2, 0); r.bg:SetPoint("BOTTOMRIGHT")
    r.bw = w - h - 2
    r.fill:ClearAllPoints(); r.fill:SetPoint("TOPLEFT", r.bg, "TOPLEFT"); r.fill:SetPoint("BOTTOMLEFT", r.bg, "BOTTOMLEFT")
    r.name:ClearAllPoints(); r.name:SetPoint("LEFT", r.bg, "LEFT", 4, 0); r.name:SetPoint("RIGHT", r.bg, "RIGHT", -40, 0)
    r.time:ClearAllPoints(); r.time:SetPoint("RIGHT", r.bg, "RIGHT", -4, 0)
    r.name:SetText(entryName(it.b))
    r.exp, r.total, r.c = now() + it.left, it.total, col
    r:Show()
  end
  for i = #list + 1, #f.rows do f.rows[i]:Hide() end
  f:SetSize(w, #list * (h + 3) - 3)
  f:Show()
end

local acc = 0
local driver = CreateFrame("Frame")
driver:SetScript("OnUpdate", function(_, el)
  acc = acc + el
  if acc < 0.25 then return end
  acc = 0
  if not S.db then return end
  local ok, err = pcall(apply)
  if not ok and S.report then S.report(err) end
  local c, look = store()
  ok, err = pcall(applyBars, c, look)
  if not ok and S.report then S.report(err) end
end)

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local win
local W, H = 520, 770
local function rows() local out = {}; for i, v in ipairs(store().list) do out[i] = { pos = i, ref = v } end return out end
function S:RefreshBuffWatcher()
  if not win or not win:IsShown() then return end
  local _, look = store()
  win.tbl:SetData(rows())
  win.on:SetChecked(look.on ~= false); win.tracker:SetChecked(look.tracker ~= false); win.glow:SetChecked(look.glow ~= false)
  win.lock:SetChecked(look.lock and true or false); win.bars:SetChecked(look.bars ~= false)
  win.barW:SetValue(look.barW or 200); win.barH:SetValue(look.barH or 18); win.glowSize:SetValue(look.glowSize or 3); win.round:SetValue(look.round or 2)
  win.strength:SetValue(math.floor((look.strength or 0.45) * 100)); win.size:SetValue(look.size or 36); win.speed:SetValue(look.speed or 3)
  win.color:SetValue(look.color or "blue"); win.color.value = look.color or "blue"
  win.anim:SetValue(look.anim or "pulse"); win.anim.value = look.anim or "pulse"
end
local function build()
  local k = K()
  win = UI:Window("CC_BuffWatcher", "BuffWatcher", W, H)
  win:SetFrameStrata("HIGH")
  local y = -40
  local hint = UI:Text(win, "|cffaaaaaaBuffs, weapon enchants, food, elixirs, flasks and potion buffs to keep up. A missing one shows in the tracker (click it to cast / use) and glows on your bars, out of combat.|r", "small")
  hint:SetPoint("TOPLEFT", 16, y); hint:SetWidth(W - 32); hint:SetJustifyH("LEFT"); y = y - 34
  local function isItemKind() return ITEM_KINDS[win.kind.value or ""] ~= nil end
  win.kind = UI:Dropdown(win, 160, { { value = "aura", text = "Buff on me" }, { value = "main", text = "Main-hand weapon" }, { value = "off", text = "Off-hand weapon" },
    { value = "food", text = "Food (Well Fed)" }, { value = "elixir", text = "Elixir" }, { value = "flask", text = "Flask" }, { value = "potion", text = "Potion buff" } }, "aura",
    function(v)
      win.spellAdd:SetShown(not ITEM_KINDS[v]); win.itemAdd:SetShown(ITEM_KINDS[v] ~= nil)
    end)
  win.kind:SetPoint("TOPLEFT", 16, y)
  -- spells: the shared spell box; items: a box that takes a name or an item dragged from your bags
  win.spellAdd = k.spellBox(win, 210, "e.g. Arcane Intellect / Windfury Weapon", function(id)
    S.BuffWatchAdd(id, win.kind.value or "aura", win.inCombat:GetChecked() and true or nil, win.cond.value)
  end)
  win.spellAdd:SetPoint("LEFT", win.kind, "RIGHT", 6, 0)
  local function addItem(id)
    if not id then return end
    S.BuffWatchAddItem(id, win.kind.value, win.cond.value)
    win.itemAdd:SetText(""); win.itemAdd:ClearFocus()
  end
  win.itemAdd = UI:Edit(win, 210, 24, "Type the item or drag it from your bags")
  win.itemAdd:SetPoint("LEFT", win.kind, "RIGHT", 6, 0)
  win.itemAdd:SetScript("OnEnterPressed", function(self)
    local txt = S.Trim(self:GetText() or "")
    if txt == "" then return end
    local id = tonumber(txt)
    if not id then
      local f = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
      if f then local ok, v = pcall(f, txt); if ok then id = v end end
    end
    if not id then UI:Alert("Couldn't find \"" .. txt .. "\".\n\nDrag the item in from your bags instead (or type its item ID).") return end
    addItem(id)
  end)
  local function fromCursor()
    if not GetCursorInfo then return end
    local kind, id = GetCursorInfo()
    if kind == "item" and id then ClearCursor(); addItem(id) end
  end
  win.itemAdd:SetScript("OnReceiveDrag", fromCursor)
  win.itemAdd:HookScript("OnMouseDown", fromCursor)
  win.itemAdd:Hide()
  win.add = win.spellAdd
  local addBtn = UI:Button(win, "Add", 56, 24, function()
    if isItemKind() then win.itemAdd:GetScript("OnEnterPressed")(win.itemAdd) else win.spellAdd:GetScript("OnEnterPressed")(win.spellAdd) end
  end)
  addBtn:SetPoint("LEFT", win.spellAdd, "RIGHT", 6, 0); y = y - 30
  local wl = UI:Text(win, "When", "small"); wl:SetPoint("TOPLEFT", 18, y - 5)
  win.cond = UI:Dropdown(win, 200, S.BuffWatchConds, "always", function(v)
    local e = win.tbl.selected and win.tbl.selected.ref
    if e then e.cond = v ~= "always" and v or nil; S:RefreshBuffWatcher() end
  end)
  win.cond:SetPoint("TOPLEFT", 60, y)
  win.warnOn = UI:Check(win, "Warn me", true, function(v)
    local e = win.tbl.selected and win.tbl.selected.ref
    if e then e.warn = (not v) and false or nil end
  end, "For a buff with a situation: a warning on screen when it happens and the buff is missing (see Warnings...). Applies to the one selected in the list.")
  win.warnOn:SetPoint("LEFT", win.cond, "RIGHT", 10, 0)
  y = y - 30
  win.inCombat = UI:Check(win, "Keep it up in combat too (Rotational: top priority when it drops)", false, function(v)
    local e = win.tbl.selected and win.tbl.selected.ref
    if e then e.combat = v or nil; S:RefreshBuffWatcher() end
  end, "Lightning Shield: when it runs out mid-fight, Rotational makes it the next spell. Applies to new buffs and to the one selected in the list.")
  win.inCombat:SetPoint("TOPLEFT", 16, y); y = y - 24
  win.barOn = UI:Check(win, "Timer bar (how long it has left)", true, function(v)
    local e = win.tbl.selected and win.tbl.selected.ref
    if e then e.bar = v or nil; S:RefreshBuffWatcher() end
  end, "A bar counting down this buff's time. Applies to the one selected in the list (new buffs get one).")
  win.barOn:SetPoint("TOPLEFT", 16, y); y = y - 28
  win.tbl = UI:Table(win, W - 32, 200, {
    { title = "Buff", w = 170, get = function(r) return "|T" .. entryIcon(r.ref) .. ":16:16:0:0:64:64:5:59:5:59|t  " .. entryName(r.ref) end },
    { title = "In combat", w = 64, get = function(r) return r.ref.combat and "|cff55ff55yes|r" or "|cff555555-|r" end },
    { title = "Bar", w = 40, get = function(r) return r.ref.bar and "|cff55ff55yes|r" or "|cff555555-|r" end },
    { title = "Checked on", w = 110, get = function(r)
        local what = ({ aura = "you", main = "main-hand weapon", off = "off-hand weapon" })[r.ref.kind or "aura"] or ITEM_KINDS[r.ref.kind or ""] or "?"
        if r.ref.cond and r.ref.cond ~= "always" then what = what .. " |cff66bbff(" .. (CONDNAME[r.ref.cond] or r.ref.cond):gsub(" %b()", "") .. ")|r" end
        return what
      end },
    { title = "Up now?", w = 70, get = function(r)
        if r.ref.cond and r.ref.cond ~= "always" and not condMet(r.ref) then return "|cff888888(not needed)|r" end
        return missing(r.ref) and "|cffff5555no|r" or "|cff55ff55yes|r"
      end },
  }, { selectable = true, emptyText = "No buffs yet - add one above.", onClick = function(r)
    win.inCombat:SetChecked(r.ref.combat and true or false); win.barOn:SetChecked(r.ref.bar and true or false)
    win.cond:SetValue(r.ref.cond or "always"); win.cond.value = r.ref.cond or "always"
    win.warnOn:SetChecked(r.ref.warn ~= false)
  end })
  win.tbl:SetPoint("TOPLEFT", 16, y); y = y - 206
  k.listControls(win, win.tbl, function() return store().list end, y, function() S:RefreshBuffWatcher() end)
  -- listControls anchors at x = 14
  y = y - 34
  local h = UI:Header(win, "Look"); h:SetPoint("TOPLEFT", 16, y); y = y - 26
  local function L() local _, l = store(); return l end
  win.on = UI:Check(win, "BuffWatcher on", true, function(v) L().on = v end); win.on:SetPoint("TOPLEFT", 16, y)
  win.tracker = UI:Check(win, "Tracker icons", true, function(v) L().tracker = v end, "Missing buffs as icons in a small box (shift-drag it to move).")
  win.tracker:SetPoint("TOPLEFT", 170, y)
  win.glow = UI:Check(win, "Glow on my bars", true, function(v) L().glow = v end); win.glow:SetPoint("TOPLEFT", 330, y); y = y - 26
  win.lock = UI:Check(win, "Lock the tracker", false, function(v) L().lock = v or nil end, "Stops it moving when you drag it.")
  win.lock:SetPoint("TOPLEFT", 16, y)
  win.bars = UI:Check(win, "Timer bars", true, function(v) L().bars = v end, "Bars counting down your buffs (the ones with Timer bar ticked). Drag to move.")
  win.bars:SetPoint("TOPLEFT", 170, y); y = y - 30
  local copts = {}
  for _, c in ipairs({ "blue", "cyan", "green", "gold", "orange", "red", "purple", "pink", "white" }) do copts[#copts + 1] = { value = c, text = c:sub(1, 1):upper() .. c:sub(2) } end
  local cl = UI:Text(win, "Colour", "small"); cl:SetPoint("TOPLEFT", 16, y - 5)
  win.color = UI:Dropdown(win, 120, copts, "blue", function(v) L().color = v end); win.color:SetPoint("TOPLEFT", 66, y)
  local al = UI:Text(win, "Effect", "small"); al:SetPoint("TOPLEFT", 210, y - 5)
  win.anim = UI:Dropdown(win, 140, { { value = "pulse", text = "Pulse" }, { value = "breathe", text = "Breathe (slow)" }, { value = "flash", text = "Flash on / off" },
    { value = "heartbeat", text = "Heartbeat" }, { value = "steady", text = "Steady" } }, "pulse", function(v) L().anim = v end)
  win.anim:SetPoint("TOPLEFT", 256, y); y = y - 30
  win.strength = UI:Slider(win, W - 40, "Glow strength", 5, 100, 5, 45, function(v) L().strength = v / 100 end, function(v) return v .. "%" end)
  win.strength:SetPoint("TOPLEFT", 18, y); y = y - 28
  win.speed = UI:Slider(win, W - 40, "Speed", 1, 16, 1, 3, function(v) L().speed = v end)
  win.speed:SetPoint("TOPLEFT", 18, y); y = y - 28
  win.size = UI:Slider(win, W - 40, "Tracker icon size", 20, 72, 2, 36, function(v) L().size = v end)
  win.size:SetPoint("TOPLEFT", 18, y); y = y - 28
  local GSN = { "Small", "Medium", "Large", "Larger", "Huge" }
  win.glowSize = UI:Slider(win, W - 40, "Tracker glow size", 1, 5, 1, 3, function(v) L().glowSize = v end, function(v) return GSN[v] or v end)
  win.glowSize:SetPoint("TOPLEFT", 18, y); y = y - 28
  local RN = { [0] = "Square", "Slight", "Rounded", "More", "Very round", "Circle" }
  win.round = UI:Slider(win, W - 40, "Tracker roundness", 0, 5, 1, 2, function(v) L().round = v end, function(v) return RN[v] or v end)
  win.round:SetPoint("TOPLEFT", 18, y); y = y - 28
  local wb = UI:Button(win, "Warnings...", 110, 22, function() S:ShowBuffWatchWarnings() end, "How situation warnings look and sound (underwater, swimming...).")
  wb:SetPoint("BOTTOMLEFT", 16, 14)
  win.barW = UI:Slider(win, W - 40, "Timer bar width", 100, 360, 10, 200, function(v) L().barW = v end)
  win.barW:SetPoint("TOPLEFT", 18, y); y = y - 28
  win.barH = UI:Slider(win, W - 40, "Timer bar height", 10, 32, 1, 18, function(v) L().barH = v end)
  win.barH:SetPoint("TOPLEFT", 18, y)
  win:HookScript("OnShow", function() if K() then K().scanButtons() end S:RefreshBuffWatcher() end)
end
function S:ShowBuffWatcher()
  if not S.RotKit then S:Print("BuffWatcher needs the Rotational tool's files.") return end
  if not win then build() end
  win:Show(); win:Raise()
  S:RefreshBuffWatcher()
end
function S:HideBuffWatcher() if win then win:Hide() end end
S:AddCommand("buffs", "", "BuffWatcher: buffs and weapon enchants to keep up", function() S:ShowBuffWatcher() end)

---------------------------------------------------------------------------
-- Warnings window: how you're told when a situation needs a buff
---------------------------------------------------------------------------
local wwin
function S:ShowBuffWatchWarnings()
  if not wwin then
    local w = warnCfg()
    wwin = UI:Window("CC_BuffWatchWarn", "BuffWatcher warnings", 440, 470)
    wwin:SetFrameStrata("DIALOG")
    local y = -42
    local function lbl(t, yy) local f = UI:Text(wwin, t, "small"); f:SetPoint("TOPLEFT", 18, yy - 5); return f end
    wwin.on = UI:Check(wwin, "Warn me when a situation needs a buff", w.on ~= false, function(v) warnCfg().on = v end,
      "Off: situational buffs only show in the tracker.")
    wwin.on:SetPoint("TOPLEFT", 16, y); y = y - 30
    lbl("Message", y)
    wwin.style = UI:Dropdown(wwin, 250, STYLES, w.style, function(v) warnCfg().style = v end); wwin.style:SetPoint("TOPLEFT", 140, y); y = y - 30
    lbl("Sound", y)
    wwin.sound = UI:Dropdown(wwin, 250, SOUNDS, w.sound, function(v) warnCfg().sound = v end); wwin.sound:SetPoint("TOPLEFT", 140, y); y = y - 30
    local copts = {}
    for _, c in ipairs({ "orange", "red", "gold", "pink", "purple", "blue", "cyan", "green", "white" }) do copts[#copts + 1] = { value = c, text = c:sub(1, 1):upper() .. c:sub(2) } end
    lbl("Colour", y)
    wwin.color = UI:Dropdown(wwin, 140, copts, w.color, function(v) warnCfg().color = v end); wwin.color:SetPoint("TOPLEFT", 140, y); y = y - 30
    lbl("Text", y)
    wwin.text = UI:Edit(wwin, 270, 24, WARN_DEFAULT.text, function(_, t) warnCfg().text = S.Trim(t or "") end)
    wwin.text:SetPoint("TOPLEFT", 140, y)
    wwin.text:HookScript("OnTextChanged", function(self) warnCfg().text = S.Trim(self:GetText() or "") end)
    y = y - 26
    local th = UI:Text(wwin, "|cff888888{when} = the situation, {buff} = the buff's name|r", "small"); th:SetPoint("TOPLEFT", 140, y); y = y - 26
    local h = UI:Header(wwin, "Wait before warning again"); h:SetPoint("TOPLEFT", 16, y); y = y - 26
    wwin.cds = {}
    for _, c in ipairs(CONDS) do
      if c.value ~= "always" then
        local sl = UI:Slider(wwin, 400, c.text:gsub(" %b()", ""), 0, 120, 5, tonumber(w.cd[c.value]) or 0, function(v) warnCfg().cd[c.value] = v end,
          function(v) return v == 0 and "never" or (v .. " s") end)
        sl:SetPoint("TOPLEFT", 18, y); y = y - 28
        wwin.cds[c.value] = sl
      end
    end
    local test = UI:Button(wwin, "Test it", 80, 22, function() S.BuffWatchTestWarning() end)
    test:SetPoint("BOTTOMLEFT", 16, 14)
    local reset = UI:Button(wwin, "Defaults", 80, 22, function()
      local _, look = store(); look.warn = nil; local nw = warnCfg()
      wwin.on:SetChecked(true); wwin.text:SetText("")
      for _, d in ipairs({ { wwin.style, nw.style }, { wwin.sound, nw.sound }, { wwin.color, nw.color } }) do d[1]:SetValue(d[2]); d[1].value = d[2] end
      for k, sl in pairs(wwin.cds) do sl:SetValue(nw.cd[k] or 0) end
    end)
    reset:SetPoint("LEFT", test, "RIGHT", 6, 0)
    local done = UI:Button(wwin, "Done", 60, 22, function() wwin:Hide() end); done:SetPoint("BOTTOMRIGHT", -16, 14)
    wwin.text:SetText(w.text ~= WARN_DEFAULT.text and w.text or "")
  end
  wwin:Show(); wwin:Raise()
end
