-- The Guide: Command Center's manual as one scrolling storybook. Every feature and every setting,
-- chapter by chapter, each marked "good to know" or "optional", most with a little
-- looping animation of the feature and a "Show me" button that opens the real thing.
-- Chapters fade in as you scroll to them. Open: Tools > Guide, /ccenter guide.
local _, S = ...
local UI = S.UI

local GOLD, GRN, GRY = "|cffffd100", "|cff55ff55", "|cff999999"
local function cmd(t) return "|cffffff00" .. t .. "|r" end
local function C(c, a) return c[1], c[2], c[3], a or 1 end
local DISC, RING, WHITE = UI.MEDIA .. "UI\\disc", UI.MEDIA .. "UI\\ring", "Interface\\Buttons\\WHITE8x8"

---------------------------------------------------------------------------
-- Little animations ("GIFs") drawn with plain textures inside a 240x135 box.
-- Each builder makes its pieces once and returns update(t) for the loop.
---------------------------------------------------------------------------
local AW, AH = 240, 135
local function tex(p, layer, r, g, b, a, file)
  local t = p:CreateTexture(nil, layer or "ARTWORK")
  t:SetTexture(file or WHITE)
  t:SetVertexColor(r or 1, g or 1, b or 1, a or 1)
  return t
end
local function box(p, x, y, w, h, r, g, b, a, layer)
  local t = tex(p, layer, r, g, b, a)
  t:SetPoint("TOPLEFT", x, -y); t:SetSize(w, h)
  return t
end
local function disc(p, x, y, size, r, g, b, a, layer)
  local t = tex(p, layer or "ARTWORK", r, g, b, a, DISC)
  t:SetPoint("CENTER", p, "TOPLEFT", x, -y); t:SetSize(size, size)
  return t
end
local function label(p, text, x, y, size, col)
  local f = p:CreateFontString(nil, "OVERLAY")
  f:SetFont("Fonts\\FRIZQT__.TTF", size or 9, ""); f:SetPoint("TOPLEFT", x, -y); f:SetText(text)
  if col then f:SetTextColor(col[1], col[2], col[3]) end
  return f
end
local function handTex(p)
  local h = p:CreateTexture(nil, "OVERLAY", nil, 3); h:SetTexture("Interface\\CURSOR\\Point"); h:SetSize(20, 20)
  return h
end
local function at(t, x, y) t:ClearAllPoints(); t:SetPoint("TOPLEFT", t:GetParent(), "TOPLEFT", x, -y) end
local function lerp(a, b, k) return a + (b - a) * math.max(0, math.min(1, k)) end
local function ease(k) k = math.max(0, math.min(1, k)); return 1 - (1 - k) * (1 - k) end

local function miniBar(p, th, y)
  box(p, 8, y or 8, AW - 16, 20, th.head1[1], th.head1[2], th.head1[3], 1)
  disc(p, 20, (y or 8) + 10, 14, th.gold[1], th.gold[2], th.gold[3], 1)
  label(p, "Command Center", 32, (y or 8) + 5, 9, th.gold)
end
local function miniTiles(p, th, y, h)
  local tiles = {}
  for i = 0, 5 do
    local cx, cy = 14 + (i % 3) * 72, (y or 36) + math.floor(i / 3) * ((h or 42) + 6)
    local t = box(p, cx, cy, 68, h or 42, th.panel[1], th.panel[2], th.panel[3], 1)
    local rib = box(p, cx, cy, 68, 4, th.ribbon[1], th.ribbon[2], th.ribbon[3], 1)
    tiles[#tiles + 1] = { t, rib }
  end
  return tiles
end

local ANIM = {}
ANIM.tiles = function(p, th)
  miniBar(p, th)
  local tiles = miniTiles(p, th, 36, 42)
  local names = { "BiB", "Meter", "Messenger", "Box", "Screenshot", "Reminders" }
  for i, n in ipairs(names) do label(p, n, 18 + ((i - 1) % 3) * 72, 54 + math.floor((i - 1) / 3) * 48, 8) end
  local hand = handTex(p)
  return function(t)
    local k = math.floor(t / 1.2) % 6 + 1
    for i, tt in ipairs(tiles) do tt[1]:SetVertexColor(i == k and th.panel2[1] * 1.6 or th.panel[1], i == k and th.panel2[2] * 1.4 or th.panel[2], i == k and th.panel2[3] * 1.2 or th.panel[3], 1) end
    at(hand, 50 + ((k - 1) % 3) * 72, 58 + math.floor((k - 1) / 3) * 48)
  end
end
ANIM.fold = function(p, th)
  miniBar(p, th)
  local arrow = disc(p, AW - 26, 18, 14, th.gold[1], th.gold[2], th.gold[3], 1)
  local page = CreateFrame("Frame", nil, p); page:SetPoint("TOPLEFT", 8, -34); page:SetSize(AW - 16, 92)
  local bg = tex(page, "ARTWORK", th.panel[1], th.panel[2], th.panel[3], 1); bg:SetAllPoints()
  for i = 0, 2 do box(page, 8 + i * 72, 10, 64, 72, th.panel2[1], th.panel2[2], th.panel2[3], 1) end
  local hand = handTex(p)
  return function(t)
    local T = t % 5
    local open = T < 1.6 or T > 3.8
    local k = T < 1.6 and 0 or T < 2.0 and (T - 1.6) / 0.4 or T < 3.8 and 1 or 1 - (T - 3.8) / 0.4
    page:SetAlpha(1 - k); page:ClearAllPoints(); page:SetPoint("TOPLEFT", 8, -34 + 14 * k)
    at(hand, lerp(130, AW - 28, ease(T / 1.2)), lerp(100, 20, ease(T / 1.2)))
    arrow:SetSize((T > 1.3 and T < 1.6 or T > 3.5 and T < 3.8) and 11 or 14, (T > 1.3 and T < 1.6 or T > 3.5 and T < 3.8) and 11 or 14)
  end
end
ANIM.snap = function(p, th)
  local bar = box(p, 60, 50, 120, 18, th.head1[1], th.head1[2], th.head1[3], 1)
  local glow = box(p, 0, 0, 3, AH, th.gold[1], th.gold[2], th.gold[3], 0.8)
  return function(t)
    local T = t % 5
    if T < 2 then
      local k = ease(T / 2)
      bar:ClearAllPoints(); bar:SetPoint("TOPLEFT", lerp(60, 4, k), -lerp(50, 30, k)); bar:SetSize(120, 18); glow:SetAlpha(k > 0.8 and 1 or 0)
    elseif T < 2.6 then
      local k = ease((T - 2) / 0.6)
      bar:SetSize(lerp(120, 20, k), lerp(18, 90, k)); glow:SetAlpha(1 - k)
    else
      bar:SetSize(20, 90); glow:SetAlpha(0)
    end
  end
end
ANIM.dock = function(p, th)
  local shelf = box(p, 30, AH - 34, AW - 60, 26, th.bg[1], th.bg[2], th.bg[3], 0.8)
  local icons = {}
  for i = 1, 8 do icons[i] = disc(p, 44 + (i - 1) * 22, AH - 22, 16, th.gold[1], th.gold[2], th.gold[3], 1) end
  local hand = handTex(p)
  return function(t)
    local x = 40 + (math.sin(t * 0.9) * 0.5 + 0.5) * 160
    at(hand, x, AH - 46)
    for i, ic in ipairs(icons) do
      local cx = 44 + (i - 1) * 22
      local d = math.abs(cx - x - 4) / 44
      local s = 16 + (d < 1 and 14 * math.cos(d * math.pi / 2) ^ 2 or 0)
      ic:SetSize(s, s); ic:ClearAllPoints(); ic:SetPoint("BOTTOM", p, "TOPLEFT", cx, -(AH - 14))
    end
  end
end
ANIM.border = function(p, th)
  local bar = box(p, 0, 0, AW, 14, th.head1[1], th.head1[2], th.head1[3], 1)
  local txt = label(p, "Command Center", 6, 2, 8, th.live)
  local mm = disc(p, AW - 34, 30, 44, 0.24, 0.35, 0.17, 1)
  local mmr = tex(p, "OVERLAY", 0.54, 0.43, 0.18, 1, RING); mmr:SetAllPoints(mm)
  return function(t)
    local T = t % 5
    local k = T < 1 and 0 or T < 1.8 and ease((T - 1) / 0.8) or T < 4 and 1 or 1 - ease((T - 4) / 0.8)
    bar:SetAlpha(k); txt:SetAlpha(k)
    mm:ClearAllPoints(); mm:SetPoint("CENTER", p, "TOPLEFT", AW - 34, -(28 + 16 * k))
  end
end
ANIM.toast = function(p, th)
  local toast = CreateFrame("Frame", nil, p); toast:SetSize(130, 34)
  local bg = tex(toast, "ARTWORK", 0.05, 0.05, 0.06, 0.95); bg:SetAllPoints()
  local edge = tex(toast, "ARTWORK", th.gold[1], th.gold[2], th.gold[3], 1); edge:SetPoint("TOPLEFT"); edge:SetPoint("BOTTOMLEFT"); edge:SetWidth(2)
  label(toast, "Zalia", 8, 4, 9, th.gold); label(toast, "raiding tonight?", 8, 18, 8)
  return function(t)
    local T = t % 4.5
    local k = T < 0.6 and ease(T / 0.6) or T < 3.4 and 1 or 1 - ease((T - 3.4) / 0.6)
    toast:ClearAllPoints(); toast:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", lerp(140, -8, k), 10)
    toast:SetAlpha(k)
  end
end
ANIM.banner = function(p, th)
  local strip = box(p, 0, 46, AW, 30, 0, 0, 0, 0.6)
  local txt = label(p, "Molten Core starts in 15 minutes!", 0, 54, 11, th.gold)
  return function(t)
    local T = t % 5
    txt:ClearAllPoints(); txt:SetPoint("TOPLEFT", p, "TOPLEFT", lerp(AW, -220, T / 5), -54)
    strip:SetAlpha(T < 0.3 and T / 0.3 or T > 4.6 and (5 - T) / 0.4 or 1)
  end
end
ANIM.smart = function(p, th)
  local bub = box(p, 10, 12, 160, 22, 0.17, 0.17, 0.19, 1)
  label(p, "can I get an inv? raid at 8", 16, 18, 8)
  local chips = {}
  local names = { "Invite Zalia", "I'm going", "Remind me 19:45" }
  for i, n in ipairs(names) do
    local c = CreateFrame("Frame", nil, p); c:SetSize(70, 16); c:SetPoint("TOPLEFT", 10 + (i - 1) * 74, -100)
    local b = tex(c, "ARTWORK", th.panel2[1], th.panel2[2], th.panel2[3], 1); b:SetAllPoints()
    local e = tex(c, "OVERLAY", th.gold[1], th.gold[2], th.gold[3], 1); e:SetPoint("BOTTOMLEFT"); e:SetPoint("BOTTOMRIGHT"); e:SetHeight(1)
    label(c, n, 4, 4, 7)
    chips[i] = c
  end
  return function(t)
    local T = t % 5
    bub:SetAlpha(T < 0.4 and T / 0.4 or 1)
    for i, c in ipairs(chips) do c:SetAlpha(T > 0.8 + i * 0.4 and 1 or 0) end
  end
end
ANIM.tools = function(p, th)
  local rows = {}
  for i = 1, 4 do rows[i] = box(p, 40, 12 + (i - 1) * 26, 160, 22, th.panel[1], th.panel[2], th.panel[3], 1) end
  local live = box(p, 40, 12, 2, 22, th.live[1], th.live[2], th.live[3], 1)
  local trash = tex(p, "OVERLAY", 1, 0.35, 0.3, 1, UI.ICON.trash); trash:SetSize(22, 22)
  local hand = handTex(p)
  return function(t)
    local T = t % 5
    if T < 2.5 then
      for i, r in ipairs(rows) do r:ClearAllPoints(); r:SetPoint("TOPLEFT", 40, -(12 + (i - 1) * 26)) end
      live:SetAlpha(T > 1 and 1 or 0); trash:Hide()
      at(hand, 120, 20)
    else
      local k = ease((T - 2.5) / 1.5)
      rows[3]:ClearAllPoints(); rows[3]:SetPoint("TOPLEFT", lerp(40, 200, k), -lerp(64, 100, k))
      at(hand, lerp(120, 220, k), lerp(70, 104, k))
      trash:ClearAllPoints(); trash:SetPoint("CENTER", p, "TOPLEFT", lerp(130, 214, k), -lerp(76, 114, k)); trash:SetShown(k > 0.6)
    end
  end
end
ANIM.loot = function(p, th)
  box(p, 12, 30, AW - 24, 30, th.panel[1], th.panel[2], th.panel[3], 1)
  local icon = box(p, 18, 34, 22, 22, 0.64, 0.21, 0.93, 1)
  label(p, "[Breastplate of Might]", 46, 40, 8, { 0.64, 0.21, 0.93 })
  local btns = {}
  for i, n in ipairs({ "MS", "OS", "Pass" }) do
    btns[i] = box(p, 40 + (i - 1) * 54, 76, 48, 18, th.panel2[1], th.panel2[2], th.panel2[3], 1)
    label(p, n, 52 + (i - 1) * 54, 80, 8)
  end
  local hand = handTex(p)
  return function(t)
    local T = t % 4.5
    at(hand, lerp(200, 60, ease(T / 1.4)), lerp(120, 82, ease(T / 1.4)))
    btns[1]:SetVertexColor(T > 1.6 and 0.2 or th.panel2[1], T > 1.6 and 0.6 or th.panel2[2], T > 1.6 and 0.2 or th.panel2[3], 1)
  end
end
ANIM.calendar = function(p, th)
  box(p, 20, 14, AW - 40, 64, th.panel[1], th.panel[2], th.panel[3], 1)
  label(p, "Molten Core", 30, 22, 10, th.gold); label(p, "Saturday 20:00  -  Healers 3/6", 30, 40, 8)
  local going = box(p, 30, 56, 60, 16, th.panel2[1], th.panel2[2], th.panel2[3], 1)
  label(p, "Going", 44, 59, 8)
  local toast = box(p, AW - 140, AH - 36, 128, 26, 0.05, 0.05, 0.06, 0.95)
  local tl = label(p, "Reminder: 15 minutes!", AW - 134, AH - 28, 8, th.gold)
  local hand = handTex(p)
  return function(t)
    local T = t % 5.5
    at(hand, lerp(160, 52, ease(T / 1.2)), lerp(110, 62, ease(T / 1.2)))
    going:SetVertexColor(T > 1.4 and 0.2 or th.panel2[1], T > 1.4 and 0.6 or th.panel2[2], T > 1.4 and 0.2 or th.panel2[3], 1)
    local k = T > 2.6 and math.min(1, (T - 2.6) / 0.4) or 0
    toast:SetAlpha(k); tl:SetAlpha(k)
  end
end
ANIM.badge = function(p, th)
  local tiers = { { 0.80, 0.50, 0.20 }, { 0.85, 0.87, 0.90 }, { 1, 0.82, 0.29 }, { 0.75, 0.93, 0.94 }, { 0.78, 0.96, 1 } }
  local ring = tex(p, "OVERLAY", 1, 1, 1, 1, RING); ring:SetSize(70, 70); ring:SetPoint("CENTER", 0, 4)
  local b = tex(p, "ARTWORK", 1, 1, 1, 1, "Interface\\AddOns\\CommandCenter\\Media\\Badges\\stinkiest_3"); b:SetSize(58, 58); b:SetPoint("CENTER", 0, 4)
  local name = label(p, "", 0, AH - 22, 10); name:ClearAllPoints(); name:SetPoint("BOTTOM", 0, 8)
  local names = { "Bronze", "Silver", "Gold", "Platinum", "Diamond" }
  return function(t)
    local k = math.floor(t / 1.1) % 5 + 1
    ring:SetVertexColor(tiers[k][1], tiers[k][2], tiers[k][3], 1)
    name:SetText(names[k]); name:SetTextColor(tiers[k][1], tiers[k][2], tiers[k][3])
  end
end
ANIM.fart = function(p, th)
  label(p, "This week", 20, 14, 9, th.gold)
  local rows = {}
  for i, r in ipairs({ { "Grukk", 31 }, { "You", 11 }, { "Zalia", 9 } }) do rows[i] = { label(p, i .. ".  " .. r[1], 24, 34 + (i - 1) * 20, 10), label(p, "", 160, 34 + (i - 1) * 20, 10), r[2] } end
  local plus = label(p, "+1  *fart*", 120, 96, 11, th.live)
  return function(t)
    local T = t % 4
    local mine = T > 1.5 and 12 or 11
    for i, r in ipairs(rows) do r[2]:SetText(tostring(i == 2 and mine or r[3])) end
    plus:SetAlpha(T > 1.5 and T < 3 and 1 - (T - 1.5) / 1.5 or 0)
    plus:ClearAllPoints(); plus:SetPoint("TOPLEFT", 120, -(96 - (T > 1.5 and (T - 1.5) * 10 or 0)))
  end
end
ANIM.search = function(p, th)
  local field = box(p, 20, 16, 200, 20, th.field[1], th.field[2], th.field[3], 1)
  local typed = label(p, "", 26, 21, 9)
  local res = box(p, 20, 40, 200, 60, th.bg[1], th.bg[2], th.bg[3], 0.95)
  local lines = { label(p, "Quickbar & dock  |  Dock mode", 26, 48, 8), label(p, "Quickbar & dock  |  Border mode", 26, 64, 8), label(p, "Behaviour  |  Show minimap button", 26, 80, 8) }
  return function(t)
    local T = t % 5
    local word = "mode"
    local n = math.min(#word, math.floor(T / 0.3))
    typed:SetText(word:sub(1, n))
    local show = n == #word and T < 4.4
    res:SetAlpha(show and 1 or 0); for _, l in ipairs(lines) do l:SetAlpha(show and 1 or 0) end
  end
end

-- plain Command Center: hidden away, just the minimap emblem and a pop-up now and then
ANIM.quiet = function(p, th)
  local mm = disc(p, AW - 50, 46, 64, 0.24, 0.35, 0.17, 1)
  local mmr = tex(p, "OVERLAY", 0.54, 0.43, 0.18, 1, RING); mmr:SetAllPoints(mm)
  local emb = disc(p, AW - 84, 70, 16, 0.2, 0.6, 0.2, 1, "OVERLAY")
  local embR = tex(p, "OVERLAY", th.gold[1], th.gold[2], th.gold[3], 1, RING); embR:SetAllPoints(emb)
  local toast = CreateFrame("Frame", nil, p); toast:SetSize(150, 30)
  local bg = tex(toast, "ARTWORK", 0.05, 0.05, 0.06, 0.95); bg:SetAllPoints()
  local edge = tex(toast, "ARTWORK", th.gold[1], th.gold[2], th.gold[3], 1); edge:SetPoint("TOPLEFT"); edge:SetPoint("BOTTOMLEFT"); edge:SetWidth(2)
  label(toast, "Command Center", 8, 4, 8, th.gold); label(toast, "Reminder: dungeon at 20:00", 8, 16, 8)
  label(p, "Everything else stays hidden", 10, 12, 8, th.muted)
  return function(t)
    local T = t % 5
    local k = T < 1 and 0 or T < 1.5 and ease((T - 1) / 0.5) or T < 3.8 and 1 or 1 - ease((T - 3.8) / 0.5)
    toast:ClearAllPoints(); toast:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", lerp(-160, 10, k), 10); toast:SetAlpha(k)
    local pulse = 16 + (k > 0 and 3 * math.sin(t * 8) or 0)
    emb:SetSize(pulse, pulse)
  end
end

-- a framed, clipped box running one of the animations (used by the Guide and the tour)
function S:MakeGuideAnim(parent, name)
  local th = UI:Theme()
  local a = CreateFrame("Frame", nil, parent)
  a:SetSize(AW, AH)
  if a.SetClipsChildren then a:SetClipsChildren(true) end
  local bg = a:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetTexture(WHITE)
  UI:Gradient(bg, "VERTICAL", 0.05, 0.08, 0.09, 1, 0.11, 0.16, 0.2, 1)
  local edge = CreateFrame("Frame", nil, a, BackdropTemplateMixin and "BackdropTemplate" or nil); edge:SetAllPoints()
  edge:SetFrameLevel(a:GetFrameLevel() + 5)
  UI.Flat(edge, { 0, 0, 0 }, 0, th.edge, 1, 1)
  a.edge = edge
  local ok, upd = pcall(ANIM[name], a, th)
  a.update = ok and upd or nil
  return a
end
S.GUIDE_ANIM_SIZE = { AW, AH }

---------------------------------------------------------------------------
-- Chapters
---------------------------------------------------------------------------
-- tag: "need" (good to know) / "opt" (optional); anim; show = fn that opens the real thing
local CH = {
  { part = "Start here" },
  { title = "What Command Center is", tag = "need", anim = "tiles",
    text = "Command Center is a utility hub and an upgrade for your interface: a dock, border bar or quick bar for everything you click, and a set of tools - BiB (your bags), a damage meter, a messenger for whispers, a Button Box, screenshots, reminders, a summoner for warlocks and a rotation helper.\n\n" ..
      "You choose how big it is: tuck it into a slim bar, or make it your main bar with your game buttons, bags, XP and other addons in one place.",
    show = function() S:ShowMain() end },
  { title = "Opening, folding, closing", tag = "need", anim = "fold",
    text = "Open Command Center with its button on the minimap or " .. cmd("/ccenter") .. ".\n\nThe " .. GOLD .. "arrow|r on the quickbar folds the page away and leaves just the bar; " .. GOLD .. "Escape|r does the same. Pressing a button again undoes it: Home folds the page away, Settings takes you back. The " .. GOLD .. "X|r closes Command Center.",
    show = function() S:ShowMain() end },
  { title = "The quickbar", tag = "need", anim = "snap",
    text = "The bar at the top with the main buttons: home, messenger, bell, settings and tools.\n\n" ..
      "Drag it to any screen edge and it snaps there - left or right makes it stand up and the page slides out sideways. Drag the corner grip along the bar for length, across it for a thinner, lower-profile bar. Right-click it for options.",
    show = function() S:ShowMain() end },
  { title = "The home page", tag = "need", anim = "tiles",
    text = "The home page has a tile for every tool. Click a tile to open the tool, click it again to close it - " .. GOLD .. "Open|r shows which ones are open.",
    show = function() S:ShowMain("home") end },
  { title = "Notifications and pop-ups", tag = "need", anim = "toast",
    text = "The " .. GOLD .. "bell|r collects everything new for you: reminders, whispers and more. Click one to jump to it. New ones also pop up for a few seconds (only Command Center's own - never other addons).\n\n" ..
      GOLD .. "Settings > Move / resize pop-ups|r puts the pop-up box wherever you like and changes its size.",
    show = function() local b = S.bellFrame; if b then S:ShowMain(); b:Click() end end },

  { part = "The tools" },
  { title = "Tools and shortcuts", tag = "opt", anim = "tools",
    text = "The " .. GOLD .. "toolbox|r turns every tool on and off: BiB, Damage Meter, Messenger, Button Box, Screenshot, Reminders, Summoner, BuffWatcher, Radialz, HealAssist, ItemMenu, Minimap, Unit Frames, CCPlates and this Guide. Click a row to open or close it (green edge = open). Drag rows to reorder, drag one out to remove it, the + brings it back. Right-click a tool for a round shortcut you can put anywhere - or drag it onto your dock / border bar.",
    show = function() if S.ShowTools then S:ShowTools() end end },
  { title = "BiB - Built-in Bag", tag = "opt",
    text = "Tools > " .. GOLD .. "BiB|r (" .. cmd("/ccenter bib") .. "): all your bags in one window. Turn it on in " .. GOLD .. "Settings > Bags (BiB)|r and it opens instead of the game's bags - B, Shift-B, the bag buttons, vendors, mail, the bank, the auction house.\n\n" ..
      "Right-click the " .. GOLD .. "sort|r button to sort by type, quality, name, item level, sell value, stack size, newest or item ID, and to group into sections (equipment, consumables, quest items, trade goods, junk...) or one section per bag. Left-click it to " .. GOLD .. "clean up|r: your items really move into that order and part stacks merge. The search box finds names and types, and words like " .. GOLD .. "epic|r, " .. GOLD .. "boe|r, " .. GOLD .. "junk|r, " .. GOLD .. "new|r or " .. GOLD .. "ilvl>100|r.\n\n" ..
      "The cog has the look - slots per row, slot size, spacing, background texture, colour and opacity, slot style, the reagent bag's own box - what to show and when it opens by itself. At a vendor, " .. GOLD .. "Sell junk|r sells every grey item.",
    show = function() if S.ShowBiB then S:ShowBiB() end end },
  { title = "Damage meter", tag = "opt",
    text = "Tools > " .. GOLD .. "Damage Meter|r (" .. cmd("/ccenter meter") .. "): damage, DPS, healing, absorbs, interrupts, dispels, damage taken, deaths and more for you and your group. Pick what to show and which fight; hover a column title for what it means, hover a player for their top spells. The speech bubble shares it to chat.\n\n" ..
      "During a fight the game only lets addons " .. GOLD .. "show|r the numbers, so rows stay in the game's order; after the fight they're ranked and everything can be read.\n\n" ..
      "It reads the game's own damage meter, so turning it on (" .. GOLD .. "Settings > Damage meter|r) switches that on for you and hides its window (" .. GOLD .. "Not working?|r in Settings shows how to do it by hand).",
    show = function() if S.ShowMeter then S:ShowMeter() end end },
  { title = "Messenger", tag = "need", anim = "toast",
    text = "Tools > " .. GOLD .. "Messenger|r (" .. cmd("/ccenter msg") .. "): your whispers as chats - one per person, with bubbles, times, sounds and pop-ups. Answer right there.\n\n" ..
      "Type a name in the search box: friends, your group and past chats are suggested as you type. Whispers are only kept on this computer. " .. GOLD .. "Settings > Keep whispers out of the chat window|r if you only want them here.",
    show = function() S:ShowMessenger() end },
  { title = "Smart suggestions", tag = "opt", anim = "smart",
    text = "In a chat, Command Center reads the last few messages and offers the next step: " .. GOLD .. "Invite|r when someone asks for an invite, " .. GOLD .. "Remind me <time>|r when you agree on a time.\n\nThe small x hides them until the next message. Settings > Smart message suggestions turns them off.",
    show = function() S:ShowMessenger() end },
  { title = "Button Box", tag = "opt",
    text = "Tools > " .. GOLD .. "Button Box|r (" .. cmd("/ccenter box") .. "): a box you fill with any icons - tools, the game's menu buttons and bags, other addons' minimap icons. The " .. GOLD .. "+|r picks icons; drag to reorder, drag one out to remove it, drag the corner to make it wider. The cog changes the icon size.\n\n" ..
      "Drag icons between the box and your dock / border bar - each thing lives in one place. An addon icon in the box (or on your bar) hides its own minimap button.\n\n" ..
      GOLD .. "Groups:|r drag one icon onto the middle of another (it glows) and they go into a group, like apps on a phone. Click a group to open it and type its name at the top; drag icons onto it to add them, drag them out to take them out. Right-click a group to rename or ungroup it.",
    show = function() if S.ShowButtonBox then S:ShowButtonBox() end end },
  { title = "Screenshots", tag = "opt",
    text = "Tools > " .. GOLD .. "Screenshot|r (" .. cmd("/ccenter screenshot") .. "): sliders for brightness, contrast, gamma, view distance, shadows and more change the world live. " .. GOLD .. "Take picture|r hides the whole interface, takes the shot and brings it back. Optional: hide names and nameplates, a 3 second countdown. Settings go back to how they were when you close it, unless you tick " .. GOLD .. "Keep|r. Not possible in combat.",
    show = function() if S.ShowSnap then S:ShowSnap() end end },
  { title = "Reminders", tag = "opt", anim = "banner",
    text = "Your own alarms (Tools > " .. GOLD .. "Reminders|r, " .. cmd("/ccenter reminders") .. "). Each one can pop up, run a line of text across your screen and play a sound - once, daily or weekly. " .. GOLD .. "Test|r plays it right away.",
    show = function() if S.ShowReminders then S:ShowReminders() end end },
  { title = "Summoner (warlocks)", tag = "opt",
    text = "Tools > " .. GOLD .. "Summoner|r (" .. cmd("/ccenter summon") .. "), warlocks only: " .. GOLD .. "Ready for summons|r tells your group to type 123. Everyone who does is listed - click a name to target and summon them. A tick shows they accepted, a cross that they declined (click to try again). Shows your soul shards and how many still need a summon.",
    show = function() if S.ShowSummoner then S:ShowSummoner() end end },
  { title = "ItemMenu", tag = "opt",
    text = "Tools > " .. GOLD .. "ItemMenu|r (" .. cmd("/ccenter itemmenu") .. "): Alt + right-click an item in your bags (or right-click an item link in chat) for a menu - open all, preview, copy link, Wowhead link, where it comes from (uses Questie when installed), link in chat, mark as unwanted (deleted automatically whenever it lands in your bags) and delete. The key is your choice in its settings.",
    show = function() if S.ShowItemMenu then S:ShowItemMenu() end end },
  { title = "Minimap", tag = "opt",
    text = "Tools > " .. GOLD .. "Minimap|r (" .. cmd("/ccenter map") .. "): the minimap in your theme - square, rounded or round, any size, a themed border, a zone bar (click: world map), a clock (click: stopwatch and alarm) and coordinates.\n\n" ..
      "Zoom with the mouse wheel; it zooms back out by itself after a while. Other addons' minimap buttons get your theme's ring, and can stay hidden until you hover the minimap. " ..
      GOLD .. "Unlock to move|r drags it anywhere (right-click to lock). Questicus pins and buttons, LibDBIcon buttons and the border bar all follow the shape.",
    show = function() if S.ShowMinimapSettings then S:ShowMinimapSettings() end end },
  { title = "BuffWatcher", tag = "opt",
    text = "Tools > " .. GOLD .. "BuffWatcher|r (" .. cmd("/ccenter buffs") .. "): the buffs and weapon enchants you want to keep up. A missing one shows in a small tracker (shift-drag to move) and glows on your bars out of combat.",
    show = function() if S.ShowBuffWatcher then S:ShowBuffWatcher() end end },
  { title = "Radialz", tag = "opt",
    text = "Tools > " .. GOLD .. "Radialz|r (" .. cmd("/ccenter radialz") .. "): an extra action bar shaped like a wheel. Press " .. GOLD .. "mouse button 5|r and it opens at the mouse; left-click a slot to use it. " ..
      "Press the key again, Escape, right-click the centre or click outside to close it; left-click the centre to go back a page. Drag spells, items and macros onto its slots (in the window or on the open wheel), " ..
      "or type macro text. A slot can " .. GOLD .. "open another page|r - a second wheel - so one key reaches dozens of actions. The Look tab sets the size, roundness, colour, names, cooldowns and animation; " ..
      "the Key tab picks another key and where it opens. It works in combat; changes to the wheel wait until combat ends.",
    show = function() if S.ShowRadialz then S:ShowRadialz() end end },
  { title = "HealAssist", tag = "opt",
    text = "Tools > " .. GOLD .. "HealAssist|r (" .. cmd("/ccenter heal") .. "): healing frames like HealBot - click a frame to heal that person, and bind every mouse button with Shift / Ctrl / Alt. A " .. GOLD .. "smart|r click picks the rank from how much health they're missing (Ranks tab: e.g. 5% = Rank 1, 10% = Rank 2). An " .. GOLD .. "auto|r click switches to Chain Heal / Prayer of Healing when the people around them are hurt too, with the rank from the whole group. The game only lets the rank change out of combat; in a fight smart clicks cast your combat choice and the frames show the gauged rank (marks on the bar, badge). " .. cmd("/ccenter heal check") .. " lists your ranks.",
    show = function() if S.ShowHealAssist then S:ShowHealAssist() end end },
  { title = "Unit Frames", tag = "opt",
    text = "Tools > " .. GOLD .. "Unit Frames|r (" .. cmd("/ccenter frames") .. "): your own player, target, target of target, focus, pet, party, raid and boss frames in the Command Center theme. Tick " .. GOLD .. "Use Command Center unit frames|r, then " .. GOLD .. "Unlock frames|r to drag them (right-click a box for its settings) and " .. GOLD .. "Test mode|r to fill them with made-up players. Each frame has its own size, bars and text, portrait (3D, 2D or class icon), buffs and debuffs, cast bar, icons, highlights (target, aggro, debuffs you can remove) and fading. Extras: incoming heals, combo points, druid mana, energy ticks / five-second rule. The game's frames are hidden for the ones you use.",
    show = function() if S.ShowUnitFrames then S:ShowUnitFrames() end end },
  { title = "CCPlates (nameplates)", tag = "opt",
    text = "Tools > " .. GOLD .. "CCPlates|r (" .. cmd("/ccenter plates") .. "): nameplates in the Command Center theme. Tick " .. GOLD .. "Use CCPlates|r, pick a " .. GOLD .. "Look|r (Command Center, Slim, Classic block, Glass pill, Clean, Bold) and fine-tune it - the preview on the right shows every change. " ..
      "Colours: class, reaction, tapped grey, threat for tanks or damage / healers (automatic from your role), execute range with a marker, and your own colour for any mob by name. " ..
      "Cast bars turn green while your interrupt is ready, grey with a shield when they can't be interrupted, and say Interrupted. Your target grows, glows or gets arrows, and the others fade. " ..
      "The game's own debuff row is moved onto the plate (it keeps working in a fight), plus raid marks, a ! on quest mobs, combo points and names-only friendly plates. Turn nameplates on with V.",
    show = function() if S.ShowPlates then S:ShowPlates() end end },
  { title = "Streamer mode", tag = "opt",
    text = "For streamers: pop-ups, the notification list and chat stop showing what whispers say. Streaming programs record the whole game, so no addon can hide a window from them - instead, drag the Messenger window under your webcam box and use its corner grip to resize it. " .. cmd("/ccenter streamer"),
    show = function() S:ShowMain("settings") end },

  { part = "Make it yours" },
  { title = "Dock mode", tag = "opt", anim = "dock",
    text = "The quickbar becomes a dock like on a Mac: every icon grows as you hover. Click to open, click again to fold away. Drag icons to rearrange them; Alt-drag to move the dock.",
    show = function() S:ShowMain("settings") end },
  { title = "Border mode", tag = "opt", anim = "border",
    text = "A thin bar along one whole screen edge, under every other window. The rest of your UI (minimap, buffs, bars) moves out of its way. Icons snap in a row (with a spacing slider) or go anywhere you like in Freestyle. Drag the bar toward another edge to move it.",
    show = function() S:ShowMain("settings") end },
  { title = "Game buttons, bags, XP and other addons", tag = "opt",
    text = "In dock or border mode you can add the game's own buttons (character, spellbook, talents, quest log, game menu...), a bag button with free slots, XP and reputation bars, and other addons' minimap icons (" .. GOLD .. "Plugins|r - pick addons from everything you have installed). Toggles can hide the game's own copies. Drag any icon off the bar to remove it; right-click the bar > Bring back icons.",
    show = function() S:ShowMain("settings") end },
  { title = "Themes and colours", tag = "opt",
    text = "Horde war-camp, Classic Blizzard, Fel green, or " .. GOLD .. "Custom colours|r: pick the accent with the game's colour picker or with hue / saturation / brightness sliders, and tint the backgrounds. Icon style: plain or in circles.",
    show = function() if S.ShowColorEditor then S:ShowColorEditor() end end },

  { part = "Every setting" },
  { title = "Settings, one by one", tag = "opt", anim = "search",
    text = "Type a word in the " .. GOLD .. "search box|r at the top of Settings to jump to any of these.\n\n" ..
      GOLD .. "Appearance:|r font, text size, window scale.\n" ..
      GOLD .. "Look & feel:|r theme, animations (minimal / smooth / flashy), icon style, custom colours.\n" ..
      GOLD .. "Quickbar & dock:|r dock mode, border mode, reset position, plugins, when I log in, border icons (snap or freestyle), icon spacing, game menu buttons & bags, hide the game's menu buttons / bag bar, XP & reputation bars, hide the game's XP bars.\n" ..
      GOLD .. "Behaviour:|r minimap button.\n" ..
      GOLD .. "Messenger:|r bubble colours, pop-up or badge or nothing, pop-up time, sounds.\n" ..
      GOLD .. "Whispers, pop-ups & streaming:|r keep whispers out of chat, smart suggestions, streamer mode, notifications as pop-ups, move / resize pop-ups.\n" ..
      GOLD .. "Damage meter|r and " .. GOLD .. "Bags (BiB)|r: turn them on, their options.\n" ..
      GOLD .. "First-time setup:|r take the tour again or redo one step.",
    show = function() S:ShowMain("settings") end },
  { title = "Help", tag = "need",
    text = "Take the tour again with " .. cmd("/ccenter tour") .. ". " .. cmd("/ccenter help") .. " lists every command. Questions or bugs: ask " .. GRN .. S.support .. "|r in game.",
    show = function() S:ShowTutorial(true) end },
}
S.GUIDE_CHAPTERS = CH

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local win, sf, child
local W, H, NAV = 760, 540, 170
local blocks = {}

local function build()
  win = UI:Window("CC_Guide", "Command Center Guide", W, H)
  win:SetFrameStrata("HIGH")
  -- contents on the left
  local nav = UI:Panel(win, NAV, H - 56, { 0.03, 0.03, 0.04, 0.9 })
  nav:SetPoint("TOPLEFT", 14, -36)
  local nsf, nchild = UI:Scroll(nav, NAV - 4, H - 64)
  nsf:SetPoint("TOPLEFT", 2, -4); nchild:SetWidth(NAV - 26)
  -- chapters on the right
  sf, child = UI:Scroll(win, W - NAV - 44, H - 56)
  sf:SetPoint("TOPLEFT", nav, "TOPRIGHT", 8, 0)
  local CW = W - NAV - 44 - 26
  child:SetWidth(CW)
  local y, ny = 8, 6
  local th = UI:Theme()
  for i, ch in ipairs(CH) do
    if ch.part then
      local h = UI:Text(child, ch.part, "large"); h:SetPoint("TOPLEFT", 4, -y); h:SetTextColor(C(th.gold))
      local ln = child:CreateTexture(nil, "ARTWORK"); ln:SetTexture(WHITE); ln:SetVertexColor(th.gold[1], th.gold[2], th.gold[3], 0.5)
      ln:SetPoint("TOPLEFT", 4, -(y + 24)); ln:SetSize(CW - 8, 1)
      local nh = UI:Text(nchild, ch.part, "small"); nh:SetPoint("TOPLEFT", 6, -ny); nh:SetTextColor(C(th.gold))
      ny = ny + 18
      y = y + 36
    else
      local f = CreateFrame("Frame", nil, child)
      f:SetPoint("TOPLEFT", 0, -y); f:SetWidth(CW)
      local hasAnim = ch.anim and ANIM[ch.anim]
      local textW = hasAnim and (CW - AW - 30) or (CW - 16)
      f.tag = UI:Text(f, ch.tag == "need" and (GRN .. "GOOD TO KNOW|r") or (GRY .. "OPTIONAL|r"), "small"); f.tag:SetPoint("TOPLEFT", 6, -4)
      f.title = UI:Text(f, ch.title, "large"); f.title:SetPoint("TOPLEFT", 6, -18); f.title:SetWidth(textW); f.title:SetJustifyH("LEFT")
      f.body = UI:Text(f, ch.text, "normal"); f.body:SetPoint("TOPLEFT", 6, -42); f.body:SetWidth(textW); f.body:SetJustifyH("LEFT"); f.body:SetWordWrap(true)
      if f.body.SetSpacing then f.body:SetSpacing(2) end
      local bh = (f.body:GetStringHeight() or 60)
      local show
      if ch.show then
        show = UI:Button(f, "Show me", 90, 22, function() pcall(ch.show) end, "Open this in Command Center.")
        show:SetPoint("TOPLEFT", 6, -(48 + bh))
      end
      local hgt = 48 + bh + (show and 32 or 6)
      if hasAnim then
        local a = S:MakeGuideAnim(f, ch.anim)
        a:SetPoint("TOPRIGHT", -6, -10)
        f.anim = a.update
        hgt = math.max(hgt, AH + 20)
      end
      f:SetHeight(hgt)
      blocks[#blocks + 1] = { f = f, y = y, h = hgt }
      -- contents entry
      local nb = CreateFrame("Button", nil, nchild); nb:SetHeight(18); nb:SetPoint("TOPLEFT", 10, -ny); nb:SetPoint("RIGHT", nchild, "RIGHT", -2, 0)
      nb.t = UI:Text(nb, ch.title, "small"); nb.t:SetPoint("LEFT"); nb.t:SetPoint("RIGHT"); nb.t:SetJustifyH("LEFT"); nb.t:SetWordWrap(false)
      local hl = nb:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.06)
      local target = y
      nb:SetScript("OnClick", function() sf:SetVerticalScroll(math.max(0, target - 6)) end)
      ny = ny + 18
      y = y + hgt + 14
      local sep = child:CreateTexture(nil, "ARTWORK"); sep:SetTexture(WHITE); sep:SetVertexColor(th.line[1], th.line[2], th.line[3], 0.8)
      sep:SetPoint("TOPLEFT", 6, -(y - 8)); sep:SetSize(CW - 12, 1)
    end
  end
  child:SetHeight(y + 20)
  nchild:SetHeight(ny + 10)
  -- chapters fade in as they come into view; animations only run while visible
  local t0 = 0
  win:HookScript("OnUpdate", function(self, el)
    t0 = t0 + el
    local top = sf:GetVerticalScroll() or 0
    local view = sf:GetHeight() or (H - 56)
    for _, b in ipairs(blocks) do
      local rel = b.y - top
      local visible = rel + b.h > 0 and rel < view
      if visible then
        b.seen = math.min(1, (b.seen or 0) + el * 2.5)
        if b.f.anim then pcall(b.f.anim, t0) end
      end
      local a = 0.25 + 0.75 * (b.seen or 0)
      b.f:SetAlpha(a)
      local off = 12 * (1 - (b.seen or 0))
      b.f:ClearAllPoints(); b.f:SetPoint("TOPLEFT", 0, -(b.y + off))
    end
  end)
end

function S:ShowGuide(chapterTitle)
  if not win then build() end
  win:Show(); win:Raise()
  if chapterTitle then
    for _, b in ipairs(blocks) do
      if b.f.title:GetText() == chapterTitle then sf:SetVerticalScroll(math.max(0, b.y - 6)) end
    end
  end
end
function S:ToggleGuide() if win and win:IsShown() then win:Hide() else S:ShowGuide() end end
S:AddCommand("guide", "", "The Guide: every tool and setting explained", function() S:ToggleGuide() end)
