-- Tests ShadeHud against a mocked UE4SS API (no game needed). Run from the project folder:
--   lua5.4 tests/test_shadehud.lua
-- The scripts are copied to a temp folder so the real mod's user_settings.lua stays untouched.

local projectDir = arg[0]:match("^(.*)/tests/") or "."
local workDir = os.tmpname()
os.remove(workDir)
assert(os.execute(string.format("mkdir -p '%s' && cp -r '%s/ShadeHud/Scripts' '%s/'", workDir, projectDir, workDir)))
package.path = workDir .. "/Scripts/?.lua;" .. package.path

-- Mocked UE4SS API ----------------------------------------------------------------------------

local logLines = {}
function print(line) logLines[#logLines + 1] = line end

-- Fields a test reads before they are set return nil instead of a fake method.
local FIELDS = { moveLocks = true, width = true, isFill = true, fullWidth = true, percent = true, text = true, position = true, removed = true, zOrder = true, owner = true,
                 fill = true, justify = true, color = true, visibility = true }

local created = {}
local function mock(kind)
    local object = { kind = kind, valid = true, inViewport = false, Font = { Size = 24 },
                     WidgetStyle = { FillImage = {}, BackgroundImage = {} } }
    setmetatable(object, { __index = function(self, method)
        if FIELDS[method] then return nil end
        return function(_, ...)
            local args = { ... }
            if method == "IsValid" then return self.valid end
            if method == "IsInViewport" then return self.inViewport end
            if method == "AddToPlayerScreen" or method == "AddToViewport" then
                self.inViewport = true; self.zOrder = args[1]; self.layer = method; return
            end
            if method == "SetOwningPlayer" then self.owner = args[1]; return end
            if method == "SetIgnoreMoveInput" then
                self.moveLocks = (rawget(self, "moveLocks") or 0) + (args[1] and 1 or -1); return
            end
            if method == "RemoveFromParent" then self.inViewport = false; self.removed = true; return end
            if method:match("^AddChild") then return mock("Slot") end
            if method == "SetWidthOverride" then
                -- The fill box is the one created with width 0; its parent bar has the full width.
                if self.width == nil and args[1] == 0 then self.isFill = true; self.fullWidth = lastBarWidth end
                if self.width == nil and args[1] ~= 0 then lastBarWidth = args[1] end
                self.width = args[1]; return
            end
            if method == "SetText" then self.text = args[1]; return end
            if method == "SetVisibility" then self.visibility = args[1]; return end
            if method == "SetFont" then self.fontSize = args[1].Size; return end
            if method == "SetPosition" then self.position = args[1]; return end
            if method == "SetJustification" then self.justify = args[1]; return end
            if method == "SetColorAndOpacity" then self.color = args[1].SpecifiedColor; return end
            if method == "SetFillColorAndOpacity" then self.fill = args[1]; return end
        end
    end })
    created[#created + 1] = object
    return object
end

gameplaySettings = { IsValid = function() return true end, m_APperLevel = 2, m_ActivePointsPerLevel = 2,
                     m_PassivePointsPerLevel = 2, m_MasteryPointPerLevel = 1 }
function StaticFindObject(path)
    if path == "/Script/TQ2Gameplay.TQ2CraftingComponent" then
        return { path = path, IsValid = function() return true end }
    end
    if path == "/Script/Engine.Default__GameplayStatics" then
        return gameplayStatics
    end
    if path == "/Script/TQ2Gameplay.Default__TQ2GameplaySettings" then
        return gameplaySettings
    end
    return { path = path }
end
function StaticConstructObject(class) return mock(class.path:match("%.(%w+)$")) end
function FindFirstOf(name) return mock(name) end
function FText(text) return text end
-- The controller's Pawn is the current playerPawn (tests swap the character, e.g. for the anvil).
local controllerMock = mock("PlayerController")
local playerController = setmetatable({}, { __index = function(_, key)
    if key == "Pawn" then return playerPawn end
    return controllerMock[key]
end })
playerPawn = { IsValid = function() return true end, GetAddress = function() return 77 end,
               CharacterMovement = { MaxWalkSpeed = 630, Velocity = { X = 0, Y = 0 }, IsValid = function() return true end },
               PlayerState = { IsValid = function() return true end, GetAddress = function() return 78 end } }
-- Values as logged in game: MaxWalkSpeed 630 = 500 x MoveSpeedFactor 1.26.
-- The set hangs below the ability system component, which belongs to the PlayerState.
local abilitySystem = { IsValid = function() return true end, GetAddress = function() return 79 end,
                        GetOuter = function() return playerPawn.PlayerState end }
playerMovementSet = { IsValid = function() return true end, MoveSpeedFactor = { CurrentValue = 1.26 },
                      GetOuter = function() return abilitySystem end }
gameplayStatics = { IsValid = function() return true end,
                    SetGlobalTimeDilation = function(self, _, factor) self.dilation = factor end }
local controllerLookups = 0
package.preload["UEHelpers"] = function()
    return { GetPlayerController = function() controllerLookups = controllerLookups + 1; return playerController end,
             GetPlayer = function() return playerPawn end }
end

local game = { current = 2.0, maximum = 3.0, remaining = 0.8, spirit = true }
local regen = { IsValid = function() return true end,
                GetRemainingDurationNormalized = function() return game.remaining end }
local viewModel = { IsValid = function() return true end,
                    GetMaximumShades = function() return game.spirit and game.maximum or 0 end,
                    GetCurrentShades = function() return game.current end,
                    GetShadeRegenEffectViewModel = function() return regen end }

-- Item descriptions with the per-item crafting cost override (bit mask + ImportText into slot 0..3).
local function itemDescription(address, mask)
    local item = { m_CraftingCostsToOverride = mask, imported = {} }
    local costsProperty = {
        ContainerPtrToValuePtr = function(_, owner, index) return { owner = owner, index = index } end,
        ImportText = function(_, text, data) data.owner.imported[data.index] = text end,
    }
    item.IsValid = function() return true end
    item.GetAddress = function() return address end
    item.GetFullName = function() return "TQ2ItemDescription /Game/Items/item_" .. address end
    item.Reflection = function() return { GetProperty = function(_, name)
        assert(name == "m_OverriddenCraftingCostByAction"); return costsProperty end } end
    return item
end
local sword = itemDescription(1, 0)
local specialRing = itemDescription(2, 0x02)

local instances = {
    TQ2PlayerCharacterViewModel = { viewModel },
    TQ2ItemDescription = { sword, specialRing },
    GrimAttributeSetMovement = { playerMovementSet },
}
function FindAllOf(className) return instances[className] end

Key = setmetatable({}, { __index = function(_, name) return name end })
ModifierKey = { SHIFT = "SHIFT", CONTROL = "CONTROL", ALT = "ALT" }
local keyBinds = {}
function RegisterKeyBind(key, modifiersOrCallback, callback)
    local modifiers = callback and modifiersOrCallback[1] or ""
    keyBinds[modifiers .. key] = callback or modifiersOrCallback
end
local function press(key) keyBinds[key]() end

local hooks = {}
-- Several modules may hook the same function; hooks[path] calls all of them (nil while none is registered).
local hookLists = {}
function RegisterHook(path, before, after)
    hookLists[path] = hookLists[path] or {}
    table.insert(hookLists[path], { before = before, after = after })
    hooks[path] = {
        before = function(...) for _, hook in ipairs(hookLists[path]) do if hook.before then hook.before(...) end end end,
        after = function(...) for _, hook in ipairs(hookLists[path]) do if hook.after then hook.after(...) end end end,
    }
end
local newObjectCallbacks = {}
local loadMapHooks = {}
function RegisterLoadMapPreHook(callback) loadMapHooks[#loadMapHooks + 1] = callback end
function NotifyOnNewObject(className, callback) newObjectCallbacks[className] = callback end
local function param(value)
    return { get = function() return value end, set = function(_, newValue) value = newValue end }
end

local loops = {}
function LoopInGameThreadWithDelay(_, callback) loops[#loops + 1] = callback end
function ExecuteInGameThreadWithDelay(_, callback) callback() end
function ExecuteInGameThread(callback) callback() end
local function tick() for _, loop in ipairs(loops) do loop() end end

-- Helpers ---------------------------------------------------------------------------------------

local failures = 0
local function check(label, condition)
    io.write((condition and "OK   " or "FAIL ") .. label .. "\n")
    if not condition then failures = failures + 1 end
end

local function allOf(kind, filter)
    local result = {}
    for _, object in ipairs(created) do
        if object.kind == kind and (filter == nil or filter(object)) then result[#result + 1] = object end
    end
    return result
end

local function last(list) return list[#list] end

-- TArray with ForEach(index, element) like UE4SS; returning true from the callback stops the loop.
local function container(values)
    return { ForEach = function(_, callback)
        for index = 1, #values do
            local element = { get = function() return values[index] end, set = function(_, value) values[index] = value end }
            if callback(index, element) then return end
        end
    end }
end

-- Both the shade display and the damage meter live in the player layer. They are told apart by the first
-- widget placed on their canvas (created right after UserWidget, WidgetTree, CanvasPanel).
local function playerLayerWidgets(firstChildKind)
    local result = {}
    for index, object in ipairs(created) do
        if object.kind == "UserWidget" and object.layer == "AddToPlayerScreen" and object.zOrder == 0
            and created[index + 3] and created[index + 3].kind == firstChildKind then
            result[#result + 1] = object
        end
    end
    return result
end

local function hudWidget()
    return last(playerLayerWidgets("VerticalBox"))
end

-- The F5 menu lives in the player layer too, one level above the HUD widgets (z-order 10).
local function menuWidget()
    return last(allOf("UserWidget", function(widget) return widget.layer == "AddToPlayerScreen" and widget.zOrder == 10 end))
end

-- The display numbers are the only centred text.
local function hudLabel()
    return last(allOf("TextBlock", function(text) return text.justify == 1 end))
end

local function lastBars(count)
    local fills, result = allOf("SizeBox", function(box) return box.isFill end), {}
    for index = #fills - count + 1, #fills do
        result[#result + 1] = string.format("%g", fills[index].width / fills[index].fullWidth)
    end
    return table.concat(result, ",")
end

-- Texts of the current menu panel only (switching tabs rebuilds the panel; older panels stay in `created`).
local function menuLines()
    local panel, start = menuWidget(), 1
    for index, object in ipairs(created) do
        if object == panel then start = index end
    end
    local lines = {}
    for index = start, #created do
        local text = created[index]
        if text.kind == "TextBlock" and text.justify == 0 and text.text ~= nil then
            lines[#lines + 1] = text.text
        end
    end
    return table.concat(lines, "|")
end

-- Tests -----------------------------------------------------------------------------------------

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
check("down at the end jumps to the tab's first row", menuLines():match("> Free") ~= nil)
press("UP_ARROW")
tick()
check("up at the start jumps to the tab's last row", menuLines():match("> Loot filter") ~= nil)
press("PAGE_DOWN")
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

local DamageMeterWidget = require("damage_meter_widget")
check("number format 1234 / 12.3k / 1.23M", DamageMeterWidget.formatNumber(1234) == "1234"
    and DamageMeterWidget.formatNumber(12345) == "12.3k" and DamageMeterWidget.formatNumber(1234567) == "1.23M")
local DamageMeter = require("damage_meter")
local meter = DamageMeter.new(5, 10)
DamageMeter.record(meter, 0, 100, false)
DamageMeter.record(meter, 4, 100, false)
check("DPS over the actual span at the start (200 in 4 s = 50)", DamageMeter.summary(meter, 4).dps == 50)
check("DPS only within the 5 s window (at 8 s: 100 / 5 = 20)", DamageMeter.summary(meter, 8).dps == 20)
DamageMeter.record(meter, 30, 40, true)
local fresh = DamageMeter.summary(meter, 30)
check("new fight after a 10 s pause", fresh.total == 40 and fresh.hits == 1 and fresh.crits == 1)
local typed = DamageMeter.new(5, 10, 30)
DamageMeter.record(typed, 100.2, 300, false, "Fire")
DamageMeter.record(typed, 101.5, 100, false, "Cold")
DamageMeter.record(typed, 101.7, 100, true, nil)
local typedSummary = DamageMeter.summary(typed, 102)
check("graph: 30 seconds, damage per second (second 100: 300, 101: 200, 102: 0)", #typedSummary.graph == 30
    and typedSummary.graph[28] == 300 and typedSummary.graph[29] == 200 and typedSummary.graph[30] == 0)
check("damage types: shares, largest first, unknown = Other", typedSummary.types[1].name == "Fire"
    and math.abs(typedSummary.types[1].share - 0.6) < 1e-9 and #typedSummary.types == 3)
check("running fight not ended", typedSummary.ended == false)
check("after 10 s without hits: last fight with average DPS", DamageMeter.summary(typed, 115).ended == true
    and math.abs(DamageMeter.summary(typed, 115).averageDps - 500 / 1.5) < 1e-9)
DamageMeter.reset(typed)
check("reset clears the meter", DamageMeter.summary(typed, 116) == nil)
check("text after the fight", DamageMeterWidget.lines({ ended = true, averageDps = 500, dps = 0, total = 500, duration = 1.5,
    hits = 3, crits = 1, highestHit = 300 })[1] == "DAMAGE  ·  last fight")
local DamageHook = require("damage_hook")
local DamageDetailWidget = require("damage_detail_widget")
local function tagNamed(name) return { TagName = { ToString = function() return name end } } end
check("damage type name from the tag", DamageHook.typeName(tagNamed("Damage.Type.VitalityDrain")) == "Vitality Drain"
    and DamageHook.typeName(tagNamed("Damage.Type.Cold")) == "Cold" and DamageHook.typeName(tagNamed("None")) == nil)
local function skillOf(description)
    return DamageHook.skillName({ "GrimAbilitySystem.Ability.AbilityFlag.Mastery.Spirit",
        "GrimAbilitySystem.Description." .. description })
end
check("skill from the description tag (as logged in game)",
    skillOf("bp_bga_player_sp_lich_m_soulBlight") == "Lich" and skillOf("bp_bga_player_sp_lich_basicAttack") == "Lich"
    and skillOf("bp_bga_player_sp_eidolonGuard_basicAttack_melee") == "Eidolon Guard"
    and skillOf("bp_bga_player_fo_automaton_m_coldAttachment_activation") == "Automaton"
    and skillOf("bp_bga_global_retaliation_p") == "Retaliation"
    and skillOf("bp_bga_player_sp_eidolonGuard_summon") == "Eidolon Guard"
    and DamageHook.skillName({ "GrimAbilitySystem.Ability.AbilityFlag.Skill" }) == nil)
local function playerAbility(description)
    return DamageHook.isPlayerAbility({ "GrimAbilitySystem.Description." .. description })
end
check("enemy hits on summons do not count (as logged in game)",
    playerAbility("bp_bga_player_fo_automaton_basicAttack") and playerAbility("bp_bga_global_retaliation_p")
    and DamageHook.isPlayerAbility({}) and not playerAbility("bp_bga_un_skeleton_archer_rangedAttack")
    and not playerAbility("bp_bga_wl_boar_charge"))
local skilled = DamageMeter.new(5, 10, 30)
DamageMeter.record(skilled, 1, 300, false, "Fire", "Lich")
DamageMeter.record(skilled, 1.5, 100, false, "Cold", nil)
local skillSummary = DamageMeter.summary(skilled, 2)
check("damage per skill: share of the total, hits without a skill under Other", #skillSummary.skills == 2
    and skillSummary.skills[1].name == "Lich" and math.abs(skillSummary.skills[1].share - 0.75) < 1e-9
    and skillSummary.skills[2].name == "Other")

local detailed = DamageMeter.new(5, 10, 60)
check("details before the first hit: empty, window says 'no fight yet'",
    DamageMeter.details(detailed, 0, 60).total == 0 and #DamageMeter.details(detailed, 0, 60).graph == 60
    and DamageDetailWidget.title(DamageMeter.details(detailed, 0, 60)):match("no fight yet") ~= nil)
DamageMeter.record(detailed, 10.1, 100, true, "Cold", "Lich")
DamageMeter.record(detailed, 10.5, 300, false, "Cold", "Lich")
DamageMeter.record(detailed, 11.2, 200, false, "Poison", "Automaton")
DamageMeter.record(detailed, 14.1, 400, false, "Cold", "Automaton")
local details = DamageMeter.details(detailed, 15, 60)
local lich, automaton = details.skills[2], details.skills[1]
check("details: best second, average over the fight's duration", details.peakDps == 400 and details.total == 1000
    and math.abs(details.averageDps - 1000 / 4) < 1e-9 and details.ended == false)
check("details per skill: damage, DPS, hits, crit rate, highest hit",
    automaton.name == "Automaton" and automaton.damage == 600 and lich.name == "Lich" and lich.damage == 400
    and lich.hits == 2 and lich.critShare == 0.5 and lich.highest == 300 and math.abs(lich.dps - 100) < 1e-9
    and math.abs(lich.share - 0.4) < 1e-9)
check("details: all damage types with damage", #details.types == 2 and details.types[1].name == "Cold"
    and details.types[1].damage == 800)
local lastSeconds = { details.graph[55], details.graph[56], details.graph[59] }
check("detail graph: seconds with damage per skill (for the stacked bars)", #details.graph == 60
    and lastSeconds[1].total == 400 and lastSeconds[1].bySkill.Lich == 400 and lastSeconds[2].bySkill.Automaton == 200
    and lastSeconds[3].total == 400)
check("detail table row", table.concat(DamageDetailWidget.skillCells(lich), "|") == "Lich|400|100|40%|2|50%|300")
local frozen = DamageMeter.details(detailed, 40, 60)
check("after the fight the graph ends at the last hit instead of scrolling on", frozen.ended == true
    and frozen.graph[60].total == 400 and frozen.graph[57].bySkill.Automaton == 200
    and DamageMeter.summary(detailed, 40, 30).graph[30] == 400)
check("compact graph stays 30 s long with 60 s of history", #DamageMeter.summary(detailed, 15, 30).graph == 30)
check("colour of the damage type", DamageMeterWidget.typeColor(require("config"), "Fire").R == 1.0
    and DamageMeterWidget.typeColor(require("config"), "Mystery") == require("config").DamageTypeDefaultColor)

-- Auto pickup on its own: categories by path/type tag, flag on for enabled kinds, original restored when off.
local AutoPickup = require("auto_pickup")
local categories = require("config").AutoPickupCategories
local function described(path, tag, canAutoPickup)
    return { IsValid = function() return true end, GetFullName = function() return "TQ2ItemDescription " .. path end,
             GetAddress = function() return path end, m_CanAutoPickup = canAutoPickup,
             m_Type = { TagName = { ToString = function() return tag end } } }
end
local scrapType = described("/Game/TQ2/Items/Crafting/da_item_scrap.da_item_scrap", "", false)
local potionType = described("/Game/TQ2/Items/Consumables/da_item_potion_health.da_item_potion_health", "GrimVentory.ItemType.Consumable", false)
local swordType = described("/Game/TQ2/Items/Weapons/da_sword_01.da_sword_01", "GrimVentory.ItemType.Weapon.Sword1H.Normal", false)
local goldType = described("/Game/TQ2/Items/Misc/da_item_gold.da_item_gold", "GrimVentory.ItemType.Currency", true)
local questType = described("/Game/TQ2/Items/Quest/da_quest_key.da_quest_key", "GrimVentory.ItemType.QuestItem", false)
instances.TQ2ItemDescription = { scrapType, potionType, swordType, goldType, questType }
check("auto pickup: categories recognised",
    categories[AutoPickup.categoryOf(categories, "/game/tq2/items/crafting/da_item_scrap")].Name == "Crafting materials"
    and categories[AutoPickup.categoryOf(categories, "grimventory.itemtype.consumable")].Name == "Potions"
    and categories[AutoPickup.categoryOf(categories, "grimventory.itemtype.weapon.sword1h.normal")].Name == "Equipment"
    and categories[AutoPickup.categoryOf(categories, "grimventory.itemtype.torso")].Name == "Equipment"
    and categories[AutoPickup.categoryOf(categories, "grimventory.itemtype.socketable.relic")].Name == "Charms & relics"
    and AutoPickup.categoryOf(categories, "grimventory.itemtype.currency") == nil
    and AutoPickup.categoryOf(categories, "grimventory.itemtype.questitem") == nil)
local pickupLog = {}
AutoPickup.apply(categories, { true, false, false, false }, function(line) pickupLog[#pickupLog + 1] = line end)
check("auto pickup materials on: only scrap switched on", scrapType.m_CanAutoPickup == true
    and potionType.m_CanAutoPickup == false and swordType.m_CanAutoPickup == false and goldType.m_CanAutoPickup == true)
check("auto pickup: overview logged once", #pickupLog == 3 and pickupLog[1]:match("Crafting materials=1") ~= nil)
AutoPickup.apply(categories, { true, true, false, false }, function() end)
check("auto pickup: potions added", potionType.m_CanAutoPickup == true and scrapType.m_CanAutoPickup == true)
AutoPickup.apply(categories, { false, false, false, false }, function() end)
AutoPickup.apply(categories, { true, true, true, true }, function() end)
check("auto pickup all on: quest items untouched", swordType.m_CanAutoPickup == true and questType.m_CanAutoPickup == false)
AutoPickup.apply(categories, { false, false, false, false }, function() end)
check("auto pickup off: original values back, gold untouched", scrapType.m_CanAutoPickup == false and swordType.m_CanAutoPickup == false
    and potionType.m_CanAutoPickup == false and goldType.m_CanAutoPickup == true)

-- Anvil anywhere: F6 opens the crafting window for the player, adding a crafting component if needed.
local anvil = { access = "none", opened = 0, closedByGame = 0 }
local craftingComponent = { IsValid = function() return true end, m_pInventory = { IsValid = function() return true end },
                            SetIsReplicated = function() end, Activate = function() end }
local anvilPlayerState = { IsValid = function() return true end, TryClearCraftingCache = function() anvil.cacheCleared = true end,
                           GetOrCreateCraftingCacheViewModel = function() end }
local anvilCharacter = {
    IsValid = function() return true end, PlayerState = anvilPlayerState, m_pCraftingComponent = nil,
    RootComponent = { GetRelativeTransform = function() return {} end },
    AddComponentByClass = function(_, class) anvil.addedClass = class; return craftingComponent end,
    GetCraftingAccess = function() return nil end,
    SetCraftingAccess = function(_, access) anvil.access = access end,
    ForceNetUpdate = function() end,
    OnCraftingUIOpened = function(_, provider) anvil.opened = anvil.opened + 1; anvil.provider = provider end,
    OnCraftingUIClosed = function() anvil.closedByGame = anvil.closedByGame + 1 end,
}
playerPawn = anvilCharacter
press("F6")
check("F6 opens the anvil: component added, player is its own access", anvil.opened == 1
    and anvil.addedClass ~= nil and anvilCharacter.m_pCraftingComponent == craftingComponent
    and anvil.access == anvilCharacter and anvil.provider == anvilCharacter and anvil.cacheCleared)
press("F6")
check("F6 again closes and clears the access", anvil.closedByGame == 1 and anvil.access == nil)
press("F6")
hooks["/Script/TQ2Gameplay.TQ2PlayerCharacter:OnCraftingUIClosed"].after(param(anvilCharacter))
check("closing with Esc clears the access", anvil.access == nil and anvil.opened == 2)

-- Equipment pickup by rarity: threshold, range, one try per item, items not filled yet wait.
local EquipmentPickup = require("equipment_pickup")
local function groundItem(name, rarity, x)
    local slot = { ItemHandle = { pItem = rarity and { IsValid = function() return true end, m_Rarity = rarity } or nil } }
    local item = { pickups = 0, present = true, slot = slot }
    item.IsValid = function() return item.present end
    item.GetFullName = function() return "bp_tq2_world_loot_item_C /Game/Level.l:PersistentLevel." .. name end
    item.K2_GetActorLocation = function() return { X = x, Y = 0, Z = 0 } end
    item.Pickup = function(_, actor, manual) item.pickups = item.pickups + 1; item.by = actor; item.manual = manual end
    item.m_ContainerData = { ItemSlots = container({ slot }) }
    return item
end
local looter = { IsValid = function() return true end, GetAddress = function() return 600 end,
                 K2_GetActorLocation = function() return { X = 0, Y = 0, Z = 0 } end,
                 PlayerState = { IsValid = function() return true end, GetAddress = function() return 601 end } }
local equipmentKinds = { da_sword_01 = true, da_ring_02 = true, da_item_potion = false }
local function isEquipmentType(typeName) return equipmentKinds[typeName] end
check("type name from the ground item", EquipmentPickup.typeNameOf(groundItem("da_sword_01_WorldItem_2147", 2, 0)) == "da_sword_01")
local equipment = EquipmentPickup.newState()
local magicSword = groundItem("da_sword_01_WorldItem_1", 1, 100)
local rareRing = groundItem("da_ring_02_WorldItem_1", 2, 100)
local farEpic = groundItem("da_sword_01_WorldItem_2", 4, 900)
local unfilled = groundItem("da_sword_01_WorldItem_3", nil, 50)
local potion = groundItem("da_item_potion_WorldItem", 3, 50)
for _, item in ipairs({ magicSword, rareRing, farEpic, unfilled, potion }) do EquipmentPickup.remember(equipment, item) end
EquipmentPickup.pass(equipment, looter, 400, { minRarity = 2 }, isEquipmentType)
check("equipment from Rare: rare ring picked up, magic sword not", rareRing.pickups == 1
    and rareRing.by == looter and rareRing.manual == false and magicSword.pickups == 0)
check("out of range and not filled yet: wait; no potion", farEpic.pickups == 0 and unfilled.pickups == 0
    and potion.pickups == 0)
unfilled.slot.ItemHandle.pItem = { IsValid = function() return true end, m_Rarity = 3 }
EquipmentPickup.pass(equipment, looter, 400, { minRarity = 2 }, isEquipmentType)
check("content filled in: picked up now; ring (inventory full) not tried again",
    unfilled.pickups == 1 and rareRing.pickups == 1)
farEpic.K2_GetActorLocation = function() return { X = 300, Y = 0, Z = 0 } end
EquipmentPickup.pass(equipment, looter, 400, { minRarity = 2 }, isEquipmentType)
check("came into range: picked up", farEpic.pickups == 1)
local newTypeAxe = groundItem("da_axe_09_WorldItem_1", 3, 100)
EquipmentPickup.remember(equipment, newTypeAxe)
EquipmentPickup.pass(equipment, looter, 400, { minRarity = 2 }, isEquipmentType)
equipmentKinds.da_axe_09 = true -- the next item type scan found the new type
EquipmentPickup.pass(equipment, looter, 400, { minRarity = 2 }, isEquipmentType)
check("new, not yet scanned type: waits for the scan instead of staying on the ground", newTypeAxe.pickups == 1)
EquipmentPickup.pass(equipment, looter, 400, {}, isEquipmentType)
check("equipment off: list cleared", #equipment.items == 0)
local hoover = { IsValid = function() return true end, m_Range = 650, m_pOwningPlayer = looter.PlayerState }
instances.GrimItemHooverComponent = { hoover }
check("range from the player's hoover", EquipmentPickup.hooverRange(equipment, looter, 400) == 650)
instances.GrimItemHooverComponent = nil

-- Menu tabs: sections by header into tabs; unknown sections go to the last tab, empty tabs are left out.
local MenuTabs = require("menu_tabs")
local built = MenuTabs.build({ { header = "A" }, { label = "a1" }, { header = "New" }, { label = "n1" },
    { header = "B" }, { label = "b1" } }, { { Name = "One", Sections = { "A" } }, { Name = "Empty", Sections = { "X" } },
    { Name = "Two", Sections = { "B" } } })
check("tabs: sections assigned, unknown ones in the last tab, empty tab left out", #built == 2
    and built[1].name == "One" and #built[1].entries == 2 and built[2].name == "Two" and #built[2].entries == 4
    and built[2].entries[1].header == "New")

-- Gold multiplier on its own: only piles created during an enemy drop, only when the factor is not 1.
local GoldMultiplier = require("gold_multiplier")
local goldFactor, clock = 1, 0
local gold = GoldMultiplier.handler(function() return goldFactor end, function(line) logLines[#logLines + 1] = line end,
    function() return clock end)
local onWorldItem = newObjectCallbacks["/Script/TQ2Gameplay.TQ2WorldItem"]
local function goldPile(amount)
    local slot = { Num = amount }
    return {
        slot = slot,
        IsValid = function() return true end,
        GetFullName = function() return "bp_tq2_world_loot_item_C /Game/Level.da_item_gold_WorldItem_3" end,
        OnUpdateWorldRepresentation = function() end,
        m_ContainerData = { ItemSlots = container({ slot }) },
    }
end
local enemy = { IsValid = function() return true end, IsA = function(_, class) return class:match("AICharacter") ~= nil end,
                GetFullName = function() return "bp_ai_default_character_C /Game/Level.Skeleton_1" end }
local chest = { IsValid = function() return true end, IsA = function() return false end,
                GetFullName = function() return "TQ2Chest /Game/Level.Chest_1" end }
local function dropFrom(source) return { source = function() return source end } end

goldFactor = 3
gold.before(dropFrom(enemy))
clock = 0.5 -- the game spawns the dropped items a moment after LaunchDropList returned
local enemyPile = goldPile(10)
onWorldItem(enemyPile)
check("gold x3: pile shortly after an enemy drop 10 -> 30", enemyPile.slot.Num == 30)
clock = 10
gold.before(dropFrom(chest))
local chestPile = goldPile(10)
onWorldItem(chestPile)
check("gold: pile from a chest unchanged", chestPile.slot.Num == 10)
clock = 20
local loadedPile = goldPile(10)
onWorldItem(loadedPile)
check("gold: pile when loading (no enemy drop shortly before) unchanged", loadedPile.slot.Num == 10)
goldFactor = 1
gold.before(dropFrom(enemy))
local normalPile = goldPile(10)
onWorldItem(normalPile)
check("gold x1: unchanged", normalPile.slot.Num == 10)
local goldLines = 0
for _, line in ipairs(logLines) do if line:match("Gold") then goldLines = goldLines + 1 end end
check("gold: no log while everything works", goldLines == 0)

for _, line in ipairs(logLines) do
    if line:match("error") then check("no error in the log: " .. line, false) end
end

-- Affix dump (diagnostic): affixes with tags and level texts, ground items with their affixes, written to a file.
local AffixDump = require("affix_dump")
local function text(value) return { ToString = function() return value end } end
local function mockAffix(name, tags, levels)
    return { IsValid = function() return true end,
             GetFullName = function() return "GrimItemAffix /Game/Affixes/" .. name .. "." .. name end,
             m_Type = 1, m_GameplayTags = { GameplayTags = container(tags) }, m_Levels = { Levels = container(levels) } }
end
local summonAffix = mockAffix("affix_summon_damage", { tagNamed("Affix.Summon") }, {
    { TitleText = text("of the Legion"), AdjectiveText = text("Commanding"),
      AffixEffects = container({ { Type = 0, ToolTipText = text("+{0}% Summon Damage") } }) } })
local brokenAffix = { IsValid = function() return true end, GetFullName = function() return "GrimItemAffix x.affix_broken" end }
local affixItem = groundItem("da_staff_03_WorldItem_7", 3, 0)
affixItem.slot.ItemHandle.pItem.m_Affixes = container({ { pAffix = summonAffix, Level = 2 } })
local emptyItem = groundItem("da_ring_01_WorldItem_8", nil, 0)
instances.GrimItemAffix = { summonAffix, brokenAffix }
instances.TQ2WorldItem = { affixItem, emptyItem }
local healthAffix = mockAffix("da_suffix_1_Health", {}, {})
local sharedTable = { IsValid = function() return true end, GetFullName = function() return "GrimItemAffixTableAsset x.shared" end }
sharedTable.m_Table = { Entries = container({ { pAffix = healthAffix } }),
                        SubTables = container({ { pTable = sharedTable } }) } -- contains itself
local function itemType(name, entries)
    return { IsValid = function() return true end, GetFullName = function() return "TQ2ItemDescription x." .. name end,
             m_RandomAffixes = { Entries = container(entries), SubTables = container({ { pTable = sharedTable } }) } }
end
local savedDescriptions = instances.TQ2ItemDescription
instances.TQ2ItemDescription = { itemType("da_weapon_2h_staff_a", { { pAffix = summonAffix } }),
                                 itemType("da_jewelry_ring_b", { { pAffix = summonAffix } }),
                                 itemType("da_armor_head_c", {}),
                                 { IsValid = function() return true end, GetFullName = function() return "x.da_broken" end } }
local charmItem = { IsValid = function() return true end, GetFullName = function() return "TQ2ItemDescription x.da_socket_charm_bones_01" end }
local function socketEffect(tooltip, low, high)
    return { ToolTipText = text(tooltip), Scale = { min = { SourceText = text(low) }, max = { SourceText = text(high) } } }
end
instances.TQ2SocketableItemDescription = { { IsValid = function() return true end,
    GetFullName = function() return "TQ2SocketableItemDescription x.Socketable" end,
    GetOuter = function() return charmItem end,
    m_EffectsByCompletionLevel = container({ { effects = container({ socketEffect("+{Value}% Vitality Resistance", "4", "6") }) } }),
    m_CompletionBonus = { effects = container({ socketEffect("+{Value} Health", "20", "40") }) },
    m_pValidTargetFilter = { IsValid = function() return true end, m_AllowedRarities = 7,
        m_ItemTypeRequirement = { BaseRequirement = { RequirementType = 0,
            GameplayTags = { GameplayTags = container({ tagNamed("GrimVentory.ItemType.Arm"), tagNamed("GrimVentory.ItemType.Ring") }) } } },
        m_GameplayTagsRequirement = { BaseRequirement = { RequirementType = 0, GameplayTags = { GameplayTags = container({}) } } } } } }
local dumpPath = workDir .. "/affix_dump.txt"
local dumpLog = {}
local pageDataPath, dumpFilterPath = workDir .. "/affix_data.js", workDir .. "/dump_filter.lua"
local dumpFilterFile = io.open(dumpFilterPath, "w")
dumpFilterFile:write('return { { name = "Say \\"hi\\"" } }\n')
dumpFilterFile:close()
AffixDump.write({ dump = dumpPath, pageData = pageDataPath, filter = dumpFilterPath },
    function(line) dumpLog[#dumpLog + 1] = line end)
local pageDataFile = io.open(pageDataPath, "r")
local pageData = pageDataFile and pageDataFile:read("a") or ""
if pageDataFile then pageDataFile:close() end
check("affix dump: data file for the editor carries the dump and the loot filter, escaped for JavaScript",
    pageData:match('^window%.TQ2_TWEAKS_DATA = { dump: "AFFIXES %(2 loaded%)\\n') ~= nil
    and pageData:find('filter: "return { { name = \\"Say \\\\\\"hi\\\\\\"\\" } }\\n" };', 1, true) ~= nil)
check("affix dump: without a loot filter the data file says null",
    AffixDump.pageData("x", nil) == 'window.TQ2_TWEAKS_DATA = { dump: "x", filter: null };\n')
local dumpFile = io.open(dumpPath, "r")
local dump = dumpFile and dumpFile:read("a") or ""
if dumpFile then dumpFile:close() end
check("affix dump: affix with tags and level texts", dump:match("AFFIXES %(2 loaded%)") ~= nil
    and dump:match("affix_summon_damage  type=1  tags=Affix.Summon") ~= nil
    and dump:match('L1 "of the Legion" adjective "Commanding": %[0%] %+{0}%% Summon Damage') ~= nil)
check("affix dump: unreadable fields do not stop the dump", dump:match("affix_broken  type=%?  tags=%?") ~= nil)
check("affix dump: ground items with their affixes, unfilled ones left out", dump:match("GROUND ITEMS %(1%)") ~= nil
    and dump:match("da_staff_03  rarity=3: affix_summon_damage L2") ~= nil)
instances.TQ2ItemDescription = savedDescriptions
instances.TQ2SocketableItemDescription = nil
check("affix dump: charms and relics with their effects per stage and the completion bonus",
    dump:find("SOCKETABLES (1)\nSOCKETABLE da_socket_charm_bones_01\n  stage 1: +{Value}% Vitality Resistance [4..6]\n  bonus: +{Value} Health [20..40]\n  sockets into: types any of Arm, Ring; rarity mask 7", 1, true) ~= nil)
check("affix dump: pools per item type, through sub-tables, same pools grouped, unreadable types left out",
    dump:match("AFFIX POOLS %(3 item types, 2 pools%)") ~= nil
    and dump:find("POOL types=da_armor_head_c\n  affixes=da_suffix_1_Health\n", 1, true) ~= nil
    and dump:find("POOL types=da_jewelry_ring_b,da_weapon_2h_staff_a\n  affixes=affix_summon_damage,da_suffix_1_Health\n", 1, true) ~= nil)
check("affix dump: logs where it went", dumpLog[1] ~= nil and dumpLog[1]:find(dumpPath, 1, true) ~= nil)

-- Loot filter rules: conditions of a rule combine with "and", an item is picked up if any rule matches.
local LootRules = require("loot_rules")
local SUMMON_DAMAGE, SUMMON_HEALTH = "da_prefix_1_Summons_PerIncreasedDamage_All", "da_suffix_1_Summons_PerIncreasedHealth"
local HEALTH, BARRIER, FIRE = "da_suffix_1_Health", "da_suffix_1_EnergyBarrier", "da_prefix_1_PerIncreasedFireDmg_high"
local RARITY = { Common = 0, Magic = 1, Rare = 2, Infrequent = 3, Epic = 4, Legendary = 5 }
local filterLog = {}
local function logFilter(line) filterLog[#filterLog + 1] = line end
local filterPath = workDir .. "/loot_filter.lua"
local function writeFilter(text)
    local filterFile = io.open(filterPath, "w")
    filterFile:write(text)
    filterFile:close()
end
writeFilter(table.concat({
    'return {',
    '    { name = "Summoner", minRarity = "Rare", needed = 1, types = {}, affixes = {',
    '        "' .. SUMMON_DAMAGE .. '", -- Beastcaller\'s: Summons have X% increased Damage',
    '        "' .. SUMMON_HEALTH .. '",',
    '    } },',
    '    { name = "Defence", minRarity = "Rare", needed = 2, types = { "head", "torso" }, affixes = {',
    '        "' .. HEALTH .. '", "' .. BARRIER .. '",',
    '    } },',
    '    { name = "Epic and better", minRarity = "Epic", needed = 1, types = {}, affixes = {} },',
    '    { name = "Everything", needed = 1, types = {}, affixes = {} },',
    '    { name = "Typo", minRarity = "Rarest" },',
    '}', '' }, "\n"))
local rules = LootRules.load(filterPath, RARITY, logFilter)
check("loot filter: rules loaded, rules without condition or with an unknown rarity left out and logged",
    #rules == 3 and filterLog[#filterLog] == "Loot filter: 3 rule(s) Summoner, Defence, Epic and better"
    and table.concat(filterLog, "|"):match("Everything: no condition") ~= nil
    and table.concat(filterLog, "|"):match("Typo: unknown rarity") ~= nil)
local function matches(rarity, typeName, ...)
    return LootRules.matchesAny(rules, { rarity = rarity, typeName = typeName, affixNames = { ... } })
end
check("rule Summoner: one summon affix on a rare is enough, a magic item is not",
    matches(2, "da_weapon_2h_staff_magic_spirit_greek_t3", SUMMON_DAMAGE, FIRE)
    and not matches(1, "da_weapon_2h_staff_magic_spirit_greek_t3", SUMMON_DAMAGE))
check("rule Defence: two defence affixes on the listed types only",
    matches(2, "da_armor_head_greek_paladin", HEALTH, BARRIER)
    and not matches(2, "da_armor_head_greek_paladin", HEALTH, FIRE)
    and not matches(2, "da_armor_leg_greek_paladin", HEALTH, BARRIER))
writeFilter('return { { name = "Arms", types = { "arm" } } }\n')
local armRules = LootRules.load(filterPath, RARITY, logFilter)
do
    local SPEED, FIRE_DMG, COLD_DMG = "da_prefix_1_Summons_PerIncreasedSpeed_All", "da_prefix_1_PerIncreasedFireDmg", "da_prefix_1_PerIncreasedColdDmg"
    local AGILITY = "da_suffix_1_Agility"
    writeFilter('return { { name = "Jewellery", minRarity = "Magic", needed = 3, craftable = true, affixes = { "'
        .. SUMMON_DAMAGE .. '", "' .. SPEED .. '", "' .. SUMMON_HEALTH .. '" } },\n'
        .. '  { name = "Plain", minRarity = "Magic", needed = 3, affixes = { "' .. SUMMON_DAMAGE .. '", "' .. SPEED .. '", "' .. SUMMON_HEALTH .. '" } } }\n')
    local craftRules = LootRules.load(filterPath, RARITY, logFilter)
    local function item(rarity, maxAffixes, ...)
        local affixes = {}
        for _, name in ipairs({ ... }) do affixes[#affixes + 1] = { name = name, random = true } end
        return { rarity = rarity, typeName = "da_jewelry_ring_x", maxAffixes = maxAffixes, affixes = affixes }
    end
    check("crafting: a magic item with 2 wanted affixes and a free place counts (add + replace)",
        LootRules.matchesAny({ craftRules[1] }, item(1, 3, SUMMON_DAMAGE, SUMMON_HEALTH))
        and not LootRules.matchesAny({ craftRules[2] }, item(1, 3, SUMMON_DAMAGE, SUMMON_HEALTH)))
    check("crafting: a full rare counts when a useless random affix of the missing kind can be replaced",
        LootRules.matchesAny({ craftRules[1] }, item(2, 4, SUMMON_DAMAGE, SUMMON_HEALTH, FIRE_DMG, AGILITY)))
    check("crafting: a prefix cannot become the missing suffix",
        not LootRules.matchesAny({ craftRules[1] }, item(2, 4, SUMMON_DAMAGE, SPEED, FIRE_DMG, COLD_DMG)))
    local unique = { rarity = 4, typeName = "da_jewelry_ring_x", affixes = {
        { name = SUMMON_DAMAGE, random = false }, { name = SPEED, random = false }, { name = FIRE_DMG, random = false } } }
    check("crafting: fixed (non-random) affixes of uniques are not replaceable",
        not LootRules.matchesAny({ craftRules[1] }, unique))
end
check("type parts match whole parts of the type name (arm is not armor)",
    LootRules.matchesAny(armRules, { rarity = 0, typeName = "da_armor_arm_greek_paladin", affixNames = {} })
    and not LootRules.matchesAny(armRules, { rarity = 0, typeName = "da_armor_head_greek_paladin", affixNames = {} }))
check("rule Epic and better: any epic, whatever its affixes", matches(4, "da_jewelry_ring_normal_greek_t1", FIRE)
    and not matches(3, "da_jewelry_ring_normal_greek_t1", FIRE))
check("missing loot filter file: no rules, logged", #LootRules.load(workDir .. "/none.lua", RARITY, logFilter) == 0
    and filterLog[#filterLog]:match("missing") ~= nil)
writeFilter('os.exit(1)\n')
check("loot filter file cannot run code", #LootRules.load(filterPath, RARITY, logFilter) == 0
    and filterLog[#filterLog]:match("not loaded") ~= nil)

-- Equipment pickup with loot rules next to the rarity rule.
local function affixItem(name, rarity, ...)
    local item = groundItem(name, rarity, 100)
    local affixes = {}
    for _, affixName in ipairs({ ... }) do
        affixes[#affixes + 1] = { pAffix = mockAffix(affixName, {}, {}), Level = 1 }
    end
    item.slot.ItemHandle.pItem.m_Affixes = container(affixes)
    return item
end
local ruleState = EquipmentPickup.newState()
local summonSword = affixItem("da_sword_01_WorldItem_20", 2, SUMMON_DAMAGE, FIRE)
local fireSword = affixItem("da_sword_01_WorldItem_21", 2, FIRE)
local magicSummonSword = affixItem("da_sword_01_WorldItem_22", 1, SUMMON_DAMAGE)
for _, item in ipairs({ summonSword, fireSword, magicSummonSword }) do EquipmentPickup.remember(ruleState, item) end
EquipmentPickup.pass(ruleState, looter, 400, { lootRules = rules }, isEquipmentType)
check("pickup by loot rules: matching item picked up, others stay on the ground",
    summonSword.pickups == 1 and fireSword.pickups == 0 and magicSummonSword.pickups == 0)
local bothState = EquipmentPickup.newState()
local magicFire = affixItem("da_sword_01_WorldItem_25", 1, FIRE)
local rareFire = affixItem("da_sword_01_WorldItem_26", 2, FIRE)
for _, item in ipairs({ magicFire, rareFire }) do EquipmentPickup.remember(bothState, item) end
EquipmentPickup.pass(bothState, looter, 400, { minRarity = 2, lootRules = {} }, isEquipmentType)
check("rarity rule still applies next to the loot rules", rareFire.pickups == 1 and magicFire.pickups == 0)
local farState = EquipmentPickup.newState()
local farSummon = affixItem("da_sword_01_WorldItem_27", 2, SUMMON_DAMAGE)
farSummon.K2_GetActorLocation = function() return { X = 900, Y = 0, Z = 0 } end
local affixReads = 0
local affixArray = farSummon.slot.ItemHandle.pItem.m_Affixes
farSummon.slot.ItemHandle.pItem.m_Affixes = { ForEach = function(self, callback)
    affixReads = affixReads + 1
    return affixArray:ForEach(callback)
end }
EquipmentPickup.remember(farState, farSummon)
for _ = 1, 3 do EquipmentPickup.pass(farState, looter, 400, { lootRules = rules }, isEquipmentType) end
farSummon.K2_GetActorLocation = function() return { X = 300, Y = 0, Z = 0 } end
EquipmentPickup.pass(farState, looter, 400, { lootRules = rules }, isEquipmentType)
check("wanted item out of range: judged once, later only its distance is checked; picked up in range",
    affixReads == 1 and farSummon.pickups == 1)
do
    local delayedState = EquipmentPickup.newState(1.5)
    local fresh = affixItem("da_sword_01_WorldItem_28", 2, SUMMON_DAMAGE)
    local reads = 0
    local freshAffixes = fresh.slot.ItemHandle.pItem.m_Affixes
    fresh.slot.ItemHandle.pItem.m_Affixes = { ForEach = function(self, callback)
        reads = reads + 1
        return freshAffixes:ForEach(callback)
    end }
    EquipmentPickup.remember(delayedState, fresh, 10)
    EquipmentPickup.pass(delayedState, looter, 400, { lootRules = rules }, isEquipmentType, 10.5)
    local readsEarly, pickupsEarly = reads, fresh.pickups
    EquipmentPickup.pass(delayedState, looter, 400, { lootRules = rules }, isEquipmentType, 11.6)
    check("new ground item is left alone until it has settled, then judged and picked up",
        readsEarly == 0 and pickupsEarly == 0 and reads == 1 and fresh.pickups == 1)
end
check("affixes are read only when a rule with affixes is reached (epic item via the rarity-only rule)",
    LootRules.matchesAny(rules, { rarity = 4, typeName = "da_jewelry_ring_x",
        readAffixes = function() error("affixes read") end }) == true)
check("affix dump key bound (for the affix picker)", keyBinds.F9 ~= nil)

do
-- Game data dump: creature templates from the game's asset list, their drop lists (weights and chances as formula
-- text, sub-lists once even when a list contains itself), item types with their affix tables, all as JSON.
local GameDataDump = require("game_data_dump")
local function formulaOf(source) return { SourceText = text(source) } end
local cacheText = '{ "pathsByClass": { "/Script/Other.Thing": { "paths": [ "/JsonData/x" ] },\n'
    .. '"/Script/TQ2Gameplay.TQ2CreatureTemplateJsonData": { "paths": [ "/JsonData/TQ2/Creatures/da_cr_skeleton",'
    .. ' "/JsonData/TQ2/Creatures/da_missing" ] } } }'
check("game data: creature paths from the asset list, object path from the asset path",
    table.concat(GameDataDump.pathsOfClass(cacheText, "/Script/TQ2Gameplay.TQ2CreatureTemplateJsonData"), "|")
        == "/JsonData/TQ2/Creatures/da_cr_skeleton|/JsonData/TQ2/Creatures/da_missing"
    and GameDataDump.objectPath("/JsonData/TQ2/Creatures/da_cr_skeleton") == "/JsonData/TQ2/Creatures/da_cr_skeleton.da_cr_skeleton")
local droppedSword = { IsValid = function() return true end, GetFullName = function() return "TQ2ItemDescription x.da_sword_x" end }
local skeletonDrops = { IsValid = function() return true end, GetFullName = function() return "GrimItemDropList x.dl_skeleton" end,
    GetClass = function() return { GetFName = function() return text("GrimItemDropList") end } end,
    m_DropChance = formulaOf("1"), m_NumRandomDrops = { min = formulaOf("1"), max = formulaOf("Level / 10") },
    m_FixedDrops = container({}) }
skeletonDrops.m_RandomDropTable = {
    Entries = container({ { Weight = formulaOf("10"), IsGuaranteed = false,
        Requirement = { GameplayTagRequirement = { BaseRequirement = { RequirementType = 1,
            GameplayTags = { GameplayTags = container({ tagNamed("Difficulty.Normal") }) } },
            AdditionalRequirements = container({}) }, CustomRequirement = formulaOf("") },
        ItemDrop = { pItemDescription = { HardReference = droppedSword },
                     NumToDrop = { min = formulaOf("1"), max = formulaOf("1") } } } }),
    SubTables = container({ { Weight = formulaOf("2"), pDropList = skeletonDrops } }) } -- contains itself
local skeleton = { IsValid = function() return true end, m_CreatureDesc = { Name = text("Skeleton"), Title = text(""),
    InternalName = text("cr_skeleton"), GameplayTags = { GameplayTags = container({ tagNamed("Creature.Undead") }) },
    pDropList = skeletonDrops, OverrideItemDropChance = true, ItemDropChanceOverride = formulaOf("0.5"),
    OverrideNumItemDrops = false } }
function LoadAsset(path)
    if path == "/JsonData/TQ2/Creatures/da_cr_skeleton.da_cr_skeleton" then return skeleton end
    error("not found: " .. path)
end
local gameCachePath, gameDataPath = workDir .. "/JsonMetaDataCache.json", workDir .. "/game_data.json"
local gameCacheFile = io.open(gameCachePath, "w")
gameCacheFile:write(cacheText)
gameCacheFile:close()
local savedItemTypes = instances.TQ2ItemDescription
instances.TQ2ItemDescription = { itemType("da_weapon_2h_staff_a", { { pAffix = summonAffix } }) }
local gameLog = {}
local gameState = GameDataDump.newState()
local gamePagePath = workDir .. "/game_data.js"
GameDataDump.start(gameState, { cache = gameCachePath, output = gameDataPath, page = gamePagePath },
    function(line) gameLog[#gameLog + 1] = line end)
local gamePageFile = io.open(gamePagePath, "r")
local gamePage = gamePageFile and gamePageFile:read("a") or ""
if gamePageFile then gamePageFile:close() end
instances.TQ2ItemDescription = savedItemTypes
local gameDataFile = io.open(gameDataPath, "r")
local gameData = gameDataFile and gameDataFile:read("a") or ""
if gameDataFile then gameDataFile:close() end
check("game data: creature with name, tags, own drop chance and its drop list",
    gameData:find('"dropChance":"0.5","dropList":"dl_skeleton","internalName":"cr_skeleton","name":"Skeleton"', 1, true) ~= nil
    and gameData:find('"tags":["Creature.Undead"]', 1, true) ~= nil)
check("game data: drop list with chance, count range, weighted item entry with its requirement tags",
    gameData:find('"randomDrops":{"max":"Level / 10","min":"1"}', 1, true) ~= nil
    and gameData:find('"item":"da_sword_x"', 1, true) ~= nil and gameData:find('"weight":"10"', 1, true) ~= nil
    and gameData:find('"tags":{"mode":1,"tags":["Difficulty.Normal"]}', 1, true) ~= nil)
check("game data: a list containing itself is written once and referenced by name",
    gameData:find('{"list":"dl_skeleton","weight":"2"}', 1, true) ~= nil)
check("game data: item types with their affix tables, creatures that do not load are listed",
    gameData:find('"name":"da_weapon_2h_staff_a"', 1, true) ~= nil
    and gameData:find('"shared":[{"affix":"da_suffix_1_Health"},{"table":"shared"}]', 1, true) ~= nil
    and gameData:find('"notLoaded":["/JsonData/TQ2/Creatures/da_missing"]', 1, true) ~= nil)
check("game data: the same data as a script for the data page",
    gamePage:sub(1, 24) == "window.TQ2_GAME_DATA = {" and gamePage:find(gameData:sub(1, 200), 1, true) ~= nil)
check("game data: finished and logged, a second start is possible again", GameDataDump.isRunning(gameState) == false
    and gameLog[#gameLog]:match("1 creatures %(1 not loaded%), 1 drop lists, 1 item types") ~= nil)
check("game data dump key off by default (developer tool)", keyBinds.SHIFTF9 == nil)
end

do
-- Gear dump: equipped items and the player's own inventories with every affix's tier and roll, as JSON.
do
    local GearDump = require("gear_dump")
    local function valid(fields)
        fields.IsValid = function() return true end
        return fields
    end
    local function gearItem(typeName, rarity, affixName, tier, scale)
        return valid({ m_pDescription = { HardReference = valid({ GetFullName = function() return "TQ2ItemDescription x." .. typeName end }) },
                       m_Rarity = rarity, m_Level = 40, m_CustomName = text(""),
                       m_Affixes = container({ { pAffix = mockAffix(affixName, {}, {}), Level = tier, Category = 2,
                                                 EffectScaleMultiplier = 1, AffixEffectInstances = container({ { Scale = scale } }) } }) })
    end
    local function slots(...)
        local list = {}
        for _, instance in ipairs({ ... }) do list[#list + 1] = { ItemHandle = { pItem = instance }, Num = 1 } end
        return { m_ContainerData = { ItemSlots = container(list) } }
    end
    local playerState = valid({ GetAddress = function() return 500 end })
    playerState.m_pEquipmentContainer = valid(slots(gearItem("da_jewelry_ring_a", 2, "da_prefix_1_Summons_PerIncreasedDamage_All", 3, 0.75), false))
    local component = valid({ GetAddress = function() return 501 end, GetOuter = function() return playerState end })
    local bag = valid(slots(gearItem("da_weapon_2h_staff_b", 4, "da_suffix_1_Health", 5, 0.5)))
    bag.GetFullName = function() return "TQ2Inventory x.Backpack" end
    bag.GetOuter = function() return component end
    local foreign = valid(slots(gearItem("da_weapon_2h_axe_c", 1, "da_suffix_1_Health", 1, 0.1)))
    foreign.GetOuter = function() return valid({ GetAddress = function() return 999 end, GetOuter = function() return nil end }) end
    local savedInventories = instances.TQ2Inventory
    instances.TQ2Inventory = { bag, foreign }
    local gearPath, gearLog = workDir .. "/gear.json", {}
    GearDump.write(gearPath, playerState, function(line) gearLog[#gearLog + 1] = line end)
    instances.TQ2Inventory = savedInventories
    local gearFile = io.open(gearPath, "r")
    local gear = gearFile and gearFile:read("a") or ""
    if gearFile then gearFile:close() end
    check("gear dump: equipped item with type, rarity, level and affix tier and roll", gear:find(
        '"equipment":[{"affixes":[{"category":"random","multiplier":1,"name":"da_prefix_1_Summons_PerIncreasedDamage_All","scales":[0.75],"tier":3}],"count":1,"level":40,"rarity":2,"slot":1,"type":"da_jewelry_ring_a"}]',
        1, true) ~= nil)
    check("gear dump: the player's inventories only, foreign ones left out",
        gear:find('"inventories":[{"items":[', 1, true) ~= nil and gear:find('"name":"Backpack"', 1, true) ~= nil
        and gear:find("da_weapon_2h_staff_b", 1, true) ~= nil and gear:find("da_weapon_2h_axe_c", 1, true) == nil
        and gearLog[1]:match("1 equipped, 1 in 1 inventories") ~= nil)
end

-- Player lookup: the controller is searched once and kept while valid, searched again after forget().
local Player = require("player")
Player.forget()
local lookupsBefore = controllerLookups
for _ = 1, 5 do Player.controller() end
local lookupsKept = controllerLookups - lookupsBefore
Player.forget()
Player.controller()
check("player controller searched once and kept, again after forget", lookupsKept == 1
    and controllerLookups - lookupsBefore == 2 and Player.character() == playerPawn)
end

do
-- Loop timing: runs, average, maximum and share of the period per loop, reported once per period.
local LoopTiming = require("loop_timing")
local timed = LoopTiming.new(60)
check("timing: no report before the period has passed", LoopTiming.report(timed, 100) == nil)
LoopTiming.record(timed, "Display", 0.002)
LoopTiming.record(timed, "Display", 0.004)
LoopTiming.record(timed, "Speed", 0.001)
check("timing: still nothing inside the period", LoopTiming.report(timed, 130) == nil)
local timingLine = LoopTiming.report(timed, 160)
check("timing: summary sorted by total time, with share of the period",
    timingLine == "Timing over 60 s: 0.01 % of the time in the mod | Display 2× avg 3.00 ms max 4 ms | Speed 1× avg 1.00 ms max 1 ms")
check("timing: next period starts empty", LoopTiming.report(timed, 220) == "Timing over 60 s: no loop ran")
end

os.execute(string.format("rm -rf '%s'", workDir))
io.write(failures == 0 and "\nAll tests passed\n" or ("\n" .. failures .. " test(s) failed\n"))
os.exit(failures == 0 and 0 or 1)
