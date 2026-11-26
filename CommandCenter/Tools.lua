-- Tools: one small window with an on/off switch for every pop-out window.
local _, S = ...
local UI = S.UI

local win
local ROW_H = 50
local TOP = 66      -- first row starts below the two-line hint
local WIN_W = 420

local function shown(name) local f = _G[name]; return f and f:IsShown() and true or false end
local function hide(name) local f = _G[name]; if f then f:Hide() end end

-- each tool: label, line under it, icon, available(), isOn(), set(on)
local TOOLS = {
  { label = "BiB", name = "BiB |cff888888(Built-in Bag)|r", tileName = "BiB", desc = "All your bags in one window - sorted, searchable, your style", icon = UI.ICON.bag, tint = true,
    tip = "Optional: when it's on, BiB opens instead of the game's bags.",
    available = function() return S.ShowBiB ~= nil end,
    isOn = function() return shown("CC_BiB") end,
    set = function(on) if on then S:ShowBiB() else S:HideBiB() end end },
  { label = "Damage Meter", desc = "Damage, healing, kicks, dispels and deaths for your group", icon = UI.ICON.meter, tint = true,
    available = function() return S.ShowMeter ~= nil end,
    isOn = function() return shown("CC_Meter") end,
    set = function(on) if on then S:ShowMeter() else S:HideMeter() end end },
  { label = "Messenger", desc = "Your whispers as chats, with sounds and pop-ups", icon = UI.ICON.messages, tint = true,
    available = function() return S.ShowMessenger ~= nil end,
    isOn = function() return shown("CC_Messenger") end,
    set = function(on) if on then S:ShowMessenger() else hide("CC_Messenger") end end },
  { label = "Button Box", desc = "A box for any icons: tools, game menu, other addons", icon = UI.ICON.box, tint = true,
    available = function() return S.ShowButtonBox ~= nil end,
    isOn = function() return shown("CC_ButtonBox") end,
    set = function(on) if on then S:ShowButtonBox() else S:HideButtonBox() end end },
  { label = "Screenshot", desc = "Tune the picture, then snap it without the interface", icon = UI.ICON.camera, tint = true,
    available = function() return S.ShowSnap ~= nil end,
    isOn = function() return shown("CC_Snap") end,
    set = function(on) if on then S:ShowSnap() else hide("CC_Snap") end end },
  { label = "Reminders", desc = "Alarms with a pop-up, on-screen text and a sound", icon = UI.ICON.clock, tint = true,
    available = function() return S.ShowReminders ~= nil end,
    isOn = function() return shown("CC_Reminders") end,
    set = function(on) if on then S:ShowReminders() else hide("CC_Reminders") end end },
  { label = "Summoner", desc = "Warlocks: collect 123s and summon with one click", icon = UI.ICON.summon, tint = true,
    class = "WARLOCK",
    available = function() return S.ShowSummoner ~= nil end,
    isOn = function() return shown("CC_Summoner") end,
    set = function(on) if on then S:ShowSummoner() else S:HideSummoner() end end },
  { label = "Rotational", name = "Rotational |cffff9933EXPERIMENTAL|r", tileTag = "|cffff9933Experimental|r", desc = "The right button glows when it's time to press it", icon = UI.ICON.rotation, tint = true,
    tip = "This is in development and has only been tested and working on Enhancement Shaman.",
    available = function() return S.ShowRotational ~= nil end,
    removed = function() return S.ROTATIONAL_REMOVED end,   -- (removed for now, see Rotational.lua)
    switchedOff = function() return S.RotationalOn ~= nil and not S.RotationalOn() end,
    isOn = function() return shown("CC_Rotational") end,
    set = function(on) if on then S:ShowRotational() else S:HideRotational() end end },
  { label = "ItemMenu", desc = "Right-click items for open all, links, sources, auto delete", icon = UI.ICON.itemmenu, tint = true,
    available = function() return S.ShowItemMenu ~= nil end,
    isOn = function() return shown("CC_ItemMenu") end,
    set = function(on) if on then S:ShowItemMenu() else S:HideItemMenu() end end },
  { label = "BuffWatcher", desc = "Buffs and weapon enchants to keep up", icon = UI.ICON.buffs, tint = true,
    available = function() return S.ShowBuffWatcher ~= nil end,
    isOn = function() return shown("CC_BuffWatcher") end,
    set = function(on) if on then S:ShowBuffWatcher() else S:HideBuffWatcher() end end },
  { label = "Radialz", desc = "A radial action bar: spells, items and macros on a wheel, with pages", icon = UI.ICON.radialz, tint = true,
    tip = "Mouse button 5 opens the wheel at the mouse, left-click a slot to use it. /ccenter radialz",
    available = function() return S.ShowRadialz ~= nil end,
    isOn = function() return shown("CC_Radialz") end,
    set = function(on) if on then S:ShowRadialz() else S:HideRadialz() end end },
  { label = "HealAssist", desc = "HealBot-style healing frames: click to heal, the right rank picked for you", icon = UI.ICON.heal, tint = true,
    tip = "Smart clicks pick the spell rank from how much health is missing (your steps on the Ranks tab). /ccenter heal",
    available = function() return S.ShowHealAssist ~= nil end,
    isOn = function() return shown("CC_HealAssist") end,
    set = function(on) if on then S:ShowHealAssist() else S:HideHealAssist() end end },
  { label = "Minimap", desc = "Your theme on the minimap: shape, size, zone bar, clock, coordinates", icon = UI.ICON.minimap, tint = true,
    available = function() return S.ShowMinimapSettings ~= nil end,
    isOn = function() return shown("CC_MinimapSettings") end,
    set = function(on) if on then S:ShowMinimapSettings() else S:HideMinimapSettings() end end },
  { label = "Unit Frames", desc = "Player, target, party, raid and boss frames in your theme", icon = UI.ICON.unitframes, tint = true,
    tip = "Turn them on inside the window (\"Use Command Center unit frames\"). Unlock to drag them, Test mode to preview.",
    available = function() return S.ShowUnitFrames ~= nil end,
    isOn = function() return shown("CC_UnitFrames") end,
    set = function(on) if on then S:ShowUnitFrames() else S:HideUnitFrames() end end },
  { label = "CCPlates", desc = "Nameplates in your theme: threat, casts, execute, target glow", icon = UI.ICON.plates, tint = true,
    tip = "Turn them on inside the window (\"Use CCPlates\"). Pick a Look, the preview shows every change.",
    available = function() return S.ShowPlates ~= nil end,
    isOn = function() return shown("CC_Plates") end,
    set = function(on) if on then S:ShowPlates() else S:HidePlates() end end },
  { label = "Guide", desc = "Every tool and setting explained", icon = UI.ICON.book, tint = true,
    available = function() return S.ShowGuide ~= nil end,
    isOn = function() return shown("CC_Guide") end,
    set = function(on) if on then S:ShowGuide() else hide("CC_Guide") end end },
  { label = "Guided tour", desc = "Walk through Command Center again", icon = UI.ICON.home, tint = true,
    available = function() return S.ShowTutorial ~= nil end,
    isOn = function() return shown("CC_Tutorial") end,
    set = function(on) if on then S:ShowTutorial(true) elseif S.EndTour then S:EndTour() else hide("CC_Tutorial") end end },
}
local function refresh()
  if not win or not win:IsShown() then return end
  local th = UI:Theme()
  for i, t in ipairs(TOOLS) do
    local r = win.rows[i]
    local okA, avail = pcall(t.available); avail = okA and avail and true or false
    local okO, on = pcall(t.isOn); on = okO and on and true or false
    r.avail, r.on = avail, on
    -- open windows get a glowing green edge
    r.lit:SetShown(on and avail)
    if on and avail then
      UI.Flat(r.lit, th.live, 0.07, th.live, 0.9)
      r.litGlow:SetVertexColor(th.live[1], th.live[2], th.live[3], 0.45)
    end
    r.label:SetTextColor(UI.C(avail and th.text or th.muted))
    r.desc:SetText(avail and t.desc or ("|cff888888" .. (t.off or t.desc) .. "|r"))
    r.icon:SetDesaturated(not avail)
  end
end

-- display order (drag rows to rearrange; saved per account)
local function order()
  local g = S.db.global
  local saved = type(g.toolsOrder) == "table" and g.toolsOrder or {}
  local byLabel, out, used = {}, {}, {}
  for i, t in ipairs(TOOLS) do byLabel[t.label] = i end
  for _, lbl in ipairs(saved) do local i = byLabel[lbl]; if i and not used[i] then used[i] = true; out[#out + 1] = i end end
  for i in ipairs(TOOLS) do if not used[i] then out[#out + 1] = i end end
  return out
end
local function saveOrder(list)
  local labels = {}
  for _, i in ipairs(list) do labels[#labels + 1] = TOOLS[i].label end
  S.db.global.toolsOrder = labels
end
-- tools you dragged out of the box (bring them back with the + in the title bar)
local function hidden() local g = S.db.global; g.toolsHidden = type(g.toolsHidden) == "table" and g.toolsHidden or {}; return g.toolsHidden end
local function added() local g = S.db.global; g.toolsAdded = type(g.toolsAdded) == "table" and g.toolsAdded or {}; return g.toolsAdded end
local function allowed(t)
  if t.officer and not S:IsOfficer() then return false end
  if t.removed then local ok, gone = pcall(t.removed); if ok and gone then return false end end
  if t.switchedOff then local ok, off = pcall(t.switchedOff); if ok and off then return false end end   -- (turned off in Settings)
  if t.class then local _, c = UnitClass("player"); if c ~= t.class then return false end end
  return true
end
local function isHidden(t)
  if not allowed(t) then return true end
  if hidden()[t.label] then return true end
  return t.addOnly and not added()[t.label]
end
local function visibleOrder()
  local out = {}
  for _, i in ipairs(order()) do if not isHidden(TOOLS[i]) then out[#out + 1] = i end end
  return out
end
local function layout()
  if not win then return end
  local list = visibleOrder()
  for _, r in ipairs(win.rows) do r:Hide() end
  for pos, i in ipairs(list) do
    local r = win.rows[i]
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", 10, -TOP - (pos - 1) * ROW_H); r:SetPoint("RIGHT", win, "RIGHT", -10, 0)
    r.line:SetShown(pos < #list)
    r:Show()
  end
  win.empty:SetShown(#list == 0)
  win:SetHeight(TOP - 8 + math.max(1, #list) * ROW_H + 16)
end

---------------------------------------------------------------------------
-- Shortcuts: right-click a tool > Create shortcut. A round icon you can put
-- anywhere: left-click opens / closes the tool, drag moves it, right-click
-- for size and delete. Saved per account.
---------------------------------------------------------------------------
local byLabel = {}
for _, t in ipairs(TOOLS) do byLabel[t.label] = t end
local SIZES = { { "Small", 32 }, { "Medium", 44 }, { "Large", 60 } }
local shortcuts = {}   -- label -> frame
local function scList() local g = S.db.global; g.toolShortcuts = type(g.toolShortcuts) == "table" and g.toolShortcuts or {}; return g.toolShortcuts end
local function scRec(label) for _, r in ipairs(scList()) do if r.label == label then return r end end end

local function applyShortcut(f, rec)
  f:SetSize(rec.size or 44, rec.size or 44)
  f:ClearAllPoints()
  if rec.x and rec.y then f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", rec.x, rec.y) else f:SetPoint("CENTER", UIParent, "CENTER", 0, 120) end
  -- Settings > icon style: plain icons (default) or icons in circles
  local circles = UI.IconCircles and UI:IconCircles()
  f.disc:SetShown(circles and true or false); f.ring:SetShown(circles and true or false)
  local k = circles and 0.62 or 0.9
  f.icon:SetSize((rec.size or 44) * k, (rec.size or 44) * k)
end
function S:RestyleToolShortcuts()
  for _, rec in ipairs(scList()) do local f = shortcuts[rec.label]; if f and f:IsShown() then applyShortcut(f, rec) end end
end

local function makeShortcut(rec)
  local t = byLabel[rec.label]
  if not t then return end
  local f = shortcuts[rec.label]
  if not f then
    f = CreateFrame("Button", nil, UIParent)
    f:SetFrameStrata("MEDIUM"); f:SetMovable(true); f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton"); f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f.disc = f:CreateTexture(nil, "BACKGROUND"); f.disc:SetTexture(UI.MEDIA .. "UI\\disc"); f.disc:SetAllPoints()
    f.ring = f:CreateTexture(nil, "BORDER"); f.ring:SetTexture(UI.MEDIA .. "UI\\ring"); f.ring:SetAllPoints()
    f.glow = f:CreateTexture(nil, "BACKGROUND", nil, -1); f.glow:SetTexture(UI.ART.glow); f.glow:SetBlendMode("ADD")
    f.glow:SetPoint("TOPLEFT", -10, 10); f.glow:SetPoint("BOTTOMRIGHT", 10, -10); f.glow:Hide()
    f.icon = f:CreateTexture(nil, "ARTWORK"); f.icon:SetPoint("CENTER"); f.icon:SetTexture(t.icon)
    if tostring(t.icon):find("Icons") then f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
    UI:Skin(f, function(self, th)
      self.disc:SetVertexColor(th.panel[1], th.panel[2], th.panel[3], 0.95)
      self.ring:SetVertexColor(th.gold[1], th.gold[2], th.gold[3], 1)
      self.glow:SetVertexColor(th.live[1], th.live[2], th.live[3], 0.7)
      if t.tint then self.icon:SetVertexColor(th.gold[1], th.gold[2], th.gold[3]) end
    end)
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
      self:StopMovingOrSizing(); self.justDragged = GetTime()
      local x, y = self:GetCenter()
      local r = scRec(rec.label); if r and x then r.x, r.y = math.floor(x + 0.5), math.floor(y + 0.5) end
    end)
    f:SetScript("OnClick", function(self, btn)
      if self.justDragged and GetTime() - self.justDragged < 0.3 then return end
      if btn == "RightButton" then
        local r = scRec(rec.label)
        local items = { { text = rec.label .. " shortcut", title = true }, { text = "Size", title = true } }
        for _, sz in ipairs(SIZES) do
          items[#items + 1] = { text = sz[1], checked = r and r.size == sz[2], func = function() if r then r.size = sz[2]; applyShortcut(self, r) end end }
        end
        if S.db.global.dockMode and S.AddToolToDock then
          items[#items + 1] = { text = "Move to the dock", func = function() S:AddToolToDock(rec.label) end }
        end
        items[#items + 1] = { text = "|cffff7777Delete shortcut|r", func = function() S:DeleteToolShortcut(rec.label) end }
        UI:Menu(self, items)
        return
      end
      local okA, avail = pcall(t.available)
      if not (okA and avail) then S:Print(rec.label .. ": " .. (t.off or "not available right now") .. ".") return end
      local okO, on = pcall(t.isOn)
      local ok, err = pcall(t.set, not (okO and on)); if not ok then S.report(err) end
      if PlaySound and SOUNDKIT and SOUNDKIT.U_CHAT_SCROLL_BUTTON then PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON) end
    end)
    f:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine(rec.label, 1, 0.82, 0)
      GameTooltip:AddLine("Left-click: open / close", 1, 1, 1)
      GameTooltip:AddLine("Drag: move    Right-click: size / delete", 0.7, 0.7, 0.7)
      GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- glow while that tool's window is open
    f:SetScript("OnUpdate", function(self, el)
      self.acc = (self.acc or 0) + el
      if self.acc < 0.5 then return end
      self.acc = 0
      local okO, on = pcall(t.isOn)
      self.glow:SetShown(okO and on and true or false)
      local okA, avail = pcall(t.available)
      self.icon:SetDesaturated(not (okA and avail))
    end)
    shortcuts[rec.label] = f
  end
  applyShortcut(f, rec)
  f:Show()
  return f
end

-- other addons add themselves as a tool (home tile, Tools window, dock, Button Box):
-- CommandCenter:RegisterTool{ label, desc, icon, available(), isOn(), set(on), window = "FrameName" }
function S:RegisterTool(t)
  if type(t) ~= "table" or not t.label or byLabel[t.label] then return false end
  t.available = t.available or function() return true end
  t.isOn = t.isOn or function() return false end
  t.set = t.set or function() end
  t.external = true
  TOOLS[#TOOLS + 1] = t
  byLabel[t.label] = t
  if win then win:Hide(); win = nil end          -- the Tools window is rebuilt with the new row next time
  if S.QuickBarLayout then pcall(S.QuickBarLayout, S) end
  return true
end

-- every tool this character can use, in toolbox order (for the Button Box)
function S:ToolLabels()
  local out = {}
  for _, i in ipairs(order()) do local t = TOOLS[i]; if allowed(t) then out[#out + 1] = t.label end end
  return out
end
function S:HasToolShortcut(label) return scRec(label) ~= nil end
-- for the dock: a tool's definition, whether it can be used right now and whether it's open
function S:ToolInfo(label)
  local t = byLabel[label]
  if not t then return end
  if t.removed then local ok, gone = pcall(t.removed); if ok and gone then return end end   -- (dock / box / shortcuts skip it)
  local okA, avail = pcall(t.available)
  local okO, on = pcall(t.isOn)
  return t, okA and avail and true or false, okO and on and true or false
end
function S:ToolToggle(label)
  local t, avail, on = S:ToolInfo(label)
  if not t then return end
  if not avail then S:Print(label .. ": " .. (t.off or "not available right now") .. ".") return end
  local ok, err = pcall(t.set, not on); if not ok then S.report(err) end
end
function S:CreateToolShortcut(label)
  if scRec(label) then return end
  -- one icon per tool: a tool that lives in the dock moves out of it
  if S.DockHasTool and S:DockHasTool(label) then
    if S.DockBuiltIn and S:DockBuiltIn(label) then S:Print("|cffffd100" .. label .. "|r is already in your dock.") return end
    S:RemoveToolFromDock(label)
  end
  local rec = { label = label, size = 44 }
  table.insert(scList(), rec)
  local f = makeShortcut(rec)
  -- start next to the toolbox so it's easy to find
  if f and win and win:IsShown() and win:GetLeft() then
    local x, y = win:GetLeft() - 40, (win:GetTop() or 400) - 40
    rec.x, rec.y = math.floor(x), math.floor(y)
    applyShortcut(f, rec)
  end
  S:Print("Shortcut for |cffffd100" .. label .. "|r created - drag it anywhere. Right-click it to resize or delete.")
end
function S:DeleteToolShortcut(label, quiet)
  local list = scList()
  for i, r in ipairs(list) do if r.label == label then table.remove(list, i) break end end
  if shortcuts[label] then shortcuts[label]:Hide() end
end
S:Listen("LOGIN", function()
  C_Timer.After(1, function() for _, rec in ipairs(scList()) do makeShortcut(rec) end end)
end)

local function build()
  win = UI:Window("CC_Tools", "Tools", WIN_W, TOP - 8 + #TOOLS * ROW_H + 16)
  win.rowsFor = TOOLS
  win:SetFrameStrata("HIGH")
  local main = S.MainFrame and S:MainFrame()
  if main then win:ClearAllPoints(); win:SetPoint("TOPLEFT", main, "TOPRIGHT", 10, 0) end
  win.sub = UI:Text(win, "Click a tool to open or close it. Drag to reorder, out of the box to remove it, or onto your dock / border bar to add it there. Right-click for a shortcut.", "muted")
  win.sub:SetPoint("TOPLEFT", 16, -34); win.sub:SetPoint("RIGHT", win, "RIGHT", -16, 0); win.sub:SetJustifyH("LEFT"); win.sub:SetWordWrap(true)
  -- where a dragged row will land
  win.marker = win:CreateTexture(nil, "OVERLAY"); win.marker:SetHeight(2); win.marker:Hide()
  UI:Skin(win.marker, function(self, th) self:SetColorTexture(th.gold[1], th.gold[2], th.gold[3], 1) end)
  win.empty = UI:Text(win, "Your toolbox is empty.\nClick the |cffffd100+|r in the top right to add tools back.", "small", "CENTER")
  win.empty:SetPoint("TOP", 0, -TOP - 8); win.empty:SetWidth(WIN_W - 40)

  -- + in the title bar: add back tools you removed
  win.add = win:HeaderButton("plus", "Add tools", "Bring back tools you dragged out of the toolbox.", function(self)
    local items = { { text = "Add to toolbox", title = true } }
    for _, t in ipairs(TOOLS) do
      if allowed(t) and isHidden(t) then
        items[#items + 1] = { text = (t.name or t.label) .. (t.officer and "  |cff888888(officers)|r" or ""),
          func = function() hidden()[t.label] = nil; if t.addOnly then added()[t.label] = true end; layout(); refresh() end }
      end
    end
    if #items == 1 then items[2] = { text = "|cff888888Every tool is already in the box|r", disabled = true } end
    UI:Menu(self, items)
  end)
  -- glow on the + while we remind you where removed tools go
  win.addGlow = win.add:CreateTexture(nil, "OVERLAY"); win.addGlow:SetTexture(UI.ART.glow); win.addGlow:SetBlendMode("ADD")
  win.addGlow:SetPoint("TOPLEFT", -10, 10); win.addGlow:SetPoint("BOTTOMRIGHT", 10, -10); win.addGlow:Hide()
  win.add:HookScript("OnUpdate", function(self) if win.addGlow:IsShown() then win.addGlow:SetAlpha(0.5 + 0.5 * math.sin(GetTime() * 6)) end end)
  UI:Skin(win.addGlow, function(self, th) self:SetVertexColor(th.gold[1], th.gold[2], th.gold[3], 1) end)

  -- the trash can that follows the cursor when a row is dragged out of the box
  win.trash = CreateFrame("Frame", nil, UIParent); win.trash:SetSize(40, 40); win.trash:SetFrameStrata("TOOLTIP"); win.trash:Hide()
  win.trash.icon = UI:Icon(win.trash, "trash", 30, "OVERLAY"); win.trash.icon:SetPoint("CENTER"); win.trash.icon:SetVertexColor(1, 0.35, 0.3)
  win.trash.glow = win.trash:CreateTexture(nil, "BACKGROUND"); win.trash.glow:SetTexture(UI.ART.glow); win.trash.glow:SetAllPoints()
  win.trash.glow:SetVertexColor(1, 0.2, 0.15, 0.7)
  win.trash.text = UI:Text(win.trash, "|cffff6655Remove|r", "small", "CENTER"); win.trash.text:SetPoint("TOP", win.trash, "BOTTOM", 0, 2)

  win.rows = {}
  for i, t in ipairs(TOOLS) do
    local r = CreateFrame("Button", nil, win)
    r:SetPoint("TOPLEFT", 10, -TOP - (i - 1) * ROW_H); r:SetPoint("RIGHT", win, "RIGHT", -10, 0); r:SetHeight(ROW_H - 4)
    local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetTexture("Interface\\Buttons\\WHITE8x8")
    r.lit = CreateFrame("Frame", nil, r); r.lit:SetAllPoints(); r.lit:SetFrameLevel(r:GetFrameLevel()); r.lit:Hide()
    r.litGlow = r.lit:CreateTexture(nil, "BACKGROUND", nil, -7); r.litGlow:SetTexture(UI.ART.glow); r.litGlow:SetBlendMode("ADD")
    r.litGlow:SetPoint("TOPLEFT", -12, 12); r.litGlow:SetPoint("BOTTOMRIGHT", 12, -12)
    UI:Skin(r, function(_, th) hl:SetVertexColor(th.gold[1], th.gold[2], th.gold[3], 0.06) end)
    r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(26, 26); r.icon:SetPoint("LEFT", 6, 0); r.icon:SetTexture(t.icon)
    if t.tint then UI:Skin(r.icon, function(self, th) self:SetVertexColor(UI.C(th.gold)) end)
    elseif tostring(t.icon):find("Icons") then r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
    r.label = UI:Text(r, t.name or t.label, "normal"); r.label:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 10, 2)
    -- hovering a tool that has a note shows it
    if t.tip then
      r:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(t.name or t.label, 1, 0.82, 0)
        GameTooltip:AddLine(t.tip, 1, 1, 1, true)
        GameTooltip:Show()
      end)
      r:HookScript("OnLeave", function() GameTooltip:Hide() end)
    end
    r.desc = UI:Text(r, t.desc, "small"); r.desc:SetPoint("TOPLEFT", r.label, "BOTTOMLEFT", 0, -3); r.desc:SetPoint("RIGHT", r, "RIGHT", -8, 0); r.desc:SetJustifyH("LEFT"); r.desc:SetWordWrap(false)
    -- click anywhere on the row to flip it
    r:RegisterForDrag("LeftButton")
    r:SetScript("OnDragStart", function(self)
      win.dragging = i; self:SetAlpha(0.55); GameTooltip:Hide()
      win.marker:Show()
    end)
    r:SetScript("OnDragStop", function(self)
      self:SetAlpha(1); win.marker:Hide(); win.trash:Hide()
      self.icon:SetTexture(t.icon); self.icon:SetVertexColor(1, 1, 1); if t.tint then self.icon:SetVertexColor(UI.C(UI:Theme().gold)) end
      local from, to, out, bar = win.dragging, win.dropPos, win.dropOut, win.dropBar
      win.dragging, win.dropPos, win.dropOut, win.dropBar = nil, nil, nil, nil
      self.justDragged = GetTime()
      if S.QuickBarShowDrop then S:QuickBarShowDrop(false) end
      if not from then return end
      -- dropped on the dock / border bar: add it there (it stays in the toolbox too)
      if out and bar and S.QuickBarDropTool then
        S:QuickBarDropTool(t.label)
        return
      end
      if out then
        -- dropped outside the toolbox: remove it (after asking)
        win.addGlow:Show()
        UI:Confirm("Remove |cffffd100" .. t.label .. "|r from your toolbox?\n\n|cffaaaaaaYou can always bring any tool back with the|r |cffffd100+|r |cffaaaaaain the top right corner of the toolbox.|r", function()
          hidden()[t.label] = true; added()[t.label] = nil
          layout(); refresh()
        end, "Remove")
        local cw = _G.CC_Confirm
        if cw and not cw.__toolsHook then
          cw.__toolsHook = true
          cw:HookScript("OnHide", function() if win and win.addGlow then win.addGlow:Hide() end end)
        end
        return
      end
      if not to then return end
      -- reorder among the visible rows, keeping hidden ones where they are
      local vis = visibleOrder()
      local cur
      for pos, idx in ipairs(vis) do if idx == from then cur = pos end end
      if not cur then return end
      table.remove(vis, cur)
      if to > cur then to = to - 1 end
      to = math.max(1, math.min(#vis + 1, to))
      local before = vis[to]   -- the row it lands in front of (nil = at the end)
      local full = order()
      for k, idx in ipairs(full) do if idx == from then table.remove(full, k) break end end
      local at = #full + 1
      if before then for k, idx in ipairs(full) do if idx == before then at = k break end end end
      table.insert(full, at, from)
      saveOrder(full); layout()
    end)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r:SetScript("OnClick", function(self, btn)
      if r.justDragged and GetTime() - r.justDragged < 0.3 then return end
      if btn == "RightButton" then
        local has = S:HasToolShortcut(t.label)
        local inDock = S.DockHasTool and S:DockHasTool(t.label)
        local builtIn = S.DockBuiltIn and S:DockBuiltIn(t.label)
        local dockOn = S.db.global.dockMode and S.AddToolToDock
        local items = { { text = t.name or t.label, title = true } }
        if not (dockOn and builtIn) then
          items[#items + 1] = { text = has and "Shortcut is on your screen" or (inDock and "Create shortcut (moves it out of the dock)" or "Create shortcut"), disabled = has,
            func = function() S:CreateToolShortcut(t.label) end }
          if has then items[#items + 1] = { text = "|cffff7777Delete shortcut|r", func = function() S:DeleteToolShortcut(t.label) end } end
        end
        if dockOn then
          if builtIn then items[#items + 1] = { text = "|cff888888Always in the dock|r", disabled = true }
          elseif inDock then items[#items + 1] = { text = "|cffff7777Remove from dock|r", func = function() S:RemoveToolFromDock(t.label) end }
          else items[#items + 1] = { text = has and "Add to dock (replaces the shortcut)" or "Add to dock", func = function() S:AddToolToDock(t.label) end } end
        end
        UI:Menu(self, items)
        return
      end
      if not r.avail then return end
      if PlaySound and SOUNDKIT and SOUNDKIT.U_CHAT_SCROLL_BUTTON then PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON) end
      local ok, err = pcall(t.set, not r.on); if not ok then S.report(err) end
      C_Timer.After(0.05, refresh)
    end)
    local ln = r:CreateTexture(nil, "BORDER"); ln:SetPoint("BOTTOMLEFT", 4, -2); ln:SetPoint("BOTTOMRIGHT", -4, -2); ln:SetHeight(1)
    UI:Skin(ln, function(self, th) self:SetColorTexture(th.line[1], th.line[2], th.line[3], 0.8) end)
    r.line = ln
    win.rows[i] = r
  end
  layout()
  -- while dragging: follow the cursor and show the drop line
  win:HookScript("OnUpdate", function(self)
    if not self.dragging then return end
    local top, left, right, bottom = self:GetTop(), self:GetLeft(), self:GetRight(), self:GetBottom()
    if not top then return end
    local cx, cy = GetCursorPosition()
    local sc = self:GetEffectiveScale() or 1
    cx, cy = cx / sc, cy / sc
    local row = self.rows[self.dragging]
    -- outside the box: it turns into a trash can
    local out = left and (cx < left - 6 or cx > right + 6 or cy > top + 6 or cy < bottom - 6)
    self.dropOut = out
    if out then
      self.marker:Hide()
      local us = UIParent:GetEffectiveScale() or 1
      self.trash:ClearAllPoints(); self.trash:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx * sc / us, cy * sc / us)
      self.trash:Show()
      -- over the dock / border bar: drop it in there instead of removing it
      local bar = S.QuickBarDropTarget and S:QuickBarDropTarget()
      self.dropBar = bar
      if bar then
        self.trash.icon:SetTexture(UI.ICON.plus); self.trash.icon:SetVertexColor(0.4, 1, 0.4)
        self.trash.glow:SetVertexColor(0.2, 1, 0.3, 0.7)
        self.trash.text:SetText("|cff66ff66Add to " .. bar .. "|r")
        S:QuickBarShowDrop(true)
        local t = TOOLS[self.dragging]
        if row and t then row.icon:SetTexture(t.icon); row.icon:SetVertexColor(1, 1, 1); if t.tint then row.icon:SetVertexColor(UI.C(UI:Theme().gold)) end end
        return
      end
      if S.QuickBarShowDrop then S:QuickBarShowDrop(false) end
      self.trash.icon:SetTexture(UI.ICON.trash); self.trash.icon:SetVertexColor(1, 0.35, 0.3)
      self.trash.glow:SetVertexColor(1, 0.2, 0.15, 0.7)
      self.trash.text:SetText("|cffff6655Remove|r")
      if row then row.icon:SetTexture(UI.ICON.trash); row.icon:SetTexCoord(0, 1, 0, 1); row.icon:SetVertexColor(1, 0.35, 0.3) end
      return
    end
    self.dropBar = nil
    if S.QuickBarShowDrop then S:QuickBarShowDrop(false) end
    self.trash:Hide(); self.marker:Show()
    local t = TOOLS[self.dragging]
    if row and t then row.icon:SetTexture(t.icon); if tostring(t.icon):find("Icons") then row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end; row.icon:SetVertexColor(1, 1, 1); if t.tint then row.icon:SetVertexColor(UI.C(UI:Theme().gold)) end end
    local nvis = #visibleOrder()
    local pos = math.floor((top - TOP - cy) / ROW_H + 0.5) + 1
    pos = math.max(1, math.min(nvis + 1, pos))
    self.dropPos = pos
    self.marker:ClearAllPoints()
    self.marker:SetPoint("TOPLEFT", self, "TOPLEFT", 14, -TOP - (pos - 1) * ROW_H + 2)
    self.marker:SetPoint("RIGHT", self, "RIGHT", -14, 0)
  end)
  -- keep switches in step when windows are opened or closed elsewhere
  win:HookScript("OnUpdate", function(self, el)
    self.acc = (self.acc or 0) + el
    if self.acc > 0.4 then self.acc = 0; refresh() end
  end)
  win:HookScript("OnShow", refresh)
end

function S:ShowTools()
  if not win then build() end
  win:Show(); win:Raise(); refresh()
end
function S:ToggleTools()
  if win and win:IsShown() then win:Hide() else S:ShowTools() end
end

S.ToolsOrder = function() return order() end
S:AddCommand("tools", "", "Open the Tools window (pop-out toggles)", function() S:ToggleTools() end)
