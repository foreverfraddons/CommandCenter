-- Notifications: a bell in the top-right of the hub with an unread counter, a
-- matching number on the minimap button, and a list you can click through.
local _, S = ...
local UI = S.UI

local MAX_KEEP = 40

---------------------------------------------------------------------------
-- "Is this record new to me?"  Records created after the last time I was
-- online (or after this session started) count as new.
---------------------------------------------------------------------------
local watermark
S:Listen("GUILD_READY", function()
  local loc = S.G.loc
  watermark = loc.lastSeen or S.now()
  loc.lastSeen = loc.lastSeen or S.now()
end)
S:On("PLAYER_LOGIN", function()
  C_Timer.NewTicker(60, function() if S.G then S.G.loc.lastSeen = S.now() end end)
end)
S:On("PLAYER_LOGOUT", function() if S.G then S.G.loc.lastSeen = S.now() end end)

function S:IsFresh(rec)
  return rec and not rec._d and watermark ~= nil and (rec._t or 0) > watermark and rec._b ~= S.me
end

---------------------------------------------------------------------------
-- API
---------------------------------------------------------------------------
local function list()
  S.G.loc.notifs = S.G.loc.notifs or {}
  return S.G.loc.notifs
end

-- opts: { title, text, icon, tab, action = "mail"|"announcement"|..., arg }
function S:Notify(key, opts)
  if not self.G then return end
  local l = list()
  for _, n in ipairs(l) do if n.key == key then return end end
  table.insert(l, 1, { key = key, title = opts.title, text = opts.text, icon = opts.icon, tab = opts.tab,
    action = opts.action, arg = opts.arg, time = S.now(), read = false })
  while #l > MAX_KEEP do table.remove(l) end
  if PlaySound and SOUNDKIT and SOUNDKIT.TELL_MESSAGE and opts.sound ~= false then PlaySound(SOUNDKIT.TELL_MESSAGE) end
  S:Fire("NOTIFY")
end

function S:UnreadNotifs()
  if not self.G then return 0 end
  local n = 0
  for _, x in ipairs(list()) do if not x.read then n = n + 1 end end
  return n
end

function S:RemoveNotifs(prefix)
  if not self.G then return end
  local l = list()
  for i = #l, 1, -1 do if l[i].key and l[i].key:sub(1, #prefix) == prefix then table.remove(l, i) end end
  S:Fire("NOTIFY")
end
function S:ReadNotif(key)
  if not self.G then return end
  for _, x in ipairs(list()) do if x.key == key and not x.read then x.read = true; S:Fire("NOTIFY") return end end
end
function S:MarkAllNotifs() if self.G then for _, x in ipairs(list()) do x.read = true end S:Fire("NOTIFY") end end
function S:ClearNotifs() if self.G then wipe(list()) S:Fire("NOTIFY") end end

S.notifyActions = {}   -- action name -> fn(arg)

function S:OpenNotif(n)
  n.read = true
  S:Fire("NOTIFY")
  local fn = n.action and S.notifyActions[n.action]
  if n.tab then S:ShowMain(n.tab) end
  if fn then fn(n.arg) end
end

---------------------------------------------------------------------------
-- Badge (red bubble with a number)
---------------------------------------------------------------------------
function UI:Badge(parent, size)
  size = size or 16
  local b = CreateFrame("Frame", nil, parent)
  b:SetSize(size, size)
  b:SetFrameLevel(parent:GetFrameLevel() + 5)
  -- dark outline, red disc, soft top highlight: clean anti-aliased circles from Media\UI\disc
  local edge = b:CreateTexture(nil, "BACKGROUND")
  edge:SetTexture(UI.MEDIA .. "UI\\disc"); edge:SetPoint("CENTER"); edge:SetSize(size + 3, size + 3)
  edge:SetVertexColor(0.05, 0.03, 0.02, 0.95)
  local bg = b:CreateTexture(nil, "ARTWORK")
  bg:SetTexture(UI.MEDIA .. "UI\\disc"); bg:SetAllPoints()
  bg:SetVertexColor(0.86, 0.12, 0.10, 1)
  local shine = b:CreateTexture(nil, "ARTWORK", nil, 1)
  shine:SetTexture(UI.MEDIA .. "UI\\disc"); shine:SetPoint("TOP", 0, -1); shine:SetSize(size * 0.62, size * 0.36)
  shine:SetVertexColor(1, 1, 1, 0.18)
  b.text = b:CreateFontString(nil, "OVERLAY")
  b.text:SetFont("Fonts\\FRIZQT__.TTF", math.max(8, math.floor(size * 0.62)), "")
  b.text:SetShadowOffset(1, -1); b.text:SetShadowColor(0, 0, 0, 0.9)
  b.text:SetTextColor(1, 1, 1)
  b.text:SetPoint("CENTER", 0.5, 0)
  function b:SetCount(n)
    if not n or n <= 0 then self:Hide() return end
    local txt = n > 9 and "9+" or tostring(n)
    self.text:SetText(txt)
    -- two characters: stretch into a pill so the number never crowds the edge
    local w = (#txt > 1) and math.floor(size * 1.4) or size
    self:SetWidth(w); edge:SetSize(w + 3, size + 3)
    self:Show()
  end
  b:Hide()
  return b
end

---------------------------------------------------------------------------
-- Bell + dropdown list (built into the main window)
---------------------------------------------------------------------------
local bell, panel, tbl

local function buildPanel(main)
  panel = CreateFrame("Frame", "CC_NotifPanel", main, BackdropTemplateMixin and "BackdropTemplate" or nil)
  panel:SetSize(380, 300)
  panel:SetPoint("TOPRIGHT", bell, "BOTTOMRIGHT", 6, -4)
  panel:SetFrameStrata("DIALOG")
  UI:DialogBackdrop(panel, true)
  panel:EnableMouse(true)
  local h = UI:Header(panel, "Notifications"); h:SetPoint("TOPLEFT", 18, -16)
  local all = UI:Button(panel, "Mark all read", 100, 20, function() S:MarkAllNotifs() end)
  all:SetPoint("TOPRIGHT", -16, -14)
  local clr = UI:Button(panel, "Clear", 60, 20, function() S:ClearNotifs() end)
  clr:SetPoint("RIGHT", all, "LEFT", -4, 0)
  tbl = UI:Table(panel, 344, 238, {
    { title = "", w = 22, get = function(n) return "|T" .. (n.icon or "Interface\\Icons\\INV_Misc_Note_01") .. ":16:16:0:0:64:64:5:59:5:59|t" end },
    { title = "What", w = 250, get = function(n)
      local txt = n.text
      -- streamer mode: never show what a message says
      if (S.StreamerOn and S.StreamerOn("whispers") or (not S.StreamerOn and S.db.global.streamer)) and (n.action == "mail" or n.action == "whisper") then txt = "|cff666666(hidden - streamer mode)|r" end
      return (n.read and "|cffaaaaaa" or "|cffffffff") .. (n.title or "") .. "|r" .. (txt and txt ~= "" and ("  |cff888888" .. txt .. "|r") or "")
    end },
    { title = "When", w = 64, get = function(n) return S.Ago(n.time) end },
  }, { rowH = 22, emptyText = "You're all caught up!", onClick = function(n)
    panel:Hide()
    S:OpenNotif(n)
  end, onEnter = function(n, f)
    GameTooltip:SetOwner(f, "ANCHOR_LEFT")
    GameTooltip:SetText(n.title or "", 1, 0.82, 0)
    if n.text and not ((S.StreamerOn and S.StreamerOn("whispers") or (not S.StreamerOn and S.db.global.streamer)) and (n.action == "mail" or n.action == "whisper")) then GameTooltip:AddLine(n.text, 1, 1, 1, true) end
    GameTooltip:AddLine(S.date(n.time, "%Y-%m-%d %H:%M"), 0.6, 0.6, 0.6)
    GameTooltip:Show()
  end })
  tbl:SetPoint("TOPLEFT", 16, -42)
  panel:SetScript("OnShow", function() tbl:SetData(S.G and list() or {}) end)
  panel:Hide()
end

function S:CreateBell(main)
  bell = CreateFrame("Button", nil, main)
  S.bellFrame = bell
  bell:SetSize(30, 30)
  bell:SetPoint("TOPRIGHT", -40, -10)
  local icon = bell:CreateTexture(nil, "ARTWORK")
  icon:SetTexture("Interface\\Icons\\INV_Misc_Bell_01"); icon:SetAllPoints(); icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  bell.icon = icon
  local ring = bell:CreateTexture(nil, "OVERLAY")
  ring:SetTexture("Interface\\Buttons\\UI-Quickslot2"); ring:SetSize(52, 52); ring:SetPoint("CENTER")
  bell:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  bell.badge = UI:Badge(bell, 16)
  bell.badge:SetPoint("TOPRIGHT", 6, 6)
  bell:SetScript("OnClick", function()
    if not panel then buildPanel(main) end
    panel:SetShown(not panel:IsShown())
    if panel:IsShown() then S:PlaceNotifPanel() end
    if PlaySound and SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
  end)
  UI:Tip(bell, "Notifications", function()
    local n = S:UnreadNotifs()
    return n > 0 and (n .. " unread - click to view") or "No new notifications"
  end)
  main:HookScript("OnHide", function() if panel then panel:Hide() end end)
  S:UpdateBadges()
  return bell
end

-- next to whichever bell icon is showing (bar, border bar or dock), kept on screen
function S:PlaceNotifPanel()
  if not panel then return end
  local placed = S.QuickBarPlace and S:QuickBarPlace(panel, "bell", S.bellFrame)
  if not placed then
    panel:ClearAllPoints()
    panel:SetPoint("TOPRIGHT", bell, "BOTTOMRIGHT", 6, -4)
  end
end

function S:UpdateBadges()
  local n = S:UnreadNotifs()
  if bell then bell.badge:SetCount(n); bell.icon:SetDesaturated(n == 0) end
  if S.mmBadge then S.mmBadge:SetCount(n) end
  if panel and panel:IsShown() then tbl:SetData(list()) end
end
S:Listen("NOTIFY", function() S:UpdateBadges() end)
S:Listen("LOGIN", function() S:UpdateBadges() end)

