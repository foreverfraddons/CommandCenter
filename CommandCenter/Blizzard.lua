-- Blizzard bits for the quickbar: the game's menu buttons (character, spellbook, talents,
-- achievements, quest log, ... game menu), a bag button, and XP / reputation info.
-- Each has a toggle to hide the game's own copy.
--
-- Taint notes: the menu and bag buttons in the bar are secure "click" buttons, so the game
-- does the actual click (works in combat too). Blizzard frames are only hidden / shown
-- out of combat, through hooks - no fields are written on Blizzard frames.
local _, S = ...
local UI = S.UI

local function G() return S.db.global end
local function inCombat() return InCombatLockdown and InCombatLockdown() end

---------------------------------------------------------------------------
-- Menu buttons
---------------------------------------------------------------------------
local MICRO = {
  { "CharacterMicroButton", "Character" },
  { "ProfessionMicroButton", "Professions" },
  { "PlayerSpellsMicroButton", "Talents & spellbook" },
  { "SpellbookMicroButton", "Spellbook & abilities" },
  { "TalentMicroButton", "Talents" },
  { "AchievementMicroButton", "Achievements" },
  { "QuestLogMicroButton", "Quest log" },
  { "GuildMicroButton", "Guild & communities" },
  { "SocialsMicroButton", "Social" },
  { "LFDMicroButton", "Group finder" },
  { "LFGMicroButton", "Group finder" },
  { "PVPMicroButton", "Player vs. player" },
  { "CollectionsMicroButton", "Collections" },
  { "EJMicroButton", "Adventure guide" },
  { "WorldMapMicroButton", "World map" },
  { "HousingMicroButton", "Housing" },
  { "StoreMicroButton", "Shop" },
  { "MainMenuMicroButton", "Game menu" },
  { "HelpMicroButton", "Help" },
}
local LABEL = {}
for _, m in ipairs(MICRO) do LABEL[m[1]] = m[2] end

-- the menu buttons this client actually has, in the game's order
function S:BlizzardMicroButtons()
  local out, seen = {}, {}
  local order = type(_G.MICRO_BUTTONS) == "table" and _G.MICRO_BUTTONS or nil
  local function add(name)
    if seen[name] then return end
    local f = _G[name]
    if f and f.GetObjectType and f:GetObjectType() == "Button" then
      seen[name] = true
      out[#out + 1] = { name = name, label = LABEL[name] or (name:gsub("MicroButton$", ""):gsub("(%l)(%u)", "%1 %2")), frame = f }
    end
  end
  if order then for _, n in ipairs(order) do add(n) end end
  for _, m in ipairs(MICRO) do add(m[1]) end
  return out
end

local function microIcon(f)
  local t = f.GetNormalTexture and f:GetNormalTexture()
  if t then
    local atlas = t.GetAtlas and t:GetAtlas()
    if atlas and atlas ~= "" then return nil, nil, atlas end
    local tex = t:GetTexture()
    if tex then return tex, t.GetTexCoord and { t:GetTexCoord() } or nil end
  end
end
local MICRO_FALLBACK = { CharacterMicroButton = "Interface\\Icons\\INV_Chest_Chain_05", AchievementMicroButton = "Interface\\Icons\\Achievement_Quests_Completed_08",
  QuestLogMicroButton = "Interface\\Icons\\INV_Misc_Book_08", GuildMicroButton = "Interface\\Icons\\INV_Shirt_GuildTabard_01",
  SpellbookMicroButton = "Interface\\Icons\\INV_Misc_Book_09", PlayerSpellsMicroButton = "Interface\\Icons\\INV_Misc_Book_09",
  TalentMicroButton = "Interface\\Icons\\Ability_Marksmanship", LFDMicroButton = "Interface\\Icons\\INV_Misc_GroupNeedMore",
  CollectionsMicroButton = "Interface\\Icons\\INV_Pet_BabyBlizzardBear", EJMicroButton = "Interface\\Icons\\INV_Misc_Book_17",
  MainMenuMicroButton = "Interface\\Icons\\INV_Misc_Gear_01", StoreMicroButton = "Interface\\Icons\\WoW_Store",
  ProfessionMicroButton = "Interface\\Icons\\INV_Misc_Note_01", SocialsMicroButton = "Interface\\Icons\\INV_Letter_02",
  PVPMicroButton = "Interface\\Icons\\Ability_DualWield", WorldMapMicroButton = "Interface\\Icons\\INV_Misc_Map_01",
  HelpMicroButton = "Interface\\Icons\\INV_Misc_QuestionMark" }

local function blzSelected()
  local g = G()
  g.blzButtons = type(g.blzButtons) == "table" and g.blzButtons or {}
  return g.blzButtons
end
function S:BlizzardButtonOn(name) return blzSelected()[name] and true or false end
function S:SetBlizzardButton(name, on)
  blzSelected()[name] = on and true or nil
  if S.QuickBarLayout then S:QuickBarLayout() end
end

local function bagFree()
  local free, total = 0, 0
  local CC = C_Container
  for bag = 0, 4 do
    local f = (CC and CC.GetContainerNumFreeSlots and CC.GetContainerNumFreeSlots(bag)) or (GetContainerNumFreeSlots and GetContainerNumFreeSlots(bag)) or 0
    local n = (CC and CC.GetContainerNumSlots and CC.GetContainerNumSlots(bag)) or (GetContainerNumSlots and GetContainerNumSlots(bag)) or 0
    free, total = free + (tonumber(f) or 0), total + (tonumber(n) or 0)
  end
  return free, total
end
S.BagFree = bagFree

-- items for the dock / border bar
function S:BlizzardItems(all)
  local items = {}
  local sel = blzSelected()
  for _, m in ipairs(S:BlizzardMicroButtons()) do
    if all or sel[m.name] then
      local f = m.frame
      -- The Game Menu button (and any micro button that only reacts to mouse down/up)
      -- ignores a secure "click", so open the menu ourselves instead.
      local plain = m.name == "MainMenuMicroButton"
        or (f.GetScript and not f:GetScript("OnClick") and f:GetScript("OnMouseUp") ~= nil)
      local click
      if plain then
        click = function()
          if InCombatLockdown and InCombatLockdown() and m.name ~= "MainMenuMicroButton" then
            S:Print(m.label .. " can't be opened from Command Center in combat.") return
          end
          if m.name == "MainMenuMicroButton" then
            -- Never call ToggleGameMenu(): like Escape it first cancels casting and
            -- targeting (SpellStopCasting etc.), which the game blocks for addons.
            -- Just show / hide the menu frame itself.
            local gm = _G.GameMenuFrame
            if not gm or (InCombatLockdown and InCombatLockdown()) then
              S:Print("Press Escape to open the game menu.") return
            end
            if gm:IsShown() then gm:Hide()
            else
              gm:Show()
              if gm.Raise then gm:Raise() end
              if PlaySound and SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPEN then PlaySound(SOUNDKIT.IG_MAINMENU_OPEN) end
            end
          else
            pcall(function()
              local down, up = f:GetScript("OnMouseDown"), f:GetScript("OnMouseUp")
              if down then down(f, "LeftButton") end
              if up then up(f, "LeftButton") end
            end)
          end
        end
      end
      items[#items + 1] = { key = "blz:" .. m.name, label = m.label, secure = (not plain) and f or nil, click = click, blizzard = true,
        iconFn = function()
          local tex, co, atlas = microIcon(f)
          if not tex and not atlas then return MICRO_FALLBACK[m.name] or "Interface\\Icons\\INV_Misc_QuestionMark" end
          return tex, co, atlas
        end,
        tip = function(tt)
          tt:AddLine(m.label, 1, 0.82, 0)
          local more = f.newbieText or (f.tooltipText ~= m.label and f.tooltipText) or nil
          if type(more) == "string" and more ~= "" then tt:AddLine(more, 1, 1, 1, true) end
        end,
        avail = function() return not f.IsEnabled or f:IsEnabled() end }
    end
  end
  if all or G().blzBags then
    local bp = _G.MainMenuBarBackpackButton
    items[#items + 1] = { key = "blz:bags", label = "Bags", secure = bp, blizzard = true,
      fallbackClick = function() if ToggleAllBags then ToggleAllBags() elseif OpenAllBags then OpenAllBags() end end,
      iconFn = function()
        local t = bp and (bp.icon or _G.MainMenuBarBackpackButtonIconTexture)
        local tex = t and t.GetTexture and t:GetTexture()
        return tex or "Interface\\Icons\\INV_Misc_Bag_08"
      end,
      count = function() local free = bagFree(); return free end,
      tip = function(tt)
        local free, total = bagFree()
        tt:AddLine("Bags", 1, 0.82, 0); tt:AddLine(free .. " of " .. total .. " slots free", 1, 1, 1)
      end }
  end
  return items
end

---------------------------------------------------------------------------
-- Hiding the game's own copies (out of combat only)
---------------------------------------------------------------------------
local hiddenBy = {}       -- frame -> true while we keep it hidden
local hooked = {}
local pending = false
local function keepHidden(f, on)
  if not f then return end
  if not hooked[f] then
    hooked[f] = true
    local function re(self) if hiddenBy[self] and not inCombat() then self:Hide() end end
    hooksecurefunc(f, "Show", re)
    if f.SetShown then hooksecurefunc(f, "SetShown", function(self, v) if v then re(self) end end) end
  end
  if on then
    if not hiddenBy[f] then hiddenBy[f] = true; f:Hide() end
  elseif hiddenBy[f] then
    hiddenBy[f] = nil; f:Show()
  end
end

local function microFrames()
  local list = {}
  for _, n in ipairs({ "MicroMenuContainer", "MicroMenu" }) do if _G[n] then list[#list + 1] = _G[n]; return list end end
  for _, m in ipairs(S:BlizzardMicroButtons()) do list[#list + 1] = m.frame end
  return list
end
local function bagFrames()
  if _G.BagsBar then return { _G.BagsBar } end
  local list = {}
  for _, n in ipairs({ "MainMenuBarBackpackButton", "CharacterBag0Slot", "CharacterBag1Slot", "CharacterBag2Slot", "CharacterBag3Slot",
      "CharacterReagentBag0Slot", "BagBarExpandToggle", "KeyRingButton" }) do
    if _G[n] then list[#list + 1] = _G[n] end
  end
  return list
end
local function xpFrames()
  local list = {}
  for _, n in ipairs({ "StatusTrackingBarManager", "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer",
      "MainMenuExpBar", "ReputationWatchBar", "MainMenuBarMaxLevelBar" }) do
    if _G[n] then list[#list + 1] = _G[n] end
  end
  return list
end

function S:ApplyBlizzardHiding()
  if inCombat() then pending = true return end
  pending = false
  local g = G()
  local active = g.dockMode or g.borderMode
  -- old clients keep the menu and bags in one frame: only hide it when both are hidden
  local both = _G.MicroButtonAndBagsBar
  if both and not _G.MicroMenuContainer and not _G.BagsBar then
    keepHidden(both, active and g.hideBlzMicro and g.hideBlzBags and true or false)
  end
  for _, f in ipairs(microFrames()) do keepHidden(f, active and g.hideBlzMicro and true or false) end
  for _, f in ipairs(bagFrames()) do keepHidden(f, active and g.hideBlzBags and true or false) end
  for _, f in ipairs(xpFrames()) do keepHidden(f, g.qbXPBars and g.hideBlzXP and true or false) end
end
S:On("PLAYER_REGEN_ENABLED", function() if pending then S:ApplyBlizzardHiding() end end)
S:On("PLAYER_ENTERING_WORLD", function() if S.db then C_Timer.After(2, function() S:ApplyBlizzardHiding() end) end end)

---------------------------------------------------------------------------
-- XP and reputation
---------------------------------------------------------------------------
function S:XPInfo()
  local level = UnitLevel and UnitLevel("player") or 1
  local maxLevel = (GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion()) or _G.MAX_PLAYER_LEVEL or 60
  if (IsXPUserDisabled and IsXPUserDisabled()) or level >= maxLevel then return nil end
  local cur, max = UnitXP("player") or 0, UnitXPMax("player") or 1
  return { cur = cur, max = max > 0 and max or 1, rested = GetXPExhaustion and GetXPExhaustion() or nil, level = level }
end

function S:RepInfo()
  local name, standing, minV, maxV, value
  if C_Reputation and C_Reputation.GetWatchedFactionData then
    local d = C_Reputation.GetWatchedFactionData()
    if d and d.name then
      name, standing = d.name, d.reaction
      minV, maxV, value = d.currentReactionThreshold or 0, d.nextReactionThreshold or 1, d.currentStanding or 0
    end
  elseif GetWatchedFactionInfo then
    name, standing, minV, maxV, value = GetWatchedFactionInfo()
  end
  if not name then return nil end
  local col = _G.FACTION_BAR_COLORS and _G.FACTION_BAR_COLORS[standing or 4]
  local label = standing and _G["FACTION_STANDING_LABEL" .. standing] or ""
  local cur, max = (value or 0) - (minV or 0), (maxV or 1) - (minV or 0)
  if max <= 0 then cur, max = 1, 1 end
  return { name = name, cur = cur, max = max, standing = label,
    r = col and col.r or 0.2, g = col and col.g or 0.7, b = col and col.b or 0.2 }
end
