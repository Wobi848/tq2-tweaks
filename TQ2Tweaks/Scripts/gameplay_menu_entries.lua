-- Menu rows for the gameplay tweaks (single player only).
local Settings = require("settings")
local listEntry = require("setting_entry")

local GameplayMenuEntries = {}

local function countEntry(settings, label, key)
    return {
        label = label,
        value = function() return tostring(settings.values[key]) end,
        change = function(direction) Settings.adjust(settings, key, direction) end,
    }
end

-- A section header followed by one on/off row per item of `list` (each with Name and Setting).
local function switchSection(settings, header, list)
    local entries = { { header = header } }
    for _, item in ipairs(list) do
        entries[#entries + 1] = listEntry(settings, item.MenuLabel or item.Name, item.Setting)
    end
    return entries
end

function GameplayMenuEntries.create(settings)
    local entries = {
        { header = "Rewards" },
        listEntry(settings, "Experience", "XpMultiplier"),
        listEntry(settings, "Gold from enemies", "GoldMultiplier"),
        listEntry(settings, "Extra loot", "LootBonus"),
        { header = "Speed" },
        listEntry(settings, "Movement speed", "MoveSpeed"),
        listEntry(settings, "Game speed", "GameSpeed"),
        { header = "Points per level" },
        countEntry(settings, "Attribute points", "AttributePointsPerLevel"),
        countEntry(settings, "Active skill points", "ActivePointsPerLevel"),
        countEntry(settings, "Passive skill points", "PassivePointsPerLevel"),
        countEntry(settings, "Mastery points", "MasteryPointsPerLevel"),
        { header = "Crafting" },
        listEntry(settings, "Free", "FreeCrafting"),
        listEntry(settings, "Anvil anywhere (" .. settings.config.AnvilKey .. ")", "AnvilAnywhere"),
        { header = "Damage meter" },
        listEntry(settings, string.format("Show (%s reset, %s details)", settings.config.DamageMeterResetKey,
            settings.config.DamageDetailKey), "DamageMeter"),
        listEntry(settings, "Position", "DamageMeterPosition"),
        listEntry(settings, "Graph", "DamageMeterGraph"),
        listEntry(settings, "Damage types", "DamageMeterTypes"),
        listEntry(settings, "Skills", "DamageMeterSkills"),
    }
    local config = settings.config
    for _, section in ipairs({
        switchSection(settings, "Auto-Pickup", config.AutoPickupCategories),
    }) do
        for _, entry in ipairs(section) do
            entries[#entries + 1] = entry
        end
    end
    entries[#entries + 1] = listEntry(settings, "Loot filter (loot_filter.html)", "LootFilter")
    entries[#entries + 1] = listEntry(settings, "   only upgrades over worn gear", "LootFilterUpgradesOnly")
    return entries
end

return GameplayMenuEntries
