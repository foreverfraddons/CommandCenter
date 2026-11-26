-- Command Center - utility hub and interface upgrade
-- Core: namespace, saved variables, events, helpers, slash commands.
local ADDON, S = ...
_G.CommandCenter = S

S.name       = "Command Center"
S.version    = "3.0.0"
S.versionNum = 30000          -- bump on every release (major*10000 + minor*100 + patch)
S.prefix     = "CMDCTR"
S.support    = "Fatedfr"
S.LOGO        = "Interface\\AddOns\\CommandCenter\\Media\\logo"
S.LOGO_ROUND  = "Interface\\AddOns\\CommandCenter\\Media\\logo_round"
S.LOGO_COORDS = { 0, 1, 0, 1 }
S.roster     = { byName = {}, list = {}, count = 0 }
S.users      = {}             -- addon users seen this session: name -> { v = versionNum, seen = time }

---------------------------------------------------------------------------
-- Events + internal message bus
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
S.eventFrame = eventFrame
local handlers = {}

local function report(err)
  local h = geterrorhandler and geterrorhandler()
  if h then h(err) else print(err) end
end
S.report = report

-- which module file registered a handler (for /ccenter perf)
local owners = {}
local function callerFile()
  local st = debugstack and debugstack(3, 1, 0) or ""
  return st:match("([%w_]+)%.lua") or "?"
end
-- /ccenter perf: while S.perf is set, every handler's time is added up per module + event
local profClock = debugprofilestop
local function profRun(rec, key, fn, ...)
  local g0, t0 = collectgarbage("count"), profClock()
  local ok, err = pcall(fn, ...)
  local dt, dg = profClock() - t0, collectgarbage("count") - g0
  local r = rec[key]
  if not r then r = { t = 0, n = 0, max = 0, g = 0 }; rec[key] = r end
  r.t = r.t + dt; r.n = r.n + 1; if dt > r.max then r.max = dt end
  if dg > 0 then r.g = (r.g or 0) + dg end           -- garbage made (KB); a collection mid-call reads as 0
  return ok, err
end

function S:On(event, fn)
  if not handlers[event] then
    handlers[event] = {}
    owners[event] = {}
    pcall(eventFrame.RegisterEvent, eventFrame, event) -- unknown events in this client are ignored
  end
  table.insert(handlers[event], fn)
  table.insert(owners[event], callerFile() .. "  " .. event)   -- (the key, made once - no garbage while measuring)
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
  local list = handlers[event]
  if not list then return end
  local perf = S.perf
  if perf then
    local own = owners[event]
    for i = 1, #list do
      local ok, err = profRun(perf, own[i], list[i], event, ...)
      if not ok then report(err) end
    end
    return
  end
  for i = 1, #list do
    local ok, err = pcall(list[i], event, ...)
    if not ok then report(err) end
  end
end)

local bus = {}
local busOwners = {}
function S:Listen(msg, fn)
  bus[msg] = bus[msg] or {}
  busOwners[msg] = busOwners[msg] or {}
  table.insert(bus[msg], fn)
  table.insert(busOwners[msg], callerFile() .. "  (msg) " .. msg)
end
function S:Fire(msg, ...)
  local list = bus[msg]
  if not list then return end
  local perf = S.perf
  if perf then
    local own = busOwners[msg]
    for i = 1, #list do
      local ok, err = profRun(perf, own[i], list[i], ...)
      if not ok then report(err) end
    end
    return
  end
  for i = 1, #list do
    local ok, err = pcall(list[i], ...)
    if not ok then report(err) end
  end
end
-- modules can time their own OnUpdate / ticker work for /ccenter perf:
--   frame:SetScript("OnUpdate", S.PerfWrap("UnitFrames  OnUpdate", fn))
function S.PerfWrap(name, fn)
  return function(...)
    local perf = S.perf
    if not perf then return fn(...) end
    local g0, t0 = collectgarbage("count"), profClock()
    local a, b, c = fn(...)
    local dt, dg = profClock() - t0, collectgarbage("count") - g0
    local r = perf[name]
    if not r then r = { t = 0, n = 0, max = 0, g = 0 }; perf[name] = r end
    r.t = r.t + dt; r.n = r.n + 1; if dt > r.max then r.max = dt end
    if dg > 0 then r.g = (r.g or 0) + dg end
    return a, b, c
  end
end

---------------------------------------------------------------------------
-- Item API shims: newer clients moved these into C_Item and removed the old
-- globals, which silently broke every list that shows item links.
---------------------------------------------------------------------------
local CI = C_Item
S.GetItemInfo = (CI and CI.GetItemInfo) or GetItemInfo or function() end
S.GetItemIcon = (CI and CI.GetItemIconByID) or GetItemIcon or function(id) return select(10, S.GetItemInfo(id)) end
S.GetDetailedItemLevelInfo = (CI and CI.GetDetailedItemLevelInfo) or GetDetailedItemLevelInfo or function() end
-- chat helpers (some moved into ChatFrameUtil on newer clients)
local CFU = ChatFrameUtil
-- prefer the newer ChatFrameUtil version: on new clients the old global can be a
-- leftover shim whose filters the chat frames never run
S.AddChatFilter = (CFU and CFU.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter or function() end
S.SendTell = ChatFrame_SendTell or (CFU and CFU.SendTell)
S.OpenChat = ChatFrame_OpenChat or (CFU and CFU.OpenChat)
S.InsertChatLink = function(link)
  if ChatEdit_InsertLink then return ChatEdit_InsertLink(link) end
  if CFU and CFU.InsertLink then return CFU.InsertLink(link) end
end
-- buff name by index (UnitBuff was replaced by C_UnitAuras on newer clients)
function S.UnitBuffName(unit, i)
  if UnitBuff then return (UnitBuff(unit, i)) end
  if C_UnitAuras and C_UnitAuras.GetBuffDataByIndex then
    local a = C_UnitAuras.GetBuffDataByIndex(unit, i)
    return a and a.name
  end
end
-- item link by id ("|cff..|Hitem:..|h[Name]|h|r") or nil if not loaded yet
function S.ItemLink(id)
  if not id then return nil end
  local ok, _, link = pcall(S.GetItemInfo, id)
  if ok then return link end
end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
S.ACCENT_HEX = "4fd1c5"
function S:Print(msg)
  local f = DEFAULT_CHAT_FRAME or ChatFrame1
  if f then f:AddMessage("|cff" .. S.ACCENT_HEX .. "Command Center|r: " .. tostring(msg)) end
end
function S:Debug(...)
  if S.db and S.db.global.debug then S:Print("|cff888888[debug]|r " .. strjoin(" ", tostringall(...))) end
end

function S.now() return (GetServerTime and GetServerTime()) or time() end
function S.date(t, fmt) return date(fmt or "%Y-%m-%d", t or S.now()) end
-- "07-21" -> "July 21" (birthdays and anniversaries)
local MONTHS = { "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December" }
function S.MonthDay(mmdd)
  local m, d = tostring(mmdd or ""):match("^(%d%d?)%-(%d%d?)$")
  m, d = tonumber(m), tonumber(d)
  if not m or not MONTHS[m] then return mmdd end
  return MONTHS[m] .. " " .. d
end
function S.Trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

function S.Split(str, sep)
  local out = {}
  if not str or str == "" then return out end
  for piece in (str .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do
    piece = S.Trim(piece)
    if piece ~= "" then out[#out + 1] = piece end
  end
  return out
end

function S.Copy(t)
  if type(t) ~= "table" then return t end
  local c = {}
  for k, v in pairs(t) do c[k] = S.Copy(v) end
  return c
end

function S.Count(t) local n = 0; for _ in pairs(t or {}) do n = n + 1 end; return n end

function S.Keys(t)
  local k = {}
  for key in pairs(t or {}) do k[#k + 1] = key end
  table.sort(k, function(a, b) return tostring(a) < tostring(b) end)
  return k
end

-- Money with the game's coin icons: 2[g] 84[s] 48[c]. Leading zero units are
-- left out (like the game does), and big gold amounts get thousands separators.
local GOLD_ICON   = "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:2:0|t"
local SILVER_ICON = "|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:2:0|t"
local COPPER_ICON = "|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:2:0|t"
local function thousands(n)
  local s = tostring(n)
  local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  return (out:gsub("^,", ""))
end
function S.Money(copper)
  copper = math.floor(tonumber(copper) or 0)
  local neg = copper < 0
  copper = math.abs(copper)
  local g, s, c = math.floor(copper / 10000), math.floor((copper % 10000) / 100), copper % 100
  local parts = {}
  if g > 0 then parts[#parts + 1] = "|cffffffff" .. thousands(g) .. "|r" .. GOLD_ICON end
  if g > 0 or s > 0 then parts[#parts + 1] = "|cffffffff" .. s .. "|r" .. SILVER_ICON end
  parts[#parts + 1] = "|cffffffff" .. c .. "|r" .. COPPER_ICON
  local str = table.concat(parts, " ")
  return neg and ("-" .. str) or str
end

function S.Ago(t)
  if not t or t == 0 then return "never" end
  local d = S.now() - t
  if d < 60 then return "just now" end
  if d < 3600 then return math.floor(d / 60) .. "m ago" end
  if d < 86400 then return math.floor(d / 3600) .. "h ago" end
  return math.floor(d / 86400) .. "d ago"
end

-- Turn a game format string ("%s rolls %d (%d-%d)") into a Lua match pattern.
local patCache = {}
function S.FmtPattern(fmt)
  if patCache[fmt] then return patCache[fmt] end
  local p = fmt:gsub("%%%d%$", "%%"):gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
  p = p:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
  p = "^" .. p .. "$"
  patCache[fmt] = p
  return p
end

local idCounter = 0
function S:NewId()
  idCounter = idCounter + 1
  return (S.Short(S.me) or "x") .. ":" .. S.now() .. ":" .. idCounter .. ":" .. math.random(100, 999)
end

-- Names: everything is stored as "Name-Realm".
function S.Realm()
  local r = (GetNormalizedRealmName and GetNormalizedRealmName()) or nil
  if not r or r == "" then r = (GetRealmName() or ""):gsub("[%s%-]", "") end
  return r
end
-- WoW Forever uses two-part names ("Baelgor Spiritbane"); each part is
-- capitalized on its own. A first name typed alone is resolved through the
-- guild roster when only one member has that first name.
local function capWords(s)
  return (s:gsub("(%S)(%S*)", function(a, b) return a:upper() .. b:lower() end))
end
-- Names coming from chat / addon messages may be spelled differently from the
-- guild roster (first name only vs first + surname). Map them to the roster key.
local canonCache = {}
function S.Canon(name)
  if not name or not S.roster or not S.roster.byName or S.roster.byName[name] then return name end
  if canonCache[name] ~= nil then return canonCache[name] or name end
  local short, realm = name:match("^(.-)%-([^%-]+)$")
  short = (short or name):lower()
  local flat = short:gsub("[%s_]", "")
  local first = short:match("^(%S+)") or short
  local hit, n = nil, 0
  for member in pairs(S.roster.byName) do
    local ms, mr = member:match("^(.-)%-([^%-]+)$")
    ms = (ms or member):lower()
    if (not realm or not mr or mr == realm) then
      local mflat = ms:gsub("[%s_]", "")
      local mfirst = ms:match("^(%S+)") or ms
      if mflat == flat or mfirst == first or ms == first then hit, n = member, n + 1 end
    end
  end
  -- nobody on that realm: the same character may carry a different realm spelling
  -- (the game hands out names with and without the realm, or a shard's name)
  if n == 0 and realm and realm:match("^[%w]+$") then
    for member in pairs(S.roster.byName) do
      local ms = (member:match("^(.-)%-([^%-]+)$") or member):lower()
      if ms:gsub("[%s_]", "") == flat then hit, n = member, n + 1 end
    end
  end
  canonCache[name] = (n == 1) and hit or false
  return (n == 1) and hit or name
end
S:Listen("ROSTER", function() wipe(canonCache) end)

-- Same character? On WoW Forever every client adds ITS OWN realm to names
-- ("...-CAMWOWUS2Realm9RPPvP" for one player, "...Realm10" for another), so the
-- realm part can't be trusted: compare the roster spelling, then the name alone.
function S.SameName(a, b)
  if not a or not b then return false end
  if a == b then return true end
  local ca, cb = S.Canon(a), S.Canon(b)
  if ca == cb then return true end
  local sa = ((a:match("^(.-)%-[^%-]+$") or a):lower():gsub("[%s_]", ""))
  local sb = ((b:match("^(.-)%-[^%-]+$") or b):lower():gsub("[%s_]", ""))
  return sa == sb
end

function S.Full(name)
  if not name or name == "" then return nil end
  name = S.Trim(name):gsub("%s+", " ")
  if name:find("-", 1, true) then return S.Canon(name) end
  name = capWords(name)
  local full = name .. "-" .. (S.realm or S.Realm())
  if S.roster and S.roster.byName and not S.roster.byName[full] and not name:find(" ", 1, true) then
    local match, n = nil, 0
    local lower = name:lower()
    for member in pairs(S.roster.byName) do
      local first = (member:match("^([^%s%-]+)") or ""):lower()
      if first == lower then match, n = member, n + 1 end
    end
    if n == 1 then return match end
  end
  return S.Canon(full)
end

-- Full, roster-spelled name of a unit ("player", "party1", "raid5", "target"...)
function S.UnitFullName(unit)
  local nm, realm = UnitName(unit)
  if not nm or nm == "" then return nil end
  if realm and realm ~= "" then return S.Full(nm .. "-" .. realm) end
  return S.Full(nm)
end

-- Turn a name someone typed into a guild member's full name.
-- Accepts "Baelgor Spiritbane", "baelgor spiritbane", or just "Baelgor" when only
-- one member has that first name. Prints a helpful message when it can't decide.
function S:Resolve(input, quiet)
  if not input then return nil end
  input = S.Trim(input)
  if input == "" then return nil end
  local full = S.Full(input)
  if self.roster.byName[full] then return full end
  local q = input:lower():gsub("%-[^%-]*$", "")
  local qflat = q:gsub("%s+", "")
  local hits = {}
  for name in pairs(self.roster.byName) do
    local s = (S.Short(name) or ""):lower()
    local first = s:match("^(%S+)") or s
    if s == q or first == q or s:gsub("%s+", "") == qflat then hits[#hits + 1] = name end
  end
  if #hits == 1 then return hits[1] end
  if #hits == 0 then return full end        -- anyone can be whispered, not just people we know
  if not quiet then
    if #hits > 1 then
      table.sort(hits)
      local t = {}
      for _, h in ipairs(hits) do t[#t + 1] = S.Short(h) end
      S:Print("Several people are called '" .. input .. "': " .. table.concat(t, ", ") .. ". Type the full name (first and last).")
    end
  end
  return nil
end
function S.Short(name)
  if not name then return nil end
  return (name:match("^([^-]+)")) or name
end

local function classColorHex(classFile)
  local c = classFile and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[classFile]
  if not c then return "ffffff" end
  return string.format("%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
end
S.ClassHex = classColorHex

-- Class-colored short name (uses roster/gear data when known).
function S:ColorName(name)
  if not name then return "?" end
  local m = self.roster.byName[name]
  local cf = m and m.classFile
  if not cf and self.G then
    local g = self:Get("gear", name)
    cf = g and g.classFile
  end
  return "|cff" .. classColorHex(cf) .. S.Short(name) .. "|r"
end

S.CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
S.ROLES = { "Tank", "Healer", "DPS" }

---------------------------------------------------------------------------
-- Saved variables
---------------------------------------------------------------------------
S.defaults = {
  font = "Friz Quadrata", fontSize = 12, scale = 1.0,
  minimap = { angle = 200, hide = false },
  tutorialDone = false, debug = false, theme = "horde", anim = "smooth",
}

function S:InitDB()
  CommandCenterDB = type(CommandCenterDB) == "table" and CommandCenterDB or {}
  local db = CommandCenterDB
  db.global = db.global or {}
  for k, v in pairs(S.defaults) do
    if db.global[k] == nil then db.global[k] = S.Copy(v) end
  end
  db.data = db.data or {}
  db.data.stores = db.data.stores or {}
  db.data.loc = db.data.loc or {}
  S.db = db
  S.G = db.data          -- this computer's data (reminders, meter history...) - never shared
  S:ImportOldSettings()
end

-- First load: copy your look, bars and tool settings from the addon this replaced
-- (its folder now only holds those settings for us - see STINKY\Import.lua).
local IMPORT_KEYS = { "anim", "barHidden", "barOrder", "bib", "blzBags", "blzButtons", "borderMode", "box", "customTheme",
  "dockMode", "dockTools", "font", "fontSize", "hideBlzBags", "hideBlzMicro", "hideBlzXP", "hideGameMeter", "iconSpacing",
  "iconStyle", "meter", "meterOn", "minimap", "msgWhispersHideChat", "msgr", "msgrPos", "msgrScale", "notifPopups",
  "plugins", "pluginsEnabled", "qb", "qbBorder", "qbCollapsed", "qbDock", "qbXPBars", "reminders", "rotAuraNames",
  "rotChar", "rotClass", "rotation", "scale", "smartChat", "snap", "startMode", "streamer", "theme", "toast",
  "toolShortcuts", "toolsAdded", "toolsHidden", "toolsOrder", "tourLook", "tutorialDone", "wlog" }
local RENAME = { ["Messages"] = "Messenger", ["tool:Messages"] = "tool:Messenger" }
local function renamed(v)
  if type(v) == "string" then return RENAME[v] or v end
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[renamed(k)] = renamed(x) end
  return out
end
function S:ImportOldSettings()
  local g = S.db.global
  if g.importDone then return end
  local old = _G.STINKY_DB
  if type(old) ~= "table" then
    -- the old addon's folder now only holds its settings, loaded just this once
    local load = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
    if load then pcall(load, "STINKY") end
    old = _G.STINKY_DB
  end
  g.importDone = true
  if type(old) ~= "table" or type(old.global) ~= "table" then return end
  local n = 0
  for _, k in ipairs(IMPORT_KEYS) do
    if old.global[k] ~= nil then g[k] = renamed(S.Copy(old.global[k])); n = n + 1 end
  end
  S.importedCount = n
end
function S:CheckGuild() end

-- Small local data stores (same calls the tools have always used; nothing is synced)
S.Stores = {}
function S:DefineStore(name, def) def = def or {}; def.name = name; S.Stores[name] = def end
function S:Data(store)
  if not self.G then return {} end
  local t = self.G.stores[store]
  if not t then t = {}; self.G.stores[store] = t end
  return t
end
function S:Get(store, key)
  if not self.G or key == nil then return nil end
  local r = self:Data(store)[key]
  if r and not r._d then return r end
end
function S:Each(store)
  local data, k = self:Data(store), nil
  return function()
    local r
    repeat k, r = next(data, k) until k == nil or not r._d
    return k, r
  end
end
function S:List(store, filter)
  local out = {}
  for k, r in self:Each(store) do if not filter or filter(r, k) then out[#out + 1] = r; r._key = k end end
  return out
end
function S:Put(store, key, rec)
  if not self.G or key == nil then return end
  rec._t = S.now(); rec._b = S.me
  self:Data(store)[key] = rec
  S:Fire("STORE", store, key, rec)
end
function S:Delete(store, key)
  local d = self:Data(store)
  if d[key] then d[key] = nil; S:Fire("STORE", store, key, nil) end
end

---------------------------------------------------------------------------
-- Guild roster cache
---------------------------------------------------------------------------
local RequestRoster = (C_GuildInfo and C_GuildInfo.GuildRoster) or GuildRoster
local lastRosterReq = 0
function S:RequestRoster(force)
  if not IsInGuild() then return end
  if not force and GetTime() - lastRosterReq < 10 then return end
  lastRosterReq = GetTime()
  if SetGuildRosterShowOffline and GetGuildRosterShowOffline and not GetGuildRosterShowOffline() then
    SetGuildRosterShowOffline(true)
  end
  if RequestRoster then RequestRoster() end
end

function S:ScanRoster()
  local n = GetNumGuildMembers()
  if not n or n == 0 then return end
  local by, list = {}, {}
  local online = 0
  for i = 1, n do
    local name, rankName, rankIndex, level, class, zone, note, onote, isOnline, status, classFile,
      _, _, _, _, _, guid = GetGuildRosterInfo(i)
    if name then
      name = S.Trim(name)
      if not name:find("-", 1, true) then name = name .. "-" .. (S.realm or S.Realm()) end
      local y, mo, d, h = 0, 0, 0, 0
      if not isOnline and GetGuildRosterLastOnline then y, mo, d, h = GetGuildRosterLastOnline(i) end
      local days = isOnline and 0 or ((y or 0) * 365 + (mo or 0) * 30 + (d or 0) + (h or 0) / 24)
      local m = {
        name = name, rank = rankName, rankIndex = rankIndex or 99, level = level or 0, class = class,
        classFile = classFile, zone = zone or "", note = note or "", onote = onote or "",
        online = isOnline and true or false, status = status, days = days, index = i,
      }
      if m.online then online = online + 1 end
      m.guid = guid
      by[name] = m
      list[#list + 1] = m
    end
  end
  S.roster.byName, S.roster.list, S.roster.count, S.roster.online = by, list, #list, online
  S:FixMyName()
  -- does this client include surnames in character names?
  local surnames = false
  for nm in pairs(by) do if (S.Short(nm) or ""):find("[%s_]") then surnames = true break end end
  S.namesHaveSurnames = surnames
  S:Fire("ROSTER")
end

-- Make sure S.me is spelled exactly like our own roster entry. With WoW Forever's
-- two-part names, UnitName() and the guild roster may not spell it the same way
-- (e.g. "Baelgor" vs "Baelgor Spiritbane"); if they differ nothing would count
-- as "me" (no officer tabs, no profile...). Match by GUID, then by name.
function S:FixMyName()
  if not S.me or self.roster.byName[S.me] then return end
  local myGuid = UnitGUID and UnitGUID("player")
  local found
  if myGuid then
    for nm, m in pairs(self.roster.byName) do if m.guid == myGuid then found = nm break end end
  end
  if not found then
    local first = (UnitName("player") or ""):lower()
    local short = (S.Short(S.me) or ""):lower()
    local hits = {}
    for nm in pairs(self.roster.byName) do
      local s = (S.Short(nm) or ""):lower()
      local f = s:match("^(%S+)") or s
      if s == short or f == first or s:gsub("[%s%-]", "") == short:gsub("[%s%-]", "") then hits[#hits + 1] = nm end
    end
    if #hits == 1 then found = hits[1] end
  end
  if not found then
    local c = S.Canon(S.me)
    if c ~= S.me and self.roster.byName[c] then found = c end
  end
  if found and found ~= S.me then
    S:Debug("player name corrected:", S.me, "->", found)
    S.me = found
    S:Fire("ME_CHANGED")
  end
end

function S:Member(name) return name and self.roster.byName[name] end
function S:IsMember(name)
  if not name then return false end
  if self.roster.byName[name] ~= nil then return true end
  local c = S.Canon(name)
  return c ~= name and self.roster.byName[c] ~= nil
end
function S:RankOf(name) local m = self.roster.byName[name]; return m and m.rankIndex end
function S:IsOnline(name) local m = self.roster.byName[name]; return m and m.online end
function S:RosterIndex(name)
  -- roster indexes shift; re-find by name
  local n = GetNumGuildMembers() or 0
  for i = 1, n do
    local nm = GetGuildRosterInfo(i)
    if nm and S.Full(nm) == name then return i end
  end
end

-- (no guild ranks or permissions: everything is open to everyone)
function S:IsOfficer() return false end
function S:IsOfficerName() return false end
function S:IsGM() return false end

-- Whisper / invite helpers (must be called from a click) -------------------
-- The name the game expects when you whisper / invite someone. In WoW Forever
-- the realm part is internal ("Baelgor Spiritbane-CAMWOWUS2Realm10RPPvP") and
-- whispering that fails with "No player named ... is currently playing", so we
-- drop our own realm and just use "Baelgor Spiritbane".
function S.TargetName(name)
  if not name then return nil end
  local short, realm = name:match("^(.-)%-([^%-]+)$")
  if short and (realm == S.realm or realm == S.Realm()) then return short end
  return name
end
local T = S.TargetName

function S:PartyInvite(name)
  name = T(name)
  if C_PartyInfo and C_PartyInfo.InviteUnit then C_PartyInfo.InviteUnit(name) elseif InviteUnit then InviteUnit(name) end
end
function S:Whisper(name, msg)
  S.msgrSending = (S.msgrSending or 0) + 1
  C_Timer.After(3, function() S.msgrSending = math.max(0, (S.msgrSending or 0) - 1) end)
  SendChatMessage(msg, "WHISPER", nil, T(name))
end
function S:OpenWhisper(name, msg)
  -- ChatFrame_SendTell handles names with spaces (two-part Forever names)
  name = T(name)
  local sendTell = ChatFrame_SendTell or (ChatFrameUtil and ChatFrameUtil.SendTell)
  if sendTell then
    sendTell(name)
    if msg and msg ~= "" then
      local eb = (ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()) or (ChatEdit_ChooseBoxForSend and ChatEdit_ChooseBoxForSend())
      if eb then eb:Insert(msg) end
    end
  elseif S.OpenChat then
    S.OpenChat("/w " .. name .. " " .. (msg or ""))
  end
end

-- Fill {name},{class},{guild},{level},{me} tokens.
function S:Fill(template, vars)
  vars = vars or {}
  return (tostring(template or ""):gsub("{(%w+)}", function(k)
    if k == "me" then return S.Short(S.me) or "" end
    local v = vars[k]
    if v == nil then return "{" .. k .. "}" end
    return tostring(v)
  end))
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
S:On("ADDON_LOADED", function(_, name)
  if name ~= ADDON then return end
  S:InitDB()
  S:Fire("DB_READY")
end)

S:On("PLAYER_LOGIN", function()
  S.realm = S.Realm()
  S.me = S.Full(UnitName("player"))
  -- (no math.randomseed: some game versions don't have it, and the game seeds random numbers itself)
  S:Fire("LOGIN")
  S:RequestRoster(true)
  C_Timer.NewTicker(120, function() S:RequestRoster() end)
  if S.importedCount and S.importedCount > 0 then
    C_Timer.After(6, function()
      S:Print("Your look, bars and tool settings were copied over. New here? |cffffff00/ccenter tour|r shows you around.")
    end)
  end
  -- the old full addon still running next to us: everything would show twice
  if _G.STINKY and _G.STINKY ~= S and not CC_STINKY_IMPORT then
    C_Timer.After(8, function()
      S:Print("|cffff6060The old STINKY addon is still installed.|r Command Center replaces it - delete or disable the STINKY folder in your AddOns.")
    end)
  end
  S:Print("v" .. S.version .. " loaded. Type |cffffff00/ccenter|r to open it (|cffffff00/ccenter help|r for commands).")
end)


-- If the game ever blocks one of our addons, say which function it was so it
-- can be fixed (the game's own popup doesn't name it). Kept in CommandCenterDB too.
local OUR_ADDONS = { CommandCenter = true }
local function blocked(_, addon, func)
  if not OUR_ADDONS[addon or ""] then return end
  -- what was under the mouse / were we fighting: helps find the culprit
  local focus
  local ok, f = pcall(function()
    if GetMouseFoci then return (GetMouseFoci())[1] end
    if GetMouseFocus then return GetMouseFocus() end
  end)
  if ok and f and f.GetName then
    local ok2, n = pcall(f.GetName, f)
    if ok2 and type(n) == "string" and not (issecretvalue and issecretvalue(n)) then focus = n end
  end
  local ctx = {}
  if InCombatLockdown and InCombatLockdown() then ctx[#ctx + 1] = "in combat" end
  if focus then ctx[#ctx + 1] = "mouse over " .. focus end
  if GameTooltip and GameTooltip.IsShown and GameTooltip:IsShown() then ctx[#ctx + 1] = "tooltip open" end
  if S.lastAction and GetTime and GetTime() - S.lastAction.at < 30 then
    ctx[#ctx + 1] = string.format("%.0fs after clicking %s", GetTime() - S.lastAction.at, tostring(S.lastAction.what))
  end
  local line = date("%Y-%m-%d %H:%M") .. "  " .. tostring(addon) .. " -> " .. tostring(func) .. (#ctx > 0 and ("  (" .. table.concat(ctx, ", ") .. ")") or "")
  if S.db then
    S.db.global.blockLog = S.db.global.blockLog or {}
    table.insert(S.db.global.blockLog, 1, line)
    while #S.db.global.blockLog > 20 do table.remove(S.db.global.blockLog) end
  end
  S:Print("|cffff5555The game blocked|r " .. tostring(addon) .. " from calling |cffffd100" .. tostring(func) ..
    "|r. Please send this line to " .. S.support .. ". (|cffffff00/ccenter blocked|r lists them)")
end
S:On("ADDON_ACTION_BLOCKED", blocked)
S:On("ADDON_ACTION_FORBIDDEN", blocked)

local rosterPending = false
S:On("GUILD_ROSTER_UPDATE", function()
  if rosterPending then return end
  rosterPending = true
  C_Timer.After(1, function() rosterPending = false; S:ScanRoster() end)
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
S.commands = {}   -- { cmd, args, desc, fn }
function S:AddCommand(cmd, args, desc, fn)
  table.insert(S.commands, { cmd = cmd, args = args, desc = desc, fn = fn })
end

SLASH_COMMANDCENTER1, SLASH_COMMANDCENTER2 = "/ccenter", "/commandcenter"
SlashCmdList.COMMANDCENTER = function(input)
  input = S.Trim(input)
  local cmd, rest = input:match("^(%S*)%s*(.-)$")
  cmd = (cmd or ""):lower()
  if cmd == "" then if S.ToggleMain then S:ToggleMain() end return end
  for _, c in ipairs(S.commands) do
    if c.cmd == cmd then c.fn(rest) return end
  end
  if S.tabsById and S.tabsById[cmd] then S:ShowMain(cmd) return end
  S:Print("Unknown command '" .. cmd .. "'. Type /ccenter help.")
end

S:AddCommand("help", "", "List all commands", function()
  S:Print("Commands:")
  for _, c in ipairs(S.commands) do
    print(string.format("  |cffffff00/ccenter %s %s|r - %s", c.cmd, c.args, c.desc))
  end
end)
S:AddCommand("blocked", "", "List actions the game blocked (for bug reports)", function()
  local log = S.db and S.db.global.blockLog or {}
  if #log == 0 then S:Print("Nothing has been blocked.") return end
  S:Print("Blocked actions (newest first):")
  for _, l in ipairs(log) do print("  " .. l) end
end)
-- /ccenter debug [on|off] = Debug mode (performance tools, Perf.lua); /ccenter debug messages = the old debug chat lines
S:AddCommand("debug", "[on|off|messages]", "Debug mode (performance tools); 'messages' toggles debug chat lines", function(arg)
  arg = arg and S.Trim(arg):lower() or ""
  if arg == "messages" or not S.PerfDebug then
    S.db.global.debug = not S.db.global.debug
    S:Print("Debug messages " .. (S.db.global.debug and "on" or "off"))
    return
  end
  if arg == "on" then S:PerfDebug(true) elseif arg == "off" then S:PerfDebug(false) else S:PerfDebug() end
end)
