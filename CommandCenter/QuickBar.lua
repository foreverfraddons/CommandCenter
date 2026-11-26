-- QuickBar: the bar along the top of the Command Center window.
--  * the arrow collapses the page under it, leaving just the quickbar
--  * the grip in the corner resizes it
--  * drag it to a screen edge and it snaps there; on the left / right edge it turns
--    vertical and the page slides out sideways
--  * drag the grip up / down to make it thinner (lower profile)
--  * Border mode: a thin bar flush along one whole screen edge; the rest of the UI
--    (minimap, buffs, action bars...) moves out of its way
--  * Dock mode (Settings) turns it into a RocketDock / macOS style dock with every
--    module, and any tools you put in it (one icon per tool: dock OR shortcut)
local _, S = ...
local UI = S.UI

local main
local userClosed = false     -- closed on purpose: the login check leaves it closed
local HEAD_H = 68
local BAR_H = HEAD_H + 6        -- thickness of the horizontal bar
local BAR_V = 78                -- thickness of the vertical bar
local GAP = 6                   -- space between the bar and the page
local SNAP = 48                 -- how close to an edge snaps
local MIN_LEN_H, MIN_LEN_V = 430, 450
local DOCK_MIN, DOCK_MAX = 28, 64
local DOCK_GAP, DOCK_PAD, DOCK_SEP = 8, 12, 14

local function C(c, a) return c[1], c[2], c[3], a or 1 end
local function clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end
-- one icon-spacing setting for the dock and the border bar
local function dockGap() local v = S.db and S.db.global.iconSpacing; return v and clamp(v, 0, 40) or 8 end
local THICK_MIN_H, THICK_MIN_V = 26, 36           -- thinnest normal bar
local BORDER_MIN, BORDER_MAX, BORDER_DEF = 18, 40, 24
local function isDock() return S.db.global.dockMode and true or false end
local function isBorder() return S.db.global.borderMode and not S.db.global.dockMode and true or false end
-- Blizzard menu / bag buttons in the bar are secure buttons: while they exist the bar
-- can't be moved, resized, shown or hidden during combat (the game forbids it), so any
-- such change waits until combat ends.
local hasSecure = false
local freestyle, freeSpot          -- (border bar freestyle helpers, defined further down)
local pendingLayout = false
local function combatLocked() return hasSecure and InCombatLockdown and InCombatLockdown() and true or false end
local function lockedMsg() S:Print("That has to wait until you're out of combat.") end
S.QuickBarLocked = function() return combatLocked() end

-- saved layout: one for the bar, one for the dock
local function cfg()
  local g = S.db.global
  local key = isDock() and "qbDock" or isBorder() and "qbBorder" or "qb"
  if type(g[key]) ~= "table" then g[key] = {} end
  local q = g[key]
  if q.edge ~= "left" and q.edge ~= "right" and q.edge ~= "top" and q.edge ~= "bottom" then q.edge = key == "qbBorder" and "top" or "free" end
  return q
end
local function isVertical() local e = cfg().edge; return e == "left" or e == "right" end
S.QuickBarConfig = cfg

local function screen()
  local us, ms = UIParent:GetEffectiveScale() or 1, main:GetEffectiveScale() or 1
  return (UIParent:GetWidth() or 1920) * us / ms, (UIParent:GetHeight() or 1080) * us / ms
end
local function cursor()
  local x, y = GetCursorPosition()
  local es = main:GetEffectiveScale() or 1
  return x / es, y / es
end

---------------------------------------------------------------------------
-- Tools in the dock (no duplicates: a tool is in the dock OR has a shortcut)
---------------------------------------------------------------------------
local BUILTIN = { Messenger = true }       -- tools the dock always has
local function dockTools()
  local g = S.db.global
  g.dockTools = type(g.dockTools) == "table" and g.dockTools or {}
  return g.dockTools
end
function S:DockBuiltIn(label) return BUILTIN[label] or false end
function S:DockHasTool(label)
  if BUILTIN[label] then return true end
  for _, l in ipairs(dockTools()) do if l == label then return true end end
  return false
end
function S:AddToolToDock(label)
  if S:DockHasTool(label) then return end
  if S.HasToolShortcut and S:HasToolShortcut(label) then S:DeleteToolShortcut(label, true) end
  table.insert(dockTools(), label)
  S:QuickBarLayout()
end
function S:RemoveToolFromDock(label)
  local l = dockTools()
  for i = #l, 1, -1 do if l[i] == label then table.remove(l, i) end end
  S:QuickBarLayout()
end

---------------------------------------------------------------------------
-- The page (drawer): which side it opens on, sliding in and out
---------------------------------------------------------------------------
local ANG = { up = 0, left = math.pi / 2, down = math.pi, right = -math.pi / 2 }
local OPP = { up = "down", down = "up", left = "right", right = "left" }
local SLIDE = 26

local function drawerSide()
  local e = cfg().edge
  if e == "left" then return "right" elseif e == "right" then return "left"
  elseif e == "bottom" then return "up" elseif e == "top" then return "down" end
  -- free: open downwards unless there's no room below
  local b, t = main:GetBottom(), main:GetTop()
  local dh = main.drawer:GetHeight() or 600
  if b and b - GAP - dh < 0 then
    local _, sh = screen()
    if (t or 0) + GAP + dh <= sh then return "up" end
  end
  return "down"
end

---------------------------------------------------------------------------
-- Dock: pages and windows come out of the icon you clicked and get sucked back
-- into it. A tiny anchor sits just past that icon; the page / window is pinned to
-- it by one point and scaled up from almost nothing (scaling shrinks toward the
-- pinned point, so it grows out of the icon).
---------------------------------------------------------------------------
-- which way things come out of the dock, and the point just past the clicked icon
local function dockSide()
  local e = cfg().edge
  if e == "left" then return "right" elseif e == "right" then return "left" elseif e == "top" then return "down" elseif e == "bottom" then return "up" end
  local b = main:GetBottom()
  local _, sh = screen()
  return (b and b > sh / 2) and "down" or "up"
end
local OUT_POINT = { up = "BOTTOM", down = "TOP", right = "LEFT", left = "RIGHT" }
local function setDockFocus(icon)
  if not icon or not main.dockAnchor then return end
  local ix, iy = icon:GetCenter()
  local l, t = main:GetLeft(), main:GetTop()
  if not (ix and l) then return end
  local a = main.dockAnchor
  a:ClearAllPoints()
  local side = dockSide()
  if side == "up" then a:SetPoint("CENTER", main, "TOPLEFT", ix - l, GAP)
  elseif side == "down" then a:SetPoint("CENTER", main, "BOTTOMLEFT", ix - l, -GAP)
  elseif side == "right" then a:SetPoint("CENTER", main, "TOPRIGHT", GAP, iy - t)
  else a:SetPoint("CENTER", main, "TOPLEFT", -GAP, iy - t) end
  main.dockFocus = icon
end
local GENIE_TIME = 0.22
-- The page / window itself is never scaled (its layout would be worked out at the
-- wrong size). A plain "ghost" panel the same shape does the growing and shrinking;
-- the real thing appears when the ghost has finished growing, and hides as it starts
-- to shrink.
local genies = {}
local genieDriver
local ghostPool = {}
local function ease2(k) k = math.max(0, math.min(1, k)); return 1 - (1 - k) * (1 - k) end
local function getGhost()
  for _, g in ipairs(ghostPool) do if not g.busy then return g end end
  local g = CreateFrame("Frame", nil, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  g:SetFrameStrata("DIALOG")
  UI:Skin(g, function(self, th) UI.Flat(self, th.bg, 0.92, th.gold, 0.9, 1) end)
  g.glow = g:CreateTexture(nil, "BACKGROUND", nil, -1); g.glow:SetTexture(UI.ART.glow); g.glow:SetBlendMode("ADD")
  g.glow:SetPoint("TOPLEFT", -14, 14); g.glow:SetPoint("BOTTOMRIGHT", 14, -14)
  UI:Skin(g.glow, function(self, th) self:SetVertexColor(th.gold[1], th.gold[2], th.gold[3], 0.35) end)
  g:Hide()
  ghostPool[#ghostPool + 1] = g
  return g
end
local function runGenies(_, el)
  local any = false
  for f, st in pairs(genies) do
    any = true
    st.t = math.min(1, st.t + el / GENIE_TIME)
    local k = ease2(st.t)
    local p = st.opening and k or (1 - k)
    local gh = st.ghost
    gh:SetSize(math.max(8, 14 + (st.w - 14) * p), math.max(8, 14 + (st.h - 14) * p))
    if (st.ox or 0) ~= 0 or (st.oy or 0) ~= 0 then
      gh:ClearAllPoints(); gh:SetPoint(OUT_POINT[dockSide()], main.dockAnchor, "CENTER", st.ox * p, st.oy * p)
    end
    gh:SetAlpha(0.35 + 0.65 * (st.opening and k or (1 - k * 0.6)))
    if st.t >= 1 then
      genies[f] = nil
      gh:Hide(); gh.busy = false
      if st.opening then f:SetAlpha(1) else f:Hide(); f:SetAlpha(1) end
      if st.done then pcall(st.done) end
    end
  end
  if not any then genieDriver:Hide() end
end
local function genie(f, opening, done)
  if not genieDriver then genieDriver = CreateFrame("Frame"); genieDriver:SetScript("OnUpdate", runGenies) end
  local cur = genies[f]
  if cur then cur.ghost:Hide(); cur.ghost.busy = false; genies[f] = nil end
  if UI:AnimLevel() == "minimal" or not main.dockAnchor then
    if opening then f:SetAlpha(1); f:Show() else f:Hide() end
    if done then pcall(done) end
    return
  end
  if opening then f:Show() end
  f:SetAlpha(0)                                  -- the ghost stands in while it moves
  local us = UIParent:GetEffectiveScale() or 1
  local fs = f:GetEffectiveScale() or us
  local w, h = (f:GetWidth() or 300) * fs / us, (f:GetHeight() or 200) * fs / us
  local gh = getGhost()
  gh.busy = true
  -- the ghost slides the same way the real frame was nudged to stay on screen
  local ox, oy = (f.__pinDX or 0) / us, (f.__pinDY or 0) / us
  local gs = gh:GetEffectiveScale() or us
  ox, oy = ox * us / gs, oy * us / gs
  gh:ClearAllPoints(); gh:SetPoint(OUT_POINT[dockSide()], main.dockAnchor, "CENTER", opening and 0 or ox, opening and 0 or oy)
  gh:SetSize(opening and 14 or w, opening and 14 or h)
  gh:Show()
  genies[f] = { opening = opening, t = 0, w = w, h = h, ghost = gh, done = done, ox = ox, oy = oy }
  genieDriver:Show()
end
local function genieBusy(f) return genies[f] ~= nil and not genies[f].opening end

-- pin a frame to the anchor so it grows out of the icon
-- How far (in screen pixels) a frame of w x h pixels pinned to the icon has to slide
-- to stay fully on screen. An icon near the top or bottom of a side bar would
-- otherwise push half the panel off the edge.
local SCREEN_MARGIN = 8
local screenShift
-- windows coming out of the dock keep a little distance from its icons, so clicks near
-- a window's top edge don't land on a dock icon
local DOCK_GAP = 16
local GAP_DIR = { up = { 0, 1 }, down = { 0, -1 }, left = { -1, 0 }, right = { 1, 0 } }
local function dockShift(wpx, hpx)
  local a = main and main.dockAnchor
  if not a or not a.GetCenter then return 0, 0 end
  local ax, ay = a:GetCenter()
  if not ax or not ay then return 0, 0 end
  local as = a:GetEffectiveScale() or 1
  local side = dockSide()
  local g = (GAP_DIR[side] or { 0, 0 })
  local gap = DOCK_GAP * (UIParent:GetEffectiveScale() or 1)
  local px, py = ax * as + g[1] * gap, ay * as + g[2] * gap
  local dx, dy = screenShift(px, py, side, wpx, hpx)
  return dx + g[1] * gap, dy + g[2] * gap
end
-- (ax, ay) and sizes in screen pixels; side = which way the frame grows from the point
screenShift = function(ax, ay, side, wpx, hpx)
  local us = UIParent:GetEffectiveScale() or 1
  local W = (GetScreenWidth and GetScreenWidth() or UIParent:GetWidth() or 0) * us
  local H = (GetScreenHeight and GetScreenHeight() or UIParent:GetHeight() or 0) * us
  if W <= 0 or H <= 0 then return 0, 0 end
  local left, bottom
  if side == "right" then left, bottom = ax, ay - hpx / 2
  elseif side == "left" then left, bottom = ax - wpx, ay - hpx / 2
  elseif side == "up" then left, bottom = ax - wpx / 2, ay
  else left, bottom = ax - wpx / 2, ay - hpx end
  local m = SCREEN_MARGIN * us
  local function fit(v, size, total)
    if size >= total - 2 * m then return m end
    return math.max(m, math.min(v, total - m - size))
  end
  return fit(left, wpx, W) - left, fit(bottom, hpx, H) - bottom
end

local function pinToDock(f)
  local fs = f:GetEffectiveScale() or 1
  local dx, dy = dockShift((f:GetWidth() or 0) * fs, (f:GetHeight() or 0) * fs)
  f.__pinDX, f.__pinDY = dx, dy                  -- screen pixels, for the ghost
  f:ClearAllPoints()
  f:SetPoint(OUT_POINT[dockSide()], main.dockAnchor, "CENTER", dx / fs, dy / fs)
end
S.QuickBarGenie = function(f, opening, done) genie(f, opening, done) end

-- Put a pop-up panel next to a bar icon, on the side away from the screen edge the
-- bar sits on, and keep it on screen. In dock mode the dock does this itself.
local EDGE_POINT = { up = "TOP", down = "BOTTOM", right = "RIGHT", left = "LEFT" }
function S:QuickBarPlace(f, key, btn)
  if not main or not f then return false end
  if isDock() and main.dockFocus and main.dockAnchor and f.__fromDock then pinToDock(f) return true end
  btn = (S.QuickBarIcon and S:QuickBarIcon(key)) or btn
  if not btn or not btn:IsShown() then return false end
  local bx, by = btn:GetCenter()
  if not bx then return false end
  local bs = btn:GetEffectiveScale() or 1
  local us = UIParent:GetEffectiveScale() or 1
  local W = (GetScreenWidth and GetScreenWidth() or UIParent:GetWidth() or 0) * us
  local H = (GetScreenHeight and GetScreenHeight() or UIParent:GetHeight() or 0) * us
  bx, by = bx * bs, by * bs
  local side
  if isVertical() then side = (bx < W / 2) and "right" or "left"
  else side = (by > H / 2) and "down" or "up" end
  local bw, bh = (btn:GetWidth() or 0) * bs, (btn:GetHeight() or 0) * bs
  local GAP = 14 * us
  local ax, ay = bx, by
  if side == "down" then ay = by - bh / 2 - GAP elseif side == "up" then ay = by + bh / 2 + GAP
  elseif side == "right" then ax = bx + bw / 2 + GAP else ax = bx - bw / 2 - GAP end
  local fs = f:GetEffectiveScale() or 1
  local dx, dy = screenShift(ax, ay, side, (f:GetWidth() or 0) * fs, (f:GetHeight() or 0) * fs)
  local gx, gy = ax - bx, ay - by                        -- anchor offset from the button centre, pixels
  f:ClearAllPoints()
  f:SetPoint(OUT_POINT[side], btn, "CENTER", (gx + dx) / fs, (gy + dy) / fs)
  return true
end

local function anchorDrawer(off)
  off = off or 0
  local d = main.drawer
  local side = drawerSide()
  d:ClearAllPoints()
  if isDock() and main.dockFocus and main.dockAnchor then
    pinToDock(d)
    main.drawerSide = dockSide()
    return
  end
  if side == "down" or side == "up" then
    local sw = screen()
    local dw = d:GetWidth() or 800
    local left, right = main:GetLeft() or 0, main:GetRight() or 0
    local p1, p2 = side == "down" and "TOP" or "BOTTOM", side == "down" and "BOTTOM" or "TOP"
    local y = side == "down" and (-GAP + off) or (GAP - off)
    if isDock() or isBorder() then
      d:SetPoint(p1, main, p2, 0, y)
    elseif left + dw > sw and right - dw >= 0 then
      d:SetPoint(p1 .. "RIGHT", main, p2 .. "RIGHT", 0, y)
    else
      d:SetPoint(p1 .. "LEFT", main, p2 .. "LEFT", 0, y)
    end
  elseif side == "right" then
    local c = isDock() or isBorder()
    d:SetPoint(c and "LEFT" or "TOPLEFT", main, c and "RIGHT" or "TOPRIGHT", GAP - off, 0)
  else
    local c = isDock() or isBorder()
    d:SetPoint(c and "RIGHT" or "TOPRIGHT", main, c and "LEFT" or "TOPLEFT", -GAP + off, 0)
  end
  main.drawerSide = side
end

local anim   -- { dir = 1 opening / -1 closing, p = 0..1 }
local function drawerOpen() return main and main.drawer:IsShown() and not (anim and anim.dir < 0) and not genieBusy(main.drawer) end
S.QuickBarOpen = function() return drawerOpen() end

local function arrowTarget()
  local side = main.drawerSide or drawerSide()
  -- open: points back at the bar (that's where it collapses to); closed: where the page comes out
  if drawerOpen() then return ANG[OPP[side]] end
  return ANG[side]
end

local function finishAnim()
  local d = main.drawer
  if not anim then return end
  if anim.dir < 0 then anim = nil; d:Hide() else anim = nil end
  d:SetAlpha(1); anchorDrawer(0)
end

local function animate(dir)
  local d = main.drawer
  -- dock: out of the icon / back into it
  if isDock() and main.dockFocus then
    anim = nil
    anchorDrawer(0)
    if dir > 0 then genie(d, true) else genie(d, false) end
    return
  end
  if UI:AnimLevel() == "minimal" then
    anim = nil
    if dir > 0 then anchorDrawer(0); d:SetAlpha(1); d:Show() else d:Hide() end
    return
  end
  local p = anim and anim.p or (dir > 0 and 0 or 1)
  anim = { dir = dir, p = p }
  if dir > 0 and not d:IsShown() then d:SetAlpha(0); anchorDrawer(SLIDE); d:Show() end
end

function S:QuickBarExpand()
  if not main then return end
  S.db.global.qbCollapsed = false
  if drawerOpen() then return end
  animate(1)
end
function S:QuickBarCollapse()
  if not main then return end
  S.db.global.qbCollapsed = true
  if not main.drawer:IsShown() then return end
  animate(-1)
end
function S:QuickBarToggle()
  if drawerOpen() then S:QuickBarCollapse() else S:QuickBarExpand() end
end

---------------------------------------------------------------------------
-- Placement and snapping
---------------------------------------------------------------------------
local function place()
  local q = cfg()
  local sw, sh = screen()
  local W, H = main:GetWidth(), main:GetHeight()
  main:ClearAllPoints()
  if isBorder() then
    -- pinned to the real screen edge (WorldFrame), outside the shrunken UIParent
    local W = WorldFrame or UIParent
    if q.edge == "bottom" then main:SetPoint("BOTTOMLEFT", W, "BOTTOMLEFT"); main:SetPoint("BOTTOMRIGHT", W, "BOTTOMRIGHT")
    elseif q.edge == "left" then main:SetPoint("TOPLEFT", W, "TOPLEFT"); main:SetPoint("BOTTOMLEFT", W, "BOTTOMLEFT")
    elseif q.edge == "right" then main:SetPoint("TOPRIGHT", W, "TOPRIGHT"); main:SetPoint("BOTTOMRIGHT", W, "BOTTOMRIGHT")
    else main:SetPoint("TOPLEFT", W, "TOPLEFT"); main:SetPoint("TOPRIGHT", W, "TOPRIGHT") end
    return
  end
  if isDock() then
    if q.edge == "bottom" then main:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", q.c or sw / 2, 0)
    elseif q.edge == "top" then main:SetPoint("TOP", UIParent, "TOPLEFT", q.c or sw / 2, 0)
    elseif q.edge == "left" then main:SetPoint("LEFT", UIParent, "BOTTOMLEFT", 0, q.c or sh / 2)
    elseif q.edge == "right" then main:SetPoint("RIGHT", UIParent, "BOTTOMRIGHT", 0, q.c or sh / 2)
    else main:SetPoint("CENTER", UIParent, "BOTTOMLEFT", q.x or sw / 2, q.y or 90) end
    return
  end
  if q.edge == "left" then main:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, -(q.pos or 120))
  elseif q.edge == "right" then main:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", 0, -(q.pos or 120))
  elseif q.edge == "top" then main:SetPoint("TOPLEFT", UIParent, "TOPLEFT", q.pos or math.floor((sw - W) / 2), 0)
  elseif q.edge == "bottom" then main:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", q.pos or math.floor((sw - W) / 2), 0)
  elseif q.x and q.y then main:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", q.x, q.y)
  else
    -- first time: bar + page centred on screen, like the old window
    local total = H + GAP + (main.drawer:GetHeight() or 600)
    main:SetPoint("TOP", UIParent, "TOP", 0, -math.max(20, math.floor((sh - total) / 2)))
  end
end

-- which screen edge (if any) the bar is close enough to snap to
local function snapEdge()
  local l, r, t, b = main:GetLeft(), main:GetRight(), main:GetTop(), main:GetBottom()
  if not (l and r and t and b) then return "free" end
  local sw, sh = screen()
  local best, bd = "free", SNAP
  for _, e in ipairs({ "left", "right", "top", "bottom" }) do
    local d = (e == "left" and l) or (e == "right" and sw - r) or (e == "top" and sh - t) or b
    if d < bd then best, bd = e, d end
  end
  return best, l, r, t, b, sw, sh
end
S.QuickBarSnapEdge = function() return (snapEdge()) end

-- a glowing strip on the edge you're about to snap to
local hint
local function showHint(e)
  if not hint then
    hint = CreateFrame("Frame", nil, UIParent); hint:SetFrameStrata("TOOLTIP")
    hint.bar = hint:CreateTexture(nil, "OVERLAY"); hint.bar:SetAllPoints()
    hint.glow = hint:CreateTexture(nil, "ARTWORK"); hint.glow:SetTexture(UI.ART.glow); hint.glow:SetBlendMode("ADD")
    hint.glow:SetPoint("TOPLEFT", -24, 24); hint.glow:SetPoint("BOTTOMRIGHT", 24, -24)
    hint.text = UI:Text(hint, "", "small", "CENTER")
  end
  if not e or e == "free" then hint:Hide() return end
  local th = UI:Theme()
  hint.bar:SetColorTexture(th.gold[1], th.gold[2], th.gold[3], 0.75)
  hint.glow:SetVertexColor(th.gold[1], th.gold[2], th.gold[3], 0.5)
  hint:ClearAllPoints(); hint.text:ClearAllPoints()
  if e == "left" or e == "right" then
    hint:SetPoint("TOP" .. e:upper(), WorldFrame or UIParent, "TOP" .. e:upper()); hint:SetPoint("BOTTOM" .. e:upper(), WorldFrame or UIParent, "BOTTOM" .. e:upper()); hint:SetWidth(5)
    hint.text:SetPoint(e == "left" and "LEFT" or "RIGHT", hint, e == "left" and "RIGHT" or "LEFT", e == "left" and 10 or -10, 0)
    hint.text:SetText("|cffffd100Snap: vertical|r")
  else
    hint:SetPoint(e:upper() .. "LEFT", WorldFrame or UIParent, e:upper() .. "LEFT"); hint:SetPoint(e:upper() .. "RIGHT", WorldFrame or UIParent, e:upper() .. "RIGHT"); hint:SetHeight(5)
    hint.text:SetPoint(e == "top" and "TOP" or "BOTTOM", hint, e == "top" and "BOTTOM" or "TOP", 0, e == "top" and -10 or 10)
    hint.text:SetText("|cffffd100Snap: " .. e .. "|r")
  end
  hint:Show()
end

-- border mode: the bar never leaves the edge; you point at the edge you want
local function cursorEdge()
  local x, y = cursor()
  local sw, sh = screen()
  local best, bd = "top", math.huge
  for _, e in ipairs({ "top", "bottom", "left", "right" }) do
    local d = (e == "left" and x) or (e == "right" and sw - x) or (e == "top" and sh - y) or y
    if d < bd then best, bd = e, d end
  end
  return best
end
local function currentHintEdge() return isBorder() and cursorEdge() or snapEdge() end

local function startDrag()
  if main.qbSizing then return end
  if combatLocked() then lockedMsg() return end
  main.qbDragging = true
  if isBorder() then return end
  main:StartMoving()
end
local function stopDrag()
  if not main.qbDragging then return end
  main.qbDragging = false
  if isBorder() then
    showHint(nil)
    cfg().edge = cursorEdge()
    S:QuickBarLayout()
    return
  end
  main:StopMovingOrSizing()
  if main.SetUserPlaced then main:SetUserPlaced(false) end
  showHint(nil)
  local e, l, r, t, b, sw, sh = snapEdge()
  if not l then return end
  local q = cfg()
  q.edge = e
  if isDock() then
    if e == "top" or e == "bottom" then q.c = math.floor((l + r) / 2)
    elseif e == "left" or e == "right" then q.c = math.floor((t + b) / 2)
    else q.x, q.y = math.floor((l + r) / 2), math.floor((t + b) / 2) end
  else
    if e == "left" or e == "right" then q.pos = math.max(0, math.floor(sh - t))
    elseif e == "top" or e == "bottom" then q.pos = math.max(0, math.floor(l))
    else q.x, q.y = math.floor(l), math.floor(t) end
  end
  S:QuickBarLayout()
end
S.QuickBarStartDrag, S.QuickBarStopDrag = startDrag, stopDrag

---------------------------------------------------------------------------
-- Bar layouts
---------------------------------------------------------------------------
local function headerElems()
  return { main.crest, main.titleText, main.crumb, main.guildLine, main.guildDot, main.onlineText, main.onlineGlow,
    main.rankPlate, main.homeBtn, main.msgBtn, main.bellBtn, main.gearBtn, main.toolsBtn, main.qbArrow }
end
local function plateWide(wide, size)
  local rp = main.rankPlate
  if not rp then return end
  rp.icon:ClearAllPoints()
  if wide then
    rp:SetSize(170, 44); rp.icon:SetSize(42, 42); rp.icon:SetPoint("LEFT", 0, 0); rp.name:Show(); rp.honor:Show()
  else
    size = size or 44
    rp:SetSize(size, size); rp.icon:SetSize(size - 2, size - 2); rp.icon:SetPoint("CENTER"); rp.name:Hide(); rp.honor:Hide()
  end
end
local function headerFill()
  main.header:ClearAllPoints()
  local t = math.min(main:GetWidth() or 80, main:GetHeight() or 80)
  local inset = t < 50 and 2 or 6
  main.header:SetPoint("TOPLEFT", 2, -math.min(8, inset + 2))
  main.header:SetPoint("BOTTOMRIGHT", -2, inset)
end
-- header buttons shrink with the bar
local function sizeButtons(s)
  for _, b in ipairs({ main.qbArrow, main.homeBtn, main.msgBtn, main.bellBtn, main.gearBtn, main.toolsBtn }) do
    b:SetSize(s, s); b.icon:SetSize(math.floor(s * 0.5), math.floor(s * 0.5))
  end
  local c = math.min(24, s)
  main.close:SetSize(c, c)
  return c
end
local function sizeCrest(cs)
  main.crest:SetSize(cs, cs)
end

-- horizontal bar: len wide, t thick (74 = full size; thinner drops the breadcrumb, then the title)
local function layoutHorizontal(len, t)
  t = t or BAR_H
  main:SetSize(len, t)
  for _, f in ipairs(headerElems()) do f:Show() end
  main.close:Show()
  local full = t >= 64
  local s = full and 40 or clamp(math.floor(t * 0.54), 16, 40)
  local cs = clamp(math.floor(t * 0.65), 16, 48)
  local gap = s >= 34 and 8 or 4
  local closeW = sizeButtons(s)
  sizeCrest(cs)
  local pad = full and 18 or 8
  main.crest:ClearAllPoints(); main.crest:SetPoint("LEFT", pad, 0)
  main.close:ClearAllPoints()
  if full then main.close:SetPoint("TOPRIGHT", -6, -6) else main.close:SetPoint("RIGHT", -18, 0) end
  main.qbArrow:ClearAllPoints(); main.qbArrow:SetPoint("RIGHT", main, "RIGHT", full and -38 or -(18 + closeW + 6), 0)
  local chain = { main.qbArrow, main.toolsBtn, main.gearBtn, main.bellBtn, main.msgBtn, main.homeBtn }
  for i = 2, #chain do chain[i]:ClearAllPoints(); chain[i]:SetPoint("RIGHT", chain[i - 1], "LEFT", -gap, 0) end
  -- rank plate: name + honor when there's height for it, otherwise just the emblem
  local wide = t >= 56
  local p = math.min(t - 6, s + 6)
  plateWide(wide, p)
  main.rankPlate:ClearAllPoints(); main.rankPlate:SetPoint("RIGHT", main.homeBtn, "LEFT", wide and -14 or -gap, (full and 4 or 0))
  local cluster = (full and 38 or (24 + closeW)) + #chain * (s + gap)
  local left = pad + cs + 12
  local plateW = wide and 184 or (p + gap)
  local mode = t >= 64 and "full" or t >= 40 and "mid" or "line"
  local textW = mode == "line" and 120 or 110
  local showTitle = len >= left + textW + cluster
  local showPlate = len >= left + (showTitle and (textW + 40) or 0) + plateW + cluster
  main.qbNoPlate = not showPlate
  main.qbNoGuild = not showTitle
  main.titleText:ClearAllPoints(); main.crumb:ClearAllPoints(); main.guildLine:ClearAllPoints()
  if mode == "full" then
    main.titleText:SetPoint("TOPLEFT", main.crest, "TOPRIGHT", 14, -4)
    main.crumb:SetPoint("TOPLEFT", main.titleText, "BOTTOMLEFT", 0, -9)
    main.crumb:SetPoint("RIGHT", showPlate and main.rankPlate or main.homeBtn, "LEFT", -12, 0)
    main.guildLine:SetPoint("BOTTOMLEFT", main.titleText, "BOTTOMRIGHT", 12, 3)
  elseif mode == "mid" then
    main.titleText:SetPoint("LEFT", main.crest, "RIGHT", 10, 0)
    main.guildLine:SetPoint("BOTTOMLEFT", main.titleText, "BOTTOMRIGHT", 12, 3)
  else
    main.guildLine:SetPoint("LEFT", main.crest, "RIGHT", 10, 0)
  end
  main.onlineText:ClearAllPoints(); main.onlineText:SetPoint("LEFT", main.guildDot, "RIGHT", 8, 0)
  main.onlineText:SetJustifyH("LEFT")
  for _, f in ipairs({ main.guildLine, main.guildDot, main.onlineText, main.onlineGlow }) do f:SetShown(showTitle) end
  main.titleText:SetShown(showTitle and mode ~= "line")
  main.crumb:SetShown(showTitle and mode == "full")
  if showTitle and not S.G then main.guildDot:Hide(); main.onlineGlow:Hide() end
  if S.UpdateRankPlate then S:UpdateRankPlate() end
  headerFill()
end

-- vertical bar: len tall, w wide
local function layoutVertical(len, w)
  w = w or BAR_V
  main:SetSize(w, len)
  for _, f in ipairs(headerElems()) do f:Show() end
  main.close:Show()
  main.qbNoPlate, main.qbNoGuild = false, true
  local s = clamp(math.floor(w * 0.52), 16, 40)
  local cs = clamp(w - 30, 16, 48)
  local closeW = sizeButtons(s)
  sizeCrest(cs)
  main.close:ClearAllPoints()
  if w >= 56 then main.close:SetPoint("TOPRIGHT", -3, -3) else main.close:SetPoint("TOP", 0, -3) end
  local crestY = w >= 56 and 26 or (closeW + 6)
  main.crest:ClearAllPoints(); main.crest:SetPoint("TOP", 0, -crestY)
  for _, f in ipairs({ main.titleText, main.crumb, main.guildLine, main.guildDot }) do f:Hide() end
  local online = w >= 60 and S.G ~= nil
  main.onlineText:ClearAllPoints(); main.onlineText:SetPoint("TOP", main.crest, "BOTTOM", 0, -6); main.onlineText:SetJustifyH("CENTER")
  main.onlineText:SetShown(online); main.onlineGlow:SetShown(online)
  plateWide(false, math.min(w - 8, s + 6))
  if S.UpdateRankPlate then S:UpdateRankPlate() end
  local items = { main.qbArrow, main.homeBtn, main.msgBtn, main.bellBtn, main.gearBtn, main.toolsBtn }
  if main.rankPlate:IsShown() then items[#items + 1] = main.rankPlate end
  local y0, hsum = crestY + cs + (online and 20 or 0) + 8, 0
  for _, f in ipairs(items) do hsum = hsum + (f:GetHeight() or 40) end
  local gap = clamp(math.floor((len - y0 - 24 - hsum) / math.max(1, #items - 1)), 4, 36)
  local y = -y0
  for _, f in ipairs(items) do
    f:ClearAllPoints(); f:SetPoint("TOP", main, "TOP", 0, y)
    y = y - (f:GetHeight() or 40) - gap
  end
  headerFill()
end

---------------------------------------------------------------------------
-- Border mode: shrink UIParent away from the bar's edge so everything that
-- hangs off that edge (minimap, buffs, bars, chat...) moves out of the way.
-- Only out of combat; a change during combat waits for combat to end.
---------------------------------------------------------------------------
local uiOrig, uiShift, uiPending
local function setUIShift(edge, amount)
  if InCombatLockdown and InCombatLockdown() then uiPending = { edge = edge, amount = amount } return end
  uiPending = nil
  if not edge and not uiShift then return end
  if edge and uiShift and uiShift.edge == edge and math.abs(uiShift.amount - amount) < 0.5 then return end
  if not uiOrig then
    uiOrig = {}
    for i = 1, (UIParent:GetNumPoints() or 0) do
      local pt = { UIParent:GetPoint(i) }
      if pt[1] then uiOrig[#uiOrig + 1] = pt end
    end
  end
  local rel = uiOrig[1] and uiOrig[1][2] or nil
  UIParent:ClearAllPoints()
  if not edge then
    if #uiOrig > 0 then for _, pt in ipairs(uiOrig) do UIParent:SetPoint(unpack(pt)) end
    else UIParent:SetPoint("TOPLEFT", rel, "TOPLEFT", 0, 0); UIParent:SetPoint("BOTTOMRIGHT", rel, "BOTTOMRIGHT", 0, 0) end
    uiShift = nil
    return
  end
  local L, R, T, B = 0, 0, 0, 0
  if edge == "top" then T = amount elseif edge == "bottom" then B = amount elseif edge == "left" then L = amount else R = amount end
  UIParent:SetPoint("TOPLEFT", rel, "TOPLEFT", L, -T)
  UIParent:SetPoint("BOTTOMRIGHT", rel, "BOTTOMRIGHT", -R, B)
  uiShift = { edge = edge, amount = amount }
end
S.QuickBarUIShift = function() return uiShift, uiPending end
local function updateUIShift()
  if main and isBorder() and main:IsShown() then
    local th = isVertical() and main:GetWidth() or main:GetHeight()
    setUIShift(cfg().edge, (th or BORDER_DEF) * (main:GetScale() or 1))
  else
    setUIShift(nil)
  end
end
S:On("PLAYER_REGEN_ENABLED", function()
  if uiPending then local p = uiPending; setUIShift(p.edge, p.amount) end
  if pendingLayout and main then C_Timer.After(0, function() S:QuickBarLayout() end) end
end)

---------------------------------------------------------------------------
-- Dock
---------------------------------------------------------------------------
local icons, seps = {}, {}
local dockList = {}
local QMARK = "Interface\\Icons\\INV_Misc_QuestionMark"

local function sectionBadge(id)
  if id == "craft" and S.OrdersWaiting then return S:OrdersWaiting() end
  if id == "officer" and S.ReviewCount then return S:ReviewCount() end
  if id == "events" and S.LiveNow then return #S:LiveNow() end
  return 0
end

-- every icon the dock / border bar shows, in the user's order (drag icons to rearrange)
local function dockCatalog()
  local list = {}
  list[#list + 1] = { key = "home", label = "Home", icon = UI.ICON.home, tint = true, selfToggle = true,
    click = function() main.homeBtn:Click() end,
    active = function() return drawerOpen() and main.view == "home" end }
  list[#list + 1] = { sep = true }
  list[#list + 1] = { key = "tool:Messenger", label = "Messenger", icon = UI.ICON.messages, tint = true, tool = "Messenger",
    click = function() if S.ToolToggle then S:ToolToggle("Messenger") elseif S.ShowMessenger then S:ShowMessenger() end end,
    on = function() local f = _G.CC_Messenger; return f and f:IsShown() end,
    badge = function() return S.UnreadMail and S:UnreadMail() or 0 end }
  list[#list + 1] = { key = "bell", label = "Notifications", icon = UI.ICON.bell, tint = true,
    click = function() main.bellBtn:Click() end,
    badge = function() return S.UnreadNotifs and S:UnreadNotifs() or 0 end }
  list[#list + 1] = { key = "settings", label = "Settings", icon = UI.ICON.settings, tint = true, selfToggle = true,
    click = function() main.gearBtn:Click() end,
    active = function() return drawerOpen() and S:CurrentTabId() == "settings" end }
  list[#list + 1] = { key = "tools", label = "Tools", icon = UI.ICON.tools, tint = true,
    click = function() main.toolsBtn:Click() end,
    on = function() local f = _G.CC_Tools; return f and f:IsShown() end }
  local added = false
  for _, label in ipairs(dockTools()) do
    local t = S.ToolInfo and S:ToolInfo(label)
    if t and not BUILTIN[label] and (not t.officer or S:IsOfficer()) then
      if not added then list[#list + 1] = { sep = true }; added = true end
      list[#list + 1] = { key = "tool:" .. label, label = t.name or label, icon = t.icon, tint = t.tint, tool = label, userTool = true,
        tip = t.tip and function(tt) tt:AddLine(t.name or label, 1, 0.82, 0); tt:AddLine(t.tip, 1, 1, 1, true) end or nil,
        click = function() S:ToolToggle(label) end,
        on = function() local _, _, on = S:ToolInfo(label); return on end,
        avail = function() local _, a = S:ToolInfo(label); return a end }
    end
  end
  -- the game's own menu buttons / bags (dock and border bar only)
  local okB, blz = pcall(function() return S.BlizzardItems and S:BlizzardItems() or {} end)
  if okB and #blz > 0 then
    list[#list + 1] = { sep = true }
    for _, it in ipairs(blz) do list[#list + 1] = it end
  end
  -- other addons' minimap icons (Plugins)
  local ok, plugs = pcall(function() return S.PluginItems and S:PluginItems() or {} end)
  if ok and #plugs > 0 then
    list[#list + 1] = { sep = true }
    for _, it in ipairs(plugs) do list[#list + 1] = it end
  end
  return list
end
S.QuickBarCatalog = function() if not main then return {} end return dockCatalog() end

local function buildDockList()
  local list = dockCatalog()
  -- icons you dragged off the bar (or moved into the Button Box)
  local hid = S.db.global.barHidden
  if type(hid) == "table" then
    local keep = {}
    for _, it in ipairs(list) do if it.sep or not hid[it.key] then keep[#keep + 1] = it end end
    list = keep
  end
  -- the user's own order (once they've dragged something); new icons go on the end
  local ord = S.db.global.barOrder
  if type(ord) == "table" then
    local byKey, out, used = {}, {}, {}
    for _, it in ipairs(list) do if not it.sep then byKey[it.key] = it end end
    for _, k in ipairs(ord) do local it = byKey[k]; if it and not used[k] then used[k] = true; out[#out + 1] = it end end
    for _, it in ipairs(list) do if not it.sep and not used[it.key] then out[#out + 1] = it end end
    return out
  end
  return list
end

local function barName() return isDock() and "dock" or "bar" end

local function dockMenu(self, it)
  local items = { { text = it.label, title = true } }
  if it.userTool then
    items[#items + 1] = { text = "Make it a floating shortcut", func = function() S:CreateToolShortcut(it.tool) end }
    items[#items + 1] = { text = "|cffff7777Remove from " .. barName() .. "|r", func = function() S:RemoveToolFromDock(it.tool) end }
  end
  if it.plugin and S.PluginRemove then
    items[#items + 1] = { text = "|cffff7777Remove from " .. barName() .. "|r", func = function() S:PluginRemove(it) end }
  end
  items[#items + 1] = { text = drawerOpen() and "Collapse page" or "Open page", func = function() S:QuickBarToggle() end }
  if S.ShowPlugins then items[#items + 1] = { text = "Plugins...", func = function() S:ShowPlugins() end } end
  if type(S.db.global.barHidden) == "table" and next(S.db.global.barHidden) then
    items[#items + 1] = { text = "Bring back icons...", func = function() S:QuickBarHiddenMenu(self) end }
  end
  items[#items + 1] = { text = "Game menu buttons...", func = function() S:BlizzardButtonsMenu(self) end }
  if it.blizzard and it.key ~= "blz:bags" then
    items[#items + 1] = { text = "|cffff7777Remove from " .. barName() .. "|r", func = function() S:SetBlizzardButton(it.key:sub(5), false) end }
  elseif it.key == "blz:bags" then
    items[#items + 1] = { text = "|cffff7777Remove from " .. barName() .. "|r", func = function() S.db.global.blzBags = false; S:QuickBarLayout() end }
  end
  if isBorder() then
    local free = S.db.global.qbBorder and S.db.global.qbBorder.layout == "free"
    items[#items + 1] = { text = free and "Icons: snap in a row" or "Icons: place freely", func = function() S:SetBorderIconLayout(free and "snap" or "free") end }
  end
  if type(S.db.global.barOrder) == "table" then
    items[#items + 1] = { text = "Reset icon order", func = function() S.db.global.barOrder = nil; S:QuickBarLayout() end }
  end
  if isDock() then
    items[#items + 1] = { text = "Exit dock mode", func = function() S:SetDockMode(false) end }
    items[#items + 1] = { text = "Border mode instead", func = function() S:SetBorderMode(true) end }
  else
    items[#items + 1] = { text = "Exit border mode", func = function() S:SetBorderMode(false) end }
    items[#items + 1] = { text = "Dock mode instead", func = function() S:SetDockMode(true) end }
  end
  items[#items + 1] = { text = "Hide Command Center", func = function() if combatLocked() then lockedMsg() else userClosed = true; main:Hide() end end }
  UI:Menu(self, items)
end

---------------------------------------------------------------------------
-- Drag to rearrange (and drop tools from the toolbox onto the bar)
---------------------------------------------------------------------------
local function overBar(slack)
  slack = slack or 24
  local mx, my = cursor()
  local l, r, t, b = main:GetLeft(), main:GetRight(), main:GetTop(), main:GetBottom()
  if not (l and r and t and b) then return false end
  return mx >= l - slack and mx <= r + slack and my >= b - slack and my <= t + slack
end
local function alongCursor()
  local mx, my = cursor()
  local l, t = main:GetLeft(), main:GetTop()
  if not (l and t) then return nil end
  return isVertical() and (t - my) or (mx - l)
end
-- where an icon dropped right now would land (1 = first), not counting skipKey
local function dropIndex(skipKey)
  local along = alongCursor()
  local idx = 1
  for _, it in ipairs(dockList) do
    if not it.sep and it.key ~= skipKey and it.center and along and it.center < along then idx = idx + 1 end
  end
  return idx
end
local function showMarker(idx, skipKey)
  local m = main.qbMarker
  local list = {}
  for _, it in ipairs(dockList) do if not it.sep and it.key ~= skipKey and it.center then list[#list + 1] = it end end
  local pos
  if list[idx] then pos = list[idx].center - (list[idx].size or 20) / 2 - 2
  elseif list[#list] then local it = list[#list]; pos = it.center + (it.size or 20) / 2 + 2 end
  if not pos then m:Hide() return end
  m:ClearAllPoints()
  local th = isVertical() and main:GetWidth() or main:GetHeight()
  if isVertical() then m:SetSize(th - 6, 2); m:SetPoint("CENTER", main, "TOP", 0, -pos)
  else m:SetSize(2, th - 6); m:SetPoint("CENTER", main, "LEFT", pos, 0) end
  m:Show()
end
local function insertKey(key, idx)
  local keys = {}
  for _, x in ipairs(dockList) do if not x.sep and x.key ~= key then keys[#keys + 1] = x.key end end
  table.insert(keys, clamp(idx or (#keys + 1), 1, #keys + 1), key)
  S.db.global.barOrder = keys
end
-- the trash can that follows the cursor when an icon is dragged off the bar
local FIXED = { home = true, settings = true }      -- these always stay
local trash
local function showTrash(it)
  if not trash then
    trash = CreateFrame("Frame", nil, UIParent); trash:SetSize(40, 40); trash:SetFrameStrata("TOOLTIP")
    trash.glow = trash:CreateTexture(nil, "BACKGROUND"); trash.glow:SetTexture(UI.ART.glow); trash.glow:SetAllPoints()
    trash.icon = UI:Icon(trash, "trash", 30, "OVERLAY"); trash.icon:SetPoint("CENTER")
    trash.text = UI:Text(trash, "", "small", "CENTER"); trash.text:SetPoint("TOP", trash, "BOTTOM", 0, 2)
  end
  -- over the Button Box: it goes in there instead of the bin
  local toBox = it and not FIXED[it.key] and S.ButtonBoxDropTarget and S:ButtonBoxDropTarget()
  if S.ButtonBoxHighlight then S:ButtonBoxHighlight(toBox and true or false) end
  if not it or toBox then trash:Hide() return end
  local x, y = GetCursorPosition()
  local us = UIParent:GetEffectiveScale() or 1
  trash:ClearAllPoints(); trash:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / us, y / us)
  if FIXED[it.key] then
    trash.icon:SetVertexColor(0.6, 0.6, 0.6); trash.glow:SetVertexColor(0.4, 0.4, 0.4, 0.5)
    trash.text:SetText("|cff999999" .. it.label .. " always stays|r")
  else
    trash.icon:SetVertexColor(1, 0.35, 0.3); trash.glow:SetVertexColor(1, 0.2, 0.15, 0.7)
    trash.text:SetText("|cffff6655Remove|r")
  end
  trash:Show()
end
local function whereBack(it)
  if it.userTool then return "the Tools window" end
  if it.plugin then return "Plugins" end
  if it.blizzard then return "Game menu buttons" end
  return "Bring back icons"
end
local function removeItem(it)
  if it.userTool then S:RemoveToolFromDock(it.tool)
  elseif it.plugin and S.PluginRemove then S:PluginRemove(it)
  elseif it.key == "blz:bags" then S.db.global.blzBags = false; S:QuickBarLayout()
  elseif it.blizzard then S:SetBlizzardButton(it.key:sub(5), false)
  else
    local g = S.db.global
    g.barHidden = type(g.barHidden) == "table" and g.barHidden or {}
    g.barHidden[it.key] = true
    S:QuickBarLayout()
  end
end
-- icons you removed from the bar, to put back
function S:QuickBarHiddenMenu(anchor)
  local g = S.db.global
  local items = { { text = "Bring back icons", title = true } }
  for key in pairs(type(g.barHidden) == "table" and g.barHidden or {}) do
    local label = key:gsub("^sec:", ""):gsub("^tool:", "")
    for _, sec in ipairs(S.HomeTileList and S.HomeTileList() or {}) do if "sec:" .. tostring(sec.id) == key then label = sec.name end end
    if key == "bell" then label = "Notifications" elseif key == "tools" then label = "Tools" end
    if S.ButtonBoxLabel then label = S:ButtonBoxLabel(key) or label end
    items[#items + 1] = { text = label, func = function()
      g.barHidden[key] = nil
      if S.ButtonBoxRemoveKey then S:ButtonBoxRemoveKey(key, true) end   -- one icon per thing: out of the Button Box
      S:QuickBarLayout()
    end }
  end
  if #items == 1 then items[2] = { text = "|cff888888Nothing removed|r", disabled = true } end
  UI:Menu(anchor, items)
end

local function finishReorder(self)
  local it = main.qbReorder
  main.qbReorder = nil
  self:SetAlpha(1); main.qbMarker:Hide(); showTrash(nil)
  if not it then return end
  if not overBar(70) and not FIXED[it.key] and S.ButtonBoxDropTarget and S:ButtonBoxDropTarget() then
    S:ButtonBoxAdd(it.key, S:ButtonBoxSlotUnderCursor())    -- takes it off the bar too
    return
  end
  if not overBar(70) then
    if FIXED[it.key] then S:QuickBarLayout() return end
    UI:Confirm("Remove |cffffd100" .. it.label .. "|r from your " .. barName() .. "?\n\n|cffaaaaaaYou can put it back any time from|r |cffffd100" .. whereBack(it) .. "|r |cffaaaaaa(right-click the " .. barName() .. ").|r",
      function() removeItem(it) end, "Remove")
    S:QuickBarLayout()
    return
  end
  if freestyle() then
    local q = cfg()
    q.free = type(q.free) == "table" and q.free or {}
    for _, o in ipairs(dockList) do if not o.sep and o.center and o ~= it then q.free[o.key] = o.center end end
    local spot = freeSpot(it, alongCursor() or it.center or 0)
    if spot then q.free[it.key] = spot else S:Print("No room there - move another icon first.") end
    S:QuickBarLayout()
    return
  end
  insertKey(it.key, dropIndex(it.key))
  S:QuickBarLayout()
end

-- the toolbox asks: is the cursor over the dock / border bar?
-- which window a dock icon opens (so it can come out of the icon)
local TOOL_WINDOWS = { Messenger = "CC_Messenger", Reminders = "CC_Reminders", Guide = "CC_Guide", Screenshot = "CC_Snap",
  Summoner = "CC_Summoner", ["Button Box"] = "CC_ButtonBox", ["Damage Meter"] = "CC_Meter", Rotational = "CC_Rotational", BuffWatcher = "CC_BuffWatcher", Radialz = "CC_Radialz", HealAssist = "CC_HealAssist", ["Unit Frames"] = "CC_UnitFrames", CCPlates = "CC_Plates", ItemMenu = "CC_ItemMenu", BiB = "CC_BiB", Minimap = "CC_MinimapSettings",
  ["Guided tour"] = "CC_Tutorial" }
function S:DockWindowFor(it)
  if not it then return nil end
  if it.key == "tools" then return "CC_Tools" end
  if it.key == "bell" then return "CC_NotifPanel" end
  if it.tool then
    if TOOL_WINDOWS[it.tool] then return TOOL_WINDOWS[it.tool] end
    local t = S.ToolInfo and S:ToolInfo(it.tool)     -- tools other addons registered (S:RegisterTool)
    return t and t.window
  end
end

-- the dock / border bar icon for a key ("home", "bell", "tool:BiB"...)
function S:QuickBarIcon(key)
  if not main or not (isDock() or isBorder()) then return nil end
  for _, it in ipairs(dockList) do if it.key == key and it.btn and it.btn:IsShown() then return it.btn end end
end
function S:QuickBarMode()
  if isDock() then return "dock" elseif isBorder() then return "border" end
  return "bar"
end

function S:QuickBarDropTarget()
  if not main or not main:IsShown() or not (isDock() or isBorder()) then return nil end
  if overBar(30) then return barName() end
end
function S:QuickBarShowDrop(on)
  if not main or not main.qbMarker then return end
  if on then showMarker(dropIndex(nil)) else main.qbMarker:Hide() end
end
function S:QuickBarDropTool(label)
  if not main then return end
  main.qbMarker:Hide()
  if BUILTIN[label] then
    S:Print("|cffffd100" .. label .. "|r is always in the " .. barName() .. ".")
    insertKey("tool:" .. label, dropIndex("tool:" .. label)); S:QuickBarLayout()
    return
  end
  local idx = dropIndex("tool:" .. label)
  if not S:DockHasTool(label) then
    if S.HasToolShortcut and S:HasToolShortcut(label) then S:DeleteToolShortcut(label, true) end
    table.insert(dockTools(), label)
  end
  local along = alongCursor()
  S:QuickBarLayout()           -- picks up the new icon
  if freestyle() then
    local it
    for _, o in ipairs(dockList) do if o.key == "tool:" .. label then it = o end end
    if it and along then
      local q = cfg(); q.free = type(q.free) == "table" and q.free or {}
      local spot = freeSpot(it, along); if spot then q.free[it.key] = spot end
    end
  else
    insertKey("tool:" .. label, idx)
  end
  S:QuickBarLayout()
  S:Print("|cffffd100" .. label .. "|r added to the " .. barName() .. ". Drag it along the " .. barName() .. " to move it.")
end

-- an icon dragged out of the Button Box onto the bar: switch on whatever it needs
-- (a tool, an addon icon, a game button) and put it where it was dropped
function S:QuickBarDropKey(key, it)
  if not main then return end
  main.qbMarker:Hide()
  local g = S.db.global
  if type(g.barHidden) == "table" then g.barHidden[key] = nil end
  local tool = key:match("^tool:(.+)$")
  if tool and not BUILTIN[tool] then S:QuickBarDropTool(tool) return end
  local idx = dropIndex(key)
  local along = alongCursor()
  if it and it.plugin then
    g.pluginsEnabled = true
    g.plugins = type(g.plugins) == "table" and g.plugins or {}
    g.plugins[it.owner or it.pluginId] = true
  elseif key == "blz:bags" then g.blzBags = true
  elseif key:find("^blz:") then
    g.blzButtons = type(g.blzButtons) == "table" and g.blzButtons or {}
    g.blzButtons[key:sub(5)] = true
  end
  S:QuickBarLayout()
  if freestyle() then
    local o2
    for _, o in ipairs(dockList) do if o.key == key then o2 = o end end
    if o2 and along then
      local q = cfg(); q.free = type(q.free) == "table" and q.free or {}
      local spot = freeSpot(o2, along); if spot then q.free[key] = spot end
    end
  else
    insertKey(key, idx)
  end
  S:QuickBarLayout()
end

local function dockIcon(key, secure)
  local b = icons[key]
  if b then return b end
  if secure then
    b = CreateFrame("Button", nil, main, "SecureActionButtonTemplate")
    b:RegisterForClicks("AnyUp", "AnyDown")
    b.isSecure = true
    b:HookScript("OnMouseUp", function(self)
      local it = self.item
      if it then S.lastAction = { what = it.label or it.key, at = GetTime() } end
    end)
  else
    b = CreateFrame("Button", nil, main)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  end
  b:RegisterForDrag("LeftButton")
  b:SetFrameLevel(main:GetFrameLevel() + 4)
  b.glow = b:CreateTexture(nil, "BACKGROUND"); b.glow:SetTexture(UI.ART.glow); b.glow:SetBlendMode("ADD")
  b.glow:SetPoint("TOPLEFT", -10, 10); b.glow:SetPoint("BOTTOMRIGHT", 10, -10); b.glow:Hide()
  b.disc = b:CreateTexture(nil, "ARTWORK"); b.disc:SetAllPoints(); b.disc:SetTexture(UI.ART.disc)
  b.ring = b:CreateTexture(nil, "ARTWORK", nil, 2); b.ring:SetAllPoints(); b.ring:SetTexture(UI.ART.ring)
  b.icon = b:CreateTexture(nil, "OVERLAY"); b.icon:SetPoint("CENTER")
  b.dot = b:CreateTexture(nil, "OVERLAY", nil, 2); b.dot:SetTexture(UI.MEDIA .. "UI\\disc"); b.dot:SetSize(6, 6); b.dot:Hide()
  b.badge = UI:Badge(b, 16); b.badge:SetPoint("TOPRIGHT", 4, 4)
  b.count = b:CreateFontString(nil, "OVERLAY"); b.count:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE"); b.count:SetPoint("BOTTOMRIGHT", 1, -1)
  b.hl = b:CreateTexture(nil, "HIGHLIGHT"); b.hl:SetTexture(UI.ART.glow); b.hl:SetBlendMode("ADD"); b.hl:SetPoint("TOPLEFT", -6, 6); b.hl:SetPoint("BOTTOMRIGHT", 6, -6)
  UI:Skin(b, function(self, th)
    self.hl:SetVertexColor(th.gold[1], th.gold[2], th.gold[3], 0.35)
    self.disc:SetVertexColor(th.panel[1], th.panel[2], th.panel[3], 0.95)
    self.ring:SetVertexColor(C(th.gold))
    self.glow:SetVertexColor(th.live[1], th.live[2], th.live[3], 0.7)
    self.dot:SetVertexColor(C(th.live))
    if self.item and self.item.tint then self.icon:SetVertexColor(C(th.gold)) end
  end)
  b:SetScript("OnEnter", function(self)
    local it = self.item; if not it or main.qbReorder then return end
    if it.enter then it.enter(self) return end
    local anchor = ({ bottom = "ANCHOR_TOP", top = "ANCHOR_BOTTOM", left = "ANCHOR_RIGHT", right = "ANCHOR_LEFT" })[cfg().edge] or "ANCHOR_TOP"
    GameTooltip:SetOwner(self, anchor)
    if it.tip then it.tip(GameTooltip) else GameTooltip:AddLine(it.label, 1, 0.82, 0) end
    if it.plugin then GameTooltip:AddLine("Plugin from " .. (it.owner or "another addon") .. "  -  Ctrl-right-click: remove", 0.6, 0.6, 0.6, true)
    elseif it.userTool then GameTooltip:AddLine("Right-click: shortcut / remove", 0.7, 0.7, 0.7) end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function(self) local it = self.item; if it and it.leave then it.leave(self) end; GameTooltip:Hide() end)
  b:SetScript("OnDragStart", function(self)
    if combatLocked() then lockedMsg() return end
    -- Alt-drag moves the whole bar; a plain drag rearranges the icons
    if IsAltKeyDown and IsAltKeyDown() then self.movingBar = true; startDrag() return end
    main.qbReorder = self.item; self:SetAlpha(0.45); GameTooltip:Hide()
  end)
  b:SetScript("OnDragStop", function(self)
    self.justDragged = GetTime()
    if self.movingBar then self.movingBar = nil; stopDrag() return end
    finishReorder(self)
  end)
  if secure then
    -- the game does the click; we only add the right-click menu
    b:HookScript("OnClick", function(self, btn, down)
      if down then return end
      local it = self.item; if not it then return end
      if self.justDragged and GetTime() - self.justDragged < 0.3 then return end
      if btn == "RightButton" then dockMenu(self, it) end
    end)
    icons[key] = b
    return b
  end
  b:SetScript("OnClick", function(self, btn)
    local it = self.item; if not it then return end
    S.lastAction = { what = it.label or it.key, at = GetTime() }
    if self.justDragged and GetTime() - self.justDragged < 0.3 then return end
    -- plugins get their own clicks (most use right-click for options); Ctrl-right-click is ours
    if it.plugin and not (btn == "RightButton" and IsControlKeyDown and IsControlKeyDown()) then it.click(self, btn) return end
    if btn == "RightButton" then dockMenu(self, it) return end
    if PlaySound and SOUNDKIT and SOUNDKIT.U_CHAT_SCROLL_BUTTON then PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON) end
    if isDock() then
      local before = main.dockFocus
      setDockFocus(self)
      -- a window from this icon: grow it out of the icon, suck it back in to close
      local wname = S.DockWindowFor and S:DockWindowFor(it)
      if wname then
        local w = _G[wname]
        -- windows holding secure buttons (Summoner) can't be shown or hidden in combat
        if w and InCombatLockdown and InCombatLockdown() and w.IsProtected and w:IsProtected() then
          S:Print((it.label or "That window") .. " can't be opened or closed in combat.") return
        end
        if w and w:IsShown() and not genieBusy(w) then
          if w.__fromDock then genie(w, false, function() w.__fromDock = nil end) else w:Hide() end
          return
        end
        if it.click then it.click(self, btn) end
        w = _G[wname]
        -- (a window you've put somewhere yourself, like the damage meter, stays where you put it)
        if w and w:IsShown() and not w.ccOwnSpot and not (wname == "CC_Messenger" and (S.StreamerOn and S.StreamerOn("messenger") or (not S.StreamerOn and S.db.global.streamer))) then
          w.__fromDock = true
          pinToDock(w)
          genie(w, true)
        end
        return
      end
      -- another module while the page is open: move the page over to this icon
      if before ~= self and main.drawer:IsShown() and not genieBusy(main.drawer) then anchorDrawer(0) end
    end
    -- clicking the module that's already open folds the page away
    if it.active and it.active() and not it.selfToggle then S:QuickBarCollapse() return end
    if it.click then it.click(self, btn) elseif it.fallbackClick then it.fallbackClick() end
  end)
  icons[key] = b
  return b
end

local function iconScale() return UI:IconCircles() and 0.56 or 0.86 end
local function setIcon(b, it)
  local tex = it.icon
  local atlas
  if it.iconFn then
    local ok, t2, co, at = pcall(it.iconFn)
    if ok then if at then atlas = at elseif t2 then tex = t2; it.coords = co or it.coords end end
  end
  local circles = UI:IconCircles()
  b.disc:SetShown(circles); b.ring:SetShown(circles)
  if atlas and b.icon.SetAtlas then
    b.icon:SetAtlas(atlas)
    if it.tint then b.icon:SetVertexColor(C(UI:Theme().gold)) else b.icon:SetVertexColor(1, 1, 1) end
    return
  end
  b.icon:SetTexture(tex or QMARK)
  if type(it.coords) == "table" and #it.coords >= 4 then b.icon:SetTexCoord(unpack(it.coords))
  elseif tostring(tex or QMARK):find("Icons") then b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  else b.icon:SetTexCoord(0, 1, 0, 1) end
  if it.tint then b.icon:SetVertexColor(C(UI:Theme().gold))
  elseif it.color then b.icon:SetVertexColor(it.color[1] or 1, it.color[2] or 1, it.color[3] or 1)
  else b.icon:SetVertexColor(1, 1, 1) end
end

local function prepareItems()
  hasSecure = false
  for _, b in pairs(icons) do b:Hide() end
  for _, sp in ipairs(seps) do sp:Hide() end
  dockList = buildDockList()
  local nsep = 0
  for _, it in ipairs(dockList) do
    if it.sep then
      nsep = nsep + 1
      if not seps[nsep] then
        seps[nsep] = main:CreateTexture(nil, "ARTWORK")
        UI:Skin(seps[nsep], function(self, th) self:SetColorTexture(th.gold[1], th.gold[2], th.gold[3], 0.45) end)
      end
      seps[nsep]:Show()
    else
      local secure = it.secure ~= nil
      local b = dockIcon((secure and "S:" or "") .. it.key, secure)
      b.item = it; it.btn = b
      if secure then
        hasSecure = true
        b:SetAttribute("type1", "click"); b:SetAttribute("clickbutton1", it.secure)
      end
      setIcon(b, it)
      b:SetAlpha(1)
      b:Show()
    end
  end
end

local function dockBase()
  local q = cfg()
  return clamp(q.size or 44, DOCK_MIN, DOCK_MAX)
end
local function dockLength(base, list)
  list = list or dockList
  local n, ns = 0, 0
  for _, it in ipairs(list) do if it.sep then ns = ns + 1 else n = n + 1 end end
  return DOCK_PAD * 2 + n * base + math.max(0, n - 1) * dockGap() + ns * DOCK_SEP
end
local function dockSizeForLength(len, list)
  list = list or dockList
  local n, ns = 0, 0
  for _, it in ipairs(list) do if it.sep then ns = ns + 1 else n = n + 1 end end
  return clamp(math.floor((len - DOCK_PAD * 2 - math.max(0, n - 1) * dockGap() - ns * DOCK_SEP) / math.max(1, n)), DOCK_MIN, DOCK_MAX)
end
S.DockSizeForLength = dockSizeForLength

-- put the icons where they belong for their current sizes (they grow away from the screen edge)
local function positionDock()
  local base = dockBase()
  local v = isVertical()
  local e = cfg().edge
  local len = v and main:GetHeight() or main:GetWidth()
  local total = DOCK_PAD * 2 - dockGap()
  for _, it in ipairs(dockList) do
    if it.sep then total = total + DOCK_SEP else total = total + (it.size or base) + dockGap() end
  end
  local pos = (len - total) / 2 + DOCK_PAD
  local si = 0
  local inset = 9
  for _, it in ipairs(dockList) do
    if it.sep then
      si = si + 1
      local sp = seps[si]
      sp:ClearAllPoints()
      local c = pos + (DOCK_SEP - dockGap()) / 2
      if v then sp:SetSize(base * 0.7, 1); sp:SetPoint("CENTER", main, "TOP", 0, -c)
      else sp:SetSize(1, base * 0.7); sp:SetPoint("CENTER", main, "LEFT", c, 0) end
      pos = pos + DOCK_SEP
    else
      local b, sz = it.btn, it.size or base
      b:SetSize(sz, sz); b.icon:SetSize(sz * iconScale(), sz * iconScale())
      b:ClearAllPoints()
      local c = pos + sz / 2
      if e == "left" then b:SetPoint("LEFT", main, "TOPLEFT", inset, -c)
      elseif e == "right" then b:SetPoint("RIGHT", main, "TOPRIGHT", -inset, -c)
      elseif e == "top" then b:SetPoint("TOP", main, "TOPLEFT", c, -inset)
      else b:SetPoint("BOTTOM", main, "BOTTOMLEFT", c, inset) end
      it.center = c
      pos = pos + sz + dockGap()
    end
  end
end

local function placeDots()
  local e = cfg().edge
  for _, it in ipairs(dockList) do
    local b = it.btn
    if b then
      b.dot:ClearAllPoints()
      if e == "left" then b.dot:SetPoint("RIGHT", b, "LEFT", -1, 0)
      elseif e == "right" then b.dot:SetPoint("LEFT", b, "RIGHT", 1, 0)
      elseif e == "top" then b.dot:SetPoint("TOP", b, "BOTTOM", 0, -1)
      else b.dot:SetPoint("TOP", b, "BOTTOM", 0, -1) end
    end
  end
end

local function layoutDock()
  for _, f in ipairs(headerElems()) do f:Hide() end
  main.close:Hide()
  main.qbNoPlate, main.qbNoGuild = true, true
  prepareItems()
  local base = dockBase()
  for _, it in ipairs(dockList) do it.size = base end
  local len = dockLength(base)
  local thick = base + 18
  if isVertical() then main:SetSize(thick, len) else main:SetSize(len, thick) end
  positionDock(); placeDots()
end

-- Border bar: emblem + "rank . online" at the start, the same icons as the dock in
-- a row (no magnifying), the arrow and close at the end
local function layoutBorderBar(len, t)
  local v = isVertical()
  if v then main:SetSize(t, len) else main:SetSize(len, t) end
  for _, f in ipairs(headerElems()) do f:Hide() end
  main.qbNoPlate = true
  local s = clamp(t - 6, 14, 34)
  local cs = clamp(t - 4, 14, 36)
  local closeW = math.min(24, s)
  main.close:SetSize(closeW, closeW); main.close:Show()
  main.qbArrow:SetSize(s, s); main.qbArrow.icon:SetSize(math.floor(s * 0.6), math.floor(s * 0.6)); main.qbArrow:Show()
  main.crest:SetSize(cs, cs); main.crest:Show()
  main.crest:ClearAllPoints(); main.close:ClearAllPoints(); main.qbArrow:ClearAllPoints()
  local start
  if v then
    main.qbNoGuild = true
    main.crest:SetPoint("TOP", 0, -4)
    main.close:SetPoint("BOTTOM", 0, 18)
    main.qbArrow:SetPoint("BOTTOM", main.close, "TOP", 0, 4)
    start = 4 + cs + 10
  else
    main.qbNoGuild = not S.G
    main.crest:SetPoint("LEFT", 6, 0)
    main.close:SetPoint("RIGHT", -16, 0)
    main.qbArrow:SetPoint("RIGHT", main.close, "LEFT", -4, 0)
    local gl = main.guildLine
    gl:ClearAllPoints(); gl:SetPoint("LEFT", main.crest, "RIGHT", 8, 0)
    gl:SetWidth(0); gl:SetWordWrap(false)
    local gw = math.min((gl:GetStringWidth() or 60) + 2, 200)
    gl:SetWidth(gw)
    main.onlineText:ClearAllPoints(); main.onlineText:SetPoint("LEFT", main.guildDot, "RIGHT", 8, 0); main.onlineText:SetJustifyH("LEFT")
    local show = S.G ~= nil
    for _, f in ipairs({ gl, main.guildDot, main.onlineText, main.onlineGlow }) do f:SetShown(show) end
    start = 6 + cs + 8 + (show and (gw + 8 + 5 + 8 + (main.onlineText:GetStringWidth() or 50) + 16) or 8)
  end
  prepareItems()
  local bo = cfg()
  local finish = len - 16 - closeW - 4 - s - 10
  if v then finish = len - 18 - closeW - 4 - s - 10 end
  main.qbBorderSpan = { start, finish }
  if bo.layout == "free" then
    -- freestyle: each icon keeps its own spot; overlaps are pushed apart
    for _, sp in ipairs(seps) do sp:Hide() end
    bo.free = type(bo.free) == "table" and bo.free or {}
    local list, nextPos = {}, start
    for _, it in ipairs(dockList) do
      if not it.sep then
        it.size = s
        local c = bo.free[it.key]
        if type(c) ~= "number" then c = nil end
        list[#list + 1] = { it = it, c = c }
      end
    end
    local maxEnd = start
    for _, e in ipairs(list) do if e.c then maxEnd = math.max(maxEnd, e.c + s / 2) end end
    for _, e in ipairs(list) do if not e.c then e.c = maxEnd + 4 + s / 2; maxEnd = e.c + s / 2 end end
    table.sort(list, function(x, y) return x.c < y.c end)
    local prevEnd = start - 2
    for _, e in ipairs(list) do
      e.c = math.max(e.c, prevEnd + 2 + s / 2, start + s / 2)
      prevEnd = e.c + s / 2
    end
    local nextStart = finish + 2
    for i = #list, 1, -1 do
      local e = list[i]
      e.c = math.min(e.c, nextStart - 2 - s / 2)
      nextStart = e.c - s / 2
    end
    for _, e in ipairs(list) do
      local it, b = e.it, e.it.btn
      b:SetSize(s, s); b.icon:SetSize(s * iconScale(), s * iconScale())
      b:ClearAllPoints()
      if v then b:SetPoint("CENTER", main, "TOP", 0, -e.c) else b:SetPoint("CENTER", main, "LEFT", e.c, 0) end
      it.center = e.c
    end
  else
    local gap = clamp(S.db.global.iconSpacing or bo.spacing or 4, 0, 40)
    local pos = start
    local si = 0
    for _, it in ipairs(dockList) do
      if it.sep then
        si = si + 1
        local sp = seps[si]
        sp:ClearAllPoints()
        local w2 = math.max(6, gap + 6)
        if v then sp:SetSize(s * 0.8, 1); sp:SetPoint("CENTER", main, "TOP", 0, -(pos + w2 / 2 - gap / 2))
        else sp:SetSize(1, s * 0.8); sp:SetPoint("CENTER", main, "LEFT", pos + w2 / 2 - gap / 2, 0) end
        pos = pos + w2
      else
        local b = it.btn
        it.size = s
        b:SetSize(s, s); b.icon:SetSize(s * iconScale(), s * iconScale())
        b:ClearAllPoints()
        local c = pos + s / 2
        if v then b:SetPoint("CENTER", main, "TOP", 0, -c) else b:SetPoint("CENTER", main, "LEFT", c, 0) end
        it.center = c
        pos = pos + s + gap
      end
    end
  end
  placeDots()
  main.header:ClearAllPoints(); main.header:SetPoint("TOPLEFT", 1, -1); main.header:SetPoint("BOTTOMRIGHT", -1, 1)
end

-- live state (open dot, glow, badges, plugin icons) for the dock and the border bar
local stateAcc = 1
local function updateStates(el)
  stateAcc = stateAcc + (el or 0)
  if stateAcc < 0.25 then return end
  stateAcc = 0
  for _, it in ipairs(dockList) do
    local btn = it.btn
    if btn and not it.sep then
      local on = (it.active and it.active()) or (it.on and it.on())
      btn.dot:SetShown(on and true or false)
      btn.glow:SetShown(it.on and it.on() and true or false)
      btn.icon:SetDesaturated(it.avail and not it.avail() or false)
      btn.badge:SetCount(it.badge and it.badge() or 0)
      btn.count:SetText(it.count and tostring(it.count()) or "")
      if it.iconFn then setIcon(btn, it) end
    end
  end
end

-- the magnification while the mouse is over the dock
local function dockUpdate(el)
  updateStates(el)
  local base = dockBase()
  local lvl = UI:AnimLevel()
  local maxS = lvl == "minimal" and base or math.floor(base * (lvl == "flashy" and 1.85 or 1.6))
  local range = base * 2.6
  local v = isVertical()
  local e = cfg().edge
  local hovering = false
  local mx, my = cursor()
  local l, r, t, b = main:GetLeft(), main:GetRight(), main:GetTop(), main:GetBottom()
  local along
  if not (r and t and b) then l = nil end
  if l and not main.qbDragging and not main.qbSizing and not main.qbReorder then
    local ext = maxS - base + 6
    local x1, x2, y1, y2 = l, r, b, t
    if e == "left" then x2 = r + ext elseif e == "right" then x1 = l - ext elseif e == "top" then y1 = b - ext else y2 = t + ext end
    hovering = mx >= x1 and mx <= x2 and my >= y1 and my <= y2
    along = v and (t - my) or (mx - l)
  end
  -- where each icon sits at rest (so growing icons don't chase the cursor)
  local pos = DOCK_PAD
  local changed = false
  for _, it in ipairs(dockList) do
    if it.sep then pos = pos + DOCK_SEP
    else
      local rest = pos + base / 2
      pos = pos + base + dockGap()
      local target = base
      if hovering and along then
        local d = math.abs(along - rest) / range
        if d < 1 then local f = math.cos(d * math.pi / 2); target = base + (maxS - base) * f * f end
      end
      local cur = it.size or base
      local nxt = cur + (target - cur) * math.min(1, (el or 0.016) * 14)
      if math.abs(nxt - target) < 0.3 then nxt = target end
      if math.abs(nxt - cur) > 0.01 then changed = true end
      it.size = nxt
    end
  end
  if changed and not combatLocked() then positionDock() end
end

freestyle = function() return isBorder() and cfg().layout == "free" end
freeSpot = function(it, want)
  local span = main.qbBorderSpan or { 0, 99999 }
  local s = it.size or 20
  local lo, hi = span[1] + s / 2, span[2] - s / 2
  local function clear(c)
    if c < lo or c > hi then return false end
    for _, o in ipairs(dockList) do
      if o ~= it and not o.sep and o.center and math.abs(o.center - c) < (s + (o.size or s)) / 2 + 1 then return false end
    end
    return true
  end
  want = clamp(want, lo, hi)
  for d = 0, math.max(1, hi - lo) do
    if clear(want + d) then return want + d end
    if clear(want - d) then return want - d end
  end
  return nil
end
function S:SetBorderIconLayout(mode)
  local q = S.db.global.qbBorder or {}
  S.db.global.qbBorder = q
  if mode == "free" and q.layout ~= "free" then
    -- start from where the icons are now
    q.free = {}
    for _, it in ipairs(dockList) do if not it.sep and it.center then q.free[it.key] = it.center end end
  end
  q.layout = mode
  if main then S:QuickBarLayout() end
end
function S:SetIconSpacing(px)
  S.db.global.iconSpacing = px
  if main and (isBorder() or isDock()) then S:QuickBarLayout() end
end
S.SetBorderIconSpacing = S.SetIconSpacing

-- while an icon is being dragged along the bar
local function reorderUpdate()
  local it = main.qbReorder
  if not it then return end
  if freestyle() then
    local along = alongCursor()
    if along and it.btn and overBar(70) then
      it.btn:ClearAllPoints()
      if isVertical() then it.btn:SetPoint("CENTER", main, "TOP", 0, -along) else it.btn:SetPoint("CENTER", main, "LEFT", along, 0) end
      it.btn:SetAlpha(0.8)
    elseif it.btn then
      it.btn:SetAlpha(0.15)
    end
    if overBar(70) then showTrash(nil) else showTrash(it) end
    return
  end
  if overBar(70) then
    showMarker(dropIndex(it.key), it.key)
    if it.btn then it.btn:SetAlpha(0.45) end
    showTrash(nil)
  else
    main.qbMarker:Hide()
    if it.btn then it.btn:SetAlpha(0.15) end
    showTrash(it)
  end
end

---------------------------------------------------------------------------
-- Chrome: bar look vs dock shelf
---------------------------------------------------------------------------
local function applyChrome()
  local dock, border = isDock(), isBorder()
  local thin = not dock and math.min(main:GetWidth() or 80, main:GetHeight() or 80) < 50
  main.header:SetShown(not dock)
  if main.headCap then for _, k in ipairs({ "TL", "T", "TR" }) do if main.headCap[k] then main.headCap[k]:SetShown(not dock and not border and not thin) end end end
  if main.shadow then main.shadow:SetShown(not border) end
  if main.drawerShadow then main.drawerShadow:SetShown(not border and not dock) end
  if dock then
    UI:Skin(main, function(self, th) UI.Flat(self, th.bg, 0.78, th.gold, 0.55, 1) end)
  elseif border then
    UI:Skin(main, function(self, th) UI.Flat(self, th.bg, 0.97, th.edge, 1, 1) end)
  else
    UI:Skin(main, function(self, th) UI.Flat(self, th.bg, 0.97, th.edge, 1, 2) end)
  end
  -- Escape: closes the window normally; in dock / border mode it only folds the page away
  if UISpecialFrames then
    -- Escape folds the page away (the quickbar stays); close Command Center with the X or /ccenter
    local want = "CC_MainDrawer"
    local other = "CC_Main"
    for i = #UISpecialFrames, 1, -1 do if UISpecialFrames[i] == other then table.remove(UISpecialFrames, i) end end
    local has = false
    for _, n in ipairs(UISpecialFrames) do if n == want then has = true end end
    if not has then tinsert(UISpecialFrames, want) end
  end
end

---------------------------------------------------------------------------
-- Everything together
---------------------------------------------------------------------------
local function placeGrip()
  local g = main.qbGrip
  g:ClearAllPoints()
  local e = cfg().edge
  local thin = math.min(main:GetWidth() or 80, main:GetHeight() or 80) < 44
  g:SetSize(thin and 12 or 16, thin and 12 or 16)
  -- the grip sits in the corner away from the screen edge
  if isDock() and isVertical() then g:SetPoint("BOTTOM", main, "BOTTOM", 0, 3); g.tex:SetRotation(-math.pi / 4)
  elseif e == "bottom" then g:SetPoint("TOPRIGHT", main, "TOPRIGHT", -2, -2); g.tex:SetRotation(math.pi / 2)
  elseif e == "right" then g:SetPoint("BOTTOMLEFT", main, "BOTTOMLEFT", 2, 2); g.tex:SetRotation(-math.pi / 2)
  else g:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", -2, 2); g.tex:SetRotation(0) end
  g:SetFrameLevel(main:GetFrameLevel() + 20)
end

local layoutXPBars
-- keys of the icons on the dock / border bar right now ({} in plain bar mode)
function S:QuickBarKeysInUse()
  local out = {}
  if not main or not (isDock() or isBorder()) then return out end
  local ok, list = pcall(buildDockList)
  if ok then for _, it in ipairs(list) do if it.key then out[it.key] = true end end end
  return out
end

function S:QuickBarLayout()
  if S.PluginSyncMinimap then pcall(S.PluginSyncMinimap, S) end
  if not main or not main.drawer then return end
  if combatLocked() then pendingLayout = true return end
  pendingLayout = false
  local q = cfg()
  local sw, sh = screen()
  if isDock() then
    layoutDock()
  else
    for _, b in pairs(icons) do b:Hide() end
    for _, s in ipairs(seps) do s:Hide() end
    if isBorder() then
      local th = clamp(q.thick or BORDER_DEF, BORDER_MIN, BORDER_MAX)
      local W = WorldFrame or UIParent
      local es = (main:GetEffectiveScale() or 1) / ((W.GetEffectiveScale and W:GetEffectiveScale()) or 1)
      local fw, fh = (W:GetWidth() or sw) / es, (W:GetHeight() or sh) / es
      layoutBorderBar(isVertical() and fh or fw, th)
    elseif isVertical() then
      layoutVertical(clamp(q.len or 520, MIN_LEN_V, math.max(MIN_LEN_V, sh)), clamp(q.thickV or BAR_V, THICK_MIN_V, BAR_V))
    else
      layoutHorizontal(clamp(q.lenH or main.fullW or 808, MIN_LEN_H, math.max(MIN_LEN_H, sw)), clamp(q.thick or BAR_H, THICK_MIN_H, BAR_H))
    end
  end
  applyChrome()
  -- the border bar sits under everything: other windows and anything you move onto it
  -- go on top; its page (drawer) still opens above other windows
  main:SetFrameStrata(isBorder() and "LOW" or "HIGH")
  main.drawer:SetFrameStrata("HIGH")
  place()
  placeGrip()
  updateUIShift()
  if main.drawer:IsShown() then anchorDrawer(anim and SLIDE * (1 - anim.p) or 0) end
  main.qbFixedLine = isBorder()
  if layoutXPBars then layoutXPBars() end
  if S.ApplyBlizzardHiding then S:ApplyBlizzardHiding() end
  if not isDock() and not isBorder() and not isVertical() and S.FitHeaderLine then S:FitHeaderLine() end
end

function S:SetDockMode(on)
  S.db.global.dockMode = on and true or false
  if main then main.dockFocus = nil; if main.drawer then main.drawer:SetScale(1); main.drawer:SetAlpha(1) end end
  if on then S.db.global.borderMode = false end
  if on then
    local d = cfg()
    if d.edge == "free" and not d.x then d.edge = "bottom" end
  end
  if not main then if on then S:ShowMain() end return end
  if on then
    if not main:IsShown() then main:Show() end
    if S:CurrentTabId() ~= "settings" then S:QuickBarCollapse() end
  end
  S:QuickBarLayout()
end

-- Border mode: a thin, always-there bar along a whole screen edge
function S:SetBorderMode(on)
  S.db.global.borderMode = on and true or false
  if on then S.db.global.dockMode = false end
  if not main then if on then S:ShowMain() end return end
  if on then
    if not main:IsShown() then main:Show() end
    if S:CurrentTabId() ~= "settings" then S:QuickBarCollapse() end
  end
  S:QuickBarLayout()
end

-- right-click on the quickbar
local function barMenu(anchor)
  UI:Menu(anchor, {
    { text = "Quickbar", title = true },
    { text = drawerOpen() and "Collapse page" or "Open page", func = function() S:QuickBarToggle() end },
    { text = "Border mode (thin bar along the screen edge)", checked = isBorder(), func = function() S:SetBorderMode(not isBorder()) end },
    { text = "Dock mode", checked = isDock(), func = function() S:SetDockMode(not isDock()) end },
    { text = "Reset size & position", func = function() S:ResetQuickBar() end },
    { text = "Plugins (other addons' minimap icons)...", func = function() if S.ShowPlugins then S:ShowPlugins() end end },
    { text = "Game menu buttons & bags...", func = function() S:BlizzardButtonsMenu(anchor) end },
    { text = "Bring back icons...", func = function() S:QuickBarHiddenMenu(anchor) end },
    { text = "XP & reputation bars", checked = S.db.global.qbXPBars and true or false, func = function() S.db.global.qbXPBars = not S.db.global.qbXPBars; S:QuickBarLayout() end },
    { text = "Hide Command Center", func = function() if combatLocked() then lockedMsg() else userClosed = true; main:Hide() end end },
  })
end

function S:ResetQuickBar()
  S.db.global.qb, S.db.global.qbDock, S.db.global.qbBorder = nil, nil, nil
  S:QuickBarLayout()
end

---------------------------------------------------------------------------
-- XP and reputation bars along the inside edge of the quickbar
---------------------------------------------------------------------------
-- a bar with round ends: a half-disc cap at each end and a plain middle, for the
-- background, the rested part and the fill
local DISC = UI.MEDIA .. "UI\\disc"
local function roundStrip(f, layer, sub)
  local r = { l = f:CreateTexture(nil, layer, nil, sub), m = f:CreateTexture(nil, layer, nil, sub), e = f:CreateTexture(nil, layer, nil, sub) }
  r.l:SetTexture(DISC); r.e:SetTexture(DISC); r.m:SetTexture("Interface\\Buttons\\WHITE8x8")
  function r:Color(cr, cg, cb, ca) for _, t in pairs({ self.l, self.m, self.e }) do t:SetVertexColor(cr, cg, cb, ca or 1) end end
  function r:Show(on) for _, t in pairs({ self.l, self.m, self.e }) do t:SetShown(on) end end
  -- len along the bar from its start; thick across
  function r:Span(len, thick, vertical)
    local cap = thick / 2
    len = math.max(len, thick)
    for _, t in pairs({ self.l, self.m, self.e }) do t:ClearAllPoints() end
    if vertical then
      self.l:SetTexCoord(0, 1, 0.5, 1); self.l:SetSize(thick, cap); self.l:SetPoint("BOTTOM", f, "BOTTOM", 0, 0)
      self.m:SetSize(thick, math.max(0.1, len - thick)); self.m:SetPoint("BOTTOM", self.l, "TOP")
      self.e:SetTexCoord(0, 1, 0, 0.5); self.e:SetSize(thick, cap); self.e:SetPoint("BOTTOM", self.m, "TOP")
    else
      self.l:SetTexCoord(0, 0.5, 0, 1); self.l:SetSize(cap, thick); self.l:SetPoint("LEFT", f, "LEFT", 0, 0)
      self.m:SetSize(math.max(0.1, len - thick), thick); self.m:SetPoint("LEFT", self.l, "RIGHT")
      self.e:SetTexCoord(0.5, 1, 0, 1); self.e:SetSize(cap, thick); self.e:SetPoint("LEFT", self.m, "RIGHT")
    end
  end
  return r
end
local function makeStatusBar()
  local f = CreateFrame("Frame", nil, main)
  f.bg = roundStrip(f, "BACKGROUND", 0); f.bg:Color(0, 0, 0, 0.55)
  f.rest = roundStrip(f, "BORDER", 0); f.rest:Color(0.25, 0.45, 1, 0.35)
  f.fill = roundStrip(f, "ARTWORK", 0); f.fill:Color(0.6, 0.2, 0.85, 1)
  f:EnableMouse(true)
  f:SetScript("OnLeave", function() GameTooltip:Hide() end)
  f:SetFrameLevel(main:GetFrameLevel() + 1)     -- under the icons and the emblem
  return f
end
local function setFill(f, pct, restPct)
  pct = clamp(pct or 0, 0, 1)
  local v = f.vertical
  local L = v and (f:GetHeight() or 0) or (f:GetWidth() or 0)
  local T = v and (f:GetWidth() or 3) or (f:GetHeight() or 3)
  f.bg:Span(L, T, v)
  f.fill:Span(L * pct, T, v); f.fill:Show(pct > 0)
  local rp = clamp(restPct or 0, 0, 1)
  f.rest:Span(L * rp, T, v); f.rest:Show(rp > pct)
end
function S:UpdateQuickBarXP()
  if not main or not main.xpBar then return end
  local on = S.db.global.qbXPBars
  local xp = on and S.XPInfo and S:XPInfo()
  local rep = on and S.RepInfo and S:RepInfo()
  main.xpBar:SetShown(xp ~= nil); main.repBar:SetShown(rep ~= nil)
  if xp then setFill(main.xpBar, xp.cur / xp.max, xp.rested and (xp.cur + xp.rested) / xp.max or 0); main.xpBar.info = xp end
  if rep then setFill(main.repBar, rep.cur / rep.max); main.repBar.fill:Color(rep.r, rep.g, rep.b, 1); main.repBar.info = rep end
end
layoutXPBars = function()
  if not main.xpBar then return end
  local e = cfg().edge
  local v = isVertical()
  local h = (isBorder() or math.min(main:GetWidth() or 80, main:GetHeight() or 80) < 50) and 3 or 4
  -- the edge that faces into the screen
  local side = (e == "bottom" and "top") or (e == "left" and "right") or (e == "right" and "left") or "bottom"
  if isDock() and e == "free" then side = "bottom" end
  local bars = { main.xpBar, main.repBar }
  for i, f in ipairs(bars) do
    f:ClearAllPoints(); f.vertical = v
    local off = 2 + (i - 1) * (h + 1)
    if side == "bottom" then f:SetPoint("BOTTOMLEFT", main, "BOTTOMLEFT", 6, off); f:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", -6, off); f:SetHeight(h)
    elseif side == "top" then f:SetPoint("TOPLEFT", main, "TOPLEFT", 6, -off); f:SetPoint("TOPRIGHT", main, "TOPRIGHT", -6, -off); f:SetHeight(h)
    elseif side == "right" then f:SetPoint("TOPRIGHT", main, "TOPRIGHT", -off, -6); f:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", -off, 6); f:SetWidth(h)
    else f:SetPoint("TOPLEFT", main, "TOPLEFT", off, -6); f:SetPoint("BOTTOMLEFT", main, "BOTTOMLEFT", off, 6); f:SetWidth(h) end
    if v then f:SetHeight(main:GetHeight() - 12) else f:SetWidth(main:GetWidth() - 12) end
  end
  S:UpdateQuickBarXP()
end
for _, ev in ipairs({ "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION", "PLAYER_LEVEL_UP", "UPDATE_FACTION" }) do
  S:On(ev, function() if S.UpdateQuickBarXP then S:UpdateQuickBarXP() end end)
end

-- the "rank . online" text changed size: make room so no icon sits on it
local lastTextW
function S:QuickBarTextChanged()
  if not main or not isBorder() or isVertical() then return end
  local function w(fs) return (fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth()) or fs:GetStringWidth() or 0 end
  local tw = math.floor(w(main.guildLine) + w(main.onlineText) + 0.5)
  if tw ~= lastTextW then lastTextW = tw; S:QuickBarLayout() end
end

-- pick which of the game's menu buttons go in the dock / border bar
function S:BlizzardButtonsMenu(anchor)
  local g = S.db.global
  local items = { { text = "Game menu buttons", title = true } }
  for _, m in ipairs(S.BlizzardMicroButtons and S:BlizzardMicroButtons() or {}) do
    items[#items + 1] = { text = m.label, keep = true, checked = S:BlizzardButtonOn(m.name), func = function() S:SetBlizzardButton(m.name, not S:BlizzardButtonOn(m.name)) end }
  end
  items[#items + 1] = { text = "Bags", keep = true, checked = g.blzBags and true or false, func = function() g.blzBags = not g.blzBags; S:QuickBarLayout() end }
  items[#items + 1] = { text = "Hide the game's menu buttons", keep = true, checked = g.hideBlzMicro and true or false, func = function() g.hideBlzMicro = not g.hideBlzMicro; S:ApplyBlizzardHiding() end }
  items[#items + 1] = { text = "Hide the game's bag bar", keep = true, checked = g.hideBlzBags and true or false, func = function() g.hideBlzBags = not g.hideBlzBags; S:ApplyBlizzardHiding() end }
  if not (g.dockMode or g.borderMode) then items[#items + 1] = { text = "|cff888888These show in dock and border mode|r", disabled = true } end
  UI:Menu(anchor, items)
end

local function build(m)
  main = m
  local d = main.drawer
  d:SetClampedToScreen(true)

  -- the arrow: folds the page away / brings it back, turning to show which way
  local arrow = UI:IconButton(main, "up", 40, nil, function() S:QuickBarToggle() end)
  arrow.angle = 0
  UI:Tip(arrow, function() return drawerOpen() and "Collapse" or "Expand" end,
    function() return drawerOpen() and "Fold the page away and keep just the quickbar." or "Bring the page back." end)
  arrow:HookScript("OnUpdate", function(self, el)
    local target = arrowTarget()
    if self.angle == target and self.shownAngle == target then return end   -- settled: nothing to redraw
    self.shownAngle = target
    local diff = target - self.angle
    while diff > math.pi do diff = diff - 2 * math.pi end
    while diff < -math.pi do diff = diff + 2 * math.pi end
    if math.abs(diff) < 0.01 then self.angle = target
    elseif UI:AnimLevel() == "minimal" then self.angle = target
    else self.angle = self.angle + diff * math.min(1, el * 12) end
    self.icon:SetRotation(self.angle)
  end)
  main.qbArrow = arrow
  -- the guild line / online count are drawn on their own layer above the icons,
  -- so nothing on the bar can cover them
  main.qbTextLayer = CreateFrame("Frame", nil, main)
  main.qbTextLayer:SetAllPoints(); main.qbTextLayer:SetFrameLevel(main:GetFrameLevel() + 8)
  for _, r in ipairs({ main.titleText, main.crumb, main.guildLine, main.guildDot, main.onlineText, main.onlineGlow }) do
    if r and r.SetParent then r:SetParent(main.qbTextLayer) end
  end
  main.xpBar = makeStatusBar(); main.repBar = makeStatusBar()
  if main.crest then main.crest:SetFrameLevel(main:GetFrameLevel() + 4) end
  main.xpBar:SetScript("OnEnter", function(self)
    local x = self.info; if not x then return end
    GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
    GameTooltip:AddLine("Level " .. x.level .. " experience", 1, 0.82, 0)
    GameTooltip:AddLine(S.Commas and (S.Commas(x.cur) .. " / " .. S.Commas(x.max)) or (x.cur .. " / " .. x.max), 1, 1, 1)
    GameTooltip:AddLine(string.format("%.1f%%", x.cur / x.max * 100), 0.8, 0.8, 0.8)
    if x.rested then GameTooltip:AddLine("Rested: " .. (S.Commas and S.Commas(x.rested) or x.rested), 0.4, 0.6, 1) end
    GameTooltip:Show()
  end)
  main.repBar:SetScript("OnEnter", function(self)
    local r = self.info; if not r then return end
    GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
    GameTooltip:AddLine(r.name, 1, 0.82, 0)
    GameTooltip:AddLine((r.standing or "") .. "  " .. r.cur .. " / " .. r.max, r.r, r.g, r.b)
    GameTooltip:Show()
  end)
  main.close:SetScript("OnClick", function() if combatLocked() then lockedMsg() else userClosed = true; main:Hide() end end)
  main.dockAnchor = CreateFrame("Frame", nil, main); main.dockAnchor:SetSize(1, 1)
  main.drawer:SetScale(1)
  main.qbMarker = main:CreateTexture(nil, "OVERLAY", nil, 7); main.qbMarker:Hide()
  UI:Skin(main.qbMarker, function(self, th) self:SetColorTexture(th.gold[1], th.gold[2], th.gold[3], 1) end)

  -- the grip: resize the quickbar (or the dock's icons)
  local grip = CreateFrame("Button", nil, main)
  grip:SetSize(16, 16)
  grip.tex = grip:CreateTexture(nil, "OVERLAY"); grip.tex:SetAllPoints(); grip.tex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine(isDock() and "Drag to resize the dock" or "Drag to resize the quickbar", 1, 0.82, 0)
    if not isDock() then GameTooltip:AddLine(isBorder() and "Drag across the bar to make it thinner or thicker." or "Along the bar: length.  Across it: thinner / thicker.", 1, 1, 1, true) end
    GameTooltip:Show()
  end)
  grip:SetScript("OnLeave", function() GameTooltip:Hide() end)
  grip:SetScript("OnMouseDown", function(self)
    if combatLocked() then lockedMsg() return end
    local x, y = cursor()
    local v = isVertical()
    self.start = { x = x, y = y, len = v and main:GetHeight() or main:GetWidth(), thick = v and main:GetWidth() or main:GetHeight() }
    main.qbSizing = true
  end)
  grip:SetScript("OnMouseUp", function(self)
    self.start = nil; main.qbSizing = false
    S:QuickBarLayout()
  end)
  grip:SetScript("OnUpdate", function(self)
    local st = self.start
    if not st then return end
    local x, y = cursor()
    local v = isVertical()
    local len = st.len + (v and (st.y - y) or (x - st.x))
    -- a centred dock grows both ways, so the grip moves half as far
    if isDock() and cfg().edge ~= "free" then len = st.len + 2 * (v and (st.y - y) or (x - st.x)) end
    local q = cfg()
    if isDock() then
      local sz = dockSizeForLength(len)
      if sz ~= q.size then q.size = sz; S:QuickBarLayout() end
    else
      -- across the bar = thickness (thinner = lower profile), along it = length
      local e = cfg().edge
      local dx, dy = x - st.x, y - st.y
      local thick
      if v then thick = st.thick + (e == "right" and -dx or dx) else thick = st.thick + (e == "bottom" and dy or -dy) end
      thick = math.floor(thick)
      if isBorder() then
        q.thick = clamp(thick, BORDER_MIN, BORDER_MAX)
      elseif v then
        q.len = math.floor(len); q.thickV = clamp(thick, THICK_MIN_V, BAR_V)
      else
        q.lenH = math.floor(len); q.thick = clamp(thick, THICK_MIN_H, BAR_H)
      end
      S:QuickBarLayout()
    end
  end)
  main.qbGrip = grip

  -- dragging the bar (or the page) moves it; dropping near an edge snaps
  main:SetScript("OnDragStart", function() startDrag() end)
  main:SetScript("OnDragStop", function() stopDrag() end)
  d:RegisterForDrag("LeftButton")
  d:SetScript("OnDragStart", function() startDrag() end)
  d:SetScript("OnDragStop", function() stopDrag() end)

  -- the page sliding in / out
  d:SetScript("OnUpdate", function(self, el)
    if not anim then return end
    anim.p = clamp(anim.p + anim.dir * el / 0.18, 0, 1)
    local e = 1 - (1 - anim.p) * (1 - anim.p)
    self:SetAlpha(e)
    anchorDrawer(SLIDE * (1 - e))
    if (anim.dir > 0 and anim.p >= 1) or (anim.dir < 0 and anim.p <= 0) then finishAnim() end
  end)
  -- hidden some other way (Escape in dock mode): remember it as folded away
  d:HookScript("OnHide", function()
    if main:IsShown() and not anim then S.db.global.qbCollapsed = true end
  end)

  main:HookScript("OnUpdate", S.PerfWrap and S.PerfWrap("QuickBar  dock/border OnUpdate", function(self, el)
    if self.qbDragging then showHint(currentHintEdge()) end
    if isDock() then dockUpdate(el) elseif isBorder() then updateStates(el) end
    if self.qbReorder then reorderUpdate() end
  end) or function(self, el)
    if self.qbDragging then showHint(currentHintEdge()) end
    if isDock() then dockUpdate(el) elseif isBorder() then updateStates(el) end
    if self.qbReorder then reorderUpdate() end
  end)
  main:HookScript("OnShow", function() S:QuickBarLayout() end)
  main:HookScript("OnHide", function() showHint(nil); setUIShift(nil) end)
  main:HookScript("OnMouseUp", function(self, btn) if btn == "RightButton" then barMenu(self) end end)

  if S.db.global.qbCollapsed then d:Hide() end
  S:QuickBarLayout()
end

S:Listen("MAIN_CREATED", build)
-- keep the dock's module list current (officer rank, new tools)
S:Listen("ME_CHANGED", function() if main and (isDock() or isBorder()) then S:QuickBarLayout() end end)
S:Listen("GUILD_CHANGED", function() if main and (isDock() or isBorder()) then S:QuickBarLayout() end end)

-- in dock mode /ccenter and the minimap button fold the page in and out instead of
-- hiding the dock; the dock comes up by itself at login
local toggleMain = S.ToggleMain
function S:ToggleMain()
  if (isDock() or isBorder()) and main and main:IsShown() then S:QuickBarToggle()
  else
    if main and main:IsShown() then userClosed = true end
    toggleMain(self)
  end
end
-- at login: wait until the guild is known, then show the quickbar (folded) unless
-- Settings > "When I log in" says to start hidden
local function loginShow(tries)
  tries = tries or 0
  if not S.db or userClosed then return end
  local g = S.db.global
  local mode = g.startMode or "auto"
  if mode == "hidden" then return end
  local function again() if tries < 15 then C_Timer.After(2, function() loginShow(tries + 1) end) end end
  if main and main:IsShown() then again() return end
  local diag = { t = date("%Y-%m-%d %H:%M:%S"), try = tries, mode = mode, guild = S.G ~= nil }
  if S.G then
    if mode == "auto" then g.qbCollapsed = true end
    local ok, err = pcall(S.ShowMain, S)
    diag.ok, diag.err, diag.shown = ok, not ok and tostring(err) or nil, main and main:IsShown() or false
  end
  g.loginDiag = diag
  -- keep checking for a little while: the guild can load late, and the loading
  -- screen or another addon can hide windows right after login
  again()
end
S.QuickBarLoginShow = loginShow
S:Listen("LOGIN", function() C_Timer.After(1, function() loginShow(0) end) end)
S:Listen("GUILD_READY", function() C_Timer.After(0.5, function() loginShow(0) end) end)
local firstWorld = true
S:On("PLAYER_ENTERING_WORLD", function()
  if not firstWorld then return end
  firstWorld = false
  C_Timer.After(3, function() loginShow(0) end)
end)
S:Listen("__OLD_LOGIN_SHOW", function()
  C_Timer.After(2, function()
    -- Settings > "When I log in": automatic (dock / border bar show), show, or start hidden
    local mode = S.db.global.startMode or "auto"
    local want = mode == "show" or (mode == "auto" and (isDock() or isBorder()))
    if want and S.G and not (main and main:IsShown()) and mode == "show" and not (isDock() or isBorder()) then
      S:ShowMain()
      return
    end
    if want and (isDock() or isBorder()) and S.G and not (main and main:IsShown()) then
      S.db.global.qbCollapsed = true
      S:ShowMain()
    end
  end)
end)

S:AddCommand("dock", "", "Turn dock mode on / off", function() S:SetDockMode(not isDock()) end)
S:AddCommand("border", "", "Turn border mode on / off (thin bar along the screen edge)", function() S:SetBorderMode(not isBorder()) end)
S:AddCommand("resetbar", "", "Put the quickbar back where it started", function() S:ResetQuickBar() end)
