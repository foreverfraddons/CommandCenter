-- Messenger: your in-game whispers as chats - bubbles, day separators, times,
-- sounds and pop-ups. Whispers are kept only on this computer.
local _, S = ...
if S.ModuleRev then S:ModuleRev("Messenger", 1) end
local UI = S.UI

local setState          -- (marks a whisper read / deletes it - set up with the whisper log below)
function S:MailBody(rec)
  if not rec then return "" end
  -- a whisper the game flagged as potentially inappropriate, still hidden
  if rec.censored and not rec.placeholder then
    return "|cffffd100Message from " .. S.Short(rec.who or "?") .. " is potentially inappropriate.|r |cff66bbff[Show message]|r"
  end
  return rec.plain or ""
end
function S:MailRead(id) return true end
function S:Inbox() return {} end
function S:SentMail() return {} end
function S:UnreadMail() return S.UnreadWhispers and S:UnreadWhispers() or 0 end

---------------------------------------------------------------------------
-- Conversations: one chat thread per person you whisper with
---------------------------------------------------------------------------
local function oneLine(text, n)
  text = (text or ""):gsub("[\r\n]+", " ")
  if #text <= n then return text end
  -- cut without breaking a UTF-8 character
  return (text:sub(1, n):gsub("[\192-\255][\128-\191]*$", "")) .. "..."
end
S.MailPreview = oneLine

local function realSubject(m)
  local s = m.subject
  if not s or s == "" or s == "(no subject)" then return nil end
  return s
end

-- { { with = name, msgs = { oldest .. newest }, last = msg, unread = n }, ... } newest chat first
-- conversations you removed from the inbox: key -> when (their history is kept)
local function hiddenTable()
  local g = S.db.global
  g.hiddenConvos = type(g.hiddenConvos) == "table" and g.hiddenConvos or {}
  return g.hiddenConvos
end
local function hkey(name) return S.Short(name or ""):lower() end
-- openers offered for chats started from the service finder: main -> { text, at }
local svcAsk = {}
function S.MsgServiceAsk(name, text) if name then svcAsk[name] = text and { text = text, at = GetTime() } or nil end end
-- built at most once per frame (lots of things ask for it while drawing)
local convCache = {}
function S.MsgInvalidate() wipe(convCache) end
function S:Conversations(includeHidden)
  local ck = includeHidden and "all" or "inbox"
  local now = GetTime and GetTime() or 0
  if convCache[ck] and convCache.t == now then return convCache[ck] end
  if convCache.t ~= now then wipe(convCache); convCache.t = now end
  local out = S.MsgBuildConversations(includeHidden)
  convCache[ck] = out
  return out
end
function S.MsgBuildConversations(includeHidden)
  local by = {}
  -- in-game whispers
  if S.WhisperThreads then
    for other, list in pairs(S:WhisperThreads()) do
      local c = by[other]
      if not c then c = { with = other, msgs = {}, unread = 0 }; by[other] = c end
      for i, e in ipairs(list) do
        e._key = "w:" .. other .. ":" .. i
        e.unread = e.to == S.me and not e.read or false
        c.msgs[#c.msgs + 1] = e
        if e.unread then c.unread = c.unread + 1 end
      end
    end
  end
  -- example chats from the guided tour
  for name, d in pairs(S.demoConvos or {}) do
    by[name] = { with = name, msgs = d.msgs, unread = 0, demo = true }
  end
  -- alts go into their main's conversation
  if S.MainOf then
    local merged = {}
    -- a main may be saved as "Name" or with another realm spelling than its own
    -- whisper thread: use the thread's spelling so it doesn't split in two
    local byShort = {}
    for name in pairs(by) do
      local k = (name:match("^[^-]+") or name):lower()
      if byShort[k] == nil then byShort[k] = name else byShort[k] = false end
    end
    local function spell(main)
      if type(main) ~= "string" or by[main] then return main end
      local k = (main:match("^[^-]+") or main):lower()
      return byShort[k] or main
    end
    for name, c in pairs(by) do
      local main = c.demo and name or spell(S.MainOf(name))
      local m = merged[main]
      if not m then m = { with = main, msgs = {}, unread = 0, demo = c.demo, chars = {} }; merged[main] = m end
      for _, e in ipairs(c.msgs) do m.msgs[#m.msgs + 1] = e end
      m.unread = m.unread + (c.unread or 0)
      m.chars[name] = true
    end
    by = merged
  end
  local out = {}
  for _, c in pairs(by) do
    table.sort(c.msgs, function(a, b)
      if (a.time or 0) ~= (b.time or 0) then return (a.time or 0) < (b.time or 0) end
      if (a._t or 0) ~= (b._t or 0) then return (a._t or 0) < (b._t or 0) end
      -- same second: the order they arrived in
      local ia = tonumber(type(a.id) == "string" and a.id:match("%.(%d+)$") or 0) or 0
      local ib = tonumber(type(b.id) == "string" and b.id:match("%.(%d+)$") or 0) or 0
      return ia < ib
    end)
    c.last = c.msgs[#c.msgs]
    -- reply to the character that whispered last (an alt, maybe)
    for i = #c.msgs, 1, -1 do local e = c.msgs[i]; if e.who ~= S.me then c.replyTo = e.who break end end
    if not c.replyTo then for i = #c.msgs, 1, -1 do local e = c.msgs[i]; if e.to and e.to ~= S.me then c.replyTo = e.to break end end end
    out[#out + 1] = c
  end
  -- removed from the inbox: stays out until something newer happens
  if not includeHidden then
    local hid = hiddenTable()
    for i = #out, 1, -1 do
      local h = hid[hkey(out[i].with)]
      local last = out[i].last
      if h ~= nil then
        -- hidden until a message newer than the one that was last when you removed it
        local same = (type(h) == "table" and last and h.id == (last.id or last._key)) or (type(h) == "number" and (last and last.time or 0) <= h)
        if same then table.remove(out, i) end
      end
    end
  end
  local function pinned(c) local p = S.MsgPerson and S:MsgPerson(c.with); return p and p.pinned and 1 or 0 end
  table.sort(out, function(a, b)
    local pa, pb = pinned(a), pinned(b)
    if pa ~= pb then return pa > pb end
    return (a.last.time or 0) > (b.last.time or 0)
  end)
  return out
end

function S:Conversation(name)
  if S.MainOf then name = S.MainOf(name) end
  local list = S:Conversations(true)
  for _, c in ipairs(list) do if c.with == name then return c end end
  -- same character, other spelling (with / without realm)
  if type(name) == "string" then
    local k = (name:match("^[^-]+") or name):lower()
    local hit
    for _, c in ipairs(list) do
      if type(c.with) == "string" and (c.with:match("^[^-]+") or c.with):lower() == k then
        if hit then return nil end   -- two people with that name: don't guess
        hit = c
      end
    end
    return hit
  end
end
-- who a message in this conversation goes to: the character that whispered last
function S.MsgReplyTarget(name)
  local c = S:Conversation(name)
  local rt = (c and c.replyTo) or name
  -- that character is offline but another of theirs is on: talk to that one
  if S.OnlineState and S.OnlineState(rt) ~= true and S.OnlineChar then
    local oc = S.OnlineChar(name)
    if oc then rt = oc end
  end
  return rt
end

function S:DeleteConversation(name) end

local function dayLabel(t)
  local now = S.now()
  local today = date("%Y%m%d", now)
  local d = date("%Y%m%d", t)
  if d == today then return "Today " .. date("%H:%M", t) end
  if d == date("%Y%m%d", now - 86400) then return "Yesterday " .. date("%H:%M", t) end
  if now - t < 6 * 86400 then return date("%A %H:%M", t) end
  return date("%b %d, %H:%M", t)
end

local function shortAgo(t)
  local d = S.now() - (t or 0)
  if d < 60 then return "now" end
  if d < 3600 then return math.floor(d / 60) .. "m" end
  if d < 86400 then return math.floor(d / 3600) .. "h" end
  if d < 7 * 86400 then return math.floor(d / 86400) .. "d" end
  return date("%b %d", t)
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local win, active, topic, filter = nil, nil, nil, ""
local RAIL = 30           -- the icon strip down the left edge (contacts, services)
local WIN_W, WIN_H = 780 + RAIL, 540
local LIST_W = 260
local ROW_H = 50
local BUBBLE_MAX = 300

local function setAvatar(t, name)
  if S.SetAvatar and name then return S.SetAvatar(t, name) end
  local m = S:Member(name)
  local cf = m and m.classFile
  local co = cf and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[cf]
  if co then
    t:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles"); t:SetTexCoord(co[1], co[2], co[3], co[4])
  else
    t:SetTexture("Interface\\Icons\\INV_Misc_GroupNeedMore"); t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  end
end
S.MsgSetAvatar = setAvatar
local function setDot(d, name)
  -- a person counts as online if any of their characters (main or alt) is
  local st = (S.PersonOnline and S.PersonOnline(name)) or (S.OnlineState and S.OnlineState(name))
  if st == nil and S:IsOnline(name) then st = true end
  if st == nil then d:Hide() return end    -- don't know: no dot rather than a wrong one
  d:SetTexture(st and "Interface\\FriendsFrame\\StatusIcon-Online" or "Interface\\FriendsFrame\\StatusIcon-Offline"); d:Show()
end
local function bubbleLook(f, c, tc) S.MsgBubbleLook(f, c, tc) end

local renderList, renderChat
local pending = false
local function refreshSoon()
  if not win or not win:IsShown() or pending then return end
  pending = true
  C_Timer.After(0.05, function() pending = false; if win:IsShown() then renderList(); renderChat(false) end end)
end

local function openChat(name, scroll)
  if name and not (S.demoConvos and S.demoConvos[name]) and not name:find("-", 1, true) and S.Full then name = S.Full(name) end
  active = (name and S.MainOf) and S.MainOf(name) or name
  if active and S.UnhideConversation then S:UnhideConversation(active) end
  if win.input then win.input:SetText("") end
  renderList(); renderChat(true)
  if active then win.input:SetFocus(); if S.AutoLookup then S:AutoLookup(active) end end
end

-- conversation list -------------------------------------------------------
local rows = {}
local function getRow(i)
  if rows[i] then return rows[i] end
  local r = CreateFrame("Button", nil, win.listChild)
  r:SetSize(LIST_W - 30, ROW_H)
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  r.sel = r:CreateTexture(nil, "BACKGROUND"); r.sel:SetAllPoints(); r.sel:SetColorTexture(1, 1, 1, 0.10); r.sel:Hide()
  r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  r.av = r:CreateTexture(nil, "ARTWORK"); r.av:SetSize(36, 36); r.av:SetPoint("LEFT", 6, 0)
  r.dot = r:CreateTexture(nil, "OVERLAY"); r.dot:SetSize(12, 12); r.dot:SetPoint("BOTTOMRIGHT", r.av, "BOTTOMRIGHT", 2, -2)
  r.name = UI:Text(r, "", "normal"); r.name:SetPoint("TOPLEFT", r.av, "TOPRIGHT", 8, -2); r.name:SetPoint("RIGHT", -40, 0); r.name:SetWordWrap(false)
  r.prev = UI:Text(r, "", "small"); r.prev:SetPoint("BOTTOMLEFT", r.av, "BOTTOMRIGHT", 8, 2); r.prev:SetPoint("RIGHT", -24, 0); r.prev:SetWordWrap(false)
  r.when = UI:Text(r, "", "small", "RIGHT"); r.when:SetPoint("TOPRIGHT", -6, -9); r.when:SetTextColor(0.6, 0.6, 0.6)
  r.badge = UI:Badge(r, 16); r.badge:SetPoint("BOTTOMRIGHT", -6, 8)
  r.pin = r:CreateTexture(nil, "OVERLAY"); r.pin:SetSize(12, 12); r.pin:SetPoint("TOPRIGHT", r.av, "TOPRIGHT", 3, 3)
  r.pin:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_1"); r.pin:Hide()
  -- swipe left to delete: drag the row left past the red strip and let go
  r.swipeBg = r:CreateTexture(nil, "BACKGROUND", nil, -7); r.swipeBg:SetAllPoints(); r.swipeBg:Hide()
  r.del = CreateFrame("Frame", nil, win.listChild)
  r.del:SetFrameLevel(math.max(0, r:GetFrameLevel() - 1))
  r.del.bg = r.del:CreateTexture(nil, "BACKGROUND"); r.del.bg:SetAllPoints(); r.del.bg:SetColorTexture(0.75, 0.12, 0.12, 0.9)
  r.del.txt = UI:Text(r.del, "Delete", "normal", "RIGHT"); r.del.txt:SetPoint("RIGHT", -12, 0); r.del.txt:SetTextColor(1, 1, 1)
  r.del:Hide()
  local SWIPE = 70
  local function cursorX() local x = GetCursorPosition(); return x / (r:GetEffectiveScale() or 1) end
  local function settle(self, dx)
    self:ClearAllPoints(); self:SetPoint("TOPLEFT", dx, self.baseY or 0)
  end
  local function endSwipe(self)
    self:SetScript("OnUpdate", nil)
    local dx = self.swipeDx or 0
    self.swipeDx = nil
    settle(self, 0); self.swipeBg:Hide(); self.del:Hide()
    if dx <= -SWIPE and self.who then
      local who = self.who
      UI:Confirm("Remove " .. (S.DisplayName and S.DisplayName(who) or S.Short(who)) .. " from your inbox?\n|cff888888Your chat history is kept - it comes back when you open the chat again or they message you.|r", function()
        S:DeleteConversation(who); if active == who then active = nil end; refreshSoon()
      end, "Remove")
    end
  end
  r:HookScript("OnMouseDown", function(self, button)
    if button ~= "LeftButton" then return end
    self.swiped = false
    local x0 = cursorX()
    self:SetScript("OnUpdate", function(f)
      if not IsMouseButtonDown("LeftButton") then endSwipe(f) return end
      local dx = math.min(0, math.max(-(LIST_W - 60), cursorX() - x0))
      if dx < -8 then
        f.swiped = true
        if not f.del:IsShown() then
          local th = UI:Theme()
          f.swipeBg:SetColorTexture(th.bg[1], th.bg[2], th.bg[3], 1); f.swipeBg:Show()
          f.del:ClearAllPoints(); f.del:SetPoint("TOPLEFT", 0, f.baseY or 0); f.del:SetSize(f:GetWidth(), f:GetHeight()); f.del:Show()
        end
        f.del.txt:SetText(dx <= -SWIPE and "Let go to delete" or "Delete")
        f.del.bg:SetColorTexture(dx <= -SWIPE and 0.9 or 0.6, 0.12, 0.12, 0.95)
      end
      f.swipeDx = dx
      if f.swiped then settle(f, dx) end
    end)
  end)
  r:HookScript("OnMouseUp", function(self) if self:GetScript("OnUpdate") then endSwipe(self) end end)
  r:SetScript("OnClick", function(self, button)
    if self.swiped then self.swiped = false return end   -- that was a swipe, not a click
    if button == "RightButton" then
      local who = self.who
      UI:Menu(nil, {
        { text = S.Short(who), title = true },
        { text = "View profile", func = function() if S.ShowProfile then S:ShowProfile(who) end end },
        { text = (S:MsgPerson(who) or {}).pinned and "Unpin from top" or "Pin to top", func = function()
          S:SetMsgPerson(who, "pinned", not (S:MsgPerson(who) or {}).pinned or "default"); refreshSoon()
        end },
        { text = "Set nickname...", func = function() C_Timer.After(0, function() if S.AskNickname then S:AskNickname(who) end end) end },
        { text = "Set as alt of...", tip = "Mark this character as an alt of their main - it then shows under the main's name.",
          func = function() C_Timer.After(0, function() if S.AskAltOf then S:AskAltOf(who) end end) end },
        { text = "Unlink an alt...", disabled = not (S.AltsOf and #S.AltsOf(who) > 0), func = function()
          C_Timer.After(0, function()
            local items = { { text = "Unlink which alt?", title = true } }
            for _, a in ipairs(S.AltsOf(who)) do
              local nm = a:sub(1, 1):upper() .. a:sub(2)
              items[#items + 1] = { text = nm, func = function() S.SetAltOf(nm, nil) end }
            end
            UI:Menu(nil, items)
          end)
        end },
        { text = (S.IsContact and S.IsContact(who)) and "Remove from contacts" or "Add to contacts",
          func = function() if S.ToggleContact then S.ToggleContact(who) end end },
        { text = "Services...", tip = "What they offer - professions, summons, portals, food & water. Shows as icons after their name.",
          func = function() C_Timer.After(0, function() if S.ShowServices then S:ShowServices(who) end end) end },
        { text = "Add friend", disabled = S.IsFriend and S:IsFriend(who), func = function() S:AddFriend(who) end },
        { text = "Whisper in game chat", disabled = S.PersonOnline and S.PersonOnline(who) == false, func = function() S:OpenWhisper(S.MsgReplyTarget(who)) end },
        { text = "Invite to group", disabled = S.PersonOnline and S.PersonOnline(who) == false, func = function() S:PartyInvite(S.MsgReplyTarget(who)) end },
        { text = "Alerts for " .. S.Short(who) .. "...", func = function() C_Timer.After(0, function() S:MsgPersonMenu(who) end) end },
        { text = "|cffff5555Clear chat history|r", func = function() C_Timer.After(0, function() S:AskClearConversation(who) end) end },
      })
      return
    end
    openChat(self.who)
    if S.LookupPending then S:LookupPending() end   -- a click: the game allows a /who now
  end)
  rows[i] = r
  return r
end

local RMASK = "Interface\\AddOns\\CommandCenter\\Media\\UI\\rmask5"
local RRING = "Interface\\AddOns\\CommandCenter\\Media\\UI\\rring5"
local BUB, GAP = 40, 12
local function contactBubble(i)
  local strip = win.strip
  strip.bubs = strip.bubs or {}
  local b = strip.bubs[i]
  if b then return b end
  b = CreateFrame("Button", nil, strip.inner)
  b:SetSize(BUB, BUB)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b.av = b:CreateTexture(nil, "ARTWORK"); b.av:SetAllPoints()
  if b.CreateMaskTexture then
    local ok, m = pcall(b.CreateMaskTexture, b)
    if ok and m then m:SetAllPoints(); pcall(m.SetTexture, m, RMASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE"); pcall(b.av.AddMaskTexture, b.av, m) end
  end
  b.ring = b:CreateTexture(nil, "OVERLAY", nil, 5); b.ring:SetAllPoints(); b.ring:SetTexture(RRING)
  b.dot = b:CreateTexture(nil, "OVERLAY", nil, 7); b.dot:SetSize(11, 11); b.dot:SetPoint("BOTTOMRIGHT", 1, -1)
  b.badge = UI:Badge(b, 14); b.badge:SetPoint("TOPRIGHT", 4, 4)
  b.label = UI:Text(strip.inner, "", "small", "CENTER"); b.label:SetWidth(BUB + GAP - 2); b.label:SetWordWrap(false)
  b.label:SetPoint("TOP", b, "BOTTOM", 0, -2)
  -- dock style: grows a little under the mouse
  b:SetScript("OnEnter", function(self)
    self:SetSize(BUB + 6, BUB + 6)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine(S:ColorName(self.who) .. (S.ServiceIcons and S.ServiceIcons(self.who) or ""))
    local c = S:Conversation(self.who)
    if c and c.last then GameTooltip:AddLine(oneLine(S:MailBody(c.last), 50), 0.8, 0.8, 0.8) end
    GameTooltip:AddLine("Click to chat - right-click for more - wheel scrolls", 0.5, 0.5, 0.5)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function(self) self:SetSize(BUB, BUB); GameTooltip:Hide() end)
  b:SetScript("OnClick", function(self, button)
    if self.add then if S.AskAddContact then S:AskAddContact() end return end
    if button == "RightButton" then
      local who = self.who
      UI:Menu(nil, {
        { text = S.DisplayName and S.DisplayName(who) or S.Short(who), title = true },
        { text = "Open chat", func = function() openChat(who) end },
        { text = "View profile", func = function() if S.ShowProfile then S:ShowProfile(who) end end },
        { text = "Services...", func = function() C_Timer.After(0, function() if S.ShowServices then S:ShowServices(who) end end) end },
        { text = "|cffff5555Remove from contacts|r", func = function() S.RemoveContact(who) end },
      })
      return
    end
    openChat(self.who)
    if S.LookupPending then S:LookupPending() end
  end)
  strip.bubs[i] = b
  return b
end
local function renderContacts()
  local strip = win.strip
  if not strip then return end
  -- only contacts who are around right now (online, or just talked)
  local list = {}
  for _, who in ipairs(S.Contacts and S.Contacts() or {}) do
    local rt = S.MsgReplyTarget and S.MsgReplyTarget(who)
    if (S.PersonOnline and S.PersonOnline(who)) or (S.OnlineState and rt and S.OnlineState(rt)) then list[#list + 1] = who end
  end
  local n = #list
  for i = 1, n + 1 do
    local b = contactBubble(i)
    b:ClearAllPoints(); b:SetPoint("CENTER", strip.inner, "TOPLEFT", 6 + BUB / 2 + (i - 1) * (BUB + GAP), -4 - BUB / 2)
    if i <= n then
      local who = list[i]
      b.who, b.add = who, nil
      setAvatar(b.av, who)
      if b.av.__cls then b.av.__cls:Hide() end
      b.label:SetText(S:ColorName(who))
      local st = S.PersonOnline and S.PersonOnline(who)
      if st == nil then b.dot:Hide() else
        b.dot:SetTexture(st and "Interface\\FriendsFrame\\StatusIcon-Online" or "Interface\\FriendsFrame\\StatusIcon-Offline"); b.dot:Show()
      end
      local c = S:Conversation(who)
      b.badge:SetCount(c and c.unread or 0)
      b.ring:SetVertexColor(who == active and 1 or 0.6, who == active and 0.82 or 0.6, who == active and 0 or 0.6)
    else
      -- the last bubble adds a contact
      b.who, b.add = nil, true
      b.av:SetTexture("Interface\\PaperDollInfoFrame\\Character-Plus"); b.av:SetTexCoord(0, 1, 0, 1)
      if b.av.__cls then b.av.__cls:Hide() end
      b.label:SetText("|cff888888Add|r")
      b.dot:Hide(); b.badge:SetCount(0); b.ring:SetVertexColor(0.5, 0.5, 0.5)
    end
    b:Show(); b.label:Show()
  end
  for i = n + 2, #(strip.bubs or {}) do strip.bubs[i]:Hide(); strip.bubs[i].label:Hide() end
  if not strip.none then
    strip.none = UI:Text(strip.inner, "", "small"); strip.none:SetWidth(170); strip.none:SetJustifyH("LEFT")
  end
  strip.none:ClearAllPoints(); strip.none:SetPoint("LEFT", strip.bubs[n + 1], "RIGHT", 10, 0)
  local total = S.Contacts and #S.Contacts() or 0
  strip.none:SetText(n == 0 and (total == 0 and "|cff888888Add contacts - they show here when they're online.|r" or "|cff888888No contacts online right now.|r") or "")
  strip.none:SetShown(n == 0)
  local w = 12 + (n + 1) * (BUB + GAP)
  strip.inner:SetWidth(w)
  strip.maxOff = math.max(0, w - strip:GetWidth())
  if strip.off > strip.maxOff then strip.off = strip.maxOff; strip.inner:ClearAllPoints(); strip.inner:SetPoint("TOPLEFT", -strip.off, 0) end
end

function renderList()
  renderContacts()
  local convs = S:Conversations()
  local q = filter:lower()
  local shown = {}
  local seenActive = false
  for _, c in ipairs(convs) do
    if q == "" or S.Short(c.with):lower():find(q, 1, true) or (S.DisplayName and S.DisplayName(c.with):lower():find(q, 1, true)) then shown[#shown + 1] = c end
    if c.with == active then seenActive = true end
  end
  -- a brand-new chat (no messages yet) still shows at the top
  if active and not seenActive then table.insert(shown, 1, { with = active, msgs = {}, unread = 0, new = true }) end
  for i, c in ipairs(shown) do
    local r = getRow(i)
    r.who = c.with
    r.baseY = -(i - 1) * ROW_H
    if not r.swipeDx then r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, r.baseY) end
    setAvatar(r.av, c.with); setDot(r.dot, c.with)
    r.name:SetText((c.unread > 0 and "|cffffffff" or "") .. S:ColorName(c.with) .. (S.ServiceIcons and S.ServiceIcons(c.with) or ""))
    if c.new then
      r.prev:SetText("|cff888888New conversation|r"); r.when:SetText("")
    else
      local l = c.last
      local body = oneLine(S:MailBody(l), 40)
      local pre = l.who == S.me and "You: " or ""
      r.prev:SetText((c.unread > 0 and "|cffffffff" or "|cff999999") .. pre .. body .. "|r")
      r.when:SetText(shortAgo(l.time))
    end
    r.badge:SetCount(c.unread)
    local pp = S:MsgPerson(c.with); r.pin:SetShown(pp and pp.pinned and true or false)
    r.sel:SetShown(c.with == active)
    r:Show()
  end
  for i = #shown + 1, #rows do rows[i]:Hide() end
  win.listChild:SetHeight(math.max(10, #shown * ROW_H))
  win.listEmpty:SetShown(#shown == 0)
  local unread = S:UnreadMail()
  win.title:SetText(unread > 0 and ("Messenger (" .. unread .. ")") or "Messenger")
end

-- chat bubbles -------------------------------------------------------------
local bubbles, seps = {}, {}
local function getBubble(i)
  if bubbles[i] then return bubbles[i] end
  local b = UI:Panel(win.chatChild, 40, 24)
  b:EnableMouse(true)
  b.fs = UI:Text(b, "", "normal"); b.fs:SetPoint("TOPLEFT", 10, -7); b.fs:SetWordWrap(true); b.fs:SetSpacing(2)
  b.fs:SetTextColor(1, 1, 1)
  b.av = b:CreateTexture(nil, "ARTWORK"); b.av:SetSize(24, 24); b.av:SetPoint("BOTTOMRIGHT", b, "BOTTOMLEFT", -4, 0)
  b:SetScript("OnEnter", function(self)
    if not self.msg then return end
    GameTooltip:SetOwner(self, self.mine and "ANCHOR_LEFT" or "ANCHOR_RIGHT")
    GameTooltip:AddLine(S.date(self.msg.time, "%A %B %d, %Y at %H:%M"), 1, 1, 1)
    if realSubject(self.msg) then GameTooltip:AddLine("About: " .. realSubject(self.msg), 1, 0.82, 0) end
    if self.msg.whisper then GameTooltip:AddLine("In-game whisper", 1, 0.5, 1) end
    if self.msg.who and self.msg.who ~= S.me and active and self.msg.who ~= active then GameTooltip:AddLine("From " .. S.Short(self.msg.who), 1, 0.82, 0) end
    GameTooltip:AddLine("Right-click for options", 0.5, 0.5, 0.5)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  if b.SetHyperlinksEnabled then
    b:SetHyperlinksEnabled(true)
    b:SetScript("OnHyperlinkClick", function(self, link, txt, button)
      if type(link) == "string" and link:find("^censoredmessage") then S.MsgReveal(self.msg) return end
      if SetItemRef then pcall(SetItemRef, link, txt, button) end
    end)
  end
  b:SetScript("OnMouseUp", function(self, button)
    if button == "LeftButton" and self.msg and self.msg.censored then S.MsgReveal(self.msg) return end
    if button ~= "RightButton" or not self.msg then return end
    local m = self.msg
    UI:Menu(nil, {
      { text = "Message", title = true },
      { text = "Copy text", func = function() UI:CopyBox("Copy message", S:MailBody(m)) end },
      { text = "Delete for me", func = function() setState(m._key, { read = true, del = true }) end },
    })
  end)
  bubbles[i] = b
  return b
end
local function getSep(i)
  if seps[i] then return seps[i] end
  local t = UI:Text(win.chatChild, "", "small", "CENTER"); t:SetTextColor(0.6, 0.6, 0.6)
  seps[i] = t
  return t
end

function renderChat(toBottom)
  for _, b in ipairs(bubbles) do b:Hide() end
  for _, t in ipairs(seps) do t:Hide() end
  win.status:Hide()
  local hasChat = active ~= nil
  win.header:SetShown(hasChat); win.footer:SetShown(hasChat); win.chatEmpty:SetShown(not hasChat)
  if not hasChat then return end

  -- colors
  local st = S:MsgCfg()
  win.right:SetBackdropColor(st.bg[1], st.bg[2], st.bg[3], 0.95)
  -- header
  setAvatar(win.hAv, active); setDot(win.hDot, active)
  local pm = S:MsgPerson(active)
  win.hBell.icon:SetDesaturated(pm and pm.notify == "off" or false)
  win.hBell.icon:SetAlpha((pm and pm.notify == "off") and 0.4 or 1)
  win.hName:SetText(S:ColorName(active) .. (S.ServiceIcons and S.ServiceIcons(active, 16) or ""))
  win.hName:SetFontObject(UI.fLarge)
  if (win.hName:GetStringWidth() or 0) > (win.hName:GetWidth() or 999) then win.hName:SetFontObject(UI.fNormal) end
  local on = true
  local pi = S.PlayerInfo and S.PlayerInfo((S.MsgReplyTarget and S.MsgReplyTarget(active)) or active)
  local bits = {}
  if pi then
    if pi.online == true then bits[#bits + 1] = "|cff55ff55Online|r" elseif pi.online == false then bits[#bits + 1] = "|cff999999Offline|r" end
    if pi.level and pi.level ~= 0 then bits[#bits + 1] = "Level " .. pi.level .. (pi.class and (" " .. pi.class) or "") end
    if pi.online and pi.area then bits[#bits + 1] = pi.area end
    if pi.bnet and pi.tag then bits[#bits + 1] = "|cff00aaff" .. pi.tag .. "|r" end
  end
  local rt = S.MsgReplyTarget and S.MsgReplyTarget(active)
  if rt and rt ~= active then table.insert(bits, 1, "|cffffd100on " .. S.Short(rt) .. "|r") end
  win.hStatus:SetText(#bits > 0 and table.concat(bits, "  |cff666666-|r  ") or "|cff888888Whispers|r")
  win.hWhisper:SetEnabled(on); win.hInvite:SetEnabled(on)
  win.hFriend:SetShown(not (S.IsFriend and S:IsFriend(active)))

  local c = S:Conversation(active)
  local msgs = c and c.msgs or {}
  local W = win.chatChild:GetWidth()
  local y, prevTime, nb, ns = 8, nil, 0, 0
  for i, m in ipairs(msgs) do
    if m.unread then
      setState(m._key, { read = true }); m.unread = false
      if m.whisper then m.read = true; if S.ReadNotif then S:ReadNotif("wh:" .. (m.id or "")) end end
      if S.ReadNotif then S:ReadNotif("mail:" .. m._key) end
    end
    local newRun = not prevTime or (m.time or 0) - prevTime > 900
    if newRun then
      ns = ns + 1
      local t = getSep(ns); t:ClearAllPoints(); t:SetPoint("TOP", win.chatChild, "TOP", 0, -y); t:SetText(dayLabel(m.time or 0)); t:Show()
      y = y + 20
    end
    local mine = m.who == S.me
    nb = nb + 1
    local b = getBubble(nb)
    b.msg, b.mine = m, mine
    local subj = realSubject(m)
    local text = (subj and ("> " .. subj .. "\n") or "") .. S:MailBody(m)
    b.fs:SetWidth(BUBBLE_MAX); b.fs:SetText(text)
    local tw = math.min(BUBBLE_MAX, math.ceil(b.fs:GetStringWidth() or 0) + 2)
    if subj then tw = BUBBLE_MAX end
    tw = math.max(tw, 20)
    b.fs:SetWidth(tw)
    local th = b.fs:GetStringHeight() or 12
    b:SetSize(tw + 20, th + 14)
    local st = S:MsgCfg()
    bubbleLook(b, mine and st.mine or st.theirs, mine and st.mineText or st.theirsText)
    b:ClearAllPoints()
    -- their avatar sits beside the last bubble of a run
    local nextM = msgs[i + 1]
    local lastOfRun = not nextM or nextM.who ~= m.who or (nextM.time or 0) - (m.time or 0) > 900
    if mine then
      b:SetPoint("TOPRIGHT", win.chatChild, "TOPRIGHT", -8, -y); b.av:Hide()
      if b.av.__cls then b.av.__cls:Hide() end    -- the small class badge goes with the picture
    else
      b:SetPoint("TOPLEFT", win.chatChild, "TOPLEFT", 36, -y)
      if lastOfRun then setAvatar(b.av, m.who); b.av:Show()
      else b.av:Hide(); if b.av.__cls then b.av.__cls:Hide() end end
    end
    b:Show()
    y = y + th + 14 + (lastOfRun and 8 or 2)
    prevTime = m.time or 0
  end

  -- "Seen" / "Sent" under my newest message
  local last = msgs[#msgs]
  if last and last.who == S.me then
    local rs = S:Get("mailst", last._key .. "|" .. last.to)
    local txt
    if rs and rs.read then txt = "Seen " .. S.Ago(rs._t)
    elseif on then txt = "Sent"
    else txt = "Sent - delivered when " .. S.Short(active) .. " logs in" end
    win.status:ClearAllPoints(); win.status:SetPoint("TOPRIGHT", win.chatChild, "TOPRIGHT", -10, -(y - 4))
    win.status:SetText(txt); win.status:Show()
    y = y + 14
  end
  if #msgs == 0 then
    ns = ns + 1
    local t = getSep(ns); t:ClearAllPoints(); t:SetPoint("TOP", win.chatChild, "TOP", 0, -40)
    t:SetText("Say hi to " .. S.Short(active) .. "!\n|cff777777They need to be online to get a whisper.|r"); t:Show()
  end
  local viewH = win.chatScroll:GetHeight() or 300
  win.chatChild:SetHeight(math.max(y + 6, viewH))
  if toBottom then
    local function bottom() win.chatScroll:SetVerticalScroll(math.max(0, (win.chatChild:GetHeight() or 0) - viewH)) end
    bottom(); C_Timer.After(0, bottom)
  end
  -- smart suggestions (invite, sign up, remind me...) from what was just said
  if S.SmartActions and win.smart then
    local acts, sig = {}, nil
    if not (S.demoConvos and S.demoConvos[active]) then acts, sig = S:SmartActions(active, msgs) end
    local ask = svcAsk[active]
    if ask and GetTime() - ask.at < 1800 then
      table.insert(acts, 1, { label = ask.text, wide = true, tip = "Click to put it in your message box - then Enter to send (or change it first).",
        run = function() svcAsk[active] = nil; if S.MsgInsert then S.MsgInsert(ask.text) end end })
    end
    win.smart.sig = sig
    for _, b in ipairs(win.smart.btns) do b:Hide() end
    local x = 22
    for i, a in ipairs(acts) do
      local b = win.smart.btns[i]
      if not b then
        b = UI:Button(win.smart, "", 100, 20)
        win.smart.btns[i] = b
      end
      b:SetText(a.label)
      local w = math.min(a.wide and 400 or 220, math.max(70, ((b.fs and b.fs:GetStringWidth()) or (#a.label * 6)) + 22))
      b:SetSize(w, 20)
      b:ClearAllPoints(); b:SetPoint("LEFT", win.smart, "LEFT", x, 0)
      x = x + w + 4
      b:SetScript("OnClick", function() a.run(); renderChat(false) end)
      b:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine(a.label, 1, 0.82, 0); if a.tip then GameTooltip:AddLine(a.tip, 1, 1, 1, true) end; GameTooltip:Show() end)
      b:SetScript("OnLeave", function() GameTooltip:Hide() end)
      b:Show()
    end
    win.smart:SetShown(#acts > 0)
  end
  -- topic chip ("About: ...") for messages started from another feature
  if topic then win.topic.text:SetText("|cffffd100About:|r " .. topic); win.topic:Show() else win.topic:Hide() end
end

local function send()
  if not active then return end
  local body = S.Trim(win.input:GetText() or "")
  if body == "" then return end
  local demo = S.demoConvos and S.demoConvos[active]
  if demo then                                   -- tour example chat: stays on your screen only
    demo.msgs[#demo.msgs + 1] = { who = S.me, to = active, time = S.now(), plain = body, _key = "demo" .. #demo.msgs + 1 }
    S.MsgInvalidate()
    win.input:SetText(""); renderList(); renderChat(true)
    if S.TourEvent then S:TourEvent("demoSent", active) end
    return
  end
  svcAsk[active] = nil
  S:SendWhisper(S.MsgReplyTarget(active), body)
  topic = nil
  win.input:SetText("")
  renderList(); renderChat(true)
  win.input:SetFocus()
end

local function build()
  win = UI:Window("CC_Messenger", "Messenger", WIN_W, WIN_H)
  win:HookScript("OnMouseDown", function() if S.LookupPending then S:LookupPending() end end)
  -- left: conversations ------------------------------------------------------
  local left = UI:Panel(win, LIST_W, WIN_H - 56, { 0.03, 0.03, 0.04, 0.9 })
  left:SetPoint("TOPLEFT", 16 + RAIL, -36)
  win.search = UI:Edit(left, LIST_W - 16, 22, "Search or type a name")
  win.search:SetPoint("TOPLEFT", 8, -8)
  win.search:HookScript("OnTextChanged", function(self)
    filter = S.Trim(self:GetText() or "")
    renderList()
    if S.MsgSuggest then S.MsgSuggest(filter) end
  end)
  win.search:SetScript("OnEnterPressed", function(self)
    local q = S.Trim(self:GetText() or "")
    if q == "" then self:ClearFocus() return end
    local who = S.MsgPickName and S.MsgPickName(q)
    if not who then return end            -- (told you why; keeps what you typed)
    self:SetText(""); filter = ""; self:ClearFocus()
    if S.MsgSuggest then S.MsgSuggest("") end
    openChat(who)
  end)
  win.search:SetScript("OnArrowPressed", function(_, key) if S.MsgSuggestMove then S.MsgSuggestMove(key == "UP" and -1 or 1) end end)
  win.search:SetScript("OnEscapePressed", function(self) self:ClearFocus(); if S.MsgSuggest then S.MsgSuggest("") end end)
  win.search:HookScript("OnEditFocusLost", function() C_Timer.After(0.2, function() if S.MsgSuggest and not win.search:HasFocus() then S.MsgSuggest("") end end) end)
  -- contacts: bubbles across the top, most recently active first; wheel scrolls sideways
  local STRIP_H = 66
  local strip = CreateFrame("Frame", nil, left)
  strip:SetPoint("TOPLEFT", 6, -34); strip:SetSize(LIST_W - 12, STRIP_H)
  if strip.SetClipsChildren then strip:SetClipsChildren(true) end
  strip.inner = CreateFrame("Frame", nil, strip); strip.inner:SetSize(10, STRIP_H); strip.inner:SetPoint("TOPLEFT", 0, 0)
  strip.off = 0
  strip:EnableMouseWheel(true)
  strip:SetScript("OnMouseWheel", function(self, d)
    self.off = math.max(0, math.min(self.maxOff or 0, self.off - d * 50))
    self.inner:ClearAllPoints(); self.inner:SetPoint("TOPLEFT", -self.off, 0)
  end)
  local line = UI:Line(left); line:SetPoint("TOPLEFT", 8, -34 - STRIP_H - 2); line:SetPoint("TOPRIGHT", -8, -34 - STRIP_H - 2)
  win.strip = strip
  local sf, child = UI:Scroll(left, LIST_W - 4, WIN_H - 56 - 44 - STRIP_H - 4)
  sf:SetPoint("TOPLEFT", 4, -38 - STRIP_H - 4)
  win.listChild = child
  win.listEmpty = UI:Text(left, "|cff888888No conversations yet.\nType a name in the search box above\nand press Enter to start one.|r", "small", "CENTER")
  win.listEmpty:SetPoint("TOP", 0, -150)

  -- right: chat ---------------------------------------------------------------
  local right = UI:Panel(win, WIN_W - LIST_W - 40 - RAIL, WIN_H - 56, { 0.06, 0.06, 0.07, 0.92 })
  right:SetPoint("TOPLEFT", left, "TOPRIGHT", 8, 0)
  win.right = right
  local RW = WIN_W - LIST_W - 40 - RAIL
  -- left edge: contacts and service finder (each opens a side drawer)
  win.railContacts = UI:IconButton(win, "roster", 28, nil, function() S:MsgDrawer("contacts") end)
  win.railContacts:SetPoint("TOPLEFT", 10, -40)
  UI:Tip(win.railContacts, "Contacts", "All your contacts - online or not. Search, open a chat, add more.")
  win.railServices = UI:IconButton(win, "craft", 28, nil, function() S:MsgDrawer("services") end)
  win.railServices:SetPoint("TOP", win.railContacts, "BOTTOM", 0, -6)
  UI:Tip(win.railServices, "Find a service", "People you've marked with services - blacksmiths, enchanters, summons, portals... Filter and search.")

  -- cog: message colors & alerts
  local cog = UI:IconButton(win, "settings", 26, "Message settings", function() S:ShowMessengerSettings() end)
  cog:SetPoint("TOPRIGHT", -38, -4)
  win.cog = cog

  win.header = CreateFrame("Frame", nil, right); win.header:SetPoint("TOPLEFT", 4, -4); win.header:SetPoint("TOPRIGHT", -4, -4); win.header:SetHeight(48)
  win.hAv = win.header:CreateTexture(nil, "ARTWORK"); win.hAv:SetSize(38, 38); win.hAv:SetPoint("LEFT", 6, 0)
  win.hDot = win.header:CreateTexture(nil, "OVERLAY"); win.hDot:SetSize(13, 13); win.hDot:SetPoint("BOTTOMRIGHT", win.hAv, "BOTTOMRIGHT", 2, -2)
  win.hName = UI:Text(win.header, "", "large"); win.hName:SetPoint("TOPLEFT", win.hAv, "TOPRIGHT", 10, -1)
  win.hStatus = UI:Text(win.header, "", "small"); win.hStatus:SetPoint("BOTTOMLEFT", win.hAv, "BOTTOMRIGHT", 10, 2)
  win.hProfile = UI:Button(win.header, "Profile", 60, 22, function() if active and S.ShowProfile then S:ShowProfile(active) end end)
  win.hProfile:SetPoint("RIGHT", -4, 0)
  win.hFriend = UI:Button(win.header, "+Friend", 62, 22, function() if active and S.AddFriend then S:AddFriend(active) end end, "Add them to your friends list.")
  win.hFriend:SetPoint("RIGHT", win.hProfile, "LEFT", -4, 0)
  win.hInvite = UI:Button(win.header, "Invite", 54, 22, function() if active then S:PartyInvite(active) end end, "Invite to your group (online only).")
  win.hInvite:SetPoint("RIGHT", win.hFriend, "LEFT", -4, 0)
  win.hWhisper = UI:Button(win.header, "Whisper", 62, 22, function() if active then S:OpenWhisper(active) end end, "Whisper in normal game chat (online only).")
  win.hWhisper:SetPoint("RIGHT", win.hInvite, "LEFT", -4, 0)
  win.hBell = UI:IconButton(win.header, "bell", 26, nil, function(self) if active then S:MsgPersonMenu(active, self) end end)
  win.hBell:SetPoint("RIGHT", win.hWhisper, "LEFT", -6, 0)
  -- name and status stop before the buttons (long names get "..." instead of running under them)
  win.hName:SetPoint("RIGHT", win.hBell, "LEFT", -8, 0); win.hName:SetWordWrap(false); win.hName:SetJustifyH("LEFT")
  win.hStatus:SetPoint("RIGHT", win.hBell, "LEFT", -8, 0); win.hStatus:SetWordWrap(false); win.hStatus:SetJustifyH("LEFT")
  local hAvBtn = CreateFrame("Button", nil, win.header); hAvBtn:SetAllPoints(win.hAv)
  hAvBtn:SetScript("OnClick", function() if active and S.PickAvatar then S:PickAvatar(active) end end)
  UI:Tip(hAvBtn, "Change picture", "Click to pick any icon in the game for this person.")
  UI:Tip(win.hBell, "Alerts for this person", function()
    return active and ("Now: " .. (S:MsgPersonSummary(active) or "my defaults") .. "\nClick to change pop-ups and sound for just this person.") or ""
  end)
  local hl = UI:Line(right); hl:SetPoint("TOPLEFT", 6, -54); hl:SetPoint("TOPRIGHT", -6, -54)

  local chatH = WIN_H - 56 - 54 - 52
  local csf, cchild = UI:Scroll(right, RW - 8, chatH)
  csf:SetPoint("TOPLEFT", 4, -58)
  cchild:SetWidth(RW - 8 - 24)
  win.chatScroll, win.chatChild = csf, cchild
  win.status = UI:Text(cchild, "", "small", "RIGHT"); win.status:SetTextColor(0.6, 0.6, 0.6)

  win.footer = CreateFrame("Frame", nil, right); win.footer:SetPoint("BOTTOMLEFT", 4, 4); win.footer:SetPoint("BOTTOMRIGHT", -4, 4); win.footer:SetHeight(48)
  win.topic = CreateFrame("Button", nil, win.footer); win.topic:SetPoint("TOPLEFT", 6, 0); win.topic:SetSize(RW - 30, 16)
  win.topic.text = UI:Text(win.topic, "", "small"); win.topic.text:SetPoint("LEFT")
  win.topic.x = UI:Text(win.topic, "|cff888888(click to remove)|r", "small"); win.topic.x:SetPoint("LEFT", win.topic.text, "RIGHT", 6, 0)
  win.topic:SetScript("OnClick", function() topic = nil; win.topic:Hide() end)
  win.topic:Hide()
  win.sweep = UI:IconButton(win.footer, "sweep", 24, nil, function() if active then S:AskClearConversation(active) end end)
  win.sweep:SetPoint("BOTTOMLEFT", 6, 4)
  UI:Tip(win.sweep, "Clear chat", "Wipe the chat history with this person (asks first).")
  win.input = UI:Edit(win.footer, RW - 130, 24, "Aa  - type a message, Enter to send", function() send() end)
  -- a whisper can be 255 bytes at most (the game drops longer ones); links count in full
  win.input:SetPoint("BOTTOMLEFT", 36, 4); win.input:SetMaxLetters(255)
  if win.input.SetMaxBytes then win.input:SetMaxBytes(256) end
  win.input:SetScript("OnEnterPressed", function() send() end)
  local sb = UI:PrimaryButton(win.footer, "Send", 76, 24, send)
  sb:SetPoint("BOTTOMRIGHT", -6, 4)
  win.sendBtn = sb

  -- smart suggestion buttons, just above the message box
  win.smart = CreateFrame("Frame", nil, right)
  win.smart:SetPoint("BOTTOMLEFT", win.footer, "TOPLEFT", 2, 2); win.smart:SetPoint("BOTTOMRIGHT", win.footer, "TOPRIGHT", -2, 2); win.smart:SetHeight(24)
  win.smart:SetFrameLevel(right:GetFrameLevel() + 10)
  win.smart.bg = win.smart:CreateTexture(nil, "BACKGROUND"); win.smart.bg:SetAllPoints(); win.smart.bg:SetColorTexture(0, 0, 0, 0.55)
  win.smart.icon = UI:Icon(win.smart, "check", 14, "OVERLAY"); win.smart.icon:SetPoint("LEFT", 4, 0)
  UI:Skin(win.smart.icon, function(self, th) self:SetVertexColor(UI.C(th.gold)) end)
  win.smart.close = UI:CloseIcon(win.smart, 16); win.smart.close:SetPoint("RIGHT", -4, 0)
  win.smart.close:SetScript("OnClick", function() if active and win.smart.sig then S:DismissSmart(active, win.smart.sig) end; win.smart:Hide() end)
  UI:Tip(win.smart.close, "Hide suggestions", "Until the next new message.")
  win.smart.btns = {}
  win.smart:Hide()
  win.chatEmpty = UI:Text(right, "|cffffd100Messenger|r\n\n|cffaaaaaaYour whispers show up here as chats.\nPick one on the left, or type a name in the search box to whisper someone.\nWhispers are only kept on this computer.|r", "normal", "CENTER")
  win.chatEmpty:SetPoint("CENTER")
  win:HookScript("OnShow", function() renderList(); renderChat(true) end)
  -- remembers where you put it and how big (streamer mode: tuck it behind your webcam)
  local g = S.db.global
  if type(g.msgrPos) == "table" and g.msgrPos.x then win:ClearAllPoints(); win:SetPoint("CENTER", UIParent, "BOTTOMLEFT", g.msgrPos.x, g.msgrPos.y) end
  win:SetScale(g.msgrScale or 1)
  win:HookScript("OnDragStop", function(self)
    local x, y = self:GetCenter()
    if x then local sc = self:GetScale() or 1; g.msgrPos = { x = x * sc, y = y * sc } end
  end)
  local grip = CreateFrame("Button", nil, win)
  grip:SetSize(16, 16); grip:SetPoint("BOTTOMRIGHT", -3, 3); grip:SetFrameLevel(win:GetFrameLevel() + 20)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  UI:Tip(grip, "Resize", "Drag to make the Messenger window bigger or smaller.")
  grip:SetScript("OnMouseDown", function(self)
    local cx = GetCursorPosition()
    self.start = { x = cx, scale = win:GetScale() or 1 }
  end)
  grip:SetScript("OnMouseUp", function(self)
    self.start = nil
    local x, y = win:GetCenter()
    if x then local sc = win:GetScale() or 1; g.msgrPos = { x = x * sc, y = y * sc } end
  end)
  grip:SetScript("OnUpdate", function(self)
    if not self.start then return end
    local cx = GetCursorPosition()
    local us = UIParent:GetEffectiveScale() or 1
    local dx = (cx - self.start.x) / us
    local sc = math.max(0.35, math.min(1.6, self.start.scale * (1 + dx / WIN_W)))
    -- keep the top-left corner where it is while scaling
    local l, t = win:GetLeft(), win:GetTop()
    local old = win:GetScale() or 1
    win:SetScale(sc); g.msgrScale = sc
    if l and t then win:ClearAllPoints(); win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l * old / sc, t * old / sc) end
  end)
  win.grip = grip
end

-- Open the messenger (optionally on a chat with `who`, with an "About:" topic)
function S:ShowMessenger(who, about)
  if not win then build() end
  if who and not (S.demoConvos and S.demoConvos[who]) and not (S.HasWhisperThread and S:HasWhisperThread(who)) then
    who = S:Resolve(who)
    if who == S.me then S:Print("You can't whisper yourself.") who = nil end
  end
  -- always the full Name-Realm, so it matches the conversation
  if who and not (S.demoConvos and S.demoConvos[who]) and not who:find("-", 1, true) and S.Full then who = S.Full(who) end
  if who then active = S.MainOf and S.MainOf(who) or who; topic = (about and about ~= "") and about or nil
  elseif not active then
    local c = S:Conversations()[1]
    active = c and c.with or nil
  end
  win:Show(); win:Raise()
  renderList(); renderChat(true)
  if active then win.input:SetFocus() else win.search:SetFocus() end
end

-- old entry points keep working
function S:ComposeMail(to, subject) S:ShowMessenger(to, subject) end
function S:ShowMailbox() S:ShowMessenger() end
S:Listen("ROSTER", function() refreshSoon() end)
S:Listen("MSGR_STYLE", function() S.MsgInvalidate(); refreshSoon() end)

S:AddCommand("msg", "[name]", "Messenger: your whispers (or a chat with someone)", function(arg)
  S:ShowMessenger(arg and S.Trim(arg) ~= "" and arg or nil)
end)

---------------------------------------------------------------------------
-- Whispers, kept only on this computer (never shared)
---------------------------------------------------------------------------
local MAX_WHISPERS = 200
local function whisperLog()
  local g = S.db.global
  g.wlog = type(g.wlog) == "table" and g.wlog or {}
  local me = S.me or "?"
  g.wlog[me] = type(g.wlog[me]) == "table" and g.wlog[me] or {}
  return g.wlog[me]
end
local function fullName(n)
  if not n or n == "" then return nil end
  if n:find("-", 1, true) then return n end
  local realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or (S.me and S.me:match("%-(.+)$"))
  return realm and (n .. "-" .. realm) or n
end
function S:WhisperThreads()
  return whisperLog()
end
function S:HasWhisperThread(who) return whisperLog()[fullName(who)] ~= nil end
-- key = "w:<name>:<index>" (see Conversations)
setState = function(key, fields)
  S.MsgInvalidate()
  local other, idx = tostring(key or ""):match("^w:(.+):(%d+)$")
  local list = other and whisperLog()[other]
  local e = list and list[tonumber(idx)]
  if not e then return end
  if fields.del then table.remove(list, tonumber(idx)); if #list == 0 then whisperLog()[other] = nil end
  elseif fields.read then e.read = true end
  refreshSoon()
end
function S:UnreadWhispers()
  local n = 0
  for _, list in pairs(whisperLog()) do for _, e in ipairs(list) do if e.to == S.me and not e.read then n = n + 1 end end end
  return n
end
local wid = 0
local function logWhisper(other, mine, text)
  S.MsgInvalidate()
  local log = whisperLog()
  other = fullName(other)
  local isNew = not log[other]
  log[other] = log[other] or {}
  if isNew and S.AutoLookup then C_Timer.After(0, function() S:AutoLookup(other) end) end
  wid = wid + 1
  local e = { who = mine and S.me or other, to = mine and other or S.me, time = S.now(), plain = text, whisper = true,
    read = mine, id = tostring(S.now()) .. "." .. wid }
  table.insert(log[other], e)
  while #log[other] > MAX_WHISPERS do table.remove(log[other], 1) end
  refreshSoon()
  return e, other
end
-- should a message to this person go out as a whisper?
function S:WhisperInstead() return true end
function S:SendWhisper(who, text)
  local target = who
  -- same realm: the short name is enough
  local realm = S.me and S.me:match("%-(.+)$")
  if realm and who:sub(-#realm - 1) == "-" .. realm then target = S.Short(who) end
  S.msgrSending = (S.msgrSending or 0) + 1
  C_Timer.After(3, function() S.msgrSending = math.max(0, (S.msgrSending or 0) - 1) end)
  if SendChatMessage then SendChatMessage(text, "WHISPER", nil, target) end
end

-- whispers the game flags as "potentially inappropriate": show them when you click,
-- or right away if you turned hiding off (Settings)
local function lineText(id)
  if not id or not C_ChatInfo or not C_ChatInfo.GetChatLineText then return nil end
  local ok, t = pcall(C_ChatInfo.GetChatLineText, id)
  if ok and type(t) == "string" and t ~= "" and not (issecretvalue and issecretvalue(t)) and not t:find("|Hcensoredmessage") then return t end
end
function S.MsgReveal(e, quiet)
  if not e or not e.censored then return end
  if e.lineID and C_ChatInfo and C_ChatInfo.UncensorChatLine then pcall(C_ChatInfo.UncensorChatLine, e.lineID) end
  local function done(t)
    if t then e.plain = t end
    e.censored, e.placeholder = nil, nil
    refreshSoon()
  end
  if not e.placeholder then done() return end      -- we already have the real text
  local t = lineText(e.lineID)
  if t then done(t) return end
  C_Timer.After(0.2, function()
    local t2 = lineText(e.lineID)
    if t2 then done(t2)
    elseif not quiet then UI:Alert("The game didn't hand over the hidden text here - it's shown in your normal chat window now.\n\n(Hidden whispers from before a reload or relog can't be shown.)") end
  end)
end
S:On("CHAT_MSG_WHISPER", function(_, text, sender, ...)
  if not S.db or not sender then return end
  if issecretvalue and (issecretvalue(text) or issecretvalue(sender)) then return end
  local lineID = select(9, ...)
  if issecretvalue and issecretvalue(lineID) then lineID = nil end
  local placeholder = type(text) == "string" and text:find("|Hcensoredmessage") and true or false
  local flagged = placeholder
  if not flagged and lineID and C_ChatInfo and C_ChatInfo.IsChatLineCensored then
    local ok, c = pcall(C_ChatInfo.IsChatLineCensored, lineID); flagged = ok and c == true
  end
  local e, who = logWhisper(sender, false, text or "")
  if flagged then
    e.censored, e.placeholder, e.lineID = true, placeholder, lineID
    if S.db.global.msgHideCensored == false then S.MsgReveal(e, true) end
    if e.censored then text = "(potentially inappropriate - click to show)" end
  end
  if S.MarkHeardFrom then S.MarkHeardFrom(who) end
  local viewing = win and win:IsShown() and active == (S.MainOf and S.MainOf(who) or who)
  if viewing then e.read = true; return end
  local mode = S:MsgNotifyMode(who)
  if mode == "off" then return end
  if S.Notify then
    S:Notify("wh:" .. e.id, { title = (S.DisplayName and S.DisplayName(who) or S.Short(who)) .. " (whisper)", text = S.db.global.streamer and "" or oneLine(text or "", 60),
      icon = "Interface\\Icons\\INV_Letter_02", action = "whisper", arg = who, sound = false })
  end
  if mode == "popup" then S:MsgToast(who, oneLine(text or "", 110), nil) end
  S:PlayMsgSound(S:MsgSoundKey(who))
end)
S:On("CHAT_MSG_WHISPER_INFORM", function(_, text, target)
  if not S.db or not target then return end
  if issecretvalue and (issecretvalue(text) or issecretvalue(target)) then return end
  local _, who = logWhisper(target, true, text or "")
  if S.MarkHeardFrom then S.MarkHeardFrom(who) end   -- the game only confirms a whisper to someone online
  -- whispered from game chat (not the Messenger): open the Messenger on them
  if (S.msgrSending or 0) == 0 and S.db.global.msgOpenOnWhisper ~= false and not (win and win:IsShown() and active == (S.MainOf and S.MainOf(who) or who)) then
    C_Timer.After(0, function() S:ShowMessenger(who) end)
  end
end)
S.notifyActions.whisper = function(who) S:ShowMessenger(who) end

-- optionally keep whispers out of the chat window
local function hideWhisper()
  local g = S.db and S.db.global
  return g and g.msgWhispersHideChat and true or false
end
S.AddChatFilter("CHAT_MSG_WHISPER", function() return hideWhisper() end)
S.AddChatFilter("CHAT_MSG_WHISPER_INFORM", function() return hideWhisper() end)

-- removing a chat from the inbox keeps its history: it comes back when they
-- message you, you message them, or you open the chat again
function S:DeleteConversation(name)
  if not name then return end
  S.MsgInvalidate()
  local main = S.MainOf and S.MainOf(name) or name
  local c = S:Conversation(main)
  local last = c and c.last
  hiddenTable()[hkey(main)] = { id = last and (last.id or last._key) or "", t = S.now() }
  refreshSoon()
end
function S:UnhideConversation(name)
  if not name or not S.db then return end
  S.MsgInvalidate()
  local main = S.MainOf and S.MainOf(name) or name
  hiddenTable()[hkey(main)] = nil
end
-- clearing really forgets the whispers (they only live on this computer)
function S:ClearConversation(name)
  if not name then return end
  S.MsgInvalidate()
  local g = S.db.global
  local log = type(g.wlog) == "table" and g.wlog[S.me]
  if type(log) ~= "table" then return end
  local main = S.MainOf and S.MainOf(name) or name
  for other in pairs(log) do
    if other == name or (S.MainOf and S.MainOf(other) == main) then log[other] = nil end
  end
  refreshSoon()
end


---------------------------------------------------------------------------
-- Search box: name suggestions while you type; Enter opens or starts a chat
---------------------------------------------------------------------------
local function fullNameOf(n)
  if not n or n == "" then return nil end
  if n:find("-", 1, true) then return n end
  local realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or (S.me and S.me:match("%-(.+)$"))
  return realm and (n .. "-" .. realm) or n
end
local function isIgnored(name)
  local short = S.Short(name)
  local CF = C_FriendList
  if CF and CF.IsIgnored then return CF.IsIgnored(name) or CF.IsIgnored(short) end
  if IsIgnored then return IsIgnored(short) or IsIgnored(name) end
  return false
end
-- everyone you could message: chats, guild, friends, your group
local function candidates()
  local seen, out = {}, {}
  local function add(name, src, tag)
    name = fullNameOf(name)
    if name and name ~= S.me and not seen[name] then seen[name] = true; out[#out + 1] = { name = name, src = src, tag = tag } end
  end
  for _, c in ipairs(S:Conversations()) do if not (S.demoConvos and S.demoConvos[c.with]) then add(c.with, "chat") end end
  for _, m in ipairs(S.roster.list or {}) do add(m.name, "guild") end
  local CF = C_FriendList
  local n = CF and CF.GetNumFriends and CF.GetNumFriends() or 0
  for i = 1, n do
    local info = CF.GetFriendInfoByIndex and CF.GetFriendInfoByIndex(i)
    if info and info.name then add(info.name, "friend") end
  end
  -- Battle.net friends playing WoW right now
  for _, f in ipairs(S.BNetWoWFriends and S.BNetWoWFriends() or {}) do if f.wow then add(f.name, "bnet", f.tag) end end
  local g = GetNumGroupMembers and GetNumGroupMembers() or 0
  for i = 1, g do
    local unit = (IsInRaid and IsInRaid()) and ("raid" .. i) or ("party" .. i)
    local nm = GetUnitName and GetUnitName(unit, true)
    if nm then add(nm, "group") end
  end
  return out
end
S.MsgCandidates = candidates

local SRC = { chat = "|cff888888chat|r", guild = "|cff55ff55guild|r", friend = "|cff66aaffriend|r", group = "|cffff9933group|r", bnet = "|cff00aaffBattle.net|r" }
local sugg, suggSel
local function buildSugg()
  sugg = CreateFrame("Frame", nil, win, BackdropTemplateMixin and "BackdropTemplate" or nil)
  sugg:SetPoint("TOPLEFT", win.search, "BOTTOMLEFT", 0, -2); sugg:SetWidth(LIST_W - 16)
  sugg:SetFrameLevel(win:GetFrameLevel() + 30)
  UI:Skin(sugg, function(self, th) UI.Flat(self, th.bg, 0.98, th.gold, 0.8, 1) end)
  sugg.rows = {}
  sugg:Hide()
end
local function suggRow(i)
  local r = sugg.rows[i]
  if r then return r end
  r = CreateFrame("Button", nil, sugg)
  r:SetHeight(24); r:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 24); r:SetPoint("RIGHT", sugg, "RIGHT", -4, 0)
  r.hl = r:CreateTexture(nil, "BACKGROUND"); r.hl:SetAllPoints(); r.hl:SetColorTexture(1, 0.82, 0, 0.12); r.hl:Hide()
  local h = r:CreateTexture(nil, "HIGHLIGHT"); h:SetAllPoints(); h:SetColorTexture(1, 1, 1, 0.06)
  r.av = r:CreateTexture(nil, "ARTWORK"); r.av:SetSize(18, 18); r.av:SetPoint("LEFT", 2, 0)
  r.name = UI:Text(r, "", "normal"); r.name:SetPoint("LEFT", r.av, "RIGHT", 6, 0)
  r.src = UI:Text(r, "", "small", "RIGHT"); r.src:SetPoint("RIGHT", -4, 0)
  r:SetScript("OnClick", function(self)
    win.search:SetText(""); filter = ""
    S.MsgSuggest("")
    if self.who and S.MsgPickName(self.who, true) then openChat(self.who); if S.LookupPending then S:LookupPending() end end
  end)
  sugg.rows[i] = r
  return r
end
-- name suggestions, best first: { { c = {name, src, tag}, score }, ... }
-- (starts-with beats contains; chats, then friends / Battle.net, group, guild; online first;
-- nicknames and BattleTags count too)
function S.MsgRank(q, skip)
  q = (q or ""):lower()
  local hits = {}
  if q == "" then return hits end
  for _, c in ipairs(candidates()) do
    if not (skip and skip(c.name)) then
      local short = S.Short(c.name):lower()
      local full = c.name:lower()
      local nick = S.NicknameOf and S.NicknameOf(c.name)
      nick = nick and nick:lower()
      local starts = short:find(q, 1, true) == 1 or full:find(q, 1, true) == 1 or (nick and nick:find(q, 1, true) == 1)
      local tag = c.tag and c.tag:lower()
      local has = starts or short:find(q, 1, true) or (tag and tag:find(q, 1, true)) or (nick and nick:find(q, 1, true))
      if has then
        local score = (starts and 0 or 10) + (c.src == "chat" and 0 or (c.src == "friend" or c.src == "bnet") and 1 or c.src == "group" and 2 or 3) + ((S.OnlineState and S.OnlineState(c.name)) and 0 or 0.5)
        hits[#hits + 1] = { c = c, score = score }
      end
    end
  end
  table.sort(hits, function(a, b) if a.score ~= b.score then return a.score < b.score end return a.c.name < b.c.name end)
  return hits
end
function S.MsgSrcLabel(c)
  return c.src == "bnet" and c.tag and ("|cff00aaff" .. c.tag:gsub("#%d+$", "") .. "|r") or SRC[c.src] or ""
end
function S.MsgSuggest(q)
  if not win then return end
  if not sugg then buildSugg() end
  q = (q or ""):lower()
  suggSel = nil
  if q == "" then sugg:Hide() return end
  local hits = S.MsgRank(q)
  for _, r in ipairs(sugg.rows) do r:Hide() end
  local n = math.min(6, #hits)
  for i = 1, n do
    local r, c = suggRow(i), hits[i].c
    r.who = c.name
    if S.MsgSetAvatar then S.MsgSetAvatar(r.av, c.name) end
    r.name:SetText(S:ColorName(c.name) .. (S.ServiceIcons and S.ServiceIcons(c.name, 12) or "") .. ((S.OnlineState and S.OnlineState(c.name)) and " |cff55ff55*|r" or ""))
    r.src:SetText(c.src == "bnet" and c.tag and ("|cff00aaff" .. c.tag:gsub("#%d+$", "") .. "|r") or SRC[c.src] or "")
    r.hl:Hide()
    r:Show()
  end
  sugg:SetHeight(n * 24 + 8)
  sugg:SetShown(n > 0)
  sugg.count = n
end
function S.MsgSuggestMove(d)
  if not sugg or not sugg:IsShown() or (sugg.count or 0) == 0 then return end
  suggSel = ((suggSel or 0) + d - 1) % sugg.count + 1
  for i, r in ipairs(sugg.rows) do r.hl:SetShown(i == suggSel) end
end

-- who does "q" mean? nil (and a message) when there's nobody to start a chat with
function S.MsgPickName(q, exact)
  if sugg and sugg:IsShown() and suggSel and sugg.rows[suggSel] and not exact then q = sugg.rows[suggSel].who end
  local ql = (q or ""):lower()
  local hit
  for _, c in ipairs(candidates()) do
    if c.name:lower() == ql or S.Short(c.name):lower() == ql or S.Short(c.name):lower():gsub("%s+", "") == ql:gsub("%s+", "") then
      if hit and hit ~= c.name then hit = nil; break end
      hit = c.name
    end
  end
  hit = hit or S:Resolve(q, true)
  if not hit or hit == S.me or isIgnored(hit) then
    UI:Alert("|cffffd100" .. (q or "") .. "|r\n\nThat player doesn't exist.")
    return nil
  end
  return hit
end

-- put text into the message box (used by smart suggestions)
function S.MsgInsert(text)
  if not win or not win.input then return end
  win.input:SetText(text or ""); win.input:SetFocus()
end

-- Shift-click links (items, spells, quests, achievements...) into the message box.
-- The game sends them to its own chat box (ChatEdit_InsertLink / ChatFrameUtil.InsertLink),
-- which never sees our box, so we hook both and take the link when the Messenger is open
-- on a chat and you're typing in it - or when no game chat box is open to take it.
local function gameChatBox()
  local get = (ChatFrameUtil and ChatFrameUtil.GetActiveWindow) or ChatEdit_GetActiveWindow
  local ok, b = pcall(get or function() end)
  if ok and b and b.IsShown and b:IsShown() then return b end
end
local lastLink, lastLinkAt
function S.MsgInsertLink(link, force)
  if type(link) ~= "string" or link == "" then return false end
  if not win or not win:IsShown() or not win.input or not active then return false end
  local now = GetTime and GetTime() or 0
  if lastLink == link and lastLinkAt == now then return true end   -- both hooks fired
  if not force and not win.input:HasFocus() and gameChatBox() then return false end
  lastLink, lastLinkAt = link, now
  win.input:SetFocus()
  win.input:Insert(link)
  return true
end
local function hookLink(link) S.MsgInsertLink(link) end
if ChatEdit_InsertLink then hooksecurefunc("ChatEdit_InsertLink", hookLink) end
if ChatFrameUtil and ChatFrameUtil.InsertLink then hooksecurefunc(ChatFrameUtil, "InsertLink", hookLink) end
S:Listen("PLAYER_INFO", function() refreshSoon() end)

function S:AskClearConversation(name)
  if not name then return end
  UI:Confirm("Clear your chat history with " .. (S.DisplayName and S.DisplayName(name) or S.Short(name)) .. "?\n|cff888888Every message is wiped for good (only on this computer).|r", function()
    S:ClearConversation(name)
  end, "Clear")
end

---------------------------------------------------------------------------
-- Side drawer (left of the Messenger): all contacts, or the service finder
---------------------------------------------------------------------------
local drawer, dmode
local DW, DROW = 260, 38
local svcFilter = {}          -- service id -> true (show people offering ANY ticked one)
local function drawerRow(i)
  drawer.rows = drawer.rows or {}
  local r = drawer.rows[i]
  if r then return r end
  r = CreateFrame("Button", nil, drawer.child)
  r:SetSize(DW - 40, DROW - 2)
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  r.av = r:CreateTexture(nil, "ARTWORK"); r.av:SetSize(28, 28); r.av:SetPoint("LEFT", 4, 0)
  r.dot = r:CreateTexture(nil, "OVERLAY"); r.dot:SetSize(10, 10); r.dot:SetPoint("BOTTOMRIGHT", r.av, "BOTTOMRIGHT", 2, -2)
  r.name = UI:Text(r, "", "normal"); r.name:SetPoint("TOPLEFT", r.av, "TOPRIGHT", 6, -1); r.name:SetPoint("RIGHT", -4, 0); r.name:SetWordWrap(false)
  r.sub = UI:Text(r, "", "small"); r.sub:SetPoint("BOTTOMLEFT", r.av, "BOTTOMRIGHT", 6, 1); r.sub:SetPoint("RIGHT", -4, 0); r.sub:SetWordWrap(false)
  r:SetScript("OnClick", function(self, button)
    if not self.who then return end
    if button == "RightButton" then
      local who = self.who
      UI:Menu(nil, {
        { text = S.DisplayName and S.DisplayName(who) or S.Short(who), title = true },
        { text = "Open chat", func = function() openChat(who) end },
        { text = "View profile", func = function() if S.ShowProfile then S:ShowProfile(who) end end },
        { text = "Services...", func = function() C_Timer.After(0, function() if S.ShowServices then S:ShowServices(who) end end) end },
        { text = (S.IsContact and S.IsContact(who)) and "Remove from contacts" or "Add to contacts", func = function() S.ToggleContact(who) end },
      })
      return
    end
    if not win:IsShown() then S:ShowMessenger() end
    -- found through the service finder: offer a ready-made opener
    if dmode == "services" and S.ServiceAsk then
      local text = S.ServiceAsk(self.who, svcFilter)
      if text then S.MsgServiceAsk(S.MainOf and S.MainOf(self.who) or self.who, text) end
    end
    openChat(self.who)
    if S.LookupPending then S:LookupPending() end
  end)
  drawer.rows[i] = r
  return r
end
local function drawerMatches(name, q)
  if q == "" then return true end
  if S.Short(name):lower():find(q, 1, true) then return true end
  local d = S.DisplayName and S.DisplayName(name)
  if d and d:lower():find(q, 1, true) then return true end
  return false
end
local function svcText(svc)
  local out = {}
  for _, sv in ipairs(S.SERVICES or {}) do if svc[sv.id] then out[#out + 1] = sv.name:gsub(" %b()", "") end end
  return table.concat(out, ", ")
end
local function renderDrawer()
  if not drawer or not drawer:IsShown() then return end
  local q = (drawer.search:GetText() or ""):lower()
  local items = {}
  if dmode == "contacts" then
    for _, who in ipairs(S.Contacts and S.Contacts() or {}) do
      if drawerMatches(who, q) then items[#items + 1] = { name = who } end
    end
  else
    local anyFilter = next(svcFilter) ~= nil
    for _, p in ipairs(S.ServiceProviders and S.ServiceProviders() or {}) do
      local ok = not anyFilter
      if anyFilter then for id in pairs(svcFilter) do if p.svc[id] then ok = true break end end end
      -- the search box also matches service names ("enchant", "portal")
      local hit = drawerMatches(p.name, q) or (q ~= "" and svcText(p.svc):lower():find(q, 1, true))
      if ok and hit then items[#items + 1] = { name = p.name, svc = p.svc } end
    end
    -- online first, then name
    for _, it in ipairs(items) do it.on = S.PersonOnline and S.PersonOnline(it.name) and 0 or 1 end
    table.sort(items, function(a, b) if a.on ~= b.on then return a.on < b.on end return (S.DisplayName(a.name) or "") < (S.DisplayName(b.name) or "") end)
  end
  for i, it in ipairs(items) do
    local r = drawerRow(i)
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -(i - 1) * DROW)
    r.who = it.name
    setAvatar(r.av, it.name); setDot(r.dot, it.name)
    r.name:SetText(S:ColorName(it.name) .. (S.ServiceIcons and S.ServiceIcons(it.name, 13) or ""))
    if dmode == "contacts" then
      local c = S:Conversation(it.name)
      local oc = S.OnlineChar and S.OnlineChar(it.name)
      if oc and S.Short(oc):lower() ~= S.Short(it.name):lower() then
        r.sub:SetText("|cff55ff55Online on " .. S.Short(oc) .. "|r")
      elseif oc then
        r.sub:SetText(c and c.last and ("|cff55ff55Online|r |cff999999- " .. oneLine(S:MailBody(c.last), 26) .. "|r") or "|cff55ff55Online|r")
      else
        r.sub:SetText(c and c.last and ("|cff999999" .. oneLine(S:MailBody(c.last), 34) .. "|r") or "|cff888888No messages yet|r")
      end
    else
      r.sub:SetText("|cffbbbbbb" .. svcText(it.svc) .. "|r")
    end
    r:Show()
  end
  for i = #items + 1, #(drawer.rows or {}) do drawer.rows[i]:Hide() end
  drawer.child:SetHeight(math.max(10, #items * DROW))
  drawer.empty:SetShown(#items == 0)
  drawer.empty:SetText(dmode == "contacts"
    and (q ~= "" and "|cff888888No contacts match.|r" or "|cff888888No contacts yet.\nAdd some with the button below,\nor right-click a chat > Add to contacts.|r")
    or ((q ~= "" or next(svcFilter)) and "|cff888888Nobody matches.|r" or "|cff888888Nobody marked yet.\nRight-click a chat > Services...\nto note what someone offers.|r"))
  -- filter chips
  for id, chip in pairs(drawer.chips or {}) do
    chip.icon:SetDesaturated(not svcFilter[id]); chip.icon:SetAlpha(svcFilter[id] and 1 or 0.45)
    chip.sel:SetShown(svcFilter[id] and true or false)
  end
end
S.MsgRenderDrawer = renderDrawer
local function buildDrawer()
  drawer = CreateFrame("Frame", "CC_MsgDrawer", win, BackdropTemplateMixin and "BackdropTemplate" or nil)
  drawer:SetSize(DW, WIN_H)
  drawer:SetPoint("TOPRIGHT", win, "TOPLEFT", -4, 0)
  drawer:SetFrameLevel(win:GetFrameLevel() + 5)
  drawer:EnableMouse(true)
  UI:Skin(drawer, function(self, th) UI.Flat(self, th.bg, 0.97, th.gold, 0.8, 1) end)
  drawer.title = UI:Text(drawer, "", "large"); drawer.title:SetPoint("TOPLEFT", 14, -12)
  local close = UI:Button(drawer, "<<", 30, 20, function() drawer:Hide() end, "Fold this away")
  close:SetPoint("TOPRIGHT", -10, -10)
  drawer.search = UI:Edit(drawer, DW - 28, 24, "Search")
  drawer.search:SetPoint("TOPLEFT", 14, -40)
  drawer.search:HookScript("OnTextChanged", function() renderDrawer() end)
  -- service filter chips (6 per row)
  drawer.chipBox = CreateFrame("Frame", nil, drawer)
  drawer.chipBox:SetPoint("TOPLEFT", drawer.search, "BOTTOMLEFT", 0, -8); drawer.chipBox:SetSize(DW - 28, 10)
  drawer.chips = {}
  local per, cs = 7, 30
  for i, sv in ipairs(S.SERVICES or {}) do
    local c = CreateFrame("Button", nil, drawer.chipBox)
    c:SetSize(cs - 4, cs - 4)
    c:SetPoint("TOPLEFT", ((i - 1) % per) * cs, -math.floor((i - 1) / per) * cs)
    c.sel = c:CreateTexture(nil, "BACKGROUND"); c.sel:SetPoint("TOPLEFT", -2, 2); c.sel:SetPoint("BOTTOMRIGHT", 2, -2); c.sel:SetColorTexture(1, 0.82, 0, 0.9)
    c.icon = c:CreateTexture(nil, "ARTWORK"); c.icon:SetAllPoints(); c.icon:SetTexture("Interface\\Icons\\" .. sv.icon); c.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    c:SetScript("OnClick", function() svcFilter[sv.id] = (not svcFilter[sv.id]) or nil; renderDrawer() end)
    UI:Tip(c, sv.name, "Click to filter by this service (pick several to see anyone offering any of them).")
    drawer.chips[sv.id] = c
  end
  drawer.chipBox:SetHeight(math.ceil(#(S.SERVICES or {}) / per) * cs)
  drawer.clearF = UI:Button(drawer, "Clear filters", 100, 20, function() wipe(svcFilter); drawer.search:SetText(""); renderDrawer() end)
  drawer.clearF:SetPoint("TOPLEFT", drawer.chipBox, "BOTTOMLEFT", 0, -4)
  drawer.sf, drawer.child = UI:Scroll(drawer, DW - 8, 100)
  drawer.empty = UI:Text(drawer, "", "small", "CENTER"); drawer.empty:SetWidth(DW - 30)
  drawer.add = UI:Button(drawer, "Add a contact", 120, 22, function() if S.AskAddContact then S:AskAddContact() end end)
  drawer.add:SetPoint("BOTTOM", 0, 12)
end
local function layoutDrawer()
  local svc = dmode == "services"
  drawer.chipBox:SetShown(svc); drawer.clearF:SetShown(svc); drawer.add:SetShown(not svc)
  drawer.title:SetText(svc and "Find a service" or "Contacts")
  drawer.search.ph:SetText(svc and "Search names or services (enchant, portal...)" or "Search contacts")
  local top = svc and (40 + 24 + 8 + drawer.chipBox:GetHeight() + 4 + 20 + 8) or (40 + 24 + 8)
  local bottom = svc and 12 or 44
  drawer.sf:ClearAllPoints(); drawer.sf:SetPoint("TOPLEFT", 6, -top)
  drawer.sf:SetHeight(WIN_H - top - bottom)
  drawer.empty:ClearAllPoints(); drawer.empty:SetPoint("TOP", drawer, "TOP", 0, -top - 30)
end
-- open / switch / fold the drawer
function S:MsgDrawer(mode)
  if not win then return end
  if not drawer then buildDrawer() end
  if drawer:IsShown() and dmode == mode then drawer:Hide() return end
  dmode = mode
  -- open on whichever side has room
  drawer:ClearAllPoints()
  if (win:GetLeft() or 1000) * (win:GetEffectiveScale() or 1) < (DW + 10) * (drawer:GetEffectiveScale() or 1) then
    drawer:SetPoint("TOPLEFT", win, "TOPRIGHT", 4, 0)
  else
    drawer:SetPoint("TOPRIGHT", win, "TOPLEFT", -4, 0)
  end
  layoutDrawer()
  drawer.search:SetText("")
  drawer:Show()
  renderDrawer()
end
S:Listen("MSGR_STYLE", function() if drawer and drawer:IsShown() then renderDrawer() end end)
S:Listen("PLAYER_INFO", function() if drawer and drawer:IsShown() then renderDrawer() end end)
