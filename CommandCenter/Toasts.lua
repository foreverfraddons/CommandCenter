-- Pop-ups ("notification box"): where they appear and how big (move / resize),
-- Command Center's own notifications as pop-ups, and streamer mode.
local _, S = ...
local UI = S.UI

local function G() return S.db.global end
local function cfg()
  local g = G()
  g.toast = type(g.toast) == "table" and g.toast or {}
  return g.toast
end
local TW, TH = 320, 70
local OWN = { CommandCenter = true }

---------------------------------------------------------------------------
-- Generic pop-ups (same look as the message pop-up), stacked
---------------------------------------------------------------------------
local pool = {}
local function make(i)
  local t = CreateFrame("Button", "CC_Toast" .. i, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  t:SetSize(TW, TH)
  t:SetFrameStrata("HIGH"); t:SetClampedToScreen(true)
  UI:Backdrop(t, { 0.05, 0.05, 0.06, 0.94 })
  t.icon = t:CreateTexture(nil, "ARTWORK"); t.icon:SetSize(36, 36); t.icon:SetPoint("LEFT", 14, 0)
  t.title = UI:Text(t, "", "normal"); t.title:SetPoint("TOPLEFT", t.icon, "TOPRIGHT", 10, 2); t.title:SetPoint("RIGHT", -26, 0); t.title:SetWordWrap(false)
  t.text = UI:Text(t, "", "small"); t.text:SetPoint("TOPLEFT", t.title, "BOTTOMLEFT", 0, -3); t.text:SetPoint("RIGHT", -12, 0)
  t.text:SetWordWrap(true); t.text:SetHeight(28); t.text:SetJustifyV("TOP")
  local x = UI:CloseIcon(t, 20); x:SetPoint("TOPRIGHT", -4, -4)
  x:SetScript("OnClick", function() t:Hide() end)
  t:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  t:SetScript("OnClick", function(self, btn)
    local d = self.data or {}
    if btn == "RightButton" then
      local items = { { text = d.title or "Pop-up", title = true } }
      items[#items + 1] = { text = "Turn these pop-ups off", func = function() G().notifPopups = false; self:Hide(); S:Print("Notification pop-ups are off (Settings to turn them back on).") end }
      items[#items + 1] = { text = "Move / resize pop-ups", func = function() S:ToastMoveMode() end }
      items[#items + 1] = { text = "Close", func = function() self:Hide() end }
      UI:Menu(nil, items)
      return
    end
    self:Hide()
    if d.onClick then pcall(d.onClick) end
  end)
  t:SetScript("OnUpdate", function(self, el)
    if self:IsMouseOver() then self.left = math.max(self.left, 1); self:SetAlpha(1) return end
    self.left = self.left - el
    if self.fadeIn < 0.25 then self.fadeIn = self.fadeIn + el; self:SetAlpha(math.min(1, self.fadeIn / 0.25)) end
    if self.left <= 0 then self:Hide() elseif self.left < 1 then self:SetAlpha(self.left) end
  end)
  t:SetScript("OnHide", function() if S.PlaceToasts then S:PlaceToasts() end end)
  t:Hide()
  pool[i] = t
  return t
end

-- all pop-ups stack from the saved spot (up, or down when it's near the top of the screen)
local hookedMsg = false
function S:PlaceToasts()
  local c = cfg()
  local sc = c.scale or 1
  local uh = UIParent:GetHeight() or 768
  local dir = (c.y and c.y > uh * 0.6) and -1 or 1
  local list = {}
  local msg = S.MessageToastFrame and S.MessageToastFrame()
  if msg and not hookedMsg then hookedMsg = true; msg:HookScript("OnHide", function() S:PlaceToasts() end) end
  if msg and msg:IsShown() then list[#list + 1] = msg end
  for _, t in ipairs(pool) do if t:IsShown() then list[#list + 1] = t end end
  for i, f in ipairs(list) do
    f:SetScale(sc)
    f:ClearAllPoints()
    local x = c.x or ((UIParent:GetWidth() or 1024) - 24)
    local y = c.y or 160
    local off = (i - 1) * (TH + 8) * sc * dir
    if dir > 0 then f:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMLEFT", x / sc, (y + off) / sc)
    else f:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", x / sc, (y + TH * sc + off) / sc) end
  end
end

-- opts: { title, text, icon, onClick, addon, key, time }
function S:ShowToast(opts)
  if not opts then return end
  -- the same source again while it's still up: update it instead of stacking
  for _, t in ipairs(pool) do
    if t:IsShown() and opts.key and t.data and t.data.key == opts.key then
      t.count = (t.count or 1) + 1
      t.title:SetText((opts.title or "") .. "  |cffaaaaaa(" .. t.count .. ")|r")
      t.text:SetText(opts.text or "")
      t.left = opts.time or 6
      return t
    end
  end
  local t
  for i = 1, 3 do local p = pool[i] or make(i); if not p:IsShown() then t = p break end end
  if not t then
    -- all three are up: reuse the oldest
    t = pool[1]
    for _, p in ipairs(pool) do if (p.born or 0) < (t.born or 0) then t = p end end
  end
  t.data, t.count, t.born = opts, 1, GetTime()
  t.icon:SetTexture(opts.icon or "Interface\\Icons\\INV_Misc_Note_01")
  t.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  t.title:SetText(opts.title or "")
  t.text:SetText(opts.text or "")
  t.left = opts.time or 6
  t.fadeIn = t:IsShown() and 1 or 0
  t:SetAlpha(t:IsShown() and 1 or 0)
  t:Show()
  S:PlaceToasts()
  return t
end

---------------------------------------------------------------------------
-- Move / resize: drag the box, drag the corner, Done
---------------------------------------------------------------------------
local mover
function S:ToastMoveMode()
  local c = cfg()
  if not mover then
    mover = CreateFrame("Frame", "CC_ToastMover", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    mover:SetSize(TW, TH); mover:SetFrameStrata("DIALOG"); mover:SetClampedToScreen(true)
    mover:SetMovable(true); mover:EnableMouse(true); mover:RegisterForDrag("LeftButton")
    UI:Skin(mover, function(self, th) UI.Flat(self, th.bg, 0.85, th.gold, 1, 2) end)
    mover.text = UI:Text(mover, "|cffffd100Pop-ups appear here|r\n|cffccccccDrag to move - drag the corner to resize|r", "small", "CENTER")
    mover.text:SetPoint("CENTER", 0, 6)
    mover.done = UI:PrimaryButton(mover, "Done", 70, 20, function() mover:Hide() end)
    mover.done:SetPoint("BOTTOM", 0, 6)
    local function save()
      local r, b = mover:GetRight(), mover:GetBottom()
      if r then local sc = mover:GetScale() or 1; c.x, c.y = math.floor(r * sc + 0.5), math.floor(b * sc + 0.5) end
      S:PlaceToasts()
    end
    mover:SetScript("OnDragStart", function(self) self:StartMoving() end)
    mover:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); save() end)
    local grip = CreateFrame("Button", nil, mover)
    grip:SetSize(16, 16); grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetScript("OnMouseDown", function(self) self.start = { x = GetCursorPosition(), scale = mover:GetScale() or 1 } end)
    grip:SetScript("OnMouseUp", function(self) self.start = nil; save() end)
    grip:SetScript("OnUpdate", function(self)
      if not self.start then return end
      local us = UIParent:GetEffectiveScale() or 1
      local dx = (GetCursorPosition() - self.start.x) / us
      local sc = math.max(0.6, math.min(1.8, self.start.scale * (1 + dx / TW)))
      local l, t = mover:GetLeft(), mover:GetTop()
      local old = mover:GetScale() or 1
      mover:SetScale(sc); c.scale = sc
      if l and t then mover:ClearAllPoints(); mover:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l * old / sc, t * old / sc) end
      S:PlaceToasts()
    end)
    mover:SetScript("OnHide", function() save() end)
  end
  local sc = c.scale or 1
  mover:SetScale(sc)
  mover:ClearAllPoints()
  mover:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMLEFT", (c.x or ((UIParent:GetWidth() or 1024) - 24)) / sc, (c.y or 160) / sc)
  mover:Show()
  S:Print("Drag the pop-up box where you want it and drag its corner to resize. Click |cffffd100Done|r when you're happy.")
end
function S:ResetToasts() G().toast = nil; S:PlaceToasts() end

---------------------------------------------------------------------------
-- Command Center's own notifications as pop-ups (Settings: "Show notifications as
-- pop-ups"). Only this addon - other addons' messages are never picked up.
-- Messages and whispers have their own pop-up, so they're skipped here.
---------------------------------------------------------------------------
local notify = S.Notify
local burst
function S:Notify(key, opts)
  local had = false
  if self.G and self.G.loc and self.G.loc.notifs then
    for _, n in ipairs(self.G.loc.notifs) do if n.key == key then had = true break end end
  end
  notify(self, key, opts)
  if had or not self.G or not opts then return end
  if G().notifPopups == false then return end
  if opts.action == "mail" or opts.action == "whisper" or opts.popup == false then return end
  -- lots at once (e.g. at login): one summary pop-up instead of a pile
  local now = GetTime()
  burst = burst or {}
  while burst[1] and now - burst[1] > 4 do table.remove(burst, 1) end
  burst[#burst + 1] = now
  if #burst > 2 then
    S:ShowToast({ title = "Command Center", text = #burst .. " new notifications - click to see them", key = "notif-burst",
      icon = "Interface\\Icons\\INV_Misc_Note_01", onClick = function() local b = S.bellFrame; if b then b:Click() end end })
    return
  end
  S:ShowToast({ title = opts.title, text = opts.text, icon = opts.icon, key = key,
    onClick = function()
      for _, n in ipairs(S.G.loc.notifs or {}) do if n.key == key then S:OpenNotif(n) return end end
    end })
end

---------------------------------------------------------------------------
-- Streamer mode
---------------------------------------------------------------------------
local help
function S:SetStreamerMode(on)
  G().streamer = on and true or false
  if not on then return end
  if not help then
    help = UI:Window("CC_StreamerHelp", "Streamer mode", 460, 300)
    help:SetFrameStrata("DIALOG")
    help.text = UI:Text(help, "", "normal")
    help.text:SetPoint("TOPLEFT", 18, -42); help.text:SetWidth(424); help.text:SetJustifyH("LEFT"); help.text:SetWordWrap(true)
    help.text:SetText(
      "|cffffd100Pop-ups:|r the text of new messages is hidden (blurred) so your stream can't read it. Chat only says who it's from.\n\n" ..
      "|cffffd100The Messages window:|r OBS and other streaming programs capture the whole game picture, so an addon can't hide " ..
      "a window from them.\n\nInstead, move and shrink the Messages window so it sits exactly where your webcam box covers the " ..
      "game on stream. Drag its title bar to move it and the corner grip to resize it. It remembers the spot.")
    local arrange = UI:PrimaryButton(help, "Arrange Messages window", 190, 26, function()
      S:ShowMessenger()
      S:Print("Drag the Messages window under your webcam box; use the corner grip to resize it.")
    end)
    arrange:SetPoint("BOTTOMLEFT", 18, 16)
    local ok = UI:Button(help, "Got it", 90, 26, function() help:Hide() end)
    ok:SetPoint("BOTTOMRIGHT", -18, 16)
  end
  help:Show(); help:Raise()
end

S:AddCommand("streamer", "", "Streamer mode on / off", function()
  S:SetStreamerMode(not G().streamer)
  S:Print("Streamer mode " .. (G().streamer and "|cff55ff55on|r" or "|cffff5555off|r") .. ".")
end)
