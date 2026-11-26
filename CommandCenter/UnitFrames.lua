-- Unit Frames: Command Center's own player, target, target of target, focus, pet,
-- party, raid and boss frames, drawn in the theme's colours.
-- Features picked from the popular unit frame addons (Shadowed / Dusk, X-Perl /
-- F-Perl, ElvUI, RUF, Luna, BetterBlizzFrames):
--   * health / power bars with class, reaction, gradient or dark colouring, smooth fill
--   * text formats (current/max, percent, deficit, short numbers), name + level
--     with elite / rare marks, dead / ghost / offline
--   * 3D, 2D or class-icon portraits, left or right
--   * cast bars with icon, timer, latency and an "uninterruptible" colour
--   * buffs / debuffs (only mine, debuff-type borders, timers, stacks); raid frames
--     show your HoTs and the debuffs on each player inside the frame
--   * leader, raid mark, role, ready check, combat, resting and PvP icons
--   * target / mouseover / aggro / dispellable-debuff highlighting
--   * range fading for group frames, out-of-combat fading for your own frame
--   * incoming heals + absorbs, combo points, druid mana, energy ticks and the
--     five-second rule
--   * unlock-and-drag movers with a grid, test mode with made-up units, per-frame
--     settings, the game's frames hidden for the ones you use
-- Everything that could come back as a "secret" value (WoW Forever hides some unit
-- values from addons in combat) is only handed to the game's own widgets.
local _, S = ...
local UI = S.UI
-- revision of this file: bump on every deploy (Revisions.lua warns in game if an older copy loads)
local REV = 137
if S.ModuleRev then S:ModuleRev("UnitFrames", REV) end

local WHITE = "Interface\\Buttons\\WHITE8x8"
local BACKDROP_T = BackdropTemplateMixin and "BackdropTemplate" or nil
local unpack = unpack or table.unpack
local floor, max, min = math.floor, math.max, math.min

local function G() return S.db.global end
local function combat() return InCombatLockdown and InCombatLockdown() end
local isSecret = issecretvalue or function() return false end
local function sec(a, b, c)
  return isSecret(a) or isSecret(b) or isSecret(c)
end
local function try(fn, ...)
  if not fn then return end
  local ok, a, b, c, d, e, f, g, h, i = pcall(fn, ...)
  if ok then return a, b, c, d, e, f, g, h, i end
end
local function setText(fs, v) if not pcall(fs.SetText, fs, v) then fs:SetText("") end end
-- a yes/no the game may hide: hidden counts as "no"
local function bool(v) if isSecret(v) then return false end return v and true or false end
local function isNil(v) return type(v) == "nil" end
-- in combat the game hands out "secret tables": single fields read fine, but # / ipairs / pairs /
-- writing into them fail - so read them field by field with nth()
local function nth(t, i)           -- t[i] for plain or secret tables
  if type(t) ~= "table" then return nil end
  local ok, v = pcall(function() return t[i] end)
  if ok then return v end
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
local KEYS = { "player", "target", "targettarget", "focus", "pet", "party", "raid", "boss" }
local LABEL = { player = "Player", target = "Target", targettarget = "Target of target", focus = "Focus", pet = "Pet",
  party = "Party", raid = "Raid", boss = "Bosses" }
local GROUPS = { party = true, raid = true, boss = true }

local BASE = {
  on = true, replace = true, scale = 1, w = 200, h = 40, powerH = 9,
  portrait = "none", side = "left",
  healthColor = "class", healthText = "curmax", powerText = "none", nameAt = "left", nameColor = "class", nameBoxAt = "left", nameBoxW = 0.6, nameBoxFit = true, nameFull = true, pvpAt = "corner", levelAt = "name", levelSide = "left", levelSize = 0,
  name = true, level = true, tooltip = true,
  castbar = false, castH = 16, castIcon = true, castPos = "below", castW = 0, castRank = "full",
  castTex = "", castFill = "fill", castDir = "ltr", castTime = "left", castDec = true, castName = "left", castSpark = true,
  castEnd = "fade", castFail = true, castColor = "theme", col = {},
  anim = { health = "none", power = "none", cast = "none" }, animCol = {}, animStr = { health = 1, power = 1, cast = 1 },
  frameAnim = "none", frameAnimCol = { 1, 0.82, 0.3 }, frameAnimStr = 1,
  round = -1, roundBars = { health = -1, power = -1, cast = -1 },
  buffs = false, debuffs = false, auraSize = 22, auraMax = 8, auraMine = false, auraPos = "below", auraTimers = true, auraTimer = "on",
  ind = { leader = true, mark = true, role = true, ready = true, combat = false, rest = false, pvp = false },
  eliteIcon = true, eliteBorder = true, eliteSize = 1, eliteArt = "type", eliteAt = "portrait", eliteNormal = false, eliteRim = true, eliteX = 0, eliteY = 0,
  hl = { target = true, mouse = true, aggro = true, dispel = true },
  range = false, rangeAlpha = 0.4, fade = false, fadeAlpha = 0.35,
  healPred = true, absorb = true,
  growth = "down", spacing = 6,
}
local DEF = {
  player = { w = 230, h = 48, powerH = 12, portrait = "3d", x = -290, y = -170, castbar = true, castH = 18, debuffs = true,
    healthText = "both", powerText = "curmax", ind = { combat = true, rest = true, pvp = true }, ticks = true, druidMana = true, totems = true },
  target = { w = 230, h = 48, powerH = 12, portrait = "3d", side = "right", x = 290, y = -170, castbar = true, castH = 18,
    buffs = true, debuffs = true, healthText = "both", powerText = "curmax", combo = true, ind = { pvp = true }, pvpAt = "namebox" },
  targettarget = { w = 120, h = 26, powerH = 0, x = 290, y = -232, healthText = "percent", level = false },
  focus = { w = 180, h = 36, powerH = 8, x = -290, y = 40, castbar = true, castH = 14, debuffs = true, auraMine = true, healthText = "percent" },
  pet = { w = 130, h = 28, powerH = 6, x = -315, y = -232, healthText = "percent", level = false, range = true },
  party = { w = 170, h = 40, powerH = 8, portrait = "2d", x = -620, y = 160, debuffs = true, auraSize = 18, auraPos = "right",
    healthText = "percent", range = true, showPlayer = false, hideInRaid = true, spacing = 26 },
  raid = { w = 78, h = 40, powerH = 3, x = -560, y = -40, healthText = "deficit", nameAt = "center", level = false,
    buffs = true, auraMine = true, debuffs = true, auraSize = 14, auraMax = 3, auraPos = "inside", range = true,
    spacing = 3, groupsAs = "columns", ind = { role = true, leader = true } },
  boss = { w = 180, h = 38, powerH = 8, x = 520, y = 220, castbar = true, castH = 14, debuffs = true, auraMine = true,
    healthText = "percent", spacing = 30 },
}
local STYLE = { texture = "smooth", font = 11, outline = "OUTLINE", bgAlpha = 0.85, border = "theme", smooth = true,
  numbers = "short", grid = true, snap = false, gridSize = 32, round = 0, face = "cc", theme = "standard", artSize = 1,
  texHealth = "", texPower = "", anim = { health = "none", power = "none", cast = "none" }, animSpeed = 1, animCol = {},
  frameAnim = "none", frameAnimCol = { 1, 0.82, 0.3 }, frameAnimScope = "player", animStr = { health = 1, power = 1, cast = 1 }, frameAnimStr = 1,
  myNameOn = false, myName = { 1, 0.82, 0.2 },
  react = { hpLoss = "trail", hpGain = "flash", ppLoss = "none", ppGain = "none", comboGain = "pop", comboSpend = "burst", scope = "pt", minPct = 0, strength = 1,
    col = { hpLoss = { 1, 0.15, 0.1 }, hpGain = { 0.3, 1, 0.4 }, ppLoss = { 1, 1, 1 }, ppGain = { 0.55, 0.85, 1 }, combo = { 1, 1, 0.8 }, spend = { 1, 0.8, 0.3 }, trail = { 1, 0.85, 0.55 } } },
  fonts = { name = {}, health = {}, power = {}, level = {}, cast = {}, castTime = {}, status = {}, aura = {} } }

local function deep(dst, src)
  for k, v in pairs(src) do
    if type(v) == "table" then
      if type(dst[k]) ~= "table" then dst[k] = {} end
      deep(dst[k], v)
    elseif dst[k] == nil then dst[k] = v end
  end
  return dst
end
local function store()
  local g = G()
  g.unitFrames = type(g.unitFrames) == "table" and g.unitFrames or {}
  local d = g.unitFrames
  if d.on == nil then d.on = false end
  d.style = deep(type(d.style) == "table" and d.style or {}, STYLE)
  d.cdm = deep(type(d.cdm) == "table" and d.cdm or {}, { on = true, hideBar = true, nameplates = true })
  d.units = type(d.units) == "table" and d.units or {}
  return d
end
local cfgCache = {}
local function cfg(key)
  local d = store()
  local c = d.units[key]
  if type(c) ~= "table" then c = {}; d.units[key] = c end
  if not cfgCache[key] or cfgCache[key] ~= c then
    deep(c, DEF[key] or {}); deep(c, BASE)
    -- buffs and debuffs each have their own spot (older settings had one for both)
    if c.buffPos == nil then c.buffPos = c.auraPos or "below" end
    if c.debuffPos == nil then c.debuffPos = c.auraPos or "below" end
    if c.auraTimers == false and not c.timerMigrated then c.auraTimer = "off" end
    c.timerMigrated = true
    cfgCache[key] = c
  end
  return c
end
local function style() return store().style end
function S.UFConfig(key) return cfg(key) end
function S.UFStyle() return style() end

---------------------------------------------------------------------------
-- Look helpers
---------------------------------------------------------------------------
local TEXTURES = {
  { value = "cc1", text = "CC Gloss", path = "Interface\\AddOns\\CommandCenter\\Media\\Bars\\ccbar1" }, { value = "cc2", text = "CC Satin", path = "Interface\\AddOns\\CommandCenter\\Media\\Bars\\ccbar2" },
  { value = "cc3", text = "CC Bevel", path = "Interface\\AddOns\\CommandCenter\\Media\\Bars\\ccbar3" }, { value = "cc4", text = "CC Tube", path = "Interface\\AddOns\\CommandCenter\\Media\\Bars\\ccbar4" },
  { value = "cc5", text = "CC Brushed", path = "Interface\\AddOns\\CommandCenter\\Media\\Bars\\ccbar5" }, { value = "cc6", text = "CC Glass", path = "Interface\\AddOns\\CommandCenter\\Media\\Bars\\ccbar6" },
  { value = "cc7", text = "CC Neon", path = "Interface\\AddOns\\CommandCenter\\Media\\Bars\\ccbar7" }, { value = "cc8", text = "CC Stripes", path = "Interface\\AddOns\\CommandCenter\\Media\\Bars\\ccbar8" },
  { value = "cc9", text = "CC Hatch", path = "Interface\\AddOns\\CommandCenter\\Media\\Bars\\ccbar9" }, { value = "cc10", text = "CC Dots", path = "Interface\\AddOns\\CommandCenter\\Media\\Bars\\ccbar10" },
  { value = "cc11", text = "CC Carbon", path = "Interface\\AddOns\\CommandCenter\\Media\\Bars\\ccbar11" },
  { value = "cc12", text = "CC Scales", path = "Interface\\AddOns\\CommandCenter\\Media\\Bars\\ccbar12" },
  { value = "cc13", text = "CC Wood", path = "Interface\\AddOns\\CommandCenter\\Media\\Bars\\ccbar13" },
  { value = "cc14", text = "CC Marble", path = "Interface\\AddOns\\CommandCenter\\Media\\Bars\\ccbar14" },
  { value = "cc15", text = "CC Pixel", path = "Interface\\AddOns\\CommandCenter\\Media\\Bars\\ccbar15" },
  { value = "cc16", text = "CC Chrome", path = "Interface\\AddOns\\CommandCenter\\Media\\Bars\\ccbar16" },
  { value = "cc17", text = "CC Velvet", path = "Interface\\AddOns\\CommandCenter\\Media\\Bars\\ccbar17" },
  { value = "cc18", text = "CC Diamond", path = "Interface\\AddOns\\CommandCenter\\Media\\Bars\\ccbar18" },
  { value = "cc19", text = "CC Ripple", path = "Interface\\AddOns\\CommandCenter\\Media\\Bars\\ccbar19" },
  { value = "cc20", text = "CC Crystal", path = "Interface\\AddOns\\CommandCenter\\Media\\Bars\\ccbar20" },
  { value = "smooth", text = "Smooth", path = "Interface\\TargetingFrame\\UI-StatusBar" },
  { value = "flat", text = "Flat", path = WHITE },
  { value = "raid", text = "Raid (soft)", path = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill" },
  { value = "skills", text = "Skill bar", path = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar" },
}
local function texturePath(pick)
  local want = (pick and pick ~= "") and pick or style().texture
  for _, t in ipairs(TEXTURES) do if t.value == want then return t.path end end
  local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
  if LSM then local p = try(LSM.Fetch, LSM, "statusbar", want); if p then return p end end
  return "Interface\\TargetingFrame\\UI-StatusBar"
end
local function textureOptions()
  local out = {}
  for _, t in ipairs(TEXTURES) do out[#out + 1] = { value = t.value, text = t.text } end
  local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
  if LSM then
    for _, n in ipairs(try(LSM.List, LSM, "statusbar") or {}) do out[#out + 1] = { value = n, text = n } end
  end
  return out
end

local function classColor(cls)
  -- r133: a hidden (secret) class token can't be used as a table key (target of target in instances errored)
  if not cls or sec(cls) or type(cls) ~= "string" then return end
  local c = (CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[cls]) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls])
  if c then return c.r, c.g, c.b end
end
local REACT = { [1] = { 0.85, 0.2, 0.15 }, [2] = { 0.85, 0.2, 0.15 }, [3] = { 0.9, 0.45, 0.1 }, [4] = { 0.95, 0.85, 0.2 },
  [5] = { 0.3, 0.8, 0.25 }, [6] = { 0.3, 0.8, 0.25 }, [7] = { 0.3, 0.8, 0.25 }, [8] = { 0.3, 0.8, 0.25 } }
local function reactionColor(u)
  local r = try(UnitReaction, u, "player")
  if r and not sec(r) and REACT[r] then return unpack(REACT[r]) end
  if bool(try(UnitIsFriend, "player", u)) then return 0.3, 0.8, 0.25 end
  return 0.85, 0.2, 0.15
end
local POWER = { [0] = { 0.2, 0.45, 0.95 }, [1] = { 0.9, 0.2, 0.2 }, [2] = { 1, 0.55, 0.25 }, [3] = { 1, 0.85, 0.2 },
  [6] = { 0, 0.82, 1 } }
local function powerColor(ptype, token)
  local c = PowerBarColor and ((token and PowerBarColor[token]) or (ptype and PowerBarColor[ptype]))
  if c and c.r then return c.r, c.g, c.b end
  local p = POWER[ptype or 0] or POWER[0]
  return p[1], p[2], p[3]
end
local function short(v)
  if sec(v) then
    if AbbreviateNumbers then local s = try(AbbreviateNumbers, v); if not isNil(s) then return s end end
    return v
  end
  v = tonumber(v) or 0
  if style().numbers ~= "short" then
    if BreakUpLargeNumbers then return BreakUpLargeNumbers(v) end
    return tostring(v)
  end
  if v >= 1e6 then return string.format("%.1fm", v / 1e6) end
  if v >= 1e4 then return string.format("%.1fk", v / 1e3) end
  return tostring(floor(v + 0.5))
end

---------------------------------------------------------------------------
-- Fonts: the game's, other addons' (LibSharedMedia) and your own from
-- Interface\AddOns\CommandCenter\Media\Fonts. WoW can't list a folder, so files
-- called 1.ttf ... 20.ttf (or .otf) are found on their own and any other name is
-- added once with "Add font file..." (it's remembered). New files need a full restart.
---------------------------------------------------------------------------
local FONT_DIR = UI.MEDIA .. "Fonts\\"
local folderFonts = {}        -- { name, path, file }
local fontOK = {}
local function fontExists(path)
  if fontOK[path] ~= nil then return fontOK[path] end
  local fs = UIParent:CreateFontString(nil, "BACKGROUND")   -- a fresh one each time: no old font to fall back on
  fs:Hide()
  local ok, r = pcall(fs.SetFont, fs, path, 12, "")
  local good = ok and r ~= false
  if good then
    local ok2 = pcall(fs.SetText, fs, "Ag")
    local wid = ok2 and fs.GetStringWidth and fs:GetStringWidth() or 0
    good = ok2 and (type(wid) ~= "number" or wid > 0)
  end
  fontOK[path] = good and true or false
  return fontOK[path]
end
local function fontName(file)
  local n = file:gsub("%.[^%.]+$", ""):gsub("[_%-]+", " ")
  return n
end
local function addFolderFont(file, name)
  local path = FONT_DIR .. file
  for _, ff in ipairs(folderFonts) do if ff.path == path then return ff end end
  if not fontExists(path) then return nil end
  local ff = { name = name or fontName(file), path = path, file = file }
  folderFonts[#folderFonts + 1] = ff
  UI.fonts[ff.name] = path      -- Settings > font in the rest of Command Center can use it too
  return ff
end
function S.UFScanFonts()
  for i = 1, 20 do
    if not addFolderFont(i .. ".ttf", "Font " .. i) then addFolderFont(i .. ".otf", "Font " .. i) end
  end
  local list = S.db and S.db.global.fontFiles
  if type(list) == "table" then for _, file in ipairs(list) do addFolderFont(file) end end
  return folderFonts
end
-- "Add font file...": the exact file name you put in the folder
function S.UFAddFontFile(file)
  file = S.Trim(file or ""):gsub("^.*[/\\]", "")
  if file == "" then return nil, "empty" end
  if not file:lower():match("%.[ot]tf$") then file = file .. ".ttf" end
  fontOK[FONT_DIR .. file] = nil
  local ff = addFolderFont(file)
  if not ff then return nil, "missing" end
  local g = S.db.global
  g.fontFiles = type(g.fontFiles) == "table" and g.fontFiles or {}
  local have = false
  for _, f in ipairs(g.fontFiles) do if f:lower() == file:lower() then have = true end end
  if not have then g.fontFiles[#g.fontFiles + 1] = file end
  return ff
end
function S.UFFolderFonts() return folderFonts end
local function facePath(pick)
  local face = (pick and pick ~= "") and pick or style().face
  if face and face ~= "cc" then
    local p = UI.fonts[face]
    if not p then
      local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
      if LSM then p = try(LSM.Fetch, LSM, "font", face) end
    end
    return p
  end
end
local function setFace(fs, size, flags, face)
  local p = facePath(face)
  if p and pcall(fs.SetFont, fs, p, size, flags) then fs.__sf = nil; return end
  UI:SetFont(fs, "bold", size, flags)
end

---------------------------------------------------------------------------
-- Rounded boxes (9-slice of Media\UI\ufround<k> / ufedge<k> / ufedgeb<k>)
---------------------------------------------------------------------------
local RC = 24 / 64
local SLICE = { TL = { 0, RC, 0, RC }, T = { RC, 1 - RC, 0, RC }, TR = { 1 - RC, 1, 0, RC },
  L = { 0, RC, RC, 1 - RC }, C = { RC, 1 - RC, RC, 1 - RC }, R = { 1 - RC, 1, RC, 1 - RC },
  BL = { 0, RC, 1 - RC, 1 }, B = { RC, 1 - RC, 1 - RC, 1 }, BR = { 1 - RC, 1, 1 - RC, 1 } }
local RADIUS = { [0] = 0, 2, 4, 6, 8, 11 }       -- corner radius in px at full corner size (12)
local function newBox(f, layer, sub, skipCenter)
  local set = { f = f, parts = {} }
  for k, tc in pairs(SLICE) do
    if not (skipCenter and k == "C") then
      local t = f:CreateTexture(nil, layer, nil, sub)
      t:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
      set[k] = t; set.parts[#set.parts + 1] = t
    end
  end
  return set
end
local function boxLayout(set, file, cs, out)
  local f = set.f
  out = out or 0
  for _, t in ipairs(set.parts) do t:SetTexture(file); t:ClearAllPoints() end
  set.TL:SetSize(cs, cs); set.TL:SetPoint("TOPLEFT", f, "TOPLEFT", -out, out)
  set.TR:SetSize(cs, cs); set.TR:SetPoint("TOPRIGHT", f, "TOPRIGHT", out, out)
  set.BL:SetSize(cs, cs); set.BL:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", -out, -out)
  set.BR:SetSize(cs, cs); set.BR:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", out, -out)
  set.T:SetPoint("TOPLEFT", set.TL, "TOPRIGHT"); set.T:SetPoint("BOTTOMRIGHT", set.TR, "BOTTOMLEFT")
  set.B:SetPoint("TOPLEFT", set.BL, "TOPRIGHT"); set.B:SetPoint("BOTTOMRIGHT", set.BR, "BOTTOMLEFT")
  set.L:SetPoint("TOPLEFT", set.TL, "BOTTOMLEFT"); set.L:SetPoint("BOTTOMRIGHT", set.BL, "TOPRIGHT")
  set.R:SetPoint("TOPLEFT", set.TR, "BOTTOMLEFT"); set.R:SetPoint("BOTTOMRIGHT", set.BR, "TOPRIGHT")
  if set.C then set.C:SetPoint("TOPLEFT", set.TL, "BOTTOMRIGHT"); set.C:SetPoint("BOTTOMRIGHT", set.BR, "TOPLEFT") end
end
local function boxColor(set, r, g, b, a) for _, t in ipairs(set.parts) do t:SetVertexColor(r, g, b, a or 1) end end
local function boxShown(set, on) for _, t in ipairs(set.parts) do t:SetShown(on and true or false) end end
-- a frame's own fill + edge (replaces its backdrop)
local function skin(f)
  f.ccFill = newBox(f, "BACKGROUND", -8)
  f.ccEdge = newBox(f, "BORDER", 7, true)
end
local function cornerSize(w, h) return max(1, min(12, floor(min(w or 12, h or 12) / 2))) end
-- roundness of the frame being laid out (Size > Roundness), else Style > Roundness
local function skinLayout(f, w, h)
  if not f.ccFill then return end
  local k = S.__ufK or style().round or 0
  local cs = cornerSize(w, h)
  boxLayout(f.ccFill, UI.MEDIA .. "UI\\ufround" .. k, cs)
  boxLayout(f.ccEdge, UI.MEDIA .. "UI\\ufedge" .. k, cs)
  if f.SetBackdropColor then f:SetBackdropColor(0, 0, 0, 0); f:SetBackdropBorderColor(0, 0, 0, 0) end
end
local function skinColor(f, bg, bgA, edge)
  if not f.ccFill then return end
  boxColor(f.ccFill, bg[1], bg[2], bg[3], bgA)
  local none = style().border == "none"
  boxShown(f.ccEdge, not none)
  if not none then boxColor(f.ccEdge, edge[1], edge[2], edge[3], 1) end
end
-- how far bars sit inside a frame so they clear the rounded corners
local function innerPad(w, h)
  local k = S.__ufK or style().round or 0
  local r = RADIUS[k] * cornerSize(w, h) / 12
  return 1 + floor(r * 0.3 + 0.5)
end
-- highlight edge (target / aggro / dispel)
local function hlColor(f, r, g, b)
  if f.ccArtCol and S.UFArt then r, g, b = S.UFArt.mix(f, r, g, b, 0.35); boxColor(f.hlBox, r, g, b, 0.55) return end
  boxColor(f.hlBox, r, g, b, 1)
end

local function newFS(parent, size, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs.__size = size
  setFace(fs, size or style().font, style().outline ~= "NONE" and style().outline or "")
  fs:SetJustifyH(justify or "LEFT"); fs:SetWordWrap(false)
  fs:SetShadowOffset(1, -1); fs:SetShadowColor(0, 0, 0, 1)
  fs:SetTextColor(1, 1, 1)
  return fs
end
-- elem = name / health / power / level / cast / castTime / status / aura: its own face and size (Effects tab)
-- Fonts per part are per frame since r111 (cfg.fonts); Layout sets S.__ufF to the frame's fonts.
-- A frame's blank face / size 0 falls back to the old all-frames style().fonts, then the Style font.
function S.UFFontFor(elem)
  local st = style()
  local g = st.fonts and st.fonts[elem] or nil
  local l = S.__ufF and S.__ufF[elem] or nil
  if not l then return g end
  local face = (l.face and l.face ~= "") and l.face or (g and g.face)
  local size = ((l.size or 0) > 0) and l.size or (g and g.size) or 0
  return { face = face, size = size }
end
local function refont(fs, delta, elem)
  local st = style()
  local e = elem and S.UFFontFor(elem) or nil
  local size = (e and (e.size or 0) > 0) and e.size or (st.font + (delta or 0))
  setFace(fs, max(6, size), st.outline ~= "NONE" and st.outline or "", e and e.face or nil)
end

local function plainBackdrop(f)
  UI.EnsureBackdrop(f)
  f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
end

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
local hider = CreateFrame("Frame"); hider:Hide()
local holders, frames, byUnit = {}, {}, {}   -- holders[key], frames = list, byUnit[unit] = { f = true }
local castHolders = {}                        -- castHolders[key]: a cast bar moved off its frame
local CAST_FREE = { player = true, target = true, focus = true, pet = true }
local single = {}                             -- single[key] = frame
local groupKids = { party = {}, boss = {}, raid = {} }
local raidHeader, partyBox
local raidPreview = {}
local testing, unlocked = false, false
local pending = {}                            -- things to do after combat
local built = false

-- errors inside updates are kept (not shown) for /ccenter frames debug
local lastErr = {}
local function run(name, fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then lastErr[name] = { msg = tostring(err), at = GetTime() } end
  return ok
end

local function afterCombat(id, fn)
  if not combat() then fn() return end
  pending[id] = fn
end

local function mapUnit(f, unit)
  if f.unit == unit then return end
  if f.unit and byUnit[f.unit] then byUnit[f.unit][f] = nil end
  f.unit = unit
  if unit then byUnit[unit] = byUnit[unit] or {}; byUnit[unit][f] = true end
end

---------------------------------------------------------------------------
-- Building one frame
---------------------------------------------------------------------------
local UpdateAll, Layout, Paint   -- forward

---------------------------------------------------------------------------
-- In combat Forever refuses aura data to every addon ("Auras cannot be accessed
-- when secret while tainted by 'CommandCenter'" - confirmed in game 2026-11-20).
-- Only the game's own code may read them, so in combat each frame shows aura rows
-- built by the game: a SecureAuraHeaderTemplate whose buttons use the game's
-- SecureAuraButtonTemplate. Our code only places / sizes them (out of combat) and
-- never reads what's on them. Out of combat our own (styled) icons are used.
---------------------------------------------------------------------------
local AURA_TPL = "SecureAuraButtonTemplate"
local tplInfo
local function auraTemplate()
  if tplInfo then return tplInfo end
  tplInfo = { ok = false, w = 30, h = 30, parts = {} }
  local ok, b = pcall(CreateFrame, "Button", nil, UIParent, AURA_TPL)
  if ok and b then
    tplInfo.ok = true
    b:Hide()
    local w, h = b:GetSize()
    if type(w) == "number" and w > 0 then tplInfo.w, tplInfo.h = w, h end
    for k, v in pairs(b) do
      if type(k) == "string" and type(v) == "table" and v.GetObjectType then tplInfo.parts[#tplInfo.parts + 1] = k .. ":" .. v:GetObjectType() end
    end
    table.sort(tplInfo.parts)
  else tplInfo.err = tostring(b) end
  return tplInfo
end
local function makeHeaders(f)
  if f.ccPreview or f.key == "raid" or f.hdr then return end
  if combat() or not auraTemplate().ok then return end
  f.hdr = {}
  for _, kind in ipairs({ "buff", "debuff" }) do
    local ok, h = pcall(CreateFrame, "Frame", nil, f, "SecureAuraHeaderTemplate")
    if ok and h then
      h:SetAttribute("template", AURA_TPL)
      h:SetAttribute("sortMethod", "TIME")
      h:SetAttribute("sortDirection", "-")
      h:Hide()
      f.hdr[kind] = h
    end
  end
end
-- geo = { point, rel, x, y, dx, dy, wrap, wx, wy } from Layout (our own icon spots)
local function placeHeader(f, kind, geo, filter, count, size)
  local h = f.hdr and f.hdr[kind]
  if not h or combat() then return end
  if not geo or count <= 0 then h.ccUse = nil; h:Hide(); return end
  local sc = size / (auraTemplate().w or 30)
  h:SetScale(sc)
  h:SetAttribute("unit", f.unit)
  h:SetAttribute("filter", filter)
  h:SetAttribute("point", geo.point)
  h:SetAttribute("xOffset", geo.dx / sc); h:SetAttribute("yOffset", geo.dy / sc)
  h:SetAttribute("wrapAfter", geo.wrap)
  h:SetAttribute("maxWraps", math.ceil(count / geo.wrap))
  h:SetAttribute("wrapXOffset", geo.wx / sc); h:SetAttribute("wrapYOffset", geo.wy / sc)
  h:SetSize(size, size)
  h:ClearAllPoints(); h:SetPoint(geo.point, f, geo.rel, geo.x / sc, geo.y / sc)
  h.ccUse = true
end
-- PLAYER_REGEN_DISABLED fires just before the lock: swap our icons for the game's rows,
-- PLAYER_REGEN_ENABLED just after: swap back
local combatRows = false
local function combatAuras(on)
  combatRows = on and true or false
  if combat() and on == false then return end
  for _, f in ipairs(frames) do
    if f.hdr then
      for _, h in pairs(f.hdr) do
        local show = on and h.ccUse and f.cfg and store().on and f.cfg.on
        if show then h:Show() else h:Hide() end
      end
      if on then
        for _, b in ipairs(f.buffs) do b:Hide() end
        for _, b in ipairs(f.debuffs) do b:Hide() end
      end
    end
  end
end

local function auraButton(parent)
  local b = CreateFrame("Button", nil, parent, BACKDROP_T)
  plainBackdrop(b)
  b:SetBackdropColor(0, 0, 0, 1); b:SetBackdropBorderColor(0, 0, 0, 1)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetPoint("TOPLEFT", 1, -1); b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
  b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  if b.CreateMaskTexture then
    b.mask = b:CreateMaskTexture()
    b.mask:SetAllPoints(b.icon)
    b.icon:AddMaskTexture(b.mask)
  end
  b.ring = b:CreateTexture(nil, "OVERLAY", nil, 3); b.ring:SetAllPoints(); b.ring:Hide()
  b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
  b.cd:SetAllPoints(b.icon); b.cd:SetReverse(true)
  if b.cd.SetDrawEdge then b.cd:SetDrawEdge(false) end
  b.over = CreateFrame("Frame", nil, b); b.over:SetAllPoints(); b.over:SetFrameLevel(b.cd:GetFrameLevel() + 2)
  b.count = newFS(b.over, 10, "RIGHT"); b.count:SetPoint("BOTTOMRIGHT", 1, 0)
  b:EnableMouse(true)
  b:SetScript("OnEnter", function(self)
    if not self.unit and not self.spell then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
    if self.auraID and GameTooltip.SetUnitAuraByAuraInstanceID then
      try(GameTooltip.SetUnitAuraByAuraInstanceID, GameTooltip, self.unit, self.auraID, self.filter)
    elseif self.index then try(GameTooltip.SetUnitAura, GameTooltip, self.unit, self.index, self.filter)
    elseif self.spell and GameTooltip.SetSpellByID then try(GameTooltip.SetSpellByID, GameTooltip, self.spell) end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b:Hide()
  return b
end
-- the timer (the game's countdown text, restyled) and the stack count, kept small and apart
local function countdownText(cd)
  if cd.GetCountdownFontString then local fs = cd:GetCountdownFontString(); if fs then return fs end end
  for _, r in ipairs({ cd:GetRegions() }) do if r.GetObjectType and r:GetObjectType() == "FontString" then return r end end
end
local function auraText(b, tpos, size)
  local tsz = max(7, floor(size * 0.40 + 0.5))
  if b.cd.SetHideCountdownNumbers then b.cd:SetHideCountdownNumbers(tpos == "off" or size < 14) end
  if b.cd.SetSwipeColor then b.cd:SetSwipeColor(0, 0, 0, 0.55) end
  local cfs = countdownText(b.cd)
  if cfs then
    local af = S.UFFontFor("aura") or {}
    setFace(cfs, (af.size or 0) > 0 and af.size or tsz, "OUTLINE", af.face)
    cfs:ClearAllPoints()
    if tpos == "under" then cfs:SetPoint("TOP", b, "BOTTOM", 0, -1) else cfs:SetPoint("TOP", b, "TOP", 0, -1) end
    if cfs.SetJustifyH then cfs:SetJustifyH("CENTER") end
    cfs:SetTextColor(1, 1, 1)
  end
  setFace(b.count, max(7, floor(size * 0.38 + 0.5)), "OUTLINE", (S.UFFontFor("aura") or {}).face)
  b.count:ClearAllPoints(); b.count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 1)
  b.count:SetTextColor(1, 0.86, 0.35)
end

-- square icons get a thin black backdrop edge, rounded ones a ring (both take the debuff colour)
local function auraShape(b)
  local k = S.__ufK or style().round or 0
  local rounded = k > 0
  if b.mask then b.mask:SetTexture(UI.MEDIA .. "UI\\rmask" .. (rounded and k or 0), "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE") end
  b.ring:SetTexture(UI.MEDIA .. "UI\\rring" .. k); b.ring:SetShown(rounded)
  if b.cd.SetSwipeTexture then b.cd:SetSwipeTexture(rounded and (UI.MEDIA .. "UI\\rmask" .. k) or WHITE) end
  b.ccRound = rounded
  if rounded then b:SetBackdropColor(0, 0, 0, 0); b:SetBackdropBorderColor(0, 0, 0, 0)
  else b:SetBackdropColor(0, 0, 0, 1) end
  b.icon:ClearAllPoints()
  local inset = rounded and 0 or 1
  b.icon:SetPoint("TOPLEFT", inset, -inset); b.icon:SetPoint("BOTTOMRIGHT", -inset, inset)
end
local function auraEdge(b, r, g, bl)
  local ar = b.ccArtRing                      -- Artistic theme: white ring on buffs, red on debuffs
  if ar then r, g, bl = ar[1], ar[2], ar[3] end
  if b.ccRound then b.ring:SetVertexColor(r, g, bl, 1); b:SetBackdropBorderColor(0, 0, 0, 0)
  else b:SetBackdropBorderColor(r, g, bl, 1) end
end

local function makeBar(parent)
  local b = CreateFrame("StatusBar", nil, parent)
  b:SetStatusBarTexture(texturePath())
  b:SetMinMaxValues(0, 1); b:SetValue(1)
  b.bg = b:CreateTexture(nil, "BACKGROUND")
  b.bg:SetAllPoints(); b.bg:SetTexture(texturePath())
  return b
end

local function indicator(parent, file, size)
  local t = parent:CreateTexture(nil, "OVERLAY", nil, 2)
  t:SetTexture(file); t:SetSize(size or 14, size or 14); t:Hide()
  return t
end

local function onEnterUnit(self)
  if self.hlMouse then self.hlMouse:SetShown(self.cfg and self.cfg.hl.mouse) end
  if self.cfg and self.cfg.tooltip and self.unit and not self.fake and UnitExists(self.unit) then
    if GameTooltip_SetDefaultAnchor then GameTooltip_SetDefaultAnchor(GameTooltip, self) else GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT") end
    GameTooltip:SetUnit(self.unit)
    GameTooltip:Show()
  end
end
local function onLeaveUnit(self)
  if self.hlMouse then self.hlMouse:Hide() end
  GameTooltip:Hide()
end

-- style a frame: works for our own buttons, the raid header's buttons and the preview frames
local function Style(f, key)
  if f.ccStyled then return f end
  f.ccStyled, f.key = true, key
  f.cfg = cfg(key)
  plainBackdrop(f)
  skin(f)
  f:SetClampedToScreen(true)
  if f.RegisterForClicks and not f.ccPreview then
    if not combat() then
      f:RegisterForClicks("AnyUp")
      f:SetAttribute("*type1", "target")
      f:SetAttribute("*type2", "togglemenu")
    end
    ClickCastFrames = ClickCastFrames or {}
    ClickCastFrames[f] = true   -- Clique and other click-casting addons
  end
  f:HookScript("OnEnter", onEnterUnit)
  f:HookScript("OnLeave", onLeaveUnit)

  -- portrait
  f.portraitBox = CreateFrame("Frame", nil, f)
  f.model = CreateFrame("PlayerModel", nil, f.portraitBox)
  f.model:SetAllPoints()
  f.ptex = f.portraitBox:CreateTexture(nil, "ARTWORK"); f.ptex:SetAllPoints()
  f.pline = f:CreateTexture(nil, "BORDER"); f.pline:SetTexture(WHITE); f.pline:SetWidth(1)

  -- bars
  f.health = makeBar(f)
  f.pred = CreateFrame("StatusBar", nil, f.health)
  f.pred:SetStatusBarTexture(texturePath()); f.pred:SetFrameLevel(f.health:GetFrameLevel()); f.pred:Hide()
  f.absorb = f.health:CreateTexture(nil, "ARTWORK", nil, 3); f.absorb:SetTexture(WHITE); f.absorb:Hide()
  f.power = makeBar(f)
  f.tick = f.power:CreateTexture(nil, "OVERLAY"); f.tick:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
  f.tick:SetBlendMode("ADD"); f.tick:SetSize(12, 24); f.tick:Hide()

  -- texts + icons on top
  f.ui = CreateFrame("Frame", nil, f)
  f.ui:SetAllPoints(); f.ui:SetFrameLevel(f.health:GetFrameLevel() + 4)
  f.nameText = newFS(f.ui, nil, "LEFT")
  f.hpText = newFS(f.ui, nil, "RIGHT")
  f.ppText = newFS(f.ui, nil, "RIGHT")
  f.status = newFS(f.ui, nil, "CENTER")
  f.levelText = newFS(f.ui, nil, "CENTER")
  f.leader = indicator(f.ui, "Interface\\GroupFrame\\UI-Group-LeaderIcon", 14)
  f.mark = indicator(f.ui, "Interface\\TargetingFrame\\UI-RaidTargetingIcons", 18)
  f.role = indicator(f.ui, "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES", 14)
  f.ready = indicator(f.ui, "Interface\\RaidFrame\\ReadyCheck-Waiting", 18)
  f.combatIcon = indicator(f.ui, "Interface\\CharacterFrame\\UI-StateIcon", 20)
  f.combatIcon:SetTexCoord(0.5, 1, 0, 0.49)
  f.restIcon = indicator(f.ui, "Interface\\CharacterFrame\\UI-StateIcon", 20)
  f.restIcon:SetTexCoord(0, 0.5, 0, 0.421875)
  f.pvp = indicator(f.ui, "Interface\\TargetingFrame\\UI-PVP-Horde", 26)
  f.pvp:SetTexCoord(0, 0.62, 0, 0.62)

  -- highlight edges (target / aggro / dispel) and mouseover
  f.hl = CreateFrame("Frame", nil, f, BACKDROP_T)
  UI.EnsureBackdrop(f.hl)
  f.hl:SetPoint("TOPLEFT", -2, 2); f.hl:SetPoint("BOTTOMRIGHT", 2, -2)
  f.hl:SetFrameLevel(f.ui:GetFrameLevel() + 1); f.hl:Hide()
  f.hlBox = newBox(f.hl, "OVERLAY", 7, true)
  f.hlMouse = f.ui:CreateTexture(nil, "OVERLAY", nil, -1)
  f.hlMouse:SetTexture(WHITE); f.hlMouse:SetBlendMode("ADD"); f.hlMouse:SetVertexColor(1, 1, 1, 0.08)
  f.hlMouse:Hide()

  -- extra bars outside the frame (druid mana), combo points
  f.mana2 = makeBar(f); plainBackdrop(f.mana2); skin(f.mana2); f.mana2:Hide()
  f.combo = {}
  for i = 1, 5 do
    local p = CreateFrame("Frame", nil, f, BACKDROP_T); plainBackdrop(p); skin(p); p:Hide()
    p.fill = p:CreateTexture(nil, "ARTWORK"); p.fill:SetTexture(WHITE)
    p.fill:SetPoint("TOPLEFT", 1, -1); p.fill:SetPoint("BOTTOMRIGHT", -1, 1)
    f.combo[i] = p
  end

  -- cast bar
  local cb = CreateFrame("StatusBar", nil, f, BACKDROP_T)
  plainBackdrop(cb); skin(cb)
  cb:SetStatusBarTexture(texturePath()); cb:SetMinMaxValues(0, 1); cb:Hide()
  cb.icon = cb:CreateTexture(nil, "ARTWORK"); cb.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  cb.spark = cb:CreateTexture(nil, "OVERLAY"); cb.spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark"); cb.spark:SetBlendMode("ADD")
  cb.safe = cb:CreateTexture(nil, "ARTWORK", nil, 2); cb.safe:SetTexture(WHITE); cb.safe:SetVertexColor(0.9, 0.15, 0.1, 0.45); cb.safe:Hide()
  cb.shield = cb:CreateTexture(nil, "OVERLAY", nil, 1); cb.shield:SetTexture("Interface\\CastingBar\\UI-CastingBar-Small-Shield")
  cb.shield:Hide()
  cb.text = newFS(cb, nil, "LEFT"); cb.time = newFS(cb, nil, "RIGHT")
  f.cast = cb

  -- auras
  f.buffs, f.debuffs = {}, {}
  f.auraBox = CreateFrame("Frame", nil, f); f.auraBox:SetAllPoints()
  makeHeaders(f)
  f.auraBox:SetFrameLevel(f.ui:GetFrameLevel() + 2)

  frames[#frames + 1] = f
  UI:Skin(f, function(self) if self.ccLaidOut then Paint(self) end end)
  return f
end

local function newUnitButton(name, parent, unit, key)
  local f = CreateFrame("Button", name, parent, "SecureUnitButtonTemplate" .. (BACKDROP_T and ",BackdropTemplate" or ""))
  f:SetAttribute("unit", unit)
  Style(f, key)
  mapUnit(f, unit)
  f:HookScript("OnAttributeChanged", function(self, attr, v) if attr == "unit" then mapUnit(self, v); UpdateAll(self) end end)
  f:HookScript("OnShow", function(self) UpdateAll(self) end)
  return f
end

---------------------------------------------------------------------------
-- Layout (sizes / points). Protected frames are only resized out of combat.
---------------------------------------------------------------------------

Layout = function(f)
  local rk = f.cfg and f.cfg.round
  S.__ufK = (type(rk) == "number" and rk >= 0) and rk or nil
  S.__ufF = f.cfg and f.cfg.fonts
  local c = f.cfg
  local st = style()
  local w, h = c.w, c.h
  if not f.ccPreview and f.SetSize then
    if combat() then pending["layout" .. tostring(f)] = function() Layout(f) end
    else f:SetSize(w, h) end
  else f:SetSize(w, h) end
  local tex = texturePath()
  local htex, ptex = texturePath(st.texHealth), texturePath(st.texPower)
  f.health:SetStatusBarTexture(htex); f.health.bg:SetTexture(htex)
  f.power:SetStatusBarTexture(ptex); f.power.bg:SetTexture(ptex)
  f.pred:SetStatusBarTexture(tex); f.cast:SetStatusBarTexture(texturePath(c.castTex))
  f.cast.ccCfg = c
  f.mana2:SetStatusBarTexture(tex); f.mana2.bg:SetTexture(tex)

  -- frame box, highlight edge, mouse-over glow (rounded to match)
  local P = innerPad(w, h)
  skinLayout(f, w, h)
  local k = S.__ufK or st.round or 0
  boxLayout(f.hlBox, UI.MEDIA .. "UI\\ufedgeb" .. k, cornerSize(w + 4, h + 4))
  f.hlMouse:ClearAllPoints(); f.hlMouse:SetPoint("TOPLEFT", P, -P); f.hlMouse:SetPoint("BOTTOMRIGHT", -P, P)
  -- portrait
  local pw = (c.portrait ~= "none") and (h - 2 * P) or 0
  f.portraitBox:ClearAllPoints()
  f.pline:ClearAllPoints()
  if pw > 0 then
    f.portraitBox:SetSize(pw, pw)
    if c.side == "right" then
      f.portraitBox:SetPoint("TOPRIGHT", -P, -P)
      f.pline:SetPoint("TOPRIGHT", f.portraitBox, "TOPLEFT"); f.pline:SetPoint("BOTTOMRIGHT", f.portraitBox, "BOTTOMLEFT")
    else
      f.portraitBox:SetPoint("TOPLEFT", P, -P)
      f.pline:SetPoint("TOPLEFT", f.portraitBox, "TOPRIGHT"); f.pline:SetPoint("BOTTOMLEFT", f.portraitBox, "BOTTOMRIGHT")
    end
    f.portraitBox:Show(); f.pline:Show()
  else f.portraitBox:Hide(); f.pline:Hide() end
  f.model:SetShown(c.portrait == "3d"); f.ptex:SetShown(c.portrait == "2d" or c.portrait == "class")

  local left = (pw > 0 and c.side ~= "right") and (pw + P + 1) or P
  local right = (pw > 0 and c.side == "right") and (pw + P + 1) or P
  local ph = c.powerH or 0
  local hh = h - 2 * P - (ph > 0 and (ph + 1) or 0)
  f.health:ClearAllPoints()
  f.health:SetPoint("TOPLEFT", left, -P); f.health:SetPoint("TOPRIGHT", -right, -P); f.health:SetHeight(max(1, hh))
  f.power:ClearAllPoints()
  if ph > 0 then
    f.power:SetPoint("BOTTOMLEFT", left, P); f.power:SetPoint("BOTTOMRIGHT", -right, P); f.power:SetHeight(ph); f.power:Show()
  else f.power:Hide() end
  f.pred:ClearAllPoints()
  f.pred:SetPoint("TOP"); f.pred:SetPoint("BOTTOM"); f.pred:SetPoint("LEFT", f.health:GetStatusBarTexture(), "RIGHT")
  f.pred:SetWidth(max(1, w - left - right))
  f.tick:SetHeight(max(8, ph * 2.2))

  -- texts
  local small = f.key == "raid" or w < 100
  refont(f.nameText, small and -1 or 0, "name"); refont(f.hpText, small and -2 or 0, "health")
  refont(f.status, 0, "status"); refont(f.ppText, -2, "power")
  f.nameText:ClearAllPoints(); f.hpText:ClearAllPoints(); f.ppText:ClearAllPoints(); f.status:ClearAllPoints()
  -- name in its own small tab on top of the frame (Bars & text > Name: Box on top)
  local boxH = 0
  if c.nameAt == "box" and c.name then
    if not f.nameBox then
      f.nameBox = CreateFrame("Frame", nil, f); skin(f.nameBox)
    end
    local nb = f.nameBox
    boxH = floor(style().font + 7)
    local bw = max(30, floor(w * min(1, max(0.2, c.nameBoxW or 0.6)) + 0.5))
    nb:SetSize(bw, boxH); nb:ClearAllPoints()
    local at = c.nameBoxAt or "left"
    local ov = 1                                         -- overlap so the tab sits on the frame's edge
    if at == "center" then nb:SetPoint("BOTTOM", f, "TOP", 0, -ov)
    elseif at == "right" then nb:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 0, -ov)
    else nb:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, -ov) end
    nb:SetFrameLevel(f.ui:GetFrameLevel())
    skinLayout(nb, bw, boxH); nb:Show()
    boxH = boxH - ov
  elseif f.nameBox then f.nameBox:Hide() end
  f.ccBoxH = boxH
  if c.nameAt == "box" and f.nameBox and c.name then
    local nb = f.nameBox
    f.nameText:SetJustifyH(((c.nameBoxAt == "center") and "CENTER") or ((c.nameBoxAt == "right") and "RIGHT") or "LEFT")
    f.nameText:SetPoint("LEFT", nb, "LEFT", 5, 0); f.nameText:SetPoint("RIGHT", nb, "RIGHT", -5, 0)
    f.ccNameR = { "RIGHT", nb, -5, 0 }
    -- the health bar now has room: health text centred-right as usual
    f.hpText:SetJustifyH("RIGHT")
    f.hpText:SetPoint("RIGHT", f.health, "RIGHT", -4, 0)
    f.hpText:SetWidth(max(1, w - left - right - 8))
  elseif c.nameAt == "center" then
    f.nameText:SetJustifyH("CENTER")
    f.nameText:SetPoint("TOPLEFT", f.health, "TOPLEFT", 2, -3); f.nameText:SetPoint("TOPRIGHT", f.health, "TOPRIGHT", -2, -3)
    f.ccNameR = { "TOPRIGHT", f.health, -2, -3 }
    f.hpText:SetJustifyH("CENTER")
    f.hpText:SetPoint("BOTTOM", f.health, "BOTTOM", 0, 3)
  else
    f.nameText:SetJustifyH("LEFT")
    f.hpText:SetJustifyH("RIGHT")
    local fs = style().font
    local room = ({ percent = 3.6, cur = 4.4, deficit = 4.8, both = 7.6, curmax = 8.6, none = 0 })[c.healthText] or 7
    local hw = floor(fs * room + 0.5)
    local barW = w - left - right
    if hw > barW * 0.6 then hw = floor(barW * 0.6) end
    f.hpText:SetPoint("RIGHT", f.health, "RIGHT", -4, 0)
    f.hpText:SetWidth(max(1, hw))
    f.nameText:SetPoint("LEFT", f.health, "LEFT", 4, 0)
    f.nameText:SetPoint("RIGHT", f.health, "RIGHT", -(hw > 0 and (hw + 10) or 4), 0)
    f.ccNameR = { "RIGHT", f.health, -(hw > 0 and (hw + 10) or 4), 0 }
  end
  f.ppText:SetPoint("RIGHT", f.power, "RIGHT", -4, 0)
  f.ppText:SetPoint("LEFT", f.power, "LEFT", 4, 0)
  if c.nameAt == "center" then f.status:SetPoint("CENTER", f.health, "CENTER", 0, -4)
  elseif c.nameAt == "box" then f.status:SetPoint("CENTER", f.health, "CENTER", 0, 0)
  else f.status:SetPoint("RIGHT", f.health, "RIGHT", -4, 0) end

  -- level: joined to the name, or on its own (Bars & text > Level)
  do
    local la = c.level and (c.levelAt or "name") or "off"
    if la == "namebox" and not (f.nameBox and f.nameBox:IsShown()) then la = "bar" end
    if la == "name" and c.nameAt == "center" then la = "off" end
    f.ccLevelAt = la
    local lf = S.UFFontFor("level") or {}
    local lsz = (c.levelSize and c.levelSize > 0) and c.levelSize or ((lf.size or 0) > 0 and lf.size) or style().font
    setFace(f.levelText, lsz, style().outline ~= "NONE" and style().outline or "", lf.face)
    local lw = floor(lsz * 2.3 + 6)                     -- room for "60+" / "Boss"
    f.ccLvW = lw
    local side = c.levelSide == "right" and "right" or "left"
    f.levelText:ClearAllPoints(); f.levelText:SetJustifyH("CENTER")
    f.ccLvUnder = 0
    local boxed = la == "beside" or la == "above" or la == "under"
    if boxed then
      if not f.levelBox then f.levelBox = CreateFrame("Frame", nil, f); skin(f.levelBox) end
      local lb = f.levelBox
      local bh = floor(lsz + 7)
      local bw = max(bh, lw)
      if la == "beside" then
        -- as tall as the frame itself; the text size only changes the number, not the box
        bh = h
        bw = max(floor(h * 0.9 + 0.5), floor(style().font * 2.3 + 8))
      end
      lb:SetSize(bw, bh); lb:ClearAllPoints()
      lb:SetFrameLevel(max(1, f.ui:GetFrameLevel() - 1))
      if la == "beside" then
        if side == "right" then lb:SetPoint("TOPLEFT", f, "TOPRIGHT", 2, 0) else lb:SetPoint("TOPRIGHT", f, "TOPLEFT", -2, 0) end
      elseif la == "above" then
        local on = (f.nameBox and f.nameBox:IsShown()) and f.nameBox or f
        local ov = on == f and 1 or 1
        if side == "right" then lb:SetPoint("BOTTOMRIGHT", on, "TOPRIGHT", 0, -ov) else lb:SetPoint("BOTTOMLEFT", on, "TOPLEFT", 0, -ov) end
        f.ccBoxH = (f.ccBoxH or 0) + bh - ov
      else
        if side == "right" then lb:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, 1) else lb:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, 1) end
        f.ccLvUnder = bh
      end
      skinLayout(lb, bw, bh); lb:Show()
      f.levelText:SetPoint("CENTER", lb, "CENTER", 0, 0)
    elseif f.levelBox then f.levelBox:Hide() end
    if la == "bar" then
      if side == "right" then
        f.levelText:SetPoint("RIGHT", f.health, "RIGHT", -4, 0); f.levelText:SetJustifyH("RIGHT")
        f.hpText:SetPoint("RIGHT", f.health, "RIGHT", -4 - lw, 0)
      else
        f.levelText:SetPoint("LEFT", f.health, "LEFT", 4, 0); f.levelText:SetJustifyH("LEFT")
        if c.nameAt ~= "center" and c.nameAt ~= "box" then f.nameText:SetPoint("LEFT", f.health, "LEFT", 4 + lw, 0) end
      end
    elseif la == "namebox" then
      local nb = f.nameBox
      if side == "right" then
        f.levelText:SetPoint("RIGHT", nb, "RIGHT", -5, 0); f.levelText:SetJustifyH("RIGHT")
        f.nameText:SetPoint("RIGHT", nb, "RIGHT", -5 - lw, 0)
        f.ccNameR = { "RIGHT", nb, -5 - lw, 0 }
      else
        f.levelText:SetPoint("LEFT", nb, "LEFT", 5, 0); f.levelText:SetJustifyH("LEFT")
        f.nameText:SetPoint("LEFT", nb, "LEFT", 5 + lw, 0)
      end
    end
    f.levelText:SetShown(la ~= "off" and la ~= "name")
  end

  -- icons
  f.leader:ClearAllPoints(); f.leader:SetPoint("CENTER", f, "TOPLEFT", left + 8, 0)
  f.role:ClearAllPoints(); f.role:SetPoint("LEFT", f.leader, "RIGHT", 1, 0)
  f.mark:ClearAllPoints(); f.mark:SetPoint("CENTER", f, "TOP", 0, 1)
  f.ready:ClearAllPoints(); f.ready:SetPoint("CENTER", f.health, "CENTER")
  f.combatIcon:ClearAllPoints(); f.combatIcon:SetPoint("CENTER", f, "BOTTOMLEFT", left + 6, 2)
  f.restIcon:ClearAllPoints(); f.restIcon:SetPoint("CENTER", f, "TOPLEFT", left - 4, 2)
  f.pvp:ClearAllPoints()
  f.ccPvpBox = nil; f.ccPvpEnd = nil
  if c.pvpAt == "namebox" and c.name and f.ccNameR then
    -- faction icon right after the name (in the name box when there is one); placed by S.UFPvpPlace
    local inBox = c.nameAt == "box" and f.nameBox and f.nameBox:IsShown()
    local sz
    if inBox then sz = floor(f.nameBox:GetHeight() + 4)
    else local _, fsz = f.nameText:GetFont(); sz = floor((tonumber(fsz) or 12) * 1.7) end
    sz = max(10, sz)
    f.pvp:SetSize(sz, sz)
    f.pvp:SetPoint("LEFT", f.nameText, "RIGHT", 1, -1)
    f.ccPvpEnd = { w = floor(sz * 0.62 + 3), y = -1, box = inBox }
  else
    f.pvp:SetSize(26, 26)
    if c.side == "right" then f.pvp:SetPoint("CENTER", f, "TOPRIGHT", 6, -6) else f.pvp:SetPoint("CENTER", f, "TOPLEFT", -6, -6) end
  end

  -- below the frame: druid mana, cast bar, auras
  local below = -2 - (f.ccLvUnder or 0)
  f.mana2:ClearAllPoints()
  if c.druidMana and f.key == "player" then
    f.mana2:SetPoint("TOPLEFT", f, "BOTTOMLEFT", left - 1, below + 1); f.mana2:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", -(right - 1), below + 1)
    f.mana2:SetHeight(6)
    skinLayout(f.mana2, w, 6)
    f.mana2.reserve = true
  else f.mana2.reserve = nil end
  if f.mana2.reserve and f.mana2:IsShown() then below = below - 7 end
  f.cast:ClearAllPoints()
  local castAbove = 0
  if c.castbar then
    local ch = c.castH or 16
    f.cast:SetHeight(ch)
    skinLayout(f.cast, w, ch)
    local iw = c.castIcon and ch or 0
    local gap = iw + (iw > 0 and 2 or 0)
    local pos = c.castPos or "below"
    local hold = castHolders[f.key]
    if pos == "free" and (not hold or f.ccPreview or not CAST_FREE[f.key]) then pos = "below" end
    if pos == "free" then
      -- its own spot on the screen (drag it in unlock mode)
      if c.castX == nil then
        local sc = c.scale or 1
        c.castX, c.castY = c.x or 0, floor((c.y or 0) - c.h * sc / 2 - ch * sc / 2 - 12)
      end
      local cwid = (c.castW and c.castW > 0) and c.castW or w
      hold:SetSize(cwid, ch)
      local sc = c.scale or 1
      hold:SetScale(sc)
      hold:ClearAllPoints(); hold:SetPoint("CENTER", UIParent, "CENTER", c.castX / sc, c.castY / sc)
      f.cast:SetPoint("TOPLEFT", hold, "TOPLEFT", gap, 0)
      f.cast:SetPoint("BOTTOMRIGHT", hold, "BOTTOMRIGHT", 0, 0)
    elseif pos == "above" then
      local top = ((c.combo and f.key == "target") and 10 or 2) + 1 + (f.ccBoxH or 0)
      f.cast:SetPoint("BOTTOMLEFT", f, "TOPLEFT", gap, top)
      f.cast:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 0, top)
      castAbove = ch + 3
    else
      f.cast:SetPoint("TOPLEFT", f, "BOTTOMLEFT", gap, below - 1)
      f.cast:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, below - 1)
    end
    f.cast.ccBelow = pos == "below"
    f.cast.icon:ClearAllPoints(); f.cast.icon:SetSize(ch, ch)
    f.cast.icon:SetPoint("RIGHT", f.cast, "LEFT", -2, 0); f.cast.icon:SetShown(c.castIcon)
    f.cast.spark:SetSize(14, ch * 2.2)
    f.cast.shield:ClearAllPoints(); f.cast.shield:SetSize(ch * 2.6, ch * 2.6); f.cast.shield:SetPoint("CENTER", f.cast.icon, "CENTER", 0, -1)
    if f.cast.SetReverseFill then f.cast:SetReverseFill(c.castDir == "rtl") end
    local rtl = c.castDir == "rtl"
    local tOff = c.castTime == "off"
    f.cast.text:ClearAllPoints()
    if c.castName == "center" then f.cast.text:SetPoint("LEFT", 4, 0); f.cast.text:SetPoint("RIGHT", -4, 0); f.cast.text:SetJustifyH("CENTER")
    elseif rtl then f.cast.text:SetPoint("RIGHT", -4, 0); f.cast.text:SetPoint("LEFT", tOff and 4 or 44, 0); f.cast.text:SetJustifyH("RIGHT")
    else f.cast.text:SetPoint("LEFT", 4, 0); f.cast.text:SetPoint("RIGHT", tOff and -4 or -44, 0); f.cast.text:SetJustifyH("LEFT") end
    f.cast.text:SetShown(c.castName ~= "off")
    f.cast.time:ClearAllPoints()
    if rtl then f.cast.time:SetPoint("LEFT", 4, 0) else f.cast.time:SetPoint("RIGHT", -4, 0) end
    f.cast.time:SetShown(not tOff)
    refont(f.cast.text, -1, "cast"); refont(f.cast.time, -1, "castTime")
    f.cast.safe:ClearAllPoints(); f.cast.safe:SetPoint("TOPRIGHT", -1, -1); f.cast.safe:SetPoint("BOTTOMRIGHT", -1, 1)
    if f.cast.ccBelow then below = below - ch - 3 end
  end

  -- combo points: a row of pips over the top edge
  local cw = (w - 8) / 5
  for i, p in ipairs(f.combo) do
    p:ClearAllPoints(); p:SetSize(cw - 2, 6); skinLayout(p, cw - 2, 6)
    p:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 4 + (i - 1) * cw, 2)
  end

  -- auras
  local size = c.auraSize
  local nb = (c.buffs and c.auraMax or 0)
  local nd = (c.debuffs and c.auraMax or 0)
  while #f.buffs < nb do f.buffs[#f.buffs + 1] = auraButton(f.auraBox) end
  while #f.debuffs < nd do f.debuffs[#f.debuffs + 1] = auraButton(f.auraBox) end
  for i = nb + 1, #f.buffs do f.buffs[i]:Hide() end
  for i = nd + 1, #f.debuffs do f.debuffs[i]:Hide() end
  local bl, dl = {}, {}
  for i = 1, nb do bl[i] = f.buffs[i] end
  for i = 1, nd do dl[i] = f.debuffs[i] end
  local perRow = max(1, floor((w + 2) / (size + 2)))
  local step = size + 2
  local tpos = c.auraTimer or "on"
  local vstep = step + ((tpos == "under") and (max(7, floor(size * 0.40 + 0.5)) + 2) or 0)
  -- running edges per side, so buffs and debuffs on the same side stack instead of overlapping
  local edge = { below = below - 1, above = ((c.combo and f.key == "target") and 10 or 2) + castAbove + (f.ccBoxH or 0), right = 0, left = 0 }
  local geo = {}
  local function place(list, pos, isBuff)
    if #list == 0 then return end
    local n = #list
    local g
    if pos == "inside" then
      g = isBuff and { point = "TOPRIGHT", rel = "TOPRIGHT", x = -2, y = -2, dx = -step, dy = 0, wrap = n, wx = 0, wy = 0 }
        or { point = "BOTTOMLEFT", rel = "BOTTOMLEFT", x = 2, y = 2 + (ph > 0 and ph + 1 or 0), dx = step, dy = 0, wrap = n, wx = 0, wy = 0 }
    elseif pos == "above" then
      g = { point = "BOTTOMLEFT", rel = "TOPLEFT", x = 0, y = edge.above + (vstep - step), dx = step, dy = 0, wrap = perRow, wx = 0, wy = vstep }
    elseif pos == "right" then
      g = { point = "TOPLEFT", rel = "TOPRIGHT", x = 4, y = -edge.right, dx = step, dy = 0, wrap = n, wx = 0, wy = 0 }
    elseif pos == "left" then
      g = { point = "TOPRIGHT", rel = "TOPLEFT", x = -4, y = -edge.left, dx = -step, dy = 0, wrap = n, wx = 0, wy = 0 }
    else
      g = { point = "TOPLEFT", rel = "BOTTOMLEFT", x = 0, y = edge.below, dx = step, dy = 0, wrap = perRow, wx = 0, wy = -vstep }
    end
    geo[isBuff and "buff" or "debuff"] = g
    if pos == "inside" then
      for i, b in ipairs(list) do
        b:SetSize(size, size); b:ClearAllPoints()
        if isBuff then b:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2 - (i - 1) * step, -2)
        else b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 2 + (i - 1) * step, 2 + (ph > 0 and ph + 1 or 0)) end
      end
    elseif pos == "above" then
      for i, b in ipairs(list) do
        local col, row = (i - 1) % perRow, floor((i - 1) / perRow)
        b:SetSize(size, size); b:ClearAllPoints(); b:SetPoint("BOTTOMLEFT", f, "TOPLEFT", col * step, edge.above + row * vstep + (vstep - step))
      end
      edge.above = edge.above + math.ceil(#list / perRow) * vstep
    elseif pos == "right" or pos == "left" then
      local rgt = pos == "right"
      for i, b in ipairs(list) do
        b:SetSize(size, size); b:ClearAllPoints()
        if rgt then b:SetPoint("TOPLEFT", f, "TOPRIGHT", 4 + (i - 1) * step, -edge.right)
        else b:SetPoint("TOPRIGHT", f, "TOPLEFT", -4 - (i - 1) * step, -edge.left) end
      end
      if rgt then edge.right = edge.right + vstep else edge.left = edge.left + vstep end
    else -- below
      for i, b in ipairs(list) do
        local col, row = (i - 1) % perRow, floor((i - 1) / perRow)
        b:SetSize(size, size); b:ClearAllPoints(); b:SetPoint("TOPLEFT", f, "BOTTOMLEFT", col * step, edge.below - row * vstep)
      end
      edge.below = edge.below - math.ceil(#list / perRow) * vstep
    end
  end
  if S.UFArt and S.UFArt.on(f) then
    -- r132 Artistic theme: buffs + debuffs fill the open space under the frame, between the art's end pieces.
    -- Player: buffs from the left, debuffs from the right; others: debuffs from the left, buffs from the right.
    local x0, y0, half = S.UFArt.auraBand(f, step)
    local leftList, rightList, leftBuff = dl, bl, false
    if f.key == "player" then leftList, rightList, leftBuff = bl, dl, true end
    local function row(list, isBuff, fromLeft)
      if #list == 0 then return end
      local sx = fromLeft and 1 or -1
      geo[isBuff and "buff" or "debuff"] = { point = fromLeft and "TOPLEFT" or "TOPRIGHT", rel = fromLeft and "BOTTOMLEFT" or "BOTTOMRIGHT",
        x = sx * x0, y = y0, dx = sx * step, dy = 0, wrap = half, wx = 0, wy = -vstep }
      for i, b in ipairs(list) do
        local col, r = (i - 1) % half, floor((i - 1) / half)
        b:SetSize(size, size); b:ClearAllPoints()
        if fromLeft then b:SetPoint("TOPLEFT", f, "BOTTOMLEFT", x0 + col * step, y0 - r * vstep)
        else b:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", -x0 - col * step, y0 - r * vstep) end
        b.ccArtRing = isBuff and S.UFArt.RING_BUFF or S.UFArt.RING_DEBUFF
      end
    end
    row(leftList, leftBuff, true)
    row(rightList, not leftBuff, false)
  else
    for _, b in ipairs(f.buffs) do b.ccArtRing = nil end
    for _, b in ipairs(f.debuffs) do b.ccArtRing = nil end
    -- debuffs go nearest the frame when both share a side
    place(dl, c.debuffPos or c.auraPos, false)
    place(bl, c.buffPos or c.auraPos, true)
  end
  f.ccGeo, f.ccAuraSize, f.ccAuraStep = geo, size, step
  if f.hdr and f.unit then
    local mineDebuffs = c.auraMine and f.key ~= "player" and f.key ~= "party"
    placeHeader(f, "buff", geo.buff, c.auraMine and "HELPFUL|PLAYER" or "HELPFUL", nb, size)
    placeHeader(f, "debuff", geo.debuff, mineDebuffs and "HARMFUL|PLAYER" or "HARMFUL", nd, size)
  end
  for _, list in ipairs({ f.buffs, f.debuffs }) do
    local where = (list == f.buffs) and (c.buffPos or c.auraPos) or (c.debuffPos or c.auraPos)
    local artRound = S.UFArt and S.UFArt.on(f)
    for _, b in ipairs(list) do
      if artRound then local keep = S.__ufK; S.__ufK = 5; auraShape(b); S.__ufK = keep else auraShape(b) end
      auraText(b, (where == "inside" and tpos == "under") and "on" or tpos, size)
    end
  end
  if S.UFArt then pcall(S.UFArt.layout, f) end
  f.ccLaidOut = true
  pcall(S.UFNameFit, f)
  pcall(S.UFRound.frame, f, w, h)
  Paint(f)
  pcall(S.UFAnim.frame, f)
  if S.UFElite then pcall(S.UFElite.update, f) end
  S.__ufK = nil; S.__ufF = nil
end

-- WoW Forever: characters have a main name + a secondary name (surname). The game may give the second
-- part in different places, so try them all; returns the full "Main Second" text, or nil.
function S.UFFullName(u)
  local function ok(v) return type(v) == "string" and not sec(v) and v ~= "" end
  local main, second = try(UnitName, u)
  if not ok(main) then return nil end
  if ok(second) and second ~= main then return main .. " " .. second end
  for _, fn in ipairs({ "UnitSecondaryName", "UnitSurname", "UnitLastName" }) do
    local f2 = _G[fn]
    if type(f2) == "function" then local v = try(f2, u); if ok(v) and v ~= main then return main .. " " .. v end end
  end
  if C_PlayerInfo and type(C_PlayerInfo.GetSecondaryName) == "function" then
    local v = try(C_PlayerInfo.GetSecondaryName, u); if ok(v) then return main .. " " .. v end
  end
  local a, b = try(UnitFullName, u)
  if ok(b) and b ~= main then return main .. " " .. b end
  local g = GetUnitName and try(GetUnitName, u, true)
  if ok(g) and #g > #main and g:find(main, 1, true) then return (g:gsub("%-", " ")) end
  return nil
end

-- Name box fits the name (Bars & text > Fit the box to the name): as wide as the text + padding,
-- never wider than the frame. Hidden names can't be measured: then the Box width setting is used.
function S.UFNameFit(f)
  local nb, c = f.nameBox, f.cfg
  if not (nb and nb:IsShown() and c and c.nameAt == "box") then return end
  local fw = c.w or 200
  local bw = floor(fw * min(1, max(0.2, c.nameBoxW or 0.6)) + 0.5)
  if c.nameBoxFit ~= false then
    local fs = f.nameText
    local tw = fs.GetUnboundedStringWidth and try(fs.GetUnboundedStringWidth, fs) or try(fs.GetStringWidth, fs)
    if type(tw) == "number" and not sec(tw) then
      local extra = 12 + ((f.ccLevelAt == "namebox") and (f.ccLvW or 0) or 0) + (f.ccPvpW or 0)
      bw = floor(tw + extra + 0.5)
    end
  end
  bw = max(30, min(fw, bw))
  nb:SetWidth(bw)
  if nb.ccFill then
    local keep = S.__ufK
    local rk = c.round
    S.__ufK = (type(rk) == "number" and rk >= 0) and rk or nil
    skinLayout(nb, bw, nb:GetHeight())
    S.__ufK = keep
  end
end

-- Faction icon right after the name (Portrait > Faction icon at: After the name). The name's area gives up
-- the icon's width (so long names cut off before it), the name box grows by it, and the icon sits where
-- the text ends. Hidden (unmeasurable) names: the icon sits at the end of the name's area.
function S.UFPvpPlace(f)
  local pe = f.ccPvpEnd
  if not pe then f.ccPvpW = 0 return end
  local fs, nr = f.nameText, f.ccNameR
  local shown = f.pvp:IsShown() and true or false
  local pw = shown and pe.w or 0
  f.ccPvpW = pw
  if nr then fs:SetPoint(nr[1], nr[2], nr[1], nr[3] - pw, nr[4] or 0) end
  if pe.box then pcall(S.UFNameFit, f) end
  if not shown then return end
  f.pvp:ClearAllPoints()
  local tw = fs.GetUnboundedStringWidth and try(fs.GetUnboundedStringWidth, fs) or try(fs.GetStringWidth, fs)
  if type(tw) ~= "number" or sec(tw) then f.pvp:SetPoint("LEFT", fs, "RIGHT", 1, pe.y) return end
  local fw = try(fs.GetWidth, fs)
  if type(fw) == "number" and not sec(fw) and fw > 1 then
    if pe.box and f.nameBox then fw = min(fw, f.nameBox:GetWidth()) end
    if tw > fw then tw = fw end
  end
  local j = fs:GetJustifyH()
  if j == "RIGHT" then f.pvp:SetPoint("LEFT", fs, "RIGHT", 1, pe.y)
  elseif j == "CENTER" then f.pvp:SetPoint("LEFT", fs, "CENTER", tw / 2 + 1, pe.y)
  else f.pvp:SetPoint("LEFT", fs, "LEFT", tw + 1, pe.y) end
end

-- Rounded bar ends (Style > Roundness): two small masks pinned to the bar's ends, clamped to white so
-- the rest of the bar stays fully visible - the corners keep their shape at any bar width.
S.UFRound = { FR = { 0.08, 0.14, 0.2, 0.26, 0.32, 0.38, 0.44, 0.5 } }
do
  local U = S.UFRound
  local CAP = "Interface\\AddOns\\CommandCenter\\Media\\Bars\\cap"
  local function pick(rpx, h)
    if not h or h <= 0 or not rpx or rpx < 1 then return nil end
    local fr = min(0.5, rpx / h)
    if fr < 0.05 then return nil end
    local best, bd = 1, 9
    for i, v in ipairs(U.FR) do local d = math.abs(v - fr); if d < bd then best, bd = i, d end end
    return best
  end
  -- round a StatusBar's fill (+ extra textures such as its background); rpx = corner radius in px, h = bar height
  -- owner = the frame whose textures get masked (masks must live in the same frame), bar = what they're pinned to
  function U.applyTo(owner, bar, rpx, h, list)
    if not owner or not owner.CreateMaskTexture then return end
    local n = pick(rpx, h)
    local m = owner.ccRoundOwn
    if not m and not n then return end
    if not m then m = { L = owner:CreateMaskTexture(), R = owner:CreateMaskTexture(), on = {} }; owner.ccRoundOwn = m end
    if not n then
      for t in pairs(m.on) do pcall(t.RemoveMaskTexture, t, m.L); pcall(t.RemoveMaskTexture, t, m.R) end
      m.on = {}
      return
    end
    m.L:SetTexture(CAP .. "L" .. n, "CLAMPTOWHITE", "CLAMPTOWHITE")
    m.R:SetTexture(CAP .. "R" .. n, "CLAMPTOWHITE", "CLAMPTOWHITE")
    m.L:ClearAllPoints(); m.L:SetPoint("TOPLEFT", bar, "TOPLEFT"); m.L:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT"); m.L:SetWidth(max(1, h))
    m.R:ClearAllPoints(); m.R:SetPoint("TOPRIGHT", bar, "TOPRIGHT"); m.R:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT"); m.R:SetWidth(max(1, h))
    for _, t in ipairs(list or {}) do
      if t and not m.on[t] then pcall(t.AddMaskTexture, t, m.L); pcall(t.AddMaskTexture, t, m.R); m.on[t] = true end
    end
  end
  function U.apply(bar, rpx, h, extra)
    if not bar or not bar.CreateMaskTexture then return end
    local n = pick(rpx, h)
    bar.ccRoundPx, bar.ccRoundH = rpx, h
    local m = bar.ccRound
    if not m and not n then return end
    if not m then
      m = { L = bar:CreateMaskTexture(), R = bar:CreateMaskTexture(), on = {}, fol = {} }
      bar.ccRound = m
    end
    local targets = {}
    local fill = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
    if fill then targets[1] = fill end
    for _, t in ipairs(extra or {}) do if t then targets[#targets + 1] = t end end
    for t in pairs(m.fol) do targets[#targets + 1] = t end
    if not n then
      for t in pairs(m.on) do pcall(t.RemoveMaskTexture, t, m.L); pcall(t.RemoveMaskTexture, t, m.R) end
      m.on = {}; m.active = false
      return
    end
    m.L:SetTexture(CAP .. "L" .. n, "CLAMPTOWHITE", "CLAMPTOWHITE")
    m.R:SetTexture(CAP .. "R" .. n, "CLAMPTOWHITE", "CLAMPTOWHITE")
    m.L:ClearAllPoints(); m.L:SetPoint("TOPLEFT", bar, "TOPLEFT"); m.L:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT"); m.L:SetWidth(max(1, h))
    m.R:ClearAllPoints(); m.R:SetPoint("TOPRIGHT", bar, "TOPRIGHT"); m.R:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT"); m.R:SetWidth(max(1, h))
    for _, t in ipairs(targets) do
      if not m.on[t] then pcall(t.AddMaskTexture, t, m.L); pcall(t.AddMaskTexture, t, m.R); m.on[t] = true end
    end
    m.active = true
  end
  -- extra textures that should follow a bar's rounding (animation pieces, trail)
  function U.follow(bar, tex)
    if bar and tex then
      bar.ccFol = bar.ccFol or {}; bar.ccFol[tex] = true
      if bar.ccArtPill and S.UFArt then pcall(S.UFArt.follow, bar, tex) end
    end
    local m = bar and bar.ccRound
    if not (m and tex) then return end
    m.fol[tex] = true
    if not m.active or m.on[tex] then return end
    pcall(tex.AddMaskTexture, tex, m.L); pcall(tex.AddMaskTexture, tex, m.R); m.on[tex] = true
  end
  -- all bars of a frame, from the frame's roundness
  function U.frame(f, w, h)
    local k = S.__ufK or style().round or 0
    local r = (RADIUS[k] or 0) * cornerSize(w, h) / 12
    local pad = innerPad(w, h)
    local br = max(0, r - pad + 1)
    local c = f.cfg
    local rb = c.roundBars or {}
    -- Size > Bar roundness: a bar's own setting (0-5), or match the frame (-1 / nil)
    local function own(key, bh) local v = rb[key]; if type(v) == "number" and v >= 0 then return (RADIUS[v] or 0) * cornerSize(w, bh) / 12 end end
    local ph = c.powerH or 0
    local hh = max(1, h - 2 * pad - (ph > 0 and (ph + 1) or 0))
    if S.UFArt and S.UFArt.on(f) then
      -- Artistic theme: the bars are clipped as one pill by S.UFArt - no per-bar corners on top of that
      U.apply(f.health, 0, 1); U.apply(f.power, 0, 1)
    else
      U.apply(f.health, own("health", hh) or br, hh, { f.health.bg, f.absorb })
      if ph > 0 then U.apply(f.power, own("power", ph) or min(br, ph / 2), ph, { f.power.bg }) end
    end
    if c.castbar then
      local ch = c.castH or 16
      U.apply(f.cast, own("cast", ch) or (RADIUS[k] or 0) * cornerSize(w, ch) / 12, ch)
    end
  end
end

-- Bar animations (Effects tab): an overlay clipped to the bar's filled part, so it never needs the
-- (maybe hidden) health value. One driver updates every animated bar that's on screen.
S.UFAnim = { bars = {}, LIST = {
  { value = "none", text = "None" }, { value = "shimmer", text = "Shimmer" }, { value = "pulse", text = "Pulse" },
  { value = "sparkle", text = "Sparkle" },
  { value = "wave", text = "Wave" }, { value = "heartbeat", text = "Heartbeat" }, { value = "scan", text = "Scanline" },
  { value = "embers", text = "Embers" }, { value = "rainbow", text = "Colour cycle" },
  { value = "lightning", text = "Lightning" }, { value = "bubbles", text = "Bubbles" }, { value = "comet", text = "Comet" },
  { value = "glitter", text = "Glitter" } },
  FRAME = { { value = "none", text = "None" }, { value = "glow", text = "Glowing edge" }, { value = "breathe", text = "Breathing border" },
    { value = "runner", text = "Running light" }, { value = "twin", text = "Twin lights" }, { value = "corners", text = "Corner flares" },
    { value = "halo", text = "Expanding halo" }, { value = "rainbow", text = "Rainbow border" } } }
do
  local A = S.UFAnim
  local M = "Interface\\AddOns\\CommandCenter\\Media\\Anim\\"
  local function tex(layer, file, wrap)
    local t = layer:CreateTexture(nil, "OVERLAY")
    if wrap then t:SetTexture(M .. file, "REPEAT", "REPEAT") else t:SetTexture(M .. file) end
    t:SetBlendMode("ADD"); t:Hide()
    return t
  end
  -- (re)build the overlay of one bar for an animation kind
  function A.set(bar, kind)
    kind = kind or "none"
    local o = bar.ccAnim
    if kind == "none" then if o then o.clip:Hide(); A.bars[bar] = nil; o.kind = "none" end return end
    if not o then
      o = { parts = {} }
      o.clip = CreateFrame("Frame", nil, bar)
      if o.clip.SetClipsChildren then o.clip:SetClipsChildren(true) end
      o.layer = CreateFrame("Frame", nil, o.clip); o.layer:SetAllPoints(bar)
      bar.ccAnim = o
    end
    local fill = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
    o.clip:ClearAllPoints()
    if fill then o.clip:SetPoint("TOPLEFT", fill, "TOPLEFT"); o.clip:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT") else o.clip:SetAllPoints(bar) end
    o.clip:SetFrameLevel(bar:GetFrameLevel() + 1)
    if o.kind ~= kind then
      for _, t in ipairs(o.parts) do t:Hide() end
      o.parts = {}
      local L = o.layer
      if kind == "shimmer" then o.parts[1] = tex(L, "shine")
      elseif kind == "pulse" or kind == "heartbeat" or kind == "rainbow" then
        local t = L:CreateTexture(nil, "OVERLAY"); t:SetTexture(WHITE); t:SetAllPoints(o.clip)
        t:SetBlendMode(kind == "rainbow" and "BLEND" or "ADD"); o.parts[1] = t
      elseif kind == "stripes" then local t = tex(L, "stripes", true); t:SetAllPoints(bar); o.parts[1] = t
      elseif kind == "wave" then local t = tex(L, "wave", true); t:SetAllPoints(bar); o.parts[1] = t
      elseif kind == "edge" then
        local g = tex(bar, "glow"); o.parts[1] = g                      -- not clipped: sits on the fill's end
      elseif kind == "sparkle" then for i = 1, 6 do o.parts[i] = tex(L, "star") end
      elseif kind == "scan" then o.parts[1] = tex(L, "scan")
      elseif kind == "embers" then for i = 1, 8 do o.parts[i] = tex(L, "dot") end
      elseif kind == "lightning" then
        for i = 1, 3 do local t = L:CreateTexture(nil, "OVERLAY"); t:SetTexture(WHITE); t:SetBlendMode("ADD"); t:Hide(); o.parts[i] = t end
        o.parts[4] = (function() local t = L:CreateTexture(nil, "OVERLAY"); t:SetTexture(WHITE); t:SetBlendMode("ADD"); t:SetAllPoints(o.clip); t:Hide(); return t end)()
      elseif kind == "bubbles" then for i = 1, 7 do local t = tex(L, "bubble"); t:SetBlendMode("BLEND"); o.parts[i] = t end
      elseif kind == "comet" then o.parts[1] = tex(L, "shine"); o.parts[2] = tex(L, "glow"); o.parts[3] = tex(L, "dot")
      elseif kind == "rings" then for i = 1, 3 do o.parts[i] = tex(bar, "glow") end      -- at the fill's end, not clipped
      elseif kind == "glitter" then for i = 1, 14 do o.parts[i] = tex(L, "dot") end end
      o.kind = kind
      o.seed = {}
      for i = 1, #o.parts do o.seed[i] = { math.random(), math.random(), math.random(), math.random() } end
    end
    o.fill = fill
    if kind == "edge" and fill then
      local g = o.parts[1]; g:ClearAllPoints()
      local rev = bar.GetReverseFill and bar:GetReverseFill()
      g:SetPoint("CENTER", fill, rev and "LEFT" or "RIGHT", 0, 0)
    end
    if bar.ccRoundPx then pcall(S.UFRound.applyTo, o.layer, bar, bar.ccRoundPx, bar.ccRoundH, o.parts) end
    if bar.ccArtPill and S.UFArt then pcall(S.UFArt.extra, bar, o.layer, o.parts) end
    o.clip:Show()
    A.bars[bar] = o
    A.driver:Show()
  end
  local function hsv(h)
    local i = floor(h * 6) % 6; local f = h * 6 - floor(h * 6)
    local q, t = 1 - f, f
    if i == 0 then return 1, t, 0 elseif i == 1 then return q, 1, 0 elseif i == 2 then return 0, 1, t
    elseif i == 3 then return 0, q, 1 elseif i == 4 then return t, 0, 1 else return 1, 0, q end
  end
  -- every animation's alpha goes through SA: x the glow strength (Effects > Glow strength)
  local curStr = 1
  local function SA(t, a) t:SetAlpha(min(1, max(0, (a or 0) * curStr))) end
  function A.step(bar, o, now)
    curStr = o.str or 1
    local W, H = bar:GetWidth(), bar:GetHeight()
    if not W or W <= 0 or not H or H <= 0 then return end
    local k, P = o.kind, o.parts
    local cr, cg, cb = 1, 1, 1
    if type(o.col) == "table" then cr, cg, cb = o.col[1] or 1, o.col[2] or 1, o.col[3] or 1 end
    if k ~= "rainbow" and k ~= "embers" then for _, t in ipairs(P) do t:SetVertexColor(cr, cg, cb) end end
    if k == "shimmer" then
      local per = 2.2; local p = (now % per) / per
      local bw = max(16, H * 2.5)
      local t = P[1]; t:SetSize(bw, H); t:ClearAllPoints(); t:SetPoint("LEFT", bar, "LEFT", -bw + (W + bw) * min(1, p * 1.4), 0)
      SA(t, 0.55); t:Show()
    elseif k == "pulse" then
      SA(P[1], 0.06 + 0.16 * (0.5 + 0.5 * math.sin(now * 3))); P[1]:Show()
    elseif k == "heartbeat" then
      local p = now % 1.3
      local a = math.exp(-((p - 0.1) / 0.06) ^ 2) + 0.7 * math.exp(-((p - 0.32) / 0.06) ^ 2)
      SA(P[1], 0.28 * a); P[1]:Show()
    elseif k == "rainbow" then
      local r, g, b = hsv((now * 0.12) % 1); P[1]:SetVertexColor(r, g, b); SA(P[1], 0.3); P[1]:Show()
    elseif k == "stripes" then
      local off = (now * 0.8) % 1
      P[1]:SetTexCoord(-off, W / 32 - off, 0, H / 32); SA(P[1], 0.35); P[1]:Show()
    elseif k == "wave" then
      local off = (now * 0.35) % 1
      P[1]:SetTexCoord(off, W / 96 + off, 0, 1); SA(P[1], 0.3); P[1]:Show()
    elseif k == "edge" then
      local g = P[1]; g:SetSize(H * 2.2, H * 2.2); SA(g, 0.45 + 0.35 * math.sin(now * 5)); g:Show()
    elseif k == "sparkle" then
      for i, t in ipairs(P) do
        local sd = o.seed[i]; local per = 1.4 + sd[3]
        local p = ((now + sd[1] * per) % per) / per
        if p < 0.05 then sd[2] = math.random() end                     -- new spot each cycle
        local sz = H * (0.7 + sd[3] * 0.6)
        t:SetSize(sz, sz); t:ClearAllPoints(); t:SetPoint("CENTER", bar, "LEFT", sd[2] * W, (sd[1] - 0.5) * H * 0.6)
        SA(t, math.max(0, math.sin(p * math.pi)) * 0.9); t:Show()
      end
    elseif k == "scan" then
      local p = (now % 1.6) / 1.6
      local t = P[1]; t:SetSize(W, max(2, H * 0.25)); t:ClearAllPoints(); t:SetPoint("CENTER", bar, "TOP", 0, -p * H)
      SA(t, 0.5); t:Show()
    elseif k == "lightning" then
      -- crackles: a few bright vertical bolts that flicker, plus a faint flash now and then
      local beat = floor(now * 9)
      if beat ~= o.beat then o.beat = beat; for _, sd in ipairs(o.seed) do sd[1], sd[2] = math.random(), math.random() end end
      for i = 1, 3 do
        local t, sd = P[i], o.seed[i]
        t:SetSize(max(1, H * 0.08), H); t:ClearAllPoints(); t:SetPoint("CENTER", bar, "LEFT", sd[1] * W, 0)
        SA(t, sd[2] > 0.55 and 0.9 or 0); t:Show()
      end
      SA(P[4], (o.seed[4][2] > 0.9) and 0.25 or 0); P[4]:Show()
    elseif k == "bubbles" then
      for i, t in ipairs(P) do
        local sd = o.seed[i]; local per = 2 + sd[3] * 1.5
        local p = ((now + sd[1] * per) % per) / per
        if p < 0.03 then sd[2] = math.random() end
        -- rise and wobble, grow a little, then pop (quick swell + fade) near the top
        local base = H * (0.3 + 0.35 * sd[3])
        local sz = base * (1 + 0.25 * p)
        local a = (p < 0.15) and (p / 0.15) or 1
        if p > 0.85 then local q = (p - 0.85) / 0.15; sz = sz * (1 + 0.6 * q); a = 1 - q end
        t:SetSize(sz, sz); t:ClearAllPoints(); t:SetPoint("CENTER", bar, "BOTTOMLEFT", sd[2] * W + math.sin(p * 9 + i) * H * 0.15, p * H * 0.95)
        if type(o.col) ~= "table" then t:SetVertexColor(0.85, 0.95, 1) end
        SA(t, a * 0.9); t:Show()
      end
    elseif k == "comet" then
      local p = (now % 1.8) / 1.8
      local x = -H + (W + 2 * H) * p
      local tail, head, core = P[1], P[2], P[3]
      tail:SetSize(H * 4, H); tail:ClearAllPoints(); tail:SetPoint("RIGHT", bar, "LEFT", x, 0); SA(tail, 0.45); tail:Show()
      head:SetSize(H * 1.8, H * 1.8); head:ClearAllPoints(); head:SetPoint("CENTER", bar, "LEFT", x, 0); SA(head, 0.8); head:Show()
      core:SetSize(H * 0.5, H * 0.5); core:ClearAllPoints(); core:SetPoint("CENTER", bar, "LEFT", x, 0); core:SetVertexColor(1, 1, 1); SA(core, 1); core:Show()
    elseif k == "rings" then
      local rev = bar.GetReverseFill and bar:GetReverseFill()
      for i, t in ipairs(P) do
        local p = ((now * 0.8) + (i - 1) / #P) % 1
        local sz = H * (0.6 + 2.6 * p)
        t:SetSize(sz, sz); t:ClearAllPoints()
        if o.fill then t:SetPoint("CENTER", o.fill, rev and "LEFT" or "RIGHT", 0, 0) else t:SetPoint("CENTER", bar, "RIGHT", 0, 0) end
        SA(t, 0.7 * (1 - p)); t:Show()
      end
    elseif k == "glitter" then
      for i, t in ipairs(P) do
        local sd = o.seed[i]; local per = 0.5 + sd[3] * 0.6
        local p = ((now + sd[1] * per) % per) / per
        if p < 0.08 then sd[2] = math.random(); sd[4] = math.random() end
        local sz = max(2, H * (0.18 + sd[3] * 0.2))
        t:SetSize(sz, sz); t:ClearAllPoints(); t:SetPoint("CENTER", bar, "BOTTOMLEFT", sd[2] * W, (sd[4] or 0.5) * H)
        SA(t, math.sin(p * math.pi)); t:Show()
      end
    elseif k == "embers" then
      for i, t in ipairs(P) do
        local sd = o.seed[i]; local per = 1.2 + sd[3] * 1.2
        local p = ((now + sd[1] * per) % per) / per
        if p < 0.04 then sd[2] = math.random() end
        local sz = max(3, H * 0.35)
        t:SetSize(sz, sz); t:ClearAllPoints()
        t:SetPoint("CENTER", bar, "BOTTOMLEFT", sd[2] * W + math.sin(p * 6 + i) * 3, p * H * 1.1)
        if type(o.col) == "table" then t:SetVertexColor(cr, cg, cb) else t:SetVertexColor(1, 0.75 - p * 0.4, 0.3) end
        SA(t, (1 - p) * 0.85); t:Show()
      end
    end
  end
  A.driver = CreateFrame("Frame"); A.driver:Hide()
  A.driver:SetScript("OnUpdate", function(self)
    local now = GetTime() * (style().animSpeed or 1)
    local any = false
    for bar, o in pairs(A.bars) do
      if bar:IsVisible() then any = true; pcall(A.step, bar, o, now) end
    end
    local frames = A.frames
    if frames then
      for fr, o in pairs(frames) do
        if fr:IsVisible() then pcall(A.fstep, fr, o, now) end
      end
    end
    if not next(A.bars) and not (frames and next(frames)) then self:Hide() end
  end)
  -- apply the chosen animations to one frame's bars
  -- r98: animations are per frame (f.cfg); the old all-frames settings move once (A.migrate)
  function A.migrate()
    local d = store()
    if d.animMoved then return end
    d.animMoved = true
    local st = d.style or {}
    local an = st.anim or {}
    local function on(v) return v and v ~= "none" end
    if on(an.health) or on(an.power) or on(an.cast) then
      local pc = cfg("player")
      pc.anim = { health = an.health or "none", power = an.power or "none", cast = an.cast or "none" }
      pc.animCol = S.Copy(st.animCol or {}); pc.animStr = S.Copy(st.animStr or { health = 1, power = 1, cast = 1 })
    end
    if on(st.frameAnim) then
      local sc = st.frameAnimScope or "player"
      for _, key in ipairs(KEYS) do
        if sc == "all" or key == "player" or (sc == "pt" and (key == "target" or key == "focus")) then
          local c = cfg(key)
          c.frameAnim, c.frameAnimCol, c.frameAnimStr = st.frameAnim, S.Copy(st.frameAnimCol or { 1, 0.82, 0.3 }), st.frameAnimStr or 1
        end
      end
    end
  end
  function A.frame(f)
    pcall(A.migrate)
    local st, fc = style(), f.cfg
    local an, ac = fc.anim or {}, fc.animCol or {}
    local function k(v) return (v == "edge" or v == "stripes" or v == "rings") and "none" or v end   -- rings removed (r99)   -- edge moved to frame animations (r91), stripes removed (r93)
    A.set(f.health, k(an.health)); A.set(f.power, (f.cfg.powerH or 0) > 0 and k(an.power) or "none"); A.set(f.cast, k(an.cast))
    local as = fc.animStr or {}
    if f.health.ccAnim then f.health.ccAnim.col = ac.health; f.health.ccAnim.str = as.health or 1 end
    if f.power.ccAnim then f.power.ccAnim.col = ac.power; f.power.ccAnim.str = as.power or 1 end
    if f.cast.ccAnim then f.cast.ccAnim.col = ac.cast; f.cast.ccAnim.str = as.cast or 1 end
    A.fset(f, fc.frameAnim or "none")
  end
  -- frame animations: around the whole frame (Effects > Frame)
  A.frames = {}
  function A.fset(f, kind)
    local o = f.ccFAnim
    if kind == "none" then if o then o.box:Hide(); A.frames[f] = nil; o.kind = "none" end return end
    if not o then
      o = {}
      o.box = CreateFrame("Frame", nil, f); o.box:SetAllPoints(f)
      f.ccFAnim = o
    end
    o.box:SetFrameLevel(f.ui:GetFrameLevel() + 1)
    if o.kind ~= kind then
      for _, t in ipairs(o.parts or {}) do t:Hide() end
      o.parts = {}
      local B = o.box
      if kind == "glow" then
        -- one soft glow laid round the frame (9-slice of Anim\edgeglow: bright at the frame's edge, fading out)
        local set = newBox(B, "OVERLAY", 0, true)
        for _, t in ipairs(set.parts) do t:SetBlendMode("ADD"); o.parts[#o.parts + 1] = t end
        o.glowSet, o.glowK = set, nil
      elseif kind == "halo" then
        local t = B:CreateTexture(nil, "BACKGROUND"); t:SetTexture(M .. "glow"); t:SetBlendMode("ADD"); o.parts[1] = t
      elseif kind == "breathe" or kind == "rainbow" then
        -- the frame's own (rounded) edge, lit up
        local set = newBox(B, "OVERLAY", 0, true)
        for _, t in ipairs(set.parts) do t:SetBlendMode("ADD"); o.parts[#o.parts + 1] = t end
        o.edgeSet, o.edgeKey = set, nil
      elseif kind == "runner" or kind == "twin" then
        for i = 1, (kind == "twin" and 2 or 1) do
          local t = B:CreateTexture(nil, "OVERLAY"); t:SetTexture(M .. "glow"); t:SetBlendMode("ADD"); o.parts[#o.parts + 1] = t
          local c2 = B:CreateTexture(nil, "OVERLAY"); c2:SetTexture(M .. "dot"); c2:SetBlendMode("ADD"); o.parts[#o.parts + 1] = c2
        end
      elseif kind == "corners" then
        for i = 1, 4 do local t = B:CreateTexture(nil, "OVERLAY"); t:SetTexture(M .. "star"); t:SetBlendMode("ADD"); o.parts[i] = t end
      end
      o.kind = kind
    end
    o.box:Show()
    A.frames[f] = o
    A.driver:Show()
  end
  -- a point on the frame's outline, d = 0..1 going clockwise from the top-left corner
  -- a point on the frame's outline (rounded corners of radius rad), d = 0..1 clockwise from the top-left
  local function perim(W, H, d, rad)
    rad = min(rad or 0, W / 2, H / 2)
    local sw, sh = W - 2 * rad, H - 2 * rad
    local arc = math.pi * rad / 2
    local segs = { sw, arc, sh, arc, sw, arc, sh, arc }
    local L = 0; for _, v in ipairs(segs) do L = L + v end
    local x = (d % 1) * L
    local function corner(cx, cy, a0, t) local a = a0 - t * math.pi / 2; return cx + rad * math.cos(a), cy + rad * math.sin(a) end
    if x < sw then return rad + x, 0 end; x = x - sw
    if x < arc then return corner(W - rad, -rad, math.pi / 2, x / arc) end; x = x - arc
    if x < sh then return W, -rad - x end; x = x - sh
    if x < arc then return corner(W - rad, -(H - rad), 0, x / arc) end; x = x - arc
    if x < sw then return W - rad - x, -H end; x = x - sw
    if x < arc then return corner(rad, -(H - rad), -math.pi / 2, x / arc) end; x = x - arc
    if x < sh then return 0, -(H - rad) + x end; x = x - sh
    return corner(rad, -rad, math.pi, min(1, x / max(0.001, arc)))
  end
  -- (made once: these were new tables on every frame for every animated frame)
  local NOCOL = {}
  local SIDE = { TL = 0, T = 0, TR = 0.25, R = 0.25, BR = 0.5, B = 0.5, BL = 0.75, L = 0.75 }
  local CORNER_PTS = { "TOPLEFT", "TOPRIGHT", "BOTTOMRIGHT", "BOTTOMLEFT" }
  function A.fstep(f, o, now)
    curStr = (f.cfg and f.cfg.frameAnimStr) or 1
    local W, H = f:GetWidth(), f:GetHeight()
    if not W or W <= 0 or not H or H <= 0 then return end
    local rk = f.cfg and f.cfg.round
    local fk = (type(rk) == "number" and rk >= 0) and rk or (style().round or 0)    -- this frame's roundness
    local frad = (RADIUS[fk] or 0) * cornerSize(W, H) / 12                        -- its corner radius in px
    local c = (f.cfg and f.cfg.frameAnimCol) or NOCOL
    local r, g, b = c[1] or 1, c[2] or 0.82, c[3] or 0.3
    local P, k = o.parts, o.kind
    if k == "glow" then
      if o.glowSet and o.glowK ~= fk then boxLayout(o.glowSet, M .. "edgeglow" .. fk, 24, 14); o.glowK = fk end
      for _, t in ipairs(P) do t:SetVertexColor(r, g, b); SA(t, 1); t:Show() end
    elseif k == "halo" then
      local p = (now % 1.8) / 1.8; local out = 4 + p * 22
      local t = P[1]; t:ClearAllPoints(); t:SetPoint("TOPLEFT", f, "TOPLEFT", -out, out); t:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", out, -out)
      t:SetVertexColor(r, g, b); SA(t, 0.8 * (1 - p)); t:Show()
    elseif k == "breathe" or k == "rainbow" then
      local a = (k == "breathe") and (0.35 + 0.55 * (0.5 + 0.5 * math.sin(now * 2.2))) or 0.85
      local key = fk .. ":" .. floor(W) .. "x" .. floor(H)
      if o.edgeSet and o.edgeKey ~= key then boxLayout(o.edgeSet, UI.MEDIA .. "UI\\ufedge" .. fk, cornerSize(W, H)); o.edgeKey = key end
      for name, t in pairs(o.edgeSet or NOCOL) do
        if type(t) == "table" and t.SetVertexColor and SIDE[name] then
          if k == "rainbow" then local rr, gg, bb = hsv((now * 0.15 + SIDE[name]) % 1); t:SetVertexColor(rr, gg, bb) else t:SetVertexColor(r, g, b) end
          SA(t, a); t:Show()
        end
      end
    elseif k == "runner" or k == "twin" then
      local n = #P / 2
      for i = 1, n do
        local d = (now * 0.35 + (i - 1) / n) % 1
        local x, y = perim(W, H, d, frad)
        local gl, dot = P[i * 2 - 1], P[i * 2]
        gl:SetSize(28, 28); gl:ClearAllPoints(); gl:SetPoint("CENTER", f, "TOPLEFT", x, y); gl:SetVertexColor(r, g, b); SA(gl, 0.8); gl:Show()
        dot:SetSize(8, 8); dot:ClearAllPoints(); dot:SetPoint("CENTER", f, "TOPLEFT", x, y); dot:SetVertexColor(1, 1, 1); SA(dot, 0.95); dot:Show()
      end
    elseif k == "corners" then
      for i, t in ipairs(P) do
        local p = ((now * 0.9) - (i - 1) * 0.25) % 1
        local sz = 10 + 14 * math.sin(p * math.pi)
        local inset = frad * 0.29                                       -- sit on the rounded corner, not the box corner
        local ix = (i == 1 or i == 4) and inset or -inset
        local iy = (i <= 2) and -inset or inset
        t:SetSize(sz, sz); t:ClearAllPoints(); t:SetPoint("CENTER", f, CORNER_PTS[i], ix, iy)
        t:SetVertexColor(r, g, b); SA(t, math.max(0, math.sin(p * math.pi))); t:Show()
      end
    end
  end
end

-- Reactive effects (Reactions tab): something happens when health / power goes down or up, or combo
-- points are gained / spent. Direction needs a readable value; the damage trail works even when the game
-- hides the numbers (a second bar follows the real one a moment later, both fed the same hidden value).
S.UFReact = { fx = {},
  HP_LOSS = { { value = "none", text = "Nothing" }, { value = "flash", text = "Red flash" }, { value = "shake", text = "Shake" },
    { value = "trail", text = "Damage trail" }, { value = "flash+trail", text = "Flash + trail" }, { value = "shake+trail", text = "Shake + trail" },
    { value = "flash+shake+trail", text = "Flash + shake + trail" } },
  GAIN = { { value = "none", text = "Nothing" }, { value = "flash", text = "Flash" }, { value = "glow", text = "Glow around the frame" },
    { value = "sparkle", text = "Rising sparkles" }, { value = "flash+sparkle", text = "Flash + sparkles" } },
  PP_LOSS = { { value = "none", text = "Nothing" }, { value = "flash", text = "Flash" }, { value = "trail", text = "Trail" }, { value = "flash+trail", text = "Flash + trail" } },
  COMBO = { { value = "none", text = "Nothing" }, { value = "pop", text = "Pop" }, { value = "flash", text = "Flash" }, { value = "pop+flash", text = "Pop + flash" } },
  SPEND = { { value = "none", text = "Nothing" }, { value = "burst", text = "Burst" } },
  SCOPE = { { value = "player", text = "My frame only" }, { value = "pt", text = "Me, target, focus" }, { value = "all", text = "Every frame" } },
}
do
  local R = S.UFReact
  local function cfgR() return style().react or {} end
  local function RA(t, a) t:SetAlpha(min(1, max(0, (a or 0) * (cfgR().strength or 1)))) end
  local function has(opt, word) return type(opt) == "string" and opt:find(word, 1, true) ~= nil end
  local DEFCOL = { hpLoss = { 1, 0.15, 0.1 }, hpGain = { 0.3, 1, 0.4 }, ppLoss = { 1, 1, 1 }, ppGain = { 0.55, 0.85, 1 }, combo = { 1, 1, 0.8 }, spend = { 1, 0.8, 0.3 }, trail = { 1, 0.85, 0.55 } }
  R.DEFCOL = DEFCOL
  -- Reactions > colour swatches
  function R.col(key)
    local t = (cfgR().col or {})[key]
    if type(t) ~= "table" or type(t[1]) ~= "number" then t = DEFCOL[key] end
    return t[1], t[2], t[3]
  end
  -- tiny tween driver: R.play(dur, fn(p)) calls fn with 0..1
  R.list = {}
  R.driver = CreateFrame("Frame"); R.driver:Hide()
  R.driver:SetScript("OnUpdate", function(self)
    local now = GetTime()
    for i = #R.list, 1, -1 do
      local t = R.list[i]
      local p = (now - t.t0) / t.dur
      pcall(t.fn, min(1, max(0, p)))
      if p >= 1 then table.remove(R.list, i) end
    end
    if #R.list == 0 then self:Hide() end
  end)
  function R.play(dur, fn) R.list[#R.list + 1] = { t0 = GetTime(), dur = dur, fn = fn }; R.driver:Show() end
  function R.scoped(f)
    local sc = cfgR().scope or "pt"
    if sc == "all" then return true end
    if sc == "player" then return f.key == "player" end
    return f.key == "player" or f.key == "target" or f.key == "focus"
  end
  -- effect pieces ---------------------------------------------------------
  function R.fx.flash(bar, r, g, b, a)
    if not bar.ccFlash then
      local t = bar:CreateTexture(nil, "OVERLAY", nil, 6); t:SetTexture(WHITE); t:SetBlendMode("ADD"); t:SetAllPoints(bar); t:Hide()
      bar.ccFlash = t
      S.UFRound.follow(bar, t)
    end
    local t = bar.ccFlash
    t:SetVertexColor(r, g, b); t:Show()
    R.play(0.45, function(p) RA(t, (a or 0.6) * (1 - p)); if p >= 1 then t:Hide() end end)
  end
  function R.fx.glow(f, r, g, b)
    if not f.ccGlow then
      local t = f:CreateTexture(nil, "OVERLAY", nil, 7)
      t:SetTexture("Interface\\AddOns\\CommandCenter\\Media\\Anim\\glow"); t:SetBlendMode("ADD")
      t:SetPoint("TOPLEFT", f, "TOPLEFT", -10, 10); t:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 10, -10); t:Hide()
      f.ccGlow = t
    end
    local t = f.ccGlow
    t:SetVertexColor(r, g, b); t:Show()
    R.play(0.7, function(p) RA(t, 0.9 * math.sin(p * math.pi)); if p >= 1 then t:Hide() end end)
  end
  function R.fx.sparkle(bar, r, g, b)
    bar.ccSpk = bar.ccSpk or {}
    local fill = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
    local H = bar:GetHeight() or 10
    for i = 1, 4 do
      local t = bar.ccSpk[i]
      if not t then
        t = bar:CreateTexture(nil, "OVERLAY", nil, 7); t:SetTexture("Interface\\AddOns\\CommandCenter\\Media\\Anim\\star"); t:SetBlendMode("ADD"); t:Hide()
        bar.ccSpk[i] = t
        S.UFRound.follow(bar, t)
      end
      local dx, delay = (math.random() - 0.5) * H * 1.6, (i - 1) * 0.06
      t:SetVertexColor(r, g, b); t:SetSize(H * 0.9, H * 0.9)
      R.play(0.6 + delay, function(p)
        local q = max(0, (p * (0.6 + delay) - delay) / 0.6)
        t:ClearAllPoints()
        if fill then t:SetPoint("CENTER", fill, "RIGHT", dx, q * H * 1.4) else t:SetPoint("CENTER", bar, "CENTER", dx, q * H * 1.4) end
        RA(t, q > 0 and (1 - q) or 0); t:SetShown(q > 0 and q < 1)
      end)
    end
  end
  function R.fx.shake(f)
    for _, part in ipairs({ f.health, f.power, f.ui }) do
      if part and part.CreateAnimationGroup then
        if not part.ccShake then
          local ag = part:CreateAnimationGroup()
          local amp, steps = 3, { 1, -2, 2, -2, 1 }
          for i, m in ipairs(steps) do
            local a = ag:CreateAnimation("Translation"); a:SetOffset(m * amp, 0); a:SetDuration(0.04); a:SetOrder(i)
          end
          part.ccShake = ag
        end
        if not part.ccShake:IsPlaying() then part.ccShake:Play() end
      end
    end
  end
  -- trail bar behind a bar (shows the chunk just lost, then catches up)
  function R.trail(bar, on)
    local t = bar.ccTrail
    if not on then
      if t then t:Hide(); if bar.bg then bar.bg:SetAlpha(1) end end
      return nil
    end
    if not t then
      t = CreateFrame("StatusBar", nil, bar)
      t:SetAllPoints(bar); t:SetFrameLevel(max(0, bar:GetFrameLevel() - 1)); t:SetMinMaxValues(0, 1)
      t.bg = t:CreateTexture(nil, "BACKGROUND"); t.bg:SetAllPoints()
      bar.ccTrail = t
    end
    local fill = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
    local tex = (fill and fill.GetTexture and fill:GetTexture()) or WHITE
    pcall(t.SetStatusBarTexture, t, tex)
    if bar.bg then
      pcall(t.bg.SetTexture, t.bg, bar.bg:GetTexture() or WHITE)
      local r, g, b, a = bar.bg:GetVertexColor(); t.bg:SetVertexColor(r or 0, g or 0, b or 0, a or 0.9)
      bar.bg:SetAlpha(0)
    end
    if t.SetReverseFill and bar.GetReverseFill then t:SetReverseFill(bar:GetReverseFill() and true or false) end
    if bar.ccRoundPx then pcall(S.UFRound.apply, t, bar.ccRoundPx, bar.ccRoundH, { t.bg }) end
    if bar.ccArtPill and S.UFArt then pcall(S.UFArt.extra, bar, t, { t:GetStatusBarTexture(), t.bg }) end
    local tr, tg, tb = R.col("trail")
    t:SetStatusBarColor(tr, tg, tb, 0.9)
    t:Show()
    return t
  end
  local function smooth(bar, v)
    if Enum and Enum.StatusBarInterpolation and pcall(bar.SetValue, bar, v, Enum.StatusBarInterpolation.ExponentialEaseOut) then return end
    pcall(bar.SetValue, bar, v)
  end
  -- one bar's change: kind = "hp" or "pp"
  function R.bar(f, kind, bar, cur, mx)
    local c = cfgR()
    local lossOpt = kind == "hp" and c.hpLoss or c.ppLoss
    local gainOpt = kind == "hp" and c.hpGain or c.ppGain
    local on = R.scoped(f) and not f.fake
    local tr = R.trail(bar, on and has(lossOpt, "trail"))
    local lastKey = "ccR" .. kind
    if f.ccReactBase or not on then
      f[lastKey] = (not sec(cur)) and cur or nil
      if tr then pcall(tr.SetMinMaxValues, tr, 0, mx); pcall(tr.SetValue, tr, cur) end
      return
    end
    local last = f[lastKey]
    local dir
    if not sec(cur) and type(cur) == "number" and type(last) == "number" then
      if cur < last then dir = -1 elseif cur > last then dir = 1 else dir = 0 end
      -- ignore small changes (Reactions > Ignore changes under N%)
      if dir ~= 0 and (c.minPct or 0) > 0 and not sec(mx) and type(mx) == "number" and mx > 0 then
        if math.abs(cur - last) / mx * 100 < c.minPct then dir = 0 end
      end
    end
    f[lastKey] = (not sec(cur)) and cur or nil
    if tr then
      pcall(tr.SetMinMaxValues, tr, 0, mx)
      if dir == 1 then pcall(tr.SetValue, tr, cur)                    -- heals: no trail
      else
        f.ccTrailSeq = (f.ccTrailSeq or 0) + 1
        local seq = f.ccTrailSeq
        C_Timer.After(0.35, function() if f.ccTrailSeq == seq and tr:IsShown() then smooth(tr, cur) end end)
      end
    end
    if dir == -1 then
      if has(lossOpt, "flash") then local r, g, b = R.col(kind == "hp" and "hpLoss" or "ppLoss"); R.fx.flash(bar, r, g, b, kind == "hp" and 0.65 or 0.45) end
      if has(lossOpt, "shake") then R.fx.shake(f) end
    elseif dir == 1 then
      local r, g, b = R.col(kind == "hp" and "hpGain" or "ppGain")
      if has(gainOpt, "flash") then R.fx.flash(bar, r, g, b, 0.5) end
      if has(gainOpt, "glow") then R.fx.glow(f, r, g, b) end
      if has(gainOpt, "sparkle") then R.fx.sparkle(bar, r, g, b) end
    end
  end
  function R.health(f, cur, mx) R.bar(f, "hp", f.health, cur, mx) end
  function R.power(f, cur, mx) if f.power:IsShown() then R.bar(f, "pp", f.power, cur, mx) end end
  -- combo points: n lit now
  function R.combo(f, n)
    local c = cfgR()
    local last = f.ccRcombo
    f.ccRcombo = n
    if f.ccReactBase or type(last) ~= "number" or not R.scoped(f) then return end
    for i, p in ipairs(f.combo) do
      if not p.ccFx then
        local t = p:CreateTexture(nil, "OVERLAY", nil, 7); t:SetTexture(WHITE); t:SetBlendMode("ADD"); t:SetAllPoints(); t:Hide()
        p.ccFx = t
      end
      local t = p.ccFx
      if i <= n and i > last then
        if has(c.comboGain, "flash") then t:SetVertexColor(R.col("combo")); t:Show(); R.play(0.4, function(q) RA(t, 0.9 * (1 - q)); if q >= 1 then t:Hide() end end) end
        if has(c.comboGain, "pop") and p.CreateAnimationGroup then
          if not p.ccPop then
            local ag = p:CreateAnimationGroup()
            local a1 = ag:CreateAnimation("Scale"); a1:SetScale(1.45, 1.45); a1:SetDuration(0.09); a1:SetOrder(1)
            local a2 = ag:CreateAnimation("Scale"); a2:SetScale(1 / 1.45, 1 / 1.45); a2:SetDuration(0.14); a2:SetOrder(2)
            p.ccPop = ag
          end
          p.ccPop:Stop(); p.ccPop:Play()
        end
      elseif i > n and i <= last and c.comboSpend == "burst" then
        t:SetVertexColor(R.col("spend")); t:Show()
        R.play(0.5, function(q) RA(t, 1 - q); if q >= 1 then t:Hide() end end)
      end
    end
  end
  -- test mode: replay the reactions on every frame in "Show on" every 4.5 s while test mode is on
  function R.testLoop(on, frameList)
    R.loopId = (R.loopId or 0) + 1
    if not on then return end
    local id = R.loopId
    local function tick()
      if R.loopId ~= id then return end
      local comboFrame
      for _, f in ipairs(frameList) do
        if f.fake and f:IsVisible() and R.scoped(f) then
          pcall(R.preview, f, nil)
          if f.key == "target" then comboFrame = f end
        end
      end
      if comboFrame then pcall(R.preview, nil, comboFrame) end
      C_Timer.After(4.5, tick)
    end
    C_Timer.After(0.6, tick)
  end
  -- Reactions tab "Preview" button: plays everything on your frame (and combo points on the target frame)
  function R.preview(pf, tf)
    local c = cfgR()
    if pf then
      if has(c.hpLoss, "flash") then local r, g, b = R.col("hpLoss"); R.fx.flash(pf.health, r, g, b, 0.65) end
      if has(c.hpLoss, "shake") then R.fx.shake(pf) end
      if has(c.hpLoss, "trail") then
        local tr = R.trail(pf.health, true)
        local v = pf.health:GetValue()
        local lo, hi = pf.health:GetMinMaxValues()
        if tr and not sec(v, lo, hi) and type(v) == "number" then
          tr:SetMinMaxValues(lo or 0, hi or 1); tr:SetValue(min(hi or 1, v + ((hi or 1) - (lo or 0)) * 0.3))
          C_Timer.After(0.35, function() smooth(tr, v) end)
        end
      end
      C_Timer.After(0.9, function()
        local r, g, b = R.col("hpGain")
        if has(c.hpGain, "flash") then R.fx.flash(pf.health, r, g, b, 0.5) end
        if has(c.hpGain, "glow") then R.fx.glow(pf, r, g, b) end
        if has(c.hpGain, "sparkle") then R.fx.sparkle(pf.health, r, g, b) end
      end)
      C_Timer.After(1.7, function()
        local lr, lg, lb = R.col("ppLoss")
        local gr, gg, gb = R.col("ppGain")
        if has(c.ppLoss, "flash") then R.fx.flash(pf.power, lr, lg, lb, 0.45) end
        if has(c.ppGain, "flash") then C_Timer.After(0.5, function() R.fx.flash(pf.power, gr, gg, gb, 0.5) end) end
        if has(c.ppGain, "sparkle") then C_Timer.After(0.5, function() R.fx.sparkle(pf.power, gr, gg, gb) end) end
        if has(c.ppGain, "glow") then C_Timer.After(0.5, function() R.fx.glow(pf, gr, gg, gb) end) end
      end)
    end
    if tf and tf.combo then
      tf.ccReactBase = nil
      tf.ccRcombo = 0
      C_Timer.After(2.6, function() R.combo(tf, 3) end)
      C_Timer.After(3.4, function() R.combo(tf, 0); tf.ccRcombo = nil end)
    end
  end
end

-- Custom colours (Colours tab, per frame): c.col[key] = { r, g, b } replaces the normal colour; nil = normal.
-- Your own name can have its own colour on every frame it shows up on (style().myNameOn / myName).
S.UFCol = {
  KEYS = { "health", "healthBg", "power", "powerBg", "cast", "castBg", "frameBg", "border", "name", "hpText", "ppText", "level", "castText", "castTime" },
  LABEL = { health = "Health bar", healthBg = "Health background", power = "Power bar", powerBg = "Power background",
    cast = "Cast bar", castBg = "Cast bar background", frameBg = "Frame background", border = "Border",
    name = "Name", hpText = "Health text", ppText = "Power text", level = "Level", castText = "Cast text", castTime = "Cast timer" },
}
do
  local K = S.UFCol
  function K.get(c, key)
    local t = c and c.col and c.col[key]
    if type(t) == "table" and type(t[1]) == "number" then return t[1], t[2], t[3] end
  end
  function K.hex(r, g, b) return string.format("|cff%02x%02x%02x", floor(r * 255 + 0.5), floor(g * 255 + 0.5), floor(b * 255 + 0.5)) end
  function K.strip(s) return (tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
  function K.isMe(f)
    if f.fake then return f.key == "player" end
    return f.unit and bool(try(UnitIsUnit, f.unit, "player"))
  end
  -- the level string in the custom colour (keeps its trailing space)
  function K.level(c, lvs)
    local r, g, b = K.get(c, "level")
    if not r or lvs == "" then return lvs end
    return K.hex(r, g, b) .. K.strip(lvs):gsub(" $", "") .. "|r "
  end
  function K.health(f)
    local c = f.cfg
    local r, g, b = K.get(c, "health")
    if r then f.health:SetStatusBarColor(r, g, b) end
    local br, bg, bb = K.get(c, "healthBg")
    if br then f.health.bg:SetVertexColor(br, bg, bb, 0.95)
    elseif r then f.health.bg:SetVertexColor(r * 0.22, g * 0.22, b * 0.22, 0.95) end
    local tr, tg, tb = K.get(c, "hpText"); f.hpText:SetTextColor(tr or 1, tg or 1, tb or 1)
  end
  function K.power(f)
    local c = f.cfg
    local r, g, b = K.get(c, "power")
    if r then f.power:SetStatusBarColor(r, g, b) end
    local br, bg, bb = K.get(c, "powerBg")
    if br then f.power.bg:SetVertexColor(br, bg, bb, 0.95)
    elseif r then f.power.bg:SetVertexColor(r * 0.22, g * 0.22, b * 0.22, 0.95) end
    local tr, tg, tb = K.get(c, "ppText"); f.ppText:SetTextColor(tr or 1, tg or 1, tb or 1)
  end
  function K.name(f)
    local c, st = f.cfg, style()
    local r, g, b = K.get(c, "name")
    if st.myNameOn and K.isMe(f) then local m = st.myName or {}; r, g, b = m[1] or 1, m[2] or 0.82, m[3] or 0.2 end
    if r then f.nameText:SetTextColor(r, g, b) end
    local lr, lg, lb = K.get(c, "level")
    if lr then f.levelText:SetTextColor(lr, lg, lb); f.levelText:SetText(K.strip(f.levelText:GetText()))
    else f.levelText:SetTextColor(1, 1, 1) end
  end
  -- frame / cast bar backgrounds and borders, text colours on the cast bar
  function K.paint(f)
    local c, th, st = f.cfg, UI:Theme(), style()
    local er, eg, eb = K.get(c, "border")
    local edge = er and { er, eg, eb } or (st.border == "black" and { 0, 0, 0 } or th.edge)
    local fr, fg, fb = K.get(c, "frameBg")
    if fr or er then
      skinColor(f, fr and { fr, fg, fb } or th.bg, st.bgAlpha, edge)
      if f.nameBox then skinColor(f.nameBox, fr and { fr, fg, fb } or th.bg, max(0.6, st.bgAlpha), edge) end
      if f.levelBox then skinColor(f.levelBox, fr and { fr, fg, fb } or th.bg, max(0.6, st.bgAlpha), edge) end
      f.pline:SetVertexColor(edge[1], edge[2], edge[3], 1)
    end
    local cr, cg, cb = K.get(c, "castBg")
    if cr or er then skinColor(f.cast, cr and { cr, cg, cb } or th.field, 0.9, edge) end
    local tr, tg, tb = K.get(c, "castText"); if tr then f.cast.text:SetTextColor(tr, tg, tb) end
    local mr, mg, mb = K.get(c, "castTime"); if mr then f.cast.time:SetTextColor(mr, mg, mb) end
    K.health(f); if (c.powerH or 0) > 0 then K.power(f) end; K.name(f)
  end
  -- the cast bar's fill (only for casts you can interrupt; grey stays grey)
  function K.cast(cb, notInt)
    local r, g, b = K.get(cb.ccCfg, "cast")
    if r and not sec(notInt) and not notInt then cb:SetStatusBarColor(r, g, b) end
  end
end

-- colours from the theme
Paint = function(f)
  local th, st = UI:Theme(), style()
  local edge = st.border == "black" and { 0, 0, 0 } or th.edge
  skinColor(f, th.bg, st.bgAlpha, edge)
  f.pline:SetVertexColor(edge[1], edge[2], edge[3], st.border == "none" and 0.6 or 1)
  skinColor(f.cast, th.field, 0.9, edge)
  if f.nameBox then skinColor(f.nameBox, th.bg, max(0.6, st.bgAlpha), edge) end
  if f.levelBox then skinColor(f.levelBox, th.bg, max(0.6, st.bgAlpha), edge) end
  skinColor(f.mana2, { 0, 0, 0 }, 0.8, edge)
  for _, p in ipairs(f.combo) do
    skinColor(p, th.field, 0.9, edge)
    p.fill:SetVertexColor(th.gold[1], th.gold[2], th.gold[3], 1)
  end
  f.cast.text:SetTextColor(th.text[1], th.text[2], th.text[3]); f.cast.time:SetTextColor(th.text[1], th.text[2], th.text[3])
  f.status:SetTextColor(th.muted[1], th.muted[2], th.muted[3])
  pcall(S.UFCol.paint, f)
  if S.UFArt then pcall(S.UFArt.post, f) end
end

---------------------------------------------------------------------------
-- Made-up units for test mode
---------------------------------------------------------------------------
local FAKE = {
  { name = "Thrallgar", class = "SHAMAN", level = 60, hp = 0.82, pp = 0.64, ptype = 0, role = "HEALER" },
  { name = "Drekthar", class = "WARRIOR", level = 60, hp = 0.46, pp = 0.35, ptype = 1, role = "TANK", leader = true },
  { name = "Zuljinna", class = "HUNTER", level = 59, hp = 1, pp = 0.9, ptype = 0, role = "DAMAGER" },
  { name = "Morgrim", class = "WARLOCK", level = 60, hp = 0.23, pp = 0.71, ptype = 0, role = "DAMAGER", dead = false },
  { name = "Vashka", class = "ROGUE", level = 60, hp = 0.67, pp = 0.5, ptype = 3, role = "DAMAGER" },
  { name = "Garona", class = "MAGE", level = 58, hp = 0, pp = 0, ptype = 0, role = "DAMAGER", dead = true },
  { name = "Sylvaris", class = "DRUID", level = 60, hp = 0.91, pp = 0.4, ptype = 0, role = "HEALER" },
  { name = "Korrak", class = "PRIEST", level = 60, hp = 0.58, pp = 0.83, ptype = 0, role = "HEALER" },
  { name = "Brakkus", class = "PALADIN", level = 60, hp = 0.74, pp = 0.6, ptype = 0, role = "TANK" },
}
local FAKE_ENEMY = { name = "Ragnaros", level = -1, hp = 0.63, pp = 1, ptype = 0, enemy = true, class = "boss" }
local FAKE_ICONS = { 136048, 135953, 136085, 135940, 136075, 132333 }

---------------------------------------------------------------------------
-- Updates
---------------------------------------------------------------------------
local function setBar(bar, v)
  if style().smooth and Enum and Enum.StatusBarInterpolation then
    if pcall(bar.SetValue, bar, v, Enum.StatusBarInterpolation.ExponentialEaseOut) then return end
  end
  pcall(bar.SetValue, bar, v)
end

local function healthRGB(f, u, cur, mx)
  local c = f.cfg
  if not bool(try(UnitIsConnected, u)) then return 0.45, 0.45, 0.45 end
  if bool(try(UnitIsTapDenied, u)) then return 0.55, 0.55, 0.55 end
  local mode = c.healthColor
  if mode == "green" then return 0.3, 0.8, 0.25 end
  if mode == "dark" then return 0.16, 0.16, 0.16 end
  if mode == "gradient" and not sec(cur, mx) and mx and mx > 0 then
    local p = cur / mx
    if p > 0.5 then return (1 - p) * 2, 0.85, 0.2 end
    return 0.9, p * 2 * 0.85, 0.15
  end
  if mode ~= "reaction" and bool(try(UnitIsPlayer, u)) then
    local _, cls = try(UnitClass, u)
    local r, g, b = classColor(cls)
    if r then return r, g, b end
  end
  return reactionColor(u)
end

local function nameRGB(f, u)
  local mode = f.cfg.nameColor
  if mode == "class" and bool(try(UnitIsPlayer, u)) then
    local _, cls = try(UnitClass, u)
    local r, g, b = classColor(cls)
    if r then return r, g, b end
  end
  if mode == "theme" then local t = UI:Theme().gold; return t[1], t[2], t[3] end
  return 1, 1, 1
end

local function levelString(u)
  local lvl = try(UnitLevel, u)
  if sec(lvl) or lvl == nil then return "" end
  local cl = try(UnitClassification, u) or "normal"
  if sec(cl) then cl = "normal" end
  local col = (GetCreatureDifficultyColor and lvl > 0 and GetCreatureDifficultyColor(lvl))
    or (GetQuestDifficultyColor and lvl > 0 and GetQuestDifficultyColor(lvl)) or { r = 1, g = 0.82, b = 0 }
  local s = lvl <= 0 and "??" or tostring(lvl)
  if cl == "worldboss" then s = "Boss" elseif cl == "rareelite" then s = s .. "R+" elseif cl == "elite" then s = s .. "+" elseif cl == "rare" then s = s .. "R" end
  return string.format("|cff%02x%02x%02x%s|r ", (col.r or 1) * 255, (col.g or 1) * 255, (col.b or 1) * 255, s)
end

local function fmt(pattern, ...)
  local ok, out = pcall(string.format, pattern, ...)
  if ok then return out end
end
-- "46" from 46.2291...: works for plain and hidden numbers
-- UnitPowerPercent takes the power type 2nd: (unit, powerType, usePredicted, curve) - unlike UnitHealthPercent
function S.UFPowerPct(u, pred, curve)
  if not UnitPowerPercent then return nil end
  local pt = try(UnitPowerType, u)
  if sec(pt) then pt = nil end
  return UnitPowerPercent(u, pt, pred, curve)
end
local function pctText(p)
  if isNil(p) then return nil end
  if not sec(p) then return tostring(floor(p + 0.5)) end
  local s = fmt("%.0f", p)
  if isNil(s) then s = fmt("%d", p) end
  return s
end
local function fmtValue(mode, cur, mx, u, percentFn)
  if mode == "none" then return "" end
  if mode == "percent" or mode == "both" then
    local p
    if not sec(cur, mx) then p = (mx and mx > 0) and floor(cur / mx * 100 + 0.5) or 0
    elseif percentFn then p = try(percentFn, u, false, CurveConstants and CurveConstants.ScaleTo100) end
    local ps = pctText(p)
    if mode == "percent" then
      if isNil(ps) then return short(cur) end
      local s = fmt("%s%%", ps)
      if isNil(s) then return "" end
      return s
    end
    if isNil(ps) then return short(cur) end
    local s = fmt("%s  %s%%", short(cur), ps)
    if isNil(s) then return short(cur) end
    return s
  end
  if mode == "cur" then return short(cur) end
  if mode == "deficit" then
    if sec(cur, mx) then
      local miss = UnitHealthMissing and try(UnitHealthMissing, u)
      if isNil(miss) then return "" end
      local s = fmt("-%s", short(miss))
      if isNil(s) then return "" end
      return s
    end
    local d = (mx or 0) - (cur or 0)
    return d > 0 and ("-" .. short(d)) or ""
  end
  local s = fmt("%s / %s", short(cur), short(mx))
  if isNil(s) then return short(cur) end
  return s
end

local function UpdateHealth(f)
  local u, c = f.unit, f.cfg
  local cur, mx = UnitHealth(u), UnitHealthMax(u)
  pcall(f.health.SetMinMaxValues, f.health, 0, mx)
  setBar(f.health, cur)
  local r, g, b = healthRGB(f, u, cur, mx)
  if c.healthColor == "dark" then
    f.health:SetStatusBarColor(0.16, 0.16, 0.16)
    local cr, cg, cb2 = 0.55, 0.15, 0.15
    if bool(try(UnitIsPlayer, u)) then local _, cls = try(UnitClass, u); local x, y, z = classColor(cls); if x then cr, cg, cb2 = x, y, z end end
    f.health.bg:SetVertexColor(cr, cg, cb2, 0.9)
  else
    f.health:SetStatusBarColor(r, g, b)
    f.health.bg:SetVertexColor(r * 0.22, g * 0.22, b * 0.22, 0.95)
  end
  S.UFCol.health(f)
  pcall(S.UFReact.health, f, cur, mx)
  -- status
  local dead, ghost, off = bool(try(UnitIsDead, u)), bool(try(UnitIsGhost, u)), not bool(try(UnitIsConnected, u))
  local st = off and "Offline" or ghost and "Ghost" or dead and "Dead" or nil
  f.status:SetText(st or ""); f.status:SetShown(st ~= nil)
  if st then f.hpText:SetText("")
  else setText(f.hpText, fmtValue(c.healthText, cur, mx, u, UnitHealthPercent)) end
  -- incoming heals and absorbs (only when the game lets us read them)
  local w = f.health:GetWidth()
  if c.healPred and UnitGetIncomingHeals and not st then
    local inc = try(UnitGetIncomingHeals, u)
    if inc and not sec(inc, mx, cur) and inc > 0 and mx > 0 then
      f.pred:SetMinMaxValues(0, mx); f.pred:SetValue(min(inc, mx - cur)); f.pred:SetWidth(max(1, w))
      f.pred:SetStatusBarColor(0.3, 1, 0.4, 0.45); f.pred:Show()
    else f.pred:Hide() end
  else f.pred:Hide() end
  if c.absorb and UnitGetTotalAbsorbs and not st then
    local ab = try(UnitGetTotalAbsorbs, u)
    if ab and not sec(ab, mx) and ab > 0 and mx > 0 then
      f.absorb:ClearAllPoints()
      f.absorb:SetPoint("TOPRIGHT", f.health, "TOPRIGHT"); f.absorb:SetPoint("BOTTOMRIGHT", f.health, "BOTTOMRIGHT")
      f.absorb:SetWidth(max(1, w * min(1, ab / mx))); f.absorb:SetVertexColor(1, 1, 1, 0.35); f.absorb:Show()
    else f.absorb:Hide() end
  else f.absorb:Hide() end
end

local playerTick = { last = nil, spentAt = nil, kind = nil }
local function UpdatePower(f)
  local u, c = f.unit, f.cfg
  if (c.powerH or 0) <= 0 then return end
  local ptype, token = UnitPowerType(u)
  local cur, mx = UnitPower(u), UnitPowerMax(u)
  pcall(f.power.SetMinMaxValues, f.power, 0, mx)
  setBar(f.power, cur)
  local r, g, b = powerColor(ptype, token)
  f.power:SetStatusBarColor(r, g, b); f.power.bg:SetVertexColor(r * 0.22, g * 0.22, b * 0.22, 0.95)
  S.UFCol.power(f)
  pcall(S.UFReact.power, f, cur, mx)
  local noPower = (not sec(mx) and (mx or 0) <= 0) or bool(try(UnitIsDeadOrGhost, u))
  if c.powerText ~= "none" and f.power:GetHeight() >= 9 and not noPower then setText(f.ppText, fmtValue(c.powerText, cur, mx, u, S.UFPowerPct))
  else f.ppText:SetText("") end
  -- druid mana while shapeshifted
  if f.key == "player" and c.druidMana then
    local _, cls = UnitClass("player")
    local show = cls == "DRUID" and not sec(ptype) and ptype ~= 0
    if show then
      local m, mm = UnitPower("player", 0), UnitPowerMax("player", 0)
      pcall(f.mana2.SetMinMaxValues, f.mana2, 0, mm); pcall(f.mana2.SetValue, f.mana2, m)
      local mr, mg, mb = powerColor(0, "MANA"); f.mana2:SetStatusBarColor(mr, mg, mb); f.mana2.bg:SetVertexColor(0, 0, 0, 0.6)
    end
    if f.mana2:IsShown() ~= show then f.mana2:SetShown(show); afterCombat("lay" .. tostring(f), function() Layout(f) end) end
  end
end

local function portraitUpdate(f)
  local u, c = f.unit, f.cfg
  if c.portrait == "3d" then
    if bool(try(UnitIsVisible, u)) and bool(try(UnitIsConnected, u)) then
      f.model:ClearModel(); f.model:SetUnit(u)
      if f.model.SetPortraitZoom then f.model:SetPortraitZoom(1) end
      f.model:SetCamDistanceScale(1); f.model:Show()
    else
      f.model:ClearModel()
      if f.model.SetModel then try(f.model.SetModel, f.model, "Interface\\Buttons\\TalkToMeQuestionMark.m2") end
      if f.model.SetCamDistanceScale then f.model:SetCamDistanceScale(1.6) end
    end
  elseif c.portrait == "2d" then
    f.ptex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    SetPortraitTexture(f.ptex, u)
  elseif c.portrait == "class" then
    local _, cls = try(UnitClass, u)
    if sec(cls) then cls = nil end
    local tc = cls and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[cls]
    if tc and bool(try(UnitIsPlayer, u)) then
      f.ptex:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles"); f.ptex:SetTexCoord(unpack(tc))
    else f.ptex:SetTexCoord(0.08, 0.92, 0.08, 0.92); SetPortraitTexture(f.ptex, u) end
  end
end

local function UpdateName(f)
  local u, c = f.unit, f.cfg
  local la = f.ccLevelAt or "name"
  local lvs = c.level and S.UFCol.level(c, levelString(u)) or ""
  if la ~= "name" then
    local own = (la ~= "off") and lvs:gsub(" $", "") or ""
    f.levelText:SetText(own)
    if f.levelBox and (la == "beside" or la == "above" or la == "under") then f.levelBox:SetShown(own ~= "" and not f.ccArtLv) end
  end
  if not c.name then f.nameText:SetText(""); if f.ccArtLv then S.UFArt.level(f, lvs) end return end
  local nm = try(UnitName, u)
  if c.nameFull ~= false then local full = S.UFFullName(u); if full then nm = full end end
  -- streamer mode: your own name on any frame (target of target, focus, party...) shows your alias.
  -- (Those names can come back hidden, so the game-wide text hook can't read and swap them.)
  if u ~= "player" and S.StreamHidingName and S.StreamHidingName() and S.StreamAlias then
    local me = try(UnitIsUnit, u, "player")
    if sec(me) then me = nil end
    if me == nil then
      local g1, g2 = try(UnitGUID, u), try(UnitGUID, "player")
      if type(g1) == "string" and type(g2) == "string" and not sec(g1) and not sec(g2) then me = (g1 == g2) end
    end
    if me == true then nm = S.StreamAlias() end
  end
  if f.ccArtLv then S.UFArt.level(f, lvs) end
  local lv = (la == "name" and not f.ccArtLv) and lvs or ""
  local r, g, b = nameRGB(f, u)
  f.nameText:SetTextColor(r, g, b)
  S.UFCol.name(f)
  if isNil(nm) then nm = "" end
  if sec(nm) then setText(f.nameText, nm)   -- hidden names can't be joined to other text
  elseif not pcall(f.nameText.SetText, f.nameText, lv .. nm) then setText(f.nameText, nm) end
  pcall(S.UFNameFit, f)
  pcall(S.UFPvpPlace, f)
  if S.UFElite then pcall(S.UFElite.update, f) end
end

local function UpdateIcons(f)
  local u, ind = f.unit, f.cfg.ind
  local inGroup = (IsInGroup and IsInGroup()) or false
  f.leader:SetShown(ind.leader and inGroup and bool(try(UnitIsGroupLeader, u)))
  local idx = ind.mark and try(GetRaidTargetIndex, u) or nil
  if not sec(idx) and idx then SetRaidTargetIconTexture(f.mark, idx); f.mark:Show() else f.mark:Hide() end
  local role = (ind.role and inGroup and UnitGroupRolesAssigned) and try(UnitGroupRolesAssigned, u) or nil
  if not sec(role) and role and role ~= "NONE" then
    if GetTexCoordsForRoleSmallCircle then f.role:SetTexCoord(GetTexCoordsForRoleSmallCircle(role))
    else
      local t = { TANK = { 0, 19 / 64, 22 / 64, 41 / 64 }, HEALER = { 20 / 64, 39 / 64, 1 / 64, 20 / 64 }, DAMAGER = { 20 / 64, 39 / 64, 22 / 64, 41 / 64 } }
      if t[role] then f.role:SetTexCoord(unpack(t[role])) end
    end
    f.role:Show()
  else f.role:Hide() end
  local rc = (ind.ready and GetReadyCheckStatus) and try(GetReadyCheckStatus, u) or nil
  if not sec(rc) and rc then
    f.ready:SetTexture(rc == "ready" and "Interface\\RaidFrame\\ReadyCheck-Ready" or rc == "notready" and "Interface\\RaidFrame\\ReadyCheck-NotReady" or "Interface\\RaidFrame\\ReadyCheck-Waiting")
    f.ready:Show()
  elseif not f.readyHold then f.ready:Hide() end
  if f.key == "player" then
    f.combatIcon:SetShown(ind.combat and (UnitAffectingCombat("player") and true or false))
    f.restIcon:SetShown(ind.rest and not f.combatIcon:IsShown() and (IsResting() and true or false))
  else f.combatIcon:Hide(); f.restIcon:Hide() end
  local ffa = ind.pvp and bool(try(UnitIsPVPFreeForAll, u))
  local pvp = ind.pvp and (bool(try(UnitIsPVP, u)) or ffa)
  if pvp then
    local fac = try(UnitFactionGroup, u)
    if sec(fac) then fac = nil end
    if ffa then f.pvp:SetTexture("Interface\\TargetingFrame\\UI-PVP-FFA")
    elseif fac == "Horde" or fac == "Alliance" then f.pvp:SetTexture("Interface\\TargetingFrame\\UI-PVP-" .. fac) end
    f.pvp:Show()
  else f.pvp:Hide() end
  pcall(S.UFPvpPlace, f)
end

local function hasDispellable(u)
  if combat() then return nil end       -- aura data is refused in combat
  if S.UFCollectAuras then
    local e = S.UFCollectAuras(u, "HARMFUL|RAID", 1)[1]
    local a = e and e.d
    if a then
      local t = nth(a, "dispelName")
      if not sec(t) and t and DebuffTypeColor and DebuffTypeColor[t] then local col = DebuffTypeColor[t]; return col.r, col.g, col.b end
      return 0.7, 0.3, 1
    end
  end
end

local function UpdateHighlight(f)
  local u, hl = f.unit, f.cfg.hl
  local r, g, b
  if hl.target and f.key ~= "target" and bool(try(UnitIsUnit, u, "target")) then local t = UI:Theme().gold; r, g, b = t[1], t[2], t[3] end
  if not r and hl.dispel then r, g, b = hasDispellable(u) end
  if not r and hl.aggro and UnitThreatSituation then
    local s = try(UnitThreatSituation, u)
    if not sec(s) and s and s >= 2 then
      if GetThreatStatusColor then r, g, b = GetThreatStatusColor(s) else r, g, b = 1, 0.15, 0.1 end
    end
  end
  if r then hlColor(f, r, g, b); f.hl:Show() else f.hl:Hide() end
end

-- auras
local auraInfo = { method = {}, err = {} }   -- for /ccenter frames debug
-- auras the game announced in UNIT_AURA (works even when lists can't be read): auraCache[unit][id] = aura
-- In combat Forever hands out "secret tables": type() says "table" and single fields can be
-- read, but # / ipairs / pairs / writing into them fail. So the game's tables are only ever
-- read field by field (or by number with lst[i]); our own lists hold { d = aura, i = index }.

-- auras the game announced in UNIT_AURA (works even when lists can't be read): auraCache[unit][id] = aura
local auraCache = {}
local function okID(id) return not isNil(id) and not sec(id) end
local function cacheAuras(u, info)
  if type(u) ~= "string" or type(info) ~= "table" then return end
  if bool(nth(info, "isFullUpdate")) then auraCache[u] = {} end
  local c = auraCache[u] or {}
  auraCache[u] = c
  local now = GetTime()
  local added = nth(info, "addedAuras")
  if type(added) == "table" then
    for i = 1, 60 do
      local a = nth(added, i)
      if type(a) ~= "table" then break end
      local id = nth(a, "auraInstanceID")
      if okID(id) then c[id] = { d = a, seen = now } end
    end
  end
  local upd = nth(info, "updatedAuraInstanceIDs")
  if type(upd) == "table" and C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID then
    for i = 1, 60 do
      local id = nth(upd, i)
      if isNil(id) then break end
      if okID(id) then
        local a = try(C_UnitAuras.GetAuraDataByAuraInstanceID, u, id)
        if type(a) == "table" then c[id] = { d = a, seen = now } end
      end
    end
  end
  local rem = nth(info, "removedAuraInstanceIDs")
  if type(rem) == "table" then
    for i = 1, 60 do
      local id = nth(rem, i)
      if isNil(id) then break end
      if okID(id) then c[id] = nil end
    end
  end
end
local function fromOld(name, icon, count, dtype, dur, exp, src, _, _, spellId)
  if isNil(name) then return nil end
  return { name = name, icon = icon, applications = count, dispelName = dtype, duration = dur, expirationTime = exp, spellId = spellId }
end
-- the auras on a unit for a filter, up to n, as { d = aura table, i = index } entries
local AURA_WAYS = {
  { "GetAuraDataByIndex", function(u, filter, n)
      local out = {}
      for i = 1, 40 do
        if #out >= n then break end
        local a = C_UnitAuras.GetAuraDataByIndex(u, i, filter)
        if type(a) ~= "table" then break end
        out[#out + 1] = { d = a, i = i }
      end
      return out
    end },
  { "GetUnitAuras", function(u, filter, n)
      local lst = C_UnitAuras.GetUnitAuras(u, filter, n)
      if type(lst) ~= "table" then return nil end
      local out = {}
      for i = 1, n do
        local a = nth(lst, i)
        if type(a) ~= "table" then break end
        out[#out + 1] = { d = a }
      end
      return out
    end },
  { "GetAuraSlots", function(u, filter, n)
      local r = { C_UnitAuras.GetAuraSlots(u, filter, n) }
      local out = {}
      for i = 2, #r do
        if #out >= n then break end
        local a = C_UnitAuras.GetAuraDataBySlot(u, r[i])
        if type(a) == "table" then out[#out + 1] = { d = a } end
      end
      return out
    end },
  { "GetUnitAuraInstanceIDs", function(u, filter, n)
      local ids = C_UnitAuras.GetUnitAuraInstanceIDs(u, filter)
      if type(ids) ~= "table" then return nil end
      local out = {}
      for i = 1, 40 do
        if #out >= n then break end
        local id = nth(ids, i)
        if isNil(id) then break end
        local a = C_UnitAuras.GetAuraDataByAuraInstanceID(u, id)
        if type(a) == "table" then out[#out + 1] = { d = a } end
      end
      return out
    end },
  { "AuraUtil.ForEachAura", function(u, filter, n)
      local out = {}
      AuraUtil.ForEachAura(u, filter, n, function(a) if type(a) == "table" then out[#out + 1] = { d = a } end; return #out >= n end, true)
      return out
    end },
  { "UnitAura", function(u, filter, n)
      local out = {}
      for i = 1, 40 do
        if #out >= n then break end
        local a = fromOld(UnitAura(u, i, filter))
        if not a then break end
        out[#out + 1] = { d = a, i = i }
      end
      return out
    end },
  { "UnitBuff/UnitDebuff", function(u, filter, n)
      local fn = filter:find("HARMFUL") and UnitDebuff or UnitBuff
      local out = {}
      for i = 1, 40 do
        if #out >= n then break end
        local a = fromOld(fn(u, i, filter))
        if not a then break end
        out[#out + 1] = { d = a, i = i }
      end
      return out
    end },
  { "events", function(u, filter, n)
      local c = auraCache[u]
      if not c or filter:find("RAID") then return {} end
      local harm, mine = filter:find("HARMFUL") ~= nil, filter:find("PLAYER") ~= nil
      local now = GetTime()
      local ids = {}
      for id, e in pairs(c) do      -- our own table
        local a = e.d
        local exp = nth(a, "expirationTime")
        if not sec(exp) and type(exp) == "number" and exp > 0 and exp < now then c[id] = nil
        else
          local isH, isB = nth(a, "isHarmful"), nth(a, "isHelpful")
          local kindOK
          if not sec(isH) and isH ~= nil then kindOK = (isH and true or false) == harm
          elseif not sec(isB) and isB ~= nil then kindOK = (isB and true or false) ~= harm
          else kindOK = true end
          local fromMe = nth(a, "isFromPlayerOrPlayerPet")
          if mine and not sec(fromMe) and fromMe == false then kindOK = false end
          if kindOK then ids[#ids + 1] = id end
        end
      end
      table.sort(ids)
      local out = {}
      for _, id in ipairs(ids) do if #out < n then out[#out + 1] = { d = c[id].d } end end
      return out
    end },
}
local function wayAvailable(name)
  if name == "GetUnitAuras" then return C_UnitAuras and C_UnitAuras.GetUnitAuras end
  if name == "GetAuraDataByIndex" then return C_UnitAuras and C_UnitAuras.GetAuraDataByIndex end
  if name == "GetAuraSlots" then return C_UnitAuras and C_UnitAuras.GetAuraSlots and C_UnitAuras.GetAuraDataBySlot end
  if name == "AuraUtil.ForEachAura" then return AuraUtil and AuraUtil.ForEachAura end
  if name == "UnitAura" then return UnitAura end
  if name == "GetUnitAuraInstanceIDs" then return C_UnitAuras and C_UnitAuras.GetUnitAuraInstanceIDs and C_UnitAuras.GetAuraDataByAuraInstanceID end
  if name == "events" then return true end
  return UnitBuff and UnitDebuff
end
local function collectAuras(u, filter, n)
  local key = filter
  local firstEmpty
  -- the way that worked last time for this filter first
  local order = {}
  for _, w in ipairs(AURA_WAYS) do if w[1] == auraInfo.method[key] then table.insert(order, 1, w) else order[#order + 1] = w end end
  for _, w in ipairs(order) do
    if wayAvailable(w[1]) then
      local ok, list = pcall(w[2], u, filter, n)
      if not ok then auraInfo.err[w[1]] = tostring(list)
      elseif list then
        if #list > 0 then
          if w[1] ~= "events" then auraInfo.method[key] = w[1] end   -- the announced list is only a stand-in
          return list
        end
        firstEmpty = firstEmpty or list
      end
    end
  end
  return firstEmpty or {}
end
S.UFCollectAuras = collectAuras

-- the timer swipe, whichever way the game lets us set it
local function auraCooldown(b, u, a, id)
  local dur, exp = nth(a, "duration"), nth(a, "expirationTime")
  if not sec(dur, exp) then
    if type(dur) == "number" and dur > 0 and type(exp) == "number" then b.cd:SetCooldown(exp - dur, dur) else b.cd:Clear() end
    return
  end
  if okID(id) and C_UnitAuras and C_UnitAuras.GetAuraDuration and b.cd.SetCooldownFromDurationObject then
    local d = try(C_UnitAuras.GetAuraDuration, u, id)
    if d and pcall(b.cd.SetCooldownFromDurationObject, b.cd, d) then return end
  end
  if b.cd.SetCooldownFromExpirationTime and pcall(b.cd.SetCooldownFromExpirationTime, b.cd, exp, dur) then return end
  b.cd:Clear()
end

local function fillAuras(f, list, filter, debuff)
  local u = f.unit
  local n = 0
  local found = collectAuras(u, filter, #list)
  if #found == 0 and filter == "HARMFUL" then found = collectAuras(u, "HARMFUL|PLAYER", #list) end
  for _, e in ipairs(found) do      -- our own list
    if n >= #list then break end
    local a = e.d
    n = n + 1
    local b = list[n]
    local id = nth(a, "auraInstanceID")
    b.unit, b.index, b.filter, b.auraID = u, e.i, filter, okID(id) and id or nil
    pcall(b.icon.SetTexture, b.icon, nth(a, "icon"))
    pcall(auraCooldown, b, u, a, id)
    -- stacks
    local apps = nth(a, "applications")
    if not sec(apps) then b.count:SetText((type(apps) == "number" and apps > 1) and apps or "")
    elseif okID(id) and C_UnitAuras and C_UnitAuras.GetAuraApplicationDisplayCount then
      local txt = try(C_UnitAuras.GetAuraApplicationDisplayCount, u, id, 2, 99)
      if isNil(txt) then b.count:SetText("") else setText(b.count, txt) end
    else setText(b.count, apps) end
    -- debuff type border
    if debuff then
      local t = nth(a, "dispelName")
      local col = (not sec(t) and t and DebuffTypeColor and DebuffTypeColor[t]) or (DebuffTypeColor and DebuffTypeColor.none) or { r = 0.8, g = 0, b = 0 }
      auraEdge(b, col.r, col.g, col.b)
    else auraEdge(b, 0, 0, 0) end
    b:Show()
  end
  for i = n + 1, #list do list[i]:Hide() end
  return found
end
---------------------------------------------------------------------------
-- Auras in combat. Forever refuses aura data to addons in a fight (confirmed in game:
-- "Auras cannot be accessed when secret while tainted"), and has no game-drawn aura
-- button template. So the frames keep track themselves:
--   * out of combat every aura is read and remembered per unit (exact timers)
--   * your own buffs / DoTs teach us their spell, duration and icon (saved)
--   * in combat: the remembered auras keep counting down, and when you cast one
--     of your learned spells its icon + timer (re)start on the target / on you
--   * live reading comes back when the fight ends
---------------------------------------------------------------------------
local auraMem = {}          -- auraMem[key] = { buffs = { e }, debuffs = { e }, at }
local function learned()
  local g = S.db.global
  g.ufLearned = type(g.ufLearned) == "table" and g.ufLearned or {}
  return g.ufLearned
end
local function unitKey(u)
  local guid = try(UnitGUID, u)
  if not isNil(guid) and not sec(guid) then return guid end
  return "tok:" .. tostring(u)
end
local function plain(v) if sec(v) then return nil end return v end
local function memEntry(a)
  local e = {
    icon = plain(nth(a, "icon")), exp = plain(nth(a, "expirationTime")), dur = plain(nth(a, "duration")),
    count = plain(nth(a, "applications")), dtype = plain(nth(a, "dispelName")), spell = plain(nth(a, "spellId")),
    name = plain(nth(a, "name")), mine = plain(nth(a, "isFromPlayerOrPlayerPet")),
  }
  if type(e.exp) ~= "number" then e.exp = 0 end
  if type(e.dur) ~= "number" then e.dur = 0 end
  return e
end
local function remember(u, foundBuffs, foundDebuffs)
  local m = { buffs = {}, debuffs = {}, at = GetTime() }
  local L = learned()
  for kind, found in pairs({ buffs = foundBuffs or {}, debuffs = foundDebuffs or {} }) do
    for _, fe in ipairs(found) do
      local e = memEntry(fe.d)
      m[kind][#m[kind] + 1] = e
      -- learn your own timed auras: spell -> duration, icon, buff or debuff, on you or on others
      if e.spell and e.mine and e.dur > 0 and e.icon then
        L[e.spell] = { dur = e.dur, icon = e.icon, harm = kind == "debuffs", self = u == "player", name = e.name }
      end
    end
  end
  auraMem[unitKey(u)] = m
  if u == "target" or u == "focus" or u == "player" then auraMem["tok:" .. u] = m end
end
-- your cast in combat: restart the learned aura on the target (debuff) or on you (buff)
local function castAura(spellID)
  if sec(spellID) or not spellID or not S.db then return false end
  local l = learned()[spellID]
  if not l then return false end
  local u = l.harm and "target" or "player"
  if l.harm and not UnitExists("target") then return false end
  local key = unitKey(u)
  local m = auraMem[key]
  if not m then m = { buffs = {}, debuffs = {}, at = GetTime() }; auraMem[key] = m end
  local list = l.harm and m.debuffs or m.buffs
  local now = GetTime()
  local hit
  for _, e in ipairs(list) do if e.spell == spellID then hit = e end end
  if not hit then hit = { spell = spellID, icon = l.icon, name = l.name, mine = true }; table.insert(list, 1, hit) end
  hit.dur, hit.exp, hit.cast = l.dur, now + l.dur, true
  if u ~= "player" then auraMem["tok:" .. u] = m end
  return true, u
end
S.UFCastAura = castAura
-- paint remembered auras (in combat): our own icons, our own (readable) timers
-- the screen spot of slot i (1-based) in a row described by Layout's geo
local function slotPoint(g, i)
  local col, row = (i - 1) % g.wrap, floor((i - 1) / g.wrap)
  return g.x + col * g.dx + row * g.wx, g.y + col * g.dy + row * g.wy
end
-- paint remembered auras (in combat): our own icons, our own (readable) timers;
-- skip = spells already shown by the Cooldown Manager, first = first free slot
local function paintMem(f, list, entries, debuff, onlyMine, skip, first, g, notMine, used)
  local now = GetTime()
  local n = 0
  used = used or 0
  first = first or (used + 1)
  for _, e in ipairs(entries or {}) do
    local alive = e.exp == 0 or e.exp > now
    if alive and (not onlyMine or e.mine) and not (notMine and e.mine) and not (skip and e.spell and skip[e.spell]) and n + used < #list then
      n = n + 1
      local b = list[n + used]
      b.unit, b.index, b.filter, b.auraID, b.spell = nil, nil, nil, nil, e.spell
      b.icon:SetTexture(e.icon or 134400)
      if e.dur > 0 and e.exp > 0 then b.cd:SetCooldown(e.exp - e.dur, e.dur) else b.cd:Clear() end
      b.count:SetText((type(e.count) == "number" and e.count > 1 and not e.cast) and e.count or "")
      if debuff then
        local col = (e.dtype and DebuffTypeColor and DebuffTypeColor[e.dtype]) or (DebuffTypeColor and DebuffTypeColor.none) or { r = 0.8, g = 0, b = 0 }
        auraEdge(b, col.r, col.g, col.b)
      else auraEdge(b, 0, 0, 0) end
      if g then
        local x, y = slotPoint(g, n + first - 1)
        b:ClearAllPoints(); b:SetPoint(g.point, f, g.rel, x, y)
      end
      b:Show()
    end
  end
  for i = n + used + 1, #list do list[i]:Hide() end
end

---------------------------------------------------------------------------
-- The enemy's nameplate in combat. Blizzard's nameplate code may read auras in a
-- fight and draws your debuffs on the plate. We copy what's on those buttons:
-- icon and stack text pass from their widgets to ours untouched (hidden values may
-- go widget to widget), and the timer is copied by catching Blizzard's own calls to
-- the plate's cooldown (hooksecurefunc) and making the same call on ours.
-- Nothing is read or worked out by our code. Nameplates must be shown.
---------------------------------------------------------------------------
local NP = { last = setmetatable({}, { __mode = "k" }), hooked = setmetatable({}, { __mode = "k" }), info = { plate = false, found = 0 } }
NP.CD_METHODS = { "SetCooldown", "SetCooldownFromDurationObject", "SetCooldownFromExpirationTime", "SetCooldownDuration", "Clear" }
function NP.hook(cd)
  if not cd or NP.hooked[cd] or not hooksecurefunc then return end
  NP.hooked[cd] = true
  for _, m in ipairs(NP.CD_METHODS) do
    if type(cd[m]) == "function" then
      pcall(hooksecurefunc, cd, m, function(self, ...) NP.last[self] = { m, select("#", ...), ... } end)
    end
  end
end
function NP.plate(u)
  if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return nil end
  local p = try(C_NamePlate.GetNamePlateForUnit, u)
  if type(p) ~= "table" then return nil end
  return p
end
-- the plate's shown aura buttons (anything with an icon + a cooldown), left to right
function NP.collect(u)
  if not (store().cdm.nameplates and u) then return nil end
  local p = NP.plate(u)
  NP.info.plate = p ~= nil
  if not p then return nil end
  local root = p.UnitFrame or p.unitFrame or p
  local out = {}
  local function scan(fr, depth)
    if depth > 6 or #out >= 16 or not fr.GetChildren then return end
    for _, ch in ipairs({ fr:GetChildren() }) do
      if type(ch) == "table" then
        local icon, cd = ch.Icon or ch.icon, ch.Cooldown or ch.cooldown
        if type(icon) == "table" and icon.GetTexture and type(cd) == "table" then
          NP.hook(cd)
          if ch:IsVisible() then out[#out + 1] = ch end
        else scan(ch, depth + 1) end
      end
    end
  end
  local ok, err = pcall(scan, root, 0)
  if not ok then NP.info.err = tostring(err) end
  -- kept in the game's own order: nameplates are restricted on Forever, measuring them (GetLeft...) errors
  NP.info.found = #out
  pcall(NP.sync, u, out)
  return out
end
-- Timers for the copied icons, without reading anything in combat:
--   * out of combat the plate's icons can be read: each one's exact time left is
--     stored by its aura ID (not a hidden value), so it keeps counting into the fight
--   * in combat, when you cast one of your learned spells and a new icon appears on
--     the plate right after, that icon gets the spell's learned duration from the cast
--   * casting it again while its icon is up restarts that timer
NP.timers = {}                                         -- key -> { spell, exp, dur }
NP.seen = setmetatable({}, { __mode = "k" })           -- plate button -> key it showed last time
NP.pending = nil                                       -- { spell, dur, t } your last cast, waiting for its icon
NP.slots = {}                                          -- r104: timers in the plate's icon order (when icons can't be told apart)
NP.byTex = {}                                          -- r104: icon texture -> timer, from your casts (when the plate's icon textures are readable)
function NP.key(btn)
  local id = nth(btn, "auraInstanceID")
  if okID(id) then return "id:" .. tostring(id) end
  return btn
end
-- the ability's own duration: what was learned, else read from its tooltip text ("over 12 sec")
NP.ddur = {}
function NP.dur(spellID)
  local l = learned()[spellID]
  if l and l.harm and type(l.dur) == "number" and l.dur > 0 then return l.dur, "learned" end
  local c = NP.ddur[spellID]
  if c ~= nil then return c or nil, c and "tooltip" or nil end
  local d
  local txt = (C_Spell and C_Spell.GetSpellDescription and try(C_Spell.GetSpellDescription, spellID))
    or (GetSpellDescription and try(GetSpellDescription, spellID))
  if type(txt) == "string" and not sec(txt) then
    local t = txt:lower()
    for _, pat in ipairs({ "over (%d+%.?%d*) sec", "for (%d+%.?%d*) sec", "lasts (%d+%.?%d*) sec", "(%d+%.?%d*) sec" }) do
      local n = t:match(pat); if n then d = tonumber(n); break end
    end
    if not d then
      for _, pat in ipairs({ "over (%d+%.?%d*) min", "for (%d+%.?%d*) min", "(%d+%.?%d*) min" }) do
        local n = t:match(pat); if n then d = tonumber(n) * 60; break end
      end
    end
  end
  if d and d <= 0 then d = nil end
  -- only spells that hit enemies (when the game can tell us)
  if d and C_Spell and C_Spell.IsSpellHarmful then
    local h = try(C_Spell.IsSpellHarmful, spellID)
    if h == false then d = nil end
  end
  NP.ddur[spellID] = d or false
  return d, d and "tooltip" or nil
end
NP.unclaimed = nil                                     -- { key, t } an icon that showed up before its cast event
NP.lastCast = nil                                      -- for /ccenter frames debug
local function npStart(key, spell, t0, dur)
  NP.timers[key] = { spell = spell, exp = t0 + dur, dur = dur, visible = true }
end
function NP.onCast(spellID)
  if sec(spellID) or not spellID or not S.db then return end
  local dur, src = NP.dur(spellID)
  local nm = C_Spell and C_Spell.GetSpellName and try(C_Spell.GetSpellName, spellID)
  NP.lastCast = { spell = spellID, name = (not sec(nm) and nm) or tostring(spellID), dur = dur, src = src, matched = false }
  if not dur then return end
  local now = GetTime()
  -- by icon picture: found again wherever the game moves the icon
  local tex = (C_Spell and C_Spell.GetSpellTexture and try(C_Spell.GetSpellTexture, spellID)) or (GetSpellTexture and try(GetSpellTexture, spellID))
  if tex and not sec(tex) then NP.byTex[tex] = { spell = spellID, exp = now + dur, dur = dur } end
  -- recast: restart the timer it already has
  for _, t in ipairs(NP.slots) do
    if t and t.spell == spellID then t.exp, t.dur = now + dur, dur; NP.lastCast.matched = "restarted"; return end
  end
  for _, t in pairs(NP.timers) do
    if t.spell == spellID and t.visible then t.exp, t.dur = now + dur, dur; NP.lastCast.matched = "restarted"; return end
  end
  local uc = NP.unclaimed
  if uc and now - uc.t < 1.0 then
    local t = { spell = spellID, exp = now + dur, dur = dur, visible = true }
    if uc.slot then NP.slots[uc.slot] = t else NP.timers[uc.key] = t end
    NP.unclaimed = nil; NP.lastCast.matched = "icon"; return
  end
  NP.pending = { spell = spellID, dur = dur, t = now }
end
-- called every look at the plate: learn (out of combat), keep timers with their icons (in combat)
function NP.sync(u, btns)
  local now = GetTime()
  for _, t in pairs(NP.timers) do t.visible = nil end
  local idsOK = #btns > 0
  for _, btn in ipairs(btns) do if type(NP.key(btn)) ~= "string" then idsOK = false end end
  NP.info.ids = idsOK
  if not combat() then
    -- out of combat the auras can be read: exact time left for every icon (by its aura ID)
    local slots = {}
    for i, btn in ipairs(btns) do
      local key = NP.key(btn)
      local t
      local id = nth(btn, "auraInstanceID")
      local a = okID(id) and C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID and try(C_UnitAuras.GetAuraDataByAuraInstanceID, u, id)
      if type(a) == "table" then
        local e = memEntry(a)
        if e.dur > 0 and e.exp > 0 then t = { spell = e.spell, exp = e.exp, dur = e.dur, visible = true } end
      end
      t = t or (NP.timers[key] and NP.timers[key].exp > now and NP.timers[key]) or nil
      NP.timers[key] = t
      slots[i] = t or false
      NP.seen[btn] = key
    end
    NP.slots = slots
  elseif idsOK then
    -- the plate tells us which aura each icon is: timers stay with their aura
    for _, btn in ipairs(btns) do
      local key = NP.key(btn)
      local t = NP.timers[key]
      if NP.seen[btn] ~= key and not t then
        local pnd = NP.pending
        if pnd and now - pnd.t < 2.5 then
          t = { spell = pnd.spell, exp = pnd.t + pnd.dur, dur = pnd.dur }; NP.timers[key] = t; NP.pending = nil
          if NP.lastCast then NP.lastCast.matched = "icon" end
        else NP.unclaimed = { key = key, t = now } end
      end
      if t then if t.exp <= now then NP.timers[key] = nil else t.visible = true end end
      NP.seen[btn] = key
    end
  else
    -- icons can't be told apart: keep timers in the plate's order. When icons go away, the game slides
    -- the rest along, so drop the timer that ran out (else an untimed one, else the one closest to its end);
    -- new icons go on the end, matched to your cast.
    local slots, n = NP.slots, #btns
    while #slots > n do
      local drop, best = nil, nil
      for i, t in ipairs(slots) do
        local score = (not t) and 1 or ((t.exp <= now + 0.3) and 0 or (2 + t.exp))
        if not best or score < best then drop, best = i, score end
      end
      table.remove(slots, drop or #slots)
    end
    while #slots < n do
      local pnd = NP.pending
      if pnd and now - pnd.t < 2.5 then
        slots[#slots + 1] = { spell = pnd.spell, exp = pnd.t + pnd.dur, dur = pnd.dur }
        NP.pending = nil
        if NP.lastCast then NP.lastCast.matched = "icon" end
      else
        slots[#slots + 1] = false
        NP.unclaimed = { slot = #slots, t = now }
      end
    end
    for k in pairs(NP.timers) do if type(k) ~= "string" then NP.timers[k] = nil end end
    for i, btn in ipairs(btns) do
      local t = slots[i]
      if t and t.exp <= now then slots[i] = false; t = nil end
      if t then t.visible = true; NP.timers[btn] = t end
      NP.seen[btn] = btn
    end
  end
  -- icons that went away: next time they show they're new again
  local here = {}
  for _, btn in ipairs(btns) do here[btn] = true end
  for btn in pairs(NP.seen) do if not here[btn] then NP.seen[btn] = nil end end
  for key, t in pairs(NP.timers) do if t.exp <= now or (not t.visible and type(key) ~= "string") then NP.timers[key] = nil end end
  for tex, t in pairs(NP.byTex) do if t.exp <= now then NP.byTex[tex] = nil end end
end

-- paint the plate's buttons onto our debuff icons; returns how many were used
function NP.paint(f, list, btns, g)
  local n = 0
  for _, src in ipairs(btns) do
    if n >= #list then break end
    n = n + 1
    local b = list[n]
    b.unit, b.index, b.filter, b.auraID, b.spell = nil, nil, nil, nil, nil
    local icon = src.Icon or src.icon
    pcall(function() b.icon:SetTexture(icon:GetTexture()) end)
    local L = NP.last[src.Cooldown or src.cooldown]
    local t
    local okT, tex = pcall(icon.GetTexture, icon)
    if okT and tex ~= nil and not sec(tex) then NP.info.tex = "readable"; t = NP.byTex[tex] elseif okT and sec(tex) then NP.info.tex = "hidden" end
    t = (t and t.exp > GetTime()) and t or NP.timers[NP.key(src)]
    if t and t.exp > GetTime() then
      b.cd:SetCooldown(t.exp - t.dur, t.dur)          -- the ability's own duration
      if t.spell then b.spell = t.spell end
    elseif L and L[1] ~= "Clear" and type(b.cd[L[1]]) == "function" then
      if not pcall(b.cd[L[1]], b.cd, unpack(L, 3, 2 + L[2])) then b.cd:Clear() end
    else b.cd:Clear() end
    local cnt = src.Count or src.count or (src.CountFrame and src.CountFrame.Count) or src.Applications
    if type(cnt) == "table" and cnt.GetText then
      local t = try(cnt.GetText, cnt)
      if isNil(t) then b.count:SetText("") else setText(b.count, t) end
    else b.count:SetText("") end
    auraEdge(b, 0.8, 0.1, 0.1)
    if g then local x, y = slotPoint(g, n); b:ClearAllPoints(); b:SetPoint(g.point, f, g.rel, x, y) end
    b:Show()
  end
  return n
end
S.UFNameplate = NP

---------------------------------------------------------------------------
-- Blizzard's Cooldown Manager in combat. Its "Tracked Buffs" icons
-- (BuffIconCooldownViewer) are drawn by Blizzard's own code, which may read auras
-- in a fight. In combat we move those icon frames into the player frame's buff row
-- (auras on you) and the target frame's debuff row (your DoTs on the target).
-- We only anchor / scale them - never read what's on them. Out of combat they go
-- back to Blizzard (and its bar can be hidden, since our own icons show then).
-- Setup: Edit Mode -> Cooldown Manager on, add spells to Tracked Buffs.
---------------------------------------------------------------------------
local CDM = { spellOf = {}, info = { viewer = false, items = 0, placed = 0 }, moved = setmetatable({}, { __mode = "k" }) }
function CDM.cfg() return store().cdm end
function CDM.viewer() return _G.BuffIconCooldownViewer end
function CDM.items()
  local v = CDM.viewer()
  local out = {}
  if not v or not v.GetChildren then return out end
  for _, ch in ipairs({ v:GetChildren() }) do
    if type(ch) == "table" and (ch.Icon or ch.icon or ch.Cooldown or ch.cooldown) then out[#out + 1] = ch end
  end
  return out
end
function CDM.spell(it)          -- spell + "is it on you" for an icon (config data, learned out of combat)
  local id = try(it.GetCooldownID, it)
  if isNil(id) or sec(id) then id = nil end
  if id and CDM.spellOf[id] then return CDM.spellOf[id].spell, CDM.spellOf[id].self end
  local sp, self
  if id and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
    local info = try(C_CooldownViewer.GetCooldownViewerCooldownInfo, id)
    if type(info) == "table" then
      sp = plain(nth(info, "overrideSpellID")) or plain(nth(info, "spellID"))
      self = plain(nth(info, "selfAura"))
    end
  end
  if not sp then sp = plain(try(it.GetSpellID, it)) or plain(try(it.GetBaseSpellID, it)) end
  if type(sp) ~= "number" then sp = nil end
  if id and sp then CDM.spellOf[id] = { spell = sp, self = self } end
  return sp, self
end
function CDM.unit(sp, self)     -- on you, or on your target
  if self == true then return "player" end
  local l = sp and S.db and learned()[sp]
  if l then return l.harm and "target" or "player" end
  if sp and C_Spell and C_Spell.IsSpellHarmful and try(C_Spell.IsSpellHarmful, sp) == true then return "target" end
  if self == false then return "target" end
  return "player"
end
function CDM.give()             -- out of combat: back to Blizzard (its bar hidden if you like)
  local v = CDM.viewer()
  if not v then return end
  local any = false
  for it in pairs(CDM.moved) do any = true; CDM.moved[it] = nil; pcall(it.SetScale, it, 1) end
  if any then
    if v.RefreshLayout then pcall(v.RefreshLayout, v) elseif v.Layout then pcall(v.Layout, v) end
  end
  local c = CDM.cfg()
  pcall(v.SetAlpha, v, (c.on and c.hideBar and store().on) and 0 or 1)
end
-- in combat: put Blizzard's shown icons into the rows; returns per unit { skip = spells, n = slots used, kind }
function CDM.place()
  local res = { player = { skip = {}, n = 0 }, target = { skip = {}, n = 0 } }
  local c, v = CDM.cfg(), CDM.viewer()
  CDM.info.viewer = v ~= nil
  if not (c.on and store().on and v) then return res end
  pcall(v.SetAlpha, v, 1)
  local items = CDM.items()
  CDM.info.items, CDM.info.placed = #items, 0
  local tf = single.target
  local npTarget = tf and tf.cfg and tf.cfg.debuffs and NP.collect("target")
  for _, it in ipairs(items) do
    local ok, err = pcall(function()
      if not it:IsShown() then return end
      local sp, self = CDM.spell(it)
      local u = CDM.unit(sp, self)
      if u == "target" and npTarget then return end      -- the nameplate copy covers your DoTs
      local f = single[u]
      if not (f and f.ccLaidOut and f:IsVisible() and not f.fake) then return end
      local kind = (u == "player") and ((f.cfg.buffs and "buff") or "debuff") or ((f.cfg.debuffs and "debuff") or "buff")
      local g = f.ccGeo and f.ccGeo[kind]
      if not g then return end
      local r = res[u]
      r.n, r.kind = r.n + 1, kind
      if sp then r.skip[sp] = true end
      local x, y = slotPoint(g, r.n)
      -- same size as our icons: scale the icon frame, then express the offset in its own units
      local w = it:GetWidth()
      if type(w) == "number" and not sec(w) and w > 0 then
        local parentScale = it:GetParent() and it:GetParent():GetEffectiveScale() or 1
        it:SetScale(((f.ccAuraSize or 22) * f:GetEffectiveScale()) / (w * parentScale))
      end
      local k = f:GetEffectiveScale() / it:GetEffectiveScale()
      it:ClearAllPoints()
      it:SetPoint(g.point, f, g.rel, x * k, y * k)
      CDM.moved[it] = true
      CDM.info.placed = CDM.info.placed + 1
    end)
    if not ok then CDM.info.err = tostring(err) end
  end
  return res
end
S.UFCdm = CDM

local function UpdateAuras(f)
  local c = f.cfg
  local u = f.unit
  if combat() then
    -- no reading in a fight: show what we remember (+ your casts)
    local m = auraMem[unitKey(u)] or auraMem["tok:" .. tostring(u)]
    if bool(try(UnitIsDead, u)) then m = nil end
    local attackable = bool(try(UnitCanAttack, "player", u))
    local cd = { skip = nil, n = 0 }
    if (f.key == "player" or f.key == "target") and f.unit == f.key then
      local ok, res = pcall(CDM.place)
      if ok and res and res[f.key] then cd = res[f.key] end
    end
    local g = f.ccGeo or {}
    if c.buffs then
      local first = (cd.kind == "buff") and cd.n + 1 or 1
      paintMem(f, f.buffs, m and m.buffs, false, c.auraMine, cd.skip, first, g.buff)
    end
    local np = c.debuffs and (f.key == "target" or f.key == "focus") and f.unit == f.key and NP.collect(u)
    if np then
      -- live debuffs from the nameplate, then others' debuffs remembered from before the fight
      local used = NP.paint(f, f.debuffs, np, g.debuff)
      paintMem(f, f.debuffs, m and m.debuffs, true, false, nil, nil, g.debuff, true, used)
    elseif c.debuffs then
      local first = (cd.kind == "debuff") and cd.n + 1 or 1
      paintMem(f, f.debuffs, m and m.debuffs, true, c.auraMine and attackable, cd.skip, first, g.debuff)
    end
    return
  end
  local fb, fd
  if c.buffs then fb = fillAuras(f, f.buffs, c.auraMine and "HELPFUL|PLAYER" or "HELPFUL", false) end
  if c.debuffs then
    local filter = "HARMFUL"
    if c.auraMine and bool(try(UnitCanAttack, "player", f.unit)) then filter = "HARMFUL|PLAYER" end
    fd = fillAuras(f, f.debuffs, filter, true)
  end
  if (f.key == "target" or f.key == "focus") and f.unit == f.key then pcall(NP.collect, u) end
  -- remember everything (all auras, not just the shown ones) for the next fight
  if u and UnitExists(u) then
    local allB = collectAuras(u, "HELPFUL", 40)
    local allD = collectAuras(u, "HARMFUL", 40)
    pcall(remember, u, allB, allD)
  end
end

-- cast bar
local function castColor(cb, notInt)
  local th = UI:Theme()
  local n = (cb.ccChannel and { th.live[1], th.live[2], th.live[3] }) or { th.gold[1], th.gold[2], th.gold[3] }
  local cc = cb.ccCfg and cb.ccCfg.castColor
  if cc == "class" and cb.ccUnit then
    local _, cls = try(UnitClass, cb.ccUnit)
    local r, g, b = classColor(not sec(cls) and cls or nil)
    if r then n = { r, g, b } end
  elseif cc == "white" then n = { 0.92, 0.92, 0.92 } end
  local grey = { 0.55, 0.55, 0.6 }
  if not sec(notInt) then
    local c = notInt and grey or n
    cb:SetStatusBarColor(c[1], c[2], c[3]); cb.shield:SetShown(notInt and true or false)
  elseif C_CurveUtil and C_CurveUtil.EvaluateColorFromBoolean and CreateColor then
    local col = try(C_CurveUtil.EvaluateColorFromBoolean, notInt, CreateColor(grey[1], grey[2], grey[3], 1), CreateColor(n[1], n[2], n[3], 1))
    if col and col.GetRGB then cb:SetStatusBarColor(col:GetRGB()) else cb:SetStatusBarColor(n[1], n[2], n[3]) end
    if cb.shield.SetAlphaFromBoolean then pcall(cb.shield.SetAlphaFromBoolean, cb.shield, notInt, 1, 0); cb.shield:Show() else cb.shield:Hide() end
  else cb:SetStatusBarColor(n[1], n[2], n[3]); cb.shield:Hide() end
  S.UFCol.cast(cb, notInt)
end
local function castOnUpdate(cb)
  if not cb.ccStart then return end
  local now = GetTime()
  local total = cb.ccEnd - cb.ccStart
  if total <= 0 then return end
  local p = (now - cb.ccStart) / total
  if p >= 1.05 then cb:Hide(); cb.ccStart = nil; return end
  local c = cb.ccCfg or {}
  local drain = cb.ccChannel
  if c.castFill == "drain" then drain = not drain end
  local v = min(1, max(0, drain and (1 - p) or p))
  cb:SetValue(v)
  cb.spark:ClearAllPoints()
  if c.castDir == "rtl" then cb.spark:SetPoint("CENTER", cb, "RIGHT", -cb:GetWidth() * v, 0) else cb.spark:SetPoint("CENTER", cb, "LEFT", cb:GetWidth() * v, 0) end
  local left, el = max(0, cb.ccEnd - now), min(total, max(0, now - cb.ccStart))
  local fmt = (c.castDec == false) and "%.0f" or "%.1f"
  local m = c.castTime or "left"
  if m == "left" then cb.time:SetText(string.format(fmt, left))
  elseif m == "leftmax" then cb.time:SetText(string.format(fmt .. " / " .. fmt, left, total))
  elseif m == "elapsed" then cb.time:SetText(string.format(fmt, el))
  elseif m == "pct" then cb.time:SetText(string.format("%d%%", floor(min(1, p) * 100 + 0.5)))
  else cb.time:SetText("") end
end
-- how a cast bar ends (Cast bar > When it ends): fade out, flash then fade, or vanish; interrupted casts say so in red
S.UFCast = {}
function S.UFCast.fade(cb)
  local t = GetTime() - cb.ccFadeAt
  local hold, len = cb.ccFadeHold or 0, cb.ccFadeLen or 0.3
  if t < hold then return end
  local a = 1 - (t - hold) / len
  if a <= 0 then cb:SetScript("OnUpdate", nil); cb.ccFading = nil; cb:Hide(); cb:SetAlpha(1); return end
  cb:SetAlpha(a)
end
local function CastStop(f, kind)
  local cb = f.cast
  if not cb:IsShown() then return end
  local c = f.cfg or {}
  if cb.ccFading == "fail" then return end                       -- already showing "Interrupted"
  local wasFail = kind == "fail" and c.castFail ~= false
  if cb.ccFading == "done" and not wasFail then return end
  cb.ccStart = nil
  local mode = kind and (c.castEnd or "fade") or "none"         -- no kind = target changed etc.: just go
  if f.fake or (mode == "none" and not wasFail) then
    cb.ccFading = nil; cb:SetScript("OnUpdate", nil); cb:Hide(); cb:SetAlpha(1); return
  end
  cb.ccFading = wasFail and "fail" or "done"
  cb.ccFadeAt = GetTime()
  cb.spark:Hide(); cb.safe:Hide()
  if cb.SetTimerDuration and cb.ccSecret then pcall(cb.SetMinMaxValues, cb, 0, 1) end
  cb.ccSecret = nil
  cb:SetValue(1)
  if wasFail then
    cb:SetStatusBarColor(0.85, 0.15, 0.1)
    cb.text:SetText(cb.ccChannel and "Stopped" or "Interrupted"); cb.time:SetText("")
    cb.ccFadeHold, cb.ccFadeLen = 0.5, 0.4
  elseif mode == "flash" then
    cb:SetStatusBarColor(1, 1, 0.85)
    cb.ccFadeHold, cb.ccFadeLen = 0.08, 0.3
  else
    cb.ccFadeHold, cb.ccFadeLen = 0, 0.3
  end
  cb:SetScript("OnUpdate", S.UFCast.fade)
end
local function CastStart(f, channel)
  local cb, u = f.cast, f.unit
  if not f.cfg.castbar then return end
  local name, text, tex, st, et, notInt, spellID, _
  if channel then name, text, tex, st, et, _, notInt, spellID = try(UnitChannelInfo, u)
  else name, text, tex, st, et, _, _, notInt, spellID = try(UnitCastingInfo, u) end
  if type(name) == "nil" then
    if not channel then local cn = try(UnitChannelInfo, u); if type(cn) ~= "nil" then return CastStart(f, true) end end
    CastStop(f) return
  end
  cb.ccChannel = channel
  cb.ccFading = nil; cb:SetAlpha(1); cb.ccUnit = u; cb.ccCfg = f.cfg
  cb.spark:SetAlpha((f.cfg.castSpark == false) and 0 or 1)
  pcall(cb.icon.SetTexture, cb.icon, tex)
  if isNil(text) then text = name end
  -- spell rank after the name (Cast bar > Spell rank), when the game lets us see which spell it is
  local rk = f.cfg.castRank
  if rk and rk ~= "off" and not sec(name) and type(name) == "string" and not sec(spellID) and type(spellID) == "number" then
    local sub = (C_Spell and C_Spell.GetSpellSubtext and try(C_Spell.GetSpellSubtext, spellID)) or (GetSpellSubtext and try(GetSpellSubtext, spellID))
    if type(sub) == "string" and not sec(sub) and sub ~= "" then
      local n = sub:match("(%d+)")
      if rk == "short" and n then text = name .. "  |cffbbbbbbR" .. n .. "|r"
      elseif rk == "full" or not n then text = name .. "  |cffbbbbbb(" .. sub .. ")|r" end
    end
  end
  if not pcall(cb.text.SetText, cb.text, text) then setText(cb.text, name) end
  castColor(cb, notInt)
  cb.safe:Hide()
  if not sec(st, et) and not isNil(st) and not isNil(et) then
    cb.ccStart, cb.ccEnd = st / 1000, et / 1000
    cb:SetMinMaxValues(0, 1)
    cb:SetScript("OnUpdate", castOnUpdate)
    cb.spark:Show()
    -- your own latency at the end of the bar
    if u == "player" and GetNetStats and not channel then
      local _, _, home, world = GetNetStats()
      local lag = max(home or 0, world or 0) / 1000
      local tot = cb.ccEnd - cb.ccStart
      if tot > 0 and lag > 0 then cb.safe:SetWidth(max(1, cb:GetWidth() * min(1, lag / tot))); cb.safe:Show() end
    end
  else
    -- the game hides the timing: let the bar run off the game's own duration object
    cb.ccStart = nil; cb:SetScript("OnUpdate", nil); cb.spark:Hide(); cb.time:SetText("")
    local dur = try(channel and UnitChannelDuration or UnitCastingDuration, u)
    local drain = channel
    if f.cfg.castFill == "drain" then drain = not drain end
    local E = Enum and Enum.StatusBarTimerDirection
    local dir = E and (drain and E.RemainingTime or E.ElapsedTime) or nil
    local ok = dur and cb.SetTimerDuration and (pcall(cb.SetTimerDuration, cb, dur, nil, dir) or pcall(cb.SetTimerDuration, cb, dur))
    cb.ccSecret = ok and true or nil
    if not ok then cb:SetMinMaxValues(0, 1); cb:SetValue(1) end
  end
  cb:Show()
end

-- combo points (on the target frame), energy ticks / five-second rule (player)
local function UpdateCombo(f)
  if f.key ~= "target" then for _, p in ipairs(f.combo) do p:Hide() end return end
  local show = f.cfg.combo
  local n, mx = 0, 5
  if show then
    local _, cls = UnitClass("player")
    if cls ~= "ROGUE" and cls ~= "DRUID" then show = false end
  end
  if show then
    local CP = Enum and Enum.PowerType and Enum.PowerType.ComboPoints
    if GetComboPoints then n = try(GetComboPoints, "player", "target") or 0 end
    if (n == 0 or sec(n)) and CP then n = try(UnitPower, "player", CP) or 0 end
    if sec(n) then n = 0 end
    if CP then local m = try(UnitPowerMax, "player", CP); if m and not sec(m) and m > 0 then mx = min(5, m) end end
    if n == 0 and not UnitExists("target") then show = false end
  end
  for i, p in ipairs(f.combo) do
    p:SetShown(show and i <= mx)
    p.fill:SetShown(i <= n)
  end
  pcall(S.UFReact.combo, f, show and n or 0)
end

local function tickOnUpdate(f)
  local t = f.tick
  if not playerTick.kind then t:Hide() return end
  local now = GetTime()
  local p
  if playerTick.kind == "mana" then
    if not playerTick.spentAt or now - playerTick.spentAt > 5 then t:Hide() return end
    p = (now - playerTick.spentAt) / 5
  else
    if not playerTick.last then t:Hide() return end
    p = ((now - playerTick.last) % 2) / 2
  end
  t:ClearAllPoints(); t:SetPoint("CENTER", f.power, "LEFT", f.power:GetWidth() * p, 0); t:Show()
end
local lastPlayerPower
local function trackPlayerPower()
  local ptype = UnitPowerType("player")
  local cur = UnitPower("player")
  if sec(cur, ptype) then playerTick.kind = nil return end
  if ptype == 3 then playerTick.kind = "energy" elseif ptype == 0 then playerTick.kind = "mana" else playerTick.kind = nil end
  if lastPlayerPower and playerTick.kind then
    if cur > lastPlayerPower then
      if playerTick.kind == "energy" then playerTick.last = GetTime() end
    elseif cur < lastPlayerPower and playerTick.kind == "mana" then playerTick.spentAt = GetTime() end
  end
  lastPlayerPower = cur
end

-- fading: range for group frames, out-of-combat fade for your own frame
local function UpdateFade(f)
  local c = f.cfg
  if f.fake then f:SetAlpha(1) return end
  if f.key == "player" and c.fade then
    local idle = not UnitAffectingCombat("player") and not UnitExists("target")
    if idle then
      local h, hm = UnitHealth("player"), UnitHealthMax("player")
      if sec(h, hm) or h < hm then idle = false end
      local pt = UnitPowerType("player")
      local p, pm = UnitPower("player"), UnitPowerMax("player")
      if idle and not sec(p, pm, pt) and pt == 0 and p < pm then idle = false end
      if f.cast:IsShown() then idle = false end
    end
    f:SetAlpha(idle and c.fadeAlpha or 1)
    return
  end
  if c.range and UnitInRange and f.unit ~= "player" and not bool(try(UnitIsUnit, f.unit, "player")) then
    local inR, checked = try(UnitInRange, f.unit)
    if sec(inR, checked) then
      if f.SetAlphaFromBoolean then pcall(f.SetAlphaFromBoolean, f, inR, 1, c.rangeAlpha) end
    elseif checked then f:SetAlpha(inR and 1 or c.rangeAlpha)
    else f:SetAlpha(1) end
  else f:SetAlpha(1) end
end

-- test mode: paint made-up values
local function PaintFake(f)
  local d = f.fake
  local c = f.cfg
  local cr, cg, cb2 = classColor(d.class)
  if d.enemy then cr, cg, cb2 = 0.85, 0.2, 0.15 end
  cr, cg, cb2 = cr or 0.3, cg or 0.8, cb2 or 0.25
  local hp = d.hp
  f.health:SetMinMaxValues(0, 1); f.health:SetValue(hp)
  if c.healthColor == "dark" then f.health:SetStatusBarColor(0.16, 0.16, 0.16); f.health.bg:SetVertexColor(cr, cg, cb2, 0.9)
  else
    if c.healthColor == "green" then cr, cg, cb2 = 0.3, 0.8, 0.25
    elseif c.healthColor == "gradient" then if hp > 0.5 then cr, cg, cb2 = (1 - hp) * 2, 0.85, 0.2 else cr, cg, cb2 = 0.9, hp * 1.7, 0.15 end end
    f.health:SetStatusBarColor(cr, cg, cb2); f.health.bg:SetVertexColor(cr * 0.22, cg * 0.22, cb2 * 0.22, 0.95)
  end
  local mx = 4200
  f.status:SetText(d.dead and "Dead" or ""); f.status:SetShown(d.dead and true or false)
  f.hpText:SetText(d.dead and "" or fmtValue(c.healthText, floor(mx * hp), mx))
  if (c.powerH or 0) > 0 then
    local r, g, b = powerColor(d.ptype)
    f.power:SetMinMaxValues(0, 1); f.power:SetValue(d.pp)
    f.power:SetStatusBarColor(r, g, b); f.power.bg:SetVertexColor(r * 0.22, g * 0.22, b * 0.22, 0.95)
    f.ppText:SetText((c.powerText ~= "none" and f.power:GetHeight() >= 9) and fmtValue(c.powerText, floor(3000 * d.pp), 3000) or "")
  end
  local lv = ""
  if c.level then lv = S.UFCol.level(c, d.level < 0 and "|cffff3333Boss|r " or ("|cffffd100" .. d.level .. "|r ")) end
  local la = f.ccLevelAt or "name"
  if f.ccArtLv then S.UFArt.level(f, lv); lv = "" end
  if la ~= "name" then
    f.levelText:SetText(la ~= "off" and (lv:gsub(" $", "")) or "")
    if f.levelBox and (la == "beside" or la == "above" or la == "under") then f.levelBox:SetShown(la ~= "off" and not f.ccArtLv) end
    lv = ""
  end
  f.nameText:SetText(c.name and (lv .. d.name) or "")
  pcall(S.UFNameFit, f)
  local nr, ng, nb = 1, 1, 1
  if c.nameColor == "class" then local x, y, z = classColor(d.class); if x then nr, ng, nb = x, y, z end
  elseif c.nameColor == "theme" then local t = UI:Theme().gold; nr, ng, nb = t[1], t[2], t[3] end
  f.nameText:SetTextColor(nr, ng, nb)
  S.UFCol.health(f); if (c.powerH or 0) > 0 then S.UFCol.power(f) end; S.UFCol.name(f)
  if c.portrait == "class" or (c.portrait ~= "none" and not d.enemy) then
    local tc = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[d.class]
    if tc then f.ptex:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles"); f.ptex:SetTexCoord(unpack(tc)); f.ptex:Show(); f.model:Hide() end
  elseif c.portrait ~= "none" then
    f.ptex:SetTexture("Interface\\TargetingFrame\\TargetDead"); f.ptex:SetTexCoord(0, 1, 0, 1); f.ptex:Show(); f.model:Hide()
  end
  f.leader:SetShown(c.ind.leader and d.leader and true or false)
  if c.ind.role and d.role and GetTexCoordsForRoleSmallCircle then f.role:SetTexCoord(GetTexCoordsForRoleSmallCircle(d.role)); f.role:Show() else f.role:Hide() end
  f.mark:Hide(); f.ready:Hide(); f.combatIcon:Hide(); f.restIcon:Hide(); f.pvp:Hide(); f.pred:Hide(); f.absorb:Hide()
  f.hl:SetShown(d.hl and true or false)
  if d.hl then hlColor(f, d.hl[1], d.hl[2], d.hl[3]) end
  -- every icon slot filled, so you see where they all go
  local DT = { "Magic", "Curse", "Poison", "Disease" }
  for i, b in ipairs(f.buffs) do
    local on = c.buffs and i <= c.auraMax
    if on then
      b.unit = nil; b.icon:SetTexture(FAKE_ICONS[(i % #FAKE_ICONS) + 1]); b.count:SetText(i == 2 and "3" or ""); b.cd:SetCooldown(GetTime() - i * 3, 30 + i * 5)
      auraEdge(b, 0, 0, 0)
    end
    b:SetShown(on and true or false)
  end
  for i, b in ipairs(f.debuffs) do
    local on = c.debuffs and i <= c.auraMax
    if on then
      b.unit = nil; b.icon:SetTexture(FAKE_ICONS[((i + 2) % #FAKE_ICONS) + 1]); b.count:SetText(i == 3 and "2" or ""); b.cd:SetCooldown(GetTime() - i * 2, 18 + i * 3)
      local t = DT[((i - 1) % #DT) + 1]
      local col = (DebuffTypeColor and DebuffTypeColor[t]) or { r = 0.8, g = 0, b = 0 }
      auraEdge(b, col.r, col.g, col.b)
    end
    b:SetShown(on and true or false)
  end
  if c.castbar then
    local cb = f.cast
    -- different spells and lengths per frame so they don't all move together
    local SP = { player = { "Lightning Bolt", 136048, 2.5 }, target = { "Fireball", 135812, 3.5 }, focus = { "Frostbolt", 135846, 3 },
      pet = { "Shadow Bolt", 136197, 2 }, party = { "Healing Wave", 136052, 3 }, boss = { "Flame Wave", 135807, 4 } }
    local sp = SP[f.key] or SP.target
    local len = sp[3] + ((f.fake and f.fake.name and #f.fake.name or 0) % 4) * 0.4
    cb.ccChannel = f.key == "pet"
    cb.ccCfg, cb.ccUnit, cb.ccFading = c, f.unit or f.key, nil
    cb:SetAlpha(1); cb.spark:SetAlpha(c.castSpark == false and 0 or 1)
    castColor(cb, f.key == "boss")
    cb.icon:SetTexture(sp[2])
    local rk = c.castRank
    cb.text:SetText(sp[1] .. ((rk == "short" and "  |cffbbbbbbR7|r") or (rk == "full" and "  |cffbbbbbb(Rank 7)|r") or ""))
    cb.ccStart, cb.ccEnd = GetTime() - len * 0.3, GetTime() + len * 0.7
    cb:SetMinMaxValues(0, 1)
    cb:SetScript("OnUpdate", function(self)
      if GetTime() > self.ccEnd then self.ccStart, self.ccEnd = GetTime(), GetTime() + len end
      castOnUpdate(self)
    end)
    cb.spark:Show(); cb:Show()
  else CastStop(f) end
  for i, p in ipairs(f.combo) do p:SetShown(f.key == "target" and c.combo and i <= 5); p.fill:SetShown(i <= 3) end
  f:SetAlpha(d.far and c.range and c.rangeAlpha or 1)
  if S.UFElite then pcall(S.UFElite.update, f) end
end

UpdateAll = function(f)
  if not f or not f.ccLaidOut then return end
  if f.fake then PaintFake(f) return end
  local u = f.unit
  if not u or not UnitExists(u) then return end
  f.ccReactBase = true                       -- new unit / full refresh: no reaction, just a new starting point
  run("UpdateHealth", UpdateHealth, f)
  run("UpdatePower", UpdatePower, f)
  run("UpdateName", UpdateName, f)
  local guid = try(UnitGUID, u)
  if sec(guid) or isNil(guid) or guid ~= f.ccGUID or f.ccPortraitMode ~= f.cfg.portrait then
    f.ccGUID = (not sec(guid)) and guid or nil
    f.ccPortraitMode = f.cfg.portrait
    run("portraitUpdate", portraitUpdate, f)
  end
  run("UpdateIcons", UpdateIcons, f)
  run("UpdateHighlight", UpdateHighlight, f)
  run("UpdateAuras", UpdateAuras, f)
  run("UpdateCombo", UpdateCombo, f)
  f.ccReactBase = nil
  run("UpdateFade", UpdateFade, f)
  if f.cfg.castbar then
    local cn = try(UnitCastingInfo, u)
    if type(cn) ~= "nil" then run("CastStart", CastStart, f, false)
    elseif type(try(UnitChannelInfo, u)) ~= "nil" then run("CastStart", CastStart, f, true)
    else CastStop(f) end
  else CastStop(f) end
end

local function forUnit(u, fn)
  local set = u and byUnit[u]
  if not set then return end
  for f in pairs(set) do
    if f.ccLaidOut and not f.fake and f:IsVisible() then run("event:" .. u, fn, f) end
  end
end
local function forAll(fn)
  for _, f in ipairs(frames) do if f.ccLaidOut and not f.fake and f.unit and f:IsVisible() then run("all", fn, f) end end
end

---------------------------------------------------------------------------
-- Holders, movers, groups
---------------------------------------------------------------------------
-- where a holder sits, as offsets from the screen centre (snaps to the centre line)
local function readPos(h)
  local hx, hy = h:GetCenter()
  local ux, uy = UIParent:GetCenter()
  local s = h:GetEffectiveScale() / UIParent:GetEffectiveScale()
  local x, y = floor(hx * s - ux + 0.5), floor(hy * s - uy + 0.5)
  local st = style()
  if st.snap then
    -- r114 grid snapping: the frame's left and top edges land on grid lines (the grid is drawn from the centre)
    local g = max(4, tonumber(st.gridSize) or 32)
    local w, hh = (h:GetWidth() or 0) * s, (h:GetHeight() or 0) * s
    local left = floor((x - w / 2) / g + 0.5) * g
    local top = floor((y + hh / 2) / g + 0.5) * g
    return floor(left + w / 2 + 0.5), floor(top - hh / 2 + 0.5)
  end
  if math.abs(x) <= 10 then x = 0 end
  if math.abs(y) <= 10 then y = 0 end
  return x, y
end
local function savePos(key)
  local h = holders[key]
  if not h then return end
  local c = cfg(key)
  c.x, c.y = readPos(h)
end

local gridFrame
local function showGrid(on)
  local step = max(4, tonumber(style().gridSize) or 32)
  if gridFrame and gridFrame.step ~= step then
    for _, t in ipairs(gridFrame.lines) do t:Hide() end
    gridFrame:Hide(); gridFrame = nil
  end
  if on and style().grid then
    if not gridFrame then
      gridFrame = CreateFrame("Frame", nil, UIParent); gridFrame:SetAllPoints(); gridFrame:SetFrameStrata("BACKGROUND")
      gridFrame.lines = {}; gridFrame.step = step
      local W, H = UIParent:GetWidth(), UIParent:GetHeight()
      local function line(horizontal, off, mid)
        local t = gridFrame:CreateTexture(nil, "BACKGROUND"); t:SetTexture(WHITE)
        if horizontal then t:SetHeight(mid and 2 or 1); t:SetPoint("LEFT", UIParent, "LEFT", 0, off); t:SetPoint("RIGHT", UIParent, "RIGHT", 0, off)
        else t:SetWidth(mid and 2 or 1); t:SetPoint("TOP", UIParent, "TOP", off, 0); t:SetPoint("BOTTOM", UIParent, "BOTTOM", off, 0) end
        t.mid = mid
        gridFrame.lines[#gridFrame.lines + 1] = t
      end
      for x = 0, W / 2, step do line(false, x, x == 0); if x > 0 then line(false, -x) end end
      for y = 0, H / 2, step do line(true, y, y == 0); if y > 0 then line(true, -y) end end
    end
    local g = UI:Theme().gold
    for _, t in ipairs(gridFrame.lines) do
      if t.mid then t:SetVertexColor(g[1], g[2], g[3], 0.5) else t:SetVertexColor(0, 0, 0, 0.35) end
    end
    gridFrame:Show()
  elseif gridFrame then gridFrame:Hide() end
end

local function placeHolder(key)
  local h, c = holders[key], cfg(key)
  if not h then return end
  local sc = c.scale or 1
  h:SetScale(sc)
  h:ClearAllPoints(); h:SetPoint("CENTER", UIParent, "CENTER", (c.x or 0) / sc, (c.y or 0) / sc)
end

local function makeMover(h, label, onDrop, onRight)
  local m = CreateFrame("Button", nil, h, BACKDROP_T)
  plainBackdrop(m)
  m:SetAllPoints(); m:SetFrameStrata("MEDIUM"); m:Hide()   -- under the settings window (DIALOG)
  m.label = UI:Text(m, label, "normal", "CENTER"); m.label:SetPoint("CENTER")
  m:RegisterForClicks("AnyUp")
  m:SetScript("OnMouseDown", function(_, b) if b == "LeftButton" and not combat() then h:StartMoving() end end)
  m:SetScript("OnMouseUp", function(_, b)
    h:StopMovingOrSizing()
    if b == "LeftButton" then onDrop() elseif b == "RightButton" then onRight() end
  end)
  m:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine(label, UI:Accent())
    GameTooltip:AddLine("Drag to move (snaps to the middle of the screen). Right-click for its settings.", 1, 1, 1, true); GameTooltip:Show()
  end)
  m:SetScript("OnLeave", function() GameTooltip:Hide() end)
  UI:Skin(m, function(self, th)
    self:SetBackdropColor(th.gold[1], th.gold[2], th.gold[3], 0.18); self:SetBackdropBorderColor(th.gold[1], th.gold[2], th.gold[3], 1)
    self.label:SetTextColor(th.text[1], th.text[2], th.text[3])
  end)
  return m
end

-- a cast bar's own holder (Cast bar > Position: free)
local function makeCastHolder(key)
  local h = CreateFrame("Frame", "CC_UF_Cast_" .. key, UIParent)
  h:SetSize(10, 10); h:SetMovable(true); h:SetClampedToScreen(true)
  h:SetFrameStrata("LOW")
  h.mover = makeMover(h, LABEL[key] .. " cast bar", function()
    local c = cfg(key)
    c.castX, c.castY = readPos(h)
    local sc = c.scale or 1
    h:ClearAllPoints(); h:SetPoint("CENTER", UIParent, "CENTER", c.castX / sc, c.castY / sc)
  end, function() S:ShowUnitFrames(key, 5) end)
  castHolders[key] = h
  return h
end

local function makeHolder(key)
  local h = CreateFrame("Frame", "CC_UF_Hold_" .. key, UIParent)
  h:SetSize(10, 10); h:SetMovable(true); h:SetClampedToScreen(true)
  h:SetFrameStrata("LOW")
  h.mover = makeMover(h, LABEL[key], function() savePos(key); placeHolder(key) end, function() S:ShowUnitFrames(key) end)
  holders[key] = h
  return h
end

-- party / boss: buttons in a column or row
local function groupSize(key, n)
  local c = cfg(key)
  local across = c.growth == "right"
  local w = across and (n * c.w + (n - 1) * c.spacing) or c.w
  local h = across and c.h or (n * c.h + (n - 1) * c.spacing)
  return max(10, w), max(10, h)
end
local function layoutGroup(key)
  local list = groupKids[key]
  local c = cfg(key)
  local h = holders[key]
  local across = c.growth == "right"
  for i, f in ipairs(list) do
    f:ClearAllPoints()
    if across then f:SetPoint("TOPLEFT", h, "TOPLEFT", (i - 1) * (c.w + c.spacing), 0)
    else f:SetPoint("TOPLEFT", h, "TOPLEFT", 0, -(i - 1) * (c.h + c.spacing)) end
  end
  h:SetSize(groupSize(key, #list))
end

-- raid: the game's group header, one column (or row) per group
local function raidAttributes()
  local c = cfg("raid")
  local h = raidHeader
  local cols = c.groupsAs ~= "rows"
  h:SetAttribute("ccW", c.w); h:SetAttribute("ccH", c.h)
  h:SetAttribute("groupBy", "GROUP")
  h:SetAttribute("groupingOrder", "1,2,3,4,5,6,7,8")
  h:SetAttribute("maxColumns", 8)
  h:SetAttribute("unitsPerColumn", 5)
  h:SetAttribute("columnSpacing", c.spacing)
  if cols then
    h:SetAttribute("point", "TOP"); h:SetAttribute("xOffset", 0); h:SetAttribute("yOffset", -c.spacing)
    h:SetAttribute("columnAnchorPoint", "LEFT")
  else
    h:SetAttribute("point", "LEFT"); h:SetAttribute("xOffset", c.spacing); h:SetAttribute("yOffset", 0)
    h:SetAttribute("columnAnchorPoint", "TOP")
  end
  local hold = holders.raid
  if cols then hold:SetSize(8 * c.w + 7 * c.spacing, 5 * c.h + 4 * c.spacing)
  else hold:SetSize(5 * c.w + 4 * c.spacing, 8 * c.h + 7 * c.spacing) end
  h:ClearAllPoints(); h:SetPoint("TOPLEFT", hold, "TOPLEFT")
  for i = 1, 40 do
    local b = h:GetAttribute("child" .. i) or _G[h:GetName() .. "UnitButton" .. i]
    if b then b:SetSize(c.w, c.h) end
  end
end

local function styleRaidChildren()
  if not raidHeader then return end
  for i = 1, 40 do
    local b = raidHeader:GetAttribute("child" .. i) or _G[raidHeader:GetName() .. "UnitButton" .. i]
    if b and not b.ccStyled then
      Style(b, "raid")
      groupKids.raid[#groupKids.raid + 1] = b
      mapUnit(b, b:GetAttribute("unit"))
      b:HookScript("OnAttributeChanged", function(self, attr, v) if attr == "unit" then mapUnit(self, v); if v then UpdateAll(self) end end end)
      b:HookScript("OnShow", function(self) mapUnit(self, self:GetAttribute("unit")); UpdateAll(self) end)
      Layout(b)
    end
  end
end

---------------------------------------------------------------------------
-- The game's own frames
---------------------------------------------------------------------------
local hidden = {}
local function kill(f, keepEvents)
  if not f or hidden[f] then return end
  hidden[f] = true
  if not keepEvents and f.UnregisterAllEvents then pcall(f.UnregisterAllEvents, f) end
  pcall(f.Hide, f)
  pcall(f.SetParent, f, hider)
end
local BLIZZ = {
  player = { "PlayerFrame" },
  pet = { "PetFrame" },
  target = { "TargetFrame", "ComboFrame" },
  targettarget = { "TargetFrameToT" },
  focus = { "FocusFrame", "FocusFrameToT" },
  party = { "PartyFrame", "PartyMemberFrame1", "PartyMemberFrame2", "PartyMemberFrame3", "PartyMemberFrame4", "CompactPartyFrame" },
  raid = { "CompactRaidFrameManager", "CompactRaidFrameContainer" },
  boss = { "BossTargetFrameContainer", "Boss1TargetFrame", "Boss2TargetFrame", "Boss3TargetFrame", "Boss4TargetFrame", "Boss5TargetFrame" },
}
-- Totem bar (r83): its own box you can move, icons in the frames' style, timers the game counts down.
-- Buttons are secure (right-click dismisses a totem, even in a fight), so they're never shown / hidden
-- or moved in combat: an empty slot just goes see-through. Layout changes wait for the fight to end.
S.UFTot = { btns = {}, ELEM = {
  [1] = { "Fire", 1, 0.35, 0.15 }, [2] = { "Earth", 0.65, 0.45, 0.2 }, [3] = { "Water", 0.25, 0.55, 1 }, [4] = { "Air", 0.6, 0.85, 1 } },
  ORDERS = { slot = { 1, 2, 3, 4 }, efwa = { 2, 1, 3, 4 }, eafw = { 2, 4, 1, 3 }, fewa = { 1, 2, 3, 4 }, wfea = { 3, 1, 2, 4 } },
  DEF = { on = true, size = 30, perRow = 4, spacing = 4, grow = "right", rowGrow = "down", order = "efwa", empty = "hide",
    timer = "on", swipe = true, edge = "element", tooltip = true, dismiss = true, scale = 1, x = -200, y = -160 } }
do
  local T = S.UFTot
  function T.cfg()
    local d = store()
    d.totemBar = deep(type(d.totemBar) == "table" and d.totemBar or {}, T.DEF)
    return d.totemBar
  end
  function T.on() return store().on and T.cfg().on end
  function T.place()
    local h, c = T.hold, T.cfg()
    if not h then return end
    h:SetScale(c.scale or 1)
    h:ClearAllPoints(); h:SetPoint("CENTER", UIParent, "CENTER", (c.x or 0) / (c.scale or 1), (c.y or 0) / (c.scale or 1))
  end
  function T.build()
    if T.hold then return end
    local h = CreateFrame("Frame", "CC_UF_Hold_totems", UIParent)
    h:SetSize(10, 10); h:SetMovable(true); h:SetClampedToScreen(true); h:SetFrameStrata("LOW")
    h.mover = makeMover(h, "Totems", function()
      local c = T.cfg(); c.x, c.y = readPos(h); T.place()
    end, function() S:ShowUnitFrames(nil, 8) end)
    T.hold = h
    for slot = 1, 4 do
      local b = auraButton(h)
      b.slot = slot
      b:SetScript("OnEnter", function(self)
        if not T.cfg().tooltip or self:GetAlpha() < 0.5 then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        if self.fake then GameTooltip:AddLine(self.fake, 1, 1, 1) else try(GameTooltip.SetTotem, GameTooltip, slot) end
        if T.cfg().dismiss then GameTooltip:AddLine("Right-click to dismiss", 0.6, 0.6, 0.6) end
        GameTooltip:Show()
      end)
      -- invisible secure button on top: right-click = dismiss this totem
      local sb = CreateFrame("Button", "CC_UF_Totem" .. slot, b, "SecureActionButtonTemplate")
      sb:SetAllPoints(); sb:RegisterForClicks("RightButtonUp", "RightButtonDown")
      sb:SetAttribute("type2", "destroytotem"); sb:SetAttribute("totem-slot", slot)
      sb:SetScript("OnEnter", function() b:GetScript("OnEnter")(b) end)
      sb:SetScript("OnLeave", function() GameTooltip:Hide() end)
      b.secure = sb
      T.btns[slot] = b
    end
  end
  -- size, rows, order, look (out of combat only)
  function T.layout()
    if not T.hold then return end
    if combat() then afterCombat("totems", T.layout) return end
    local c = T.cfg()
    local sz, sp, per = c.size, c.spacing, max(1, min(4, c.perRow))
    local order = T.ORDERS[c.order] or T.ORDERS.slot
    local across = c.grow == "right" or c.grow == "left"
    local rows = math.ceil(4 / per)
    local w = across and (per * sz + (per - 1) * sp) or (rows * sz + (rows - 1) * sp)
    local hgt = across and (rows * sz + (rows - 1) * sp) or (per * sz + (per - 1) * sp)
    local under = c.timer == "under" and max(7, floor(sz * 0.40 + 0.5)) + 2 or 0
    if across then hgt = hgt + under * (rows - 1) else w = w end
    T.hold:SetSize(max(10, w), max(10, hgt + under))
    for pos, slot in ipairs(order) do
      local b = T.btns[slot]
      local i, r = (pos - 1) % per, floor((pos - 1) / per)
      local step, rstep = sz + sp, sz + sp + (across and under or 0)
      local x, y
      if across then
        x = (c.grow == "left") and (w - sz - i * step) or (i * step)
        y = (c.rowGrow == "up") and -((rows - 1 - r) * rstep) or -(r * rstep)
      else
        y = (c.grow == "up") and -(hgt - sz - i * (sz + sp + under)) or -(i * (sz + sp + under))
        x = (c.rowGrow == "left") and ((rows - 1 - r) * step) or (r * step)
      end
      b:ClearAllPoints(); b:SetPoint("TOPLEFT", T.hold, "TOPLEFT", x, y)
      b:SetSize(sz, sz)
      auraShape(b); auraText(b, c.timer, sz)
      if b.cd.SetDrawSwipe then b.cd:SetDrawSwipe(c.swipe and true or false) end
      local e = T.ELEM[slot]
      if c.edge == "element" then auraEdge(b, e[2], e[3], e[4])
      elseif c.edge == "theme" then local th = UI.theme or {}; local g = th.gold or { 0.9, 0.75, 0.3 }; auraEdge(b, g[1], g[2], g[3])
      else auraEdge(b, 0, 0, 0) end
      b.secure:SetAttribute("type2", c.dismiss and "destroytotem" or nil)
      b:Show()
    end
    local show = T.on()
    T.hold:SetShown(show)
    T.update()
  end
  -- what's down right now (safe in combat: only alpha, texture and the cooldown change)
  function T.update()
    if not T.hold or not T.hold:IsShown() then return end
    local c = T.cfg()
    local emptyA = c.empty == "show" and 1 or c.empty == "dim" and 0.3 or 0
    for slot, b in ipairs(T.btns) do
      if b.fake then
        b:SetAlpha(1)
      else
        local ok, have, name, start, dur, icon = pcall(GetTotemInfo, slot)
        if not ok then have = false end
        if sec(have) then
          if b.SetAlphaFromBoolean then pcall(b.SetAlphaFromBoolean, b, have, 1, emptyA) else b:SetAlpha(1) end
          b.icon:SetTexture(icon); pcall(b.cd.SetCooldown, b.cd, start, dur)
        elseif have and not isNil(icon) and (sec(icon) or icon ~= "") then
          b:SetAlpha(1)
          b.icon:SetTexture(icon)
          if sec(start, dur) then pcall(b.cd.SetCooldown, b.cd, start, dur)
          elseif type(dur) == "number" and dur > 0 then b.cd:SetCooldown(start, dur) else b.cd:Clear() end
          b.icon:SetDesaturated(false)
        else
          b:SetAlpha(emptyA); b.cd:Clear()
          b.icon:SetTexture(c.empty == "hide" and nil or 136232)   -- empty: plain totem icon
          b.icon:SetDesaturated(true)
        end
      end
    end
  end
  local FAKE_T = { { 135825, "Searing Totem", 55 }, { 136097, "Stoneskin Totem", 120 }, { 135861, "Mana Spring Totem", 60 }, { 136114, "Windfury Totem", 120 } }
  function T.test(on)
    if not T.hold then return end
    for slot, b in ipairs(T.btns) do
      if on then
        local f = FAKE_T[slot]
        b.fake = f[2]; b.icon:SetTexture(f[1]); b.icon:SetDesaturated(false)
        b.cd:SetCooldown(GetTime() - f[3] * (slot / 6), f[3])
      else b.fake = nil end
    end
    T.layout()
  end
  function T.unlock(on) if T.hold then T.hold.mover:SetShown(on and T.on() and true or false) end end
end

local function keepTotems()
  local tf = _G.TotemFrame
  if tf and S.UFTot.on() then pcall(kill, tf) return end
  if not tf or not single.player or not cfg("player").totems then return end
  pcall(tf.SetParent, tf, UIParent)
  pcall(tf.ClearAllPoints, tf)
  pcall(tf.SetPoint, tf, "TOPLEFT", single.player, "BOTTOMLEFT", 0, -((cfg("player").castbar and cfg("player").castPos ~= "free" and cfg("player").castPos ~= "above") and (cfg("player").castH + 8) or 6))
end
local function hideBlizzard()
  local d = store()
  if not d.on then return end
  afterCombat("blizz", function()
    for key, names in pairs(BLIZZ) do
      local c = cfg(key)
      if c.on and c.replace then
        if key == "player" then keepTotems() end
        for _, n in ipairs(names) do kill(_G[n], key == "raid" or key == "party") end
      end
    end
    local pc = cfg("player")
    if pc.on and pc.replace and pc.castbar then
      kill(_G.PlayerCastingBarFrame); kill(_G.CastingBarFrame)
    end
  end)
end

---------------------------------------------------------------------------
-- Build / apply
---------------------------------------------------------------------------
local function buildAll()
  if built then return end
  built = true
  for _, key in ipairs(KEYS) do makeHolder(key) end
  for key in pairs(CAST_FREE) do makeCastHolder(key) end
  S.UFTot.build()
  for _, key in ipairs({ "player", "target", "targettarget", "focus", "pet" }) do
    local f = newUnitButton("CC_UF_" .. key, holders[key], key, key)
    f:SetPoint("TOPLEFT", holders[key], "TOPLEFT")
    single[key] = f
  end
  -- party: a box that's only there in a group (and, if you like, not in a raid)
  partyBox = CreateFrame("Frame", "CC_UF_PartyBox", holders.party, "SecureHandlerStateTemplate")
  partyBox:SetAllPoints()
  local pp = newUnitButton("CC_UF_PartyPlayer", partyBox, "player", "party")
  pp.ccPartyPlayer = true
  groupKids.party[1] = pp
  for i = 1, 4 do groupKids.party[i + 1] = newUnitButton("CC_UF_Party" .. i, partyBox, "party" .. i, "party") end
  for i = 1, 5 do groupKids.boss[i] = newUnitButton("CC_UF_Boss" .. i, holders.boss, "boss" .. i, "boss") end
  -- raid header
  raidHeader = CreateFrame("Frame", "CC_UF_Raid", holders.raid, "SecureGroupHeaderTemplate")
  raidHeader:SetAttribute("template", "SecureUnitButtonTemplate" .. (BACKDROP_T and ",BackdropTemplate" or ""))
  raidHeader:SetAttribute("initialConfigFunction", [[
    local header = self:GetParent()
    self:SetWidth(header:GetAttribute("ccW") or 78)
    self:SetHeight(header:GetAttribute("ccH") or 40)
    self:SetAttribute("*type1", "target")
    self:SetAttribute("*type2", "togglemenu")
  ]])
  -- (no RegisterForClicks in the snippet: it doesn't exist in Forever's secure environment -
  --  Style() registers the clicks for each raid button, out of combat)
  raidHeader:SetAttribute("showRaid", true)
  raidHeader:SetAttribute("showParty", false)
  raidHeader:SetAttribute("showPlayer", true)
  raidHeader:SetAttribute("showSolo", false)
  raidAttributes()
  -- make all 40 buttons now (so nothing has to be built in combat)
  raidHeader:SetAttribute("startingIndex", -39)
  raidHeader:Show()
  raidHeader:SetAttribute("startingIndex", 1)
  styleRaidChildren()
end

local function applyKey(key)
  local d = store()
  local c = cfg(key)
  local on = d.on and c.on
  placeHolder(key)
  if key == "party" then
    for _, f in ipairs(groupKids.party) do f.cfg = c; Layout(f) end
    local list = {}
    for _, f in ipairs(groupKids.party) do
      local use = on and (not f.ccPartyPlayer or c.showPlayer)
      if use then list[#list + 1] = f end
      if not testing then
        if use and not f.ccPartyPlayer then RegisterUnitWatch(f)
        elseif use then UnregisterUnitWatch(f); f:Show()
        else UnregisterUnitWatch(f); f:Hide() end
      end
    end
    local all = groupKids.party
    groupKids.party = list; layoutGroup("party"); groupKids.party = all
    if not testing then
      if on then RegisterStateDriver(partyBox, "visibility", (c.hideInRaid and cfg("raid").on) and "[group:raid] hide; [group:party] show; hide" or "[group] show; hide")
      else UnregisterStateDriver(partyBox, "visibility"); partyBox:Hide() end
    end
  elseif key == "boss" then
    for _, f in ipairs(groupKids.boss) do
      f.cfg = c; Layout(f)
      if not testing then if on then RegisterUnitWatch(f) else UnregisterUnitWatch(f); f:Hide() end end
    end
    layoutGroup("boss")
  elseif key == "raid" then
    styleRaidChildren()
    raidAttributes()
    for _, f in ipairs(groupKids.raid) do f.cfg = c; Layout(f) end
    if not testing then
      if on then RegisterStateDriver(raidHeader, "visibility", "[group:raid] show; hide")
      else UnregisterStateDriver(raidHeader, "visibility"); raidHeader:Hide() end
    end
  else
    local f = single[key]
    f.cfg = c; Layout(f)
    holders[key]:SetSize(c.w, c.h)
    if not testing then
      if on then if key == "player" then UnregisterUnitWatch(f); f:Show() else RegisterUnitWatch(f) end
      else UnregisterUnitWatch(f); f:Hide() end
    end
  end
  if key == "player" then keepTotems() end
end

local function applyNow(key)
  if not built then buildAll() end
  local sd = store()
  if not sd.fontsMoved then               -- r111: per-part fonts moved from all frames to each frame
    sd.fontsMoved = true
    local old = sd.style and sd.style.fonts
    if type(old) == "table" then
      for _, k in ipairs(KEYS) do
        local c = cfg(k); c.fonts = c.fonts or {}
        for e, v in pairs(old) do if type(v) == "table" then c.fonts[e] = { face = v.face, size = v.size } end end
      end
      sd.style.fonts = nil
    end
  end
  if key then applyKey(key) else for _, k in ipairs(KEYS) do applyKey(k) end end
  S.UFTot.place(); S.UFTot.layout()
  hideBlizzard()
  if key and GROUPS[key] then for _, f in ipairs(groupKids[key]) do UpdateAll(f) end
  elseif key and single[key] then UpdateAll(single[key])
  else for _, f in ipairs(frames) do UpdateAll(f) end end
end
-- apply settings (now, or right after the fight)
function S.UFApply(key)
  if not S.db then return end
  if combat() then
    pending["apply" .. (key or "all")] = function() applyNow(key) end
    if not S.__ufCombatNote then S.__ufCombatNote = true; S:Print("Unit frames: changes apply when the fight ends.") end
    return
  end
  local ok, err = pcall(applyNow, key)
  if not ok and S.report then S.report(err) end
end

---------------------------------------------------------------------------
-- Unlock (movers) and test mode
---------------------------------------------------------------------------
function S.UFUnlocked() return unlocked end
function S.UFSetUnlocked(on)
  if on and combat() then S:Print("Can't move frames during a fight.") return end
  if on and not built then buildAll() end
  unlocked = on and true or false
  for key, h in pairs(holders) do
    local c = cfg(key)
    h.mover:SetShown(unlocked and store().on and c.on)
    if key == "raid" then
      h.mover.label:SetText(LABEL.raid .. "  |cffaaaaaa(8 groups)|r")
    end
  end
  for key, h in pairs(castHolders) do
    local c = cfg(key)
    h.mover:SetShown(unlocked and store().on and c.on and c.castbar and c.castPos == "free")
  end
  S.UFTot.unlock(unlocked)
  showGrid(unlocked)
  S.__ufShowGrid = showGrid
  if S.RefreshUnitFrames then S:RefreshUnitFrames() end
  if S.UFEdit then pcall(unlocked and S.UFEdit.enter or S.UFEdit.leave) end
end

local function previewRaid(on)
  local c = cfg("raid")
  if on then
    for i = 1, 25 do
      local f = raidPreview[i]
      if not f then
        f = CreateFrame("Button", nil, holders.raid, BACKDROP_T)
        f.ccPreview = true
        Style(f, "raid")
        raidPreview[i] = f
      end
      f.cfg = c; Layout(f)
      local grp, idx = floor((i - 1) / 5), (i - 1) % 5
      f:ClearAllPoints()
      if c.groupsAs ~= "rows" then f:SetPoint("TOPLEFT", holders.raid, "TOPLEFT", grp * (c.w + c.spacing), -idx * (c.h + c.spacing))
      else f:SetPoint("TOPLEFT", holders.raid, "TOPLEFT", idx * (c.w + c.spacing), -grp * (c.h + c.spacing)) end
      local base = FAKE[((i - 1) % #FAKE) + 1]
      f.fake = setmetatable({ far = (i % 7 == 0), hl = (i == 3) and { 0.7, 0.3, 1, 1 } or nil, hp = (i % 4 == 0) and 0.35 or base.hp }, { __index = base })
      f:SetShown(c.on); PaintFake(f)
    end
  else
    for _, f in ipairs(raidPreview) do f.fake = nil; f:Hide() end
  end
end

function S.UFTesting() return testing end
function S.UFSetTesting(on)
  if on and combat() then S:Print("Test mode can't start during a fight.") return end
  if not built then buildAll() end
  testing = on and true or false
  pcall(S.UFTot.test, testing)
  pcall(S.UFReact.testLoop, testing, frames)
  local d = store()
  local n = 0
  local function fake(f, data)
    n = n + 1
    f.fake = data
    UnregisterUnitWatch(f)
    f:SetShown(d.on and f.cfg.on)
    PaintFake(f)
  end
  if testing then
    local _, myClass = UnitClass("player")
    local ptype = UnitPowerType("player")
    if sec(ptype) then ptype = 0 end
    local myName = UnitName("player")
    if sec(myName) or isNil(myName) then myName = "You" end
    fake(single.player, { name = myName, class = myClass, level = (not sec(UnitLevel("player")) and UnitLevel("player")) or 60, hp = 0.88, pp = 0.72, ptype = ptype })
    fake(single.target, setmetatable({ hl = nil }, { __index = FAKE_ENEMY }))
    fake(single.targettarget, FAKE[2])
    fake(single.focus, FAKE[4])
    fake(single.pet, { name = "Wolf", class = "HUNTER", level = 60, hp = 0.7, pp = 0.5, ptype = 2 })
    UnregisterStateDriver(partyBox, "visibility"); partyBox:SetShown(d.on and cfg("party").on)
    for i, f in ipairs(groupKids.party) do
      if not f.ccPartyPlayer or cfg("party").showPlayer then
        fake(f, setmetatable({ far = i == 4, hl = (i == 3) and { 0.7, 0.3, 1, 1 } or nil }, { __index = FAKE[i] }))
      end
    end
    for i, f in ipairs(groupKids.boss) do
      if i <= 3 then fake(f, setmetatable({ name = ({ "Ragnaros", "Majordomo", "Flamewaker" })[i], hp = 1 - i * 0.2 }, { __index = FAKE_ENEMY })) end
    end
    UnregisterStateDriver(raidHeader, "visibility"); raidHeader:Hide()
    previewRaid(d.on and cfg("raid").on)
  else
    for _, f in ipairs(frames) do
      if f.fake and not f.ccPreview then f.fake = nil; CastStop(f) end
    end
    previewRaid(false)
    S.UFApply()
  end
  if S.RefreshUnitFrames then S:RefreshUnitFrames() end
end

---------------------------------------------------------------------------
-- Events: one handler, routed to the frames showing that unit
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
local function reg(e) pcall(ev.RegisterEvent, ev, e) end
local UNIT_EVENTS = {
  UNIT_HEALTH = UpdateHealth, UNIT_MAXHEALTH = UpdateHealth, UNIT_HEALTH_FREQUENT = UpdateHealth,
  UNIT_HEAL_PREDICTION = UpdateHealth, UNIT_ABSORB_AMOUNT_CHANGED = UpdateHealth, UNIT_CONNECTION = UpdateAll,
  UNIT_POWER_UPDATE = UpdatePower, UNIT_POWER_FREQUENT = UpdatePower, UNIT_MAXPOWER = UpdatePower, UNIT_DISPLAYPOWER = UpdatePower,
  UNIT_NAME_UPDATE = UpdateName, UNIT_LEVEL = UpdateName, UNIT_CLASSIFICATION_CHANGED = UpdateName,
  UNIT_FACTION = function(f) UpdateHealth(f); UpdateName(f); UpdateIcons(f) end, UNIT_FLAGS = UpdateIcons,
  UNIT_AURA = function(f) UpdateAuras(f); UpdateHighlight(f) end,
  UNIT_PORTRAIT_UPDATE = portraitUpdate, UNIT_MODEL_CHANGED = portraitUpdate,
  UNIT_THREAT_SITUATION_UPDATE = UpdateHighlight, UNIT_THREAT_LIST_UPDATE = UpdateHighlight,
  UNIT_SPELLCAST_START = function(f) CastStart(f, false) end, UNIT_SPELLCAST_DELAYED = function(f) CastStart(f, false) end,
  UNIT_SPELLCAST_CHANNEL_START = function(f) CastStart(f, true) end, UNIT_SPELLCAST_CHANNEL_UPDATE = function(f) CastStart(f, true) end,
  UNIT_SPELLCAST_STOP = function(f) CastStop(f, "done") end, UNIT_SPELLCAST_CHANNEL_STOP = function(f) CastStop(f, "done") end,
  UNIT_SPELLCAST_INTERRUPTED = function(f) CastStop(f, "fail") end,
  -- "failed" also fires for a spell you pressed while already casting: only count it when nothing is being cast any more
  UNIT_SPELLCAST_FAILED = function(f) if isNil(try(UnitCastingInfo, f.unit)) and isNil(try(UnitChannelInfo, f.unit)) then CastStop(f, "fail") end end,
  UNIT_SPELLCAST_INTERRUPTIBLE = function(f) castColor(f.cast, false) end,
  UNIT_SPELLCAST_NOT_INTERRUPTIBLE = function(f) castColor(f.cast, true) end,
}
for e in pairs(UNIT_EVENTS) do reg(e) end
for _, e in ipairs({ "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "UNIT_PET", "GROUP_ROSTER_UPDATE", "RAID_TARGET_UPDATE",
  "PARTY_LEADER_CHANGED", "READY_CHECK", "READY_CHECK_CONFIRM", "READY_CHECK_FINISHED", "PLAYER_UPDATE_RESTING",
  "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD", "INSTANCE_ENCOUNTER_ENGAGE_UNIT", "UNIT_TARGETABLE_CHANGED",
  "PLAYER_FLAGS_CHANGED", "UNIT_COMBO_POINTS", "PLAYER_ROLES_ASSIGNED", "UNIT_TARGET", "UNIT_SPELLCAST_SUCCEEDED", "PLAYER_TOTEM_UPDATE" }) do reg(e) end

ev:SetScript("OnEvent", function(_, e, u, ...)
  if not built or not store().on then
    if e == "PLAYER_REGEN_ENABLED" then for id, fn in pairs(pending) do pending[id] = nil; pcall(fn) end end
    return
  end
  if e == "PLAYER_TOTEM_UPDATE" then pcall(S.UFTot.update) return end
  if e == "UNIT_AURA" then run("cacheAuras", cacheAuras, u, ...) end
  if e == "UNIT_SPELLCAST_SUCCEEDED" then
    if u == "player" and combat() then
      local _, spellID = ...
      pcall(NP.onCast, spellID)
      local ok, did, who = pcall(castAura, spellID)
      if ok and did then forUnit(who, UpdateAuras); if who == "target" then forUnit("targettarget", UpdateAuras) end end
    end
    return
  end
  local fn = UNIT_EVENTS[e]
  if fn then
    if u == "player" and (e == "UNIT_POWER_UPDATE" or e == "UNIT_POWER_FREQUENT") then trackPlayerPower() end
    forUnit(u, fn)
    if u == "player" and (e == "UNIT_POWER_UPDATE" or e == "UNIT_POWER_FREQUENT") and single.target then pcall(UpdateCombo, single.target) end
    if (e == "UNIT_AURA" or e == "UNIT_THREAT_SITUATION_UPDATE") then forUnit("target", UpdateHighlight) end
    return
  end
  if e == "PLAYER_TARGET_CHANGED" then
    auraCache.target = nil
    NP.pending = nil; NP.slots = {}; NP.byTex = {}
    local tg = try(UnitGUID, "target")
    if combat() and (isNil(tg) or sec(tg)) then auraMem["tok:target"] = nil end   -- can't tell who it is: don't show the last target's auras
    forUnit("target", UpdateAll); forUnit("targettarget", UpdateAll)
    forAll(UpdateHighlight)
    if single.target then pcall(UpdateCombo, single.target) end
    forUnit("player", UpdateFade)
  elseif e == "PLAYER_FOCUS_CHANGED" then auraCache.focus = nil; if combat() then auraMem["tok:focus"] = nil end; forUnit("focus", UpdateAll)
  elseif e == "UNIT_PET" then forUnit("pet", UpdateAll)
  elseif e == "UNIT_TARGET" then
    if u == "target" then forUnit("targettarget", UpdateAll) end
  elseif e == "GROUP_ROSTER_UPDATE" or e == "PLAYER_ENTERING_WORLD" or e == "PLAYER_ROLES_ASSIGNED" then
    forAll(UpdateAll)
    if e == "PLAYER_ENTERING_WORLD" then trackPlayerPower(); pcall(S.UFTot.update) end
  elseif e == "RAID_TARGET_UPDATE" or e == "PARTY_LEADER_CHANGED" or e == "PLAYER_FLAGS_CHANGED" then forAll(UpdateIcons)
  elseif e == "READY_CHECK" or e == "READY_CHECK_CONFIRM" then forAll(function(f) f.readyHold = nil; UpdateIcons(f) end)
  elseif e == "READY_CHECK_FINISHED" then
    forAll(function(f) f.readyHold = true end)
    C_Timer.After(6, function() forAll(function(f) f.readyHold = nil; f.ready:Hide() end) end)
  elseif e == "PLAYER_UPDATE_RESTING" then forUnit("player", UpdateIcons)
  elseif e == "PLAYER_REGEN_DISABLED" then
    if testing then S.UFSetTesting(false) end
    if unlocked then S.UFSetUnlocked(false) end
    combatAuras(true)
    forUnit("player", function(f) UpdateIcons(f); UpdateFade(f) end)
  elseif e == "PLAYER_REGEN_ENABLED" then
    for id, f2 in pairs(pending) do pending[id] = nil; pcall(f2) end
    combatAuras(false)
    pcall(CDM.give)
    for _, ff in ipairs(frames) do if ff.ccLaidOut and not ff.ccPreview then pcall(Layout, ff) end end
    forAll(UpdateAuras)
    S.__ufCombatNote = nil
    forUnit("player", function(f) UpdateIcons(f); UpdateFade(f) end)
  elseif e == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" or e == "UNIT_TARGETABLE_CHANGED" then
    for _, f in ipairs(groupKids.boss) do UpdateAll(f) end
  elseif e == "UNIT_COMBO_POINTS" then
    if single.target then pcall(UpdateCombo, single.target) end
  end
end)

-- polled: target of target (no events), range, ticks, fading
local acc, accTot, accMem = 0, 0, 0
ev:SetScript("OnUpdate", function(_, el)
  if not built then return end
  local pf = single.player
  if pf and pf.ccLaidOut and pf.cfg.ticks and (pf.cfg.powerH or 0) > 0 and pf:IsVisible() then tickOnUpdate(pf)
  elseif pf then pf.tick:Hide() end
  accTot = accTot + el
  if accTot >= 0.2 then
    accTot = 0
    if not store().on then return end
    forUnit("targettarget", UpdateAll)
  end
  acc = acc + el
  if acc < 0.3 then return end
  acc = 0
  if not store().on then return end
  forUnit("player", UpdateFade)
  if combat() then
    forUnit("player", UpdateAuras); forUnit("target", UpdateAuras)
    accMem = (accMem or 0) + 1
    if accMem >= 3 then accMem = 0; forUnit("focus", UpdateAuras) end
  end
  for _, key in ipairs({ "party", "raid", "pet" }) do
    local list = key == "pet" and { single.pet } or groupKids[key]
    for _, f in ipairs(list) do if f.ccLaidOut and f.unit and not f.fake and f:IsVisible() then run("UpdateFade", UpdateFade, f) end end
  end
end)

S:Listen("LOGIN", function()
  S.UFScanFonts()
  C_Timer.After(2, function() if not combat() then pcall(CDM.give) end end)
  -- Command Center's own font may be one from the folder: it wasn't known when the look was first applied
  local g = S.db.global
  for _, ff in ipairs(folderFonts) do if g.font == ff.name and UI.ApplyTheme then UI:ApplyTheme() break end end
  if store().on then S.UFApply() end
end)

---------------------------------------------------------------------------
-- Settings window
---------------------------------------------------------------------------
local win
local W, H = 980, 720
local cur = "player"
local controls = {}

local function C() return cfg(cur) end
local function path(t, p)
  local a, b = p:match("^(%w+)%.(%w+)$")
  if a then return t[a], b end
  return t, p
end
local function getv(p) local t, k = path(C(), p); return t[k] end
local function setv(p, v)
  local t, k = path(C(), p); t[k] = v
  S.UFApply(cur)
  if unlocked then S.UFSetUnlocked(true) end
end

local ONLY = {
  castbar = { player = 1, target = 1, focus = 1, boss = 1, party = 1, pet = 1 },
  castW = { player = 1, target = 1, focus = 1, pet = 1 },
  combo = { target = 1 }, ticks = { player = 1 }, druidMana = { player = 1 }, totems = { player = 1 },
  fade = { player = 1 }, growth = { party = 1, boss = 1 }, spacing = { party = 1, boss = 1, raid = 1 },
  showPlayer = { party = 1 }, hideInRaid = { party = 1 }, groupsAs = { raid = 1 },
  range = { party = 1, raid = 1, pet = 1 }, rangeAlpha = { party = 1, raid = 1, pet = 1 },
}
local function relevant(ctl) local o = ctl.only and ONLY[ctl.only]; return not o or o[cur] ~= nil end

local function addCtl(ctl, key, only, kind, get)
  ctl.key, ctl.only, ctl.kind, ctl.get = key, only, kind, get
  controls[#controls + 1] = ctl
  return ctl
end
local function check(pane, x, y, label, key, tip, only)
  local b = UI:Check(pane, label, false, function(v) setv(key, v) end, tip)
  b:SetPoint("TOPLEFT", x, y)
  return addCtl(b, key, only, "check")
end
local function slider(pane, x, y, w, label, key, lo, hi, step, fmt, only, scale)
  local s = UI:Slider(pane, w, label, lo, hi, step, lo, function(v) setv(key, scale and v / scale or v) end, fmt)
  s:SetPoint("TOPLEFT", x, y)
  s.scale = scale
  return addCtl(s, key, only, "slider")
end
local function dropdown(pane, x, y, label, key, opts, w, only)
  local l = UI:Text(pane, label, "small"); l:SetPoint("TOPLEFT", x, y - 5)
  local d = UI:Dropdown(pane, w or 150, opts, nil, function(v) setv(key, v) end)
  d:SetPoint("TOPLEFT", x + 110, y)
  d.lbl = l
  if key ~= "castPos" and key ~= "growth" and key ~= "groupsAs" then d.ccPreview = true end
  return addCtl(d, key, only, "drop")
end

function S:RefreshUnitFrames()
  if not win or not win:IsShown() then return end
  local d = store()
  win.master:SetChecked(d.on)
  win.unitDrop:SetValue(cur)
  win.unlock:SetText(unlocked and "Lock frames" or "Unlock frames")
  win.test:SetText(testing and "Stop test" or "Test mode")
  win.enabled:SetChecked(C().on)
  win.replace:SetChecked(C().replace)
  for _, ctl in ipairs(controls) do
    local show = relevant(ctl)
    ctl:SetShown(show)
    if ctl.lbl then ctl.lbl:SetShown(show) end
    if show then
      local v
      if ctl.get then v = ctl.get() elseif ctl.key then v = getv(ctl.key) end
      if ctl.kind == "check" then ctl:SetChecked(v and true or false)
      elseif ctl.kind == "slider" then ctl:SetValue(ctl.scale and floor((v or 0) * ctl.scale + 0.5) or (v or 0))
      elseif ctl.kind == "drop" then ctl:SetValue(v) end
    end
  end
  win.castMove:SetShown(CAST_FREE[cur] and C().castbar and true or false)
  local cdc = store().cdm
  win.cdmOn:SetChecked(cdc.on); win.cdmHide:SetChecked(cdc.hideBar); win.npOn:SetChecked(cdc.nameplates)
  local enabled = C_CVar and C_CVar.GetCVarBool and C_CVar.GetCVarBool("cooldownViewerEnabled")
  local v = CDM.viewer()
  if not v then win.cdmStatus:SetText("|cffff9933Cooldown Manager not found in this game version.|r")
  elseif enabled == false then win.cdmStatus:SetText("|cffff9933Cooldown Manager is off - press the button.|r")
  else win.cdmStatus:SetText("|cff55ff55Cooldown Manager on|r - " .. #CDM.items() .. " tracked buff icons") end
  local st = style()
  win.sTex:SetValue(st.texture); win.sFont:SetValue(st.font); win.sOutline:SetValue(st.outline)
  win.sBg:SetValue(floor(st.bgAlpha * 100 + 0.5)); win.sBorder:SetValue(st.border)
  win.sRound:SetValue(st.round or 0); win.sFace:SetValue(st.face or "cc")
  win.sSmooth:SetChecked(st.smooth); win.sNum:SetValue(st.numbers); win.sGrid:SetChecked(st.grid)
  win.sTheme:SetValue(st.theme or "standard"); win.sArt:SetValue(floor((st.artSize or 1) * 100 + 0.5))
  for _, sw in ipairs(win.swatches or {}) do sw:Refresh() end
  if win.mySw then win.mySw:Refresh(); win.myOn:SetChecked(style().myNameOn and true or false) end
  if win.eTexH then
    local st2 = style(); local an = C().anim or {}
    win.eTexH:SetValue(st2.texHealth or ""); win.eTexP:SetValue(st2.texPower or "")
    win.eAnH:SetValue(an.health or "none"); win.eAnP:SetValue(an.power or "none"); win.eAnC:SetValue(an.cast or "none")
    win.eSpd:SetValue(floor((st2.animSpeed or 1) * 100 + 0.5))
    win.eFA:SetValue(C().frameAnim or "none")
    for _, sw in ipairs(win.eCols or {}) do sw:Refresh() end
    for _, sl in ipairs(win.eStr or {}) do sl:SetValue(floor(sl.ccGet() * 100 + 0.5)) end
    for key, ctl in pairs(win.eFonts) do local fe = (C().fonts or {})[key] or {}; ctl[1]:SetValue(fe.face or ""); ctl[2]:SetValue(fe.size or 0) end
  end
  if win.rHL then
    local rc = style().react or {}
    win.rHL:SetValue(rc.hpLoss or "none"); win.rHG:SetValue(rc.hpGain or "none"); win.rPL:SetValue(rc.ppLoss or "none")
    win.rPG:SetValue(rc.ppGain or "none"); win.rCG:SetValue(rc.comboGain or "none"); win.rCS:SetValue(rc.comboSpend or "none")
    win.rSc:SetValue(rc.scope or "pt"); win.rMin:SetValue(rc.minPct or 0)
    for _, sw in ipairs(win.rCols or {}) do sw:Refresh() end
    win.rStr:SetValue(floor((rc.strength or 1) * 100 + 0.5))
  end
  local tc = S.UFTot.cfg()
  win.tOn:SetChecked(tc.on); win.tSize:SetValue(tc.size); win.tPer:SetValue(tc.perRow); win.tSp:SetValue(tc.spacing)
  win.tScale:SetValue(floor((tc.scale or 1) * 100 + 0.5)); win.tGrow:SetValue(tc.grow); win.tRow:SetValue(tc.rowGrow)
  win.tOrder:SetValue(tc.order); win.tEmpty:SetValue(tc.empty); win.tTimer:SetValue(tc.timer); win.tEdge:SetValue(tc.edge)
  win.tSwipe:SetChecked(tc.swipe); win.tTip:SetChecked(tc.tooltip); win.tDis:SetChecked(tc.dismiss)
  win.info:SetText(d.on and "" or "|cffff9933Turn on \"Use Command Center unit frames\" to see them.|r")
  if win.paintSide then win.paintSide() end
end

local function buildWindow()
  win = UI:Window("CC_UnitFrames", "Unit Frames", W, H)
  win:SetFrameStrata("DIALOG")   -- above the frames, cast bars and unlock boxes
  local y = -44
  win.master = UI:Check(win, "Use Command Center unit frames", false, function(v)
    local d = store()
    local was = d.on
    d.on = v and true or false
    if v then S.UFApply()
    else
      S.UFSetUnlocked(false); if testing then S.UFSetTesting(false) end
      S.UFApply()
      if was then S.UFAskReload("The game's own frames come back after a reload.") end
    end
    S:RefreshUnitFrames()
  end, "Player, target, target of target, focus, pet, party, raid and boss frames in Command Center's style. The game's frames are hidden for the ones you use.")
  win.master:SetPoint("TOPLEFT", 16, y)
  win.unlock = UI:PrimaryButton(win, "Unlock frames", 120, 24, function() S.UFSetUnlocked(not unlocked) end,
    "Shows a box on every frame: drag to move, right-click for its settings. Locks again when a fight starts.")
  win.unlock:SetPoint("TOPRIGHT", -16, y + 3)
  win.test = UI:Button(win, "Test mode", 100, 24, function() S.UFSetTesting(not testing) end,
    "Fills every frame with made-up players (party, raid, bosses, cast bars, auras) so you can see your changes.")
  win.test:SetPoint("RIGHT", win.unlock, "LEFT", -6, 0)
  y = y - 30
  win.info = UI:Text(win, "", "small"); win.info:SetPoint("TOPLEFT", 16, y + 6)
  y = y - 14
  local fl = UI:Text(win, "Frame", "small"); fl:SetPoint("TOPLEFT", 16, y - 5)
  local uopts = {}
  for _, k in ipairs(KEYS) do uopts[#uopts + 1] = { value = k, text = LABEL[k] } end
  win.unitDrop = UI:Dropdown(win, 160, uopts, cur, function(v) cur = v; S:RefreshUnitFrames() end)
  win.unitDrop:SetPoint("TOPLEFT", 60, y)
  win.enabled = UI:Check(win, "Show this frame", true, function(v) setv("on", v); if unlocked then S.UFSetUnlocked(true) end end)
  win.enabled:SetPoint("LEFT", win.unitDrop, "RIGHT", 14, 0)
  win.replace = UI:Check(win, "Hide the game's frame", true, function(v)
    setv("replace", v)
    if not v then S.UFAskReload("The game's frame comes back after a reload.") end
  end, "Hides the game's own frame for this one (and the game's cast bar for your own when its cast bar is on).")
  win.replace:SetPoint("LEFT", win.enabled, "RIGHT", 120, 0)
  local copy = UI:Button(win, "Copy from...", 96, 22, function(self)
    local items = { { text = "Copy the look of...", title = true } }
    for _, k in ipairs(KEYS) do
      if k ~= cur then
        items[#items + 1] = { text = LABEL[k], func = function()
          local src, dst = cfg(k), cfg(cur)
          for _, f in ipairs({ "portrait", "healthColor", "healthText", "powerText", "nameColor", "auraSize", "auraTimer", "castIcon", "castRank", "castTex", "castColor", "castFill", "castDir", "castTime", "castName", "castEnd", "castSpark", "castDec", "castFail", "nameAt", "nameBoxAt", "nameBoxW", "nameBoxFit", "nameFull", "round", "pvpAt", "levelAt", "levelSide", "levelSize", "buffPos", "debuffPos", "eliteIcon", "eliteBorder", "eliteSize", "eliteArt", "eliteAt", "eliteNormal", "eliteRim", "eliteX", "eliteY" }) do dst[f] = src[f] end
          dst.fonts = {}; for e, v in pairs(src.fonts or {}) do dst.fonts[e] = { face = v.face, size = v.size } end
          dst.hl = S.Copy(src.hl); dst.col = S.Copy(src.col or {}); dst.roundBars = S.Copy(src.roundBars or {})
          dst.anim, dst.animCol, dst.animStr = S.Copy(src.anim or {}), S.Copy(src.animCol or {}), S.Copy(src.animStr or {})
          dst.frameAnim, dst.frameAnimCol, dst.frameAnimStr = src.frameAnim, S.Copy(src.frameAnimCol or {}), src.frameAnimStr
          S.UFApply(cur); S:RefreshUnitFrames()
        end }
      end
    end
    UI:Menu(self, items)
  end, "Copies colours, text formats, portrait and aura look from another frame (not size or position).")
  copy:SetPoint("TOPRIGHT", -16, y + 1)
  local prof = UI:Button(win, "Profiles...", 90, 22, function() S.UFProfiles() end,
    "Save the whole unit frame setup under a name (shared by all your characters), switch between setups, or export / import them as text for another account.")
  prof:SetPoint("RIGHT", copy, "LEFT", -6, 0)
  y = y - 34

  local panes = {}
  local names = { "Size", "Bars & text", "Portrait", "Auras", "Cast bar", "Extras", "Style", "Totems", "Colours", "Effects", "Reactions" }
  local tabs             -- r136: the page navigator, made at the end (the old tab strip is gone)
  y = y - 36
  for i = 1, #names do
    local p = CreateFrame("Frame", nil, win)
    p:SetPoint("TOPLEFT", 16, y); p:SetPoint("BOTTOMRIGHT", -16, 50)
    p:Hide(); panes[i] = p
  end
  local SW = 720

  -- 1 Size
  local p = panes[1]
  slider(p, 0, 0, SW, "Width", "w", 40, 400, 2)
  slider(p, 0, -30, SW, "Height", "h", 16, 120, 1)
  slider(p, 0, -60, SW, "Power bar height", "powerH", 0, 30, 1, function(v) return v == 0 and "Off" or v end)
  slider(p, 0, -90, SW, "Scale", "scale", 50, 200, 5, function(v) return v .. "%" end, nil, 100)
  slider(p, 0, -120, SW, "Spacing", "spacing", 0, 60, 1, nil, "spacing")
  dropdown(p, 0, -156, "Grow", "growth", { { value = "down", text = "Downwards" }, { value = "right", text = "To the right" } }, 150, "growth")
  dropdown(p, 0, -156, "Groups as", "groupsAs", { { value = "columns", text = "Columns (side by side)" }, { value = "rows", text = "Rows (stacked)" } }, 190, "groupsAs")
  check(p, 0, -192, "Show me in the party frames", "showPlayer", nil, "showPlayer")
  check(p, 260, -192, "Hide party frames in a raid", "hideInRaid", "When raid frames are on.", "hideInRaid")
  local pos = UI:Button(p, "Reset position", 120, 22, function()
    local c = C(); local dflt = DEF[cur] or {}
    c.x, c.y = dflt.x or 0, dflt.y or 0
    c.castX, c.castY = nil, nil
    S.UFApply(cur)
  end)
  pos:SetPoint("TOPLEFT", 0, -232)
  local rs = UI:Button(p, "|cffff7777Reset this frame|r", 130, 22, function()
    UI:Confirm("Put every setting of the " .. LABEL[cur] .. " frame back to the default?", function()
      store().units[cur] = nil; cfgCache[cur] = nil
      S.UFApply(cur); S:RefreshUnitFrames()
    end, "Reset")
  end)
  rs:SetPoint("LEFT", pos, "RIGHT", 8, 0)
  local RNAMES = { "Square", "Slight", "Rounded", "More", "Very round", "Round" }
  local function rOpts(first)
    local o = { { value = -1, text = first } }
    for i = 0, 5 do o[#o + 1] = { value = i, text = RNAMES[i + 1] } end
    return o
  end
  local rh = UI:Header(p, "Roundness (this frame)"); rh:SetPoint("TOPLEFT", 0, -270)
  dropdown(p, 0, -296, "Frame", "round", rOpts("Same as Look and theme"), 170)
  dropdown(p, 390, -296, "Health bar", "roundBars.health", rOpts("Match the frame"), 170)
  dropdown(p, 0, -328, "Power bar", "roundBars.power", rOpts("Match the frame"), 170)
  dropdown(p, 390, -328, "Cast bar", "roundBars.cast", rOpts("Match the frame"), 170, "castbar")

  -- 2 Bars & text
  p = panes[2]
  local HC = { { value = "class", text = "Class / reaction" }, { value = "reaction", text = "Reaction only" }, { value = "gradient", text = "Green to red" },
    { value = "dark", text = "Dark (class behind)" }, { value = "green", text = "Always green" } }
  dropdown(p, 0, 0, "Health colour", "healthColor", HC, 180)
  local TF = { { value = "curmax", text = "4.2k / 5.0k" }, { value = "both", text = "4.2k  84%" }, { value = "percent", text = "84%" },
    { value = "cur", text = "4.2k" }, { value = "deficit", text = "-800 (missing)" }, { value = "none", text = "None" } }
  dropdown(p, 0, -32, "Health text", "healthText", TF, 180)
  dropdown(p, 0, -64, "Power text", "powerText", TF, 180)
  dropdown(p, 0, -96, "Name", "nameAt", { { value = "left", text = "Left" }, { value = "center", text = "Centre (raid style)" }, { value = "box", text = "Box on top of the frame" } }, 180)
  win.nbAt = dropdown(p, 320, -96, "Box", "nameBoxAt", { { value = "left", text = "Left" }, { value = "center", text = "Middle" }, { value = "right", text = "Right" } }, 100)
  win.nbAt.lbl:ClearAllPoints(); win.nbAt.lbl:SetPoint("TOPLEFT", 320, -101); win.nbAt:ClearAllPoints(); win.nbAt:SetPoint("TOPLEFT", 350, -96)
  slider(p, 320, -128, 280, "Box width", "nameBoxW", 20, 100, 5, function(v) return v .. "%" end, nil, 100)
  check(p, 470, -96, "Fit the box to the name", "nameBoxFit", "The name box grows with the name, up to the frame's full width (never wider). Off: the Box width above is used.")
  dropdown(p, 0, -128, "Name colour", "nameColor", { { value = "class", text = "Class colour" }, { value = "white", text = "White" }, { value = "theme", text = "Theme accent" } }, 180)
  check(p, 0, -164, "Show the name", "name")
  check(p, 200, -164, "Level (elite / rare marks)", "level")
  dropdown(p, 0, -248, "Level", "levelAt", { { value = "name", text = "Before the name" }, { value = "bar", text = "In the bar" },
    { value = "namebox", text = "In the name box" }, { value = "beside", text = "Box beside the frame" },
    { value = "above", text = "Box on top (on the name box)" }, { value = "under", text = "Box under the frame" } }, 180)
  win.lvSide = dropdown(p, 320, -248, "Side", "levelSide", { { value = "left", text = "Left" }, { value = "right", text = "Right" } }, 100)
  win.lvSide.lbl:ClearAllPoints(); win.lvSide.lbl:SetPoint("TOPLEFT", 320, -253); win.lvSide:ClearAllPoints(); win.lvSide:SetPoint("TOPLEFT", 350, -248)
  slider(p, 0, -282, SW, "Level text size", "levelSize", 0, 24, 1, function(v) return v == 0 and "Same as name" or v end)
  check(p, 0, -190, "Incoming heals", "healPred", "Green overlay for heals on the way (when the game shares them).")
  check(p, 200, -190, "Absorb shields", "absorb")
  check(p, 0, -216, "Tooltip on mouse-over", "tooltip")
  check(p, 200, -216, "Both names (main + secondary)", "nameFull", "WoW Forever characters have two names. On: \"Baelgor Stormhide\". Off: just the main name.")

  -- 3 Portrait
  p = panes[3]
  dropdown(p, 0, 0, "Portrait", "portrait", { { value = "3d", text = "3D model" }, { value = "2d", text = "2D picture" }, { value = "class", text = "Class icon" }, { value = "none", text = "None" } }, 160)
  dropdown(p, 0, -32, "Side", "side", { { value = "left", text = "Left" }, { value = "right", text = "Right" } }, 160)
  check(p, 320, -32, "Faction icon", "ind.pvp", "The Horde / Alliance badge (shown when PvP-flagged). Turn off to remove it. Same as Extras > Icons > Faction / PvP.")
  dropdown(p, 0, -64, "Faction icon at", "pvpAt", { { value = "corner", text = "Frame corner" }, { value = "namebox", text = "After the name" } }, 160)
  check(p, 0, -96, "Elite / rare glow", "eliteBorder", "A glowing edge round the frame - only while the unit is an elite (gold) or a rare (silver).")
  local ph = UI:Text(p, "|cffaaaaaaThe portrait is a square as tall as the frame. Class icon shows the class for players and the picture for NPCs.|r", "small")
  ph:SetPoint("TOPLEFT", 0, -130); ph:SetWidth(SW); ph:SetJustifyH("LEFT")
  local ph2 = UI:Text(p, "|cffaaaaaa'After the name' puts the badge right where the name ends - in the name box when Name is Box on top, otherwise on the bar. Each frame has its own setting: pick the frame on the left first.|r", "small")
  ph2:SetPoint("TOPLEFT", 0, -154); ph2:SetWidth(SW); ph2:SetJustifyH("LEFT")

  -- 4 Auras
  p = panes[4]
  check(p, 0, 0, "Buffs", "buffs")
  check(p, 120, 0, "Debuffs", "debuffs")
  check(p, 240, 0, "Only mine", "auraMine", "Buffs: only the ones you cast (your HoTs on raid frames). Debuffs on enemies: only yours.")

  local POS = { { value = "below", text = "Below" }, { value = "above", text = "Above" }, { value = "right", text = "Right" },
    { value = "left", text = "Left" }, { value = "inside", text = "Inside (raid style)" } }
  dropdown(p, 0, -32, "Buffs at", "buffPos", POS, 170)
  dropdown(p, 0, -64, "Debuffs at", "debuffPos", POS, 170)
  dropdown(p, 0, -96, "Timer", "auraTimer", { { value = "on", text = "On the icon (top)" }, { value = "under", text = "Under the icon" },
    { value = "off", text = "Off" } }, 170)
  slider(p, 0, -132, SW, "Icon size", "auraSize", 10, 40, 1)
  slider(p, 0, -162, SW, "How many (each)", "auraMax", 1, 16, 1)
  local testB = UI:Button(p, "Show in test mode", 140, 22, function() if not testing then S.UFSetTesting(true) end end,
    "Fills every frame with made-up buffs, debuffs and cast bars so you can see where they go.")
  testB:SetPoint("TOPLEFT", 300, -32)
  local ah = UI:Text(p, "|cffaaaaaaWhen buffs and debuffs share a side, debuffs sit nearest the frame. Debuff borders show the debuff type (magic, curse, poison, disease). Hover an icon for its tooltip.|r", "small")
  ah:SetPoint("TOPLEFT", 0, -196); ah:SetWidth(SW); ah:SetJustifyH("LEFT")
  -- in combat (all frames): Blizzard's Cooldown Manager icons
  local ch2 = UI:Header(p, "In combat"); ch2:SetPoint("TOPLEFT", 0, -232)
  win.cdmOn = UI:Check(p, "Show the Cooldown Manager's icons on my frames (my buffs and DoTs)", true, function(v)
    store().cdm.on = v; if not combat() then pcall(CDM.give) end
  end, "WoW Forever hides auras from addons during a fight. Blizzard's Cooldown Manager still draws your tracked buffs and DoTs, so they're moved onto your player frame (buffs on you) and target frame (your DoTs) while you fight. Everything else shows what was there when the fight started, plus your own casts.")
  win.cdmOn:SetPoint("TOPLEFT", 0, -258)
  win.cdmHide = UI:Check(p, "Hide the Cooldown Manager's own buff bar out of combat", true, function(v)
    store().cdm.hideBar = v; if not combat() then pcall(CDM.give) end
  end, "Out of combat your frames show every aura themselves, so Blizzard's Tracked Buffs bar would only repeat them.")
  win.cdmHide:SetPoint("TOPLEFT", 0, -284)
  win.npOn = UI:Check(p, "Copy my debuffs from the enemy's nameplate (nameplates must be on)", true, function(v)
    store().cdm.nameplates = v
  end, "Blizzard's nameplates still show your debuffs in a fight. Their icon, timer and stacks are copied onto the target / focus frame. Turn nameplates on with V (or in the game's Interface options).")
  win.npOn:SetPoint("TOPLEFT", 0, -310)
  local setupB = UI:Button(p, "Set up Cooldown Manager...", 190, 22, function()
    if combat() then S:Print("After the fight.") return end
    if C_CVar and C_CVar.GetCVarBool and C_CVar.GetCVarBool("cooldownViewerEnabled") == false and C_CVar.SetCVar then
      pcall(C_CVar.SetCVar, "cooldownViewerEnabled", "1"); S:Print("Cooldown Manager turned on.")
    end
    local sf = _G.CooldownViewerSettings
    local shown = false
    if sf then
      if sf.TogglePanel then shown = pcall(sf.TogglePanel, sf) end
      if not shown and ShowUIPanel then shown = pcall(ShowUIPanel, sf) end
      if not shown then shown = pcall(sf.Show, sf) end
    end
    if not shown then
      UI:Alert("Open Edit Mode (Esc > Edit Mode), click the Cooldown Manager and choose its advanced options / settings. Drag the buffs and DoTs you want (Lightning Shield, Flame Shock...) into Tracked Buffs.")
    end
  end, "Turns Blizzard's Cooldown Manager on and opens its settings: put your buffs and DoTs (Lightning Shield, Flame Shock...) into Tracked Buffs.")
  setupB:SetPoint("TOPLEFT", 0, -338)
  win.cdmStatus = UI:Text(p, "", "small"); win.cdmStatus:SetPoint("LEFT", setupB, "RIGHT", 10, 0); win.cdmStatus:SetWidth(SW - 200); win.cdmStatus:SetJustifyH("LEFT")

  -- 5 Cast bar
  p = panes[5]
  check(p, 0, 0, "Cast bar", "castbar", "Under the frame. Grey with a shield = can't be interrupted. Your own shows your latency in red at the end.", "castbar")
  check(p, 160, 0, "Spell icon", "castIcon", nil, "castbar")
  dropdown(p, 300, 0, "Spell rank", "castRank", { { value = "full", text = "Fireball (Rank 7)" }, { value = "short", text = "Fireball  R7" }, { value = "off", text = "Off" } }, 150, "castbar")
  slider(p, 0, -34, SW, "Height", "castH", 8, 36, 1, nil, "castbar")
  dropdown(p, 0, -68, "Position", "castPos", function()
    local o = { { value = "below", text = "Under the frame" }, { value = "above", text = "Above the frame" } }
    if CAST_FREE[cur] then o[3] = { value = "free", text = "Free - drag it anywhere" } end
    return o
  end, 200, "castbar")
  slider(p, 0, -102, SW, "Width (free)", "castW", 0, 500, 5, function(v) return v == 0 and "Frame" or v end, "castW")
  local moveB = UI:PrimaryButton(p, "Move it", 90, 22, function()
    if C().castPos ~= "free" then setv("castPos", "free") end
    if not unlocked then S.UFSetUnlocked(true) end
  end, "Sets the position to Free and unlocks the frames: drag the box called \"" .. "cast bar\" (it snaps to the middle of the screen). Lock frames when you're done.")
  moveB:SetPoint("TOPLEFT", 330, -68)
  win.castMove = moveB
  local lh = UI:Header(p, "Look"); lh:SetPoint("TOPLEFT", 0, -134)
  dropdown(p, 0, -160, "Texture", "castTex", function()
    local o = { { value = "", text = "Same as the frames" } }
    for _, t in ipairs(textureOptions()) do o[#o + 1] = t end
    return o
  end, 170, "castbar")
  dropdown(p, 310, -160, "Colour", "castColor", { { value = "theme", text = "Theme" }, { value = "class", text = "Class colour" }, { value = "white", text = "White" } }, 170, "castbar")
  dropdown(p, 0, -192, "Progress", "castFill", { { value = "fill", text = "Fills up" }, { value = "drain", text = "Empties (reverse)" } }, 170, "castbar")
  dropdown(p, 310, -192, "Direction", "castDir", { { value = "ltr", text = "Left to right" }, { value = "rtl", text = "Right to left" } }, 170, "castbar")
  dropdown(p, 0, -224, "Timer", "castTime", { { value = "left", text = "Time left  1.4" }, { value = "leftmax", text = "Left / total  1.4 / 2.5" },
    { value = "elapsed", text = "Time cast  1.1" }, { value = "pct", text = "Percent  44%" }, { value = "off", text = "Off" } }, 170, "castbar")
  dropdown(p, 310, -224, "Spell name", "castName", { { value = "left", text = "At the start" }, { value = "center", text = "In the middle" }, { value = "off", text = "Off" } }, 170, "castbar")
  dropdown(p, 0, -256, "When it ends", "castEnd", { { value = "fade", text = "Fade out" }, { value = "flash", text = "Flash, then fade" }, { value = "none", text = "Vanish" } }, 170, "castbar")
  check(p, 0, -290, "Spark", "castSpark", "The bright line at the edge of the moving bar.", "castbar")
  check(p, 140, -290, "Tenths of a second", "castDec", nil, "castbar")
  check(p, 320, -290, "Show \"Interrupted\"", "castFail", "Interrupted casts turn red and say so for a moment.", "castbar")
  local ch = UI:Text(p, "|cffaaaaaaCast bars: player, target, focus, pet, party and bosses. Turning on your own hides the game's cast bar. Free position: player, target, focus and pet; width 'Frame' = as wide as the frame. Test mode shows the look. When the game hides an enemy's cast timing the bar still runs, but without timer text.|r", "small")
  ch:SetPoint("TOPLEFT", 0, -322); ch:SetWidth(SW); ch:SetJustifyH("LEFT")

  -- 6 Extras
  p = panes[6]
  local hh = UI:Header(p, "Highlight the frame"); hh:SetPoint("TOPLEFT", 0, 0)
  check(p, 0, -26, "When it's my target", "hl.target")
  check(p, 180, -26, "Mouse-over", "hl.mouse")
  check(p, 0, -52, "Has aggro", "hl.aggro")
  check(p, 180, -52, "Debuff I can remove", "hl.dispel")
  local ih = UI:Header(p, "Icons"); ih:SetPoint("TOPLEFT", 0, -84)
  check(p, 0, -110, "Leader", "ind.leader")
  check(p, 120, -110, "Raid mark", "ind.mark")
  check(p, 240, -110, "Role", "ind.role")
  check(p, 360, -110, "Ready check", "ind.ready")
  check(p, 0, -136, "In combat", "ind.combat")
  check(p, 120, -136, "Resting", "ind.rest")
  check(p, 240, -136, "Faction / PvP", "ind.pvp", "The Horde / Alliance badge on the frame's corner (shown when the unit is flagged for PvP).")
  local xh = UI:Header(p, "More"); xh:SetPoint("TOPLEFT", 0, -168)
  check(p, 0, -194, "Fade when out of range", "range", nil, "range")
  slider(p, 0, -220, SW, "Out of range opacity", "rangeAlpha", 10, 90, 5, function(v) return v .. "%" end, "rangeAlpha", 100)
  check(p, 0, -194, "Fade when idle (out of combat, full, no target)", "fade", nil, "fade")
  slider(p, 0, -220, SW, "Idle opacity", "fadeAlpha", 10, 90, 5, function(v) return v .. "%" end, "fade", 100)
  check(p, 0, -250, "Combo points (rogues, cat druids)", "combo", nil, "combo")
  check(p, 0, -250, "Energy ticks and the five-second rule", "ticks", "A spark on your power bar: when the next energy tick lands, or how long until mana regen starts again after a cast.", "ticks")
  check(p, 0, -276, "Druid mana while shapeshifted", "druidMana", nil, "druidMana")
  check(p, 300, -276, "Keep the game's totem bar", "totems", "Only used when Command Center's own totem bar (Totem bar page) is off: moves the game's totem timers under your frame.", "totems")

  -- 8 Totems (one bar for all; not per frame)
  p = panes[8]
  local T = S.UFTot
  local function tset(k, v) T.cfg()[k] = v; T.place(); T.layout(); if unlocked then T.unlock(true) end end
  local tn = UI:Text(p, "Your totems in their own box. Unlock frames to drag it; right-click a totem to dismiss it. These settings are for the bar, whichever frame is picked above.", "small")
  tn:SetPoint("TOPLEFT", 0, 0); tn:SetPoint("RIGHT", p, "RIGHT", 0, 0); tn:SetJustifyH("LEFT")
  win.tOn = UI:Check(p, "Show the totem bar", true, function(v)
    tset("on", v)
    if not v then S.UFAskReload("The game's own totem timers come back after a reload.") end
  end, "Replaces the game's totem timers.")
  win.tOn:SetPoint("TOPLEFT", 0, -30)
  win.tSize = UI:Slider(p, SW, "Icon size", 16, 64, 1, 30, function(v) tset("size", v) end); win.tSize:SetPoint("TOPLEFT", 0, -60)
  win.tPer = UI:Slider(p, SW, "Per row", 1, 4, 1, 4, function(v) tset("perRow", v) end); win.tPer:SetPoint("TOPLEFT", 0, -90)
  win.tSp = UI:Slider(p, SW, "Spacing", 0, 20, 1, 4, function(v) tset("spacing", v) end); win.tSp:SetPoint("TOPLEFT", 0, -120)
  win.tScale = UI:Slider(p, SW, "Scale", 50, 200, 5, 100, function(v) tset("scale", v / 100) end, function(v) return v .. "%" end); win.tScale:SetPoint("TOPLEFT", 0, -150)
  local function tdrop(x, y, label, key, opts, w)
    local l = UI:Text(p, label, "small"); l:SetPoint("TOPLEFT", x, y - 5)
    local d = UI:Dropdown(p, w or 150, opts, nil, function(v) tset(key, v) end); d:SetPoint("TOPLEFT", x + 90, y)
    return d
  end
  win.tGrow = tdrop(0, -186, "Grows", "grow", { { value = "right", text = "To the right" }, { value = "left", text = "To the left" }, { value = "down", text = "Down" }, { value = "up", text = "Up" } })
  win.tRow = tdrop(300, -186, "New rows", "rowGrow", { { value = "down", text = "Below / to the right" }, { value = "up", text = "Above / to the left" } }, 170)
  win.tOrder = tdrop(0, -218, "Order", "order", { { value = "efwa", text = "Earth Fire Water Air" }, { value = "slot", text = "Fire Earth Water Air" }, { value = "eafw", text = "Earth Air Fire Water" }, { value = "wfea", text = "Water Fire Earth Air" } })
  win.tEmpty = tdrop(300, -218, "Empty slot", "empty", { { value = "hide", text = "Hidden" }, { value = "dim", text = "Faded" }, { value = "show", text = "Shown" } }, 170)
  win.tTimer = tdrop(0, -250, "Timer", "timer", { { value = "on", text = "On the icon" }, { value = "under", text = "Under the icon" }, { value = "off", text = "Off" } })
  win.tEdge = tdrop(300, -250, "Edge colour", "edge", { { value = "element", text = "Element colours" }, { value = "theme", text = "Theme" }, { value = "black", text = "Black" } }, 170)
  win.tSwipe = UI:Check(p, "Dark sweep as it runs out", true, function(v) tset("swipe", v) end); win.tSwipe:SetPoint("TOPLEFT", 0, -284)
  win.tTip = UI:Check(p, "Tooltip on mouse-over", true, function(v) tset("tooltip", v) end); win.tTip:SetPoint("TOPLEFT", 220, -284)
  win.tDis = UI:Check(p, "Right-click dismisses", true, function(v) tset("dismiss", v) end); win.tDis:SetPoint("TOPLEFT", 420, -284)
  local tnote = UI:Text(p, "Roundness, border and font follow Look and theme. Changes made during a fight apply when it ends.", "small")
  tnote:SetPoint("TOPLEFT", 0, -316); tnote:SetTextColor(0.6, 0.6, 0.6)

  -- colour picker (the game's own) + swatch buttons
  local function pickColor(r, g, b, onChange)
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
  local function swatch(parent, x, y, label, get, set, tip)
    local b = CreateFrame("Button", nil, parent, BACKDROP_T)
    plainBackdrop(b); b:SetSize(20, 20); b:SetPoint("TOPLEFT", x, y)
    b:SetBackdropColor(0, 0, 0, 1); b:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    b.fill = b:CreateTexture(nil, "ARTWORK"); b.fill:SetPoint("TOPLEFT", 2, -2); b.fill:SetPoint("BOTTOMRIGHT", -2, 2); b.fill:SetTexture(WHITE)
    b.none = b:CreateTexture(nil, "OVERLAY"); b.none:SetAllPoints(b.fill); b.none:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up"); b.none:SetAlpha(0.5)
    b.label = UI:Text(parent, label, "small"); b.label:SetPoint("LEFT", b, "RIGHT", 6, 0)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    function b:Refresh()
      local col = get()
      if col then self.fill:SetVertexColor(col[1], col[2], col[3]); self.fill:Show(); self.none:Hide()
      else self.fill:SetVertexColor(0.25, 0.25, 0.25); self.none:Show() end
    end
    b:SetScript("OnClick", function(self, btn)
      if btn == "RightButton" then set(nil); self:Refresh() return end
      local col = get() or { 1, 1, 1 }
      pickColor(col[1], col[2], col[3], function(r, g, bl) set({ r, g, bl }); self:Refresh() end)
    end)
    b:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine(label, 1, 1, 1)
      if tip then GameTooltip:AddLine(tip, 0.8, 0.8, 0.8, true) end
      GameTooltip:AddLine("Left-click: pick a colour   Right-click: back to normal", 0.6, 0.6, 0.6, true); GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
  end

  -- 9 Colours (this frame)
  p = panes[9]
  win.swatches = {}
  local cn = UI:Text(p, "Pick your own colour for any part of this frame. Crossed out = the normal colour (class, power type, theme...). Right-click a swatch to go back to normal.", "small")
  cn:SetPoint("TOPLEFT", 0, 0); cn:SetPoint("RIGHT", p, "RIGHT", 0, 0); cn:SetJustifyH("LEFT")
  for i, key in ipairs(S.UFCol.KEYS) do
    local col, row = (i - 1) % 2, floor((i - 1) / 2)
    win.swatches[#win.swatches + 1] = swatch(p, col * 340, -34 - row * 28, S.UFCol.LABEL[key],
      function() local t = C().col and C().col[key]; return type(t) == "table" and t or nil end,
      function(v) local c2 = C(); c2.col = c2.col or {}; c2.col[key] = v; S.UFApply(cur) end,
      key == "cast" and "Only for casts you can interrupt - the grey 'can't interrupt' colour stays." or nil)
  end
  local cy = -34 - 7 * 28 - 8
  local resetC = UI:Button(p, "Reset this frame's colours", 180, 22, function()
    C().col = {}; S.UFApply(cur); S:RefreshUnitFrames()
  end)
  resetC:SetPoint("TOPLEFT", 0, cy)
  local allC = UI:Button(p, "Use these colours on every frame", 220, 22, function()
    local src = C().col or {}
    for _, k in ipairs(KEYS) do if k ~= cur then cfg(k).col = S.Copy(src) end end
    S.UFApply(); S:RefreshUnitFrames()
  end)
  allC:SetPoint("LEFT", resetC, "RIGHT", 10, 0)
  local mh = UI:Header(p, "Your own name"); mh:SetPoint("TOPLEFT", 0, cy - 36)
  win.myOn = UI:Check(p, "Give my name its own colour on every frame (party, raid, target of target...)", false, function(v) style().myNameOn = v; S.UFApply() end)
  win.myOn:SetPoint("TOPLEFT", 0, cy - 62)
  win.mySw = swatch(p, 0, cy - 92, "My name's colour", function() return style().myName end,
    function(v) style().myName = v or { 1, 0.82, 0.2 }; style().myNameOn = true; S.UFApply(); S:RefreshUnitFrames() end)

  -- 10 Effects (all frames): bar textures, animations, a font for each part
  p = panes[10]
  local function eset(k, v) style()[k] = v; S.UFApply() end
  local function texOpts()
    local o = { { value = "", text = "Same as Look and theme" } }
    for _, t in ipairs(textureOptions()) do o[#o + 1] = t end
    return o
  end
  local eh = UI:Header(p, "Bar textures (CC ones are new)"); eh:SetPoint("TOPLEFT", 0, 0)
  local l1 = UI:Text(p, "Health", "small"); l1:SetPoint("TOPLEFT", 0, -31)
  win.eTexH = UI:Dropdown(p, 170, texOpts, "", function(v) eset("texHealth", v) end); win.eTexH:SetPoint("TOPLEFT", 80, -26)
  local l2 = UI:Text(p, "Power", "small"); l2:SetPoint("TOPLEFT", 350, -31)
  win.eTexP = UI:Dropdown(p, 170, texOpts, "", function(v) eset("texPower", v) end); win.eTexP:SetPoint("TOPLEFT", 430, -26)
  local ah = UI:Header(p, "Animations (for the frame picked on the left)"); ah:SetPoint("TOPLEFT", 0, -64)
  local function aset(k, v) local c = C(); c.anim = c.anim or {}; c.anim[k] = v; S.UFApply(cur) end
  local la1 = UI:Text(p, "Health bar", "small"); la1:SetPoint("TOPLEFT", 0, -95)
  win.eAnH = UI:Dropdown(p, 170, S.UFAnim.LIST, "none", function(v) aset("health", v) end); win.eAnH:SetPoint("TOPLEFT", 80, -90)
  local la2 = UI:Text(p, "Power bar", "small"); la2:SetPoint("TOPLEFT", 350, -95)
  win.eAnP = UI:Dropdown(p, 170, S.UFAnim.LIST, "none", function(v) aset("power", v) end); win.eAnP:SetPoint("TOPLEFT", 430, -90)
  local la3 = UI:Text(p, "Cast bar", "small"); la3:SetPoint("TOPLEFT", 0, -127)
  win.eAnC = UI:Dropdown(p, 170, S.UFAnim.LIST, "none", function(v) aset("cast", v) end); win.eAnC:SetPoint("TOPLEFT", 80, -122)
  win.eSpd = UI:Slider(p, 330, "Speed", 25, 300, 25, 100, function(v) style().animSpeed = v / 100 end, function(v) return v .. "%" end)
  win.eSpd:SetPoint("TOPLEFT", 350, -120)
  -- a colour for every animation (crossed out = its own colours)
  local function acol(key)
    return function() local t = (C().animCol or {})[key]; return type(t) == "table" and t or nil end,
      function(v) local c = C(); c.animCol = c.animCol or {}; c.animCol[key] = v; S.UFApply(cur) end
  end
  win.eCols = {}
  local g1, s1 = acol("health"); win.eCols[1] = swatch(p, 256, -91, "", g1, s1, "Health bar animation colour")
  local g2, s2 = acol("power"); win.eCols[2] = swatch(p, 606, -91, "", g2, s2, "Power bar animation colour")
  local g3, s3 = acol("cast"); win.eCols[3] = swatch(p, 256, -123, "", g3, s3, "Cast bar animation colour")
  local la4 = UI:Text(p, "Frame", "small"); la4:SetPoint("TOPLEFT", 0, -159)
  win.eFA = UI:Dropdown(p, 170, S.UFAnim.FRAME, "none", function(v) C().frameAnim = v; S.UFApply(cur) end); win.eFA:SetPoint("TOPLEFT", 80, -154)
  win.eCols[4] = swatch(p, 256, -155, "", function() return C().frameAnimCol end,
    function(v) C().frameAnimCol = v or { 1, 0.82, 0.3 }; S.UFApply(cur) end, "Frame animation colour (Rainbow border uses all colours)")
  local allA = UI:Button(p, "Use these animations on every frame", 250, 22, function()
    local src = C()
    for _, k in ipairs(KEYS) do
      if k ~= cur then
        local d2 = cfg(k)
        d2.anim, d2.animCol, d2.animStr = S.Copy(src.anim or {}), S.Copy(src.animCol or {}), S.Copy(src.animStr or {})
        d2.frameAnim, d2.frameAnimCol, d2.frameAnimStr = src.frameAnim, S.Copy(src.frameAnimCol or { 1, 0.82, 0.3 }), src.frameAnimStr
      end
    end
    S.UFApply(); S:RefreshUnitFrames()
  end, "Copies this frame's bar + frame animations, their colours and glow strength to every other frame.")
  allA:SetPoint("TOPLEFT", 350, -154)
  -- glow strength for each animation (x alpha; 100% = as made)
  local function strSlider(x, y, label, get, set)
    local sl = UI:Slider(p, 330, label, 10, 200, 10, 100, function(v) set(v / 100) end, function(v) return v .. "%" end)
    sl:SetPoint("TOPLEFT", x, y); sl.ccGet = get
    return sl
  end
  local function astr(key) return function() return (C().animStr or {})[key] or 1 end,
    function(v) local c = C(); c.animStr = c.animStr or {}; c.animStr[key] = v; S.UFApply(cur) end end
  win.eStr = {}
  local sth = UI:Header(p, "Glow strength"); sth:SetPoint("TOPLEFT", 0, -190)
  local gh, sh = astr("health"); win.eStr[1] = strSlider(0, -216, "Health bar", gh, sh)
  local gp, sp = astr("power"); win.eStr[2] = strSlider(400, -216, "Power bar", gp, sp)
  local gc, sc2 = astr("cast"); win.eStr[3] = strSlider(0, -248, "Cast bar", gc, sc2)
  win.eStr[4] = strSlider(400, -248, "Frame", function() return C().frameAnimStr or 1 end, function(v) C().frameAnimStr = v end)
  local en = UI:Text(p, "|cffaaaaaaTextures and speed are for all frames; animations, their colours and glow strength are for the frame picked on the left. The cast bar's texture is per frame (Cast bar tab). Fonts are on Look and theme.|r", "small")
  en:SetPoint("TOPLEFT", 0, -290); en:SetWidth(SW); en:SetJustifyH("LEFT")

  -- 11 Reactions (all frames)
  p = panes[11]
  local function rset(k, v) local st = style(); st.react = st.react or {}; st.react[k] = v; S.UFApply() end
  local rn = UI:Text(p, "Effects that play the moment something changes. Up / down needs numbers the game shows: on enemies whose health is hidden only the damage trail works.", "small")
  rn:SetPoint("TOPLEFT", 0, 0); rn:SetPoint("RIGHT", p, "RIGHT", 0, 0); rn:SetJustifyH("LEFT")
  local function rdrop(x, y, label, key, opts)
    local l = UI:Text(p, label, "small"); l:SetPoint("TOPLEFT", x, y - 5)
    local d = UI:Dropdown(p, 190, opts, nil, function(v) rset(key, v) end); d:SetPoint("TOPLEFT", x + 100, y)
    return d
  end
  local R = S.UFReact
  win.rCols = {}
  local function rcol(x, y, key, tip)
    win.rCols[#win.rCols + 1] = swatch(p, x + 296, y - 1, "", function()
      local t = ((style().react or {}).col or {})[key]; return type(t) == "table" and t or R.DEFCOL[key]
    end, function(v)
      local st = style(); st.react = st.react or {}; st.react.col = st.react.col or {}; st.react.col[key] = v; S.UFApply()
    end, tip)
  end
  local h1 = UI:Header(p, "Health"); h1:SetPoint("TOPLEFT", 0, -34)
  win.rHL = rdrop(0, -60, "Goes down", "hpLoss", R.HP_LOSS)
  win.rHG = rdrop(390, -60, "Goes up", "hpGain", R.GAIN)
  local h2 = UI:Header(p, "Power (mana, energy, rage)"); h2:SetPoint("TOPLEFT", 0, -98)
  win.rPL = rdrop(0, -124, "Goes down", "ppLoss", R.PP_LOSS)
  win.rPG = rdrop(390, -124, "Goes up", "ppGain", R.GAIN)
  local h3 = UI:Header(p, "Combo points (target frame)"); h3:SetPoint("TOPLEFT", 0, -162)
  win.rCG = rdrop(0, -188, "Gained", "comboGain", R.COMBO)
  win.rCS = rdrop(390, -188, "Spent", "comboSpend", R.SPEND)
  rcol(0, -60, "hpLoss", "Health down colour"); rcol(390, -60, "hpGain", "Health up colour")
  rcol(0, -124, "ppLoss", "Power down colour"); rcol(390, -124, "ppGain", "Power up colour")
  rcol(0, -188, "combo", "Combo point gained colour"); rcol(390, -188, "spend", "Combo points spent colour")
  rcol(-296, -326, "trail", "The damage trail's colour")
  local tl = UI:Text(p, "Damage trail colour", "small"); tl:SetPoint("TOPLEFT", 26, -330)
  win.rStr = UI:Slider(p, 330, "Glow strength", 10, 200, 10, 100, function(v) rset("strength", v / 100) end, function(v) return v .. "%" end)
  win.rStr:SetPoint("TOPLEFT", 390, -324)
  local h4 = UI:Header(p, "Where"); h4:SetPoint("TOPLEFT", 0, -226)
  win.rSc = rdrop(0, -252, "Show on", "scope", R.SCOPE)
  win.rMin = UI:Slider(p, 330, "Ignore changes under", 0, 20, 1, 0, function(v) rset("minPct", v) end, function(v) return v == 0 and "Off" or (v .. "%") end)
  win.rMin:SetPoint("TOPLEFT", 390, -250)
  local pv = UI:PrimaryButton(p, "Preview", 110, 24, function()
    if not testing then S.UFSetTesting(true) end
    S.UFReact.preview(single.player, single.target)
  end, "Turns on test mode and plays your choices on your frame (combo points on the target frame).")
  pv:SetPoint("TOPLEFT", 0, -292)
  local rn2 = UI:Text(p, "|cffaaaaaa'Ignore changes under' keeps small ticks (regen, HoTs) from flashing every second.|r", "small")
  rn2:SetPoint("LEFT", pv, "RIGHT", 12, 0); rn2:SetWidth(SW - 130); rn2:SetJustifyH("LEFT")

  -- 7 Style (all frames)
  p = panes[7]
  local function sset(k, v) style()[k] = v; S.UFApply() end
  local sl = UI:Text(p, "Bar texture", "small"); sl:SetPoint("TOPLEFT", 0, -5)
  win.sTex = UI:Dropdown(p, 180, textureOptions, "smooth", function(v) sset("texture", v) end); win.sTex:SetPoint("TOPLEFT", 110, 0)
  local fl = UI:Text(p, "Font", "small"); fl:SetPoint("TOPLEFT", 0, -37)
  win.sFace = UI:Dropdown(p, 180, function()
    local o = { { value = "cc", text = "Command Center's font" } }
    for _, n in ipairs(UI:FontList()) do o[#o + 1] = { value = n, text = n } end
    return o
  end, "cc", function(v) sset("face", v) end)
  win.sFace:SetPoint("TOPLEFT", 110, -32)
  local addF = UI:Button(p, "Add font file...", 120, 22, function()
    UI:Prompt("Put the font in  Interface\\AddOns\\CommandCenter\\Media\\Fonts  and type its file name here (e.g. Roboto-Bold.ttf).\n\nFiles called 1.ttf to 20.ttf are found on their own.", "", function(name)
      local ff, why = S.UFAddFontFile(name)
      if ff then
        style().face = ff.name; S.UFApply(); S:RefreshUnitFrames()
        S:Print("Font added: " .. ff.name .. " - it's in Command Center's font list too (Settings).")
      elseif why ~= "empty" then
        UI:Alert("Couldn't load \"" .. S.Trim(name) .. "\" from Media\\Fonts.\n\nCheck the spelling (with .ttf or .otf). WoW only sees files that were there when the game started - after adding a file, quit the game fully and start it again (a /reload isn't enough).")
      end
    end)
  end, "Your own fonts: drop .ttf / .otf files into CommandCenter\\Media\\Fonts, restart the game, then add them here once.")
  addF:SetPoint("LEFT", win.sFace, "RIGHT", 8, 0)
  win.sFont = UI:Slider(p, SW, "Text size", 7, 18, 1, 11, function(v) sset("font", v) end); win.sFont:SetPoint("TOPLEFT", 0, -66)
  local ol = UI:Text(p, "Text outline", "small"); ol:SetPoint("TOPLEFT", 0, -101)
  win.sOutline = UI:Dropdown(p, 180, { { value = "OUTLINE", text = "Outline" }, { value = "THICKOUTLINE", text = "Thick outline" }, { value = "NONE", text = "Shadow only" } },
    "OUTLINE", function(v) sset("outline", v) end)
  win.sOutline:SetPoint("TOPLEFT", 110, -96)
  win.sBg = UI:Slider(p, SW, "Background", 0, 100, 5, 85, function(v) sset("bgAlpha", v / 100) end, function(v) return v .. "%" end)
  win.sBg:SetPoint("TOPLEFT", 0, -130)
  local bl = UI:Text(p, "Border", "small"); bl:SetPoint("TOPLEFT", 0, -165)
  win.sBorder = UI:Dropdown(p, 180, { { value = "theme", text = "Theme edge" }, { value = "black", text = "Black" }, { value = "none", text = "No border" } },
    "theme", function(v) sset("border", v) end)
  win.sBorder:SetPoint("TOPLEFT", 110, -160)
  local RN = { [0] = "Square", "Slight", "Rounded", "More", "Very round", "Round" }
  win.sRound = UI:Slider(p, SW, "Roundness", 0, 5, 1, 0, function(v) sset("round", v) end, function(v) return RN[v] or v end)
  win.sRound:SetPoint("TOPLEFT", 0, -194)
  local nl = UI:Text(p, "Numbers", "small"); nl:SetPoint("TOPLEFT", 0, -229)
  win.sNum = UI:Dropdown(p, 180, { { value = "short", text = "Short (4.2k)" }, { value = "full", text = "Full (4,200)" } }, "short", function(v) sset("numbers", v) end)
  win.sNum:SetPoint("TOPLEFT", 110, -224)
  local thl = UI:Text(p, "Theme", "small"); thl:SetPoint("TOPLEFT", 420, -5)
  win.sTheme = UI:Dropdown(p, 170, { { value = "standard", text = "Standard" }, { value = "artistic", text = "Artistic" } }, "standard",
    function(v) sset("theme", v) end, "Artistic: ornate frame art by creature type / class round every frame (not raid) - no portrait, the bars fill the frame and take the art's colours and texture, the level sits in a bubble.")
  win.sTheme:SetPoint("TOPLEFT", 480, 0)
  win.sArt = UI:Slider(p, 300, "Art size (Artistic theme)", 60, 160, 5, 100, function(v) sset("artSize", v / 100) end, function(v) return v .. "%" end)
  win.sArt:SetPoint("TOPLEFT", 420, -222)
  for _, d in ipairs({ win.sTheme, win.sTex, win.sFace, win.sOutline, win.sBorder, win.sNum, win.eTexH, win.eTexP, win.eAnH, win.eAnP, win.eAnC, win.eFA }) do d.ccPreview = true end
  win.sSmooth = UI:Check(p, "Smooth bars", true, function(v) sset("smooth", v) end, "Bars glide to the new value instead of jumping.")
  win.sSmooth:SetPoint("TOPLEFT", 0, -260)
  win.sGrid = UI:Check(p, "Grid while unlocked", true, function(v) style().grid = v; if unlocked then showGrid(true) end end)
  win.sGrid:SetPoint("TOPLEFT", 200, -260)
  local fh = UI:Header(p, "Fonts - one for each part (for the frame picked on the left)"); fh:SetPoint("TOPLEFT", 0, -292)
  local FE = { { "name", "Name" }, { "health", "Health text" }, { "power", "Power text" }, { "level", "Level" },
    { "cast", "Cast text" }, { "castTime", "Cast timer" }, { "status", "Dead / Offline" }, { "aura", "Buff timers" } }
  local function faceOpts()
    local o = { { value = "", text = "Same as the font above" } }
    for _, n in ipairs(UI:FontList()) do o[#o + 1] = { value = n, text = n } end
    return o
  end
  local sizeOpts = { { value = 0, text = "Auto" } }
  for n = 7, 24 do sizeOpts[#sizeOpts + 1] = { value = n, text = tostring(n) } end
  win.eFonts = {}
  for i, e in ipairs(FE) do
    local col, row = (i - 1) % 2, floor((i - 1) / 2)
    local x, y = col * 350, -320 - row * 30
    local key = e[1]
    local function fset(field, v)
      local c = C(); c.fonts = c.fonts or {}; c.fonts[key] = c.fonts[key] or {}; c.fonts[key][field] = v; S.UFApply(cur)
    end
    local lbl = UI:Text(p, e[2], "small"); lbl:SetPoint("TOPLEFT", x, y - 5)
    local fd = UI:Dropdown(p, 150, faceOpts, "", function(v) fset("face", v) end); fd:SetPoint("TOPLEFT", x + 90, y)
    local sd = UI:Dropdown(p, 70, sizeOpts, 0, function(v) fset("size", v) end); sd:SetPoint("TOPLEFT", x + 246, y)
    win.eFonts[key] = { fd, sd }
    fd.ccPreview = true; sd.ccPreview = true
  end
  local allF = UI:Button(p, "Use these fonts on every frame", 230, 22, function()
    local src = C().fonts or {}
    for _, k in ipairs(KEYS) do
      if k ~= cur then
        local c = cfg(k); c.fonts = {}
        for e, v in pairs(src) do c.fonts[e] = { face = v.face, size = v.size } end
      end
    end
    S.UFApply(); S:Print("Unit frames: fonts copied to every frame.")
  end, "Copies the fonts above (from the frame picked on the left) to all the other frames.")
  allF:SetPoint("TOPLEFT", 0, -446)

  -- search box: finds any setting by its text on every tab; click a result to jump there
  do
    local box = UI:Edit(win, 220, 24, "Search settings...")
    box:SetPoint("TOPRIGHT", win, "TOPRIGHT", -250, -41)
    win.search = box
    local list = CreateFrame("Frame", nil, win, BACKDROP_T)
    plainBackdrop(list)
    list:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -2); list:SetWidth(320)
    list:SetFrameStrata("FULLSCREEN_DIALOG"); list:Hide()
    UI:Skin(list, function(self, th) self:SetBackdropColor(th.bg[1], th.bg[2], th.bg[3], 0.98); self:SetBackdropBorderColor(th.gold[1], th.gold[2], th.gold[3], 1) end)
    local rows = {}
    local hl = CreateFrame("Frame", nil, win, BACKDROP_T)
    plainBackdrop(hl); hl:SetFrameStrata("FULLSCREEN_DIALOG"); hl:Hide()
    hl:SetBackdropColor(0, 0, 0, 0)
    local function clean(t) return (tostring(t or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("\n", " ")) end
    -- every text on every tab (rebuilt each search: dropdowns change their text)
    local function index()
      local out, seen = {}, {}
      local function walk(fr, tab)
        for _, r in ipairs({ fr:GetRegions() }) do
          if r.GetObjectType and r:GetObjectType() == "FontString" then
            local t = clean(r:GetText())
            if t ~= "" and #t <= 140 then
              local k = tab .. "|" .. t
              if not seen[k] then seen[k] = true; out[#out + 1] = { tab = tab, fs = r, text = t, low = t:lower() } end
            end
          end
        end
        for _, ch in ipairs({ fr:GetChildren() }) do walk(ch, tab) end
      end
      for i, pn in ipairs(panes) do walk(pn, i) end
      return out
    end
    local function flash(e)
      local fs = e.fs
      hl:ClearAllPoints()
      local par = fs:GetParent()
      local isCheck = par and par.GetObjectType and par:GetObjectType() == "CheckButton"
      hl:SetPoint("TOPLEFT", isCheck and par or fs, "TOPLEFT", -5, 5); hl:SetPoint("BOTTOMRIGHT", fs, "BOTTOMRIGHT", 5, -5)
      local th = UI:Theme()
      hl:SetBackdropBorderColor(th.gold[1], th.gold[2], th.gold[3], 1)
      hl:Show(); hl:SetAlpha(1)
      local t0 = GetTime()
      hl:SetScript("OnUpdate", function(self)
        local p2 = (GetTime() - t0) / 2.2
        if p2 >= 1 then self:Hide(); self:SetScript("OnUpdate", nil) return end
        self:SetAlpha(0.5 + 0.5 * math.cos(p2 * math.pi * 6) * (1 - p2))
      end)
    end
    local function row(i)
      local r = rows[i]
      if r then return r end
      r = CreateFrame("Button", nil, list)
      r:SetHeight(20); r:SetPoint("TOPLEFT", 6, -4 - (i - 1) * 20); r:SetPoint("TOPRIGHT", -6, -4 - (i - 1) * 20)
      r.text = UI:Text(r, "", "small"); r.text:SetPoint("LEFT", 2, 0); r.text:SetPoint("RIGHT", -2, 0); r.text:SetJustifyH("LEFT"); r.text:SetWordWrap(false)
      r.hi = r:CreateTexture(nil, "BACKGROUND"); r.hi:SetAllPoints(); r.hi:SetTexture(WHITE); r.hi:SetVertexColor(1, 1, 1, 0.08); r.hi:Hide()
      r:SetScript("OnEnter", function(self) self.hi:Show() end)
      r:SetScript("OnLeave", function(self) self.hi:Hide() end)
      r:SetScript("OnClick", function(self)
        list:Hide(); box:ClearFocus()
        tabs:Select(self.entry.tab)
        if self.entry.fs then C_Timer.After(0.05, function() flash(self.entry) end) end
      end)
      rows[i] = r
      return r
    end
    function win.doSearch(q)
      q = S.Trim and S.Trim(q or "") or (q or "")
      for _, r in ipairs(rows) do r:Hide() end
      if #q < 2 then list:Hide() return {} end
      local low = q:lower()
      local hits = {}
      for i, n in ipairs(names) do if n:lower():find(low, 1, true) then hits[#hits + 1] = { tab = i, text = n .. " tab" } end end
      for _, e in ipairs(index()) do
        if e.low:find(low, 1, true) then hits[#hits + 1] = e end
        if #hits >= 10 then break end
      end
      if #hits == 0 then hits[1] = { none = true, text = "Nothing found" } end
      for i, e in ipairs(hits) do
        local r = row(i)
        r.entry = e
        if e.none then r.text:SetText("|cff888888" .. e.text .. "|r"); r:Disable()
        else
          local here = (not e.fs) or (e.fs:GetParent() and e.fs:GetParent():IsShown())
          local short = #e.text > 52 and (e.text:sub(1, 50) .. "...") or e.text
          r.text:SetText(short .. "  |cff888888- " .. names[e.tab] .. (here and "" or " (not for this frame)") .. "|r")
          r:Enable()
        end
        r:Show()
      end
      list:SetHeight(8 + #hits * 20); list:Show()
      return hits
    end
    box:HookScript("OnTextChanged", function(self, user) win.doSearch(self:GetText()) end)
    box:HookScript("OnEditFocusLost", function() C_Timer.After(0.2, function() if not box:HasFocus() then list:Hide() end end) end)
    box:SetScript("OnEnterPressed", function(self)
      local first = rows[1]
      if first and first:IsShown() and first:IsEnabled() then first:Click() else self:ClearFocus() end
    end)
  end

  -- r136: settings revamp. The old tab panes above are only built as parts: they're cut into small cards
  -- (by the y offsets of their pieces) and stacked on 8 pages - per frame: Layout, Text, Auras, Cast bar,
  -- Extras; for everything: Look and theme, Effects, Totem bar. A frame list on the left picks the frame.
  -- Cards marked "more" start folded (the less used settings); folding is remembered.
  do
    local X0 = 16 + 150 + 12
    local TOPY = -84
    local pageW = W - X0 - 16
    local cardW = pageW - 28
    local openState = G().ufCardsOpen or {}
    G().ufCardsOpen = openState
    local PNAMES = { "Layout", "Text", "Auras", "Cast bar", "Extras", "Look and theme", "Effects", "Totem bar" }
    local pages, pageCards = {}, {}
    for i = 1, #PNAMES do
      local holder = CreateFrame("Frame", nil, win)
      holder:SetPoint("TOPLEFT", X0, TOPY - 34); holder:SetPoint("BOTTOMRIGHT", -16, 40)
      local sf, child = UI:Scroll(holder, pageW, H - 84 - 34 - 40)
      sf:SetPoint("TOPLEFT", 0, 0); sf:SetPoint("BOTTOMRIGHT", -24, 0)
      child:SetWidth(cardW + 4)
      holder.child = child; holder:Hide()
      pages[i] = holder; pageCards[i] = {}
    end
    local function stack(i)
      local y = -2
      for _, cd in ipairs(pageCards[i]) do
        cd:ClearAllPoints(); cd:SetPoint("TOPLEFT", pages[i].child, "TOPLEFT", 2, y)
        local open = cd.open
        cd.content:SetShown(open)
        if cd.chev then cd.chev:SetText(open and "-" or "+") end
        local hgt = 32 + (open and (cd.ch + 10) or 0)
        cd:SetHeight(hgt)
        y = y - hgt - 10
      end
      pages[i].child:SetHeight(-y + 10)
    end
    local function card(i, id, title, ch, more, desc)
      local cd = CreateFrame("Frame", nil, pages[i].child, BACKDROP_T)
      UI.EnsureBackdrop(cd)
      cd:SetWidth(cardW)
      UI:Skin(cd, function(self, th)
        self:SetBackdropColor(th.panel and th.panel[1] or 0.1, th.panel and th.panel[2] or 0.1, th.panel and th.panel[3] or 0.12, 0.55)
        self:SetBackdropBorderColor(th.edge[1], th.edge[2], th.edge[3], 0.5)
        if self.title then self.title:SetTextColor(th.gold[1], th.gold[2], th.gold[3]) end
        if self.chev then self.chev:SetTextColor(th.gold[1], th.gold[2], th.gold[3]) end
      end)
      cd.title = UI:Text(cd, title, "normal"); cd.title:SetPoint("TOPLEFT", 12, -9)
      if desc then cd.desc = UI:Text(cd, "|cff888888" .. desc .. "|r", "small"); cd.desc:SetPoint("LEFT", cd.title, "RIGHT", 10, 0) end
      cd.content = CreateFrame("Frame", nil, cd)
      cd.content:SetPoint("TOPLEFT", 12, -34); cd.content:SetSize(cardW - 24, ch)
      cd.ch = ch
      if more then
        cd.chev = UI:Text(cd, "+", "large"); cd.chev:SetPoint("TOPRIGHT", -12, -6)
        local hit = CreateFrame("Button", nil, cd)
        hit:SetPoint("TOPLEFT", 0, 0); hit:SetPoint("TOPRIGHT", 0, 0); hit:SetHeight(30)
        hit:SetScript("OnClick", function()
          cd.open = not cd.open; openState[id] = cd.open; stack(i)
        end)
        cd.hint = UI:Text(cd, "|cff888888click to show|r", "small"); cd.hint:SetPoint("RIGHT", cd.chev, "LEFT", -8, 0)
        cd.open = openState[id] and true or false
        hooksecurefunc(cd.content, "SetShown", function(_, v) cd.hint:SetShown(not v) end)
      else cd.open = true end
      cd.id = id
      pageCards[i][#pageCards[i] + 1] = cd
      return cd
    end
    win.ufPages, win.ufCards = pages, pageCards
    -- move the pieces of an old pane that sit between y0 (top, included) and y1 (bottom) into a card
    local moved = {}
    local VERT = { LEFT = "TOPLEFT", RIGHT = "TOPRIGHT", CENTER = "TOP" }
    local function slice(src, y0, y1, dst, hideTop, shift)
      shift = shift or 0
      local objs = {}
      for _, r in ipairs({ src:GetRegions() }) do objs[#objs + 1] = r end
      for _, c in ipairs({ src:GetChildren() }) do objs[#objs + 1] = c end
      for _, o in ipairs(objs) do
        if not moved[o] then
          local n = o.GetNumPoints and o:GetNumPoints() or 0
          local pts, topY = {}, nil
          for k = 1, n do
            local pt, rel, rp, x, y = o:GetPoint(k)
            pts[k] = { pt, rel, rp, x or 0, y or 0 }
            if (rel == src or rel == nil) and topY == nil and (pt:find("TOP") or not VERT[pt]) then topY = y or 0 end
          end
          if topY and topY <= y0 and topY > y1 then
            moved[o] = dst
            if hideTop and topY == y0 and o.GetObjectType and o:GetObjectType() == "FontString" then o:Hide(); o.ccDropped = true end
            o:SetParent(dst); o:ClearAllPoints()
            for _, p in ipairs(pts) do
              local pt, rel, rp, x, y = p[1], p[2], p[3], p[4], p[5]
              if rel == src or rel == nil then
                if VERT[pt] and VERT[rp] and not pt:find("TOP") then pt, rp, y = VERT[pt], VERT[rp], topY end
                o:SetPoint(pt, dst, rp, x, y - y0 + shift)
              else o:SetPoint(pt, rel, rp, x, y) end
            end
          end
        end
      end
    end
    -- pieces anchored to other pieces go where those went
    local function follow(src)
      local again = true
      while again do
        again = false
        local objs = {}
        for _, r in ipairs({ src:GetRegions() }) do objs[#objs + 1] = r end
        for _, c in ipairs({ src:GetChildren() }) do objs[#objs + 1] = c end
        for _, o in ipairs(objs) do
          if not moved[o] and o.GetPoint then
            local _, rel = o:GetPoint(1)
            local d = rel and moved[rel]
            if d then moved[o] = d; o:SetParent(d); again = true end
          end
        end
      end
    end
    local function add(page, id, title, src, y0, y1, more, hideTop, desc)
      local shift = hideTop and 26 or 0          -- the old sub-heading is dropped (the card has a title): close the gap
      local cd = card(page, id, title, y0 - y1 - shift, more, desc)
      slice(panes[src], y0, y1, cd.content, hideTop, shift)
      return cd
    end
    -- 1 Layout
    do
      local cd = card(1, "show", "Show", 24)
      win.enabled:SetParent(cd.content); win.enabled:ClearAllPoints(); win.enabled:SetPoint("TOPLEFT", 0, 0)
      win.replace:SetParent(cd.content); win.replace:ClearAllPoints(); win.replace:SetPoint("TOPLEFT", 260, 0)
    end
    add(1, "portrait", "Portrait and badges", 3, 0, -190)
    add(1, "size", "Size and position", 1, 0, -258)
    add(1, "colours", "Colours", 9, 0, -358, true, false, "pick your own colour for any part")
    add(1, "round", "Roundness", 1, -270, -356, true, true, "frame and bar corners")
    -- 2 Text
    add(2, "bars", "Bars and name", 2, 0, -152)
    add(2, "showon", "Show on the frame", 2, -160, -240)
    add(2, "level", "Level", 2, -244, -308)
    add(2, "fonts", "Fonts", 7, -292, -470, true, true, "a font and size for each part")
    -- 3 Auras
    add(3, "auras", "Buffs and debuffs", 4, 0, -226)
    add(3, "combat", "In combat", 4, -232, -364, true, true, "how auras still show during a fight")
    -- 4 Cast bar
    add(4, "cast", "Cast bar", 5, 0, -130)
    add(4, "castlook", "Look", 5, -134, -356, true, true, "texture, colour, timer, spell name")
    -- 5 Extras
    add(5, "hl", "Highlight the frame", 6, 0, -80, false, true)
    add(5, "icons", "Icons", 6, -84, -164, false, true)
    add(5, "more", "Fading and class extras", 6, -168, -302, false, true)
    add(5, "anim", "Animations", 10, -64, -332, true, true, "moving effects on the bars and frame")
    -- 6 Look and theme (every frame)
    add(6, "look", "Look and theme", 7, 0, -290)
    add(6, "tex", "Bar textures", 10, 0, -62, false, true, "health and power")
    -- 7 Effects (every frame)
    add(7, "react", "Reactions", 11, 0, -354, false, false, "flashes when health, power or combo points change")
    -- 8 Totem bar
    add(8, "totem", "Totem bar", 8, 0, -342)
    for k = 1, 11 do follow(panes[k]) end
    for i = 1, #pages do stack(i) end
    win.ufLeft = {}
    for k = 1, 11 do
      for _, r in ipairs({ panes[k]:GetRegions() }) do if not moved[r] and not r.ccDropped then win.ufLeft[#win.ufLeft + 1] = r end end
      for _, c in ipairs({ panes[k]:GetChildren() }) do if not moved[c] then win.ufLeft[#win.ufLeft + 1] = c end end
    end
    -- tab strip (per-frame pages) + title for the "everything" pages
    local cur5 = 1
    local strip
    local ptitle = UI:Text(win, "", "large"); ptitle:SetPoint("TOPLEFT", X0, TOPY - 4)
    local pnote = UI:Text(win, "|cff888888These settings are for every frame.|r", "small"); pnote:SetPoint("LEFT", ptitle, "RIGHT", 12, 0)
    local nav = { current = 1 }
    win.ufNav = nav
    local side = {}
    function nav:Select(i)
      i = (i and pages[i]) and i or 1
      self.current = i
      for j, pg in ipairs(pages) do pg:SetShown(j == i) end
      local perFrame = i <= 5
      if perFrame then cur5 = i; strip.current = i; strip:Paint() end
      strip:SetShown(perFrame); copy:SetShown(perFrame)
      ptitle:SetShown(not perFrame); pnote:SetShown(not perFrame)
      if not perFrame then ptitle:SetText(PNAMES[i]) end
      if win.paintSide then win.paintSide() end
    end
    strip = UI:SubTabs(win, { "Layout", "Text", "Auras", "Cast bar", "Extras" }, function(i) nav:Select(i) end)
    strip:SetPoint("TOPLEFT", X0, TOPY); strip:SetPoint("TOPRIGHT", -16, TOPY)
    copy:ClearAllPoints(); copy:SetPoint("TOPRIGHT", win, "TOPRIGHT", -16, TOPY - 2)
    -- frame list
    local sideBox = CreateFrame("Frame", nil, win, BACKDROP_T)
    UI.EnsureBackdrop(sideBox)
    sideBox:SetPoint("TOPLEFT", 16, TOPY + 2); sideBox:SetPoint("BOTTOMLEFT", 16, 40); sideBox:SetWidth(150)
    UI:Skin(sideBox, function(self, th) self:SetBackdropColor(0, 0, 0, 0.25); self:SetBackdropBorderColor(th.edge[1], th.edge[2], th.edge[3], 0.4) end)
    local sy = -40
    local function head(t)
      local h = UI:Text(sideBox, "|cff888888" .. t .. "|r", "small"); h:SetPoint("TOPLEFT", 10, sy); sy = sy - 18
    end
    local function item(text, onClick, isFrame)
      local b = CreateFrame("Button", nil, sideBox)
      b:SetHeight(22); b:SetPoint("TOPLEFT", 4, sy); b:SetPoint("TOPRIGHT", -4, sy); sy = sy - 23
      b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints(); b.bg:SetTexture(WHITE); b.bg:Hide()
      b.hot = b:CreateTexture(nil, "BACKGROUND", nil, 1); b.hot:SetAllPoints(); b.hot:SetTexture(WHITE); b.hot:SetVertexColor(1, 1, 1, 0.05); b.hot:Hide()
      b.text = UI:Text(b, text, "normal"); b.text:SetPoint("LEFT", isFrame and 22 or 10, 0)
      if isFrame then b.dot = b:CreateTexture(nil, "ARTWORK"); b.dot:SetTexture(UI.MEDIA .. "UI\\disc"); b.dot:SetSize(8, 8); b.dot:SetPoint("LEFT", 9, 0) end
      b:SetScript("OnEnter", function(self) self.hot:Show() end)
      b:SetScript("OnLeave", function(self) self.hot:Hide() end)
      b:SetScript("OnClick", onClick)
      side[#side + 1] = b
      return b
    end
    head("Frames")
    for _, k in ipairs(KEYS) do
      local b = item(LABEL[k], function()
        cur = k; S:RefreshUnitFrames()
        if nav.current > 5 then nav:Select(cur5) else nav:Select(nav.current) end
      end, true)
      b.key = k
    end
    sy = sy - 6
    head("Every frame")
    for i = 6, 8 do local b = item(PNAMES[i], function() nav:Select(i) end); b.page = i end
    function win.paintSide()
      local th = UI:Theme()
      local on = store().on
      for _, b in ipairs(side) do
        local sel = (b.key and b.key == cur and nav.current <= 5) or (b.page and b.page == nav.current)
        b.bg:SetShown(sel); b.bg:SetVertexColor(th.gold[1], th.gold[2], th.gold[3], 0.16)
        b.text:SetTextColor(unpack(sel and th.gold or th.text))
        if b.dot then
          local live = on and cfg(b.key).on
          if live then b.dot:SetVertexColor(0.3, 0.85, 0.35, 1) else b.dot:SetVertexColor(0.45, 0.45, 0.45, 1) end
        end
      end
    end
    -- the old layout's frame picker row and the old tab strip are gone
    fl:Hide(); win.unitDrop:Hide()
    prof:ClearAllPoints(); prof:SetPoint("RIGHT", win.test, "LEFT", -6, 0)
    win.unlock:SetText("Move frames")
    if win.search then
      win.search:ClearAllPoints(); win.search:SetPoint("TOPLEFT", sideBox, "TOPLEFT", 6, -6); win.search:SetWidth(138)
      win.search:SetFrameLevel(sideBox:GetFrameLevel() + 3)
    end
    -- search / old callers use these
    panes, names, tabs = pages, PNAMES, nav
    win.tabs = nav
    win.ufOld2New = { 1, 2, 1, 3, 4, 5, 6, 8, 1, 7, 7 }
  end

  local foot = UI:Text(win, "|cffaaaaaa/ccenter frames  -  unlock  -  test|r", "small")
  foot:SetPoint("BOTTOMLEFT", 16, 18)
  tabs:Select(1)
  win:HookScript("OnShow", function() S:RefreshUnitFrames() end)
end

-- Elite / rare glow (r126): gold (elite) / silver (rare) glowing edge round the frame. Per frame: eliteBorder.
;(function()
  local E = {}
  S.UFElite = E
  local MEDIA = UI.MEDIA
  local COL = { gold = { 1, 0.80, 0.26 }, silver = { 0.86, 0.89, 0.96 } }
  local FR = {
    humanoid_normal = { 0.4557, 0.5130, 0.2630, 0.6216, 0.7016, 0.0951 },
    humanoid_elite = { 0.4505, 0.5286, 0.2526, 0.6098, 0.7096, 0.0912 },
    humanoid_rare = { 0.5026, 0.5182, 0.2917, 0.6589, 0.7474, 0.1219 },
    humanoid_rareelite = { 0.4766, 0.5391, 0.2786, 0.6536, 0.7109, 0.1042 },
    dragonkin_normal = { 0.4974, 0.5078, 0.2995, 0.6797, 0.7057, 0.1161 },
    dragonkin_elite = { 0.4974, 0.5182, 0.2969, 0.6849, 0.7266, 0.1219 },
    dragonkin_rare = { 0.4661, 0.5339, 0.2760, 0.6589, 0.7161, 0.0979 },
    dragonkin_rareelite = { 0.4609, 0.5182, 0.2630, 0.6641, 0.7161, 0.1104 },
    beast_normal = { 0.4818, 0.5234, 0.2865, 0.6536, 0.7161, 0.0917 },
    beast_elite = { 0.4714, 0.5234, 0.2760, 0.6589, 0.7214, 0.1161 },
    beast_rare = { 0.4974, 0.5026, 0.2969, 0.6589, 0.7370, 0.1161 },
    beast_rareelite = { 0.4557, 0.5339, 0.2656, 0.6233, 0.7243, 0.0960 },
    undead_normal = { 0.5130, 0.5130, 0.3047, 0.6797, 0.7109, 0.1161 },
    undead_elite = { 0.5078, 0.5182, 0.2969, 0.6589, 0.7370, 0.1161 },
    undead_rare = { 0.4505, 0.5130, 0.2526, 0.6098, 0.6940, 0.0912 },
    undead_rareelite = { 0.4609, 0.5130, 0.2630, 0.6268, 0.7016, 0.0951 },
    elemental_normal = { 0.4818, 0.5182, 0.2969, 0.6641, 0.7109, 0.1047 },
    elemental_elite = { 0.4818, 0.5182, 0.2969, 0.6589, 0.7161, 0.0979 },
    elemental_rare = { 0.4661, 0.5182, 0.2786, 0.6536, 0.7161, 0.0990 },
    elemental_rareelite = { 0.4609, 0.5182, 0.2760, 0.6589, 0.7161, 0.1104 },
    mechanical_normal = { 0.4609, 0.5182, 0.2747, 0.6589, 0.7161, 0.1104 },
    mechanical_elite = { 0.4870, 0.5286, 0.2969, 0.6641, 0.7161, 0.0990 },
    mechanical_rare = { 0.4453, 0.5182, 0.2500, 0.6029, 0.6973, 0.0903 },
    mechanical_rareelite = { 0.4557, 0.5078, 0.2656, 0.6233, 0.6982, 0.0960 },
    demon_normal = { 0.4557, 0.5182, 0.2760, 0.6536, 0.7214, 0.0922 },
    demon_elite = { 0.4609, 0.5234, 0.2760, 0.6328, 0.7005, 0.0807 },
    demon_rare = { 0.4557, 0.5182, 0.2734, 0.6589, 0.7214, 0.1104 },
    demon_rareelite = { 0.4974, 0.5234, 0.2995, 0.6589, 0.7214, 0.0990 },
    giant_normal = { 0.4870, 0.5339, 0.2969, 0.6589, 0.7214, 0.0932 },
    giant_elite = { 0.4766, 0.5182, 0.2786, 0.6589, 0.7214, 0.0979 },
    giant_rare = { 0.4609, 0.5182, 0.2682, 0.6589, 0.7214, 0.0990 },
    giant_rareelite = { 0.4661, 0.5182, 0.2682, 0.6589, 0.7214, 0.0990 },
    aberration_normal = { 0.4870, 0.5130, 0.2943, 0.6693, 0.7266, 0.1047 },
    aberration_elite = { 0.4609, 0.5078, 0.2760, 0.6589, 0.7109, 0.0990 },
    aberration_rare = { 0.4661, 0.5026, 0.2734, 0.6641, 0.7161, 0.0990 },
    aberration_rareelite = { 0.4870, 0.4870, 0.2995, 0.6641, 0.7161, 0.1104 },
    critter_normal = { 0.4974, 0.5234, 0.3047, 0.6641, 0.7266, 0.1161 },
    critter_elite = { 0.4661, 0.5130, 0.2760, 0.6641, 0.7161, 0.0979 },
    critter_rare = { 0.4714, 0.5182, 0.2734, 0.6589, 0.7161, 0.0990 },
    critter_rareelite = { 0.4870, 0.5182, 0.2891, 0.6641, 0.7161, 0.0990 },
  }
  E.FR = FR
  E.TYPES = { "humanoid", "dragonkin", "beast", "undead", "elemental", "mechanical", "demon", "giant", "aberration", "critter" }
  local TYPEMAP = { Humanoid = "humanoid", Dragonkin = "dragonkin", Beast = "beast", Undead = "undead", Elemental = "elemental",
    Mechanical = "mechanical", Demon = "demon", Giant = "giant", Aberration = "aberration", Critter = "critter",
    ["Wild Pet"] = "critter", ["Non-combat Pet"] = "critter", ["Gas Cloud"] = "elemental", Totem = "elemental" }
  -- classification: "elite" (elite + world boss), "rare", "rareelite", "normal"; nil when unknown / hidden
  local function classOf(f)
    local cl
    if f.fake then
      cl = f.fake.classif
      if not cl then
        if f.key == "target" then cl = "elite" elseif f.key == "focus" then cl = "rare" elseif f.key == "boss" then cl = "worldboss" else cl = "normal" end
      end
    else
      if not f.unit then return nil end
      cl = try(UnitClassification, f.unit)
      if sec(cl) or cl == nil then return nil end
    end
    if cl == "worldboss" then return "elite" end
    if cl == "elite" or cl == "rare" or cl == "rareelite" then return cl end
    return "normal"
  end
  local function kindOf(f)           -- gold / silver / nil (for the border)
    local cl = classOf(f)
    if cl == "elite" then return "gold" end
    if cl == "rare" or cl == "rareelite" then return "silver" end
    return nil
  end
  E.kindOf = kindOf; E.classOf = classOf
  local function typeOf(f)
    local c = f.cfg
    if c.eliteArt and c.eliteArt ~= "type" and FR[c.eliteArt .. "_normal"] then return c.eliteArt end
    if f.fake then return f.fake.ctype or (f.key == "focus" and "beast") or (f.key == "boss" and "dragonkin") or "humanoid" end
    local t = f.unit and try(UnitCreatureType, f.unit)
    if sec(t) or not t then return "humanoid" end
    return TYPEMAP[t] or "humanoid"
  end
  E.typeOf = typeOf
  local function make(f)
    local o = CreateFrame("Frame", nil, f)
    o:SetAllPoints(f)
    o.glow = newBox(o, "BACKGROUND", 0, true)
    for _, t in ipairs(o.glow.parts) do t:SetBlendMode("ADD") end
    o.edge = newBox(o, "OVERLAY", 1, true)
    o.edge2 = newBox(o, "OVERLAY", 2, true)
    for _, t in ipairs(o.edge2.parts) do t:SetBlendMode("ADD") end
    f.ccElite = o
    return o
  end
  function E.update(f)
    local c = f.cfg
    if not c or not f.ui then return end
    if S.UFArt then pcall(S.UFArt.refresh, f) end
    local kind = kindOf(f)
    local wantEdge = kind and c.eliteBorder ~= false
    local o = f.ccElite
    if not wantEdge then if o then o:Hide() end return end
    o = o or make(f)
    local W, H = f:GetWidth() or 0, f:GetHeight() or 0
    if W <= 0 or H <= 0 then o:Hide() return end
    -- r128 Artistic theme: the glow hugs the bars' pill under the art (the art's ornaments overlap it) in the art's colours
    local af = f.ccArtF
    if af and af.ccOn and af.bh then
      o:ClearAllPoints(); o:SetAllPoints(af.region)
      o:SetFrameLevel(f.health:GetFrameLevel() + 1)
      local col = { S.UFArt.mix(f, COL[kind][1], COL[kind][2], COL[kind][3], 0.55) }
      local r = floor(af.bh / 2 + 0.5)
      local key = "art" .. kind .. r .. ":" .. (af.ccDesign or "") .. floor(W)
      if o.key ~= key then
        -- r129: soft glow only (no edge lines), faint, mostly hidden under the art's rim
        boxLayout(o.glow, MEDIA .. "Anim\\edgeglow5", r + 10, 10)
        boxColor(o.glow, col[1], col[2], col[3], 0.32)
        o.key = key
      end
      boxShown(o.glow, true); boxShown(o.edge, false); boxShown(o.edge2, false)
      o.ccArt = kind
      o:Show()
      return
    end
    o:ClearAllPoints(); o:SetAllPoints(f)
    o:SetFrameLevel(f.ui:GetFrameLevel() + 3)
    if wantEdge then
      local col = COL[kind]
      local rk = c.round
      local fk = (type(rk) == "number" and rk >= 0) and rk or (style().round or 0)
      local key = kind .. fk .. ":" .. floor(W) .. "x" .. floor(H)
      if o.key ~= key then
        local cs = cornerSize(W, H)
        boxLayout(o.glow, MEDIA .. "Anim\\edgeglow" .. fk, 24, 14)
        boxLayout(o.edge, MEDIA .. "UI\\ufedge" .. fk, cs)
        boxLayout(o.edge2, MEDIA .. "UI\\ufedge" .. fk, cs, 1)
        boxColor(o.glow, col[1], col[2], col[3], kind == "gold" and 0.75 or 0.6)
        boxColor(o.edge, col[1], col[2], col[3], 1)
        boxColor(o.edge2, col[1], col[2], col[3], 0.55)
        o.key = key
      end
    end
    boxShown(o.glow, wantEdge); boxShown(o.edge, wantEdge); boxShown(o.edge2, wantEdge)
    o.ccArt = kind
    o:Show()
  end
end)()

-- Artistic theme (r127): Style > Theme "artistic". The frame art CCPlates uses for its artistic nameplates
-- (Media\Plates\gw\, made from Good Unit Frames' art - not to be published without that author's OK) wraps every
-- frame except raid: big ornaments round the portrait-side end, a band of the same ornaments along the top and
-- bottom, a smaller collar on the other end with the level in a bubble. No portrait; the health + power bars fill the
-- frame as one pill tucked just under the art's inner rim; bar colours + texture come from the art (A.THEME).
-- Design: players -> their class, everything else -> creature type (unknown when hidden); rares -> the rare art.
-- Same geometry as CCPlates (P.GW): the art is drawn for a bar of height H, ring inner edge ri from the middle line.
;(function()
  local A = {}
  S.UFArt = A
  local MEDIA = UI.MEDIA
  local GW = { H = 48, ts = 0.6, ox = 70, oy = 64, tw = 256, th = 128, ringC = 4.8, railD = 30.8, railTop = 24, railLen = 472 }
  A.GW = GW
  -- health colour, power colour, bar texture (Media\Bars\ccbarN)
  A.THEME = {
    humanoid = { { 0.18, 0.62, 0.60 }, { 0.70, 0.47, 0.27 }, 17 }, beast = { { 0.88, 0.44, 0.16 }, { 0.88, 0.82, 0.64 }, 13 },
    undead = { { 0.82, 0.76, 0.58 }, { 0.22, 0.58, 0.50 }, 14 }, dragonkin = { { 0.52, 0.45, 0.72 }, { 0.80, 0.52, 0.28 }, 12 },
    elemental = { { 0.20, 0.60, 1.00 }, { 0.85, 0.90, 0.95 }, 19 }, mechanical = { { 0.15, 0.65, 0.65 }, { 0.78, 0.60, 0.35 }, 11 },
    demon = { { 0.68, 0.12, 0.12 }, { 0.35, 0.78, 0.25 }, 7 }, giant = { { 0.80, 0.72, 0.52 }, { 0.70, 0.50, 0.25 }, 5 },
    aberration = { { 0.52, 0.26, 0.95 }, { 0.20, 0.70, 0.75 }, 18 }, critter = { { 0.55, 0.66, 0.25 }, { 0.80, 0.65, 0.40 }, 2 },
    unknown = { { 0.30, 0.46, 0.56 }, { 0.20, 0.60, 0.60 }, 1 },
    warrior = { { 0.80, 0.15, 0.12 }, { 0.72, 0.74, 0.78 }, 5 }, paladin = { { 0.98, 0.76, 0.24 }, { 0.78, 0.13, 0.13 }, 16 },
    hunter = { { 0.82, 0.65, 0.42 }, { 0.45, 0.56, 0.25 }, 13 }, rogue = { { 0.72, 0.12, 0.15 }, { 0.86, 0.70, 0.30 }, 11 },
    priest = { { 0.98, 0.88, 0.60 }, { 0.95, 0.95, 1.00 }, 6 }, shaman = { { 1.00, 0.45, 0.10 }, { 0.20, 0.55, 1.00 }, 19 },
    mage = { { 0.36, 0.76, 1.00 }, { 0.80, 0.93, 1.00 }, 20 }, warlock = { { 0.95, 0.35, 0.08 }, { 0.52, 0.20, 0.66 }, 7 },
    druid = { { 0.50, 0.70, 0.25 }, { 0.70, 0.50, 0.30 }, 13 }, deathknight = { { 0.45, 0.80, 1.00 }, { 0.70, 0.75, 0.82 }, 20 },
    demonhunter = { { 0.30, 0.85, 0.25 }, { 0.86, 0.66, 0.30 }, 7 }, monk = { { 0.45, 0.90, 0.70 }, { 0.90, 0.75, 0.40 }, 17 },
    evoker = { { 0.15, 0.70, 0.45 }, { 0.90, 0.70, 0.30 }, 12 },
  }
  local TYPES = { Humanoid = "humanoid", Beast = "beast", Dragonkin = "dragonkin", Undead = "undead", Elemental = "elemental",
    Mechanical = "mechanical", Demon = "demon", Giant = "giant", Aberration = "aberration", Critter = "critter",
    ["Non-combat Pet"] = "critter", ["Wild Pet"] = "critter" }
  function A.on(f)
    local c = f and f.cfg
    return c and f.key ~= "raid" and style().theme == "artistic" and true or false
  end
  -- three baked sizes (as in CCPlates r26): returns t, sub folder, texels per unit, extra scale u
  local function set(size)
    size = min(1.6, max(0.6, tonumber(size) or 1))
    if size < 0.866 then return 0.75, "s\\", 0.75, size / 0.75
    elseif size > 1.162 then return 1.35, "l\\", 0.6 / 1.35, size / 1.35 end
    return 1, "", GW.ts, size
  end
  A.set = set
  local function file(kind, design, rank, sub) return MEDIA .. "Plates\\gw\\" .. (sub or "") .. kind .. "_" .. design .. "_" .. rank end
  function A.design(f)
    local cls, pl
    if f.fake then
      pl = not f.fake.enemy and f.key ~= "pet" and type(f.fake.class) == "string"
      cls = f.fake.class
    elseif f.unit then
      pl = bool(try(UnitIsPlayer, f.unit))
      if pl then local _, t = try(UnitClass, f.unit); cls = t end
    end
    if pl and type(cls) == "string" and not sec(cls) then
      local k = cls:lower()
      if A.THEME[k] then return k, "normal" end
    end
    local d
    if f.fake then d = f.fake.ctype or (f.key == "focus" and "beast") or (f.key == "pet" and "beast") or (f.key == "boss" and "dragonkin") or "humanoid"
    else
      local t = f.unit and try(UnitCreatureType, f.unit)
      d = (type(t) == "string" and not sec(t) and TYPES[t]) or "unknown"
    end
    local cl = S.UFElite and S.UFElite.classOf(f)
    return d, (cl == "rare" or cl == "rareelite") and "rare" or "normal"
  end
  local function make(f)
    local o = CreateFrame("Frame", nil, f)
    o:SetAllPoints(f)
    o.region = CreateFrame("Frame", nil, f)
    o.back = f:CreateTexture(nil, "BACKGROUND", nil, -7); o.back:SetTexture(WHITE); o.back:SetAllPoints(o.region)
    o.top = o:CreateTexture(nil, "OVERLAY", nil, 1); o.bot = o:CreateTexture(nil, "OVERLAY", nil, 1)
    o.cap = o:CreateTexture(nil, "OVERLAY", nil, 1); o.main = o:CreateTexture(nil, "OVERLAY", nil, 2)
    o.bub = o:CreateTexture(nil, "OVERLAY", nil, 3)
    o.lvl = o:CreateFontString(nil, "OVERLAY"); o.lvl:SetDrawLayer("OVERLAY", 4)
    for _, t in ipairs({ o.top, o.bot, o.cap, o.main, o.bub }) do
      pcall(t.SetSnapToPixelGrid, t, false); pcall(t.SetTexelSnappingBias, t, 0)
    end
    o.masks = {}
    f.ccArtF = o
    return o
  end
  -- one pill-shaped clip over both bars (+ the dark backing): a half-circle mask at each end of the region
  local function pill(o, owner, list, d)
    if not owner or not owner.CreateMaskTexture then return end
    local m = o.masks[owner]
    if not m then m = { L = owner:CreateMaskTexture(), R = owner:CreateMaskTexture(), on = {} }; o.masks[owner] = m end
    m.L:SetTexture(MEDIA .. "Bars\\capL8", "CLAMPTOWHITE", "CLAMPTOWHITE")
    m.R:SetTexture(MEDIA .. "Bars\\capR8", "CLAMPTOWHITE", "CLAMPTOWHITE")
    m.L:ClearAllPoints(); m.L:SetPoint("TOPLEFT", o.region, "TOPLEFT"); m.L:SetPoint("BOTTOMLEFT", o.region, "BOTTOMLEFT"); m.L:SetWidth(max(1, d))
    m.R:ClearAllPoints(); m.R:SetPoint("TOPRIGHT", o.region, "TOPRIGHT"); m.R:SetPoint("BOTTOMRIGHT", o.region, "BOTTOMRIGHT"); m.R:SetWidth(max(1, d))
    for _, t in ipairs(list) do
      if t and not m.on[t] then pcall(t.AddMaskTexture, t, m.L); pcall(t.AddMaskTexture, t, m.R); m.on[t] = true end
    end
  end
  function A.clip(f)
    local o = f.ccArtF
    local bh = o.bh
    local hl = { f.health:GetStatusBarTexture(), f.health.bg, f.absorb }
    local pl = { f.power:GetStatusBarTexture(), f.power.bg }
    -- animation pieces / reaction trails that follow a bar's rounding get the pill too
    for t in pairs(f.health.ccFol or {}) do hl[#hl + 1] = t end
    for t in pairs(f.power.ccFol or {}) do pl[#pl + 1] = t end
    pill(o, f.health, hl, bh)
    pill(o, f.power, pl, bh)
    pill(o, f, { o.back }, bh)
    f.health.ccArtPill, f.power.ccArtPill = o.masks[f.health], o.masks[f.power]
    f.health.ccArtO, f.power.ccArtO = o, o
    -- r130: the reaction trail bars (their own StatusBar + background, drawn in place of the bar's background)
    -- and the bar animation layers are separate frames: they need their own pill masks
    for _, bar in ipairs({ f.health, f.power }) do
      local t = bar.ccTrail
      if t then pill(o, t, { t:GetStatusBarTexture(), t.bg }, bh) end
      local an = S.UFAnim and S.UFAnim.bars and S.UFAnim.bars[bar]
      if an and an.layer then pill(o, an.layer, an.parts or {}, bh) end
    end
  end
  -- a frame of its own that draws over / instead of a bar (trail bar, animation layer)
  function A.extra(bar, owner, list)
    local o = bar.ccArtO
    if not (o and o.ccOn and o.bh) then return end
    pill(o, owner, list, o.bh)
  end
  function A.follow(bar, tex)
    local m = bar.ccArtPill
    if m and not m.on[tex] then pcall(tex.AddMaskTexture, tex, m.L); pcall(tex.AddMaskTexture, tex, m.R); m.on[tex] = true end
  end
  local function unpill(o)
    for owner in pairs(o.masks) do owner.ccArtPill = nil end
    for _, m in pairs(o.masks) do
      for t in pairs(m.on) do pcall(t.RemoveMaskTexture, t, m.L); pcall(t.RemoveMaskTexture, t, m.R) end
      m.on = {}
    end
  end
  -- colours + texture of the current design (also on target changes, from S.UFElite.update)
  function A.refresh(f)
    local o = f.ccArtF
    if not (o and o.ccOn) then f.ccArtCol = nil return end
    local d, r = A.design(f)
    local th = A.THEME[d] or A.THEME.unknown
    f.ccArtCol = th
    local key = d .. "_" .. r .. (o.sub or "")
    if o.key ~= key then
      o.key = key
      local sub = o.sub
      o.top:SetTexture(file("gwt", d, r, sub)); o.bot:SetTexture(file("gwt", d, r, sub))
      o.main:SetTexture(file("gw", d, r, sub)); o.cap:SetTexture(file("gwr", d, r, sub))
      o.bub:SetTexture(file("gwb", d, r, sub))
    end
    local tex = MEDIA .. "Bars\\ccbar" .. th[3]
    f.health:SetStatusBarTexture(tex); f.health.bg:SetTexture(tex)
    f.power:SetStatusBarTexture(tex); f.power.bg:SetTexture(tex)
    if o.bh then A.clip(f) end
    A.color(f)
    o.ccDesign = key
  end
  function A.color(f)
    local th = f.ccArtCol
    if not th then return end
    local h, p = th[1], th[2]
    f.health:SetStatusBarColor(h[1], h[2], h[3]); f.health.bg:SetVertexColor(h[1] * 0.2, h[2] * 0.2, h[3] * 0.2, 0.95)
    f.power:SetStatusBarColor(p[1], p[2], p[3]); f.power.bg:SetVertexColor(p[1] * 0.2, p[2] * 0.2, p[3] * 0.2, 0.95)
  end
  -- runs in Layout after everything is placed: re-places the bars / texts / level and draws the art
  function A.layout(f)
    local o = f.ccArtF
    if not A.on(f) then
      if o and o.ccOn then
        o.ccOn = false; o:Hide(); o.back:Hide(); unpill(o); f.levelText:SetAlpha(1)
        f.hl:ClearAllPoints(); f.hl:SetPoint("TOPLEFT", -2, 2); f.hl:SetPoint("BOTTOMRIGHT", 2, -2); f.hl:SetFrameLevel(f.ui:GetFrameLevel() + 1)
        if f.ccElite then f.ccElite.key = nil end
      end
      f.ccArtLv, f.ccArtCol = nil, nil
      return
    end
    o = o or make(f)
    o.ccOn = true
    local c, st = f.cfg, style()
    local w, h = c.w, c.h
    local size = min(1.6, max(0.6, tonumber(st.artSize) or 1))
    local ov = max(1, h * 0.07)
    local hv = h - 2 * ov
    local t, sub, ts, u = set(size)
    local k = hv / GW.H * u
    local ri = min(h / 2, hv / 2 * u)
    if o.sub ~= sub then o.sub = sub; o.key = nil end
    -- over the bars, under the texts (f.ui) and the aura icons; the cast bar goes over it too
    o:SetFrameLevel(f.health:GetFrameLevel() + 2)
    if f.cast:GetFrameLevel() <= o:GetFrameLevel() then f.cast:SetFrameLevel(o:GetFrameLevel() + 1) end
    -- r129: texts always above the art (target of target lost its texts in game)
    if f.ui:GetFrameLevel() <= o:GetFrameLevel() + 1 then
      f.ui:SetFrameLevel(o:GetFrameLevel() + 2)
      f.auraBox:SetFrameLevel(f.ui:GetFrameLevel() + 2)
    end
    -- no portrait: the bars fill the frame as one pill, just under the ring's inner edge
    f.portraitBox:Hide(); f.pline:Hide()
    local ix, iy = max(0, h / 2 - ri), max(0, h / 2 - ri)
    local bh = 2 * ri
    o.region:ClearAllPoints(); o.region:SetPoint("TOPLEFT", f, "TOPLEFT", ix, -iy); o.region:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -ix, iy)
    local ph = (c.powerH or 0) > 0 and max(3, floor(bh * 0.32 + 0.5)) or 0
    f.health:ClearAllPoints()
    f.health:SetPoint("TOPLEFT", o.region, "TOPLEFT"); f.health:SetPoint("TOPRIGHT", o.region, "TOPRIGHT")
    f.health:SetHeight(max(1, bh - (ph > 0 and (ph + 1) or 0)))
    if ph > 0 then
      f.power:ClearAllPoints()
      f.power:SetPoint("BOTTOMLEFT", o.region, "BOTTOMLEFT"); f.power:SetPoint("BOTTOMRIGHT", o.region, "BOTTOMRIGHT"); f.power:SetHeight(ph)
    end
    f.pred:SetWidth(max(1, w - 2 * ix))
    o.back:SetVertexColor(0.03, 0.03, 0.04, 0.92); o.back:Show()
    o.bh = bh
    A.clip(f)
    -- target / aggro / dispel edge: round the pill, under the art
    f.hl:ClearAllPoints(); f.hl:SetPoint("TOPLEFT", o.region, "TOPLEFT", -2, 2); f.hl:SetPoint("BOTTOMRIGHT", o.region, "BOTTOMRIGHT", 2, -2)
    f.hl:SetFrameLevel(f.health:GetFrameLevel() + 1)
    boxLayout(f.hlBox, UI.MEDIA .. "UI\\ufedgeb5", floor(bh / 2 + 2.5))
    f.hlMouse:ClearAllPoints(); f.hlMouse:SetAllPoints(o.region)
    -- texts clear of the ornaments / bubble
    local inset = floor(h * 0.42 + 0.5)
    if c.nameAt ~= "box" and c.nameAt ~= "center" then f.nameText:SetPoint("LEFT", f.health, "LEFT", inset, 0) end
    f.hpText:SetPoint("RIGHT", f.health, "RIGHT", -inset, 0)
    f.ppText:SetPoint("LEFT", f.power, "LEFT", inset, 0); f.ppText:SetPoint("RIGHT", f.power, "RIGHT", -inset, 0)
    if c.nameAt ~= "box" and c.nameAt ~= "center" then f.status:SetPoint("RIGHT", f.health, "RIGHT", -inset, 0) end
    -- r131: "Box on top" name: no box - the name rides the top ornament band, centred
    if c.nameAt == "box" and c.name then
      f.nameText:ClearAllPoints(); f.nameText:SetJustifyH("CENTER")
      f.nameText:SetPoint("BOTTOM", f, "TOP", 0, floor(GW.railD * t * k * 0.22 + 0.5) - 2)
      f.nameText:SetWidth(max(20, w - h))
      f.ccNameR = nil
    end
    -- the art (gwt_ rails cut to length so the ornaments keep their shape; gw_ main end; gwr_ collar; gwb_ bubble)
    local right = c.side == "right"
    local railD = GW.railD * t
    local rw = max(1, w - h)
    local fr = min(1, (rw / k) / GW.railLen)
    local rh = (railD + 1.2) * k
    o.top:SetTexCoord(0, fr, 0, 1); o.top:SetSize(rw, rh); o.top:ClearAllPoints(); o.top:SetPoint("TOPLEFT", f, "LEFT", h / 2, ri + railD * k)
    o.bot:SetTexCoord(0, fr, 1, 0); o.bot:SetSize(rw, rh); o.bot:ClearAllPoints(); o.bot:SetPoint("TOPLEFT", f, "LEFT", h / 2, -ri + 1.2 * k)
    local Lw, Lh = GW.tw / ts * k, GW.th / ts * k
    local eL, eR = h / 2 - ri, w - h / 2 + ri
    local function place(tx, onRight)
      tx:SetSize(Lw, Lh); tx:ClearAllPoints()
      if onRight then tx:SetTexCoord(1, 0, 0, 1); tx:SetPoint("TOPLEFT", f, "LEFT", eR + GW.ox / ts * k - Lw, GW.oy / ts * k)
      else tx:SetTexCoord(0, 1, 0, 1); tx:SetPoint("TOPLEFT", f, "LEFT", eL - GW.ox / ts * k, GW.oy / ts * k) end
    end
    place(o.main, right); place(o.cap, not right)
    local bd = floor(h * 0.74 * max(0.85, size) + 0.5)
    local bx = right and (eL - GW.ringC * t * k) or (eR + GW.ringC * t * k)
    o.bub:SetSize(bd, bd); o.bub:ClearAllPoints(); o.bub:SetPoint("CENTER", f, "LEFT", bx, 0)
    setFace(o.lvl, max(7, min(16, floor(bd * 0.42))), "OUTLINE")
    o.lvl:ClearAllPoints(); o.lvl:SetPoint("CENTER", f, "LEFT", bx + 0.5, 0)
    local lvOn = c.level and true or false
    o.bub:SetShown(lvOn); o.lvl:SetShown(lvOn)
    -- the level lives in the bubble
    f.ccArtLv = true
    f.levelText:SetAlpha(0)
    if f.levelBox then f.levelBox:Hide() end
    o.key = nil
    o:Show()
    A.refresh(f)
  end
  -- after Paint: the art is the edge - no frame box / edge / portrait line
  function A.post(f)
    local o = f.ccArtF
    if not (o and o.ccOn) then
      if f.nameBox and f.nameBox.ccArtHid then f.nameBox.ccArtHid = nil; boxShown(f.nameBox.ccFill, true); boxShown(f.nameBox.ccEdge, true) end
      return
    end
    if f.ccFill then boxShown(f.ccFill, false) end
    if f.ccEdge then boxShown(f.ccEdge, false) end
    if f.nameBox and f.nameBox.ccFill then boxShown(f.nameBox.ccFill, false); boxShown(f.nameBox.ccEdge, false); f.nameBox.ccArtHid = true end
    f.pline:Hide()
    A.color(f)
  end
  -- a status colour (elite gold, target / aggro edge) pulled toward the art's own colour by amount a (0-1),
  -- kept bright so it still reads as a glow
  function A.mix(f, r, g, b, a)
    local th = f.ccArtCol
    if not th then return r, g, b end
    local h = th[1]
    local mr, mg, mb = r + (h[1] - r) * a, g + (h[2] - g) * a, b + (h[3] - b) * a
    local m = max(mr, mg, mb, 0.01)
    local lift = m < 0.85 and (0.85 / m) or 1
    return min(1, mr * lift), min(1, mg * lift), min(1, mb * lift)
  end
  A.RING_BUFF, A.RING_DEBUFF = { 1, 1, 1 }, { 0.9, 0.1, 0.08 }
  -- where the aura row sits under the frame: just under the bottom ornament band's thin middle, clear of the
  -- end pieces; returns x inset, y (from the frame's bottom, negative = down), icons per side
  function A.auraBand(f, step)
    local c = f.cfg
    local h, w = c.h, c.w
    local t, _, _, u = set(style().artSize)
    local k = (h - 2 * max(1, h * 0.07)) / GW.H * u
    local x0 = floor(h * 0.8 + 0.5)
    -- r135: below the bottom ornament band (not on it): the band shows about 0.45 of its depth under the frame
    local y0 = -floor(GW.railD * t * k * 0.45 + 2.5)
    local n = max(1, floor((w - 2 * x0 + 2) / max(1, step)))
    return x0, y0, max(1, floor(n / 2))
  end
  function A.level(f, lvs)
    local o = f.ccArtF
    if o and o.ccOn then o.lvl:SetText((tostring(lvs or ""):gsub(" $", ""))) end
  end
  -- bar colours from the art win over the usual ones
  local K = S.UFCol
  local oh, op, on = K.health, K.power, K.name
  K.name = function(f, ...)
    on(f, ...)
    local th = f.ccArtCol
    if not th then return end
    -- r131: the name takes a light tint of the art (keeps a class colour's hue, pulled toward the frame's colour)
    local r, g, b = f.nameText:GetTextColor()
    if type(r) ~= "number" or sec(r) then r, g, b = 1, 1, 1 end
    local h = th[1]
    local mr, mg, mb = r * 0.5 + h[1] * 0.3 + 0.2, g * 0.5 + h[2] * 0.3 + 0.2, b * 0.5 + h[3] * 0.3 + 0.2
    f.nameText:SetTextColor(min(1, mr), min(1, mg), min(1, mb))
    f.nameText:SetShadowColor(0, 0, 0, 0.9); f.nameText:SetShadowOffset(1, -1)
  end
  K.health = function(f, ...) oh(f, ...); if f.ccArtCol then A.color(f) end end
  K.power = function(f, ...) op(f, ...); if f.ccArtCol then A.color(f) end end
end)()

-- Edit mode (r114): unlocking hides the settings window, plays the CCFrames logo intro (logo fades and
-- grows in at the middle of the screen, holds, then flies up into a small see-through box) and shows the
-- box: grid on/off, snap to grid, grid size, test mode, "Lock & open settings". Locking plays the logo out.
;(function()
  local E = {}
  S.UFEdit = E
  local LOGO = UI.MEDIA .. "UI\\ccframes_logo"
  local box, intro
  local function ease(t) return 1 - (1 - t) * (1 - t) end
  local function stopIntro() if intro then intro:SetScript("OnUpdate", nil); intro:Hide() end end
  local function makeIntro()
    intro = CreateFrame("Frame", "CC_UF_EditIntro", UIParent)
    intro:SetSize(640, 160); intro:SetFrameStrata("FULLSCREEN_DIALOG")
    -- r115: the big (1024x256) description logo, so the intro stays sharp at full size
    intro.tex = intro:CreateTexture(nil, "ARTWORK"); intro.tex:SetAllPoints(); intro.tex:SetTexture(LOGO .. "_big")
    intro:Hide()
  end
  local function boxLogoPos()
    -- where the box's logo sits, as an offset from the screen centre (for the fly-in)
    local bx, by = box.logo:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if not bx or not ux then return 0, 300 end
    local s = box.logo:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return bx * s - ux, by * s - uy
  end
  -- play(kind): "in" = centre -> box, "out" = box -> grows + fades
  local function play(kind, done)
    if not intro then makeIntro() end
    local tx, ty = boxLogoPos()
    local small = 256 / 640
    local t = 0
    intro:SetAlpha(0); intro:Show()
    local function at(x, y, sc, a)
      intro:SetScale(sc); intro:ClearAllPoints(); intro:SetPoint("CENTER", UIParent, "CENTER", x / sc, y / sc); intro:SetAlpha(a)
    end
    intro:SetScript("OnUpdate", function(_, el)
      t = t + el
      if kind == "in" then
        if t < 0.45 then local k = ease(t / 0.45); at(0, 40, 0.55 + 0.5 * k, k)          -- fade + grow in
        elseif t < 1.25 then local k = (t - 0.45) / 0.8; at(0, 40, 1.05 - 0.05 * k, 1)  -- hold, settle
        elseif t < 1.8 then
          local k = ease((t - 1.25) / 0.55)
          local x = (t - 1.25) / 0.55                                                    -- crossfade at the end:
          local cf = x > 0.65 and min(1, (x - 0.65) / 0.35) or 0                         -- the box's own small logo
          at(tx * k, 40 + (ty - 40) * k, 1 + (small - 1) * k, 1 - cf)                    -- fly into the box
          if box then box:SetAlpha(k); box.logo:SetAlpha(cf) end
        else stopIntro(); if box then box:SetAlpha(1); box.logo:SetAlpha(1) end; if done then done() end end
      else
        if t < 0.5 then local k = ease(t / 0.5); at(tx, ty + 30 * k, small * (1 + 0.6 * k), 1 - k)
        else stopIntro(); if done then done() end end
      end
    end)
  end
  E.play = play
  local function makeBox()
    box = CreateFrame("Frame", "CC_UF_EditBox", UIParent, BACKDROP_T)
    box:SetSize(380, 236); box:SetFrameStrata("DIALOG"); box:SetClampedToScreen(true)
    box:SetPoint("TOP", UIParent, "TOP", 0, -90)
    box:SetMovable(true); box:EnableMouse(true); box:RegisterForDrag("LeftButton")
    box:SetScript("OnDragStart", box.StartMoving); box:SetScript("OnDragStop", box.StopMovingOrSizing)
    plainBackdrop(box)
    local g = UI:Theme().gold
    box:SetBackdropColor(0, 0, 0, 0.55); box:SetBackdropBorderColor(g[1], g[2], g[3], 0.8)
    box.logo = box:CreateTexture(nil, "ARTWORK"); box.logo:SetSize(256, 64); box.logo:SetPoint("TOP", 0, -6); box.logo:SetTexture(LOGO .. "_small")   -- r116: no tagline, made for 256x64
    local info = UI:Text(box, "Edit mode - drag any frame. Right-click one for its settings.", "small", "CENTER")
    info:SetPoint("TOP", box.logo, "BOTTOM", 0, -2); info:SetWidth(356)
    box.grid = UI:Check(box, "Show grid", true, function(v) style().grid = v; if S.__ufShowGrid then S.__ufShowGrid(true) end end)
    box.grid:SetPoint("TOPLEFT", 14, -94)
    box.snap = UI:Check(box, "Snap to grid", false, function(v) style().snap = v end,
      "While on, a frame you drop lines its left and top edges up with the nearest grid lines.")
    box.snap:SetPoint("TOPLEFT", 190, -94)
    box.size = UI:Slider(box, 350, "Grid size", 8, 64, 4, 32, function(v)
      style().gridSize = v; if S.__ufShowGrid then S.__ufShowGrid(true) end
    end)
    box.size:SetPoint("TOPLEFT", 14, -124)
    box.test = UI:Button(box, "Test mode", 110, 24, function() S.UFSetTesting(not S.UFTesting()) end,
      "Fills every frame with made-up units so you can see where everything goes.")
    box.test:SetPoint("BOTTOMLEFT", 14, 14)
    box.lock = UI:PrimaryButton(box, "Lock & open settings", 200, 24, function()
      E.reopen = true
      S.UFSetUnlocked(false)
    end)
    box.lock:SetPoint("BOTTOMRIGHT", -14, 14)
    box:Hide()
  end
  function E.enter()
    if not box then makeBox() end
    local w = _G.CC_UnitFrames
    if w and w:IsShown() then w:Hide() end
    local st = style()
    box.grid:SetChecked(st.grid and true or false); box.snap:SetChecked(st.snap and true or false)
    box.size:SetValue(tonumber(st.gridSize) or 32)
    if box:IsShown() then return end
    box:SetAlpha(0); box.logo:SetAlpha(0); box:Show()
    play("in")
  end
  function E.leave()
    if not box or not box:IsShown() then
      if E.reopen then E.reopen = nil; S:ShowUnitFrames() end
      return
    end
    box.logo:SetAlpha(0)
    play("out", function() if E.reopen then E.reopen = nil; S:ShowUnitFrames() end end)
    box:Hide()
  end
end)()

-- Profiles (r112): G().ufProfiles[name] = { v, saved, style, units, totemBar, cdm } (account-wide like the
-- rest of G()). Export = "CCUF2!" + base64(deflate(serialized)) when C_EncodingUtil has them, else
-- "CCUF1!" + serialized. Import accepts both. Loading replaces style / units / totem bar / Cooldown
-- Manager settings (frame positions included); the master on/off switch stays as it is.
;(function()
  local function dcopy(t)
    if type(t) ~= "table" then return t end
    local o = {}
    for k, v in pairs(t) do if type(k) == "string" or type(k) == "number" then o[k] = dcopy(v) end end
    return o
  end
  local PARTS = { "style", "units", "totemBar", "cdm" }
  local P = {}
  S.UFProf = P
  function P.list()
    local g = G(); g.ufProfiles = type(g.ufProfiles) == "table" and g.ufProfiles or {}
    return g.ufProfiles
  end
  function P.snapshot()
    local d = store()
    local snap = { v = 1, saved = time and time() or 0 }
    for _, k in ipairs(PARTS) do snap[k] = dcopy(d[k]) end
    return snap
  end
  function P.save(name)
    name = S.Trim and S.Trim(name or "") or (name or "")
    if name == "" then return nil, "Give the profile a name." end
    P.list()[name] = P.snapshot()
    return true
  end
  function P.load(name)
    local p = P.list()[name]
    if type(p) ~= "table" then return nil, "No profile called \"" .. tostring(name) .. "\"." end
    if combat() then return nil, "Can't switch profiles during a fight." end
    local d = store()
    for _, k in ipairs(PARTS) do if type(p[k]) == "table" then d[k] = dcopy(p[k]) end end
    d.fontsMoved = true; d.animMoved = true
    G().ufProfileOn = name
    S.UFApply()
    if S.RefreshUnitFrames then S:RefreshUnitFrames() end
    return true
  end
  function P.delete(name) P.list()[name] = nil end
  function P.export(name)
    local p = name and P.list()[name] or P.snapshot()
    local out = { name = name }
    for k, v in pairs(p) do out[k] = v end
    local raw = S.Ser.Serialize(out)
    local E = C_EncodingUtil
    if E and E.CompressString and E.EncodeBase64 then
      local ok, packed = pcall(function() return E.EncodeBase64(E.CompressString(raw)) end)
      if ok and type(packed) == "string" and packed ~= "" then return "CCUF2!" .. packed end
    end
    return "CCUF1!" .. raw
  end
  function P.decode(text)
    text = tostring(text or ""):gsub("%s", "")
    local kind, body = text:match("^CCUF(%d)!(.+)$")
    if not kind then return nil, "That isn't a Command Center unit frame profile (it should start with CCUF)." end
    local raw = body
    if kind == "2" then
      local E = C_EncodingUtil
      if not (E and E.DecodeBase64 and E.DecompressString) then return nil, "This game can't unpack that profile." end
      local ok, r = pcall(function() return E.DecompressString(E.DecodeBase64(body)) end)
      if not ok or type(r) ~= "string" then return nil, "The profile text is damaged (copy all of it)." end
      raw = r
    end
    local t = S.Ser.Deserialize(raw)
    if type(t) ~= "table" or type(t.units) ~= "table" or type(t.style) ~= "table" then
      return nil, "The profile text is damaged (copy all of it)."
    end
    local clean = { v = 1, saved = time and time() or 0 }
    for _, k in ipairs(PARTS) do if type(t[k]) == "table" then clean[k] = t[k] end end
    return clean, type(t.name) == "string" and t.name or nil
  end

  -- window (DIALOG strata like the shared Command Center dialogs; front() raises the shared dialog it
  -- just opened above this window - r113, they used to open behind it)
  local w
  local function front()
    for _, n in ipairs({ "CC_Confirm", "CC_Prompt", "CC_Copy" }) do
      local d = _G[n]
      if d and d:IsShown() then d:SetFrameStrata("FULLSCREEN_DIALOG"); d:Raise() end
    end
  end
  local function refresh()
    if not w then return end
    local names = {}
    for n in pairs(P.list()) do names[#names + 1] = n end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    local cur = G().ufProfileOn
    for i, row in ipairs(w.rows) do
      local n = names[i]
      row:SetShown(n ~= nil)
      if n then
        row.name = n
        row.label:SetText((n == cur) and ("|cffffd100" .. n .. "|r  |cffaaaaaa(in use)|r") or n)
      end
    end
    w.child:SetHeight(max(10, #names * 28))
    w.empty:SetShown(#names == 0)
  end
  function S.UFProfiles()
    if not w then
      w = UI:Window("CC_UF_Profiles", "Unit frame profiles", 520, 440)
      local note = UI:Text(w, "|cffaaaaaaProfiles are shared by every character on this account. Export gives a text you can import on another account.|r", "small")
      note:SetPoint("TOPLEFT", 16, -40); note:SetWidth(488); note:SetJustifyH("LEFT")
      w.nameBox = UI:Edit(w, 250, 24, "Profile name...")
      w.nameBox:SetPoint("TOPLEFT", 16, -72)
      local saveB = UI:PrimaryButton(w, "Save current setup", 150, 24, function()
        local n = w.nameBox:GetText()
        local function doSave()
          local ok, why = P.save(n)
          if ok then G().ufProfileOn = S.Trim and S.Trim(n) or n; S:Print("Unit frames: profile saved - " .. n); refresh()
          else UI:Alert(why); front() end
        end
        if P.list()[S.Trim and S.Trim(n) or n] then UI:Confirm("Replace the profile \"" .. n .. "\" with your current setup?", doSave, "Replace"); front()
        else doSave() end
      end, "Saves everything on every tab (all frames, their positions, the Style tab, the totem bar).")
      saveB:SetPoint("LEFT", w.nameBox, "RIGHT", 8, 0)
      local sf, child = UI:Scroll(w, 488, 270)
      sf:SetPoint("TOPLEFT", 16, -108)
      w.child = child
      w.empty = UI:Text(child, "|cffaaaaaaNo profiles yet - type a name above and save your current setup.|r", "small")
      w.empty:SetPoint("TOPLEFT", 4, -6)
      w.rows = {}
      for i = 1, 40 do
        local row = CreateFrame("Frame", nil, child)
        row:SetHeight(26); row:SetPoint("TOPLEFT", 0, -(i - 1) * 28); row:SetPoint("RIGHT", child, "RIGHT", 0, 0)
        row.label = UI:Text(row, "", "normal"); row.label:SetPoint("LEFT", 4, 0); row.label:SetWidth(200); row.label:SetJustifyH("LEFT")
        local del = UI:Button(row, "Delete", 60, 22, function()
          local n = row.name
          UI:Confirm("Delete the profile \"" .. n .. "\"?", function()
            P.delete(n); if G().ufProfileOn == n then G().ufProfileOn = nil end; refresh()
          end, "Delete"); front()
        end)
        del:SetPoint("RIGHT", -2, 0)
        local exp = UI:Button(row, "Export", 64, 22, function()
          UI:CopyBox("Export: " .. row.name, P.export(row.name)); front()
        end, "Text you can paste into Profiles > Import on another account.")
        exp:SetPoint("RIGHT", del, "LEFT", -4, 0)
        local load = UI:PrimaryButton(row, "Load", 60, 22, function()
          local n = row.name
          UI:Confirm("Load \"" .. n .. "\"? Your current setup is replaced (save it first if you want to keep it).", function()
            local ok, why = P.load(n)
            if ok then S:Print("Unit frames: profile loaded - " .. n); refresh() else UI:Alert(why); front() end
          end, "Load"); front()
        end)
        load:SetPoint("RIGHT", exp, "LEFT", -4, 0)
        row:Hide()
        w.rows[i] = row
      end
      local imp = UI:Button(w, "Import...", 110, 24, function()
        UI:CopyBox("Import a unit frame profile", "", function(text)
          local prof, nameOrWhy = P.decode(text)
          if not prof then UI:Alert(nameOrWhy); front() return end
          UI:Prompt("Name for the imported profile:", nameOrWhy or "Imported", function(n)
            n = S.Trim and S.Trim(n or "") or (n or "")
            if n == "" then return end
            P.list()[n] = prof
            S:Print("Unit frames: profile imported - " .. n .. ". Press Load to use it.")
            refresh()
          end); front()
        end); front()
      end, "Paste a profile exported on another account (or shared by a friend).")
      imp:SetPoint("BOTTOMLEFT", 16, 16)
      local expNow = UI:Button(w, "Export current setup", 160, 24, function()
        UI:CopyBox("Export: current setup", P.export(nil)); front()
      end)
      expNow:SetPoint("LEFT", imp, "RIGHT", 8, 0)
    end
    refresh()
    w:Show(); w:Raise()
  end
end)()

-- Reload prompt (r110): ReloadUI() is blocked for addons on Forever (ADDON_ACTION_BLOCKED "Reload()"), so
-- the "Reload now" button has an invisible secure macro button on top that runs /reload from your click.
;(function()
  local dlg
  function S.UFAskReload(msg)
    if combat() then S:Print(msg .. " Type /reload when the fight is over.") return end
    if not dlg then
      dlg = UI:Window("CC_UF_ReloadAsk", "Reload?", 340, 150)
      dlg:SetFrameStrata("FULLSCREEN_DIALOG")
      dlg.msg = UI:Text(dlg, "", "normal"); dlg.msg:SetPoint("TOPLEFT", 16, -42); dlg.msg:SetWidth(308); dlg.msg:SetJustifyH("LEFT")
      local go = UI:Button(dlg, "Reload now", 120, 24, function() end)
      go:SetPoint("BOTTOMLEFT", 16, 14)
      local sec = CreateFrame("Button", "CC_UF_ReloadBtn", go, "SecureActionButtonTemplate")
      sec:SetAllPoints(go); sec:SetFrameLevel(go:GetFrameLevel() + 5)
      sec:RegisterForClicks("AnyUp", "AnyDown")
      sec:SetAttribute("type", "macro"); sec:SetAttribute("macrotext", "/reload")
      dlg.sec = sec
      local later = UI:Button(dlg, "Later", 90, 24, function() dlg:Hide() end)
      later:SetPoint("BOTTOMRIGHT", -16, 14)
    end
    dlg.msg:SetText(msg .. "\n\n|cffaaaaaaReload now, or type /reload later.|r")
    dlg:Show()
  end
end)()

-- Hover preview (r108): in a look dropdown (d.ccPreview), resting the mouse on a choice shows it on the
-- frames straight away; moving off the list / closing it without a click puts the old choice back, a click
-- keeps it. Works by wrapping UI:Menu (only menus opened from a ccPreview dropdown are touched) and running
-- the menu item's own func (= SetValue + the dropdown's setter). Out of combat only.
S.UFPrev = {}
;(function()
  local P = S.UFPrev
  local origMenu = UI.Menu
  local function findMenu(anchor)
    if P.menu and P.menu.buttons then return P.menu end
    for _, c in ipairs({ UIParent:GetChildren() }) do
      local ok, isMenu = pcall(function()
        if type(rawget(c, "buttons")) ~= "table" then return false end
        local _, rel = c:GetPoint(1)
        return rel == anchor
      end)
      if ok and isMenu then P.menu = c; return c end
    end
  end
  local function restore()
    local st = P.st
    if not st or st.done then return end
    P.st = nil
    if st.cur ~= st.old and st.oldItem and st.oldItem.func then pcall(st.oldItem.func) end
  end
  P.restore = restore
  local function show(st, it)
    if st.done or combat() then return end
    if st.cur == it then return end
    st.cur = it
    if it.func then pcall(it.func) end
  end
  function UI:Menu(anchor, items)
    origMenu(self, anchor, items)
    if not (type(anchor) == "table" and anchor.ccPreview and type(items) == "table") or combat() then return end
    local m = findMenu(anchor)
    if not m then return end
    local old
    for _, it in ipairs(items) do if it.checked then old = it end end
    if not old then return end                  -- current value not in the list: no safe way back
    local st = { old = old, oldItem = old, cur = old }
    P.st = st
    if not m.ccPrevHooked then
      m.ccPrevHooked = true
      m:HookScript("OnHide", function() restore() end)
    end
    for i, it in ipairs(items) do
      local mb = m.buttons[i]
      if mb and not it.title and not it.disabled and not it.keep then
        local enter, leave, click = mb:GetScript("OnEnter"), mb:GetScript("OnLeave"), mb:GetScript("OnClick")
        mb:SetScript("OnEnter", function(b, ...)
          if enter then enter(b, ...) end
          st.hover = it
          show(st, it)
        end)
        mb:SetScript("OnLeave", function(b, ...)
          if leave then leave(b, ...) end
          if st.hover == it then st.hover = nil end
          C_Timer.After(0.15, function()
            if P.st == st and not st.hover and not st.done then show(st, st.old) end
          end)
        end)
        mb:SetScript("OnClick", function(b, ...)
          st.done = true
          if P.st == st then P.st = nil end
          if click then click(b, ...) end
        end)
      end
    end
  end
end)()

function S:ShowUnitFrames(key, tab)
  if key and LABEL[key] then cur = key end
  if not win then buildWindow() end
  win:Show(); win:Raise()
  if tab then win.tabs:Select((win.ufOld2New and win.ufOld2New[tab]) or tab) end
  S:RefreshUnitFrames()
end
function S:HideUnitFrames() if win then win:Hide() end end
function S.UFSearch(q) if win and win.doSearch then return win.doSearch(q) end end

-- what the game gives us for auras on your target (for bug reports)
function S.UFDebug()
  local P = function(m) S:Print("|cffaaaaaa[frames]|r " .. m) end
  local u = UnitExists("target") and "target" or "player"
  P("checking " .. u .. (u == "player" and " (target something to check it)" or "") .. ", in combat: " .. tostring(combat() and true or false))
  local have = {}
  for _, w in ipairs(AURA_WAYS) do have[#have + 1] = w[1] .. (wayAvailable(w[1]) and "+" or "-") end
  P("aura APIs: " .. table.concat(have, "  "))
  for _, filter in ipairs({ "HELPFUL", "HARMFUL", "HARMFUL|PLAYER", "HELPFUL|PLAYER" }) do
    local parts = {}
    for _, w in ipairs(AURA_WAYS) do
      if wayAvailable(w[1]) then
        local ok, list = pcall(w[2], u, filter, 8)
        if not ok then parts[#parts + 1] = w[1] .. "=ERR " .. tostring(list):sub(1, 80)
        else
          local n = list and #list or 0
          local nm = ""
          if n > 0 then
            local v = nth(list[1].d, "name")
            nm = sec(v) and " (hidden name)" or (" (" .. tostring(v) .. ")")
          end
          parts[#parts + 1] = w[1] .. "=" .. n .. nm
        end
      end
    end
    P(filter .. ": " .. table.concat(parts, ", "))
  end
  local f = single[u]
  if f then
    local c = f.cfg
    local shown = 0
    for _, b in ipairs(f.debuffs) do if b:IsShown() then shown = shown + 1 end end
    local sb = 0
    for _, b in ipairs(f.buffs) do if b:IsShown() then sb = sb + 1 end end
    P(string.format("frame: buffs %s (%d made, %d shown) at %s, debuffs %s (%d made, %d shown) at %s, only mine %s",
      tostring(c.buffs), #f.buffs, sb, tostring(c.buffPos), tostring(c.debuffs), #f.debuffs, shown, tostring(c.debuffPos), tostring(c.auraMine)))
    local hp = UnitHealth(u)
    P("health value hidden by the game: " .. tostring(sec(hp)) .. ", percent API: " .. tostring(UnitHealthPercent ~= nil) .. ", text: " .. tostring(f.hpText:GetText()))
  end
  local ti = auraTemplate()
  local pl = NP.plate("target")
  local npl = UnitExists("target") and NP.collect("target")
  P("nameplate copy: " .. (store().cdm.nameplates and "on" or "off") .. ", target plate " .. (pl and "found" or "|cffff9933not found (nameplates off / too far?)|r")
    .. ", aura buttons on it " .. tostring(npl and #npl or 0) .. ", ability timers " .. (function() local k = 0; for _, t in pairs(NP.timers) do if t.exp > GetTime() then k = k + 1 end end; return k end)()
    .. ", Blizzard timers caught " .. (function() local k = 0; for _ in pairs(NP.last) do k = k + 1 end; return k end)()
    .. (NP.info.err and (", error: " .. NP.info.err:sub(1, 100)) or ""))
  do
    local u2 = UnitExists("target") and "target" or "player"
    local function show(...)
      local o, n = {}, 0
      for i = 1, select("#", ...) do if select(i, ...) ~= nil then n = i end end
      for i = 1, n do local v = select(i, ...); o[#o + 1] = sec(v) and "<hidden>" or tostring(v) end
      return n == 0 and "nothing" or table.concat(o, " | ")
    end
    P("names (" .. u2 .. "): UnitName -> " .. show(try(UnitName, u2)) .. ";  UnitFullName -> " .. show(try(UnitFullName, u2))
      .. ";  GetUnitName(true) -> " .. show(GetUnitName and try(GetUnitName, u2, true)) .. ";  shown: " .. tostring(S.UFFullName(u2) or "main name only"))
  end
  do
    local tf = single.target
    local cl = UnitExists("target") and try(UnitClassification, "target")
    local o = tf and tf.ccElite
    local ct = UnitExists("target") and try(UnitCreatureType, "target")
    P("target: classification " .. (cl == nil and "none" or (sec(cl) and "<hidden>" or tostring(cl))) .. ", type " .. (ct == nil and "none" or (sec(ct) and "<hidden>" or tostring(ct)))
      .. " -> " .. tostring(tf and S.UFElite.classOf(tf) or "?") .. ";  glow " .. ((o and o:IsShown() and o.ccArt) or "off")
      .. ";  portrait " .. tostring(tf and tf.cfg and tf.cfg.portrait) .. ", side " .. tostring(tf and tf.cfg and tf.cfg.side))
  end
  -- r130: target of target text check (Artistic theme)
  do
    local tt = single.targettarget
    if tt then
      local function lv(x) return x and x.GetFrameLevel and tostring(x:GetFrameLevel()) or "-" end
      local function tx(fs) local ok, v = pcall(fs.GetText, fs); if not ok then return "?" end if sec(v) then return "hidden" end return tostring(v) end
      local function sh(x) return (x and x.IsVisible and x:IsVisible()) and "vis" or "hid" end
      local a = tt.ccArtF
      P("target of target: name '" .. tx(tt.nameText) .. "' " .. sh(tt.nameText) .. " a" .. tostring(tt.nameText:GetAlpha()) .. ", hp '" .. tx(tt.hpText) .. "' " .. sh(tt.hpText)
        .. "; levels frame " .. lv(tt) .. " health " .. lv(tt.health) .. " art " .. lv(a) .. " texts " .. lv(tt.ui) .. " glow " .. lv(tt.ccElite) .. " hl " .. lv(tt.hl)
        .. "; art " .. tostring(a and a.ccOn) .. " " .. tostring(a and a.ccDesign) .. "; size " .. floor(tt:GetWidth() or 0) .. "x" .. floor(tt:GetHeight() or 0)
        .. ", health " .. floor(tt.health:GetWidth() or 0) .. "x" .. floor(tt.health:GetHeight() or 0))
    end
  end
  P("nameplate icons: aura IDs " .. (NP.info.ids and "readable" or "hidden") .. ", icon pictures " .. tostring(NP.info.tex or "not seen yet")
    .. "  (" .. ((NP.info.ids and "timers follow the aura") or (NP.info.tex == "readable" and "your timers follow the picture") or "timers follow the icon order") .. ")")
  local lc = NP.lastCast
  P("last cast: " .. (lc and (tostring(lc.name) .. " (" .. tostring(lc.spell) .. "), duration " .. (lc.dur and (lc.dur .. " s from " .. lc.src) or "|cffff9933unknown - no timer|r")
    .. ", matched to an icon: " .. tostring(lc.matched)) or "none yet"))
  local ci = CDM.info
  local en = C_CVar and C_CVar.GetCVarBool and C_CVar.GetCVarBool("cooldownViewerEnabled")
  P("Cooldown Manager: " .. (CDM.viewer() and "found" or "|cffff5555not found|r") .. ", enabled " .. tostring(en) .. ", use in combat " .. tostring(store().cdm.on)
    .. ", tracked icons " .. #CDM.items() .. ", last fight placed " .. tostring(ci.placed) .. (ci.err and (", error: " .. ci.err:sub(1, 120)) or ""))
  for i, it in ipairs(CDM.items()) do
    if i <= 8 then
      local sp, self = CDM.spell(it)
      local nm = sp and C_Spell and C_Spell.GetSpellName and try(C_Spell.GetSpellName, sp)
      P("  icon " .. i .. ": " .. tostring(nm or sp or "?") .. " -> " .. CDM.unit(sp, self) .. (it:IsShown() and "" or " (hidden now)"))
    end
  end
  local nl = 0
  for _ in pairs(S.db.global.ufLearned or {}) do nl = nl + 1 end
  P("in combat: remembered auras + your casts (" .. nl .. " of your spells learned so far)")
  P("game-drawn auras in combat: " .. (ti.ok and ("on - template size " .. floor(ti.w) .. "x" .. floor(ti.h) .. ", parts: " .. (#ti.parts > 0 and table.concat(ti.parts, ", ") or "none listed"))
    or ("|cffff5555not available|r (" .. tostring(ti.err):sub(1, 120) .. ")")))
  local diag = S.db.global.ufAuraDiag
  for _, du in ipairs({ "target", "player" }) do
    local d = diag and diag[du]
    if d then
      P("|cffffd100last in-fight check on " .. du .. (d.at and time and (" (" .. floor((time() - d.at) / 60) .. " min ago)") or "") .. ":|r")
      for _, line in ipairs(d.lines or {}) do P("  " .. line) end
    end
  end
  if not diag then P("no in-fight check yet - fight something with buffs/debuffs on it, then run this again") end
  local nc = 0
  for _ in pairs(auraCache[u] or {}) do nc = nc + 1 end
  P("auras the game announced on " .. u .. " since targeting: " .. nc)
  for k, v in pairs(auraInfo.method) do P("aura way used for " .. k .. ": " .. v) end
  for k, v in pairs(auraInfo.err) do P("aura error " .. k .. ": " .. v:sub(1, 160)) end
  local any = false
  for k, v in pairs(lastErr) do any = true; P("|cffff6666error|r in " .. k .. " (" .. floor(GetTime() - v.at) .. "s ago): " .. v.msg:sub(1, 200)) end
  if not any then P("no update errors") end
end

S:AddCommand("frames", "[unlock|test|on|off|debug]", "Unit frames: settings, move them, test mode", function(rest)
  rest = (rest or ""):lower()
  if rest == "unlock" or rest == "move" then
    if not store().on then S:Print("Unit frames are off - /ccenter frames on") return end
    S.UFSetUnlocked(not unlocked)
  elseif rest == "test" then
    if not store().on then S:Print("Unit frames are off - /ccenter frames on") return end
    S.UFSetTesting(not testing)
  elseif rest == "debug" then S.UFDebug()
  elseif rest == "on" then store().on = true; S.UFApply(); S:Print("Unit frames on.")
  elseif rest == "off" then store().on = false; S.UFSetUnlocked(false); S.UFApply(); S:Print("Unit frames off - the game's frames come back after /reload.")
  else S:ShowUnitFrames() end
end)

-- for tests
S.__UF = { castHolders = castHolders, cfg = cfg, store = store, frames = frames, single = single, groupKids = groupKids, holders = holders, byUnit = byUnit,
  UpdateAll = UpdateAll, Layout = function(f) return Layout(f) end, fmtValue = fmtValue, pending = pending,
  build = function() buildAll() end, events = ev, getWin = function() return win end }
