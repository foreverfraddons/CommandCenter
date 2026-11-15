-- Button Box: a movable, resizable box you fill with any icons you like - Command Center's own
-- pages and tools, the game's menu buttons and bags, and other addons' minimap icons.
-- One icon per thing: putting something in the box takes it off the dock / border bar
-- (bring it back to the bar and it leaves the box). Addon icons in the box hide their
-- minimap button (see Plugins.lua).
local _, S = ...
local UI = S.UI

local PAD, HEAD, GAP = 12, 34, 6
local QMARK = "Interface\\Icons\\INV_Misc_QuestionMark"
local SIZES = { { "Small", 30 }, { "Medium", 38 }, { "Large", 48 } }

local function G() return S.db.global end
local function cfg()
  local g = G()
  g.box = type(g.box) == "table" and g.box or {}
  local b = g.box
  b.keys = type(b.keys) == "table" and b.keys or {}
  b.size = tonumber(b.size) or 38
  b.w = tonumber(b.w) or 260
  return b
end
local function combat() return InCombatLockdown and InCombatLockdown() end

local win, picker
local icons = {}                 -- pool key -> button
local pending = false

---------------------------------------------------------------------------
-- What can go in the box
---------------------------------------------------------------------------
local SKIP = { home = true, settings = true, ["tool:Button Box"] = true }
function S:ButtonBoxCatalog()
  local out, seen = {}, {}
  local function add(it, group)
    if not it or it.sep or not it.key or SKIP[it.key] or seen[it.key] then return end
    seen[it.key] = true
    it.group = group
    out[#out + 1] = it
  end
  local ok, cat = pcall(function() return S.QuickBarCatalog and S.QuickBarCatalog() or {} end)
  if ok then
    for _, it in ipairs(cat) do
      if not it.blizzard and not it.plugin and not it.userTool then add(it, "Hub") end
    end
  end
  for _, label in ipairs(S.ToolLabels and S:ToolLabels() or {}) do
    local t = S:ToolInfo(label)
    if t then
      add({ key = "tool:" .. label, label = t.name or label, icon = t.icon, tint = t.tint, tool = label,
        tip = t.tip and function(tt) tt:AddLine(t.name or label, 1, 0.82, 0); tt:AddLine(t.tip, 1, 1, 1, true) end or nil,
        click = function() S:ToolToggle(label) end,
        on = function() local _, _, on = S:ToolInfo(label); return on end,
        avail = function() local _, a = S:ToolInfo(label); return a end }, "Tools")
    end
  end
  local okB, blz = pcall(function() return S.BlizzardItems and S:BlizzardItems(true) or {} end)
  if okB then for _, it in ipairs(blz) do add(it, "Game") end end
  local okP, plugs = pcall(function() return S.PluginItems and S:PluginItems(true) or {} end)
  if okP then for _, it in ipairs(plugs) do add(it, "Addons") end end
  return out
end

function S:ButtonBoxKeys()
  local out = {}
  if not S.db then return out end
  for _, k in ipairs(cfg().keys) do out[k] = true end
  return out
end
function S:ButtonBoxHas(key) for _, k in ipairs(cfg().keys) do if k == key then return true end end return false end
function S:ButtonBoxLabel(key)
  for _, it in ipairs(S:ButtonBoxCatalog()) do if it.key == key then return it.label end end
end

function S:ButtonBoxAdd(key, slot)
  local keys = cfg().keys
  for i = #keys, 1, -1 do if keys[i] == key then table.remove(keys, i) end end
  table.insert(keys, math.max(1, math.min(slot or (#keys + 1), #keys + 1)), key)
  local g = G()
  g.barHidden = type(g.barHidden) == "table" and g.barHidden or {}
  g.barHidden[key] = true                       -- one icon per thing: off the bar
  if S.QuickBarLayout then S:QuickBarLayout() end
  S:RefreshButtonBox()
end
function S:ButtonBoxRemoveKey(key, quiet)
  local keys = cfg().keys
  for i = #keys, 1, -1 do if keys[i] == key then table.remove(keys, i) end end
  if not quiet and S.PluginSyncMinimap then S:PluginSyncMinimap() end
  S:RefreshButtonBox()
end

---------------------------------------------------------------------------
-- Icons
---------------------------------------------------------------------------
local function iconText(it, size)
  size = size or 18
  local tex, co, atlas = it.icon, it.coords, nil
  if it.iconFn then
    local ok, t2, c2, a2 = pcall(it.iconFn)
    if ok then if a2 then atlas = a2 elseif t2 then tex = t2; co = c2 or co end end
  end
  return tex, co, atlas
end

local function paintIcon(b, it)
  local tex, co, atlas = iconText(it)
  if atlas and b.icon.SetAtlas then b.icon:SetAtlas(atlas); b.icon:SetVertexColor(1, 1, 1) return end
  b.icon:SetTexture(tex or QMARK)
  if type(co) == "table" and #co >= 4 then b.icon:SetTexCoord(unpack(co))
  elseif tostring(tex or QMARK):find("Icons") then b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  else b.icon:SetTexCoord(0, 1, 0, 1) end
  local th = UI:Theme()
  if it.tint then b.icon:SetVertexColor(th.gold[1], th.gold[2], th.gold[3])
  elseif it.color then b.icon:SetVertexColor(it.color[1] or 1, it.color[2] or 1, it.color[3] or 1)
  else b.icon:SetVertexColor(1, 1, 1) end
end

local function menuFor(self)
  local it = self.item; if not it then return end
  local keys = cfg().keys
  local idx; for i, k in ipairs(keys) do if k == it.key then idx = i end end
  UI:Menu(self, {
    { text = it.label or it.key, title = true },
    { text = "Move left", disabled = not idx or idx == 1, func = function()
      if combat() then return end
      keys[idx], keys[idx - 1] = keys[idx - 1], keys[idx]; S:RefreshButtonBox() end },
    { text = "Move right", disabled = not idx or idx == #keys, func = function()
      if combat() then return end
      keys[idx], keys[idx + 1] = keys[idx + 1], keys[idx]; S:RefreshButtonBox() end },
    { text = "Remove from the box", func = function() S:ButtonBoxRemoveKey(it.key) end },
    { text = "Add icons...", func = function() S:ShowButtonBoxPicker() end },
  })
end

-- which slot the cursor is over (for drag to reorder)
local function slotUnderCursor()
  if not win then return end
  local x, y = GetCursorPosition()
  local s = win.grid:GetEffectiveScale() or 1
  x, y = x / s, y / s
  local l, t = win.grid:GetLeft(), win.grid:GetTop()
  if not l or not t then return end
  local size = cfg().size
  local col = math.floor((x - l) / (size + GAP))
  local row = math.floor((t - y) / (size + GAP))
  if col < 0 or row < 0 or col >= (win.cols or 1) then return end
  return row * (win.cols or 1) + col + 1
end
local function overWindow()
  if not win then return false end
  return win:IsMouseOver(8, -8, -8, 8)
end
-- for the dock / border bar: is the cursor over the open box?
function S:ButtonBoxDropTarget() return win ~= nil and win:IsShown() and overWindow() end
function S:ButtonBoxSlotUnderCursor() return slotUnderCursor() end
function S:ButtonBoxHighlight(on)
  if not win then return end
  if not win.dropGlow then
    win.dropGlow = win:CreateTexture(nil, "OVERLAY")
    win.dropGlow:SetPoint("TOPLEFT", -6, 6); win.dropGlow:SetPoint("BOTTOMRIGHT", 6, -6)
    win.dropGlow:SetTexture(UI.ART.glow); win.dropGlow:SetBlendMode("ADD")
  end
  local th = UI:Theme()
  win.dropGlow:SetVertexColor(th.live[1], th.live[2], th.live[3], 0.55)
  win.dropGlow:SetShown(on and true or false)
end

local function getIcon(it)
  local secure = it.secure ~= nil
  local key = (secure and "S:" or "") .. it.key
  local b = icons[key]
  if b then return b end
  if secure then
    b = CreateFrame("Button", nil, win.grid, "SecureActionButtonTemplate")
    b:RegisterForClicks("AnyUp", "AnyDown")
    b.isSecure = true
  else
    b = CreateFrame("Button", nil, win.grid)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  end
  b:RegisterForDrag("LeftButton")
  b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints()
  UI:Skin(b.bg, function(self, th) self:SetColorTexture(th.field[1], th.field[2], th.field[3], 0.85) end)
  b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetPoint("TOPLEFT", 3, -3); b.icon:SetPoint("BOTTOMRIGHT", -3, 3)
  b.hl = b:CreateTexture(nil, "HIGHLIGHT"); b.hl:SetAllPoints(); b.hl:SetColorTexture(1, 1, 1, 0.12)
  b.dot = b:CreateTexture(nil, "OVERLAY"); b.dot:SetTexture(UI.MEDIA .. "UI\\disc"); b.dot:SetSize(6, 6); b.dot:SetPoint("BOTTOM", 0, 1); b.dot:Hide()
  b.badge = UI:Badge(b, 14); b.badge:SetPoint("TOPRIGHT", 4, 4)
  b.count = b:CreateFontString(nil, "OVERLAY"); b.count:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE"); b.count:SetPoint("BOTTOMRIGHT", -1, 2)
  b:SetScript("OnEnter", function(self)
    local it2 = self.item; if not it2 then return end
    if it2.enter then pcall(it2.enter, self) return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if it2.tip then pcall(it2.tip, GameTooltip) else GameTooltip:AddLine(it2.label or "", 1, 0.82, 0) end
    GameTooltip:AddLine("Drag to move. Ctrl-right-click: box menu.", 0.6, 0.6, 0.6)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function(self)
    local it2 = self.item
    if it2 and it2.leave then pcall(it2.leave, self) end
    GameTooltip:Hide()
  end)
  b:SetScript("OnDragStart", function(self)
    if combat() then return end
    self.dragging = true; self:SetAlpha(0.45)
    -- show where it would land on the dock / border bar
    self:SetScript("OnUpdate", function()
      local onBar = S.QuickBarDropTarget and S:QuickBarDropTarget()
      if S.QuickBarShowDrop then S:QuickBarShowDrop(onBar and true or false) end
    end)
  end)
  b:SetScript("OnDragStop", function(self)
    if not self.dragging then return end
    self.dragging = false; self:SetAlpha(1)
    self:SetScript("OnUpdate", nil)
    if S.QuickBarShowDrop then S:QuickBarShowDrop(false) end
    self.justDragged = GetTime()
    local it2 = self.item; if not it2 or combat() then return end
    -- dropped on the dock / border bar: it moves there
    if not overWindow() and S.QuickBarDropTarget and S:QuickBarDropTarget() then
      local key = it2.key
      S:ButtonBoxRemoveKey(key, true)
      S:QuickBarDropKey(key, it2)
      return
    end
    if not overWindow() then
      UI:Confirm("Take |cffffd100" .. (it2.label or "this icon") .. "|r out of the Button Box?", function() S:ButtonBoxRemoveKey(it2.key) end, "Remove")
      return
    end
    local slot = slotUnderCursor()
    local keys = cfg().keys
    local from; for i, k in ipairs(keys) do if k == it2.key then from = i end end
    if slot and from and slot ~= from then
      table.remove(keys, from)
      table.insert(keys, math.min(slot, #keys + 1), it2.key)
      S:RefreshButtonBox()
    end
  end)
  if secure then
    -- the click itself is the game's; right-click still opens our menu
    b:HookScript("OnClick", function(self, btn, down)
      if btn == "RightButton" and not down then menuFor(self) end
    end)
  else
    b:SetScript("OnClick", function(self, btn)
      local it2 = self.item; if not it2 then return end
      if self.justDragged and GetTime() - self.justDragged < 0.3 then return end
      local ctrlRight = btn == "RightButton" and IsControlKeyDown and IsControlKeyDown()
      if it2.plugin and not ctrlRight then pcall(it2.click, self, btn) return end    -- addons use right-click themselves
      if btn == "RightButton" then menuFor(self) return end
      if it2.click then it2.click(self, btn) elseif it2.fallbackClick then it2.fallbackClick() end
    end)
  end
  icons[key] = b
  return b
end

local function states()
  if not win or not win:IsShown() then return end
  local th = UI:Theme()
  for _, b in pairs(icons) do
    local it = b.item
    if it and b:IsShown() then
      local on = false
      if it.on then local ok, v = pcall(it.on); on = ok and v end
      if not on and it.active then local ok, v = pcall(it.active); on = ok and v end
      b.dot:SetShown(on and true or false); b.dot:SetVertexColor(th.live[1], th.live[2], th.live[3])
      local n = 0
      if it.badge then local ok, v = pcall(it.badge); n = ok and tonumber(v) or 0 end
      b.badge:SetCount(n)
      if it.count then local ok, v = pcall(it.count); b.count:SetText(ok and v and tostring(v) or "") else b.count:SetText("") end
      local avail = true
      if it.avail then local ok, v = pcall(it.avail); avail = not ok or v and true or false end
      b.icon:SetDesaturated(not avail)
    end
  end
end

function S:RefreshButtonBox()
  if not win then return end
  if combat() then pending = true return end
  pending = false
  local c = cfg()
  local byKey = {}
  for _, it in ipairs(S:ButtonBoxCatalog()) do byKey[it.key] = it end
  for _, b in pairs(icons) do b:Hide(); b.item = nil end
  local size = c.size
  local width = math.max(size + PAD * 2, c.w)
  local cols = math.max(1, math.floor((width - PAD * 2 + GAP) / (size + GAP)))
  win.cols = cols
  local n = 0
  for _, key in ipairs(c.keys) do
    local it = byKey[key]
    if it then
      local b = getIcon(it)
      b.item = it
      if it.secure then b:SetAttribute("type1", "click"); b:SetAttribute("clickbutton1", it.secure) end
      local i = n; n = n + 1
      b:SetSize(size, size)
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", win.grid, "TOPLEFT", (i % cols) * (size + GAP), -math.floor(i / cols) * (size + GAP))
      paintIcon(b, it)
      b:Show()
    end
  end
  local rows = math.max(1, math.ceil(n / cols))
  win.empty:SetShown(n == 0)
  win:SetSize(width, HEAD + rows * (size + GAP) - GAP + PAD + (n == 0 and 30 or 0))
  states()
  if S.PluginSyncMinimap then S:PluginSyncMinimap() end
end
S:On("PLAYER_REGEN_ENABLED", function() if pending then S:RefreshButtonBox() end end)
S:Listen("GUILD_READY", function() if win then S:RefreshButtonBox() end end)

---------------------------------------------------------------------------
-- The box window
---------------------------------------------------------------------------
local function build()
  local c = cfg()
  win = UI:Window("CC_ButtonBox", "Button Box", c.w, 120, { header = 26 })
  win:SetFrameStrata("MEDIUM")
  -- it may hold the game's secure buttons: Escape mustn't try to close it in combat
  if UISpecialFrames then
    for i = #UISpecialFrames, 1, -1 do if UISpecialFrames[i] == "CC_ButtonBox" then table.remove(UISpecialFrames, i) end end
  end
  if c.pos then win:ClearAllPoints(); win:SetPoint(c.pos[1], UIParent, c.pos[2], c.pos[3], c.pos[4]) end
  win:HookScript("OnDragStop", function(self)
    local p, _, rp, x, y = self:GetPoint()
    if p then cfg().pos = { p, rp, x, y } end
  end)
  win:HeaderButton("plus", "Add icons", "Pick icons for the box: Command Center, the game's menu, other addons.", function() S:ShowButtonBoxPicker() end)
  win:HeaderButton("settings", "Box options", "Icon size.", function(self)
    local items = { { text = "Icon size", title = true } }
    for _, sz in ipairs(SIZES) do
      items[#items + 1] = { text = sz[1], checked = cfg().size == sz[2], func = function() cfg().size = sz[2]; S:RefreshButtonBox() end }
    end
    UI:Menu(self, items)
  end)
  win.grid = CreateFrame("Frame", nil, win)
  win.grid:SetPoint("TOPLEFT", PAD, -HEAD); win.grid:SetPoint("BOTTOMRIGHT", -PAD, PAD)
  win.empty = UI:Text(win, "|cffaaaaaaEmpty - press the|r |cffffd100+|r |cffaaaaaaat the top to add icons.|r", "small", "CENTER")
  win.empty:SetPoint("TOPLEFT", PAD, -HEAD - 4); win.empty:SetPoint("RIGHT", -PAD, 0)
  -- width grip: the icons wrap to fit
  win:SetResizable(true)
  if win.SetResizeBounds then win:SetResizeBounds(80, 60, 1200, 900) elseif win.SetMinResize then win:SetMinResize(80, 60) end
  local grip = CreateFrame("Button", nil, win)
  grip:SetSize(14, 14); grip:SetPoint("BOTTOMRIGHT", -2, 2)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetScript("OnMouseDown", function() if not combat() then win:StartSizing("RIGHT") end end)
  grip:SetScript("OnMouseUp", function()
    win:StopMovingOrSizing()
    cfg().w = math.floor(win:GetWidth() + 0.5)
    S:RefreshButtonBox()
  end)
  win:HookScript("OnShow", function() cfg().open = true; S:RefreshButtonBox() end)
  win:HookScript("OnHide", function() if not (S.SnapBusy and S.SnapBusy()) then cfg().open = false end end)
  local acc = 0
  win:HookScript("OnUpdate", function(_, el) acc = acc + el; if acc > 0.5 then acc = 0; states() end end)
end

function S:ShowButtonBox()
  if not win then build() end
  if combat() and win:IsProtected() then S:Print("The Button Box can't be opened or closed in combat.") return end
  win:Show(); win:Raise()
  S:RefreshButtonBox()
end
function S:HideButtonBox()
  if not win then return end
  if combat() and win:IsProtected() then S:Print("The Button Box can't be opened or closed in combat.") return end
  win:Hide()
end

---------------------------------------------------------------------------
-- Picker: everything that can go in the box
---------------------------------------------------------------------------
local GROUP_ORDER = { Hub = 1, Tools = 2, Game = 3, Addons = 4 }
local GROUP_NAME = { Hub = "Command Center", Tools = "Tool", Game = "Game menu", Addons = "Addon" }
local function pickRows()
  local q = picker and (picker.search:GetText() or ""):lower() or ""
  local out = {}
  local onBar = S.QuickBarKeysInUse and S:QuickBarKeysInUse() or {}
  for _, it in ipairs(S:ButtonBoxCatalog()) do
    local label = tostring(it.label or it.key)
    if q == "" or label:lower():find(q, 1, true) or (it.owner and it.owner:lower():find(q, 1, true)) then
      out[#out + 1] = { it = it, label = label, inBox = S:ButtonBoxHas(it.key), onBar = onBar[it.key] }
    end
  end
  table.sort(out, function(a, b)
    local ga, gb = GROUP_ORDER[a.it.group] or 9, GROUP_ORDER[b.it.group] or 9
    if ga ~= gb then return ga < gb end
    return a.label:lower() < b.label:lower()
  end)
  return out
end
function S:RefreshButtonBoxPicker()
  if picker and picker:IsShown() then picker.tbl:SetData(pickRows()) end
end
function S:ShowButtonBoxPicker()
  if not picker then
    picker = UI:Window("CC_ButtonBoxPick", "Add icons to the Button Box", 460, 500)
    picker:SetFrameStrata("HIGH")
    picker.search = UI:Edit(picker, 300, 22, "Search...")
    picker.search:SetPoint("TOPLEFT", 14, -38)
    picker.search:HookScript("OnTextChanged", function() S:RefreshButtonBoxPicker() end)
    picker.tbl = UI:Table(picker, 432, 500 - 70 - 40, {
      { title = "", w = 28, get = function(r)
          local tex, co, atlas = iconText(r.it)
          if atlas then return "|A:" .. atlas .. ":18:18|a" end
          return "|T" .. tostring(tex or QMARK) .. ":18:18|t"
        end },
      { title = "Icon", w = 210, get = function(r) return r.label end },
      { title = "From", w = 90, get = function(r) return "|cff888888" .. (GROUP_NAME[r.it.group] or "") .. "|r" end },
      { title = "Where", w = 100, get = function(r)
          if r.inBox then return "|cff55ff55In the box|r" end
          if r.onBar then return "|cffaaaaaaon your bar|r" end
          return ""
        end },
    }, { emptyText = "Nothing found.",
         rowColor = function(r) if r.inBox then return 0.2, 0.8, 0.2, 0.12 end end,
         onClick = function(r)
           if combat() then S:Print("Change the Button Box after combat.") return end
           if r.inBox then S:ButtonBoxRemoveKey(r.it.key) else S:ButtonBoxAdd(r.it.key) end
           if not (win and win:IsShown()) then S:ShowButtonBox() end
           S:RefreshButtonBoxPicker()
         end })
    picker.tbl:SetPoint("TOPLEFT", 14, -68)
    local foot = UI:Text(picker, "|cff888888Click to put an icon in the box or take it out. Icons in the box leave your dock / border bar.|r", "small")
    foot:SetPoint("BOTTOMLEFT", 16, 12); foot:SetWidth(430); foot:SetJustifyH("LEFT")
    picker:HookScript("OnShow", function() S:RefreshButtonBoxPicker() end)
  end
  picker:Show(); picker:Raise()
  S:RefreshButtonBoxPicker()
end

-- open again after login if it was open
S:Listen("LOGIN", function()
  C_Timer.After(3, function()
    if cfg().open and not combat() then S:ShowButtonBox() end
  end)
end)

S:AddCommand("box", "", "Button Box: a box of any icons you like", function() S:ShowButtonBox() end)
