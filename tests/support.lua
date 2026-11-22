-- Shared test support: mocked UE4SS API, the mod copied to a temp folder, check() and fakes used by several
-- test files. Required once by tests/test_tq2tweaks.lua; the test files get it through require("support").
-- The scripts are copied to a temp folder so the real mod's user_settings.lua stays untouched.

local projectDir = arg[0]:match("^(.*)/tests/") or "."
local workDir = os.tmpname()
os.remove(workDir)
assert(os.execute(string.format("mkdir -p '%s' && cp -r '%s/TQ2Tweaks/Scripts' '%s/'", workDir, projectDir, workDir)))
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
local counts = { controllerLookups = 0 }
package.preload["UEHelpers"] = function()
    return { GetPlayerController = function() counts.controllerLookups = counts.controllerLookups + 1; return playerController end,
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


-- Fakes used by several test files ----------------------------------------------------------

local function tagNamed(name) return { TagName = { ToString = function() return name end } } end
local function text(value) return { ToString = function() return value end } end
local function mockAffix(name, tags, levels)
    return { IsValid = function() return true end,
             GetFullName = function() return "GrimItemAffix /Game/Affixes/" .. name .. "." .. name end,
             m_Type = 1, m_GameplayTags = { GameplayTags = container(tags) }, m_Levels = { Levels = container(levels) } }
end
-- A ground item (AGrimWorldItem) with its item instance; rarity nil = not filled in yet.
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

return {
    projectDir = projectDir,
    workDir = workDir,
    logLines = logLines,
    FIELDS = FIELDS,
    created = created,
    mock = mock,
    controllerMock = controllerMock,
    playerController = playerController,
    abilitySystem = abilitySystem,
    game = game,
    regen = regen,
    viewModel = viewModel,
    itemDescription = itemDescription,
    sword = sword,
    specialRing = specialRing,
    instances = instances,
    keyBinds = keyBinds,
    press = press,
    hooks = hooks,
    hookLists = hookLists,
    newObjectCallbacks = newObjectCallbacks,
    loadMapHooks = loadMapHooks,
    param = param,
    loops = loops,
    tick = tick,
    check = check,
    allOf = allOf,
    last = last,
    container = container,
    playerLayerWidgets = playerLayerWidgets,
    hudWidget = hudWidget,
    menuWidget = menuWidget,
    hudLabel = hudLabel,
    lastBars = lastBars,
    menuLines = menuLines,
    tagNamed = tagNamed,
    text = text,
    mockAffix = mockAffix,
    groundItem = groundItem,
    looter = looter,
    equipmentKinds = equipmentKinds,
    isEquipmentType = isEquipmentType,
    counts = counts,
    failures = function() return failures end,
}
