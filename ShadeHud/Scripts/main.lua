-- TQ2 Tweaks (folder ShadeHud): shade display, XP/gold/loot tweaks, speed, level points, free crafting and a
-- damage meter, all adjustable in the F5 menu. This file only wires the modules together.
local config = require("config")
local Settings = require("settings")
local Menu = require("menu")
local MenuTabs = require("menu_tabs")
local MenuWidget = require("menu_widget")
local MovementLock = require("movement_lock")
local ShadeMenuEntries = require("shade_menu_entries")
local GameplayMenuEntries = require("gameplay_menu_entries")
local ShadeState = require("shade_state")
local ShadeWidget = require("shade_widget")
local XpMultiplier = require("xp_multiplier")
local DropHooks = require("drop_hooks")
local GoldMultiplier = require("gold_multiplier")
local LootBonus = require("loot_bonus")
local LevelPoints = require("level_points")
local CraftingCost = require("crafting_cost")
local MovementSpeed = require("movement_speed")
local GameSpeed = require("game_speed")
local DamageMeter = require("damage_meter")
local DamageHook = require("damage_hook")
local DamageMeterWidget = require("damage_meter_widget")
local DamageDetailWidget = require("damage_detail_widget")
local AutoPickup = require("auto_pickup")
local EquipmentPickup = require("equipment_pickup")
local WorldItems = require("world_items")
local Player = require("player")
local Cutscene = require("cutscene")
local CraftingAnywhere = require("crafting_anywhere")
local AffixDump = require("affix_dump")
local GameDataDump = require("game_data_dump")
local GearDump = require("gear_dump")
local LootRules = require("loot_rules")
local LoopTiming = require("loop_timing")

local LOG_PREFIX = "[ShadeHud] "
-- Sample values so the display can be adjusted in the menu without a Spirit character.
local PREVIEW_SHADES = { current = 2, maximum = 3, progress = 0.5 }

local function log(line)
    print(LOG_PREFIX .. line .. "\n")
end
-- Diagnostics (shade values, game HUD state, auto pickup overview) only with config.DebugLog.
local debugLog = config.DebugLog and log or nil

-- The loops run several times per second; each message source logs repeated lines only once.
local function dedupedLogger()
    local lastLine = nil
    return function(line)
        if line ~= lastLine then
            log(line)
            lastLine = line
        end
    end
end

local function concat(first, second)
    local result = {}
    for _, entry in ipairs(first) do result[#result + 1] = entry end
    for _, entry in ipairs(second) do result[#result + 1] = entry end
    return result
end

local settings = Settings.new(config, log)
local menuEntries = concat(ShadeMenuEntries.create(settings), GameplayMenuEntries.create(settings))
local menuTabs = MenuTabs.build(menuEntries, config.MenuTabs)
local menu = Menu.register(config.EditKey, menuTabs, function() Settings.save(settings) end, log)
local shownRevision = settings.revision

local damageMeter = DamageMeter.new(config.DamageMeterWindowSeconds, config.DamageMeterEncounterTimeout,
    math.max(config.DamageMeterGraphSeconds, config.DamageDetailGraphSeconds))
local function damageMeterEnabled()
    return Settings.selected(settings, "DamageMeter").Enabled
end

-- Every widget update is a series of engine calls, so the damage panels refresh less often than the display loop
-- runs. hurry() makes the next refresh immediate (after a reset, a toggle or a settings change).
local function newThrottle(intervalSeconds)
    return { interval = intervalSeconds, lastAt = -math.huge }
end

local function isDue(throttle, now)
    if now - throttle.lastAt < throttle.interval then
        return false
    end
    throttle.lastAt = now
    return true
end

local function hurry(throttle)
    throttle.lastAt = -math.huge
end

local summaryThrottle = newThrottle(config.DamageMeterIntervalSeconds)
local detailThrottle = newThrottle(config.DamageDetailIntervalSeconds)
local detailOpen = false

local function updateDamageDetail(shown)
    if not shown then
        DamageDetailWidget.show(nil)
        hurry(detailThrottle)
        return
    end
    local now = os.clock()
    if isDue(detailThrottle, now) then
        DamageDetailWidget.show(DamageMeter.details(damageMeter, now, config.DamageDetailGraphSeconds), config)
    end
end

local function updateDamageSummary(shown)
    if not shown then
        DamageMeterWidget.show(nil)
        hurry(summaryThrottle)
        return
    end
    local now = os.clock()
    if isDue(summaryThrottle, now) then
        DamageMeterWidget.show(DamageMeter.summary(damageMeter, now, config.DamageMeterGraphSeconds), config,
            Settings.selected(settings, "DamageMeterPosition"), {
                graph = Settings.selected(settings, "DamageMeterGraph").Enabled,
                types = Settings.selected(settings, "DamageMeterTypes").Enabled,
                skills = Settings.selected(settings, "DamageMeterSkills").Enabled,
            })
    end
end

local logShades = dedupedLogger()
local function updateDisplay()
    local shades = ShadeState.read()
    if debugLog ~= nil then
        logShades(shades and string.format("current=%d max=%d progress=%.3f", shades.current, shades.maximum,
            shades.progress) or "no Spirit character")
    end
    if settings.revision ~= shownRevision then
        ShadeWidget.reset()
        DamageMeterWidget.reset()
        hurry(summaryThrottle)
        shownRevision = settings.revision
    end
    if menu.open then
        shades = shades or PREVIEW_SHADES
    end
    -- During cutscenes the HUD widgets are hidden (the F5 menu stays usable).
    local inCutscene = Cutscene.isRunning(os.clock(), debugLog)
    local showDamage = damageMeterEnabled() and not inCutscene
    -- The compact panel steps aside while the detail window is shown; the detail window steps aside for the F5
    -- menu, which would overlap it.
    local showDetail = showDamage and detailOpen and not menu.open
    ShadeWidget.show(not inCutscene and shades or nil, Settings.layout(settings))
    MovementLock.sync(menu.open)
    MenuWidget.update(menu, config)
    updateDamageDetail(showDetail)
    updateDamageSummary(showDamage and not showDetail)
end

local function applySpeeds()
    MovementSpeed.apply(Settings.selected(settings, "MoveSpeed").Factor, log, os.clock())
    GameSpeed.apply(Settings.selected(settings, "GameSpeed").Factor)
end

local function applyLevelPoints()
    local values = {}
    for key in pairs(LevelPoints.FIELDS) do
        values[key] = settings.values[key]
    end
    LevelPoints.apply(values)
end

-- Lowest rarity of equipment to pick up, or nil when equipment pickup is off.
local function equipmentThreshold()
    return Settings.selected(settings, "AutoPickupEquipment").Rarity
end

local function lootFilterOn()
    return Settings.selected(settings, "LootFilter").Enabled
end

local rarityByName = {}
for _, threshold in ipairs(config.EquipmentRarityThresholds) do
    if threshold.Rarity ~= nil then
        rarityByName[threshold.Name] = threshold.Rarity
    end
end

-- Loot filter rules, read again on every settings change while the filter is on (so a new loot_filter.lua is taken
-- over by switching the row off and on).
local lootFilter = { rules = nil, revision = nil }
local function lootRules()
    if not lootFilterOn() then
        return nil
    end
    if lootFilter.revision ~= settings.revision then
        lootFilter.rules = LootRules.load(Settings.modFilePath(config.LootFilterFile), rarityByName, log)
        lootFilter.revision = settings.revision
    end
    return lootFilter.rules
end

local function equipmentPickupOn()
    return equipmentThreshold() ~= nil or lootFilterOn()
end

local function applyAutoPickup()
    local enabled = {}
    for index, category in ipairs(config.AutoPickupCategories) do
        -- Equipment is not switched via the type flag but picked up by rarity (equipment_pickup.lua).
        enabled[index] = not category.ByRarity and Settings.selected(settings, category.Setting).Enabled
    end
    AutoPickup.apply(config.AutoPickupCategories, enabled, debugLog, equipmentPickupOn())
end

local equipmentState = EquipmentPickup.newState(config.EquipmentJudgeDelaySeconds)
local equipmentPickupsLogged = 0
local EQUIPMENT_PICKUP_LOG_LIMIT = 5

-- nil while the item type has not been scanned yet (see EquipmentPickup.pass).
local function isEquipment(typeName)
    local category = AutoPickup.kindByName[typeName]
    if category == nil then
        return nil
    end
    return category and config.AutoPickupCategories[category].ByRarity == true or false
end

local function applyEquipmentPickup()
    if not equipmentPickupOn() then
        equipmentState.items = {}
        return
    end
    local character = Player.character()
    if not character:IsValid() then
        return
    end
    local range = EquipmentPickup.hooverRange(equipmentState, character, config.EquipmentPickupFallbackRange)
    local rule = { minRarity = equipmentThreshold(), lootRules = lootRules(), affixPlaces = config.AffixPlacesByRarity }
    local pickedUp = EquipmentPickup.pass(equipmentState, character, range, rule, isEquipment, os.clock())
    -- The first pickups are logged to confirm in game that Pickup from Lua works.
    if pickedUp > 0 and equipmentPickupsLogged < EQUIPMENT_PICKUP_LOG_LIMIT then
        equipmentPickupsLogged = equipmentPickupsLogged + 1
        log(string.format("Equipment pickup: %d item(s) picked up (range %.0f)", pickedUp, range))
    end
end

-- Runs action periodically on the game thread (the only safe place for UObject calls). LoopInGameThreadWithDelay
-- is used instead of LoopAsync + ExecuteInGameThread to avoid handing work across threads several times per
-- second. Errors go to UE4SS.log and the loop keeps running; each feature on its own so one failure does not take
-- the others down.
-- With config.TimingLog every loop is timed and a summary goes to the log once per TimingReportSeconds.
local timing = config.TimingLog and LoopTiming.new(config.TimingReportSeconds) or nil

local function everyMs(intervalMs, name, action)
    local logError = dedupedLogger()
    LoopInGameThreadWithDelay(intervalMs, function()
        local startedAt = timing and os.clock()
        local ok, err = pcall(action)
        if not ok then
            logError(name .. " error: " .. tostring(err))
        end
        if timing then
            local now = os.clock()
            LoopTiming.record(timing, name, now - startedAt)
            local summary = LoopTiming.report(timing, now)
            if summary then
                log(summary)
            end
        end
    end)
end

everyMs(config.UpdateIntervalMs, "Display", updateDisplay)
everyMs(config.GameplayIntervalMs, "Level points", applyLevelPoints)
everyMs(config.SpeedIntervalMs, "Speed", applySpeeds)
everyMs(config.ItemTypeScanIntervalMs, "Auto pickup", applyAutoPickup)
everyMs(config.EquipmentPickupIntervalMs, "Equipment pickup", applyEquipmentPickup)

-- Hooks are registered only once their feature is switched on, so a feature that is off does not touch the game
-- at all (this keeps "off" a clean baseline when hunting crashes). Once registered they stay registered and read
-- the current menu choice on every call, so switching back off still takes effect immediately.
local function xpFactor() return Settings.selected(settings, "XpMultiplier").Factor end
local function goldFactor() return Settings.selected(settings, "GoldMultiplier").Factor end
local function lootExtra() return Settings.selected(settings, "LootBonus").Extra end

local lazyHooks = {
    {
        name = "XP hook",
        needed = function() return xpFactor() ~= 1 end,
        register = function() XpMultiplier.register(xpFactor) end,
    },
    {
        name = "Drop hook",
        needed = function() return goldFactor() ~= 1 or lootExtra() ~= 0 end,
        register = function()
            DropHooks.register({
                GoldMultiplier.handler(goldFactor, dedupedLogger(), os.clock),
                LootBonus.handler(lootExtra),
            }, dedupedLogger())
        end,
    },
    {
        name = "Free crafting hooks",
        needed = function() return Settings.selected(settings, "FreeCrafting").Enabled end,
        register = function()
            local logError = dedupedLogger()
            local function guarded(action)
                return function()
                    local ok, err = pcall(action, log)
                    if not ok then
                        logError("Free crafting error: " .. tostring(err))
                    end
                end
            end
            RegisterHook("/Script/TQ2Gameplay.TQ2PlayerCharacter:OnCraftingUIOpened", function() end,
                guarded(function(logger)
                    if Settings.selected(settings, "FreeCrafting").Enabled then
                        CraftingCost.onAnvilOpened(logger)
                    end
                end))
            RegisterHook("/Script/TQ2Gameplay.TQ2PlayerCharacter:OnCraftingUIClosed", function() end,
                guarded(CraftingCost.onAnvilClosed))
        end,
    },
    {
        name = "Equipment pickup watcher",
        needed = equipmentPickupOn,
        register = function()
            WorldItems.subscribe(function(item)
                if equipmentPickupOn() then
                    EquipmentPickup.remember(equipmentState, item, os.clock())
                end
            end, log)
        end,
    },
    {
        name = "Damage hook",
        needed = damageMeterEnabled,
        register = function()
            DamageHook.register(damageMeter, damageMeterEnabled, os.clock, dedupedLogger())
        end,
    },
}

local function registerNeededHooks()
    for _, hook in ipairs(lazyHooks) do
        if not hook.registered and hook.needed() then
            hook.register()
            hook.registered = true
            log(hook.name .. " registered")
        end
    end
end

everyMs(config.GameplayIntervalMs, "Hook registration", registerNeededHooks)

-- Anvil anywhere: the key callback only hands the work to the game thread.
local logAnvilError = dedupedLogger()
local anvilKey = Key[config.AnvilKey]
if anvilKey == nil then
    log("Unknown AnvilKey '" .. tostring(config.AnvilKey) .. "', anvil anywhere not available")
else
    RegisterKeyBind(anvilKey, function()
        if not Settings.selected(settings, "AnvilAnywhere").Enabled then
            return
        end
        ExecuteInGameThread(function()
            local ok, err = pcall(CraftingAnywhere.toggle)
            if not ok then
                logAnvilError("Anvil error: " .. tostring(err))
            end
        end)
    end)
end

-- Damage meter reset: only clears Lua state, so it can run directly in the key callback.
local resetKey = Key[config.DamageMeterResetKey]
if resetKey == nil then
    log("Unknown DamageMeterResetKey '" .. tostring(config.DamageMeterResetKey) .. "'")
else
    RegisterKeyBind(resetKey, function()
        DamageMeter.reset(damageMeter)
        hurry(summaryThrottle)
        hurry(detailThrottle)
    end)
end

-- Detail window: the key callback only flips Lua state, the display loop builds or removes the window.
local detailKey = Key[config.DamageDetailKey]
if detailKey == nil then
    log("Unknown DamageDetailKey '" .. tostring(config.DamageDetailKey) .. "'")
else
    RegisterKeyBind(detailKey, function()
        detailOpen = not detailOpen
        hurry(summaryThrottle)
        hurry(detailThrottle)
    end)
end

-- Affix dump for the affix picker: the key callback only hands the work to the game thread.
local affixDumpKey = Key[config.AffixDumpKey]
if affixDumpKey == nil then
    log("Unknown AffixDumpKey '" .. tostring(config.AffixDumpKey) .. "'")
else
    RegisterKeyBind(affixDumpKey, function()
        ExecuteInGameThread(function()
            local paths = { dump = Settings.modFilePath(config.AffixDumpFile),
                            pageData = Settings.modFilePath(config.AffixPageDataFile),
                            filter = Settings.modFilePath(config.LootFilterFile) }
            local ok, err = pcall(AffixDump.write, paths, log)
            if not ok then
                log("Affix dump error: " .. tostring(err))
            end
            local controller = Player.controller()
            local playerState = controller:IsValid() and controller.PlayerState or nil
            local gearOk, gearErr = pcall(GearDump.write, Settings.modFilePath(config.GearDumpFile), playerState, log)
            if not gearOk then
                log("Gear dump error: " .. tostring(gearErr))
            end
        end)
    end)
end

-- Game data dump: Shift + the affix dump key. The mod folder lies in <game>/Binaries/Win64/ue4ss/Mods, so the game
-- folder is everything before "/Binaries/".
local gameDataDump = GameDataDump.newState()
local gameDataModifier = ModifierKey[config.GameDataDumpModifier]
if config.GameDataDump and affixDumpKey ~= nil and gameDataModifier ~= nil then
    RegisterKeyBind(affixDumpKey, { gameDataModifier }, function()
        ExecuteInGameThread(function()
            local gameDir = Settings.modFilePath(""):match("^(.*)[/\\][Bb]inaries[/\\]")
            if gameDir == nil then
                log("Game data dump: game folder not found from the mod path")
                return
            end
            local paths = { cache = gameDir .. "/" .. config.GameDataCacheFile,
                            output = Settings.modFilePath(config.GameDataFile),
                            page = Settings.modFilePath(config.GameDataPageFile) }
            local ok, err = pcall(GameDataDump.start, gameDataDump, paths, log)
            if not ok then
                log("Game data dump error: " .. tostring(err))
            end
        end)
    end)
end

-- Before a level loads, the game tears down the old world. Our widgets and every cached game object are dropped
-- first, while they still exist, so nothing of ours points into the teardown (crashes and hangs around loading
-- screens, 21.11.). Everything is found or built again on the next loop.
local function forgetWorldObjects()
    ShadeWidget.reset()
    DamageMeterWidget.reset()
    DamageDetailWidget.reset()
    MenuWidget.reset()
    MovementLock.sync(false)
    Player.forget()
    ShadeState.forget()
    MovementSpeed.forget()
    EquipmentPickup.clear(equipmentState)
    hurry(summaryThrottle)
    hurry(detailThrottle)
end

RegisterLoadMapPreHook(function()
    local ok, err = pcall(forgetWorldObjects)
    if not ok then
        log("Level change cleanup error: " .. tostring(err))
    end
end)

log("loaded")
