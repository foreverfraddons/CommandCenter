-- Messenger: colors, notification style (count only / count + pop-up),
-- notification sounds, per-person overrides, and the pop-up toast.
-- Saved per account in CommandCenterDB.global.msgr.
local _, S = ...
local UI = S.UI

S.MSG_PRESETS = {
  { name = "Messenger Blue", mine = { 0.00, 0.44, 0.95 }, mineText = { 1, 1, 1 }, theirs = { 0.20, 0.20, 0.23 }, theirsText = { 1, 1, 1 }, bg = { 0.06, 0.06, 0.07 } },
  { name = "Horde Red",      mine = { 0.62, 0.08, 0.06 }, mineText = { 1, 0.93, 0.82 }, theirs = { 0.22, 0.17, 0.14 }, theirsText = { 1, 0.9, 0.75 }, bg = { 0.08, 0.05, 0.04 } },
  { name = "Fel Green",   mine = { 0.20, 0.55, 0.12 }, mineText = { 1, 1, 1 }, theirs = { 0.18, 0.22, 0.16 }, theirsText = { 0.85, 1, 0.8 }, bg = { 0.04, 0.07, 0.04 } },
  { name = "Royal Purple",   mine = { 0.45, 0.22, 0.78 }, mineText = { 1, 1, 1 }, theirs = { 0.21, 0.19, 0.27 }, theirsText = { 0.95, 0.92, 1 }, bg = { 0.06, 0.05, 0.09 } },
  { name = "Goblin Gold",    mine = { 0.78, 0.60, 0.10 }, mineText = { 0.10, 0.07, 0.02 }, theirs = { 0.25, 0.22, 0.16 }, theirsText = { 1, 0.92, 0.7 }, bg = { 0.07, 0.06, 0.03 } },
  { name = "Light",          mine = { 0.00, 0.52, 1.00 }, mineText = { 1, 1, 1 }, theirs = { 0.86, 0.87, 0.90 }, theirsText = { 0.08, 0.08, 0.10 }, bg = { 0.96, 0.96, 0.97 } },
}

-- sound choices: SOUNDKIT names, picked up if the client has them
S.MSG_SOUNDS = {
  { key = "whisper", text = "Whisper chime",  kit = "TELL_MESSAGE" },
  { key = "ping",    text = "Map ping",       kit = "MAP_PING" },
  { key = "quest",   text = "Quest complete", kit = "IG_QUEST_LIST_COMPLETE" },
  { key = "coin",    text = "Coins",          kit = "LOOT_WINDOW_COIN_SOUND" },
  { key = "ready",   text = "Ready check",    kit = "READY_CHECK" },
  { key = "warning", text = "Raid warning",   kit = "RAID_WARNING" },
}

local function copy3(c) return { c[1], c[2], c[3] } end
function S:MsgCfg()
  local g = S.db.global
  if not g.msgr then
    local p = S.MSG_PRESETS[1]
    g.msgr = { preset = p.name, mine = copy3(p.mine), mineText = copy3(p.mineText), theirs = copy3(p.theirs), theirsText = copy3(p.theirsText),
      bg = copy3(p.bg), notify = "popup", popupTime = 6, sound = true, soundKey = "whisper", people = {} }
  end
  g.msgr.people = g.msgr.people or {}
  return g.msgr
end

function S:ApplyMsgPreset(name)
  local c = S:MsgCfg()
  for _, p in ipairs(S.MSG_PRESETS) do
    if p.name == name then
      c.preset = p.name
      c.mine, c.mineText, c.theirs, c.theirsText, c.bg = copy3(p.mine), copy3(p.mineText), copy3(p.theirs), copy3(p.theirsText), copy3(p.bg)
    end
  end
  S:Fire("MSGR_STYLE")
end

-- per person: notify = "default"|"popup"|"badge"|"off", sound = "default"|"none"|<sound key>
function S:MsgPerson(who) return S:MsgCfg().people[who] end
function S:SetMsgPerson(who, field, value)
  local ppl = S:MsgCfg().people
  local p = ppl[who] or {}
  p[field] = (value ~= "default") and value or nil
  ppl[who] = next(p) and p or nil
  S:Fire("MSGR_STYLE")
end
function S:MsgNotifyMode(who)
  local p = S:MsgPerson(who)
  if p and p.notify then return p.notify end
  return S:MsgCfg().notify
end
function S:MsgSoundKey(who)
  local p = S:MsgPerson(who)
  if p and p.sound then return p.sound end
  local c = S:MsgCfg()
  return c.sound and c.soundKey or "none"
end

local lastSound = 0
function S:PlayMsgSound(key, force)
  if not key or key == "none" then return end
  if not force and GetTime() - lastSound < 2 then return end     -- don't machine-gun at login
  lastSound = GetTime()
  for _, s in ipairs(S.MSG_SOUNDS) do
    if s.key == key and PlaySound and SOUNDKIT and SOUNDKIT[s.kit] then PlaySound(SOUNDKIT[s.kit], "Master") return end
  end
end

local MODE_TEXT = { popup = "Count + pop-up box", badge = "Count only (minimap & bell)", off = "Off (no alerts)" }
S.MSG_MODE_TEXT = MODE_TEXT
local function soundText(key)
  if key == "none" then return "No sound" end
  for _, s in ipairs(S.MSG_SOUNDS) do if s.key == key then return s.text end end
  return key
end

function S:MsgPersonSummary(who)
  local p = S:MsgPerson(who)
  if not p then return nil end
  local parts = {}
  if p.notify then parts[#parts + 1] = MODE_TEXT[p.notify] end
  if p.sound then parts[#parts + 1] = soundText(p.sound) end
  return table.concat(parts, ", ")
end

-- the per-person menu (from the chat header bell or right-clicking a chat)
function S:MsgPersonMenu(who, anchor)
  local p = S:MsgPerson(who) or {}
  local items = { { text = "Alerts for " .. S.Short(who), title = true },
    { text = "Use my default (" .. MODE_TEXT[S:MsgCfg().notify] .. ")", checked = p.notify == nil, func = function() S:SetMsgPerson(who, "notify", "default") end } }
  for _, k in ipairs({ "popup", "badge", "off" }) do
    items[#items + 1] = { text = MODE_TEXT[k], checked = p.notify == k, func = function() S:SetMsgPerson(who, "notify", k) end }
  end
  items[#items + 1] = { text = "Sound", title = true }
  items[#items + 1] = { text = "Use my default (" .. soundText(S:MsgCfg().sound and S:MsgCfg().soundKey or "none") .. ")", checked = p.sound == nil,
    func = function() S:SetMsgPerson(who, "sound", "default") end }
  items[#items + 1] = { text = "No sound", checked = p.sound == "none", func = function() S:SetMsgPerson(who, "sound", "none") end }
  for _, s in ipairs(S.MSG_SOUNDS) do
    items[#items + 1] = { text = s.text, checked = p.sound == s.key, func = function() S:SetMsgPerson(who, "sound", s.key); S:PlayMsgSound(s.key, true) end }
  end
  UI:Menu(anchor, items)
end

---------------------------------------------------------------------------
-- Color picker (works with both the old and new game color picker)
---------------------------------------------------------------------------
local function pickColor(c, onChange)
  if not ColorPickerFrame then return end
  local r, g, b = c[1], c[2], c[3]
  local function apply(prev)
    local nr, ng, nb
    if type(prev) == "table" and prev.r then nr, ng, nb = prev.r, prev.g, prev.b
    else nr, ng, nb = ColorPickerFrame:GetColorRGB() end
    c[1], c[2], c[3] = nr, ng, nb
    onChange()
  end
  if ColorPickerFrame.SetupColorPickerAndShow then
    ColorPickerFrame:SetupColorPickerAndShow({ r = r, g = g, b = b, hasOpacity = false,
      swatchFunc = function() apply() end, cancelFunc = function(prev) apply(prev) end })
  else
    -- old clients only (no SetupColorPickerAndShow): the picker is set up through its fields
    ColorPickerFrame.hasOpacity = false
    ColorPickerFrame.previousValues = { r = r, g = g, b = b }
    ColorPickerFrame.func = function() apply() end
    ColorPickerFrame.cancelFunc = function(prev) apply(prev) end
    if ColorPickerFrame.SetColorRGB then ColorPickerFrame:SetColorRGB(r, g, b) end
    if ShowUIPanel then ShowUIPanel(ColorPickerFrame) else ColorPickerFrame:Show() end
  end
  -- Don't change the game's picker unless it would open behind our windows (DIALOG):
  -- writing to Blizzard frames from addon code can taint them.
  local st = ColorPickerFrame.GetFrameStrata and ColorPickerFrame:GetFrameStrata()
  if st ~= "FULLSCREEN_DIALOG" and st ~= "TOOLTIP" and not InCombatLockdown() then
    ColorPickerFrame:SetFrameStrata("FULLSCREEN_DIALOG")
  end
  if ColorPickerFrame.Raise then ColorPickerFrame:Raise() end
end

UI.PickColor = pickColor

local function bubble(parent, w, text)
  local b = UI:Panel(parent, w, 26)
  b.fs = UI:Text(b, text, "small"); b.fs:SetPoint("LEFT", 9, 0)
  return b
end
-- Bubble colours on the rounded panel. (It used to put a plain white backdrop on top,
-- which the new rounded look never recoloured - every bubble came out white.)
local function look(b, c, tc)
  local edge = { math.min(1, c[1] + 0.15), math.min(1, c[2] + 0.15), math.min(1, c[3] + 0.15) }
  b.__bubble = { c = { c[1], c[2], c[3] }, e = edge }
  -- own skin so a theme change doesn't repaint it in the panel colour
  UI:Skin(b, function(self) local d = self.__bubble; if d then UI.Flat(self, d.c, 0.95, d.e, 1) end end)
  if b.fs then b.fs:SetTextColor(tc[1], tc[2], tc[3]) end
end
S.MsgBubbleLook = look

---------------------------------------------------------------------------
-- The settings block (used in the messenger cog window and the Settings tab)
-- Returns the frame; height is ~ 360.
---------------------------------------------------------------------------
function S:BuildMessengerSettings(parent, width)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(width, 380)
  local cfg = S.MsgCfg
  local y = 0
  local function hdr(t) local h = UI:Header(f, t); h:SetPoint("TOPLEFT", 0, y); y = y - 26 end
  local function lbl(t, x, yy) local l = UI:Text(f, t, "small"); l:SetPoint("TOPLEFT", x or 0, (yy or y) - 4); return l end

  hdr("Message colors")
  lbl("Theme")
  local presets = {}
  for _, p in ipairs(S.MSG_PRESETS) do presets[#presets + 1] = p.name end
  presets[#presets + 1] = "Custom"
  f.preset = UI:Dropdown(f, 170, presets, cfg(S).preset or "Custom", function(v) if v ~= "Custom" then S:ApplyMsgPreset(v) end end)
  f.preset:SetPoint("TOPLEFT", 110, y)
  y = y - 32

  -- swatches
  local swatches = {}
  local SW = { { "mine", "My bubbles" }, { "mineText", "My text" }, { "theirs", "Their bubbles" }, { "theirsText", "Their text" }, { "bg", "Chat background" } }
  for i, s in ipairs(SW) do
    local col = (i - 1) % 3
    local row = math.floor((i - 1) / 3)
    local x, yy = col * 150, y - row * 28
    local b = CreateFrame("Button", nil, f)
    b:SetSize(20, 20); b:SetPoint("TOPLEFT", x, yy)
    local border = b:CreateTexture(nil, "BACKGROUND"); border:SetAllPoints(); border:SetColorTexture(0.8, 0.8, 0.8, 1)
    b.sw = b:CreateTexture(nil, "ARTWORK"); b.sw:SetPoint("TOPLEFT", 2, -2); b.sw:SetPoint("BOTTOMRIGHT", -2, 2)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    local t = UI:Text(f, s[2], "small"); t:SetPoint("LEFT", b, "RIGHT", 6, 0)
    b:SetScript("OnClick", function()
      pickColor(cfg(S)[s[1]], function() cfg(S).preset = "Custom"; S:Fire("MSGR_STYLE") end)
    end)
    UI:Tip(b, s[2], "Click to pick a color.")
    swatches[s[1]] = b
  end
  y = y - 60

  -- live preview
  local prev = UI:Panel(f, math.min(width, 440), 74)
  prev:SetPoint("TOPLEFT", 0, y)
  local theirs = bubble(prev, 170, "Raiding tonight?"); theirs:SetPoint("TOPLEFT", 10, -10)
  local mine = bubble(prev, 190, "Yes! See you at 8 :)"); mine:SetPoint("BOTTOMRIGHT", -10, 10)
  y = y - 86

  hdr("Message alerts")
  lbl("When someone messages me")
  f.mode = UI:Dropdown(f, 230, { { text = MODE_TEXT.popup, value = "popup" }, { text = MODE_TEXT.badge, value = "badge" }, { text = MODE_TEXT.off, value = "off" } },
    cfg(S).notify, function(v) cfg(S).notify = v; S:Fire("MSGR_STYLE") end)
  f.mode:SetPoint("TOPLEFT", 170, y)
  y = y - 30
  lbl("Pop-up stays for")
  f.time = UI:Dropdown(f, 90, { { text = "3 sec", value = 3 }, { text = "5 sec", value = 5 }, { text = "8 sec", value = 8 }, { text = "12 sec", value = 12 } },
    cfg(S).popupTime or 6, function(v) cfg(S).popupTime = v end)
  f.time:SetPoint("TOPLEFT", 170, y)
  local test = UI:Button(f, "Preview pop-up", 120, 22, function()
    S:MsgToast(S.me, "This is what a new message looks like. Click me to open the chat!", nil, true)
  end)
  test:SetPoint("TOPLEFT", 290, y)
  y = y - 30
  f.snd = UI:Check(f, "Play a sound", cfg(S).sound, function(v) cfg(S).sound = v; S:Fire("MSGR_STYLE") end)
  f.snd:SetPoint("TOPLEFT", 0, y)
  local opts = {}
  for _, s in ipairs(S.MSG_SOUNDS) do opts[#opts + 1] = { text = s.text, value = s.key } end
  f.sound = UI:Dropdown(f, 150, opts, cfg(S).soundKey, function(v) cfg(S).soundKey = v; S:PlayMsgSound(v, true) end)
  f.sound:SetPoint("TOPLEFT", 170, y)
  local play = UI:Button(f, "Test", 60, 22, function() S:PlayMsgSound(cfg(S).soundKey, true) end)
  play:SetPoint("TOPLEFT", 330, y)
  y = y - 32
  f.people = UI:Text(f, "", "small"); f.people:SetPoint("TOPLEFT", 0, y); f.people:SetWidth(width - 110); f.people:SetWordWrap(true)
  local reset = UI:Button(f, "Reset all", 80, 22, function()
    UI:Confirm("Remove every per-person alert setting?", function() wipe(cfg(S).people); S:Fire("MSGR_STYLE") end)
  end)
  reset:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, y + 2)
  f.reset = reset
  y = y - 40
  f:SetHeight(-y)

  function f:Refresh()
    local c = cfg(S)
    self.preset:SetValue(c.preset or "Custom")
    for k, b in pairs(swatches) do b.sw:SetColorTexture(c[k][1], c[k][2], c[k][3], 1) end
    prev:SetBackdropColor(c.bg[1], c.bg[2], c.bg[3], 0.95)
    look(theirs, c.theirs, c.theirsText); look(mine, c.mine, c.mineText)
    self.mode:SetValue(c.notify); self.time:SetValue(c.popupTime or 6)
    self.snd:SetChecked(c.sound and true or false); self.sound:SetValue(c.soundKey)
    self.sound:SetEnabled(c.sound and true or false)
    local list = {}
    for who in pairs(c.people) do list[#list + 1] = S.Short(who) .. " |cff888888(" .. (S:MsgPersonSummary(who) or "") .. ")|r" end
    table.sort(list)
    self.people:SetText("|cffffd100Per person:|r " .. (#list > 0 and table.concat(list, ", ") or
      "|cff888888none - click the bell in a chat (or right-click a chat) to set alerts for one person.|r"))
    self.reset:SetShown(#list > 0)
  end
  f:SetScript("OnShow", function(self) self:Refresh() end)
  S:Listen("MSGR_STYLE", function() if f:IsVisible() then f:Refresh() end end)
  f:Refresh()
  return f
end

local prefsWin
function S:ShowMessengerSettings()
  if not prefsWin then
    prefsWin = UI:Window("CC_MessengerSettings", "Message settings", 500, 470)
    prefsWin.body = S:BuildMessengerSettings(prefsWin, 450)
    prefsWin.body:SetPoint("TOPLEFT", 26, -40)
  end
  prefsWin:Show(); prefsWin:Raise()
  prefsWin.body:Refresh()
end

---------------------------------------------------------------------------
-- Pop-up toast (bottom right of the screen, fades out)
---------------------------------------------------------------------------
local toast
local function inCombat() return InCombatLockdown and InCombatLockdown() end

local function setHint()
  if not toast then return end
  toast.hint:SetText(inCombat() and "|cffff9933In combat - open it after the fight|r" or "|cff888888Click to open the chat|r")
end

local function buildToast()
  toast = CreateFrame("Button", "CC_MessageToast", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  toast:SetSize(320, 70)
  toast:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -24, 160)
  toast:SetFrameStrata("HIGH")
  toast:SetClampedToScreen(true)
  UI:Backdrop(toast, { 0.05, 0.05, 0.06, 0.94 })
  toast.av = toast:CreateTexture(nil, "ARTWORK"); toast.av:SetSize(40, 40); toast.av:SetPoint("LEFT", 12, 0)
  toast.icon = toast:CreateTexture(nil, "OVERLAY"); toast.icon:SetSize(16, 16); toast.icon:SetPoint("BOTTOMRIGHT", toast.av, "BOTTOMRIGHT", 4, -4)
  toast.icon:SetTexture("Interface\\Icons\\INV_Letter_02")
  toast.name = UI:Text(toast, "", "normal"); toast.name:SetPoint("TOPLEFT", toast.av, "TOPRIGHT", 10, 2); toast.name:SetPoint("RIGHT", -26, 0)
  toast.name:SetWordWrap(false)
  toast.text = UI:Text(toast, "", "small"); toast.text:SetPoint("TOPLEFT", toast.name, "BOTTOMLEFT", 0, -3); toast.text:SetPoint("RIGHT", -12, 0)
  toast.text:SetWordWrap(true); toast.text:SetHeight(26); toast.text:SetJustifyV("TOP")
  toast.hint = UI:Text(toast, "", "small"); toast.hint:SetPoint("BOTTOMLEFT", toast.av, "BOTTOMRIGHT", 10, -6)
  -- streamer mode: the words are replaced by soft grey bars so the stream can't read them
  toast.blur = CreateFrame("Frame", nil, toast)
  toast.blur:SetPoint("TOPLEFT", toast.text, "TOPLEFT", 0, -2); toast.blur:SetPoint("RIGHT", toast, "RIGHT", -16, 0); toast.blur:SetHeight(24)
  for i, w in ipairs({ 0.92, 0.6 }) do
    local bar = toast.blur:CreateTexture(nil, "ARTWORK")
    bar:SetTexture(UI.MEDIA .. "UI\\pill"); bar:SetVertexColor(0.55, 0.55, 0.58, 0.55)
    bar:SetPoint("TOPLEFT", 0, -(i - 1) * 12); bar:SetHeight(9)
    toast.blur["bar" .. i], toast.blur["w" .. i] = bar, w
    local glow = toast.blur:CreateTexture(nil, "BACKGROUND")
    glow:SetTexture(UI.ART.glow); glow:SetVertexColor(0.6, 0.6, 0.65, 0.35)
    glow:SetPoint("TOPLEFT", bar, -6, 5); glow:SetPoint("BOTTOMRIGHT", bar, 6, -5)
  end
  toast.blur:SetScript("OnSizeChanged", function(self, w) self.bar1:SetWidth(w * self.w1); self.bar2:SetWidth(w * self.w2) end)
  toast.blur:Hide()
  local x = UI:CloseIcon(toast, 20); x:SetPoint("TOPRIGHT", -4, -4)
  x:SetScript("OnClick", function() toast:Hide() end)
  toast:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  toast:SetScript("OnClick", function(self, button)
    if button == "RightButton" then self:Hide() return end
    if inCombat() then setHint(); return end
    if self.preview then self:Hide() return end
    local who = self.who
    self:Hide()
    if who then S:ShowMessenger(who) end
  end)
  -- fade: hold, then fade out; hovering keeps it up
  toast:SetScript("OnUpdate", function(self, el)
    if self:IsMouseOver() then self.left = math.max(self.left, 1.0); self:SetAlpha(1) return end
    self.left = self.left - el
    if self.fadeIn < 0.25 then self.fadeIn = self.fadeIn + el; self:SetAlpha(math.min(1, self.fadeIn / 0.25)) end
    if self.left <= 0 then self:Hide()
    elseif self.left < 1 then self:SetAlpha(self.left) end
  end)
  toast:SetScript("OnHide", function(self) self.count = 0 end)
  local ev = CreateFrame("Frame")
  ev:RegisterEvent("PLAYER_REGEN_DISABLED"); ev:RegisterEvent("PLAYER_REGEN_ENABLED")
  ev:SetScript("OnEvent", setHint)
  toast.count = 0
  toast:Hide()
end

function S:MsgToast(who, text, key, preview)
  if not toast then buildToast() end
  local again = toast:IsShown() and toast.who == who and not preview
  toast.count = (again and toast.count or 0) + 1
  toast.who, toast.key, toast.preview = who, key, preview
  if S.MsgSetAvatar then S.MsgSetAvatar(toast.av, who) end
  toast.name:SetText(S:ColorName(who) .. (S.ServiceIcons and S.ServiceIcons(who) or "") .. (toast.count > 1 and ("  |cffaaaaaa(" .. toast.count .. " new)|r") or ""))
  local streamer = S.db.global.streamer and not preview
  toast.text:SetText(streamer and "" or (text or ""))
  toast.blur:SetShown(streamer and true or false)
  if streamer then local w = (toast.blur:GetWidth() or 240); toast.blur.bar1:SetWidth(w * 0.92); toast.blur.bar2:SetWidth(w * 0.6) end
  setHint()
  if streamer then toast.hint:SetText("|cff888888Streamer mode - text hidden|r") end
  toast.left = S:MsgCfg().popupTime or 6
  toast.fadeIn = toast:IsShown() and 1 or 0
  toast:SetAlpha(toast:IsShown() and 1 or 0)
  toast:Show()
  if S.PlaceToasts then S:PlaceToasts() end
end
S.MessageToastFrame = function() return toast end
