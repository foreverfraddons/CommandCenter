-- Screenshot studio: a small panel to tune the picture (brightness, contrast, gamma,
-- view distance, shadows ...) while you look at the world, then one button hides the
-- whole interface, takes the picture and brings the interface back.
-- Game settings changed here go back to how they were when the panel closes, unless
-- "Keep these settings" is ticked.
local _, S = ...
local UI = S.UI

local function G() return S.db.global end
local function cfg()
  local g = G()
  g.snap = type(g.snap) == "table" and g.snap or { hideNames = true, countdown = 0, keep = false }
  return g.snap
end

local function getCVar(name)
  local v
  if C_CVar and C_CVar.GetCVar then v = C_CVar.GetCVar(name) elseif GetCVar then v = GetCVar(name) end
  return v
end
local function setCVar(name, value)
  if C_CVar and C_CVar.SetCVar then return pcall(C_CVar.SetCVar, name, tostring(value)) end
  if SetCVar then return pcall(SetCVar, name, tostring(value)) end
end

-- each setting lists the CVar names it may have in this client; the first one that
-- exists is used, settings this client doesn't have are left out
local SETTINGS = {
  { label = "Brightness", cvars = { "Brightness" }, min = 0, max = 100, step = 1 },
  { label = "Contrast", cvars = { "Contrast" }, min = 0, max = 100, step = 1 },
  { label = "Gamma", cvars = { "Gamma" }, min = 0.3, max = 2.8, step = 0.05, fmt = function(v) return string.format("%.2f", v) end },
  { label = "View distance", cvars = { "graphicsViewDistance" }, min = 1, max = 10, step = 1 },
  { label = "View distance", cvars = { "farclip" }, min = 177, max = 2600, step = 1, alt = true },
  { label = "Ground clutter", cvars = { "graphicsGroundClutter" }, min = 1, max = 10, step = 1 },
  { label = "Shadows", cvars = { "graphicsShadowQuality" }, min = 1, max = 6, step = 1 },
  { label = "Particles", cvars = { "graphicsParticleDensity" }, min = 1, max = 6, step = 1 },
  { label = "Sun shafts", cvars = { "graphicsSunshafts" }, min = 1, max = 3, step = 1 },
  { label = "Picture quality", cvars = { "screenshotQuality" }, min = 1, max = 10, step = 1, file = true },
}
local FORMATS = { { value = "jpg", text = "JPG (small file)" }, { value = "png", text = "PNG (best quality)" }, { value = "tga", text = "TGA (huge)" } }

-- the names over heads and nameplates are drawn by the game world, not the interface,
-- so they are switched off with game settings for the moment of the picture
local NAME_CVARS = { "UnitNameOwn", "UnitNameNPC", "UnitNameFriendlyPlayerName", "UnitNameEnemyPlayerName",
  "UnitNameFriendlyPetName", "UnitNameEnemyPetName", "UnitNameFriendlyGuardianName", "UnitNameEnemyGuardianName",
  "UnitNameGuildTitle", "UnitNamePlayerGuild", "UnitNamePlayerPVPTitle", "UnitNameNonCombatCreatureName",
  "nameplateShowAll", "nameplateShowEnemies", "nameplateShowFriends", "floatingCombatTextCombatDamage", "enableFloatingCombatText" }

local win
local before = {}          -- cvar -> value when the panel opened (only ones we touched)
local function remember(cv) if before[cv] == nil then before[cv] = getCVar(cv) end end
local function restoreAll()
  for cv, v in pairs(before) do if v ~= nil then setCVar(cv, v) end end
  before = {}
end

---------------------------------------------------------------------------
-- Taking the picture
---------------------------------------------------------------------------
local busy = false
local savedNames
local failsafe
local function after(sec, fn) if C_Timer and C_Timer.After then C_Timer.After(sec, fn) else fn() end end

local function bringBack()
  if not busy then return end
  if failsafe then failsafe.cancelled = true; failsafe = nil end
  if savedNames then for cv, v in pairs(savedNames) do setCVar(cv, v) end; savedNames = nil end
  if not UIParent:IsShown() then
    if InCombatLockdown and InCombatLockdown() then
      S:Print("Combat started - press |cffffd100Alt+Z|r to bring your interface back.")
    else
      UIParent:Show()                            -- still "busy": the panel's OnShow keeps its undo list
    end
  end
  busy = false
end

local function snap()
  if InCombatLockdown and InCombatLockdown() then
    S:Print("Pictures without the interface can't be taken in combat.") return
  end
  busy = true
  if cfg().hideNames then
    savedNames = {}
    for _, cv in ipairs(NAME_CVARS) do
      local v = getCVar(cv)
      if v ~= nil then savedNames[cv] = v; setCVar(cv, 0) end
    end
  end
  UIParent:Hide()
  -- give the game a moment to draw the frame without the interface
  after(0.25, function()
    if not busy then return end
    if Screenshot then Screenshot() elseif TakeScreenshot then TakeScreenshot() end
    -- if the game never says it's done, come back anyway
    local token = {}
    failsafe = token
    after(4, function() if failsafe == token and not token.cancelled then bringBack() end end)
  end)
end

local cd
function S:SnapTakePicture()
  if busy then return end
  if InCombatLockdown and InCombatLockdown() then UI:Alert("Pictures without the interface can't be taken in combat.") return end
  local n = tonumber(cfg().countdown) or 0
  if n <= 0 then snap() return end
  if not cd then
    cd = CreateFrame("Frame", "CC_SnapCountdown", UIParent)
    cd:SetSize(200, 120); cd:SetPoint("CENTER", 0, 120); cd:SetFrameStrata("FULLSCREEN_DIALOG")
    cd.text = cd:CreateFontString(nil, "OVERLAY"); cd.text:SetFont("Fonts\\FRIZQT__.TTF", 72, "OUTLINE"); cd.text:SetPoint("CENTER")
    cd.text:SetTextColor(1, 0.82, 0)
  end
  local left = n
  cd.text:SetText(left); cd:Show()
  local function tick()
    left = left - 1
    if left <= 0 then cd:Hide(); snap() return end
    cd.text:SetText(left)
    after(1, tick)
  end
  after(1, tick)
end

S:On("SCREENSHOT_SUCCEEDED", function()
  if not busy then return end
  after(0.1, function()
    bringBack()
    S:Print("Picture saved in your |cffffd100Screenshots|r folder.")
  end)
end)
S:On("SCREENSHOT_FAILED", function()
  if not busy then return end
  bringBack()
  S:Print("|cffff5555The game couldn't save the picture.|r")
end)
-- never leave the interface hidden going into a fight
S:On("PLAYER_REGEN_DISABLED", function() if busy then bringBack() end end)

---------------------------------------------------------------------------
-- The panel
---------------------------------------------------------------------------
local function available(st)
  for _, cv in ipairs(st.cvars) do if getCVar(cv) ~= nil then return cv end end
end

local function syncSliders()
  if not win then return end
  for _, row in ipairs(win.sliders) do
    local v = tonumber(getCVar(row.cv))
    if v then row.slider:SetValue(math.max(row.st.min, math.min(row.st.max, v))) end
  end
  if win.format then win.format:SetValue(getCVar("screenshotFormat") or "jpg") end
end

local function build()
  local rows, seenLabel = {}, {}
  for _, st in ipairs(SETTINGS) do
    local cv = available(st)
    if cv and not seenLabel[st.label] then seenLabel[st.label] = true; rows[#rows + 1] = { st = st, cv = cv } end
  end
  local H = 38 + 24 + #rows * 28 + 34 + 30 + 30 + 30 + 48
  win = UI:Window("CC_Snap", "Screenshot", 400, H)
  win:SetFrameStrata("HIGH")
  win:ClearAllPoints(); win:SetPoint("RIGHT", UIParent, "RIGHT", -40, 0)
  -- this panel isn't closed by Escape (Escape would also undo the picture settings)
  if UISpecialFrames then
    for i = #UISpecialFrames, 1, -1 do if UISpecialFrames[i] == "CC_Snap" then table.remove(UISpecialFrames, i) end end
  end
  local y = -38
  local hint = UI:Text(win, "|cffaaaaaaChanges show in the game straight away.|r", "small")
  hint:SetPoint("TOPLEFT", 16, y); y = y - 24
  win.sliders = {}
  for _, row in ipairs(rows) do
    local st, cv = row.st, row.cv
    row.slider = UI:Slider(win, 368, st.label, st.min, st.max, st.step, tonumber(getCVar(cv)) or st.min, function(v)
      remember(cv); setCVar(cv, v)
    end, st.fmt)
    row.slider:SetPoint("TOPLEFT", 16, y); y = y - 28
    win.sliders[#win.sliders + 1] = row
  end
  if getCVar("screenshotFormat") ~= nil then
    local fl = UI:Text(win, "File type", "small"); fl:SetPoint("TOPLEFT", 16, y - 4)
    win.format = UI:Dropdown(win, 170, FORMATS, getCVar("screenshotFormat") or "jpg", function(v) remember("screenshotFormat"); setCVar("screenshotFormat", v) end)
    win.format:SetPoint("TOPLEFT", 152, y)
  end
  y = y - 34
  win.names = UI:Check(win, "Hide names and nameplates in the picture", cfg().hideNames ~= false, function(on) cfg().hideNames = on end)
  win.names:SetPoint("TOPLEFT", 16, y); y = y - 30
  win.count = UI:Check(win, "3 second countdown (time to pose)", (cfg().countdown or 0) > 0, function(on) cfg().countdown = on and 3 or 0 end)
  win.count:SetPoint("TOPLEFT", 16, y); y = y - 30
  win.keep = UI:Check(win, "Keep these game settings after closing", cfg().keep, function(on) cfg().keep = on end,
    "Off: brightness, view distance and the rest go back to how they were when you close this panel.")
  win.keep:SetPoint("TOPLEFT", 16, y)

  local go = UI:PrimaryButton(win, "Take picture", 150, 28, function() S:SnapTakePicture() end,
    "Hides the whole interface, takes the picture and brings it back.")
  go:SetPoint("BOTTOMRIGHT", -14, 14)
  local undo = UI:Button(win, "Undo changes", 110, 28, function() restoreAll(); syncSliders() end,
    "Put every setting back to how it was when you opened this panel.")
  undo:SetPoint("BOTTOMLEFT", 14, 14)

  win:HookScript("OnShow", function()
    if busy then return end                     -- back from taking a picture: keep the undo list
    before = {}; syncSliders()
  end)
  win:HookScript("OnHide", function()
    if busy then return end                     -- hidden with the interface for the picture
    if not cfg().keep then restoreAll() else before = {} end
  end)
end

function S:ShowSnap()
  if not win then build() end
  win:Show(); win:Raise()
end
function S:HideSnap() if win then win:Hide() end end
S.SnapBusy = function() return busy end

S:AddCommand("screenshot", "", "Screenshot studio: tune the picture, then take it without the interface", function() S:ShowSnap() end)
