-- Module revisions: a guard against files being rolled back.
-- Several chats build Command Center on this PC. Each module says which revision it is:
--     if S.ModuleRev then S:ModuleRev("UnitFrames", 75) end
-- At login the highest revision seen on this PC is remembered per module. If a module
-- loads with a LOWER revision, an older copy was written over a newer one: you're told
-- (chat line + a pop-up), and /ccenter versions lists everything.
local _, S = ...
S.revs = S.revs or {}

function S:ModuleRev(name, rev)
  rev = tonumber(rev)
  if type(name) == "string" and rev then S.revs[name] = rev end
end

local function store()
  local g = S.db and S.db.global
  if not g then return {} end
  g.moduleRevs = type(g.moduleRevs) == "table" and g.moduleRevs or {}
  return g.moduleRevs
end

-- modules now older than what this PC has had before
function S.RolledBack()
  local seen, out = store(), {}
  for name, rev in pairs(S.revs) do
    local best = tonumber(seen[name])
    if best and rev < best then out[#out + 1] = { name = name, rev = rev, best = best } end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

S:Listen("LOGIN", function()
  local seen = store()
  for name, rev in pairs(S.revs) do
    local best = tonumber(seen[name])
    if not best or rev > best then seen[name] = rev end
  end
  local back = S.RolledBack()
  if #back == 0 then return end
  local parts = {}
  for _, b in ipairs(back) do parts[#parts + 1] = b.name .. " (r" .. b.rev .. ", was r" .. b.best .. ")" end
  local msg = "Older files loaded: " .. table.concat(parts, ", ")
    .. ". An older copy was written over a newer one - ask the chat that owns it to put the newest back."
  S:Print("|cffff5555" .. msg .. "|r  (/ccenter versions)")
  if C_Timer and C_Timer.After and S.UI and S.UI.Alert then
    C_Timer.After(6, function() S.UI:Alert(msg .. "\n\n/ccenter versions lists them; /ccenter versions accept keeps the older ones on purpose.") end)
  end
end)

S:AddCommand("versions", "[accept]", "Module revisions - spots files rolled back to older copies", function(rest)
  local seen = store()
  if (rest or ""):lower() == "accept" then
    for name, rev in pairs(S.revs) do seen[name] = rev end
    S:Print("Current module revisions accepted.")
    return
  end
  local names = {}
  for name in pairs(S.revs) do names[#names + 1] = name end
  table.sort(names)
  if #names == 0 then S:Print("No module reports a revision yet.") return end
  for _, name in ipairs(names) do
    local rev, best = S.revs[name], tonumber(seen[name]) or S.revs[name]
    local flag = rev < best and ("  |cffff5555ROLLED BACK (newest seen r" .. best .. ")|r") or ""
    S:Print(name .. ": r" .. rev .. flag)
  end
end)
