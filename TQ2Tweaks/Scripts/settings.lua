-- Settings changed in game: load, change, save, and derive ready-to-use layout values.
local Settings = {}

local EDITABLE_KEYS = {
    "OffsetX", "OffsetY", "Scale", "ColorPreset", "TextColorPreset", "DisplayMode",
    "XpMultiplier", "GoldMultiplier", "LootBonus", "FreeCrafting", "AnvilAnywhere", "CaravanAnywhere", "MoveSpeed", "GameSpeed", "DamageMeter",
    "DamageMeterPosition", "DamageMeterGraph", "DamageMeterTypes", "DamageMeterSkills",
    "AutoPickupMaterials", "AutoPickupPotions", "AutoPickupSocketables", "AutoPickupEquipment",
    "LootFilter", "LootFilterUpgradesOnly", "AttributePointsPerLevel", "ActivePointsPerLevel", "PassivePointsPerLevel", "MasteryPointsPerLevel",
}

-- Settings whose value is an index into a list from config (setting -> list name).
local LIST_SETTINGS = {
    ColorPreset = "ColorPresets",
    TextColorPreset = "TextColorPresets",
    DisplayMode = "DisplayModes",
    XpMultiplier = "RewardMultipliers",
    GoldMultiplier = "RewardMultipliers",
    LootBonus = "LootBonuses",
    FreeCrafting = "OnOffOptions",
    AnvilAnywhere = "OnOffOptions",
    CaravanAnywhere = "OnOffOptions",
    MoveSpeed = "MoveSpeeds",
    GameSpeed = "GameSpeeds",
    DamageMeter = "OnOffOptions",
    DamageMeterPosition = "DamageMeterPositions",
    DamageMeterGraph = "OnOffOptions",
    DamageMeterTypes = "OnOffOptions",
    DamageMeterSkills = "OnOffOptions",
    AutoPickupMaterials = "OnOffOptions",
    AutoPickupPotions = "OnOffOptions",
    AutoPickupSocketables = "OnOffOptions",
    AutoPickupEquipment = "EquipmentRarityThresholds",
    LootFilter = "OnOffOptions",
    LootFilterUpgradesOnly = "OnOffOptions",
}

-- Whole-number settings with a range (setting -> config keys for min and max).
local COUNT_SETTINGS = {
    AttributePointsPerLevel = { "PointsMin", "PointsMax" },
    ActivePointsPerLevel = { "PointsMin", "PointsMax" },
    PassivePointsPerLevel = { "PointsMin", "PointsMax" },
    MasteryPointsPerLevel = { "PointsMin", "PointsMax" },
}

-- Path of a file in the mod folder (next to the Scripts folder).
function Settings.modFilePath(fileName)
    local scriptPath = debug.getinfo(1, "S").source:sub(2)
    local scriptDir = scriptPath:match("^(.*[/\\])") or ""
    return scriptDir .. "../" .. fileName
end

local function userSettingsPath()
    return Settings.modFilePath("user_settings.lua")
end

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function fileExists(path)
    local file = io.open(path, "r")
    if file == nil then
        return false
    end
    file:close()
    return true
end

-- Reads saved values; a missing or broken file falls back to the defaults.
local function loadSaved(path, log)
    if not fileExists(path) then
        return {}
    end
    local chunk, loadError = loadfile(path)
    if chunk == nil then
        log("user_settings.lua is broken, using defaults: " .. tostring(loadError))
        return {}
    end
    local ok, saved = pcall(chunk)
    if not ok or type(saved) ~= "table" then
        log("user_settings.lua is broken, using defaults: " .. tostring(saved))
        return {}
    end
    return saved
end

-- Creates the settings from config (defaults) plus saved values; out-of-range values are clamped.
function Settings.new(config, log)
    local saved = loadSaved(userSettingsPath(), log)
    local values = {}
    for _, key in ipairs(EDITABLE_KEYS) do
        values[key] = type(saved[key]) == "number" and saved[key] or config[key]
    end
    values.Scale = clamp(values.Scale, config.ScaleMin, config.ScaleMax)
    for key, listName in pairs(LIST_SETTINGS) do
        values[key] = clamp(math.floor(values[key]), 1, #config[listName])
    end
    for key, range in pairs(COUNT_SETTINGS) do
        values[key] = clamp(math.floor(values[key]), config[range[1]], config[range[2]])
    end
    return { config = config, values = values, revision = 0, log = log }
end

local function changed(settings)
    settings.revision = settings.revision + 1
end

function Settings.move(settings, deltaX, deltaY)
    settings.values.OffsetX = settings.values.OffsetX + deltaX
    settings.values.OffsetY = settings.values.OffsetY + deltaY
    changed(settings)
end

function Settings.resize(settings, direction)
    local config = settings.config
    local scale = settings.values.Scale + direction * config.ScaleStep
    settings.values.Scale = clamp(math.floor(scale * 10 + 0.5) / 10, config.ScaleMin, config.ScaleMax)
    changed(settings)
end

-- Steps a list setting (see LIST_SETTINGS) forward (1) or back (-1), wrapping around.
function Settings.cycle(settings, key, direction)
    local count = #settings.config[LIST_SETTINGS[key]]
    settings.values[key] = (settings.values[key] - 1 + direction) % count + 1
    changed(settings)
end

-- The currently selected list entry of a list setting.
function Settings.selected(settings, key)
    return settings.config[LIST_SETTINGS[key]][settings.values[key]]
end

-- Changes a count setting (see COUNT_SETTINGS) by delta within its range.
function Settings.adjust(settings, key, delta)
    local range = COUNT_SETTINGS[key]
    local config = settings.config
    settings.values[key] = clamp(settings.values[key] + delta, config[range[1]], config[range[2]])
    changed(settings)
end

function Settings.save(settings)
    local path = userSettingsPath()
    local file, openError = io.open(path, "w")
    if file == nil then
        settings.log("Could not save settings: " .. tostring(openError))
        return
    end
    file:write("-- Saved by TQ2Tweaks in game (F5 menu). Delete this file to reset to the values in config.lua.\n")
    file:write("return {\n")
    for _, key in ipairs(EDITABLE_KEYS) do
        file:write(string.format("    %s = %s,\n", key, tostring(settings.values[key])))
    end
    file:write("}\n")
    file:close()
    settings.log("Settings saved")
end

-- Ready-to-use values for the shade display: scaled sizes, resolved colours and display mode.
function Settings.layout(settings)
    local config, values = settings.config, settings.values
    local preset = Settings.selected(settings, "ColorPreset")
    local mode = Settings.selected(settings, "DisplayMode")
    local scale = values.Scale
    return {
        anchorX = config.AnchorX,
        anchorY = config.AnchorY,
        offsetX = values.OffsetX,
        offsetY = values.OffsetY,
        barWidth = math.floor(config.BarWidth * scale + 0.5),
        barHeight = math.floor(config.BarHeight * scale + 0.5),
        barSpacing = math.floor(config.BarSpacing * scale + 0.5),
        fontSize = math.floor(config.FontSize * scale + 0.5),
        fullColor = preset.Full,
        chargingColor = preset.Charging,
        textColor = Settings.selected(settings, "TextColorPreset").Color,
        showBars = mode.ShowBars,
        showNumbers = mode.ShowNumbers,
    }
end

return Settings
