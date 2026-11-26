-- Main hub window: a home screen of tool tiles, the Settings page, minimap button.
local _, S = ...
local UI = S.UI
local function FS(n) return n + ((tonumber(S.db and S.db.global.fontSize) or 12) - 12) end

S.tabs, S.tabsById = {}, {}
S.CW, S.CH = 760, 500     -- content area size available to tabs

-- opts: { officer = true (officers only), icon = texture }
function S:AddTab(id, label, build, refresh, opts)
  local t = { id = id, label = label, build = build, refresh = refresh, opts = opts or {} }
  S.tabs[#S.tabs + 1] = t
  S.tabsById[id] = t
end

local main

-- Sections: only Settings is a page now; the home screen shows a tile per tool.
S.SECTIONS = {
  { id = "settings", name = "Settings", hidden = true, pages = { { "settings", "Settings" } } },
}
-- pages that live inside another page now
local PAGE_ALIAS = {}

local function sectionOf(id, sub)
  for _, sec in ipairs(S.SECTIONS) do
    for i, pg in ipairs(sec.pages) do if pg[1] == id and pg[3] and pg[3] == sub then return sec, i end end
  end
  for _, sec in ipairs(S.SECTIONS) do
    for i, pg in ipairs(sec.pages) do if pg[1] == id then return sec, i end end
  end
end

-- the sidebar is gone; these stay so old settings / commands don't break
function S:ApplyTabOrder() end
function S:SaveTabOrder() end
function S:ResetTabOrder() end
function S:LayoutSidebar() end

local function C(c, a) return c[1], c[2], c[3], a or 1 end

---------------------------------------------------------------------------
-- What each home tile says right now
---------------------------------------------------------------------------
local LIVE = {}
---------------------------------------------------------------------------
-- Pieces (built to match the redesign preview)
---------------------------------------------------------------------------
local ICONKEY = { settings = "settings" }

-- round icon: dark disc, gold ring, gold line icon
local function roundIcon(parent, size, key)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(size, size)
  f.disc = f:CreateTexture(nil, "ARTWORK"); f.disc:SetAllPoints(); f.disc:SetTexture(UI.ART.disc); f.disc:SetVertexColor(0, 0, 0, 0.45)
  f.ring = f:CreateTexture(nil, "ARTWORK", nil, 2); f.ring:SetAllPoints(); f.ring:SetTexture(UI.ART.ring)
  f.icon = UI:Icon(f, key or "tools", math.floor(size * 0.5), "OVERLAY"); f.icon:SetPoint("CENTER")
  UI:Skin(f, function(self, th) self.ring:SetVertexColor(C(th.gold)); self.icon:SetVertexColor(C(th.gold)) end)
  function f:SetIcon(k) self.icon:SetTexture(UI.ICON[k]) end
  return f
end

local drag   -- the home tile being dragged (see dragStart below)
local function makeTile(parent)
  local t = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  -- outer glow (shown on hover)
  t.halo = CreateFrame("Frame", nil, t)
  t.halo:SetPoint("TOPLEFT", -16, 16); t.halo:SetPoint("BOTTOMRIGHT", 16, -16)
  t.halo:SetFrameLevel(math.max(0, t:GetFrameLevel() - 1))
  t.haloTex = t.halo:CreateTexture(nil, "BACKGROUND"); t.haloTex:SetAllPoints(); t.haloTex:SetTexture(UI.ART.glow); t.haloTex:SetAlpha(0)
  t.grad = UI:RoundGradient(t, "BACKGROUND", 2, 6, 0)   -- top cap = ribbon, body = panel gradient
  t.ico = roundIcon(t, 44); t.ico:SetPoint("TOP", 0, -18)
  t.name = t:CreateFontString(nil, "OVERLAY"); UI:SetFont(t.name, "head", FS(18)); t.name:SetPoint("TOP", t.ico, "BOTTOM", 0, -8); t.name:SetJustifyH("CENTER"); t.name:SetWordWrap(false)
  t.live = t:CreateFontString(nil, "OVERLAY"); UI:SetFont(t.live, "body", FS(12)); t.live:SetPoint("TOP", t.name, "BOTTOM", 0, -4); t.live:SetJustifyH("CENTER"); t.live:SetWordWrap(false)
  t.subs = t:CreateFontString(nil, "OVERLAY"); UI:SetFont(t.subs, "body", FS(12)); t.subs:SetPoint("TOP", t.live, "BOTTOM", 0, -4); t.subs:SetJustifyH("CENTER"); t.subs:SetJustifyV("TOP"); t.subs:SetWordWrap(true)
  t.badge = UI:Badge(t, 20); t.badge:SetPoint("TOPRIGHT", -12, -14)
  local function paint(self, th)
    th = th or UI:Theme()
    UI.Flat(self, th.panel, 1, self.__hot and th.gold or th.edge, 1)
    self.grad:Colors(th.ribbon, th.panel, th.panel2, th.panel2)
    self.haloTex:SetVertexColor(C(th.gold))
    UI:SetFont(self.name, "head", FS(18)); self.name:SetTextColor(C(th.text))
    UI:SetFont(self.live, "body", FS(12)); self.live:SetTextColor(C(th.live))
    UI:SetFont(self.subs, "body", FS(12)); self.subs:SetTextColor(C(th.muted))
  end
  t.Paint = paint
  UI:Skin(t, paint)
  t:SetScript("OnEnter", function(self)
    self.__hot = true; paint(self)
    local lvl = UI:AnimLevel()
    if lvl ~= "minimal" then
      self.haloTex:SetAlpha(lvl == "flashy" and 0.55 or 0.3)
      if self.home and not (drag and drag.tile == self) then self:ClearAllPoints(); self:SetPoint("TOPLEFT", self.home[1], self.home[2] + 3) end
    end
    if lvl == "flashy" and PlaySound and SOUNDKIT and SOUNDKIT.U_CHAT_SCROLL_BUTTON then PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON) end
  end)
  t:SetScript("OnLeave", function(self)
    self.__hot = false; paint(self)
    self.haloTex:SetAlpha(0)
    if self.home and not (drag and drag.tile == self) then self:ClearAllPoints(); self:SetPoint("TOPLEFT", self.home[1], self.home[2]) end
  end)
  return t
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local tiles = {}
local HEAD_H = 68
local BODY_W = S.CW + 8
local BODY_H = 34 + 8 + 30 + 8 + S.CH + 18     -- back row, tabs row, content panel

-- Home pages, like apps on a phone: 4 x 3 tiles per page, the mouse wheel (or the dots)
-- flips pages, drag a tile to move it - hold it at the left / right edge to take it to
-- another page. Saved: S.db.global.homeSlots = { [tile id] = slot } (slot 1 = page 1 top
-- left; 13 = page 2 top left). Tools without a saved slot fill the first free ones.
local COLS, ROWS = 4, 3
local PER = COLS * ROWS
local homePage = 1
local function homeSlots()
  local g = S.db and S.db.global
  if not g then return {} end
  if type(g.homeSlots) ~= "table" then
    g.homeSlots = {}
    -- the older saved order (one list) becomes slots 1, 2, 3...
    if type(g.homeOrder) == "table" then for i, id in ipairs(g.homeOrder) do g.homeSlots[id] = i end end
    g.homeOrder = nil
  end
  return g.homeSlots
end
local function homeTiles()
  local list = {}
  for _, label in ipairs(S.ToolLabels and S:ToolLabels() or {}) do
    local t = S:ToolInfo(label)
    if t then
      list[#list + 1] = { id = "tool:" .. label, name = t.tileName or label, pages = {}, tool = label, icon = t.icon, tint = t.tint,
        badgeText = t.tileTag, subsText = t.desc, action = function() S:ToolToggle(label) end }
    end
  end
  -- give every tile a slot: its saved one if free, else the first free slot
  local saved, taken = homeSlots(), {}
  for _, sec in ipairs(list) do
    local sl = tonumber(saved[sec.id])
    if sl and sl >= 1 and not taken[sl] then sec.slot = sl; taken[sl] = true end
  end
  local nextFree = 1
  for _, sec in ipairs(list) do
    if not sec.slot then
      while taken[nextFree] do nextFree = nextFree + 1 end
      sec.slot = nextFree; taken[nextFree] = true
    end
  end
  table.sort(list, function(x, y) return x.slot < y.slot end)
  return list
end
local function pageCount(list, extra)
  local maxSlot = 0
  for _, sec in ipairs(list) do if sec.slot > maxSlot then maxSlot = sec.slot end end
  return math.max(1, math.ceil(maxSlot / PER)) + (extra and 1 or 0)
end
local function slotXY(slot, grid)
  local i = (slot - 1) % PER
  local col, row = i % COLS, math.floor(i / COLS)
  return col * (grid.tw + grid.gap), -56 - row * (grid.th + grid.gap)   -- (56: the greeting + its hint line above)
end
local function slotPage(slot) return math.floor((slot - 1) / PER) + 1 end
-- put `id` at slot `to`; whoever is there moves one along (and so on) until a free slot
local function placeAt(map, id, to)
  local at = {}
  for k, v in pairs(map) do if k ~= id then at[v] = k end end
  map[id] = to
  local carry, sl = at[to], to
  while carry do
    sl = sl + 1
    local nextCarry = at[sl]
    map[carry] = sl
    carry = nextCarry
  end
end
-- empty pages in between are removed (later pages move up)
local function compact(map)
  local used = {}
  for _, v in pairs(map) do used[slotPage(v)] = true end
  local maxPage = 0
  for pg in pairs(used) do if pg > maxPage then maxPage = pg end end
  local shift, newOf = 0, {}
  for pg = 1, maxPage do
    if not used[pg] then shift = shift + 1 end
    newOf[pg] = pg - shift
  end
  for k, v in pairs(map) do map[k] = v - (slotPage(v) - newOf[slotPage(v)]) * PER end
end

local refreshHome
local function cursorInHome()
  local home = main.home
  local s = home:GetEffectiveScale() or 1
  local cx, cy = GetCursorPosition()
  return cx / s - (home:GetLeft() or 0), cy / s - (home:GetTop() or 0)
end
local function slotUnder(x, y, grid)
  local col = math.max(0, math.min(COLS - 1, math.floor((x + grid.gap / 2) / (grid.tw + grid.gap))))
  local row = math.max(0, math.min(ROWS - 1, math.floor((-56 - y + grid.gap / 2) / (grid.th + grid.gap))))
  return (homePage - 1) * PER + row * COLS + col + 1
end
-- lay the tiles of the current page out (map = slots to show, e.g. a drag preview)
local function layoutPage(map, skip)
  local grid = main.homeGrid
  if not grid then return end
  for _, t in ipairs(main.homeTilesShown or {}) do
    if t ~= skip then
      local sl = map[t.secId]
      if sl and slotPage(sl) == homePage then
        local x, y = slotXY(sl, grid)
        t.home = { x, y }
        t:ClearAllPoints(); t:SetPoint("TOPLEFT", x, y); t:Show()
      else
        t:Hide()
      end
    end
  end
end
local function paintDots(n)
  local d = main.homeDots
  if not d then return end
  for i, dot in ipairs(d.dots) do dot:SetShown(i <= n) end
  for i = #d.dots + 1, n do
    local dot = CreateFrame("Button", nil, d)
    dot:SetSize(14, 14)
    dot.t = dot:CreateTexture(nil, "ARTWORK"); dot.t:SetPoint("CENTER"); dot.t:SetSize(8, 8); dot.t:SetTexture(UI.ART.disc)
    dot:SetScript("OnClick", function() S:HomePage(i) end)
    d.dots[i] = dot
  end
  local th = UI:Theme()
  for i = 1, n do
    local dot = d.dots[i]
    dot:ClearAllPoints(); dot:SetPoint("CENTER", d, "CENTER", (i - (n + 1) / 2) * 18, 0)
    if i == homePage then dot.t:SetVertexColor(C(th.gold)); dot.t:SetSize(10, 10)
    else dot.t:SetVertexColor(C(th.muted, 0.6)); dot.t:SetSize(7, 7) end
  end
  d:SetShown(n > 1 or drag ~= nil)
end
-- slide the page in from the side it comes from
local function slideIn(dir)
  if UI:AnimLevel() == "minimal" or not main.homeTilesShown then return end
  local list = {}
  for _, t in ipairs(main.homeTilesShown) do if t:IsShown() and t.home and not (drag and drag.tile == t) then list[#list + 1] = t end end
  main.homeSlide = main.homeSlide or CreateFrame("Frame", nil, main.home)
  local w, p = (BODY_W + 40) * dir, 0
  main.homeSlide:SetScript("OnUpdate", function(self, el)
    p = math.min(1, p + el / 0.18)
    local e = 1 - (1 - p) * (1 - p)
    for _, t in ipairs(list) do t:ClearAllPoints(); t:SetPoint("TOPLEFT", t.home[1] + w * (1 - e), t.home[2]) end
    if p >= 1 then self:SetScript("OnUpdate", nil) end
  end)
end
function S:HomePage(n, quiet)
  if not main or not main.home then return end
  local total = drag and drag.pages or pageCount(homeTiles())
  n = math.max(1, math.min(total, n or 1))
  if n == homePage then return end
  local dir = n > homePage and 1 or -1
  homePage = n
  if drag then
    drag.to, drag.preview = nil, nil
    layoutPage(drag.map, drag.tile)
  else
    refreshHome(false)
  end
  paintDots(total)
  if not quiet then slideIn(dir) end
  if PlaySound and SOUNDKIT and SOUNDKIT.IG_ABILITY_PAGE_TURN then PlaySound(SOUNDKIT.IG_ABILITY_PAGE_TURN) end
end
local EDGE, EDGE_WAIT = 26, 0.55
local function dragUpdate()
  if not drag then return end
  local t, grid = drag.tile, main.homeGrid
  local x, y = cursorInHome()
  t:ClearAllPoints(); t:SetPoint("TOPLEFT", x - drag.dx, y - drag.dy)
  -- hold it at the left / right edge to change page
  local edge = (x < EDGE and -1) or (x > BODY_W - EDGE and 1) or nil
  if edge then
    if drag.edge ~= edge then drag.edge, drag.edgeAt = edge, GetTime() end
    main.homeEdge:ClearAllPoints()
    main.homeEdge:SetPoint(edge < 0 and "LEFT" or "RIGHT", main.home, edge < 0 and "LEFT" or "RIGHT", 0, -20)
    main.homeEdge:Show()
    if GetTime() - drag.edgeAt >= EDGE_WAIT then
      drag.edgeAt = GetTime()
      local target = homePage + edge
      if target >= 1 and target <= drag.pages then S:HomePage(target) end
    end
    return
  end
  drag.edge = nil; main.homeEdge:Hide()
  local to = slotUnder(x, y, grid)
  if to ~= drag.to then
    drag.to = to
    local preview = {}
    for k, v in pairs(drag.map) do preview[k] = v end
    placeAt(preview, t.secId, to)
    drag.preview = preview
    layoutPage(preview, t)
  end
end
local function dragStart(t)
  if not main.homeGrid or not t.secId then return end
  local map = {}
  for _, x in ipairs(main.homeTilesShown or {}) do map[x.secId] = x.slot end
  local x, y = cursorInHome()
  drag = { tile = t, map = map, dx = x - t.home[1], dy = y - t.home[2] }
  -- one empty page after the last, to start a new page
  local list = {}
  for _, x2 in ipairs(main.homeTilesShown or {}) do list[#list + 1] = { slot = x2.slot } end
  drag.pages = pageCount(list, true)
  t:SetFrameLevel(t:GetFrameLevel() + 20)
  t.haloTex:SetAlpha(0.6)
  main.homeDrag = main.homeDrag or CreateFrame("Frame", nil, main.home)
  main.homeDrag:SetScript("OnUpdate", dragUpdate)
  paintDots(drag.pages)
end
local function dragStop()
  if not drag then return end
  local d = drag
  drag = nil
  if main.homeDrag then main.homeDrag:SetScript("OnUpdate", nil) end
  if main.homeEdge then main.homeEdge:Hide() end
  d.tile:SetFrameLevel(math.max(1, d.tile:GetFrameLevel() - 20))
  d.tile.justDragged = GetTime()
  local map = d.preview or d.map
  if not d.preview and d.to == nil then
    -- dropped right after a page change: first free slot on this page, else the end of it
    map = {}
    for k, v in pairs(d.map) do map[k] = v end
    local used = {}
    for k, v in pairs(map) do if k ~= d.tile.secId then used[v] = true end end
    local first = (homePage - 1) * PER + 1
    local spot
    for sl = first, first + PER - 1 do if not used[sl] then spot = sl; break end end
    placeAt(map, d.tile.secId, spot or (first + PER - 1))
  end
  compact(map)
  S.db.global.homeSlots = map
  homePage = math.min(homePage, pageCount((function() local l = {} for _, v in pairs(map) do l[#l + 1] = { slot = v } end return l end)()))
  refreshHome(false)
end
function S:ResetHomeOrder()
  if S.db then S.db.global.homeSlots = {}; S.db.global.homeOrder = nil end
  homePage = 1
  refreshHome(false)
end
S:AddCommand("tiles", "reset", "Home window: put the tool tiles back in their normal order", function(arg)
  if (arg or ""):lower():find("reset") then S:ResetHomeOrder(); S:Print("Home tiles are back in their normal order.")
  else S:Print("Drag a tile on the home window to move it (hold it at the edge for another page). /ccenter tiles reset puts them back.") end
end)
refreshHome = function(animate)
  if not main or not main.home then return end
  local list = homeTiles()
  local gap = 12
  local tw = math.floor((BODY_W - gap * (COLS - 1)) / COLS)
  local th2 = math.floor((BODY_H - 56 - 22 - gap * (ROWS - 1)) / ROWS)   -- 22 = the page dots
  main.homeGrid = { cols = COLS, tw = tw, th = th2, gap = gap }
  main.homeTilesShown = {}
  local pages = pageCount(list)
  if homePage > pages then homePage = pages end
  -- page dots + the edge arrow shown while dragging
  if not main.homeDots then
    main.homeDots = CreateFrame("Frame", nil, main.home); main.homeDots.dots = {}
    main.homeDots:SetSize(200, 16); main.homeDots:SetPoint("BOTTOM", main.home, "BOTTOM", 0, 2)
    main.homeEdge = CreateFrame("Frame", nil, main.home); main.homeEdge:SetSize(22, 120); main.homeEdge:SetFrameLevel(main.home:GetFrameLevel() + 30)
    main.homeEdge.t = main.homeEdge:CreateTexture(nil, "OVERLAY"); main.homeEdge.t:SetAllPoints(); main.homeEdge.t:SetTexture(UI.ART.glow)
    main.homeEdge.t:SetVertexColor(C(UI:Theme().gold, 0.8)); main.homeEdge:Hide()
    -- the mouse wheel flips pages (down / right = next)
    main.home:EnableMouseWheel(true)
    main.home:SetScript("OnMouseWheel", function(_, delta) S:HomePage(homePage + (delta < 0 and 1 or -1)) end)
  end
  for i, sec in ipairs(list) do
    local t = tiles[i] or makeTile(main.home)
    tiles[i] = t
    t.secId, t.slot = sec.id, sec.slot
    main.homeTilesShown[i] = t
    if not t.dragReady then
      t.dragReady = true
      t:RegisterForDrag("LeftButton")
      t:SetScript("OnDragStart", function(self) dragStart(self) end)
      t:SetScript("OnDragStop", function() dragStop() end)
      t:SetScript("OnHide", function(self) if drag and drag.tile == self then dragStop() end end)
      t:EnableMouseWheel(true)
      t:SetScript("OnMouseWheel", function(_, delta) if not drag then S:HomePage(homePage + (delta < 0 and 1 or -1)) end end)
    end
    local x, y = slotXY(sec.slot, main.homeGrid)
    t.home = { x, y }
    t:ClearAllPoints(); t:SetPoint("TOPLEFT", x, y); t:SetSize(tw, th2)
    t.name:SetWidth(tw - 20); t.live:SetWidth(tw - 20); t.subs:SetWidth(tw - 24)
    -- the description gets whatever room is left under the name and status line
    local room = math.max(12, th2 - (18 + 44 + 8 + 22 + 4 + 14 + 4) - 12)
    t.subs:SetHeight(room)
    if t.subs.SetMaxLines then t.subs:SetMaxLines(math.max(1, math.floor(room / 14))) end
    if sec.icon then
      t.ico.icon:SetTexture(sec.icon)
      if sec.tint then local g = UI:Theme().gold; t.ico.icon:SetVertexColor(g[1], g[2], g[3]) else t.ico.icon:SetVertexColor(1, 1, 1) end
    else t.ico:SetIcon(ICONKEY[sec.id] or "tools") end
    UI:SetFont(t.name, "head", FS(18)); t.name:SetText(sec.tileName or sec.name)
    -- long names step down a size so they fit on one line
    if (t.name:GetStringWidth() or 0) > tw - 20 then UI:SetFont(t.name, "head", FS(15)) end
    local status = ""
    if sec.tool then
      local _, avail, isOn = S:ToolInfo(sec.tool)
      if isOn then status = "Open" elseif not avail then status = "|cff888888Not available|r" end
    end
    if sec.badgeText then status = (status ~= "" and (status .. "  ") or "") .. sec.badgeText end
    t.live:SetText(status)
    if sec.subs then t.subs:SetText(sec.subs(S:IsOfficer()))
    elseif sec.subsText then t.subs:SetText(sec.subsText)
    else
      local labels = {}
      for _, pg in ipairs(sec.pages) do
        local tt = S.tabsById and S.tabsById[pg[1]]
        if not (tt and tt.opts and tt.opts.officer and not S:IsOfficer()) then labels[#labels + 1] = pg[2] end
      end
      t.subs:SetText(table.concat(labels, "  -  "))
    end
    local n = 0
    if sec.tool == "Messenger" and S.UnreadMail then n = S:UnreadMail() end
    t.badge:SetCount(n)
    t:SetScript("OnClick", function(self)
      if self.justDragged and GetTime() - self.justDragged < 0.3 then return end   -- that was a drag, not a click
      if PlaySound and SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_TAB then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB) end
      if sec.action then sec.action() else S:SelectTab(sec.pages[1][1]) end
    end)
    t:SetShown(slotPage(sec.slot) == homePage)
    if animate and t:IsShown() then UI:Animate(t, "tile", (((sec.slot - 1) % PER)) * 0.05) end
  end
  for i = #list + 1, #tiles do tiles[i]:Hide() end
  paintDots(pages)
  local hour = tonumber(date("%H")) or 12
  local hello = (hour >= 5 and hour < 12) and "Good morning" or ((hour >= 12 and hour < 18) and "Good afternoon" or "Good evening")
  main.hello:SetText(hello .. ", " .. (S.Short(S.me or "") or "friend"))
  main.helloSub:SetText("Click a tool to open or close it - drag tiles to move them - scroll for more pages")
end

S.SectionOf = sectionOf
S.HomeTileList = function() return homeTiles() end
S.SECTION_ICON = ICONKEY
S.MAIN_HEAD_H = HEAD_H

local function showHome(animate, keepCollapsed)
  if not main then return end
  if not keepCollapsed and S.QuickBarExpand then S:QuickBarExpand() end
  for _, t in ipairs(S.tabs) do if t.panel then t.panel:Hide() end end
  main.view = "home"
  main.current = nil
  main.section:Hide()
  main.home:Show()
  main.crumb:SetText("Home")
  refreshHome(animate ~= false)
  if animate ~= false then UI:Animate(main.home, "page") end
end
function S:ShowHome() showHome(true) end

function S:ApplyMainTheme()
  if not main then return end
  local th = UI:Theme()
  UI:SetFont(main.titleText, "head", FS(22)); main.titleText:SetTextColor(C(th.gold))
  UI:SetFont(main.crumb, "body", FS(13)); main.crumb:SetTextColor(C(th.muted))
  UI:SetFont(main.hello, "head", FS(20)); main.hello:SetTextColor(C(th.text))
  UI:SetFont(main.helloSub, "body", FS(13)); main.helloSub:SetTextColor(C(th.muted))
  UI:SetFont(main.secName, "head", FS(21)); main.secName:SetTextColor(C(th.text))
  UI:SetFont(main.secLive, "body", FS(13)); main.secLive:SetTextColor(C(th.muted))
  UI:Gradient(main.banner, "HORIZONTAL", th.ribbon[1], th.ribbon[2], th.ribbon[3], 1, th.ribbon[1], th.ribbon[2], th.ribbon[3], 0)
  main.bannerEdge:SetTexture(UI.MEDIA .. "UI\\rfill"); main.bannerEdge:SetTexCoord(0, 1, 0, 1); main.bannerEdge:SetVertexColor(C(th.gold))
  for _, c in pairs(main.bannerCap or {}) do c:SetVertexColor(C(th.ribbon)) end
  main.crestGlow:SetVertexColor(C(th.gold))
  main.crestRing:SetVertexColor(C(th.gold))
  main.ver:SetTextColor(C(th.muted)); main.status:SetTextColor(C(th.muted)); main.guildLine:SetTextColor(C(th.muted))
  main.guildDot:SetVertexColor(C(th.muted))
  main.onlineText:SetTextColor(C(th.live)); main.onlineText:SetShadowColor(th.live[1] * 0.4, th.live[2] * 0.4, th.live[3] * 0.4, 1)
  main.onlineGlow:SetVertexColor(th.live[1], th.live[2], th.live[3], 0.35)
  if main.view == "home" then refreshHome(false) end
end

-- Settings and the rank emblem open a page; pressed again they put things back:
-- the page was folded away -> fold it again; another page was open -> go back to it.
local function pageOpen() return not S.QuickBarOpen or S.QuickBarOpen() end
local function toggleButton(key, isShowing, open)
  local st = main.toggleFrom
  if pageOpen() and isShowing() then
    main.toggleFrom = nil
    if st and st.key == key then
      if st.collapsed and S.QuickBarCollapse then S:QuickBarCollapse()
      elseif st.id and st.id ~= "home" then S:SelectTab(st.id, st.sub)
      else showHome(true) end
    elseif S.QuickBarCollapse then
      S:QuickBarCollapse()
    end
    return
  end
  local wasOpen = pageOpen() and main:IsShown()
  local cur = S:CurrentTabId()
  local sub = main.current and main.current.panel and main.current.panel.tabs and main.current.panel.tabs.current
  main.toggleFrom = { key = key, collapsed = not wasOpen, id = wasOpen and cur or nil, sub = sub }
  open()
end
function S:RankPlateClick()
  if not main then return end
  -- (no rank emblem in Command Center)
end

local function createMain()
  local W, H = BODY_W + 40, HEAD_H + 16 + BODY_H + 36
  main = UI:Window("CC_Main", "Command Center", W, H, { header = HEAD_H })
  main:SetFrameStrata("HIGH")
  main:Hide()
  main:SetScale(S.db.global.scale or 1)
  main.fullW = W
  -- the window is two parts: the quickbar (this frame: crest, title, header buttons) and
  -- the drawer under it with the home page and every module. QuickBar.lua collapses,
  -- snaps and re-lays them.
  main:SetHeight(HEAD_H + 6)
  if main.headLine then main.headLine:Hide() end
  local drawer = CreateFrame("Frame", "CC_MainDrawer", main, BackdropTemplateMixin and "BackdropTemplate" or nil)
  drawer:SetSize(W, H - HEAD_H - 4)
  drawer:SetPoint("TOPLEFT", main, "BOTTOMLEFT", 0, -6)
  drawer:EnableMouse(true)
  local dsh = CreateFrame("Frame", nil, drawer)
  dsh:SetPoint("TOPLEFT", -22, 22); dsh:SetPoint("BOTTOMRIGHT", 22, -26); dsh:SetFrameLevel(math.max(0, drawer:GetFrameLevel() - 1))
  local dst = dsh:CreateTexture(nil, "BACKGROUND"); dst:SetAllPoints(); dst:SetTexture(UI.ART.glow); dst:SetVertexColor(0, 0, 0, 0.85)
  main.drawerShadow = dsh
  UI:DialogBackdrop(drawer)
  main.drawer = drawer

  -- crest: dark circle, gold ring, the emblem, soft glow
  local crest = CreateFrame("Frame", nil, main)
  crest:SetSize(48, 48); crest:SetPoint("TOPLEFT", 18, -13)
  main.crest = crest
  main.crestGlow = crest:CreateTexture(nil, "BACKGROUND"); main.crestGlow:SetTexture(UI.ART.glow)
  main.crestGlow:SetPoint("TOPLEFT", -22, 22); main.crestGlow:SetPoint("BOTTOMRIGHT", 22, -22); main.crestGlow:SetAlpha(0.35)
  local disc = crest:CreateTexture(nil, "ARTWORK"); disc:SetAllPoints(); disc:SetTexture(UI.ART.disc); disc:SetVertexColor(0.05, 0.08, 0.05, 1)
  local emblem = crest:CreateTexture(nil, "ARTWORK", nil, 1); emblem:SetPoint("TOPLEFT", 4, -4); emblem:SetPoint("BOTTOMRIGHT", -4, 4)
  emblem:SetTexture(S.LOGO_ROUND or S.LOGO)
  main.crestRing = crest:CreateTexture(nil, "OVERLAY"); main.crestRing:SetAllPoints(); main.crestRing:SetTexture(UI.ART.ring)
  local acc = 0
  crest:SetScript("OnUpdate", function(_, el)
    acc = acc + el
    local lvl = UI:AnimLevel()
    if lvl == "flashy" then main.crestGlow:SetAlpha(0.35 + 0.3 * math.sin(acc * 2.5))
    elseif lvl == "smooth" then main.crestGlow:SetAlpha(0.35)
    else main.crestGlow:SetAlpha(0.2) end
  end)

  main.titleText = main:CreateFontString(nil, "OVERLAY"); UI:SetFont(main.titleText, "head", FS(22)); main.titleText:SetPoint("TOPLEFT", crest, "TOPRIGHT", 14, -4)
  main.titleText:SetText("Command Center")
  main.crumb = main:CreateFontString(nil, "OVERLAY"); UI:SetFont(main.crumb, "body", FS(13)); main.crumb:SetPoint("TOPLEFT", main.titleText, "BOTTOMLEFT", 0, -9)
  -- "<rank>  •  22 online": rank in muted text, a small dot, the online count glowing green
  main.guildLine = UI:Text(main, "", "muted"); main.guildLine:SetPoint("BOTTOMLEFT", main.titleText, "BOTTOMRIGHT", 12, 3)
  main.guildDot = main:CreateTexture(nil, "OVERLAY"); main.guildDot:SetTexture(UI.MEDIA .. "UI\\disc"); main.guildDot:SetSize(5, 5)
  main.guildDot:SetPoint("LEFT", main.guildLine, "RIGHT", 8, 0)
  main.onlineText = UI:Text(main, "", "normal"); main.onlineText:SetPoint("LEFT", main.guildDot, "RIGHT", 8, 0)
  main.onlineGlow = main:CreateTexture(nil, "ARTWORK"); main.onlineGlow:SetTexture(UI.ART.glow); main.onlineGlow:SetBlendMode("ADD")
  main.onlineGlow:SetPoint("TOPLEFT", main.onlineText, "TOPLEFT", -14, 10); main.onlineGlow:SetPoint("BOTTOMRIGHT", main.onlineText, "BOTTOMRIGHT", 14, -10)

  -- header buttons (square, like the preview): home, messages, notifications, settings
  main.close:ClearAllPoints(); main.close:SetPoint("TOPRIGHT", -6, -6)
  local tools = UI:IconButton(main, "tools", 40, "Tools", function() if S.ToggleTools then S:ToggleTools() end end)
  tools:SetPoint("TOPRIGHT", -38, -14)
  UI:Tip(tools, "Tools", "Turn every tool on and off: BiB, Damage Meter, Messenger, Button Box and more.")
  main.toolsBtn = tools
  -- the cog opens Settings; pressing it again goes back to where you were
  local gear = UI:IconButton(main, "settings", 40, "Settings", function()
    toggleButton("settings", function() return S:CurrentTabId() == "settings" end, function() S:SelectTab("settings") end)
  end)
  main.gearBtn = gear
  gear:SetPoint("RIGHT", tools, "LEFT", -8, 0)
  S:CreateBell(main)
  local oldBell = S.bellFrame
  if oldBell then oldBell:SetAlpha(0); oldBell:EnableMouse(false); oldBell:ClearAllPoints(); oldBell:SetPoint("RIGHT", gear, "LEFT", -8, 0) end
  local bell = UI:IconButton(main, "bell", 40, "Notifications", function() if oldBell then oldBell:Click() end end)
  bell:SetPoint("RIGHT", gear, "LEFT", -8, 0)
  bell.badge = UI:Badge(bell, 18); bell.badge:SetPoint("TOPRIGHT", 7, 7)
  S.bellFrame = bell
  main.bellBtn = bell
  local msg = UI:IconButton(main, "messages", 40, "Messenger", function()
    local w = _G.CC_Messenger
    if w and w:IsShown() then w:Hide() elseif S.ShowMessenger then S:ShowMessenger() end
  end)
  msg:SetPoint("RIGHT", bell, "LEFT", -8, 0)
  msg.badge = UI:Badge(msg, 18); msg.badge:SetPoint("TOPRIGHT", 7, 7)
  main.msgBtn = msg
  -- Home: pressed while the home page is already showing, it folds the page away
  local home = UI:IconButton(main, "home", 40, "Home", function()
    if main.view == "home" and pageOpen() and S.QuickBarCollapse then S:QuickBarCollapse() else showHome(true) end
  end)
  home:SetPoint("RIGHT", msg, "LEFT", -8, 0)
  main.homeBtn = home

  -- (old rank plate: kept hidden so the bar layout code keeps working)
  local rp = CreateFrame("Button", nil, main)
  rp:SetSize(170, 44); rp:SetPoint("RIGHT", home, "LEFT", -14, 4)
  rp.icon = rp:CreateTexture(nil, "ARTWORK"); rp.icon:SetSize(42, 42); rp.icon:SetPoint("LEFT", 0, 0)
  rp.glow = rp:CreateTexture(nil, "BACKGROUND"); rp.glow:SetTexture(UI.ART.glow); rp.glow:SetBlendMode("ADD")
  rp.glow:SetPoint("TOPLEFT", rp.icon, -10, 10); rp.glow:SetPoint("BOTTOMRIGHT", rp.icon, 10, -10); rp.glow:SetVertexColor(0.6, 1, 0.3, 0.25)
  rp.name = UI:Text(rp, "", "normal"); rp.name:SetPoint("TOPLEFT", rp.icon, "TOPRIGHT", 6, -10); rp.name:SetWidth(120); rp.name:SetWordWrap(false)
  rp.honor = UI:Text(rp, "", "small"); rp.honor:SetPoint("TOPLEFT", rp.name, "BOTTOMLEFT", 0, -3); rp.honor:SetWidth(120); rp.honor:SetWordWrap(false)
  rp:SetScript("OnEnter", function(self)
    do return end
    do return end
    GameTooltip:Show()
  end)
  rp:SetScript("OnLeave", function() GameTooltip:Hide() end)
  rp:SetScript("OnClick", function() S:RankPlateClick() end)
  main.rankPlate = rp
  -- (no guild line, online count or rank emblem in Command Center: keep them hidden for good)
  for _, f in ipairs({ main.guildDot, main.onlineGlow, rp }) do
    f:Hide(); f.Show = f.Hide; f.SetShown = function(self) self:Hide() end
  end
  -- the breadcrumb under the title stops before the rank plate (long paths get "...")
  main.crumb:SetPoint("RIGHT", rp, "LEFT", -12, 0); main.crumb:SetJustifyH("LEFT"); main.crumb:SetWordWrap(false)

  -- body
  local body = CreateFrame("Frame", nil, drawer)
  body:SetPoint("TOPLEFT", 20, -16); body:SetSize(BODY_W, BODY_H)
  main.body = body

  -- home view: greeting + tiles
  main.home = CreateFrame("Frame", nil, body); main.home:SetAllPoints()
  main.hello = main.home:CreateFontString(nil, "OVERLAY"); UI:SetFont(main.hello, "head", FS(20)); main.hello:SetPoint("TOPLEFT", 2, -6)
  main.hello:SetPoint("RIGHT", -2, 0); main.hello:SetJustifyH("LEFT"); main.hello:SetWordWrap(false)
  -- the hint goes on its own line under the greeting (side by side they ran into each other)
  main.helloSub = main.home:CreateFontString(nil, "OVERLAY"); UI:SetFont(main.helloSub, "body", FS(13))
  main.helloSub:SetPoint("TOPLEFT", main.hello, "BOTTOMLEFT", 0, -3); main.helloSub:SetPoint("RIGHT", -2, 0)
  main.helloSub:SetJustifyH("LEFT"); main.helloSub:SetWordWrap(false)

  -- LIVE event indicator (top right of the home screen): shows while an event is live;
  -- click it to join / take part
  local lb = CreateFrame("Button", nil, main.home)
  lb:SetSize(320, 30); lb:SetPoint("TOPRIGHT", -2, -2)
  UI.Flat(lb, UI:Theme().panel, 0.9, { 0.9, 0.2, 0.15 }, 1)
  lb.dot = lb:CreateTexture(nil, "ARTWORK"); lb.dot:SetTexture(UI.MEDIA .. "UI\\disc"); lb.dot:SetSize(10, 10); lb.dot:SetPoint("LEFT", 10, 0)
  lb.dot:SetVertexColor(1, 0.25, 0.2)
  lb.glow = lb:CreateTexture(nil, "BACKGROUND", nil, 2); lb.glow:SetTexture(UI.ART.glow); lb.glow:SetBlendMode("ADD")
  lb.glow:SetPoint("TOPLEFT", lb.dot, -8, 8); lb.glow:SetPoint("BOTTOMRIGHT", lb.dot, 8, -8); lb.glow:SetVertexColor(1, 0.3, 0.2, 0.8)
  lb.tag = UI:Text(lb, "|cffff5040LIVE|r", "normal"); lb.tag:SetPoint("LEFT", lb.dot, "RIGHT", 6, 0)
  lb.title = UI:Text(lb, "", "normal"); lb.title:SetPoint("LEFT", lb.tag, "RIGHT", 8, 0); lb.title:SetWordWrap(false)
  lb.join = UI:Text(lb, "", "small", "RIGHT"); lb.join:SetPoint("RIGHT", -10, 0)
  lb:SetScript("OnUpdate", function(self) local a = 0.55 + 0.45 * math.sin(GetTime() * 4); self.dot:SetAlpha(a); self.glow:SetAlpha(a * 0.8) end)
  lb:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
    for i, it in ipairs(S:LiveNow()) do
      GameTooltip:AddLine("|cffff5040LIVE|r  " .. (it.title or "Event"), 1, 1, 1)
      if it.sub then GameTooltip:AddLine(it.sub, 0.8, 0.8, 0.8, true) end
      if i == 1 then GameTooltip:AddLine(it.joined and "Click to open your event window" or "Click to join", 0.5, 1, 0.5) end
    end
    GameTooltip:Show()
  end)
  lb:SetScript("OnLeave", function() GameTooltip:Hide() end)
  lb:SetScript("OnClick", function(self, btn)
    local live = S:LiveNow()
    if #live > 1 and btn ~= "LeftButton" or #live > 1 and IsShiftKeyDown and IsShiftKeyDown() then
      local items = { { text = "Live now", title = true } }
      for _, it in ipairs(live) do items[#items + 1] = { text = it.title or "Event", func = function() if it.onClick then it.onClick() end end } end
      UI:Menu(self, items); return
    end
    local it = live[1]
    if it and it.onClick then it.onClick() end
  end)
  lb:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  lb:Hide()
  main.liveBtn = lb

  -- section view: back + banner, tabs, content panel
  local sec = CreateFrame("Frame", nil, body); sec:SetAllPoints(); sec:Hide()
  main.section = sec
  local back = UI:Button(sec, "Home", 96, 34, function() showHome(true) end, "Back to the home screen")
  back:SetPoint("TOPLEFT", 0, 0)
  back.fs:ClearAllPoints(); back.fs:SetPoint("LEFT", 36, 0); back.fs:SetPoint("RIGHT", -10, 0)
  local arrow = UI:Icon(back, "left", 16, "OVERLAY"); arrow:SetPoint("LEFT", 14, 0)
  UI:Skin(arrow, function(self, th) self:SetVertexColor(C(th.gold)) end)
  main.banner = sec:CreateTexture(nil, "ARTWORK"); main.banner:SetPoint("TOPLEFT", back, "TOPRIGHT", 14, 0); main.banner:SetPoint("RIGHT", sec, "RIGHT", 0, 0); main.banner:SetHeight(34)
  main.bannerCap = {}
  for i, k in ipairs({ "TL", "L", "BL" }) do
    local tc = ({ TL = { 0, 0.375, 0, 0.375 }, L = { 0, 0.375, 0.375, 0.625 }, BL = { 0, 0.375, 0.625, 1 } })[k]
    local c = sec:CreateTexture(nil, "ARTWORK"); c:SetTexture(UI.MEDIA .. "UI\\rfill"); c:SetTexCoord(unpack(tc))
    main.bannerCap[k] = c
  end
  main.bannerCap.TL:SetPoint("TOPLEFT", back, "TOPRIGHT", 14, 0); main.bannerCap.TL:SetSize(7, 7)
  main.bannerCap.BL:SetPoint("TOPLEFT", main.bannerCap.TL, "BOTTOMLEFT", 0, -20); main.bannerCap.BL:SetSize(7, 7)
  main.bannerCap.L:SetPoint("TOPLEFT", main.bannerCap.TL, "BOTTOMLEFT"); main.bannerCap.L:SetPoint("BOTTOMRIGHT", main.bannerCap.BL, "TOPRIGHT")
  main.banner:ClearAllPoints(); main.banner:SetPoint("TOPLEFT", main.bannerCap.TL, "TOPRIGHT"); main.banner:SetPoint("RIGHT", sec, "RIGHT", 0, 0); main.banner:SetHeight(34)
  main.bannerEdge = sec:CreateTexture(nil, "OVERLAY"); main.bannerEdge:SetPoint("LEFT", main.bannerCap.L, "LEFT", 0, 0); main.bannerEdge:SetSize(4, 26)
  main.secName = sec:CreateFontString(nil, "OVERLAY"); UI:SetFont(main.secName, "head", FS(21)); main.secName:SetPoint("LEFT", main.banner, "LEFT", 11, 0)
  main.secLive = sec:CreateFontString(nil, "OVERLAY"); UI:SetFont(main.secLive, "body", FS(13)); main.secLive:SetPoint("LEFT", main.secName, "RIGHT", 14, -1)
  main.tabsHolder = CreateFrame("Frame", nil, sec)
  main.tabsHolder:SetPoint("TOPLEFT", 0, -42); main.tabsHolder:SetSize(BODY_W, 30)
  main.inset = UI:Panel(sec, BODY_W, S.CH + 18, { 0, 0, 0, 0.9 })
  main.inset:SetPoint("TOPLEFT", 0, -80)
  main.content = CreateFrame("Frame", nil, main.inset)
  main.content:SetSize(S.CW, S.CH)
  main.content:SetPoint("TOPLEFT", 4, -9)

  -- footer
  main.status = UI:Text(drawer, "", "muted", "RIGHT"); main.status:SetPoint("BOTTOMRIGHT", -22, 14)
  main.ver = UI:Text(drawer, "Command Center v" .. S.version, "muted"); main.ver:SetPoint("BOTTOMLEFT", 22, 14)

  main:SetScript("OnShow", function(self)
    if PlaySound and SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_OPEN then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN) end
    UI:Animate(self, "window")
    S:RequestRoster(); S:RefreshCurrent()
  end)
  main:SetScript("OnHide", function()
    if PlaySound and SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_CLOSE then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE) end
  end)
  UI:ApplyTheme()
  S:ApplyMainTheme()
  S:Fire("MAIN_CREATED", main)
end

-- section page tabs (underline style, like the preview)
local secTabs = {}
local function layoutTabs(sec, idx)
  local key = sec.id or sec.name
  local strip = secTabs[key]
  if not strip then
    local names = {}
    for _, pg in ipairs(sec.pages) do names[#names + 1] = pg[2] end
    strip = UI:SubTabs(main.tabsHolder, names, function(i)
      if strip.__quiet then return end
      local pg = sec.pages[i]
      if pg then S:SelectTab(pg[1], pg[3]) end
    end)
    strip:SetPoint("BOTTOMLEFT", 0, 2); strip:SetSize(BODY_W, 26)
    secTabs[key] = strip
  end
  for k, st in pairs(secTabs) do st:SetShown(k == key) end
  strip.__quiet = true; strip:Select(idx); strip.__quiet = false
  -- officer-only pages hidden for members
  for i, b in ipairs(strip.buttons) do
    local pg = sec.pages[i]
    local t = pg and S.tabsById[pg[1]]
    b:SetShown(not (t and t.opts.officer and not S:IsOfficer()))
  end
  -- close the gaps left by hidden pages
  local x, visible = 0, 0
  for _, b in ipairs(strip.buttons) do
    if b:IsShown() then b:ClearAllPoints(); b:SetPoint("BOTTOMLEFT", x, 0); x = x + (b:GetWidth() or 0) + 2; visible = visible + 1 end
  end
  strip:SetShown(visible > 1)
end

function S:SelectTab(id, sub)
  if not main then return end
  if S.QuickBarExpand then S:QuickBarExpand() end
  if not id or id == "home" then return showHome(true) end
  local alias = PAGE_ALIAS[id]
  if alias then id, sub = alias[1], alias[2] end
  local t = S.tabsById[id]
  if not t or (t.opts.officer and not S:IsOfficer()) then return showHome(true) end
  local sec, idx = sectionOf(id, sub)
  sec = sec or { name = t.label, pages = { { id, t.label } } }
  idx = idx or 1
  local changed = main.current ~= t
  -- (pages embedded inside another page are left to their host)
  for _, other in ipairs(S.tabs) do if other.panel and other ~= t and not other.embedded then other.panel:Hide() end end
  if not t.panel then
    t.panel = CreateFrame("Frame", nil, main.content)
    t.panel:SetAllPoints(main.content)
    local ok, err = pcall(t.build, t.panel)
    if not ok then S.report(err) end
  end
  main.home:Hide()
  local wasHome = main.view ~= "section"
  main.view = "section"
  main.section:Show()
  t.panel:Show()
  main.current = t
  main.sec = sec
  S.db.global.lastTab = t.id
  main.secName:SetText(sec.name)
  local ok, live = pcall(LIVE[sec.id] or function() return "" end)
  main.secLive:SetText(ok and live or "")
  main.crumb:SetText("Home  >  " .. sec.name .. (#sec.pages > 1 and ("  >  " .. sec.pages[idx][2]) or ""))
  layoutTabs(sec, idx)
  -- a page with one tab: the content panel moves up into the tabs' row
  main.inset:ClearAllPoints(); main.inset:SetPoint("TOPLEFT", 0, #sec.pages > 1 and -80 or -46)
  if not sub and t.opts.defaultSub then sub = t.opts.defaultSub() end
  if sub and t.panel.tabs and t.panel.tabs.Select then pcall(t.panel.tabs.Select, t.panel.tabs, sub) end
  if wasHome then UI:Animate(main.section, "page") elseif changed then UI:Animate(t.panel, "page") end
  S:RefreshCurrent()
end

local refreshPending = false
function S:RefreshCurrent(now)
  if not main or not main:IsShown() then return end
  if not now then
    if refreshPending then return end
    refreshPending = true
    C_Timer.After(0.25, function() refreshPending = false; S:RefreshCurrent(true) end)
    return
  end
  main.body:Show()
  main.guildLine:SetText(""); main.onlineText:SetText("")
  main.guildDot:Hide(); main.onlineGlow:Hide()
  if S.UpdateRankPlate then S:UpdateRankPlate() end
  if S.FitHeaderLine then S:FitHeaderLine() end
  if S.QuickBarTextChanged then S:QuickBarTextChanged() end
  main.status:SetText("")
  if main.msgBtn and main.msgBtn.badge then main.msgBtn.badge:SetCount(S.UnreadMail and S:UnreadMail() or 0) end
  if main.bellBtn and main.bellBtn.badge then main.bellBtn.badge:SetCount(S.UnreadNotifs and S:UnreadNotifs() or 0) end
  if main.view == "home" then
    refreshHome(false)
    return
  end
  local t = main.current
  if t and t.refresh and t.panel then
    local ok, err = pcall(t.refresh, t.panel)
    if not ok then S.report(err) end
  end
end

local function safe(fn, ...)
  local ok, err = xpcall(fn, function(e) return tostring(e) .. "\n" .. (debugstack and debugstack(2) or "") end, ...)
  if not ok then
    S.report(err)
    print("|cff4fd1c5Command Center|r window error: " .. tostring(err):match("^[^\n]*"))
  end
  return ok
end
S.SafeCall = safe

function S:ShowMain(id)
  if not main then safe(createMain) end
  if not main then return end
  local wasShown = main:IsShown()
  -- a bar holding the game's own menu buttons can't appear mid-combat
  if not wasShown and S.QuickBarLocked and S.QuickBarLocked() then
    -- say it once (login / reload in a fight asks several times), then open when the fight ends
    if not S.__mainPending then S:Print("Command Center opens after combat.") end
    S.__mainPending = { id = id }
    return
  end
  S.__mainPending = nil
  main:Show()
  if id then safe(S.SelectTab, S, id)
  elseif not wasShown or not main.view then safe(showHome, true, true) end
end
function S:ToggleMain()
  if main and main:IsShown() then main:Hide() else S:ShowMain() end
end
function S:MainShown() return main and main:IsShown() end
function S:CurrentTabId() return main and (main.view == "home" and "home" or (main.current and main.current.id)) end
function S:MainFrame() return main end

-- Refresh whenever synced data, the roster or permissions change.
S:Listen("STORE", function() S:RefreshCurrent() end)
S:Listen("ROSTER", function() S:RefreshCurrent() end)
S:Listen("ME_CHANGED", function() S:RefreshCurrent() end)
S:Listen("NOTIFY", function() S:RefreshCurrent() end)

---------------------------------------------------------------------------
-- Minimap button
---------------------------------------------------------------------------
local mm
local function placeMinimap()
  local deg = S.db.global.minimap.angle or 200
  local x, y
  if S.MinimapEdge then x, y = S.MinimapEdge(deg, 6)   -- follows the minimap's shape (Minimap.lua)
  else
    local a, r = math.rad(deg), (Minimap:GetWidth() / 2) + 6
    x, y = math.cos(a) * r, math.sin(a) * r
  end
  mm:ClearAllPoints()
  mm:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- right-click menu on the minimap button
function S:MinimapMenu(anchor)
  GameTooltip:Hide()
  local items = {
    { text = "Command Center", title = true },
    { text = "Open Command Center", func = function() S:ShowMain() end },
    { text = "Tools", func = function() if S.ShowTools then S:ShowTools() end end },
    { text = "Settings", func = function() S:ShowMain("settings") end },
    { text = "Messenger", func = function() if S.ShowMessenger then S:ShowMessenger() end end },
    { text = "Messenger settings", func = function() if S.ShowMessengerSettings then S:ShowMessengerSettings() end end },
    { text = "Minimap settings", func = function() if S.ShowMinimapSettings then S:ShowMinimapSettings() end end },
    { text = "Other", title = true },
    { text = "Mark notifications read", disabled = (S.UnreadNotifs and S:UnreadNotifs() or 0) == 0, func = function() S:MarkAllNotifs() end },
    { text = "Hide minimap button", func = function()
      S.db.global.minimap.hide = true; S:UpdateMinimap()
      S:Print("Minimap button hidden. Bring it back with |cffffff00/ccenter minimap|r or in Settings.")
    end },
  }
  UI:Menu(anchor, items)
end

function S:UpdateMinimap()
  if not mm then
    mm = CreateFrame("Button", "CC_Minimap", Minimap)
    mm:SetSize(31, 31); mm:SetFrameStrata("MEDIUM"); mm:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 8)
    local overlay = mm:CreateTexture(nil, "OVERLAY")
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder"); overlay:SetSize(53, 53); overlay:SetPoint("TOPLEFT")
    local icon = mm:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture(S.LOGO_ROUND or S.LOGO); icon:SetTexCoord(unpack(S.LOGO_COORDS)); icon:SetSize(21, 21); icon:SetPoint("TOPLEFT", 6, -5)
    S.mmBadge = UI:Badge(mm, 14)
    S.mmBadge:SetPoint("TOPRIGHT", 0, 0)
    if S.UpdateBadges then S:UpdateBadges() end
    mm:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    mm:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    mm:RegisterForDrag("LeftButton")
    mm:SetScript("OnClick", function(_, button)
      if button == "RightButton" then S:MinimapMenu(mm) else S:ToggleMain() end
    end)
    mm:SetScript("OnDragStart", function(self)
      self:SetScript("OnUpdate", function()
        local mx, my = Minimap:GetCenter()
        local cx, cy = GetCursorPosition()
        local s = Minimap:GetEffectiveScale()
        S.db.global.minimap.angle = math.deg(math.atan2(cy / s - my, cx / s - mx))
        placeMinimap()
      end)
    end)
    mm:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    mm:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_LEFT")
      GameTooltip:SetText("|cff" .. S.ACCENT_HEX .. "Command Center|r")
      local n = S.UnreadNotifs and S:UnreadNotifs() or 0
      if n > 0 then GameTooltip:AddLine(n .. " new notification" .. (n > 1 and "s" or ""), 1, 0.82, 0) end
      GameTooltip:AddLine("Left-click: open hub", 1, 1, 1)
      GameTooltip:AddLine("Right-click: menu (tools, settings, messenger)", 1, 1, 1)
      GameTooltip:AddLine("Drag: move button", 0.7, 0.7, 0.7)
      GameTooltip:Show()
    end)
    mm:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
  placeMinimap()
  -- with the minimap drawer on, the zone bar's box button carries this button's menu and badge
  local drawer = S.MinimapDrawerOn and S.MinimapDrawerOn()
  mm:SetShown(not S.db.global.minimap.hide and not drawer)
end

S:Listen("LOGIN", function() UI:ApplyTheme() end)
S:Listen("LOGIN", function() S:UpdateMinimap() end)
S:On("PLAYER_ENTERING_WORLD", function() if S.db then S:UpdateMinimap() end end)

S:AddCommand("minimap", "", "Show/hide the minimap button", function()
  S.db.global.minimap.hide = not S.db.global.minimap.hide
  S:UpdateMinimap()
end)


function S:UpdateRankPlate()
  local rp = main and main.rankPlate
  if not rp then return end
  do rp:Hide() return end
  local r, honor = S:FartRank(S.me)
  rp.icon:SetTexture(r.icon)
  rp.name:SetText("|cff9dff5e" .. r.name .. "|r")
  rp.honor:SetText(S.Commas(honor) .. " Fart Honor")
  rp:SetShown(not main.qbNoPlate)
end

-- (old header line fitting - the line is always empty now)
-- shrinks (with "...") to whatever room is left
function S:FitHeaderLine()
  if not main or not main.rankPlate or not main.guildLine or main.qbFixedLine then return end
  local gl, plate = main.guildLine, main.rankPlate
  gl:SetWidth(0)
  local want = gl:GetStringWidth() or 0
  if not gl:IsShown() then return end
  local left, stop = gl:GetLeft(), plate:IsShown() and plate:GetLeft() or (main.homeBtn and main.homeBtn:GetLeft())
  if not left or not stop then return end
  local tail = 8 + 5 + 8 + (main.onlineText:GetStringWidth() or 0) + 12
  local room = stop - left - tail
  gl:SetWordWrap(false)
  gl:SetWidth(math.max(30, math.min(want + 2, room)))
end


---------------------------------------------------------------------------
-- Live events (not used by Command Center; kept so older calls do nothing)
-- provider() returns a list of { title, sub, joined, onClick }.
---------------------------------------------------------------------------
S.liveProviders = {}
function S:AddLiveProvider() end
function S:LiveNow() return {} end
function S:UpdateLiveButton() if main and main.liveBtn then main.liveBtn:Hide() end end
-- keep it current while the window is open


S:On("PLAYER_REGEN_ENABLED", function()
  local p = S.__mainPending
  if p then C_Timer.After(0.2, function() if S.__mainPending then S:ShowMain(S.__mainPending.id) end end) end
end)
