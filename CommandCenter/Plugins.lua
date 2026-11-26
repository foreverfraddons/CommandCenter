-- Plugins: put other addons' minimap icons into the dock / border bar.
-- Works with LibDataBroker launchers (what most minimap icons are, via LibDBIcon) and
-- with plain minimap buttons whose name matches an installed addon. You pick which
-- addons from the list of everything installed.
local _, S = ...
local UI = S.UI

local OWN = { CommandCenter = true }
local QMARK = "Interface\\Icons\\INV_Misc_QuestionMark"
-- Our own addons wear the theme inside Command Center: their minimap icon / launcher shows a
-- white glyph tinted with the theme gold (like every Command Center tool). On their own they
-- keep their personal icons - this only changes what the dock / border bar / Button Box draws.
local NATIVE = {
  Questicus = "Interface\\AddOns\\Questicus\\Media\\i_questicus",
  StinkyFart = "Interface\\AddOns\\CommandCenter\\Media\\UI\\i_stinkyfart",
  Radialz = "Interface\\AddOns\\CommandCenter\\Media\\UI\\i_radialz",
  HealAssist = "Interface\\AddOns\\CommandCenter\\Media\\UI\\i_heal",
}
local FULL = { 0, 1, 0, 1 }
S.NativeIcons = NATIVE

local function G() return S.db.global end
local function selected()
  local g = G()
  g.plugins = type(g.plugins) == "table" and g.plugins or {}
  return g.plugins
end
local function norm(s)
  s = tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
  return (s:lower():gsub("[^%w]", ""))
end

---------------------------------------------------------------------------
-- Installed addons
---------------------------------------------------------------------------
-- cached: the list only changes when an addon loads (rebuilding it scanned every addon's
-- title with several gsubs - the Minimap's box fill called it every few seconds)
local installedCache
function S:InstalledAddons()
  if installedCache then return installedCache end
  local out = {}
  local CA = C_AddOns
  local num = (CA and CA.GetNumAddOns and CA.GetNumAddOns()) or (GetNumAddOns and GetNumAddOns()) or 0
  for i = 1, num do
    local name, title
    if CA and CA.GetAddOnInfo then name, title = CA.GetAddOnInfo(i) elseif GetAddOnInfo then name, title = GetAddOnInfo(i) end
    if name and not name:find("^Blizzard_") and not OWN[name] then
      local loaded = (CA and CA.IsAddOnLoaded and CA.IsAddOnLoaded(name)) or (IsAddOnLoaded and IsAddOnLoaded(name))
      local clean = tostring(title or name):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
      out[#out + 1] = { name = name, title = clean, loaded = loaded and true or false, n = norm(name), nt = norm(clean) }
    end
  end
  table.sort(out, function(a, b) return a.n < b.n end)
  installedCache = out
  return out
end
local guessCache = {}   -- frame name -> owner addon / false (quest and map pins are named frames too)
S:On("ADDON_LOADED", function() installedCache = nil; wipe(guessCache) end)

-- which installed addon an icon most likely belongs to
local function stem(n)
  n = norm(n)
  for _, suf in ipairs({ "minimapbutton", "minimapicon", "minimap", "button", "broker", "launcher", "ldb", "icon" }) do
    if #n > #suf + 2 and n:sub(-#suf) == suf then n = n:sub(1, -#suf - 1) end
  end
  n = n:gsub("^libdbicon10", ""):gsub("^broker", "")
  return n
end
local function guessAddon(name, addons)
  local n = stem(name)
  if n == "" then return nil end
  for _, a in ipairs(addons) do if a.n == n or a.nt == n then return a.name end end
  local best, bl = nil, 0
  for _, a in ipairs(addons) do
    for _, an in ipairs({ a.n, a.nt }) do
      if #an >= 4 and #n >= 4 and (n:find(an, 1, true) == 1 or an:find(n, 1, true) == 1) and #an > bl then best, bl = a.name, #an end
    end
  end
  return best
end
S.PluginGuessAddon = guessAddon

---------------------------------------------------------------------------
-- Icons found on this client
---------------------------------------------------------------------------
-- Blizzard's own minimap buttons are never touched (clicking those from an addon can break things)
local SKIP = { "^Minimap", "^MiniMap", "^GameTime", "^TimeManager", "^QueueStatus", "^Garrison", "^ExpansionLandingPage",
  "^GuildInstanceDifficulty", "^LibDBIcon10_", "^CC_", "^HybridMinimap", "^AddonCompartment", "^Blizzard",
  "^LFG", "^Battlefield", "^MinimapZone", "^Durability", "^VehicleSeat", "^Instance" }
local function skipName(n)
  for _, p in ipairs(SKIP) do if n:find(p) then return true end end
  return false
end
local BORDER_IDS = { [136430] = true, [136467] = true, [136477] = true }
local function buttonIcon(f)
  local cand = f.icon or f.Icon
  if cand and cand.GetTexture and cand:GetTexture() then return cand:GetTexture(), cand.GetTexCoord and { cand:GetTexCoord() } or nil end
  for _, r in ipairs({ f:GetRegions() }) do
    if r.GetObjectType and r:GetObjectType() == "Texture" and r.GetTexture then
      local tex = r:GetTexture()
      local ts = tostring(tex or "")
      if tex and not BORDER_IDS[tonumber(tex) or 0] and not ts:find("Border") and not ts:find("Background") and not ts:find("Highlight") then
        return tex, r.GetTexCoord and { r:GetTexCoord() } or nil
      end
    end
  end
end
local function pretty(n)
  n = tostring(n):gsub("_?[Mm]ini[Mm]ap_?[Bb]utton$", ""):gsub("_?[Mm]ini[Mm]ap$", ""):gsub("_?[Bb]utton$", ""):gsub("_", " ")
  return n
end

function S:PluginSources()
  local out, seen = {}, {}
  local addons = S:InstalledAddons()
  local LDB = LibStub and LibStub.GetLibrary and LibStub:GetLibrary("LibDataBroker-1.1", true)
  if LDB and LDB.DataObjectIterator then
    for name, obj in LDB:DataObjectIterator() do
      if type(obj) == "table" and (obj.type == "launcher" or (obj.icon and obj.OnClick)) and not OWN[name] and not tostring(name):find("^CommandCenter") then
        out[#out + 1] = { id = "ldb:" .. name, name = obj.label or name, kind = "ldb", obj = obj, owner = guessAddon(name, addons) }
        seen[stem(name)] = true
      end
    end
  end
  -- plain minimap buttons (not LibDBIcon): only ones whose name matches an installed addon
  local function scan(parent)
    if not parent or not parent.GetChildren then return end
    for _, c in ipairs({ parent:GetChildren() }) do
      local n = c.GetName and c:GetName()
      if n and guessCache[n] ~= false and c.GetObjectType and c:GetObjectType() == "Button" and not skipName(n) and not seen[stem(n)] then
        local owner = guessCache[n]
        if owner == nil then owner = guessAddon(n, addons) or false; guessCache[n] = owner end
        if owner then
          out[#out + 1] = { id = "btn:" .. n, name = pretty(n), kind = "button", frame = c, owner = owner }
          seen[stem(n)] = true
        end
      end
    end
  end
  scan(Minimap); scan(_G.MinimapBackdrop)
  return out, addons
end

---------------------------------------------------------------------------
-- Dock / border bar items
---------------------------------------------------------------------------
local function failed(src, err)
  S.report(err)
  S:Print("Plugin |cffffd100" .. (src.name or "?") .. "|r" .. (src.owner and (" (" .. src.owner .. ")") or "") ..
    " had a problem. Let Fatedfr know which addon it was and it can get a fix.")
end
local function makeItem(src)
  local it = { key = "plug:" .. src.id, label = src.name, plugin = true, pluginId = src.id, owner = src.owner }
  if src.kind == "ldb" then
    local obj = src.obj
    it.iconFn = function() return obj.icon or QMARK, obj.iconCoords end
    if obj.iconR then it.color = { obj.iconR, obj.iconG, obj.iconB } end
    it.click = function(frame, btn)
      if not obj.OnClick then return end
      local ok, err = pcall(obj.OnClick, frame, btn); if not ok then failed(src, err) end
    end
    if obj.OnTooltipShow then
      it.tip = function(tt)
        local ok, err = pcall(obj.OnTooltipShow, tt); if not ok then tt:AddLine(src.name, 1, 0.82, 0); failed(src, err) end
      end
    elseif obj.OnEnter then
      it.enter = function(frame) local ok, err = pcall(obj.OnEnter, frame); if not ok then failed(src, err) end end
      it.leave = obj.OnLeave and function(frame) pcall(obj.OnLeave, frame) end
    end
  else
    local f = src.frame
    it.iconFn = function() local tex, co = buttonIcon(f); return tex or QMARK, co end
    it.click = function(_, btn)
      local ok, err = pcall(function()
        if f:GetScript("OnClick") then f:Click(btn)
        else
          local down, up = f:GetScript("OnMouseDown"), f:GetScript("OnMouseUp")
          if down then down(f, btn) end
          if up then up(f, btn) end
        end
      end)
      if not ok then failed(src, err) end
    end
    it.tip = function(tt) tt:AddLine(src.name, 1, 0.82, 0) end
  end
  local glyph = src.owner and NATIVE[src.owner]
  if glyph then
    it.iconFn = function() return glyph, FULL end
    it.tint, it.color = true, nil
  end
  return it
end

-- all = every icon found (for the Button Box), otherwise only the addons picked here
function S:PluginItems(all)
  if not all and not G().pluginsEnabled then return {} end
  local sel = selected()
  local items = {}
  for _, src in ipairs((S:PluginSources())) do
    if all or (src.owner and sel[src.owner]) or sel[src.id] then items[#items + 1] = makeItem(src) end
  end
  return items
end

---------------------------------------------------------------------------
-- No double buttons: an addon icon that's on the dock / border bar or in the
-- Button Box has its own minimap button hidden. It comes back when you take the
-- icon off again (or turn this off in the Plugins window).
---------------------------------------------------------------------------
local hiddenByUs = {}
local function minimapFrame(src)
  if src.kind == "button" then return src.frame end
  local name = src.id:gsub("^ldb:", "")
  local DBI = LibStub and LibStub.GetLibrary and LibStub:GetLibrary("LibDBIcon-1.0", true)
  local f = DBI and DBI.GetMinimapButton and DBI:GetMinimapButton(name)
  return f or _G["LibDBIcon10_" .. name]
end
local function keepHidden(f)
  if f.__ccHide then return end
  f.__ccHide = true
  -- the addon (or LibDBIcon) may show it again later: hide it straight back
  f:HookScript("OnShow", function(self) if hiddenByUs[self] then self:Hide() end end)
end
function S:PluginSyncMinimap()
  if not S.db then return end
  local use = {}
  if G().pluginHideMinimap ~= false then
    local function mark(keys) for k in pairs(keys or {}) do if type(k) == "string" and k:find("^plug:") then use[k:sub(6)] = true end end end
    if S.QuickBarKeysInUse then mark(S:QuickBarKeysInUse()) end
    if S.ButtonBoxKeys then mark(S:ButtonBoxKeys()) end
  end
  if not next(use) and not next(hiddenByUs) then return end
  for _, src in ipairs((S:PluginSources())) do
    local f = minimapFrame(src)
    if f and f.Hide then
      if use[src.id] then
        keepHidden(f)
        if not hiddenByUs[f] then hiddenByUs[f] = true; f:Hide() end
      elseif hiddenByUs[f] then
        hiddenByUs[f] = nil
        f:Show()
      end
    end
  end
end

function S:PluginRemove(it)
  local sel = selected()
  if it.owner then sel[it.owner] = nil end
  if it.pluginId then sel[it.pluginId] = nil end
  if S.QuickBarLayout then S:QuickBarLayout() end
  if S.RefreshPlugins then S:RefreshPlugins() end
end

local relayoutPending
local function relayout()
  if relayoutPending then return end
  if S.RefreshButtonBox then C_Timer.After(1.1, function() S:RefreshButtonBox() end) end
  relayoutPending = true
  C_Timer.After(1, function()
    relayoutPending = false
    local g = G()
    if g.pluginsEnabled and (g.dockMode or g.borderMode) and S.QuickBarLayout then S:QuickBarLayout() end
    if S.RefreshPlugins then S:RefreshPlugins() end
  end)
end

---------------------------------------------------------------------------
-- The Plugins window: pick addons from everything installed
---------------------------------------------------------------------------
local win, tbl
local function rows()
  local sources, addons = S:PluginSources()
  local byOwner, other = {}, {}
  for _, src in ipairs(sources) do
    if src.owner then byOwner[src.owner] = byOwner[src.owner] or {}; table.insert(byOwner[src.owner], src.name)
    else other[#other + 1] = src end
  end
  local q = win and (win.search:GetText() or ""):lower() or ""
  local sel = selected()
  local out = {}
  for _, a in ipairs(addons) do
    if q == "" or a.name:lower():find(q, 1, true) or a.title:lower():find(q, 1, true) then
      out[#out + 1] = { key = a.name, label = a.title, on = sel[a.name] and true or false, icons = byOwner[a.name], loaded = a.loaded }
    end
  end
  for _, src in ipairs(other) do
    if q == "" or src.name:lower():find(q, 1, true) then
      out[#out + 1] = { key = src.id, label = src.name .. "  |cff888888(icon)|r", on = sel[src.id] and true or false, icons = { src.name }, loaded = true, other = true }
    end
  end
  table.sort(out, function(x, y)
    if (x.icons ~= nil) ~= (y.icons ~= nil) then return x.icons ~= nil end
    return norm(x.label) < norm(y.label)
  end)
  return out
end
function S:RefreshPlugins()
  if not win or not win:IsShown() then return end
  win.enable:SetChecked(G().pluginsEnabled and true or false)
  local g = G()
  win.mode:SetText((g.dockMode or g.borderMode) and "" or "|cffffd100Plugins show in dock mode and border mode.|r Turn one on in Settings > Quickbar & dock.")
  tbl:SetData(rows())
end
function S:ShowPlugins()
  if not win then
    win = UI:Window("CC_Plugins", "Plugins", 500, 570)
    win:SetFrameStrata("HIGH")
    win.enable = UI:Check(win, "Enable plugins (other addons' minimap icons in your dock / border bar)", G().pluginsEnabled, function(v)
      G().pluginsEnabled = v and true or false
      if S.QuickBarLayout then S:QuickBarLayout() end
    end)
    win.enable:SetPoint("TOPLEFT", 14, -36)
    win.note = UI:Text(win, "|cffff9933Please note:|r |cffccccccsome addons may not work here - there are far too many to test them all. If one doesn't, tell Fatedfr (Baelgor Spiritbane) which addon it is and compatibility can be added.|r", "small")
    win.note:SetPoint("TOPLEFT", 16, -62); win.note:SetWidth(468); win.note:SetJustifyH("LEFT"); win.note:SetWordWrap(true)
    win.hideMM = UI:Check(win, "Hide their minimap buttons while they're on the bar or in the Button Box", G().pluginHideMinimap ~= false, function(v)
      G().pluginHideMinimap = v and true or false
      S:PluginSyncMinimap()
    end)
    win.hideMM:SetPoint("TOPLEFT", 14, -122)
    win.mode = UI:Text(win, "", "small"); win.mode:SetPoint("TOPLEFT", 16, -96); win.mode:SetWidth(468); win.mode:SetJustifyH("LEFT")
    win.search = UI:Edit(win, 300, 22, "Search addons...")
    win.search:SetPoint("TOPLEFT", 14, -150)
    win.search:HookScript("OnTextChanged", function() S:RefreshPlugins() end)
    local rescan = UI:Button(win, "Rescan", 80, 22, function() S:RefreshPlugins(); if S.QuickBarLayout then S:QuickBarLayout() end end, "Look for minimap icons again (some addons create them late).")
    rescan:SetPoint("LEFT", win.search, "RIGHT", 8, 0)
    tbl = UI:Table(win, 472, 540 - 184 - 30, {
      { title = "", w = 28, get = function(r) return r.on and "|TInterface\\Buttons\\UI-CheckBox-Check:16|t" or "|cff555555-|r" end },
      { title = "AddOn", w = 230, get = function(r) return (r.loaded and "" or "|cff777777") .. r.label .. (r.loaded and "" or "|r") end },
      { title = "Minimap icon", w = 210, get = function(r)
          if r.icons then return "|cff55ff55" .. table.concat(r.icons, ", ") .. "|r" end
          return r.loaded and "|cff888888none found|r" or "|cff666666not loaded|r"
        end },
    }, { emptyText = "No other addons installed.",
         rowColor = function(r) if r.on then return 0.2, 0.8, 0.2, 0.12 end end,
         onClick = function(r)
           local sel = selected()
           sel[r.key] = not r.on or nil
           if sel[r.key] and not G().pluginsEnabled then G().pluginsEnabled = true end
           if sel[r.key] and not r.icons then
             S:Print("|cffffd100" .. r.label .. "|r is on your list, but no minimap icon was found for it" .. (r.loaded and "" or " (it isn't loaded)") .. ". It'll show up once it makes one.")
           end
           S:RefreshPlugins()
           if S.QuickBarLayout then S:QuickBarLayout() end
         end })
    tbl:SetPoint("TOPLEFT", 14, -180)
    win.foot = UI:Text(win, "|cff888888Click an addon to add / remove it. Right-click a plugin icon: its own menu.  Ctrl-right-click: remove it from the bar.|r", "small")
    win.foot:SetPoint("BOTTOMLEFT", 16, 10); win.foot:SetWidth(468)
    win:HookScript("OnShow", function() S:RefreshPlugins() end)
  end
  win:Show(); win:Raise(); S:RefreshPlugins()
end

-- addons create their icons at different times: look again when new ones appear
S:Listen("LOGIN", function()
  local LDB = LibStub and LibStub.GetLibrary and LibStub:GetLibrary("LibDataBroker-1.1", true)
  if LDB and LDB.RegisterCallback then
    local cb = {}
    pcall(LDB.RegisterCallback, cb, "LibDataBroker_DataObjectCreated", function() relayout() end)
  end
  C_Timer.After(5, relayout)
end)

S:AddCommand("plugins", "", "Pick other addons' minimap icons for the dock / border bar", function() S:ShowPlugins() end)
