-- Summoner (warlocks): announce that summons are up, collect everyone who types 123,
-- click a name to target them and cast Ritual of Summoning. Each name shows how it
-- went: summoning, waiting for them to accept, accepted (tick) or declined (cross -
-- click again to retry). Shows your soul shards and how many still need a summon.
--
-- Accept / decline: Command Center users' clients report it to the warlock. For people without
-- it the warlock's client watches for them turning up nearby; after two minutes
-- with no sign of them the summon counts as declined.
local _, S = ...
local UI = S.UI

local PREFIX = "STNKSUM"
local SUMMON_SPELL = 698                       -- Ritual of Summoning
local SHARD_ITEM = 6265                        -- Soul Shard
local OFFER_TIME = 120                         -- how long a summon waits for an answer
local MAX_ROWS = 40
local ROW_H = 26

local function isWarlock() local _, c = UnitClass("player"); return c == "WARLOCK" end
S.IsWarlock = isWarlock
local function combat() return InCombatLockdown and InCombatLockdown() end
local function spellName()
  if C_Spell and C_Spell.GetSpellName then local n = C_Spell.GetSpellName(SUMMON_SPELL); if n then return n end end
  if GetSpellInfo then local n = GetSpellInfo(SUMMON_SPELL); if n then return n end end
  return "Ritual of Summoning"
end
local function groupChannel()
  if IsInRaid and IsInRaid() then return "RAID" end
  if IsInGroup and IsInGroup() then return "PARTY" end
end
local function say(text)
  local ch = groupChannel()
  if not ch then S:Print("You're not in a group - nobody to tell.") return false end
  SendChatMessage(text, ch)
  return true
end
local function shortName(full) return (Ambiguate and Ambiguate(full or "", "none")) or (full or ""):gsub("%-.*", "") end

function S:SoulShards()
  local n = GetItemCount and GetItemCount(SHARD_ITEM) or 0
  if (n or 0) == 0 and UnitPower then
    local pt = (Enum and Enum.PowerType and Enum.PowerType.SoulShards) or 7
    local p = UnitPower("player", pt)
    if p and p > 0 then n = p end
  end
  return n or 0
end

-- the group unit for a name ("raid7", "party2"), if they're in the group
local function unitFor(name)
  local short = shortName(name)
  if IsInRaid and IsInRaid() then
    for i = 1, (GetNumGroupMembers and GetNumGroupMembers() or 0) do
      local u = "raid" .. i
      local n, r = UnitName(u)
      if n and (n == short or (r and r ~= "" and (n .. "-" .. r) == name)) then return u end
    end
  else
    for i = 1, 4 do
      local u = "party" .. i
      local n, r = UnitName(u)
      if n and (n == short or (r and r ~= "" and (n .. "-" .. r) == name)) then return u end
    end
  end
end

---------------------------------------------------------------------------
-- The list
---------------------------------------------------------------------------
-- state: "waiting" (said 123), "casting", "offered" (summon sent), "accepted", "declined"
local list = {}
local byName = {}
local listening = false
local current                                  -- entry being summoned right now
local win, refresh

local function need()
  local n = 0
  for _, e in ipairs(list) do if e.state ~= "accepted" then n = n + 1 end end
  return n
end
S.SummonNeedCount = need

local function add(name)
  local e = byName[name]
  if e then
    if e.state == "accepted" or e.state == "declined" then e.state = "waiting"; e.at = GetTime() end
  else
    e = { name = name, state = "waiting", at = GetTime() }
    byName[name] = e
    list[#list + 1] = e
  end
  if refresh then refresh() end
  return e
end
local function remove(e)
  byName[e.name] = nil
  for i, o in ipairs(list) do if o == e then table.remove(list, i) break end end
  if current == e then current = nil end
  if refresh then refresh() end
end
function S:SummonList() return list end
function S:SummonAdd(name) return add(name) end
local function setState(e, st)
  if not e then return end
  e.state, e.at = st, GetTime()
  if refresh then refresh() end
end

---------------------------------------------------------------------------
-- 123 in chat
---------------------------------------------------------------------------
local CHAT = { "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING",
  "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER", "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_WHISPER" }
local function heard(_, msg, sender)
  if not listening or type(msg) ~= "string" or not sender then return end
  if issecretvalue and (issecretvalue(msg) or issecretvalue(sender)) then return end
  if not msg:find("%f[%d]123%f[%D]") then return end
  if shortName(sender) == UnitName("player") then return end
  if not unitFor(sender) then return end         -- only people in your group can be summoned
  add(sender)
  if win and not win:IsShown() and not combat() then S:ShowSummoner() end
end
for _, ev in ipairs(CHAT) do S:On(ev, heard) end

function S:SummonReady()
  if not groupChannel() then UI:Alert("Join a group or raid first - summons go to people in your group.") return end
  listening = true
  say("Summons are up! Type 123 in chat if you need a summon.")
  if refresh then refresh() end
end
function S:SummonStop()
  listening = false
  if refresh then refresh() end
end
S.SummonListening = function() return listening end

---------------------------------------------------------------------------
-- Casting: the row buttons are secure "/target name, /cast Ritual of Summoning"
-- macros. The chat line and the state go out from the click just before.
---------------------------------------------------------------------------
local function beforeCast(e)
  if not e then return end
  if S:SoulShards() <= 0 then S:Print("|cffff5555You have no soul shards.|r") end
  current = e
  setState(e, "casting")
  say("Summoning " .. shortName(e.name) .. ", clicky clicky!")
end

local function mine(unit, castGUID, spellID)
  return unit == "player" and (spellID == SUMMON_SPELL or (spellID and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID) == spellName())
    or (spellID and GetSpellInfo and GetSpellInfo(spellID) == spellName()))
end
-- the ritual is done: the summon now waits on the other player
local function offered()
  if current and current.state == "casting" then
    local u = unitFor(current.name)
    current.wasNear = u and (CheckInteractDistance and CheckInteractDistance(u, 4)) or false
    setState(current, "offered")
  end
  current = nil
end
S:On("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, guid, id) if mine(unit, guid, id) then offered() end end)
S:On("UNIT_SPELLCAST_CHANNEL_STOP", function(_, unit, guid, id) if mine(unit, guid, id) then offered() end end)
local function failed(_, unit, guid, id)
  if mine(unit, guid, id) and current and current.state == "casting" then setState(current, "declined"); current.failed = true; current = nil end
end
S:On("UNIT_SPELLCAST_INTERRUPTED", failed)
S:On("UNIT_SPELLCAST_FAILED", failed)

-- people without Command Center: did they turn up? did the offer run out?
local watch = CreateFrame("Frame")
local acc = 0
watch:SetScript("OnUpdate", function(_, el)
  acc = acc + el
  if acc < 1 then return end
  acc = 0
  local changed = false
  for _, e in ipairs(list) do
    if e.state == "offered" then
      local u = unitFor(e.name)
      local near = u and CheckInteractDistance and CheckInteractDistance(u, 4)
      if near and not e.wasNear then e.state = "accepted"; changed = true
      elseif GetTime() - (e.at or 0) > OFFER_TIME then e.state = "declined"; changed = true end
    elseif e.state == "casting" and GetTime() - (e.at or 0) > 30 then
      e.state = "declined"; changed = true                       -- the cast never happened
    end
  end
  if changed and refresh then refresh() end
  if win and win:IsShown() and win.shards then win.shards:SetText(S:SoulShards()) end
end)

-- Command Center users tell the warlock what they did with the summon
local function tell(code)
  local ch = groupChannel()
  if not ch then return end
  if S.Comm and S.Comm.SendRaw then S.Comm:SendRaw(PREFIX, code, ch)
  elseif C_ChatInfo and C_ChatInfo.SendAddonMessage then C_ChatInfo.SendAddonMessage(PREFIX, code, ch)
  elseif SendAddonMessage then SendAddonMessage(PREFIX, code, ch) end
end
local function hook(tbl, name, code)
  if tbl and type(tbl[name]) == "function" then hooksecurefunc(tbl, name, function() tell(code) end) end
end
hook(C_SummonInfo, "ConfirmSummon", "A")
hook(C_SummonInfo, "CancelSummon", "D")
hook(_G, "ConfirmSummon", "A")
hook(_G, "CancelSummon", "D")
S:On("CONFIRM_SUMMON", function() tell("O") end)

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
elseif RegisterAddonMessagePrefix then RegisterAddonMessagePrefix(PREFIX) end
S:On("CHAT_MSG_ADDON", function(_, prefix, msg, _, sender)
  if prefix ~= PREFIX or not sender then return end
  local e = byName[sender] or byName[shortName(sender)]
  if not e then
    for _, o in ipairs(list) do if shortName(o.name) == shortName(sender) then e = o end end
  end
  if not e then return end
  if msg == "A" then setState(e, "accepted")
  elseif msg == "D" then setState(e, "declined")
  elseif msg == "O" and (e.state == "casting" or e.state == "waiting") then e.wasNear = false; setState(e, "offered") end
end)

---------------------------------------------------------------------------
-- The panel
---------------------------------------------------------------------------
local STATE = {
  waiting  = { "|cffffd100needs a summon|r", nil },
  casting  = { "|cffb48cffsummoning...|r", "Interface\\Icons\\Spell_Shadow_Twilight" },
  offered  = { "|cffb48cffwaiting for them to accept|r", "Interface\\Icons\\Spell_Shadow_Twilight" },
  accepted = { "|cff55ff55here|r", "check" },
  declined = { "|cffff5555declined - click to try again|r", "close" },
}

local pendingAttr = false
local function setRowAttr(r, e)
  if combat() then pendingAttr = true return end
  if e then
    r:SetAttribute("type1", "macro")
    r:SetAttribute("macrotext1", "/target " .. e.name .. "\n/cast " .. spellName())
  else
    r:SetAttribute("type1", nil); r:SetAttribute("macrotext1", nil)
  end
end

local function makeRow(i)
  local r = CreateFrame("Button", "CC_SummonRow" .. i, win.list, "SecureActionButtonTemplate")
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  r:SetHeight(ROW_H - 2)
  r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H); r:SetPoint("RIGHT", win.list, "RIGHT", 0, 0)
  r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints()
  UI:Skin(r.bg, function(self, th) self:SetColorTexture(th.field[1], th.field[2], th.field[3], 0.9) end)
  r.hl = r:CreateTexture(nil, "HIGHLIGHT"); r.hl:SetAllPoints(); r.hl:SetColorTexture(1, 1, 1, 0.06)
  r.mark = r:CreateTexture(nil, "ARTWORK"); r.mark:SetSize(16, 16); r.mark:SetPoint("LEFT", 6, 0)
  r.name = UI:Text(r, ""); r.name:SetPoint("LEFT", 28, 0); r.name:SetWidth(130); r.name:SetJustifyH("LEFT")
  r.state = UI:Text(r, "", "small"); r.state:SetPoint("LEFT", 162, 0); r.state:SetPoint("RIGHT", -6, 0); r.state:SetJustifyH("LEFT")
  r:HookScript("PreClick", function(self, btn)
    if btn == "LeftButton" and self.entry then beforeCast(self.entry) end
  end)
  r:HookScript("OnClick", function(self, btn)
    if btn == "RightButton" and self.entry then
      local e = self.entry
      UI:Menu(self, {
        { text = "Mark as here", func = function() setState(e, "accepted") end },
        { text = "Remove from the list", func = function() remove(e) end },
      })
    end
  end)
  r:SetScript("OnEnter", function(self)
    if not self.entry then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(shortName(self.entry.name), 1, 0.82, 0)
    GameTooltip:AddLine("Click: target and summon", 1, 1, 1)
    GameTooltip:AddLine("Right-click: mark as here / remove", 0.7, 0.7, 0.7)
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return r
end

refresh = function()
  if not win then return end
  local th = UI:Theme()
  for i = 1, MAX_ROWS do
    local r = win.rows[i]
    local e = list[i]
    if r.entry ~= e or pendingAttr then setRowAttr(r, e) end
    r.entry = e
    if e then
      local col = S.ColorName and S:ColorName(e.name) or shortName(e.name)
      r.name:SetText(col)
      local st = STATE[e.state] or STATE.waiting
      r.state:SetText(st[1])
      local icon = st[2]
      if icon == "check" or icon == "close" then
        r.mark:SetTexture(UI.ICON[icon]); r.mark:SetTexCoord(0, 1, 0, 1)
        if icon == "check" then r.mark:SetVertexColor(0.33, 1, 0.33) else r.mark:SetVertexColor(1, 0.33, 0.33) end
        r.mark:Show()
      elseif icon then
        r.mark:SetTexture(icon); r.mark:SetTexCoord(0.07, 0.93, 0.07, 0.93); r.mark:SetVertexColor(1, 1, 1); r.mark:Show()
      else r.mark:Hide() end
      r:SetAlpha(1)
    end
    if not combat() then r:SetShown(e ~= nil) else r:SetAlpha(e and 1 or 0) end
  end
  if not combat() then pendingAttr = false end
  win.shards:SetText(S:SoulShards())
  local n = need()
  win.need:SetText(n)
  win.empty:SetShown(#list == 0)
  win.empty:SetText(listening and "Waiting for people to type 123..." or "Press |cffffd100Ready for summons|r to tell the group.")
  win.ready:SetText(listening and "Announce again" or "Ready for summons")
  win.listenDot:SetVertexColor(listening and th.live[1] or 0.4, listening and th.live[2] or 0.4, listening and th.live[3] or 0.4)
end
S:On("PLAYER_REGEN_ENABLED", function() if pendingAttr and refresh then refresh() end end)
S:On("BAG_UPDATE_DELAYED", function() if win and win:IsShown() then win.shards:SetText(S:SoulShards()) end end)
S:On("GROUP_ROSTER_UPDATE", function()
  -- people who left the group can't be summoned any more
  local gone = false
  for i = #list, 1, -1 do if not unitFor(list[i].name) then byName[list[i].name] = nil; table.remove(list, i); gone = true end end
  if not groupChannel() then listening = false end
  if refresh then refresh() end
end)

local function build()
  win = UI:Window("CC_Summoner", "Summoner", 380, 440)
  win:SetFrameStrata("HIGH")
  -- secure name buttons live in here: never let Escape close it in combat
  if UISpecialFrames then
    for i = #UISpecialFrames, 1, -1 do if UISpecialFrames[i] == "CC_Summoner" then table.remove(UISpecialFrames, i) end end
  end
  -- top: shards and how many still need summoning
  local shardIcon = win:CreateTexture(nil, "ARTWORK"); shardIcon:SetSize(30, 30); shardIcon:SetPoint("TOPLEFT", 16, -40)
  shardIcon:SetTexture("Interface\\Icons\\INV_Misc_Gem_Amethyst_02"); shardIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  win.shards = win:CreateFontString(nil, "OVERLAY"); win.shards:SetFont("Fonts\\FRIZQT__.TTF", 22, "OUTLINE")
  win.shards:SetPoint("LEFT", shardIcon, "RIGHT", 8, 0)
  local sl = UI:Text(win, "soul shards", "small"); sl:SetPoint("LEFT", win.shards, "RIGHT", 6, -1)
  local needIcon = win:CreateTexture(nil, "ARTWORK"); needIcon:SetSize(30, 30); needIcon:SetPoint("TOPLEFT", 196, -40)
  needIcon:SetTexture("Interface\\Icons\\Spell_Shadow_Twilight"); needIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  win.need = win:CreateFontString(nil, "OVERLAY"); win.need:SetFont("Fonts\\FRIZQT__.TTF", 22, "OUTLINE")
  win.need:SetPoint("LEFT", needIcon, "RIGHT", 8, 0)
  local nl = UI:Text(win, "need a summon", "small"); nl:SetPoint("LEFT", win.need, "RIGHT", 6, -1)
  UI:Skin(win.shards, function(self, th) self:SetTextColor(0.7, 0.55, 1) end)
  UI:Skin(win.need, function(self, th) self:SetTextColor(th.gold[1], th.gold[2], th.gold[3]) end)

  win.ready = UI:PrimaryButton(win, "Ready for summons", 200, 26, function() S:SummonReady() end,
    "Tells your group: summons are up, type 123 in chat if you need one.")
  win.ready:SetPoint("TOPLEFT", 16, -82)
  win.listenDot = win:CreateTexture(nil, "OVERLAY"); win.listenDot:SetTexture(UI.MEDIA .. "UI\\disc"); win.listenDot:SetSize(10, 10)
  win.listenDot:SetPoint("LEFT", win.ready, "RIGHT", 10, 0)
  local stop = UI:Button(win, "Stop", 60, 26, function() S:SummonStop() end, "Stop adding people who type 123.")
  stop:SetPoint("LEFT", win.listenDot, "RIGHT", 8, 0)
  local clear = UI:Button(win, "Clear", 60, 26, function()
    if combat() then S:Print("Clear the list after combat.") return end
    wipe(list); wipe(byName); current = nil; refresh()
  end, "Empty the list.")
  clear:SetPoint("LEFT", stop, "RIGHT", 4, 0)

  local hint = UI:Text(win, "|cffaaaaaaClick a name to target and summon. Right-click for more.|r", "small")
  hint:SetPoint("TOPLEFT", 16, -118)
  win.list = CreateFrame("Frame", nil, win)
  win.list:SetPoint("TOPLEFT", 14, -138); win.list:SetPoint("BOTTOMRIGHT", -14, 14)
  win.empty = UI:Text(win.list, "", "small", "CENTER"); win.empty:SetPoint("TOP", 0, -30); win.empty:SetWidth(320)
  win.rows = {}
  for i = 1, MAX_ROWS do win.rows[i] = makeRow(i); win.rows[i]:Hide() end
  win:HookScript("OnShow", function() refresh() end)
end

local function fitHeight()
  if not win or combat() then return end
  local visible = math.max(6, math.min(#list, MAX_ROWS))
  win:SetHeight(138 + visible * ROW_H + 18)
end
local oldRefresh = refresh
refresh = function() oldRefresh(); fitHeight() end

function S:ShowSummoner()
  if combat() then S:Print("The Summoner can't be opened or closed in combat.") return end
  if not win then build() end
  win:Show(); win:Raise()
  refresh()
end
function S:HideSummoner()
  if not win then return end
  if combat() then S:Print("The Summoner can't be opened or closed in combat.") return end
  win:Hide()
end

S:AddCommand("summon", "", "Summoner (warlocks): collect 123s and summon with one click", function()
  if not isWarlock() and not S:IsOfficer() then S:Print("The Summoner is for warlocks.") return end
  S:ShowSummoner()
end)
