-- Reminders: your own alarms. Made by hand in the Reminders window (Tools) or with one
-- click from smart suggestions in a chat. Each one can pop up, run a big line of text
-- across the screen and play a sound; it can repeat daily or weekly.
local _, S = ...
local UI = S.UI

local function G() return S.db.global end
local function list()
  local g = G()
  g.reminders = type(g.reminders) == "table" and g.reminders or {}
  return g.reminders
end

S.REMINDER_SOUNDS = {
  { value = "raid", text = "Raid warning", kit = "RAID_WARNING", id = 8959 },
  { value = "ready", text = "Ready check", kit = "READY_CHECK", id = 8960 },
  { value = "alarm", text = "Alarm clock", kit = "ALARM_CLOCK_WARNING_3", id = 12889 },
  { value = "levelup", text = "Level up", kit = "LEVELUP", id = 888 },
  { value = "none", text = "No sound" },
}
local REPEATS = { { value = "none", text = "Once" }, { value = "daily", text = "Every day" }, { value = "weekly", text = "Every week" } }

function S:PlayReminderSound(key)
  for _, s in ipairs(S.REMINDER_SOUNDS) do
    if s.value == key then
      if s.file then if PlaySoundFile then PlaySoundFile(s.file, "Master") end
      elseif PlaySound then
        local id = (SOUNDKIT and s.kit and SOUNDKIT[s.kit]) or s.id
        if id then PlaySound(id, "Master") end
      end
      return
    end
  end
end

---------------------------------------------------------------------------
-- The line of text that slides across the screen
---------------------------------------------------------------------------
local banner
local function showBanner(text)
  if not banner then
    banner = CreateFrame("Frame", "CC_ReminderBanner", UIParent)
    banner:SetFrameStrata("FULLSCREEN_DIALOG"); banner:SetHeight(54)
    banner:SetPoint("LEFT", UIParent, "LEFT"); banner:SetPoint("RIGHT", UIParent, "RIGHT")
    banner:SetPoint("TOP", UIParent, "TOP", 0, -170)
    banner.bg = banner:CreateTexture(nil, "BACKGROUND"); banner.bg:SetAllPoints(); banner.bg:SetColorTexture(0, 0, 0, 0.55)
    banner.edge1 = banner:CreateTexture(nil, "BORDER"); banner.edge1:SetPoint("TOPLEFT"); banner.edge1:SetPoint("TOPRIGHT"); banner.edge1:SetHeight(2)
    banner.edge2 = banner:CreateTexture(nil, "BORDER"); banner.edge2:SetPoint("BOTTOMLEFT"); banner.edge2:SetPoint("BOTTOMRIGHT"); banner.edge2:SetHeight(2)
    banner.text = banner:CreateFontString(nil, "OVERLAY")
    banner.text:SetFont("Fonts\\FRIZQT__.TTF", 26, "OUTLINE"); banner.text:SetWordWrap(false)
    banner:EnableMouse(true)
    banner:SetScript("OnMouseUp", function(self) self:Hide() end)
    banner:SetScript("OnUpdate", function(self, el)
      self.t = self.t + el
      local W = UIParent:GetWidth() or 1024
      local tw = self.text:GetStringWidth() or 300
      local dur = 9
      local x = W - (W + tw) * (self.t / dur)
      self.text:ClearAllPoints(); self.text:SetPoint("LEFT", self, "LEFT", x, 0)
      local a = math.min(1, self.t * 3, (dur - self.t) * 2)
      self:SetAlpha(math.max(0, a))
      if self.t >= dur then
        self.loops = self.loops - 1
        if self.loops > 0 then self.t = 0 else self:Hide() end
      end
    end)
  end
  local th = UI:Theme()
  banner.edge1:SetColorTexture(th.gold[1], th.gold[2], th.gold[3], 0.9); banner.edge2:SetColorTexture(th.gold[1], th.gold[2], th.gold[3], 0.9)
  banner.text:SetTextColor(th.gold[1], th.gold[2], th.gold[3])
  banner.text:SetText("|TInterface\\Icons\\INV_Misc_PocketWatch_01:28|t  " .. (text or ""))
  banner.t, banner.loops = 0, 2
  banner:Show()
end
S.ShowReminderBanner = showBanner

---------------------------------------------------------------------------
-- API
---------------------------------------------------------------------------
local function defaults() return { popup = true, banner = true, sound = "raid", rep = "none" } end
-- opts: { popup, banner, sound, rep }
function S:AddReminder(at, text, quiet, opts)
  if not at or at <= S.now() then S:Print("That time has already passed.") return end
  local l = list()
  for _, r in ipairs(l) do if r.at == at and r.text == text then if not quiet then S:Print("You already have that reminder.") end return end end
  local r = defaults()
  for k, v in pairs(opts or {}) do r[k] = v end
  r.at, r.text, r.id = at, text, tostring(at) .. "." .. math.random(1000, 9999)
  l[#l + 1] = r
  table.sort(l, function(a, b) return a.at < b.at end)
  if not quiet then S:Print("Reminder set for |cffffd100" .. date("%a %b %d %H:%M", at) .. "|r: " .. text .. "  (|cffffff00/ccenter reminders|r to change it)") end
  if S.RefreshReminders then S:RefreshReminders() end
  return r
end
function S:HasReminder(at) for _, r in ipairs(list()) do if math.abs(r.at - at) < 60 then return true end end return false end
function S:DeleteReminder(id)
  local l = list()
  for i = #l, 1, -1 do if l[i].id == id then table.remove(l, i) end end
  if S.RefreshReminders then S:RefreshReminders() end
end

function S:FireReminder(r, test)
  if r.popup ~= false and S.ShowToast then
    S:ShowToast({ title = test and "Reminder (test)" or "Reminder", text = r.text, icon = "Interface\\Icons\\INV_Misc_PocketWatch_01",
      key = "rem:" .. (r.id or "x"), time = 12, onClick = function() S:ShowReminders() end })
  end
  if r.banner ~= false then showBanner(r.text) end
  S:PlayReminderSound(r.sound or "raid")
  if not test then
    if S.Notify then S:Notify("rem:" .. r.id .. ":" .. r.at, { title = "Reminder", text = r.text, icon = "Interface\\Icons\\INV_Misc_PocketWatch_01", popup = false }) end
    S:Print("|cffffff00Reminder:|r " .. r.text)
  end
end

local onlineSince                    -- reminders that came due while you were offline don't go off later
local function check()
  if not S.db or not onlineSince then return end
  local l, now = list(), S.now()
  local changed = false
  for i = #l, 1, -1 do
    local r = l[i]
    if r.at <= now then
      if r.at >= onlineSince then S:FireReminder(r) end      -- missed while offline: skipped quietly
      if r.rep == "daily" or r.rep == "weekly" then
        local step = r.rep == "daily" and 86400 or 7 * 86400
        while r.at <= now do r.at = r.at + step end
      else
        table.remove(l, i)
      end
      changed = true
    end
  end
  if changed then
    table.sort(l, function(a, b) return a.at < b.at end)
    if S.RefreshReminders then S:RefreshReminders() end
  end
end
S.CheckReminders = check
S:On("PLAYER_LOGIN", function()
  onlineSince = S.now()
  check()                              -- clear out (or move on) what was missed while offline, silently
  C_Timer.NewTicker(10, check)
end)

---------------------------------------------------------------------------
-- Window: list + editor
---------------------------------------------------------------------------
local win, tbl, sel
local function setTime(ts)
  win.date:SetText(date("%Y-%m-%d", ts)); win.time:SetText(date("%H:%M", ts))
end
local function readTime()
  local y, mo, d = (win.date:GetText() or ""):match("^(%d%d%d%d)%-(%d%d?)%-(%d%d?)$")
  local hh, mm = (win.time:GetText() or ""):match("^(%d%d?):(%d%d)$")
  if not y or not hh then return nil end
  return time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d), hour = tonumber(hh), min = tonumber(mm), sec = 0 })
end
local function load(r)
  sel = r
  local d = r or defaults()
  win.text:SetText(r and r.text or "")
  setTime(r and r.at or (S.now() + 3600 - S.now() % 60))
  win.popup:SetChecked(d.popup ~= false); win.banner:SetChecked(d.banner ~= false)
  win.sound:SetValue(d.sound or "raid"); win.rep:SetValue(d.rep or "none")
  win.save:SetText(r and "Save changes" or "Add reminder")
  win.del:SetShown(r ~= nil)
  win.edTitle:SetText(r and "Edit reminder" or "New reminder")
  tbl.selected = r; tbl:Draw()
end
local function current()
  return { popup = win.popup:GetChecked() and true or false, banner = win.banner:GetChecked() and true or false,
    sound = win.sound.value or "raid", rep = win.rep.value or "none" }
end
function S:RefreshReminders()
  if not win or not win:IsShown() then return end
  tbl:SetData(list())
end
function S:ShowReminders()
  if not win then
    win = UI:Window("CC_Reminders", "Reminders", 480, 470)
    win:SetFrameStrata("HIGH")
    tbl = UI:Table(win, 452, 170, {
      { title = "When", w = 120, get = function(r) return date("%a %b %d  %H:%M", r.at) end, sort = function(r) return r.at end },
      { title = "Reminder", w = 220, get = function(r) return r.text or "" end },
      { title = "Alerts", w = 100, get = function(r)
          local t = {}
          if r.popup ~= false then t[#t + 1] = "pop-up" end
          if r.banner ~= false then t[#t + 1] = "banner" end
          if r.sound and r.sound ~= "none" then t[#t + 1] = "sound" end
          return "|cff888888" .. table.concat(t, ", ") .. (r.rep ~= "none" and r.rep and (" |cff66aaff" .. r.rep .. "|r") or "") .. "|r"
        end },
    }, { sortCol = 1, emptyText = "No reminders. Make one below, or from a chat's smart suggestions.", selectable = true,
         onClick = function(r) load(r) end })
    tbl:SetPoint("TOPLEFT", 14, -38)

    local y = -218
    win.edTitle = UI:Header(win, "New reminder"); win.edTitle:SetPoint("TOPLEFT", 14, y); y = y - 28
    win.text = UI:Edit(win, 452, 24, "What should I remind you about?"); win.text:SetPoint("TOPLEFT", 14, y); y = y - 32
    local dl = UI:Text(win, "When", "small"); dl:SetPoint("TOPLEFT", 16, y - 4)
    win.date = UI:Edit(win, 100, 22, "YYYY-MM-DD"); win.date:SetPoint("TOPLEFT", 60, y)
    win.time = UI:Edit(win, 60, 22, "HH:MM"); win.time:SetPoint("LEFT", win.date, "RIGHT", 6, 0)
    local function quick(label, fn, anchor)
      local b = UI:Button(win, label, 64, 22, function() local base = readTime() or S.now(); setTime(fn(base)) end)
      b:SetPoint("LEFT", anchor, "RIGHT", 6, 0)
      return b
    end
    local q1 = quick("+15 min", function(t) return math.max(t, S.now()) + 900 end, win.time)
    local q2 = quick("+1 hour", function(t) return math.max(t, S.now()) + 3600 end, q1)
    quick("Tomorrow", function(t) return t + 86400 end, q2)
    y = y - 32
    win.popup = UI:Check(win, "Pop-up", true); win.popup:SetPoint("TOPLEFT", 14, y)
    win.banner = UI:Check(win, "Text across the screen", true); win.banner:SetPoint("TOPLEFT", 120, y)
    y = y - 30
    local sl = UI:Text(win, "Sound", "small"); sl:SetPoint("TOPLEFT", 16, y - 4)
    win.sound = UI:Dropdown(win, 140, S.REMINDER_SOUNDS, "raid", function(v) S:PlayReminderSound(v) end)
    win.sound:SetPoint("TOPLEFT", 60, y)
    local rl = UI:Text(win, "Repeat", "small"); rl:SetPoint("TOPLEFT", 222, y - 4)
    win.rep = UI:Dropdown(win, 130, REPEATS, "none"); win.rep:SetPoint("TOPLEFT", 270, y)
    y = y - 40
    win.save = UI:PrimaryButton(win, "Add reminder", 130, 24, function()
      local text = S.Trim(win.text:GetText() or "")
      if text == "" then UI:Alert("Write what the reminder is for.") return end
      local at = readTime()
      if not at then UI:Alert("Use the date as YYYY-MM-DD and the time as HH:MM.") return end
      if at <= S.now() then UI:Alert("That time has already passed.") return end
      if sel then
        for k, v in pairs(current()) do sel[k] = v end
        sel.text, sel.at = text, at
        table.sort(list(), function(a, b) return a.at < b.at end)
        S:Print("Reminder updated.")
      else
        S:AddReminder(at, text, true, current())
        S:Print("Reminder set for |cffffd100" .. date("%a %b %d %H:%M", at) .. "|r.")
      end
      load(nil); S:RefreshReminders()
    end)
    win.save:SetPoint("BOTTOMRIGHT", -14, 14)
    local new = UI:Button(win, "New", 70, 24, function() load(nil) end, "Clear the form to make a new reminder.")
    new:SetPoint("RIGHT", win.save, "LEFT", -6, 0)
    local test = UI:Button(win, "Test", 70, 24, function()
      local r = current(); r.text = S.Trim(win.text:GetText() or "") ~= "" and win.text:GetText() or "This is a test reminder"
      S:FireReminder(r, true)
    end, "Show the pop-up, text and sound right now.")
    test:SetPoint("BOTTOMLEFT", 14, 14)
    win.del = UI:Button(win, "|cffff7777Delete|r", 80, 24, function() if sel then S:DeleteReminder(sel.id); load(nil) end end)
    win.del:SetPoint("LEFT", test, "RIGHT", 6, 0)
    win:HookScript("OnShow", function() S:RefreshReminders() end)
  end
  win:Show(); win:Raise()
  load(nil)
  S:RefreshReminders()
end
S:AddCommand("reminders", "", "Your reminders: make, change, test", function() S:ShowReminders() end)
