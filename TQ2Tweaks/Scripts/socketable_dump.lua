-- Charms and relics for the affix dump: each one's effects per completion stage, its completion bonus and the items
-- it may be socketed into (UTQ2SocketableItemDescription, a sub-object of its item type). Only reads.
local GameObject = require("game_object")

local SocketableDump = {}

local UNREADABLE = "?"
local REQUIREMENT_MODES = { [0] = "any of", [1] = "all of", [2] = "none of", [3] = "not all of" }

-- Value of read(), or "?" if the field cannot be read (one bad field must not stop the dump).
local function readOr(read)
    local value = GameObject.read(read)
    if value == nil then
        return UNREADABLE
    end
    return value
end

local function formulaText(formula)
    return readOr(function() return formula.SourceText:ToString() end)
end

-- Effects of a socketable stage (FTQ2SocketableItemEffects) as "tooltip [min..max]" texts.
local function socketEffects(effects)
    local texts = {}
    for _, effect in ipairs(GameObject.listOf(effects.effects)) do
        local tooltip = readOr(function() return effect.ToolTipText:ToString() end)
        local low, high = formulaText(effect.Scale.min), formulaText(effect.Scale.max)
        texts[#texts + 1] = string.format("%s [%s..%s]", tostring(tooltip), tostring(low), tostring(high))
    end
    return texts
end

-- A tag requirement (FGrimGameplayTagRequirement) as text, e.g. "any of Weapon, Ring"; nil when it has no tags.
local function requirementText(requirement)
    local base = requirement.BaseRequirement
    local names = GameObject.tagNames(base.GameplayTags)
    if #names == 0 then
        return nil
    end
    local short = {}
    for index, name in ipairs(names) do
        short[index] = name:gsub("^GrimVentory%.ItemType%.", "")
    end
    return (REQUIREMENT_MODES[base.RequirementType] or UNREADABLE) .. " " .. table.concat(short, ", ")
end

-- Where a charm or relic may go (its UGrimItemFilter): item types, other tags and the allowed rarities as a bit mask
-- (bit n = rarity n, 0 Common … 5 Legendary). A missing requirement means no condition.
local function socketTargets(filter)
    if not GameObject.usable(filter) then
        return "any item"
    end
    local parts = {}
    local types = GameObject.read(function() return requirementText(filter.m_ItemTypeRequirement) end)
    local tags = GameObject.read(function() return requirementText(filter.m_GameplayTagsRequirement) end)
    parts[#parts + 1] = "types " .. (types or "any")
    if tags then
        parts[#parts + 1] = "tags " .. tags
    end
    parts[#parts + 1] = "rarity mask " .. tostring(readOr(function() return filter.m_AllowedRarities end))
    return table.concat(parts, "; ")
end

-- One charm or relic as { item, stages = { { effect texts } }, bonus, targets }, nil if it cannot be read.
function SocketableDump.describe(socketable)
    local stages = {}
    local ok = pcall(function()
        for _, stage in ipairs(GameObject.listOf(socketable.m_EffectsByCompletionLevel)) do
            stages[#stages + 1] = socketEffects(stage)
        end
    end)
    if not ok then
        return nil
    end
    return { item = GameObject.read(function() return GameObject.shortName(socketable:GetOuter()) end)
                 or GameObject.shortName(socketable) or UNREADABLE,
             stages = stages, bonus = GameObject.read(function() return socketEffects(socketable.m_CompletionBonus) end) or {},
             targets = readOr(function() return socketTargets(socketable.m_pValidTargetFilter) end) }
end

-- Text lines of the socketables section, sorted by item.
function SocketableDump.lines(socketables)
    table.sort(socketables, function(a, b) return a.item < b.item end)
    local lines = { string.format("SOCKETABLES (%d)", #socketables) }
    for _, socketable in ipairs(socketables) do
        lines[#lines + 1] = "SOCKETABLE " .. socketable.item
        for index, stage in ipairs(socketable.stages) do
            lines[#lines + 1] = string.format("  stage %d: %s", index, table.concat(stage, " | "))
        end
        lines[#lines + 1] = "  bonus: " .. table.concat(socketable.bonus, " | ")
        lines[#lines + 1] = "  sockets into: " .. socketable.targets
    end
    return lines
end

return SocketableDump
