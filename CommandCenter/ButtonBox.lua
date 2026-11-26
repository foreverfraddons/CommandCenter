-- Button Box: a movable, resizable box you fill with any icons you like - Command Center's own
-- pages and tools, the game's menu buttons and bags, and other addons' minimap icons.
-- One icon per thing: putting something in the box takes it off the dock / border bar
-- (bring it back to the bar and it leaves the box). Addon icons in the box hide their
-- minimap button (see Plugins.lua).
-- Groups: drag an icon onto the middle of another to put them in a group (like apps on a
-- phone); click a group to open it, click its name to rename it.
local _, S = ...
if S.ModuleRev then S:ModuleRev("ButtonBox", 2) end
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
local dock                       -- set by Minimap.lua: the box hangs under the minimap (S:ButtonBoxDock)

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

---------------------------------------------------------------------------
-- Groups ("folders", like apps on a phone): drag one icon onto the middle of
-- another and both go into a group. cfg().keys holds "group:<id>" for a group;
-- cfg().groups[id] = { name = "...", keys = { ... } }. A group always lives in
-- the box; when only one icon is left in it, that icon takes the group's place.
---------------------------------------------------------------------------
local function groups()
  local c = cfg()
  c.groups = type(c.groups) == "table" and c.groups or {}
  return c.groups
end
local function groupId(key) return type(key) == "string" and key:match("^group:(.+)$") end
local function listFor(where)
  if where == "box" or where == nil then return cfg().keys end
  local g = groups()[where]
  return g and g.keys
end
-- every key in the box, groups opened up (one place per icon)
local function allKeys()
  local out = {}
  for _, k in ipairs(cfg().keys) do
    local id = groupId(k)
    if id then
      local g = groups()[id]
      for _, k2 in ipairs(g and g.keys or {}) do out[#out + 1] = k2 end
    else
      out[#out + 1] = k
    end
  end
  return out
end
-- where a key lives: "box" or a group id (and its index there)
local function whereIs(key)
  for i, k in ipairs(cfg().keys) do if k == key then return "box", i end end
  for id, g in pairs(groups()) do
    for i, k in ipairs(g.keys or {}) do if k == key then return id, i end end
  end
end
local function takeOut(key)
  local where, i = whereIs(key)
  if where then table.remove(listFor(where), i) end
  return where, i
end

local folderWin                  -- the open group (built further down)
local function closeFolderIf(id) if folderWin and folderWin:IsShown() and (id == nil or folderWin.groupId == id) then folderWin:Hide() end end

-- a group with one icon left turns back into that icon; an empty one goes away
local function tidyGroup(id)
  local g = groups()[id]
  local keys = cfg().keys
  local pos
  for i, k in ipairs(keys) do if k == "group:" .. id then pos = i end end
  if not g then if pos then table.remove(keys, pos) end return end
  local n = #(g.keys or {})
  if n >= 2 then return end
  groups()[id] = nil
  if pos then
    if n == 1 then keys[pos] = g.keys[1] else table.remove(keys, pos) end
  elseif n == 1 then
    keys[#keys + 1] = g.keys[1]
  end
  closeFolderIf(id)
end
local function tidyAllGroups()
  for id in pairs(groups()) do tidyGroup(id) end
  -- a group key whose group is gone (old saved data): drop it
  local keys = cfg().keys
  for i = #keys, 1, -1 do
    local id = groupId(keys[i])
    if id and not groups()[id] then table.remove(keys, i) end
  end
end

-- a starting name from what's in it (you can change it straight away)
local GROUP_NAME_FOR = { Hub = "Command Center", Tools = "Tools", Game = "Game", Addons = "Addons" }
local function guessName(keys)
  local cat = {}
  for _, it in ipairs(S:ButtonBoxCatalog()) do cat[it.key] = it.group end
  local first
  for _, k in ipairs(keys) do
    local gname = cat[k] or "Addons"
    if first == nil then first = gname elseif first ~= gname then return "Group" end
  end
  return GROUP_NAME_FOR[first] or "Group"
end
local function newGroupId()
  local n = 1
  while groups()["g" .. n] do n = n + 1 end
  return "g" .. n
end

function S:ButtonBoxKeys()
  local out = {}
  if not S.db then return out end
  for _, k in ipairs(allKeys()) do out[k] = true end
  return out
end
function S:ButtonBoxHas(key) return whereIs(key) ~= nil end
function S:ButtonBoxLabel(key)
  for _, it in ipairs(S:ButtonBoxCatalog()) do if it.key == key then return it.label end end
end
function S:ButtonBoxGroups() return groups() end

-- put two icons together: target's spot becomes a group (or the dragged icon joins target's group)
local function merge(dragKey, targetKey)
  if dragKey == targetKey or groupId(dragKey) then return end
  local tid = groupId(targetKey)
  if tid then
    local g = groups()[tid]
    if not g then return end
    takeOut(dragKey)
    g.keys[#g.keys + 1] = dragKey
    return tid
  end
  local tWhere = whereIs(targetKey)
  if tWhere ~= "box" then return end
  local fromWhere = takeOut(dragKey)
  local keys = cfg().keys
  local pos
  for i, k in ipairs(keys) do if k == targetKey then pos = i end end
  if not pos then return end
  local id = newGroupId()
  groups()[id] = { name = guessName({ targetKey, dragKey }), keys = { targetKey, dragKey }, new = true }
  keys[pos] = "group:" .. id
  if fromWhere and fromWhere ~= "box" then tidyGroup(fromWhere) end
  return id, true
end

function S:ButtonBoxAdd(key, slot, inner)
  local keys = cfg().keys
  takeOut(key)
  local target = slot and keys[slot]
  if inner and target and groupId(target) then
    merge(key, target)                          -- dropped on a group: it goes in
  elseif inner and target and target ~= key then
    keys[#keys + 1] = key; merge(key, target)   -- dropped on an icon: a new group
  else
    table.insert(keys, math.max(1, math.min(slot or (#keys + 1), #keys + 1)), key)
  end
  local g = G()
  g.barHidden = type(g.barHidden) == "table" and g.barHidden or {}
  g.barHidden[key] = true                       -- one icon per thing: off the bar
  tidyAllGroups()
  if S.QuickBarLayout then S:QuickBarLayout() end
  S:RefreshButtonBox()
end
-- several at once (the minimap drawer fills the box with every addon icon): one refresh
function S:ButtonBoxAddMany(list)
  local keys = cfg().keys
  local g = G()
  g.barHidden = type(g.barHidden) == "table" and g.barHidden or {}
  for _, key in ipairs(list or {}) do
    if not whereIs(key) then keys[#keys + 1] = key end
    g.barHidden[key] = true
  end
  if S.QuickBarLayout then pcall(S.QuickBarLayout, S) end
  S:RefreshButtonBox()
  if S.PluginSyncMinimap then S:PluginSyncMinimap() end
end
function S:ButtonBoxRemoveKey(key, quiet)
  local id = groupId(key)
  if id then
    -- a whole group out of the box: its icons go too
    local g = groups()[id]
    groups()[id] = nil
    local keys = cfg().keys
    for i = #keys, 1, -1 do if keys[i] == key then table.remove(keys, i) end end
    closeFolderIf(id)
  else
    local where = takeOut(key)
    if where and where ~= "box" then tidyGroup(where) end
  end
  if not quiet and S.PluginSyncMinimap then S:PluginSyncMinimap() end
  S:RefreshButtonBox()
end
-- a group's icons back into the box, where the group was
function S:ButtonBoxUngroup(id)
  local g = groups()[id]
  if not g then return end
  local keys = cfg().keys
  local pos
  for i, k in ipairs(keys) do if k == "group:" .. id then pos = i end end
  groups()[id] = nil
  if pos then table.remove(keys, pos) else pos = #keys + 1 end
  for i, k in ipairs(g.keys or {}) do table.insert(keys, math.min(pos + i - 1, #keys + 1), k) end
  closeFolderIf(id)
  S:RefreshButtonBox()
end
function S:ButtonBoxRenameGroup(id, name)
  local g = groups()[id]
  if not g then return end
  name = S.Trim(name or "")
  g.name = name ~= "" and name or guessName(g.keys)
  g.new = nil
  S:RefreshButtonBox()
end
function S:ButtonBoxAskRename(id)
  local g = groups()[id]
  if not g then return end
  UI:Prompt("Name this group:", g.name or "", function(v) S:ButtonBoxRenameGroup(id, v) end)
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

local function paintTex(tex, it)
  local t, co, atlas = iconText(it)
  if atlas and tex.SetAtlas then tex:SetAtlas(atlas); tex:SetVertexColor(1, 1, 1) return end
  tex:SetTexture(t or QMARK)
  if type(co) == "table" and #co >= 4 then tex:SetTexCoord(unpack(co))
  elseif tostring(t or QMARK):find("Icons") then tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  else tex:SetTexCoord(0, 1, 0, 1) end
  local th = UI:Theme()
  if it.tint then tex:SetVertexColor(th.gold[1], th.gold[2], th.gold[3])
  elseif it.color then tex:SetVertexColor(it.color[1] or 1, it.color[2] or 1, it.color[3] or 1)
  else tex:SetVertexColor(1, 1, 1) end
end

-- a group's face: up to four of its icons in a 2 x 2 grid on a raised tile
local function paintGroup(b, it)
  if not b.minis then
    b.minis = {}
    for i = 1, 4 do b.minis[i] = b:CreateTexture(nil, "ARTWORK") end
    b.groupEdge = CreateFrame("Frame", nil, b)
    b.groupEdge:SetAllPoints()
    b.groupEdge:EnableMouse(false)
  end
  local size = b:GetWidth() or 38
  local inner = size - 8
  local m = math.floor((inner - 2) / 2)
  for i = 1, 4 do
    local t = b.minis[i]
    t:ClearAllPoints()
    t:SetSize(m, m)
    t:SetPoint("TOPLEFT", b, "TOPLEFT", 4 + ((i - 1) % 2) * (m + 2), -4 - math.floor((i - 1) / 2) * (m + 2))
    local sub = it.children and it.children[i]
    if sub then paintTex(t, sub); t:Show() else t:Hide() end
  end
  local th = UI:Theme()
  UI.Flat(b.groupEdge, th.panel2, 0, th.gold, 0.7)
  b.bg:SetColorTexture(th.panel2[1], th.panel2[2], th.panel2[3], 0.95)
  b.icon:Hide()
end

local function paintIcon(b, it)
  if it.groupId then paintGroup(b, it) return end
  if b.minis then for _, t in ipairs(b.minis) do t:Hide() end end
  if b.groupEdge then b.groupEdge:Hide() end
  local th = UI:Theme()
  b.bg:SetColorTexture(th.field[1], th.field[2], th.field[3], 0.85)
  b.icon:Show()
  paintTex(b.icon, it)
end

local function menuFor(self)
  local it = self.item; if not it then return end
  local where = self.where or "box"
  local keys = listFor(where) or {}
  local idx; for i, k in ipairs(keys) do if k == it.key then idx = i end end
  local items = { { text = it.label or it.key, title = true } }
  if it.groupId then
    items[#items + 1] = { text = "Open", func = function() S:ButtonBoxOpenGroup(it.groupId, self) end }
    items[#items + 1] = { text = "Rename...", func = function() S:ButtonBoxAskRename(it.groupId) end }
    items[#items + 1] = { text = "Ungroup (icons back into the box)", func = function() if not combat() then S:ButtonBoxUngroup(it.groupId) end end }
  end
  items[#items + 1] = { text = "Move left", disabled = not idx or idx == 1, func = function()
    if combat() then return end
    keys[idx], keys[idx - 1] = keys[idx - 1], keys[idx]; S:RefreshButtonBox() end }
  items[#items + 1] = { text = "Move right", disabled = not idx or idx == #keys, func = function()
    if combat() then return end
    keys[idx], keys[idx + 1] = keys[idx + 1], keys[idx]; S:RefreshButtonBox() end }
  if where ~= "box" then
    items[#items + 1] = { text = "Take out of the group", func = function()
      if combat() then return end
      takeOut(it.key); table.insert(cfg().keys, it.key); tidyGroup(where); S:RefreshButtonBox() end }
  end
  items[#items + 1] = { text = it.groupId and "Remove the group from the box" or "Remove from the box", func = function()
    if it.groupId then
      UI:Confirm("Take the group |cffffd100" .. (it.label or "") .. "|r and every icon in it out of the Button Box?", function() S:ButtonBoxRemoveKey(it.key) end, "Remove")
    else S:ButtonBoxRemoveKey(it.key) end
  end }
  items[#items + 1] = { text = "Add icons...", func = function() S:ShowButtonBoxPicker() end }
  UI:Menu(self, items)
end

-- which slot of a grid the cursor is over, and whether it is over the middle of that slot
-- (the middle = "put them together", the edges = "move it here")
local function gridHit(frame, grid, cols)
  if not frame or not grid then return end
  local x, y = GetCursorPosition()
  local s = grid:GetEffectiveScale() or 1
  x, y = x / s, y / s
  local l, t = grid:GetLeft(), grid:GetTop()
  if not l or not t then return end
  local size = cfg().size
  local cw = size + GAP
  local col = math.floor((x - l) / cw)
  local row = math.floor((t - y) / cw)
  if col < 0 or row < 0 or col >= (cols or 1) then return end
  local fx, fy = ((x - l) - col * cw) / size, ((t - y) - row * cw) / size
  local inner = fx > 0.2 and fx < 0.8 and fy > 0.2 and fy < 0.8
  return row * (cols or 1) + col + 1, inner
end
local function slotUnderCursor() if win then return gridHit(win, win.grid, win.cols) end end
local function overWindow()
  if not win then return false end
  return win:IsShown() and win:IsMouseOver(8, -8, -8, 8)
end
local function overFolder()
  return folderWin ~= nil and folderWin:IsShown() and folderWin:IsMouseOver(6, -6, -6, 6)
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

-- the icon shown at a grid slot (for the "put together" highlight while dragging)
local shownAt = { box = {}, folder = {} }
local mergeTarget
local function setMergeTarget(b)
  if mergeTarget == b then return end
  if mergeTarget and mergeTarget.mergeGlow then mergeTarget.mergeGlow:Hide(); mergeTarget:SetScale(1) end
  mergeTarget = b
  if b then b:SetScale(1.18) end   -- the icon it would group with steps forward
  if b then
    if not b.mergeGlow then
      b.mergeGlow = b:CreateTexture(nil, "OVERLAY", nil, 7)
      b.mergeGlow:SetPoint("TOPLEFT", -7, 7); b.mergeGlow:SetPoint("BOTTOMRIGHT", 7, -7)
      b.mergeGlow:SetTexture(UI.ART.glow); b.mergeGlow:SetBlendMode("ADD")
    end
    local th = UI:Theme()
    b.mergeGlow:SetVertexColor(th.gold[1], th.gold[2], th.gold[3], 0.9)
    b.mergeGlow:Show()
  end
end

-- what you're carrying: a copy of the icon under the cursor, with a line saying what letting go does
local ghost
local function ghostFrame()
  if ghost then return ghost end
  ghost = CreateFrame("Frame", "CC_ButtonBoxGhost", UIParent)
  ghost:SetFrameStrata("TOOLTIP"); ghost:EnableMouse(false)
  ghost.bg = ghost:CreateTexture(nil, "BACKGROUND"); ghost.bg:SetAllPoints()
  ghost.icon = ghost:CreateTexture(nil, "ARTWORK"); ghost.icon:SetPoint("TOPLEFT", 3, -3); ghost.icon:SetPoint("BOTTOMRIGHT", -3, 3)
  ghost.edge = CreateFrame("Frame", nil, ghost); ghost.edge:SetAllPoints(); ghost.edge:EnableMouse(false)
  ghost.label = CreateFrame("Frame", nil, ghost); ghost.label:SetHeight(18); ghost.label:EnableMouse(false)
  ghost.label:SetPoint("TOP", ghost, "BOTTOM", 0, -4)
  ghost.label.text = UI:Text(ghost.label, "", "small", "CENTER"); ghost.label.text:SetPoint("CENTER")
  -- gold bar between two icons = "it goes here"
  ghost.line = CreateFrame("Frame", "CC_ButtonBoxInsert", UIParent)
  ghost.line:SetFrameStrata("TOOLTIP"); ghost.line:EnableMouse(false)
  ghost.line.tex = ghost.line:CreateTexture(nil, "OVERLAY"); ghost.line.tex:SetAllPoints()
  ghost.line:Hide()
  return ghost
end
local function showGhost(b)
  local g = ghostFrame()
  local size = cfg().size
  g:SetSize(size, size)
  local th = UI:Theme()
  g.bg:SetColorTexture(th.field[1], th.field[2], th.field[3], 0.9)
  local it = b.item
  if it and it.groupId then
    g.icon:SetTexture(UI.MEDIA .. "UI\\i_box"); g.icon:SetTexCoord(0, 1, 0, 1); g.icon:SetVertexColor(th.gold[1], th.gold[2], th.gold[3])
  elseif it then paintTex(g.icon, it) end
  UI.Flat(g.edge, th.panel, 0, th.gold, 1)
  UI.Flat(g.label, th.panel, 0.95, th.gold, 0.8)
  g.label.text:SetTextColor(th.text[1], th.text[2], th.text[3])
  g.line.tex:SetColorTexture(th.gold[1], th.gold[2], th.gold[3], 1)
  g:SetAlpha(0.9)
  g:Show()
end
local function hideGhost()
  if not ghost then return end
  ghost:Hide(); ghost.line:Hide()
end
local function ghostLabel(text)
  if not ghost then return end
  ghost.label.text:SetText(text or "")
  ghost.label:SetWidth(math.max(60, ghost.label.text:GetStringWidth() + 16))
  ghost.label:SetShown(text ~= nil and text ~= "")
end
-- the insertion bar at a slot of a grid (before that slot)
local function showInsert(gridFrame, cols, slot, count)
  if not ghost then return end
  if not gridFrame or not slot then ghost.line:Hide() return end
  local size = cfg().size
  local i = math.max(0, math.min(slot - 1, count or (slot - 1)))
  local col, row = i % cols, math.floor(i / cols)
  ghost.line:ClearAllPoints()
  ghost.line:SetSize(3, size + 4)
  ghost.line:SetScale(gridFrame:GetEffectiveScale() / UIParent:GetEffectiveScale())
  ghost.line:SetPoint("TOPLEFT", gridFrame, "TOPLEFT", col * (size + GAP) - math.floor(GAP / 2) - 1, -row * (size + GAP) + 2)
  ghost.line:Show()
end

-- where a drag would land right now: kind ("merge" / "move" / "bar" / "out"), the target container, slot
local function dropSpot(self)
  if not overWindow() and not overFolder() and S.QuickBarDropTarget and S:QuickBarDropTarget() then return "bar" end
  if overFolder() then
    local slot = gridHit(folderWin, folderWin.grid, folderWin.cols)
    return "move", folderWin.groupId, slot
  end
  if overWindow() then
    local slot, inner = slotUnderCursor()
    local target = slot and shownAt.box[slot]
    if inner and target and target ~= self and not (self.item and self.item.groupId) then return "merge", "box", slot, target end
    return "move", "box", slot
  end
  return "out"
end

local refreshFolder
local function onDragStop(self)
  if not self.dragging then return end
  self.dragging = false; self:SetAlpha(1)
  self:SetScript("OnUpdate", nil)
  setMergeTarget(nil)
  hideGhost()
  if S.QuickBarShowDrop then S:QuickBarShowDrop(false) end
  self.justDragged = GetTime()
  local it2 = self.item; if not it2 or combat() then return end
  local key, from = it2.key, self.where or "box"
  local kind, to, slot, target = dropSpot(self)
  if kind == "bar" then
    -- dropped on the dock / border bar: it moves there (a group stays in the box)
    if it2.groupId then S:Print("Groups stay in the Button Box - drag the icons inside it to your bar.") return end
    takeOut(key)
    if from ~= "box" then tidyGroup(from) end
    S:RefreshButtonBox()
    S:QuickBarDropKey(key, it2)
    return
  end
  if kind == "merge" then
    local id, fresh = merge(key, target.item.key)
    if from ~= "box" then tidyGroup(from) end
    S:RefreshButtonBox()
    if fresh then S:ButtonBoxOpenGroup(id, nil, true) end    -- name it right away, like a phone does
    return
  end
  if kind == "move" then
    if to ~= "box" and it2.groupId then return end          -- no groups inside groups
    local list = listFor(to)
    if not list then return end
    local fromWhere, fromIdx = whereIs(key)
    if fromWhere == to and slot and fromIdx == slot then return end
    takeOut(key)
    list = listFor(to)
    table.insert(list, math.max(1, math.min(slot or (#list + 1), #list + 1)), key)
    if fromWhere and fromWhere ~= "box" and fromWhere ~= to then tidyGroup(fromWhere) end
    S:RefreshButtonBox()
    return
  end
  -- dropped outside: out of a group = back into the box; out of the box = remove it (asks first)
  if from ~= "box" then
    takeOut(key); table.insert(cfg().keys, key); tidyGroup(from)
    S:RefreshButtonBox()
    return
  end
  if it2.groupId then
    UI:Confirm("Take the group |cffffd100" .. (it2.label or "") .. "|r and every icon in it out of the Button Box?", function() S:ButtonBoxRemoveKey(key) end, "Remove")
  else
    UI:Confirm("Take |cffffd100" .. (it2.label or "this icon") .. "|r out of the Button Box?", function() S:ButtonBoxRemoveKey(key) end, "Remove")
  end
end

local function getIcon(it, pool, parent)
  local secure = it.secure ~= nil
  local key = (secure and "S:" or "") .. it.key
  local b = pool[key]
  if b then return b end
  if secure then
    b = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate")
    b:RegisterForClicks("AnyUp")       -- on release, so a press that becomes a drag can be stopped
    b.isSecure = true
  else
    b = CreateFrame("Button", nil, parent)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  end
  b:RegisterForDrag("LeftButton")
  b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints()
  UI:Skin(b.bg, function(self, th)
    if b.item and b.item.groupId then self:SetColorTexture(th.panel2[1], th.panel2[2], th.panel2[3], 0.95)
    else self:SetColorTexture(th.field[1], th.field[2], th.field[3], 0.85) end
  end)
  b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetPoint("TOPLEFT", 3, -3); b.icon:SetPoint("BOTTOMRIGHT", -3, 3)
  b.hl = b:CreateTexture(nil, "HIGHLIGHT"); b.hl:SetAllPoints(); b.hl:SetColorTexture(1, 1, 1, 0.12)
  b.dot = b:CreateTexture(nil, "OVERLAY"); b.dot:SetTexture(UI.MEDIA .. "UI\\disc"); b.dot:SetSize(6, 6); b.dot:SetPoint("BOTTOM", 0, 1); b.dot:Hide()
  b.badge = UI:Badge(b, 14); b.badge:SetPoint("TOPRIGHT", 4, 4)
  b.count = b:CreateFontString(nil, "OVERLAY"); b.count:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE"); b.count:SetPoint("BOTTOMRIGHT", -1, 2)
  b:SetScript("OnEnter", function(self)
    local it2 = self.item; if not it2 then return end
    if it2.enter then pcall(it2.enter, self) return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if it2.groupId then
      GameTooltip:AddLine(it2.label or "Group", 1, 0.82, 0)
      for i, sub in ipairs(it2.children or {}) do
        if i > 12 then GameTooltip:AddLine("...", 0.7, 0.7, 0.7) break end
        GameTooltip:AddLine("  " .. (sub.label or sub.key), 1, 1, 1)
      end
      GameTooltip:AddLine("Click: open   Right-click: rename, ungroup", 0.6, 0.6, 0.6)
    elseif it2.tip then pcall(it2.tip, GameTooltip) else GameTooltip:AddLine(it2.label or "", 1, 0.82, 0) end
    GameTooltip:AddLine("Drag to move - onto another icon to group them. Ctrl-right-click: box menu.", 0.6, 0.6, 0.6, true)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function(self)
    local it2 = self.item
    if it2 and it2.leave then pcall(it2.leave, self) end
    GameTooltip:Hide()
  end)
  b:SetScript("OnDragStart", function(self)
    if combat() then return end
    self.dragging = true; self:SetAlpha(0.3)
    GameTooltip:Hide()
    showGhost(self)
    -- show where it would land: on the dock / border bar, onto an icon (a group), or between icons
    self:SetScript("OnUpdate", function()
      local x, y = GetCursorPosition()
      local sc = UIParent:GetEffectiveScale()
      ghost:ClearAllPoints()
      ghost:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / sc - (UIParent:GetLeft() or 0) + 6, y / sc - (UIParent:GetBottom() or 0) - 6)
      local kind, to, slot, target = dropSpot(self)
      if S.QuickBarShowDrop then S:QuickBarShowDrop(kind == "bar") end
      setMergeTarget(kind == "merge" and target or nil)
      local it2 = self.item
      if kind == "merge" then
        local tit = target.item
        ghostLabel(tit and tit.groupId and ("Add to " .. (tit.label or "group")) or "Make a group")
        ghost.line:Hide()
      elseif kind == "move" then
        if to ~= "box" and it2 and it2.groupId then ghostLabel("Groups can't go in groups"); ghost.line:Hide()
        else
          local gw = (to == "box") and win or folderWin
          local list = listFor(to) or {}
          ghostLabel(to == "box" and (self.where ~= "box" and "Out of the group" or "Move here") or "Into this group")
          showInsert(gw and gw.grid, gw and gw.cols or 1, slot or (#list + 1), #list)
        end
      elseif kind == "bar" then ghostLabel(it2 and it2.groupId and "Groups stay in the box" or "Put on the bar"); ghost.line:Hide()
      else
        ghostLabel(self.where ~= "box" and "Out of the group" or "Take out of the box"); ghost.line:Hide()
      end
    end)
  end)
  b:SetScript("OnDragStop", onDragStop)
  -- a press held longer than a click (or a drag) must never open the thing
  b:SetScript("OnMouseDown", function(self, btn)
    self.downAt = GetTime()
    if self.isSecure and btn == "LeftButton" and not combat() then self:SetAttribute("type1", nil) end
  end)
  b:SetScript("OnMouseUp", function(self, btn)
    if self.isSecure and btn == "LeftButton" and not combat() then
      local quick = self.downAt and (GetTime() - self.downAt) < 0.35 and not self.dragging
      local justDragged = self.justDragged and GetTime() - self.justDragged < 0.3
      if quick and not justDragged and self.item and self.item.secure then self:SetAttribute("type1", "click") end
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
      if self.downAt and GetTime() - self.downAt > 0.35 then return end   -- held, not clicked
      if it2.groupId then
        if btn == "RightButton" then menuFor(self) else S:ButtonBoxOpenGroup(it2.groupId, self) end
        return
      end
      local ctrlRight = btn == "RightButton" and IsControlKeyDown and IsControlKeyDown()
      if it2.plugin and not ctrlRight then pcall(it2.click, self, btn) return end    -- addons use right-click themselves
      if btn == "RightButton" then menuFor(self) return end
      if it2.click then it2.click(self, btn) elseif it2.fallbackClick then it2.fallbackClick() end
    end)
  end
  pool[key] = b
  return b
end

local folderIcons = {}
local function itemState(it, th, b)
  local on = false
  if it.on then local ok, v = pcall(it.on); on = ok and v end
  if not on and it.active then local ok, v = pcall(it.active); on = ok and v end
  local n = 0
  if it.badge then local ok, v = pcall(it.badge); n = ok and tonumber(v) or 0 end
  return on and true or false, n
end
local function paintState(b, th)
  local it = b.item
  if not it or not b:IsShown() then return end
  local on, n = false, 0
  if it.groupId then
    -- a group lights up / counts for what's inside it
    for _, sub in ipairs(it.children or {}) do
      local o2, n2 = itemState(sub, th)
      on = on or o2; n = n + (n2 or 0)
    end
    b.count:SetText("")
    b.icon:SetDesaturated(false)
  else
    on, n = itemState(it, th)
    if it.count then local ok, v = pcall(it.count); b.count:SetText(ok and v and tostring(v) or "") else b.count:SetText("") end
    local avail = true
    if it.avail then local ok, v = pcall(it.avail); avail = not ok or v and true or false end
    b.icon:SetDesaturated(not avail)
  end
  b.dot:SetShown(on); b.dot:SetVertexColor(th.live[1], th.live[2], th.live[3])
  b.badge:SetCount(n)
end
local function states()
  if not win or not win:IsShown() then return end
  local th = UI:Theme()
  for _, b in pairs(icons) do paintState(b, th) end
  if folderWin and folderWin:IsShown() then for _, b in pairs(folderIcons) do paintState(b, th) end end
end

-- lay out a list of keys in a grid; returns how many were placed
local function layoutGrid(pool, grid, list, byKey, cols, where, shown)
  local size = cfg().size
  for _, b in pairs(pool) do b:Hide(); b.item = nil end
  wipe(shown)
  local n = 0
  for _, key in ipairs(list) do
    local it = byKey[key]
    if it then
      local b = getIcon(it, pool, grid)
      b.item, b.where = it, where
      if it.secure then b:SetAttribute("type1", "click"); b:SetAttribute("clickbutton1", it.secure) end
      local i = n; n = n + 1
      shown[n] = b
      b:SetSize(size, size)
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", grid, "TOPLEFT", (i % cols) * (size + GAP), -math.floor(i / cols) * (size + GAP))
      paintIcon(b, it)
      b:Show()
    end
  end
  return n
end

local function itemsByKey()
  local byKey = {}
  for _, it in ipairs(S:ButtonBoxCatalog()) do byKey[it.key] = it end
  for id, g in pairs(groups()) do
    local children = {}
    for _, k in ipairs(g.keys or {}) do if byKey[k] then children[#children + 1] = byKey[k] end end
    byKey["group:" .. id] = { key = "group:" .. id, groupId = id, label = g.name or "Group", children = children }
  end
  return byKey
end

function S:RefreshButtonBox()
  if not win then return end
  if combat() then pending = true return end
  pending = false
  local c = cfg()
  tidyAllGroups()
  local byKey = itemsByKey()
  local size = c.size
  local width = math.max(size + PAD * 2, (dock and dock.width) or c.w)
  local cols = math.max(1, math.floor((width - PAD * 2 + GAP) / (size + GAP)))
  win.cols = cols
  local n = layoutGrid(icons, win.grid, c.keys, byKey, cols, "box", shownAt.box)
  local rows = math.max(1, math.ceil(n / cols))
  win.empty:SetShown(n == 0)
  win:SetSize(width, HEAD + rows * (size + GAP) - GAP + PAD + (n == 0 and 30 or 0))
  if refreshFolder then refreshFolder(byKey) end
  states()
  if S.PluginSyncMinimap then S:PluginSyncMinimap() end
end
S:On("PLAYER_REGEN_ENABLED", function() if pending then S:RefreshButtonBox() end end)
-- entering combat: every game button in the box clicks normally (attributes can't change in combat)
S:On("PLAYER_REGEN_DISABLED", function()
  for _, pool in ipairs({ icons, folderIcons }) do
    for _, b in pairs(pool) do
      if b.isSecure and b.item and b.item.secure then b:SetAttribute("type1", "click") end
    end
  end
  if ghost then hideGhost() end
end)
S:Listen("GUILD_READY", function() if win then S:RefreshButtonBox() end end)

---------------------------------------------------------------------------
-- An open group: a small window next to it with the group's icons and its name
-- (click the name to change it). Drag icons out to take them out of the group.
---------------------------------------------------------------------------
local function buildFolder()
  folderWin = UI:Window("CC_ButtonBoxGroup", "", 200, 120, { header = 32 })
  folderWin:SetFrameStrata("HIGH")
  -- may hold the game's secure buttons: Escape mustn't try to close it in combat
  if UISpecialFrames then
    for i = #UISpecialFrames, 1, -1 do if UISpecialFrames[i] == "CC_ButtonBoxGroup" then table.remove(UISpecialFrames, i) end end
  end
  folderWin.title:Hide()
  folderWin.name = UI:Edit(folderWin, 150, 22, "Group name", function(_, text)
    if folderWin.groupId then S:ButtonBoxRenameGroup(folderWin.groupId, text) end
  end)
  folderWin.name:SetPoint("TOPLEFT", 10, -5)
  folderWin.name:SetPoint("RIGHT", folderWin.close, "LEFT", -4, 0)
  folderWin.name:HookScript("OnEditFocusLost", function(self)
    local id = folderWin.groupId
    local g = id and groups()[id]
    if g and S.Trim(self:GetText() or "") ~= (g.name or "") then S:ButtonBoxRenameGroup(id, self:GetText()) end
  end)
  folderWin.grid = CreateFrame("Frame", nil, folderWin)
  folderWin.grid:SetPoint("TOPLEFT", PAD, -42); folderWin.grid:SetPoint("BOTTOMRIGHT", -PAD, PAD)
  folderWin.hint = UI:Text(folderWin, "|cff888888Drag an icon out to take it out of the group.|r", "small", "CENTER")
  folderWin.hint:SetPoint("BOTTOMLEFT", PAD, 8); folderWin.hint:SetPoint("BOTTOMRIGHT", -PAD, 8)
  folderWin:SetScript("OnDragStart", nil)    -- it sits on its group
  folderWin:HookScript("OnHide", function(self)
    if self.name:HasFocus() then self.name:ClearFocus() end
    self.groupId = nil
  end)
  local acc = 0
  folderWin:HookScript("OnUpdate", function(_, el) acc = acc + el; if acc > 0.5 then acc = 0; states() end end)
end

shownAt.folder = {}
refreshFolder = function(byKey)
  if not folderWin or not folderWin:IsShown() then return end
  local id = folderWin.groupId
  local g = id and groups()[id]
  if not g then folderWin:Hide() return end
  byKey = byKey or itemsByKey()
  local size = cfg().size
  local n = #(g.keys or {})
  local cols = math.max(2, math.min(4, n <= 4 and 2 or (n <= 9 and 3 or 4)))
  folderWin.cols = cols
  local placed = layoutGrid(folderIcons, folderWin.grid, g.keys, byKey, cols, id, shownAt.folder)
  local rows = math.max(1, math.ceil(placed / cols))
  folderWin:SetSize(math.max(180, cols * (size + GAP) - GAP + PAD * 2), 42 + rows * (size + GAP) - GAP + PAD + 22)
  if not folderWin.name:HasFocus() then folderWin.name:SetText(g.name or "") end
end

-- open a group next to its icon; fresh = just made, so the name is ready to type
function S:ButtonBoxOpenGroup(id, anchor, fresh)
  if not groups()[id] then return end
  if combat() then S:Print("Groups open after combat.") return end
  if not folderWin then buildFolder() end
  if folderWin:IsShown() and folderWin.groupId == id and not fresh then folderWin:Hide() return end
  folderWin.groupId = id
  if not anchor then for _, b in pairs(icons) do if b:IsShown() and b.item and b.item.groupId == id then anchor = b end end end
  folderWin:ClearAllPoints()
  if anchor then
    local _, y = anchor:GetCenter()
    local up = y and y < (UIParent:GetHeight() or 768) * 0.4
    if up then folderWin:SetPoint("BOTTOM", anchor, "TOP", 0, 8) else folderWin:SetPoint("TOP", anchor, "BOTTOM", 0, -8) end
  else
    folderWin:SetPoint("CENTER")
  end
  folderWin:Show(); folderWin:Raise()
  refreshFolder()
  local g = groups()[id]
  if fresh or (g and g.new) then
    if g then g.new = nil end
    folderWin.name:SetFocus(); folderWin.name:HighlightText()
  end
end

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
  win:SetScript("OnDragStart", function(self) if not dock then self:StartMoving() end end)   -- docked: stays on the minimap
  win:HookScript("OnDragStop", function(self)
    if dock then return end
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
  win.grip = grip
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
  win:HookScript("OnHide", function() if not (S.SnapBusy and S.SnapBusy()) then cfg().open = false end; closeFolderIf(nil) end)
  local acc = 0
  win:HookScript("OnUpdate", function(_, el) acc = acc + el; if acc > 0.5 then acc = 0; states() end end)
end

-- docked under the minimap (Minimap.lua's drawer) or free again (d = nil)
local function applyDock()
  if not win or combat() then return end
  win:ClearAllPoints()
  if dock then
    win:SetPoint(dock.point or "TOP", dock.anchor, dock.relPoint or "BOTTOM", dock.x or 0, dock.y or -6)
    if win.grip then win.grip:Hide() end
    if dock.decorate then pcall(dock.decorate, win) end
  else
    if win.grip then win.grip:Show() end
    local c = cfg()
    if c.pos then win:SetPoint(c.pos[1], UIParent, c.pos[2], c.pos[3], c.pos[4]) else win:SetPoint("CENTER") end
  end
end
function S:ButtonBoxDock(d)
  dock = d
  if win then applyDock(); S:RefreshButtonBox() end
end
function S:ButtonBoxDocked() return dock ~= nil end
function S:ButtonBoxWindow() return win end

function S:ShowButtonBox()
  if not win then build(); if dock then applyDock() end end
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
