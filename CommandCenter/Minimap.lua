-- Minimap: the game's minimap drawn in Command Center's look. Same theme colours as every
-- other window (re-colours live with the theme / custom colours), any shape from square to
-- round (the same roundness steps as BiB slots), a size slider, a zone name bar, a clock +
-- coordinates bar, mouse-wheel zoom with auto zoom-out, addon buttons themed to match (and
-- optionally only shown on mouse-over), and it can be moved.
--
-- Plays nicely with:
--  * border mode / dock: everything stays anchored to UIParent, so the border bar still
--    pushes the minimap out of its way;
--  * Plugins / Button Box: addon buttons they hide stay hidden (we only change alpha / art);
--  * LibDBIcon buttons, GatherMate2, Questie and anything using HereBeDragons: GetMinimapShape()
--    reports ROUND or SQUARE, LibDBIcon buttons are re-placed when the shape changes;
--  * Questicus (pins + its minimap button) and StinkyFart (its button): they use
--    CommandCenter.MinimapEdge() / CommandCenter:OnMinimapChange() to sit on the edge;
--  * Questicus Maps / any world map: the zone bar opens the map with ToggleWorldMap();
--  * the game's clock alarm (TimeManager): our clock pulses when the alarm goes off.
-- Only out of combat for anything that moves or scales a Blizzard frame.
local _, S = ...
if S.ModuleRev then S:ModuleRev("Minimap", 9) end
local UI = S.UI

local MEDIA = UI.MEDIA
local WHITE = "Interface\\Buttons\\WHITE8x8"
local ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"   -- the game's own round mask (when we hand it back)
-- corner radius of Media\UI\rmask0-5 as a share of the full width (0 = square, .5 = circle)
local CORNER = { [0] = 0, 0.107, 0.187, 0.293, 0.4, 0.5 }
local ROUND_NAMES = { [0] = "Square", "Slightly rounded", "Rounded", "Very rounded", "Almost round", "Round" }

local DEF = {
  on = true, round = 5, scale = 1, ring = true, accent = true,
  zone = true, clock = true, coords = true,
  wheel = true, hideZoom = true, hideWorldBtn = true, autoZoom = 15,
  skinButtons = true, fadeButtons = false,
  tidy = true,        -- the game's mail / tracking / calendar buttons sit in the bars
  drawer = true,      -- Button Box docked to the minimap, opened from the zone bar; addon icons go in it
  hideDupCoords = true,
}
local function G() return S.db.global end
local function cfg()
  local g = G()
  if type(g.mmSkin) ~= "table" then g.mmSkin = {} end
  local c = g.mmSkin
  for k, v in pairs(DEF) do if c[k] == nil then c[k] = v end end
  return c
end
S.MinimapCfg = cfg
local function active() return S.db and Minimap and cfg().on and true or false end
local function roundK()
  local k = tonumber(cfg().round) or 5
  return math.max(0, math.min(5, math.floor(k + 0.5)))
end
local function inCombat() return InCombatLockdown and InCombatLockdown() end

---------------------------------------------------------------------------
-- Shape API (used by our minimap button, Questicus, StinkyFart, LibDBIcon...)
---------------------------------------------------------------------------
-- offset (x, y) from the minimap centre of a point on its edge at angleDeg, pushed out by pad px.
-- Round: exactly the old "radius + pad" circle, so nothing moves for round minimaps.
function S.MinimapEdge(angleDeg, pad)
  local w = ((Minimap and Minimap:GetWidth()) or 140) / 2
  pad = pad or 0
  local a = math.rad(angleDeg or 0)
  local c, s = math.cos(a), math.sin(a)
  local k = active() and roundK() or 5
  local h = w + pad
  if k >= 5 then return c * h, s * h end
  local rc = CORNER[k] * 2 * w + pad
  local m = math.max(math.abs(c), math.abs(s))
  if m < 1e-6 then return 0, 0 end
  local t = h / m
  local x, y = c * t, s * t
  local inner = h - rc
  if rc > 0 and math.abs(x) > inner and math.abs(y) > inner then
    local cx, cy = (x > 0 and inner or -inner), (y > 0 and inner or -inner)
    local b = c * cx + s * cy
    local disc = b * b - (cx * cx + cy * cy - rc * rc)
    if disc < 0 then disc = 0 end
    t = b + math.sqrt(disc)
    x, y = c * t, s * t
  end
  return x, y
end
function S.MinimapShapeName() return (not active() or roundK() >= 5) and "ROUND" or "SQUARE" end

local listeners = {}
-- fn() is called whenever the shape / size / position changes (re-place your minimap button)
function S:OnMinimapChange(fn) if type(fn) == "function" then listeners[#listeners + 1] = fn end end
local function fireChange()
  for _, fn in ipairs(listeners) do local ok, err = pcall(fn); if not ok and S.report then S.report(err) end end
  -- LibDBIcon buttons ask GetMinimapShape() when they are placed: place them again
  local DBI = LibStub and LibStub.GetLibrary and LibStub:GetLibrary("LibDBIcon-1.0", true)
  if DBI and DBI.GetButtonList and DBI.Refresh then
    for _, name in ipairs(DBI:GetButtonList() or {}) do pcall(DBI.Refresh, DBI, name) end
  end
end
S.MinimapChanged = fireChange

-- the global most minimap code asks (LibDBIcon, HereBeDragons pins, Questicus lines)
local prevShape = _G.GetMinimapShape
_G.GetMinimapShape = function()
  if active() then return S.MinimapShapeName() end
  if prevShape then return prevShape() end
  return "ROUND"
end

---------------------------------------------------------------------------
-- The game's art we hide (both the classic names and the newer ones)
---------------------------------------------------------------------------
local function pick(...)
  local out = {}
  for i = 1, select("#", ...) do
    local f = select(i, ...)
    local ok, o = pcall(f)
    if ok and type(o) == "table" then out[#out + 1] = o end
  end
  return out
end
local function cluster() return _G.MinimapCluster end
local ART = {   -- plain art: hidden whenever the look is on
  border = function() return pick(
    function() return _G.MinimapBorder end,
    function() return _G.MinimapCompassTexture end,
    function() return _G.MinimapNorthTag end) end,
  -- containers that also hold buttons: only their own textures go
  top = function() return pick(
    function() return _G.MinimapBorderTop end,
    function() return cluster() and cluster().BorderTop end) end,
  zone = function() return pick(
    function() return _G.MinimapZoneTextButton end,
    function() return cluster() and cluster().ZoneTextButton end) end,
  zoom = function() return pick(
    function() return _G.MinimapZoomIn end, function() return _G.MinimapZoomOut end,
    function() return Minimap.ZoomIn end, function() return Minimap.ZoomOut end,
    function() return Minimap.ZoomHitArea end) end,
  world = function() return pick(
    function() return _G.MiniMapWorldMapButton end,
    function() return _G.MinimapToggleButton end) end,
  clock = function() return pick(function() return _G.TimeManagerClockButton end) end,
}
local hidden = {}   -- obj -> { alpha, mouse } or { regions = {tex -> alpha} }
local function hideObj(o)
  if hidden[o] or not o.SetAlpha then return end
  local rec = { alpha = o:GetAlpha() }
  if o.IsMouseEnabled and o.EnableMouse then rec.mouse = o:IsMouseEnabled(); pcall(o.EnableMouse, o, false) end
  hidden[o] = rec
  o:SetAlpha(0)
end
local function hideRegions(o)
  if hidden[o] or not o.GetRegions then return end
  local rec = { regions = {} }
  for _, r in ipairs({ o:GetRegions() }) do
    if r.GetObjectType and r:GetObjectType() == "Texture" then rec.regions[r] = r:GetAlpha(); r:SetAlpha(0) end
  end
  hidden[o] = rec
end
local function showObj(o)
  local rec = hidden[o]
  if not rec then return end
  hidden[o] = nil
  if rec.regions then
    for r, a in pairs(rec.regions) do r:SetAlpha(a or 1) end
  else
    o:SetAlpha(rec.alpha or 1)
    if rec.mouse ~= nil and o.EnableMouse then pcall(o.EnableMouse, o, rec.mouse) end
  end
end
local function setArt(kind, hide, regionsOnly)
  for _, o in ipairs(ART[kind]()) do
    if hide then
      local kind = o.GetObjectType and o:GetObjectType()
      if kind == "Texture" then hideObj(o)                -- classic: MinimapBorder / MinimapBorderTop are plain textures
      elseif regionsOnly or (kind == "Frame" and o.GetNumChildren and o:GetNumChildren() > 0) then hideRegions(o)
      else hideObj(o) end
    else showObj(o) end
  end
end

---------------------------------------------------------------------------
-- Our own pieces: back plate + shadow, themed ring, zone bar, info bar
---------------------------------------------------------------------------
local back, ring, zoneBar, infoBar, mover
local MAP_GAP = 5

local function pvpColor(th)
  local pvp = GetZonePVPInfo and GetZonePVPInfo()
  if pvp == "sanctuary" then return 0.41, 0.8, 0.94
  elseif pvp == "arena" or pvp == "hostile" or pvp == "combat" then return 1, 0.25, 0.2
  elseif pvp == "friendly" then return 0.35, 1, 0.35
  elseif pvp == "contested" then return 1, 0.7, 0.1 end
  return th.text[1], th.text[2], th.text[3]
end

local function openWorldMap()
  if ToggleWorldMap then pcall(ToggleWorldMap)
  elseif _G.WorldMapFrame and ToggleFrame then pcall(ToggleFrame, _G.WorldMapFrame) end
end

local function buildPieces()
  if ring then return end
  -- shadow + plate under the map (a sibling one level below, so it draws behind the map)
  back = CreateFrame("Frame", "CC_MinimapBack", Minimap:GetParent() or UIParent)
  back:SetFrameStrata(Minimap:GetFrameStrata())
  back:SetFrameLevel(math.max(0, (Minimap:GetFrameLevel() or 1) - 1))
  back:SetPoint("CENTER", Minimap, "CENTER")
  back.shadow = back:CreateTexture(nil, "BACKGROUND", nil, -6)
  back.shadow:SetTexture(UI.ART.glow); back.shadow:SetVertexColor(0, 0, 0, 0.8)
  back.plate = back:CreateTexture(nil, "BACKGROUND", nil, -4)
  back:EnableMouse(false)

  -- ring over the map edge (below addon buttons, which sit at level +8)
  ring = CreateFrame("Frame", "CC_MinimapRing", Minimap)
  ring:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 2)
  ring:SetPoint("CENTER", Minimap, "CENTER")
  ring:EnableMouse(false)
  ring.accent = ring:CreateTexture(nil, "BORDER", nil, 1)
  ring.accent:SetPoint("CENTER")
  ring.edge = ring:CreateTexture(nil, "BORDER", nil, 2)
  ring.edge:SetPoint("CENTER")
  ring.shine = ring:CreateTexture(nil, "BORDER", nil, 3)   -- faint inner highlight along the top
  ring.shine:SetPoint("CENTER")

  -- zone name bar above the map
  zoneBar = CreateFrame("Button", "CC_MinimapZone", Minimap)
  zoneBar:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 6)
  zoneBar:SetHeight(20)
  zoneBar:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  zoneBar.text = UI:Text(zoneBar, "", nil, "CENTER")
  zoneBar.text:SetPoint("LEFT", 26, 0); zoneBar.text:SetPoint("RIGHT", -26, 0)
  -- a small slot at each end of both bars (mail | zone | box button, tracking | coords  clock | calendar)
  local function slot(bar, side)
    local f = CreateFrame("Frame", nil, bar)
    f:SetSize(18, 18); f:SetPoint(side, bar, side, side == "LEFT" and 2 or -2, 0)
    f:SetFrameLevel(bar:GetFrameLevel() + 3)
    return f
  end
  zoneBar.slotL, zoneBar.slotR = slot(zoneBar, "LEFT"), slot(zoneBar, "RIGHT")
  zoneBar.text:SetWordWrap(false)
  UI:Skin(zoneBar, function(self, th)
    UI.Flat(self, th.panel, 0.94, self.__hot and th.gold or th.edge, 1)
    self.text:SetTextColor(pvpColor(th))
  end)
  zoneBar:SetScript("OnClick", function(self, btn)
    if btn == "RightButton" then S:MinimapMenu2(self) else openWorldMap() end
  end)
  zoneBar:SetScript("OnEnter", function(self)
    self.__hot = true; UI.Flat(self, UI:Theme().panel, 0.94, UI:Theme().gold, 1)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    local zone = (GetRealZoneText and GetRealZoneText()) or ""
    local sub = (GetSubZoneText and GetSubZoneText()) or ""
    GameTooltip:AddLine(zone ~= "" and zone or ((GetMinimapZoneText and GetMinimapZoneText()) or ""), pvpColor(UI:Theme()))
    if sub ~= "" and sub ~= zone then GameTooltip:AddLine(sub, 1, 1, 1) end
    local pvp, _, faction = GetZonePVPInfo and GetZonePVPInfo()
    if pvp == "sanctuary" then GameTooltip:AddLine(SANCTUARY_TERRITORY or "(Sanctuary)", 0.41, 0.8, 0.94)
    elseif pvp == "friendly" and faction then GameTooltip:AddLine(FACTION_CONTROLLED_TERRITORY and FACTION_CONTROLLED_TERRITORY:format(faction) or faction, 0.35, 1, 0.35)
    elseif pvp == "hostile" and faction then GameTooltip:AddLine(FACTION_CONTROLLED_TERRITORY and FACTION_CONTROLLED_TERRITORY:format(faction) or faction, 1, 0.25, 0.2)
    elseif pvp == "contested" then GameTooltip:AddLine(CONTESTED_TERRITORY or "(Contested territory)", 1, 0.7, 0.1)
    elseif pvp == "combat" or pvp == "arena" then GameTooltip:AddLine(COMBAT_ZONE or "(Combat zone)", 1, 0.25, 0.2) end
    GameTooltip:AddLine("Click: world map   Right-click: minimap options", 0.7, 0.7, 0.7)
    GameTooltip:Show()
  end)
  zoneBar:SetScript("OnLeave", function(self)
    self.__hot = false; UI.Flat(self, UI:Theme().panel, 0.94, UI:Theme().edge, 1); GameTooltip:Hide()
  end)

  -- clock + coordinates under the map
  infoBar = CreateFrame("Frame", "CC_MinimapInfo", Minimap)
  infoBar:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 6)
  infoBar:SetHeight(20)
  infoBar.coords = CreateFrame("Button", nil, infoBar)
  infoBar.coords:SetPoint("TOPLEFT"); infoBar.coords:SetPoint("BOTTOMLEFT"); infoBar.coords:SetWidth(70)
  infoBar.coords.text = UI:Text(infoBar.coords, "", "small", "LEFT"); infoBar.coords.text:SetPoint("LEFT", 8, 0)
  infoBar.clock = CreateFrame("Button", nil, infoBar)
  infoBar.clock:SetPoint("TOPRIGHT"); infoBar.clock:SetPoint("BOTTOMRIGHT"); infoBar.clock:SetWidth(70)
  infoBar.clock.text = UI:Text(infoBar.clock, "", "small", "RIGHT"); infoBar.clock.text:SetPoint("RIGHT", -8, 0)
  UI:Skin(infoBar, function(self, th)
    UI.Flat(self, th.panel, 0.94, th.edge, 1)
    self.coords.text:SetTextColor(th.muted[1], th.muted[2], th.muted[3])
    self.clock.text:SetTextColor(th.text[1], th.text[2], th.text[3])
  end)
  infoBar.coords:SetScript("OnClick", function() openWorldMap() end)
  infoBar.coords:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM"); GameTooltip:AddLine("Where you are", 1, 0.82, 0)
    GameTooltip:AddLine("Map coordinates (x, y). Click: world map", 1, 1, 1); GameTooltip:Show()
  end)
  infoBar.coords:SetScript("OnLeave", function() GameTooltip:Hide() end)
  infoBar.clock:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  infoBar.clock:SetScript("OnClick", function(_, btn)
    if btn == "RightButton" then
      SetCVar("timeMgrUseLocalTime", GetCVar("timeMgrUseLocalTime") == "1" and "0" or "1")
    elseif TimeManager_Toggle then pcall(TimeManager_Toggle)
    elseif C_AddOns and C_AddOns.LoadAddOn then
      pcall(C_AddOns.LoadAddOn, "Blizzard_TimeManager"); if TimeManager_Toggle then pcall(TimeManager_Toggle) end
    end
  end)
  infoBar.clock:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    local h, m = GetGameTime()
    GameTooltip:AddLine("Clock", 1, 0.82, 0)
    GameTooltip:AddDoubleLine("Server time", string.format("%02d:%02d", h or 0, m or 0), 1, 1, 1, 1, 1, 1)
    GameTooltip:AddDoubleLine("Local time", date("%H:%M"), 1, 1, 1, 1, 1, 1)
    GameTooltip:AddLine("Click: stopwatch and alarm   Right-click: server / local time", 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
  end)
  infoBar.clock:SetScript("OnLeave", function() GameTooltip:Hide() end)
  infoBar.slotL, infoBar.slotR = slot(infoBar, "LEFT"), slot(infoBar, "RIGHT")
  -- more slots going left from the right end (day / night, anything else the game puts on the minimap)
  infoBar.rightSlots = { infoBar.slotR }
  function infoBar:RightSlot(i)
    local sl = self.rightSlots[i]
    if not sl then
      sl = CreateFrame("Frame", nil, self)
      sl:SetSize(18, 18); sl:SetFrameLevel(self:GetFrameLevel() + 3)
      sl:SetPoint("RIGHT", self:RightSlot(i - 1), "LEFT", -2, 0)
      self.rightSlots[i] = sl
    end
    return sl
  end
  infoBar.slotR2 = infoBar:RightSlot(2)
end

local function clockText()
  local useLocal = GetCVar and GetCVar("timeMgrUseLocalTime") == "1"
  local h24 = GetCVar and GetCVar("timeMgrUseMilitaryTime") == "1"
  local h, m
  if useLocal then h, m = tonumber(date("%H")), tonumber(date("%M")) else h, m = GetGameTime() end
  h, m = h or 0, m or 0
  if h24 then return string.format("%02d:%02d", h, m) end
  local ap = h >= 12 and "PM" or "AM"
  local h12 = h % 12; if h12 == 0 then h12 = 12 end
  return string.format("%d:%02d %s", h12, m, ap)
end
local function coordText()
  local CM = C_Map
  if not (CM and CM.GetBestMapForUnit and CM.GetPlayerMapPosition) then return "" end
  local map = CM.GetBestMapForUnit("player")
  local pos = map and CM.GetPlayerMapPosition(map, "player")
  if not pos then return "--" end
  local x, y
  if pos.GetXY then x, y = pos:GetXY() else x, y = pos.x, pos.y end
  if not x or not y or (x == 0 and y == 0) then return "--" end
  return string.format("%.1f, %.1f", x * 100, y * 100)
end
S.MinimapClockText, S.MinimapCoordText = clockText, coordText

local infoAcc = 0
local function infoUpdate(self, el)
  infoAcc = infoAcc + el
  if infoAcc < 0.2 then return end
  infoAcc = 0
  local c = cfg()
  if c.coords then self.coords.text:SetText(coordText()) end
  if c.clock then
    self.clock.text:SetText(clockText())
    -- the game's alarm went off (TimeManager flashes its own, now hidden, clock): pulse ours
    local tm = _G.TimeManagerClockButton
    if tm and tm.alarmFiring then
      local a = 0.55 + 0.45 * math.abs(math.sin(GetTime() * 4))
      self.clock.text:SetAlpha(a)
    else
      self.clock.text:SetAlpha(1)
    end
  end
end

local function updateZone()
  if not zoneBar then return end
  zoneBar.text:SetText((GetMinimapZoneText and GetMinimapZoneText()) or "")
  zoneBar.text:SetTextColor(pvpColor(UI:Theme()))
end

local function layoutPieces()
  local c = cfg()
  local k = roundK()
  local w, h = Minimap:GetWidth() or 140, Minimap:GetHeight() or 140
  back:SetSize(w + 10, h + 10)
  back.shadow:ClearAllPoints(); back.shadow:SetPoint("TOPLEFT", -16, 16); back.shadow:SetPoint("BOTTOMRIGHT", 16, -18)
  back.plate:SetAllPoints()
  back.plate:SetTexture(MEDIA .. "UI\\rmask" .. k)
  ring:SetSize(w + 10, h + 10)
  ring.edge:SetTexture(MEDIA .. "UI\\rring" .. k); ring.edge:SetSize(w + 6, h + 6)
  ring.accent:SetTexture(MEDIA .. "UI\\rring" .. k); ring.accent:SetSize(w + 10, h + 10)
  ring.shine:SetTexture(MEDIA .. "UI\\rring" .. k); ring.shine:SetSize(w - 2, h - 2)
  ring.edge:SetShown(c.ring); ring.shine:SetShown(c.ring)
  ring.accent:SetShown(c.ring and c.accent)
  back.plate:SetShown(c.ring)

  -- bars hug the shape: full width when square-ish, narrower when round
  local frac = (k >= 5 and 0.62) or (k >= 4 and 0.74) or (k >= 3 and 0.86) or 1
  local bw = math.floor(w * frac + 0.5)
  zoneBar:ClearAllPoints()
  zoneBar:SetPoint("BOTTOM", Minimap, "TOP", 0, MAP_GAP + (c.ring and 3 or 0))
  zoneBar:SetWidth(math.max(90, bw))
  zoneBar:SetShown(c.zone or c.drawer or c.tidy)
  zoneBar.text:SetShown(c.zone)
  infoBar:ClearAllPoints()
  infoBar:SetPoint("TOP", Minimap, "BOTTOM", 0, -(MAP_GAP + (c.ring and 3 or 0)))
  infoBar:SetWidth(math.max(90, bw))
  infoBar.coords:SetShown(c.coords); infoBar.clock:SetShown(c.clock)
  infoBar.coords:SetWidth(c.clock and math.floor(infoBar:GetWidth() / 2) or infoBar:GetWidth())
  infoBar.clock:SetWidth(c.coords and math.floor(infoBar:GetWidth() / 2) or infoBar:GetWidth())
  infoBar.coords.text:ClearAllPoints()
  infoBar.clock.text:ClearAllPoints()
  local inset = c.tidy and 24 or 8
  local rInset = c.tidy and (4 + 20 * (S.MinimapRightSlotsUsed and S.MinimapRightSlotsUsed() or 1)) or 8
  if c.coords and c.clock then
    infoBar.coords.text:SetPoint("LEFT", inset, 0); infoBar.clock.text:SetPoint("RIGHT", -rInset, 0)
  else
    infoBar.coords.text:SetPoint("CENTER"); infoBar.clock.text:SetPoint("CENTER")
  end
  infoBar:SetShown(c.clock or c.coords or c.tidy)
  infoBar:SetScript("OnUpdate", (c.clock or c.coords) and infoUpdate or nil)
  infoAcc = 1
  if infoBar:IsShown() then infoUpdate(infoBar, 0) end
  updateZone()
end

-- theme colours for the plate / ring (re-run by UI:ApplyTheme)
local function skinRing(_, th)
  if not ring then return end
  back.plate:SetVertexColor(th.bg[1], th.bg[2], th.bg[3], 1)
  ring.edge:SetVertexColor(th.edge[1], th.edge[2], th.edge[3], 1)
  ring.accent:SetVertexColor(th.gold[1], th.gold[2], th.gold[3], 0.95)
  ring.shine:SetVertexColor(th.gold[1], th.gold[2], th.gold[3], 0.18)
end

---------------------------------------------------------------------------
-- Addon buttons on the minimap: themed ring instead of the old gold border,
-- optionally only shown while the mouse is over the minimap
---------------------------------------------------------------------------
local BORDER_ID, BG_ID = 136430, 136467
local function isBorderTex(r)
  local t = r.GetTexture and r:GetTexture()
  if not t then return false end
  if tonumber(t) == BORDER_ID then return true end
  return tostring(t):lower():find("minimap%-trackingborder") ~= nil
end
local function isBgTex(r)
  local t = r.GetTexture and r:GetTexture()
  if not t then return false end
  if tonumber(t) == BG_ID then return true end
  return tostring(t):lower():find("ui%-minimap%-background") ~= nil
end
-- Blizzard's own indicator buttons are left alone (tracking, mail, LFG...)
local BLIZZ = { "^Minimap", "^MiniMap", "^GameTime", "^TimeManager", "^QueueStatus", "^Garrison", "^ExpansionLandingPage",
  "^GuildInstanceDifficulty", "^HybridMinimap", "^AddonCompartment", "^Blizzard", "^LFG", "^Battlefield", "^Durability",
  "^VehicleSeat", "^Instance", "^CC_MinimapZone", "^CC_MinimapInfo", "^CC_MinimapRing", "^CC_MinimapMover" }
local function blizzName(n)
  if not n then return true end
  for _, p in ipairs(BLIZZ) do if n:find(p) then return true end end
  return false
end
-- a real minimap button (not a map pin: Questie, GatherMate2 and Questicus pins are children
-- of the minimap too and must never be faded or re-drawn)
local KNOWN = { CC_Minimap = true, QuesticusMinimapButton = true, StinkyFart_MinimapButton = true }
local function looksLikeButton(b, n)
  if KNOWN[n] or n:find("^LibDBIcon10_") then return true end
  for _, r in ipairs({ b:GetRegions() }) do
    if r.GetObjectType and r:GetObjectType() == "Texture" and isBorderTex(r) then return true end
  end
  return false
end
-- The minimap can hold hundreds of children (GatherMate2 / HereBeDragons / quest pins), so
-- the list is only rebuilt when the number of children (or LibDBIcon buttons) changed, and
-- every child is looked at once ("is it a minimap button?" is remembered per frame).
local classified = setmetatable({}, { __mode = "k" })   -- frame -> true (button) / false (pin, art...)
local scanList, scanKey = {}, nil
local function childKey()
  local n = (Minimap:GetNumChildren() or 0) + ((_G.MinimapBackdrop and _G.MinimapBackdrop:GetNumChildren()) or 0)
  local DBI = LibStub and LibStub.GetLibrary and LibStub:GetLibrary("LibDBIcon-1.0", true)
  local d = (DBI and DBI.GetButtonList and #(DBI:GetButtonList() or {})) or 0
  return n * 1000 + d
end
S.MinimapChildKey = childKey
local function addonButtons(force)
  local key = childKey()
  if force or key ~= scanKey then
    scanKey = key
    local out, seen = {}, {}
    local function add(b) if b and not seen[b] then seen[b] = true; out[#out + 1] = b end end
    for _, parent in ipairs({ Minimap, _G.MinimapBackdrop }) do
      if parent then
        for _, c in ipairs({ parent:GetChildren() }) do
          local is = classified[c]
          if is == nil then
            local n = c.GetName and c:GetName()
            is = (c.GetObjectType and c:GetObjectType() == "Button" and not blizzName(n) and looksLikeButton(c, n)) and true or false
            classified[c] = is
          end
          if is then add(c) end
        end
      end
    end
    local DBI = LibStub and LibStub.GetLibrary and LibStub:GetLibrary("LibDBIcon-1.0", true)
    if DBI and DBI.GetButtonList and DBI.GetMinimapButton then
      for _, name in ipairs(DBI:GetButtonList() or {}) do add(DBI:GetMinimapButton(name)) end
    end
    scanList = out
  end
  -- tucked into a bar since the scan? not an addon button any more
  local res = {}
  for _, b in ipairs(scanList) do if not (S.MinimapTidied and S.MinimapTidied(b)) then res[#res + 1] = b end end
  return res
end
S.MinimapAddonButtons = addonButtons

local skinned = {}   -- button -> { border = {tex = alpha}, bg = {tex = true}, ring = tex }
local function iconOf(b)
  local cand = b.icon or b.Icon
  if cand and cand.GetObjectType and cand:GetObjectType() == "Texture" then return cand end
  for _, r in ipairs({ b:GetRegions() }) do
    if r.GetObjectType and r:GetObjectType() == "Texture" and r:GetDrawLayer() ~= "HIGHLIGHT" and not isBorderTex(r) and not isBgTex(r) and r.GetTexture and r:GetTexture() then
      return r
    end
  end
end
local function skinButton(b)
  if skinned[b] then return end
  local rec = { border = {}, bg = {} }
  for _, r in ipairs({ b:GetRegions() }) do
    if r.GetObjectType and r:GetObjectType() == "Texture" then
      if isBorderTex(r) then rec.border[r] = r:GetAlpha(); r:SetAlpha(0)
      elseif isBgTex(r) then rec.bg[r] = true end
    end
  end
  if not next(rec.border) then return end   -- not the classic round button: leave it as its addon drew it
  local icon = iconOf(b)
  local d = 22
  if icon and icon.GetWidth and (icon:GetWidth() or 0) > 0 then d = math.max(18, math.min(30, icon:GetWidth() + 6)) end
  rec.ring = b:CreateTexture(nil, "OVERLAY", nil, 6)
  rec.ring:SetTexture(MEDIA .. "UI\\rring5"); rec.ring:SetSize(d, d)
  if icon then rec.ring:SetPoint("CENTER", icon, "CENTER") else rec.ring:SetPoint("CENTER") end
  rec.disc = b:CreateTexture(nil, "BACKGROUND", nil, -7)
  rec.disc:SetTexture(MEDIA .. "UI\\rmask5"); rec.disc:SetSize(d - 2, d - 2)
  rec.disc:SetPoint("CENTER", rec.ring, "CENTER")
  for r in pairs(rec.bg) do r:SetAlpha(0) end
  skinned[b] = rec
  UI:Skin(rec.ring, function(self, th)
    if not skinned[b] then return end
    self:SetVertexColor(th.gold[1], th.gold[2], th.gold[3], 0.95)
    rec.disc:SetVertexColor(th.bg[1], th.bg[2], th.bg[3], 0.95)
  end)
end
local function unskinButton(b)
  local rec = skinned[b]
  if not rec then return end
  skinned[b] = nil
  for r, a in pairs(rec.border) do r:SetAlpha(a or 1) end
  for r in pairs(rec.bg) do r:SetAlpha(1) end
  if rec.ring then rec.ring:Hide() end
  if rec.disc then rec.disc:Hide() end
end
S.MinimapSkinnedButtons = function() return skinned end

local function skinAllButtons()
  local on = active() and cfg().skinButtons
  if on then
    for _, b in ipairs(addonButtons()) do
      if skinned[b] then skinned[b].ring:Show(); skinned[b].disc:Show() else skinButton(b) end
    end
  else
    for b in pairs(skinned) do unskinButton(b) end
  end
end

-- mouse-over fade
local faded = {}
local fadeFrame
local function mouseNear()
  if MouseIsOver and MouseIsOver(Minimap, 24, -24, -24, 24) then return true end
  for b in pairs(faded) do if b:IsVisible() and MouseIsOver and MouseIsOver(b) then return true end end
  return false
end
local function keepVisible(b)
  -- our own button keeps showing while it has news on it
  if b == _G.CC_Minimap and S.UnreadNotifs and (S:UnreadNotifs() or 0) > 0 then return true end
  return false
end
local function setFade(on)
  if not fadeFrame then fadeFrame = CreateFrame("Frame") end
  if not on then
    fadeFrame:SetScript("OnUpdate", nil)
    for b in pairs(faded) do b:SetAlpha(1) end
    wipe(faded)
    return
  end
  local acc, scan, cur = 0, 99, 1
  fadeFrame:SetScript("OnUpdate", (S.PerfWrap or function(_, f) return f end)("Minimap  button fade", function(_, el)
    acc, scan = acc + el, scan + el
    if scan > 3 then
      scan = 0
      for _, b in ipairs(addonButtons()) do faded[b] = true end
    end
    if acc < 0.05 then return end
    local step = acc * 6
    acc = 0
    local target = mouseNear() and 1 or 0
    if target > cur then cur = math.min(1, cur + step) elseif target < cur then cur = math.max(0, cur - step) end
    for b in pairs(faded) do b:SetAlpha(keepVisible(b) and 1 or cur) end
  end))
end

---------------------------------------------------------------------------
-- Blizzard indicator buttons (tracking, mail, battleground / LFG, day-night):
-- on a non-round minimap they are slid out onto the new edge, same angle.
---------------------------------------------------------------------------
local INDICATORS = {
  function() return _G.MiniMapTracking end, function() return _G.MiniMapTrackingFrame end,
  function() return _G.MiniMapMailFrame end, function() return _G.MiniMapBattlefieldFrame end,
  function() return _G.MiniMapLFGFrame end, function() return _G.LFGMinimapFrame end,
  function() return _G.GameTimeFrame end, function() return _G.MiniMapInstanceDifficulty end,
}
local slid = {}   -- frame -> { orig = {points}, x, y }
local function centerOffset(f)
  local fx, fy = f:GetCenter()
  local mx, my = Minimap:GetCenter()
  if not (fx and mx) then return end
  local fs, ms = f:GetEffectiveScale(), Minimap:GetEffectiveScale()
  return (fx * fs - mx * ms) / ms, (fy * fs - my * ms) / ms
end
local function slideIndicators(on)
  if inCombat() then return end
  local half = (Minimap:GetWidth() or 140) / 2
  for _, get in ipairs(INDICATORS) do
    local ok, f = pcall(get)
    if ok and f and f.GetCenter and not (S.MinimapTidied and S.MinimapTidied(f)) then
      local rec = slid[f]
      if on then
        local p1, rel, _, x1, y1 = f:GetPoint(1)
        local ours = rec and rel == Minimap and p1 == "CENTER" and math.abs((x1 or 0) - rec.x) < 0.5 and math.abs((y1 or 0) - rec.y) < 0.5
        if not ours then
          -- first time (or something else moved it): measure where it sits now
          local dx, dy = centerOffset(f)
          local dist = dx and math.sqrt(dx * dx + dy * dy)
          if dist and dist > half * 0.55 and dist < half * 1.7 then
            local orig = {}
            for i = 1, (f:GetNumPoints() or 0) do orig[#orig + 1] = { f:GetPoint(i) } end
            rec = { orig = (rec and rec.orig) or orig, angle = math.deg((math.atan2 or math.atan)(dy, dx)), pad = dist - half }
            slid[f] = rec
          else
            rec = nil
          end
        end
        if rec then
          rec.x, rec.y = S.MinimapEdge(rec.angle, rec.pad)
          f:ClearAllPoints(); f:SetPoint("CENTER", Minimap, "CENTER", rec.x, rec.y)
        end
      elseif rec then
        slid[f] = nil
        f:ClearAllPoints()
        for _, pt in ipairs(rec.orig) do f:SetPoint(unpack(pt)) end
      end
    end
  end
end

---------------------------------------------------------------------------
-- Size and position (MinimapCluster, so every button scales with it)
---------------------------------------------------------------------------
local origCluster, scaled, movedApplied
local function saveOrigCluster()
  local mc = cluster()
  if origCluster or not mc then return end
  origCluster = {}
  for i = 1, (mc:GetNumPoints() or 0) do origCluster[#origCluster + 1] = { mc:GetPoint(i) } end
end
local function applyScaleAndPos()
  local mc = cluster()
  if not mc or inCombat() then return false end
  local c = cfg()
  local on = active()
  local sc = on and (tonumber(c.scale) or 1) or 1
  if math.abs(sc - 1) > 0.001 or scaled then
    mc:SetScale(sc)
    scaled = math.abs(sc - 1) > 0.001
  end
  if on then S.MinimapFitClamp() else S.MinimapFitClamp(true) end
  if on and type(c.pos) == "table" then
    saveOrigCluster()
    local s = mc:GetScale() or 1
    mc:ClearAllPoints()
    mc:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", (c.pos.x or 0) / s, (c.pos.y or 0) / s)
    movedApplied = true
  elseif movedApplied and origCluster then
    mc:ClearAllPoints()
    for _, pt in ipairs(origCluster) do mc:SetPoint(unpack(pt)) end
    movedApplied = false
  end
  return true
end

-- MinimapCluster is bigger than what you see (empty space round the map): clamp to what's
-- drawn - the map with its frame and the two bars - so it goes right up to the screen edge
local clampOrig
function S.MinimapFitClamp(restore)
  local mc = cluster()
  if not mc or not mc.SetClampRectInsets then return end
  if restore then
    if clampOrig then mc:SetClampRectInsets(unpack(clampOrig.insets)); mc:SetClampedToScreen(clampOrig.clamped); clampOrig = nil end
    return
  end
  if not clampOrig then
    clampOrig = { insets = { 0, 0, 0, 0 }, clamped = mc:IsClampedToScreen() and true or false }
    if mc.GetClampRectInsets then clampOrig.insets = { mc:GetClampRectInsets() } end
  end
  local ml, mr, mt, mb = mc:GetLeft(), mc:GetRight(), mc:GetTop(), mc:GetBottom()
  if not (ml and mr and mt and mb) then mc:SetClampedToScreen(true) return end
  local me = mc:GetEffectiveScale()
  local L, R, T, B
  local function grow(f)
    if not f or not f:IsShown() then return end
    local l, r, t, b = f:GetLeft(), f:GetRight(), f:GetTop(), f:GetBottom()
    if not (l and r and t and b) then return end
    local k = f:GetEffectiveScale() / me
    l, r, t, b = l * k, r * k, t * k, b * k
    L = L and math.min(L, l) or l; R = R and math.max(R, r) or r
    T = T and math.max(T, t) or t; B = B and math.min(B, b) or b
  end
  grow(Minimap); grow(ring); grow(zoneBar); grow(infoBar)
  if not L then mc:SetClampedToScreen(true) return end
  -- insets move each edge of the clamp box in to what's drawn
  mc:SetClampRectInsets(L - ml, R - mr, T - mt, B - mb)
  mc:SetClampedToScreen(true)
end

local function buildMover()
  if mover then return mover end
  mover = CreateFrame("Button", "CC_MinimapMover", Minimap)
  mover:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 20)
  mover:SetPoint("TOPLEFT", Minimap, "TOPLEFT", -8, 34); mover:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMRIGHT", 8, -32)
  mover:RegisterForDrag("LeftButton")
  mover:RegisterForClicks("RightButtonUp")
  mover.text = UI:Text(mover, "Drag to move the minimap\nRight-click to lock it", "small", "CENTER")
  mover.text:SetPoint("CENTER")
  UI:Skin(mover, function(self, th)
    UI.Flat(self, th.bg, 0.55, th.gold, 1, 2)
    self.text:SetTextColor(th.gold[1], th.gold[2], th.gold[3])
  end)
  mover:SetScript("OnDragStart", function()
    local mc = cluster()
    if not mc or inCombat() then return end
    saveOrigCluster()
    mc:SetMovable(true)
    S.MinimapFitClamp()
    mc:StartMoving()
    mover.moving = true
  end)
  mover:SetScript("OnDragStop", function()
    local mc = cluster()
    if not mc or not mover.moving then return end
    mover.moving = false
    mc:StopMovingOrSizing()
    if mc.SetUserPlaced then pcall(mc.SetUserPlaced, mc, false) end   -- we keep the spot, not the layout cache
    local s = mc:GetEffectiveScale() / UIParent:GetEffectiveScale()
    cfg().pos = { x = mc:GetRight() * s - UIParent:GetRight(), y = mc:GetTop() * s - UIParent:GetTop() }
    applyScaleAndPos()
    fireChange()
  end)
  mover:SetScript("OnClick", function() S:MinimapUnlock(false) end)
  mover:Hide()
  return mover
end
function S:MinimapUnlock(on)
  if on and not active() then S:Print("Turn on the Command Center minimap look first.") return end
  if on and inCombat() then S:Print("The minimap can be moved after combat.") return end
  buildMover():SetShown(on and true or false)
  if S.RefreshMinimapSettings then S:RefreshMinimapSettings() end
end
function S:MinimapResetPos()
  cfg().pos = nil
  if mover then mover:Hide() end
  S:ApplyMinimap()
end

---------------------------------------------------------------------------
-- Zoom: mouse wheel, back out after a while
---------------------------------------------------------------------------
local ourWheel, zoomTimer, zoomHooked
local function onWheel(self, d)
  local z = self:GetZoom() or 0
  local max = (self.GetZoomLevels and self:GetZoomLevels() or 6) - 1
  if d > 0 and z < max then self:SetZoom(z + 1) elseif d < 0 and z > 0 then self:SetZoom(z - 1) end
end
local function zoomChanged()
  if zoomTimer then zoomTimer:Cancel(); zoomTimer = nil end
  local secs = active() and tonumber(cfg().autoZoom) or 0
  if secs and secs > 0 and (Minimap:GetZoom() or 0) > 0 and C_Timer and C_Timer.NewTimer then
    zoomTimer = C_Timer.NewTimer(secs, function()
      zoomTimer = nil
      if active() and (Minimap:GetZoom() or 0) > 0 then
        Minimap:SetZoom(0)
        -- keep the game's zoom buttons in step (when they are shown)
        if _G.MinimapZoomOut and _G.MinimapZoomOut.Disable then pcall(_G.MinimapZoomOut.Disable, _G.MinimapZoomOut) end
        if _G.MinimapZoomIn and _G.MinimapZoomIn.Enable then pcall(_G.MinimapZoomIn.Enable, _G.MinimapZoomIn) end
      end
    end)
  end
end
local function setWheel(on)
  if not zoomHooked and hooksecurefunc then
    zoomHooked = true
    hooksecurefunc(Minimap, "SetZoom", zoomChanged)
  end
  if on then
    if not Minimap:GetScript("OnMouseWheel") then
      Minimap:EnableMouseWheel(true)
      Minimap:SetScript("OnMouseWheel", onWheel)
      ourWheel = true
    end
  elseif ourWheel then
    Minimap:SetScript("OnMouseWheel", nil)
    Minimap:EnableMouseWheel(false)
    ourWheel = false
  end
end


---------------------------------------------------------------------------
-- Tidy: the game's own buttons go into the bars' end slots, small and in line
--   zone bar left = mail, info bar left = tracking (magnifying glass),
--   info bar right = calendar / day-night. (Their clicks and tooltips are the game's.)
---------------------------------------------------------------------------
local tidied = {}   -- frame -> { parent, points, scale, borders = {tex = alpha} }
function S.MinimapTidied(f) return tidied[f] ~= nil end
local TIDY = {
  { id = "mail", bar = "zone", side = "slotL", point = "LEFT",
    frames = { function() return cluster() and cluster().IndicatorFrame end, function() return _G.MiniMapMailFrame end },
    visual = function(f) return f.MailFrame or _G.MiniMapMailIcon end },
  { id = "tracking", bar = "info", side = "slotL",
    frames = { function() return cluster() and cluster().Tracking end, function() return _G.MiniMapTrackingFrame end, function() return _G.MiniMapTracking end },
    visual = function(f) return f.Button or _G.MiniMapTrackingIcon or _G.MiniMapTrackingButton end },
  { id = "calendar", bar = "info", side = "slotR",
    frames = { function() return _G.GameTimeFrame end },
    visual = function(f) return nil end },
  -- the day / night (sun / moon) button: the Forever client's own one, or anything that looks like it
  { id = "daynight", bar = "info", side = "slotR2",
    -- Forever's moon is the game's ExpansionLandingPageMinimapButton (MoveAny also drags it round the ring)
    frames = { function() return S.MinimapFindDial and S.MinimapFindDial() end,
      function() return _G.ExpansionLandingPageMinimapButton end, function() return _G.MetashiForeverMinimapButton end,
      function() return S.MinimapFindDayNight and S.MinimapFindDayNight() end },
    visual = function(f)
      if f == _G.ExpansionLandingPageMinimapButton then return nil end   -- its art fills the button
      return f.icon or f.Icon or iconOf(f)
    end },
}
-- Forever's day/night dial (found 2026-11-20 with "Tuck an icon"): an unnamed, roughly
-- 42 x 41 frame that is a child of MinimapCluster.MinimapContainer (next to Minimap itself).
-- Once found it is remembered, because tucking moves it out of that container.
local dialFrame
function S.MinimapFindDial()
  if dialFrame then return dialFrame end
  local mc = cluster()
  local box = mc and rawget(mc, "MinimapContainer")
  if type(box) ~= "table" or not box.GetChildren then return end
  for _, ch in ipairs({ box:GetChildren() }) do
    if ch ~= Minimap and not (ch.IsForbidden and ch:IsForbidden()) and not (ch.GetName and ch:GetName()) then
      local w, h = ch:GetWidth() or 0, ch:GetHeight() or 0
      if w >= 30 and w <= 56 and h >= 30 and h <= 56 and math.abs(w - h) <= 6 then
        dialFrame = ch
        return ch
      end
    end
  end
end
-- a button around the minimap whose art is a sun / moon / day-night picture
local DAYNIGHT_WORDS = { "daynight", "day%-night", "gametime", "sun", "moon", "night" }
function S.MinimapFindDayNight()
  for _, p in ipairs({ Minimap, cluster(), _G.MinimapBackdrop }) do
    for _, ch in ipairs(p and { p:GetChildren() } or {}) do
      local n = ch.GetName and ch:GetName()
      if n and n ~= "GameTimeFrame" and not n:find("^CC_") and not tidied[ch] and ch.GetObjectType and ch:GetObjectType() == "Button" then
        local hay = n:lower()
        for _, r in ipairs({ ch:GetRegions() }) do
          if r.GetObjectType and r:GetObjectType() == "Texture" and r.GetTexture then hay = hay .. " " .. tostring(r:GetTexture() or ""):lower() end
        end
        if ch.GetNormalTexture and ch:GetNormalTexture() then hay = hay .. " " .. tostring(ch:GetNormalTexture():GetTexture() or ""):lower() end
        for _, w in ipairs(DAYNIGHT_WORDS) do if hay:find(w) then return ch end end
      end
    end
  end
end
S.MINIMAP_TIDY = TIDY
local function firstFrame(list)
  for _, get in ipairs(list) do
    local ok, f = pcall(get)
    if ok and type(f) == "table" and f.SetParent then return f end
  end
end
local function hideBorders(f, rec)
  local function scan(o)
    for _, r in ipairs({ o:GetRegions() }) do
      if r.GetObjectType and r:GetObjectType() == "Texture" and isBorderTex(r) and not rec.borders[r] then
        rec.borders[r] = r:GetAlpha(); r:SetAlpha(0)
      end
    end
  end
  scan(f)
  for _, ch in ipairs({ f:GetChildren() }) do scan(ch) end
end
local tidyBusy, retidyQueued
local tidyAll
local function guard(f)
  local rec = tidied[f]
  if not rec or rec.hooked or not hooksecurefunc then return end
  rec.hooked = true
  local function back()
    if tidyBusy or not tidied[f] or retidyQueued then return end
    retidyQueued = true
    C_Timer.After(0, function()
      retidyQueued = false
      if active() and cfg().tidy and not inCombat() and tidyAll then tidyAll() end
    end)
  end
  hooksecurefunc(f, "SetPoint", back)
  hooksecurefunc(f, "SetParent", back)
end
local function tidyOne(e, slotFrame)
  local f = firstFrame(e.frames)
  if not f or not slotFrame then return end
  local rec = tidied[f]
  local p1, rel = f:GetPoint(1)
  if rec and rel == slotFrame and f:GetParent() == slotFrame then return end   -- still where we put it
  if not rec then
    rec = { parent = f:GetParent(), scale = f:GetScale(), points = {}, borders = {}, level = f:GetFrameLevel() }
    for i = 1, (f:GetNumPoints() or 0) do rec.points[#rec.points + 1] = { f:GetPoint(i) } end
    tidied[f] = rec
  end
  if skinned[f] then unskinButton(f) end    -- it gets the bar's look, not the addon-button ring
  tidyBusy = true
  hideBorders(f, rec)
  -- art turned to follow the ring (MoveAny does that) sits straight in the bar
  rec.rot = rec.rot or {}
  for _, r in ipairs({ f:GetRegions() }) do
    if r.GetRotation and r.SetRotation and rec.rot[r] == nil then
      local a = r:GetRotation() or 0
      if a ~= 0 then rec.rot[r] = a; r:SetRotation(0) end
    end
  end
  f:SetParent(slotFrame)
  f:SetFrameLevel(slotFrame:GetFrameLevel() + 1)
  local vis = e.visual(f)
  if type(vis) ~= "table" or not vis.GetHeight then vis = nil end
  local vh = (vis and vis:GetHeight()) or f:GetHeight() or 18
  if not vh or vh <= 0 then vh = 18 end
  f:SetScale(math.max(0.25, math.min(1.5, 17 / vh)))
  f:ClearAllPoints()
  if e.point == "LEFT" and not vis then
    f:SetPoint("LEFT", slotFrame, "LEFT", 0, 0)
  else
    -- line the visible icon (not the frame, which often has its art off-centre) up with the slot
    local dx, dy = 0, 0
    if vis then
      f:SetPoint("CENTER", slotFrame, "CENTER", 0, 0)
      local fx, fy = f:GetCenter()
      local ix, iy = vis:GetCenter()
      if fx and ix then
        local k = (vis.GetEffectiveScale and vis:GetEffectiveScale() or 1) / (f:GetEffectiveScale() or 1)
        dx, dy = ix * k - fx, iy * k - fy
      end
      f:ClearAllPoints()
    end
    f:SetPoint("CENTER", slotFrame, "CENTER", -dx, -dy)
  end
  tidyBusy = false
  guard(f)
end
local extras = {}     -- ordered list of frames given an extra bottom-bar slot (see tidyExtras)
local function untidyAll()
  if inCombat() then return end
  tidyBusy = true
  for f, rec in pairs(tidied) do
    pcall(function()
    for r, a in pairs(rec.borders) do r:SetAlpha(a or 1) end
    for r, a in pairs(rec.rot or {}) do r:SetRotation(a) end
    f:SetParent(rec.parent)
    f:SetScale(rec.scale or 1)
    if rec.level then f:SetFrameLevel(rec.level) end
    f:ClearAllPoints()
    for _, pt in ipairs(rec.points) do f:SetPoint(unpack(pt)) end
    end)
  end
  wipe(tidied)
  wipe(extras)
  tidyBusy = false
end
-- anything else the game itself puts around the minimap (battleground / LFG eye, dungeon
-- difficulty...) gets the next slot along the bottom bar instead of sitting on the edge
local EXTRA_SKIP = { MiniMapPing = true, MinimapBackdrop = true, MinimapNorthTag = true, MinimapCompassTexture = true,
  MinimapZoneTextButton = true, MinimapZoomIn = true, MinimapZoomOut = true, MiniMapWorldMapButton = true,
  MinimapToggleButton = true, TimeManagerClockButton = true, MinimapZoneText = true, HybridMinimap = true,
  AddonCompartmentFrame = true, MinimapCluster = true, MinimapBorder = true, MinimapBorderTop = true }
local function extraCandidate(f)
  if f.IsForbidden and f:IsForbidden() then return false end
  local n = f.GetName and f:GetName()
  if not n or EXTRA_SKIP[n] or tidied[f] or n:find("^CC_") or n:find("DropDown") or n:find("Ping") then return false end
  if not blizzName(n) or n:find("^AddonCompartment") or n:find("^HybridMinimap") then return false end
  local kind = f.GetObjectType and f:GetObjectType()
  if kind ~= "Button" and kind ~= "Frame" then return false end
  local w, h = f:GetWidth() or 0, f:GetHeight() or 0
  if w < 12 or h < 12 or w > 90 or h > 90 or math.abs(w - h) > math.max(w, h) * 0.45 then return false end
  local dx, dy = centerOffset(f)
  if not dx then return false end
  local half = (Minimap:GetWidth() or 140) / 2
  return math.abs(dx) < half + 60 and math.abs(dy) < half + 60
end
local picked = {}      -- frames you clicked with "Tuck an icon" this session (unnamed ones can't be saved)
local tidyErrors = {}  -- frame name -> why it couldn't be tucked (shown by /ccenter map frames)
local function safeTidy(e, slotFrame, f)
  local fn = f and f.GetName and f:GetName()
  if fn and tidyErrors[fn] then return end   -- it failed once this session: don't keep trying every few seconds
  local ok, err = pcall(tidyOne, e, slotFrame)
  tidyBusy = false
  if not ok then
    -- half moved: hand it back as it was
    local fr = f or firstFrame(e.frames)
    local rec = fr and tidied[fr]
    if rec then
      for r, a in pairs(rec.borders or {}) do pcall(r.SetAlpha, r, a or 1) end
      pcall(fr.SetParent, fr, rec.parent); pcall(fr.SetScale, fr, rec.scale or 1)
      pcall(fr.ClearAllPoints, fr)
      for _, pt in ipairs(rec.points or {}) do pcall(fr.SetPoint, fr, unpack(pt)) end
      tidied[fr] = nil
    end
    local n = (f and f.GetName and f:GetName()) or e.id or "?"
    if not tidyErrors[n] then
      tidyErrors[n] = tostring(err)
      S:Print("Minimap: couldn't tuck " .. n .. " into the bar (" .. tostring(err):gsub("^.-:%d+: ", "") .. ").")
    end
  end
end
-- Frames without a name are remembered by their path from the nearest named frame:
-- "MinimapCluster.SomeKey#2@1" = MinimapCluster, its field SomeKey, that frame's 2nd child,
-- its 1st texture. Worked out before the frame is moved, and looked up again at login.
local pathCache = {}   -- path -> object found this session (it moves, so the walk only works once)
local function keyIn(parent, child)
  if child.GetParentKey then
    local ok, k = pcall(child.GetParentKey, child)
    if ok and type(k) == "string" and k ~= "" and rawget(parent, k) == child then return "." .. k end
  end
  for k, v in pairs(parent) do
    if v == child and type(k) == "string" and k:match("^[%a_][%w_]*$") then return "." .. k end
  end
  if child.GetObjectType and child:GetObjectType() == "Texture" or (child.IsObjectType and not child.GetChildren) then
    for i, r in ipairs({ parent:GetRegions() }) do if r == child then return "@" .. i end end
  else
    for i, c in ipairs({ parent:GetChildren() }) do if c == child then return "#" .. i end end
  end
end
function S.MinimapPathOf(o)
  local parts, cur = {}, o
  for _ = 1, 8 do
    local n = cur.GetName and cur:GetName()
    if n and _G[n] == cur then table.insert(parts, 1, n); return table.concat(parts, "") end
    local p = cur.GetParent and cur:GetParent()
    if not p then return end
    local k = keyIn(p, cur)
    if not k then return end
    table.insert(parts, 1, k)
    cur = p
  end
end
function S.MinimapResolvePath(path)
  if pathCache[path] then return pathCache[path] end
  local name, rest = tostring(path):match("^([^%.#@]+)(.*)$")
  local cur = name and _G[name]
  if type(cur) ~= "table" then return end
  for sep, tok in rest:gmatch("([%.#@])([^%.#@]+)") do
    if type(cur) ~= "table" then return end
    if sep == "." then cur = rawget(cur, tok) or cur[tok]
    elseif sep == "#" then cur = select(tonumber(tok) or 0, cur:GetChildren())
    else cur = select(tonumber(tok) or 0, cur:GetRegions()) end
  end
  if type(cur) == "table" and cur.SetParent and not (cur.IsForbidden and cur:IsForbidden()) then
    pathCache[path] = cur
    return cur
  end
end
-- Only things that live on / round the minimap may be tucked: their parents must lead to
-- Minimap, MinimapCluster or MinimapBackdrop (or they hang straight off UIParent). Anything that
-- belongs to another window - the world map's close button sat under the minimap once while
-- Questicus Maps sized the map, and got tucked - is never taken.
function S.MinimapBelongs(o)
  if type(o) ~= "table" or not o.GetParent then return false end
  local p = o:GetParent()
  if p == UIParent then return true end
  local wm, cur, steps = _G.WorldMapFrame, p, 0
  while cur and steps < 25 do
    if cur == wm then return false end
    if cur == Minimap or cur == cluster() or cur == _G.MinimapBackdrop then return true end
    cur = cur.GetParent and cur:GetParent()
    steps = steps + 1
  end
  return false
end
local function tuckedFrames()
  local out = {}
  local c = cfg()
  for path, kind in pairs(type(c.tuckPaths) == "table" and c.tuckPaths or {}) do
    if kind == "frame" then
      local f = S.MinimapResolvePath(path)
      if f and S.MinimapBelongs(f) then out[#out + 1] = f
      elseif f then c.tuckPaths[path] = nil end            -- saved by mistake: forget it
    end
  end
  for name in pairs(type(c.tuck) == "table" and c.tuck or {}) do
    local f = _G[name]
    if type(f) == "table" and f.SetParent and not (f.IsForbidden and f:IsForbidden()) then
      if S.MinimapBelongs(f) then out[#out + 1] = f
      else
        c.tuck[name] = nil
        S:Print("Minimap: " .. name .. " belongs to another window - it won't be tucked into the minimap bar.")
      end
    end
  end
  for f in pairs(picked) do out[#out + 1] = f end
  return out
end
local function tidyExtras()
  for _, f in ipairs(tuckedFrames()) do
    local have = false
    for _, x in ipairs(extras) do if x == f then have = true end end
    -- one of the named slots (mail / tracking / calendar / day-night) already holds it? leave it there
    local inNamed = false
    for _, e in ipairs(TIDY) do if firstFrame(e.frames) == f then inNamed = true end end
    if not have and not inNamed then table.insert(extras, 1, f) end
  end
  for _, p in ipairs({ Minimap, cluster(), _G.MinimapBackdrop }) do
    for _, ch in ipairs(p and { p:GetChildren() } or {}) do
      if ch:IsShown() and extraCandidate(ch) then extras[#extras + 1] = ch end
    end
  end
  -- shown ones take the slots in order; hidden ones keep theirs until they show again
  local i = 3
  for _, f in ipairs(extras) do
    local slotFrame = infoBar:RightSlot(i)
    safeTidy({ frames = { function() return f end }, visual = function(fr) return fr.icon or fr.Icon or iconOf(fr) end }, slotFrame, f)
    if f:IsShown() then i = i + 1 end
  end
end
-- how many right-hand slots of the bottom bar hold something (for the clock's room)
local lastRInset
local function updateClockInset()
  if not infoBar then return end
  local c = cfg()
  if not (c.coords and c.clock and c.tidy) then return end
  local r = 4 + 20 * S.MinimapRightSlotsUsed()
  if r == lastRInset then return end
  lastRInset = r
  infoBar.clock.text:ClearAllPoints(); infoBar.clock.text:SetPoint("RIGHT", -r, 0)
end
S.MinimapUpdateClockInset = function() lastRInset = nil; updateClockInset() end
function S.MinimapRightSlotsUsed()
  if not infoBar or not cfg().tidy then return 1 end
  local used = 0
  for i, sl in ipairs(infoBar.rightSlots) do
    for _, ch in ipairs({ sl:GetChildren() }) do if ch:IsShown() then used = i end end
  end
  return math.max(1, used)
end
tidyAll = function()
  if inCombat() or not zoneBar then return end
  -- look up saved paths first: "#3" means the 3rd child NOW, before anything is moved out
  for path in pairs(type(cfg().tuckPaths) == "table" and cfg().tuckPaths or {}) do pcall(S.MinimapResolvePath, path) end
  for _, e in ipairs(TIDY) do
    local bar = e.bar == "zone" and zoneBar or infoBar
    safeTidy(e, bar[e.side], firstFrame(e.frames))   -- one stubborn frame never stops the others
  end
  tidyExtras()
  if S._mmRestoreRegionTucks then pcall(S._mmRestoreRegionTucks) end
  lastRInset = nil; updateClockInset()
end

---------------------------------------------------------------------------
-- Drawer: the Button Box docked to the minimap, opened from a small button on the
-- zone bar. Every addon's minimap icon goes in it (once - take one out and it stays
-- out), which hides their buttons on the minimap (Plugins). Command Center's own
-- minimap button steps aside: the drawer button carries its menu and badge.
---------------------------------------------------------------------------
local boxBtn
local function drawerOn() return active() and cfg().drawer and S.ShowButtonBox ~= nil end
S.MinimapDrawerOn = drawerOn
local function buildBoxButton()
  if boxBtn then return boxBtn end
  boxBtn = CreateFrame("Button", "CC_MinimapBoxButton", zoneBar.slotR)
  boxBtn:SetAllPoints()
  boxBtn:SetFrameLevel(zoneBar.slotR:GetFrameLevel() + 1)
  boxBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  boxBtn.icon = UI:Icon(boxBtn, "box", 14); boxBtn.icon:SetPoint("CENTER")
  boxBtn.hl = boxBtn:CreateTexture(nil, "HIGHLIGHT"); boxBtn.hl:SetTexture(MEDIA .. "UI\\glow"); boxBtn.hl:SetPoint("TOPLEFT", -4, 4); boxBtn.hl:SetPoint("BOTTOMRIGHT", 4, -4)
  boxBtn.hl:SetBlendMode("ADD")
  if UI.Badge then boxBtn.badge = UI:Badge(boxBtn, 12); boxBtn.badge:SetPoint("TOPRIGHT", 6, 6) end
  local function paint(self, th)
    th = th or UI:Theme()
    local open = _G.CC_ButtonBox and _G.CC_ButtonBox:IsShown()
    local col = (open or self.__hot) and th.gold or th.muted
    self.icon:SetVertexColor(col[1], col[2], col[3])
    self.hl:SetVertexColor(th.gold[1], th.gold[2], th.gold[3], 0.35)
  end
  boxBtn.paint = paint
  UI:Skin(boxBtn, paint)
  boxBtn:SetScript("OnClick", function(self, btn)
    GameTooltip:Hide()
    if btn == "RightButton" then
      if S.MinimapMenu then S:MinimapMenu(self) end
    else
      local box = _G.CC_ButtonBox
      if box and box:IsShown() then S:HideButtonBox() else S:ShowButtonBox() end
    end
    paint(self)
  end)
  boxBtn:SetScript("OnEnter", function(self)
    self.__hot = true; paint(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
    GameTooltip:AddLine("|cff" .. (S.ACCENT_HEX or "ffd100") .. "Addon buttons|r")
    local n = S.UnreadNotifs and S:UnreadNotifs() or 0
    if n > 0 then GameTooltip:AddLine(n .. " new notification" .. (n > 1 and "s" or ""), 1, 0.82, 0) end
    GameTooltip:AddLine("Click: open / close the Button Box (every addon's minimap icon)", 1, 1, 1, true)
    GameTooltip:AddLine("Right-click: Command Center menu", 1, 1, 1)
    GameTooltip:Show()
  end)
  boxBtn:SetScript("OnLeave", function(self) self.__hot = false; paint(self); GameTooltip:Hide() end)
  -- open state + badge follow along
  local acc = 0
  boxBtn:SetScript("OnUpdate", function(self, el)
    acc = acc + el; if acc < 0.5 then return end; acc = 0
    paint(self)
    if self.badge and self.badge.SetCount then self.badge:SetCount(S.UnreadNotifs and S:UnreadNotifs() or 0) end
  end)
  return boxBtn
end

-- every addon icon not seen before goes in the box (unless it is on your dock / border bar)
-- What fillBox looks at: LibDataBroker launchers + the minimap's addon buttons. Quest / map
-- pins (Questie, HereBeDragons...) come and go all the time but don't change this.
local function ldbCount()
  local LDB = LibStub and LibStub.GetLibrary and LibStub:GetLibrary("LibDataBroker-1.1", true)
  if not (LDB and LDB.DataObjectIterator) then return 0 end
  local n = 0
  for _ in LDB:DataObjectIterator() do n = n + 1 end
  return n
end
local function buttonSig() return #addonButtons() * 10000 + ldbCount() end
S.MinimapButtonSig = buttonSig
local lastFillSig
local function fillBox(force)
  if not drawerOn() or inCombat() or not (S.PluginItems and S.ButtonBoxAddMany) then return end
  local sig = buttonSig()
  if not force and sig == lastFillSig then return end    -- nothing new since the last fill
  lastFillSig = sig
  local c = cfg()
  c.boxSeen = type(c.boxSeen) == "table" and c.boxSeen or {}
  local onBar = S.QuickBarKeysInUse and S:QuickBarKeysInUse() or {}
  local add = {}
  local ok, items = pcall(S.PluginItems, S, true)
  if not ok then return end
  for _, it in ipairs(items or {}) do
    if it.key and not c.boxSeen[it.key] then
      c.boxSeen[it.key] = true
      if not onBar[it.key] and not S:ButtonBoxHas(it.key) then add[#add + 1] = it.key end
    end
  end
  if #add > 0 then S:ButtonBoxAddMany(add) end
end
S.MinimapFillBox = fillBox

-- the newer client's addon compartment (the number button) rides in the box's header
local compart
local function dockCompartment(win)
  local ac = _G.AddonCompartmentFrame
  if not ac or not win or inCombat() then return end
  if not compart then compart = { parent = ac:GetParent(), scale = ac:GetScale(), points = {} }
    for i = 1, (ac:GetNumPoints() or 0) do compart.points[#compart.points + 1] = { ac:GetPoint(i) } end
  end
  ac:SetParent(win)
  ac:SetFrameLevel(win:GetFrameLevel() + 5)
  local h = ac:GetHeight() or 20; if h <= 0 then h = 20 end
  ac:SetScale(18 / h)
  ac:ClearAllPoints()
  local anchor = win.headBtns and win.headBtns[#win.headBtns]
  if anchor then ac:SetPoint("RIGHT", anchor, "LEFT", -4, 0) else ac:SetPoint("TOPRIGHT", win, "TOPRIGHT", -80, -5) end
end
local function undockCompartment()
  local ac = _G.AddonCompartmentFrame
  if not ac or not compart or inCombat() then return end
  ac:SetParent(compart.parent); ac:SetScale(compart.scale or 1); ac:ClearAllPoints()
  for _, pt in ipairs(compart.points) do ac:SetPoint(unpack(pt)) end
  compart = nil
end

local function boxDock()
  local anchorTop = (infoBar and infoBar:IsShown()) and infoBar or Minimap
  local anchorBottom = (zoneBar and zoneBar:IsShown()) and zoneBar or Minimap
  local _, my = Minimap:GetCenter()
  local screenH = UIParent:GetHeight() or 768
  local below = not my or (my * (Minimap:GetEffectiveScale() / UIParent:GetEffectiveScale())) > screenH * 0.45
  local k = Minimap:GetEffectiveScale() / UIParent:GetEffectiveScale()
  return {
    anchor = below and anchorTop or anchorBottom,
    point = below and "TOP" or "BOTTOM", relPoint = below and "BOTTOM" or "TOP",
    x = 0, y = below and -6 or 6,
    width = math.floor(((Minimap:GetWidth() or 140) + 10) * k + 0.5),
    decorate = dockCompartment,
  }
end
local function setDrawer(on)
  if not S.ButtonBoxDock then return end
  if on then
    buildBoxButton():Show()
    S:ButtonBoxDock(boxDock())
    fillBox(true)
  else
    if boxBtn then boxBtn:Hide() end
    if S.ButtonBoxDocked and S:ButtonBoxDocked() then S:ButtonBoxDock(nil) end
    undockCompartment()
  end
  if S.UpdateMinimap and S.db then S:UpdateMinimap() end   -- our own minimap button hides / comes back
end

---------------------------------------------------------------------------
-- Another addon's coordinates next to the minimap (when ours are on): hidden, so
-- there's one line of coordinates
---------------------------------------------------------------------------
local dupHidden = {}
local function looksLikeCoords(t)
  if type(t) ~= "string" then return false end
  t = t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  return t:match("^%s*%(?%d+%.?%d*%s*[,/ ]%s*%d+%.?%d*%)?%s*$") ~= nil
end
local function hideDupCoords(on)
  if not on then
    for fs, a in pairs(dupHidden) do fs:SetAlpha(a or 1) end
    wipe(dupHidden)
    return
  end
  local mx, my = Minimap:GetCenter()
  if not mx then return end
  local ms = Minimap:GetEffectiveScale()
  local reach = (Minimap:GetWidth() or 140) * 0.5 + 70
  local function near(o)
    local x, y = o:GetCenter()
    if not x then return false end
    local s = (o.GetEffectiveScale and o:GetEffectiveScale()) or ms
    local dx, dy = x * s / ms - mx, y * s / ms - my
    return math.abs(dx) < reach and math.abs(dy) < reach
  end
  local mine = infoBar and infoBar.coords.text
  local function check(fs)
    if fs ~= mine and not dupHidden[fs] and fs.GetText and looksLikeCoords(fs:GetText()) and fs:GetAlpha() > 0 and near(fs) then
      dupHidden[fs] = fs:GetAlpha(); fs:SetAlpha(0)
    end
  end
  local function scan(f, depth)
    if not f or f == infoBar or (f.IsForbidden and f:IsForbidden()) then return end
    for _, r in ipairs({ f:GetRegions() }) do
      if r.GetObjectType and r:GetObjectType() == "FontString" then check(r) end
    end
    if depth > 0 then for _, ch in ipairs({ f:GetChildren() }) do scan(ch, depth - 1) end end
  end
  scan(Minimap, 2); scan(cluster(), 2); scan(_G.MinimapBackdrop, 1)
  -- addons that hang their text off UIParent next to the minimap
  -- (some of the game's frames are off limits to addons: skip those, or the game errors)
  for _, ch in ipairs({ UIParent:GetChildren() }) do
    if not (ch.IsForbidden and ch:IsForbidden()) then
      local ok, _, rel = pcall(ch.GetPoint, ch, 1)
      if ok and (rel == Minimap or rel == cluster()) then scan(ch, 1) end
    end
  end
end
S.MinimapLooksLikeCoords = looksLikeCoords

-- what's around the minimap (for "/ccenter map frames": tell Fatedfr what still needs a home)
local function listFrames()
  local seen, out = {}, {}
  local function add(f, why)
    if not f or seen[f] or not f.GetName then return end
    seen[f] = true
    local n = f:GetName() or ("<" .. (f.GetObjectType and f:GetObjectType() or "?") .. ">")
    local x, y = f:GetCenter()
    local mx, my = Minimap:GetCenter()
    local where = (x and mx) and string.format("%+d,%+d", math.floor(x - mx), math.floor(y - my)) or "?"
    out[#out + 1] = string.format("%s  %s  %s%s", n, where, f:IsShown() and "shown" or "hidden", why or "")
  end
  for _, p in ipairs({ Minimap, cluster(), _G.MinimapBackdrop }) do
    if p then for _, ch in ipairs({ p:GetChildren() }) do if ch:GetName() then add(ch) end end end
  end
  for f in pairs(tidied) do add(f, "  (in a bar)") end
  for n, err in pairs(tidyErrors) do out[#out + 1] = n .. "  COULDN'T TUCK: " .. err end
  return out
end
S.MinimapListFrames = listFrames

---------------------------------------------------------------------------
-- "Tuck an icon into the bar": point at anything on or round the minimap and click it;
-- it moves into the bottom bar and stays there (saved by name).
---------------------------------------------------------------------------
local pickFrame
local pickedRegions = {}   -- texture tucked by hand -> { parent, points, w, h }
-- everything drawn on / round the minimap that could be "the icon": frames AND plain textures,
-- found by position (some of the game's icons don't take the mouse, so the click went through)
local function pickCandidates()
  local out, seen = {}, {}
  local function consider(o, depth, isRegion)
    if not o or seen[o] then return end
    seen[o] = true
    if o.IsForbidden and o:IsForbidden() then return end
    local n = o.GetName and o:GetName() or ""
    if n:find("^CC_") and n ~= "CC_Minimap" then return end
    if o == Minimap or o == cluster() or o == _G.MinimapBackdrop or o == ring or o == back or o == zoneBar or o == infoBar then
      -- containers: look inside
    elseif o.IsVisible and o:IsVisible() then
      local w, h = o:GetWidth() or 0, o:GetHeight() or 0
      if w >= 10 and h >= 10 and w <= 100 and h <= 100 and S.MinimapBelongs(o) then out[#out + 1] = { obj = o, region = isRegion } end
    end
    if isRegion or depth <= 0 then return end
    if o.GetRegions then
      for _, r in ipairs({ o:GetRegions() }) do
        if r.GetObjectType and r:GetObjectType() == "Texture" then consider(r, 0, true) end
      end
    end
    if o.GetChildren then for _, ch in ipairs({ o:GetChildren() }) do consider(ch, depth - 1) end end
  end
  consider(Minimap, 3); consider(cluster(), 3); consider(_G.MinimapBackdrop, 3)
  -- frames hung off UIParent next to the minimap
  for _, ch in ipairs({ UIParent:GetChildren() }) do
    if not (ch.IsForbidden and ch:IsForbidden()) then
      local ok, _, rel = pcall(ch.GetPoint, ch, 1)
      if ok and (rel == Minimap or rel == cluster() or rel == _G.MinimapBackdrop) then consider(ch, 2) end
    end
  end
  return out
end
local function pickTarget()
  local x, y = GetCursorPosition()
  local best, bestArea, bestFrame
  for _, c in ipairs(pickCandidates()) do
    local o = c.obj
    local l, r, t, b = o:GetLeft(), o:GetRight(), o:GetTop(), o:GetBottom()
    if l and r and t and b then
      local s = o:GetEffectiveScale()
      if x >= l * s and x <= r * s and y >= b * s and y <= t * s then
        local area = (r - l) * (t - b) * s * s
        -- the smallest thing under the cursor wins; a frame beats a texture of the same size
        local isFrame = not c.region
        if not best or area < bestArea - 1 or (math.abs(area - bestArea) <= 1 and isFrame and not bestFrame) then
          best, bestArea, bestFrame = c, area, isFrame
        end
      end
    end
  end
  if not best then return end
  local o = best.obj
  -- a texture inside a small button: take the button
  if best.region then
    local p = o:GetParent()
    if p and p ~= Minimap and p ~= cluster() and p ~= _G.MinimapBackdrop and (p:GetWidth() or 999) <= 100 and S.MinimapBelongs(p) then return p, false end
    return o, true
  end
  if not S.MinimapBelongs(o) then return end
  return o, false
end
local function describe(o)
  local n = o.GetName and o:GetName()
  local kind = o.GetObjectType and o:GetObjectType() or "?"
  local p = o.GetParent and o:GetParent()
  local pn = p and p.GetName and p:GetName() or "?"
  local extra = ""
  if kind == "Texture" and o.GetTexture then extra = " " .. tostring(o:GetTexture() or "") end
  return string.format("%s (%s%s, in %s, %dx%d)", n or "no name", kind, extra, pn, math.floor(o:GetWidth() or 0), math.floor(o:GetHeight() or 0))
end
-- a plain texture (no frame of its own) goes into a slot as it is
local function tuckRegion(tex, slotFrame)
  if pickedRegions[tex] then return end
  local rec = { parent = tex:GetParent(), points = {}, w = tex:GetWidth(), h = tex:GetHeight(), layer = { tex:GetDrawLayer() } }
  for i = 1, (tex:GetNumPoints() or 0) do rec.points[#rec.points + 1] = { tex:GetPoint(i) } end
  pickedRegions[tex] = rec
  tex:SetParent(slotFrame)
  tex:ClearAllPoints(); tex:SetSize(17, 17); tex:SetPoint("CENTER", slotFrame, "CENTER")
end
-- plain textures you tucked: back into the bar after a reload
function S._mmRestoreRegionTucks()
  local paths = type(cfg().tuckPaths) == "table" and cfg().tuckPaths or {}
  for path, kind in pairs(paths) do
    if kind == "region" then
      local tex = S.MinimapResolvePath(path)
      if tex and not S.MinimapBelongs(tex) and not pickedRegions[tex] then paths[path] = nil; tex = nil end
      if tex and not pickedRegions[tex] then
        local slotFrame = infoBar:RightSlot(math.max(3, (S.MinimapRightSlotsUsed() or 1) + 1))
        pcall(tuckRegion, tex, slotFrame)
      end
    end
  end
end
local function untuckRegions()
  for tex, rec in pairs(pickedRegions) do
    pcall(function()
      tex:SetParent(rec.parent); tex:SetSize(rec.w or 16, rec.h or 16); tex:ClearAllPoints()
      for _, pt in ipairs(rec.points) do tex:SetPoint(unpack(pt)) end
    end)
  end
  wipe(pickedRegions)
end

function S:MinimapPickTuck()
  if not active() or not cfg().tidy then S:Print("Turn on the minimap look and \"Mail, tracking and calendar buttons in the bars\" first.") return end
  if inCombat() then S:Print("You can tuck icons after combat.") return end
  if not pickFrame then
    -- a see-through sheet over the whole screen catches the click, so nothing underneath gets it
    pickFrame = CreateFrame("Button", "CC_MinimapPick", UIParent)
    pickFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    pickFrame:SetAllPoints(WorldFrame or UIParent)
    pickFrame:EnableMouse(true)
    pickFrame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    pickFrame.shade = pickFrame:CreateTexture(nil, "BACKGROUND"); pickFrame.shade:SetAllPoints(); pickFrame.shade:SetColorTexture(0, 0, 0, 0.15)
    pickFrame.banner = CreateFrame("Frame", nil, pickFrame); pickFrame.banner:SetSize(520, 46)
    pickFrame.banner:SetPoint("TOP", UIParent, "TOP", 0, -90)
    pickFrame.banner.text = UI:Text(pickFrame.banner, "", nil, "CENTER"); pickFrame.banner.text:SetPoint("CENTER")
    pickFrame.tip = CreateFrame("Frame", nil, pickFrame); pickFrame.tip:SetSize(300, 22)
    pickFrame.tip.text = UI:Text(pickFrame.tip, "", "small", "LEFT"); pickFrame.tip.text:SetPoint("LEFT", 8, 0)
    pickFrame.glow = CreateFrame("Frame", nil, pickFrame)
    pickFrame.glow.tex = pickFrame.glow:CreateTexture(nil, "OVERLAY"); pickFrame.glow.tex:SetAllPoints()
    pickFrame.glow.tex:SetTexture(UI.ART.glow); pickFrame.glow.tex:SetBlendMode("ADD")
    UI:Skin(pickFrame, function(self, th)
      UI.Flat(self.banner, th.panel, 0.95, th.gold, 1)
      UI.Flat(self.tip, th.panel, 0.95, th.gold, 0.8)
      self.banner.text:SetTextColor(th.text[1], th.text[2], th.text[3])
      self.tip.text:SetTextColor(th.gold[1], th.gold[2], th.gold[3])
      self.glow.tex:SetVertexColor(th.gold[1], th.gold[2], th.gold[3], 1)
    end)
    pickFrame:SetScript("OnClick", function(self, btn)
      if btn == "RightButton" then self:Hide() return end
      local t, isRegion = pickTarget()
      if not t then S:Print("Minimap: nothing there - point right at the icon on the minimap.") return end
      local n = t.GetName and t:GetName()
      local path = not n and S.MinimapPathOf(t) or nil
      S:Print("Minimap: tucking " .. (path or describe(t)) .. " into the bottom bar.")
      if path then
        -- no name of its own: remember where it lives so it goes in by itself next time
        local c = cfg(); c.tuckPaths = type(c.tuckPaths) == "table" and c.tuckPaths or {}
        c.tuckPaths[path] = isRegion and "region" or "frame"
        pathCache[path] = t
      end
      if isRegion then
        local slotFrame = infoBar:RightSlot(math.max(3, (S.MinimapRightSlotsUsed() or 1) + 1))
        local ok, err = pcall(tuckRegion, t, slotFrame)
        if not ok then S:Print("Minimap: couldn't move it (" .. tostring(err):gsub("^.-:%d+: ", "") .. ").") end
      elseif n then
        local c = cfg(); c.tuck = type(c.tuck) == "table" and c.tuck or {}; c.tuck[n] = true
      elseif not path then
        picked[t] = true
      end
      if n then tidyErrors[n] = nil end
      self:Hide()
      C_Timer.After(0.05, function() if tidyAll then tidyAll() end end)
    end)
    pickFrame:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)
  end
  pickFrame.banner.text:SetText("|cffffd100Tuck an icon into the bar|r - click the icon on the minimap.  Right-click to cancel.")
  pickFrame:Show()
  local started = GetTime()
  pickFrame:SetScript("OnUpdate", function(self)
    local x, y = GetCursorPosition()
    local sc = UIParent:GetEffectiveScale()
    self.tip:ClearAllPoints()
    self.tip:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x / sc - (UIParent:GetLeft() or 0) + 18, y / sc - (UIParent:GetBottom() or 0) + 12)
    local t = pickTarget()
    if t then
      self.glow:ClearAllPoints()
      self.glow:SetPoint("TOPLEFT", t, "TOPLEFT", -6, 6)
      self.glow:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", 6, -6)
      self.glow:Show()
      local name = (t.GetName and t:GetName()) or "(no name)"
      self.tip.text:SetText(name)
    else
      self.glow:Hide()
      self.tip.text:SetText("point at the icon")
    end
    self.tip:SetWidth(math.max(120, self.tip.text:GetStringWidth() + 16))
    if GetTime() - started > 60 then self:Hide() end
  end)
end
function S:MinimapUntuckAll()
  cfg().tuck = nil; cfg().tuckPaths = nil; wipe(picked); wipe(tidyErrors)
  untuckRegions()
  untidyAll()
  S:ApplyMinimap()
end

---------------------------------------------------------------------------
-- Apply / remove the whole look
---------------------------------------------------------------------------
local pending, applied
local function setMask(k)
  local tex = k and (MEDIA .. "UI\\rmask" .. k) or ROUND_MASK
  pcall(Minimap.SetMaskTexture, Minimap, tex)
  -- newer clients draw some maps through HybridMinimap with its own mask
  local hm = _G.HybridMinimap
  if hm then
    if hm.CircleMask and hm.CircleMask.SetTexture then pcall(hm.CircleMask.SetTexture, hm.CircleMask, tex) end
    if hm.MapCanvas and hm.MapCanvas.SetUseMaskTexture then pcall(hm.MapCanvas.SetUseMaskTexture, hm.MapCanvas, true) end
  end
end

function S:ApplyMinimap()
  if not S.db or not Minimap then return end
  if inCombat() then pending = true return end
  pending = false
  local c = cfg()
  local on = c.on and true or false
  if on then
    buildPieces()
    if not ring.__skinned then ring.__skinned = true; UI:Skin(ring, skinRing) end
    setMask(roundK())
    setArt("border", true)
    setArt("top", true, true)
    setArt("zone", c.zone)
    setArt("zoom", c.hideZoom)
    setArt("world", c.hideWorldBtn)
    setArt("clock", c.clock)
    back:Show(); ring:Show()
    layoutPieces()
    skinRing(nil, UI:Theme())
    setWheel(c.wheel)
    if c.tidy then tidyAll() else untidyAll() end
    slideIndicators(roundK() < 5)
  else
    if applied then
      untidyAll()
      setMask(nil)
      for _, kind in ipairs({ "border", "top", "zone", "zoom", "world", "clock" }) do setArt(kind, false) end
      slideIndicators(false)
    end
    if back then back:Hide(); ring:Hide(); zoneBar:Hide(); infoBar:Hide(); infoBar:SetScript("OnUpdate", nil) end
    if mover then mover:Hide() end
    setWheel(false)
  end
  applyScaleAndPos()
  skinAllButtons()
  setFade(on and c.fadeButtons)
  setDrawer(on and c.drawer and S.ShowButtonBox ~= nil)
  pcall(hideDupCoords, on and c.coords and c.hideDupCoords)   -- never let this stop the rest of the apply
  applied = on or applied
  zoomChanged()
  fireChange()
  if S.RefreshMinimapSettings then S:RefreshMinimapSettings() end
end

-- events
-- Housekeeping for buttons that arrive late (addons keep adding minimap buttons for a while
-- after login): every 4 s for the first minute only. After that it runs only when an addon
-- loads or the minimap's number of children changes (checked every 2 s - just a count).
-- Each part is timed for /ccenter perf.
local wrap = function(name, fn) if S.PerfWrap then return S.PerfWrap(name, fn) end return fn end
local houseSkin = wrap("Minimap  housekeeping: skin buttons", function() skinAllButtons() end)
local houseTidy = wrap("Minimap  housekeeping: tidy bars", function()
  if cfg().tidy then tidyAll() end
  if roundK() < 5 then slideIndicators(true) end
end)
local houseBox = wrap("Minimap  housekeeping: fill box", function() fillBox() end)
local houseCoords = wrap("Minimap  housekeeping: other coords", function()
  if cfg().coords and cfg().hideDupCoords then pcall(hideDupCoords, true) end
end)
local function housekeeping(full)
  if not active() or inCombat() then return end
  houseSkin(); houseTidy(); houseBox()
  if full then houseCoords() end
end
S.MinimapHousekeeping = housekeeping
local ticker, watch, lastKey, queued
local function queueHousekeeping(full)
  if queued then return end
  queued = true
  C_Timer.After(1, function() queued = false; housekeeping(full) end)
end
S:Listen("LOGIN", function()
  cfg()
  C_Timer.After(0.5, function() S:ApplyMinimap() end)
  if not ticker and C_Timer.NewTicker then
    ticker = C_Timer.NewTicker(4, function() housekeeping(true) end, 15)   -- the first minute
    C_Timer.After(61, function()
      -- the raw child count changes whenever a quest / map pin appears, so only a change in
      -- the addon buttons themselves (or LibDataBroker launchers) starts housekeeping
      lastKey = buttonSig()
      watch = C_Timer.NewTicker(2, function()
        if inCombat() then return end
        local k = buttonSig()
        if k ~= lastKey then lastKey = k; queueHousekeeping(false) end
      end)
    end)
  end
end)
S:On("ADDON_LOADED", function(_, name)
  if name ~= "CommandCenter" and S.db and watch then queueHousekeeping(true) end
end)
S:On("PLAYER_ENTERING_WORLD", function() if S.db and applied then C_Timer.After(0.2, function() S:ApplyMinimap() end) end end)
S:On("PLAYER_REGEN_ENABLED", function() if pending then S:ApplyMinimap() end end)
S:On("ADDON_LOADED", function(_, name)
  if name == "Blizzard_TimeManager" and S.db and active() then setArt("clock", cfg().clock) end
end)
for _, ev in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA" }) do
  S:On(ev, function() if active() then updateZone() end end)
end
for _, ev in ipairs({ "UPDATE_BATTLEFIELD_STATUS", "UPDATE_PENDING_MAIL", "LFG_UPDATE" }) do
  S:On(ev, function() if active() and roundK() < 5 then C_Timer.After(0, function() slideIndicators(true) end) end end)
end
-- our own Command Center button follows the edge
S:OnMinimapChange(function() if S.UpdateMinimap and S.db then S:UpdateMinimap() end end)

---------------------------------------------------------------------------
-- Settings window
---------------------------------------------------------------------------
local win
local function set(key, v) cfg()[key] = v; S:ApplyMinimap() end
local function moveAnyActive()
  local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("MoveAny")) or (IsAddOnLoaded and IsAddOnLoaded("MoveAny"))
  return loaded and true or false
end

function S:ShowMinimapSettings()
  if not win then
    win = UI:Window("CC_MinimapSettings", "Minimap", 440, 640)
    local c = cfg()
    local y = -44
    local function row(f, x, dy) f:SetPoint("TOPLEFT", x or 16, y); y = y - (dy or 26) end
    local function check(label, key, tip)
      local cb = UI:Check(win, label, cfg()[key], function(v) set(key, v) end, tip)
      row(cb, 16, 24); win.ctl[key] = cb
      return cb
    end
    win.ctl = {}
    win.ctl.on = check("Command Center minimap look", "on", "Your theme's colours and trim on the minimap, a zone bar, clock and coordinates. Off = the game's own minimap.")
    y = y - 4
    local h1 = UI:Header(win, "Shape and size"); row(h1, 16, 26)
    win.ctl.round = UI:Slider(win, 400, "Shape", 0, 5, 1, c.round, function(v) set("round", v) end, function(v) return ROUND_NAMES[math.floor(v + 0.5)] or "" end)
    row(win.ctl.round, 16, 28)
    win.ctl.scale = UI:Slider(win, 400, "Size", 70, 160, 5, math.floor((c.scale or 1) * 100 + 0.5), function(v) set("scale", v / 100) end, function(v) return math.floor(v + 0.5) .. "%" end)
    row(win.ctl.scale, 16, 28)
    check("Themed border", "ring", "A frame in your theme's colours around the map.")
    check("Thin accent line around the border", "accent")
    y = y - 4
    local h2 = UI:Header(win, "Bars"); row(h2, 16, 26)
    check("Zone name bar (click: world map)", "zone", "Coloured like the game does it: blue sanctuary, green friendly, red hostile, orange contested.")
    check("Clock (click: stopwatch and alarm)", "clock", "Follows the game's clock settings (local or server time, 24-hour). Right-click it to switch between local and server time.")
    check("Coordinates", "coords")
    y = y - 4
    local h3 = UI:Header(win, "Zoom and buttons"); row(h3, 16, 26)
    check("Zoom with the mouse wheel", "wheel")
    check("Hide the + / - zoom buttons", "hideZoom")
    check("Hide the world map button", "hideWorldBtn")
    win.ctl.autoZoom = UI:Slider(win, 400, "Zoom back out after", 0, 60, 5, c.autoZoom or 0, function(v) set("autoZoom", v) end,
      function(v) v = math.floor(v + 0.5); return v == 0 and "Never" or (v .. " s") end)
    row(win.ctl.autoZoom, 16, 28)
    check("Theme other addons' minimap buttons", "skinButtons", "Their round gold border becomes your theme's ring. Buttons with their own art are left as they are.")
    check("Show addon buttons only when the mouse is over the minimap", "fadeButtons", "The Command Center button stays visible while it has new notifications.")
    check("Addon buttons in a drawer (Button Box under the minimap)", "drawer", "A small button on the zone bar opens the Button Box, docked to the minimap. Every addon's minimap icon goes in it and leaves the minimap edge. Take one out and it stays out.")
    check("Mail, tracking and calendar buttons in the bars", "tidy", "Mail at the left of the zone bar, tracking (magnifying glass) at the left of the bottom bar, calendar at its right.")
    check("Hide other addons' coordinates next to the minimap", "hideDupCoords", "When another addon also writes your coordinates under the minimap, only Command Center's line shows.")
    y = y - 6
    win.move = UI:Button(win, "Unlock to move", 130, 22, function() S:MinimapUnlock(not (mover and mover:IsShown())) end, "Drag the minimap anywhere. Right-click it (or press Lock) when done.")
    row(win.move, 16, 0)
    win.reset = UI:Button(win, "Reset position", 120, 22, function() S:MinimapResetPos() end, "Back to where the game puts it.")
    win.reset:SetPoint("TOPLEFT", 156, y)
    win.def = UI:Button(win, "Defaults", 90, 22, function()
      local g = G(); local pos = g.mmSkin and g.mmSkin.pos
      g.mmSkin = { pos = pos }; cfg(); S:ApplyMinimap()
    end, "Every option above back to its default (keeps the position).")
    win.def:SetPoint("TOPLEFT", 286, y)
    y = y - 30
    win.tuck = UI:Button(win, "Tuck an icon into the bar...", 200, 22, function() S:MinimapPickTuck() end,
      "Something still sitting on the map? Click this, then click the icon: it moves into the bottom bar and stays there.")
    win.tuck:SetPoint("TOPLEFT", 16, y)
    win.untuck = UI:Button(win, "Put tucked icons back", 170, 22, function() S:MinimapUntuckAll() end)
    win.untuck:SetPoint("TOPLEFT", 226, y)
    y = y - 30
    win.note = UI:Text(win, "", "small")
    win.note:SetPoint("TOPLEFT", 16, y); win.note:SetWidth(408)
    win:SetHeight(-y + 46)
  end
  S:RefreshMinimapSettings()
  win:Show()
end
function S:HideMinimapSettings() if win then win:Hide() end end
function S:RefreshMinimapSettings()
  if not win then return end
  local c = cfg()
  for key, cb in pairs(win.ctl) do
    if cb.SetChecked then cb:SetChecked(c[key] and true or false) end
  end
  local function slider(f, v) if f and f.SetValue then f.quiet = true; pcall(f.SetValue, f, v); f.quiet = false end end
  slider(win.ctl.round, c.round); slider(win.ctl.scale, math.floor((c.scale or 1) * 100 + 0.5)); slider(win.ctl.autoZoom, c.autoZoom or 0)
  local unlocked = mover and mover:IsShown()
  win.move:SetText(unlocked and "Lock" or "Unlock to move")
  local notes = {}
  if moveAnyActive() then notes[#notes + 1] = "|cffff9933MoveAny is on:|r if it moves your minimap too, use only one of them for the position." end
  if c.pos then notes[#notes + 1] = "Moved by you - Reset position puts it back." end
  notes[#notes + 1] = "|cff888888Other addons' buttons can also go into your dock, border bar or Button Box (Settings > Plugins).|r"
  win.note:SetText(table.concat(notes, "\n"))
end

-- right-click on the zone bar
function S:MinimapMenu2(anchor)
  GameTooltip:Hide()
  local c = cfg()
  UI:Menu(anchor, {
    { text = "Minimap", title = true },
    { text = "Minimap settings...", func = function() S:ShowMinimapSettings() end },
    { text = (mover and mover:IsShown()) and "Lock the minimap" or "Unlock to move", func = function() S:MinimapUnlock(not (mover and mover:IsShown())) end },
    { text = "Reset position", disabled = not c.pos, func = function() S:MinimapResetPos() end },
    { text = "Tuck an icon into the bar...", func = function() S:MinimapPickTuck() end },
    { text = "Put tucked icons back", disabled = not ((type(c.tuck) == "table" and next(c.tuck)) or (type(c.tuckPaths) == "table" and next(c.tuckPaths))), func = function() S:MinimapUntuckAll() end },
    { text = "Shape", title = true },
    { text = "Round", checked = roundK() == 5, func = function() set("round", 5) end },
    { text = "Rounded square", checked = roundK() == 2, func = function() set("round", 2) end },
    { text = "Square", checked = roundK() == 0, func = function() set("round", 0) end },
  })
end

S:AddCommand("map", "", "Minimap look: shape, size, zone bar, clock, coordinates", function(rest)
  rest = (rest or ""):lower()
  if rest == "off" then set("on", false); S:Print("Minimap: the game's own look.")
  elseif rest == "on" then set("on", true)
  elseif rest == "unlock" or rest == "move" then S:MinimapUnlock(true)
  elseif rest == "lock" then S:MinimapUnlock(false)
  elseif rest == "reset" then S:MinimapResetPos()
  elseif rest == "tuck" then S:MinimapPickTuck()
  elseif rest == "untuck" then S:MinimapUntuckAll()
  elseif rest == "frames" then
    S:Print("Frames around the minimap (name, offset from its centre, shown):")
    for _, l in ipairs(listFrames()) do print("  " .. l) end
  else S:ShowMinimapSettings() end
end)
