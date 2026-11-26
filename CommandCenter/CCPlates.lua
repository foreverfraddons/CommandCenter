-- CCPlates: Command Center's own nameplates, drawn in the theme's colours.
-- Features picked from the popular nameplate addons (Plater, Platynator, Threat Plates,
-- KuiNameplates, Tidy/NeatPlates, ElvUI, nPlates):
--   * looks (presets), size, scale, 20 CC bar textures, roundness 0-5, theme / black / no border
--   * name (above / inside / below), level with difficulty colour, elite / rare / boss badges
--   * health text (percent, current, both, current / max, missing)
--   * colours: reaction, class colours for players, tapped grey, threat for tank or
--     damage / healing (auto from your role), execute range with a marker line,
--     your own colour per NPC name
--   * cast bars: icon, name, timer, spark, "can't interrupt" shield, interrupt-ready
--     colour, "Interrupted" flash
--   * target: bigger, glow, arrows, others faded; mouse-over highlight
--   * Blizzard's own nameplate debuffs: the game's debuff row moved onto the plate
--     (timers keep working in a fight), or copied into CCPlates icons; raid marks, quest mobs, combo points on your target, friendly plates as names only
--   * the game's nameplate options (show enemies / friends, stacking, distance)
--   * live preview in the settings window
-- Forever's nameplates are "restricted": nothing on them (the game's parts or ours) may be
-- measured (GetPoint, GetWidth, GetLeft... fail), so CCPlates keeps every size itself.
-- WoW Forever hides some unit values from addons in combat ("secret" values): they are
-- only handed to the game's own widgets (status bars, font strings), never compared.
-- The game's plate is kept alive under ours (only made invisible), so its debuff
-- code - and Unit Frames' copy of it - keeps working.
local _, S = ...
local UI = S.UI
-- revision of this file: bump on every deploy (Revisions.lua warns in game if an older copy loads)
local REV = 36
if S.ModuleRev then S:ModuleRev("CCPlates", REV) end

local P = { plates = {}, byUnit = {}, hooked = setmetatable({}, { __mode = "k" }), hiddenUF = setmetatable({}, { __mode = "k" }),
  borrowed = setmetatable({}, { __mode = "k" }), previews = {} }
S.CCP = P

local WHITE = "Interface\\Buttons\\WHITE8x8"
local MEDIA = UI.MEDIA .. "Plates\\"
local BARS = UI.MEDIA .. "Bars\\"
local FRIZ = "Fonts\\FRIZQT__.TTF"
local BACKDROP_T = BackdropTemplateMixin and "BackdropTemplate" or nil
local floor, ceil, max, min, abs = math.floor, math.ceil, math.max, math.min, math.abs
local unpack = unpack or table.unpack

local function G() return S.db.global end
local function combat() return InCombatLockdown and InCombatLockdown() end
local isSecret = issecretvalue or function() return false end
local function sec(a, b, c) return isSecret(a) or isSecret(b) or isSecret(c) end
local function try(fn, ...)
  if not fn then return end
  local ok, a, b, c, d, e, f, g, h, i = pcall(fn, ...)
  if ok then return a, b, c, d, e, f, g, h, i end
end
local function bool(v) if isSecret(v) then return false end return v and true or false end
local function isNil(v) return type(v) == "nil" end
local function setText(fs, v) if not pcall(fs.SetText, fs, v) then fs:SetText("") end end
local function fmt(pattern, ...) local ok, out = pcall(string.format, pattern, ...); if ok then return out end end
local function nth(t, k) if type(t) ~= "table" then return nil end local ok, v = pcall(function() return t[k] end); if ok then return v end end
P.errs = {}
local function guard(fn, o)
  local ok, err = pcall(fn, o)
  if not ok then P.lastErr = tostring(err); P.errs[#P.errs + 1] = P.lastErr; if #P.errs > 20 then table.remove(P.errs, 1) end end
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
local COLDEF = {
  hostile = { 0.86, 0.2, 0.15 }, neutral = { 0.95, 0.8, 0.2 }, friendly = { 0.3, 0.8, 0.3 }, tapped = { 0.55, 0.55, 0.55 },
  tankGood = { 0.25, 0.6, 1 }, tankWarn = { 1, 0.6, 0.1 }, tankBad = { 1, 0.15, 0.1 },
  dpsBad = { 1, 0.15, 0.1 }, dpsWarn = { 1, 0.6, 0.1 },
  execute = { 1, 0.45, 0.85 },
  castNon = { 0.55, 0.55, 0.6 }, castReady = { 0.35, 0.95, 0.4 }, castFail = { 0.9, 0.15, 0.1 },
  -- nil defaults below = the theme's colour
  castInt = false, castChan = false, glow = false, arrows = false, mouse = false,
}
local DEF = {
  on = false, look = "cc",
  w = 130, h = 12, scale = 1, tex = "cc2", round = 2, border = "theme", bgAlpha = 0.85,
  font = "", fontSize = 10, outline = "OUTLINE",
  nameShow = true, nameAt = "above", nameFit = false, nameAlign = "center", nameColor = "white", nameSize = 0,
  levelAt = "name", classIcon = true, eliteStyle = "wrap", eliteSize = 1, eliteFrame = true, questStyle = "shield", questAt = "right", questSize = 16, questCrest = true,
  theme = "standard", frames = false, frameDesign = "auto", frameSide = "left", frameLevel = true, framePlayers = false, frameClass = true, frameFriendly = false, frameSize = 1,
  hpText = "percent", hpAt = "right", hpSize = -1,
  classPlayers = true, tapped = true, threat = true, role = "auto", thrGlow = true, thrText = false, thrPct = false, thrGroup = false, thrGlowAlpha = 0.9, thrGlowSize = 1, thrTextSize = 1, thrTextGlow = 0.5, thrFx = "pulse",
  execute = true, execPct = 20, execLine = true,
  castShow = true, castH = 9, castIcon = true, castName = true, castTime = true, castSpark = true, castReady = true, castFailShow = true,
  tScale = 1.15, tGlow = true, tInd = "off", tIndSize = 1, tIndAnim = true, tBorder = true, fade = true, fadeAlpha = 0.6, mouseHL = true,
  auraMode = "move", auraAt = "above", auraScale = 1, auraX = 0, auraY = 2, auraSize = 20, auraMax = 6, auraTimer = true, auraNumbers = "cc", auraNumAt = "center", auraNumSize = 10,
  raidAt = "left", raidSize = 18,
  quest = true, combo = true, friendNameOnly = true, clickMatch = true, corpseLoot = true, corpseSize = 1,
  col = {}, npc = {},
}
local function deep(dst, src)
  for k, v in pairs(src) do
    if type(v) == "table" then
      if type(dst[k]) ~= "table" then dst[k] = {} end
      deep(dst[k], v)
    elseif dst[k] == nil then dst[k] = v end
  end
  return dst
end
local function C()
  local g = G()
  local old = type(g.plates) == "table" and g.plates or {}
  if old.auraMove == false and old.auraMode == nil then old.auraMode = "off" end
  if old.eliteStyle == nil and old.eliteAt == "name" then old.eliteStyle = "atlas" end
  old.eliteAt = nil
  old.auraMove = nil
  -- r30: plate themes. "standard" = plain plates; "artistic" = Good Unit Frames' art: creature frames on mobs, class
  -- frames on players. The elite dragons belong to every theme (own settings in Extras). Old saves: frames on -> artistic.
  if old.theme == nil then old.theme = old.frames and "artistic" or "standard" end
  if old.tInd == nil and old.tArrows ~= nil then old.tInd = old.tArrows and "standard" or "off" end   -- r31
  old.tArrows = nil
  g.plates = deep(old, DEF)
  g.plates.frames = (g.plates.theme == "artistic")
  return g.plates
end
P.Config = C

-- colour from the settings (own pick > default > theme)
local function col(key)
  local c = C().col[key]
  if type(c) == "table" and c[1] then return c[1], c[2], c[3] end
  local d = COLDEF[key]
  if d then return d[1], d[2], d[3] end
  local th = UI:Theme()
  if key == "castChan" then return th.live[1], th.live[2], th.live[3] end
  return th.gold[1], th.gold[2], th.gold[3]
end
P.col = col

-- Looks: one click sets the visual settings (Platynator-style designs)
P.LOOKS = {
  { value = "cc", text = "Command Center", tip = "Theme edge, satin bar, name above, percent on the right.",
    set = { w = 130, h = 12, tex = "cc2", round = 2, border = "theme", nameAt = "above", nameAlign = "center", hpText = "percent", hpAt = "right",
      castH = 9, tGlow = true, tInd = "off", tBorder = true, levelAt = "name", fontSize = 10 } },
  { value = "slim", text = "Slim", tip = "A thin rounded line under the name, no border - quiet in big pulls.",
    set = { w = 116, h = 6, tex = "flat", round = 5, border = "none", nameAt = "above", nameAlign = "left", hpText = "none",
      castH = 5, tGlow = true, tInd = "off", tBorder = false, levelAt = "off", fontSize = 9 } },
  { value = "block", text = "Classic block", tip = "Tall square bar with the name inside, like the old plates.",
    set = { w = 140, h = 17, tex = "cc3", round = 0, border = "black", nameAt = "inside", nameAlign = "left", hpText = "percent", hpAt = "right",
      castH = 10, tGlow = false, tInd = "standard", tBorder = true, levelAt = "left", fontSize = 10 } },
  { value = "glass", text = "Glass pill", tip = "Round glassy bar with a soft glow on your target.",
    set = { w = 128, h = 14, tex = "cc6", round = 5, border = "theme", nameAt = "above", nameAlign = "center", hpText = "percent", hpAt = "center",
      castH = 10, tGlow = true, tInd = "standard", tBorder = true, levelAt = "name", fontSize = 10 } },
  { value = "clean", text = "Clean (Kui style)", tip = "Flat bar, thin black edge, name on the left, small and sharp.",
    set = { w = 132, h = 10, tex = "cc5", round = 1, border = "black", nameAt = "above", nameAlign = "left", hpText = "percent", hpAt = "right",
      castH = 6, tGlow = false, tInd = "off", tBorder = true, levelAt = "off", fontSize = 10 } },
  { value = "bold", text = "Bold (Threat Plates style)", tip = "Big tube bar, name inside, arrows on your target.",
    set = { w = 156, h = 20, tex = "cc4", round = 3, border = "theme", nameAt = "inside", nameAlign = "center", hpText = "percent", hpAt = "right",
      castH = 12, tGlow = true, tInd = "standard", tBorder = true, levelAt = "left", fontSize = 11 } },
}
function P.ApplyLook(key)
  for _, l in ipairs(P.LOOKS) do
    if l.value == key then
      local c = C()
      for k, v in pairs(l.set) do c[k] = v end
      c.look = key
    end
  end
  P.Refresh()
end

-- bar textures (the CC ones + the game's + LibSharedMedia)
P.TEXTURES = {
  { value = "cc1", text = "CC Gloss" }, { value = "cc2", text = "CC Satin" }, { value = "cc3", text = "CC Bevel" }, { value = "cc4", text = "CC Tube" },
  { value = "cc5", text = "CC Brushed" }, { value = "cc6", text = "CC Glass" }, { value = "cc7", text = "CC Neon" }, { value = "cc8", text = "CC Stripes" },
  { value = "cc9", text = "CC Hatch" }, { value = "cc10", text = "CC Dots" }, { value = "cc11", text = "CC Carbon" }, { value = "cc12", text = "CC Scales" },
  { value = "cc13", text = "CC Wood" }, { value = "cc14", text = "CC Marble" }, { value = "cc15", text = "CC Pixel" }, { value = "cc16", text = "CC Chrome" },
  { value = "cc17", text = "CC Velvet" }, { value = "cc18", text = "CC Diamond" }, { value = "cc19", text = "CC Ripple" }, { value = "cc20", text = "CC Crystal" },
  { value = "smooth", text = "Smooth", path = "Interface\\TargetingFrame\\UI-StatusBar" }, { value = "flat", text = "Flat", path = WHITE },
  { value = "raid", text = "Raid (soft)", path = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill" },
}
local function texPath(v)
  local n = type(v) == "string" and v:match("^cc(%d+)$")
  if n then return BARS .. "ccbar" .. n end
  for _, t in ipairs(P.TEXTURES) do if t.value == v and t.path then return t.path end end
  local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
  if LSM then local p = try(LSM.Fetch, LSM, "statusbar", v); if p then return p end end
  return "Interface\\TargetingFrame\\UI-StatusBar"
end
function P.TextureOptions()
  local out = {}
  for _, t in ipairs(P.TEXTURES) do out[#out + 1] = { value = t.value, text = t.text } end
  local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
  if LSM then for _, n in ipairs(try(LSM.List, LSM, "statusbar") or {}) do out[#out + 1] = { value = n, text = n } end end
  return out
end
local function fontPath()
  local c = C()
  if c.font ~= "" and UI.fonts[c.font] then return UI.fonts[c.font] end
  return UI.fonts[G().font or "Friz Quadrata"] or FRIZ
end
local function setFont(fs, size)
  local c = C()
  local fl = c.outline == "none" and "" or c.outline
  local path = fontPath()
  local ok, r = pcall(fs.SetFont, fs, path, max(6, size), fl)
  if not ok or r == false then pcall(fs.SetFont, fs, FRIZ, max(6, size), fl) end
  fs:SetShadowOffset(1, -1); fs:SetShadowColor(0, 0, 0, c.outline == "none" and 0.9 or 0.5)
end

---------------------------------------------------------------------------
-- Colours and words that don't depend on a plate
---------------------------------------------------------------------------
local function classColor(cls)
  if not cls or sec(cls) then return end
  local c = (CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[cls]) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls])
  if c then return c.r, c.g, c.b end
end
-- pick a or b by a yes/no the game may hide (hidden: the game's own colour helper decides)
local function pickColor(flag, a, b)
  if not sec(flag) then if flag then return a else return b end end
  if C_CurveUtil and C_CurveUtil.EvaluateColorFromBoolean and CreateColor then
    local c = try(C_CurveUtil.EvaluateColorFromBoolean, flag, CreateColor(a[1], a[2], a[3], 1), CreateColor(b[1], b[2], b[3], 1))
    if c then return c end
  end
  return b
end
-- paint a bar with a plain {r,g,b} or a colour object the game handed us
local function paintBar(bar, c)
  if type(c) ~= "table" then return end
  if c[1] then bar:SetStatusBarColor(c[1], c[2], c[3]) return end
  if c.GetRGB then if not pcall(function() bar:SetStatusBarColor(c:GetRGB()) end) then bar:SetStatusBarColor(1, 1, 1) end end
end
local function short(v)
  if sec(v) then
    if AbbreviateNumbers then local s = try(AbbreviateNumbers, v); if not isNil(s) then return s end end
    return v
  end
  v = tonumber(v) or 0
  if v >= 1e6 then return string.format("%.1fm", v / 1e6) end
  if v >= 1e4 then return string.format("%.1fk", v / 1e3) end
  return tostring(floor(v + 0.5))
end
local function pctText(p)
  if isNil(p) then return nil end
  if not sec(p) then return tostring(floor(p + 0.5)) end
  local s = fmt("%.0f", p)
  if isNil(s) then s = fmt("%d", p) end
  return s
end
local function hpString(mode, cur, mx, pct)
  if mode == "none" then return "" end
  if mode == "percent" or mode == "both" then
    local p = pct
    if isNil(p) and not sec(cur, mx) and mx and mx > 0 then p = cur / mx * 100 end
    local ps = pctText(p)
    if isNil(ps) then return short(cur) end
    if mode == "percent" then return fmt("%s%%", ps) or "" end
    return fmt("%s - %s%%", short(cur), ps) or short(cur)
  end
  if mode == "cur" then return short(cur) end
  if mode == "deficit" then
    if sec(cur, mx) then return "" end
    local d = (mx or 0) - (cur or 0)
    return d > 0 and ("-" .. short(d)) or ""
  end
  return fmt("%s / %s", short(cur), short(mx)) or short(cur)
end
local function levelString(lvl, cl, noPlus)
  if sec(lvl) or lvl == nil then return "" end
  local c = (GetCreatureDifficultyColor and lvl > 0 and GetCreatureDifficultyColor(lvl))
    or (GetQuestDifficultyColor and lvl > 0 and GetQuestDifficultyColor(lvl)) or { r = 1, g = 0.82, b = 0 }
  local s = lvl <= 0 and "??" or tostring(lvl)
  if cl == "worldboss" then s = "??" elseif (cl == "elite" or cl == "rareelite") and not noPlus then s = s .. "+" end
  return string.format("|cff%02x%02x%02x%s|r", (c.r or 1) * 255, (c.g or 1) * 255, (c.b or 1) * 255, s)
end
P.levelString = levelString

-- your interrupt: ready (true), on cooldown (false) or unknown (nil)
P.KICKS = { 1766, 1767, 1768, 1769, 38768, 6552, 6554, 72, 1671, 1672, 29704, 2139, 57994, 8042, 8044, 8045, 8046, 10412, 10413, 10414,
  15487, 19647, 96231, 47528, 106839, 16979, 147362, 34490, 187707 }
function P.KickSpell()
  local now = GetTime()
  if P.kickAt and now - P.kickAt < 10 then return P.kick end
  P.kickAt, P.kick = now, nil
  for _, id in ipairs(P.KICKS) do
    local known = (IsPlayerSpell and try(IsPlayerSpell, id)) or (IsSpellKnown and try(IsSpellKnown, id))
    if bool(known) then P.kick = id end
  end
  return P.kick
end
function P.KickReady()
  local id = P.KickSpell()
  if not id then return nil end
  local st, dur
  if C_Spell and C_Spell.GetSpellCooldown then
    local info = try(C_Spell.GetSpellCooldown, id)
    if type(info) == "table" then st, dur = info.startTime, info.duration end
  elseif GetSpellCooldown then st, dur = try(GetSpellCooldown, id) end
  if sec(st, dur) or isNil(st) then return nil end
  return st == 0 or (dur or 0) <= 1.6
end

-- are you the tank? (auto: group role, bear form, defensive stance, righteous fury)
function P.IsTank()
  local r = C().role
  if r == "tank" then return true elseif r == "dps" then return false end
  local role = UnitGroupRolesAssigned and try(UnitGroupRolesAssigned, "player")
  if role == "TANK" then return true end
  local _, cls = UnitClass("player")
  local form = GetShapeshiftFormID and try(GetShapeshiftFormID)
  if cls == "DRUID" and (form == 5 or form == 8) then return true end
  if cls == "WARRIOR" and GetShapeshiftForm and try(GetShapeshiftForm) == 2 then return true end
  if (cls == "PALADIN" or cls == "DEATHKNIGHT") and not combat() and C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellName then
    if try(C_UnitAuras.GetPlayerAuraBySpellName, "Righteous Fury") or try(C_UnitAuras.GetPlayerAuraBySpellName, "Frost Presence") then return true end
  end
  return false
end

---------------------------------------------------------------------------
-- Where the facts come from: the game (REAL) or the preview (a fake table)
---------------------------------------------------------------------------
local REAL = {}
function REAL.health(u) return UnitHealth(u), UnitHealthMax(u) end
function REAL.pct(u) if UnitHealthPercent then return try(UnitHealthPercent, u, false, CurveConstants and CurveConstants.ScaleTo100) end end
function REAL.name(u) return try(UnitName, u) end
function REAL.level(u)
  local cl = try(UnitClassification, u)
  if sec(cl) then cl = nil end
  return try(UnitLevel, u), cl
end
function REAL.isPlayer(u) return bool(try(UnitIsPlayer, u)) end
function REAL.ctype(u) local t = UnitCreatureType and try(UnitCreatureType, u); if sec(t) then return nil end return t end
function REAL.class(u) local _, c = try(UnitClass, u); if sec(c) then return nil end return c end
function REAL.reaction(u) return try(UnitReaction, u, "player") end
function REAL.canAttack(u) return try(UnitCanAttack, "player", u) end
function REAL.tapped(u) return bool(UnitIsTapDenied and try(UnitIsTapDenied, u)) end
function REAL.threat(u) return try(UnitThreatSituation, "player", u) end
-- r31: the game's own threat %: 100 = you pull it (scaledPercent). Possibly hidden (secret) - only shown via widgets.
function REAL.threatPct(u) if not UnitDetailedThreatSituation then return nil end local _, _, p = try(UnitDetailedThreatSituation, "player", u); return p end
-- r35 corpses: dead + can I loot it (CanLootUnit(guid) -> hasLoot, canLoot)
function REAL.lootable(u)
  local g = UnitGUID and try(UnitGUID, u)
  if g == nil or sec(g) or not CanLootUnit then return nil end
  local has, can = try(CanLootUnit, g)
  if sec(has) or sec(can) then return nil end
  return (has and can ~= false) and true or false
end
function REAL.grouped() return (IsInGroup and IsInGroup()) and true or false end
function REAL.aggro(u) return try(UnitIsUnit, u .. "target", "player") end
function REAL.isTarget(u) return bool(try(UnitIsUnit, u, "target")) end
function REAL.isMouse(u) return bool(try(UnitIsUnit, u, "mouseover")) end
function REAL.anyTarget() return UnitExists("target") and true or false end
function REAL.raid(u) return GetRaidTargetIndex and try(GetRaidTargetIndex, u) end
function REAL.combat() return combat() end
function REAL.dead(u) return bool(try(UnitIsDeadOrGhost, u)) end
function REAL.combo(u)
  if not REAL.isTarget(u) then return nil end
  local _, cls = UnitClass("player")
  if cls ~= "ROGUE" and cls ~= "DRUID" then return nil end
  local n = GetComboPoints and try(GetComboPoints, "player", "target")
  local CP = Enum and Enum.PowerType and Enum.PowerType.ComboPoints
  if (isNil(n) or n == 0) and CP then n = try(UnitPower, "player", CP) end
  if sec(n) or isNil(n) then return nil end
  local mx = 5
  if CP then local m = try(UnitPowerMax, "player", CP); if m and not sec(m) and m > 0 then mx = min(7, m) end end
  if cls == "DRUID" and n == 0 then return nil end
  return n, mx
end
-- quest mob? (read out of combat only, kept for the fight)
function REAL.quest(u, o)
  if combat() then return o and o.questWas end
  local q = false
  if C_QuestLog and C_QuestLog.UnitIsRelatedToActiveQuest then
    q = bool(try(C_QuestLog.UnitIsRelatedToActiveQuest, u))
  end
  if not q and C_TooltipInfo and C_TooltipInfo.GetUnit then
    local data = try(C_TooltipInfo.GetUnit, u)
    local lines = type(data) == "table" and data.lines
    local E = Enum and Enum.TooltipDataLineType
    if type(lines) == "table" and E and not sec(lines) then
      for _, l in ipairs(lines) do
        if type(l) == "table" and (l.type == E.QuestObjective or l.type == E.QuestTitle) then q = true; break end
      end
    end
  end
  if o then o.questWas = q end
  return q
end
function REAL.cast(u)
  local name, text, tex, st, et, _, _, notInt, spellID = try(UnitCastingInfo, u)
  if not isNil(name) then return name, text, tex, st, et, notInt, false end
  local _
  name, text, tex, st, et, _, notInt, spellID = try(UnitChannelInfo, u)
  if not isNil(name) then return name, text, tex, st, et, notInt, true end
end
function REAL.castDuration(u, channel)
  return try(channel and UnitChannelDuration or UnitCastingDuration, u)
end
local function src(o) return o.fake or REAL end

---------------------------------------------------------------------------
-- Building a plate (used for the game's plates and for the preview)
---------------------------------------------------------------------------
local RC, RCG = 16 / 64, 30 / 64
local RADII = { [0] = 0, 4, 7, 10, 13, 16 }
local function slices(rc)
  return { TL = { 0, rc, 0, rc }, T = { rc, 1 - rc, 0, rc }, TR = { 1 - rc, 1, 0, rc },
    L = { 0, rc, rc, 1 - rc }, M = { rc, 1 - rc, rc, 1 - rc }, R = { 1 - rc, 1, rc, 1 - rc },
    BL = { 0, rc, 1 - rc, 1 }, B = { rc, 1 - rc, 1 - rc, 1 }, BR = { 1 - rc, 1, 1 - rc, 1 } }
end
local SL, SLG = slices(RC), slices(RCG)
local function newBox(f, layer, sub, glow)
  local set = { f = f, parts = {}, sl = glow and SLG or SL }
  for k, tc in pairs(set.sl) do
    local t = f:CreateTexture(nil, layer, nil, sub)
    t:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
    set[k] = t; set.parts[#set.parts + 1] = t
  end
  return set
end
local function boxLayout(set, anchor, file, cs, out)
  out = out or 0
  for _, t in ipairs(set.parts) do t:SetTexture(file); t:ClearAllPoints() end
  set.TL:SetSize(cs, cs); set.TL:SetPoint("TOPLEFT", anchor, "TOPLEFT", -out, out)
  set.TR:SetSize(cs, cs); set.TR:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", out, out)
  set.BL:SetSize(cs, cs); set.BL:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", -out, -out)
  set.BR:SetSize(cs, cs); set.BR:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", out, -out)
  set.T:SetPoint("TOPLEFT", set.TL, "TOPRIGHT"); set.T:SetPoint("BOTTOMRIGHT", set.TR, "BOTTOMLEFT")
  set.B:SetPoint("TOPLEFT", set.BL, "TOPRIGHT"); set.B:SetPoint("BOTTOMRIGHT", set.BR, "BOTTOMLEFT")
  set.L:SetPoint("TOPLEFT", set.TL, "BOTTOMLEFT"); set.L:SetPoint("BOTTOMRIGHT", set.BL, "TOPRIGHT")
  set.R:SetPoint("TOPLEFT", set.TR, "BOTTOMLEFT"); set.R:SetPoint("BOTTOMRIGHT", set.BR, "TOPRIGHT")
  set.M:SetPoint("TOPLEFT", set.TL, "BOTTOMRIGHT"); set.M:SetPoint("BOTTOMRIGHT", set.BR, "TOPLEFT")
end
local function boxColor(set, r, g, b, a) for _, t in ipairs(set.parts) do t:SetVertexColor(r, g, b, a or 1) end end
local function boxShown(set, on) for _, t in ipairs(set.parts) do t:SetShown(on and true or false) end end
local function corner(w, h) return max(1, min(8, floor(min(w, h) / 2))) end

-- rounded bar ends: two masks pinned to the bar's ends (Media\Plates\capL<k> / capR<k>)
local function roundBar(bar, k, h, extra)
  bar.ccMasks = bar.ccMasks or {}
  local tex = bar:GetStatusBarTexture()
  local list = { tex }
  for _, t in ipairs(extra or {}) do list[#list + 1] = t end
  local m = bar.ccMasks
  if (k or 0) <= 0 or not bar.CreateMaskTexture then
    if m.L then for _, t in ipairs(list) do pcall(t.RemoveMaskTexture, t, m.L); pcall(t.RemoveMaskTexture, t, m.R) end end
    m.on = false
    return
  end
  if not m.L then
    m.L = bar:CreateMaskTexture(); m.R = bar:CreateMaskTexture()
  end
  pcall(m.L.SetTexture, m.L, MEDIA .. "capL" .. k, "CLAMPTOWHITE", "CLAMPTOWHITE")
  pcall(m.R.SetTexture, m.R, MEDIA .. "capR" .. k, "CLAMPTOWHITE", "CLAMPTOWHITE")
  m.L:ClearAllPoints(); m.L:SetPoint("TOPLEFT", bar, "TOPLEFT"); m.L:SetSize(h, h)
  m.R:ClearAllPoints(); m.R:SetPoint("TOPRIGHT", bar, "TOPRIGHT"); m.R:SetSize(h, h)
  if not m.on then
    for _, t in ipairs(list) do pcall(t.AddMaskTexture, t, m.L); pcall(t.AddMaskTexture, t, m.R) end
    m.on = true
  end
end

function P.Build(parent)
  local o = CreateFrame("Frame", nil, parent)
  o:SetSize(130, 12)
  o:EnableMouse(false)
  if o.SetIgnoreParentScale then o:SetIgnoreParentScale(false) end
  o.glow = newBox(o, "BACKGROUND", -8, true)
  o.thr = newBox(o, "BACKGROUND", -7, true); boxShown(o.thr, false)        -- r31 threat glow
  o.edge = newBox(o, "BACKGROUND", -7)
  o.bg = newBox(o, "BACKGROUND", -6)
  o.hp = CreateFrame("StatusBar", nil, o)
  o.hp:SetStatusBarTexture(WHITE); o.hp:SetMinMaxValues(0, 1); o.hp:SetValue(1)
  o.hp.bg = o.hp:CreateTexture(nil, "BACKGROUND"); o.hp.bg:SetAllPoints(); o.hp.bg:SetTexture(WHITE)
  o.hp.hl = o.hp:CreateTexture(nil, "OVERLAY"); o.hp.hl:SetAllPoints(); o.hp.hl:SetTexture(WHITE); o.hp.hl:SetBlendMode("ADD"); o.hp.hl:Hide()
  o.exec = o.hp:CreateTexture(nil, "OVERLAY", nil, 2); o.exec:SetTexture(WHITE); o.exec:SetWidth(1)
  -- text sits in its own frame above the bar
  o.over = CreateFrame("Frame", nil, o)
  o.over:SetAllPoints(o)
  o.over:SetFrameLevel(o.hp:GetFrameLevel() + 4)
  o.name = o.over:CreateFontString(nil, "OVERLAY"); o.name:SetWordWrap(false)
  o.level = o.over:CreateFontString(nil, "OVERLAY")
  o.hpText = o.over:CreateFontString(nil, "OVERLAY"); o.hpText:SetWordWrap(false)
  o.cls = o.over:CreateTexture(nil, "OVERLAY")
  -- elite dragon wrapped round the bar's left end (above the bar) + its tail along the bottom (under the bar)
  o.drg = o.over:CreateTexture(nil, "OVERLAY", nil, 1); o.drg:Hide()          -- the dragon (above the frame and the tail)
  o.drgM = o.over:CreateTexture(nil, "OVERLAY", nil, -1); o.drgM:Hide()       -- middle band: the ring's left side, squashed to the bar
  o.drgB = o.over:CreateTexture(nil, "OVERLAY", nil, -1); o.drgB:Hide()       -- bottom band: belly just under the bar
  -- elite frame in the dragon's metal: rails along the top / bottom edges + a cap on the right end
  -- elite frame: a shaded metal border round the whole plate (9-slice, no middle) + a gem setting on the right end
  o.ef = {}
  for _, k in ipairs({ "TL", "T", "TR", "L", "R", "BL", "B", "BR" }) do o.ef[k] = o.over:CreateTexture(nil, "OVERLAY", nil, -2); o.ef[k]:Hide() end
  o.efCap = o.over:CreateTexture(nil, "OVERLAY", nil, -1); o.efCap:Hide()
  o.tail = o.over:CreateTexture(nil, "OVERLAY", nil, 0); o.tail:Hide()       -- the dragon's own tail, over the frame's bottom edge
  -- "Dragon ring with the level": a ring badge at the bar's right end, the dragon round it, the level inside
  o.lring = o.over:CreateTexture(nil, "OVERLAY", nil, 2); o.lring:Hide()
  o.ringLvl = o.over:CreateFontString(nil, "OVERLAY"); o.ringLvl:Hide()
  -- creature-type frame wrapped round the plate (normal / rare mobs): plain ring rails + right cap, the ornament
  -- piece over the left end, the level bubble on the right end
  o.gwTop = o.over:CreateTexture(nil, "OVERLAY", nil, 1); o.gwTop:Hide()
  o.gwBot = o.over:CreateTexture(nil, "OVERLAY", nil, 1); o.gwBot:Hide()
  o.gwCap = o.over:CreateTexture(nil, "OVERLAY", nil, 1); o.gwCap:Hide()
  o.gwL = o.over:CreateTexture(nil, "OVERLAY", nil, 2); o.gwL:Hide()
  o.gwB = o.over:CreateTexture(nil, "OVERLAY", nil, 3); o.gwB:Hide()
  -- r25: the art moves with the plate at sub-pixel positions; with the game's pixel snapping every piece rounds on its
  -- own and they jitter against each other while the mob moves - so no snapping on any art piece
  local arts = { o.gwTop, o.gwBot, o.gwCap, o.gwL, o.gwB, o.drg, o.tail, o.efCap, o.lring, o.quest, o.drgM, o.drgB }
  for _, t in pairs(o.ef or {}) do arts[#arts + 1] = t end
  for _, t in ipairs(arts) do
    if t then
      if t.SetSnapToPixelGrid then pcall(t.SetSnapToPixelGrid, t, false) end
      if t.SetTexelSnappingBias then pcall(t.SetTexelSnappingBias, t, 0) end
    end
  end
  o.ufLvl = o.over:CreateFontString(nil, "OVERLAY"); o.ufLvl:Hide()
  o.quest = o.over:CreateTexture(nil, "OVERLAY", nil, 3); o.quest:SetTexture(MEDIA .. "quest2")
  if o.quest.SetSnapToPixelGrid then pcall(o.quest.SetSnapToPixelGrid, o.quest, false); pcall(o.quest.SetTexelSnappingBias, o.quest, 0) end
  o.raid = o.over:CreateTexture(nil, "OVERLAY"); o.raid:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
  o.arrowL = o:CreateTexture(nil, "OVERLAY"); o.arrowL:SetTexture(MEDIA .. "arrow"); o.arrowL:SetTexCoord(1, 0, 0, 1)
  o.arrowR = o:CreateTexture(nil, "OVERLAY"); o.arrowR:SetTexture(MEDIA .. "arrow")
  -- r31 threat words / %; r34: in a small frame (o.thrF) with a soft glow behind, so the frame can be animated
  o.thrF = CreateFrame("Frame", nil, o.over); o.thrF:SetSize(1, 1); o.thrF:SetFrameLevel(o.over:GetFrameLevel() + 5)
  o.thrTG = o.thrF:CreateTexture(nil, "BACKGROUND"); o.thrTG:SetTexture(MEDIA .. "tglow"); o.thrTG:SetBlendMode("ADD"); o.thrTG:SetPoint("CENTER"); o.thrTG:Hide()
  o.thrTxt = o.thrF:CreateFontString(nil, "OVERLAY"); o.thrTxt:SetPoint("CENTER"); o.thrTxt:Hide()
  for _, t in ipairs({ o.arrowL, o.arrowR }) do
    if t.SetSnapToPixelGrid then pcall(t.SetSnapToPixelGrid, t, false); pcall(t.SetTexelSnappingBias, t, 0) end
  end
  o.combo = {}
  for i = 1, 7 do
    local g = o.over:CreateTexture(nil, "OVERLAY", nil, 1); g:SetTexture(MEDIA .. "combo")
    local r = o.over:CreateTexture(nil, "OVERLAY", nil, 0); r:SetTexture(MEDIA .. "comboring")
    o.combo[i] = { fill = g, ring = r }
  end
  -- cast bar
  local cb = CreateFrame("StatusBar", nil, o)
  cb:SetStatusBarTexture(WHITE); cb:SetMinMaxValues(0, 1); cb:SetValue(0)
  cb.edge = newBox(cb, "BACKGROUND", -7)
  cb.bgBox = newBox(cb, "BACKGROUND", -6)
  cb.bg = cb:CreateTexture(nil, "BACKGROUND", nil, -5); cb.bg:SetAllPoints(); cb.bg:SetTexture(WHITE)
  cb.icon = cb:CreateTexture(nil, "ARTWORK"); cb.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  cb.iconEdge = cb:CreateTexture(nil, "BACKGROUND", nil, -4); cb.iconEdge:SetTexture(WHITE)
  cb.top = CreateFrame("Frame", nil, cb); cb.top:SetAllPoints(cb); cb.top:SetFrameLevel(cb:GetFrameLevel() + 3)
  cb.text = cb.top:CreateFontString(nil, "OVERLAY"); cb.text:SetWordWrap(false); cb.text:SetJustifyH("LEFT")
  cb.time = cb.top:CreateFontString(nil, "OVERLAY"); cb.time:SetJustifyH("RIGHT")
  cb.spark = cb.top:CreateTexture(nil, "OVERLAY"); cb.spark:SetTexture(MEDIA .. "spark"); cb.spark:SetBlendMode("ADD")
  cb.shield = cb.top:CreateTexture(nil, "OVERLAY"); cb.shield:SetTexture(MEDIA .. "shield")
  cb:Hide()
  o.cast = cb
  return o
end

---------------------------------------------------------------------------
-- Layout: sizes and spots from the settings
---------------------------------------------------------------------------
local function borderRGB(c)
  if c.border == "black" then return 0, 0, 0 end
  local th = UI:Theme()
  return th.edge[1], th.edge[2], th.edge[3]
end
-- elite / rare / boss badge. Elite = the game's gold elite dragon, rare elite = the silver one
-- (the atlases Blizzard's own nameplates use); our own art if Forever lacks them.
P.DRAGON = { elite = "nameplates-icon-elite-gold", rareelite = "nameplates-icon-elite-silver", worldboss = "nameplates-icon-elite-gold" }
P.atlasOK = {}
function P.HasAtlas(name)
  if P.atlasOK[name] == nil then
    local info = C_Texture and C_Texture.GetAtlasInfo and try(C_Texture.GetAtlasInfo, name)
    P.atlasOK[name] = type(info) == "table"
  end
  return P.atlasOK[name]
end
function P.BadgeKind(cl)
  if type(cl) ~= "string" or sec(cl) then return nil end
  if cl == "elite" or cl == "rareelite" or cl == "worldboss" or cl == "rare" then return cl end
end
-- is it drawn as a dragon wrapped over the bar's start? size of the badge
function P.BadgeSize(kind, h, wrap)
  if not wrap then return max(12, min(20, h + 6)) end
  if (kind == "elite" or kind == "rareelite") then return max(18, min(40, floor(h * 1.9 + 6))) end
  return max(14, min(26, h + 8))
end
-- The elite dragon (art from the user, 2026-11-25), mirrored so its ring curls round the bar's LEFT end.
-- Cut in three bands so it hugs the plate: top (art y 0-38: head + back) sits right on the bar's top
-- edge, bottom (y 136-end: belly) right under its bottom edge, and only the middle (the ring's left
-- side, y 38-136) is squashed to the bar's height. The tail is cut off at x "cut" and drawn as one
-- piece (dtail: art x 100-178, y 110-160) stretched along the bottom to about half the bar.
-- Files: drg2_<winged|plain>_<gold|silver> (256x256, art top-left), dtail_<col> (128x64, art 78x50).
-- Art pixels: winged 195x159, plain 160x160 (same body 35 px further left); barX = the bar's left
-- end (inside the ring), left = where the wings end.
-- r12 (drg4_*, make_tex5.py): ONE seamless piece per dragon. Baked into the art: the ring's left side
-- + wings squeezed smoothly to ~55% (a tight bend round the bar's end), and the rows between the
-- claws and the belly squeezed smoothly so the bar is 47.6 art rows high (no band seams). The claws
-- (hands) and jaw rest on the bar's top edge (art row "rest"), the belly sits on its bottom edge
-- ("belly"). The tail (dtail2_*) is cut from the same warped art below the bar's middle and
-- cross-faded into the body over 10 px; it's baked long (natural at the join and the tip, stretched
-- between) for a 130x12 plate and stretched a little more or less to end at half the bar.
P.DRG = {
  -- r21 (drg5_* / dtail3_*, make_tex8.py): wings squeezed harder (0.40), body right of the bar's end x1.25, tail
  -- baked to reach 72% of a 130 px bar (512 px wide file)
  winged = { w = 188, h = 112, barX = 40.6, rest = 39, belly = 86.6, tailX = 58.6, tailY = 62, left = 0 },
  plain = { w = 174, h = 113, barX = 26.6, rest = 39, belly = 86.6, tailX = 44.6, tailY = 62, left = 0 },
  tailW = 359, tailH = 50, tailFile = 512, tailEnd = 0.72,
}
function P.DragonGeom(kind, w, h)
  local D, A = P.DRG, P.DRG[kind]
  local sx = min(0.4, max(0.15, 0.021 * max(h, 8))) * (C().eliteSize or 1)   -- art px -> screen px (across)
  local sy = h / (A.belly - A.rest)                                          -- (down: the bar fills the gap exactly)
  local g = { sx = sx, sy = sy, A = A }
  g.x, g.y, g.w, g.h = -A.barX * sx, h / 2 + A.rest * sy, A.w * sx, A.h * sy
  g.lead = floor((A.barX - A.left) * sx) + 2             -- wings' reach left of the bar
  g.head = (A.w - A.barX) * sx                           -- head's reach right, along the top edge
  g.tailX = (A.tailX - A.barX) * sx
  g.tailY = h / 2 - (A.tailY - A.rest) * sy
  g.tailW = max(20 * sx, w * (D.tailEnd or 0.5) - g.tailX)   -- runs along the bottom to ~3/4 of the bar
  g.tailH = D.tailH * sy
  -- frame: rail thickness, cap scale (cap art: bar end between rows 21 and 43, inner edge at x 12)
  g.rail = max(3, floor(h * 0.3 + 0.5))
  g.cap = (h + g.rail) / 22
  g.trail = floor((48 - 12) * g.cap * 0.75)             -- how far the cap reaches right of the bar
  return g
end
-- the elite frame (eframe_<col>: 64x64, border 9 px, corners 24 px) round the plate's outline
P.EF_SL = { TL = { 0, 24, 0, 24 }, T = { 24, 40, 0, 24 }, TR = { 40, 64, 0, 24 }, L = { 0, 24, 24, 40 }, R = { 40, 64, 24, 40 },
  BL = { 0, 24, 40, 64 }, B = { 24, 40, 40, 64 }, BR = { 40, 64, 40, 64 } }
function P.Frame(o, colr, w, h, on)
  local ef = o.ef
  if not on then for _, t in pairs(ef) do t:Hide() end return 0 end
  local t = max(2, floor(h * 0.22 + 0.5))                 -- border thickness
  local cs = 24 * t / 9                                   -- corner size
  local x0, x1, yt, yb = -t + 1, w + t - 1, h / 2 + t - 1, -h / 2 - t + 1
  local W, H = x1 - x0, yt - yb
  local cw, ch = min(cs, W / 2), min(cs, H / 2)
  local spots = {
    TL = { x0, yt, cw, ch }, TR = { x1 - cw, yt, cw, ch }, BL = { x0, yb + ch, cw, ch }, BR = { x1 - cw, yb + ch, cw, ch },
    T = { x0 + cw, yt, W - 2 * cw, ch }, B = { x0 + cw, yb + ch, W - 2 * cw, ch },
    L = { x0, yt - ch, cw, H - 2 * ch }, R = { x1 - cw, yt - ch, cw, H - 2 * ch } }
  local file = MEDIA .. "eframe_" .. colr
  for k, tex in pairs(ef) do
    local sp, tc = spots[k], P.EF_SL[k]
    if sp[3] > 0.2 and sp[4] > 0.2 then
      tex:SetTexture(file); tex:SetTexCoord(tc[1] / 64, tc[2] / 64, tc[3] / 64, tc[4] / 64); tex:SetVertexColor(1, 1, 1)
      tex:SetSize(sp[3], sp[4]); tex:ClearAllPoints(); tex:SetPoint("TOPLEFT", o, "LEFT", sp[1], sp[2]); tex:Show()
    else tex:Hide() end
  end
  return t
end
-- elite looks (setting eliteStyle) and quest marker looks (questStyle)
P.ELITE_STYLES = {
  { value = "wrap", text = "Dragon round the bar" },
  { value = "wrapPlain", text = "Dragon round the bar, no wings" },
  { value = "mini", text = "Small dragon by the name" },
  { value = "atlas", text = "Blizzard's nameplate dragon" },
  { value = "wingstar", text = "Winged star" },
  { value = "star", text = "Star" },
  { value = "ring", text = "Dragon ring with the level (bar's end)" },
}
P.QUEST_STYLES = {
  { value = "shield", text = "Gold shield !" },
  { value = "classic", text = "Classic yellow !" },
  { value = "badge", text = "Round badge !" },
  { value = "turnin", text = "Classic yellow ?" },
}
P.QUEST_FILES = { shield = MEDIA .. "quest2", classic = "Interface\\GossipFrame\\AvailableQuestIcon",
  badge = MEDIA .. "quest", turnin = "Interface\\GossipFrame\\ActiveQuestIcon" }
function P.IsWrap() local st = C().eliteStyle; return st == "wrap" or st == "wrapPlain" end
-- the small badges go INTO the name text, right before the level (no measuring needed: nameplates
-- are restricted, so a separate icon can't be lined up with the name's start)
function P.BadgeInline(kind, size)
  local st = C().eliteStyle
  local silver = kind == "rare" or kind == "rareelite"
  local z = max(8, floor(size + 0.5))
  if st == "mini" then
    local art = (kind == "rare") and "plain" or "winged"
    local f = MEDIA .. "drgmini_" .. art .. "_" .. (silver and "silver" or "gold")
    if art == "winged" then return string.format("|T%s:%d:%d:0:0:128:128:0:128:0:104|t", f, z, floor(z * 1.23 + 0.5)) end
    return string.format("|T%s:%d:%d|t", f, z, z)
  end
  if kind == "worldboss" and st ~= "atlas" then return string.format("|T%s:%d:%d|t", MEDIA .. "skull", z, z) end
  if st == "star" then return string.format("|T%s:%d:%d|t", MEDIA .. (silver and "star_silver" or "star"), z, z) end
  if st == "atlas" and kind ~= "rare" then
    local a = P.DRAGON[kind]
    if a and P.HasAtlas(a) then return string.format("|A:%s:%d:%d|a", a, z, z) end
  end
  if st == "atlas" and kind == "rare" then return string.format("|T%s:%d:%d|t", MEDIA .. "star_silver", z, z) end
  -- winged star (also the atlas fallback): our white mask tinted gold / silver
  local r, g, b = 255, 204, 64
  if silver then r, g, b = 205, 225, 255 end
  return string.format("|T%s:%d:%d:0:0:64:64:0:64:0:64:%d:%d:%d|t", MEDIA .. "elite", z, z, r, g, b)
end
function P.SetBadge(t, kind)
  local st = C().eliteStyle
  local silver = kind == "rare" or kind == "rareelite"
  if t.SetDesaturated then t:SetDesaturated(false) end
  if st == "mini" then
    local art = (kind == "rare") and "plain" or "winged"
    t:SetTexture(MEDIA .. "drgmini_" .. art .. "_" .. (silver and "silver" or "gold"))
    if art == "winged" then t:SetTexCoord(0, 1, 0, 104 / 128) else t:SetTexCoord(0, 1, 0, 1) end
    t:SetVertexColor(1, 1, 1); return "mini"
  end
  if st == "star" or st == "wingstar" then
    t:SetTexCoord(0, 1, 0, 1)
    if kind == "worldboss" then t:SetTexture(MEDIA .. "skull"); t:SetVertexColor(1, 1, 1); return "own" end
    if st == "star" then t:SetTexture(MEDIA .. "star"); t:SetVertexColor(1, 1, 1)
      if silver and t.SetDesaturated then t:SetDesaturated(true); t:SetVertexColor(0.95, 0.97, 1) end
    else t:SetTexture(MEDIA .. "elite"); if silver then t:SetVertexColor(0.8, 0.88, 1) else t:SetVertexColor(1, 0.8, 0.25) end end
    return "own"
  end
  local atlas = P.DRAGON[kind]
  if kind == "worldboss" then atlas = nil end           -- bosses keep the skull
  if atlas and P.HasAtlas(atlas) and t.SetAtlas and pcall(t.SetAtlas, t, atlas, false) then
    t:SetVertexColor(1, 1, 1); return "atlas"
  end
  t:SetTexCoord(0, 1, 0, 1)
  if kind == "worldboss" then t:SetTexture(MEDIA .. "skull"); t:SetVertexColor(1, 1, 1)
  elseif kind == "rare" then t:SetTexture(MEDIA .. "star"); t:SetVertexColor(1, 1, 1)
  elseif kind == "rareelite" then t:SetTexture(MEDIA .. "elite"); t:SetVertexColor(0.8, 0.88, 1)
  else t:SetTexture(MEDIA .. "elite"); t:SetVertexColor(1, 0.8, 0.25) end
  return "own"
end

-- debuffs "under the name" with the name above the bar: the name moves up to make room
function P.NameLift(o)
  local c = C()
  if c.auraAt ~= "undername" or c.auraMode == "off" or o.nameOnly or not c.nameShow or c.nameAt ~= "above" then return 0 end
  local h
  if c.auraMode == "copy" then h = floor((c.auraSize or 20) * 0.75 * (c.auraScale or 1))
  else h = floor(15 * (c.auraScale or 1) + 0.5) end
  return h + 3 + max(0, c.auraY or 0)
end
-- creature-type frames (Frames tab): Good Unit Frames' round creature frames (art by Druid Whims), morphed to wrap a
-- nameplate (generator /home/claude/cc/gufw/warp.py). Reference bar height 48 units; per design / rank in Media/Plates/gw:
--   gw_<d>_<r>   256x128: the ornaments wrapped round the bar's left end (half-circle cap radius h/2); 0.6 texels per
--                unit, the bar's left-middle at texel (70, 64)
--   gwf_<d>_<r>  128x64: the plain ring round a stadium (height = 48 + 2 x band): [0,32) left cap, [32,96) straight
--                band (stretched), [96,128) right cap; 0.8746 texels per unit, band 12.59 units
--   gwb_<d>_<r>  64x64: the level bubble, undistorted
--   gwt_<d>_<r>  512x64 (r23): the top edge band - ring + the design's ornaments at half size, mirror-tiled, baked
--                472 units long (a 130x12 plate); d from -1.2 (row 64) to 30.8 (row 0); bottom edge = flipped
--   gwr_<d>_<r>  256x128 (r23): the smaller ornament collar for the other end, laid out like gw_ (drawn mirrored)
P.GW = { H = 48, ts = 0.6, ox = 70, oy = 64, tw = 256, th = 128, kf = 0.8746466, band = 12.586207, ringC = 4.8, lead = 34, railD = 30.8, railTop = 24, collar = 20 }
P.UF_DESIGNS = { "humanoid", "beast", "dragonkin", "undead", "elemental", "mechanical", "demon", "giant", "aberration", "critter", "unknown" }
P.UF_TYPES = {            -- the game's creature type (English) -> design
  Humanoid = "humanoid", Beast = "beast", Dragonkin = "dragonkin", Undead = "undead", Elemental = "elemental",
  Mechanical = "mechanical", Demon = "demon", Giant = "giant", Aberration = "aberration", Critter = "critter",
  ["Non-combat Pet"] = "critter", ["Wild Pet"] = "critter",
}
-- r29: players get their class's frame (Good Unit Frames' class / spec portraits, flipped + warped the same way;
-- one spec's art per class, picked to match GUF's class look): gw*_<class>_normal
P.UF_CLASSES = { warrior = true, paladin = true, hunter = true, rogue = true, priest = true, shaman = true, mage = true,
  warlock = true, druid = true, deathknight = true, demonhunter = true, monk = true, evoker = true }
function P.GWFile(kind, design, rank, sub) return MEDIA .. "gw\\" .. (sub or "") .. kind .. "_" .. design .. "_" .. rank end
-- r26 frame size: three baked sets (ring + ornaments 0.75x / 1x / 1.35x as thick round the same bar), the rest of the
-- slider is a small uniform scale (u) of the nearest set: returns t, folder, texels per unit, u
function P.GWSet(size)
  size = min(1.6, max(0.6, tonumber(size) or 1))
  if size < 0.866 then return 0.75, "s\\", 0.75, size / 0.75
  elseif size > 1.162 then return 1.35, "l\\", 0.6 / 1.35, size / 1.35 end
  return 1, nil, P.GW.ts, size
end
-- which frame a plate gets: "normal" / "rare", or nil (off, elites keep the dragon, players / friends by setting)
function P.UFKind(o, cl)
  local c = C()
  if not c.frames or o.nameOnly then return nil end
  if type(cl) == "string" and not sec(cl) and (cl == "elite" or cl == "rareelite" or cl == "worldboss") then return nil end
  local s, u = src(o), o.unit
  local pl = s.isPlayer(u)
  if pl and not c.framePlayers then return nil end
  if not c.frameFriendly then
    local re = s.reaction(u)
    if not sec(re) and type(re) == "number" and re >= 5 then return nil end
  end
  if pl then return "normal" end                     -- class frames have no rare version
  return (cl == "rare") and "rare" or "normal"
end
function P.UFDesign(o)
  local c = C()
  local s = src(o)
  if c.frameClass ~= false and s.isPlayer(o.unit) then
    local cls = s.class and s.class(o.unit)
    if type(cls) == "string" and not sec(cls) then
      cls = cls:lower()
      if P.UF_CLASSES[cls] then return cls end
    end
  end
  if c.frameDesign and c.frameDesign ~= "auto" then return c.frameDesign end
  local t = src(o).ctype and src(o).ctype(o.unit)
  return (type(t) == "string" and P.UF_TYPES[t]) or "unknown"
end
function P.FitOn()
  local c = C()
  return c.nameFit and c.nameShow and c.nameAt == "inside" and true or false
end
-- width of the name's text, measured on our own hidden-from-view string OFF the nameplate
-- (nameplates are restricted: nothing under them may be measured). nil when the name is hidden by the game.
function P.MeasureName(text, size)
  if text == nil or isSecret(text) or type(text) ~= "string" or text == "" then return nil end
  local m = P.mfs
  if not m then
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(1, 1); f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0); f:SetAlpha(0); f:Show()
    m = f:CreateFontString(nil, "OVERLAY"); m:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0); m:SetWordWrap(false)
    P.mfs = m
  end
  local c = C()
  setFont(m, size or (c.fontSize + (c.nameSize or 0)))
  m:SetText(text)
  local ok, tw = pcall(m.GetUnboundedStringWidth, m)
  if not ok or type(tw) ~= "number" or isSecret(tw) then ok, tw = pcall(m.GetStringWidth, m) end
  if not ok or type(tw) ~= "number" or isSecret(tw) or tw <= 0 then return nil end
  return ceil(tw)
end
-- "Fit the name to the bar" (name inside): the bar keeps its width, the name's text shrinks until it fits
-- curve for hidden (secret) names: text width -> text scale min(1, avail / width), worked out by the game
P.fitCurves = {}
function P.FitCurve(avail)
  avail = floor(avail + 0.5)
  local cv = P.fitCurves[avail]
  if cv ~= nil then return cv or nil end
  P.fitCurves[avail] = false
  if not (C_CurveUtil and C_CurveUtil.CreateCurve) then return nil end
  cv = try(C_CurveUtil.CreateCurve)
  if not cv then return nil end
  local E = Enum and Enum.LuaCurveType
  if E and E.Linear and cv.SetType then pcall(cv.SetType, cv, E.Linear) end
  local ok = pcall(cv.AddPoint, cv, 0, 1) and pcall(cv.AddPoint, cv, avail, 1)
  for i = 1, 16 do                                   -- 1/x sampled every 10 %, a hair small so it always fits
    local x = avail * (1 + i * 0.1)
    ok = ok and pcall(cv.AddPoint, cv, x, 0.97 * avail / x)
  end
  ok = ok and pcall(cv.AddPoint, cv, avail * 50, 0.97 / 2.6)
  if not ok then return nil end
  P.fitCurves[avail] = cv
  return cv
end
local function textScale(fs, v) if fs.SetTextScale then return pcall(fs.SetTextScale, fs, v) end return false end
-- "Fit the name to the bar" (name inside): the bar keeps its width, the name's text shrinks until it fits.
-- Readable names: we measure (off the plate) and pick a font size. Names the game hides (dungeons): the hidden width
-- goes through a curve and the result straight into the font string's text scale - no maths on our side.
function P.FitName(o)
  local c = C()
  local base = c.fontSize + (c.nameSize or 0) + (o.nameOnly and 2 or 0)
  local size, how = base, "off"
  textScale(o.name, 1)
  if P.FitOn() and not o.nameOnly and o.nameAvail and o.nameAvail > 0 and o.nameShown ~= nil then
    local tw = P.MeasureName(o.nameShown, base)
    if tw then
      how = "measured"
      if tw > o.nameAvail then
        size = max(6, floor(base * o.nameAvail / tw))
        for _ = 1, 4 do                                  -- text width isn't exactly linear in size
          local t2 = P.MeasureName(o.nameShown, size)
          if not t2 or t2 <= o.nameAvail or size <= 6 then break end
          size = size - 1
        end
      end
    else
      how = "hidden name: no curve"
      local m = P.mfs
      if not m then P.MeasureName("x", base); m = P.mfs end
      local cv = P.FitCurve(o.nameAvail)
      if m and cv then
        setFont(m, base)
        if pcall(m.SetText, m, o.nameShown) then
          local ok, sw = pcall(m.GetUnboundedStringWidth, m)
          if not ok or sw == nil then ok, sw = pcall(m.GetStringWidth, m) end
          if ok and sw ~= nil then
            local ok2, sc = pcall(cv.Evaluate, cv, sw)
            if ok2 and sc ~= nil then
              setFont(o.name, base)
              how = textScale(o.name, sc) and "hidden name: curve -> text scale" or "hidden name: text scale refused"
            end
          end
        end
      end
    end
  end
  o.nameFS, o.fitHow = size, how
  setFont(o.name, size)
end
function P.Layout(o)
  local c = C()
  local w, h = c.w, c.h
  local k = c.round or 0
  local nameOnly = o.nameOnly
  -- r25: with a creature frame the bar gets fully rounded ends and no outer edge line - the frame is its edge
  local ufEarly
  do local _, cl0 = src(o).level(o.unit); ufEarly = P.UFKind(o, cl0) end
  if ufEarly then k = 5 end
  o.w = w
  o:SetSize(w, h)
  o.baseScale = c.scale
  -- body: edge box 1 px outside, background box, glow 6 px outside
  local cs = corner(w, h)
  local bfile = MEDIA .. "box" .. k
  boxLayout(o.edge, o, bfile, cs + 1, 1)
  boxLayout(o.bg, o, bfile, cs, 0)
  boxLayout(o.glow, o, MEDIA .. "glow" .. k, 11, 6)
  local showEdge = c.border ~= "none" and not nameOnly and not ufEarly
  boxShown(o.edge, showEdge)
  boxShown(o.bg, not nameOnly)
  -- bar inside (clears the rounded corners a little)
  local pad = (k >= 3) and 1 or 1
  o.hp:ClearAllPoints()
  o.hp:SetPoint("TOPLEFT", pad, -pad); o.hp:SetPoint("BOTTOMRIGHT", -pad, pad)
  o.hp:SetStatusBarTexture(texPath(c.tex))
  o.hp:SetShown(not nameOnly)
  pcall(roundBar, o.hp, k, max(1, h - pad * 2), { o.hp.bg, o.hp.hl })
  -- execute marker
  o.exec:ClearAllPoints()
  o.exec:SetPoint("TOP", o.hp, "TOPLEFT", (w - pad * 2) * (c.execPct or 20) / 100, 0)
  o.exec:SetPoint("BOTTOM", o.hp, "BOTTOMLEFT", (w - pad * 2) * (c.execPct or 20) / 100, 0)
  -- fonts
  local fs = c.fontSize
  setFont(o.name, fs + (c.nameSize or 0) + (nameOnly and 2 or 0))
  setFont(o.level, fs)
  setFont(o.hpText, fs + (c.hpSize or 0))
  -- name
  o.name:ClearAllPoints()
  local at, al = c.nameAt, c.nameAlign
  if nameOnly then at, al = "center", "center" end
  o.name:SetJustifyH(al == "left" and "LEFT" or al == "right" and "RIGHT" or "CENTER")
  local lvlLeft = c.levelAt == "left" and not nameOnly
  -- the badge sits over the bar's start ("wrap"): things on the left move out of its way
  local _, clk = src(o).level(o.unit)
  local ufKind = P.UFKind(o, clk)
  local badge = c.classIcon and not nameOnly and P.BadgeKind(clk) or nil
  if ufKind then badge = nil end                         -- the frame (silver for rares) replaces the rare's badge
  local wrap = badge and P.IsWrap() or false
  local bs = floor(P.BadgeSize(badge, h, wrap) * (c.eliteSize or 1))
  local lead = wrap and (floor(bs * 0.4) + 1) or 0     -- how far it sticks out past the bar's left end
  local inLead = wrap and floor(bs * 0.6) or 0          -- how far it reaches into the bar
  -- elite / boss: gold winged dragon; rare elite: silver winged; rare: silver without wings
  local trail = 0                                       -- how far the elite frame's cap reaches right
  local crestX                                          -- quest crest on the elite frame: its right edge (x)
  local inTrail = 0                                     -- how far a portrait frame on the right reaches into the bar
  local dragon = wrap and (badge == "elite" or badge == "rareelite" or badge == "worldboss" or badge == "rare")
  local ringMode = badge and c.eliteStyle == "ring" and not nameOnly or false
  local colr = (badge == "rareelite" or badge == "rare") and "silver" or "gold"
  local art = (badge == "rare" or c.eliteStyle == "wrapPlain") and "plain" or "winged"
  local dg
  local ft = P.Frame(o, colr, w, h, (dragon or ringMode) and c.eliteFrame and not nameOnly)
  if dragon then
    dg = P.DragonGeom(art, w, h)
    lead, inLead = dg.lead, 4
    local A, D = dg.A, P.DRG
    o.drg:SetTexture(MEDIA .. "drg5_" .. art .. "_" .. colr); o.drg:SetTexCoord(0, A.w / 256, 0, A.h / 256); o.drg:SetVertexColor(1, 1, 1)
    o.drg:SetSize(dg.w, dg.h); o.drg:ClearAllPoints(); o.drg:SetPoint("TOPLEFT", o, "LEFT", dg.x, dg.y); o.drg:Show()
    o.drgM:Hide(); o.drgB:Hide()
    o.tail:SetTexture(MEDIA .. "dtail3_" .. colr); o.tail:SetTexCoord(0, D.tailW / (D.tailFile or 256), 0, D.tailH / 64); o.tail:SetVertexColor(1, 1, 1)
    o.tail:SetSize(dg.tailW, dg.tailH); o.tail:ClearAllPoints(); o.tail:SetPoint("TOPLEFT", o, "LEFT", dg.tailX, dg.tailY); o.tail:Show()
    if ft > 0 then
      -- spear end piece (ecap4_<col>, 128x128, drawn in 64-space): the crescent's tips span 44 units, the frame's
      -- right edge sits at x = 12 (inside the socket the bar slides into), the spear tip reaches x = 62.5
      local k = (h + 2 * ft) / 44
      o.efCap:SetTexture(MEDIA .. "ecap4_" .. colr); o.efCap:SetTexCoord(0, 1, 0, 1); o.efCap:SetVertexColor(1, 1, 1)
      o.efCap:SetSize(64 * k, 64 * k); o.efCap:ClearAllPoints(); o.efCap:SetPoint("TOPLEFT", o, "LEFT", w + ft - 1 - 12 * k, 32 * k); o.efCap:Show()
      trail = floor(ft + 51 * k + 1)
      crestX = w + ft - 1 - 7 * k - 1                     -- just left of the end piece's socket
    else o.efCap:Hide() end
  else o.drg:Hide(); o.drgM:Hide(); o.drgB:Hide(); o.tail:Hide(); o.efCap:Hide() end
  if ringMode then
    -- ring art (lring_<art>_<col>, 256x256): ring centre (79, 85), outer radius 43; the bar comes in from the left
    local R = max(8, 1.05 * h * (c.eliteSize or 1))
    local sc = R / 43
    local cx = w + R * 0.35
    o.lring:SetTexture(MEDIA .. "lring_" .. art .. "_" .. colr); o.lring:SetTexCoord(0, 1, 0, 1); o.lring:SetVertexColor(1, 1, 1)
    o.lring:SetSize(256 * sc, 256 * sc); o.lring:ClearAllPoints(); o.lring:SetPoint("TOPLEFT", o, "LEFT", cx - 79 * sc, 85 * sc); o.lring:Show()
    setFont(o.ringLvl, max(7, min(16, floor(R * 0.85))))
    o.ringLvl:ClearAllPoints(); o.ringLvl:SetPoint("CENTER", o, "LEFT", cx + 0.5, 0); o.ringLvl:Show()
    trail = floor(R * 0.35 + (art == "plain" and 80 or 115) * sc + 2)       -- the dragon's wings reach right
    if ft > 0 then crestX = cx - R * 1.1 end             -- just left of the ring
  else o.lring:Hide(); o.ringLvl:Hide() end
  -- creature-type frame themed all the way round (r23): the design's ornaments wrapped round one end, a band of the
  -- same ornaments along the top and bottom edges, a smaller ornament collar round the other end with the level bubble
  o.ufKind = ufKind
  o.frameLift = 0
  if ufKind then
    local G = P.GW
    local ov = max(1, h * 0.07)                              -- r25: the frame overlaps the bar's edge by this much
    local hv = h - 2 * ov                                    -- ... drawn as if the bar were this tall
    local fsz = min(1.6, max(0.6, tonumber(c.frameSize) or 1))
    local t, sub, ts, u = P.GWSet(fsz)                       -- r26: frame size
    local k = hv / G.H * u                                   -- screen px per unit
    local ri = hv / 2 * u                                    -- the ring's inner edge from the bar's middle line
    local right = c.frameSide == "right"
    local dsg = P.UFDesign(o)
    local railD = G.railD * t
    -- rails (gwt_: 512x64, the top edge band, outward = up; d from -1.2 to 30.8 units; bottom = flipped)
    local rt = P.GWFile("gwt", dsg, ufKind, sub)
    local rh = (railD + 1.2) * k
    o.gwTop:SetTexture(rt); o.gwTop:SetTexCoord(0, 1, 0, 1); o.gwTop:SetSize(max(1, w - h), rh)
    o.gwTop:ClearAllPoints(); o.gwTop:SetPoint("TOPLEFT", o, "LEFT", h / 2, ri + railD * k); o.gwTop:Show()
    o.gwBot:SetTexture(rt); o.gwBot:SetTexCoord(0, 1, 1, 0); o.gwBot:SetSize(max(1, w - h), rh)
    o.gwBot:ClearAllPoints(); o.gwBot:SetPoint("TOPLEFT", o, "LEFT", h / 2, -ri + 1.2 * k); o.gwBot:Show()
    -- main ornaments (gw_) and the collar (gwr_), both drawn like the left end; the one on the right is mirrored
    local Lw, Lh = G.tw / ts * k, G.th / ts * k
    local eL, eR = h / 2 - ri, w - h / 2 + ri                -- where the ring's inner edge crosses the middle line
    local function place(tx, file, onRight)
      tx:SetTexture(file); tx:SetSize(Lw, Lh); tx:ClearAllPoints()
      if onRight then tx:SetTexCoord(1, 0, 0, 1); tx:SetPoint("TOPLEFT", o, "LEFT", eR + G.ox / ts * k - Lw, G.oy / ts * k)
      else tx:SetTexCoord(0, 1, 0, 1); tx:SetPoint("TOPLEFT", o, "LEFT", eL - G.ox / ts * k, G.oy / ts * k) end
      tx:Show()
    end
    place(o.gwL, P.GWFile("gw", dsg, ufKind, sub), right)
    place(o.gwCap, P.GWFile("gwr", dsg, ufKind, sub), not right)
    -- level bubble on the collar's end
    local bd = 1.2 * h * max(0.85, fsz)
    local ringC = G.ringC * t
    local bx = right and (eL - ringC * k) or (eR + ringC * k)      -- on the ring's middle line
    o.gwB:SetTexture(P.GWFile("gwb", dsg, ufKind, sub)); o.gwB:SetSize(bd, bd); o.gwB:ClearAllPoints()
    o.gwB:SetPoint("CENTER", o, "LEFT", bx, 0); o.gwB:SetShown(c.frameLevel and true or false)
    setFont(o.ufLvl, max(6, min(14, floor(bd * 0.5))))
    o.ufLvl:ClearAllPoints(); o.ufLvl:SetPoint("CENTER", o, "LEFT", bx + 0.5, 0)
    o.ufLvl:SetShown(c.frameLevel and true or false)
    local orn = floor(G.lead * t * k)
    local col = floor(max(G.collar * t * k, c.frameLevel and (bd / 2 + ringC * k) or 0) + 2)
    local bubIn = (c.frameLevel and floor(bd / 2 - ringC * k) + 1 or 0)
    if right then lead = max(lead, col); trail = max(trail, orn); inLead = max(inLead, max(bubIn, floor(h * 0.35)))
    else lead = max(lead, orn); trail = max(trail, col); inLead = max(inLead, floor(h * 0.35)); inTrail = max(bubIn, floor(h * 0.35)) end
    o.frameLift = floor(G.railTop * t * k + 0.5)                 -- the edge band's ornaments rise this far above the bar
  else o.gwTop:Hide(); o.gwBot:Hide(); o.gwCap:Hide(); o.gwL:Hide(); o.gwB:Hide(); o.ufLvl:Hide() end
  o.dragon, o.trail, o.ringMode = dragon, trail, ringMode
  o.badge, o.badgeWrap, o.lead = badge, wrap, lead
  local function hAnchor(vp, rel, relp, y)
    if al == "left" then o.name:SetPoint(vp .. "LEFT", rel, relp .. "LEFT", 1 + ((dg and vp == "BOTTOM") and floor(dg.head) or 0), y)
    elseif al == "right" then o.name:SetPoint(vp .. "RIGHT", rel, relp .. "RIGHT", -1, y)
    else o.name:SetPoint(vp, rel, relp, 0, y) end
  end
  if at == "center" then o.name:SetPoint("CENTER", o, "CENTER", 0, 0); o.name:SetWidth(w + 80)
  elseif at == "inside" then
    o.name:SetPoint("LEFT", o.hp, "LEFT", al == "left" and (3 + inLead) or inLead, 0)
    o.name:SetPoint("RIGHT", o.hp, "RIGHT", ((c.hpText ~= "none" and c.hpAt == "right") and -34 or -3) - inTrail, 0)
    if al == "center" then o.name:ClearAllPoints(); o.name:SetPoint("CENTER", o.hp, "CENTER", 0, 0); o.name:SetWidth(w - 8) end
  elseif at == "below" then hAnchor("TOP", o, "BOTTOM", -2 - (o.frameLift or 0)); o.name:SetWidth(w)
  else hAnchor("BOTTOM", o, "TOP", 3 + P.NameLift(o) + (o.frameLift or 0)); o.name:SetWidth(al == "center" and w + 40 or w) end
  o.nameW = (at == "center") and (w + 80) or (at == "inside") and (w - 8) or (at == "above" and al == "center") and (w + 40) or w
  if at == "inside" then
    local rp = ((c.hpText ~= "none" and c.hpAt == "right") and 34 or 3) + inTrail
    local lp = (al == "left" and 3 or 0) + inLead
    o.nameAvail = (al == "center") and (w - 2 - 2 * max(lp, rp, 4)) or (w - 2 - lp - rp)
  else o.nameAvail = nil end
  P.FitName(o)
  o.name:SetShown(c.nameShow or nameOnly)
  -- level
  o.level:ClearAllPoints()
  if lvlLeft then o.level:SetPoint("RIGHT", o, "LEFT", -3 - lead, 0) end
  o.level:SetShown(lvlLeft)
  -- health text
  o.hpText:ClearAllPoints()
  local ha = c.hpAt
  if ha == "left" then o.hpText:SetPoint("LEFT", o.hp, "LEFT", 3 + inLead, 0); o.hpText:SetJustifyH("LEFT")
  elseif ha == "center" then o.hpText:SetPoint("CENTER", o.hp, "CENTER", 0, 0); o.hpText:SetJustifyH("CENTER")
  elseif ha == "outside" then o.hpText:SetPoint("LEFT", o, "RIGHT", 4 + trail, 0); o.hpText:SetJustifyH("LEFT")
  else o.hpText:SetPoint("RIGHT", o.hp, "RIGHT", -3 - inTrail, 0); o.hpText:SetJustifyH("RIGHT") end
  o.hpText:SetShown(c.hpText ~= "none" and not nameOnly)
  -- class badge (elite / rare / boss): left of the name, or left of the bar
  if c.eliteStyle == "mini" and badge ~= "rare" then o.cls:SetSize(floor(bs * 1.25), bs) else o.cls:SetSize(bs, bs) end
  o.cls:ClearAllPoints()
  -- (only used when neither the name nor the level is shown; otherwise the badge is inline in that text)
  o.cls:SetPoint("RIGHT", o, "LEFT", lvlLeft and -24 or -2, 0)
  -- quest marker: right of the plate
  local qs = c.questSize or 16
  o.quest:SetSize(qs, qs)
  o.quest:SetTexture(P.QUEST_FILES[c.questStyle] or P.QUEST_FILES.shield); o.quest:SetTexCoord(0, 1, 0, 1)
  if c.questStyle == "badge" then o.quest:SetVertexColor(1, 0.82, 0.15) else o.quest:SetVertexColor(1, 1, 1) end
  o.quest:ClearAllPoints()
  o.questCrest = (c.questCrest and ft > 0 and crestX) and true or false
  if o.questCrest then
    -- elite frame: a metal crest (qseal_<col>, 64x64: medallion centre (32, 26), clasp down to y 62) standing on
    -- the frame's top rail near the right end; its clasp grips the rail
    local S = max(18, (h + 2 * ft) * 1.3) * qs / 16
    o.quest:SetTexture(MEDIA .. "qseal_" .. colr); o.quest:SetVertexColor(1, 1, 1)
    o.quest:SetSize(S, S)
    o.quest:SetPoint("TOPLEFT", o, "LEFT", crestX - S, h / 2 + 62 * S / 64)
  elseif c.questAt == "left" then o.quest:SetPoint("RIGHT", o, "LEFT", -(lead + (lvlLeft and 24 or 4) + 2), 0)
  elseif c.questAt == "top" then o.quest:SetPoint("BOTTOM", o, "TOP", 0, ((c.nameShow and at == "above") and (fs + 6 + P.NameLift(o)) or 4) + (o.frameLift or 0))
  else o.quest:SetPoint("LEFT", o, "RIGHT", (ha == "outside" and 32 or 3) + trail, 0) end
  -- raid mark
  local rs = c.raidSize or 18
  o.raid:SetSize(rs, rs); o.raid:ClearAllPoints()
  if c.raidAt == "right" then o.raid:SetPoint("LEFT", o, "RIGHT", (ha == "outside" and 34 or 4) + trail, 0)
  elseif c.raidAt == "top" then o.raid:SetPoint("BOTTOM", o, "TOP", 0, ((c.nameShow and at == "above") and (fs + 6 + P.NameLift(o)) or 4) + (o.frameLift or 0))
  else o.raid:SetPoint("RIGHT", o, "LEFT", (lvlLeft and -24 or -4) - lead - ((c.classIcon and badge and not wrap and not c.nameShow and not lvlLeft) and (bs + 2) or 0), 0) end
  -- target indicators (r31: 5 styles, P.TIND)
  P.TindLayout(o, h, (lvlLeft and -22 or -4) - lead, (ha == "outside" and 30 or 4) + trail)
  -- threat glow + words / % (r31)
  local gsz = min(2.5, max(0.5, c.thrGlowSize or 1))
  boxLayout(o.thr, o, MEDIA .. "glow" .. k, 11 * gsz, 6 * gsz)
  if o.thrS then for i = 0, 3 do boxLayout(o.thrS[i], o, MEDIA .. "glow" .. k, 11 * gsz, 6 * gsz) end end
  o.thrFS = max(7, floor(c.fontSize * 0.85 * min(2.5, max(0.6, c.thrTextSize or 1)) + 0.5))
  setFont(o.thrTxt, o.thrFS)
  o.thrSpot = nil; P.ThreatSpot(o)
  -- combo points under the bar
  local gs = max(7, min(12, floor(h * 0.8)))
  o.comboGS = gs
  for i, p in ipairs(o.combo) do
    p.fill:SetSize(gs, gs); p.ring:SetSize(gs, gs)
    p.fill:ClearAllPoints(); p.ring:ClearAllPoints()
    p.ring:SetPoint("TOP", o, "BOTTOM", (i - 3) * (gs + 2), -2)
    p.fill:SetPoint("CENTER", p.ring, "CENTER")
  end
  -- cast bar under the plate (and under combo points)
  local cb = o.cast
  local ch = c.castH
  cb:ClearAllPoints()
  cb:SetPoint("TOPLEFT", o, "BOTTOMLEFT", 0, -3)
  cb:SetPoint("TOPRIGHT", o, "BOTTOMRIGHT", 0, -3)
  cb:SetHeight(ch)
  cb.ccW = w
  o.castY = -3
  cb:SetStatusBarTexture(texPath(c.tex))
  local ccs = corner(w, ch)
  boxLayout(cb.edge, cb, bfile, ccs + 1, 1)
  boxLayout(cb.bgBox, cb, bfile, ccs, 0)
  boxShown(cb.edge, c.border ~= "none")
  pcall(roundBar, cb, k, ch, { cb.bg })
  -- spell icon left of the plate, as tall as plate + cast bar
  cb.icon:ClearAllPoints()
  local isz = min(ch + h + 3, 28)
  cb.icon:SetSize(isz, isz)
  cb.icon:SetPoint("TOPRIGHT", o, "TOPLEFT", (lvlLeft and -24 or -3) - lead, 0)
  cb.icon:SetShown(c.castIcon)
  cb.iconEdge:ClearAllPoints(); cb.iconEdge:SetPoint("TOPLEFT", cb.icon, -1, 1); cb.iconEdge:SetPoint("BOTTOMRIGHT", cb.icon, 1, -1)
  cb.iconEdge:SetShown(c.castIcon and c.border ~= "none")
  setFont(cb.text, max(7, min(fs, ch + 1)))
  setFont(cb.time, max(7, min(fs - 1, ch + 1)))
  cb.text:ClearAllPoints(); cb.text:SetPoint("LEFT", cb, "LEFT", 3, 0); cb.text:SetPoint("RIGHT", cb, "RIGHT", c.castTime and -26 or -3, 0)
  cb.time:ClearAllPoints(); cb.time:SetPoint("RIGHT", cb, "RIGHT", -3, 0)
  cb.text:SetShown(c.castName); cb.time:SetShown(c.castTime)
  if ch < 7 then cb.text:ClearAllPoints(); cb.text:SetPoint("TOP", cb, "BOTTOM", 0, -1); cb.time:Hide() end
  cb.spark:SetSize(10, ch * 2.2)
  cb.shield:SetSize(ch + 6, ch + 6); cb.shield:ClearAllPoints(); cb.shield:SetPoint("CENTER", cb, "LEFT", 0, 0)
  if c.castIcon then cb.shield:SetPoint("CENTER", cb.icon, "CENTER") end
  P.Paint(o)
end

-- colours that come from the theme / settings (not from the unit)
function P.Paint(o)
  local c = C()
  local th = UI:Theme()
  local br, bg_, bb = borderRGB(c)
  o.ccEdgeRGB = { br, bg_, bb }
  boxColor(o.edge, br, bg_, bb, 1)
  local f = th.field or { 0.05, 0.05, 0.05 }
  boxColor(o.bg, f[1] * 0.6, f[2] * 0.6, f[3] * 0.6, c.bgAlpha)
  boxColor(o.cast.edge, br, bg_, bb, 1)
  boxColor(o.cast.bgBox, f[1] * 0.6, f[2] * 0.6, f[3] * 0.6, c.bgAlpha)
  o.cast.bg:SetVertexColor(0, 0, 0, 0)
  o.cast.iconEdge:SetVertexColor(br, bg_, bb, 1)
  o.hp.bg:SetVertexColor(0, 0, 0, 0)
  o.hp.hl:SetVertexColor(1, 1, 1, 0.18)
  o.exec:SetVertexColor(1, 1, 1, 0.75)
  local gr, gg, gb = col("glow"); boxColor(o.glow, gr, gg, gb, 0.95)
  P.TindColor(o)
  o.cast.shield:SetVertexColor(0.85, 0.85, 0.9)
  o.cast.spark:SetVertexColor(1, 1, 1, 0.9)
  o.hpText:SetTextColor(1, 1, 1)
  o.cast.text:SetTextColor(1, 1, 1); o.cast.time:SetTextColor(0.9, 0.9, 0.9)
end

---------------------------------------------------------------------------
-- Updates from the unit (or the preview)
---------------------------------------------------------------------------
local REACT = { [1] = "hostile", [2] = "hostile", [3] = "hostile", [4] = "neutral", [5] = "friendly", [6] = "friendly", [7] = "friendly", [8] = "friendly" }
local function rgb(key) local r, g, b = col(key); return { r, g, b } end

-- friendly unit you can't attack -> name only (when asked for); a hidden answer keeps the bar
function P.IsNameOnly(o)
  if not C().friendNameOnly then return false end
  local s, u = src(o), o.unit
  local att = s.canAttack(u)
  if sec(att) or isNil(att) then return false end
  return not att
end

-- the bar colour: tapped > your NPC colour > threat > class / reaction; execute range on top
function P.BarColor(o)
  local c, s, u = C(), src(o), o.unit
  if c.tapped and s.tapped(u) then return rgb("tapped") end
  local nm = s.name(u)
  if type(nm) == "string" and not sec(nm) then
    local n = c.npc[nm]
    if type(n) == "table" and n[1] then return { n[1], n[2], n[3] } end
  end
  if s.isPlayer(u) and c.classPlayers then
    local r, g, b = classColor(s.class(u))
    if r then return { r, g, b } end
  end
  -- reaction
  local base
  local re = s.reaction(u)
  if not sec(re) and REACT[re] then base = rgb(REACT[re])
  else base = pickColor(s.canAttack(u), rgb("hostile"), rgb("friendly")) end
  -- threat (only hostile units, only in a fight)
  if c.threat and s.combat() then
    local att = s.canAttack(u)
    if bool(att) or sec(att) then
      local tank = o.fake and o.fake.tank or P.IsTank()
      local st = s.threat(u)
      if not isNil(st) and not sec(st) then
        if tank then
          if st == 3 then return rgb("tankGood") elseif st == 2 or st == 1 then return rgb("tankWarn") end
          return rgb("tankBad")
        else
          if st == 3 then return rgb("dpsBad") elseif st == 2 or st == 1 then return rgb("dpsWarn") end
        end
      elseif sec(st) then
        -- the game hides the threat state: fall back to "is it looking at me?"
        local ag = s.aggro(u)
        if tank then return pickColor(ag, rgb("tankGood"), rgb("tankBad")) end
        if type(base) == "table" and base[1] then return pickColor(ag, rgb("dpsBad"), base) end
      end
    end
  end
  return base
end

-- execute range: a plain comparison when the game shows health, else its colour curve
P.curves = {}
function P.ExecColor(o, base, cur, mx)
  local c, s, u = C(), src(o), o.unit
  if not c.execute then return base end
  local att = s.canAttack(u)
  if not (bool(att) or sec(att)) then return base end
  local pct = c.execPct or 20
  if not sec(cur, mx) then
    if mx and mx > 0 and cur > 0 and cur / mx * 100 <= pct then return rgb("execute") end
    return base
  end
  -- hidden health: a step curve, evaluated by the game
  if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor and UnitHealthPercent) then return base end
  if type(base) ~= "table" or not base[1] then return base end
  local er, eg, eb = col("execute")
  local key = string.format("%.3f%.3f%.3f%.3f%.3f%.3f%d", base[1], base[2], base[3], er, eg, eb, pct)
  local cv = P.curves[key]
  if cv == nil then
    cv = try(C_CurveUtil.CreateColorCurve) or false
    if cv then
      local E = Enum and Enum.LuaCurveType
      if E and E.Step and cv.SetType then pcall(cv.SetType, cv, E.Step) end
      local ex, nb = CreateColor(er, eg, eb, 1), CreateColor(base[1], base[2], base[3], 1)
      pcall(cv.AddPoint, cv, 0, ex)
      pcall(cv.AddPoint, cv, pct / 100, nb)
      pcall(cv.AddPoint, cv, 1, nb)
    end
    P.curves[key] = cv
  end
  if not cv then return base end
  local out = try(UnitHealthPercent, u, false, cv)
  if type(out) == "table" and out.GetRGB then return out end
  return base
end

function P.UpdateHealth(o)
  if o.nameOnly then return end
  local c, s, u = C(), src(o), o.unit
  local cur, mx = s.health(u)
  pcall(o.hp.SetMinMaxValues, o.hp, 0, mx)
  if not pcall(o.hp.SetValue, o.hp, cur) then o.hp:SetValue(0) end
  local base = P.BarColor(o)
  paintBar(o.hp, P.ExecColor(o, base, cur, mx))
  o.exec:SetShown(c.execute and c.execLine and (bool(s.canAttack(u)) or sec(s.canAttack(u))))
  if c.hpText ~= "none" then
    if s.dead(u) then o.hpText:SetText("Dead")
    else setText(o.hpText, hpString(c.hpText, cur, mx, (c.hpText == "percent" or c.hpText == "both") and sec(cur, mx) and s.pct(u) or nil)) end
  end
end

function P.UpdateName(o)
  local c, s, u = C(), src(o), o.unit
  do local _, cl0 = s.level(u); if P.UFKind(o, cl0) ~= o.ufKind then guard(P.Layout, o) end end
  local nm = s.name(u)
  if isNil(nm) then nm = "" end
  local lvl, cl = s.level(u)
  local ls = levelString(lvl, cl)
  -- small elite badge (not the dragon): inline, right before the level
  local kind = c.classIcon and not o.nameOnly and P.BadgeKind(cl) or nil
  local ring = kind and c.eliteStyle == "ring" or false
  local inl = (kind and not P.IsWrap() and not ring) and P.BadgeInline(kind, c.fontSize * 1.35 * (c.eliteSize or 1)) or nil
  if ring then o.ringLvl:SetText(levelString(lvl, cl, true)); ls = "" end      -- the level lives in the ring
  if o.ufKind and c.frameLevel then o.ufLvl:SetText(levelString(lvl, cl, true)); ls = "" end   -- ... or in the frame's bubble
  o.badgeInline = nil
  local pre = ""
  if inl and (c.nameShow and c.levelAt ~= "left") then pre = inl .. " "; o.badgeInline = "name" end
  local shown = nm
  if c.levelAt == "name" and ls ~= "" and not o.nameOnly then
    local out = fmt("%s%s %s", pre, ls, nm)
    if not isNil(out) then shown = out end
  elseif pre ~= "" then
    local out = fmt("%s%s", pre, nm)
    if not isNil(out) then shown = out end
  end
  setText(o.name, shown)
  -- fit the name to the bar: shrink the text (measured off the plate) when it's too long
  o.nameShown = shown
  guard(P.FitName, o)
  if c.levelAt == "left" then
    if inl then o.level:SetText(inl .. " " .. ls); o.badgeInline = "level" else o.level:SetText(ls) end
  else o.level:SetText("") end
  -- name colour
  local th = UI:Theme()
  local mode = c.nameColor
  if o.nameOnly and mode == "white" then mode = "reaction" end
  local r, g, b = 1, 1, 1
  if mode == "theme" then r, g, b = th.gold[1], th.gold[2], th.gold[3]
  elseif mode == "class" or mode == "reaction" then
    local done
    if s.isPlayer(u) then local x, y, z = classColor(s.class(u)); if x then r, g, b, done = x, y, z, true end end
    if not done and mode == "reaction" then
      local re = s.reaction(u)
      if not sec(re) and REACT[re] then r, g, b = col(REACT[re]) end
    end
  end
  o.name:SetTextColor(r, g, b)
  -- elite / rare / boss badge
  if c.classIcon and not o.nameOnly and cl and cl ~= "normal" and cl ~= "trivial" and cl ~= "minus" then
    if o.dragon then o.badgeHow = "dragon"; o.cls:Hide()
    elseif o.ringMode then o.badgeHow = "ring"; o.cls:Hide()
    elseif o.badgeInline then o.badgeHow = "inline-" .. o.badgeInline; o.cls:Hide()
    else o.badgeHow = P.SetBadge(o.cls, cl); o.cls:Show() end      -- no name / level shown: icon left of the bar
    local wantBadge = (not P.UFKind(o, cl)) and P.BadgeKind(cl) or nil
    if o.badgeWrap ~= (wantBadge and P.IsWrap() or false) or o.badge ~= wantBadge or (o.ringMode or false) ~= (wantBadge ~= nil and c.eliteStyle == "ring") then guard(P.Layout, o) end   -- classification learned late
  else
    o.cls:Hide()
    if o.dragon or o.ringMode then guard(P.Layout, o) end      -- no longer elite: take the dragon away
  end
end

-- raid marks. Forever may hide the mark number on nameplates ("secret"), so there are three ways:
--   plain   the number is readable: our own icon
--   curve   hidden number: 8 stacked icons, each one's alpha worked out by the game from a
--           step curve (1 at its own mark, 0 elsewhere) - no comparisons on our side
--   game    last resort: the game's own raid icon on its (invisible) plate, pinned onto ours
local function markCell(t, i)
  t:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
  if SetRaidTargetIconTexture and pcall(SetRaidTargetIconTexture, t, i) then return end
  local k = i - 1
  t:SetTexCoord((k % 4) * 0.25, (k % 4) * 0.25 + 0.25, floor(k / 4) * 0.25, floor(k / 4) * 0.25 + 0.25)
end
P.markCurves = nil
local function markCurves()
  if P.markCurves ~= nil then return P.markCurves end
  P.markCurves = false
  if not (C_CurveUtil and C_CurveUtil.CreateCurve) then return false end
  local list = {}
  for i = 1, 8 do
    local cv = try(C_CurveUtil.CreateCurve)
    if not cv then return false end
    local E = Enum and Enum.LuaCurveType
    if E and E.Step and cv.SetType then pcall(cv.SetType, cv, E.Step) end
    if not (pcall(cv.AddPoint, cv, 0, 0) and pcall(cv.AddPoint, cv, i - 0.5, 1) and pcall(cv.AddPoint, cv, i + 0.5, 0) and pcall(cv.AddPoint, cv, 9, 0)) then return false end
    list[i] = cv
  end
  P.markCurves = list
  return list
end
local function curveMarks(o, idx)
  local list = markCurves()
  if not list then return false end
  if not o.marks then
    o.marks = {}
    for i = 1, 8 do local t = o.over:CreateTexture(nil, "OVERLAY", nil, 2); markCell(t, i); t:Hide(); o.marks[i] = t end
  end
  for i = 1, 8 do
    local t = o.marks[i]
    t:ClearAllPoints(); t:SetAllPoints(o.raid)
    local cv = list[i]
    local ok = pcall(function() t:SetAlpha(cv:Evaluate(idx)) end)
    if not ok then for j = 1, 8 do o.marks[j]:Hide() end return false end
    t:Show()
  end
  return true
end
local function hideCurveMarks(o) if o.marks then for i = 1, 8 do o.marks[i]:Hide() end end end
function P.UpdateRaid(o)
  local s, u = src(o), o.unit
  local idx = s.raid(u)
  if sec(idx) then
    o.raid:SetTexture(nil); o.raid:Show()          -- kept as the anchor for the marks
    if curveMarks(o, idx) then o.raidHow = "hidden number, drawn by CCPlates"; P.BorrowRaid(o, false) return end
    hideCurveMarks(o)
    o.raidHow = P.BorrowRaid(o, true) and "hidden number, the game's icon" or "hidden number, game icon not found"
    return
  end
  hideCurveMarks(o)
  if (isNil(idx) or idx == 0) and not o.fake and bool(try(UnitIsUnit, u, "target")) then
    local t = try(GetRaidTargetIndex, "target")      -- the plate's unit is your target: ask by "target"
    if not sec(t) and t and t > 0 then idx = t end
  end
  if idx and idx > 0 and idx <= 8 then
    P.BorrowRaid(o, false)
    markCell(o.raid, idx)
    o.raid:Show()
    o.raidHow = "mark " .. idx
  else
    o.raid:Hide()
    -- nothing readable: show the game's own icon on our plate (the game shows it only when marked)
    if not o.fake and C().raidGame ~= false then
      o.raidHow = P.BorrowRaid(o, true) and "none readable - the game's own icon is shown" or "no mark"
    else o.raidHow = "no mark" end
  end
end

function P.UpdateQuest(o)
  local c, s, u = C(), src(o), o.unit
  o.quest:SetShown(c.quest and not o.nameOnly and s.quest(u, o) and true or false)
end

function P.UpdateCombo(o)
  local c, s, u = C(), src(o), o.unit
  local n, mx
  if c.combo and not o.nameOnly then n, mx = s.combo(u) end
  local th = UI:Theme()
  for i, p in ipairs(o.combo) do
    local show = n and i <= mx
    p.ring:SetShown(show and true or false)
    p.fill:SetShown(show and i <= n or false)
    if show then
      p.ring:SetVertexColor(th.edge[1], th.edge[2], th.edge[3], 0.9)
      if n == mx then p.fill:SetVertexColor(1, 0.35, 0.2) else p.fill:SetVertexColor(th.gold[1], th.gold[2], th.gold[3]) end
      p.ring:ClearAllPoints(); p.ring:SetPoint("TOP", o, "BOTTOM", (i - (mx + 1) / 2) * ((o.comboGS or 8) + 2), -2)
    end
  end
  o.comboShown = n ~= nil
  -- the cast bar steps down under the gems
  local cb = o.cast
  do
    local gs = o.comboGS or 8
    local y = o.comboShown and -(gs + 5) or -3
    if o.castY ~= y then
      o.castY = y
      cb:ClearAllPoints()
      cb:SetPoint("TOPLEFT", o, "BOTTOMLEFT", 0, y); cb:SetPoint("TOPRIGHT", o, "BOTTOMRIGHT", 0, y)
    end
  end
end

-- r31 target indicators: animated pieces either side of your target's plate, pointing in. Art in Media\Plates\tind_*
-- (made by tind/gen_tind.py, every one points LEFT: the right piece as drawn, the left one mirrored). w = width per
-- unit of height; tint = coloured with the "arrows" colour; anim: dx = px it moves in and back, dur = seconds one way,
-- alpha / scale = pulse to that value and back.
P.TIND = {
  standard = { file = "tind_std",  w = 1, tint = true, anim = { dx = 5, dur = 0.45 } },
  minimal  = { file = "tind_min",  w = 1, tint = true, size = 0.8, anim = { dx = 2, dur = 0.8, alpha = 0.45 } },
  artistic = { file = "tind_art",  w = 2, tint = false, size = 1.15, anim = { dx = 3, dur = 0.9 } },
  cartoon  = { file = "tind_toon", w = 2, tint = true, anim = { dx = 7, dur = 0.32, scale = 1.12 } },
  glow     = { file = "tind_glow", w = 2, tint = true, add = true, anim = { dx = 4, dur = 0.6, alpha = 0.35 } },
}
P.TIND_ORDER = { "standard", "minimal", "artistic", "cartoon", "glow" }
function P.TindLayout(o, h, xl, xr)
  local c = C()
  local st = P.TIND[c.tInd]
  if not st then return end
  local as = max(12, (h + 8) * (st.size or 1) * (c.tIndSize or 1))
  local aw = as * st.w
  for side, t in pairs({ L = o.arrowL, R = o.arrowR }) do
    t:SetTexture(MEDIA .. st.file)
    if side == "L" then t:SetTexCoord(1, 0, 0, 1) else t:SetTexCoord(0, 1, 0, 1) end
    t:SetBlendMode(st.add and "ADD" or "BLEND")
    t:SetSize(aw, as); t:ClearAllPoints()
  end
  o.arrowL:SetPoint("RIGHT", o, "LEFT", xl, 0)
  o.arrowR:SetPoint("LEFT", o, "RIGHT", xr, 0)
  o.tindStyle = c.tInd
end
function P.TindColor(o)
  local st = P.TIND[C().tInd]
  if st and not st.tint then o.arrowL:SetVertexColor(1, 1, 1); o.arrowR:SetVertexColor(1, 1, 1) return end
  local ar, ag, ab = col("arrows"); o.arrowL:SetVertexColor(ar, ag, ab); o.arrowR:SetVertexColor(ar, ag, ab)
end
-- one looping animation per piece and style (made once); dir +1 = moves right (the left piece, toward the plate)
local function tindAnim(t, style, dir)
  t.ccAG = t.ccAG or {}
  local ag = t.ccAG[style]
  if ag ~= nil then return ag end
  local a = P.TIND[style] and P.TIND[style].anim
  if not (a and t.CreateAnimationGroup) then t.ccAG[style] = false return false end
  -- r32: REPEAT with an explicit "in" step (order 1) and "back" step (order 2) that end exactly where they started -
  -- BOUNCE flashed / jumped for a frame at the turn-around (user 23:18 "glitching at the end of the animations")
  local ok = pcall(function()
    ag = t:CreateAnimationGroup()
    ag:SetLooping("REPEAT")
    for step = 1, 2 do
      local fwd = step == 1
      local tr = ag:CreateAnimation("Translation"); tr:SetOrder(step); tr:SetDuration(a.dur); tr:SetSmoothing("IN_OUT")
      tr:SetOffset((fwd and a.dx or -a.dx) * dir, 0)
      if a.alpha then
        local al = ag:CreateAnimation("Alpha"); al:SetOrder(step); al:SetDuration(a.dur); al:SetSmoothing("IN_OUT")
        al:SetFromAlpha(fwd and 1 or a.alpha); al:SetToAlpha(fwd and a.alpha or 1)
      end
      if a.scale then
        local sc = ag:CreateAnimation("Scale"); sc:SetOrder(step); sc:SetDuration(a.dur); sc:SetSmoothing("IN_OUT")
        if sc.SetScaleFrom then
          sc:SetScaleFrom(fwd and 1 or a.scale, fwd and 1 or a.scale); sc:SetScaleTo(fwd and a.scale or 1, fwd and a.scale or 1)
        else local k = fwd and a.scale or (1 / a.scale); sc:SetScale(k, k) end
        if sc.SetOrigin then sc:SetOrigin(dir > 0 and "RIGHT" or "LEFT", 0, 0) end
      end
    end
  end)
  t.ccAG[style] = ok and ag or false
  return t.ccAG[style]
end
function P.TindShow(o, on)
  local c = C()
  local style = c.tInd
  for side, t in pairs({ L = o.arrowL, R = o.arrowR }) do
    t:SetShown(on and true or false)
    for k, g in pairs(t.ccAG or {}) do
      if g and (not on or k ~= style or not c.tIndAnim) and g:IsPlaying() then g:Stop() end
    end
    if on and c.tIndAnim then
      local g = tindAnim(t, style, side == "L" and 1 or -1)
      if g and not g:IsPlaying() then g:Play() end
    end
  end
end

-- r31 threat: a glow round the plate in the threat colour, and / or words + the game's threat %, in a fight.
-- Tank: 3 = you hold it (THREAT), 2 = losing it (LOSING), 0/1 = someone else has it (NO THREAT).
-- Damage / healing: 3/2 = it's on you (AGGRO), 1 = you're about to pull it (PULLING), 0 = safe (nothing shown).
-- The game may hide the threat state / % (secret): then 4 stacked glows each shown by a step curve the game
-- evaluates, and the % goes straight into the text widget.
local function thrLook(tank, st)
  if tank then
    if st == 3 then return "tankGood", "THREAT" elseif st == 2 then return "tankWarn", "LOSING" end
    return "tankBad", "NO THREAT"
  end
  if st == 3 or st == 2 then return "dpsBad", "AGGRO" elseif st == 1 then return "dpsWarn", "PULLING" end
  return nil, nil
end
P.thrCurves = nil
local function thrCurves()
  if P.thrCurves ~= nil then return P.thrCurves end
  P.thrCurves = false
  if not (C_CurveUtil and C_CurveUtil.CreateCurve) then return false end
  local list = {}
  for i = 0, 3 do
    local cv = try(C_CurveUtil.CreateCurve)
    if not cv then return false end
    local E = Enum and Enum.LuaCurveType
    if E and E.Step and cv.SetType then pcall(cv.SetType, cv, E.Step) end
    if not (pcall(cv.AddPoint, cv, -1, 0) and pcall(cv.AddPoint, cv, i - 0.5, 1) and pcall(cv.AddPoint, cv, i + 0.5, 0) and pcall(cv.AddPoint, cv, 4, 0)) then return false end
    list[i] = cv
  end
  P.thrCurves = list
  return list
end
-- r34 where the threat words sit: neat against the bar's top-right corner, unless debuffs are showing in that spot
-- (debuffs above the bar) - then centred just above the debuff row so they're always readable. Nothing on the plate
-- can be measured, so the row's height comes from the settings (like P.NameLift).
local function debuffsShowing(o)
  local c = C()
  if c.auraMode == "off" then return false end
  if c.auraMode == "copy" or o.fake then
    for _, b in ipairs(o.auras or {}) do if b:IsShown() then return true end end
    return false
  end
  local row = P.AuraRow(o.base)
  return row and #P.RowButtons(row) > 0 or false
end
function P.ThreatSpot(o)
  local c = C()
  local at = c.auraAt or "above"
  local up = (at == "above" or at == "undername" or o.nameOnly) and debuffsShowing(o)
  local spot = up and "up" or "bar"
  if o.thrSpot == spot then return end
  o.thrSpot = spot
  local f = o.thrF
  f:ClearAllPoints()
  if not up then
    f:SetPoint("BOTTOMRIGHT", o, "TOPRIGHT", -2, 2 + (o.frameLift or 0) + floor((o.thrFS or 10) / 2))
    o.thrTxt:ClearAllPoints(); o.thrTxt:SetPoint("RIGHT", f, "CENTER", 0, 0); o.thrTxt:SetJustifyH("RIGHT")
    return
  end
  local nameAbove = c.nameShow and (c.nameAt == "above" or o.nameOnly)
  local rowH = (c.auraMode == "copy" or o.fake) and floor((c.auraSize or 20) * 0.75 * (c.auraScale or 1)) or floor(17 * (c.auraScale or 1) + 0.5)
  local anchor, y = o, (o.frameLift or 0)
  if nameAbove then anchor, y = o.name, 0 end
  if at == "undername" and nameAbove then y = 2                     -- the row is under the name: words go over the name
  else y = y + (c.auraY or 2) + rowH + 3 end
  f:SetPoint("BOTTOM", anchor, "TOP", c.auraX or 0, y + floor((o.thrFS or 10) / 2))
  o.thrTxt:ClearAllPoints(); o.thrTxt:SetPoint("CENTER", f, "CENTER", 0, 0); o.thrTxt:SetJustifyH("CENTER")
end
-- r34 effects on the threat words (the whole little frame, glow included): pulse / bounce / flash, looping in two steps
P.THR_FX = { pulse = { scale = 1.18, dur = 0.45 }, bounce = { dy = 4, dur = 0.35 }, flash = { alpha = 0.35, dur = 0.4 } }
local function thrFx(o, on)
  local f = o.thrF
  local fx = C().thrFx or "none"
  f.ccAG = f.ccAG or {}
  for k, g in pairs(f.ccAG) do if g and (k ~= fx or not on) and g:IsPlaying() then g:Stop() end end
  local a = P.THR_FX[fx]
  if not (on and a and f.CreateAnimationGroup) then return end
  local g = f.ccAG[fx]
  if g == nil then
    local ok = pcall(function()
      g = f:CreateAnimationGroup(); g:SetLooping("REPEAT")
      for step = 1, 2 do
        local fwd = step == 1
        if a.scale then
          local sc = g:CreateAnimation("Scale"); sc:SetOrder(step); sc:SetDuration(a.dur); sc:SetSmoothing("IN_OUT")
          if sc.SetScaleFrom then sc:SetScaleFrom(fwd and 1 or a.scale, fwd and 1 or a.scale); sc:SetScaleTo(fwd and a.scale or 1, fwd and a.scale or 1)
          else local k = fwd and a.scale or (1 / a.scale); sc:SetScale(k, k) end
        end
        if a.dy then local tr = g:CreateAnimation("Translation"); tr:SetOrder(step); tr:SetDuration(a.dur); tr:SetSmoothing("IN_OUT"); tr:SetOffset(0, fwd and a.dy or -a.dy) end
        if a.alpha then local al = g:CreateAnimation("Alpha"); al:SetOrder(step); al:SetDuration(a.dur); al:SetSmoothing("IN_OUT"); al:SetFromAlpha(fwd and 1 or a.alpha); al:SetToAlpha(fwd and a.alpha or 1) end
      end
    end)
    f.ccAG[fx] = ok and g or false
    g = f.ccAG[fx]
  end
  if g and not g:IsPlaying() then g:Play() end
end
local function thrHide(o)
  boxShown(o.thr, false)
  if o.thrS then for i = 0, 3 do boxShown(o.thrS[i], false) end end
  o.thrTxt:Hide(); o.thrTG:Hide(); thrFx(o, false)
end
function P.UpdateThreat(o)
  local c, s, u = C(), src(o), o.unit
  o.thrHow = nil
  if not (c.thrGlow or c.thrText or c.thrPct) or o.nameOnly or not s.combat() then thrHide(o) return end
  local att = s.canAttack(u)
  if not (bool(att) or sec(att)) then thrHide(o) return end
  if c.thrGroup and not (s.grouped and s.grouped()) then thrHide(o) return end
  local tank = o.fake and o.fake.tank or P.IsTank()
  local st = s.threat(u)
  local pct = s.threatPct and s.threatPct(u)
  local label, key
  if sec(st) then
    -- hidden state: glows by curve, no words
    o.thrHow = "hidden"
    boxShown(o.thr, false)
    local list = c.thrGlow and thrCurves()
    if list then
      if not o.thrS then
        o.thrS = {}
        for i = 0, 3 do o.thrS[i] = newBox(o, "BACKGROUND", -7, true); boxShown(o.thrS[i], false) end
        local k = (c.round or 0); local bf = MEDIA .. "glow" .. ((o.ufKind and 5) or k)
        for i = 0, 3 do boxLayout(o.thrS[i], o, bf, 11, 6) end
      end
      for i = 0, 3 do
        local ck = thrLook(tank, i)
        local set = o.thrS[i]
        if ck then
          local r, g, b = col(ck)
          local ok = pcall(function() local a = list[i]:Evaluate(st); for _, t in ipairs(set.parts) do t:SetVertexColor(r, g, b, c.thrGlowAlpha or 0.9); t:SetAlpha(a) end end)
          boxShown(set, ok)
        else boxShown(set, false) end
      end
    elseif o.thrS then for i = 0, 3 do boxShown(o.thrS[i], false) end end
  else
    if o.thrS then for i = 0, 3 do boxShown(o.thrS[i], false) end end
    if isNil(st) then st = 0 end
    key, label = thrLook(tank, st)
    o.thrHow = label or "safe"
    if key and c.thrGlow then local r, g, b = col(key); boxColor(o.thr, r, g, b, c.thrGlowAlpha or 0.9); boxShown(o.thr, true)
    else boxShown(o.thr, false) end
  end
  -- words / %
  local words = c.thrText and label or nil
  local t = o.thrTxt
  if key then local r, g, b = col(key); t:SetTextColor(r, g, b) else t:SetTextColor(1, 1, 1) end
  local shown = false
  if c.thrPct and pct ~= nil then
    if sec(pct) then
      shown = pcall(t.SetFormattedText, t, words and (words .. " %.0f%%") or "%.0f%%", pct)
    elseif type(pct) == "number" then
      t:SetText((words and (words .. " ") or "") .. string.format("%d%%", floor(pct + 0.5))); shown = true
    end
  end
  if not shown and words then t:SetText(words); shown = true end
  t:SetShown(shown)
  -- r34: spot (bar corner / above the debuffs), soft glow behind the words, effect
  P.ThreatSpot(o)
  local gA = shown and (c.thrTextGlow or 0) or 0
  if gA > 0 then
    local fs = o.thrFS or 10
    local chars = (words and #words or 0) + (c.thrPct and 5 or 0)
    o.thrTG:SetSize(max(fs * 3, chars * fs * 0.62 + fs * 1.6), fs * 2.4)
    o.thrTG:ClearAllPoints(); o.thrTG:SetPoint("CENTER", t, "CENTER", 0, 0)
    local r, g, b = 1, 1, 1
    if key then r, g, b = col(key) end
    o.thrTG:SetVertexColor(r, g, b, gA); o.thrTG:Show()
  else o.thrTG:Hide() end
  thrFx(o, shown)
end

-- r35 lootable corpses (user 00:07 "Turn nameplate of dead enemy that is lootable into loot icon till looted and then
-- dissapears"): a dead unit's plate becomes a bobbing loot bag while you can loot it; looted / not yours -> nothing.
-- NB: the game usually takes the plate away when a mob dies - this only works while it keeps one (P.corpseSeen counts).
P.corpseSeen = 0
local function lootFrame(o)
  if o.lootF then return o.lootF end
  local base = o.base or o:GetParent()
  local f = CreateFrame("Frame", nil, base); f:SetSize(32, 32); f:Hide()
  f.glow = f:CreateTexture(nil, "BACKGROUND"); f.glow:SetTexture(MEDIA .. "tglow"); f.glow:SetBlendMode("ADD"); f.glow:SetPoint("CENTER")
  f.glow:SetVertexColor(1, 0.8, 0.25, 0.8)
  f.icon = f:CreateTexture(nil, "ARTWORK"); f.icon:SetAllPoints()
  if not (f.icon.SetAtlas and pcall(f.icon.SetAtlas, f.icon, "VignetteLoot")) or (f.icon.GetAtlas and not f.icon:GetAtlas()) then
    f.icon:SetTexture("Interface\\Icons\\INV_Misc_Bag_08"); f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  end
  pcall(function()
    local g = f:CreateAnimationGroup(); g:SetLooping("REPEAT")
    for step = 1, 2 do
      local tr = g:CreateAnimation("Translation"); tr:SetOrder(step); tr:SetDuration(0.6); tr:SetSmoothing("IN_OUT"); tr:SetOffset(0, step == 1 and 4 or -4)
    end
    f.ag = g
  end)
  o.lootF = f
  return f
end
local function corpseOff(o)
  if o.lootF then o.lootF:Hide(); if o.lootF.ag then o.lootF.ag:Stop() end end
  if o.corpseHid then o.corpseHid = nil; if o.unit then o:Show() end end
  o.corpse = nil
end
function P.UpdateCorpse(o)
  local c, s, u = C(), src(o), o.unit
  if not u then corpseOff(o) return end
  local dead = s.dead and s.dead(u)
  if not c.corpseLoot or sec(dead) or not dead then corpseOff(o) return end
  if not o.corpse then P.corpseSeen = P.corpseSeen + 1 end
  o.corpse = true
  o:Hide(); o.corpseHid = true
  local f = lootFrame(o)
  local loot = s.lootable and s.lootable(u)
  o.corpseRaw = loot
  -- r36: in dungeons the game hides the unit's GUID, so CanLootUnit can't be asked (loot = nil, user 00:14: 2 corpse
  -- plates, 0 bags, in a dungeon). Then: a bag on every corpse that isn't someone else's tag, until you loot it
  -- (o.looted, set on LOOT_OPENED for the dead plate you have targeted / under the mouse).
  if loot == nil then
    local denied = s.tapped and s.tapped(u)
    loot = not denied and not o.looted
    o.corpseGuess = true
  else o.corpseGuess = nil end
  if o.looted then loot = false end
  if loot then
    local sz = floor(26 * min(2, max(0.5, c.corpseSize or 1)) * (c.scale or 1) + 0.5)
    f:SetSize(sz, sz); f.glow:SetSize(sz * 2.2, sz * 1.5)
    f:ClearAllPoints(); f:SetPoint("CENTER", o.base or f:GetParent(), "CENTER", 0, 0)
    f:Show(); if f.ag and not f.ag:IsPlaying() then f.ag:Play() end
    o.corpseHow = o.corpseGuess and "loot bag (guessed)" or "loot bag"
  else
    f:Hide(); if f.ag then f.ag:Stop() end
    o.corpseHow = o.looted and "looted" or (o.corpseGuess and "someone else's" or "nothing to loot")
  end
end

-- target / mouse-over: size, glow, arrows, edge colour, fading the others
function P.UpdateTarget(o)
  local c, s, u = C(), src(o), o.unit
  local isT = s.isTarget(u)
  local any = s.anyTarget()
  local sc = (o.baseScale or 1) * ((isT and not o.nameOnly) and c.tScale or 1)
  if o.ccScale ~= sc then o.ccScale = sc; o:SetScale(max(0.2, sc)); P.PlaceOn(o) end
  local glowOn = isT and c.tGlow and not o.nameOnly
  boxShown(o.glow, glowOn)
  P.TindShow(o, isT and c.tInd ~= "off" and not o.nameOnly)
  local e = o.ccEdgeRGB or { 0, 0, 0 }
  if isT and c.tBorder and c.border ~= "none" then local r, g, b = col("glow"); boxColor(o.edge, r, g, b, 1)
  else boxColor(o.edge, e[1], e[2], e[3], 1) end
  local a = 1
  if c.fade and any and not isT then a = c.fadeAlpha end
  if o.ccAlpha ~= a then o.ccAlpha = a; o:SetAlpha(a) end
  o.hp.hl:SetShown(c.mouseHL and not isT and s.isMouse(u) or false)
  o.isTarget = isT
  -- the plate you're targeting is drawn above the others
  if o.base and o.base.SetFrameLevel and not o.fake then
    local lvl = isT and 40 or 10
    if o.ccLvl ~= lvl then
      o.ccLvl = lvl
      local ok, bl = pcall(o.base.GetFrameLevel, o.base)
      if not ok or sec(bl) or type(bl) ~= "number" then bl = 0 end
      pcall(o.SetFrameLevel, o, bl + lvl)
    end
  end
end

---------------------------------------------------------------------------
-- Cast bar
---------------------------------------------------------------------------
local function castColor(o, notInt, channel)
  local c = C()
  local cb = o.cast
  local n = channel and rgb("castChan") or rgb("castInt")
  if c.castReady and not channel then
    local ready
    if o.fake then ready = o.fake.kickReady else ready = P.KickReady() end
    if ready then n = rgb("castReady") end
  end
  local grey = rgb("castNon")
  if not sec(notInt) then
    local x = notInt and grey or n
    cb:SetStatusBarColor(x[1], x[2], x[3]); cb.shield:SetShown(notInt and true or false)
  else
    paintBar(cb, pickColor(notInt, grey, n))
    if cb.shield.SetAlphaFromBoolean then pcall(cb.shield.SetAlphaFromBoolean, cb.shield, notInt, 1, 0); cb.shield:Show() else cb.shield:Hide() end
  end
end
local function castTick(cb)
  if not cb.ccStart then return end
  local now = GetTime()
  local total = cb.ccEnd - cb.ccStart
  if total <= 0 then return end
  local p = (now - cb.ccStart) / total
  if p >= 1.05 then cb:SetScript("OnUpdate", nil); cb.ccStart = nil; if not cb.ccLoop then cb:Hide() end return end
  local v = min(1, max(0, cb.ccChannel and (1 - p) or p))
  cb:SetValue(v)
  cb.spark:ClearAllPoints(); cb.spark:SetPoint("CENTER", cb, "LEFT", (cb.ccW or 100) * v, 0)
  cb.time:SetText(string.format("%.1f", max(0, cb.ccEnd - now)))
end
local function castFade(cb)
  local t = GetTime() - cb.ccFadeAt
  local hold, len = cb.ccHold or 0, cb.ccLen or 0.3
  if t < hold then return end
  local a = 1 - (t - hold) / len
  if a <= 0 then cb:SetScript("OnUpdate", nil); cb.ccFading = nil; cb:Hide(); cb:SetAlpha(1) return end
  cb:SetAlpha(a)
end
function P.CastStop(o, failed)
  local cb = o.cast
  if not cb:IsShown() or cb.ccFading == "fail" then return end
  cb.ccStart = nil
  if failed == nil then cb.ccFading = nil; cb:SetScript("OnUpdate", nil); cb:Hide(); cb:SetAlpha(1) return end
  local c = C()
  cb.spark:Hide()
  if cb.ccSecret then pcall(cb.SetMinMaxValues, cb, 0, 1) end
  cb.ccSecret = nil
  cb:SetValue(1)
  cb.ccFadeAt = GetTime()
  if failed and c.castFailShow then
    cb.ccFading = "fail"
    local r, g, b = col("castFail"); cb:SetStatusBarColor(r, g, b)
    cb.text:SetText(cb.ccChannel and "Stopped" or "Interrupted"); cb.time:SetText("")
    cb.ccHold, cb.ccLen = 0.5, 0.4
  else
    cb.ccFading = "done"; cb.ccHold, cb.ccLen = 0, 0.25
  end
  cb:SetScript("OnUpdate", castFade)
end
function P.CastStart(o)
  local c, s, u = C(), src(o), o.unit
  local cb = o.cast
  if not c.castShow or o.nameOnly then cb:Hide() return end
  local name, text, tex, st, et, notInt, channel = s.cast(u)
  if isNil(name) then P.CastStop(o) return end
  cb.ccChannel = channel
  cb.ccFading = nil; cb:SetAlpha(1)
  cb.spark:SetShown(c.castSpark)
  pcall(cb.icon.SetTexture, cb.icon, tex)
  if isNil(text) or text == "" then text = name end
  if not pcall(cb.text.SetText, cb.text, name) then setText(cb.text, text) end
  castColor(o, notInt, channel)
  if not sec(st, et) and not isNil(st) and not isNil(et) then
    cb.ccSecret = nil
    cb.ccStart, cb.ccEnd = st / 1000, et / 1000
    cb:SetMinMaxValues(0, 1)
    cb:SetScript("OnUpdate", castTick)
    castTick(cb)
  else
    -- the game hides the timing: the bar runs off the game's own duration object
    cb.ccStart = nil; cb:SetScript("OnUpdate", nil); cb.spark:Hide(); cb.time:SetText("")
    local dur = REAL.castDuration(u, channel)
    local E = Enum and Enum.StatusBarTimerDirection
    local dir = E and (channel and E.RemainingTime or E.ElapsedTime) or nil
    local ok = dur and cb.SetTimerDuration and (pcall(cb.SetTimerDuration, cb, dur, nil, dir) or pcall(cb.SetTimerDuration, cb, dur))
    cb.ccSecret = ok and true or nil
    if not ok then cb:SetMinMaxValues(0, 1); cb:SetValue(1) end
  end
  cb:Show()
end

---------------------------------------------------------------------------
-- The game's plate under ours: made invisible (never hidden: its debuff code
-- keeps running), its debuff row and raid mark borrowed onto our plate
---------------------------------------------------------------------------
local function blizzUF(base) return base and (base.UnitFrame or base.unitFrame) end
P.lockAlpha = false
function P.HideBlizz(o)
  local uf = blizzUF(o.base)
  if not uf then return end
  P.hiddenUF[uf] = true
  if not P.hooked[uf] and hooksecurefunc then
    P.hooked[uf] = true
    pcall(hooksecurefunc, uf, "SetAlpha", function(self)
      if P.lockAlpha or not P.hiddenUF[self] or not P.Enabled() then return end
      P.lockAlpha = true; self:SetAlpha(0); P.lockAlpha = false
    end)
  end
  P.lockAlpha = true; uf:SetAlpha(0); P.lockAlpha = false
end
-- r28: on this client the game decides where a plate takes clicks with hit-test points on the plate, anchored to ITS
-- name + health bar (Blizzard_NamePlateUnitFrame UpdateHitTestArea) - and it clears them for friendly players shown
-- as names only (cvar nameplateShowOnlyNameForFriendlyPlayerUnits), so those plates can't be clicked at all. We put
-- the points on OUR plate instead (bar + name + frame bands, or just the name on name-only plates), again every time
-- the game re-does its own. Can't be changed in a fight -> retried after it.
function P.HitArea(o)
  local base = o and o.base
  if not (base and base.SetHitTestPoints) or not o.unit then return end
  if combat() and base.CanChangeHitTestPoints then
    local ok, can = pcall(base.CanChangeHitTestPoints, base)
    if not ok or not can then P.pendingHit = true return end
  end
  local c = C()
  local pts
  if o.nameOnly then
    pts = { { point = "TOPLEFT", relativeTo = o.name, relativePoint = "TOPLEFT", offsetX = -8, offsetY = 3 },
            { point = "BOTTOMRIGHT", relativeTo = o.name, relativePoint = "BOTTOMRIGHT", offsetX = 8, offsetY = -3 } }
  else
    local nh = (c.fontSize or 10) + (c.nameSize or 0) + 4
    local fl = o.ufKind and (o.frameLift or 0) or 0
    local top = fl + ((c.nameShow and c.nameAt == "above") and (nh + P.NameLift(o)) or 0)
    local bot = fl + ((c.nameShow and c.nameAt == "below") and nh or 0)
    pts = { { point = "TOPLEFT", relativeTo = o, relativePoint = "TOPLEFT", offsetX = -4 - (o.lead or 0), offsetY = top + 2 },
            { point = "BOTTOMRIGHT", relativeTo = o, relativePoint = "BOTTOMRIGHT", offsetX = 4 + (o.trail or 0), offsetY = -bot - 2 } }
  end
  local ok = pcall(base.SetHitTestPoints, base, pts)
  o.hitHow = ok and (o.nameOnly and "ours (name)" or "ours") or "game (refused)"
  if not ok and combat() then P.pendingHit = true end
  local uf = blizzUF(base)
  if uf and not P.hitHooked[uf] and hooksecurefunc and uf.UpdateHitTestArea then
    P.hitHooked[uf] = true
    pcall(hooksecurefunc, uf, "UpdateHitTestArea", function(self)
      local oo = P.plates[base]
      if oo and oo.unit and oo:IsShown() and P.Enabled() then P.HitArea(oo) end
    end)
  end
end
P.hitHooked = setmetatable({}, { __mode = "k" })
-- give the click area back to the game's own name + bar
function P.HitAreaBack(o)
  local uf = blizzUF(o and o.base)
  if uf and uf.UpdateHitTestArea and NamePlateSetupOptions and not combat() then pcall(uf.UpdateHitTestArea, uf, NamePlateSetupOptions) end
end
function P.ShowBlizz(o)
  local uf = blizzUF(o.base)
  if not uf then return end
  P.hiddenUF[uf] = nil
  P.lockAlpha = true; uf:SetAlpha(1); P.lockAlpha = false
end

-- borrow one of the game's regions: it keeps its parent (Unit Frames still finds it),
-- ignores the invisible parent's alpha, and is pinned to our plate
P.placing = false
-- r27: the game's debuff row / raid icon sit over the plate above when pinned onto ours; clicks must pass through
-- them (tooltips on mouse-over still work). Out of combat only, remembered per region.
P.clickFree = setmetatable({}, { __mode = "k" })
function P.ClickThrough(r)
  if not r or P.clickFree[r] or combat() then return end
  P.clickFree[r] = true
  if r.SetMouseClickEnabled then pcall(r.SetMouseClickEnabled, r, false) end
end
function P.Pin(o, region, place)
  if not region then return end
  P.ClickThrough(region)
  local b = P.borrowed[region]
  if not b then
    b = {}
    P.borrowed[region] = b
    if hooksecurefunc then
      pcall(hooksecurefunc, region, "SetPoint", function(self)
        local bb = P.borrowed[self]
        if P.placing or not bb or not bb.o or not P.Enabled() then return end
        P.placing = true; pcall(bb.place, bb.o, self); P.placing = false
      end)
    end
  end
  b.o, b.place = o, place
  if region.SetIgnoreParentAlpha then pcall(region.SetIgnoreParentAlpha, region, true) end
  P.placing = true; pcall(place, o, region); P.placing = false
end
function P.Unpin(region)
  local b = region and P.borrowed[region]
  if not b or not b.o then return end
  b.o = nil
  -- its old spot can't be read back (restricted), so it stays put; a /reload puts it back exactly
  if region.SetIgnoreParentAlpha then pcall(region.SetIgnoreParentAlpha, region, false) end
  pcall(region.SetScale, region, 1)
  pcall(region.SetAlpha, region, 1)
end
-- Blizzard's own nameplate debuffs. The game keeps drawing them in a fight (addons
-- can't read auras then), so CCPlates uses the game's row itself:
--   move: the row is pinned onto our plate (real icons, timers, stacks, type borders)
--   copy: our own icons mirror the game's buttons (icon, stacks, timer swipe passed on)
-- The row is found by its field name, else by looking for the frame holding aura
-- buttons (anything with an Icon + a Cooldown) - found once, remembered per plate.
P.ROW_KEYS = { "AurasFrame", "BuffFrame", "DebuffFrame", "aurasFrame", "buffFrame", "debuffFrame", "AuraFrame", "auraFrame" }
local function isAuraButton(ch)
  local ic = nth(ch, "Icon") or nth(ch, "icon")
  return type(ic) == "table" and ic.GetTexture ~= nil and ic.GetObjectType ~= nil and (ch.Cooldown or ch.cooldown or ch.CountFrame or ch.Count or ch.auraInstanceID or ch.Border) ~= nil
end
P.rowOf = setmetatable({}, { __mode = "k" })     -- base plate -> { row, how }
function P.AuraRow(base)
  local known = P.rowOf[base]
  if known then return known.row, known.how end
  local uf = blizzUF(base)
  if not uf then return end
  for _, k in ipairs(P.ROW_KEYS) do
    local f = nth(uf, k)
    if type(f) == "table" and f.GetChildren then P.rowOf[base] = { row = f, how = k }; return f, k end
  end
  local found
  local function scan(fr, depth)
    if found or depth > 4 or not fr.GetChildren then return end
    for _, ch in ipairs({ fr:GetChildren() }) do
      if type(ch) == "table" then
        if isAuraButton(ch) then found = fr return end
        scan(ch, depth + 1)
      end
    end
  end
  pcall(scan, uf, 0)
  if found and found ~= uf then P.rowOf[base] = { row = found, how = "found by its buttons" }; return found, "found by its buttons" end
end
local function auraFrame(base) return (P.AuraRow(base)) end

-- where the debuffs go (used for the game's row, our copied icons and the preview row)
function P.PlaceRow(o, af, w)
  local c = C()
  af:ClearAllPoints()
  local x, y = c.auraX or 0, c.auraY or 2
  local at = c.auraAt or "above"
  if o.nameOnly then at = "above" end
  if at == "undername" then
    local nameAbove = (c.nameShow and c.nameAt == "above") and not o.nameOnly
    if nameAbove then
      af:SetPoint("BOTTOM", o, "TOP", x, 2)          -- in the gap left between the lifted name and the bar
    elseif (c.nameShow or o.nameOnly) then
      af:SetPoint("TOP", o.name, "BOTTOM", x, -y)
    else
      af:SetPoint("BOTTOM", o, "TOP", x, y)
    end
  elseif at == "below" then
    local down = (c.castShow and (c.castH + 5) or 2) + (o.comboShown and 12 or 0)
    af:SetPoint("TOP", o, "BOTTOM", x, -down - y)
  elseif at == "left" then
    local lvlLeft = c.levelAt == "left" and not o.nameOnly
    af:SetPoint("RIGHT", o, "LEFT", x - (lvlLeft and 24 or 4) - (o.lead or 0) - (c.castIcon and (min(c.castH + c.h + 3, 28) + 2) or 0), y)
  elseif at == "right" then
    af:SetPoint("LEFT", o, "RIGHT", x + 6 + (o.trail or 0) + (c.quest and 18 or 0) + (c.raidAt == "right" and (c.raidSize or 18) + 4 or 0), y)
  else
    local anchor = o
    if (c.nameShow or o.nameOnly) and (c.nameAt == "above" or o.nameOnly) then anchor = o.name end
    af:SetPoint("BOTTOM", anchor, "TOP", x, y)
  end
end
local function placeAuras(o, af)
  P.PlaceRow(o, af)
  pcall(af.SetScale, af, max(0.3, (C().auraScale or 1) * (o.ccScale or 1)))
end

-- the game's shown aura buttons, left to right
function P.RowButtons(row)
  local out = {}
  if not row or not row.GetChildren then return out end
  local function scan(fr, depth)
    if depth > 2 or #out >= 16 then return end
    for _, ch in ipairs({ fr:GetChildren() }) do
      if type(ch) == "table" then
        if isAuraButton(ch) then local ok, v = pcall(ch.IsShown, ch); if ok and v and not sec(v) then out[#out + 1] = ch end
        elseif ch.GetChildren then scan(ch, depth + 1) end
      end
    end
  end
  pcall(scan, row, 0)
  -- (kept in the game's order: positions can't be read on restricted plates)
  return out
end
-- remember the game's last timer call on each of its cooldowns, so ours can repeat it
P.cdLast = setmetatable({}, { __mode = "k" })
P.cdHooked = setmetatable({}, { __mode = "k" })
P.cdAt = setmetatable({}, { __mode = "k" })
P.cdMem = setmetatable({}, { __mode = "k" })     -- cooldown -> { exp, at }: last readable end time
P.CD_METHODS = { "SetCooldown", "SetCooldownFromDurationObject", "SetCooldownFromExpirationTime", "SetCooldownDuration", "Clear" }
function P.HookCD(cd)
  if not cd or P.cdHooked[cd] or not hooksecurefunc then return end
  P.cdHooked[cd] = true
  for _, m in ipairs(P.CD_METHODS) do
    if type(cd[m]) == "function" then
      pcall(hooksecurefunc, cd, m, function(self, ...) P.cdLast[self] = { m, select("#", ...), ... }; P.cdAt[self] = GetTime() end)
    end
  end
end
-- Time left on one of the game's debuff timers, from the first place that answers:
--   game        the cooldown's own times (readable outside fights)
--   hook        the game's last SetCooldown call, if its numbers are readable
--   duration    the game's duration object (time left may be hidden: only shown, never compared)
--   remembered  the last readable end time, kept into the fight until the game re-times it
-- nil = nothing known: the game's own countdown numbers stay on.
function P.TimeLeft(cd)
  if type(cd) ~= "table" then return end
  local now = GetTime()
  local ok, st, du = pcall(cd.GetCooldownTimes, cd)
  if ok and not sec(st, du) and type(st) == "number" and type(du) == "number" then
    if du > 0 and st > 0 then
      local exp = (st + du) / 1000
      P.cdMem[cd] = { exp = exp, at = now }
      return exp - now, "game"
    end
    if not combat() then P.cdMem[cd] = nil; return 0, "none" end
  end
  -- a readable end time we saw, and the game hasn't re-timed it since
  local m = P.cdMem[cd]
  if m and not (P.cdAt[cd] and P.cdAt[cd] > m.at) then
    local r = m.exp - now
    if r > -0.5 then return r, "remembered" end
  end
  local L = P.cdLast[cd]
  if L then
    if L[1] == "Clear" then return 0, "none" end
    if L[1] == "SetCooldown" and not sec(L[3], L[4]) and type(L[3]) == "number" and type(L[4]) == "number" and L[4] > 0 and L[3] + L[4] - now > -0.5 then
      return L[3] + L[4] - now, "hook"
    end
    if L[1] == "SetCooldownFromExpirationTime" and not sec(L[3]) and type(L[3]) == "number" and L[3] - now > -0.5 then return L[3] - now, "hook" end
    local d = L[3]
    if L[1] == "SetCooldownFromDurationObject" and type(d) == "table" then
      local r = d.GetRemainingDuration and try(d.GetRemainingDuration, d)
      if not isNil(r) then return r, "duration" end
    end
  end
end
local function timeText(r)
  if isNil(r) then return "" end
  if sec(r) then return fmt("%.0f", r) or "" end
  if r <= 0 then return "" end
  if r >= 3600 then return floor(r / 3600 + 0.5) .. "h" end
  if r >= 60 then return floor(r / 60 + 0.5) .. "m" end
  if r < 3 then return string.format("%.1f", r) end
  return tostring(floor(r + 0.5))
end
P.timeText = timeText
-- our countdown number on a debuff (a game button or one of our copied icons)
P.numbers = setmetatable({}, { __mode = "k" })
function P.Number(btn, cd, size)
  local c = C()
  local h = P.numbers[btn]
  if not h then
    local okF, f = pcall(CreateFrame, "Frame", nil, btn)
    if not okF or not f then return end
    f:SetAllPoints(btn)
    local okL, lvl = pcall(btn.GetFrameLevel, btn)
    if okL and type(lvl) == "number" and not sec(lvl) then pcall(f.SetFrameLevel, f, lvl + 10) end
    h = { f = f, fs = f:CreateFontString(nil, "OVERLAY") }
    P.numbers[btn] = h
  end
  local fs = h.fs
  setFont(fs, size or c.auraNumSize or 10)
  fs:ClearAllPoints()
  if c.auraNumAt == "bottom" then fs:SetPoint("TOP", h.f, "BOTTOM", 0, 1) elseif c.auraNumAt == "top" then fs:SetPoint("BOTTOM", h.f, "TOP", 0, -1)
  else fs:SetPoint("CENTER", h.f, "CENTER", 0, 0) end
  local mine = c.auraNumbers == "cc"
  local r, how = nil, nil
  if mine then r, how = P.TimeLeft(cd) end
  h.how = how
  local ours = mine and not isNil(r) and how ~= "none"
  -- the game's own numbers: off while ours show, back on when we know nothing
  if type(cd) == "table" and cd.SetHideCountdownNumbers then
    local hideGame = (c.auraNumbers == "off") or ours or (mine and how == "none")
    if h.hid ~= hideGame then h.hid = hideGame; pcall(cd.SetHideCountdownNumbers, cd, hideGame) end
  end
  if not ours then fs:SetText(""); return how end
  setText(fs, timeText(r))
  if not sec(r) and r < 5 then fs:SetTextColor(1, 0.3, 0.2) else fs:SetTextColor(1, 1, 1) end
  return how
end
-- numbers on the game's own row (move mode)
function P.RowNumbers(o)
  local c = C()
  if c.auraMode ~= "move" or o.fake or o.nameOnly then return end
  local row = auraFrame(o.base)
  if not row then return end
  local size = max(7, floor((c.auraNumSize or 10)))
  local free = not combat()
  if free then P.ClickThrough(row) end
  for _, btn in ipairs(P.RowButtons(row)) do
    local cd = nth(btn, "Cooldown") or nth(btn, "cooldown")
    P.HookCD(cd)
    P.Number(btn, cd, size)
    if free then P.ClickThrough(btn) end
  end
end
local function auraIcon(o, i)
  o.auras = o.auras or {}
  local b = o.auras[i]
  if b then return b end
  b = CreateFrame("Frame", nil, o.over)
  b.edge = b:CreateTexture(nil, "BACKGROUND"); b.edge:SetPoint("TOPLEFT", -1, 1); b.edge:SetPoint("BOTTOMRIGHT", 1, -1); b.edge:SetTexture(WHITE)
  b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetAllPoints(); b.icon:SetTexCoord(0.08, 0.92, 0.2, 0.8)
  b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
  b.cd:SetAllPoints()
  if b.cd.SetDrawEdge then b.cd:SetDrawEdge(false) end
  if b.cd.SetReverse then b.cd:SetReverse(true) end
  b.count = b:CreateFontString(nil, "OVERLAY"); b.count:SetPoint("BOTTOMRIGHT", 2, -2)
  b:Hide()
  o.auras[i] = b
  return b
end
-- copy mode: our icons show what the game's buttons show (values pass widget to widget)
function P.CopyAuras(o)
  local c = C()
  local list = {}
  if c.auraMode == "copy" and not o.nameOnly and not o.fake then list = P.RowButtons(auraFrame(o.base)) end
  if o.fake and c.auraMode ~= "off" then list = o.fake.debuffs or {} end
  local n = min(#list, c.auraMax or 6)
  local sz = max(10, floor((c.auraSize or 20) * (c.auraScale or 1)))
  local th = UI:Theme()
  local row = o.auraRow
  if not row then row = CreateFrame("Frame", nil, o.over); o.auraRow = row end
  row:SetSize(max(1, n * (sz + 3) - 3), floor(sz * 0.75))
  P.PlaceRow(o, row)
  for i = 1, max(n, #(o.auras or {})) do
    local b = auraIcon(o, i)
    if i <= n then
      local src = list[i]
      b:SetSize(sz, floor(sz * 0.75))
      b:ClearAllPoints(); b:SetPoint("LEFT", row, "LEFT", (i - 1) * (sz + 3), 0)
      setFont(b.count, max(7, floor(sz * 0.5)))
      b.edge:SetVertexColor(0, 0, 0, 1)
      if o.fake then
        b.icon:SetTexture(src.icon); b.count:SetText(src.count or "")
        b.edge:SetVertexColor(th.edge[1], th.edge[2], th.edge[3], 1)
        if c.auraTimer and b.cd.SetCooldown then pcall(b.cd.SetCooldown, b.cd, GetTime() - (src.gone or 3), src.dur or 12) end
        local h = P.numbers[b] or (P.Number(b, nil) and P.numbers[b]) or P.numbers[b]
        if h then
          setFont(h.fs, c.auraMode == "copy" and max(7, floor(sz * 0.5)) or (c.auraNumSize or 10))
          h.fs:ClearAllPoints()
          if c.auraNumAt == "bottom" then h.fs:SetPoint("TOP", h.f, "BOTTOM", 0, 1) elseif c.auraNumAt == "top" then h.fs:SetPoint("BOTTOM", h.f, "TOP", 0, -1)
          else h.fs:SetPoint("CENTER", h.f, "CENTER") end
          src.t0 = src.t0 or GetTime()
          local left = (src.dur or 12) - (src.gone or 3) - ((GetTime() - src.t0) % (src.dur or 12))
          h.fs:SetText(c.auraNumbers == "off" and "" or timeText(left)); h.fs:SetTextColor(1, 1, 1)
        end
      else
        local ic = src.Icon or src.icon
        pcall(function() b.icon:SetTexture(ic:GetTexture()) end)
        local cnt = src.Count or src.count or (src.CountFrame and src.CountFrame.Count)
        if type(cnt) == "table" and cnt.GetText then pcall(function() b.count:SetText(cnt:GetText()) end) else b.count:SetText("") end
        local bor = src.Border or src.border
        if type(bor) == "table" and bor.GetVertexColor then pcall(function() b.edge:SetVertexColor(bor:GetVertexColor()) end) end
        local cd = src.Cooldown or src.cooldown
        P.HookCD(cd)
        local last = P.cdLast[cd]
        local swiped
        if c.auraTimer then
          local ok, st, du = pcall(cd.GetCooldownTimes, cd)
          if ok and not sec(st, du) and type(st) == "number" and type(du) == "number" and du > 0 then
            if b.ccSt ~= st or b.ccDu ~= du then b.ccSt, b.ccDu = st, du; pcall(b.cd.SetCooldown, b.cd, st / 1000, du / 1000) end
            swiped = true
          elseif last and type(b.cd[last[1]]) == "function" and P.cdAt[cd] ~= b.ccAt then
            b.ccAt = P.cdAt[cd]; b.ccSt = nil
            pcall(b.cd[last[1]], b.cd, select(3, unpack(last, 1, last[2] + 2)))
            swiped = true
          elseif last then swiped = true end
        end
        if not swiped and b.cd.Clear and not c.auraTimer then b.cd:Clear() end
        if b.cd.SetHideCountdownNumbers then pcall(b.cd.SetHideCountdownNumbers, b.cd, true) end
        if c.auraNumbers == "cc" then
          local how = P.Number(b, cd, max(7, floor(sz * 0.5)))
          b.how = how
        elseif P.numbers[b] then P.numbers[b].fs:SetText("") end
      end
      b:Show()
    else b:Hide() end
  end
end
function P.BorrowAuras(o)
  local c = C()
  local af = auraFrame(o.base)
  if af then
    if c.auraMode == "move" then P.Pin(o, af, placeAuras) else P.Unpin(af) end
  end
  guard(P.CopyAuras, o)
  guard(P.RowNumbers, o)
end
local function placeRaid(o, rf)
  local c = C()
  rf:ClearAllPoints()
  rf:SetPoint("CENTER", o.raid, "CENTER")
  pcall(rf.SetScale, rf, max(0.3, min(4, (c.raidSize or 18) / 18)))   -- the game's icon is about 18 px
end
P.RAID_KEYS = { "RaidTargetFrame", "raidTargetFrame", "RaidTargetIcon", "raidTargetIcon", "RaidIcon", "raidIcon" }
function P.GameRaidIcon(base)
  local uf = blizzUF(base)
  if not uf then return end
  for _, k in ipairs(P.RAID_KEYS) do
    local r = nth(uf, k)
    if type(r) == "table" and r.SetPoint then return r, k end
  end
  local nf = nth(uf, "name") or nth(uf, "healthBar")
  for _, k in ipairs(P.RAID_KEYS) do
    local r = type(nf) == "table" and nth(nf, k)
    if type(r) == "table" and r.SetPoint then return r, k end
  end
end
function P.BorrowRaid(o, on)
  local rf = P.GameRaidIcon(o.base)
  if not rf then return false end
  if on then P.Pin(o, rf, placeRaid) elseif P.borrowed[rf] and P.borrowed[rf].o then P.Unpin(rf) end
  return true
end
-- borrowed regions follow our plate's alpha (they ignore the invisible parent's)
function P.FollowAlpha(o)
  local a = o:GetEffectiveAlpha() or 1
  for r, b in pairs(P.borrowed) do
    if b.o == o and r.SetAlpha then pcall(r.SetAlpha, r, a) end
  end
end

-- r27: how far our plate reaches above / below the bar's middle and past its ends (unscaled px): bar, name above or
-- below, debuffs under the name, creature frames' edge bands and end pieces
function P.ClickBox(c)
  c = c or C()
  local up, down, side = c.h / 2, c.h / 2, 0
  if c.nameShow then
    local nh = (c.fontSize or 10) + 4
    if c.nameAt == "above" then up = up + nh + P.NameLift({}) elseif c.nameAt == "below" then down = down + nh end
  end
  if c.frames then
    local _, _, _, u = P.GWSet(c.frameSize)
    local t = P.GWSet(c.frameSize)
    local k = (c.h - 2 * max(1, c.h * 0.07)) / P.GW.H * u
    local lift = P.GW.railTop * t * k
    up, down, side = up + lift, down + lift, P.GW.lead * t * k
  end
  return up, down, side
end
-- the bar sits this far from the game plate's middle (game plate px) so the click box covers name + bar evenly
function P.PlaceOn(o, base)
  base = base or o.base
  if not base then return end
  local y = (P.plateY or 0) / max(0.2, o.ccScale or o.baseScale or 1)
  if o.ccY == y then return end
  o.ccY = y
  o:ClearAllPoints(); o:SetPoint("CENTER", base, "CENTER", 0, y)
end
-- make the game's plate as big as ours, so clicking our plate selects the unit; the game stacks plates by this size,
-- so it must cover everything we draw or stacked plates overlap and clicks land on the wrong one (r27)
function P.ClickArea()
  local c = C()
  if not (c.on and c.clickMatch) or not C_NamePlate then
    if P.plateY and P.plateY ~= 0 then P.plateY = 0; for _, o in pairs(P.plates) do P.PlaceOn(o) end end
    return
  end
  if combat() then P.pendingClick = true return end
  local up, down, side = P.ClickBox(c)
  local sc = c.scale or 1
  local w = (c.w + 2 * side) * sc + 6
  local h = (up + down) * sc + 4
  if not P.sizeHome then
    local ew, eh = try(C_NamePlate.GetNamePlateEnemySize)
    local fw, fh = try(C_NamePlate.GetNamePlateFriendlySize)
    P.sizeHome = { ew = ew, eh = eh, fw = fw, fh = fh }
  end
  if C_NamePlate.SetNamePlateEnemySize then try(C_NamePlate.SetNamePlateEnemySize, w, h) end
  if C_NamePlate.SetNamePlateFriendlySize then try(C_NamePlate.SetNamePlateFriendlySize, w, h) end
  -- the old size API also moved the click box; without it (this client) the hit-test points follow our plate (r28)
  P.plateY = C_NamePlate.SetNamePlateEnemySize and (down - up) / 2 * sc or 0
  for _, o in pairs(P.plates) do P.PlaceOn(o) end
end
function P.ClickAreaBack()
  local h = P.sizeHome
  if not h or combat() or not C_NamePlate then return end
  if h.ew and C_NamePlate.SetNamePlateEnemySize then try(C_NamePlate.SetNamePlateEnemySize, h.ew, h.eh) end
  if h.fw and C_NamePlate.SetNamePlateFriendlySize then try(C_NamePlate.SetNamePlateFriendlySize, h.fw, h.fh) end
  P.plateY = 0
  for _, o in pairs(P.plates) do P.PlaceOn(o) end
end

---------------------------------------------------------------------------
-- Plates coming and going
---------------------------------------------------------------------------
function P.Enabled() return S.db and C().on and true or false end
function P.Full(o)
  o.nameOnly = P.IsNameOnly(o)
  guard(P.Layout, o)
  guard(P.UpdateName, o)
  guard(P.UpdateHealth, o)
  guard(P.UpdateRaid, o)
  guard(P.UpdateQuest, o)
  guard(P.UpdateCombo, o)
  guard(P.UpdateTarget, o)
  guard(P.UpdateThreat, o)
  if o.fake then if o.fake.cast then guard(P.CastStart, o) else o.cast:Hide() end
  else guard(P.CastStart, o) end
  if o.fake then guard(P.CopyAuras, o) else guard(P.BorrowAuras, o); guard(P.HitArea, o) end
end

local function plateUnit(base)
  if not base then return end
  local u = base.namePlateUnitToken or (base.UnitFrame and base.UnitFrame.unit)
  if type(u) == "string" and not sec(u) then return u end
end
function P.Add(u)
  if not P.Enabled() or not C_NamePlate then return end
  local base = try(C_NamePlate.GetNamePlateForUnit, u)
  if type(base) ~= "table" then return end
  if bool(try(UnitIsUnit, u, "player")) then return end   -- personal resource bar stays the game's
  local o = P.plates[base]
  if not o then o = P.Build(base); o.base = base; P.plates[base] = o end
  if o.unit and P.byUnit[o.unit] == o then P.byUnit[o.unit] = nil end
  o.unit = u
  o.questWas = nil
  o.looted = nil
  P.byUnit[u] = o
  o.ccScale, o.ccAlpha, o.ccLvl, o.castY, o.ccY = nil, nil, nil, nil, nil
  P.PlaceOn(o, base)
  P.HideBlizz(o)
  P.Full(o)
  o:Show()
  guard(P.UpdateCorpse, o)
end
function P.Remove(u)
  local o = P.byUnit[u]
  if not o then return end
  P.byUnit[u] = nil
  P.CastStop(o)
  for _, b in ipairs(o.auras or {}) do b:Hide() end
  o:Hide()
  o.unit = nil
  corpseOff(o); o:Hide()
end
function P.ScanAll()
  if not C_NamePlate or not C_NamePlate.GetNamePlates then return end
  for _, base in ipairs(try(C_NamePlate.GetNamePlates) or {}) do
    local u = plateUnit(base)
    if u then P.Add(u) end
  end
end
-- settings changed: redraw everything (plates + preview)
function P.Refresh()
  P.curves = {}
  if P.Enabled() then
    for u in pairs(P.byUnit) do P.Add(u) end
    P.ScanAll()
    P.ClickArea()
  end
  if P.UpdatePreview then P.UpdatePreview() end
end
function P.SetEnabled(on)
  C().on = on and true or false
  if on then
    P.ScanAll(); P.ClickArea()
    S:Print("CCPlates on.")
  else
    for base, o in pairs(P.plates) do
      corpseOff(o); o:Hide(); P.CastStop(o)
      P.ShowBlizz(o); P.HitAreaBack(o)
      local af = auraFrame(base); if af then P.Unpin(af) end
      local uf = blizzUF(base); if uf and uf.RaidTargetFrame then P.Unpin(uf.RaidTargetFrame) end
      o.unit = nil
    end
    wipe(P.byUnit)
    P.ClickAreaBack()
    S:Print("CCPlates off - the game's nameplates are back. A /reload puts their debuff row back exactly where it was.")
  end
  if P.UpdatePreview then P.UpdatePreview() end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
S:On("NAME_PLATE_UNIT_ADDED", function(_, u) P.forbid[u] = nil; P.Add(u) end)
S:On("NAME_PLATE_UNIT_REMOVED", function(_, u) P.Remove(u) end)
-- plates the game locks away from addons (friendly plates in dungeons / raids): counted for the debug line only
P.forbid = {}
S:On("FORBIDDEN_NAME_PLATE_UNIT_ADDED", function(_, u) if u then P.forbid[u] = true end end)
S:On("FORBIDDEN_NAME_PLATE_UNIT_REMOVED", function(_, u) if u then P.forbid[u] = nil end end)
local function each(fn) for _, o in pairs(P.byUnit) do guard(fn, o) end end
local function one(u, fn) local o = u and P.byUnit[u]; if o then guard(fn, o) end end
S:On("PLAYER_TARGET_CHANGED", function()
  each(P.UpdateTarget); each(P.UpdateCombo); each(P.BorrowAuras)
end)
S:On("UPDATE_MOUSEOVER_UNIT", function() each(P.UpdateTarget) end)
for _, ev in ipairs({ "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_HEALTH_FREQUENT", "UNIT_THREAT_SITUATION_UPDATE", "UNIT_THREAT_LIST_UPDATE", "UNIT_FLAGS" }) do
  S:On(ev, function(_, u) one(u, P.UpdateHealth); one(u, P.UpdateCorpse) end)
end
-- r36: opening loot marks the dead plate you're looting (target / mouse-over) as looted
S:On("LOOT_OPENED", function()
  for _, o in pairs(P.byUnit) do
    if o.corpse and o.unit and (bool(try(UnitIsUnit, o.unit, "target")) or bool(try(UnitIsUnit, o.unit, "mouseover")) or bool(try(UnitIsUnit, o.unit, "npc"))) then o.looted = true end
  end
  each(P.UpdateCorpse)
end)
for _, ev in ipairs({ "LOOT_CLOSED", "LOOT_SLOT_CLEARED" }) do
  S:On(ev, function() each(P.UpdateCorpse) end)
end
S:On("UNIT_CLASSIFICATION_CHANGED", function(_, u) local o = u and P.byUnit[u]; if o then P.Full(o) end end)
for _, ev in ipairs({ "UNIT_NAME_UPDATE", "UNIT_LEVEL" }) do
  S:On(ev, function(_, u) one(u, P.UpdateName) end)
end
S:On("UNIT_FACTION", function(_, u) local o = u and P.byUnit[u]; if o then P.Full(o) end end)
S:On("RAID_TARGET_UPDATE", function() each(P.UpdateRaid) end)
S:On("UNIT_AURA", function(_, u)
  local o = u and P.byUnit[u]
  if not o or C().auraMode == "off" then return end
  if C_Timer and C_Timer.After then C_Timer.After(0, function() if P.byUnit[u] == o then guard(P.BorrowAuras, o) end end)
  else guard(P.BorrowAuras, o) end
end)
S:On("QUEST_LOG_UPDATE", function() if not combat() then each(P.UpdateQuest) end end)
S:On("UNIT_QUEST_LOG_CHANGED", function() if not combat() then each(P.UpdateQuest) end end)
S:On("UNIT_POWER_UPDATE", function(_, u) if u == "player" then each(P.UpdateCombo) end end)
S:On("UNIT_POWER_FREQUENT", function(_, u) if u == "player" then each(P.UpdateCombo) end end)
S:On("PLAYER_REGEN_DISABLED", function() each(P.UpdateHealth) end)
S:On("PLAYER_REGEN_ENABLED", function()
  each(P.UpdateHealth)
  if P.pendingClick then P.pendingClick = nil; P.ClickArea() end
  if P.pendingHit then P.pendingHit = nil; for _, o in pairs(P.plates) do if o.unit then P.HitArea(o) end end end
  if P.pendingCVars then local f = P.pendingCVars; P.pendingCVars = nil; f() end
end)
for _, ev in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_UPDATE",
  "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" }) do
  S:On(ev, function(_, u) one(u, P.CastStart) end)
end
S:On("UNIT_SPELLCAST_STOP", function(_, u) local o = u and P.byUnit[u]; if o then P.CastStop(o, false) end end)
S:On("UNIT_SPELLCAST_CHANNEL_STOP", function(_, u) local o = u and P.byUnit[u]; if o then P.CastStop(o, false) end end)
S:On("UNIT_SPELLCAST_FAILED", function(_, u) local o = u and P.byUnit[u]; if o then P.CastStop(o, true) end end)
S:On("UNIT_SPELLCAST_INTERRUPTED", function(_, u) local o = u and P.byUnit[u]; if o then P.CastStop(o, true) end end)
S:On("SPELLS_CHANGED", function() P.kickAt = nil end)
S:On("UPDATE_SHAPESHIFT_FORM", function() each(P.UpdateHealth) end)

-- light ticker: borrowed regions follow our alpha, kick-ready colour on running casts, threat
local tick = CreateFrame("Frame")
tick.t, tick.slow = 0, 0
tick:SetScript("OnUpdate", function(self, el)
  self.t = self.t + el
  if self.t < 0.2 then return end
  self.slow = self.slow + self.t
  self.t = 0
  if not P.Enabled() then return end
  local doSlow = self.slow >= 0.6
  if doSlow then self.slow = 0 end
  for _, o in pairs(P.byUnit) do
    if o.corpse then
      if doSlow then guard(P.UpdateCorpse, o) end
    elseif o:IsShown() then
      guard(P.UpdateTarget, o)
      guard(P.UpdateThreat, o)
      P.FollowAlpha(o)
      if C().auraMode == "copy" then guard(P.CopyAuras, o) else guard(P.RowNumbers, o) end
      if doSlow then
        if o.cast:IsShown() and not o.cast.ccFading and C().castReady then
          local _, _, _, _, _, notInt, ch = REAL.cast(o.unit)
          guard(function() castColor(o, notInt, ch) end, o)
        end
        if combat() then guard(P.UpdateHealth, o) end
        guard(P.UpdateRaid, o)
      end
    end
  end
end)

-- theme changes repaint the plates
S:Listen("LOGIN", function()
  P.themeProxy = P.themeProxy or {}
  UI:Skin(P.themeProxy, function() if S.db then P.Refresh() end end)
  if P.Enabled() then C_Timer.After(0.5, function() P.ScanAll(); P.ClickArea() end) end
end)

---------------------------------------------------------------------------
-- The game's own nameplate options (CVars), only changed out of combat
---------------------------------------------------------------------------
P.CVARS = {
  { key = "nameplateShowEnemies", label = "Show enemy nameplates", tip = "The game's switch (V)." },
  { key = "nameplateShowFriends", label = "Show friendly nameplates", tip = "Shift+V in the game." },
  { key = "nameplateShowAll", label = "Show nameplates all the time", tip = "Off = only in a fight / when you look at them (game option)." },
}
local function getCVar(k)
  local v = (C_CVar and C_CVar.GetCVar and try(C_CVar.GetCVar, k)) or (GetCVar and try(GetCVar, k))
  return v
end
local function setCVar(k, v)
  local function doit()
    if C_CVar and C_CVar.SetCVar then try(C_CVar.SetCVar, k, tostring(v)) elseif SetCVar then try(SetCVar, k, tostring(v)) end
  end
  if combat() then
    local prev = P.pendingCVars
    P.pendingCVars = function() if prev then prev() end doit() end
    S:Print("CCPlates: the game's nameplate options change when the fight ends.")
  else doit() end
end
P.getCVar, P.setCVar = getCVar, setCVar

---------------------------------------------------------------------------
-- Settings window with a live preview
---------------------------------------------------------------------------
local win
local WIN_W, WIN_H, PREV_W = 1120, 660, 300
local FAKES = {
  { label = "Your target, casting", d = { name = "Defias Pillager", level = 18, cl = "elite", hp = 72, hostile = true, target = true, threat = 3, tpct = 100,
      debuffs = { { icon = "Interface\\Icons\\Spell_Shadow_ShadowWordPain", dur = 18, gone = 4 }, { icon = "Interface\\Icons\\Ability_Rogue_Rupture", dur = 12, gone = 7 },
        { icon = "Interface\\Icons\\Ability_Warrior_Sunder", dur = 30, gone = 2, count = "3" } },
      cast = { name = "Fireball", icon = 135812, len = 3 }, kickReady = true, combo = 3, combat = true, raid = 8 } },
  { label = "In execute range", d = { name = "Murloc Tidehunter", level = 16, cl = "normal", ctype = "Humanoid", icon = "Interface\\Icons\\INV_Misc_Head_Murloc_01", hp = 14, hostile = true, threat = 1, tpct = 92, combat = true, quest = true,
      debuffs = { { icon = "Interface\\Icons\\Spell_Nature_Slow", dur = 15, gone = 9 } } } },
  { label = "Rare elite, can't be interrupted", d = { name = "Old Murk-Eye", level = 20, cl = "rareelite", hp = 100, hostile = true,
      cast = { name = "Mind Flay", icon = 136208, len = 4, notInt = true, channel = true }, raid = 1 } },
  { label = "Neutral", d = { name = "Stonetusk Boar", level = 9, cl = "normal", ctype = "Beast", icon = "Interface\\Icons\\Ability_Hunter_Pet_Boar", hp = 100, neutral = true } },
  { label = "Friendly player", d = { name = "Fatedfr", level = 60, hp = 100, player = true, class = "SHAMAN", friendly = true } },
}
local function fakeSource(d)
  local f = {}
  f.health = function() return d.hp, 100 end
  f.pct = function() return d.hp end
  f.name = function() return d.name end
  f.level = function() return d.level, d.cl end
  f.isPlayer = function() return d.player and true or false end
  f.ctype = function() return d.ctype end
  f.icon = d.icon
  f.class = function() return d.class end
  f.reaction = function() return d.hostile and 2 or d.neutral and 4 or 5 end
  f.canAttack = function() return (d.hostile or d.neutral) and true or false end
  f.tapped = function() return false end
  f.threat = function() return d.threat end
  f.aggro = function() return d.threat == 3 end
  f.threatPct = function() return d.tpct end
  f.dead = function() return d.dead and true or false end
  f.lootable = function() return d.loot and true or false end
  f.grouped = function() return true end
  f.isTarget = function() return d.target and true or false end
  f.isMouse = function() return false end
  f.anyTarget = function() return true end
  f.raid = function() return d.raid end
  f.combat = function() return d.combat and true or false end
  f.dead = function() return false end
  f.combo = function() if d.combo then return d.combo, 5 end end
  f.quest = function() return d.quest and true or false end
  f.cast = function()
    local c = d.cast
    if not c then return end
    local now = GetTime() * 1000
    d.castAt = d.castAt or now
    if now - d.castAt > (c.len + 0.8) * 1000 then d.castAt = now end
    return c.name, c.name, c.icon, d.castAt, d.castAt + c.len * 1000, c.notInt and true or false, c.channel and true or false
  end
  f.tank = false
  f.kickReady = d.kickReady
  f.debuffs = d.debuffs
  return f
end

function P.UpdatePreview()
  if not win or not win:IsShown() then return end
  for _, pv in ipairs(P.previews) do
    pv.o.fake.tank = P.IsTank()
    P.Full(pv.o)
    pv.o.cast.ccLoop = pv.o.fake.cast ~= nil
  end
  if win.Sync then win.Sync() end
end

local function pickColor2(r, g, b, onChange)
  local CP = ColorPickerFrame
  if not CP then return end
  if CP.SetFrameStrata then CP:SetFrameStrata("FULLSCREEN_DIALOG") end
  local function now() local nr, ng, nb = CP:GetColorRGB(); onChange(nr, ng, nb) end
  local function cancel(prev)
    if type(prev) == "table" and prev.r then onChange(prev.r, prev.g, prev.b)
    elseif CP.GetPreviousValues then local pr, pg, pb = CP:GetPreviousValues(); if pr then onChange(pr, pg, pb) end
    else onChange(r, g, b) end
  end
  if CP.SetupColorPickerAndShow then
    CP:SetupColorPickerAndShow({ r = r, g = g, b = b, hasOpacity = false, swatchFunc = now, cancelFunc = cancel })
  else
    CP.func, CP.cancelFunc, CP.opacityFunc = now, cancel, nil
    CP.hasOpacity, CP.previousValues = false, { r = r, g = g, b = b }
    CP:SetColorRGB(r, g, b); CP:Hide(); CP:Show()
  end
end
local function swatch(parent, x, y, label, getRGB, set, tip)
  local b = CreateFrame("Button", nil, parent, BACKDROP_T)
  b:SetSize(20, 20); b:SetPoint("TOPLEFT", x, y)
  if b.SetBackdrop then b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 }); b:SetBackdropColor(0, 0, 0, 1); b:SetBackdropBorderColor(0.5, 0.5, 0.5, 1) end
  b.fill = b:CreateTexture(nil, "ARTWORK"); b.fill:SetPoint("TOPLEFT", 2, -2); b.fill:SetPoint("BOTTOMRIGHT", -2, 2); b.fill:SetTexture(WHITE)
  b.label = UI:Text(parent, label, "small"); b.label:SetPoint("LEFT", b, "RIGHT", 6, 0)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  function b:Refresh() local r, g, bl = getRGB(); self.fill:SetVertexColor(r, g, bl) end
  b:SetScript("OnClick", function(self, btn)
    if btn == "RightButton" then set(nil); self:Refresh() return end
    local r, g, bl = getRGB()
    pickColor2(r, g, bl, function(nr, ng, nb) set({ nr, ng, nb }); self:Refresh() end)
  end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine(label, 1, 1, 1)
    if tip then GameTooltip:AddLine(tip, 0.8, 0.8, 0.8, true) end
    GameTooltip:AddLine("Left-click: pick a colour   Right-click: back to normal", 0.6, 0.6, 0.6, true); GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b:Refresh()
  return b
end

local function buildWindow()
  win = UI:Window("CC_Plates", "CCPlates  |cff888888- nameplates|r", WIN_W, WIN_H)
  local ctl = {}           -- every control with a :Sync()
  win.ctl = ctl
  local function changed(layoutOnly) P.Refresh() end
  local function set(key, v) C()[key] = v; changed() end
  local function check(p, x, y, label, key, tip, after)
    local b = UI:Check(p, label, C()[key], function(v) C()[key] = v; if after then after(v) end; changed() end, tip)
    b:SetPoint("TOPLEFT", x, y)
    ctl[#ctl + 1] = function() b:SetChecked(C()[key] and true or false) end
    return b
  end
  local function slider(p, x, y, label, key, lo, hi, step, f, w)
    local s = UI:Slider(p, w or 360, label, lo, hi, step, C()[key], function(v) C()[key] = v; changed() end, f)
    s:SetPoint("TOPLEFT", x, y)
    ctl[#ctl + 1] = function() s:SetValue(C()[key]) end
    return s
  end
  local function pctSlider(p, x, y, label, key, lo, hi, w)
    local s = UI:Slider(p, w or 360, label, lo, hi, 5, floor(C()[key] * 100 + 0.5), function(v) C()[key] = v / 100; changed() end, function(v) return v .. "%" end)
    s:SetPoint("TOPLEFT", x, y)
    ctl[#ctl + 1] = function() s:SetValue(floor(C()[key] * 100 + 0.5)) end
    return s
  end
  local function drop(p, x, y, label, key, opts, w, after)
    local l = UI:Text(p, label, "small"); l:SetPoint("TOPLEFT", x, y - 5)
    local d = UI:Dropdown(p, w or 180, opts, C()[key], function(v) C()[key] = v; if after then after(v) end; changed() end)
    d:SetPoint("TOPLEFT", x + 136, y)
    ctl[#ctl + 1] = function() d:SetValue(C()[key]) end
    return d
  end
  local function note(p, x, y, text, w)
    local t = UI:Text(p, text, "small"); t:SetPoint("TOPLEFT", x, y); t:SetWidth(w or 560); t:SetJustifyH("LEFT")
    t:SetTextColor(0.65, 0.65, 0.65)
    return t
  end
  local function head(p, x, y, text) local h = UI:Text(p, text, "normal"); h:SetPoint("TOPLEFT", x, y); UI:Skin(h, function(self, th) self:SetTextColor(th.gold[1], th.gold[2], th.gold[3]) end); return h end

  -- r33 settings revamp (user 23:24 "revamp all the settings, consolidate everything better, group it together better,
  -- make it all simple and very user friendly, easy to look at and less intimidating"): 8 tabs instead of 10, every
  -- tab = two columns of titled cards, short labels, the details in tooltips instead of paragraphs.
  local onB = UI:Check(win, "Use CCPlates nameplates", C().on, function(v) P.SetEnabled(v) end,
    "Draws Command Center's plates over the game's. Turn nameplates on with V (enemies) and Shift+V (friends).")
  onB:SetPoint("TOPLEFT", 18, -46)
  ctl[#ctl + 1] = function() onB:SetChecked(C().on) end
  local tipT = UI:Text(win, "Hover any option for what it does. The preview on the right updates as you go.", "small")
  tipT:SetPoint("LEFT", onB.label, "RIGHT", 24, 0); tipT:SetTextColor(0.55, 0.55, 0.55)

  local area = CreateFrame("Frame", nil, win)
  area:SetPoint("TOPLEFT", 18, -110); area:SetPoint("BOTTOMRIGHT", -(PREV_W + 30), 30)
  local panes = {}
  local names = { "Style", "Text", "Target", "Combat", "Icons", "Debuffs", "Colours", "More" }
  for i = 1, #names do
    local p = CreateFrame("Frame", nil, area); p:SetAllPoints(); p:Hide(); panes[i] = p
  end
  local tabs = UI:SubTabs(win, names, function(i) for j, p in ipairs(panes) do p:SetShown(j == i) end; win.tab = i end)
  win.tabs = tabs
  tabs:SetPoint("TOPLEFT", 18, -76); tabs:SetPoint("RIGHT", win, "RIGHT", -(PREV_W + 30), 0)

  -- a column of cards: each card = a soft panel with a gold title; controls stack down it
  local COLW = 368
  local function column(p, x)
    local c = { p = p, x = x, y = 0 }
    function c:card(title)
      self.cardTop = self.y
      local bg = p:CreateTexture(nil, "BACKGROUND"); bg:SetTexture(WHITE); bg:SetVertexColor(1, 1, 1, 0.035)
      local line = p:CreateTexture(nil, "BORDER"); line:SetTexture(WHITE); line:SetHeight(1)
      UI:Skin(line, function(t, th) t:SetVertexColor(th.gold[1], th.gold[2], th.gold[3], 0.45) end)
      local h = UI:Text(p, title, "normal"); h:SetPoint("TOPLEFT", self.x + 10, self.y - 8)
      UI:Skin(h, function(t, th) t:SetTextColor(th.gold[1], th.gold[2], th.gold[3]) end)
      line:SetPoint("TOPLEFT", self.x + 10, self.y - 26); line:SetPoint("TOPRIGHT", p, "TOPLEFT", self.x + COLW - 10, self.y - 26)
      self.bg = bg
      self.y = self.y - 34
      return self
    end
    function c:done()
      local bg = self.bg
      if bg then bg:SetPoint("TOPLEFT", self.x, self.cardTop); bg:SetPoint("BOTTOMRIGHT", p, "TOPLEFT", self.x + COLW, self.y - 4) end
      self.y = self.y - 14
      return self
    end
    local X = function(self) return self.x + 10 end
    function c:check(label, key, tip, after) check(p, X(self), self.y, label, key, tip, after); self.y = self.y - 26; return self end
    function c:checks(a, b)       -- two short checks on one line
      check(p, X(self), self.y, a[1], a[2], a[3], a[4]); check(p, X(self) + 172, self.y, b[1], b[2], b[3], b[4]); self.y = self.y - 26; return self
    end
    function c:slider(label, key, lo, hi, step, f) slider(p, X(self), self.y, label, key, lo, hi, step, f, COLW - 20); self.y = self.y - 28; return self end
    function c:pct(label, key, lo, hi) pctSlider(p, X(self), self.y, label, key, lo, hi, COLW - 20); self.y = self.y - 28; return self end
    function c:drop(label, key, opts, after) drop(p, X(self), self.y, label, key, opts, COLW - 156, after); self.y = self.y - 30; return self end
    function c:note(text) local t = note(p, X(self), self.y + 2, text, COLW - 20); self.y = self.y - (t.GetStringHeight and max(14, (t:GetStringHeight() or 14)) or 14) - 6; return self end
    function c:swatch(label, key, tip)
      win.swatches[#win.swatches + 1] = swatch(p, X(self), self.y, label, function() return col(key) end, function(v) C().col[key] = v; changed() end, tip)
      self.y = self.y - 26; return self
    end
    function c:swatches(a, b)     -- two colours on one line
      win.swatches[#win.swatches + 1] = swatch(p, X(self), self.y, a[1], function() return col(a[2]) end, function(v) C().col[a[2]] = v; changed() end, a[3])
      if b then win.swatches[#win.swatches + 1] = swatch(p, X(self) + 172, self.y, b[1], function() return col(b[2]) end, function(v) C().col[b[2]] = v; changed() end, b[3]) end
      self.y = self.y - 26; return self
    end
    return c
  end
  local L, R = 0, COLW + 18
  local signed = function(v) return (v > 0 and "+" or "") .. v end
  win.swatches = {}

  -- 1 Style ------------------------------------------------------------------------------------------------
  local p = panes[1]
  local lookD
  local a = column(p, L):card("Quick start")
  do
    local l = UI:Text(p, "Look", "small"); l:SetPoint("TOPLEFT", a.x + 10, a.y - 5)
    lookD = UI:Dropdown(p, COLW - 156, P.LOOKS, C().look, function(v) P.ApplyLook(v); for _, f in ipairs(ctl) do pcall(f) end; changed() end)
    lookD:SetPoint("TOPLEFT", a.x + 146, a.y)
    ctl[#ctl + 1] = function() lookD:SetValue(C().look) end
    a.y = a.y - 30
  end
  a:drop("Theme", "theme", { { value = "standard", text = "Standard" }, { value = "artistic", text = "Artistic (art frames)" } },
    function(v) if v == "artistic" then C().framePlayers = true; C().frameClass = true end end)
  a:note("A Look sets everything at once - then fine-tune below. Artistic adds hand-painted frames round the plates.")
  a:done()
  a:card("Size"):slider("Width", "w", 60, 260, 2):slider("Height", "h", 4, 30, 1):pct("Scale", "scale", 50, 200):done()
  local b = column(p, R):card("Bar")
  b:drop("Texture", "tex", P.TextureOptions)
  b:slider("Roundness", "round", 0, 5, 1, function(v) return ({ [0] = "Square", "1", "2", "3", "4", "Pill" })[v] or tostring(v) end)
  b:drop("Border", "border", { { value = "theme", text = "Theme colour" }, { value = "black", text = "Thin black" }, { value = "none", text = "None" } })
  b:pct("Background", "bgAlpha", 0, 100)
  b:done()
  local dopts = { { value = "auto", text = "By creature type" } }
  for _, k in ipairs(P.UF_DESIGNS) do dopts[#dopts + 1] = { value = k, text = (k == "unknown" and "Always plain" or ("Always " .. k:sub(1, 1):upper() .. k:sub(2))) } end
  b:card("Artistic frames")
  b:drop("Mob frames", "frameDesign", dopts)
  b:drop("Ornaments on", "frameSide", { { value = "left", text = "Left end" }, { value = "right", text = "Right end" } })
  b:pct("Frame size", "frameSize", 60, 160)
  b:checks({ "Level bubble", "frameLevel", "The mob's level sits in a bubble on the frame." }, { "On players", "framePlayers", "Players get frames too." })
  b:checks({ "Class frames", "frameClass", "Players get their class's frame (warrior, mage, druid...). Off: the humanoid frame." },
           { "Friendly NPCs", "frameFriendly", "Friendly NPCs get frames too." })
  b:note("Only with the Artistic theme. Art: Good Unit Frames by Druid Whims.")
  b:done()

  -- 2 Text -------------------------------------------------------------------------------------------------
  p = panes[2]
  a = column(p, L):card("Name")
  a:check("Show the name", "nameShow")
  a:drop("Where", "nameAt", { { value = "above", text = "Above the bar" }, { value = "inside", text = "Inside the bar" }, { value = "below", text = "Below the bar" } })
  a:check("Shrink long names to fit", "nameFit", "With the name inside the bar: long names get smaller text so all of it fits. The bar keeps its width.")
  a:drop("Line up", "nameAlign", { { value = "center", text = "Centre" }, { value = "left", text = "Left" }, { value = "right", text = "Right" } })
  a:drop("Colour", "nameColor", { { value = "white", text = "White" }, { value = "class", text = "Class (players)" }, { value = "reaction", text = "Reaction / class" }, { value = "theme", text = "Theme accent" } })
  a:slider("Size", "nameSize", -4, 6, 1, signed)
  a:done()
  a:card("Level")
  a:drop("Show level", "levelAt", { { value = "name", text = "Before the name" }, { value = "left", text = "Left of the bar" }, { value = "off", text = "Off" } })
  a:check("Elite / rare badge", "classIcon", "Gold = elite and bosses, silver = rare. Pick the look in Icons.")
  a:done()
  local fonts = function()
    local out = { { value = "", text = "Same as Command Center" } }
    for _, n in ipairs(UI:FontList()) do out[#out + 1] = { value = n, text = n } end
    return out
  end
  b = column(p, R):card("Font")
  b:drop("Font", "font", fonts):slider("Size", "fontSize", 7, 18, 1)
  b:drop("Outline", "outline", { { value = "OUTLINE", text = "Outline" }, { value = "THICKOUTLINE", text = "Thick outline" }, { value = "none", text = "Shadow only" } })
  b:done()
  b:card("Health")
  b:drop("Show", "hpText", { { value = "percent", text = "Percent" }, { value = "cur", text = "Current" }, { value = "both", text = "Current + percent" },
    { value = "curmax", text = "Current / max" }, { value = "deficit", text = "Missing" }, { value = "none", text = "Nothing" } })
  b:drop("Where", "hpAt", { { value = "right", text = "Right, inside" }, { value = "center", text = "Centre" }, { value = "left", text = "Left, inside" }, { value = "outside", text = "Right, outside" } })
  b:slider("Size", "hpSize", -4, 4, 1, signed)
  b:done()

  -- 3 Target -----------------------------------------------------------------------------------------------
  p = panes[3]
  a = column(p, L):card("Your target")
  a:pct("Size", "tScale", 100, 160)
  a:check("Glow around it", "tGlow")
  a:check("Edge in the glow colour", "tBorder")
  a:check("Fade the other plates", "fade", "While you have a target, the others go see-through.")
  a:pct("Others at", "fadeAlpha", 20, 100)
  a:done()
  a:card("Mouse-over"):check("Light up when the mouse is over it", "mouseHL"):done()
  b = column(p, R):card("Target indicator")
  b:drop("Style", "tInd", { { value = "off", text = "Off" }, { value = "standard", text = "Standard arrows" }, { value = "minimal", text = "Minimal chevrons" },
    { value = "artistic", text = "Artistic spearheads" }, { value = "cartoon", text = "Cartoon (bouncy)" }, { value = "glow", text = "Glow (pulsing)" } })
  b:check("Animated", "tIndAnim", "The pieces move in and out. Off: they stay still.")
  b:pct("Size", "tIndSize", 60, 160)
  b:note("Animated pieces either side of your target, pointing at it. Colour: Colours tab (except Artistic).")
  b:done()

  -- 4 Combat -----------------------------------------------------------------------------------------------
  p = panes[4]
  a = column(p, L):card("Threat")
  a:drop("I'm playing", "role", { { value = "auto", text = "Automatic" }, { value = "tank", text = "Tank" }, { value = "dps", text = "Damage / healer" } })
  a:check("Colour the bar by threat", "threat", "Tank: you hold it / losing it / someone else has it. Damage / healing: it's on you / you're about to pull it.")
  a:check("Glow round the plate", "thrGlow", "The same threat colours as a glow round the plate.")
  a:checks({ "Words", "thrText", "AGGRO, PULLING, THREAT, LOSING, NO THREAT." }, { "Percentage", "thrPct", "The game's own threat %: 100% = you pull it." })
  a:check("Only in a group", "thrGroup")
  a:done()
  a:card("Execute range")
  a:check("Own colour when low", "execute", "Enemies under the set health get the execute colour.")
  a:check("Marker line on the bar", "execLine")
  a:slider("Low means under", "execPct", 5, 50, 1, function(v) return v .. "%" end)
  a:done()
  b = column(p, R):card("Cast bar")
  b:check("Show cast bars", "castShow")
  b:slider("Height", "castH", 4, 20, 1)
  b:checks({ "Spell icon", "castIcon" }, { "Spell name", "castName" })
  b:checks({ "Time left", "castTime" }, { "Spark", "castSpark" })
  b:check("Show \"Interrupted\"", "castFailShow")
  b:check("Green while my interrupt is ready", "castReady", "Kick, Pummel, Shield Bash, Counterspell, Earth Shock / Wind Shear, Silence, Rebuke... (whichever you know).")
  b:note("Casts you can't interrupt get a grey bar and a shield.")
  b:done()
  b:card("Threat look")
  b:drop("Words effect", "thrFx", { { value = "none", text = "None" }, { value = "pulse", text = "Pulse" }, { value = "bounce", text = "Bounce" }, { value = "flash", text = "Flash" } })
  b:pct("Words size", "thrTextSize", 60, 250)
  b:pct("Words glow", "thrTextGlow", 0, 100)
  b:pct("Plate glow", "thrGlowAlpha", 0, 100)
  b:pct("Plate glow size", "thrGlowSize", 50, 250)
  b:done()

  -- 5 Icons ------------------------------------------------------------------------------------------------
  p = panes[5]
  a = column(p, L):card("Elites and bosses")
  a:drop("Look", "eliteStyle", P.ELITE_STYLES)
  a:pct("Size", "eliteSize", 50, 150)
  a:check("Metal frame round the plate", "eliteFrame", "Bronze-gold (silver for rares) round the whole plate, with the dragon looks and the ring.")
  a:note("Gold = elite and bosses, silver = rare. Same in every theme.")
  a:done()
  a:card("Marks")
  a:drop("Raid mark", "raidAt", { { value = "left", text = "Left" }, { value = "right", text = "Right" }, { value = "top", text = "On top" } })
  a:slider("Raid mark size", "raidSize", 10, 40, 1)
  a:check("Combo points on my target", "combo")
  a:done()
  b = column(p, R):card("Quest mobs")
  b:check("Mark quest mobs", "quest")
  b:drop("Icon", "questStyle", P.QUEST_STYLES)
  b:drop("Where", "questAt", { { value = "right", text = "Right of the plate" }, { value = "left", text = "Left of the plate" }, { value = "top", text = "Above the name" } })
  b:slider("Size", "questSize", 10, 32, 1)
  b:check("Crest on elite frames", "questCrest", "On elite frames the quest mark is a gold / silver crest standing on the frame.")
  b:done()
  b:card("Corpses")
  b:check("Loot bag on lootable corpses", "corpseLoot", "A dead mob's plate turns into a bobbing loot bag while you can loot it, and goes away once it's looted. Only while the game keeps a plate for the corpse.")
  b:pct("Bag size", "corpseSize", 50, 200)
  b:done()

  -- 6 Debuffs ----------------------------------------------------------------------------------------------
  p = panes[6]
  a = column(p, L):card("Debuffs")
  a:drop("Show", "auraMode", { { value = "move", text = "Blizzard's icons (best)" }, { value = "copy", text = "CCPlates icons" }, { value = "off", text = "Off" } })
  a:drop("Where", "auraAt", { { value = "above", text = "Above the name" }, { value = "undername", text = "Under the name" }, { value = "below", text = "Under the cast bar" }, { value = "left", text = "Left of the plate" }, { value = "right", text = "Right of the plate" } })
  a:pct("Size", "auraScale", 50, 200)
  a:slider("Move left / right", "auraX", -60, 60, 1)
  a:slider("Move up / down", "auraY", -20, 40, 1)
  a:note("The game's own nameplate debuffs - it keeps them working in a fight, so CCPlates uses them.")
  a:done()
  b = column(p, R):card("Timers")
  b:drop("Numbers", "auraNumbers", { { value = "cc", text = "CCPlates timers" }, { value = "game", text = "The game's own" }, { value = "off", text = "None" } })
  b:drop("Number spot", "auraNumAt", { { value = "center", text = "On the icon" }, { value = "bottom", text = "Under the icon" }, { value = "top", text = "Over the icon" } })
  b:slider("Number size", "auraNumSize", 7, 16, 1)
  b:done()
  b:card("CCPlates icons")
  b:slider("Icon size", "auraSize", 12, 36, 1)
  b:slider("Most icons", "auraMax", 1, 12, 1)
  b:check("Timer swipe", "auraTimer")
  b:note("Only when Show is set to CCPlates icons.")
  b:done()

  -- 7 Colours ----------------------------------------------------------------------------------------------
  p = panes[7]
  a = column(p, L):card("Bars")
  a:checks({ "Class colours", "classPlayers", "Players' bars in their class colour." }, { "Grey if tapped", "tapped", "Grey when someone else tagged the mob." })
  a:swatches({ "Enemy", "hostile" }, { "Neutral", "neutral" })
  a:swatches({ "Friendly", "friendly" }, { "Tapped", "tapped" })
  a:swatches({ "Execute range", "execute" })
  a:done()
  a:card("Target")
  a:swatches({ "Glow / edge", "glow" }, { "Indicator", "arrows" })
  a:note("Right-click a colour to put it back. Glow and indicator follow your Command Center theme until you pick one.")
  a:done()
  b = column(p, R):card("Threat")
  b:swatches({ "Tank: holding", "tankGood" }, { "Tank: losing", "tankWarn" })
  b:swatches({ "Tank: lost it", "tankBad" }, { "Me: aggro", "dpsBad" })
  b:swatches({ "Me: about to pull", "dpsWarn" })
  b:done()
  b:card("Cast bar")
  b:swatches({ "Interruptible", "castInt" }, { "Can't interrupt", "castNon" })
  b:swatches({ "Channel", "castChan" }, { "Interrupt ready", "castReady" })
  b:swatches({ "Interrupted", "castFail" })
  b:done()

  -- 8 More -------------------------------------------------------------------------------------------------
  p = panes[8]
  a = column(p, L):card("Friends")
  a:check("Friendly plates as names only", "friendNameOnly", "Like Kui / Plater: friendly players and NPCs only show their name.")
  a:check("Click area follows the plate", "clickMatch", "Clicking anywhere on the plate (bar, name, frame) selects the unit.",
    function(v) if v then P.ClickArea() else P.ClickAreaBack() end end)
  a:done()
  a:card("Game options")
  for _, cv in ipairs(P.CVARS) do
    local bb = UI:Check(p, cv.label, getCVar(cv.key) == "1", function(v) setCVar(cv.key, v and 1 or 0) end, cv.tip)
    bb:SetPoint("TOPLEFT", a.x + 10, a.y); a.y = a.y - 26
    ctl[#ctl + 1] = function() bb:SetChecked(getCVar(cv.key) == "1") end
  end
  do
    local l = UI:Text(p, "Plates", "small"); l:SetPoint("TOPLEFT", a.x + 10, a.y - 5)
    local stackD = UI:Dropdown(p, COLW - 156, { { value = "1", text = "Stack (no overlap)" }, { value = "0", text = "Overlap" } }, getCVar("nameplateMotion") or "1",
      function(v) setCVar("nameplateMotion", v) end)
    stackD:SetPoint("TOPLEFT", a.x + 146, a.y); a.y = a.y - 30
    ctl[#ctl + 1] = function() stackD:SetValue(getCVar("nameplateMotion") or "1") end
    local dist = UI:Slider(p, COLW - 20, "Max distance", 10, 60, 1, tonumber(getCVar("nameplateMaxDistance")) or 20, function(v) setCVar("nameplateMaxDistance", v) end,
      function(v) return v .. " yd" end)
    dist:SetPoint("TOPLEFT", a.x + 10, a.y); a.y = a.y - 28
    ctl[#ctl + 1] = function() dist:SetValue(tonumber(getCVar("nameplateMaxDistance")) or 20) end
  end
  a:note("The game's own options. They change out of combat.")
  a:done()
  b = column(p, R):card("Mob colours")
  b:note("Give a mob its own bar colour by name - dangerous casters, adds to kill first, totems.")
  local nameBox = UI:Edit(p, 150, 24, "NPC name")
  nameBox:SetPoint("TOPLEFT", b.x + 10, b.y)
  local list = CreateFrame("Frame", nil, p); list:SetPoint("TOPLEFT", b.x + 10, b.y - 34); list:SetSize(COLW - 20, 330)
  b.y = b.y - 34 - 330
  local rows = {}
  local function redraw()
    for _, r in ipairs(rows) do r:Hide() end
    local names2 = {}
    for n in pairs(C().npc) do names2[#names2 + 1] = n end
    table.sort(names2)
    for i, n in ipairs(names2) do
      if i > 12 then break end
      local r = rows[i]
      if not r then
        r = CreateFrame("Frame", nil, list); r:SetSize(COLW - 20, 26)
        r.sw = swatch(r, 0, -3, "", function() local t = C().npc[r.n]; if t then return t[1], t[2], t[3] end return 1, 1, 1 end,
          function(v) if v then C().npc[r.n] = v else C().npc[r.n] = { 1, 0.5, 0 } end; changed() end)
        r.txt = UI:Text(r, "", "normal"); r.txt:SetPoint("LEFT", 30, 0); r.txt:SetWidth(COLW - 140); r.txt:SetJustifyH("LEFT")
        r.del = UI:Button(r, "Remove", 70, 20, function() C().npc[r.n] = nil; changed(); redraw() end)
        r.del:SetPoint("RIGHT", 0, 0)
        rows[i] = r
      end
      r.n = n
      r:SetPoint("TOPLEFT", 0, -(i - 1) * 27)
      r.txt:SetText(n); r.sw:Refresh(); r:Show()
    end
  end
  local function addName(n)
    n = S.Trim(n or "")
    if n == "" then return end
    if not C().npc[n] then C().npc[n] = { 1, 0.5, 0 } end
    nameBox:SetText(""); nameBox:ClearFocus()
    changed(); redraw()
  end
  local addB = UI:Button(p, "Add", 50, 24, function() addName(nameBox:GetText()) end); addB:SetPoint("LEFT", nameBox, "RIGHT", 6, 0)
  nameBox:SetScript("OnEnterPressed", function(self) addName(self:GetText()) end)
  local tgtB = UI:Button(p, "My target", 90, 24, function()
    local n = UnitExists("target") and try(UnitName, "target")
    if n and not sec(n) then addName(n) else S:Print("CCPlates: target a mob first (out of combat).") end
  end)
  tgtB:SetPoint("LEFT", addB, "RIGHT", 6, 0)
  ctl[#ctl + 1] = redraw
  b:done()

  -- right: preview
  local pv = CreateFrame("Frame", nil, win, BACKDROP_T)
  pv:SetPoint("TOPRIGHT", -16, -44); pv:SetPoint("BOTTOMRIGHT", -16, 16); pv:SetWidth(PREV_W)
  pv:SetClipsChildren(true)
  UI:Skin(pv, function(self, th)
    if self.SetBackdrop then
      self:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
      self:SetBackdropColor(0.04, 0.05, 0.05, 1); self:SetBackdropBorderColor(th.edge[1], th.edge[2], th.edge[3], 1)
    end
  end)
  local world = pv:CreateTexture(nil, "BACKGROUND", nil, 1); world:SetPoint("TOPLEFT", 1, -1); world:SetPoint("BOTTOMRIGHT", -1, 1)
  world:SetTexture(UI.ART.noise); world:SetVertexColor(0.16, 0.2, 0.15, 0.9)
  local pt = UI:Text(pv, "Preview", "normal"); pt:SetPoint("TOP", 0, -8)
  UI:Skin(pt, function(self, th) self:SetTextColor(th.gold[1], th.gold[2], th.gold[3]) end)
  local step = (WIN_H - 44 - 16 - 40) / #FAKES
  for i, fk in ipairs(FAKES) do
    local holder = CreateFrame("Frame", nil, pv); holder:SetSize(PREV_W, step)
    holder:SetPoint("TOP", pv, "TOP", 0, -32 - (i - 1) * step)
    local lab = UI:Text(holder, fk.label, "small"); lab:SetPoint("TOPLEFT", 8, -2); lab:SetTextColor(0.6, 0.6, 0.6)
    local o = P.Build(holder)
    o.fake = fakeSource(fk.d)
    o.unit = "preview" .. i
    o:SetPoint("CENTER", holder, "CENTER", 0, -4)
    P.previews[#P.previews + 1] = { o = o, holder = holder }
  end
  -- keep the fake casts running
  pv:SetScript("OnUpdate", function(self, el)
    self.t = (self.t or 0) + el
    if self.t < 0.25 then return end
    self.t = 0
    for _, x in ipairs(P.previews) do
      local o = x.o
      if o.fake.cast and not o.cast.ccStart and not o.cast.ccFading then guard(P.CastStart, o) end
    end
  end)
  local hint = UI:Text(win, "/ccenter plates", "small"); hint:SetPoint("BOTTOMLEFT", 18, 10); hint:SetTextColor(0.5, 0.5, 0.5)

  function win.Sync() for _, f in ipairs(ctl) do pcall(f) end; for _, s in ipairs(win.swatches) do s:Refresh() end end
  win:HookScript("OnShow", function() win.Sync(); P.UpdatePreview() end)
  tabs:Select(1)
end

function S:ShowPlates(tab)
  if not win then buildWindow() end
  win:Show()
  if tab and win.tabs then win.tabs:Select(tab) end
  P.UpdatePreview()
end
function S:HidePlates() if win then win:Hide() end end
function S:TogglePlates() if win and win:IsShown() then win:Hide() else S:ShowPlates() end end

-- what's going on (for bug reports)
function P.Debug()
  local n = 0
  for _ in pairs(P.byUnit) do n = n + 1 end
  S:Print(string.format("CCPlates r%d: %s, %d plates shown, last error: %s", REV, C().on and "on" or "off", n, tostring(P.lastErr or "none")))
  do
    local fr, nf = 0, 0
    for u2, o2 in pairs(P.byUnit) do
      local re = try(UnitReaction, u2, "player")
      if not sec(re) and type(re) == "number" and re >= 5 then fr = fr + 1; if o2.nameOnly then nf = nf + 1 end end
    end
    local locked = 0
    for _ in pairs(P.forbid) do locked = locked + 1 end
    -- r24: look at one friendly plate closely (visibility, alpha, text, font, the game's plate under it)
    for u2, o2 in pairs(P.byUnit) do
      local re = try(UnitReaction, u2, "player")
      if not sec(re) and type(re) == "number" and re >= 5 then
        local function q(obj, m, ...) if not (obj and obj[m]) then return "-" end local ok, a1, a2, a3 = pcall(obj[m], obj, ...); if not ok then return "err" end
          local function f(v) if v == nil then return "nil" elseif sec(v) then return "hidden" elseif type(v) == "number" then return string.format("%.2f", v) else return tostring(v) end end
          return f(a1) .. ((a2 ~= nil) and ("/" .. f(a2)) or "") .. ((a3 ~= nil) and ("/" .. f(a3)) or "") end
        local base = o2.base
        S:Print(string.format("  friendly plate %s: ours shown %s visible %s alpha %s | name shown %s visible %s alpha %s text %s font %s | game plate visible %s alpha %s, its UnitFrame alpha %s",
          u2, q(o2, "IsShown"), q(o2, "IsVisible"), q(o2, "GetEffectiveAlpha"), q(o2.name, "IsShown"), q(o2.name, "IsVisible"), q(o2.name, "GetAlpha"),
          q(o2.name, "GetText"), q(o2.name, "GetFont"), q(base, "IsVisible"), q(base, "GetEffectiveAlpha"), q(base and base.UnitFrame, "GetAlpha")))
        break
      end
    end
    -- r35: corpses
    do
      local cn, lb = 0, 0
      local hows = {}
      for _, o3 in pairs(P.byUnit) do
        if o3.corpse then
          cn = cn + 1; if (o3.corpseHow or ""):find("loot bag") then lb = lb + 1 end
          hows[#hows + 1] = tostring(o3.corpseHow) .. " (CanLootUnit " .. (o3.corpseRaw == nil and "hidden" or tostring(o3.corpseRaw)) .. ")"
        end
      end
      S:Print(string.format("  corpses: %d dead plates now (%d loot bags), %d seen since login (0 = the game removes plates when mobs die); CanLootUnit %s%s",
        cn, lb, P.corpseSeen or 0, CanLootUnit and "found" or "|cffff9933missing|r", #hows > 0 and (": " .. table.concat(hows, ", ")) or ""))
    end
    -- r28: click areas
    do
      local hows = {}
      for _, o3 in pairs(P.byUnit) do local k = tostring(o3.hitHow or "not set"); hows[k] = (hows[k] or 0) + 1 end
      local parts = {}
      for k, v in pairs(hows) do parts[#parts + 1] = v .. " " .. k end
      local anyBase = next(P.plates)
      S:Print(string.format("  clicks: %s; hit-test API %s, game 'friendly players name only' = %s, pending after the fight: %s",
        (#parts > 0 and table.concat(parts, ", ") or "no plates"), (anyBase and anyBase.SetHitTestPoints) and "found" or "|cffff9933missing|r",
        tostring(GetCVar and try(GetCVar, "nameplateShowOnlyNameForFriendlyPlayerUnits")), tostring(P.pendingHit and true or false)))
    end
    local cv = GetCVar and try(GetCVar, "nameplateShowFriends")
    local inInst = IsInInstance and select(1, try(IsInInstance))
    S:Print(string.format("  friendly: %d plates ours (%d as names only), %d locked by the game (addons can't touch those), game option 'show friendly plates' (Shift+V) = %s, in a dungeon/raid: %s, friends as names only: %s",
      fr, nf, locked, tostring(cv), tostring(inInst and true or false), tostring(C().friendNameOnly)))
  end
  local u = next(P.byUnit)
  if u then
    local base = P.byUnit[u].base
    local uf = blizzUF(base)
    local row, how = P.AuraRow(base)
    do
      local o1 = P.byUnit[u]
      S:Print(string.format("  fit name: %s, room %s, size %s, %s, name %s", P.FitOn() and "on" or "off", tostring(o1.nameAvail and floor(o1.nameAvail) or "-"),
        tostring(o1.nameFS or "-"), tostring(o1.fitHow or "-"), (o1.nameShown ~= nil and isSecret(o1.nameShown)) and "HIDDEN by the game" or "readable"))
    end
    S:Print("  debuffs: " .. C().auraMode .. ", game's row: " .. (row and ("found (" .. tostring(how) .. "), " .. #P.RowButtons(row) .. " shown") or "|cffff9933not found yet (shows up with the first debuff)|r"))
    if row then
      local kids, btns, names = 0, 0, {}
      local function walk(fr, d)
        if d > 2 then return end
        for _, ch in ipairs({ fr:GetChildren() }) do
          kids = kids + 1
          if isAuraButton(ch) then btns = btns + 1 end
          if d == 0 and #names < 6 then
            local nm
            for k, v in pairs(fr) do if v == ch and type(k) == "string" then nm = k break end end
            names[#names + 1] = nm or "?"
          end
          walk(ch, d + 1)
        end
      end
      pcall(walk, row, 0)
      local shownOk, shown = pcall(row.IsShown, row)
      local srcs = {}
      for _, b in ipairs(P.RowButtons(row)) do
        local cd = nth(b, "Cooldown") or nth(b, "cooldown")
        local _, how = P.TimeLeft(cd)
        local L = cd and P.cdLast[cd]
        srcs[#srcs + 1] = tostring(how or "unknown") .. (L and ("/" .. L[1]) or "")
      end
      if #srcs > 0 then S:Print("  timers: " .. table.concat(srcs, ", ")) end
      S:Print("  row: " .. kids .. " frames inside, " .. btns .. " look like debuffs, row shown: " .. tostring(shownOk and shown) .. (#names > 0 and (", parts: " .. table.concat(names, ", ")) or ""))
    end
    S:Print("  game plate: " .. (uf and "found" or "missing")
      .. ", game's raid icon: " .. (select(2, P.GameRaidIcon(base)) or "missing"))
    local oo = P.byUnit[u]
    local idx = REAL.raid(u)
    S:Print("  raid mark on " .. u .. ": " .. (sec(idx) and "hidden by the game" or tostring(idx)) .. " -> " .. tostring(oo.raidHow))
  end
  local id = P.KickSpell()
  S:Print("  interrupt: " .. (id and (tostring(id) .. " ready=" .. tostring(P.KickReady())) or "none known") .. ", tank: " .. tostring(P.IsTank()))
end

S:AddCommand("plates", "[on|off|debug]", "CCPlates: Command Center nameplates", function(rest)
  rest = S.Trim(rest or ""):lower()
  if rest == "on" then P.SetEnabled(true)
  elseif rest == "off" then P.SetEnabled(false)
  elseif rest == "debug" then P.Debug()
  else S:TogglePlates() end
end)
