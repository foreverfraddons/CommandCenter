-- The guided tour (spotlight style). Each step opens the right place, frames what it
-- talks about in glowing gold (the rest of the screen dims), a hand cursor shows the
-- click, and short examples play with pretend players. Nothing is saved or sent.
-- Every step says whether it's needed or optional. The full manual is the Guide
-- (Guide.lua): the same topics as a scrolling storybook you can reopen any time.
local _, S = ...
local UI = S.UI

local function ic(path, size) return "|T" .. path .. ":" .. (size or 14) .. ":" .. (size or 14) .. ":0:0:64:64:5:59:5:59|t " end
local GOLD, GRN, GRY, WHT = "|cffffd100", "|cff55ff55", "|cff999999", "|cffffffff"
local function cmd(t) return "|cffffff00" .. t .. "|r" end

-- pretend players used in the examples
local FAKE = { "Zalia Moonfang", "Grukk Stonefist", "Borak Ashmane", "Nyx Duskwhisper" }
local function fake(i) return "|cff" .. ({ "ff7d0a", "c79c6e", "0070de", "fff569" })[i] .. FAKE[i] .. "|r" end

local function itemLink(id, name, q)
  return (S.ItemLink and S.ItemLink(id)) or ("|cff" .. (q or "a335ee") .. "|Hitem:" .. id .. "::::::::60:::::|h[" .. name .. "]|h|r")
end

---------------------------------------------------------------------------
-- Finding things on screen
---------------------------------------------------------------------------
local function main() return S.MainFrame and S:MainFrame() end
local function panel(id) local t = S.tabsById[id]; return t and t.panel end
local function tabButton(id) local t = S.tabsById[id]; return t and t.button end
local function findButton(root, text, depth)
  if not root or (depth or 0) > 6 or not root.GetChildren then return nil end
  for _, c in ipairs({ root:GetChildren() }) do
    if c.GetText and c:IsShown() then
      local ok, t = pcall(c.GetText, c)
      if ok and type(t) == "string" and t:find(text, 1, true) == 1 then return c end
    end
    local hit = findButton(c, text, (depth or 0) + 1)
    if hit then return hit end
  end
end
local function subTab(id, label)
  local p = panel(id)
  if not (p and p.tabs) then return end
  for i, b in ipairs(p.tabs.buttons or {}) do
    if b.label and b.label:GetText() == label then return i, b end
  end
end
local function selectSub(id, label)
  local i = subTab(id, label)
  local p = panel(id)
  if i and p then p.tabs:Select(i) end
end

---------------------------------------------------------------------------
-- Examples ("fake tests") that run real windows with fake data
---------------------------------------------------------------------------
local timers = {}
local function later(sec, fn)
  local t = { cancelled = false }
  timers[#timers + 1] = t
  C_Timer.After(sec, function() if not t.cancelled then fn() end end)
end
local function cancelTimers() for _, t in ipairs(timers) do t.cancelled = true end wipe(timers) end

local demos = {}

demos.bell = {
  run = function()
    S:Notify("demo:1", { title = FAKE[2] .. " (whisper)", text = "Example - want to run a dungeon later?",
      icon = "Interface\\Icons\\INV_Letter_02", sound = false })
    later(1.2, function()
      S:Notify("demo:2", { title = "Reminder: dungeon at 20:00", text = "Example - your reminder", icon = "Interface\\Icons\\INV_Misc_PocketWatch_01", sound = false })
    end)
  end,
  cleanup = function() if S.RemoveNotifs then S:RemoveNotifs("demo:") end end,
}

demos.tools = {
  run = function() later(0.8, function() if S.ShowTools then S:ShowTools() end end) end,
  cleanup = function() local w = _G.CC_Tools; if w then w:Hide() end end,
}

demos.messages = {
  run = function()
    local who = FAKE[1]
    S.demoConvos = { [who] = { msgs = {
      { who = who, to = S.me, time = S.now() - 3600, plain = "Hey! Up for a dungeon on Saturday?", _key = "demo1" },
      { who = S.me, to = who, time = S.now() - 3500, plain = "Wouldn't miss it!", _key = "demo2" },
    } } }
    S.demo = S.demo or {}
    S.demo.mailst = { ["demo2|" .. who] = { read = true, _t = S.now() - 3400 } }
    -- 1) a message arrives while you're busy: the pop-up box
    if S.MsgToast then S:MsgToast(who, "Can you bring some fire resist potions? I'm all out :(", nil, true) end
    -- 2) open the chat
    later(2.5, function()
      if S.MsgToast then local t = _G.CC_MessageToast; if t then t:Hide() end end
      local c = S.demoConvos and S.demoConvos[who]
      if not c then return end
      c.msgs[#c.msgs + 1] = { who = who, to = S.me, time = S.now() - 60, plain = "Can you bring some fire resist potions? I'm all out :(", _key = "demo3" }
      S:ShowMessenger(who)
      if S.TourEvent then S:TourEvent("retarget", _G.CC_Messenger) end
    end)
    later(5, function()
      local c = S.demoConvos and S.demoConvos[who]
      if not c then return end
      c.msgs[#c.msgs + 1] = { who = who, to = S.me, time = S.now(), plain = "Try typing a reply below and press Enter - it's just a practice chat!", _key = "demo4" }
      S:ShowMessenger(who)
    end)
  end,
  cleanup = function()
    local m = _G.CC_Messenger
    S.demoConvos = nil
    if S.demo then S.demo.mailst = nil end
    if m and m:IsShown() then m:Hide() end
    local t = _G.CC_MessageToast; if t then t:Hide() end
  end,
}

demos.profile = {
  run = function() if S.ShowProfile then S:ShowProfile(S.me); if S.TourEvent then S:TourEvent("retarget", _G.CC_Profile) end end end,
  cleanup = function() local w = _G.CC_Profile; if w then w:Hide() end end,
}

demos.loot = {
  run = function()
    S.demo = S.demo or {}
    S.demo.lresp = {}
    S.demo.lsess = { demo = { open = true, mode = "roll", master = FAKE[3], time = S.now(),
      items = { itemLink(16865, "Breastplate of Might"), itemLink(18814, "Choker of the Fire Lord") } } }
    S:ShowLootPopup("demo")
    if S.TourEvent then S:TourEvent("retarget", _G.CC_LootPopup) end
  end,
  cleanup = function()
    if S.demo then S.demo.lsess, S.demo.lresp = nil, nil end
    local p = _G.CC_LootPopup; if p then p:Hide() end
    local c = _G.CC_Confirm; if c then c:Hide() end
  end,
}

demos.craft = {
  run = function()
    S.demo = S.demo or {}
    S.demo.corder = { demo1 = { who = S.me, crafter = FAKE[2], prof = "Tailoring", item = itemLink(2575, "Red Linen Shirt", "ffffff"), itemId = 2575, qty = 2,
      status = "accepted", cAvail = "Tonight 8-10pm server", cAvailT = S.now() - 600, rAvail = "After 9pm", rAvailT = S.now() - 300,
      note = "For the RP night!", time = S.now() - 3600, _t = S.now() - 300,
      mats = { { n = itemLink(2589, "Linen Cloth", "ffffff"), q = 4, h = 4 }, { n = itemLink(2320, "Coarse Thread", "ffffff"), q = 2, h = 1 },
               { n = itemLink(2604, "Red Dye", "ffffff"), q = 2, h = 2 } } } }
    S:ShowOrder("demo1")
    if S.TourEvent then S:TourEvent("retarget", _G.CC_OrderView) end
  end,
  cleanup = function()
    if S.demo then S.demo.corder = nil end
    local v = _G.CC_OrderView; if v then v:Hide() end
  end,
}


-- fold the page away and back with the quickbar arrow
demos.fold = {
  run = function()
    later(1.6, function() if S.QuickBarCollapse then S:QuickBarCollapse() end end)
    later(3.4, function() if S.QuickBarExpand then S:QuickBarExpand() end end)
  end,
  cleanup = function() if S.QuickBarExpand then S:QuickBarExpand() end end,
}
-- dock / border bar: open a page from its icon, then fold it away again
demos.barOpen = {
  run = function()
    if S.QuickBarCollapse then S:QuickBarCollapse() end
    later(1.4, function() S:SelectTab("roster") end)
    later(3.6, function() if S.QuickBarCollapse then S:QuickBarCollapse() end end)
  end,
  cleanup = function() end,
}
-- a pop-up and the text across the screen, like a reminder
demos.reminder = {
  run = function()
    later(1.2, function() if S.FireReminder then S:FireReminder({ text = "Example: your dungeon starts in 15 minutes!", popup = true, banner = true, sound = "ready" }, true) end end)
  end,
  cleanup = function() local b = _G.CC_ReminderBanner; if b then b:Hide() end; for i = 1, 3 do local t = _G["CC_Toast" .. i]; if t then t:Hide() end end end,
}
-- a notification pop-up
demos.popup = {
  run = function()
    later(1.0, function() if S.ShowToast then S:ShowToast({ title = "Example: Reminder", text = "Time to repair your gear.", key = "demo-pop", icon = "Interface\\Icons\\INV_Misc_PocketWatch_01" }) end end)
  end,
  cleanup = function() for i = 1, 3 do local t = _G["CC_Toast" .. i]; if t then t:Hide() end end end,
}

---------------------------------------------------------------------------
-- The steps
---------------------------------------------------------------------------
-- title, tag ("needed" / "optional"), text, tab (opened first), sub, target (fn -> frame),
-- lines (example lines), demo (live example), choices ({ text, tip, fn }), officer
local S_TIERLINE = "|cffcd7f32Bronze|r > |cffd8dee6Silver|r > |cffffd24aGold|r > |cffbfeef0Platinum|r > |cffc8f4ffDiamond|r"
local function setLook(look)
  local g = S.db.global
  if look == "quiet" then g.startMode = "hidden"; if S.SetDockMode then S:SetDockMode(false) end; if S.SetBorderMode then S:SetBorderMode(false) end
  elseif look == "bar" then g.startMode = "auto"; if S.SetDockMode then S:SetDockMode(false) end; if S.SetBorderMode then S:SetBorderMode(false) end
  elseif look == "dock" then g.startMode = "auto"; if S.SetDockMode then S:SetDockMode(true) end
  elseif look == "border" then g.startMode = "auto"; if S.SetBorderMode then S:SetBorderMode(true) end end
  g.tourLook = look
  if S.QuickBarExpand then S:QuickBarExpand() end
end
local STEPS = {
  { title = "Welcome to Command Center!", tag = "needed",
    text = "Command Center is a utility hub and an upgrade for your interface: a dock, border bar or quick bar for everything you click, plus a set of tools - your bags in one window (BiB), a damage meter, a messenger for whispers, a Button Box, screenshots, reminders and more.\n\n" ..
      "You decide how much of it you see. It can sit quietly in the background until you need it, or become your main bar with your game buttons and other addons in one place.\n\n" ..
      "This tour takes a few minutes. The " .. GOLD .. "gold frame|r shows where things are and a hand shows what to click. " .. GRY .. "Skip any time; the Guide (" .. cmd("/ccenter guide") .. ") has everything again.|r",
    tab = "home", target = main },

  { title = "How do you want it to look?", tag = "optional",
    text = "Pick a look - watch each one below, then click the one you like. You can change it any time in " .. GOLD .. "Settings > Quickbar & dock|r.",
    target = main,
    choices = {
      { text = "Quiet", anim = "quiet", tip = "Command Center stays hidden. You still get pop-ups for whispers and reminders. Open it from the minimap or with /ccenter.", fn = function() setLook("quiet") end },
      { text = "Quickbar", anim = "fold", tip = "The normal look: a bar at the top of the window you can fold away. (Recommended to start.)", fn = function() setLook("bar") end },
      { text = "Dock", anim = "dock", tip = "A dock like on a Mac: big icons that grow as you hover them.", fn = function() setLook("dock") end },
      { text = "Border bar", anim = "border", tip = "A thin bar along the whole top of your screen. Your other UI moves out of its way.", fn = function() setLook("border") end },
    } },

  { title = "Opening and closing", tag = "needed",
    text = "Click the " .. GOLD .. "Command Center button|r on your minimap, or type " .. cmd("/ccenter") .. " (" .. cmd("/commandcenter") .. " works too).\n\n" ..
      GOLD .. "Escape|r folds the page away and leaves the quickbar. The " .. GOLD .. "X|r closes Command Center completely.",
    target = function() return _G.CC_Minimap end, place = "target",
    lines = { ic("Interface\\AddOns\\CommandCenter\\Media\\logo_round") .. "Click the button: open / close Command Center",
              "Drag the button: move it around the minimap",
              "|cffff3333(3)|r on the button = 3 things you haven't seen yet" } },

  { title = "The quickbar", tag = "needed",
    text = "The bar at the top is the " .. GOLD .. "quickbar|r with the main buttons.\n\n" ..
      "The " .. GOLD .. "arrow|r folds the page away and brings it back - watch. Drag the bar to any screen edge and it snaps there (left or right makes it stand up). The grip in its corner resizes it, even very thin. " .. GOLD .. "Right-click|r the bar for its options.",
    target = function() local m = main(); return m and m.qbArrow end, demo = "fold", cursor = true,
    lines = { "Arrow: fold the page away / bring it back", "Drag the bar to an edge: it snaps there", "Corner grip: longer, shorter, thinner" } },

  { title = "The home page", tag = "needed",
    text = "The home page has a " .. GOLD .. "tile for every tool|r. Click a tile to open that tool, click it again to close it. The " .. GOLD .. "house|r button brings you home.\n\n" ..
      "Pressing a button again undoes it: Home folds the page away, Settings takes you back to where you were.",
    tab = "home", target = function() local m = main(); return m and m.home end,
    lines = { "Tiles: BiB, Damage Meter, Messenger, Button Box, Screenshot, Reminders...",
              "Buttons: " .. GOLD .. "house|r Home, " .. GOLD .. "letter|r Messenger, " .. GOLD .. "bell|r notifications, " .. GOLD .. "cog|r Settings, " .. GOLD .. "toolbox|r Tools" } },

  { title = "Notifications and pop-ups", tag = "needed",
    text = "The " .. GOLD .. "bell|r collects everything new: reminders, whispers and more. Click one to jump straight to it. Each one also pops up for a few seconds.\n\n" ..
      "Don't like where pop-ups appear? " .. GOLD .. "Settings > Move / resize pop-ups|r. Turn them off there too.",
    target = function() return S.bellFrame end, demo = "bell", cursor = true,
    lines = { "Two example notifications are arriving...", "Click the bell to see them, click one to open it.", GRY .. "(The examples disappear on the next step.)|r" } },

  { title = "Messenger", tag = "needed",
    text = "Your " .. GOLD .. "whispers as chats|r - one per person, with bubbles, times, sounds and pop-ups. Answer right there.\n\n" ..
      "Start a chat by typing a name in the search box - names are suggested as you type. Watch: a whisper pops up, then the chat opens. " .. GRY .. "(The example is pretend - nothing is sent.)|r",
    tab = "home", target = function() local m = main(); return m and m.msgBtn end, demo = "messages", cursor = true,
    lines = { ic("Interface\\Icons\\INV_Letter_02") .. "Pop-up: click it to open the chat (not in combat)",
              "Cog in the Messenger: colours, pop-ups, sounds",
              "Settings: keep whispers out of the chat window" } },

  { title = "Smart suggestions", tag = "optional",
    text = "In a chat, Command Center reads the last few messages and offers the next step as buttons above the message box:\n\n" ..
      GOLD .. "Invite|r when someone asks for an invite, " .. GOLD .. "Remind me <time>|r when you agree on a time. The small x hides them.",
    target = function() local m = main(); return m and m.msgBtn end,
    lines = { fake(1) .. ": \"can I get an inv? dungeon at 8 tonight\"",
              "->  [ Invite " .. FAKE[1]:match("^%S+") .. " ]  [ Remind me 20:00 ]",
              GRY .. "Turn off in Settings > Smart message suggestions.|r" } },

  { title = "Tools and shortcuts", tag = "optional",
    text = "The " .. GOLD .. "toolbox|r turns every tool on and off: BiB, Damage Meter, Messenger, Button Box, Screenshot, Reminders, Summoner, Rotational and the Guide. Click a row to open or close it - a " .. GRN .. "green edge|r means it's open.\n\n" ..
      "Drag rows to reorder, drag one out to remove it (the " .. GOLD .. "+|r brings it back). Right-click a tool to make a round shortcut you can put anywhere on your screen.",
    target = function() local m = main(); return m and m.toolsBtn end, demo = "tools", cursor = true,
    lines = { "Click a row: open / close that tool", "Drag a row out: remove it (the + brings it back)", "Right-click: shortcut icon for your screen" } },

  { title = "BiB - Built-in Bag", tag = "optional",
    text = "All your bags in " .. GOLD .. "one window|r (Tools > " .. GOLD .. "BiB|r): sorted by type, quality, name, item level, value and more, grouped into sections (equipment, consumables, trade goods, junk...), with a search box and a one-click " .. GOLD .. "Clean up|r that really tidies your bags.\n\n" ..
      "Style it your way - slot size, slots per row, spacing, background texture and colour. Turned on, it opens instead of the game's bags (B, the bag buttons, vendors, mail, the bank). Use it?",
    target = main,
    choices = {
      { text = "Use BiB", tip = "BiB opens instead of the game's bags.", isOn = function() return S.BiBIsOn and S:BiBIsOn() end,
        msg = "BiB on - press B to open your bags.", fn = function() if S.SetBiBOn then S:SetBiBOn(true) end end },
      { text = "Keep the game's bags", tip = "You can turn BiB on any time in Settings > Bags (BiB).", isOn = function() return not (S.BiBIsOn and S:BiBIsOn()) end,
        msg = "Keeping the game's bags - Settings > Bags (BiB) turns BiB on.", fn = function() if S.SetBiBOn and S:BiBIsOn() then S:SetBiBOn(false) end end },
    },
    lines = { "Sort, sections, search, clean up", "Your look: size, rows, colours, textures", cmd("/ccenter bib") } },

  { title = "Damage meter", tag = "optional",
    text = "A damage meter for you and your group: damage, healing, interrupts, dispels, deaths and more - live in a fight, ranked with each player's top spells after it (Tools > " .. GOLD .. "Damage Meter|r).\n\n" ..
      "It reads the game's own damage meter, so Command Center switches that on for you and hides its window. Turn it on?",
    target = main,
    choices = {
      { text = "Turn it on", tip = "Switches on the game's meter (hidden) so Command Center's meter can show the numbers.", isOn = function() return S.MeterIsOn and S:MeterIsOn() end,
        msg = "Damage meter on.", fn = function() if S.SetMeterOn then S:SetMeterOn(true) end end },
      { text = "Not now", tip = "You can turn it on any time in Settings > Damage meter.", isOn = function() return S.db.global.meterOn == false end,
        msg = "Damage meter stays off - Settings > Damage meter turns it on.", fn = function() if S.SetMeterOn then S:SetMeterOn(false) end end },
    },
    lines = { "Live in fights, ranked after them", "Hover a player for their top spells", "Share it to party / raid / guild chat" } },

  { title = "Button Box", tag = "optional",
    text = "A box you fill with any icons you like - tools, the game's menu buttons and bags, other addons' minimap icons (Tools > " .. GOLD .. "Button Box|r).\n\n" ..
      "The " .. GOLD .. "+|r adds icons, drag them to reorder, drag the corner to resize. Drag icons between the box and your dock / border bar. An addon icon in the box hides its minimap button, so there's never two.",
    target = main,
    lines = { "+ : pick icons for the box", "Drag between the box and your bar", cmd("/ccenter box") } },

  { title = "Screenshots", tag = "optional",
    text = "Tools > " .. GOLD .. "Screenshot|r: tune brightness, contrast, view distance and more while you look at the world, then " .. GOLD .. "Take picture|r - the interface vanishes, the picture is taken, and it comes right back.\n\n" ..
      "Optional: hide names and nameplates, a 3 second countdown to pose. Your settings go back to normal when you close it.",
    target = main,
    lines = { "Live sliders: brightness, contrast, gamma...", "Take picture: no interface in the shot", cmd("/ccenter screenshot") } },

  { title = "Reminders", tag = "optional",
    text = "Your own alarms (Tools > " .. GOLD .. "Reminders|r). Each one can pop up, run a line of text across your screen and play a sound - once, every day or every week. Reminders made from a chat's smart suggestions show up there too.\n\nWatch the example:",
    target = main, demo = "reminder",
    lines = { "Pop-up + text across the screen + a sound", "Change or test any reminder in its window", cmd("/ccenter reminders") } },

  { title = "More tools", tag = "optional",
    text = GOLD .. "Summoner|r (warlocks): collect 123s from your group and summon them with one click - with your soul shards and who still needs a summon.\n\n" ..
      GOLD .. "Rotational|r " .. GRY .. "(experimental)|r: set up your rotation and the right button glows when it's time to press it, with proc pop-ups. So far only tested on Enhancement Shaman.",
    target = function() local m = main(); return m and m.toolsBtn end,
    lines = { cmd("/ccenter summon"), cmd("/ccenter rotation") } },

  { title = "Dock, border bar and your other buttons", tag = "optional",
    text = "Want Command Center to be your whole bar? " .. GOLD .. "Dock mode|r and " .. GOLD .. "border mode|r put everything in one row. Then you can add:\n\n" ..
      "- the game's own buttons (character, spellbook, quest log, game menu...) and a bag button\n- XP and reputation bars\n- other addons' minimap icons (" .. GOLD .. "Plugins|r)\n- your tools (drag them from the toolbox)\n\nDrag icons to rearrange them, or off the bar to remove them.",
    tab = "settings", target = function() local m = main(); return m and m.content end,
    lines = { "Settings > Quickbar & dock", "Right-click the bar: Game menu buttons, Plugins, Bring back icons" } },

  { title = "Look and feel", tag = "optional",
    text = "Themes (Horde, Classic, Fel green or your own " .. GOLD .. "Custom colours|r with a colour picker or hue / saturation / brightness sliders), icons with or without circles, animations, font, size and scale.",
    tab = "settings", target = function() local m = main(); return m and m.content end },

  { title = "Settings", tag = "needed",
    text = "Everything here is optional. Type in the " .. GOLD .. "search box|r at the top to find any setting - it scrolls there and lights it up.\n\n" ..
      "Good ones to know: " .. GOLD .. "When I log in|r (show Command Center or start hidden), " .. GOLD .. "Streamer mode|r (hides whisper text on stream), pop-up position and size.",
    tab = "settings", target = function() local m = main(); return m and m.content end },

  { title = "You're ready!", tag = "needed",
    text = "That's the tour. The " .. GOLD .. "Guide|r has every tool and every setting explained, with little animations - open it any time from Tools or with " .. cmd("/ccenter guide") .. ".\n\nQuestions or bugs? Ask " .. GRN .. S.support .. "|r in game.",
    tab = "home", target = main, guide = true },
}
---------------------------------------------------------------------------
-- The same steps told for the look you picked: the dock and the border bar have no
-- quickbar buttons, so those steps point at the right icons and say the right things.
---------------------------------------------------------------------------
local function barIcon(key) return function() return (S.QuickBarIcon and S:QuickBarIcon(key)) or main() end end
local function lookNow()
  local g = S.db.global
  if g.dockMode then return "dock" end
  if g.borderMode then return "border" end
  if g.tourLook == "quiet" then return "quiet" end
  return "bar"
end
local THING = { dock = "dock", border = "border bar" }
local VARIANTS = {
  ["Opening and closing"] = {
    dock = { title = "Opening and closing",
      text = "Your " .. GOLD .. "dock|r sits at the bottom of the screen and comes up by itself when you log in.\n\n" ..
        "Click an icon to open it; click the same icon again to fold it away. " .. GOLD .. "Escape|r folds the page away too - the dock stays. " .. cmd("/ccenter") .. " and the minimap button open and fold the page.\n\n" ..
        "To hide the dock completely, right-click any icon > " .. GOLD .. "Hide Command Center|r.",
      target = main, place = "target",
      lines = { "Click an icon: open it", "Click it again (or Escape): fold it away", "Right-click an icon: more options" } },
    border = { title = "Opening and closing",
      text = "Your " .. GOLD .. "border bar|r runs along the top of the screen and comes up by itself when you log in. Everything else on your screen has moved down to make room for it.\n\n" ..
        "Click an icon to open it; click it again to fold it away. " .. GOLD .. "Escape|r folds the page away too - the bar stays. The " .. GOLD .. "X|r at its end hides Command Center completely.",
      target = main, place = "target",
      lines = { "Click an icon: open it", "Click it again (or Escape): fold it away", "Right-click the bar: options" } },
    quiet = { text = "Command Center now starts hidden and only pops up when something needs you. Open it with its " .. GOLD .. "minimap button|r or " .. cmd("/ccenter") .. ".\n\n" ..
        GOLD .. "Escape|r folds the page away; the " .. GOLD .. "X|r closes Command Center again." },
  },
  ["The quickbar"] = {
    dock = { title = "Your dock",
      text = "Home, the Messenger, notifications, Settings and Tools are icons here - and any tool you drag onto it. Icons grow as your mouse passes over them; a small " .. GRN .. "dot|r means that window is open.\n\n" ..
        "Watch: clicking an icon opens it, clicking it again folds it away.\n\n" ..
        "Drag an icon along the dock to move it; drag it off to remove it. " .. GOLD .. "Alt-drag|r moves the whole dock - near a screen edge it snaps there. The corner grip makes the icons bigger or smaller. Right-click for options.",
      target = barIcon("home"), demo = "barOpen", cursor = true,
      lines = { "Click an icon: open / fold it", "Drag along the dock: rearrange   Drag off: remove", "Alt-drag: move the dock   Grip: icon size" } },
    border = { title = "Your border bar",
      text = "A thin bar along the screen edge with Home, the Messenger, notifications, Settings, Tools and any tool you drag onto it. It sits under every other window, so you can put things on top of it.\n\n" ..
        "Watch: clicking an icon opens it, clicking it again folds it away.\n\n" ..
        "Drag icons to rearrange them (snap in a row, or anywhere in Freestyle), drag one off to remove it. Drag the bar toward another screen edge to move it there. The grip makes it thinner or thicker. Right-click the bar for options.",
      target = barIcon("home"), demo = "barOpen", cursor = true,
      lines = { "Click an icon: open / fold it", "Drag along the bar: rearrange   Drag off: remove", "Drag the bar to another edge: it moves there" } },
    quiet = { text = "When you do open Command Center, this bar at the top is the " .. GOLD .. "quickbar|r with the main buttons. The " .. GOLD .. "arrow|r folds the page away and brings it back - watch. Drag the bar to a screen edge and it snaps there; the corner grip resizes it." },
  },
  ["The home page"] = {
    dock = { text = "The " .. GOLD .. "house|r icon in your dock opens the home page: a tile for every tool. Click a tile to open that tool, click it again to close it.\n\nClick the house again to fold the page away." },
    border = { text = "The " .. GOLD .. "house|r icon on your border bar opens the home page: a tile for every tool. Click a tile to open that tool, click it again to close it.\n\nClick the house again to fold the page away." },
  },
  ["Notifications and pop-ups"] = {
    dock = { target = barIcon("bell"), text = "The " .. GOLD .. "bell|r icon in your dock collects everything new: reminders, whispers and more. A red number shows how many. Click it to see them, click one to jump to it. Each one also pops up for a few seconds.\n\n" ..
        GOLD .. "Settings > Move / resize pop-ups|r puts the pop-up box wherever you like." },
    border = { target = barIcon("bell"), text = "The " .. GOLD .. "bell|r icon on your border bar collects everything new: reminders, whispers and more. A red number shows how many. Click it to see them, click one to jump to it. Each one also pops up for a few seconds.\n\n" ..
        GOLD .. "Settings > Move / resize pop-ups|r puts the pop-up box wherever you like." },
  },
  ["Messenger"] = {
    dock = { target = barIcon("tool:Messenger") }, border = { target = barIcon("tool:Messenger") },
  },
  ["Smart suggestions"] = {
    dock = { target = barIcon("tool:Messenger") }, border = { target = barIcon("tool:Messenger") },
  },
  ["Tools and shortcuts"] = {
    dock = { target = barIcon("tools"), text = "The " .. GOLD .. "toolbox|r icon turns every tool on and off: BiB, Damage Meter, Messenger, Button Box, Screenshot, Reminders and more. Click a row to open or close it - a " .. GRN .. "green edge|r means it's open.\n\n" ..
        GOLD .. "Drag a tool from the toolbox onto your dock|r to give it its own icon there. Drag rows to reorder, drag one out to remove it (the + brings it back)." },
    border = { target = barIcon("tools"), text = "The " .. GOLD .. "toolbox|r icon turns every tool on and off: BiB, Damage Meter, Messenger, Button Box, Screenshot, Reminders and more. Click a row to open or close it - a " .. GRN .. "green edge|r means it's open.\n\n" ..
        GOLD .. "Drag a tool from the toolbox onto your border bar|r to give it its own icon there. Drag rows to reorder, drag one out to remove it (the + brings it back)." },
  },
  ["Dock, border bar and your other buttons"] = {
    dock = { title = "More for your dock",
      text = "Your dock can hold more than Command Center. Right-click it to add:\n\n- the game's own buttons (character, spellbook, quest log, game menu...) and a bag button\n- other addons' minimap icons (" .. GOLD .. "Plugins|r)\n- your tools (drag them from the toolbox)\n\n" ..
        "Settings > Quickbar & dock also has XP and reputation bars, icon spacing, and toggles to hide the game's own buttons and bars.",
      lines = { "Right-click the dock: Game menu buttons & bags, Plugins, Bring back icons", "Settings > Quickbar & dock: spacing, XP bars, hide the game's copies" } },
    border = { title = "More for your border bar",
      text = "Your border bar can hold more than Command Center. Right-click it to add:\n\n- the game's own buttons (character, spellbook, quest log, game menu...) and a bag button\n- other addons' minimap icons (" .. GOLD .. "Plugins|r)\n- your tools (drag them from the toolbox)\n\n" ..
        "Settings > Quickbar & dock also has XP and reputation bars, Snap or Freestyle icons, icon spacing, and toggles to hide the game's own buttons and bars.",
      lines = { "Right-click the bar: Game menu buttons & bags, Plugins, Bring back icons", "Settings > Quickbar & dock: Freestyle, spacing, XP bars" } },
  },
}
local function resolve(st)
  local v = VARIANTS[st.title]
  local over = v and v[lookNow()]
  if not over then return st end
  local out = {}
  for k, val in pairs(st) do out[k] = val end
  for k, val in pairs(over) do out[k] = val end
  return out
end
S.TourResolveStep = function(i) return STEPS[i] and resolve(STEPS[i]) end

-- officer-only steps are left out of a member's tour
local ALL_STEPS = {}
for i, st in ipairs(STEPS) do ALL_STEPS[i] = st end
function S:TourSteps()
  local officer = S.IsOfficer and S:IsOfficer()
  for i = #STEPS, 1, -1 do STEPS[i] = nil end
  for _, st in ipairs(ALL_STEPS) do if not st.officer or officer then STEPS[#STEPS + 1] = st end end
  return STEPS
end
S.TUTORIAL_STEPS = STEPS

---------------------------------------------------------------------------
-- Glow frame + dimmer
---------------------------------------------------------------------------
local glow, dim, win
local cur, curTarget, activeDemo

local function buildGlow()
  glow = CreateFrame("Frame", "CC_TourGlow", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  glow:SetFrameStrata("FULLSCREEN_DIALOG")
  glow:EnableMouse(false)
  glow:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 16 })
  glow:SetBackdropBorderColor(1, 0.82, 0, 1)
  -- outer soft glow (pulses)
  glow.outer = CreateFrame("Frame", nil, glow, BackdropTemplateMixin and "BackdropTemplate" or nil)
  glow.outer:SetPoint("TOPLEFT", -7, 7); glow.outer:SetPoint("BOTTOMRIGHT", 7, -7)
  glow.outer:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 22 })
  glow.outer:SetBackdropBorderColor(1, 0.75, 0.1, 0.6)
  glow.corner = {}
  for i, pt in ipairs({ "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }) do
    local t = glow:CreateTexture(nil, "OVERLAY")
    t:SetTexture("Interface\\Cooldown\\star4"); t:SetBlendMode("ADD"); t:SetSize(28, 28); t:SetPoint("CENTER", glow, pt)
    t:SetVertexColor(1, 0.85, 0.2)
    glow.corner[i] = t
  end
  local acc = 0
  glow:SetScript("OnUpdate", function(self, el)
    acc = acc + el
    local a = 0.55 + 0.45 * math.sin(acc * 4)
    self.outer:SetAlpha(a)
    for _, t in ipairs(self.corner) do t:SetAlpha(0.4 + 0.6 * a) end
    if curTarget and not curTarget:IsVisible() then self:Hide(); dim:Hide() end
  end)
  glow:Hide()

  dim = CreateFrame("Frame", nil, UIParent)
  dim:SetFrameStrata("FULLSCREEN"); dim:SetAllPoints(UIParent); dim:EnableMouse(false)
  dim.t = {}
  for i = 1, 4 do local t = dim:CreateTexture(nil, "BACKGROUND"); t:SetColorTexture(0, 0, 0, 0.5); dim.t[i] = t end
  dim:SetScript("OnUpdate", function(self)
    if not glow:IsShown() then return end
    local L, R, T, B = glow:GetLeft(), glow:GetRight(), glow:GetTop(), glow:GetBottom()
    if not L then return end
    local W, H = UIParent:GetWidth(), UIParent:GetHeight()
    local function put(t, x1, y1, x2, y2)
      t:ClearAllPoints()
      t:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x1, y1)
      t:SetSize(math.max(0.1, x2 - x1), math.max(0.1, y2 - y1))
    end
    put(self.t[1], 0, T, W, H)        -- above
    put(self.t[2], 0, 0, W, B)        -- below
    put(self.t[3], 0, B, L, T)        -- left
    put(self.t[4], R, B, W, T)        -- right
  end)
  dim:Hide()
end

local function placeCallout(target, mode)
  win:ClearAllPoints()
  local m = main()
  local sw = UIParent:GetWidth()
  local anchor = (mode == "target" or not (m and m:IsShown())) and target or m
  if not anchor or not anchor.GetRight or not anchor:GetRight() then win:SetPoint("CENTER") return end
  local s = anchor:GetEffectiveScale() / UIParent:GetEffectiveScale()
  local right = anchor:GetRight() * s
  local left = anchor:GetLeft() * s
  if right + win:GetWidth() + 16 <= sw then
    win:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 14, mode == "target" and 0 or -30)
  elseif left - win:GetWidth() - 16 >= 0 then
    win:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -14, mode == "target" and 0 or -30)
  else
    win:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -20, 120)
  end
end

local function highlight(target, mode)
  if not glow then buildGlow() end
  curTarget = target
  if not target or not target:IsVisible() then glow:Hide(); dim:Hide(); return end
  glow:ClearAllPoints()
  glow:SetPoint("TOPLEFT", target, "TOPLEFT", -6, 6)
  glow:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", 6, -6)
  glow:Show()
  -- dim the rest, except during a live example (its windows need to stay bright)
  dim:SetShown(activeDemo == nil)
end

---------------------------------------------------------------------------
-- The hand: glides from the tour window to the thing to click and "clicks" it,
-- over and over while the step is open (the tour's little GIF)
---------------------------------------------------------------------------
local hand
local function uiPos(f)
  local x, y = f:GetCenter()
  if not x then return nil end
  local s = (f:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
  return x * s, y * s
end
local function buildHand()
  hand = CreateFrame("Frame", "CC_TourHand", UIParent)
  hand:SetFrameStrata("TOOLTIP"); hand:SetSize(32, 32); hand:EnableMouse(false)
  hand.tex = hand:CreateTexture(nil, "OVERLAY", nil, 2); hand.tex:SetTexture("Interface\\CURSOR\\Point"); hand.tex:SetAllPoints()
  hand.ping = hand:CreateTexture(nil, "OVERLAY", nil, 1); hand.ping:SetTexture(UI.ART.ring); hand.ping:SetPoint("CENTER", hand, "TOPLEFT", 4, -4)
  hand.ping:SetVertexColor(1, 0.82, 0.2); hand.ping:SetBlendMode("ADD")
  hand:SetScript("OnUpdate", function(self, el)
    self.t = (self.t or 0) + el
    local T = self.t % 3.2
    local fx, fy, tx, ty = self.fx, self.fy, self.tx, self.ty
    if not tx then self:Hide() return end
    local p = math.min(1, T / 1.1)
    p = 1 - (1 - p) * (1 - p)                     -- ease out
    local x, y = fx + (tx - fx) * p, fy + (ty - fy) * p
    self:ClearAllPoints(); self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x - 4, y + 4)
    if T > 1.2 and T < 1.8 then
      local k = (T - 1.2) / 0.6
      self.ping:SetSize(10 + 40 * k, 10 + 40 * k); self.ping:SetAlpha(1 - k); self.ping:Show()
      self.tex:SetSize(28, 28)
    else
      self.ping:Hide(); self.tex:SetSize(32, 32)
    end
    self:SetAlpha(T > 2.8 and math.max(0, (3.2 - T) / 0.4) or 1)
  end)
  hand:Hide()
end
local function pointAt(target)
  if not hand then buildHand() end
  if not target or not target:IsVisible() or not win then hand:Hide() return end
  local tx, ty = uiPos(target)
  local fx, fy = uiPos(win)
  if not tx or not fx then hand:Hide() return end
  hand.fx, hand.fy, hand.tx, hand.ty, hand.t = fx, fy, tx, ty, 0
  hand:Show()
end
local function hideHand() if hand then hand:Hide() end end

---------------------------------------------------------------------------
-- Callout window
---------------------------------------------------------------------------
local lineTimer
local function buildWin()
  win = UI:Window("CC_Tutorial", "Command Center Tour", 380, 320)
  win:SetFrameStrata("FULLSCREEN_DIALOG"); win:SetFrameLevel(50)
  local icon = win:CreateTexture(nil, "ARTWORK"); icon:SetTexture(S.LOGO); icon:SetTexCoord(unpack(S.LOGO_COORDS)); icon:SetSize(36, 36); icon:SetPoint("TOPLEFT", 20, -34)
  win.head = UI:Text(win, "", "large"); win.head:SetPoint("LEFT", icon, "RIGHT", 10, 0); win.head:SetPoint("RIGHT", -20, 0)
  win.body = UI:Text(win, "", "normal"); win.body:SetPoint("TOPLEFT", 22, -80); win.body:SetWidth(336); win.body:SetJustifyV("TOP"); win.body:SetSpacing(2)
  win.card = UI:Panel(win, 340, 60, { 0.02, 0.02, 0.02, 0.85 })
  win.cardTitle = UI:Text(win.card, GOLD .. "Example|r " .. GRY .. "(pretend players)|r", "small"); win.cardTitle:SetPoint("TOPLEFT", 10, -8)
  win.lines = {}
  for i = 1, 6 do
    local l = UI:Text(win.card, "", "small"); l:SetPoint("TOPLEFT", 12, -8 - i * 17); l:SetWidth(318); l:SetWordWrap(false)
    win.lines[i] = l
  end
  win.replay = UI:Button(win.card, "Play again", 80, 18); win.replay:SetPoint("TOPRIGHT", -6, -4)
  win.progress = UI:Bar(win, 340, 10); win.progress:SetPoint("BOTTOM", 0, 48)
  win.step = UI:Text(win, "", "small", "RIGHT"); win.step:SetPoint("BOTTOMRIGHT", -20, 60)
  win.next = UI:PrimaryButton(win, "Next", 90, 24); win.next:SetPoint("BOTTOMRIGHT", -18, 16)
  win.back = UI:Button(win, "Back", 70, 24); win.back:SetPoint("RIGHT", win.next, "LEFT", -6, 0)
  win.skip = UI:Button(win, "Skip tour", 80, 24, function() S:EndTour() end, "Close the tour. You can take it again from Settings, or read everything in the Guide.")
  win.skip:SetPoint("BOTTOMLEFT", 18, 16)
  win.guideBtn = UI:Button(win, "Open the Guide", 120, 24, function() S:EndTour(); if S.ShowGuide then S:ShowGuide() end end)
  win.guideBtn:SetPoint("LEFT", win.skip, "RIGHT", 6, 0)
  -- needed / optional
  win.tag = UI:Text(win, "", "small", "RIGHT"); win.tag:SetPoint("TOPRIGHT", -40, -40)
  -- answers for a question step
  win.choices = {}
  for i = 1, 4 do
    local b = UI:Button(win, "", 80, 24)
    b.glow = b:CreateTexture(nil, "BACKGROUND"); b.glow:SetTexture(UI.ART.glow); b.glow:SetBlendMode("ADD")
    b.glow:SetPoint("TOPLEFT", -8, 8); b.glow:SetPoint("BOTTOMRIGHT", 8, -8); b.glow:SetVertexColor(1, 0.82, 0.2, 0.7); b.glow:Hide()
    win.choices[i] = b
  end
  win.close:SetScript("OnClick", function() S:EndTour() end)
  win:SetScript("OnHide", function() if cur then S:EndTour(true) end end)
end

local function playLines(st)
  if lineTimer then lineTimer.cancelled = true end
  for _, l in ipairs(win.lines) do l:SetText(""); l:SetAlpha(1) end
  local lines = st.lines or {}
  local token = { cancelled = false }
  lineTimer = token
  for i, txt in ipairs(lines) do
    if win.lines[i] then
      C_Timer.After(0.35 + (i - 1) * 1.1, function()
        if token.cancelled then return end
        win.lines[i]:SetText(txt)
        if PlaySound and SOUNDKIT and SOUNDKIT.U_CHAT_SCROLL_BUTTON then PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON) end
      end)
    end
  end
end

local function stopDemo()
  cancelTimers()
  if activeDemo and demos[activeDemo] and demos[activeDemo].cleanup then pcall(demos[activeDemo].cleanup) end
  activeDemo = nil
end

local function runDemo(st)
  stopDemo()
  if st.demo and demos[st.demo] then
    activeDemo = st.demo
    local ok, err = pcall(demos[st.demo].run)
    if not ok then S:Debug("tour demo failed: " .. tostring(err)) end
    if dim then dim:Hide() end
  end
end

local function show(i)
  stopDemo()
  cur = i
  local st = resolve(STEPS[i])
  if st.tab then S:ShowMain(st.tab) elseif not (main() and main():IsShown()) then S:ShowMain() end
  if st.sub then selectSub(st.tab, st.sub) end
  win.head:SetText(st.title)
  win.body:SetText(st.text)
  win.tag:SetText(st.tag == "optional" and (GRY .. "OPTIONAL|r") or st.tag == "needed" and (GRN .. "GOOD TO KNOW|r") or "")
  -- last step: "Open the Guide" takes the Skip button's place (they'd overlap Back otherwise)
  win.guideBtn:SetShown(st.guide and true or false)
  win.skip:SetShown(not st.guide)
  win.guideBtn:ClearAllPoints(); win.guideBtn:SetPoint("BOTTOMLEFT", 18, 16)
  local bodyH = (win.body:GetStringHeight() or 60) + 4
  -- question step: answers under the text; with animated previews they sit in a 2 x 2 grid
  local nc = st.choices and #st.choices or 0
  local withPics = nc > 0 and st.choices[1].anim ~= nil and S.MakeGuideAnim ~= nil
  win.previews = win.previews or {}
  for _, pv in pairs(win.previews) do pv:Hide() end
  local SC = 0.92
  local PW, PH = (S.GUIDE_ANIM_SIZE or { 240, 135 })[1], (S.GUIDE_ANIM_SIZE or { 240, 135 })[2]
  win:SetWidth(withPics and (44 + 2 * PW * SC + 16) or 380)
  win.body:SetWidth(withPics and (2 * PW * SC + 12) or 336)
  bodyH = (win.body:GetStringHeight() or 60) + 4
  for ci, b in ipairs(win.choices) do
    local ch = st.choices and st.choices[ci]
    b:SetShown(ch ~= nil)
    if ch then
      b:SetText(ch.text); b:SetWidth(withPics and math.floor(PW * SC) or 80)
      b:ClearAllPoints()
      if withPics then
        local col, row = (ci - 1) % 2, math.floor((ci - 1) / 2)
        local x = 22 + col * (PW * SC + 16)
        local y = 80 + bodyH + 6 + row * (PH * SC + 40)
        local pv = win.previews[ch.anim]
        if not pv then
          pv = S:MakeGuideAnim(win, ch.anim)
          pv:SetScale(SC); pv:EnableMouse(true)
          pv.t = 0
          pv:SetScript("OnUpdate", function(self, el) self.t = self.t + el; if self.update then pcall(self.update, self.t) end end)
          win.previews[ch.anim] = pv
        end
        pv:ClearAllPoints(); pv:SetPoint("TOPLEFT", win, "TOPLEFT", x / SC, -y / SC)
        pv:SetScript("OnMouseUp", function() b:Click() end)
        local th = UI:Theme()
        local picked = S.db.global.tourLook == ({ quiet = "quiet", fold = "bar", dock = "dock", border = "border" })[ch.anim]
        UI.Flat(pv.edge, { 0, 0, 0 }, 0, picked and th.gold or th.edge, 1, picked and 2 or 1)
        pv:Show()
        b:SetPoint("TOPLEFT", win, "TOPLEFT", x, -(y + PH * SC + 4))
      else
        b:SetPoint("TOPLEFT", win, "TOPLEFT", 22 + (ci - 1) * 86, -80 - bodyH - 6)
      end
      if ch.isOn then
        local ok, on = pcall(ch.isOn); b.glow:SetShown(ok and on and true or false)
      else
        b.glow:SetShown(S.db.global.tourLook == ch.text:lower():gsub(" bar", "") or (S.db.global.tourLook == "bar" and ch.text == "Quickbar"))
      end
      b:SetScript("OnClick", function()
        pcall(ch.fn)
        for _, o in ipairs(win.choices) do o.glow:Hide() end
        b.glow:Show()
        -- the chosen picture gets a gold frame
        local th = UI:Theme()
        for key, pv in pairs(win.previews or {}) do
          UI.Flat(pv.edge, { 0, 0, 0 }, 0, key == ch.anim and th.gold or th.edge, 1, key == ch.anim and 2 or 1)
        end
        if ch.msg then S:Print(ch.msg)
        else S:Print("Look set: |cffffd100" .. ch.text .. "|r - change it any time in Settings > Quickbar & dock.") end
      end)
      b:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine(ch.text, 1, 0.82, 0); GameTooltip:AddLine(ch.tip or "", 1, 1, 1, true); GameTooltip:Show() end)
      b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
  end
  if withPics then bodyH = bodyH + 2 * (PH * SC + 40) + 6
  elseif nc > 0 then bodyH = bodyH + 36 end
  local n = st.lines and #st.lines or 0
  win.card:ClearAllPoints(); win.card:SetPoint("TOPLEFT", 20, -80 - bodyH - 8)
  win.card:SetHeight(28 + math.max(n, 1) * 17)
  win.card:SetShown(n > 0 or st.demo ~= nil)
  win.replay:SetScript("OnClick", function() playLines(st); runDemo(st); local t = st.target and st.target(); if not activeDemo then highlight(t, st.place) end end)
  win.replay:SetText(st.demo and "Run it again" or "Play again"); win.replay:SetWidth(st.demo and 96 or 80)
  local cardH = win.card:IsShown() and (win.card:GetHeight() + 10) or 0
  win:SetHeight(math.max(220, 80 + bodyH + cardH + 80))
  win.progress:SetValue(i, #STEPS)
  win.step:SetText("Step " .. i .. " of " .. #STEPS)
  win.back:SetEnabled(i > 1)
  win.next:SetText(i == #STEPS and "Finish" or "Next")
  win.next:SetScript("OnClick", function() if i == #STEPS then S:EndTour() else show(i + 1) end end)
  win.back:SetScript("OnClick", function() if i > 1 then show(i - 1) end end)
  win:Show(); win:Raise()
  -- let the tab draw, then frame the target and run the example
  C_Timer.After(0.05, function()
    if cur ~= i then return end
    local ok, t = pcall(function() return st.target and st.target() end)
    t = ok and t or nil
    highlight(t, st.place)
    placeCallout(t, st.place)
    playLines(st)
    hideHand()
    if st.cursor or st.place == "target" then C_Timer.After(0.1, function() if cur == i then pointAt(t) end end) end
    if st.demo then later(0.8, function() if cur == i then runDemo(st) end end) end
  end)
end

-- examples can move the gold frame onto a window they open
function S:TourEvent(what, arg)
  if not cur then return end
  if what == "retarget" and arg then
    C_Timer.After(0.05, function() if cur then highlight(arg); if dim then dim:Hide() end end end)
  elseif what == "lootPicked" then
    local l = win.lines[#(resolve(STEPS[cur]).lines or {}) + 1]
    if l then l:SetText(GRN .. "Locked in!|r In a real session the loot master now sees your pick.") end
  elseif what == "demoSent" then
    later(1.5, function()
      local c = S.demoConvos and S.demoConvos[arg]
      if not c then return end
      c.msgs[#c.msgs + 1] = { who = arg, to = S.me, time = S.now(), plain = "Perfect, thank you! See you Saturday :)", _key = "demo" .. (#c.msgs + 1) }
      S.demo = S.demo or {}; S.demo.mailst = S.demo.mailst or {}
      S.demo.mailst["demo" .. (#c.msgs - 1) .. "|" .. arg] = { read = true, _t = S.now() }
      S:ShowMessenger(arg)
    end)
  end
end

function S:EndTour(fromHide)
  stopDemo()
  hideHand()
  if lineTimer then lineTimer.cancelled = true end
  cur, curTarget = nil, nil
  if glow then glow:Hide() end
  if dim then dim:Hide() end
  S.db.global.tutorialDone = true
  if win and not fromHide then win:Hide() end
end

-- force: show even if done before; startStep: open on that step
function S:ShowTutorial(force, startStep)
  if S.db.global.tutorialDone and not force then return end
  if not win then buildWin() end
  S:TourSteps()
  show(math.max(1, math.min(#STEPS, tonumber(startStep) or 1)))
end

S:Listen("LOGIN", function()
  if not S.db.global.tutorialDone then C_Timer.After(6, function() S:ShowTutorial() end) end
end)
S:AddCommand("tour", "", "Take the guided tour again", function() S:ShowTutorial(true) end)
S.TourPointAt = function(f) pointAt(f) end
