-- Damage Meter: Command Center's own meter window on top of the game's built-in damage meter
-- (C_DamageMeter). This client doesn't let addons read the combat log, so the game's
-- meter is the only source of combat numbers.
--
-- In combat the game keeps the numbers secret: they can be SHOWN (text, bars) but not
-- compared or added up, so rows stay in the game's order and other players' details
-- wait until the fight ends. Out of combat everything can be read.
local _, S = ...
local UI = S.UI

local DM = C_DamageMeter
local SESSION = { Overall = 0, Current = 1, Expired = 2 }
local TYPES = {
  { id = 0, key = "dmg", label = "Damage done", stat = "cbDmg", rate = true },
  { id = 1, key = "dps", label = "DPS" },
  { id = 2, key = "heal", label = "Healing done", stat = "cbHeal", rate = true },
  { id = 3, key = "hps", label = "HPS" },
  { id = 4, key = "absorb", label = "Absorbs", stat = "cbAbsorb" },
  { id = 5, key = "int", label = "Interrupts", stat = "cbInt", count = true },
  { id = 6, key = "dispel", label = "Dispels", stat = "cbDispel", count = true },
  { id = 7, key = "taken", label = "Damage taken", stat = "cbTaken" },
  { id = 8, key = "avoid", label = "Avoidable damage taken", stat = "cbAvoid" },
  { id = 9, key = "deaths", label = "Deaths", count = true },
  { id = 10, key = "enemy", label = "Enemy damage taken" },
}
local DESC = {
  dmg = "All the damage you did to enemies this fight. In brackets: per second.",
  dps = "Damage per second: damage done divided by how long you were fighting.",
  heal = "Healing that actually landed (overhealing not counted). In brackets: per second.",
  hps = "Healing per second.",
  absorbs = "Damage soaked by your shields and absorb effects.",
  int = "Spell casts you interrupted (kicks, counterspells, stuns that stop a cast).",
  dispel = "Harmful effects you removed from allies, or buffs you stripped from enemies.",
  taken = "All the damage you took.",
  avoid = "Damage taken from things you could have dodged - standing in fire, frontal attacks...",
  deaths = "How many times each player died.",
  enemy = "Damage taken by each enemy.",
}
DESC.absorb = DESC.absorbs
local byKey = {}
for _, t in ipairs(TYPES) do byKey[t.key] = t; if Enum and Enum.DamageMeterType then
  -- use the game's own numbers when it has the enum
  local names = { dmg = "DamageDone", dps = "Dps", heal = "HealingDone", hps = "Hps", absorb = "Absorbs", int = "Interrupts",
    dispel = "Dispels", taken = "DamageTaken", avoid = "AvoidableDamageTaken", deaths = "Deaths", enemy = "EnemyDamageTaken" }
  local v = Enum.DamageMeterType[names[t.key]]
  if type(v) == "number" then t.id = v end
end end
if Enum and Enum.DamageMeterSessionType then
  for k in pairs(SESSION) do local v = Enum.DamageMeterSessionType[k]; if type(v) == "number" then SESSION[k] = v end end
end

local function G() return S.db.global end
local function cfg()
  local g = G()
  g.meter = type(g.meter) == "table" and g.meter or {}
  local m = g.meter
  m.mode = byKey[m.mode] and m.mode or "dmg"
  m.session = m.session or "Current"
  m.w = tonumber(m.w) or 300
  m.h = tonumber(m.h) or 220
  return m
end
local function combat() return InCombatLockdown and InCombatLockdown() end
local function secret(v) return issecretvalue ~= nil and issecretvalue(v) end

local lastProblem                              -- why the game's meter gave us nothing (shown in the window)
function S:MeterAvailable()
  if not DM or not DM.GetCombatSessionFromType then lastProblem = "This game version has no built-in damage meter."; return false end
  if DM.IsDamageMeterAvailable then
    local ok, a, why = pcall(DM.IsDamageMeterAvailable)
    if ok and a == false then
      lastProblem = "The game's damage meter is switched off" .. (why and (" (" .. tostring(why) .. ")") or "") ..
        ". Turn it on in the game's Options (search for \"damage meter\")."
      return false
    end
  end
  return true
end

---------------------------------------------------------------------------
-- Numbers
---------------------------------------------------------------------------
local function short(n)
  if n >= 1e9 then return string.format("%.2fB", n / 1e9) end
  if n >= 1e6 then return string.format("%.2fM", n / 1e6) end
  if n >= 1e4 then return string.format("%.1fk", n / 1e3) end
  return tostring(math.floor(n + 0.5))
end
-- something SetText can take: a plain string, or the game's own (secret) text
local function showNum(v)
  if v == nil then return "" end
  if secret(v) then
    if AbbreviateNumbers then local ok, t = pcall(AbbreviateNumbers, v); if ok and t ~= nil then return t end end
    return v
  end
  return short(tonumber(v) or 0)
end
local function setText(fs, v) if not pcall(fs.SetText, fs, v) then fs:SetText("-") end end

local function getSession(sessionKey, typeId)
  if not S:MeterAvailable() then return nil end
  local ok, s
  if type(sessionKey) == "number" then
    ok, s = pcall(DM.GetCombatSessionFromID, sessionKey, typeId)
  else
    ok, s = pcall(DM.GetCombatSessionFromType, SESSION[sessionKey] or 1, typeId)
  end
  if ok and type(s) == "table" then return s end
  if not ok then lastProblem = "The game refused: " .. tostring(s) end
end

-- the newest finished fight (its session id), for when "This fight" is empty
local function latestSessionID()
  if not DM or not DM.GetAvailableCombatSessions then return nil end
  local ok, list = pcall(DM.GetAvailableCombatSessions)
  if not ok or type(list) ~= "table" then return nil end
  local best
  for _, s in ipairs(list) do
    local id = s.sessionID
    if id and not secret(id) and (not best or id > best) then best = id end
  end
  return best
end
-- the player rows of a session, however the game hands them over (a list, or a
-- table keyed by something else); nothing if it can't be read right now
local function sourcesOf(sess)
  local out = {}
  pcall(function()
    local cs = sess and sess.combatSources
    if type(cs) ~= "table" then return end
    local n = 0
    for _, src in ipairs(cs) do n = n + 1; out[n] = src end
    if n == 0 then
      for _, src in pairs(cs) do if type(src) == "table" then n = n + 1; out[n] = src end end
    end
  end)
  return out
end
local function sourceCount(sess) return #sourcesOf(sess) end

---------------------------------------------------------------------------
-- (Command Center keeps no stats of its own: the game's meter has them all)
---------------------------------------------------------------------------
local function myAmount(sess)
  local amount, rate
  local ok = pcall(function()
    if type(sess.combatSources) ~= "table" then return end
    amount = 0
    for _, src in ipairs(sourcesOf(sess)) do
      if src.isLocalPlayer then
        if secret(src.totalAmount) then amount = nil return end
        amount = tonumber(src.totalAmount) or 0
        if not secret(src.amountPerSecond) then rate = tonumber(src.amountPerSecond) end
      end
    end
  end)
  if ok then return amount, rate end
end

local function recorded()
  if not S.G then return nil end
  S.G.loc.meterSeen = type(S.G.loc.meterSeen) == "table" and S.G.loc.meterSeen or {}
  return S.G.loc.meterSeen
end

function S:MeterRecordFights()
  if not S:MeterIsOn() then return 0 end
  if combat() or not S:MeterAvailable() or not DM.GetAvailableCombatSessions or not S.AwardBump then return 0 end
  local seen = recorded(); if not seen then return 0 end
  local ok, list = pcall(DM.GetAvailableCombatSessions)
  if not ok or type(list) ~= "table" then return 0 end
  local n = 0
  for _, info in ipairs(list) do
    local id = info.sessionID
    if id and not secret(id) then
      local dur = tonumber(info.durationSeconds) or 0
      local sig = tostring(id) .. ":" .. tostring(info.name or "") .. ":" .. math.floor(dur)
      if not seen[sig] then
        seen[sig] = S.now()
        n = n + 1
        S.AwardBump("cbFights", 1)
        if dur > 0 then S.AwardBump("cbTime", math.floor(dur)) end
        for _, t in ipairs(TYPES) do
          if t.stat then
            local amount, rate = myAmount(getSession(id, t.id))
            if amount and amount > 0 then
              S.AwardBump(t.stat, math.floor(amount))
              -- best DPS / HPS of the month: only fights long enough to mean something
              if t.key == "dmg" and dur >= 20 and rate then S.AwardBest("cbBestDps", math.floor(rate)) end
              if t.key == "heal" and dur >= 20 and rate then S.AwardBest("cbBestHps", math.floor(rate)) end
            end
          end
        end
      end
    end
  end
  -- forget old signatures
  local cut = S.now() - 3 * 86400
  for k, t in pairs(seen) do if t < cut then seen[k] = nil end end
  return n
end

S:On("PLAYER_REGEN_ENABLED", function() C_Timer.After(1.5, function() S:MeterRecordFights() end) end)
S:On("DAMAGE_METER_COMBAT_SESSION_UPDATED", function() if not combat() then C_Timer.After(1, function() S:MeterRecordFights() end) end end)

-- deaths anywhere
S:On("PLAYER_DEAD", function() if S.AwardBump and S:MeterIsOn() then S.AwardBump("cbDeaths", 1) end end)

-- threat pulls: you (not a tank) become the one being hit by a mob, in a group
local lastStatus, lastPull = 0, 0
S:On("UNIT_THREAT_SITUATION_UPDATE", function(_, unit)
  if unit ~= "player" or not UnitThreatSituation then return end
  local ok, st = pcall(UnitThreatSituation, "player")
  if not ok or st == nil or secret(st) then return end
  local was = lastStatus; lastStatus = st
  if st < 3 or was >= 3 then return end
  if not (IsInGroup and IsInGroup()) or not S:MeterIsOn() then return end
  local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned("player")
  if role == "TANK" then return end
  if GetTime() - lastPull < 8 then return end
  lastPull = GetTime()
  if S.AwardBump then S.AwardBump("cbPulls", 1) end
end)
S:On("PLAYER_REGEN_ENABLED", function() lastStatus = 0 end)

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local win
local ROW_H = 18
local AMT_W, RATE_W = 70, 52
local rows = {}
-- the amount column sits next to the rate column, or at the edge when there's no rate
local function placeColumns(r, hasRate)
  r.val:ClearAllPoints()
  if hasRate then r.val:SetPoint("RIGHT", r.rate, "LEFT", -4, 0) else r.val:SetPoint("RIGHT", -4, 0) end
  r.rate:SetShown(hasRate)
end
-- column titles for each mode: amount, per second
local HEAD = { dmg = { "Damage Done", "DPS" }, heal = { "Healing Done", "HPS" }, dps = { "DPS" }, hps = { "HPS" },
  absorb = { "Absorbed" }, int = { "Interrupts" }, dispel = { "Dispels" }, taken = { "Damage Taken" },
  avoid = { "Avoidable" }, deaths = { "Deaths" }, enemy = { "Damage Taken" } }
-- a class picture when the game gives no spec icon
local function classIcon(tex, cls)
  local co = cls and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[cls]
  if not co then return false end
  tex:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
  tex:SetTexCoord(co[1], co[2], co[3], co[4])
  return true
end

local function classColor(cls)
  local c = cls and ((CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[cls]) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]))
  if c then return c.r, c.g, c.b end
  return 0.6, 0.6, 0.6
end

local function getRow(i)
  if rows[i] then return rows[i] end
  local r = CreateFrame("StatusBar", nil, win.list)
  r:SetHeight(ROW_H - 1)
  r:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints(); r.bg:SetColorTexture(0, 0, 0, 0.35)
  r.icon = r:CreateTexture(nil, "OVERLAY"); r.icon:SetSize(ROW_H - 3, ROW_H - 3); r.icon:SetPoint("LEFT", 1, 0)
  r.name = r:CreateFontString(nil, "OVERLAY"); r.name:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
  r.name:SetPoint("LEFT", ROW_H + 2, 0); r.name:SetJustifyH("LEFT"); r.name:SetWordWrap(false)
  r.val = r:CreateFontString(nil, "OVERLAY"); r.val:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE"); r.val:SetJustifyH("RIGHT")
  r.rate = r:CreateFontString(nil, "OVERLAY"); r.rate:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE"); r.rate:SetJustifyH("RIGHT")
  r.rate:SetPoint("RIGHT", -4, 0); r.rate:SetWidth(RATE_W)
  r.val:SetWidth(AMT_W)
  r.name:SetPoint("RIGHT", r.val, "LEFT", -6, 0)
  r:EnableMouse(true)
  r:SetScript("OnEnter", function(self) S:MeterRowTip(self) end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  rows[i] = r
  return r
end

-- spell breakdown for a row (out of combat for everyone, in combat only for you)
function S:MeterRowTip(r)
  local src = r.src; if not src then return end
  GameTooltip:SetOwner(r, "ANCHOR_LEFT")
  pcall(GameTooltip.AddLine, GameTooltip, src.name, 1, 0.82, 0)
  local t = byKey[cfg().mode]
  if combat() and not src.isLocalPlayer then
    GameTooltip:AddLine("Details after the fight.", 0.7, 0.7, 0.7)
    GameTooltip:Show() return
  end
  if DM.GetCombatSessionSourceFromType and not secret(src.sourceGUID) then
    local sk = cfg().session
    local ok, d
    if type(sk) == "number" and DM.GetCombatSessionSourceFromID then ok, d = pcall(DM.GetCombatSessionSourceFromID, sk, t.id, src.sourceGUID)
    else ok, d = pcall(DM.GetCombatSessionSourceFromType, SESSION[sk] or 1, t.id, src.sourceGUID) end
    if ok and type(d) == "table" and type(d.combatSpells) == "table" then
      local n = 0
      for _, sp in ipairs(d.combatSpells) do
        n = n + 1; if n > 10 then break end
        local name = sp.spellID and ((C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(sp.spellID)) or (GetSpellInfo and GetSpellInfo(sp.spellID))) or sp.creatureName or "?"
        pcall(GameTooltip.AddDoubleLine, GameTooltip, name, showNum(sp.totalAmount), 1, 1, 1, 1, 1, 1)
      end
      if n == 0 then GameTooltip:AddLine("No breakdown.", 0.7, 0.7, 0.7) end
    end
  end
  GameTooltip:Show()
end

local function sessionLabel(sk)
  if sk == "Current" then return "This fight" elseif sk == "Overall" then return "Overall" end
  if type(sk) == "number" and DM and DM.GetAvailableCombatSessions then
    local ok, list = pcall(DM.GetAvailableCombatSessions)
    if ok and type(list) == "table" then for _, s in ipairs(list) do if s.sessionID == sk then return s.name or ("Fight " .. sk) end end end
  end
  return "Fight"
end

function S:RefreshMeter()
  if not win or not win:IsShown() or win.guildView then return end
  local c = cfg()
  local t = byKey[c.mode]
  win.modeBtn:SetText(t.label)
  local hd = HEAD[t.key] or { t.label }
  win.hAmt:SetText(hd[1]); win.hRate:SetText(t.rate and hd[2] or "")
  win.hAmt:ClearAllPoints()
  if t.rate then win.hAmt:SetPoint("RIGHT", win.hRate, "LEFT", -4, 0) else win.hAmt:SetPoint("RIGHT", win.head, "RIGHT", -4, 0) end
  win.hRate:SetShown(t.rate and true or false)
  win.lastList, win.lastReadable, win.lastSess = nil, nil, nil
  win.sessBtn:SetText(sessionLabel(c.session))
  if not S:MeterAvailable() then
    for _, r in ipairs(rows) do r:Hide() end
    win.msg:SetText("The game's damage meter isn't available here.")
    win.msg:Show()
    return
  end
  lastProblem = nil
  local sess = getSession(c.session, t.id)
  win.fallback = nil
  -- "This fight" is empty once the fight is over: show the last fight instead
  if c.session == "Current" and sourceCount(sess) == 0 then
    local s2 = getSession("Expired", t.id)
    if sourceCount(s2) > 0 then sess = s2; win.fallback = "Expired"
    elseif not combat() then
      local id = latestSessionID()
      if id then
        s2 = getSession(id, t.id)
        if sourceCount(s2) > 0 then sess = s2; win.fallback = id end
      end
    end
  end
  local list = {}
  -- in combat the values inside are secret: only look, never compare
  for _, src in ipairs(sourcesOf(sess)) do list[#list + 1] = src end
  -- out of combat the numbers can be sorted; in combat they stay in the game's order
  local readable = #list > 0 and not secret(list[1].totalAmount)
  if readable then
    for _, src in ipairs(list) do if secret(src.totalAmount) then readable = false end end
  end
  if readable then table.sort(list, function(a, b) return (tonumber(a.totalAmount) or 0) > (tonumber(b.totalAmount) or 0) end) end
  local maxAmount
  pcall(function() maxAmount = sess and sess.maxAmount end)
  if not secret(maxAmount) and (maxAmount == nil or maxAmount == 0) then
    maxAmount = (readable and list[1]) and list[1].totalAmount or 1
  end
  local fit = math.max(1, math.floor((win.list:GetHeight() or 100) / ROW_H))
  for i = 1, math.max(#rows, math.min(#list, fit)) do
    local r = getRow(i)
    local src = list[i]
    if src and i <= fit then
      -- every step on its own: a value the game keeps secret only blanks that one
      -- piece (never test a secret with "or"/"and"/"==", the game forbids it)
      local function try(fn, ...) local ok, err = pcall(fn, ...); if not ok then win.rowErr = tostring(err) end return ok end
      r.src = src
      r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H); r:SetPoint("RIGHT", win.list, "RIGHT", 0, 0)
      try(function() r:SetStatusBarColor(classColor(src.classFilename)) end)
      if not try(function() r:SetMinMaxValues(0, maxAmount) end) then pcall(r.SetMinMaxValues, r, 0, 1) end
      if not try(function() r:SetValue(src.totalAmount) end) then pcall(r.SetValue, r, 0) end
      if not try(function()
        local icon = src.specIconID
        if icon and icon ~= 0 then r.icon:SetTexture(icon); r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93); r.icon:Show()
        elseif classIcon(r.icon, src.classFilename) then r.icon:Show()
        else r.icon:Hide() end
      end) then r.icon:Hide() end
      if not try(function()
        local nm = src.name
        if secret(nm) then r.name:SetText(nm) return end
        nm = tostring(nm or "?")
        if readable then nm = i .. ". " .. ((Ambiguate and Ambiguate(nm, "short")) or nm) end
        r.name:SetText(nm)
      end) then r.name:SetText("?") end
      placeColumns(r, t.rate and true or false)
      if not try(function() r.val:SetText(showNum(src.totalAmount)) end) then r.val:SetText("-") end
      if t.rate and not try(function() r.rate:SetText(showNum(src.amountPerSecond)) end) then r.rate:SetText("-") end
      r:Show()
    else
      r:Hide(); r.src = nil
    end
  end
  win.lastList, win.lastReadable = list, readable
  win.lastSess = sess
  if #list == 0 or win.rowErr then
    -- something to read but no rows: keep a note of what the game handed over
    local snap = {}
    pcall(function()
      snap[#snap + 1] = date("%H:%M:%S") .. " combat=" .. tostring(combat()) .. " session=" .. tostring(c.session) .. " fallback=" .. tostring(win.fallback)
      snap[#snap + 1] = "sess type=" .. type(sess) .. (sess and (" secret=" .. tostring(secret(sess))) or "")
      if sess then
        local keys = {}
        for k, v in pairs(sess) do keys[#keys + 1] = tostring(k) .. ":" .. type(v) end
        snap[#snap + 1] = "fields " .. table.concat(keys, ",")
        local cs = sess.combatSources
        snap[#snap + 1] = "combatSources type=" .. type(cs) .. " secret=" .. tostring(secret(cs)) .. " #=" .. tostring(type(cs) == "table" and #cs or "-")
        if type(cs) == "table" then
          for k, v in pairs(cs) do
            local f = {}
            if type(v) == "table" then for k2, v2 in pairs(v) do f[#f + 1] = tostring(k2) .. "=" .. (secret(v2) and "SECRET" or tostring(v2)) end end
            snap[#snap + 1] = "  [" .. tostring(k) .. "] " .. type(v) .. " " .. table.concat(f, " ")
            break
          end
        end
      end
    end)
    if win.rowErr then snap[#snap + 1] = "row error: " .. win.rowErr; win.rowErr = nil end
    G().meterSnap = snap
  end
  win.msg:SetShown(#list == 0)
  win.msg:SetText(lastProblem or (combat() and "Fighting... (waiting for the game's meter)" or "No numbers yet - go hit something.\n|cff888888Still empty after a fight? Type /ccenter meterdebug|r"))
  if win.fallback then win.sessBtn:SetText("Last fight") end
  -- the totals line
  local total, dur
  pcall(function() total = sess and sess.totalAmount; dur = sess and sess.durationSeconds end)
  if not secret(total) and not secret(dur) and total ~= nil and dur ~= nil and dur > 0 then
    win.foot:SetText(string.format("|cffaaaaaaTotal %s  -  %d:%02d|r", short(tonumber(total) or 0), math.floor(dur / 60), math.floor(dur % 60)))
  else
    win.foot:SetText(combat() and "|cff888888Other players' details show after the fight.|r" or "")
  end
end

local function build()
  local c = cfg()
  win = UI:Window("CC_Meter", "Damage Meter", c.w, c.h, { header = 26 })
  win:SetFrameStrata("MEDIUM")
  if UISpecialFrames then
    for i = #UISpecialFrames, 1, -1 do if UISpecialFrames[i] == "CC_Meter" then table.remove(UISpecialFrames, i) end end
  end
  -- where you left it: the top-left corner, in screen units (works whatever anchor
  -- the game used while dragging or resizing)
  if type(c.at) == "table" and c.at[1] and c.at[2] then
    win:ClearAllPoints(); win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", c.at[1], c.at[2])
  end
  win:HookScript("OnDragStop", function() S:MeterSavePlace() end)

  win.modeBtn = UI:Button(win, "", 150, 20, function(self)
    local items = { { text = "Show", title = true } }
    for _, t in ipairs(TYPES) do
      items[#items + 1] = { text = t.label, tip = DESC[t.key], checked = cfg().mode == t.key, func = function() cfg().mode = t.key; S:RefreshMeter() end }
    end
    UI:Menu(self, items)
  end)
  win.modeBtn:SetPoint("TOPLEFT", 8, -32)
  win.sessBtn = UI:Button(win, "", 100, 20, function(self)
    local items = { { text = "Fight", title = true },
      { text = "This fight", checked = cfg().session == "Current", func = function() cfg().session = "Current"; S:RefreshMeter() end },
      { text = "Overall", checked = cfg().session == "Overall", func = function() cfg().session = "Overall"; S:RefreshMeter() end } }
    if DM and DM.GetAvailableCombatSessions and not combat() then
      local ok, list = pcall(DM.GetAvailableCombatSessions)
      if ok and type(list) == "table" then
        for i = #list, math.max(1, #list - 9), -1 do
          local s = list[i]
          if s and s.sessionID and not secret(s.sessionID) then
            local d = tonumber(s.durationSeconds)
            items[#items + 1] = { text = (s.name or "Fight") .. (d and string.format("  |cff888888%d:%02d|r", math.floor(d / 60), math.floor(d % 60)) or ""),
              checked = cfg().session == s.sessionID, func = function() cfg().session = s.sessionID; S:RefreshMeter() end }
          end
        end
      end
    end
    UI:Menu(self, items)
  end)
  win.sessBtn:SetPoint("LEFT", win.modeBtn, "RIGHT", 4, 0)
  UI:Tip(win.modeBtn, function() return byKey[cfg().mode].label end, function() return { DESC[cfg().mode] or "", "|cff888888Click to pick what to show.|r" } end)
  UI:Tip(win.sessBtn, "Which fight", "This fight, everything since the last reset (Overall), or one of your recent fights.")
  -- the three buttons share the width and never overlap
  local function layoutTop()
    local W = win:GetWidth() or 300
    local avail = W - 16 - 4
    local mode = math.floor(avail * 0.6)
    win.modeBtn:SetWidth(math.max(40, mode))
    win.sessBtn:SetWidth(math.max(30, avail - mode))
    win.modeBtn.fs:SetWidth(win.modeBtn:GetWidth() - 10)
    win.sessBtn.fs:SetWidth(win.sessBtn:GetWidth() - 10)
  end
  win.layoutTop = layoutTop
  win:HookScript("OnSizeChanged", layoutTop)
  layoutTop()
  win:HeaderButton("trash", "Reset", "Clear the game's damage meter (all fights).", function()
    UI:Confirm("Clear all damage meter fights?", function()
      S:MeterRecordFights()                  -- save your stats first
      if DM and DM.ResetAllCombatSessions then pcall(DM.ResetAllCombatSessions) end
      cfg().session = "Current"
      S:RefreshMeter()
    end, "Clear")
  end)

  win:HeaderButton("share", "Share to chat", "Post this meter in a chat channel.", function(self) S:MeterShareMenu(self) end)
  win.list = CreateFrame("Frame", nil, win)
  win.head = CreateFrame("Frame", nil, win)
  win.head:SetPoint("TOPLEFT", 8, -57); win.head:SetPoint("TOPRIGHT", -8, -57); win.head:SetHeight(16)
  local hbg = win.head:CreateTexture(nil, "BACKGROUND"); hbg:SetAllPoints(); hbg:SetColorTexture(0, 0, 0, 0.3)
  local function headText(txt, w, tip)
    local fs = win.head:CreateFontString(nil, "OVERLAY"); fs:SetFont("Fonts\\FRIZQT__.TTF", 10, ""); fs:SetText(txt)
    UI:Skin(fs, function(self, th) self:SetTextColor(th.gold[1], th.gold[2], th.gold[3]) end)
    if w then fs:SetWidth(w) end
    return fs
  end
  win.hName = headText("Name"); win.hName:SetPoint("LEFT", ROW_H + 2, 0); win.hName:SetJustifyH("LEFT")
  win.hRate = headText("DPS", RATE_W); win.hRate:SetPoint("RIGHT", -4, 0); win.hRate:SetJustifyH("RIGHT")
  win.hAmt = headText("Damage Done", AMT_W + 30); win.hAmt:SetJustifyH("RIGHT")
  -- hovering the column titles explains them
  local tipF = CreateFrame("Frame", nil, win.head); tipF:SetAllPoints()
  UI:Tip(tipF, function() return byKey[cfg().mode].label end, function()
    local t = byKey[cfg().mode]
    local lines = { DESC[t.key] or "" }
    if t.rate then lines[#lines + 1] = "|cff888888Right column: per second over the fight.|r" end
    lines[#lines + 1] = "|cff888888The picture by each name is their specialization.|r"
    return lines
  end)
  win.list = CreateFrame("Frame", nil, win)
  win.list:SetPoint("TOPLEFT", 8, -75); win.list:SetPoint("BOTTOMRIGHT", -8, 22)
  win.msg = UI:Text(win, "", "small", "CENTER"); win.msg:SetPoint("TOP", win.list, "TOP", 0, -20); win.msg:SetWidth(260)
  win.foot = UI:Text(win, "", "small"); win.foot:SetPoint("BOTTOMLEFT", 10, 6)

  win:SetResizable(true)
  if win.SetResizeBounds then win:SetResizeBounds(240, 120, 900, 900) elseif win.SetMinResize then win:SetMinResize(240, 120) end
  local grip = CreateFrame("Button", nil, win)
  grip:SetSize(14, 14); grip:SetPoint("BOTTOMRIGHT", -2, 2)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetScript("OnMouseDown", function() if not win.guildView then win:StartSizing("BOTTOMRIGHT") end end)
  grip:SetScript("OnMouseUp", function()
    win:StopMovingOrSizing()
    cfg().w, cfg().h = math.floor(win:GetWidth() + 0.5), math.floor(win:GetHeight() + 0.5)
    S:MeterSavePlace()
    S:RefreshMeter()
  end)

  win:HookScript("OnShow", function() cfg().open = true; S:RefreshMeter() end)
  win:HookScript("OnHide", function()
    if S.SnapBusy and S.SnapBusy() then return end
    if not UIParent:IsShown() or S.__loggingOut then return end    -- the whole interface went away, not you
    cfg().open = false
  end)
  win.close:HookScript("OnClick", function() cfg().open = false end)
  -- live while fighting (the game's numbers change constantly), calm otherwise
  local acc = 0
  win:HookScript("OnUpdate", function(_, el)
    acc = acc + el
    if acc >= (combat() and 0.5 or 2) then acc = 0; S:RefreshMeter() end
  end)
end

S:On("DAMAGE_METER_CURRENT_SESSION_UPDATED", function() if win and win:IsShown() and not combat() then S:RefreshMeter() end end)
S:On("DAMAGE_METER_RESET", function() if win and win:IsShown() then S:RefreshMeter() end end)

function S:MeterSavePlace()
  if not win then return end
  local l, t = win:GetLeft(), win:GetTop()
  if not l or not t then return end
  local fs, us = win:GetEffectiveScale() or 1, UIParent:GetEffectiveScale() or 1
  cfg().at = { math.floor(l * fs / us + 0.5), math.floor(t * fs / us + 0.5) }
  cfg().pos = nil
  win.ccOwnSpot = true          -- from now on it opens here, not out of the dock icon
  win.__fromDock = nil
end

---------------------------------------------------------------------------
-- Share to chat
---------------------------------------------------------------------------
local CHANNELS = {
  { "SAY", "Say", "Only works inside dungeons and raids (the game blocks addons from /say outside)." },
  { "PARTY", "Party" }, { "RAID", "Raid" }, { "INSTANCE_CHAT", "Instance" },
  { "GUILD", "Guild" }, { "OFFICER", "Officer" }, { "WHISPER", "Whisper your target" },
}
local function canUse(ch)
  if ch == "PARTY" then return IsInGroup and IsInGroup() end
  if ch == "RAID" then return IsInRaid and IsInRaid() end
  if ch == "INSTANCE_CHAT" then return IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) end
  if ch == "GUILD" then return IsInGuild and IsInGuild() end
  if ch == "OFFICER" then return IsInGuild and IsInGuild() end
  if ch == "WHISPER" then return UnitIsPlayer and UnitIsPlayer("target") and not (UnitIsUnit and UnitIsUnit("target", "player")) or false end
  if ch == "SAY" then local inst = IsInInstance and IsInInstance(); return inst and true or false end
  return true
end

function S:MeterShareLines(n)
  if not win or not win.lastList then return nil, "Open the meter first." end
  if combat() or not win.lastReadable then return nil, "The game keeps the numbers secret during a fight - share it afterwards." end
  local list = win.lastList
  if #list == 0 then return nil, "Nothing to share yet." end
  local c = cfg()
  local t = byKey[c.mode]
  local fight = win.fallback and "last fight" or sessionLabel(c.session)
  local lines = { t.label .. " - " .. fight .. ":" }
  for i = 1, math.min(n or 5, #list) do
    local src = list[i]
    local name = (not secret(src.name) and src.name) and ((Ambiguate and Ambiguate(src.name, "short")) or src.name) or "?"
    local line = i .. ". " .. name .. "  " .. showNum(src.totalAmount)
    if t.rate and not secret(src.amountPerSecond) and src.amountPerSecond then line = line .. " (" .. showNum(src.amountPerSecond) .. ")" end
    lines[#lines + 1] = line
  end
  return lines
end

function S:MeterShare(ch)
  local c = cfg()
  ch = ch or c.shareChan or "PARTY"
  if not canUse(ch) then
    local why = { PARTY = "You're not in a group.", RAID = "You're not in a raid.", INSTANCE_CHAT = "You're not in an instance group.",
      GUILD = "You're not in a guild.", OFFICER = "Officer chat is for officers.", WHISPER = "Target a player to whisper them.",
      SAY = "The game only lets addons use /say inside dungeons and raids." }
    UI:Alert(why[ch] or "You can't post there right now.") return
  end
  local lines, err = S:MeterShareLines(c.shareLines or 5)
  if not lines then UI:Alert(err) return end
  local target = ch == "WHISPER" and GetUnitName and GetUnitName("target", true) or nil
  if ch == "WHISPER" then   -- don't pop the Messenger open for our own report
    S.msgrSending = (S.msgrSending or 0) + #lines
    C_Timer.After(#lines * 0.15 + 3, function() S.msgrSending = math.max(0, (S.msgrSending or 0) - #lines) end)
  end
  for i, l in ipairs(lines) do
    -- a short gap between lines so the chat doesn't throttle us
    C_Timer.After((i - 1) * 0.15, function() SendChatMessage(l, ch, nil, target) end)
  end
  c.shareChan = ch
end

function S:MeterShareMenu(anchor)
  local c = cfg()
  local items = { { text = "Share to", title = true } }
  for _, chn in ipairs(CHANNELS) do
    local ok = canUse(chn[1])
    items[#items + 1] = { text = chn[2], checked = c.shareChan == chn[1], disabled = not ok, tip = chn[3],
      func = function() S:MeterShare(chn[1]) end }
  end
  items[#items + 1] = { text = "How many players", title = true }
  for _, n in ipairs({ 3, 5, 10 }) do
    items[#items + 1] = { text = "Top " .. n, checked = (c.shareLines or 5) == n, func = function() c.shareLines = n; S:MeterShareMenu(anchor) end }
  end
  UI:Menu(anchor, items)
end

function S:ShowMeter()
  if not S:MeterIsOn() then
    UI:Confirm("Turn on the damage meter?\n\n|cffaaaaaaIt shows damage, healing, interrupts, dispels and more for you and your group.|r",
      function() S:SetMeterOn(true); S:ShowMeter() end, "Turn on")
    return
  end
  if not win then build() end
  -- once you've placed it, it always opens right there
  local at = cfg().at
  if type(at) == "table" and at[1] and at[2] then
    win.ccOwnSpot = true; win.__fromDock = nil
    win:ClearAllPoints(); win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", at[1], at[2])
  end
  win:Show(); win:Raise()
  S:RefreshMeter()
end
function S:HideMeter() if win then win:Hide() end end

---------------------------------------------------------------------------
-- On / off. We read the game's built-in damage meter, so that has to be
-- switched on - its own window is hidden (made invisible) so you only see ours.
---------------------------------------------------------------------------
function S:MeterIsOn()
  if not S.db then return false end
  local g = G()
  -- already using it before this setting existed (moved / opened the window): keep it on
  if g.meterOn == nil and type(g.meter) == "table" and (g.meter.open ~= nil or g.meter.at or g.meter.pos) then g.meterOn = true end
  return g.meterOn == true
end

-- the game's meter windows (made invisible, mouse off) - or shown again
local GAME_FRAMES = { "DamageMeter", "DamageMeterSessionWindow1", "DamageMeterSessionWindow2", "DamageMeterSessionWindow3", "DamageMeterSessionWindow4" }
local hooked = {}
local function quiet(f, hide)
  local function walk(fr)
    pcall(function() if fr.EnableMouse then fr:EnableMouse(not hide) end end)
    pcall(function() if fr.EnableMouseWheel then fr:EnableMouseWheel(not hide) end end)
    for _, ch in ipairs({ fr:GetChildren() }) do walk(ch) end
  end
  pcall(function() f:SetAlpha(hide and 0 or 1) end)
  pcall(walk, f)
end
local function wantHidden() return S.db and S:MeterIsOn() and G().hideGameMeter ~= false end
function S:MeterApplyGameWindow()
  for _, name in ipairs(GAME_FRAMES) do
    local f = _G[name]
    if f then
      if not hooked[f] then
        hooked[f] = true
        -- the game shows it again (new fight, loading screen): keep it invisible
        f:HookScript("OnShow", function(self) if wantHidden() then quiet(self, true) end end)
      end
      quiet(f, wantHidden())
    end
  end
end

-- switch the game's meter on (it has to be on for us to read it)
local function gameMeterOn()
  local ok, a = pcall(function() return DM and DM.IsDamageMeterAvailable and DM.IsDamageMeterAvailable() end)
  return ok and a == true
end
local function enableGameMeter()
  if not DM then return false end
  if gameMeterOn() then return true end
  for _, cv in ipairs({ "damageMeterEnabled", "enableDamageMeter", "damageMeter" }) do
    local cur = (C_CVar and C_CVar.GetCVar and C_CVar.GetCVar(cv)) or (GetCVar and GetCVar(cv))
    if cur ~= nil then
      if C_CVar and C_CVar.SetCVar then pcall(C_CVar.SetCVar, cv, "1") elseif SetCVar then pcall(SetCVar, cv, "1") end
    end
  end
  return gameMeterOn()
end
local function meterHelp()
  UI:Alert("Command Center couldn't switch on the game's damage meter for you - please do it once:\n\n" ..
    "1. Press |cffffd100Escape|r and click |cffffd100Options|r\n" ..
    "2. Open |cffffd100Gameplay Enhancements|r\n" ..
    "3. Tick |cffffd100Damage Meter|r\n\n" ..
    "|cffaaaaaaCommand Center hides the game's own meter window for you - only ours shows.|r")
end
S.MeterHelp = meterHelp
function S:MeterGameOn() return gameMeterOn() end

function S:SetMeterOn(on)
  G().meterOn = on and true or false
  if on then
    if not DM then UI:Alert("This version of the game has no built-in damage meter, so the damage meter can't work here.") return end
    enableGameMeter()
    S:MeterApplyGameWindow()
    -- the game can take a moment after the setting changes
    C_Timer.After(1.5, function()
      S:MeterApplyGameWindow()
      if gameMeterOn() then
        S:Print("Damage meter on.")
      else
        meterHelp()
      end
    end)
  else
    S:MeterApplyGameWindow()                              -- give the game's window back
    if win then win:Hide() end
    S:Print("Damage meter off - your combat stats are no longer recorded.")
  end
  if S.RefreshCurrent then pcall(S.RefreshCurrent, S) end
end

S:On("PLAYER_ENTERING_WORLD", function() C_Timer.After(2, function() if S.db then S:MeterApplyGameWindow() end end) end)
S:On("ADDON_LOADED", function(_, name) if name == "Blizzard_DamageMeter" then C_Timer.After(0.5, function() if S.db then S:MeterApplyGameWindow() end end) end end)
S:On("DAMAGE_METER_COMBAT_SESSION_UPDATED", function() if wantHidden() then S:MeterApplyGameWindow() end end)

-- open again after logging in or /reload if it was open (loading screens keep it as it is)
local reopened = false
local function reopen()
  if reopened or not S.db then return end
  reopened = true
  if cfg().open and S:MeterIsOn() then S:ShowMeter() end
end
S:On("PLAYER_ENTERING_WORLD", function() C_Timer.After(2, reopen) end)
S:Listen("LOGIN", function() C_Timer.After(3, reopen) end)
-- logging out / reloading hides every window: remember the meter as it really was
S:On("PLAYER_LOGOUT", function()
  S.__loggingOut = true
  if win and S.db then cfg().open = win:IsShown() and true or false; S:MeterSavePlace() end
end)

---------------------------------------------------------------------------
-- /ccenter meterdebug: what the game's meter actually gives us. Printed, and
-- saved (SavedVariables, after /reload) so it can be read for a bug report.
---------------------------------------------------------------------------
function S:MeterDebug()
  local out = {}
  local function line(...) local t = {} for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end out[#out + 1] = table.concat(t, " ") end
  line("time", date("%Y-%m-%d %H:%M:%S"), "combat", tostring(combat()))
  line("C_DamageMeter", DM and "yes" or "NO")
  if DM then
    local fns = {}
    for k, v in pairs(DM) do fns[#fns + 1] = k .. (type(v) == "function" and "()" or "") end
    table.sort(fns); line("functions:", table.concat(fns, ", "))
    if DM.IsDamageMeterAvailable then line("IsDamageMeterAvailable:", pcall(DM.IsDamageMeterAvailable)) end
    if DM.GetAvailableCombatSessions then
      local ok, list = pcall(DM.GetAvailableCombatSessions)
      line("GetAvailableCombatSessions ok", ok, "type", type(list), "count", type(list) == "table" and #list or "-")
      if ok and type(list) == "table" then
        for i = math.max(1, #list - 4), #list do local s = list[i]; if s then line("  session", s.sessionID, s.name, s.durationSeconds) end end
      end
    end
    for _, sk in ipairs({ "Current", "Overall", "Expired" }) do
      local ok, sess = pcall(DM.GetCombatSessionFromType, SESSION[sk], byKey.dmg.id)
      local n = ok and sourceCount(sess) or "-"
      line(sk, "(" .. tostring(SESSION[sk]) .. ")", "ok", ok, "type", type(sess), "sources", n, ok and "" or tostring(sess))
      if ok and type(sess) == "table" then
        pcall(function()
          local keys = {}
          for k in pairs(sess) do keys[#keys + 1] = tostring(k) end
          line("  fields:", table.concat(keys, ","), "max", sess.maxAmount, "total", sess.totalAmount)
          local src = sess.combatSources and sess.combatSources[1]
          if src then
            local f = {}
            for k, v in pairs(src) do f[#f + 1] = tostring(k) .. "=" .. (secret(v) and "SECRET" or tostring(v)) end
            line("  first source:", table.concat(f, " "))
          end
        end)
      end
    end
  end
  if Enum then
    line("Enum.DamageMeterType", Enum.DamageMeterType and "yes" or "no", "Enum.DamageMeterSessionType", Enum.DamageMeterSessionType and "yes" or "no")
  end
  for _, cv in ipairs({ "damageMeterEnabled", "damageMeter", "enableDamageMeter", "showDamageMeter", "DamageMeterEnabled" }) do
    local v = GetCVar and GetCVar(cv) or (C_CVar and C_CVar.GetCVar and C_CVar.GetCVar(cv))
    if v ~= nil then line("cvar", cv, "=", v) end
  end
  G().meterDiag = out
  S:Print("Damage meter check:")
  for _, l in ipairs(out) do print("  " .. l) end
  S:Print("Saved - type |cffffd100/reload|r so it's written to your saved files.")
end
S:AddCommand("meterdebug", "", "Check what the game's damage meter is giving us (for bug reports)", function() S:MeterDebug() end)

S:AddCommand("meter", "", "Damage meter: damage, healing, interrupts, dispels and more", function() S:ShowMeter() end)
