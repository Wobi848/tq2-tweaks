-- Tests: Whole mod through main.lua: shade display, menu and tabs, gameplay settings, hooks, saved settings.
-- Run all tests with: lua5.4 tests/test_tq2tweaks.lua

local T = require("support")
local workDir, logLines, playerController, game = T.workDir, T.logLines, T.playerController, T.game
local sword, specialRing, instances, press = T.sword, T.specialRing, T.instances, T.press
local hooks, loadMapHooks, param, tick = T.hooks, T.loadMapHooks, T.param, T.tick
local check, allOf, last, playerLayerWidgets = T.check, T.allOf, T.last, T.playerLayerWidgets
local hudWidget, menuWidget, hudLabel, lastBars = T.hudWidget, T.menuWidget, T.hudLabel, T.lastBars
local menuLines, text = T.menuLines, T.text

-- The tests expect the release default (no diagnostics), whatever config.lua says while debugging.
require("config").DebugLog = false
require("config").TimingLog = false
dofile(workDir .. "/Scripts/main.lua")

tick()
check("2 of 3 shades, third at 20%", lastBars(3) == "1,1,0.2")
do
local label, labelWrites = hudLabel(), 0
local setLabelText = label.SetText
label.SetText = function(self, value) labelWrites = labelWrites + 1; return setLabelText(self, value) end
tick()
local writesUnchanged = labelWrites
game.remaining = 0.7
tick()
check("shade display redrawn only when the values change", writesUnchanged == 0 and labelWrites == 1)
label.SetText = setLabelText
game.remaining = 0.8
tick()
check("numbers without a word, rounded", hudLabel().text == "2/3  ·  20%")
check("display in the player layer below the Lyra UI (1000)", hudWidget().zOrder < 1000
    and hudWidget().owner == playerController)
check("bars made of colour areas instead of ProgressBar", #allOf("ProgressBar") == 0)
check("no menu without F5", menuWidget() == nil)

-- Each os.clock call advances one second from here on, so time-based caches always expire between ticks.
os.clock = (function(original) local offset = 0 return function() offset = offset + 1; return original() + offset end end)(os.clock)
local cutsceneActor = { IsValid = function() return true end, m_EventRunning = true }
instances.TQ2CutsceneQuestActor = { cutsceneActor }
tick()
check("cutscene running: display hidden", hudWidget().visibility == 1)
cutsceneActor.m_EventRunning = false
tick()
check("cutscene over: display back", hudWidget().visibility == 3)
-- A sequence without a cutscene actor: the game fades out its own HUD.
local gameHud = { IsValid = function() return true end, IsVisible = function() return true end,
                  GetRenderOpacity = function(self) return self.opacity end, IsActivated = function() return true end,
                  opacity = 0 }
instances.wbp_hud_C = { gameHud }
tick()
check("game HUD hidden (boss sequence): display hidden", hudWidget().visibility == 1)
gameHud.opacity = 1
tick()
check("game HUD back: display back", hudWidget().visibility == 3)
local hudStateLines = 0
for _, line in ipairs(logLines) do if line:match("Game HUD state") then hudStateLines = hudStateLines + 1 end end
check("HUD state not logged (diagnostics only with DebugLog)", hudStateLines == 0)
local staleHud = { IsValid = function() return true end, IsVisible = function() return false end,
                   GetRenderOpacity = function() return 1 end, IsActivated = function() return false end }
instances.wbp_hud_C = { staleHud, gameHud }
tick()
check("stale hidden game HUD next to a visible one: display stays", hudWidget().visibility == 3)

game.current = 3.0
tick()
check("all full", lastBars(3) == "1,1,1" and hudLabel().text == "3/3")

game.spirit = false
tick()
check("hidden without a Spirit character", hudWidget().visibility == 1)

end
press("F5")
tick()
check("F5 opens the menu in the player layer, below the game's menus (1000)", menuWidget() ~= nil
    and menuWidget().zOrder < 1000 and menuWidget().owner == playerController)
check("menu shows a preview without a Spirit character", hudLabel().text == "2/3  ·  50%")
check("movement blocked while the menu is open", playerController.moveLocks == 1)
local lines = menuLines()
check("menu title, tab strip, only the first tab's section", lines:match("TQ2 TWEAKS")
    and lines:match("%[ Shades %]") and lines:match("SHADE DISPLAY") and not lines:match("REWARDS")
    and lines:match("> Bar colour") ~= nil)
check("colour value shown", lines:match("<  Teal/Gold  >") ~= nil)

press("RIGHT_ARROW")
tick()
check("right: next colour", menuLines():match("Purple/White") ~= nil)
press("LEFT_ARROW")
press("LEFT_ARROW")
tick()
check("left: backwards, wrapping around", menuLines():match("Green/White") ~= nil)

press("DOWN_ARROW")
press("RIGHT_ARROW")
tick()
check("text colour changed", menuLines():match("> Text colour") and menuLines():match("<  Gold  >")
    and hudLabel().color.G == 0.82)

press("DOWN_ARROW")
press("RIGHT_ARROW")
tick()
check("display mode changed", menuLines():match("> Display") and menuLines():match("Bars only") ~= nil)

press("DOWN_ARROW")
press("RIGHT_ARROW")
press("RIGHT_ARROW")
tick()
check("size 1.2x -> font 36", menuLines():match("1%.2x") and hudLabel().fontSize == 36)

local before = hudWidget()
press("DOWN_ARROW")
press("RIGHT_ARROW")
press("DOWN_ARROW")
press("SHIFTRIGHT_ARROW")
tick()
check("old widget removed after a change", before.removed == true)
local position = nil
for _, slot in ipairs(allOf("Slot")) do position = slot.position or position end
check("moved by +5/+50", position.X == 5 and position.Y == 160)

check("experience and drop hooks not registered with default values",
    hooks["/Script/TQ2Gameplay.TQ2AttributeSetProgression:Server_GrantLevelProgress"] == nil
    and hooks["/Script/GrimVentory.GrimWorldItemReplicationHelper:LaunchDropList"] == nil)
check("crafting unchanged before switching on", sword.m_CraftingCostsToOverride == 0 and next(sword.imported) == nil)

press("PAGE_DOWN")
tick()
check("Page Down: Gameplay tab, first row experience", menuLines():match("%[ Gameplay %]")
    and menuLines():match("> Experience") ~= nil)
press("RIGHT_ARROW")
press("RIGHT_ARROW")
tick()
local grant = hooks["/Script/TQ2Gameplay.TQ2AttributeSetProgression:Server_GrantLevelProgress"].before
local progress = param(100)
grant(nil, progress, param(false))
check("experience x2: 100 -> 200", progress:get() == 200)
local loaded = param(100)
grant(nil, loaded, param(true))
check("experience: progress set outright (override) unchanged", loaded:get() == 100)

press("DOWN_ARROW")
press("DOWN_ARROW")
press("RIGHT_ARROW")
press("RIGHT_ARROW")
tick()
local launch = hooks["/Script/GrimVentory.GrimWorldItemReplicationHelper:LaunchDropList"]
local count = param(3)
launch.before(param(nil), param(nil), param(nil), param(nil), param(nil), count, param(nil))
check("loot +2: 3 -> 5 drops", count:get() == 5)

press("DOWN_ARROW")
press("RIGHT_ARROW")
press("RIGHT_ARROW")
tick()
local function near(value, expected) return math.abs(value - expected) < 1e-6 end
check("movement speed x1.25: MoveSpeedFactor 1.26 -> 1.575, MaxWalkSpeed untouched",
    menuLines():match("> Movement speed") and near(playerMovementSet.MoveSpeedFactor.CurrentValue, 1.575)
    and playerPawn.CharacterMovement.MaxWalkSpeed == 630)
-- The game recalculates after a buff.
playerMovementSet.MoveSpeedFactor.CurrentValue = 1.3
tick()
check("movement speed after the game recalculated: 1.3 -> 1.625",
    near(playerMovementSet.MoveSpeedFactor.CurrentValue, 1.625))
tick()
check("movement speed does not stack when applied repeatedly", near(playerMovementSet.MoveSpeedFactor.CurrentValue, 1.625))
check("game speed x1: nothing set", gameplayStatics.dilation == nil)

press("DOWN_ARROW")
press("RIGHT_ARROW")
press("RIGHT_ARROW")
press("RIGHT_ARROW")
tick()
check("game speed x2", gameplayStatics.dilation == 2)

press("DOWN_ARROW")
press("RIGHT_ARROW")
press("RIGHT_ARROW")
tick()
check("attribute points per level 2 -> 4", gameplaySettings.m_APperLevel == 4 and gameplaySettings.m_MasteryPointPerLevel == 1)
press("DOWN_ARROW")
press("DOWN_ARROW")
press("DOWN_ARROW")

press("PAGE_DOWN")
press("RIGHT_ARROW")
tick()
local anvilOpened = "/Script/TQ2Gameplay.TQ2PlayerCharacter:OnCraftingUIOpened"
local anvilClosed = "/Script/TQ2Gameplay.TQ2PlayerCharacter:OnCraftingUIClosed"
check("free crafting on: no change without an open anvil", menuLines():match("> Free")
    and sword.m_CraftingCostsToOverride == 0 and next(sword.imported) == nil)
hooks[anvilOpened].after(param(playerPawn))
check("anvil open: all 4 actions free", sword.m_CraftingCostsToOverride == 0x0F
    and sword.imported[0] ~= nil and sword.imported[3] ~= nil and sword.imported[4] == nil)
check("crafting: replacement cost gold 0, no resources", sword.imported[0]:match('SourceText="0"')
    and sword.imported[0]:match("Resources=%(%)") ~= nil)
check("item with its own cost override untouched", specialRing.m_CraftingCostsToOverride == 0x02
    and next(specialRing.imported) == nil)
hooks[anvilClosed].after(param(playerPawn))
check("anvil closed: normal costs", sword.m_CraftingCostsToOverride == 0 and specialRing.m_CraftingCostsToOverride == 0x02)
sword.imported = {}
hooks[anvilOpened].after(param(playerPawn))
check("opened again: free again, formulas not imported again", sword.m_CraftingCostsToOverride == 0x0F
    and next(sword.imported) == nil)
hooks[anvilClosed].after(param(playerPawn))

press("RIGHT_ARROW")
tick()
hooks[anvilOpened].after(param(playerPawn))
check("crafting off: opening the anvil changes nothing", sword.m_CraftingCostsToOverride == 0)
hooks[anvilClosed].after(param(playerPawn))
press("RIGHT_ARROW")
tick()

press("DOWN_ARROW")
tick()
check("anvil anywhere row in the crafting section, on by default", menuLines():match("> Anvil anywhere %(F6%)")
    and menuLines():match("<  On  >") ~= nil)

press("PAGE_DOWN")
tick()
check("damage meter invisible before the first hit", #playerLayerWidgets("Border") == 0)
check("damage hook not registered before switching on",
    hooks["/Script/TQ2Gameplay.TQ2Character:Multicast_HandleDamageReceived_Unreliable"] == nil)
press("RIGHT_ARROW")
tick()
local damaged = hooks["/Script/TQ2Gameplay.TQ2Character:Multicast_HandleDamageReceived_Unreliable"].before
local enemyCharacter = { IsValid = function() return true end, IsA = function(_, class) return class:match("AICharacter") ~= nil end }
local playerCharacter = { IsValid = function() return true end, IsA = function() return false end }
damaged(param(enemyCharacter), param(nil), param({ Damage = 120, CritType = 1 }))
damaged(param(enemyCharacter), param(nil), param({ Damage = 30, CritType = 0 }))
damaged(param(playerCharacter), param(nil), param({ Damage = 999, CritType = 0 }))
tick()
local meterTexts = {}
for _, text in ipairs(allOf("TextBlock", function(t) return t.text ~= nil end)) do meterTexts[#meterTexts + 1] = text.text end
local meterText = table.concat(meterTexts, "|")
check("damage meter in the player layer", #playerLayerWidgets("Border") == 1)
check("damage meter: only hits on enemies counted", meterText:match("Total  150") ~= nil
    and meterText:match("Hits 2  ·  Crits 1 %(50%%%)") ~= nil and meterText:match("Highest hit  120") ~= nil)

local meterBefore = last(playerLayerWidgets("Border"))
press("DOWN_ARROW")
press("RIGHT_ARROW")
tick()
check("damage meter position changed, panel rebuilt", menuLines():match("> Position")
    and menuLines():match("<  Top centre  >") and meterBefore.removed == true and #playerLayerWidgets("Border") == 2)

press("F7")
tick()
check("detail window stays closed while the F5 menu is open (they would overlap)",
    #allOf("TextBlock", function(t) return t.text ~= nil and t.text:match("^DAMAGE DETAILS") ~= nil end) == 0)
press("F7")
press("F5") -- close the menu
game.spirit = true
tick()
local compactBefore = last(playerLayerWidgets("Border"))
press("F7")
tick()
check("shade display stays visible next to the detail window", hudWidget().visibility == 3)
local detailWindow = last(playerLayerWidgets("Border"))
local detailTitle = last(allOf("TextBlock", function(t) return t.text ~= nil and t.text:match("^DAMAGE DETAILS") ~= nil end))
check("F7 opens the detail window, the compact panel steps aside", detailWindow ~= compactBefore and detailTitle ~= nil
    and compactBefore.removed == true and detailWindow.removed == nil)
check("detail window: table row per skill (without tags: Other)",
    #allOf("TextBlock", function(t) return t.text == "Other" end) > 0)
press("F7")
tick()
check("F7 closes the detail window, the compact panel comes back", detailWindow.removed == true
    and last(playerLayerWidgets("Border")) ~= detailWindow)
game.spirit = false
press("F5") -- reopen the menu for the following tests
tick()

local menuBeforeLoad, meterBeforeLoad = menuWidget(), last(playerLayerWidgets("Border"))
loadMapHooks[1]()
check("level change: menu and damage meter removed before the old world goes",
    menuBeforeLoad.removed == true and meterBeforeLoad.removed == true)
tick()
check("level change: rebuilt on the next loop", menuWidget() ~= menuBeforeLoad and menuWidget().removed == nil
    and last(playerLayerWidgets("Border")) ~= meterBeforeLoad)

press("PAGE_UP") -- back to the Items tab
for _ = 1, 5 do press("DOWN_ARROW") end -- anvil row, then the auto pickup rows
tick()
check("auto pickup section in the menu", menuLines():match("AUTO%-PICKUP") and menuLines():match("> Equipment from") ~= nil)
press("DOWN_ARROW")
tick()
check("loot filter row after the rarity row, off by default", menuLines():match("> Loot filter") ~= nil
    and menuLines():match("Loot filter %(loot_filter.html%)|<  Off  >") ~= nil)
press("DOWN_ARROW")
tick()
check("only-upgrades row under the loot filter, on by default", menuLines():match("> +only upgrades over worn gear") ~= nil
    and menuLines():match("only upgrades over worn gear|<  On  >") ~= nil)
press("DOWN_ARROW")
tick()
check("down at the end jumps to the tab's first row", menuLines():match("> Free") ~= nil)
press("UP_ARROW")
tick()
check("up at the start jumps to the tab's last row", menuLines():match("> +only upgrades") ~= nil)
press("PAGE_DOWN")
press("PAGE_DOWN")
tick()
check("Filter tab: info row when there is no loot filter file", menuLines():match("%[ Filter %]") ~= nil
    and menuLines():match("> Rules in loot_filter.lua|<  no file yet  >") ~= nil)
do
    local filterFile = io.open(workDir .. "/loot_filter.lua", "w")
    filterFile:write('return {\n    { name = "Helmet", minRarity = "Magic", needed = 2, types = { "head" }, affixes = {\n'
        .. '        "da_suffix_1_Health", "da_suffix_1_EnergyBarrier", "da_prefix_1_PerFireRes",\n    } },\n}\n')
    filterFile:close()
    tick() -- the check loop reads the file and refills the tab
    tick() -- the display loop rebuilds the panel
    check("Filter tab: rows per rule after the file appeared (on/off, rarity, affixes needed)",
        menuLines():match("Helmet|<  On  >") ~= nil and menuLines():match("rarity from|<  Magic  >") ~= nil
        and menuLines():match("affixes needed|<  2 of 3  >") ~= nil)
    press("DOWN_ARROW") -- Helmet on/off
    press("RIGHT_ARROW")
    press("DOWN_ARROW") -- rarity from
    press("RIGHT_ARROW")
    press("DOWN_ARROW") -- affixes needed
    press("RIGHT_ARROW")
    tick() -- edits written and the file read again
    tick()
    local edited = io.open(workDir .. "/loot_filter.lua", "r")
    local editedText = edited:read("a")
    edited:close()
    check("Filter tab: changes are written into loot_filter.lua and shown after the reload",
        editedText:find('{ name = "Helmet", minRarity = "Rare", needed = 3, enabled = false, types = { "head" }', 1, true) ~= nil
        and menuLines():match("Helmet|<  Off  >") ~= nil)
    os.remove(workDir .. "/loot_filter.lua")
    tick()
end
press("PAGE_DOWN")
tick()
check("Page Down after the last tab: the first one again", menuLines():match("%[ Shades %]")
    and menuLines():match("> Bar colour") ~= nil)

local menuBefore = menuWidget()
press("F5")
tick()
check("F5 closes the menu", menuBefore.removed == true)
check("movement free again after closing", playerController.moveLocks == 0)
check("preview gone after closing", hudWidget().visibility == 1)
local saved = dofile(workDir .. "/user_settings.lua")
check("saved", saved.OffsetX == 5 and saved.OffsetY == 160 and saved.Scale == 1.2
    and saved.ColorPreset == 4 and saved.TextColorPreset == 2 and saved.DisplayMode == 2
    and saved.XpMultiplier == 3 and saved.LootBonus == 3 and saved.AttributePointsPerLevel == 4
    and saved.FreeCrafting == 2 and saved.MoveSpeed == 3 and saved.GameSpeed == 4 and saved.DamageMeter == 2
    and saved.DamageMeterPosition == 2)

press("RIGHT_ARROW")
tick()
check("arrow keys do nothing while the menu is closed", dofile(workDir .. "/user_settings.lua").DamageMeter == 2)

-- Restart: saved values are loaded
package.loaded["settings"] = nil
local Settings = require("settings")
local reloaded = Settings.new(require("config"), function() end)
check("restart loads the saved values", reloaded.values.OffsetX == 5 and reloaded.values.ColorPreset == 4)

local file = io.open(workDir .. "/user_settings.lua", "w")
file:write("return { kaputt")
file:close()
local messages = {}
local fallback = Settings.new(require("config"), function(line) messages[#messages + 1] = line end)
check("broken file -> defaults + message", fallback.values.OffsetX == 0 and #messages == 1)
