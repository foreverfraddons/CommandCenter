-- Rotational: lights up the spell on your action bars that you should press next,
-- following a rotation you set up in its panel.
--
--   Priority  - your abilities in order: the first one that's ready glows
--   Opener    - what to start a fight with, in range or out of range
--   Procs     - pop-ups for procs (Maelstrom Weapon, Flurry ...) that can move a spell
--               to the front or reset its cooldown
--   (buffs to keep up moved to their own tool: BuffWatcher)
--   Dispels   - purge / spellsteal a buff off your target, cleanse your group
--   Look      - how the "press now" glow and the next-spell icon look and move
--
-- This game hides some combat information from addons during fights (cooldowns,
-- buffs). Rotational reads what it's allowed to; where a cooldown is hidden it works
-- it out from your own casts, and the panel shows what it can see. You press the
-- buttons - it only makes them glow.
local _, S = ...
local UI = S.UI
if S.ModuleRev then S:ModuleRev("Rotational", 6) end

local function G() return S.db.global end
-- the whole tool on / off (Settings > Behaviour "Use Rotational"; g.rotationalOff). Off: no deciding,
-- no glows, no next-spell icon, no tile. (Spec detection, the button list and cast tracking stay on:
-- BuffWatcher uses them)
-- REMOVED FOR NOW (user, 2026-11-26: "remove rotational from command center for now"): the tool is
-- gone from Command Center (no tile, Tools row, dock icon, window, setting or Guide page) and never
-- decides or glows. The file still loads because BuffWatcher and HealAssist use its spell helpers
-- (S.RotKit, S.RotSpecs, cast tracking). To bring it back: set S.ROTATIONAL_REMOVED = false.
S.ROTATIONAL_REMOVED = true
function S.RotationalOn() return not S.ROTATIONAL_REMOVED and not (S.db and S.db.global.rotationalOff) end
local function combat() return (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) end
local function secret(v) return issecretvalue ~= nil and issecretvalue(v) end
-- a table we may read (in combat the game hands out secret tables: type() says "table" but ipairs / pairs / # fail)
local function readable(t) return type(t) == "table" and not secret(t) end
local function now() return GetTime() end

---------------------------------------------------------------------------
-- Spells
---------------------------------------------------------------------------
local function spellInfo(x)
  if x == nil or x == "" then return nil end
  if C_Spell and C_Spell.GetSpellInfo then
    local ok, t = pcall(C_Spell.GetSpellInfo, tonumber(x) or x)
    if ok and readable(t) and t.spellID then return t.spellID, t.name, t.iconID end
  end
  if GetSpellInfo then
    local ok, name, _, icon, _, _, _, id = pcall(GetSpellInfo, tonumber(x) or x)
    if ok and name then return id or tonumber(x), name, icon end
  end
end
S.RotSpellInfo = spellInfo
local nameCache = {}
local function spellName(id)
  if id == nil then return "?" end
  local c = nameCache[id]; if c then return c end
  local _, n = spellInfo(id)
  if n then nameCache[id] = n end
  return n or ("#" .. tostring(id))
end
local function spellIcon(id) local _, _, i = spellInfo(id); return i or "Interface\\Icons\\INV_Misc_QuestionMark" end
local function known(id)
  if not id then return false end
  if IsPlayerSpell then local ok, k = pcall(IsPlayerSpell, id); if ok and k then return true end end
  if IsSpellKnown then local ok, k = pcall(IsSpellKnown, id); if ok and k then return true end end
  return not (IsPlayerSpell or IsSpellKnown)
end

---------------------------------------------------------------------------
-- Settings (per character and talent set)
---------------------------------------------------------------------------
-- Setups belong to your class (every character of that class shares them) and come
-- as profiles - one per specialization, or any you make. Each character remembers
-- which profile it uses for each talent set.
local function myClass() local loc, cls = UnitClass("player"); return cls or "UNKNOWN", loc or cls or "?" end
local function talentGroup()
  return (GetActiveTalentGroup and GetActiveTalentGroup()) or (C_SpecializationInfo and C_SpecializationInfo.GetActiveSpecGroup and C_SpecializationInfo.GetActiveSpecGroup()) or 1
end
-- your class's specializations: { { name=, points= } }
-- WoW: Forever has no talent tabs: the whole class is ONE trait tree (C_Traits) with the
-- three classic specializations side by side, and the specialization API only knows the
-- class itself. So: talent tabs if the game has them, else named sub trees, else the one
-- tree split into its three columns by where the talents sit. Points = talents bought.
local CLASS_TREES = {
  WARRIOR = { "Arms", "Fury", "Protection" }, PALADIN = { "Holy", "Protection", "Retribution" },
  HUNTER = { "Beast Mastery", "Marksmanship", "Survival" }, ROGUE = { "Assassination", "Combat", "Subtlety" },
  PRIEST = { "Discipline", "Holy", "Shadow" }, SHAMAN = { "Elemental", "Enhancement", "Restoration" },
  MAGE = { "Arcane", "Fire", "Frost" }, WARLOCK = { "Affliction", "Demonology", "Destruction" },
  DRUID = { "Balance", "Feral Combat", "Restoration" },
}
S.ROT_CLASS_TREES = CLASS_TREES
local function isClassName(name)
  if type(name) ~= "string" then return true end
  local loc, cls = UnitClass("player")
  local n = name:lower()
  return n == "" or n == tostring(loc or ""):lower() or n == tostring(cls or ""):lower()
end
local specLog                -- lines for /ccenter specs
local function slog(...)
  if not specLog then return end
  local t = {}
  for i = 1, select("#", ...) do local v = select(i, ...); t[#t + 1] = secret(v) and "SECRET" or tostring(v) end
  specLog[#specLog + 1] = table.concat(t, " ")
end
local function pc(fn, ...) if type(fn) ~= "function" then return nil end local r = { pcall(fn, ...) } if r[1] then return unpack(r, 2) end end

-- 1) old talent tabs (GetTalentTabInfo)
local function talentTabs()
  local out = {}
  local tabs = pc(GetNumTalentTabs) or 0
  for i = 1, tabs do
    local r = { pcall(GetTalentTabInfo, i) }
    if r[1] then
      local name, pts
      for j = 2, #r do
        local v = r[j]
        if type(v) == "string" and not name and not v:find("[\\/]") and v ~= "" and not tonumber(v) then name = v end
        if type(v) == "number" and v <= 100 and not pts and j > 3 then pts = v end
      end
      if not pts and GetNumTalents and GetTalentInfo then
        pts = 0
        for k = 1, (pc(GetNumTalents, i) or 0) do
          local rr = { pcall(GetTalentInfo, i, k) }
          if rr[1] and type(rr[6]) == "number" then pts = pts + rr[6] end
        end
      end
      if name and not isClassName(name) then out[#out + 1] = { name = name, points = pts or 0 } end
    end
  end
  slog("talent tabs:", tabs, "named:", #out)
  return out
end

-- 2) the specialization API (dual-spec style); only counts if it names real specs
local function specAPI()
  local out = {}
  local SI = C_SpecializationInfo
  local n = pc(GetNumSpecializations) or (SI and pc(SI.GetNumSpecializationsForClassID, select(3, UnitClass("player")))) or 0
  local cur = pc(GetSpecialization) or (SI and pc(SI.GetSpecialization))
  local info = GetSpecializationInfo or (SI and SI.GetSpecializationInfo)
  local raw = {}
  for i = 1, (tonumber(n) or 0) do
    local _, name = pc(info, i)
    raw[#raw + 1] = tostring(name)
    if type(name) == "string" and not isClassName(name) then out[#out + 1] = { name = name, points = (cur == i) and 100 or 0 } end
  end
  slog("spec API: count", n, "current", cur, "names", table.concat(raw, ", "))
  return out
end

-- 3) the trait tree
local function nodeList(configID, treeID)
  local nodes = {}
  local ids = pc(C_Traits.GetTreeNodes, treeID) or {}
  for _, nodeID in ipairs(ids) do
    local ni = pc(C_Traits.GetNodeInfo, configID, nodeID)
    if type(ni) == "table" and not secret(ni) then
      local pts = tonumber(ni.ranksPurchased) or tonumber(ni.currentRank) or 0
      local entry = ni.activeEntry and ni.activeEntry.entryID or (type(ni.entryIDs) == "table" and ni.entryIDs[1])
      nodes[#nodes + 1] = { id = nodeID, x = tonumber(ni.posX), y = tonumber(ni.posY), pts = pts, sub = ni.subTreeID, entry = entry }
    end
  end
  return nodes
end
local function talentName(configID, entryID)
  if not entryID then return "?" end
  local e = pc(C_Traits.GetEntryInfo, configID, entryID)
  local def = type(e) == "table" and e.definitionID and pc(C_Traits.GetDefinitionInfo, e.definitionID)
  if type(def) ~= "table" then return "?" end
  if type(def.overrideName) == "string" and def.overrideName ~= "" then return def.overrideName end
  if def.spellID then return spellName(def.spellID) end
  return "?"
end
-- split talents into 3 groups at the two widest gaps along x (or y if that balances better)
local function splitTree(nodes)
  local best
  for _, axis in ipairs({ "x", "y" }) do
    local list = {}
    for _, n in ipairs(nodes) do if n[axis] then list[#list + 1] = n end end
    if #list >= 6 then
      table.sort(list, function(a, b) return a[axis] < b[axis] end)
      local gaps = {}
      for i = 1, #list - 1 do
        local g = list[i + 1][axis] - list[i][axis]
        if g > 0 then gaps[#gaps + 1] = { i = i, g = g } end
      end
      table.sort(gaps, function(a, b) return a.g > b.g end)
      local minSize = math.max(1, math.floor(#list * 0.15))
      -- widest pair of gaps that leaves every group at least 15% of the talents
      for a = 1, #gaps do
        for b = a + 1, #gaps do
          local c1, c2 = math.min(gaps[a].i, gaps[b].i), math.max(gaps[a].i, gaps[b].i)
          local s1, s2, s3 = c1, c2 - c1, #list - c2
          if s1 >= minSize and s2 >= minSize and s3 >= minSize then
            local score = (gaps[a].g + gaps[b].g) * (math.min(s1, s2, s3) / math.max(s1, s2, s3))
            if not best or score > best.score then best = { score = score, axis = axis, list = list, c1 = c1, c2 = c2 } end
          end
        end
        if best and best.axis == axis then break end
      end
    end
  end
  if not best then return nil end
  local groups = { {}, {}, {} }
  for i, n in ipairs(best.list) do
    local g = groups[(i <= best.c1) and 1 or (i <= best.c2) and 2 or 3]
    g[#g + 1] = n
  end
  return groups, best.axis
end
local function traitTrees()
  local out = {}
  if not (C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_Traits and C_Traits.GetConfigInfo) then
    slog("trait API: missing (C_ClassTalents", C_ClassTalents ~= nil, "C_Traits", C_Traits ~= nil, ")")
    return out
  end
  local configID = pc(C_ClassTalents.GetActiveConfigID)
  slog("trait config:", configID)
  if not configID then return out end
  local ci = pc(C_Traits.GetConfigInfo, configID)
  local trees = type(ci) == "table" and ci.treeIDs or {}
  local _, cls = UnitClass("player")
  for _, treeID in ipairs(trees) do
    local nodes = nodeList(configID, treeID)
    local total = 0
    for _, n in ipairs(nodes) do total = total + n.pts end
    -- named sub trees (hero talents style)
    local subs, subOrder = {}, {}
    for _, n in ipairs(nodes) do
      if n.sub then
        if not subs[n.sub] then subs[n.sub] = { pts = 0 }; subOrder[#subOrder + 1] = n.sub end
        subs[n.sub].pts = subs[n.sub].pts + n.pts
      end
    end
    slog("tree", treeID, "talents", #nodes, "points", total, "sub trees", #subOrder)
    for _, sid in ipairs(subOrder) do
      local si = pc(C_Traits.GetSubTreeInfo, configID, sid)
      local name = type(si) == "table" and si.name
      slog("  sub tree", sid, tostring(name), "points", subs[sid].pts)
      if type(name) == "string" and not isClassName(name) then out[#out + 1] = { name = name, points = subs[sid].pts } end
    end
    if #out == 0 and #nodes >= 6 then
      local groups, axis = splitTree(nodes)
      local names = CLASS_TREES[cls] or { "Tree 1", "Tree 2", "Tree 3" }
      if groups then
        for gi, grp in ipairs(groups) do
          local pts, sample = 0, {}
          for _, n in ipairs(grp) do
            pts = pts + n.pts
            if specLog and #sample < 4 then sample[#sample + 1] = talentName(configID, n.entry) end
          end
          slog("  group", gi, "(" .. axis .. ")", names[gi], "talents", #grp, "points", pts, "e.g.", table.concat(sample, ", "))
          out[#out + 1] = { name = names[gi], points = pts }
        end
      else
        slog("  could not split the tree into 3")
      end
    end
  end
  return out
end

-- Reading the talent tree builds a lot of tables (5.7 KB a time), and the talent events below come
-- often on Forever, so they only mark the copy out of date: it's read again at most twice a second
-- (a spec switch shows within half a second), and every 30 s at the latest.
local specCache, specCacheAt, specDirty = nil, -99, false
function S:RotSpecs(fresh)
  if specCache then
    local age = now() - specCacheAt
    if age < 0.5 or (not fresh and not specDirty and age < 30) then return specCache end
  end
  local out = talentTabs()
  if #out == 0 then out = specAPI() end
  if #out == 0 then out = traitTrees() end
  specCache, specCacheAt, specDirty = out, now(), false
  return out
end
-- the specialization you play: most points (or the one the game says is active)
function S.CurrentSpec()
  local best
  for _, sp in ipairs(S:RotSpecs()) do if (sp.points or 0) > 0 and (not best or sp.points > best.points) then best = sp end end
  return best and best.name
end
for _, ev in ipairs({ "TRAIT_CONFIG_UPDATED", "TRAIT_CONFIG_LIST_UPDATED", "ACTIVE_COMBAT_CONFIG_CHANGED", "CHARACTER_POINTS_CHANGED",
  "PLAYER_TALENT_UPDATE", "PLAYER_SPECIALIZATION_CHANGED", "ACTIVE_TALENT_GROUP_CHANGED" }) do
  pcall(S.On, S, ev, function() specDirty = true end)
end
function S:RotSpecsReport()
  specLog = {}
  local _, cls = UnitClass("player")
  slog("class", cls, "| APIs: GetNumTalentTabs", GetNumTalentTabs ~= nil, "GetSpecializationInfo", GetSpecializationInfo ~= nil,
    "C_SpecializationInfo", C_SpecializationInfo ~= nil, "C_ClassTalents", C_ClassTalents ~= nil, "C_Traits", C_Traits ~= nil)
  local ok, err = pcall(function()
    local a = talentTabs(); local b = specAPI(); local c = traitTrees()
    local use = (#a > 0 and a) or (#b > 0 and b) or c
    local parts = {}
    for _, sp in ipairs(use) do parts[#parts + 1] = sp.name .. " " .. tostring(sp.points) end
    slog("=> specs:", #parts > 0 and table.concat(parts, ", ") or "none", "| you're:", tostring(S.CurrentSpec()))
  end)
  if not ok then slog("error:", tostring(err)) end
  specCache = nil
  local lines = specLog
  specLog = nil
  if S.db then G().specsDiag = lines end
  for _, l in ipairs(lines) do print("|cff4fd1c5Command Center|r specs: " .. l) end
end
S:AddCommand("specs", "", "Show which talent specializations the game reports", function() S:RotSpecsReport() end)
local function mainSpec() return S.CurrentSpec() end

local function newProfile()
  return { enabled = true, prio = {}, opener = {}, procs = {}, buffs = {}, purge = {}, cleanse = {}, cleanses = {},
    look = { strong = 0.9, soft = 0.45, color = "gold", next = true } }
end
local function classStore()
  local g = G()
  g.rotClass = type(g.rotClass) == "table" and g.rotClass or {}
  local cls = myClass()
  local c = g.rotClass[cls]
  if type(c) ~= "table" then
    c = { profiles = {}, order = {} }
    g.rotClass[cls] = c
    -- one empty profile per specialization
    for _, sp in ipairs(S:RotSpecs()) do c.profiles[sp.name] = newProfile(); c.order[#c.order + 1] = sp.name end
    -- this character's setup from before profiles: into its main specialization
    local old = type(g.rotation) == "table" and g.rotation[(S.me or "?") .. ":" .. tostring(talentGroup())]
    if type(old) == "table" then
      local name = mainSpec() or "Main"
      if not c.profiles[name] then c.order[#c.order + 1] = name end
      c.profiles[name] = old
    end
    if #c.order == 0 then c.profiles.Main = newProfile(); c.order[1] = "Main" end
  end
  c.profiles = c.profiles or {}; c.order = c.order or {}
  return c
end
S.RotClassStore = classStore
-- which profile this character uses for its current talent set
local function activeName()
  local c = classStore()
  local g = G()
  g.rotChar = type(g.rotChar) == "table" and g.rotChar or {}
  local mine = g.rotChar[S.me or "?"]
  if type(mine) ~= "table" then mine = {}; g.rotChar[S.me or "?"] = mine end
  local k = tostring(talentGroup())
  local name = mine[k]
  if not name or not c.profiles[name] then
    name = mainSpec()
    if not name or not c.profiles[name] then name = c.order[1] end
    mine[k] = name
  end
  return name
end
function S:RotActiveProfile() return activeName() end
function S:RotUseProfile(name)
  local c = classStore()
  if not c.profiles[name] then return end
  activeName()
  G().rotChar[S.me or "?"][tostring(talentGroup())] = name
  if S.RotResetState then S:RotResetState() end
  if S.RefreshRotational then S:RefreshRotational() end
end
function S:RotNewProfile(name, copyFrom)
  local c = classStore()
  name = (S.Trim and S.Trim(name or "") or name or "")
  if name == "" or c.profiles[name] then return false end
  local p = newProfile()
  if copyFrom and c.profiles[copyFrom] then
    local function copy(t) if type(t) ~= "table" then return t end local o = {} for k, v in pairs(t) do o[k] = copy(v) end return o end
    p = copy(c.profiles[copyFrom])
  end
  c.profiles[name] = p; c.order[#c.order + 1] = name
  S:RotUseProfile(name)
  return true
end
function S:RotRenameProfile(old, new)
  local c = classStore()
  new = (S.Trim and S.Trim(new or "") or new or "")
  if new == "" or c.profiles[new] or not c.profiles[old] then return false end
  c.profiles[new], c.profiles[old] = c.profiles[old], nil
  for i, n in ipairs(c.order) do if n == old then c.order[i] = new end end
  for _, ch in pairs(G().rotChar or {}) do for k, v in pairs(ch) do if v == old then ch[k] = new end end end
  if S.RefreshRotational then S:RefreshRotational() end
  return true
end
function S:RotDeleteProfile(name)
  local c = classStore()
  if not c.profiles[name] or #c.order <= 1 then return false end
  c.profiles[name] = nil
  for i = #c.order, 1, -1 do if c.order[i] == name then table.remove(c.order, i) end end
  if S.RefreshRotational then S:RefreshRotational() end
  return true
end

local function P()
  local c = classStore()
  local p = c.profiles[activeName()]
  if type(p) ~= "table" then p = newProfile(); c.profiles[activeName()] = p end
  p.prio = p.prio or {}; p.opener = p.opener or {}; p.procs = p.procs or {}; p.buffs = p.buffs or {}
  p.purge = p.purge or {}; p.cleanse = p.cleanse or {}
  -- older setups: plain spell IDs in the priority list -> { id = }
  for i, e in ipairs(p.prio) do if type(e) == "number" then p.prio[i] = { id = e } end end
  -- one cleanse spell -> a list of them
  if not p.cleanses then
    p.cleanses = {}
    if p.cleanse.spell then p.cleanses[1] = { spell = p.cleanse.spell, type = "any" } end
    p.cleanseOn = p.cleanse.on
  end
  p.look = p.look or { strong = 0.9, soft = 0.45, color = "gold", next = true }
  return p
end
S.RotProfile = P

---------------------------------------------------------------------------
-- What the game lets us read (for the panel's status line)
---------------------------------------------------------------------------
local seen = { cd = "unknown", aura = "unknown" }

-- cooldowns: the game's numbers when readable, otherwise worked out from your casts
local baseCD = {}            -- spellID -> seconds (read out of combat)
local lastCast = {}          -- spellID -> GetTime() of your last cast
local buffCast = {}          -- buff spellID -> GetTime() you last put it up
local totemCast = {}         -- totem spellID -> GetTime() you last dropped it
local resetReady = {}        -- spellID -> true while a reset proc says it's ready
local eventGlowUntil         -- (below)
local totemLeft              -- (below)
local resetAt = {}           -- spellID -> time a proc reset it
local function cacheBase(id)
  if baseCD[id] ~= nil or not GetSpellBaseCooldown then return end
  local ok, ms = pcall(GetSpellBaseCooldown, id)
  if ok and not secret(ms) then baseCD[id] = (tonumber(ms) or 0) / 1000 end
end

local function readCooldown(id)
  local start, dur
  if C_Spell and C_Spell.GetSpellCooldown then
    local ok, t = pcall(C_Spell.GetSpellCooldown, id)
    if ok and readable(t) then start, dur = t.startTime, t.duration end
  elseif GetSpellCooldown then
    local ok, a, b = pcall(GetSpellCooldown, id)
    if ok then start, dur = a, b end
  end
  if start == nil or secret(start) or secret(dur) then return nil end
  return tonumber(start) or 0, tonumber(dur) or 0
end

-- seconds until the spell is ready (0 = ready; global cooldown ignored)
local cdOverride = {}         -- spellID -> seconds you typed in the panel
local sharedUntil = {}        -- spellID -> on cooldown until (another spell with the same shared cooldown was cast)
local function cooldownLeft(id)
  local start, dur = readCooldown(id)
  if start then
    seen.cd = combat() and "readable" or seen.cd
    if dur <= 1.6 then return 0 end                      -- just the global cooldown
    return math.max(0, start + dur - now())
  end
  seen.cd = "worked out from your casts"
  local shared = sharedUntil[id] and math.max(0, sharedUntil[id] - now()) or 0
  local last = lastCast[id]
  if not last then return shared end
  if resetAt[id] and resetAt[id] >= last then return 0 end
  local base = cdOverride[id] or baseCD[id] or 0
  if base <= 1.6 then return shared end
  return math.max(shared, last + base - now())
end

local function usable(id)
  local fn = (C_Spell and C_Spell.IsSpellUsable) or IsUsableSpell
  if not fn then return true end
  local ok, u, noMana = pcall(fn, id)
  if not ok or u == nil or secret(u) then return true end   -- can't tell: don't block it
  return u and true or false
end

-- true / false, or nil when the game won't say
local function inRange(id, unit)
  unit = unit or "target"
  if C_Spell and C_Spell.IsSpellInRange then
    local ok, r = pcall(C_Spell.IsSpellInRange, id, unit)
    if ok and r ~= nil and not secret(r) then return r and true or false end
  end
  if IsSpellInRange then
    local ok, r = pcall(IsSpellInRange, spellName(id), unit)
    if ok and r ~= nil and not secret(r) then return r == 1 or r == true end
  end
  return nil
end

-- your own buff: aura table or nil; stacks when readable
local function myAura(nameOrId)
  local a
  local id = tonumber(nameOrId)
  pcall(function()
    if id and C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then a = C_UnitAuras.GetPlayerAuraBySpellID(id) end
    if not a then
      local name = id and spellName(id) or nameOrId
      if C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then a = C_UnitAuras.GetAuraDataBySpellName("player", name, "HELPFUL")
      elseif AuraUtil and AuraUtil.FindAuraByName then
        local n, _, count = AuraUtil.FindAuraByName(name, "player", "HELPFUL")
        if n then a = { name = n, applications = count } end
      end
    end
  end)
  if a then
    local st = a.applications
    if secret(st) then seen.aura = "partly hidden (stack counts)"; return a, nil end
    seen.aura = "readable"
    return a, tonumber(st) or 0
  end
  return nil
end

-- does this unit carry something that matches the filter? (only asks "is there one")
local function hasAura(unit, filter)
  if not UnitExists or not UnitExists(unit) then return false end
  local found = false
  pcall(function()
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
      found = C_UnitAuras.GetAuraDataByIndex(unit, 1, filter) ~= nil
    elseif UnitAura then
      found = UnitAura(unit, 1, filter) ~= nil
    end
  end)
  return found
end
local function targetHasStealable()
  if not UnitExists("target") or not (UnitCanAttack and UnitCanAttack("player", "target")) then return false end
  if hasAura("target", "HELPFUL|STEALABLE") then return true end
  -- older filter set: look for a magic buff marked stealable
  local yes = false
  pcall(function()
    for i = 1, 40 do
      local a = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex and C_UnitAuras.GetAuraDataByIndex("target", i, "HELPFUL")
      if not a then break end
      if not secret(a.isStealable) and a.isStealable then yes = true break end
      if not secret(a.dispelName) and a.dispelName == "Magic" then yes = true break end
    end
  end)
  return yes
end
-- debuff types on your group that you can remove: { Magic = true, Poison = true, ... }
-- ("unknown" when the game hides the type but there is something)
local function groupDebuffTypes()
  local units = { "player" }
  if IsInRaid and IsInRaid() then for i = 1, (GetNumGroupMembers and GetNumGroupMembers() or 0) do units[#units + 1] = "raid" .. i end
  elseif IsInGroup and IsInGroup() then for i = 1, 4 do units[#units + 1] = "party" .. i end end
  local types, any = {}, false
  for _, u in ipairs(units) do
    if UnitExists and UnitExists(u) then
      for _, filter in ipairs({ "HARMFUL|RAID_PLAYER_DISPELLABLE", "HARMFUL|RAID" }) do
        pcall(function()
          for i = 1, 40 do
            local a = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex and C_UnitAuras.GetAuraDataByIndex(u, i, filter)
            if not a then break end
            any = true
            local dn = a.dispelName
            if dn ~= nil and not secret(dn) and dn ~= "" then types[dn] = true else types.unknown = true end
          end
        end)
      end
      -- every debuff whose type the game shows (Magic, Curse, Poison, Disease)
      pcall(function()
        for i = 1, 40 do
          local a
          if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then a = C_UnitAuras.GetAuraDataByIndex(u, i, "HARMFUL")
          elseif UnitDebuff then
            local n, _, _, dt = UnitDebuff(u, i)
            if n then a = { dispelName = dt } end
          end
          if not a then break end
          local dn = a.dispelName
          if dn ~= nil and not secret(dn) and (dn == "Magic" or dn == "Curse" or dn == "Poison" or dn == "Disease") then types[dn] = true; any = true end
        end
      end)
    end
  end
  return any and types or nil
end
local function groupNeedsCleanse()
  local units = { "player" }
  if IsInRaid and IsInRaid() then for i = 1, (GetNumGroupMembers and GetNumGroupMembers() or 0) do units[#units + 1] = "raid" .. i end
  elseif IsInGroup and IsInGroup() then for i = 1, 4 do units[#units + 1] = "party" .. i end end
  for _, u in ipairs(units) do
    -- "RAID" on harmful = what you can dispel
    if hasAura(u, "HARMFUL|RAID_PLAYER_DISPELLABLE") or hasAura(u, "HARMFUL|RAID") then return true end
  end
  return false
end

-- weapon enchant on main / off hand
local function hasEnchant(hand)
  if not GetWeaponEnchantInfo then return true end
  local ok, hasMain, _, _, _, hasOff = pcall(GetWeaponEnchantInfo)
  if not ok then return true end
  if hand == "off" then
    if not (GetInventoryItemLink and GetInventoryItemLink("player", 17)) then return true end   -- nothing in the off hand
    return hasOff and true or false
  end
  return hasMain and true or false
end

---------------------------------------------------------------------------
-- Your debuffs on the target (DoTs to keep up)
---------------------------------------------------------------------------
local dotCast = {}            -- spellID -> GetTime() you last put it on the current target
local dotLearned = {}         -- spellID -> how long it lasted when the game showed it
S:On("PLAYER_TARGET_CHANGED", function() wipe(dotCast) end)
-- seconds left of your debuff on the target: number, or nil when unknown
local function targetDebuffLeft(id, lasts)
  local left
  pcall(function()
    local a
    if C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then a = C_UnitAuras.GetAuraDataBySpellName("target", spellName(id), "HARMFUL|PLAYER") end
    if a then
      local exp, dur = a.expirationTime, a.duration
      if exp ~= nil and not secret(exp) and exp > 0 then
        left = exp - now()
        if dur ~= nil and not secret(dur) and dur > 0 then dotLearned[id] = dur end
      else left = 99 end                                      -- it's there, the time is hidden
    end
  end)
  if left then return left end
  -- the game won't say: work it out from when you cast it
  local t = dotCast[id]
  local d = tonumber(lasts) or dotLearned[id] or 12      -- 12 s until the game shows the real time
  if t then return math.max(0, t + d - now()) end
  return 0
end

---------------------------------------------------------------------------
-- Procs: the game's own spell highlight events, and your proc buffs
---------------------------------------------------------------------------
local overlay = {}          -- spellID -> true while the game highlights it
local procOn = {}           -- index in p.procs -> true while active (and its trigger matched)
local rawOn = {}            -- index -> the buff / highlight is there (whatever caused it)
local risingAt = {}         -- index -> when it appeared, waiting a moment to see what caused it
local matched = {}          -- index -> its trigger matched when it appeared

-- What just happened in the fight, from the game's combat text events (still allowed):
-- you dodged / parried / blocked, the target dodged / parried, you crit.
local recent = {}           -- kind -> GetTime()
S.ROT_TRIGGERS = {
  { value = "any", text = "Any way (always)" },
  { value = "other", text = "Anything else (e.g. random)" },
  { value = "dodge", text = "After you dodge" },
  { value = "parry", text = "After you parry" },
  { value = "dodgeparry", text = "After you dodge or parry" },
  { value = "block", text = "After you block" },
  { value = "miss", text = "After an attack misses you" },
  { value = "avoid", text = "After you dodge, parry, block or are missed" },
  { value = "tmiss", text = "After your attack misses" },
  { value = "tdodge", text = "After your target dodges" },
  { value = "tparry", text = "After your target parries" },
  { value = "crit", text = "After a critical hit" },
  { value = "cast", text = "When the game reports this spell (weapon procs)" },
  { value = "extra", text = "When you get extra attacks (Windfury)" },
  { value = "wf", text = "Extra melee swings (Windfury - experimental)" },
}
local TRIGGER_KINDS = { dodge = { "dodge" }, parry = { "parry" }, dodgeparry = { "dodge", "parry" }, block = { "block" },
  miss = { "miss" }, avoid = { "dodge", "parry", "block", "miss" }, tmiss = { "tmiss" }, extra = { "extra" }, wf = { "wf" },
  tdodge = { "tdodge" }, tparry = { "tparry" }, crit = { "crit" } }
-- how long after the dodge / parry the proc can show up and still count (in game it
-- showed up 2-3 seconds later); crits have to be right away
local TRIGGER_WINDOW = { dodge = 3.5, parry = 3.5, block = 3.5, miss = 3.5, tdodge = 3.5, tparry = 3.5, tmiss = 3.5, crit = 0.75 }
-- a short log of what the game reports (to see why a trigger didn't fire)
local diag = {}
local spyUntil                 -- /ccenter rotspy: record everything until then
local spyLog                   -- the recording (oldest first), kept in g.rotSpy
local logEvent
logEvent = function(ev, ...)
  local parts = { string.format("%s +%.1f", date("%H:%M:%S"), GetTime() % 100), ev }
  for i = 1, math.min(select("#", ...), 4) do
    local v = select(i, ...)
    parts[#parts + 1] = secret(v) and "SECRET" or tostring(v)
  end
  table.insert(diag, 1, table.concat(parts, " "))
  while #diag > 20 do table.remove(diag) end
  if spyUntil and now() < spyUntil and spyLog then
    spyLog[#spyLog + 1] = parts and table.concat(parts, " ") or ""
    if #spyLog > 600 then table.remove(spyLog, 1) end
  end
  if S.db then G().rotDiag = diag end
end
S.RotDiag = function() return diag end
-- the scrolling combat text over your character: "Dodge", "Parry", "Block" ...
-- ordinary hits and heals would flood the log; keep everything else
local NOISE = { DAMAGE = true, SPELL_DAMAGE = true, DAMAGE_CRIT = true, SPELL_DAMAGE_CRIT = true, HEAL = true, HEAL_CRIT = true,
  PERIODIC_HEAL = true, PERIODIC_DAMAGE = true, SPELL_AURA_START = true, SPELL_AURA_END = true, SPELL_AURA_START_HARMFUL = true,
  SPELL_AURA_END_HARMFUL = true, ENERGIZE = true, PERIODIC_ENERGIZE = true, WOUND = true }
S:On("COMBAT_TEXT_UPDATE", function(_, kind, a2, a3)
  -- the details (spell / buff name) aren't in the event any more: ask for them
  if a2 == nil and GetCurrentCombatTextEventInfo then
    local ok, x, y = pcall(GetCurrentCombatTextEventInfo)
    if ok then a2, a3 = x, y end
  end
  -- a named buff showing up in the scrolling text counts as that spell being reported
  if (kind == "SPELL_AURA_START" or kind == "SPELL_ACTIVE") and type(a2) == "string" and not secret(a2) then
    local id = spellInfo(a2)
    if id then S:RotSpellReported(id) else S:RotNameReported(a2) end
  end
  local spying = spyUntil and now() < spyUntil
  if secret(kind) or not NOISE[tostring(kind)] or (spying and kind ~= "DAMAGE" and kind ~= "SPELL_DAMAGE") then logEvent("COMBAT_TEXT_UPDATE", kind, a2, a3) end
  if secret(kind) then return end
  local t = now()
  local k = tostring(kind or ""):upper()
  if k == "DODGE" or k == "SPELL_DODGE" then S:RotHappened("dodge")
  elseif k == "PARRY" or k == "SPELL_PARRY" then S:RotHappened("parry")
  elseif k == "BLOCK" or k == "SPELL_BLOCK" or k == "BLOCK_REDUCED" then S:RotHappened("block")
  elseif k == "MISS" or k == "SPELL_MISS" then S:RotHappened("miss")
  elseif k == "EXTRA_ATTACKS" then S:RotHappened("extra") end
end)
-- Windfury: your normal swings land ~2-3 s apart (one weapon). In game the extra
-- attacks come 0.3-0.6 s after the swing, so a swing much sooner than the last one
-- is an extra attack. Your spells' own hits (Stormstrike ...) and fire / nature hits
-- (shocks, totems) don't count as swings.
local WF_GAP = 1.0                      -- a swing this soon after the last one = extra attack
local lastHitAt, lastWfAt, lastSwingAt = 0, 0, 0
local SWINGS = { WOUND = true, MISS = true, DODGE = true, PARRY = true, BLOCK = true, ABSORB = true, RESIST = true }
local function physical(school)
  if school == nil or secret(school) then return nil end      -- unknown
  return school == 1
end
S:On("UNIT_COMBAT", function(_, unit, action, flag, amount, school)
  local spying = spyUntil and now() < spyUntil
  if spying and unit == "target" then
    logEvent("HIT", tostring(action), "school=" .. (school == nil and "nil" or (secret(school) and "SECRET" or tostring(school))),
      string.format("gap=%.3f", now() - lastHitAt), string.format("swingGap=%.3f", now() - lastSwingAt), string.format("sinceCast=%.2f", now() - (S.__lastPlayerCast or 0)))
  end
  if (unit == "player" or unit == "target") and (secret(action) or not NOISE[tostring(action)]) then logEvent("UNIT_COMBAT", unit, action, flag, amount) end
  if unit == "target" and not secret(unit) and not secret(action) and SWINGS[tostring(action):upper()] then
    local t = now()
    local phys = physical(school)
    local fromSpell = t - (S.__lastPlayerCast or 0) <= 0.15      -- the hit of a spell you just cast
    if phys ~= false and not fromSpell then                     -- an auto-attack swing
      if t - lastSwingAt <= WF_GAP and t - lastWfAt > 1.5 then  -- one pop-up per Windfury (its swings come in a burst)
        lastWfAt = t
        S:RotHappened("wf")
      end
      lastSwingAt = t
    end
    lastHitAt = t
  end
  if secret(unit) or secret(action) then return end
  local t = now()
  if unit == "player" then
    action = tostring(action or ""):upper()
    if action == "DODGE" then S:RotHappened("dodge") elseif action == "PARRY" then S:RotHappened("parry")
    elseif action == "BLOCK" then S:RotHappened("block") elseif action == "MISS" then S:RotHappened("miss") end
    if not secret(flag) and flag == "BLOCK" then S:RotHappened("block") end
    recent.seen = t
  elseif unit == "target" then
    action = tostring(action or ""):upper()
    if action == "DODGE" then S:RotHappened("tdodge") elseif action == "PARRY" then S:RotHappened("tparry")
    elseif action == "MISS" then S:RotHappened("tmiss") end
    if action == "WOUND" and not secret(flag) and flag == "CRITICAL" then S:RotHappened("crit") end
    recent.seen = t
  end
end)
-- "on the dodge / parry itself" procs: no buff or cooldown to watch - the pop-up goes
-- off the moment the game reports it, and the spell (if any) glows for a few seconds
eventGlowUntil = {}           -- proc entry -> glow its spell until
local eventLastFired = {}     -- proc entry -> last pop-up (the game reports a dodge twice)
-- anything triggered by a dodge / parry / block / miss fires on the event itself,
-- unless you untick it for that proc (then it waits for its buff or cooldown)
local EVENT_TRIGGERS = { dodge = true, parry = true, dodgeparry = true, block = true, miss = true, avoid = true, tdodge = true, tparry = true, tmiss = true, extra = true, wf = true }
local function eventOnly(pr) return (pr.eventOnly ~= false and EVENT_TRIGGERS[pr.trigger or ""] == true) or pr.trigger == "cast" end
S.RotEventOnly = eventOnly
function S:RotHappened(kind)
  local t = now()
  recent[kind] = t; recent.seen = t
  if not S.db then return end
  if not S.RotationalOn() then return end   -- (removed / switched off: no pop-ups, sounds or glows)
  local p = P()
  if not p.enabled then return end
  for _, pr in ipairs(p.procs) do
    if eventOnly(pr) then
      local hit = false
      for _, k in ipairs(TRIGGER_KINDS[pr.trigger] or {}) do if k == kind then hit = true end end
      if hit and t - (eventLastFired[pr] or 0) > 1 then
        eventLastFired[pr] = t
        logEvent("EVENT-PROC", kind, pr.text or (pr.use and spellName(pr.use)) or "pop-up")
        if pr.popup ~= false and S.RotPopup and S.RotProcPopupOpts then S.RotPopup(S.RotProcPopupOpts(pr)) end
        if pr.use then
          eventGlowUntil[pr] = t + (tonumber(pr.lasts) or 5)
          if pr.reset then resetReady[pr.use] = true end
        end
      end
    end
  end
  if S.RotApply then pcall(S.RotApply) end
end
-- procs set to "When the game reports this spell": the moment that spell shows up as
-- something you cast or a buff you gained (Windfury Attack ...), the pop-up goes off
function S:RotNameReported(nm) return S:RotSpellReported(nil, nm) end
function S:RotSpellReported(id, byName)
  if not S.db then return end
  if not S.RotationalOn() then return end   -- (removed / switched off: no pop-ups, sounds or glows)
  local p = P()
  if not p.enabled then return end
  local nm = byName or spellName(id)
  local t = now()
  for _, pr in ipairs(p.procs) do
    if pr.trigger == "cast" and pr.aura and ((id and pr.aura == id) or spellName(pr.aura) == nm) and t - (eventLastFired[pr] or 0) > 0.5 then
      eventLastFired[pr] = t
      logEvent("SPELL-PROC", nm)
      if pr.popup ~= false and S.RotPopup and S.RotProcPopupOpts then S.RotPopup(S.RotProcPopupOpts(pr)) end
      if pr.use then eventGlowUntil[pr] = t + (tonumber(pr.lasts) or 5); if pr.reset then resetReady[pr.use] = true end end
    end
  end
end
function S:RotResetState() wipe(procOn); wipe(rawOn); wipe(risingAt); wipe(matched); wipe(eventGlowUntil) end
S:On("ACTIVE_TALENT_GROUP_CHANGED", function() S:RotResetState(); if S.RefreshRotational then S:RefreshRotational() end end)
S:On("PLAYER_SPECIALIZATION_CHANGED", function(_, u) if u == "player" then S:RotResetState(); if S.RefreshRotational then S:RefreshRotational() end end end)
local function happened(kind, at)
  local t = recent[kind]
  if t == nil then return false end
  local d = (at or now()) - t                    -- seconds from the dodge to the proc
  return d >= -0.5 and d <= (TRIGGER_WINDOW[kind] or 1)
end
function S:RotRecentEvents() return recent end
-- did this entry's trigger cause the proc that appeared at time `at`?
local function triggerMatches(pr, at, siblings)
  local trig = pr.trigger or "any"
  if trig == "any" then return true end
  if trig == "other" then
    -- only when none of the specific causes listed for the same proc happened
    for _, sib in ipairs(siblings) do
      for _, k in ipairs(TRIGGER_KINDS[sib.trigger or ""] or {}) do if happened(k, at) then return false end end
    end
    return true
  end
  for _, k in ipairs(TRIGGER_KINDS[trig] or {}) do if happened(k, at) then return true end end
  return false
end
-- two entries watch the same proc: same buff (or, without a buff, the same lit-up spell)
local function sameProc(a, b)
  if a.aura or b.aura then return a.aura == b.aura end
  return a.use == b.use
end
S:On("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", function(_, id)
  if id and not secret(id) then overlay[id] = true end
  if logEvent then logEvent("GAME-LIGHTS-UP", secret(id) and "SECRET" or (tostring(id) .. " " .. spellName(id))) end
end)
S:On("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", function(_, id) if id and not secret(id) then overlay[id] = nil end end)

local POP_COLORS = {
  gold = { 1, 0.82, 0.2 }, white = { 1, 1, 1 }, green = { 0.35, 1, 0.35 }, blue = { 0.35, 0.65, 1 },
  red = { 1, 0.3, 0.25 }, purple = { 0.78, 0.45, 1 }, orange = { 1, 0.55, 0.1 },
}
S.ROT_POP_ANIMS = { { value = "fade", text = "Fade in" }, { value = "zoom", text = "Zoom in" }, { value = "bounce", text = "Bounce" },
  { value = "shake", text = "Shake" }, { value = "slide", text = "Slide in" } }
S.ROT_SCREEN = { { value = "none", text = "No screen effect" }, { value = "edges", text = "Glowing screen edges" },
  { value = "pulse", text = "Pulsing screen edges" }, { value = "flash", text = "Whole-screen flash" } }
S.ROT_SIZES = { { value = 14, text = "Small" }, { value = 20, text = "Normal" }, { value = 28, text = "Big" }, { value = 38, text = "Huge" } }
S.ROT_POP_COLORS = {}
for _, k in ipairs({ "gold", "white", "green", "blue", "red", "purple", "orange" }) do S.ROT_POP_COLORS[#S.ROT_POP_COLORS + 1] = { value = k, text = k:sub(1, 1):upper() .. k:sub(2) } end

-- full-screen effects: coloured edges (steady or pulsing) or a quick flash
local screenFx
local function screenEffect(kind, color)
  if not kind or kind == "none" then return end
  if not screenFx then
    local f = CreateFrame("Frame", "CC_RotScreenFx", UIParent)
    f:SetAllPoints(UIParent); f:SetFrameStrata("FULLSCREEN_DIALOG"); f:EnableMouse(false)
    f.flash = f:CreateTexture(nil, "BACKGROUND"); f.flash:SetAllPoints(); f.flash:SetTexture("Interface\\Buttons\\WHITE8X8")
    f.edges = {}
    local function edge(p1, p2, horiz)
      local t = f:CreateTexture(nil, "ARTWORK"); t:SetTexture("Interface\\Buttons\\WHITE8X8")
      t:SetPoint(p1); t:SetPoint(p2)
      if horiz then t:SetHeight(90) else t:SetWidth(90) end
      f.edges[#f.edges + 1] = { tex = t, horiz = horiz, p = p1 }
      return t
    end
    edge("TOPLEFT", "TOPRIGHT", true); edge("BOTTOMLEFT", "BOTTOMRIGHT", true)
    edge("TOPLEFT", "BOTTOMLEFT", false); edge("TOPRIGHT", "BOTTOMRIGHT", false)
    f:SetScript("OnUpdate", function(self, el)
      self.t = self.t + el
      local a
      if self.kind == "flash" then a = math.max(0, 0.45 * (1 - self.t / 0.6)); if self.t > 0.6 then self:Hide() end
      elseif self.kind == "pulse" then a = 0.6 * (0.5 + 0.5 * math.sin(self.t * 9)) * math.max(0, 1 - self.t / 2); if self.t > 2 then self:Hide() end
      else a = 0.65 * (self.t < 0.2 and self.t / 0.2 or math.max(0, 1 - (self.t - 1.2) / 0.6)); if self.t > 1.8 then self:Hide() end end
      self:SetAlpha(a)
    end)
    screenFx = f
  end
  local c = POP_COLORS[color] or POP_COLORS.gold
  local f = screenFx
  f.kind, f.t = kind, 0
  f.flash:SetShown(kind == "flash"); f.flash:SetVertexColor(c[1], c[2], c[3], 1)
  for _, e in ipairs(f.edges) do
    e.tex:SetShown(kind ~= "flash")
    -- strong at the screen edge, fading towards the middle
    local tex = e.tex
    local from, to = CreateColor and CreateColor(c[1], c[2], c[3], 1), CreateColor and CreateColor(c[1], c[2], c[3], 0)
    if tex.SetGradient and from then
      if e.horiz then
        if e.p == "TOPLEFT" then tex:SetGradient("VERTICAL", to, from) else tex:SetGradient("VERTICAL", from, to) end
      else
        if e.p == "TOPLEFT" then tex:SetGradient("HORIZONTAL", from, to) else tex:SetGradient("HORIZONTAL", to, from) end
      end
    else tex:SetVertexColor(c[1], c[2], c[3], 0.5) end
  end
  f:SetAlpha(0); f:Show()
end
S.RotScreenEffect = screenEffect

-- opts: text, icon, color, anim, screen, size, sound
-- Pop-ups: each one gets its own frame at a random spot around the usual place, picked
-- so it overlaps the ones already showing as little as possible.
local popups = {}
local POP_W, POP_H = 340, 60          -- roughly how much room one takes
local SPREAD_X, SPREAD_Y = 170, 130   -- how far from the usual place it may land
local function popupOnUpdate(self, el)
  self.t = self.t + el
  local t = self.t
  local a = t < 0.05 and t / 0.05 or (t > 1.8 and math.max(0, 1 - (t - 1.8) / 0.4) or 1)
  local scale, dx = 1, 0
  if self.anim == "zoom" then scale = t < 0.2 and (1.8 - 0.8 * t / 0.2) or 1
  elseif self.anim == "bounce" then scale = t < 0.5 and (1 + 0.35 * math.abs(math.sin(t * 12)) * (1 - t / 0.5)) or 1
  elseif self.anim == "shake" then dx = t < 0.5 and (10 * math.sin(t * 60) * (1 - t / 0.5)) or 0
  elseif self.anim == "slide" then dx = t < 0.25 and (-260 * (1 - t / 0.25)) or 0; a = math.min(a, 1) end
  self:SetScale(scale); self:SetAlpha(a)
  self:ClearAllPoints(); self:SetPoint("CENTER", UIParent, "CENTER", (self.baseX or 0) / scale + dx, (self.baseY or 180) / scale)
  if t > 2.2 then self:Hide() end
end
local function getPopup()
  for _, f in ipairs(popups) do if not f:IsShown() then return f end end
  local n = #popups + 1
  local f = CreateFrame("Frame", n == 1 and "CC_RotPopup" or ("CC_RotPopup" .. n), UIParent)
  f:SetSize(360, 64); f:SetFrameStrata("HIGH")
  f.icon = f:CreateTexture(nil, "ARTWORK"); f.icon:SetSize(48, 48); f.icon:SetPoint("LEFT", 8, 0)
  f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  f.glow = f:CreateTexture(nil, "BACKGROUND"); f.glow:SetTexture(UI.ART.glow); f.glow:SetBlendMode("ADD")
  f.glow:SetPoint("TOPLEFT", f.icon, -14, 14); f.glow:SetPoint("BOTTOMRIGHT", f.icon, 14, -14)
  f.text = f:CreateFontString(nil, "OVERLAY")
  f.text:SetPoint("LEFT", f.icon, "RIGHT", 10, 0); f.text:SetJustifyH("LEFT")
  f:SetScript("OnUpdate", popupOnUpdate)
  f:Hide()
  popups[n] = f
  return f
end
-- a spot near (cx, cy) that overlaps the pop-ups on screen as little as possible
local function freeSpot(cx, cy, self)
  local others = {}
  for _, f in ipairs(popups) do if f ~= self and f:IsShown() and f.baseX then others[#others + 1] = f end end
  if #others == 0 then
    -- on its own: still a little random so repeated pop-ups don't look stuck
    return cx + math.random(-SPREAD_X, SPREAD_X) * 0.3, cy + math.random(-SPREAD_Y, SPREAD_Y) * 0.3
  end
  local bestX, bestY, bestOverlap
  for _ = 1, 30 do
    local x = cx + math.random(-SPREAD_X, SPREAD_X)
    local y = cy + math.random(-SPREAD_Y, SPREAD_Y)
    local overlap = 0
    for _, o in ipairs(others) do
      local ox = math.max(0, POP_W - math.abs(x - o.baseX))
      local oy = math.max(0, POP_H - math.abs(y - o.baseY))
      overlap = overlap + ox * oy
    end
    if not bestOverlap or overlap < bestOverlap then bestX, bestY, bestOverlap = x, y, overlap end
    if overlap == 0 then break end
  end
  return bestX, bestY
end
S.RotPopupFreeSpot = freeSpot

local function showPopup(opts)
  if not S.RotationalOn() then return end   -- (removed / switched off: no pop-ups, sounds or glows)
  if type(opts) == "string" then opts = { text = opts } end
  local popup = getPopup()
  local c = POP_COLORS[opts.color or "gold"] or POP_COLORS.gold
  popup.glow:SetVertexColor(c[1], c[2], c[3], 0.85)
  popup.icon:SetTexture(opts.icon or "Interface\\Icons\\Spell_Nature_Lightning")
  popup.text:SetFont("Fonts\\FRIZQT__.TTF", tonumber(opts.size) or 20, "OUTLINE")
  popup.text:SetTextColor(c[1], c[2], c[3])
  popup.text:SetText(opts.text or "")
  local at = P().look.popAt
  popup.baseX, popup.baseY = nil, nil
  popup.baseX, popup.baseY = freeSpot(at and at[1] or 0, at and at[2] or 180, popup)
  popup.anim = opts.anim or "fade"
  popup.t = 0; popup:SetAlpha(0); popup:Show()
  screenEffect(opts.screen, opts.screenColor or opts.color)
  if opts.sound ~= "none" then
    if opts.sound and S.PlayReminderSound then S:PlayReminderSound(opts.sound)
    elseif PlaySound and SOUNDKIT and SOUNDKIT.ALARM_CLOCK_WARNING_3 then PlaySound(SOUNDKIT.ALARM_CLOCK_WARNING_3, "SFX") end
  end
  return popup
end
-- the pop-up a proc shows, from its settings
-- the pop-up's picture: the spell you chose for it, else the proc's own spell;
-- Windfury pop-ups use the Windfury Weapon icon
local function popupIcon(pr)
  if pr.iconSpell then return spellIcon(pr.iconSpell) end
  if pr.use or pr.aura then return spellIcon(pr.use or pr.aura) end
  if pr.trigger == "wf" then
    local id = spellInfo("Windfury Weapon")
    return id and spellIcon(id) or "Interface\\Icons\\Spell_Nature_Cyclone"
  end
end
local function procPopupOpts(pr)
  local text = pr.text and pr.text ~= "" and pr.text
    or ((pr.label or spellName(pr.aura or pr.use)) .. (pr.use and ("  |cffffffff> " .. spellName(pr.use) .. "|r") or ""))
  if not (pr.text and pr.text ~= "") and not pr.aura and not pr.use and pr.trigger == "wf" then text = "Windfury!" end
  return { text = text, icon = popupIcon(pr), color = pr.color, anim = pr.anim, screen = pr.screen, size = pr.size, sound = pr.sound }
end
S.RotProcPopupOpts = procPopupOpts
S.RotPopup = showPopup

-- is proc #i active right now?
-- Some procs leave no buff - the game just ends the cooldown early (Improved
-- Stormstrike on a dodge / parry). When cooldowns can be read, spot that: the spell
-- was on cooldown a moment ago, still had a while to go, and now it's ready.
local cdTrack = {}            -- spellID -> { left =, t = } last reading
local resetSeen = {}          -- spellID -> when its cooldown ended early
function S:RotWatchResets()
  local p = P()
  for _, pr in ipairs(p.procs) do
    local id = pr.use
    if id and pr.reset then
      local start, dur = readCooldown(id)
      if start then
        local left = (dur > 1.6) and math.max(0, start + dur - now()) or 0
        local prev = cdTrack[id]
        if prev and prev.left > 0.6 and left <= 0.05 then
          local expected = prev.left - (now() - prev.t)       -- what should still be left
          if expected > 0.5 then
            resetSeen[id] = now()
            logEvent("CD-RESET", spellName(id), string.format("%.1fs early", expected))
          end
        end
        cdTrack[id] = { left = left, t = now() }
      end
    end
  end
end

local function procActive(pr)
  -- a cooldown that ended early counts as the proc, until you use the spell
  if pr.reset and pr.use and resetSeen[pr.use] and now() - resetSeen[pr.use] < 15 then return true end
  if pr.aura then
    local a, st = myAura(pr.aura)
    if a then
      if pr.stacks and pr.stacks > 1 then
        if st == nil then return pr.use and overlay[pr.use] and true or false end   -- stacks hidden: trust the game's highlight
        return st >= pr.stacks
      end
      return true
    end
  end
  if pr.use and overlay[pr.use] then return true end
  return false
end

---------------------------------------------------------------------------
-- Action buttons
---------------------------------------------------------------------------
local buttons = {}            -- list of action buttons found
local bfCache, bfAt = {}, 0   -- spell -> its visible buttons (buttonsFor; cleared on bar changes, kept 0.5 s)
local function slotOf(btn)
  local a = btn.action
  if type(a) ~= "number" and btn.GetAttribute then local ok, v = pcall(btn.GetAttribute, btn, "action"); if ok then a = tonumber(v) end end
  if type(a) == "number" and not secret(a) then return a end
end
-- (one plain function for every frame - no new function per frame, the UI has thousands)
local function isActionButton(f)
  return f.IsObjectType and (f:IsObjectType("CheckButton") or f:IsObjectType("Button")) and slotOf(f) and f:GetName() and true or false
end
local function scanButtons()
  if combat() then return end
  local out = {}
  local f = EnumerateFrames and EnumerateFrames()
  while f do
    local ok, yes = pcall(isActionButton, f)
    if ok and yes then out[#out + 1] = f end
    f = EnumerateFrames(f)
  end
  if #out == 0 then
    for _, bar in ipairs({ "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarRightButton", "MultiBarLeftButton",
      "MultiBar5Button", "MultiBar6Button", "MultiBar7Button" }) do
      for i = 1, 12 do local b = _G[bar .. i]; if b and slotOf(b) then out[#out + 1] = b end end
    end
  end
  buttons = out
  wipe(bfCache)
end
S.RotScanButtons = scanButtons

-- the spell an action slot casts (spells and macros)
local function slotSpell(slot)
  if not GetActionInfo then return nil end
  local ok, kind, id = pcall(GetActionInfo, slot)
  if not ok or secret(kind) or secret(id) then return nil end
  if kind == "spell" then return id end
  if kind == "macro" and GetMacroSpell then local ok2, sid = pcall(GetMacroSpell, id); if ok2 and not secret(sid) then return sid end end
end
-- (20 times a second: the answer is kept per spell for half a second, and dropped at once when a
-- bar or a spell changes - it used to check every button's slot and spell on each call)
local function buttonsFor(spellID)
  local t = GetTime()
  if t - bfAt > 0.5 then wipe(bfCache); bfAt = t end
  local hit = spellID and bfCache[spellID]
  if hit then return hit end
  local out = {}
  if spellID then bfCache[spellID] = out end
  local nm = spellName(spellID)
  for _, b in ipairs(buttons) do
    local ok, vis = pcall(b.IsVisible, b)
    if ok and vis then
      local slot = slotOf(b)
      local sid = slot and slotSpell(slot)
      if sid and (sid == spellID or spellName(sid) == nm) then out[#out + 1] = b end
    end
  end
  return out
end

---------------------------------------------------------------------------
-- Glows: our own frames laid over the buttons (the buttons themselves are never touched)
---------------------------------------------------------------------------
local COLORS = {
  gold = { 1, 0.82, 0.2 }, green = { 0.3, 1, 0.3 }, blue = { 0.3, 0.6, 1 }, red = { 1, 0.3, 0.25 }, purple = { 0.75, 0.4, 1 }, white = { 1, 1, 1 },
  orange = { 1, 0.55, 0.1 }, cyan = { 0.2, 0.95, 1 }, pink = { 1, 0.4, 0.8 },
}
S.RotColors = COLORS
local function lookColor(look, key, def)
  local v = look[key]
  if type(v) == "table" then return v end
  return COLORS[v or def] or COLORS[def] or COLORS.gold
end
-- how bright the glow is at time t: pulse / breathe / flash / steady / heartbeat
local function animAlpha(anim, t, speed)
  speed = speed or 6
  if anim == "steady" then return 1 end
  if anim == "flash" then return (math.sin(t * speed) > 0) and 1 or 0.12 end
  if anim == "breathe" then return 0.35 + 0.65 * (0.5 + 0.5 * math.sin(t * speed * 0.45)) end
  if anim == "heartbeat" then
    local ph = (t * speed / 6) % 1
    if ph < 0.12 then return 1 elseif ph < 0.22 then return 0.45 elseif ph < 0.34 then return 1 end
    return 0.35
  end
  return 0.55 + 0.45 * math.sin(t * speed)              -- pulse
end
S.RotAnimAlpha = animAlpha
local glows = {}              -- button -> glow frame
local function getGlow(btn)
  local g = glows[btn]
  if g then return g end
  g = CreateFrame("Frame", nil, UIParent)
  g:SetAllPoints(btn)
  g.outer = g:CreateTexture(nil, "OVERLAY"); g.outer:SetTexture(UI.ART.glow); g.outer:SetBlendMode("ADD")
  g.edge = g:CreateTexture(nil, "OVERLAY", nil, 2); g.edge:SetTexture("Interface\\Buttons\\UI-ActionButton-Border"); g.edge:SetBlendMode("ADD")
  g.edge:SetPoint("CENTER")
  -- extra effects: a turning star burst, a solid tint over the icon
  g.star = g:CreateTexture(nil, "OVERLAY", nil, 3); g.star:SetTexture("Interface\\Cooldown\\star4"); g.star:SetBlendMode("ADD"); g.star:SetPoint("CENTER")
  g.tint = g:CreateTexture(nil, "OVERLAY", nil, 1); g.tint:SetAllPoints(); g.tint:SetColorTexture(1, 1, 1, 1); g.tint:SetBlendMode("ADD")
  g:Hide()
  g:SetScript("OnUpdate", function(self, el)
    self.t = (self.t or 0) + el
    local look = self.look or {}
    local a = (self.power or 0.8) * animAlpha(look.anim or "pulse", self.t, look.speed or 7)
    self.outer:SetAlpha(a); self.edge:SetAlpha(math.min(1, a + 0.2))
    if self.star:IsShown() then self.star:SetRotation(self.t * (look.spinSpeed or 1.6)); self.star:SetAlpha(math.min(1, a + 0.1)) end
    if self.tint:IsShown() then self.tint:SetAlpha(a * 0.35) end
  end)
  glows[btn] = g
  return g
end
local function setGlow(btn, kind)
  local g = getGlow(btn)
  local look = P().look
  local c = lookColor(look, "color", "gold")
  if kind == "soft" then c = lookColor(look, "softColor", "blue") end
  g.kind, g.look = kind, look
  g.power = kind == "strong" and (look.strong or 0.9) or (look.soft or 0.45)
  local style = look.style or "both"           -- glow / border / both
  g.outer:SetShown(style ~= "border"); g.edge:SetShown(style ~= "glow")
  local pad = look.glowSize or 12
  g.outer:ClearAllPoints(); g.outer:SetPoint("TOPLEFT", -pad, pad); g.outer:SetPoint("BOTTOMRIGHT", pad, -pad)
  g.outer:SetVertexColor(c[1], c[2], c[3]); g.edge:SetVertexColor(c[1], c[2], c[3])
  local w = btn:GetWidth() or 36
  g.edge:SetSize(w * 1.75, w * 1.75)
  g.star:SetShown(look.spin and kind == "strong" and true or false)
  g.star:SetSize(w * 2.2, w * 2.2); g.star:SetVertexColor(c[1], c[2], c[3])
  g.tint:SetShown(look.tint and kind == "strong" and true or false); g.tint:SetVertexColor(c[1], c[2], c[3])
  g:SetFrameStrata(btn:GetFrameStrata() or "MEDIUM"); g:SetFrameLevel((btn:GetFrameLevel() or 1) + 8)
  g:Show()
end

-- the movable "next" icon (optional)
local nextIcon
local function getNextIcon()
  if nextIcon then return nextIcon end
  local f = CreateFrame("Frame", "CC_RotNext", UIParent)
  f:SetSize(52, 52); f:SetFrameStrata("MEDIUM")
  local at = P().look.nextAt
  if type(at) == "table" then f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", at[1], at[2]) else f:SetPoint("CENTER", 0, -160) end
  -- rounded corners, glow around the outside edge
  f.icon = f:CreateTexture(nil, "ARTWORK"); f.icon:SetAllPoints(); f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  f.glow = f:CreateTexture(nil, "BACKGROUND"); f.glow:SetTexture("Interface\\AddOns\\CommandCenter\\Media\\UI\\halo_r"); f.glow:SetBlendMode("ADD"); f.glow:SetPoint("CENTER")
  f.border = f:CreateTexture(nil, "OVERLAY"); f.border:SetTexture("Interface\\AddOns\\CommandCenter\\Media\\UI\\rring2"); f.border:SetAllPoints()
  if f.CreateMaskTexture then
    local ok, m = pcall(f.CreateMaskTexture, f)
    if ok and m then
      m:SetAllPoints(); f.mask = m
      pcall(f.icon.AddMaskTexture, f.icon, m)
    end
  end
  f.star = f:CreateTexture(nil, "OVERLAY", nil, 2); f.star:SetTexture("Interface\\Cooldown\\star4"); f.star:SetBlendMode("ADD"); f.star:SetPoint("CENTER")
  f.label = f:CreateFontString(nil, "OVERLAY"); f.label:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE"); f.label:SetPoint("TOP", f, "BOTTOM", 0, -2)
  f:EnableMouse(true); f:SetMovable(true); f:RegisterForDrag("LeftButton"); f:SetClampedToScreen(true)
  f:SetScript("OnDragStart", function(self) if IsShiftKeyDown() then self:StartMoving() end end)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    P().look.nextAt = { math.floor((self:GetLeft() or 0) + 0.5), math.floor((self:GetTop() or 0) + 0.5) }
  end)
  f:SetScript("OnUpdate", function(self, el)
    self.t = (self.t or 0) + el
    local look = P().look
    local a = (self.power or 0.9) * animAlpha(look.nextAnim or look.anim or "pulse", self.t, look.speed or 7)
    self.glow:SetAlpha(a); self.border:SetAlpha(math.min(1, a + 0.2))
    if self.star:IsShown() then self.star:SetRotation(self.t * (look.spinSpeed or 1.6)); self.star:SetAlpha(a) end
    -- pop / bounce when the spell changes
    local base = look.nextSize or 52
    if self.popT then
      local p = (GetTime() - self.popT) / 0.25
      if p >= 1 then self.popT = nil; self:SetSize(base, base)
      else local k = 1 + 0.35 * math.sin(p * math.pi); self:SetSize(base * k, base * k) end
    end
  end)
  UI:Tip(f, "Rotational", "The spell to press next. Shift-drag to move it.")
  nextIcon = f
  return f
end
local function styleNextIcon(f, look, c, power)
  local size = look.nextSize or 52
  if not f.popT then f:SetSize(size, size) end
  local gs = math.max(1, math.min(5, look.nextGlow or 3))
  local GF = { 1.25, 1.45, 1.7, 2.0, 2.4 }
  local rd = math.max(0, math.min(5, look.nextRound or 2))
  if f.gs ~= gs or f.rd ~= rd then
    f.gs, f.rd = gs, rd
    f.glow:SetTexture("Interface\\AddOns\\CommandCenter\\Media\\UI\\halo_" .. rd .. "_" .. gs)
    f.border:SetTexture("Interface\\AddOns\\CommandCenter\\Media\\UI\\rring" .. rd)
    if f.mask then pcall(f.mask.SetTexture, f.mask, "Interface\\AddOns\\CommandCenter\\Media\\UI\\rmask" .. rd, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE") end
  end
  f.glow:SetSize(size * GF[gs], size * GF[gs])
  local style = look.nextStyle or look.style or "both"
  f.glow:SetShown(style ~= "border"); f.border:SetShown(style ~= "glow")
  f.star:SetShown(look.spin and true or false); f.star:SetSize(size * 2.2, size * 2.2)
  f.glow:SetVertexColor(c[1], c[2], c[3]); f.border:SetVertexColor(c[1], c[2], c[3]); f.star:SetVertexColor(c[1], c[2], c[3])
  f.power = power
  f.label:SetShown(look.nextLabel ~= false)
  f:SetAlpha(look.nextAlpha or 1)
end

---------------------------------------------------------------------------
-- The decision
---------------------------------------------------------------------------
local lastPick
local function ready(id)
  if not id or not known(id) then return false end
  cacheBase(id)
  -- a proc reset it: ready, whatever the cooldown reading says, until you use it
  if resetReady[id] then return usable(id) end
  return cooldownLeft(id) <= 0.25 and usable(id)
end
local function hostileTarget()
  return UnitExists and UnitExists("target") and UnitCanAttack and UnitCanAttack("player", "target") and not (UnitIsDead and UnitIsDead("target"))
end

-- can we see your buffs during this fight? (the game may hide them)
local auraSeenInCombat = false
local buffAtStart = {}
local buffUpOOC = {}          -- buff spellID -> was it up the last time we looked out of combat
S:On("PLAYER_REGEN_DISABLED", function()
  auraSeenInCombat = false
  wipe(buffAtStart)
  for k, v in pairs(buffUpOOC) do buffAtStart[k] = v end
end)
-- is this buff missing right now? (true / false)
local function buffMissing(b)
  if b.kind == "main" then return not hasEnchant("main") end
  if b.kind == "off" then return not hasEnchant("off") end
  local a = myAura(b.aura or b.spell)
  if not combat() then buffUpOOC[b.spell] = a ~= nil end
  if a then if combat() then auraSeenInCombat = true end return false end
  if not combat() or auraSeenInCombat then return true end
  -- can we see your other buffs right now? then this one really is gone
  local visible = false
  pcall(function()
    local any = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex and C_UnitAuras.GetAuraDataByIndex("player", 1, "HELPFUL")
    if any and any.spellId ~= nil and not secret(any.spellId) then visible = true end
  end)
  if visible then auraSeenInCombat = true; return true end
  -- buffs hidden this fight: missing unless it was up when the fight started or you just put it up
  local cast = buffCast[b.spell]
  if cast and now() - cast < (tonumber(b.lasts) or 600) then return false end
  return not buffAtStart[b.spell]
end
S.RotBuffMissing = buffMissing

-- your health in percent, or nil when the game won't say
local function healthPct()
  local ok, h, m = pcall(function() return UnitHealth("player"), UnitHealthMax("player") end)
  if ok and h ~= nil and m ~= nil and not secret(h) and not secret(m) and m > 0 then return h / m * 100 end
  if UnitHealthPercent then
    local ok2, pct = pcall(UnitHealthPercent, "player")
    if ok2 and pct ~= nil and not secret(pct) then return pct <= 1 and pct * 100 or pct end
  end
  return nil
end
S.RotHealthPct = healthPct
local lowWarned = false
local lowHealth
-- the spells to cast in order when health is low (older setups had one spell)
local function lowSeq(l)
  if type(l.seq) ~= "table" then l.seq = l.spell and { l.spell } or {} end
  l.spell = l.seq[1]                              -- (the pop-up names the first one)
  return l.seq
end
S.RotLowSeq = lowSeq
local lowQueue, lowQueueAt, lowWasLow = nil, 0, false
-- what the low-health sequence wants pressed now (nil when there's nothing left)
local function lowHealthPick(p)
  local l = p.lowhp
  local low = l and l.on and lowHealth(p) or false
  if low and not lowWasLow then
    -- just dropped low: start the sequence from the top
    lowQueue = {}
    for _, id in ipairs(lowSeq(l)) do lowQueue[#lowQueue + 1] = id end
    lowQueueAt = now()
    if #lowQueue > 0 then logEvent("LOW-HP", #lowQueue .. " spell(s) queued") end
  end
  lowWasLow = low
  if lowQueue and (#lowQueue == 0 or now() - lowQueueAt > 25) then
    lowQueue = nil
    -- still low after the whole sequence: go again if you asked for that
    if low and l.repeatSeq and #lowSeq(l) > 0 then lowWasLow = false end
  end
  if not lowQueue then return nil end
  -- the first spell in the queue that can be cast now (one on cooldown waits its turn)
  for _, id in ipairs(lowQueue) do if ready(id) then return id end end
end
-- you cast a spell: tick it off the queue
local function lowQueueCast(same)
  if not lowQueue then return end
  for i, id in ipairs(lowQueue) do if same(id) then table.remove(lowQueue, i); lowQueueAt = now(); return end end
end
S.RotLowQueue = function() return lowQueue end
lowHealth = function(p)
  local l = p.lowhp
  if not l or not l.on then return false end
  local pct = healthPct()
  local limit = tonumber(l.pct) or 35
  if not pct then
    -- health hidden in fights: the game's own low-health glow (red screen edges) still shows
    local f = _G.LowHealthFrame or _G.PlayerFrameLowHealthOverlay
    local ok, shown = pcall(function() return f and f:IsVisible() end)
    if ok and shown and not secret(shown) then pct = limit else
      lowWarned = false                             -- the glow went away: warn again next time
      return false
    end
  end
  if pct <= limit then
    if not lowWarned then
      lowWarned = true
      if l.popup ~= false then
        showPopup({ text = (l.text and l.text ~= "") and l.text or ("LOW HEALTH" .. (l.spell and ("  |cffffffff> " .. spellName(l.spell) .. "|r") or "")),
          icon = l.spell and spellIcon(l.spell) or "Interface\\Icons\\Spell_Holy_SealOfSacrifice", color = l.color or "red", anim = l.anim or "shake",
          screen = l.screen or "pulse", size = l.size or 28, sound = l.sound })
      end
    end
    return true
  end
  if pct > limit + 8 then lowWarned = false end      -- healed up again: warn next time
  return false
end

-- returns strong = spellID to press now (or nil), soft = { spellIDs } buffs to put up
function S:RotDecide()
  local p = P()
  local soft = {}
  if not p.enabled then return nil, soft end
  local fighting = combat()

  -- (buffs to keep up are BuffWatcher's job now)

  -- procs: pop-up when they start, and they can move a spell to the front
  local procPick
  S:RotWatchResets()
  for i, pr in ipairs(p.procs) do
   if eventOnly(pr) then
    local on = eventGlowUntil[pr] ~= nil and now() < eventGlowUntil[pr]
    if not on and eventGlowUntil[pr] then eventGlowUntil[pr] = nil; if pr.use then resetReady[pr.use] = nil end end
    procOn[i] = on or nil
    if on and pr.use and not procPick and ready(pr.use) then procPick = pr.use end
   else
    local raw = procActive(pr)
    if raw and not rawOn[i] then risingAt[i] = now(); matched[i] = nil; logEvent("PROC", spellName(pr.aura or pr.use), pr.trigger or "any") end
    if not raw then
      if rawOn[i] and pr.reset and pr.use and matched[i] then resetReady[pr.use] = nil end
      risingAt[i], matched[i] = nil, nil
    end
    rawOn[i] = raw or nil
    -- the dodge / parry always arrives before the proc: decide the moment it appears
    if raw and matched[i] == nil then
      local siblings = {}
      for j, o in ipairs(p.procs) do if j ~= i and sameProc(o, pr) and TRIGGER_KINDS[o.trigger or ""] then siblings[#siblings + 1] = o end end
      matched[i] = triggerMatches(pr, risingAt[i], siblings)
      logEvent("PROC-MATCH", spellName(pr.aura or pr.use), pr.trigger or "any", matched[i] and "yes" or "no")
      if matched[i] then
        if pr.popup ~= false then showPopup(procPopupOpts(pr)) end
        if pr.reset and pr.use then
          resetAt[pr.use] = now(); resetReady[pr.use] = true; sharedUntil[pr.use] = nil
          local start = readCooldown(pr.use)
          logEvent("RESET", spellName(pr.use), start and ("cd shown " .. string.format("%.1f", cooldownLeft(pr.use))) or "cd hidden")
        end
      end
    end
    local on = raw and matched[i] == true
    procOn[i] = on or nil
    if on and pr.use and not procPick and ready(pr.use) then procPick = pr.use end
   end
  end

  if not fighting then
    local lp = lowHealthPick(p); if lp then return lp, soft end
    local cl = S:RotCleansePick(); if cl then return cl, soft end
    -- the opener: what to start the fight with
    local rules = p.opener.rules or {}
    if hostileTarget() and (p.opener.near or p.opener.far or #rules > 0) then
      local check = p.opener.check or p.opener.near
      local r = check and inRange(check, "target")
      if r == nil and CheckInteractDistance then local ok, v = pcall(CheckInteractDistance, "target", 3); if ok and not secret(v) then r = v and true or false end end
      -- "if this buff is up, open with that": first one that fits wins
      for _, rule in ipairs(rules) do
        local rangeOk = (rule.range or "any") == "any" or (rule.range == "near" and r == true) or (rule.range == "far" and r == false)
        if rule.buff and rule.spell and rangeOk and known(rule.spell) and myAura(rule.buff) and ready(rule.spell) then return rule.spell, soft end
      end
      local pick = (r and p.opener.near) or (not r and p.opener.far) or p.opener.near or p.opener.far
      if pick and known(pick) then return pick, soft end
    end
    return procPick, soft
  end

  -- low health: your emergency spell before anything else
  local lp = lowHealthPick(p); if lp then return lp, soft end
  -- BuffWatcher buffs marked "keep up in combat" (Lightning Shield): top priority when they drop
  if S.BuffWatchCombatPicks then
    for _, id in ipairs(S.BuffWatchCombatPicks()) do if ready(id) then return id, soft end end
  end
  if p.purge.on and p.purge.spell and ready(p.purge.spell) and targetHasStealable() then return p.purge.spell, soft end
  local cl = S:RotCleansePick(); if cl then return cl, soft end
  if procPick then return procPick, soft end
  local pick = S:RotNextAbility()
  return pick, soft
end

-- seconds left on your totem from this spell (0 = not down)
totemLeft = function(id, lasts)
  local nm = spellName(id)
  local readable, left = false, 0
  if GetTotemInfo then
    for slot = 1, 4 do
      pcall(function()
        local have, name, start, dur = GetTotemInfo(slot)
        if name ~= nil and not secret(name) then
          readable = true
          if have and name ~= "" and (name == nm or name:find(nm, 1, true) or nm:find(name, 1, true)) then
            if start ~= nil and dur ~= nil and not secret(start) and not secret(dur) then left = math.max(left, start + dur - now()) else left = 99 end
          end
        end
      end)
    end
  end
  if readable then return left end
  -- the game won't say: from when you dropped it
  local t = totemCast[id] or lastCast[id]
  if t then return math.max(0, t + (tonumber(lasts) or 60) - now()) end
  return 0
end

-- a cleanse spell to press now (the one for the debuff type that's there first)
function S:RotCleansePick()
  local p = P()
  if not p.cleanseOn or #p.cleanses == 0 then return nil end
  local types = groupDebuffTypes()
  if not types then return nil end
  for _, c in ipairs(p.cleanses) do
    local t = c.type or "any"
    if t ~= "any" and types[t] and c.spell and ready(c.spell) then return c.spell end
  end
  local onlyHidden = types.unknown and true or false
  for k in pairs(types) do if k ~= "unknown" then onlyHidden = false end end
  for _, c in ipairs(p.cleanses) do
    local t = c.type or "any"
    if c.spell and ready(c.spell) and (t == "any" or onlyHidden) then return c.spell end
  end
end

-- the rotation: primaries top to bottom - the first one that's ready, in range and
-- (for a DoT) missing from the target wins. Fillers only when no primary can go.
function S:RotNextAbility()
  local p = P()
  local function ok(e)
    if not e.id or not ready(e.id) then return false end
    if inRange(e.id, "target") == false then return false end
    if e.dot and targetDebuffLeft(e.id, e.lasts) > (tonumber(e.refresh) or 1.5) then return false end
    if (e.totem or (e.totem == nil and spellName(e.id):find("Totem"))) and totemLeft(e.id, e.lasts) > (tonumber(e.refresh) or 1.5) then return false end
    return true
  end
  for _, e in ipairs(p.prio) do if not e.filler and ok(e) then return e.id end end
  for _, e in ipairs(p.prio) do if e.filler and ok(e) then return e.id end end
end

local function apply()
  for _, g in pairs(glows) do g:Hide() end
  if not S.RotationalOn() then if nextIcon then nextIcon:Hide() end return end
  local p = P()
  local strong, soft = S:RotDecide()
  lastPick = strong
  for _, id in ipairs(soft) do for _, b in ipairs(buttonsFor(id)) do setGlow(b, "soft") end end
  if strong then for _, b in ipairs(buttonsFor(strong)) do setGlow(b, "strong") end end
  if p.enabled and p.look.next ~= false and (strong or soft[1]) then
    local f = getNextIcon()
    local id = strong or soft[1]
    if f.spell ~= id and p.look.pop ~= false then f.popT = GetTime() end
    f.spell = id
    f.icon:SetTexture(spellIcon(id))
    local c = strong and lookColor(p.look, "color", "gold") or lookColor(p.look, "softColor", "blue")
    styleNextIcon(f, p.look, c, strong and (p.look.strong or 0.9) or (p.look.soft or 0.45))
    f.label:SetText(spellName(id))
    f:Show()
  elseif nextIcon then nextIcon:Hide() end
end
S.RotApply = apply

local driver = CreateFrame("Frame")
local acc_off   -- (switched off: glows already cleared)
local cacheTick
local acc = 0
driver:SetScript("OnUpdate", function(_, el)
  acc = acc + el
  if acc < 0.05 then return end
  acc = 0
  if not S.db then return end
  if not S.RotationalOn() then
    if not acc_off then for _, g in pairs(glows) do g:Hide() end; if nextIcon then nextIcon:Hide() end; acc_off = true end
    return
  end
  acc_off = nil
  local p = P()
  if not p.enabled or (#p.prio == 0 and #p.buffs == 0 and not p.opener.near and not p.opener.far and not (p.opener.rules and #p.opener.rules > 0) and #p.procs == 0 and #p.cleanses == 0 and not p.purge.spell and not (p.lowhp and p.lowhp.on)) then
    for _, g in pairs(glows) do g:Hide() end
    if nextIcon then nextIcon:Hide() end
    return
  end
  -- read cooldowns straight away, then every 5 seconds out of combat
  if cacheTick == nil or cacheTick >= 100 then cacheTick = 0; pcall(S.RotCacheCooldowns, S) end
  cacheTick = cacheTick + 1
  local ok, err = pcall(apply)
  if not ok then S.report(err) end
end)

-- react the moment cooldowns change (a reset) - same quick path as buffs below
S:On("SPELL_UPDATE_COOLDOWN", function()
  if not S.db then return end
  local p = P()
  if not p.enabled or #p.procs == 0 then return end
  pcall(apply)
end)
-- react the moment your buffs change (procs), not on the next check
local lastAuraApply = 0
-- recording: compare your whole buff list with last time and note what's new / gone
local spyBuffs = {}
local castBuffs = {}           -- your buffs last time (for "spell reported" procs)
function S:RotSpyScanBuffs(reset)
  local seenNow = {}
  for i = 1, 60 do
    local name, id
    local ok = pcall(function()
      local a = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex and C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
      if a then name, id = a.name, a.spellId; if name == nil then name = "?" end
      elseif UnitBuff then name, _, _, _, _, _, _, _, _, id = UnitBuff("player", i) end
    end)
    if not ok then if not reset then logEvent("BUFFS", "unreadable at " .. i) end break end
    if not name then break end
    local key = (secret(name) and "SECRET" or tostring(name)) .. "#" .. (secret(id) and "?" or tostring(id))
    seenNow[key] = true
    if not reset and not spyBuffs[key] then logEvent("BUFF-ON", key) end
  end
  if not reset then for k in pairs(spyBuffs) do if not seenNow[k] then logEvent("BUFF-OFF", k) end end end
  spyBuffs = seenNow
end
S:On("UNIT_AURA", function(_, unit, info)
  if unit ~= "player" or not S.db then return end
  if spyUntil and now() < spyUntil then
    pcall(S.RotSpyScanBuffs, S)
    if readable(info) and not readable(info.addedAuras) then
      local keys = {}
      for k, v in pairs(info) do keys[#keys + 1] = tostring(k) .. "=" .. (secret(v) and "SECRET" or (readable(v) and ("[" .. #v .. "]") or tostring(v))) end
      logEvent("UNIT_AURA-INFO", table.concat(keys, " "))
    end
  end
  -- recording: every buff that appears on you (name / ID when the game shows them)
  if spyUntil and now() < spyUntil then
    local n = (readable(info) and readable(info.addedAuras)) and #info.addedAuras or -1
    if n ~= 0 then logEvent("UNIT_AURA", type(info), "added=" .. n) end
  end
  if spyUntil and now() < spyUntil and readable(info) and readable(info.addedAuras) then
    for _, a in ipairs(info.addedAuras) do
      local ok, err = pcall(function()
        local nm, id = a.name, a.spellId
        logEvent("NEW-BUFF", secret(nm) and "name=SECRET" or tostring(nm), secret(id) and "id=SECRET" or ("id=" .. tostring(id)),
          (not secret(a.isHelpful) and a.isHelpful == false) and "debuff" or "")
      end)
      if not ok then logEvent("NEW-BUFF", "unreadable", tostring(err):sub(1, 60)) end
    end
  end
  -- "When the game reports this spell" procs: any buff that's new since last time counts
  local p0 = P()
  local wantCast = false
  for _, pr in ipairs(p0.procs) do if pr.trigger == "cast" then wantCast = true end end
  if wantCast then
    pcall(function()
      local nowSet = {}
      for i = 1, 60 do
        local a = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex and C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
        if not a then break end
        local nm, id = a.name, a.spellId
        local key = (not secret(id) and id) or (not secret(nm) and nm) or nil
        if key then
          nowSet[key] = true
          if not castBuffs[key] then
            if type(key) == "number" then S:RotSpellReported(key) else S:RotNameReported(key) end
          end
        end
      end
      castBuffs = nowSet
    end)
  end
  -- buffs that pop for an instant (weapon procs): their spell counts as "reported"
  if readable(info) and readable(info.addedAuras) then
    for _, a in ipairs(info.addedAuras) do
      pcall(function() local id = a.spellId; if id ~= nil and not secret(id) then S:RotSpellReported(id) end end)
    end
  end
  local t = now()
  if t - lastAuraApply < 0.03 then return end
  lastAuraApply = t
  local p = P()
  if not p.enabled or #p.procs == 0 then return end
  local ok, err = pcall(apply)
  if not ok then S.report(err) end
end)

-- your own casts drive the worked-out cooldowns
-- your casts: the spell ID, or - when the game hides it - the one inside the cast
-- code ("Cast-3-...-<spellID>-..."); other ranks of a spell count by name
local function castSpellID(guid, id)
  if id ~= nil and not secret(id) then return id end
  if guid ~= nil and not secret(guid) and type(guid) == "string" then
    local sid = guid:match("^Cast%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
    if sid then return tonumber(sid) end
  end
end
-- which shared cooldown a priority entry belongs to ("shock" for every shaman shock)
local function cdGroup(e)
  if e.group and e.group ~= "" then return e.group end
  if e.group == "" then return nil end
  local nm = spellName(e.id)
  if select(2, UnitClass("player")) == "SHAMAN" and nm:find(" Shock$") then return "shock" end
end
S.RotCdGroup = cdGroup
local function noteCast(id)
  local t = now()
  lastCast[id] = t
  local nm = spellName(id)
  local p = P()
  local function same(x) return x == id or (x and spellName(x) == nm) end
  for k in pairs(resetReady) do if same(k) then resetReady[k] = nil end end
  for k in pairs(resetSeen) do if same(k) then resetSeen[k] = nil end end
  for pr in pairs(eventGlowUntil) do if pr.use and same(pr.use) then eventGlowUntil[pr] = nil end end
  local castGroup, castCd
  for _, e in ipairs(p.prio) do
    if same(e.id) then
      lastCast[e.id] = t
      if e.dot then dotCast[e.id] = t end
      castGroup = castGroup or cdGroup(e)
      castCd = castCd or cdOverride[e.id] or baseCD[e.id]
      if e.totem then totemCast[e.id] = t end
    end
  end
  -- everything sharing its cooldown goes on cooldown too (Flame Shock -> Earth Shock)
  if castGroup and castCd and castCd > 1.6 then
    for _, e in ipairs(p.prio) do
      if not same(e.id) and cdGroup(e) == castGroup then sharedUntil[e.id] = math.max(sharedUntil[e.id] or 0, t + castCd) end
    end
  end
  for _, b in ipairs(p.buffs) do if same(b.spell) then lastCast[b.spell] = t; buffCast[b.spell] = t end end
  if S.BuffWatchCast then pcall(S.BuffWatchCast, id, nm) end
  for _, c in ipairs(p.cleanses) do if same(c.spell) then lastCast[c.spell] = t end end
  if p.purge.spell and same(p.purge.spell) then lastCast[p.purge.spell] = t end
  if p.lowhp then
    for _, id in ipairs(lowSeq(p.lowhp)) do if same(id) then lastCast[id] = t end end
    lowQueueCast(same)
  end
end
local castSeen = 0
S:On("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, guid, id)
  if unit ~= "player" then return end
  S.__lastPlayerCast = now()
  local sid = castSpellID(guid, id)
  -- log the first few casts of each fight so problems can be seen
  local spying = spyUntil and now() < spyUntil
  if castSeen < 6 or spying then castSeen = castSeen + 1; logEvent("CAST", secret(id) and "id=SECRET" or ("id=" .. tostring(id)), secret(guid) and "guid=SECRET" or "guid ok", sid and spellName(sid) or "?") end
  if sid then noteCast(sid); S:RotSpellReported(sid) end
end)
S:On("PLAYER_REGEN_DISABLED", function()
  castSeen = 0
  -- what can be read as the fight starts
  local p = P()
  for i = 1, math.min(3, #p.prio) do
    local e = p.prio[i]
    if e and e.id then
      local start = readCooldown(e.id)
      logEvent("CD", spellName(e.id), start and "readable" or "hidden", "base=" .. tostring(cdOverride[e.id] or baseCD[e.id]))
    end
  end
  local ok, hp = pcall(UnitHealth, "player")
  logEvent("HP", ok and (secret(hp) and "SECRET" or tostring(hp)) or "error")
end)
-- Switching specs fires ACTIONBAR_SLOT_CHANGED for every slot (~120 times at once): each one used to
-- start its own full scan of every frame in the game half a second later = a 7 s freeze. Now all of
-- them share one scan.
local scanPending
local timedScan = S.PerfWrap and S.PerfWrap("Rotational  scan action buttons", scanButtons) or scanButtons
local function scanSoon()
  wipe(bfCache)                    -- (a bar / spell changed: which button holds what is looked at again)
  if scanPending then return end
  scanPending = true
  C_Timer.After(0.5, function() scanPending = nil; timedScan() end)
end
for _, ev in ipairs({ "PLAYER_ENTERING_WORLD", "ACTIONBAR_SLOT_CHANGED", "UPDATE_BONUS_ACTIONBAR", "ACTIONBAR_PAGE_CHANGED", "PLAYER_REGEN_ENABLED", "SPELLS_CHANGED" }) do
  S:On(ev, scanSoon)
end
-- read base cooldowns while it's allowed (out of combat), and your typed overrides
-- names of buffs you've had (passives like Maelstrom Weapon can't be looked up by
-- name, only by ID) - learned out of combat, when the game shows them
function S:RotLearnAuraNames()
  if combat() or not S.db then return end
  local g = G()
  g.rotAuraNames = type(g.rotAuraNames) == "table" and g.rotAuraNames or {}
  for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
    pcall(function()
      for i = 1, 40 do
        local a = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex and C_UnitAuras.GetAuraDataByIndex("player", i, filter)
        if not a then break end
        local nm, id = a.name, a.spellId
        if nm ~= nil and id ~= nil and not secret(nm) and not secret(id) then g.rotAuraNames[nm:lower()] = id end
      end
    end)
  end
end
function S:RotCacheCooldowns()
  if combat() or not S.db then return end
  pcall(S.RotLearnAuraNames, S)
  local p = P()
  wipe(cdOverride)
  for _, e in ipairs(p.prio) do
    if e.id then
      if baseCD[e.id] == nil then cacheBase(e.id) end
      if tonumber(e.cd) then cdOverride[e.id] = tonumber(e.cd) end
    end
  end
  for _, c in ipairs(p.cleanses) do if c.spell and baseCD[c.spell] == nil then cacheBase(c.spell) end end
  if p.purge.spell and baseCD[p.purge.spell] == nil then cacheBase(p.purge.spell) end
  if p.lowhp then for _, id in ipairs(lowSeq(p.lowhp)) do if baseCD[id] == nil then cacheBase(id) end end end
end
S:On("PLAYER_REGEN_ENABLED", function() S:RotCacheCooldowns() end)
local cdPending   -- (SPELLS_CHANGED comes in bursts too: one cooldown read for all of them)
S:On("SPELLS_CHANGED", function()
  wipe(baseCD)
  if cdPending then return end
  cdPending = true
  C_Timer.After(1, function() cdPending = nil; S:RotCacheCooldowns() end)
end)
S:On("PLAYER_ENTERING_WORLD", function() C_Timer.After(2, function() S:RotCacheCooldowns() end) end)

---------------------------------------------------------------------------
-- Ready-made example (enhancement shaman)
---------------------------------------------------------------------------
local function idOf(name) local id = spellInfo(name); return id end
function S:RotLoadEnhance()
  local p = P()
  p.prio = {}
  for _, e in ipairs({ { "Stormstrike" }, { "Flame Shock", dot = true, lasts = 18 }, { "Earth Shock" }, { "Lava Lash" },
      { "Fire Nova", filler = true }, { "Lightning Bolt", filler = true } }) do
    local id = idOf(e[1])
    if id then p.prio[#p.prio + 1] = { id = id, dot = e.dot, lasts = e.lasts, filler = e.filler } end
  end
  p.opener = { far = idOf("Lightning Bolt"), near = idOf("Stormstrike"), check = idOf("Stormstrike") }
  p.procs = {}
  if idOf("Maelstrom Weapon") then p.procs[#p.procs + 1] = { aura = idOf("Maelstrom Weapon"), stacks = 5, use = idOf("Lightning Bolt"), popup = true, label = "Maelstrom Weapon" } end
  if idOf("Flurry") then p.procs[#p.procs + 1] = { aura = idOf("Flurry"), popup = true, label = "Flurry" } end
  p.buffs = {}
  -- the buffs go to BuffWatcher
  if S.BuffWatchAdd then
    if idOf("Windfury Weapon") then S.BuffWatchAdd(idOf("Windfury Weapon"), "main") end
    if idOf("Flametongue Weapon") then S.BuffWatchAdd(idOf("Flametongue Weapon"), "off") end
    if idOf("Lightning Shield") then S.BuffWatchAdd(idOf("Lightning Shield"), "aura", true) end
  end
  p.purge = { on = idOf("Purge") ~= nil, spell = idOf("Purge") }
  p.cleanses = {}
  if idOf("Cleanse Spirit") then p.cleanses[#p.cleanses + 1] = { spell = idOf("Cleanse Spirit"), type = "any" } end
  if idOf("Cure Toxins") then p.cleanses[#p.cleanses + 1] = { spell = idOf("Cure Toxins"), type = "Poison" } end
  if idOf("Cure Poison") then p.cleanses[#p.cleanses + 1] = { spell = idOf("Cure Poison"), type = "Poison" } end
  if idOf("Cure Disease") then p.cleanses[#p.cleanses + 1] = { spell = idOf("Cure Disease"), type = "Disease" } end
  p.cleanseOn = #p.cleanses > 0
  S:RefreshRotational()
  S:Print("Enhancement shaman example loaded - change anything you like.")
end

---------------------------------------------------------------------------
-- The panel
---------------------------------------------------------------------------
local win
local panes = {}
local W, H = 540, 594

-- "type a spell or drag one here" box; calls fn(spellID)
local function spellBox(parent, w, placeholder, fn)
  local e = UI:Edit(parent, w, 24, placeholder)
  local function take(text)
    local id = spellInfo(text)
    if not id and tonumber(text) then id = spellInfo(tonumber(text)) or tonumber(text) end     -- a spell ID
    if not id and text and text ~= "" then
      pcall(S.RotLearnAuraNames, S)
      local known = G().rotAuraNames
      id = type(known) == "table" and known[text:lower()] or nil                              -- a buff you've had
    end
    if not id then
      UI:Alert("Couldn't find \"" .. tostring(text) .. "\".\n\nSpells: check the spelling, or drag it in from your spellbook.\nBuffs and passives (e.g. Maelstrom Weapon): get the buff on you once out of combat and try again, or type its spell ID.")
      return
    end
    fn(id); e:SetText(""); e:ClearFocus()
  end
  e:SetScript("OnEnterPressed", function(self) take(S.Trim and S.Trim(self:GetText() or "") or self:GetText()) end)
  local function fromCursor()
    if not GetCursorInfo then return end
    local kind, a, b, c = GetCursorInfo()
    local id
    if kind == "spell" then id = c or (C_SpellBook and C_SpellBook.GetSpellBookItemInfo and select(2, pcall(function() return C_SpellBook.GetSpellBookItemInfo(a, b).spellID end))) end
    if kind == "action" and a then id = slotSpell(a) end
    if type(id) == "number" then ClearCursor(); fn(id); e:SetText("") end
  end
  e:SetScript("OnReceiveDrag", fromCursor)
  e:HookScript("OnMouseDown", fromCursor)
  return e
end

local function spellCell(id) return "|T" .. spellIcon(id) .. ":16:16:0:0:64:64:5:59:5:59|t  " .. spellName(id) end

-- a list with up / down / remove for the selected row
local function listControls(parent, tbl, list, y, onChange)
  local function sel() return tbl.selected end
  local function idx() local s = sel(); for i, v in ipairs(list()) do if v == (s and s.ref) then return i end end end
  local up = UI:Button(parent, "Move up", 80, 22, function() local i = idx(); local l = list(); if i and i > 1 then l[i], l[i - 1] = l[i - 1], l[i]; onChange() end end)
  up:SetPoint("TOPLEFT", 14, y)
  local down = UI:Button(parent, "Move down", 90, 22, function() local i = idx(); local l = list(); if i and i < #l then l[i], l[i + 1] = l[i + 1], l[i]; onChange() end end)
  down:SetPoint("LEFT", up, "RIGHT", 4, 0)
  local rm = UI:Button(parent, "|cffff7777Remove|r", 80, 22, function() local i = idx(); if i then table.remove(list(), i); tbl.selected = nil; onChange() end end)
  rm:SetPoint("LEFT", down, "RIGHT", 4, 0)
  return up, down, rm
end

-- shared with BuffWatcher
S.RotKit = {
  spellInfo = spellInfo, spellName = spellName, spellIcon = spellIcon, known = known, myAura = myAura,
  hasEnchant = hasEnchant, buttonsFor = buttonsFor, scanButtons = function() scanButtons() end, combat = combat,
  secret = secret, spellBox = spellBox, spellCell = spellCell, listControls = listControls, slotSpell = slotSpell,
}
local function buildPriority(p)
  local pane = panes[1]
  local hint = UI:Text(pane, "|cffaaaaaaIn a fight the first main ability that's ready, in range and (for a DoT) missing from the target glows. Fillers only when no main ability can go.|r", "small")
  hint:SetPoint("TOPLEFT", 14, -4); hint:SetWidth(W - 28); hint:SetJustifyH("LEFT")
  pane.add = spellBox(pane, 300, "Type a spell name, or drag one here", function(id)
    table.insert(P().prio, { id = id }); cacheBase(id); S:RefreshRotational()
  end)
  pane.add:SetPoint("TOPLEFT", 14, -30)
  local addBtn = UI:Button(pane, "Add", 60, 24, function() pane.add:GetScript("OnEnterPressed")(pane.add) end)
  addBtn:SetPoint("LEFT", pane.add, "RIGHT", 6, 0)
  if select(2, UnitClass("player")) == "SHAMAN" then
    local ex = UI:Button(pane, "Enhancement example", 150, 24, function()
      UI:Confirm("Replace your whole rotation with the enhancement shaman example?", function() S:RotLoadEnhance() end, "Load")
    end, "Fills every tab with a ready-made enhancement shaman setup.")
    ex:SetPoint("LEFT", addBtn, "RIGHT", 6, 0)
  end
  local function selected() return pane.tbl.selected and pane.tbl.selected.ref end
  pane.tbl = UI:Table(pane, W - 28, 190, {
    { title = "#", w = 30, get = function(r) return r.pos end },
    { title = "Ability", w = 200, get = function(r) return spellCell(r.ref.id) end, tip = "Highest priority at the top." },
    { title = "Role", w = 70, get = function(r) return r.ref.filler and "|cff88aaffFiller|r" or "|cffffd100Main|r" end,
      tip = "Main abilities go first, top to bottom. Fillers are only used when every main ability is on cooldown or can't be used." },
    { title = "DoT", w = 70, get = function(r)
        if not r.ref.dot then return "|cff555555-|r" end
        local d = tonumber(r.ref.lasts) or dotLearned[r.ref.id]
        return "|cff55ff55keep up|r" .. (d and (" " .. math.floor(d) .. "s") or "")
      end, tip = "Only used when your debuff from it is missing from the target (or about to run out), to keep it up all the time." },
    { title = "Cooldown", w = 70, get = function(r)
        local b = tonumber(r.ref.cd) or baseCD[r.ref.id]
        local g = cdGroup(r.ref)
        return (b and b > 1.6 and (b .. "s" .. (r.ref.cd and "*" or "")) or "|cff888888-|r") .. (g and (" |cff88aaff" .. g .. "|r") or "")
      end,
      tip = "How long until it can be used again (read from the game when you're out of combat)." },
    { title = "Known", w = 50, get = function(r) return known(r.ref.id) and "|cff55ff55yes|r" or "|cffff5555no|r" end },
  }, { selectable = true, emptyText = "Add your abilities above, most important first.",
       onClick = function() S:RotLoadSelected() end })
  pane.tbl:SetPoint("TOPLEFT", 14, -62)
  listControls(pane, pane.tbl, function() return P().prio end, -258, function() S:RefreshRotational() end)
  -- options for the selected ability
  local y = -286
  pane.selName = UI:Text(pane, "|cff888888Click an ability above to change its options.|r", "small"); pane.selName:SetPoint("TOPLEFT", 16, y)
  y = y - 22
  pane.filler = UI:Check(pane, "Filler - only when every main ability is on cooldown", false, function(v)
    local e = selected(); if e then e.filler = v or nil; S:RefreshRotational() end
  end)
  pane.filler:SetPoint("TOPLEFT", 14, y); y = y - 26
  pane.dot = UI:Check(pane, "Keep its debuff up on the target (use it when it's missing)", false, function(v)
    local e = selected(); if e then e.dot = v or nil; S:RefreshRotational() end
  end)
  pane.dot:SetPoint("TOPLEFT", 14, y); y = y - 28
  local ll = UI:Text(pane, "Debuff lasts (seconds)", "small"); ll:SetPoint("TOPLEFT", 40, y - 4)
  pane.lasts = UI:Edit(pane, 50, 22, "auto", nil, true); pane.lasts:SetPoint("TOPLEFT", 190, y)
  pane.lasts:SetScript("OnTextChanged", function(self, user)
    if not user then return end
    local e = selected(); if e then e.lasts = tonumber(self:GetText() or "") end
  end)
  UI:Tip(ll, "Debuff lasts", "Used when the game hides your debuffs on the target during a fight. Leave on 'auto' to learn it from the game.")
  local rl = UI:Text(pane, "Recast with (seconds) left", "small"); rl:SetPoint("TOPLEFT", 256, y - 4)
  pane.refresh = UI:Edit(pane, 50, 22, "1.5", nil, false); pane.refresh:SetPoint("TOPLEFT", 420, y)
  pane.refresh:SetScript("OnTextChanged", function(self, user)
    if not user then return end
    local e = selected(); if e then e.refresh = tonumber(self:GetText() or "") end
  end)
  y = y - 28
  local cl = UI:Text(pane, "Cooldown (seconds)", "small"); cl:SetPoint("TOPLEFT", 16, y - 4)
  pane.cd = UI:Edit(pane, 50, 22, "auto", nil, false); pane.cd:SetPoint("TOPLEFT", 190, y)
  pane.cd:SetScript("OnTextChanged", function(self, user)
    if not user then return end
    local e = selected(); if e then e.cd = tonumber(self:GetText() or ""); S:RotCacheCooldowns() end
  end)
  UI:Tip(cl, "Cooldown", "Only needed when the game hides cooldowns in fights and reads this spell's cooldown wrong. 'auto' = read from the game.")
  local cdNote = UI:Text(pane, "|cff888888auto = read from the game|r", "small"); cdNote:SetPoint("LEFT", pane.cd, "RIGHT", 8, 0)
  y = y - 26
  local gl = UI:Text(pane, "Shares cooldown with", "small"); gl:SetPoint("TOPLEFT", 16, y - 4)
  pane.group = UI:Edit(pane, 90, 22, "auto", nil, false); pane.group:SetPoint("TOPLEFT", 190, y)
  pane.group:SetScript("OnTextChanged", function(self, user)
    if not user then return end
    local e = selected(); if e then local v = S.Trim and S.Trim(self:GetText() or "") or self:GetText(); e.group = (v == "" and nil) or (v:lower() == "none" and "") or v:lower(); S:RefreshRotational() end
  end)
  UI:Tip(gl, "Shared cooldown", { "Abilities with the same word here share one cooldown - using one puts the others on cooldown too.",
    "Shaman shocks (Earth, Flame, Frost) are linked automatically as 'shock'. Type 'none' to unlink." })
  pane.totem = UI:Check(pane, "Totem: skip while it's down", false, function(v)
    local e = selected(); if e then e.totem = v and true or false; S:RefreshRotational() end
  end, "Only suggests it again once the totem is gone (spells with 'Totem' in the name do this automatically).")
  pane.totem:SetPoint("TOPLEFT", 290, y)
  pane.optFrames = { pane.filler, pane.dot, pane.lasts, pane.refresh, pane.cd, pane.group, pane.totem }
end

function S:RotLoadSelected()
  local pane = panes[1]
  local e = pane.tbl and pane.tbl.selected and pane.tbl.selected.ref
  if not e then pane.selName:SetText("|cff888888Click an ability above to change its options.|r") return end
  pane.selName:SetText("Options for " .. spellCell(e.id))
  pane.filler:SetChecked(e.filler and true or false)
  pane.dot:SetChecked(e.dot and true or false)
  pane.lasts:SetText(e.lasts and tostring(e.lasts) or "")
  pane.refresh:SetText(e.refresh and tostring(e.refresh) or "")
  pane.cd:SetText(e.cd and tostring(e.cd) or "")
  pane.group:SetText(e.group == "" and "none" or (e.group or ""))
  pane.totem:SetChecked(e.totem or (e.totem == nil and spellName(e.id):find("Totem") ~= nil) or false)
end

local function buildOpener()
  local pane = panes[2]
  local hint = UI:Text(pane, "|cffaaaaaaBefore a fight: with an enemy targeted, the right opener glows depending on how far away it is.|r", "small")
  hint:SetPoint("TOPLEFT", 14, -4); hint:SetWidth(W - 28); hint:SetJustifyH("LEFT")
  local rows = {
    { key = "far", label = "Out of range - start with", tip = "e.g. Lightning Bolt to pull from a distance" },
    { key = "near", label = "In range - start with", tip = "e.g. Stormstrike when you're already in melee" },
    { key = "check", label = "Range is checked with", tip = "The spell whose range decides near / far. Empty = the 'in range' spell." },
  }
  local y = -34
  pane.fields = {}
  for _, r in ipairs(rows) do
    local l = UI:Text(pane, r.label, "small"); l:SetPoint("TOPLEFT", 16, y - 5); l:SetWidth(170)
    local cur = UI:Text(pane, "", "normal"); cur:SetPoint("TOPLEFT", 190, y - 4); cur:SetWidth(170)
    local box = spellBox(pane, 150, "spell name / drag", function(id) P().opener[r.key] = id; S:RefreshRotational() end)
    box:SetPoint("TOPLEFT", 370, y)
    local clr = UI:Button(pane, "x", 22, 22, function() P().opener[r.key] = nil; S:RefreshRotational() end, "Clear")
    clr:SetPoint("LEFT", box, "RIGHT", 4, 0)
    UI:Tip(l, r.label, r.tip)
    pane.fields[r.key] = cur
    y = y - 36
  end
  -- if a buff is up, open with a particular spell (checked before the ones above)
  y = y - 6
  local h = UI:Header(pane, "If a buff is up, open with..."); h:SetPoint("TOPLEFT", 14, y); y = y - 24
  local hint2 = UI:Text(pane, "|cffaaaaaaChecked first, top to bottom. e.g. Maelstrom Weapon up > Lightning Bolt.|r", "small")
  hint2:SetPoint("TOPLEFT", 16, y); hint2:SetWidth(W - 32); hint2:SetJustifyH("LEFT"); y = y - 20
  pane.newRule = {}
  local bl = UI:Text(pane, "Buff", "small"); bl:SetPoint("TOPLEFT", 16, y - 5)
  pane.ruleBuff = spellBox(pane, 150, "buff name / drag", function(id) pane.newRule.buff = id; pane.ruleBuffCur:SetText(spellCell(id)) end)
  pane.ruleBuff:SetPoint("TOPLEFT", 52, y)
  pane.ruleBuffCur = UI:Text(pane, "", "small"); pane.ruleBuffCur:SetPoint("LEFT", pane.ruleBuff, "RIGHT", 6, 0); pane.ruleBuffCur:SetWidth(170)
  y = y - 30
  local sl = UI:Text(pane, "Spell", "small"); sl:SetPoint("TOPLEFT", 16, y - 5)
  pane.ruleSpell = spellBox(pane, 150, "spell name / drag", function(id) pane.newRule.spell = id; pane.ruleSpellCur:SetText(spellCell(id)) end)
  pane.ruleSpell:SetPoint("TOPLEFT", 52, y)
  pane.ruleSpellCur = UI:Text(pane, "", "small"); pane.ruleSpellCur:SetPoint("LEFT", pane.ruleSpell, "RIGHT", 6, 0); pane.ruleSpellCur:SetWidth(170)
  y = y - 30
  local RANGES = { { value = "any", text = "Any range" }, { value = "near", text = "Only in range" }, { value = "far", text = "Only out of range" } }
  pane.ruleRange = UI:Dropdown(pane, 150, RANGES, "any")
  pane.ruleRange:SetPoint("TOPLEFT", 52, y)
  local add = UI:Button(pane, "Add rule", 90, 24, function()
    local nr = pane.newRule
    if not nr.buff or not nr.spell then UI:Alert("Pick a buff and a spell first (type them and press Enter, or drag them in).") return end
    local o = P().opener
    o.rules = o.rules or {}
    o.rules[#o.rules + 1] = { buff = nr.buff, spell = nr.spell, range = pane.ruleRange.value ~= "any" and pane.ruleRange.value or nil }
    pane.newRule = {}; pane.ruleBuffCur:SetText(""); pane.ruleSpellCur:SetText("")
    S:RefreshRotational()
  end)
  add:SetPoint("LEFT", pane.ruleRange, "RIGHT", 8, 0)
  y = y - 32
  pane.rtbl = UI:Table(pane, W - 28, 130, {
    { title = "If this buff is up", w = 190, get = function(r) return spellCell(r.ref.buff) end },
    { title = "Open with", w = 180, get = function(r) return spellCell(r.ref.spell) end },
    { title = "Range", w = 100, get = function(r) return ({ near = "in range", far = "out of range" })[r.ref.range or ""] or "any" end },
  }, { selectable = true, emptyText = "No rules yet." })
  pane.rtbl:SetPoint("TOPLEFT", 14, y)
  y = y - 136
  listControls(pane, pane.rtbl, function() local o = P().opener; o.rules = o.rules or {}; return o.rules end, y, function() S:RefreshRotational() end)
end

local function buildProcs()
  local pane = panes[3]
  local hint = UI:Text(pane, "|cffaaaaaaA pop-up when a proc happens. It can push a spell to the front (Maelstrom Weapon at 5 > Lightning Bolt) or reset its cooldown. Click a proc in the list to change it.|r", "small")
  hint:SetPoint("TOPLEFT", 14, -4); hint:SetWidth(W - 28); hint:SetJustifyH("LEFT")
  pane.draft = {}
  local y = -34
  local function label(t, x, yy) local l = UI:Text(pane, t, "small"); l:SetPoint("TOPLEFT", x, yy - 5); return l end
  label("Proc (buff)", 16, y)
  pane.aura = spellBox(pane, 150, "e.g. Maelstrom Weapon", function(id) pane.draft.aura = id; pane.auraName:SetText(spellCell(id)) end)
  pane.aura:SetPoint("TOPLEFT", 100, y)
  pane.auraName = UI:Text(pane, "", "small"); pane.auraName:SetPoint("LEFT", pane.aura, "RIGHT", 6, 0); pane.auraName:SetWidth(130)
  label("Stacks", 400, y)
  pane.stacks = UI:Edit(pane, 40, 24, "1", nil, true); pane.stacks:SetPoint("TOPLEFT", 450, y)
  y = y - 30
  label("Then use", 16, y)
  pane.use = spellBox(pane, 150, "optional", function(id) pane.draft.use = id; pane.useName:SetText(spellCell(id)) end)
  pane.use:SetPoint("TOPLEFT", 100, y)
  pane.useName = UI:Text(pane, "", "small"); pane.useName:SetPoint("LEFT", pane.use, "RIGHT", 6, 0); pane.useName:SetWidth(130)
  pane.reset = UI:Check(pane, "Resets its cooldown", false, nil, "Tick for procs that make that spell ready again straight away.")
  pane.reset:SetPoint("TOPLEFT", 400, y - 3)
  y = y - 30
  local tl = label("Triggered by", 16, y)
  pane.trigger = UI:Dropdown(pane, 200, S.ROT_TRIGGERS, "any"); pane.trigger:SetPoint("TOPLEFT", 100, y)
  UI:Tip(tl, "Triggered by", { "Only react when the proc came from this.",
    "Make several entries for the same proc - e.g. one 'After you dodge or parry' and one 'Anything else' - each with its own pop-up and spell.",
    "|cff888888Uses the game's dodge / parry / block text for you and your target.|r" })
  pane.eventOnly = UI:Check(pane, "Fire on the event itself", true, nil,
    { "On (normal): the pop-up goes off the moment the game reports the dodge / parry / block / miss - no waiting for a buff or cooldown. 'Proc (buff)' can stay empty. A 'Then use' spell glows for 5 seconds (or until you use it).",
      "Off: wait until the proc's buff (or its cooldown reset) actually shows up." })
  pane.eventOnly:SetPoint("LEFT", pane.trigger, "RIGHT", 10, 0)
  pane.trigSeen = UI:Text(pane, "", "small"); pane.trigSeen:SetPoint("TOPLEFT", pane.trigger, "BOTTOMLEFT", 0, -1); pane.trigSeen:SetWidth(300)
  y = y - 32
  label("Pop-up text", 16, y)
  pane.text = UI:Edit(pane, 160, 24, "empty = proc name > spell"); pane.text:SetPoint("TOPLEFT", 100, y)
  local il = UI:Text(pane, "Icon", "small"); il:SetPoint("TOPLEFT", 268, y - 5)
  UI:Tip(il, "Pop-up icon", "Use the icon of any spell (type its name or drag it in). Empty = the proc's own spell (Windfury pop-ups use Windfury Weapon).")
  pane.iconPic = pane:CreateTexture(nil, "ARTWORK"); pane.iconPic:SetSize(22, 22); pane.iconPic:SetPoint("TOPLEFT", 296, y - 1)
  pane.iconPic:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  pane.icon = spellBox(pane, 84, "spell", function(id) pane.draft.iconSpell = id; pane.iconPic:SetTexture(spellIcon(id)); pane.iconPic:Show() end)
  pane.icon:SetPoint("TOPLEFT", 322, y)
  pane.pop = UI:Check(pane, "Pop-up", true); pane.pop:SetPoint("TOPLEFT", 414, y - 3)
  y = y - 30
  label("Colour", 16, y)
  pane.color = UI:Dropdown(pane, 100, S.ROT_POP_COLORS, "gold"); pane.color:SetPoint("TOPLEFT", 100, y)
  label("Size", 214, y)
  pane.size = UI:Dropdown(pane, 90, S.ROT_SIZES, 20); pane.size:SetPoint("TOPLEFT", 250, y)
  label("Sound", 352, y)
  local sounds = { { value = "default", text = "Default" } }
  for _, so in ipairs(S.REMINDER_SOUNDS or {}) do sounds[#sounds + 1] = so end
  pane.sound = UI:Dropdown(pane, 110, sounds, "default", function(v) if v ~= "default" and v ~= "none" and S.PlayReminderSound then S:PlayReminderSound(v) end end)
  pane.sound:SetPoint("TOPLEFT", 398, y)
  y = y - 30
  label("Effect", 16, y)
  pane.anim = UI:Dropdown(pane, 120, S.ROT_POP_ANIMS, "fade"); pane.anim:SetPoint("TOPLEFT", 100, y)
  label("Screen", 234, y)
  pane.screen = UI:Dropdown(pane, 190, S.ROT_SCREEN, "none"); pane.screen:SetPoint("TOPLEFT", 284, y)
  y = y - 34
  local function form()
    local d = pane.draft
    local snd = pane.sound.value
    return { aura = d.aura, use = d.use, iconSpell = d.iconSpell, stacks = tonumber(pane.stacks:GetText() or "") or nil,
      reset = pane.reset:GetChecked() and true or false, popup = pane.pop:GetChecked() and true or false,
      text = (pane.text:GetText() or "") ~= "" and pane.text:GetText() or nil,
      color = pane.color.value or "gold", size = pane.size.value or 20, anim = pane.anim.value or "fade",
      screen = pane.screen.value or "none", sound = snd ~= "default" and snd or nil, trigger = pane.trigger.value or "any",
      eventOnly = pane.eventOnly:GetChecked() and true or false }
  end
  local function clearForm()
    pane.editing = nil; pane.draft = {}
    pane.auraName:SetText(""); pane.useName:SetText(""); pane.stacks:SetText(""); pane.text:SetText("")
    pane.iconPic:Hide()
    pane.reset:SetChecked(false); pane.pop:SetChecked(true)
    pane.color:SetValue("gold"); pane.color.value = "gold"; pane.size:SetValue(20); pane.size.value = 20
    pane.anim:SetValue("fade"); pane.anim.value = "fade"; pane.screen:SetValue("none"); pane.screen.value = "none"
    pane.sound:SetValue("default"); pane.sound.value = "default"
    pane.trigger:SetValue("any"); pane.trigger.value = "any"
    pane.eventOnly:SetChecked(true)
    pane.save:SetText("Add proc")
  end
  pane.save = UI:PrimaryButton(pane, "Add proc", 110, 24, function()
    local f = form()
    if f.trigger == "cast" and not f.aura then UI:Alert("Put the proc's spell in 'Proc (buff)' - e.g. Windfury Attack.") return end
    local evt = f.eventOnly and EVENT_TRIGGERS[f.trigger or ""]
    if not f.aura and not f.use and not evt then UI:Alert("Pick the proc buff (or the spell the game lights up), or tick 'On the dodge/parry itself'.") return end
    if pane.editing then for k, v in pairs(f) do pane.editing[k] = v end
      for _, k in ipairs({ "text", "sound", "stacks", "iconSpell" }) do if f[k] == nil then pane.editing[k] = nil end end
    else table.insert(P().procs, f) end
    clearForm(); S:RefreshRotational()
  end)
  pane.save:SetPoint("TOPLEFT", 14, y)
  local new = UI:Button(pane, "New", 60, 24, function() clearForm(); pane.tbl.selected = nil; S:RefreshRotational() end, "Clear the form for a new proc.")
  new:SetPoint("LEFT", pane.save, "RIGHT", 6, 0)
  local test = UI:Button(pane, "Preview", 80, 24, function()
    local f = form()
    if not f.aura and not f.use and not f.eventOnly then f.label = "Maelstrom Weapon"; f.use = spellInfo("Lightning Bolt") end
    if f.eventOnly and EVENT_TRIGGERS[f.trigger or ""] and not f.text and not f.aura and not f.use then f.text = "Dodge / Parry!" end
    showPopup(procPopupOpts(f))
  end, "Shows the pop-up with the settings above.")
  test:SetPoint("LEFT", new, "RIGHT", 6, 0)
  y = y - 32
  pane.tbl = UI:Table(pane, W - 28, 150, {
    { title = "Proc", w = 150, get = function(r)
        if eventOnly(r.ref) then return (r.ref.aura and spellCell(r.ref.aura) or "|cffffd100(the event itself)|r") .. " |cff55ff55instant|r" end
        return (r.ref.aura and spellCell(r.ref.aura) or "|cff888888(game highlight)|r") .. (r.ref.stacks and r.ref.stacks > 1 and (" x" .. r.ref.stacks) or "")
      end },
    { title = "When", w = 90, get = function(r)
        local t = r.ref.trigger or "any"
        local names = { any = "always", other = "anything else", dodge = "you dodge", parry = "you parry", dodgeparry = "dodge / parry",
          miss = "missed", avoid = "dodge/parry/block/miss", tmiss = "you miss", cast = "spell reported", extra = "extra attacks", wf = "two hits (WF)",
          block = "you block", tdodge = "target dodges", tparry = "target parries", crit = "a crit" }
        return (t == "any" and "|cff888888" or "|cffffd100") .. (names[t] or t) .. "|r"
      end, tip = "What has to cause the proc for this entry to react." },
    { title = "Then use", w = 120, get = function(r) return r.ref.use and spellCell(r.ref.use) or "|cff888888pop-up only|r" end },
    { title = "Resets", w = 50, get = function(r) return r.ref.reset and "|cff55ff55yes|r" or "" end, tip = "Resets the cooldown of the 'then use' spell." },
    { title = "Look", w = 100, get = function(r)
        if r.ref.popup == false then return "|cff888888no pop-up|r" end
        return (r.ref.anim or "fade") .. ((r.ref.screen and r.ref.screen ~= "none") and (" + " .. r.ref.screen) or "")
      end },
  }, { selectable = true, emptyText = "No procs yet.", onClick = function(r)
        -- load it into the form to change it
        local pr = r.ref
        pane.editing = pr
        pane.draft = { aura = pr.aura, use = pr.use, iconSpell = pr.iconSpell }
        local ic = popupIcon(pr)
        if ic then pane.iconPic:SetTexture(ic); pane.iconPic:Show() else pane.iconPic:Hide() end
        pane.auraName:SetText(pr.aura and spellCell(pr.aura) or ""); pane.useName:SetText(pr.use and spellCell(pr.use) or "")
        pane.stacks:SetText(pr.stacks and tostring(pr.stacks) or ""); pane.text:SetText(pr.text or "")
        pane.reset:SetChecked(pr.reset and true or false); pane.pop:SetChecked(pr.popup ~= false)
        pane.eventOnly:SetChecked(pr.eventOnly ~= false)
        for _, k in ipairs({ { "color", pr.color or "gold" }, { "size", pr.size or 20 }, { "anim", pr.anim or "fade" }, { "screen", pr.screen or "none" }, { "sound", pr.sound or "default" }, { "trigger", pr.trigger or "any" } }) do
          pane[k[1]]:SetValue(k[2]); pane[k[1]].value = k[2]
        end
        pane.save:SetText("Save changes")
      end })
  pane.tbl:SetPoint("TOPLEFT", 14, y)
  listControls(pane, pane.tbl, function() return P().procs end, y - 156, function() clearForm(); S:RefreshRotational() end)
end

local function buildBuffs()
  local pane = panes[4]
  local hint = UI:Text(pane, "|cffaaaaaaBuffs to keep up. Out of combat, a missing one glows softly so you remember before the pull.|r", "small")
  hint:SetPoint("TOPLEFT", 14, -4); hint:SetWidth(W - 28); hint:SetJustifyH("LEFT")
  pane.kind = UI:Dropdown(pane, 170, { { value = "aura", text = "Buff on me" }, { value = "main", text = "Main-hand weapon" }, { value = "off", text = "Off-hand weapon" } }, "aura")
  pane.kind:SetPoint("TOPLEFT", 14, -30)
  pane.add = spellBox(pane, 220, "e.g. Lightning Shield / Windfury Weapon", function(id)
    table.insert(P().buffs, { spell = id, kind = pane.kind.value or "aura", combat = pane.inCombat:GetChecked() and true or nil }); S:RefreshRotational()
  end)
  pane.add:SetPoint("LEFT", pane.kind, "RIGHT", 6, 0)
  local addBtn = UI:Button(pane, "Add", 60, 24, function() pane.add:GetScript("OnEnterPressed")(pane.add) end)
  addBtn:SetPoint("LEFT", pane.add, "RIGHT", 6, 0)
  pane.inCombat = UI:Check(pane, "Keep it up in combat too (top priority when it drops)", false, function(v)
    local e = pane.tbl.selected and pane.tbl.selected.ref
    if e then e.combat = v or nil; S:RefreshRotational() end
  end, "Lightning Shield: when the charges run out mid-fight it glows before anything else. Applies to new buffs and to the one selected in the list.")
  pane.inCombat:SetPoint("TOPLEFT", 14, -60)
  pane.tbl = UI:Table(pane, W - 28, 280, {
    { title = "Buff", w = 200, get = function(r) return spellCell(r.ref.spell) end },
    { title = "In combat", w = 70, get = function(r) return r.ref.combat and "|cff55ff55yes|r" or "|cff555555-|r" end,
      tip = "Also kept up during fights, at top priority." },
    { title = "Checked on", w = 120, get = function(r) return ({ aura = "you", main = "main-hand weapon", off = "off-hand weapon" })[r.ref.kind or "aura"] end },
    { title = "Up now?", w = 80, get = function(r)
        return buffMissing(r.ref) and "|cffff5555no|r" or "|cff55ff55yes|r"
      end },
  }, { selectable = true, emptyText = "No buffs yet.", onClick = function(r) pane.inCombat:SetChecked(r.ref.combat and true or false) end })
  pane.tbl:SetPoint("TOPLEFT", 14, -88)
  listControls(pane, pane.tbl, function() return P().buffs end, -374, function() S:RefreshRotational() end)
end

local CLEANSE_TYPES = { { value = "any", text = "Any debuff" }, { value = "Magic", text = "Magic" }, { value = "Curse", text = "Curse" },
  { value = "Poison", text = "Poison" }, { value = "Disease", text = "Disease" } }
local function buildDispels()
  local pane = panes[5]
  local hint = UI:Text(pane, "|cffaaaaaaThese glow ahead of your rotation when they're needed.|r", "small")
  hint:SetPoint("TOPLEFT", 14, -4); hint:SetWidth(W - 28); hint:SetJustifyH("LEFT")
  -- purge / spellsteal: one spell
  local h = UI:Header(pane, "Purge / Spellsteal"); h:SetPoint("TOPLEFT", 14, -26)
  local d = UI:Text(pane, "|cffaaaaaaGlows when your enemy target has a buff you can take off.|r", "small"); d:SetPoint("TOPLEFT", 16, -50)
  pane.purgeOn = UI:Check(pane, "On", P().purge.on, function(v) P().purge.on = v end); pane.purgeOn:SetPoint("TOPLEFT", 14, -74)
  pane.purgeCur = UI:Text(pane, "", "normal"); pane.purgeCur:SetPoint("TOPLEFT", 90, -76)
  local pbox = spellBox(pane, 180, "e.g. Purge / Spellsteal", function(id) P().purge.spell = id; P().purge.on = true; S:RefreshRotational() end)
  pbox:SetPoint("TOPLEFT", 300, -70)
  -- cleanses: as many as you like, each for a debuff type
  local h2 = UI:Header(pane, "Cleanse / Cure / Dispel"); h2:SetPoint("TOPLEFT", 14, -112)
  local d2 = UI:Text(pane, "|cffaaaaaaGlows when you or your group has a debuff you can remove. Add one spell per debuff type - the one that matches glows. When the game hides the type, the first ready one glows.|r", "small")
  d2:SetPoint("TOPLEFT", 16, -136); d2:SetWidth(W - 32); d2:SetJustifyH("LEFT")
  pane.cleanseOn = UI:Check(pane, "On", P().cleanseOn, function(v) P().cleanseOn = v end); pane.cleanseOn:SetPoint("TOPLEFT", 14, -170)
  pane.ctype = UI:Dropdown(pane, 120, CLEANSE_TYPES, "any"); pane.ctype:SetPoint("TOPLEFT", 90, -168)
  local cbox = spellBox(pane, 200, "e.g. Cure Toxins", function(id)
    table.insert(P().cleanses, { spell = id, type = pane.ctype.value or "any" }); P().cleanseOn = true; S:RefreshRotational()
  end)
  cbox:SetPoint("LEFT", pane.ctype, "RIGHT", 6, 0)
  local addC = UI:Button(pane, "Add", 50, 24, function() cbox:GetScript("OnEnterPressed")(cbox) end)
  addC:SetPoint("LEFT", cbox, "RIGHT", 6, 0)
  pane.ctbl = UI:Table(pane, W - 28, 150, {
    { title = "Spell", w = 260, get = function(r) return spellCell(r.ref.spell) end },
    { title = "Removes", w = 120, get = function(r) local t = r.ref.type or "any"; return t == "any" and "any debuff" or t end },
    { title = "Known", w = 70, get = function(r) return known(r.ref.spell) and "|cff55ff55yes|r" or "|cffff5555no|r" end },
  }, { selectable = true, emptyText = "No cleanse spells yet." })
  pane.ctbl:SetPoint("TOPLEFT", 14, -202)
  listControls(pane, pane.ctbl, function() return P().cleanses end, -358, function() S:RefreshRotational() end)
end

local function buildHealth()
  local pane = panes[6]
  local function L() local p = P(); p.lowhp = p.lowhp or { on = false, pct = 35, color = "red", anim = "shake", screen = "pulse", size = 28 }; return p.lowhp end
  local hint = UI:Text(pane, "|cffaaaaaaWhen your health drops below the line: a pop-up, and your emergency spell glows before everything else (in and out of combat).|r", "small")
  hint:SetPoint("TOPLEFT", 14, -4); hint:SetWidth(W - 28); hint:SetJustifyH("LEFT")
  local y = -34
  pane.on = UI:Check(pane, "Low health warning on", L().on, function(v) L().on = v end); pane.on:SetPoint("TOPLEFT", 14, y); y = y - 32
  pane.pct = UI:Slider(pane, W - 40, "Below this much health", 5, 90, 5, L().pct or 35, function(v) L().pct = v end, function(v) return v .. "%" end)
  pane.pct:SetPoint("TOPLEFT", 16, y); y = y - 34
  local sl = UI:Text(pane, "Cast in this order", "small"); sl:SetPoint("TOPLEFT", 16, y - 5)
  UI:Tip(sl, "Low health sequence", { "When your health drops, these glow one after another - each one as soon as you've cast the one before - then your normal rotation comes back.",
    "Add the same spell twice to cast it twice (e.g. two heals). Leave it empty for just the pop-up." })
  pane.spell = spellBox(pane, 190, "add a spell, e.g. Healing Wave", function(id) table.insert(lowSeq(L()), id); L().spell = lowSeq(L())[1]; S:RefreshRotational() end)
  pane.spell:SetPoint("TOPLEFT", 140, y)
  local addB = UI:Button(pane, "Add", 50, 24, function() pane.spell:GetScript("OnEnterPressed")(pane.spell) end)
  addB:SetPoint("LEFT", pane.spell, "RIGHT", 4, 0)
  y = y - 28
  pane.seq = UI:Table(pane, W - 28, 84, {
    { title = "#", w = 30, get = function(r) return r.pos end },
    { title = "Spell", w = 300, get = function(r) return spellCell(r.ref) end },
  }, { selectable = true, emptyText = "No spells - just the pop-up." })
  pane.seq:SetPoint("TOPLEFT", 14, y)
  y = y - 88
  -- move / remove (the list holds spell IDs, so work on positions)
  local function idx() local sel = pane.seq.selected; return sel and sel.pos end
  local up = UI:Button(pane, "Up", 50, 20, function() local i, l = idx(), lowSeq(L()); if i and i > 1 then l[i], l[i - 1] = l[i - 1], l[i]; S:RefreshRotational() end end)
  up:SetPoint("TOPLEFT", 14, y)
  local dn = UI:Button(pane, "Down", 56, 20, function() local i, l = idx(), lowSeq(L()); if i and i < #l then l[i], l[i + 1] = l[i + 1], l[i]; S:RefreshRotational() end end)
  dn:SetPoint("LEFT", up, "RIGHT", 4, 0)
  local rm = UI:Button(pane, "|cffff7777Remove|r", 70, 20, function() local i = idx(); if i then table.remove(lowSeq(L()), i); pane.seq.selected = nil; lowSeq(L()); S:RefreshRotational() end end)
  rm:SetPoint("LEFT", dn, "RIGHT", 4, 0)
  pane.repeatSeq = UI:Check(pane, "Start again if still low after the last one", L().repeatSeq, function(v) L().repeatSeq = v end)
  pane.repeatSeq:SetPoint("LEFT", rm, "RIGHT", 12, 0)
  y = y - 28
  local h = UI:Header(pane, "Pop-up"); h:SetPoint("TOPLEFT", 14, y); y = y - 28
  pane.popup = UI:Check(pane, "Show a pop-up", L().popup ~= false, function(v) L().popup = v end); pane.popup:SetPoint("TOPLEFT", 14, y); y = y - 30
  local tl = UI:Text(pane, "Text", "small"); tl:SetPoint("TOPLEFT", 16, y - 5)
  pane.text = UI:Edit(pane, 300, 24, "empty = LOW HEALTH > spell"); pane.text:SetPoint("TOPLEFT", 100, y)
  pane.text:SetScript("OnTextChanged", function(self, user) if user then L().text = self:GetText() end end)
  y = y - 30
  local function dd(lbl, x, w, opts, key, def)
    local t = UI:Text(pane, lbl, "small"); t:SetPoint("TOPLEFT", x, y - 5)
    local d = UI:Dropdown(pane, w, opts, L()[key] or def, function(v) L()[key] = v end)
    d:SetPoint("TOPLEFT", x + 50, y)
    return d
  end
  pane.color = dd("Colour", 16, 100, S.ROT_POP_COLORS, "color", "red")
  pane.size = dd("Size", 216, 90, S.ROT_SIZES, "size", 28)
  y = y - 30
  pane.anim = dd("Effect", 16, 120, S.ROT_POP_ANIMS, "anim", "shake")
  pane.screen = dd("Screen", 216, 190, S.ROT_SCREEN, "screen", "pulse")
  y = y - 30
  local sounds = { { value = "default", text = "Default" } }
  for _, so in ipairs(S.REMINDER_SOUNDS or {}) do sounds[#sounds + 1] = so end
  local stl = UI:Text(pane, "Sound", "small"); stl:SetPoint("TOPLEFT", 16, y - 5)
  pane.sound = UI:Dropdown(pane, 130, sounds, L().sound or "default", function(v)
    L().sound = v ~= "default" and v or nil
    if v ~= "default" and v ~= "none" and S.PlayReminderSound then S:PlayReminderSound(v) end
  end)
  pane.sound:SetPoint("TOPLEFT", 66, y)
  y = y - 38
  local prev = UI:Button(pane, "Preview", 90, 24, function()
    local l = L()
    showPopup({ text = (l.text and l.text ~= "") and l.text or ("LOW HEALTH" .. (l.spell and ("  |cffffffff> " .. spellName(l.spell) .. "|r") or "")),
      icon = l.spell and spellIcon(l.spell) or "Interface\\Icons\\Spell_Holy_SealOfSacrifice", color = l.color or "red", anim = l.anim or "shake",
      screen = l.screen or "pulse", size = l.size or 28, sound = l.sound })
  end)
  prev:SetPoint("TOPLEFT", 14, y)
  pane.hpNow = UI:Text(pane, "", "small"); pane.hpNow:SetPoint("LEFT", prev, "RIGHT", 12, 0)
end

local ANIMS = { { value = "pulse", text = "Pulse" }, { value = "breathe", text = "Breathe (slow)" }, { value = "flash", text = "Flash on / off" },
  { value = "heartbeat", text = "Heartbeat" }, { value = "steady", text = "Steady" } }
local STYLES = { { value = "both", text = "Glow + border" }, { value = "glow", text = "Glow only" }, { value = "border", text = "Border only" } }
local function buildLook()
  local pane = panes[7]
  local p = P()
  local look = function() return P().look end
  local y = -6
  local function lbl(t, x, yy) local f = UI:Text(pane, t, "small"); f:SetPoint("TOPLEFT", x, yy - 5); return f end
  pane.enabled = UI:Check(pane, "Rotational on", p.enabled ~= false, function(v) P().enabled = v end, "Turn all the glows on or off.")
  pane.enabled:SetPoint("TOPLEFT", 14, y); y = y - 28
  local h1 = UI:Header(pane, "Press now (on your action bars)"); h1:SetPoint("TOPLEFT", 14, y); y = y - 26
  pane.strong = UI:Slider(pane, W - 40, "Glow strength", 10, 100, 5, math.floor((p.look.strong or 0.9) * 100), function(v) look().strong = v / 100 end, function(v) return v .. "%" end)
  pane.strong:SetPoint("TOPLEFT", 16, y); y = y - 28
  local opts = {}
  for _, k in ipairs({ "gold", "orange", "red", "pink", "purple", "blue", "cyan", "green", "white" }) do opts[#opts + 1] = { value = k, text = k:sub(1, 1):upper() .. k:sub(2) } end
  lbl("Colour", 16, y)
  pane.color = UI:Dropdown(pane, 130, opts, type(p.look.color) == "string" and p.look.color or "gold", function(v) look().color = v end)
  pane.color:SetPoint("TOPLEFT", 70, y)
  lbl("Style", 268, y)
  pane.style = UI:Dropdown(pane, 150, STYLES, p.look.style or "both", function(v) look().style = v end)
  pane.style:SetPoint("TOPLEFT", 316, y); y = y - 30
  lbl("Effect", 16, y)
  pane.anim = UI:Dropdown(pane, 130, ANIMS, p.look.anim or "pulse", function(v) look().anim = v end)
  pane.anim:SetPoint("TOPLEFT", 70, y); y = y - 30
  pane.speed = UI:Slider(pane, W - 40, "Speed", 1, 16, 1, p.look.speed or 7, function(v) look().speed = v end)
  pane.speed:SetPoint("TOPLEFT", 16, y); y = y - 28
  pane.size = UI:Slider(pane, W - 40, "Bar glow size", 0, 30, 1, p.look.glowSize or 12, function(v) look().glowSize = v end)
  pane.size:SetPoint("TOPLEFT", 16, y); y = y - 28
  pane.spin = UI:Check(pane, "Spinning star", p.look.spin and true or false, function(v) look().spin = v or nil end, "A star burst that turns behind the button.")
  pane.spin:SetPoint("TOPLEFT", 14, y)
  pane.tint = UI:Check(pane, "Tint the icon", p.look.tint and true or false, function(v) look().tint = v or nil end, "Washes the button in the glow colour as it pulses.")
  pane.tint:SetPoint("TOPLEFT", 200, y); y = y - 30

  local h2 = UI:Header(pane, "Next-spell icon"); h2:SetPoint("TOPLEFT", 14, y); y = y - 26
  pane.next = UI:Check(pane, "Show the next spell as a big icon (shift-drag it to move)", p.look.next ~= false, function(v) look().next = v end)
  pane.next:SetPoint("TOPLEFT", 14, y); y = y - 26
  pane.nsize = UI:Slider(pane, W - 40, "Icon size", 28, 120, 2, p.look.nextSize or 52, function(v) look().nextSize = v end)
  pane.nsize:SetPoint("TOPLEFT", 16, y); y = y - 28
  pane.nalpha = UI:Slider(pane, W - 40, "Opacity", 20, 100, 5, math.floor((p.look.nextAlpha or 1) * 100), function(v) look().nextAlpha = v / 100 end, function(v) return v .. "%" end)
  pane.nalpha:SetPoint("TOPLEFT", 16, y); y = y - 28
  local GSN = { "Small", "Medium", "Large", "Larger", "Huge" }
  pane.nglow = UI:Slider(pane, W - 40, "Icon glow size", 1, 5, 1, p.look.nextGlow or 3, function(v) look().nextGlow = v end, function(v) return GSN[v] or v end)
  pane.nglow:SetPoint("TOPLEFT", 16, y); y = y - 28
  local RN = { [0] = "Square", "Slight", "Rounded", "More", "Very round", "Circle" }
  pane.nround = UI:Slider(pane, W - 40, "Icon roundness", 0, 5, 1, p.look.nextRound or 2, function(v) look().nextRound = v end, function(v) return RN[v] or v end)
  pane.nround:SetPoint("TOPLEFT", 16, y); y = y - 28
  local nanims = { { value = "same", text = "Same as buttons" } }
  for _, a in ipairs(ANIMS) do nanims[#nanims + 1] = a end
  lbl("Effect", 16, y)
  pane.nanim = UI:Dropdown(pane, 150, nanims, p.look.nextAnim or "same", function(v) look().nextAnim = v ~= "same" and v or nil end)
  pane.nanim:SetPoint("TOPLEFT", 70, y)
  lbl("Style", 268, y)
  local nstyles = { { value = "same", text = "Same as buttons" } }
  for _, a in ipairs(STYLES) do nstyles[#nstyles + 1] = a end
  pane.nstyle = UI:Dropdown(pane, 150, nstyles, p.look.nextStyle or "same", function(v) look().nextStyle = v ~= "same" and v or nil end)
  pane.nstyle:SetPoint("TOPLEFT", 316, y); y = y - 30
  pane.pop = UI:Check(pane, "Pop when the spell changes", p.look.pop ~= false, function(v) look().pop = v end)
  pane.pop:SetPoint("TOPLEFT", 14, y)
  pane.nlabel = UI:Check(pane, "Spell name under it", p.look.nextLabel ~= false, function(v) look().nextLabel = v end)
  pane.nlabel:SetPoint("TOPLEFT", 260, y); y = y - 32
  local test = UI:Button(pane, "Test the glows", 130, 24, function()
    scanButtons()
    local any = false
    for _, b in ipairs(buttons) do
      local ok, vis = pcall(b.IsVisible, b)
      if ok and vis and slotSpell(slotOf(b) or 0) then setGlow(b, "strong"); any = true; break end
    end
    if not any then UI:Alert("No spells found on your action bars.") end
    C_Timer.After(4, function() for _, g in pairs(glows) do g:Hide() end end)
  end, "Lights up the first spell on your bars for 4 seconds with these settings.")
  test:SetPoint("TOPLEFT", 14, y)
end

function S:RefreshRotational()
  if not win or not win:IsShown() then return end
  local p = P()
  local function rows(list) local out = {} for i, v in ipairs(list) do out[i] = { pos = i, ref = v } end return out end
  if panes[1].tbl then panes[1].tbl:SetData(rows(p.prio)) end
  if panes[2].fields then
    for k, fs in pairs(panes[2].fields) do if k ~= "rules" then fs:SetText(p.opener[k] and spellCell(p.opener[k]) or "|cff888888(not set)|r") end end
    if panes[2].rtbl then panes[2].rtbl:SetData(rows(p.opener.rules or {})) end
  end
  if panes[3].tbl then panes[3].tbl:SetData(rows(p.procs)) end
  if panes[4].tbl then panes[4].tbl:SetData(rows(p.buffs)) end
  if panes[5].purgeCur then
    panes[5].purgeCur:SetText(p.purge.spell and spellCell(p.purge.spell) or "|cff888888(no spell)|r"); panes[5].purgeOn:SetChecked(p.purge.on and true or false)
    panes[5].cleanseOn:SetChecked(p.cleanseOn and true or false)
    panes[5].ctbl:SetData(rows(p.cleanses))
  end
  if panes[1].selName then S:RotLoadSelected() end
  local hp = panes[6]
  if hp.on then
    local l = p.lowhp or {}
    hp.on:SetChecked(l.on and true or false); hp.pct:SetValue(l.pct or 35); hp.popup:SetChecked(l.popup ~= false)
    local rows = {}
    for i, id in ipairs(lowSeq(l)) do rows[i] = { pos = i, ref = id } end
    hp.seq:SetData(rows)
    hp.repeatSeq:SetChecked(l.repeatSeq and true or false)
    hp.text:SetText(l.text or "")
    for _, k in ipairs({ { "color", l.color or "red" }, { "size", l.size or 28 }, { "anim", l.anim or "shake" }, { "screen", l.screen or "pulse" }, { "sound", l.sound or "default" } }) do
      hp[k[1]]:SetValue(k[2]); hp[k[1]].value = k[2]
    end
    local pct = healthPct()
    hp.hpNow:SetText(pct and string.format("|cff888888Your health now: %d%%|r", pct) or "|cffff9933Health is hidden right now - using the game's own low-health glow instead.|r")
  end
  local lk = panes[7]
  if lk.enabled then
    local L = p.look
    lk.enabled:SetChecked(p.enabled ~= false)
    lk.strong:SetValue(math.floor((L.strong or 0.9) * 100))
    for _, k in ipairs({ { lk.color, type(L.color) == "string" and L.color or "gold" }, { lk.style, L.style or "both" }, { lk.anim, L.anim or "pulse" },
      { lk.nanim, L.nextAnim or "same" }, { lk.nstyle, L.nextStyle or "same" } }) do k[1]:SetValue(k[2]); k[1].value = k[2] end
    lk.speed:SetValue(L.speed or 7); lk.size:SetValue(L.glowSize or 12)
    lk.spin:SetChecked(L.spin and true or false); lk.tint:SetChecked(L.tint and true or false)
    lk.next:SetChecked(L.next ~= false); lk.nsize:SetValue(L.nextSize or 52); lk.nalpha:SetValue(math.floor((L.nextAlpha or 1) * 100)); lk.nglow:SetValue(L.nextGlow or 3); lk.nround:SetValue(L.nextRound or 2)
    lk.pop:SetChecked(L.pop ~= false); lk.nlabel:SetChecked(L.nextLabel ~= false)
  end
  if panes[3].trigSeen then
    local t = recent.seen
    local last = diag[1]
    panes[3].trigSeen:SetText(t and "|cff55ff55game reports dodges/parries|r" or (last and "|cffff9933seen, but no dodge/parry yet|r" or "|cff888888nothing reported yet|r"))
  end
  win.status:SetText("|cff888888In fights the game lets us see:|r cooldowns " .. seen.cd .. ", buffs " .. seen.aura)
  win.profBtn:SetText(activeName())
end

local function build()
  win = UI:Window("CC_Rotational", "Rotational", W, H)
  win:SetFrameStrata("HIGH")
  -- "Rotational (Shaman)" in your class colour: setups are for your class only
  local cls, clsName = myClass()
  local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
  win.title:SetText("Rotational " .. (cc and string.format("|cff%02x%02x%02x(%s)|r", cc.r * 255, cc.g * 255, cc.b * 255, clsName) or ("(" .. clsName .. ")")))
  -- profile row: one setup per specialization (or any you make)
  local pl = UI:Text(win, "Setup", "small"); pl:SetPoint("TOPLEFT", 16, -42)
  UI:Tip(pl, "Setups", { "Every " .. clsName .. " you play shares these setups.", "Pick the one for your specialization - each character remembers its choice for each talent set." })
  win.profBtn = UI:Button(win, "", 190, 22, function(self)
    local c = classStore()
    local items = { { text = clsName .. " setups", title = true } }
    for _, n in ipairs(c.order) do items[#items + 1] = { text = n, checked = n == activeName(), func = function() S:RotUseProfile(n) end } end
    UI:Menu(self, items)
  end)
  win.profBtn:SetPoint("TOPLEFT", 60, -38)
  local function prompt(text, def, fn) UI:Prompt(text, def, fn) end
  local newB = UI:Button(win, "New", 54, 22, function()
    prompt("Name for the new setup (e.g. a specialization):", "", function(name)
      if not S:RotNewProfile(name) then UI:Alert("That name is empty or already used.") end
    end)
  end, "A new empty setup.")
  newB:SetPoint("LEFT", win.profBtn, "RIGHT", 6, 0)
  local copyB = UI:Button(win, "Copy", 54, 22, function()
    local from = activeName()
    prompt("Name for the copy of '" .. from .. "':", from .. " 2", function(name)
      if not S:RotNewProfile(name, from) then UI:Alert("That name is empty or already used.") end
    end)
  end, "A copy of this setup to change.")
  copyB:SetPoint("LEFT", newB, "RIGHT", 4, 0)
  local renB = UI:Button(win, "Rename", 66, 22, function()
    local cur = activeName()
    prompt("New name for '" .. cur .. "':", cur, function(name)
      if not S:RotRenameProfile(cur, name) then UI:Alert("That name is empty or already used.") end
    end)
  end)
  renB:SetPoint("LEFT", copyB, "RIGHT", 4, 0)
  local delB = UI:Button(win, "|cffff7777Delete|r", 64, 22, function()
    local cur = activeName()
    if #classStore().order <= 1 then UI:Alert("You need at least one setup.") return end
    UI:Confirm("Delete the setup '" .. cur .. "'?", function() S:RotDeleteProfile(cur) end, "Delete")
  end)
  delB:SetPoint("LEFT", renB, "RIGHT", 4, 0)

  local names = { "Priority", "Opener", "Procs", "Buffs", "Dispels", "Health", "Look" }
  -- Buffs moved out to BuffWatcher: its tab is left out (pane numbers stay the same)
  local TABS = { 1, 2, 3, 5, 6, 7 }
  local tabNames = {}
  for k, i in ipairs(TABS) do tabNames[k] = names[i] end
  for i = 1, #names do
    panes[i] = CreateFrame("Frame", nil, win)
    panes[i]:SetPoint("TOPLEFT", 0, -102); panes[i]:SetPoint("BOTTOMRIGHT", 0, 30)
    panes[i]:Hide()
  end
  win.tabs = UI:SubTabs(win, tabNames, function(k) local i = TABS[k]; for j, pn in ipairs(panes) do pn:SetShown(i == j) end S:RefreshRotational() end)
  win.tabs:SetPoint("TOPLEFT", 14, -70); win.tabs:SetSize(W - 28, 24)
  panes[1]:Show()
  local p = P()
  buildPriority(p); buildOpener(); buildProcs(); buildDispels(); buildHealth(); buildLook()
  win.status = UI:Text(win, "", "small"); win.status:SetPoint("BOTTOMLEFT", 16, 10); win.status:SetWidth(W - 32); win.status:SetJustifyH("LEFT")
  win:HookScript("OnShow", function() scanButtons(); S:RefreshRotational() end)
end

function S:ShowRotational()
  if S.ROTATIONAL_REMOVED then S:Print("Rotational has been removed from Command Center for now.") return end
  if not win then build() end
  win:Show(); win:Raise()
  S:RefreshRotational()
end
function S:HideRotational() if win then win:Hide() end end

function S:RotSpy(sec)
  sec = tonumber(sec) or 60
  spyUntil = now() + sec
  spyLog = {}
  G().rotSpy = spyLog
  S:RotSpyScanBuffs(true)
  S:Print(string.format("Recording everything the game reports for |cffffd100%d seconds|r - fight now (let Windfury proc a few times), then |cffffd100/reload|r.", sec))
  C_Timer.After(sec, function() S:Print("Recording finished - type |cffffd100/reload|r so it's saved.") end)
end
S:AddCommand("rotspy", "[seconds]", "Rotational: record what the game reports (to set up a new proc)", function(arg) S:RotSpy(arg) end)
S:AddCommand("rotation", "", "Rotational: set up your rotation and make the right button glow", function() S:ShowRotational() end)
