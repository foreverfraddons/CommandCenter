-- Smart messaging: reads the last few messages of a chat and offers the most useful
-- next step as one-click buttons above the message box:
--   * someone asks for an invite        -> Invite <name>
--   * a time or day is mentioned        -> Remind me
-- Reminders made here show up in the Reminders window (Tools) where you can change them.
local _, S = ...
local UI = S.UI

local function G() return S.db.global end
local function lower(t) return (tostring(t or "")):lower() end

-- (reminders themselves live in Reminders.lua: S:AddReminder, S:HasReminder)

---------------------------------------------------------------------------
-- Reading times: "at 8", "8:30pm", "20:00", "tonight", "tomorrow", "saturday",
-- "in 30 min", "in 2 hours"
---------------------------------------------------------------------------
local DAYS = { sun = 1, mon = 2, tue = 3, wed = 4, thu = 5, fri = 6, sat = 7 }
local DAYNAMES = { sunday = 1, monday = 2, tuesday = 3, wednesday = 4, thursday = 5, friday = 6, saturday = 7,
  sun = 1, mon = 2, tue = 3, tues = 3, wed = 4, thu = 5, thur = 5, thurs = 5, fri = 6, sat = 7 }

function S.ParseWhen(text, now)
  now = now or S.now()
  local t = " " .. lower(text):gsub("[%?!,%.]", " ") .. " "
  -- relative: in 30 min / in 2 hours / in an hour
  local n, unit = t:match("%sin%s+(%d+)%s*(%a+)")
  if n and unit then
    n = tonumber(n)
    if unit:find("^m") then return now + n * 60, "in " .. n .. " min" end
    if unit:find("^h") then return now + n * 3600, "in " .. n .. " hour" .. (n == 1 and "" or "s") end
  end
  if t:find("%sin%s+an?%s+hour") then return now + 3600, "in an hour" end
  if t:find("half%s+an%s+hour") then return now + 1800, "in 30 min" end
  -- clock time
  local hh, mm, ap
  hh, mm, ap = t:match("(%d%d?):(%d%d)%s*([ap]m?)")
  if not hh then hh, mm = t:match("(%d%d?):(%d%d)") end
  if not hh then hh, ap = t:match("%s(%d%d?)%s*([ap]m)%s") end
  if not hh then hh = t:match("%sat%s+(%d%d?)%s") end
  if not hh then hh = t:match("%s@%s*(%d%d?)%s") end
  if not hh then return nil end
  hh, mm = tonumber(hh), tonumber(mm) or 0
  if hh > 23 or mm > 59 then return nil end
  if ap and ap:sub(1, 1) == "p" and hh < 12 then hh = hh + 12 end
  if ap and ap:sub(1, 1) == "a" and hh == 12 then hh = 0 end
  if not ap and hh >= 1 and hh <= 11 and not t:find("morning") then hh = hh + 12 end   -- "at 8" = evening, it's a game
  -- day
  local base = date("*t", now)
  local addDays, dayWord
  if t:find("tomorrow") or t:find("%stmrw?%s") or t:find("%stmr%s") then addDays = 1
  elseif t:find("tonight") or t:find("today") then addDays = 0
  else
    for word in t:gmatch("%a+") do
      local wd = DAYNAMES[word]
      if wd then addDays = (wd - base.wday) % 7; dayWord = true; break end
    end
  end
  local when = time({ year = base.year, month = base.month, day = base.day + (addDays or 0), hour = hh, min = mm, sec = 0 })
  if when <= now then
    if dayWord then when = when + 7 * 86400                       -- "saturday" said on a Saturday evening: next week
    elseif addDays == nil then when = when + 86400 end           -- just a time that's passed: tomorrow
  end
  if when <= now then return nil end
  local label = date("%a %H:%M", when)
  if date("%Y%m%d", when) == date("%Y%m%d", now) then label = "today " .. date("%H:%M", when)
  elseif date("%Y%m%d", when) == date("%Y%m%d", now + 86400) then label = "tomorrow " .. date("%H:%M", when) end
  return when, label
end

---------------------------------------------------------------------------
-- What's the conversation about?
---------------------------------------------------------------------------
local INVITE = { "%f[%a]inv%f[%A]", "%f[%a]invite", "%f[%a]inv%s*pl[sz]", "%f[%a]can%s+i%s+get%s+an?%s+inv", "add%s+me%s+to%s+(the%s+)?group",
  "%f[%a]group%s+me", "%f[%a]party%s+inv", "%f[%a]inv%s+me", "%f[%a]invite%s+me" }
local TYPES = { { "raid", "Raid" }, { "dungeon", "Dungeon" }, { "%f[%a]m%+", "Dungeon" }, { "%f[%a]key%f[%A]", "Dungeon" }, { "%f[%a]mythic", "Dungeon" },
  { "%f[%a]pvp", "PvP" }, { "%f[%a]bgs?%f[%A]", "PvP" }, { "battleground", "PvP" }, { "arena", "PvP" },
  { "fishing", "Contest" }, { "contest", "Contest" }, { "meeting", "Meeting" }, { "farm", "Farming" } }
local STOP = { ["the"] = true, ["and"] = true, ["night"] = true, ["guild"] = true, ["event"] = true, ["with"] = true, ["from"] = true, ["this"] = true, ["that"] = true, ["will"] = true }

local function guessType(text)
  local t = lower(text)
  for _, p in ipairs(TYPES) do if t:find(p[1]) then return p[2] end end
end
local function titleWords(title)
  local out = {}
  for w in lower(title):gmatch("%a+") do if #w >= 4 and not STOP[w] then out[#out + 1] = w end end
  return out
end
-- a planned event this text is about (by name, or by type + day)
local function matchEvent(text, now)
  local t = lower(text)
  local evs = S.UpcomingEvents and S:UpcomingEvents(14) or {}
  for _, e in ipairs(evs) do
    for _, w in ipairs(titleWords(e.title or "")) do if t:find(w, 1, true) then return e end end
  end
  local ty = guessType(text)
  if ty then
    local when = S.ParseWhen(text, now)
    local day = t:find("tonight") and date("%Y%m%d", now) or t:find("tomorrow") and date("%Y%m%d", now + 86400) or (when and date("%Y%m%d", when))
    for _, e in ipairs(evs) do
      if (e.type == ty or lower(e.title):find(lower(ty), 1, true)) and (not day or date("%Y%m%d", e.start) == day) and e.start > now - 3600 then return e end
    end
  end
end

local dismissed = {}
function S:DismissSmart(with, sig) dismissed[with] = sig end

-- { { label, tip, run }, ... } for the chat with "with"
function S:SmartActions(with, msgs)
  if not with or not msgs or #msgs == 0 or G().smartChat == false then return {}, nil end
  local now = S.now()
  local recent = {}
  for i = #msgs, math.max(1, #msgs - 3), -1 do
    local m = msgs[i]
    if m and (now - (m.time or 0)) < 3 * 3600 then recent[#recent + 1] = m end
  end
  if #recent == 0 then return {}, nil end
  local last = msgs[#msgs]
  local sig = (last._key or "") .. ":" .. (last.time or 0)
  if dismissed[with] == sig then return {}, sig end
  local out, seen = {}, {}
  local function add(key, label, tip, run) if not seen[key] and #out < 3 then seen[key] = true; out[#out + 1] = { label = label, tip = tip, run = run } end end
  local short = S.Short(with)

  for _, m in ipairs(recent) do
    local body = S:MailBody(m)
    local t = lower(body)
    local theirs = m.who ~= S.me
    -- 1. invite requests
    if theirs then
      for _, p in ipairs(INVITE) do
        if t:find(p) then
          local inGroup = UnitInParty and (UnitInParty(short) or UnitInParty(with)) or false
          if not inGroup then
            add("invite", "Invite " .. short, "Invite " .. short .. " to your group now.", function() S:PartyInvite(with); S:Print("Invited " .. S:ColorName(with) .. ".") end)
          end
          break
        end
      end
    end
    -- 2. a planned guild event
    local e = matchEvent(body, now)
    if e and e._key then
      local mine = S.MyRsvp and S:MyRsvp(e._key)
      local when = date("%a %H:%M", e.start)
      if not (mine and mine.status == "yes") and e.start > now then
        add("rsvp", "I'm going: " .. (e.title or "event"), "Sign up as going for " .. (e.title or "the event") .. " (" .. when .. ").",
          function() S:Rsvp(e._key, "yes"); S:Print("Signed up for " .. (e.title or "the event") .. " - " .. when .. ".") end)
      end
      if e.start - 15 * 60 > now and not S:HasReminder(e.start - 15 * 60) then
        add("remind-ev", "Remind me (15 min before)", "A pop-up 15 minutes before " .. (e.title or "it") .. " starts.",
          function() S:AddReminder(e.start - 15 * 60, (e.title or "Event") .. " starts in 15 minutes (" .. date("%H:%M", e.start) .. ")") end)
      end
      if theirs and (t:find("when") or t:find("what%s+time")) then
        add("tell", "Reply with the time", "Puts the time into your message box.",
          function() if S.MsgInsert then S.MsgInsert((e.title or "It") .. " is " .. date("%A at %H:%M", e.start) .. " (server time)") end end)
      end
    else
      -- 3. a time was mentioned, nothing planned yet
      local when, label = S.ParseWhen(body, now)
      if when then
        if not S:HasReminder(when) then
          local what = guessType(body) or "Plans"
          add("remind", "Remind me " .. label, "A pop-up at " .. date("%a %H:%M", when) .. ".",
            function() S:AddReminder(when, what .. " with " .. short .. " (" .. date("%H:%M", when) .. ")") end)
        end
        if S:IsOfficer() and guessType(body) and S.OpenEventEditor then
          local ty = guessType(body)
          add("create", "Create event " .. label, "Opens the event editor with this time filled in.",
            function() S.OpenEventEditor({ title = ty == "Dungeon" and "Dungeon run" or ty == "PvP" and "PvP night" or ty, type = ty, start = when, leader = S.me }) end)
        end
      end
    end
  end
  return out, sig
end
