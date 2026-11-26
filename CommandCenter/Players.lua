-- Players: everything the game will tell us about another player, in one place.
--   * S.PlayerInfo(name): merges your target / group, friends list, Battle.net friends,
--     your guild roster, /who results and what we remembered from last time
--   * unique avatars (each name always gets the same picture)
--   * the player profile window (View profile), Add friend
--   * /r in game chat opens the Messenger on the person you'd be replying to
local _, S = ...
if S.ModuleRev then S:ModuleRev("MessengerPlayers", 4) end
local UI = S.UI

local function G() return S.db.global end
local function clean(v) if issecretvalue and issecretvalue(v) then return nil end return v end
-- the name alone: "Name-Realm" and "Name-" (empty realm, WoW Forever) -> "Name"
local function short(n)
  if type(n) ~= "string" then return n end
  if S.MsgName then return S.MsgName(n) end
  n = n:gsub("%-+$", "")
  return n:match("^(.-)%-[^%-]+$") or n
end
local function same(a, b)
  if not a or not b then return false end
  -- the whole name, never just the first name (Core's S.SameName / S.Canon match first
  -- names, which glued two different "Karl"s together)
  return short(a):lower() == short(b):lower()
end

---------------------------------------------------------------------------
-- Remembered facts (so a profile still says something when they're offline)
---------------------------------------------------------------------------
local function memory()
  local g = G()
  g.people = type(g.people) == "table" and g.people or {}
  return g.people
end
local function remember(name, t)
  if not name or not t then return end
  local m = memory()
  local key = short(name)
  local r = m[key] or {}
  for k, v in pairs(t) do if v ~= nil and v ~= "" then r[k] = v end end
  r.seen = time()
  m[key] = r
  -- keep it small: forget the oldest beyond 400 people
  local n = 0
  for _ in pairs(m) do n = n + 1 end
  if n > 400 then
    local oldest, ok
    for k, v in pairs(m) do if not ok or (v.seen or 0) < (oldest.seen or 0) then ok, oldest = k, v end end
    if ok then m[ok] = nil end
  end
end

---------------------------------------------------------------------------
-- Sources
---------------------------------------------------------------------------
local UNITS = { "target", "focus", "mouseover" }
for i = 1, 4 do UNITS[#UNITS + 1] = "party" .. i end
for i = 1, 40 do UNITS[#UNITS + 1] = "raid" .. i end
local function unitFor(name)
  if not name then return end
  if same(name, S.me) then return "player" end
  for _, u in ipairs(UNITS) do
    if UnitExists and UnitExists(u) and UnitIsPlayer and UnitIsPlayer(u) then
      local ok, n, realm = pcall(UnitName, u)
      n, realm = ok and clean(n), ok and clean(realm)
      if n and same(n .. ((realm and realm ~= "") and ("-" .. realm) or ""), name) then return u end
    end
  end
end
S.PlayerUnit = unitFor

local function fromUnit(u)
  local t = {}
  pcall(function()
    t.level = clean(UnitLevel(u))
    local cl, cf = UnitClass(u); t.class, t.classFile = clean(cl), clean(cf)
    t.race = clean((UnitRace(u)))
    local gn, gr = GetGuildInfo(u); t.guild, t.guildRank = clean(gn), clean(gr)
    t.faction = clean((UnitFactionGroup(u)))
    t.online = true
    t.inGroup = (UnitInParty and UnitInParty(u)) or (UnitInRaid and UnitInRaid(u)) or false
    if UnitIsAFK and UnitIsAFK(u) then t.status = "Away" elseif UnitIsDND and UnitIsDND(u) then t.status = "Busy" end
  end)
  return t
end

local function fromFriends(name)
  local CF = C_FriendList
  local n = CF and CF.GetNumFriends and CF.GetNumFriends() or 0
  for i = 1, n do
    local info = CF.GetFriendInfoByIndex and CF.GetFriendInfoByIndex(i)
    if info and info.name and same(info.name, name) then
      return { friend = true, level = info.level, class = info.className, area = info.area, online = info.connected,
        note = info.notes, status = info.afk and "Away" or info.dnd and "Busy" or nil }
    end
  end
end

-- Battle.net friends who are on a WoW character right now
local function bnetFriends()
  local out = {}
  local n = (BNGetNumFriends and BNGetNumFriends()) or 0
  for i = 1, n do
    local ok, acc = pcall(function() return C_BattleNet and C_BattleNet.GetFriendAccountInfo and C_BattleNet.GetFriendAccountInfo(i) end)
    if ok and type(acc) == "table" then
      local ga = acc.gameAccountInfo
      if type(ga) == "table" and ga.characterName and ga.characterName ~= "" and ga.isOnline ~= false then
        out[#out + 1] = { name = ga.characterName .. ((ga.realmName and ga.realmName ~= "" and ga.realmName ~= GetRealmName()) and ("-" .. ga.realmName) or ""),
          tag = acc.battleTag or acc.accountName, area = ga.areaName, level = ga.characterLevel, class = ga.className, race = ga.raceName,
          faction = ga.factionName, client = ga.clientProgram, rich = ga.richPresence, note = acc.note, online = true, wow = (ga.clientProgram == (BNET_CLIENT_WOW or "WoW")) }
      end
    end
  end
  return out
end
S.BNetWoWFriends = bnetFriends
local function fromBNet(name)
  for _, f in ipairs(bnetFriends()) do if same(f.name, name) then return f end end
end

local whoCache = {}
local function fromWho(name) return whoCache[short(name):lower()] end

local function fromGuild(name)
  local m = S.Member and S:Member(name)
  if not m and S.roster then for nm, x in pairs(S.roster.byName or {}) do if same(nm, name) then m = x break end end end
  if not m then return end
  return { level = m.level, class = m.class, classFile = m.classFile, area = m.zone, online = m.online, guildRank = m.rank,
    guild = GetGuildInfo and GetGuildInfo("player"), gnote = m.note ~= "" and m.note or nil, days = m.days }
end

-- everything we know, newest source wins
function S.PlayerInfo(name)
  local info = { name = name }
  local function merge(t) if t then for k, v in pairs(t) do if v ~= nil and v ~= "" then info[k] = v end end end end
  local mem = memory()[short(name or "")]
  if mem then merge(mem); info.fromMemory = true; info.online = nil end
  merge(fromWho(name))
  merge(fromGuild(name))
  local f = fromFriends(name); merge(f)
  local b = fromBNet(name); merge(b); if b then info.bnet = true end
  local u = unitFor(name)
  if u then merge(fromUnit(u)); info.unit = u end
  if S.OnlineState then info.online = S.OnlineState(name) end
  -- turn a class name into the class token (for colours and the class badge)
  if info.class and not info.classFile and LOCALIZED_CLASS_NAMES_MALE then
    for tok, nm in pairs(LOCALIZED_CLASS_NAMES_MALE) do if nm == info.class then info.classFile = tok end end
    if not info.classFile and LOCALIZED_CLASS_NAMES_FEMALE then
      for tok, nm in pairs(LOCALIZED_CLASS_NAMES_FEMALE) do if nm == info.class then info.classFile = tok end end
    end
  end
  remember(name, { level = info.level, class = info.class, classFile = info.classFile, race = info.race, guild = info.guild,
    guildRank = info.guildRank, area = info.online and info.area or nil, faction = info.faction })
  return info
end

function S:IsFriend(name) return fromFriends(name) ~= nil end
function S:AddFriend(name)
  if not name then return end
  local target = S.TargetName and S.TargetName(name) or short(name)
  local ok = pcall(function()
    if C_FriendList and C_FriendList.AddFriend then C_FriendList.AddFriend(target) elseif AddFriend then AddFriend(target) end
  end)
  if ok then S:Print("Friend request / add sent for |cffffd100" .. short(name) .. "|r.") end
  C_Timer.After(1, function() if S.RefreshPlayer then S:RefreshPlayer() end end)
end

-- /who lookup. The game blocks addons from doing this except straight from a click or
-- key press - calling it any other time is what caused "action blocked" errors.
-- So automatic lookups only get *queued*; they go out on your next click / keystroke
-- in the Messenger or the profile window (S:LookupPending is called from those handlers).
local whoWanted, whoAt = nil, 0
local tried, notFound = {}, {}   -- short lower name -> GetTime() of last try / time() nobody was found
local pendingAuto
local function now() return GetTime and GetTime() or 0 end
local function setWhoToUi(on)
  pcall(function() if C_FriendList and C_FriendList.SetWhoToUi then C_FriendList.SetWhoToUi(on) elseif SetWhoToUI then SetWhoToUI(on and 1 or 0) end end)
end
local ourWhoUntil = 0      -- while our own lookup is answering, any window it pops open is shut again
local panelsBefore = {}
local function panelNames()
  local out = {}
  for nm in pairs(UIPanelWindows or {}) do out[#out + 1] = nm end
  for _, nm in ipairs(UISpecialFrames or {}) do out[#out + 1] = nm end
  for _, nm in ipairs({ "FriendsFrame", "WhoFrame", "LFGParentFrame", "LFGListingFrame", "LFGBrowseFrame", "PVEFrame" }) do out[#out + 1] = nm end
  return out
end
local function snapshotPanels()
  wipe(panelsBefore)
  for _, nm in ipairs(panelNames()) do
    local f = _G[nm]
    if type(f) == "table" and f.IsShown and f:IsShown() then panelsBefore[nm] = true end
  end
end
local function shut(f, nm)
  if type(f) ~= "table" or not f.IsShown or not f:IsShown() then return end
  if nm and panelsBefore[nm] then return end
  if InCombatLockdown and InCombatLockdown() then return end
  if not pcall(HideUIPanel, f) or f:IsShown() then pcall(f.Hide, f) end
end
-- shut whatever window our lookup opened (the Who / Looking For Group window)
local function shutNew()
  for _, nm in ipairs(panelNames()) do if not panelsBefore[nm] then shut(_G[nm], nm) end end
end
local hookedShow = false
local function hookPanels()
  if hookedShow then return end
  hookedShow = true
  if hooksecurefunc and ShowUIPanel then
    hooksecurefunc("ShowUIPanel", function(f)
      if now() > ourWhoUntil or type(f) ~= "table" then return end
      local nm = f.GetName and f:GetName()
      if nm and panelsBefore[nm] then return end
      C_Timer.After(0, function() if now() <= ourWhoUntil + 1 then shut(f, nm) end end)
    end)
  end
end
-- results of a small /who come back as chat lines when the Who window is off: read them
-- (and keep them out of your chat) instead of opening the window
local function fmtPattern(f)
  if type(f) ~= "string" then return nil end
  f = f:gsub("|4[^;]*;", "\001")
  f = f:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
  f = f:gsub("%%s", "(.-)"):gsub("%%d", "(%%d+)"):gsub("\001", ".-")
  return "^" .. f .. "$"
end
local function onWhoResult(name, t)
  local k = short(name):lower()
  t.whoAt = time()
  whoCache[k] = t; notFound[k] = nil
  remember(name, t)
end
local function finishWho(found)
  if not whoWanted then return end
  if not found then notFound[whoWanted:lower()] = time() end
  whoWanted = nil
  C_Timer.After(0, shutNew)
  C_Timer.After(0.3, shutNew)
  C_Timer.After(1.5, function() ourWhoUntil = 0 end)
  if S.RefreshPlayer then S:RefreshPlayer() end
  S:Fire("PLAYER_INFO")
end
local whoLineFound = false
S.AddChatFilter("CHAT_MSG_SYSTEM", function(_, _, msg)
  if now() > ourWhoUntil or type(msg) ~= "string" or (issecretvalue and issecretvalue(msg)) then return false end
  local pg, pl, pt = fmtPattern(WHO_LIST_GUILD_FORMAT), fmtPattern(WHO_LIST_FORMAT), fmtPattern(WHO_NUM_RESULTS)
  local link, _, lvl, race, cls, guild, zone
  if pg then link, _, lvl, race, cls, guild, zone = msg:match(pg) end
  if not link and pl then link, _, lvl, race, cls, zone = msg:match(pl) end
  if link then
    onWhoResult(link, { level = tonumber(lvl), race = race, class = cls, guild = guild, area = zone })
    if whoWanted and short(link):lower() == whoWanted:lower() then whoLineFound = true end
    return true
  end
  if pt and msg:match(pt) then
    local f = whoLineFound
    whoLineFound = false
    C_Timer.After(0, function() finishWho(f) end)
    return true
  end
  return false
end)

-- Stop error catchers (BugGrabber / BugSack and the like) from reporting the
-- "AddOn 'CommandCenter' tried to call the protected function 'SendWho()'" notice for
-- our own lookup: every frame listening for ADDON_ACTION_BLOCKED stops listening for a
-- moment and gets it back right after. Returns the function that restores them.
function S.MuteBlockedReports()
  local list
  if GetFramesRegisteredForEvent then
    list = { GetFramesRegisteredForEvent("ADDON_ACTION_BLOCKED") }
  elseif EnumerateFrames then
    list = {}
    local f = EnumerateFrames()
    while f do
      if f.IsEventRegistered and f:IsEventRegistered("ADDON_ACTION_BLOCKED") then list[#list + 1] = f end
      f = EnumerateFrames(f)
    end
  else
    return nil
  end
  local muted = {}
  -- use the real frame methods: some catchers (BugGrabber) replace their own
  -- Register/UnregisterEvent with do-nothing functions
  local function method(f, name)
    local mt = getmetatable(f)
    local idx = type(mt) == "table" and mt.__index
    local m = type(idx) == "table" and rawget(idx, name) or nil
    return m or f[name]
  end
  for _, f in ipairs(list) do
    if type(f) == "table" and f ~= UIParent then
      local un = method(f, "UnregisterEvent")
      if un and pcall(un, f, "ADDON_ACTION_BLOCKED") then muted[#muted + 1] = f end
    end
  end
  return function()
    for _, f in ipairs(muted) do
      local re = method(f, "RegisterEvent")
      if re then pcall(re, f, "ADDON_ACTION_BLOCKED") end
    end
    wipe(muted)
  end
end
-- backup: if an error catcher still stored the SendWho notice, take it back out
function S.ForgetBlockedReports()
  local BG = _G.BugGrabber
  if type(BG) ~= "table" then return end
  local ok, db = pcall(function() return BG.GetDB and BG:GetDB() end)
  if not ok or type(db) ~= "table" then return end
  for i = #db, 1, -1 do
    local e = db[i]
    local m = type(e) == "table" and e.message or nil
    if type(m) == "string" and m:find("CommandCenter", 1, true) and m:find("SendWho", 1, true) then table.remove(db, i) end
  end
end
-- only call from a click / key handler
function S:WhoLookup(name, auto)
  if not name then return end
  whoWanted = short(name); whoAt = now()
  tried[whoWanted:lower()] = now()
  hookPanels(); snapshotPanels()
  ourWhoUntil = now() + 6
  whoLineFound = false
  setWhoToUi(false)        -- answer in (hidden) chat lines, not the Who / Looking For Group window
  local q = 'n-"' .. whoWanted .. '"'
  -- the game still answers, but reports a "blocked action" for it; keep that report quiet
  local muted = S.MuteBlockedReports and S.MuteBlockedReports()
  local ok = pcall(function() if C_FriendList and C_FriendList.SendWho then C_FriendList.SendWho(q) elseif SendWho then SendWho(q) end end)
  -- the notice can arrive a moment later, so stay muted a little while
  if muted then C_Timer.After(1.5, muted) end
  C_Timer.After(2, function() if S.ForgetBlockedReports then S.ForgetBlockedReports() end end)
  if not ok and not auto then S:Print("The game didn't allow a lookup right now - try again in a moment.") end
  C_Timer.After(6, function() if whoWanted and now() - whoAt >= 5.9 then finishWho(false) end end)
end
-- do we still need to look this person up?
local function needsLookup(name)
  if not name or same(name, S.me) then return false end
  local k = short(name):lower()
  local w = whoCache[k]
  if w and w.whoAt and time() - w.whoAt < 1800 then return false end
  if notFound[k] and time() - notFound[k] < 600 then return false end
  if unitFor(name) or fromFriends(name) or fromBNet(name) then return false end
  local t = tried[k]
  if t and now() - t < 30 then return false end
  return true
end
-- a conversation started / you opened one: queue a lookup (never sends by itself)
function S:AutoLookup(name)
  if not S.db or G().msgAutoLookup == false or not needsLookup(name) then return end
  pendingAuto = name
end
-- called from click / key handlers only
function S:LookupPending()
  if not pendingAuto then return end
  if whoWanted and now() - whoAt < 5 then return end
  local n = pendingAuto
  pendingAuto = nil
  if S.db and G().msgAutoLookup ~= false and needsLookup(n) then S:WhoLookup(n, true) end
end
S:On("WHO_LIST_UPDATE", function()
  local n = (C_FriendList and C_FriendList.GetNumWhoResults and C_FriendList.GetNumWhoResults()) or (GetNumWhoResults and GetNumWhoResults()) or 0
  local found = false
  for i = 1, n do
    local w
    if C_FriendList and C_FriendList.GetWhoInfo then w = C_FriendList.GetWhoInfo(i)
    elseif GetWhoInfo then local nm, g, lv, race, cl, zone, cf = GetWhoInfo(i); w = { fullName = nm, fullGuildName = g, level = lv, raceStr = race, classStr = cl, area = zone, filename = cf } end
    if type(w) == "table" and type(w.fullName) == "string" and not (issecretvalue and issecretvalue(w.fullName)) then
      local t = { level = w.level, race = w.raceStr, class = w.classStr, classFile = w.filename, guild = (w.fullGuildName and w.fullGuildName ~= "") and w.fullGuildName or nil,
        area = w.area, whoAt = time() }
      local k = short(w.fullName):lower()
      onWhoResult(w.fullName, t)
      if whoWanted and k == whoWanted:lower() then found = true end
    end
  end
  if whoWanted then finishWho(found) end
end)

---------------------------------------------------------------------------
-- Online or not: true / false / nil (don't know)
---------------------------------------------------------------------------
local lastHeard, offlineAt = {}, {}
local stateCache = {}
function S.MarkHeardFrom(name)
  if not name then return end
  local k = short(name):lower()
  lastHeard[k] = time(); offlineAt[k] = nil; stateCache[k] = nil
end
function S.OnlineState(name)
  if not name then return nil end
  local k = short(name):lower()
  local c = stateCache[k]
  local t = now()
  if c and t - c.t < 1 then return c.v end
  local v
  if unitFor(name) then v = true end
  if v == nil then
    local f = fromFriends(name)
    if f then v = f.online and true or false end
  end
  if v == nil and fromBNet(name) then v = true end
  if v == nil then
    local g = fromGuild(name)
    if g then v = g.online and true or false end
  end
  if v == nil then
    local recent = math.max(lastHeard[k] or 0, (whoCache[k] and whoCache[k].whoAt) or 0)
    local off = math.max(offlineAt[k] or 0, notFound[k] or 0)
    if recent > 0 or off > 0 then
      if off > recent and time() - off < 900 then v = false
      elseif recent >= off and time() - recent < 900 then v = true end
    end
  end
  stateCache[k] = { t = t, v = v }
  return v
end
-- "No player named 'X' is currently playing." -> offline
S:On("CHAT_MSG_SYSTEM", function(_, msg)
  if type(msg) ~= "string" or (issecretvalue and issecretvalue(msg)) or not ERR_CHAT_PLAYER_NOT_FOUND_S then return end
  local pat = "^" .. ERR_CHAT_PLAYER_NOT_FOUND_S:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%%%s", "(.+)") .. "$"
  local who = msg:match(pat)
  if who then
    offlineAt[short(who):lower()] = time(); stateCache[short(who):lower()] = nil
    S:Fire("PLAYER_INFO")
  end
end)

---------------------------------------------------------------------------
-- Avatars: every name gets its own picture (always the same one), with a small
-- class badge in the corner when we know their class
---------------------------------------------------------------------------
local PICS = {
  "INV_Misc_Head_Orc_01", "INV_Misc_Head_Troll_01", "INV_Misc_Head_Tauren_01", "INV_Misc_Head_Undead_01", "INV_Misc_Head_Human_01",
  "INV_Misc_Head_Dwarf_01", "INV_Misc_Head_Gnome_01", "INV_Misc_Head_Elf_01", "INV_Misc_Head_Dragon_01", "INV_Misc_Head_Murloc_01",
  "INV_Misc_Head_Kobold_01", "Ability_Hunter_Pet_Wolf", "Ability_Hunter_Pet_Bear", "Ability_Hunter_Pet_Cat", "Ability_Hunter_Pet_Owl",
  "Ability_Hunter_Pet_Raptor", "Ability_Hunter_Pet_Gorilla", "Ability_Hunter_Pet_Boar", "Ability_Hunter_Pet_Crab", "Ability_Hunter_Pet_Turtle",
  "Ability_Hunter_Pet_Spider", "Ability_Hunter_Pet_Bat", "Ability_Hunter_Pet_Hyena", "Ability_Hunter_Pet_Scorpid", "Ability_Hunter_Pet_Vulture",
  "Ability_Hunter_Pet_WindSerpent", "Ability_Hunter_Pet_TallStrider", "Ability_Mount_Raptor", "Ability_Mount_WhiteTiger", "INV_Misc_Fish_02",
  "INV_Mushroom_11", "Spell_Nature_Polymorph", "INV_Misc_Bomb_04", "INV_Misc_Gem_Pearl_04", "Spell_Fire_Fire", "Spell_Frost_FrostBolt02",
  "Spell_Shadow_ShadowBolt", "Spell_Holy_HolyBolt", "Spell_Nature_Lightning", "INV_Misc_Rune_01",
}
local function hash(s)
  local h = 5381
  s = tostring(s or ""):lower()
  for i = 1, #s do h = (h * 33 + s:byte(i)) % 2147483647 end
  return h
end
local function customPics() local g = G(); g.avatars = type(g.avatars) == "table" and g.avatars or {}; return g.avatars end
function S.AvatarFor(name)
  local c = S.db and customPics()[short(name):lower()]
  if c then return (type(c) == "string" and not c:find("\\")) and ("Interface\\Icons\\" .. c) or c end
  return "Interface\\Icons\\" .. PICS[hash(short(name)) % #PICS + 1]
end
function S.SetCustomAvatar(name, icon)
  if not name then return end
  customPics()[short(name):lower()] = icon
  S:Fire("MSGR_STYLE"); S:Fire("PLAYER_INFO")
  if S.RefreshPlayer then S:RefreshPlayer() end
end
function S.SetAvatar(tex, name)
  if not tex or not name then return end
  tex:SetTexture(S.AvatarFor(name)); tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  -- class badge in the corner
  local parent = tex:GetParent()
  if parent and parent.CreateTexture then
    local b = tex.__cls
    if not b then
      b = parent:CreateTexture(nil, "OVERLAY", nil, 6)
      local w = tex:GetWidth() or 36
      b:SetSize(math.max(10, w * 0.42), math.max(10, w * 0.42))
      b:SetPoint("TOPLEFT", tex, "TOPLEFT", -2, 2)
      tex.__cls = b
    end
    local mem = memory()[short(name)]
    local cf = mem and mem.classFile
    if not cf and S.Member then local m = S:Member(name); cf = m and m.classFile end
    local co = cf and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[cf]
    if co then b:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles"); b:SetTexCoord(co[1], co[2], co[3], co[4]); b:Show() else b:Hide() end
  end
end

---------------------------------------------------------------------------
-- Profile window
---------------------------------------------------------------------------
local pwin, who
local function armoryLink(name)
  local region = (GetCurrentRegionName and GetCurrentRegionName()) or "us"
  region = tostring(region):lower()
  local n = short(name):lower():gsub("%s+", "-")
  return "https://worldofwarcraft.blizzard.com/en-us/forever/" .. region .. "/armory/character/" .. n
end
local function ago(t)
  if not t then return nil end
  local d = time() - t
  if d < 120 then return "just now" elseif d < 3600 then return math.floor(d / 60) .. " minutes ago"
  elseif d < 86400 then return math.floor(d / 3600) .. " hours ago" end
  return math.floor(d / 86400) .. " days ago"
end

function S:RefreshPlayer()
  if not pwin or not pwin:IsShown() or not who then return end
  local i = S.PlayerInfo(who)
  local hex = S.ClassHex and S.ClassHex(i.classFile) or "ffffff"
  S.SetAvatar(pwin.av, who)
  local shown = S.DisplayName and S.DisplayName(who) or short(who)
  -- name (+ service icons) on one line; their real name under it when a nickname / main shows
  pwin.name:SetFontObject(UI.fTitle)
  pwin.name:SetText("|cff" .. hex .. shown .. "|r" .. (S.ServiceIcons and S.ServiceIcons(who, 16) or ""))
  if (pwin.name:GetStringWidth() or 0) > (pwin.name:GetWidth() or 999) then pwin.name:SetFontObject(UI.fLarge) end
  pwin.real:SetText(shown ~= short(who) and ("|cff888888" .. short(who) .. "|r") or "")
  pwin.real:SetHeight(shown ~= short(who) and 14 or 1)
  local line = {}
  if i.level and i.level ~= 0 then line[#line + 1] = "Level " .. i.level end
  if i.race then line[#line + 1] = i.race end
  if i.class then line[#line + 1] = "|cff" .. hex .. i.class .. "|r" end
  pwin.sub:SetText(#line > 0 and table.concat(line, " ") or "|cff888888Level, race and class unknown - target them, group up or press Look up|r")
  local rows = {}
  local function add(k, v) if v and v ~= "" then rows[#rows + 1] = { k, v } end end
  local status
  if i.online == true then status = "|cff55ff55Online|r" .. (i.status and (" - " .. i.status) or "")
  elseif i.online == false then status = "|cff999999Offline|r" .. (i.days and i.days > 0 and (" (" .. math.floor(i.days) .. " days)") or "")
  else status = "|cff999999Not sure|r" end
  add("Status", status)
  local oc = S.OnlineChar and S.OnlineChar(who)
  if oc and short(oc):lower() ~= short(who):lower() then add("Playing", "|cff55ff55Online on " .. short(oc) .. "|r") end
  add("Guild", i.guild and ("<" .. i.guild .. ">" .. (i.guildRank and ("  |cff888888" .. i.guildRank .. "|r") or "")))
  add("Where", i.area)
  add("Faction", i.faction)
    if i.bnet then add("Battle.net", (i.tag or "") .. (i.client and i.client ~= "WoW" and ("  |cff888888" .. i.client .. "|r") or "")) end
  add("Friend", i.friend and "|cff55ff55On your friends list|r" or (i.bnet and "|cff00aaffBattle.net friend|r") or "No")
  add("Nickname", S.NicknameOf and S.NicknameOf(who))
  local note = S.NoteOf and S.NoteOf(who)
  if note then rows[#rows + 1] = { "My note", note, true } end
  if S.ServiceNames then local sv = S.ServiceNames(who); if sv ~= "" then add("Services", sv) end end
  local main = S.MainOf and S.MainOf(who)
  if main and short(main):lower() ~= short(who):lower() then add("Alt of", S.DisplayName(main) .. (S.DisplayName(main) ~= short(main) and ("  |cff888888(" .. short(main) .. ")|r") or "")) end
  local alts = S.AltsOf and S.AltsOf(who) or {}
  if #alts > 0 then
    local t = {}; for _, a in ipairs(alts) do t[#t + 1] = a:sub(1, 1):upper() .. a:sub(2) end
    add("Alts", table.concat(t, ", "))
  end
  add("Friend note", i.note)
  add("Guild note", i.gnote)
  if i.fromMemory and not i.unit and not i.friend then add("Last seen", ago(i.seen)) end
  if i.whoAt then add("Looked up", ago(i.whoAt)) end
  local y = -128
  for n, r in ipairs(rows) do
    local row = pwin.rows[n]
    if not row then
      row = CreateFrame("Frame", nil, pwin); row:SetSize(372, 20)
      row.k = UI:Text(row, "", "small"); row.k:SetPoint("TOPLEFT", 0, -4); row.k:SetWidth(96); row.k:SetJustifyH("LEFT")
      row.v = UI:Text(row, "", "normal"); row.v:SetPoint("TOPLEFT", 104, -3); row.v:SetWidth(268); row.v:SetJustifyH("LEFT")
      if row.v.SetJustifyV then row.v:SetJustifyV("TOP") end
      pwin.rows[n] = row
    end
    row:ClearAllPoints(); row:SetPoint("TOPLEFT", 20, y)
    row.k:SetText("|cffffd100" .. r[1] .. "|r")
    -- the note may take up to 3 lines (hover the row to read all of it)
    row.v:SetWordWrap(r[3] and true or false)
    if row.v.SetMaxLines then row.v:SetMaxLines(r[3] and 3 or 1) end
    row.v:SetHeight(0); row.v:SetText(r[2])
    local h = 20
    if r[3] then
      local one = select(2, row.v:GetFont()) or 12
      local th = math.min(row.v:GetStringHeight() or one, (one + 2) * 3)
      row.v:SetHeight(th); h = math.max(20, th + 6)
    else
      row.v:SetHeight(14)
    end
    row:SetHeight(h)
    row.full = r[3] and r[2] or nil
    if not row.tipSet then
      row.tipSet = true
      row:EnableMouse(true)
      row:SetScript("OnEnter", function(self)
        if not self.full then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine("My note", 1, 0.82, 0)
        GameTooltip:AddLine(self.full, 1, 1, 1, true); GameTooltip:AddLine("Change it with the Note button.", 0.6, 0.6, 0.6, true); GameTooltip:Show()
      end)
      row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    row:Show()
    y = y - h - 2
  end
  for n = #rows + 1, #pwin.rows do pwin.rows[n]:Hide() end
  pwin.addFriend:SetEnabled(not i.friend)
  pwin.addFriend:SetText(i.friend and "Friends" or "Add friend")
  pwin.invite:SetEnabled(i.online ~= false)
  local m = S.MainOf(who)
  pwin.ctB:SetText(S.IsContact(who) and "Remove contact" or "Add contact")
  pwin.altB:SetText((m and short(m):lower() ~= short(who):lower()) and "Not an alt" or "Alt of...")
end

function S:ShowPlayer(name)
  if not name then return end
  who = name
  if not pwin then
    pwin = UI:Window("CC_Player", "Player", 412, 516)
    pwin.av = pwin:CreateTexture(nil, "ARTWORK"); pwin.av:SetSize(64, 64); pwin.av:SetPoint("TOPLEFT", 20, -44)
    local avBtn = CreateFrame("Button", nil, pwin); avBtn:SetAllPoints(pwin.av)
    avBtn:SetScript("OnClick", function() S:PickAvatar(who) end)
    UI:Tip(avBtn, "Change picture", "Click to pick any icon in the game for this person.")
    pwin.name = UI:Text(pwin, "", "title"); pwin.name:SetPoint("TOPLEFT", pwin.av, "TOPRIGHT", 14, -4)
    pwin.name:SetPoint("RIGHT", pwin, "RIGHT", -16, 0); pwin.name:SetWordWrap(false); pwin.name:SetJustifyH("LEFT")
    pwin.real = UI:Text(pwin, "", "small"); pwin.real:SetPoint("TOPLEFT", pwin.name, "BOTTOMLEFT", 0, -3)
    pwin.real:SetPoint("RIGHT", pwin, "RIGHT", -16, 0); pwin.real:SetWordWrap(false); pwin.real:SetJustifyH("LEFT")
    pwin.sub = UI:Text(pwin, "", "normal"); pwin.sub:SetPoint("TOPLEFT", pwin.real, "BOTTOMLEFT", 0, -5)
    pwin.sub:SetPoint("RIGHT", pwin, "RIGHT", -16, 0); pwin.sub:SetWordWrap(true); pwin.sub:SetJustifyH("LEFT")
    pwin.rows = {}
    local function btn(txt, w, fn, tip) return UI:Button(pwin, txt, w, 24, fn, tip) end
    local msg = btn("Message", 86, function() if S.ShowMessenger then S:ShowMessenger(who) end end, "Whisper them in the Messenger.")
    msg:SetPoint("BOTTOMLEFT", 16, 50)
    local svcB = btn("Services...", 96, function() S:ShowServices(who) end, "What they offer: professions, summons, portals, food & water... shows as icons after their name.")
    svcB:SetPoint("BOTTOMLEFT", 16, 82)
    pwin.ctB = btn("Add contact", 110, function() S.ToggleContact(who) end, "Contacts sit as bubbles across the top of your Messenger inbox.")
    pwin.ctB:SetPoint("LEFT", svcB, "RIGHT", 6, 0)
    local picB = btn("Picture...", 90, function() S:PickAvatar(who) end, "Pick any icon in the game as their picture.")
    picB:SetPoint("LEFT", pwin.ctB, "RIGHT", 6, 0)
    local noteB = btn("Note...", 66, function() S:AskNote(who) end, "Write a note about them - only you see it. It shows on their profile (and on all their alts).")
    noteB:SetPoint("LEFT", picB, "RIGHT", 6, 0)
    pwin.invite = btn("Invite", 70, function() if S.PartyInvite then S:PartyInvite(who) end end, "Invite to your group.")
    pwin.invite:SetPoint("LEFT", msg, "RIGHT", 6, 0)
    pwin.addFriend = btn("Add friend", 96, function() S:AddFriend(who) end, "Put them on your friends list.")
    pwin.addFriend:SetPoint("LEFT", pwin.invite, "RIGHT", 6, 0)
    local look = btn("Look up", 80, function() S:WhoLookup(who) end, "Ask the game who they are (/who): level, race, class, guild and where they are - if they're online.")
    look:SetPoint("LEFT", pwin.addFriend, "RIGHT", 6, 0)
    local arm = btn("Armory link", 110, function() if UI.CopyBox then UI:CopyBox("Armory link - copy it (Ctrl+C)", armoryLink(who)) end end,
      "Their armory page on the WoW website - copy the link and open it in your browser.")
    arm:SetPoint("BOTTOMLEFT", 16, 18)
    local copyName = btn("Copy name", 84, function() if UI.CopyBox then UI:CopyBox("Name - copy it (Ctrl+C)", short(who)) end end)
    copyName:SetPoint("LEFT", arm, "RIGHT", 6, 0)
    local nickB = btn("Nickname", 86, function() S:AskNickname(who) end, "Give them a name of your own - it shows instead of theirs everywhere.")
    nickB:SetPoint("LEFT", copyName, "RIGHT", 6, 0)
    pwin.altB = btn("Alt of...", 76, function()
      local m = S.MainOf(who)
      if m and short(m):lower() ~= short(who):lower() then S.SetAltOf(who, nil) else S:AskAltOf(who) end
    end, "Mark them as an alt of another character (their main). Their whispers then show under the main's name.")
    pwin.altB:SetPoint("LEFT", nickB, "RIGHT", 6, 0)
    pwin:HookScript("OnShow", function() S:RefreshPlayer() end)
    pwin:HookScript("OnMouseDown", function() S:LookupPending() end)
  end
  pwin:Show(); pwin:Raise()
  S:AutoLookup(name)
  S:RefreshPlayer()
end
S.ShowProfile = S.ShowPlayer          -- every "View profile" lands here

for _, ev in ipairs({ "FRIENDLIST_UPDATE", "BN_FRIEND_INFO_CHANGED", "BN_FRIEND_ACCOUNT_ONLINE", "BN_FRIEND_ACCOUNT_OFFLINE",
  "GROUP_ROSTER_UPDATE", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "GUILD_ROSTER_UPDATE" }) do
  S:On(ev, function()
    if pwin and pwin:IsShown() then S:RefreshPlayer() end
    -- learn about people as we see them
    if ev == "PLAYER_TARGET_CHANGED" or ev == "UPDATE_MOUSEOVER_UNIT" then
      local u = ev == "PLAYER_TARGET_CHANGED" and "target" or "mouseover"
      if UnitExists and UnitExists(u) and UnitIsPlayer and UnitIsPlayer(u) and not UnitIsUnit(u, "player") then
        local ok, n, realm = pcall(UnitName, u)
        n, realm = ok and clean(n), ok and clean(realm)
        if n then remember(n .. ((realm and realm ~= "") and ("-" .. realm) or ""), fromUnit(u)) end
      end
    end
  end)
end
S:AddCommand("player", "<name>", "Profile of any player: level, class, guild, where they are...", function(arg)
  if arg and S.Trim(arg) ~= "" then S:ShowPlayer(S.Trim(arg)) elseif UnitExists("target") and UnitIsPlayer("target") then S:ShowPlayer((UnitName("target"))) end
end)

---------------------------------------------------------------------------
-- /r in game chat: open the Messenger on the person you'd be replying to
---------------------------------------------------------------------------
local function lastPartner()
  local t = ChatEdit_GetLastTellTarget and ChatEdit_GetLastTellTarget()
  if type(t) == "string" and t ~= "" and not (issecretvalue and issecretvalue(t)) then return t end
  -- fall back to the Messenger's own log: whoever you talked with last
  local best, bt
  for other, list in pairs(S.WhisperThreads and S:WhisperThreads() or {}) do
    local e = list[#list]
    if e and (not bt or (e.time or 0) > bt) then best, bt = other, e.time or 0 end
  end
  return best
end
S.LastWhisperPartner = lastPartner
local hooked = {}
local function hookBox(box)
  if not box or hooked[box] then return end
  hooked[box] = true
  box:HookScript("OnTextChanged", function(self, user)
    if not user or not S.db or G().replyOpensMessenger == false then return end
    local txt = self:GetText()
    if type(txt) ~= "string" or (issecretvalue and issecretvalue(txt)) then return end
    if txt:lower():match("^/r%s$") or txt:lower():match("^/reply%s$") then
      local target = lastPartner()
      if not target or not S.ShowMessenger then return end
      local box = self
      C_Timer.After(0, function()
        -- close the game's whisper line so you type in the Messenger instead
        if ChatEdit_DeactivateChat then pcall(ChatEdit_DeactivateChat, box) end
        S:ShowMessenger(target)
      end)
    end
  end)
end
-- Saved names from before: "jean heels-" / "Name-Realm" keys and values -> the name alone
local function tidyNames()
  local g = G()
  local function rekey(t, lower, fixVal)
    if type(t) ~= "table" then return end
    local moves = {}
    for k, v in pairs(t) do
      local nk = type(k) == "string" and short(k) or k
      if lower and type(nk) == "string" then nk = nk:lower() end
      if fixVal then v = fixVal(v) ; t[k] = v end
      if nk ~= k then moves[#moves + 1] = { k, nk, v } end
    end
    for _, m in ipairs(moves) do
      t[m[1]] = nil
      if t[m[2]] == nil then t[m[2]] = m[3]
      elseif type(t[m[2]]) == "table" and type(m[3]) == "table" then
        for f, x in pairs(m[3]) do if t[m[2]][f] == nil then t[m[2]][f] = x end end
      end
    end
  end
  local function fixName(v) if type(v) == "string" then return short(v) end; return v end
  local function fixRec(v) if type(v) == "table" then if v.name then v.name = short(v.name) end; if v._name then v._name = short(v._name) end end; return v end
  rekey(g.people, false, nil)
  rekey(g.nicknames, true, nil)
  rekey(g.altOf, true, fixName)
  rekey(g.services, true, fixRec)
  rekey(g.contacts, true, fixRec)
  rekey(g.avatars, true, nil)
  rekey(g.pnotes, true, nil)
  rekey(g.hiddenConvos, true, nil)
end
S.MsgTidyNames = tidyNames
S:Listen("LOGIN", function() if S.db then pcall(tidyNames) end end)
S:Listen("LOGIN", function()
  for i = 1, (NUM_CHAT_WINDOWS or 10) do hookBox(_G["ChatFrame" .. i .. "EditBox"]) end
end)

---------------------------------------------------------------------------
-- Icon picker: every icon the game has (macro icons + item icons)
---------------------------------------------------------------------------
local allIcons
local function iconList()
  if allIcons then return allIcons end
  allIcons = {}
  local function grab(fn) if type(fn) == "function" then local t = {}; pcall(fn, t); for _, v in ipairs(t) do allIcons[#allIcons + 1] = v end end end
  grab(GetLooseMacroIcons); grab(GetMacroIcons); grab(GetLooseMacroItemIcons); grab(GetMacroItemIcons)
  if #allIcons == 0 then for _, p in ipairs(PICS) do allIcons[#allIcons + 1] = p end end
  return allIcons
end
local function iconPath(v)
  if type(v) == "number" then return v end
  if type(v) == "string" and not v:find("\\") then return "Interface\\Icons\\" .. v end
  return v
end
-- Icon names: the game's icon list has no names, so we learn them from spells
-- (every spell has a name and an icon). Built once, a little each frame, the
-- first time you search.
local iconNames = {}      -- icon -> "lowercase spell names" (a few, joined)
local iconTitle = {}      -- icon -> first spell name (for the tooltip)
local iconRaw = {}        -- icon -> "Spell Name|Other Name" (kept: saved and shipped)
local indexDone, indexing, indexPct = false, false, 0
local function gameBuild()
  local v, b = GetBuildInfo and GetBuildInfo()
  return tostring(v or "?") .. "-" .. tostring(b or "?")
end
local function learn(ic, raw)
  if not ic or not raw or raw == "" then return end
  local cur = iconRaw[ic]
  if cur then
    for n in raw:gmatch("[^|]+") do
      if #cur < 90 and not cur:lower():find(n:lower(), 1, true) then cur = cur .. "|" .. n end
    end
  else cur = raw end
  iconRaw[ic] = cur
  iconNames[ic] = cur:lower()
  iconTitle[ic] = cur:match("^[^|]+")
end
-- names found before (saved), and the list that ships with the addon (IconNames.lua)
local loadedKnown = false
local function loadKnown()
  if loadedKnown then return end
  loadedKnown = true
  if type(S.ICON_NAMES) == "table" then for ic, raw in pairs(S.ICON_NAMES) do learn(ic, raw) end end
  local saved = S.db and G().iconIndex
  if type(saved) == "table" and type(saved.names) == "table" then for ic, raw in pairs(saved.names) do learn(ic, raw) end end
  -- already complete for this game version: no need to look again
  local b = gameBuild()
  if (type(saved) == "table" and saved.done and saved.build == b) or (S.ICON_NAMES_BUILD == b) then indexDone = true; indexPct = 100 end
end
local function saveKnown()
  if not S.db then return end
  G().iconIndex = { build = gameBuild(), done = true, names = iconRaw, at = time() }
end
S.IconNamesKnown = function() local n = 0; for _ in pairs(iconRaw) do n = n + 1 end; return n end
local onIndexStep
local function spellNameIcon(id)
  if C_Spell and C_Spell.GetSpellName then
    local n = C_Spell.GetSpellName(id)
    if n then return n, C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id) end
    return nil
  end
  if GetSpellInfo then local n, _, ic = GetSpellInfo(id); return n, ic end
end
local function startIndex()
  loadKnown()
  if indexDone or indexing then return end
  indexing = true
  local id, misses, MAXID = 1, 0, 1600000
  local runner = CreateFrame("Frame")
  local clock = debugprofilestop or function() return GetTime() * 1000 end
  runner:SetScript("OnUpdate", function(self)
    local t0 = clock()
    while clock() - t0 < 6 do
      for _ = 1, 400 do
        local ok, n, ic = pcall(spellNameIcon, id)
        if ok and n and ic and n ~= "" then
          misses = 0
          if not issecretvalue or not issecretvalue(n) then learn(ic, n) end
        else
          misses = misses + 1
        end
        id = id + 1
        if id > MAXID or misses > 250000 then
          indexDone, indexing = true, false
          self:SetScript("OnUpdate", nil)
          indexPct = 100
          saveKnown()          -- found once, kept for next time
          if onIndexStep then onIndexStep(true) end
          return
        end
      end
    end
    indexPct = math.min(99, math.floor(id / 4000))   -- rough: most spell ids are below ~400k
    if onIndexStep then onIndexStep(false) end
  end)
end
S.IconIndexStart = startIndex

local picker, pickFor
local COLS, ROWS, SZ = 10, 7, 36
local shown            -- what the grid shows (all icons, or search results)
local function searchIcons(q)
  q = S.Trim(q or ""):lower()
  if q == "" then return nil end
  local starts, has, seen = {}, {}, {}
  -- an exact icon file name works too
  if GetFileIDFromPath then
    local fid = GetFileIDFromPath("Interface\\Icons\\" .. q)
    if fid then starts[#starts + 1] = fid; seen[fid] = true end
  end
  for ic, names in pairs(iconNames) do
    if not seen[ic] then
      local p = names:find(q, 1, true)
      if p then
        seen[ic] = true
        if p == 1 or names:sub(p - 1, p - 1) == "|" or names:sub(p - 1, p - 1) == " " then starts[#starts + 1] = ic else has[#has + 1] = ic end
      end
    end
  end
  table.sort(starts, function(a, b) return (iconTitle[a] or "") < (iconTitle[b] or "") end)
  table.sort(has, function(a, b) return (iconTitle[a] or "") < (iconTitle[b] or "") end)
  for _, ic in ipairs(has) do starts[#starts + 1] = ic end
  return starts
end
local function paintPicker()
  local list = shown or iconList()
  local per = COLS * ROWS
  local maxOff = math.max(0, math.ceil(#list / COLS) - ROWS)
  picker.off = math.max(0, math.min(picker.off or 0, maxOff))
  for k, b in ipairs(picker.btns) do
    local v = list[picker.off * COLS + k]
    b.v = v
    if v then b.tex:SetTexture(iconPath(v)); b:Show() else b:Hide() end
  end
  local note = ""
  if shown and indexing then note = "  |cff888888(still learning icon names " .. indexPct .. "%...)|r" end
  if #list == 0 then
    picker.page:SetText(shown and ("No icons match" .. note) or "")
  else
    picker.page:SetText(string.format("%d - %d of %d", picker.off * COLS + 1, math.min(#list, picker.off * COLS + per), #list) .. note)
  end
  picker.cur:SetTexture(S.AvatarFor(pickFor)); picker.cur:SetTexCoord(0.08, 0.92, 0.08, 0.92)
end
local searchPending
local function runSearch()
  searchPending = false
  if not picker then return end
  local q = picker.search:GetText()
  shown = searchIcons(q)
  picker.off = 0
  paintPicker()
end
local function searchSoon()
  if searchPending then return end
  searchPending = true
  C_Timer.After(0.15, runSearch)
end
onIndexStep = function(done)
  -- refresh results while names are being learned (not every frame)
  if picker and picker:IsShown() and shown then
    picker.lastStep = picker.lastStep or 0
    if done or GetTime() - picker.lastStep > 0.5 then picker.lastStep = GetTime(); runSearch() end
  end
end
function S:PickAvatar(name)
  if not name then return end
  pickFor = name
  if not picker then
    picker = UI:Window("CC_IconPick", "Pick a picture", COLS * (SZ + 4) + 36, ROWS * (SZ + 4) + 186)
    picker.search = UI:Edit(picker, COLS * (SZ + 4) - 4, 26, "Search icons: fire, wolf, sword, potion...")
    picker.search:SetPoint("TOPLEFT", 18, -40)
    picker.search:HookScript("OnTextChanged", function() startIndex(); searchSoon() end)
    picker.search:SetScript("OnEnterPressed", function(self) self:ClearFocus(); runSearch() end)
    picker.btns = {}
    for k = 1, COLS * ROWS do
      local b = CreateFrame("Button", nil, picker)
      b:SetSize(SZ, SZ)
      b:SetPoint("TOPLEFT", 18 + ((k - 1) % COLS) * (SZ + 4), -76 - math.floor((k - 1) / COLS) * (SZ + 4))
      b.tex = b:CreateTexture(nil, "ARTWORK"); b.tex:SetAllPoints(); b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
      b:SetScript("OnClick", function(self) if self.v then S.SetCustomAvatar(pickFor, self.v); paintPicker() end end)
      b:SetScript("OnEnter", function(self)
        local t = self.v and iconTitle[self.v]
        if not t then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine(t, 1, 1, 1); GameTooltip:Show()
      end)
      b:SetScript("OnLeave", function() GameTooltip:Hide() end)
      picker.btns[k] = b
    end
    picker:EnableMouseWheel(true)
    picker:SetScript("OnMouseWheel", function(_, d) picker.off = (picker.off or 0) - d * 2; paintPicker() end)
    local by = -76 - ROWS * (SZ + 4) - 6
    local up = UI:Button(picker, "Up", 50, 22, function() picker.off = (picker.off or 0) - ROWS; paintPicker() end)
    up:SetPoint("TOPLEFT", 18, by)
    local dn = UI:Button(picker, "Down", 56, 22, function() picker.off = (picker.off or 0) + ROWS; paintPicker() end)
    dn:SetPoint("LEFT", up, "RIGHT", 4, 0)
    picker.page = UI:Text(picker, "", "small"); picker.page:SetPoint("LEFT", dn, "RIGHT", 10, 0)
    picker.cur = picker:CreateTexture(nil, "ARTWORK"); picker.cur:SetSize(40, 40); picker.cur:SetPoint("BOTTOMLEFT", 18, 16)
    local curLabel = UI:Text(picker, "|cff888888Now|r", "small"); curLabel:SetPoint("LEFT", picker.cur, "RIGHT", 8, 0)
    local reset = UI:Button(picker, "Automatic", 84, 22, function() S.SetCustomAvatar(pickFor, nil); paintPicker() end, "Go back to the picture Command Center picked.")
    reset:SetPoint("LEFT", curLabel, "RIGHT", 12, 0)
    local done = UI:Button(picker, "Done", 60, 22, function() picker:Hide() end)
    done:SetPoint("BOTTOMRIGHT", -16, 16)
    picker:HookScript("OnShow", paintPicker)
  end
  if picker.title then picker.title:SetText(("Picture for %s"):format(short(name))) end
  picker.search:SetText(""); shown = nil
  startIndex()          -- learn icon names in the background so search is ready
  picker:Show(); picker:Raise(); paintPicker()
  picker.search:SetFocus()
end

---------------------------------------------------------------------------
-- Nicknames and alts: a character can have a nickname, and can be marked as an alt
-- of another character (its main). Alts show under the main's name / nickname and
-- their whispers land in the main's conversation.
---------------------------------------------------------------------------
local function idTables()
  local g = G()
  g.nicknames = type(g.nicknames) == "table" and g.nicknames or {}
  g.altOf = type(g.altOf) == "table" and g.altOf or {}
  return g.nicknames, g.altOf
end
local function key(n) return n and short(n):lower() or nil end
-- the main for a name (follows alt -> main links), or the name itself
function S.MainOf(name)
  if not name or not S.db then return name end
  local _, alts = idTables()
  local m, seen = name, {}
  for _ = 1, 6 do
    local k = key(m)
    local nxt = alts[k]
    if not nxt or seen[k] then break end
    seen[k] = true
    m = nxt
  end
  return m
end
function S.NicknameOf(name)
  if not name or not S.db then return nil end
  local nicks = idTables()
  return nicks[key(name)]
end
-- what to show for a name: main's nickname > main's name (for alts) > own nickname > name
function S.DisplayName(name)
  if not name then return "?" end
  local main = S.MainOf(name)
  return S.NicknameOf(main) or S.NicknameOf(name) or short(main)
end
function S.SetNickname(name, nick)
  if not name then return end
  local nicks = idTables()
  nick = nick and S.Trim(nick) or ""
  nicks[key(name)] = nick ~= "" and nick or nil
  S:Fire("MSGR_STYLE"); S:Fire("PLAYER_INFO")
end
-- find a character by nickname (case doesn't matter)
function S.ByNickname(nick)
  if not nick then return nil end
  local nicks = idTables()
  local l = S.Trim(nick):lower()
  for k, v in pairs(nicks) do
    if v:lower() == l then
      -- turn the stored short key back into a full name if we can
      for _, c in ipairs(S.Conversations and S:Conversations() or {}) do if key(c.with) == k then return c.with end end
      return S.MsgResolve and S.MsgResolve(k) or k
    end
  end
end
function S.SetAltOf(alt, main)
  if not alt then return end
  local _, alts = idTables()
  if main and key(S.MainOf(main)) == key(alt) then S:Print("That would make them their own main.") return end
  alts[key(alt)] = main and short(main) or nil
  S:Fire("MSGR_STYLE"); S:Fire("PLAYER_INFO")
end
function S.AltsOf(main)
  local _, alts = idTables()
  local out = {}
  local mk = key(main)
  for k, m in pairs(alts) do if key(S.MainOf(m)) == mk then out[#out + 1] = k end end
  table.sort(out)
  return out
end
-- prompt: "Set as alt of..." (type a character name or a nickname)
-- "Set as alt of...": a name box with the same suggestions as the Messenger search
-- a name box with the same suggestions as the Messenger search
--   S:PickPerson({ title, text, skip = fn(name), onPick = fn(fullName) })
local pickWin, pickOpts, pickSel
local function resolveName(txt)
  txt = S.Trim(txt or "")
  if txt == "" then return nil end
  local hit = S.ByNickname(txt)
  if not hit and S.MsgCandidates then
    for _, c in ipairs(S.MsgCandidates()) do if short(c.name):lower() == txt:lower() or c.name:lower() == txt:lower() then hit = c.name break end end
  end
  return hit or (S.MsgResolve and S.MsgResolve(txt)) or txt
end
local function choose(name)
  if not name or not pickOpts then return end
  pickWin:Hide()
  local fn = pickOpts.onPick
  if fn then fn(name) end
end
local function pickSuggest()
  local q = pickWin.edit:GetText() or ""
  local hits = S.MsgRank and S.MsgRank(q, pickOpts and pickOpts.skip) or {}
  local n = math.min(6, #hits)
  pickSel = nil
  for k, r in ipairs(pickWin.rows) do
    local h = hits[k]
    if k <= n and h then
      r.who = h.c.name
      S.SetAvatar(r.av, h.c.name)
      local nick = S.NicknameOf(h.c.name)
      r.name:SetText(S:ColorName(h.c.name) .. S.ServiceIcons(h.c.name) .. (nick and ("  |cff888888" .. short(h.c.name) .. "|r") or "")
        .. ((S.OnlineState and S.OnlineState(h.c.name)) and " |cff55ff55*|r" or ""))
      r.src:SetText(S.MsgSrcLabel and S.MsgSrcLabel(h.c) or "")
      r.hl:Hide(); r:Show()
    else r:Hide() end
  end
  pickWin.count = n
  pickWin.none:SetShown(n == 0 and q ~= "")
end
local function pickMove(d)
  if (pickWin.count or 0) == 0 then return end
  pickSel = ((pickSel or 0) + d - 1) % pickWin.count + 1
  for k, r in ipairs(pickWin.rows) do r.hl:SetShown(k == pickSel) end
end
function S:PickPerson(opts)
  pickOpts = opts or {}
  if not pickWin then
    pickWin = UI:Window("CC_PickPerson", "Pick someone", 360, 300)
    pickWin.msg = UI:Text(pickWin, "", "normal"); pickWin.msg:SetPoint("TOPLEFT", 16, -42); pickWin.msg:SetWidth(328)
    pickWin.edit = UI:Edit(pickWin, 328, 26, "Name or nickname")
    pickWin.edit:SetPoint("TOPLEFT", 16, -82)
    pickWin.edit:HookScript("OnTextChanged", function() pickSuggest() end)
    pickWin.edit:SetScript("OnEnterPressed", function(self)
      local r = pickSel and pickWin.rows[pickSel]
      if r and r.who then choose(r.who)
      elseif (pickWin.count or 0) == 1 then choose(pickWin.rows[1].who)
      else choose(resolveName(self:GetText())) end
    end)
    pickWin.edit:SetScript("OnArrowPressed", function(_, k) if k == "DOWN" then pickMove(1) elseif k == "UP" then pickMove(-1) end end)
    pickWin.edit:SetScript("OnTabPressed", function() pickMove(IsShiftKeyDown() and -1 or 1) end)
    pickWin.rows = {}
    for k = 1, 6 do
      local r = CreateFrame("Button", nil, pickWin)
      r:SetHeight(24); r:SetPoint("TOPLEFT", pickWin.edit, "BOTTOMLEFT", 0, -4 - (k - 1) * 24); r:SetPoint("RIGHT", pickWin.edit, "RIGHT", 0, 0)
      r.hl = r:CreateTexture(nil, "BACKGROUND"); r.hl:SetAllPoints(); r.hl:SetColorTexture(1, 0.82, 0, 0.12); r.hl:Hide()
      local h = r:CreateTexture(nil, "HIGHLIGHT"); h:SetAllPoints(); h:SetColorTexture(1, 1, 1, 0.06)
      r.av = r:CreateTexture(nil, "ARTWORK"); r.av:SetSize(18, 18); r.av:SetPoint("LEFT", 2, 0)
      r.name = UI:Text(r, "", "normal"); r.name:SetPoint("LEFT", r.av, "RIGHT", 6, 0)
      r.src = UI:Text(r, "", "small", "RIGHT"); r.src:SetPoint("RIGHT", -4, 0)
      r:SetScript("OnClick", function(self) if self.who then choose(self.who) end end)
      r:Hide()
      pickWin.rows[k] = r
    end
    pickWin.none = UI:Text(pickWin, "|cff888888Nobody you know by that name - press Enter to use it anyway.|r", "small")
    pickWin.none:SetPoint("TOPLEFT", pickWin.edit, "BOTTOMLEFT", 2, -8); pickWin.none:SetWidth(320)
    pickWin.ok = UI:PrimaryButton(pickWin, "Set", 90, 24, function() pickWin.edit:GetScript("OnEnterPressed")(pickWin.edit) end)
    pickWin.ok:SetPoint("BOTTOMRIGHT", pickWin, "BOTTOM", -6, 14)
    local no = UI:Button(pickWin, "Cancel", 90, 24, function() pickWin:Hide() end)
    no:SetPoint("BOTTOMLEFT", pickWin, "BOTTOM", 6, 14)
  end
  if pickWin.title then pickWin.title:SetText(pickOpts.title or "Pick someone") end
  pickWin.msg:SetText(pickOpts.text or "Start typing a name or nickname.")
  pickWin.ok:SetText(pickOpts.okText or "Set")
  pickWin.edit:SetText("")
  pickSuggest()
  pickWin:Show(); pickWin:Raise()
  pickWin.edit:SetFocus()
end
-- "Set as alt of..."
function S:AskAltOf(alt)
  if not alt then return end
  S:PickPerson({ title = "Set as alt", text = "Whose alt is |cffffd100" .. short(alt) .. "|r? Start typing their main's name or nickname.",
    skip = function(n) return same(n, alt) end,
    onPick = function(main)
      S.SetAltOf(alt, main)
      S:Print(short(alt) .. " is now an alt of |cffffd100" .. S.DisplayName(main) .. "|r.")
    end })
end
-- Your own note about someone (only you see it, never sent anywhere). Saved on the
-- main, so it shows on all their alts: g.pnotes[short lower main] = { text, t }
local function notesTable() local g = G(); g.pnotes = type(g.pnotes) == "table" and g.pnotes or {}; return g.pnotes end
function S.NoteOf(name)
  if not name or not S.db then return nil end
  local n = notesTable()[key(S.MainOf(name) or name)]
  return n and n.text
end
function S.NoteTime(name)
  if not name or not S.db then return nil end
  local n = notesTable()[key(S.MainOf(name) or name)]
  return n and n.t
end
function S.SetNote(name, txt)
  if not name then return end
  txt = S.Trim(txt or ""):gsub("|", "/")
  notesTable()[key(S.MainOf(name) or name)] = (txt ~= "") and { text = txt, t = time() } or nil
  S:Fire("MSGR_STYLE"); S:Fire("PLAYER_INFO")
end
function S:AskNote(name)
  if not name then return end
  local shown = S.DisplayName and S.DisplayName(name) or short(name)
  UI:Prompt("Your note about |cffffd100" .. shown .. "|r - only you see it (leave empty to remove):", S.NoteOf(name) or "", function(txt)
    S.SetNote(name, txt)
  end)
end

function S:AskNickname(name)
  UI:Prompt("Nickname for |cffffd100" .. short(name) .. "|r (leave empty to remove):", S.NicknameOf(name) or "", function(txt)
    S.SetNickname(name, txt)
  end)
end

-- names everywhere show the nickname / main (coloured by the character's class)
do
  local colorName = S.ColorName
  function S:ColorName(name)
    local s = colorName(self, name)
    if not name or not S.db then return s end
    local shown = S.DisplayName(name)
    if shown ~= short(name) then
      local esc = short(name):gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
      s = s:gsub(esc, (shown:gsub("%%", "%%%%")), 1)
    end
    return s
  end
end
S:Listen("PLAYER_INFO", function() if S.RefreshPlayer then S:RefreshPlayer() end end)

---------------------------------------------------------------------------
-- Services: what someone offers (professions, summons, portals, food & water...).
-- Saved per person (their main), shown as small icons right after their name.
---------------------------------------------------------------------------
local SERVICES = {
  { id = "bs",    name = "Blacksmithing",   icon = "Trade_BlackSmithing" },
  { id = "lw",    name = "Leatherworking",  icon = "Trade_LeatherWorking" },
  { id = "tail",  name = "Tailoring",       icon = "Trade_Tailoring" },
  { id = "eng",   name = "Engineering",     icon = "Trade_Engineering" },
  { id = "alch",  name = "Alchemy",         icon = "Trade_Alchemy" },
  { id = "ench",  name = "Enchanting",      icon = "Trade_Engraving" },
  { id = "jc",    name = "Jewelcrafting",   icon = "INV_Misc_Gem_01" },
  { id = "insc",  name = "Inscription",     icon = "INV_Inscription_Tradeskill01" },
  { id = "cook",  name = "Cooking",         icon = "INV_Misc_Food_15" },
  { id = "fa",    name = "First Aid",       icon = "Spell_Holy_SealOfSacrifice" },
  { id = "mine",  name = "Mining",          icon = "Trade_Mining" },
  { id = "herb",  name = "Herbalism",       icon = "Spell_Nature_NatureTouchGrow" },
  { id = "skin",  name = "Skinning",        icon = "INV_Misc_Pelt_Wolf_01" },
  { id = "fish",  name = "Fishing",         icon = "Trade_Fishing" },
  { id = "summ",  name = "Summons (warlock)", icon = "Spell_Shadow_Twilight" },
  { id = "port",  name = "Portals (mage)",  icon = "Spell_Arcane_PortalOrgrimmar" },
  { id = "food",  name = "Food & water (mage)", icon = "INV_Drink_18" },
  { id = "lock",  name = "Lockpicking (rogue)", icon = "INV_Misc_Key_03" },
}
S.SERVICES = SERVICES
local function svcTable()
  local g = G()
  g.services = type(g.services) == "table" and g.services or {}
  return g.services
end
local function svcKey(name) return key(S.MainOf(name)) end
function S.ServicesOf(name)
  if not name or not S.db then return {} end
  return svcTable()[svcKey(name)] or {}
end
function S.SetService(name, id, on)
  if not name then return end
  local t = svcTable()
  local k = svcKey(name)
  local s = t[k] or {}
  s[id] = on and true or nil
  s._name = S.MainOf(name)              -- who it is (for the service finder)
  local any = false
  for kk in pairs(s) do if kk ~= "_name" then any = true break end end
  t[k] = any and s or nil
  S:Fire("MSGR_STYLE"); S:Fire("PLAYER_INFO")
end
-- everyone you've marked with a service: { { name = full name, svc = {id = true} }, ... }
function S.ServiceProviders()
  local out = {}
  for k, s in pairs(svcTable()) do
    if type(s) == "table" then
      local nm = short(s._name or (S.MsgResolve and S.MsgResolve(k)) or k)
      out[#out + 1] = { name = nm, svc = s }
    end
  end
  return out
end
-- " |T..|t|T..|t" after a name ("" when they offer nothing)
function S.ServiceIcons(name, size)
  local s = S.ServicesOf(name)
  size = size or 14
  local out = {}
  for _, sv in ipairs(SERVICES) do
    if s[sv.id] then out[#out + 1] = "|TInterface\\Icons\\" .. sv.icon .. ":" .. size .. ":" .. size .. ":0:0:64:64:5:59:5:59|t" end
  end
  if #out == 0 then return "" end
  return " " .. table.concat(out, "")
end
function S.ServiceNames(name)
  local s = S.ServicesOf(name)
  local out = {}
  for _, sv in ipairs(SERVICES) do if s[sv.id] then out[#out + 1] = "|TInterface\\Icons\\" .. sv.icon .. ":14:14:0:0:64:64:5:59:5:59|t " .. sv.name end end
  return table.concat(out, ", ")
end

local svcWin, svcFor
function S:ShowServices(name)
  if not name then return end
  svcFor = name
  if not svcWin then
    local rowsN = math.ceil(#SERVICES / 2)
    svcWin = UI:Window("CC_Services", "Services", 440, rowsN * 26 + 120)
    svcWin.msg = UI:Text(svcWin, "", "normal"); svcWin.msg:SetPoint("TOPLEFT", 16, -42); svcWin.msg:SetWidth(408)
    svcWin.checks = {}
    for i, sv in ipairs(SERVICES) do
      local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
      local ic = svcWin:CreateTexture(nil, "ARTWORK"); ic:SetSize(20, 20)
      ic:SetTexture("Interface\\Icons\\" .. sv.icon); ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      ic:SetPoint("TOPLEFT", 18 + col * 210, -70 - row * 26)
      local cb = UI:Check(svcWin, sv.name, false, function(v) S.SetService(svcFor, sv.id, v) end)
      cb:SetPoint("LEFT", ic, "RIGHT", 4, 0)
      svcWin.checks[sv.id] = cb
    end
    local done = UI:Button(svcWin, "Done", 70, 22, function() svcWin:Hide() end)
    done:SetPoint("BOTTOMRIGHT", -16, 14)
    local clear = UI:Button(svcWin, "Clear all", 80, 22, function()
      for _, sv in ipairs(SERVICES) do S.SetService(svcFor, sv.id, false); svcWin.checks[sv.id]:SetChecked(false) end
    end)
    clear:SetPoint("BOTTOMLEFT", 16, 14)
  end
  svcWin.msg:SetText("What does |cffffd100" .. S.DisplayName(name) .. "|r offer? Ticked ones show as icons after their name.")
  local s = S.ServicesOf(name)
  for id, cb in pairs(svcWin.checks) do cb:SetChecked(s[id] and true or false) end
  svcWin:Show(); svcWin:Raise()
end

---------------------------------------------------------------------------
-- Contacts: people you keep close. Shown as bubbles across the top of the
-- Messenger inbox, most recently active first. Saved on the main.
---------------------------------------------------------------------------
local function ctTable()
  local g = G()
  g.contacts = type(g.contacts) == "table" and g.contacts or {}
  return g.contacts
end
function S.IsContact(name)
  if not name or not S.db then return false end
  return ctTable()[key(S.MainOf(name))] ~= nil
end
function S.AddContact(name)
  if not name then return end
  local main = S.MainOf(name)
  ctTable()[key(main)] = { name = main, added = time() }
  S:Fire("MSGR_STYLE"); S:Fire("PLAYER_INFO")
end
function S.RemoveContact(name)
  if not name then return end
  ctTable()[key(S.MainOf(name))] = nil
  S:Fire("MSGR_STYLE"); S:Fire("PLAYER_INFO")
end
function S.ToggleContact(name)
  if S.IsContact(name) then S.RemoveContact(name) else S.AddContact(name) end
end
-- last time we heard from / talked with them (any of their characters)
local function lastActive(name, rec)
  local t = 0
  local c = S.Conversation and S:Conversation(name)
  if c and c.last and (c.last.time or 0) > t then t = c.last.time end
  local hk = key(name)
  if lastHeard[hk] and lastHeard[hk] > t then t = lastHeard[hk] end
  local w = whoCache[hk]
  if w and w.whoAt and w.whoAt > t then t = w.whoAt end
  if t == 0 and (unitFor(name) or (S.OnlineState and S.OnlineState(name))) then t = time() - 60 end
  if t == 0 then t = rec and rec.added or 0 end    -- nothing yet: when you added them
  return t
end
-- contact names, most recently active first
function S.Contacts()
  local out = {}
  for _, rec in pairs(ctTable()) do
    if type(rec) == "table" and rec.name then out[#out + 1] = { name = S.MainOf(rec.name), t = lastActive(rec.name, rec) } end
  end
  table.sort(out, function(a, b) if a.t ~= b.t then return a.t > b.t end return a.name < b.name end)
  local names = {}
  for i, o in ipairs(out) do names[i] = o.name end
  return names
end
function S:AskAddContact()
  S:PickPerson({ title = "Add a contact", text = "Who do you want in your contacts? Start typing a name or nickname.", okText = "Add",
    skip = function(n) return S.IsContact(n) end,
    onPick = function(n) S.AddContact(n); S:Print("|cffffd100" .. S.DisplayName(n) .. "|r added to your contacts.") end })
end

---------------------------------------------------------------------------
-- A person = their main + alts. Online if ANY of their characters is.
---------------------------------------------------------------------------
local function capFull(k)
  if not k then return nil end
  if k:find("-", 1, true) then return k end
  return S.MsgResolve and S.MsgResolve(k) or k
end
-- every character we know for this person (main first)
function S.CharsOf(name)
  if not name then return {} end
  local main = S.MainOf(name)
  local out, seen = { main }, { [key(main)] = true }
  -- the spellings seen in their whispers first (real realm), then alts we only know by name
  local c = S.Conversation and S:Conversation(main)
  if c and c.chars then for ch in pairs(c.chars) do if not seen[key(ch)] then seen[key(ch)] = true; out[#out + 1] = ch end end end
  for _, a in ipairs(S.AltsOf(main)) do
    if not seen[a] then seen[a] = true; out[#out + 1] = capFull(a) end
  end
  return out
end
-- the character of theirs that's online right now (nil if none we know of)
function S.OnlineChar(name)
  for _, ch in ipairs(S.CharsOf(name)) do
    if S.OnlineState(ch) == true then return ch end
  end
end
-- true (some character online) / false (main known offline, no alt online) / nil
function S.PersonOnline(name)
  if not name then return nil end
  if S.OnlineChar(name) then return true end
  local st
  for _, ch in ipairs(S.CharsOf(name)) do
    local v = S.OnlineState(ch)
    if v == false then st = false end
  end
  return st
end

-- "Hey, are you available for ... atm?" for someone you found by their services
local ASK = {
  bs = "some blacksmithing", lw = "some leatherworking", tail = "some tailoring", eng = "some engineering",
  alch = "some alchemy", ench = "some enchanting", jc = "some jewelcrafting", insc = "some inscription",
  cook = "some cooking", fa = "some first aid", mine = "some mining", herb = "some herbalism",
  skin = "some skinning", fish = "some fishing", summ = "a summon", lock = "some lockpicking",
}
function S.ServiceAsk(name, only)
  local s = S.ServicesOf(name)
  local function want(id) return s[id] and (not only or not next(only) or only[id]) end
  local parts = {}
  -- mage: portals and/or food & water
  if want("port") and want("food") then parts[#parts + 1] = "mage services"
  elseif want("port") then parts[#parts + 1] = "a portal"
  elseif want("food") then parts[#parts + 1] = "some food and water" end
  for _, sv in ipairs(SERVICES) do
    if ASK[sv.id] and want(sv.id) then parts[#parts + 1] = ASK[sv.id] end
  end
  if #parts == 0 then return nil end
  while #parts > 3 do table.remove(parts) end
  local what = #parts == 1 and parts[1] or (table.concat(parts, ", ", 1, #parts - 1) .. " or " .. parts[#parts])
  return "Hey, are you available for " .. what .. " atm?"
end
