-- Affix dump (AffixDumpKey): writes every loaded item affix (UGrimItemAffix) with its tags and level
-- texts, plus the affixes of the items lying on the ground, to a text file in the mod folder. The loot filter
-- editor (loot_filter.html) reads this file to choose the affixes for equipment pickup. Only reads.
local DamageHook = require("damage_hook")
local EquipmentPickup = require("equipment_pickup")
local JsonText = require("json_text")

local AffixDump = {}

local AFFIX_CLASS = "GrimItemAffix"
local WORLD_ITEM_CLASS = "TQ2WorldItem"
local ITEM_DESCRIPTION_CLASS = "TQ2ItemDescription"
local SOCKETABLE_CLASS = "TQ2SocketableItemDescription"
local UNREADABLE = "?"

-- Value of read(), or "?" if the field cannot be read (fields differ between affixes; one bad field must not stop
-- the dump).
local function readOr(read)
    local ok, value = pcall(read)
    if not ok or value == nil then
        return UNREADABLE
    end
    return value
end

-- TArray as a Lua list (collected first, no work inside the engine loop).
local function listOf(array)
    local list = {}
    array:ForEach(function(_, element) list[#list + 1] = element:get() end)
    return list
end

local function objectName(object)
    return object:GetFullName():match("([^%.:]+)$") or UNREADABLE
end

local function describeEffect(effect)
    return { type = readOr(function() return effect.Type end),
             tooltip = readOr(function() return effect.ToolTipText:ToString() end) }
end

local function describeLevel(level)
    local effects = {}
    local ok, list = pcall(listOf, level.AffixEffects)
    for _, effect in ipairs(ok and list or {}) do
        effects[#effects + 1] = describeEffect(effect)
    end
    return { title = readOr(function() return level.TitleText:ToString() end),
             adjective = readOr(function() return level.AdjectiveText:ToString() end),
             effects = effects }
end

-- Plain description of one affix: { name, type, tags, levels = { { title, adjective, effects } } }.
function AffixDump.describeAffix(affix)
    local levels = {}
    local ok, list = pcall(function() return listOf(affix.m_Levels.Levels) end)
    for _, level in ipairs(ok and list or {}) do
        levels[#levels + 1] = describeLevel(level)
    end
    return { name = readOr(function() return objectName(affix) end),
             type = readOr(function() return affix.m_Type end),
             tags = readOr(function() return table.concat(DamageHook.tagNames(affix.m_GameplayTags), ", ") end),
             levels = levels }
end

-- Plain description of a ground item: { type, rarity, affixes = { affix names } }, or nil while it is not filled in.
function AffixDump.describeGroundItem(item)
    local instance = EquipmentPickup.instanceOf(item)
    if instance == nil then
        return nil
    end
    local affixes = {}
    for _, affix in ipairs(EquipmentPickup.affixesOf(instance)) do
        affixes[#affixes + 1] = affix.name .. " L" .. tostring(affix.level)
    end
    return { type = EquipmentPickup.typeNameOf(item), rarity = instance.m_Rarity, affixes = affixes }
end

-- Affix names of an affix table (FGrimItemAffixTable) including its sub-tables. Sub-table assets are shared by many
-- item types, so their names are kept in `cache` (by asset) and each one is walked once.
local function tableAffixes(affixTable, cache)
    local names = {}
    for _, entry in ipairs(listOf(affixTable.Entries)) do
        local affix = entry.pAffix
        if affix ~= nil and affix:IsValid() then
            names[objectName(affix)] = true
        end
    end
    for _, subTable in ipairs(listOf(affixTable.SubTables)) do
        local asset = subTable.pTable
        if asset ~= nil and asset:IsValid() then
            local key = asset:GetFullName()
            if cache[key] == nil then
                cache[key] = {} -- guards against a table that contains itself
                cache[key] = tableAffixes(asset.m_Table, cache)
            end
            for name in pairs(cache[key]) do
                names[name] = true
            end
        end
    end
    return names
end

-- Random affix pool of an item type: { type, affixes = sorted names }, or nil if it has none or cannot be read.
function AffixDump.describePool(description, cache)
    local ok, names = pcall(tableAffixes, description.m_RandomAffixes, cache)
    if not ok then
        return nil
    end
    local affixes = {}
    for name in pairs(names) do
        affixes[#affixes + 1] = name
    end
    if #affixes == 0 then
        return nil
    end
    table.sort(affixes)
    return { type = objectName(description), affixes = affixes }
end

local function formulaText(formula)
    return readOr(function() return formula.SourceText:ToString() end)
end

-- Effects of a socketable stage (FTQ2SocketableItemEffects) as "tooltip [min..max]" texts.
local function socketEffects(effects)
    local texts = {}
    for _, effect in ipairs(listOf(effects.effects)) do
        local tooltip = readOr(function() return effect.ToolTipText:ToString() end)
        local low, high = formulaText(effect.Scale.min), formulaText(effect.Scale.max)
        texts[#texts + 1] = string.format("%s [%s..%s]", tostring(tooltip), tostring(low), tostring(high))
    end
    return texts
end

local REQUIREMENT_MODES = { [0] = "any of", [1] = "all of", [2] = "none of", [3] = "not all of" }

-- A tag requirement (FGrimGameplayTagRequirement) as text, e.g. "any of Weapon, Ring"; nil when it has no tags.
local function requirementText(requirement)
    local base = requirement.BaseRequirement
    local names = DamageHook.tagNames(base.GameplayTags)
    if #names == 0 then
        return nil
    end
    local short = {}
    for index, name in ipairs(names) do
        short[index] = name:gsub("^GrimVentory%.ItemType%.", "")
    end
    return (REQUIREMENT_MODES[base.RequirementType] or "?") .. " " .. table.concat(short, ", ")
end

-- Where a charm or relic may go (its UGrimItemFilter): item types, other tags and the allowed rarities as a bit mask
-- (bit n = rarity n, 0 Common … 5 Legendary).
local function socketTargets(filter)
    if filter == nil or not readOr(function() return filter:IsValid() end) then
        return "any item"
    end
    -- Unlike readOr, a missing requirement is nil here (no condition), not "?".
    local function optional(read)
        local ok, value = pcall(read)
        return ok and value or nil
    end
    local parts = {}
    local types = optional(function() return requirementText(filter.m_ItemTypeRequirement) end)
    local tags = optional(function() return requirementText(filter.m_GameplayTagsRequirement) end)
    local rarities = readOr(function() return filter.m_AllowedRarities end)
    parts[#parts + 1] = "types " .. (types or "any")
    if tags then
        parts[#parts + 1] = "tags " .. tags
    end
    parts[#parts + 1] = "rarity mask " .. tostring(rarities)
    return table.concat(parts, "; ")
end

-- Charm or relic (UTQ2SocketableItemDescription, a sub-object of its item type): effects per completion stage, the
-- completion bonus and the items it may be socketed into. nil if it cannot be read.
function AffixDump.describeSocketable(socketable)
    local stages = {}
    local ok = pcall(function()
        for _, stage in ipairs(listOf(socketable.m_EffectsByCompletionLevel)) do
            stages[#stages + 1] = socketEffects(stage)
        end
    end)
    if not ok then
        return nil
    end
    return { item = readOr(function() return objectName(socketable:GetOuter()) end) or objectName(socketable),
             stages = stages, bonus = readOr(function() return socketEffects(socketable.m_CompletionBonus) end) or {},
             targets = readOr(function() return socketTargets(socketable.m_pValidTargetFilter) end) or "?" }
end

-- Item types with the same pool share one entry: { types = sorted names, affixes }.
local function groupedPools(pools)
    local byKey, groups = {}, {}
    for _, pool in ipairs(pools) do
        local key = table.concat(pool.affixes, ",")
        local group = byKey[key]
        if group == nil then
            group = { types = {}, affixes = pool.affixes }
            byKey[key] = group
            groups[#groups + 1] = group
        end
        group.types[#group.types + 1] = pool.type
    end
    for _, group in ipairs(groups) do
        table.sort(group.types)
    end
    table.sort(groups, function(a, b) return a.types[1] < b.types[1] end)
    return groups
end

local function levelLine(index, level)
    local tooltips = {}
    for _, effect in ipairs(level.effects) do
        tooltips[#tooltips + 1] = string.format("[%s] %s", tostring(effect.type), effect.tooltip)
    end
    return string.format("  L%d \"%s\" adjective \"%s\": %s", index, level.title, level.adjective,
        table.concat(tooltips, " | "))
end

-- Text lines of the dump: affixes sorted by name, the ground items, then which random affixes each item type can
-- roll (item types with the same pool grouped), then the charms and relics with their effects.
function AffixDump.lines(affixes, groundItems, pools, socketables)
    table.sort(affixes, function(a, b) return a.name < b.name end)
    local lines = { string.format("AFFIXES (%d loaded)", #affixes) }
    for _, affix in ipairs(affixes) do
        lines[#lines + 1] = string.format("%s  type=%s  tags=%s", affix.name, tostring(affix.type), affix.tags)
        for index, level in ipairs(affix.levels) do
            lines[#lines + 1] = levelLine(index, level)
        end
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = string.format("GROUND ITEMS (%d)", #groundItems)
    for _, item in ipairs(groundItems) do
        lines[#lines + 1] = string.format("%s  rarity=%s: %s", item.type, tostring(item.rarity),
            table.concat(item.affixes, ", "))
    end
    local groups = groupedPools(pools or {})
    lines[#lines + 1] = ""
    lines[#lines + 1] = string.format("AFFIX POOLS (%d item types, %d pools)", #(pools or {}), #groups)
    for _, group in ipairs(groups) do
        lines[#lines + 1] = "POOL types=" .. table.concat(group.types, ",")
        lines[#lines + 1] = "  affixes=" .. table.concat(group.affixes, ",")
    end
    socketables = socketables or {}
    table.sort(socketables, function(a, b) return a.item < b.item end)
    lines[#lines + 1] = ""
    lines[#lines + 1] = string.format("SOCKETABLES (%d)", #socketables)
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

local function describeAll(className, describe)
    local result = {}
    for _, object in ipairs(FindAllOf(className) or {}) do
        local description = object:IsValid() and describe(object)
        if description then
            result[#result + 1] = description
        end
    end
    return result
end

local function readAll(path)
    local file = io.open(path, "r")
    if file == nil then
        return nil
    end
    local text = file:read("a")
    file:close()
    return text
end

local function writeAll(path, text, log)
    local file, openError = io.open(path, "w")
    if file == nil then
        log("Affix dump not written: " .. tostring(openError))
        return false
    end
    file:write(text)
    file:close()
    return true
end

-- The data file next to loot_filter.html: a browser may not read local files on its own, but it loads a script
-- beside the page. It carries the dump and the current loot filter, so the editor opens with both.
function AffixDump.pageData(dumpText, filterText)
    return "window.TQ2_TWEAKS_DATA = { dump: " .. JsonText.string(dumpText) .. ", filter: "
        .. (filterText and JsonText.string(filterText) or "null") .. " };\n"
end

-- Writes the dump to paths.dump and the editor's data file to paths.pageData (with the loot filter read from
-- paths.filter) and logs where they went. Call on the game thread.
function AffixDump.write(paths, log)
    local cache = {}
    local lines = AffixDump.lines(describeAll(AFFIX_CLASS, AffixDump.describeAffix),
        describeAll(WORLD_ITEM_CLASS, AffixDump.describeGroundItem),
        describeAll(ITEM_DESCRIPTION_CLASS, function(description) return AffixDump.describePool(description, cache) end),
        describeAll(SOCKETABLE_CLASS, AffixDump.describeSocketable))
    local dumpText = table.concat(lines, "\n") .. "\n"
    if writeAll(paths.dump, dumpText, log)
        and writeAll(paths.pageData, AffixDump.pageData(dumpText, readAll(paths.filter)), log) then
        log(string.format("Affix dump written to %s (%d lines)", paths.dump, #lines))
    end
end

return AffixDump
