-- Settings: appearance, quickbar / dock / border bar, every tool's options,
-- command list, support contact.
local _, S = ...
local UI = S.UI

local ctl = {}

local buildSearch
local function build(p)
  local sf, c = UI:Scroll(p, S.CW, S.CH - 34)
  sf:SetPoint("TOPLEFT", 0, -34)
  ctl.sf, ctl.c, ctl.headers = sf, c, {}
  c:SetHeight(2120)
  local g = S.db.global
  local y = -4
  local function hdr(t) local h = UI:Header(c, t); h:SetPoint("TOPLEFT", 0, y); ctl.headers[#ctl.headers + 1] = h; y = y - 26 end
  buildSearch(p)
  local function lbl(t, x) local l = UI:Text(c, t, "small"); l:SetPoint("TOPLEFT", x or 0, y - 4); return l end

  hdr("Appearance")
  lbl("Font")
  ctl.font = UI:Dropdown(c, 180, function() return UI:FontList() end, g.font, function(v) g.font = v; UI:ApplyTheme() end)
  ctl.font:SetPoint("TOPLEFT", 120, y)
  lbl("Size", 330)
  ctl.size = UI:Dropdown(c, 70, { 10, 11, 12, 13, 14, 15, 16 }, g.fontSize, function(v) g.fontSize = v; UI:ApplyTheme() end)
  ctl.size:SetPoint("TOPLEFT", 370, y)
  y = y - 30
  lbl("Window scale", 330)
  ctl.scale = UI:Dropdown(c, 70, { 0.8, 0.85, 0.9, 0.95, 1.0, 1.05, 1.1, 1.2 }, g.scale, function(v) g.scale = v; local m = S:MainFrame(); if m then m:SetScale(v); if S.QuickBarLayout then S:QuickBarLayout() end end end)
  ctl.scale:SetPoint("TOPLEFT", 420, y)
  y = y - 40

  hdr("Look & feel")
  lbl("Theme")
  local tOpts = {}
  for _, k in ipairs(UI.THEME_ORDER) do tOpts[#tOpts + 1] = { text = UI.THEMES[k].name, value = k } end
  ctl.theme = UI:Dropdown(c, 180, tOpts, g.theme or "horde", function(v)
    g.theme = v
    UI:ApplyTheme(); S:RefreshCurrent()
  end)
  ctl.theme:SetPoint("TOPLEFT", 120, y)
  lbl("Animations", 330)
  ctl.anim = UI:Dropdown(c, 120, { { text = "Minimal", value = "minimal" }, { text = "Smooth", value = "smooth" }, { text = "Flashy", value = "flashy" } },
    g.anim or "smooth", function(v) g.anim = v; local m = S:MainFrame(); if m then UI:Animate(m, "window") end end)
  ctl.anim:SetPoint("TOPLEFT", 420, y)
  y = y - 34
  lbl("Icon style")
  ctl.iconStyle = UI:Dropdown(c, 180, { { text = "Plain icons", value = "plain" }, { text = "Icons in circles", value = "circle" } },
    g.iconStyle or "plain", function(v)
      g.iconStyle = v
      if S.QuickBarLayout then S:QuickBarLayout() end
      if S.RestyleToolShortcuts then S:RestyleToolShortcuts() end
    end)
  ctl.iconStyle:SetPoint("TOPLEFT", 120, y)
  local colors = UI:Button(c, "Custom colours...", 150, 22, function() S:ShowColorEditor() end,
    "Make your own colour scheme: pick the accent colour, or use hue / saturation / brightness sliders.")
  colors:SetPoint("TOPLEFT", 420, y)
  y = y - 34
  local function check2(label, key, tip, fn)
    local cb = UI:Check(c, label, g[key], function(v) g[key] = v; if fn then fn(v) end; S:RefreshCurrent() end, tip)
    cb:SetPoint("TOPLEFT", 0, y); y = y - 24
    return cb
  end
  y = y - 10

  hdr("Quickbar & dock")
  ctl.dock = check2("Dock mode - the quickbar becomes a dock with every module (like RocketDock or the macOS dock)", "dockMode",
    "Icons grow as you hover them. Click a module to open it, click it again to fold it away. Drag tools from the Tools window onto the dock (or border bar); drag icons along it to rearrange. A tool is either in the dock or a floating shortcut, never both.",
    function(v) S:SetDockMode(v) end)
  ctl.border = check2("Border mode - a thin bar along the whole screen edge; the rest of your UI (minimap, buffs, bars) moves out of its way", "borderMode",
    "Drag the bar toward another screen edge to move it there. Drag the grip across it for thinner or thicker. Can't be used together with dock mode.",
    function(v) S:SetBorderMode(v) end)
  local qbHelp = UI:Text(c, "|cff888888Drag the quickbar to any screen edge to snap it (left / right = vertical). The arrow folds the page away; the corner grip resizes it (along = length, across = thinner / thicker). Right-click the bar for options.|r", "small")
  qbHelp:SetPoint("TOPLEFT", 0, y - 2); qbHelp:SetWidth(S.CW - 180)
  local qbReset = UI:Button(c, "Reset position", 120, 22, function() S:ResetQuickBar() end, "Put the quickbar (and dock) back where they started.")
  qbReset:SetPoint("TOPLEFT", S.CW - 160, y)
  local qbPlug = UI:Button(c, "Plugins...", 120, 22, function() S:ShowPlugins() end, "Put other addons' minimap icons into your dock / border bar.")
  qbPlug:SetPoint("TOPLEFT", qbReset, "BOTTOMLEFT", 0, -4)
  y = y - 58
  lbl("When I log in")
  ctl.startMode = UI:Dropdown(c, 260, { { text = "Show the quickbar (page folded)", value = "auto" }, { text = "Show Command Center with the page open", value = "show" }, { text = "Start hidden", value = "hidden" } },
    g.startMode or "auto", function(v) g.startMode = v end)
  ctl.startMode:SetPoint("TOPLEFT", 120, y)
  y = y - 32
  lbl("Border bar icons")
  local bq = g.qbBorder or {}
  ctl.borderLayout = UI:Dropdown(c, 160, { { text = "Snap in a row", value = "snap" }, { text = "Freestyle", value = "free" } },
    bq.layout or "snap", function(v) S:SetBorderIconLayout(v) end)
  ctl.borderLayout:SetPoint("TOPLEFT", 120, y)
  ctl.spacing = UI:Slider(c, 300, "Icon spacing", 0, 30, 1, g.iconSpacing or bq.spacing or 6, function(v) S:SetIconSpacing(v) end,
    function(v) return math.floor(v + 0.5) .. " px" end)
  ctl.spacing:SetPoint("TOPLEFT", 300, y)
  y = y - 30
  local gm = UI:Button(c, "Game menu buttons & bags...", 210, 22, function(self) S:BlizzardButtonsMenu(self) end,
    "Put the game's own buttons (character, spellbook, talents, quest log, game menu...) and a bag button in your dock / border bar.")
  gm:SetPoint("TOPLEFT", 0, y)
  y = y - 30
  check2("Hide the game's menu buttons (in dock / border mode)", "hideBlzMicro", nil, function() S:ApplyBlizzardHiding() end)
  check2("Hide the game's bag bar (in dock / border mode)", "hideBlzBags", nil, function() S:ApplyBlizzardHiding() end)
  check2("XP and reputation bars on the quickbar", "qbXPBars", "Thin bars along the inside edge of the quickbar, dock or border bar. Hover them for numbers.",
    function() if S.QuickBarLayout then S:QuickBarLayout() end end)
  check2("Hide the game's XP and reputation bars", "hideBlzXP", "Only while the quickbar's XP and reputation bars are on.", function() S:ApplyBlizzardHiding() end)
  y = y - 10

  hdr("Behaviour")
  local function check(label, key, tip, fn)
    local cb = UI:Check(c, label, g[key], function(v) g[key] = v; if fn then fn(v) end end, tip)
    cb:SetPoint("TOPLEFT", 0, y); y = y - 24
    return cb
  end
  check("Show minimap button", "minimapShown", nil, function(v) g.minimap.hide = not v; S:UpdateMinimap() end):SetChecked(not g.minimap.hide)
  y = y - 10

  local ms = S:BuildMessengerSettings(c, S.CW - 40)
  ms:SetPoint("TOPLEFT", 0, y)
  ctl.msgr = ms
  y = y - ms:GetHeight() - 6
  local om = UI:Button(c, "Open Messenger", 120, 22, function() S:ShowMessenger() end); om:SetPoint("TOPLEFT", 0, y)
  y = y - 36

  hdr("Whispers, pop-ups & streaming")
  ctl.whHide = check2("Keep whispers out of the chat window", "msgWhispersHideChat", "They still show up in the Messenger.")
  ctl.smart = UI:Check(c, "Smart message suggestions", S.db.global.smartChat ~= false, function(v) S.db.global.smartChat = v and true or false end,
    "In a chat, Command Center offers the next step from what was said: invite someone who asks for an invite, set a reminder for a time you agreed on...")
  ctl.smart:SetPoint("TOPLEFT", 0, y); y = y - 24
  ctl.reply = UI:Check(c, "/r in game chat opens the Messenger", S.db.global.replyOpensMessenger ~= false, function(v) S.db.global.replyOpensMessenger = v and true or false end,
    "Typing /r (or /reply) opens the Messenger on the person you'd reply to - whoever whispered you last.")
  ctl.reply:SetPoint("TOPLEFT", 0, y); y = y - 24
  ctl.openOnWh = check2("Open the Messenger when I whisper someone in game chat", "msgOpenOnWhisper", "Send a /w from normal chat and the Messenger opens on that person.")
  if S.db.global.msgOpenOnWhisper == nil then ctl.openOnWh:SetChecked(true) end
  ctl.autoLook = check2("Look people up when a chat starts", "msgAutoLookup", "Quietly runs a /who on someone new so their profile shows level, class, guild and where they are.")
  if S.db.global.msgAutoLookup == nil then ctl.autoLook:SetChecked(true) end
  ctl.hideCens = check2("Hide whispers the game flags as potentially inappropriate", "msgHideCensored",
    "On: they show as \"potentially inappropriate\" until you click them. Off: the Messenger shows them straight away.")
  if S.db.global.msgHideCensored == nil then ctl.hideCens:SetChecked(true) end
  ctl.streamer = check2("Streamer mode", "streamer",
    "Hides what new whispers say in pop-ups, the notification list and chat, and helps you tuck the Messenger window behind your webcam on stream.",
    function(v) S:SetStreamerMode(v) end)
  ctl.notifPopups = UI:Check(c, "Show notifications as pop-ups", S.db.global.notifPopups ~= false, function(v) S.db.global.notifPopups = v and true or false end,
    "Everything that lands in the notification bell (reminders, whispers...) also pops up. Only Command Center's - never other addons.")
  ctl.notifPopups:SetPoint("TOPLEFT", 0, y); y = y - 24
  local mv = UI:Button(c, "Move / resize pop-ups", 170, 22, function() S:ToastMoveMode() end, "Drag the pop-up box anywhere and resize it.")
  mv:SetPoint("TOPLEFT", 0, y)
  local test = UI:Button(c, "Test pop-up", 100, 22, function()
    S:ShowToast({ title = "Command Center", text = "This is how notifications pop up.", key = "test" })
  end)
  test:SetPoint("LEFT", mv, "RIGHT", 8, 0)
  y = y - 36

  hdr("Damage meter")
  ctl.meterOn = UI:Check(c, "Damage meter on", S.MeterIsOn and S:MeterIsOn() or false, function(v) if S.SetMeterOn then S:SetMeterOn(v) end end,
    "Shows damage, healing, interrupts, dispels and more for your group (Tools > Damage Meter). Needs the game's own damage meter switched on - Command Center does that for you and hides the game's window.")
  ctl.meterOn:SetPoint("TOPLEFT", 0, y); y = y - 24
  ctl.meterOn:HookScript("OnShow", function(self) self:SetChecked(S.MeterIsOn and S:MeterIsOn() or false) end)
  ctl.meterHide = UI:Check(c, "  Hide the game's own damage meter window", S.db.global.hideGameMeter ~= false, function(v)
    S.db.global.hideGameMeter = v and true or false
    if S.MeterApplyGameWindow then S:MeterApplyGameWindow() end
  end, "The game's meter has to stay switched on for Command Center to read it; this makes its window invisible so you only see ours.")
  ctl.meterHide:SetPoint("TOPLEFT", 0, y); y = y - 24
  local om2 = UI:Button(c, "Open damage meter", 140, 22, function() if S.ShowMeter then S:ShowMeter() end end); om2:SetPoint("TOPLEFT", 0, y)
  local help = UI:Button(c, "Not working?", 110, 22, function() if S.MeterHelp then S.MeterHelp() end end, "How to switch the game's damage meter on by hand.")
  help:SetPoint("LEFT", om2, "RIGHT", 8, 0)
  y = y - 36

  hdr("Bags (BiB)")
  ctl.bibOn = UI:Check(c, "Use BiB for my bags", S.BiBIsOn and S:BiBIsOn() or false, function(v) if S.SetBiBOn then S:SetBiBOn(v) end end,
    "BiB (Built-in Bag) puts all your bags in one window - sorted, grouped into sections, searchable, styled your way. When it's on it opens instead of the game's bags (B, Shift-B, the bag buttons, vendors, mail, the bank).")
  ctl.bibOn:SetPoint("TOPLEFT", 0, y); y = y - 24
  ctl.bibOn:HookScript("OnShow", function(self) self:SetChecked(S.BiBIsOn and S:BiBIsOn() or false) end)
  local bo = UI:Button(c, "BiB options", 110, 22, function() if S.ShowBiBOptions then S:ShowBiBOptions() end end, "Look, sorting, what to show, when it opens.")
  bo:SetPoint("TOPLEFT", 0, y)
  local bopen = UI:Button(c, "Open BiB", 90, 22, function() if S.ShowBiB then S:ShowBiB() end end); bopen:SetPoint("LEFT", bo, "RIGHT", 8, 0)
  y = y - 36

  hdr("First-time setup")
  local setup = UI:PrimaryButton(c, "Run first-time setup again", 200, 22, function()
    S:ShowTutorial(true, 1)
  end, "Replay the guided tour of every tool.")
  setup:SetPoint("TOPLEFT", 0, y)
  local redoL = UI:Text(c, "Redo one step:", "small"); redoL:SetPoint("LEFT", setup, "RIGHT", 16, 0)
  local guideB = UI:Button(c, "Open the Guide", 120, 22, function() S:ShowGuide() end, "Every tool and every setting explained, with little animations.")
  guideB:SetPoint("TOPLEFT", setup, "BOTTOMLEFT", 0, -6)
  local function stepOptions()
    local opts = { { text = "Pick a step...", value = "" } }
    for i, st in ipairs(S.TourSteps and S:TourSteps() or S.TUTORIAL_STEPS or {}) do opts[#opts + 1] = { text = "Tour " .. i .. ": " .. st.title, value = "t" .. i } end
    return opts
  end
  ctl.redo = UI:Dropdown(c, 250, stepOptions, "", function(v)
    local kind, n = v:match("^(%a)(%d+)$")
    n = tonumber(n)
    if kind == "t" then S:ShowTutorial(true, n) end
    C_Timer.After(0, function() ctl.redo:SetValue("") end)
  end)
  ctl.redo:SetPoint("LEFT", redoL, "RIGHT", 10, 0)
  y = y - 66

  hdr("Help & support")
  local sup = UI:Text(c, "Questions, bugs or ideas? Contact |cff" .. S.ACCENT_HEX .. S.support .. "|r in game.\nVersion " .. S.version, "small")
  sup:SetPoint("TOPLEFT", 0, y); y = y - 40


  -- the command list is long, so it goes last and the page grows to fit it
  hdr("Commands")
  ctl.cmds = UI:Text(c, "", "small"); ctl.cmds:SetPoint("TOPLEFT", 0, y); ctl.cmds:SetWidth(S.CW - 40)
  ctl.cmds:SetJustifyH("LEFT"); ctl.cmds:SetWordWrap(true)
  if ctl.cmds.SetSpacing then ctl.cmds:SetSpacing(2) end
  ctl.cmdsY = y
  ctl.content = c
end

---------------------------------------------------------------------------
-- Search: type a word, pick a match, the page scrolls to it and it lights up
---------------------------------------------------------------------------
local function plain(t) return (tostring(t or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("||", "|")) end
local function textOf(o)
  if o.GetObjectType and o:GetObjectType() == "FontString" then return o:GetText() end
  if o.label and o.label.GetText then return o.label:GetText() end
  if o.fs and o.fs.GetText then return o.fs:GetText() end
end
local function entries()
  local out, c = {}, ctl.c
  local top = c and c:GetTop()
  if not top then return out end
  local function add(o)
    local t = textOf(o)
    if t and t ~= "" and o:IsShown() and o.GetTop and o:GetTop() then out[#out + 1] = { obj = o, text = plain(t), off = top - o:GetTop() } end
  end
  local function scan(f, depth)
    for _, r in ipairs({ f:GetRegions() }) do add(r) end
    for _, ch in ipairs({ f:GetChildren() }) do
      add(ch)
      if depth < 3 and not ch.label and not ch.fs then scan(ch, depth + 1) end
    end
  end
  scan(c, 0)
  local heads = {}
  for _, h in ipairs(ctl.headers or {}) do if h:GetTop() then heads[#heads + 1] = { text = plain(h:GetText()), off = top - h:GetTop() } end end
  table.sort(heads, function(a, b) return a.off < b.off end)
  for _, e in ipairs(out) do
    for _, h in ipairs(heads) do if h.off <= e.off + 1 then e.section = h.text end end
  end
  return out
end
local function jump(e)
  ctl.sf:SetVerticalScroll(math.max(0, e.off - 30))
  local f = ctl.flash
  if not f then
    f = CreateFrame("Frame", nil, ctl.c); f:SetFrameLevel(ctl.c:GetFrameLevel() + 20)
    f.t = f:CreateTexture(nil, "OVERLAY"); f.t:SetAllPoints(); f.t:SetTexture(UI.ART.glow); f.t:SetBlendMode("ADD")
    f:SetScript("OnUpdate", function(self, el)
      self.left = self.left - el
      local a = math.max(0, math.min(1, self.left)) * (0.6 + 0.4 * math.sin(GetTime() * 8))
      self.t:SetAlpha(a)
      if self.left <= 0 then self:Hide() end
    end)
    ctl.flash = f
  end
  local th = UI:Theme(); f.t:SetVertexColor(th.gold[1], th.gold[2], th.gold[3])
  local o = e.obj
  local w = (o.GetStringWidth and o:GetStringWidth()) or (o.label and (o.label:GetStringWidth() + 28)) or o:GetWidth() or 120
  f:ClearAllPoints(); f:SetPoint("LEFT", o, "LEFT", -14, 0); f:SetSize(w + 28, math.max(26, (o:GetHeight() or 18) + 12))
  f.left = 2.2; f:Show()
end
buildSearch = function(p)
  local box = UI:Edit(p, 300, 24, "Search settings...")
  box:SetPoint("TOPLEFT", 0, -2)
  local res = CreateFrame("Frame", nil, p, BackdropTemplateMixin and "BackdropTemplate" or nil)
  res:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -2); res:SetWidth(460); res:SetFrameLevel(p:GetFrameLevel() + 40)
  UI:Skin(res, function(self, th) UI.Flat(self, th.bg, 0.98, th.gold, 0.8, 1) end)
  res.rows = {}
  res:Hide()
  local hits = {}
  local function show()
    local q = S.Trim(box:GetText() or ""):lower()
    for _, r in ipairs(res.rows) do r:Hide() end
    if q == "" then res:Hide() return end
    hits = {}
    local seen = {}
    for _, e in ipairs(entries()) do
      local key = e.text .. "|" .. math.floor(e.off)
      if not seen[key] and e.text:lower():find(q, 1, true) then seen[key] = true; hits[#hits + 1] = e end
    end
    table.sort(hits, function(a, b) return a.off < b.off end)
    local n = math.min(10, #hits)
    for i = 1, n do
      local r = res.rows[i]
      if not r then
        r = CreateFrame("Button", nil, res); r:SetHeight(22)
        r:SetPoint("TOPLEFT", 6, -4 - (i - 1) * 22); r:SetPoint("RIGHT", res, "RIGHT", -6, 0)
        local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.07)
        r.sec = UI:Text(r, "", "small"); r.sec:SetPoint("LEFT", 2, 0); r.sec:SetWidth(130); r.sec:SetWordWrap(false); r.sec:SetJustifyH("LEFT")
        r.txt = UI:Text(r, "", "normal"); r.txt:SetPoint("LEFT", 138, 0); r.txt:SetPoint("RIGHT", -2, 0); r.txt:SetWordWrap(false); r.txt:SetJustifyH("LEFT")
        r:SetScript("OnClick", function(self) if not self.e then return end; res:Hide(); box:ClearFocus(); jump(self.e) end)
        res.rows[i] = r
      end
      local e = hits[i]
      r.e = e
      r.sec:SetText("|cff888888" .. (e.section or "") .. "|r")
      local t = e.text:gsub("\n.*", "")
      if #t > 70 then t = t:sub(1, 67) .. "..." end
      r.txt:SetText(t)
      r:Show()
    end
    if n == 0 then
      local r = res.rows[1]
      if r then r.e = nil; r.sec:SetText(""); r.txt:SetText("|cff888888No setting matches that.|r"); r:Show(); n = 1 end
    end
    res:SetHeight(n * 22 + 8)
    res:SetShown(n > 0 and (#hits > 0 or res.rows[1] ~= nil))
  end
  box:HookScript("OnTextChanged", show)
  box:SetScript("OnEnterPressed", function(self) if hits[1] then res:Hide(); self:ClearFocus(); jump(hits[1]) end end)
  box:SetScript("OnEscapePressed", function(self) self:SetText(""); res:Hide(); self:ClearFocus() end)
  box:HookScript("OnEditFocusLost", function() C_Timer.After(0.25, function() res:Hide() end) end)
  ctl.search = box
end

local function refresh()
  if not ctl.cmds then return end
  if ctl.dock then ctl.dock:SetChecked(S.db.global.dockMode and true or false) end
  if ctl.border then ctl.border:SetChecked(S.db.global.borderMode and not S.db.global.dockMode and true or false) end
  local lines = {}
  -- "|" starts a colour/link code in game text, so it has to be doubled to show up
  local function esc(t) return (tostring(t or ""):gsub("|", "||")) end
  for _, cmd in ipairs(S.commands) do lines[#lines + 1] = "|cffffff00/ccenter " .. esc(cmd.cmd) .. (cmd.args ~= "" and (" " .. esc(cmd.args)) or "") .. "|r  -  " .. esc(cmd.desc) end
  lines[#lines + 1] = "|cffffff00/ccenter|r  -  open / close Command Center   (|cffffff00/commandcenter|r works too)"
  ctl.cmds:SetText(table.concat(lines, "\n"))
  if ctl.content then ctl.content:SetHeight(-(ctl.cmdsY or 0) + (ctl.cmds:GetStringHeight() or 400) + 40) end
end

S:AddTab("settings", "Settings", build, refresh)


---------------------------------------------------------------------------
-- Custom colours: accent picker / sliders and background hue, saturation, brightness
---------------------------------------------------------------------------
local cwin
local applyPending
local function applyColors()
  S.db.global.theme = "custom"
  if ctl.theme and ctl.theme.SetValue then pcall(ctl.theme.SetValue, ctl.theme, "custom") end
  if applyPending then return end
  applyPending = true
  C_Timer.After(0.05, function()
    applyPending = false
    UI:ApplyTheme(); S:RefreshCurrent()
    if S.QuickBarLayout then S:QuickBarLayout() end
  end)
end
local function syncSliders()
  if not cwin then return end
  local cs = UI:CustomSettings()
  cwin.ah:SetValue(cs.ah or 41); cwin.as:SetValue((cs.as or 0.67) * 100); cwin.av:SetValue((cs.av or 0.88) * 100)
  cwin.tint:SetChecked(cs.tintBg and true or false)
  cwin.bh:SetValue(cs.bh or 22); cwin.bs:SetValue((cs.bs or 1) * 100); cwin.bv:SetValue((cs.bv or 1) * 100)
  local r, g, b = UI.HSVtoRGB(cs.ah or 41, cs.as or 0.67, cs.av or 0.88)
  cwin.swatch:SetColorTexture(r, g, b, 1)
end
function S:ShowColorEditor()
  if not cwin then
    cwin = UI:Window("CC_Colors", "Custom colours", 440, 420)
    cwin:SetFrameStrata("DIALOG")
    local cs = UI:CustomSettings()
    local y = -40
    local function row(h) local yy = y; y = y - (h or 28); return yy end
    local baseL = UI:Text(cwin, "Start from", "small"); baseL:SetPoint("TOPLEFT", 16, y - 4)
    local bOpts = {}
    for _, k in ipairs(UI.THEME_ORDER) do if k ~= "custom" then bOpts[#bOpts + 1] = { text = UI.THEMES[k].name, value = k } end end
    cwin.base = UI:Dropdown(cwin, 180, bOpts, cs.base or "horde", function(v) UI:CustomSettings().base = v; applyColors() end)
    cwin.base:SetPoint("TOPLEFT", 152, row(34))
    local h1 = UI:Header(cwin, "Accent colour"); h1:SetPoint("TOPLEFT", 16, row(26))
    cwin.swatch = cwin:CreateTexture(nil, "ARTWORK"); cwin.swatch:SetSize(22, 22); cwin.swatch:SetPoint("TOPLEFT", 16, y)
    local pick = UI:Button(cwin, "Pick colour...", 120, 22, function()
      local c = UI:CustomSettings()
      local col = { UI.HSVtoRGB(c.ah or 41, c.as or 0.67, c.av or 0.88) }
      if not UI.PickColor then return end
      UI.PickColor(col, function()
        local h, sat, v = UI.RGBtoHSV(col[1], col[2], col[3])
        c.ah, c.as, c.av = math.floor(h + 0.5), sat, v
        syncSliders(); applyColors()
      end)
    end, "Open the game's colour picker.")
    pick:SetPoint("LEFT", cwin.swatch, "RIGHT", 10, 0)
    row(30)
    local function slider(label, min, max, val, fn, fmt)
      local sl = UI:Slider(cwin, 408, label, min, max, 1, val, fn, fmt)
      sl:SetPoint("TOPLEFT", 16, row(26))
      return sl
    end
    local pct = function(v) return math.floor(v + 0.5) .. "%" end
    local deg = function(v) return math.floor(v + 0.5) .. "°" end
    cwin.ah = slider("Hue", 0, 359, cs.ah or 41, function(v) UI:CustomSettings().ah = v; syncSliders(); applyColors() end, deg)
    cwin.as = slider("Saturation", 0, 100, (cs.as or 0.67) * 100, function(v) UI:CustomSettings().as = v / 100; syncSliders(); applyColors() end, pct)
    cwin.av = slider("Brightness", 10, 100, (cs.av or 0.88) * 100, function(v) UI:CustomSettings().av = v / 100; syncSliders(); applyColors() end, pct)
    row(6)
    local h2 = UI:Header(cwin, "Backgrounds"); h2:SetPoint("TOPLEFT", 16, row(26))
    cwin.tint = UI:Check(cwin, "Give backgrounds my own hue", cs.tintBg, function(v) UI:CustomSettings().tintBg = v; applyColors() end)
    cwin.tint:SetPoint("TOPLEFT", 16, row(26))
    cwin.bh = slider("Hue", 0, 359, cs.bh or 22, function(v) UI:CustomSettings().bh = v; applyColors() end, deg)
    cwin.bs = slider("Saturation", 0, 200, (cs.bs or 1) * 100, function(v) UI:CustomSettings().bs = v / 100; applyColors() end, pct)
    cwin.bv = slider("Brightness", 40, 250, (cs.bv or 1) * 100, function(v) UI:CustomSettings().bv = v / 100; applyColors() end, pct)
    local reset = UI:Button(cwin, "Reset", 90, 24, function()
      local c = UI:CustomSettings()
      for k, v in pairs(UI.CUSTOM_DEFAULT) do c[k] = v end
      syncSliders(); applyColors()
    end, "Back to the default custom colours.")
    reset:SetPoint("BOTTOMLEFT", 16, 14)
    local done = UI:PrimaryButton(cwin, "Done", 90, 24, function() cwin:Hide() end)
    done:SetPoint("BOTTOMRIGHT", -16, 14)
    cwin:HookScript("OnShow", syncSliders)
  end
  cwin:Show(); cwin:Raise(); syncSliders()
  if S.db.global.theme ~= "custom" then applyColors() end
end
S:AddCommand("colors", "", "Make your own colour scheme", function() S:ShowColorEditor() end)
