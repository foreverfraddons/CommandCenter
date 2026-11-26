-- Perf: find what makes the game lag or stutter.
--   /ccenter perf [seconds]   measure (default 20 s), then show a report you can copy
--   /ccenter perf stop        stop early and show the report
-- The report has: how many stutters (frames over 50 ms) and the worst frame, which addons
-- went over 5 / 10 ms per frame (the game's own addon profiler), which addons made the
-- most garbage (memory that has to be cleaned up - a common cause of hitches), and inside
-- Command Center which module + event used the most time.
local _, S = ...
-- (looked up when used: this file loads before UI.lua and the game's tables)
local P, M, CA
local function api() P = C_AddOnProfiler; M = Enum and Enum.AddOnProfilerMetric; CA = C_AddOns end
local GAME = "The game itself (Blizzard UI)"
local deep          -- a deep check in progress (see below)
-- Debug mode (Settings > Behaviour, /ccenter debug): nothing here measures or records anything
-- unless it's on - the overlay, /ccenter perf, the deep check and the frame-script notes
local function debugOn() return S.db and S.db.global.debugMode == true end
local capOn = false       -- frame-script notes (set at login from debug mode)
local function needDebug()
  if debugOn() then return true end
  S:Print("Performance tools are part of Debug mode: turn it on in Settings > Behaviour or type /ccenter debug on.")
  return false
end
local SKIP_WRAP     -- (function names the deep check leaves alone: set below)
local profClock = debugprofilestop or function() return GetTime() * 1000 end
local function secret(v) return issecretvalue and issecretvalue(v) end

local function metric(name, m)
  if not (P and P.GetAddOnMetric and M and m) then return nil end
  local ok, v = pcall(P.GetAddOnMetric, name, m)
  if ok and type(v) == "number" and not secret(v) then return v end
end
local function addons()
  local out = {}
  local n = (CA and CA.GetNumAddOns and CA.GetNumAddOns()) or (GetNumAddOns and GetNumAddOns()) or 0
  for i = 1, n do
    local name = (CA and CA.GetAddOnInfo and CA.GetAddOnInfo(i)) or (GetAddOnInfo and GetAddOnInfo(i))
    local loaded = name and ((CA and CA.IsAddOnLoaded and CA.IsAddOnLoaded(name)) or (IsAddOnLoaded and IsAddOnLoaded(name)))
    if loaded then out[#out + 1] = name end
  end
  return out
end
local function memAll(list)
  local out = {}
  if UpdateAddOnMemoryUsage then pcall(UpdateAddOnMemoryUsage) end
  for _, n in ipairs(list) do
    local ok, v = pcall(GetAddOnMemoryUsage, n)
    out[n] = ok and tonumber(v) or 0
  end
  return out
end
local function counts(list, m)
  local out = {}
  for _, n in ipairs(list) do out[n] = metric(n, m) or 0 end
  return out
end

local run          -- the measurement in progress
local ov           -- the live overlay (built further down)
local watcher = CreateFrame("Frame")
watcher:Hide()
watcher:SetScript("OnUpdate", function(_, el)
  if not run then watcher:Hide() return end
  local ms = el * 1000
  run.frames = run.frames + 1
  run.total = run.total + ms
  if ms > run.worst then run.worst = ms end
  if ms > 50 then run.hitch = run.hitch + 1 end
  if ms > 100 then run.big = run.big + 1 end
  if GetTime() >= run.stopAt then S:PerfStop() end
end)

function S:PerfStart(secs)
  if not needDebug() then return end
  if run then S:Print("Already measuring - /ccenter perf stop to finish now.") return end
  api()
  secs = math.max(5, math.min(300, tonumber(secs) or 20))
  local list = addons()
  run = {
    list = list, secs = secs, startAt = GetTime(), stopAt = GetTime() + secs,
    frames = 0, total = 0, worst = 0, hitch = 0, big = 0,
    mem0 = memAll(list), gc0 = collectgarbage("count"),
    o5 = M and counts(list, M.CountTimeOver5Ms) or {}, o10 = M and counts(list, M.CountTimeOver10Ms) or {},
    o50 = M and counts(list, M.CountTimeOver50Ms) or {},
  }
  S.perf = {}
  watcher:Show()
  S:Print(string.format("Measuring for %d s - play as normal (fight, open your bags...). The report pops up when it's done.", secs))
end

local function sorted(tbl, key)
  local out = {}
  for k, v in pairs(tbl) do out[#out + 1] = { k = k, v = key and v[key] or v, r = v } end
  table.sort(out, function(a, b) return a.v > b.v end)
  return out
end

function S:PerfStop()
  if not run then S:Print("Not measuring. Start with /ccenter perf") return end
  api()
  local UI = S.UI
  local r = run
  run = nil
  watcher:Hide()
  local prof = S.perf or {}
  S.perf = (ov and ov:IsShown()) and {} or nil
  local secs = math.max(0.1, GetTime() - r.startAt)
  local lines = {}
  local function add(s) lines[#lines + 1] = s end
  add(string.format("Command Center performance report - %.0f s", secs))
  add(string.format("Frames: %d (avg %.0f fps), worst frame %.0f ms, stutters over 50 ms: %d, over 100 ms: %d",
    r.frames, r.frames / secs, r.worst, r.hitch, r.big))
  -- addons over the limits (game's profiler)
  if M then
    local o5, o10, o50 = counts(r.list, M.CountTimeOver5Ms), counts(r.list, M.CountTimeOver10Ms), counts(r.list, M.CountTimeOver50Ms)
    local rows = {}
    for _, n in ipairs(r.list) do
      local d5, d10, d50 = (o5[n] or 0) - (r.o5[n] or 0), (o10[n] or 0) - (r.o10[n] or 0), (o50[n] or 0) - (r.o50[n] or 0)
      local avg = metric(n, M.RecentAverageTime) or 0
      local peak = metric(n, M.PeakTime) or 0
      if d5 > 0 or avg > 0.2 then rows[#rows + 1] = { n = n, d5 = d5, d10 = d10, d50 = d50, avg = avg, peak = peak } end
    end
    table.sort(rows, function(a, b) if a.d5 ~= b.d5 then return a.d5 > b.d5 end return a.avg > b.avg end)
    add("")
    add("Addons by slow frames (frames where the addon alone took over 5 / 10 / 50 ms):")
    if #rows == 0 then add("  none - no addon went over 5 ms in a frame") end
    for i = 1, math.min(10, #rows) do
      local x = rows[i]
      add(string.format("  %-22s >5ms: %d  >10ms: %d  >50ms: %d   avg now %.2f ms/frame   peak ever %.0f ms", x.n, x.d5, x.d10, x.d50, x.avg, x.peak))
    end
  else
    add("(this game version has no addon profiler - addon CPU can't be shown)")
  end
  -- garbage
  local mem1 = memAll(r.list)
  local grow = {}
  for _, n in ipairs(r.list) do
    local d = (mem1[n] or 0) - (r.mem0[n] or 0)
    if d > 1 then grow[n] = d end
  end
  local gs = sorted(grow)
  add("")
  add(string.format("Memory growth (garbage the game has to clean up; all addons %.0f KB/s):", math.max(0, collectgarbage("count") - r.gc0) / secs))
  if #gs == 0 then add("  nothing notable") end
  for i = 1, math.min(8, #gs) do add(string.format("  %-22s +%.0f KB  (%.1f KB/s)", gs[i].k, gs[i].v, gs[i].v / secs)) end
  -- inside Command Center
  local ps = sorted(prof, "t")
  add("")
  add("Inside Command Center (events + timed updates), most time first:")
  if #ps == 0 then add("  nothing ran") end
  local ccTotal = 0
  for _, x in ipairs(ps) do ccTotal = ccTotal + x.r.t end
  for i = 1, math.min(15, #ps) do
    local x = ps[i].r
    add(string.format("  %-44s %7.1f ms total  %5d calls  %.2f ms each  slowest %.1f ms", ps[i].k, x.t, x.n, x.t / math.max(1, x.n), x.max))
  end
  local ccAvg = M and metric("CommandCenter", M.RecentAverageTime)
  add(string.format("  events total %.0f ms (%.2f ms/s)%s", ccTotal, ccTotal / secs,
    ccAvg and string.format("; Command Center overall now %.2f ms/frame (the rest is OnUpdate / timers / drawing)", ccAvg) or ""))
  local text = table.concat(lines, "\n")
  S:Print(lines[2])
  if UI and UI.CopyBox then UI:CopyBox("Performance report - copy it (Ctrl+A, Ctrl+C) and paste it to Claude", text)
  else for _, l in ipairs(lines) do print(l) end end
  S.lastPerfReport = text
end

S:AddCommand("perf", "[seconds|stop]", "Measure lag / stutters for a while and show which addon or module causes them", function(arg)
  arg = arg and S.Trim(arg) or ""
  if arg == "stop" then S:PerfStop() else S:PerfStart(arg) end
end)

---------------------------------------------------------------------------
-- Live overlay: /ccenter fps or Settings > Behaviour (S.db.global.perfOverlay)
---------------------------------------------------------------------------
-- (ov is declared at the top of the file)
-- Updates once a second, so it costs almost nothing itself:
--   FPS + frame time, worst frame and stutters (>50 ms) in the last 10 s, latency,
--   the addons using the most time per frame (the game's addon profiler),
--   the busiest Command Center modules (handler time per second), Lua garbage per second.
local OV_W = 300
local function fpsColor(f) if f >= 50 then return "|cff55ff55" elseif f >= 30 then return "|cffffd100" end return "|cffff5555" end
local function kbColor(v) return v > 500 and "|cffff5555" or (v > 150 and "|cffffd100" or "|cff55ff55") end
local function msColor(m) if m < 1 then return "|cff55ff55" elseif m < 3 then return "|cffffd100" end return "|cffff5555" end
local function buildOverlay()
  local f = CreateFrame("Frame", "CC_PerfOverlay", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  f:SetSize(OV_W, 120); f:SetFrameStrata("HIGH"); f:SetClampedToScreen(true)
  f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
  if f.SetBackdrop then
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    f:SetBackdropColor(0, 0, 0, 0.72); f:SetBackdropBorderColor(1, 0.82, 0.3, 0.5)
  end
  local at = S.db.global.perfOverlayAt
  if type(at) == "table" then f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", at[1], at[2]) else f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -220, -12) end
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    S.db.global.perfOverlayAt = { math.floor((self:GetLeft() or 0) + 0.5), math.floor((self:GetTop() or 0) + 0.5) }
  end)
  f:SetScript("OnMouseUp", function(self, b) if b == "RightButton" then S.PerfOverlayMenu(self) end end)
  f:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("Performance overlay", 1, 0.82, 0.3)
    GameTooltip:AddLine("Drag to move. Right-click for: report the last 60 seconds, record the next 60 seconds, close.", 0.8, 0.8, 0.8, true)
    GameTooltip:AddLine("For a full report to share: /ccenter perf 30", 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
  end)
  f:SetScript("OnLeave", function() GameTooltip:Hide() end)
  f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.text:SetPoint("TOPLEFT", 8, -6); f.text:SetWidth(OV_W - 16); f.text:SetJustifyH("LEFT"); f.text:SetJustifyV("TOP")
  f.text:SetSpacing(2)
  -- frame times, every frame (cheap): worst frame + stutters in a 10 s window
  f.hist = {}      -- { time, ms } of frames over 50 ms
  f.worst, f.acc = 0, 0
  f.gc = collectgarbage("count")
  f:SetScript("OnUpdate", function(self, el)
    local ms = el * 1000
    if ms > self.worst then self.worst = ms end
    if ms > 50 then self.hist[#self.hist + 1] = GetTime(); self.secHitch = (self.secHitch or 0) + 1 end
    self.acc = self.acc + el
    if self.acc >= 1 then
      local secs = self.acc
      self.acc = 0
      S.PerfOverlayUpdate(self, secs)
    end
  end)
  return f
end
function S.PerfOverlayUpdate(f, secs)
  api()
  local now = GetTime()
  -- stutters in the last 10 s
  local keep = {}
  for _, t in ipairs(f.hist) do if now - t <= 10 then keep[#keep + 1] = t end end
  f.hist = keep
  local fps = GetFramerate and GetFramerate() or 0
  local snap = { t = now, fps = fps, worst = f.worst, hitch = f.secHitch or 0, addons = {}, cc = {} }
  f.secHitch = 0
  local lines = {}
  lines[1] = string.format("%sFPS %.0f|r  (%.1f ms)   worst 1s: %s%.0f ms|r   stutters 10s: %s%d|r",
    fpsColor(fps), fps, fps > 0 and 1000 / fps or 0, f.worst > 50 and "|cffff5555" or "|cffffffff", f.worst, #keep > 0 and "|cffff5555" or "|cff55ff55", #keep)
  f.worst = 0
  if GetNetStats then
    local _, _, home, world = GetNetStats()
    lines[#lines + 1] = string.format("Latency  home %d ms   world %d ms", home or 0, world or 0)
    snap.home, snap.world = home, world
  end
  -- addons (game's profiler)
  if P and M and P.GetTopKAddOnsForMetric then
    local ok, top = pcall(P.GetTopKAddOnsForMetric, M.RecentAverageTime, 6)
    if ok and type(top) == "table" then
      local parts = {}
      for idx, r in ipairs(top) do
        local v = r.metricValue
        if type(v) == "number" and not secret(v) and r.addOnName then parts[#parts + 1] = (idx <= 4) and string.format("%s %s%.2f|r", r.addOnName, msColor(v), v) or nil; snap.addons[r.addOnName] = v end
      end
      if #parts > 0 then lines[#lines + 1] = "Addons ms/frame:  " .. table.concat(parts, "   ") end
    end
  elseif P == nil then
    lines[#lines + 1] = "|cff888888(no addon profiler in this game version)|r"
  end
  -- inside Command Center
  local perf = S.perf
  if perf then
    local rows = {}
    -- while a /ccenter perf report is measuring, S.perf keeps adding up: use this second's share
    local prev = run and f.ccPrev or nil
    local prevG = run and f.ccPrevG or nil
    local tot = run and {} or nil
    local totG = run and {} or nil
    for k, r in pairs(perf) do
      local t, g = r.t, r.g or 0
      if tot then tot[k] = t; t = t - ((prev and prev[k]) or 0); totG[k] = g; g = g - ((prevG and prevG[k]) or 0) end
      rows[#rows + 1] = { k = k, t = t, g = g }
    end
    f.ccPrev, f.ccPrevG = tot, totG
    snap.ccg = {}
    table.sort(rows, function(a, b) return a.g > b.g end)
    local gparts = {}
    for i = 1, math.min(10, #rows) do if rows[i].g > 0 then snap.ccg[rows[i].k] = rows[i].g / secs end end
    for i = 1, math.min(3, #rows) do
      if rows[i].g / secs >= 1 then gparts[#gparts + 1] = string.format("%s %s%.0f|r", (rows[i].k:gsub("%s+", " ")), kbColor(rows[i].g / secs), rows[i].g / secs) end
    end
    table.sort(rows, function(a, b) return a.t > b.t end)
    for i = 1, math.min(10, #rows) do if rows[i].t > 0 then snap.cc[rows[i].k] = rows[i].t end end
    snap.ccgLine = #gparts > 0 and ("CC garbage (KB/s):  " .. table.concat(gparts, ",  ")) or nil
    local parts = {}
    for i = 1, math.min(3, #rows) do
      local name = rows[i].k:gsub("%s+", " ")
      parts[#parts + 1] = string.format("%s %s%.1f|r", name, msColor(rows[i].t / secs / 10), rows[i].t / secs)
    end
    lines[#lines + 1] = "CC busiest (ms/s):  " .. (#parts > 0 and table.concat(parts, ",  ") or "idle")
    if snap.ccgLine then lines[#lines + 1] = snap.ccgLine end
    if not run then S.perf = {} end          -- a fresh window each second (unless a /ccenter perf report is measuring)
  end
  local gc = collectgarbage("count")
  local rate = math.max(0, gc - (f.gc or gc)) / secs
  f.gc = gc
  snap.gc = rate
  f.ring = f.ring or {}
  table.insert(f.ring, snap)
  while #f.ring > 60 do table.remove(f.ring, 1) end
  lines[#lines + 1] = string.format("Lua garbage  %s%.0f KB/s|r", kbColor(rate), rate)
  -- who makes it: every addon's memory, sampled every 5 s (the game's count goes DOWN for
  -- everyone when it cleans up, so a sample that shrank keeps the last good rate)
  -- reading every addon's memory is slow (40+ ms with Questie loaded = a hitch of its own),
  -- so it's off unless you turn it on in the right-click menu, and then every 30 s at most
  local memOn = S.db.global.perfMemOn == true
  if not memOn then f.memRate, f.memPrev, f.memAt = nil, nil, nil end
  f.memEvery = (f.memCost and f.memCost < 5) and 5 or 30
  if memOn and UpdateAddOnMemoryUsage and GetAddOnMemoryUsage and now - (f.memAt or 0) >= f.memEvery then
    f.addonList = f.addonList or addons()
    local t0 = debugprofilestop and debugprofilestop() or 0
    local cur = memAll(f.addonList)
    local cost = (debugprofilestop and debugprofilestop() or 0) - t0
    f.memCost = cost
    local dt = now - (f.memAt or now)
    local gcNow = collectgarbage("count")
    if f.memPrev and dt > 0 then
      local rates, sum = {}, 0
      for _, n in ipairs(f.addonList) do
        local d = (cur[n] or 0) - (f.memPrev[n] or 0)
        if d >= 0 then rates[n] = d / dt else rates[n] = f.memRate and f.memRate[n] or 0 end
        sum = sum + rates[n]
      end
      -- the rest of the Lua garbage is the game's own interface (Blizzard code, e.g. the world map)
      local total = (gcNow - (f.memGc or gcNow)) / dt
      if total > sum then rates[GAME] = total - sum
      else rates[GAME] = f.memRate and f.memRate[GAME] or 0 end
      f.memRate = rates
    end
    f.memPrev, f.memAt, f.memGc = cur, now, gcNow
  end
  if f.memRate then
    snap.mem = f.memRate
    local mr = {}
    for n, v in pairs(f.memRate) do if v >= 1 then mr[#mr + 1] = { n = n, v = v } end end
    table.sort(mr, function(a, b) return a.v > b.v end)
    local parts = {}
    for i = 1, math.min(4, #mr) do parts[#parts + 1] = string.format("%s %s%.0f|r", mr[i].n, kbColor(mr[i].v), mr[i].v) end
    lines[#lines + 1] = "Garbage by addon (KB/s):  " .. (#parts > 0 and table.concat(parts, "   ") or "none")
  elseif memOn and UpdateAddOnMemoryUsage then
    lines[#lines + 1] = "|cff888888Garbage by addon: measuring...|r"
  end
  local mo = S.perfMapOpen
  if mo and now - mo.at < 120 then lines[#lines + 1] = "Last map open:  " .. mo.short end
  f.text:SetText(table.concat(lines, "\n"))
  f:SetHeight(math.max(40, (f.text:GetStringHeight() or 80) + 12))
end
function S:PerfOverlay(on)
  if on == nil then on = not (ov and ov:IsShown()) end
  if on and not needDebug() then S.db.global.perfOverlay = false; return end
  S.db.global.perfOverlay = on and true or false
  if on then
    ov = ov or buildOverlay()
    ov:Show()
    if not run then S.perf = S.perf or {} end   -- time Command Center's handlers while it shows
    ov.text:SetText("|cff888888measuring...|r")
  else
    if ov then ov:Hide() end
    if not run then S.perf = nil end
  end
end
-- the last 60 seconds the overlay saw, as a report you can copy
function S:PerfReportLast()
  local ring = ov and ov.ring or {}
  if #ring == 0 then S:Print("Nothing recorded yet - leave the overlay on for a bit first.") return end
  local n = #ring
  local secs = math.max(1, ring[n].t - ring[1].t + 1)
  local sumFps, minFps, worst, hitch, sumGc, maxGc = 0, 9999, 0, 0, 0, 0
  local addons, addonPeak, cc = {}, {}, {}
  for _, sn in ipairs(ring) do
    sumFps = sumFps + sn.fps; if sn.fps < minFps then minFps = sn.fps end
    if sn.worst > worst then worst = sn.worst end
    hitch = hitch + sn.hitch
    sumGc = sumGc + (sn.gc or 0); if (sn.gc or 0) > maxGc then maxGc = sn.gc end
    for a, v in pairs(sn.addons) do addons[a] = (addons[a] or 0) + v; if v > (addonPeak[a] or 0) then addonPeak[a] = v end end
    for k, v in pairs(sn.cc) do cc[k] = (cc[k] or 0) + v end
  end
  local lines = {}
  local function add(x) lines[#lines + 1] = x end
  add(string.format("Command Center performance - the last %d seconds (live overlay)", secs))
  add(string.format("FPS: average %.0f, lowest %.0f.  Worst frame %.0f ms.  Stutters over 50 ms: %d", sumFps / n, minFps, worst, hitch))
  local last = ring[n]
  if last.home then add(string.format("Latency now: home %d ms, world %d ms", last.home, last.world or 0)) end
  add("")
  add("Addons by time per frame (average / highest over the period):")
  local ar = {}
  for a, t in pairs(addons) do ar[#ar + 1] = { a = a, avg = t / n, peak = addonPeak[a] } end
  table.sort(ar, function(x, y) return x.avg > y.avg end)
  if #ar == 0 then add("  (no addon profiler data)") end
  for i = 1, math.min(8, #ar) do add(string.format("  %-22s avg %.2f ms/frame   highest %.2f", ar[i].a, ar[i].avg, ar[i].peak)) end
  add("")
  add("Inside Command Center (events + timed updates), total over the period:")
  local cr = {}
  for k, t in pairs(cc) do cr[#cr + 1] = { k = k, t = t } end
  table.sort(cr, function(x, y) return x.t > y.t end)
  if #cr == 0 then add("  idle") end
  for i = 1, math.min(12, #cr) do add(string.format("  %-44s %7.1f ms  (%.2f ms/s)", cr[i].k, cr[i].t, cr[i].t / secs)) end
  add("")
  add(string.format("Lua garbage: average %.0f KB/s, highest %.0f KB/s", sumGc / n, maxGc))
  -- garbage by addon (5 s samples) and inside Command Center
  local memSum, memN, seenT = {}, 0, {}
  local ccgSum = {}
  for _, sn in ipairs(ring) do
    if sn.mem and not seenT[sn.mem] then
      seenT[sn.mem] = true; memN = memN + 1
      for a, v in pairs(sn.mem) do memSum[a] = (memSum[a] or 0) + v end
    end
    for k, v in pairs(sn.ccg or {}) do ccgSum[k] = (ccgSum[k] or 0) + v end
  end
  if memN > 0 then
    local mr = {}
    for a, v in pairs(memSum) do if v / memN >= 1 then mr[#mr + 1] = { a = a, v = v / memN } end end
    table.sort(mr, function(x, y) return x.v > y.v end)
    add("Garbage by addon (average KB/s, sampled every 5-30 s):")
    if #mr == 0 then add("  none notable") end
    for i = 1, math.min(8, #mr) do add(string.format("  %-22s %6.0f KB/s", mr[i].a, mr[i].v)) end
    if ov and ov.memCost then add(string.format("  (one memory sample costs %.1f ms here)", ov.memCost)) end
  end
  local mo = S.perfMapOpen
  if mo then
    add(string.format("Last time the map opened (%.0f s ago): %.0f KB of garbage in 1.5 s", GetTime() - mo.at, mo.total))
    for i = 1, math.min(6, #mo.rows) do add(string.format("  %-30s +%.0f KB", mo.rows[i].n, mo.rows[i].v)) end
  end
  local gr = {}
  for k, v in pairs(ccgSum) do gr[#gr + 1] = { k = k, v = v / n } end
  table.sort(gr, function(x, y) return x.v > y.v end)
  if #gr > 0 then
    add("Garbage inside Command Center (average KB/s):")
    for i = 1, math.min(8, #gr) do add(string.format("  %-44s %6.1f KB/s", gr[i].k, gr[i].v)) end
  end
  -- the seconds with stutters, so you can see what was busy right then
  local bad = {}
  for i, sn in ipairs(ring) do if sn.hitch > 0 or sn.fps < 30 then bad[#bad + 1] = i end end
  if #bad > 0 then
    add("")
    add("Seconds with stutters or under 30 FPS (seconds ago: fps, worst frame, busiest addon, busiest CC part):")
    for j = math.max(1, #bad - 15), #bad do
      local sn = ring[bad[j]]
      local ba, bv = "-", 0
      for a, v in pairs(sn.addons) do if v > bv then ba, bv = a, v end end
      local bc, bt = "-", 0
      for k, v in pairs(sn.cc) do if v > bt then bc, bt = k:gsub("%s+", " "), v end end
      add(string.format("  %3ds ago: %.0f fps, worst %.0f ms, %s %.2f ms/frame, %s %.1f ms", math.floor(last.t - sn.t + 0.5), sn.fps, sn.worst, ba, bv, bc, bt))
    end
  end
  local text = table.concat(lines, "\n")
  S.lastPerfReport = text
  if S.UI and S.UI.CopyBox then S.UI:CopyBox("Last 60 seconds - copy it (Ctrl+A, Ctrl+C) and paste it to Claude", text)
  else for _, l in ipairs(lines) do print(l) end end
end
function S.PerfOverlayMenu(anchor)
  local UI = S.UI
  local items = {
    { text = "Performance overlay", title = true },
    { text = "Report the last 60 seconds", func = function() S:PerfReportLast() end },
    { text = run and "Recording... (stop now)" or "Record the next 60 seconds", func = function() if run then S:PerfStop() else S:PerfStart(60) end end },
    { text = deep and "Deep check running... (stop now)" or "Deep check Questicus (30 s)",
      func = function() if deep then S:PerfDeepStop() else S:PerfDeepStart({ "Questicus", "QuesticusMap" }, 30) end end },
    { text = "Deep check Command Center + Questicus (30 s)", disabled = deep ~= nil,
      func = function() S:PerfDeepStart({ "CommandCenter", "Questicus", "QuesticusMap" }, 30) end },
    { text = "Measure garbage by addon (a small hitch every 30 s)", checked = S.db.global.perfMemOn == true,
      func = function() S.db.global.perfMemOn = not (S.db.global.perfMemOn == true); if ov then ov.memCost = nil end end },
    { text = "Close the overlay", func = function() S:PerfOverlay(false) end },
  }
  if UI and UI.Menu then UI:Menu(anchor, items) else S:PerfReportLast() end
end
S:AddCommand("fps", "", "Performance overlay on / off (FPS, lag, what's using time)", function() S:PerfOverlay() end)
---------------------------------------------------------------------------
-- Deep check: wraps every function of another addon's global tables for a while
-- (e.g. Questicus + QuesticusMap) and reports which functions take the most time and
-- make the most garbage. Times are inclusive (a function that calls others counts theirs
-- too). Everything is put back when it ends. Only for normal addon tables - never the game's.
---------------------------------------------------------------------------
local function deepFinish(rec, t0, g0, ...)
  local dt, dg = profClock() - t0, collectgarbage("count") - g0
  rec.n = rec.n + 1; rec.t = rec.t + dt
  if dg > 0 then rec.g = rec.g + dg end
  if dt > rec.max then rec.max = dt end
  if dt > 10 then rec.big = (rec.big or 0) + 1 end
  return ...
end
-- Scripts other addons put on their frames (OnUpdate / OnEvent) are local functions no table
-- holds, so the deep check can't find them by walking the addon's tables. Command Center loads
-- before most addons, so it notes each SetScript call (frame, script, addon folder, file:line)
-- as it happens; a deep check then times those too. (Only a note - nothing is changed here.)
local scriptLog = setmetatable({}, { __mode = "k" })   -- frame -> { [script] = { fn, addon, where } }
local capBusy
do
  -- (cheap on purpose: the game and addons switch OnUpdate scripts on and off all the time, so the
  -- stack is read once per frame only - a known frame just gets its new function noted, and a frame
  -- no addon set a script on is skipped from then on)
  local notAddon = setmetatable({}, { __mode = "k" })
  local function onSetScript(self, script, fn)
    if not capOn or capBusy or type(fn) ~= "function" or (script ~= "OnUpdate" and script ~= "OnEvent") or notAddon[self] then return end
    local known = scriptLog[self]
    local k = known and known[script]
    if k then k.fn = fn return end
    if known then   -- (the frame's other script: same addon, same place)
      local _, other = next(known)
      known[script] = { fn = fn, addon = other.addon, where = other.where }
      return
    end
    local st = debugstack and debugstack(2, 4, 0)
    if type(st) ~= "string" then return end
    for addon, file, line in st:gmatch('AddOns[/\\]([^/\\]+)[/\\]([^"%]:\n]-%.lua)"?%]?:(%d+)') do
      if not (addon == "CommandCenter" and file == "Perf.lua") then   -- (Command Center's own modules count too, not this file)
        local e = scriptLog[self] or {}
        scriptLog[self] = e
        e[script] = { fn = fn, addon = addon, where = file:gsub("\\", "/") .. ":" .. line }
        return
      end
    end
    notAddon[self] = true
  end
  S.PerfNoteScript = onSetScript     -- (for tests)
  for _, kind in ipairs({ "Frame", "Button", "StatusBar", "ScrollFrame", "CheckButton" }) do
    local ok, probe = pcall(CreateFrame, kind)
    local mt = ok and probe and getmetatable(probe)
    local idx = mt and mt.__index
    if type(idx) == "table" and idx.SetScript and hooksecurefunc then pcall(hooksecurefunc, idx, "SetScript", onSetScript) end
  end
end
local function looksLikeCode(t)
  local n = 0
  for _, v in pairs(t) do
    if type(v) == "function" then return true end
    n = n + 1; if n > 60 then return false end
  end
  return false
end
-- (Command Center's own measuring and dispatch are never wrapped: it would measure itself)
SKIP_WRAP = { PerfDeepStart = true, PerfDeepStop = true, PerfWrap = true, PerfOverlayUpdate = true, PerfOverlay = true,
  PerfOverlayMenu = true, PerfReportLast = true, PerfStart = true, PerfStop = true, PerfNoteScript = true,
  On = true, Listen = true }
function S:PerfDeepStart(names, secs)
  if not needDebug() then return end
  if deep then S:Print("A deep check is already running.") return end
  secs = math.max(10, math.min(120, tonumber(secs) or 30))
  deep = { list = {}, recs = {}, at = GetTime(), secs = secs, names = names }
  local seen, budget = {}, 40000
  local function walk(t, path, depth)
    if seen[t] or depth > 4 or budget <= 0 then return end
    seen[t] = true
    if rawget(t, 0) ~= nil and type(rawget(t, 0)) == "userdata" then return end   -- a frame
    if depth > 1 and not looksLikeCode(t) then return end                          -- saved data
    local keys = {}
    for k, v in pairs(t) do keys[#keys + 1] = k; budget = budget - 1; if budget <= 0 then break end end
    for _, k in ipairs(keys) do
      local v = rawget(t, k)
      if type(k) == "string" and not SKIP_WRAP[k] then
        if type(v) == "function" then
          local name = path .. "." .. k
          local rec = { n = 0, t = 0, g = 0, max = 0 }
          deep.recs[name] = rec
          local orig = v
          local wrapped = function(...) return deepFinish(rec, profClock(), collectgarbage("count"), orig(...)) end
          deep.list[#deep.list + 1] = { t = t, k = k, orig = orig, w = wrapped }
          rawset(t, k, wrapped)
        elseif type(v) == "table" then
          walk(v, path .. "." .. k, depth + 1)
        end
      end
    end
  end
  local found = {}
  for _, n in ipairs(names) do
    local t = _G[n]
    if type(t) == "table" and not (t.IsForbidden or t.GetObjectType) then walk(t, n, 1); found[#found + 1] = n end
  end
  -- the addons' frame scripts noted since login (addon folder = a name, or a name's start: Questicus for QuesticusMap)
  local function wanted(addon)
    for _, n in ipairs(names) do if addon == n or n:sub(1, #addon) == addon then return true end end
  end
  deep.scripts = {}
  for frame, e in pairs(scriptLog) do
    for script, info in pairs(e) do
      local okP, prot = pcall(frame.IsProtected, frame)
      local okG, cur = pcall(frame.GetScript, frame, script)
      if wanted(info.addon) and okG and cur == info.fn and not (okP and prot) then
        local name = info.addon .. "  " .. info.where .. "  " .. script
        local rec = deep.recs[name] or { n = 0, t = 0, g = 0, max = 0 }
        deep.recs[name] = rec
        local orig = cur
        local wrapped = function(...) return deepFinish(rec, profClock(), collectgarbage("count"), orig(...)) end
        capBusy = true
        local okS = pcall(frame.SetScript, frame, script, wrapped)
        capBusy = false
        if okS then deep.scripts[#deep.scripts + 1] = { f = frame, s = script, orig = orig, w = wrapped } end
      end
    end
  end
  if #deep.list == 0 then deep = nil; S:Print("Nothing to check (no addon table named " .. table.concat(names, ", ") .. ").") return end
  S:Print(string.format("Deep check of %s: %d functions + " .. #deep.scripts .. " frame scripts watched for %d s - play as normal (open the map too). The report pops up when it's done.", table.concat(found, " + "), #deep.list, secs))
  C_Timer.After(secs, function() if deep then S:PerfDeepStop() end end)
end
function S:PerfDeepStop()
  if not deep then S:Print("No deep check running.") return end
  local d = deep
  deep = nil
  for _, e in ipairs(d.list) do if rawget(e.t, e.k) == e.w then rawset(e.t, e.k, e.orig) end end
  for _, e in ipairs(d.scripts or {}) do
    local okG, cur = pcall(e.f.GetScript, e.f, e.s)
    if okG and cur == e.w then capBusy = true; pcall(e.f.SetScript, e.f, e.s, e.orig); capBusy = false end
  end
  local secs = math.max(1, GetTime() - d.at)
  local rows = {}
  for name, r in pairs(d.recs) do if r.n > 0 then rows[#rows + 1] = { k = name, r = r } end end
  local lines = {}
  local function add(x) lines[#lines + 1] = x end
  add(string.format("Deep check of %s - %.0f s, %d functions + %d frame scripts watched, %d were called", table.concat(d.names, " + "), secs, #d.list, #(d.scripts or {}), #rows))
  add("(times and garbage include the functions each one calls)")
  add("")
  add("Most garbage:")
  table.sort(rows, function(a, b) return a.r.g > b.r.g end)
  for i = 1, math.min(20, #rows) do
    local r = rows[i].r
    if r.g < 1 then break end
    add(string.format("  %-46s %8.0f KB (%6.1f KB/s)  %6d calls  %5.1f KB each", rows[i].k, r.g, r.g / secs, r.n, r.g / r.n))
  end
  add("")
  add("Most time:")
  table.sort(rows, function(a, b) return a.r.t > b.r.t end)
  for i = 1, math.min(20, #rows) do
    local r = rows[i].r
    add(string.format("  %-46s %8.1f ms (%5.2f ms/s)  %6d calls  slowest %.1f ms%s", rows[i].k, r.t, r.t / secs, r.n, r.max,
      (r.big or 0) > 0 and string.format("  (%d over 10 ms)", r.big) or ""))
  end
  -- what made the slow frames: everything that took over 10 ms in one go
  local spikes = {}
  for _, x in ipairs(rows) do if (x.r.big or 0) > 0 then spikes[#spikes + 1] = x end end
  table.sort(spikes, function(a, b) return a.r.big > b.r.big end)
  if #spikes > 0 then
    add("")
    add("Took over 10 ms in one go (these make the stutters):")
    for i = 1, math.min(15, #spikes) do
      local r = spikes[i].r
      add(string.format("  %-46s %4d times, slowest %.1f ms", spikes[i].k, r.big, r.max))
    end
  end
  local text = table.concat(lines, "\n")
  S.lastPerfReport = text
  if S.UI and S.UI.CopyBox then S.UI:CopyBox("Deep check - copy it (Ctrl+A, Ctrl+C) and paste it to Claude", text)
  else for _, l in ipairs(lines) do print(l) end end
end
S:AddCommand("deepcheck", "[addon tables...] [seconds|stop]", "Watch every function of an addon for a while and report the slowest / most garbage", function(arg)
  arg = arg and S.Trim(arg) or ""
  if arg == "stop" then S:PerfDeepStop() return end
  local names, secs = {}, nil
  for w in arg:gmatch("%S+") do if tonumber(w) then secs = tonumber(w) else names[#names + 1] = w end end
  if #names == 0 then names = { "Questicus", "QuesticusMap" } end
  S:PerfDeepStart(names, secs)
end)

-- opening the world map: who made the garbage? (only while the overlay shows; reads every
-- addon's memory right when the map opens and again 1.5 s later - a hitch you won't notice
-- on top of the map opening)
local mapBusy
local function mapProbe()
  -- (reading every addon's memory costs ~30 ms twice: only when you asked for garbage by addon -
  -- otherwise this probe itself was a stutter on every map opening)
  if mapBusy or not (ov and ov:IsShown()) or S.db.global.perfMemOn ~= true or not (UpdateAddOnMemoryUsage and GetAddOnMemoryUsage) then return end
  mapBusy = true
  api()
  ov.addonList = ov.addonList or addons()
  local list = ov.addonList
  local before, g0 = memAll(list), collectgarbage("count")
  C_Timer.After(1.5, function()
    mapBusy = false
    local after, g1 = memAll(list), collectgarbage("count")
    local rows, sum = {}, 0
    for _, n in ipairs(list) do
      local d = (after[n] or 0) - (before[n] or 0)
      if d > 0 then rows[#rows + 1] = { n = n, v = d }; sum = sum + d end
    end
    local total = math.max(0, g1 - g0)
    if total > sum then rows[#rows + 1] = { n = GAME, v = total - sum } end
    table.sort(rows, function(a, b) return a.v > b.v end)
    local parts, long = {}, {}
    for i = 1, math.min(4, #rows) do
      parts[#parts + 1] = string.format("%s %s%.0f KB|r", rows[i].n, kbColor(rows[i].v / 10), rows[i].v)
      long[#long + 1] = string.format("%s +%.0f KB", rows[i].n, rows[i].v)
    end
    local all = math.max(total, sum)
    S.perfMapOpen = { at = GetTime(), total = all, rows = rows,
      short = string.format("%s%.0f KB|r", kbColor(all / 10), all) .. (#parts > 0 and ("  -  " .. table.concat(parts, ",  ")) or "") }
    S:Print(string.format("Map opened: %.1f MB of Lua garbage in 1.5 s. Made by: %s", all / 1024, #long > 0 and table.concat(long, ", ") or "nothing measurable"))
  end)
end
local mapHooked
local function hookMap()
  if WorldMapFrame and not mapHooked then
    mapHooked = true
    WorldMapFrame:HookScript("OnShow", mapProbe)
  end
end
S:On("ADDON_LOADED", function(_, name) if name == "Blizzard_WorldMap" then hookMap() end end)
S:On("PLAYER_LOGIN", function() hookMap() end)

S:On("PLAYER_LOGIN", function() if debugOn() and S.db.global.perfOverlay then C_Timer.After(1, function() S:PerfOverlay(true) end) end end)
-- (Command Center loads before most addons: reading the setting here means the frame-script notes
-- see the other addons load - but only in debug mode)
S:On("ADDON_LOADED", function(_, name) if name == "CommandCenter" then capOn = debugOn() end end)
-- Debug mode on / off. Off stops everything that measures: overlay, report, deep check, notes
function S:PerfDebug(on)
  if on == nil then on = not debugOn() end
  S.db.global.debugMode = on and true or false
  capOn = on and true or false
  if on then
    S:Print("Debug mode on: performance overlay (/ccenter fps), /ccenter perf and the deep check are available. (For the deep check to see every addon's frame scripts, /reload once.)")
  else
    if ov and ov:IsShown() then S:PerfOverlay(false) end
    S.db.global.perfOverlay = false
    if deep then S:PerfDeepStop() end
    if run then S:PerfStop() end
    S.perf = nil
    wipe(scriptLog)
    S:Print("Debug mode off: Command Center measures nothing.")
  end
  if S.RefreshSettings then pcall(S.RefreshSettings, S) end
end
-- (the command is /ccenter debug, in Core.lua)
