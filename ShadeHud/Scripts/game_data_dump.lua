-- Game data dump (GameDataDumpKey): loads every creature template listed in the game's JsonMetaDataCache.json and
-- writes the creatures with their drop lists, the global drop lists and the affix tables of all item types to a JSON
-- file in the mod folder. Chances, weights and counts are formulas in the game; their source text is written as it is
-- (e.g. "0.05 * Level"). Only reads. Assets are loaded in small batches so the game keeps running.
local DamageHook = require("damage_hook")
local JsonText = require("json_text")
local BatchJob = require("batch_job")

local GameDataDump = {}

local CREATURE_CLASS = "/Script/TQ2Gameplay.TQ2CreatureTemplateJsonData"
local GLOBAL_DROP_LIST_CLASS = "GrimGlobalItemDropList"
local ITEM_DESCRIPTION_CLASS = "TQ2ItemDescription"
local BATCH_SIZE = 20
local BATCH_DELAY_MS = 50

-- Asset paths of one class from JsonMetaDataCache.json ({ "pathsByClass": { "<class>": { "paths": [ ... ] } } }).
function GameDataDump.pathsOfClass(cacheText, className)
    local pattern = '"' .. className:gsub("%p", "%%%0") .. '"%s*:%s*{%s*"paths"%s*:%s*%[(.-)%]'
    local paths = {}
    for path in (cacheText:match(pattern) or ""):gmatch('"([^"]+)"') do
        paths[#paths + 1] = path
    end
    return paths
end

-- "/JsonData/TQ2/Creatures/da_cr_x" -> "/JsonData/TQ2/Creatures/da_cr_x.da_cr_x" (package path plus object name).
function GameDataDump.objectPath(assetPath)
    return assetPath .. "." .. assetPath:match("([^/]+)$")
end

-- Value of read(), or nil if a field is missing or unreadable (the dump goes on).
local function readOr(read)
    local ok, value = pcall(read)
    if ok then
        return value
    end
    return nil
end

local function listOf(array)
    local list = {}
    if array ~= nil then
        array:ForEach(function(_, element) list[#list + 1] = element:get() end)
    end
    return list
end

local function nameOf(object)
    return object:GetFullName():match("([^%.:]+)$")
end

local function usable(object)
    return object ~= nil and readOr(function() return object:IsValid() end) == true
end

local function text(read)
    local value = readOr(function() return read():ToString() end)
    if value == nil or value == "" then
        return nil
    end
    return value
end

local function formula(value)
    return text(function() return value.SourceText end)
end

local function valueRange(range)
    local result = { min = formula(range.min), max = formula(range.max) }
    if result.min == nil and result.max == nil then
        return nil
    end
    return result
end

local function tagNames(container)
    local names = readOr(function() return DamageHook.tagNames(container) end)
    if names == nil or #names == 0 then
        return nil
    end
    return names
end

-- Tag requirement (FGrimGameplayTagRequirement) as { mode, tags, more = { { mode, tags } } }, nil when empty.
local function tagRequirement(requirement)
    local base = requirement.BaseRequirement
    local result = { tags = tagNames(base.GameplayTags), mode = readOr(function() return base.RequirementType end) }
    local more = {}
    for _, extra in ipairs(readOr(function() return listOf(requirement.AdditionalRequirements) end) or {}) do
        local tags = tagNames(extra.GameplayTags)
        if tags then
            more[#more + 1] = { tags = tags, mode = readOr(function() return extra.RequirementType end) }
        end
    end
    result.more = #more > 0 and more or nil
    if result.tags == nil and result.more == nil then
        return nil
    end
    return result
end

-- Requirement of a table entry (tags, custom formula, item level for affix tables), nil when there is none.
local function requirement(value)
    local result = {
        tags = readOr(function() return tagRequirement(value.GameplayTagRequirement) end),
        custom = formula(value.CustomRequirement),
        itemLevelMin = readOr(function() return formula(value.ItemLevelMin) end),
        itemLevelMax = readOr(function() return formula(value.ItemLevelMax) end),
    }
    if next(result) == nil then
        return nil
    end
    return result
end

-- Name of the item type an FGrimItemDrop drops (loaded reference, else the soft path).
local function droppedItem(itemDrop)
    local pointer = itemDrop.pItemDescription
    local loaded = readOr(function() return pointer.HardReference end)
    if usable(loaded) then
        return nameOf(loaded)
    end
    return text(function() return pointer.SoftPath.Path end)
end

local function itemDrop(entry)
    return {
        item = readOr(function() return droppedItem(entry.ItemDrop) end),
        count = readOr(function() return valueRange(entry.ItemDrop.NumToDrop) end),
        rarityWeights = readOr(function() return formula(entry.ItemDrop.RarityWeights.RarityWeights) end),
    }
end

local describeDropList

-- A drop table (FGrimItemDropTable): weighted entries and weighted sub-lists.
local function dropTable(dropTableValue, lists)
    local entries = {}
    for _, entry in ipairs(readOr(function() return listOf(dropTableValue.Entries) end) or {}) do
        local drop = itemDrop(entry)
        drop.weight = formula(entry.Weight)
        drop.guaranteed = readOr(function() return entry.IsGuaranteed end) or nil
        drop.requirement = readOr(function() return requirement(entry.Requirement) end)
        entries[#entries + 1] = drop
    end
    for _, subTable in ipairs(readOr(function() return listOf(dropTableValue.SubTables) end) or {}) do
        entries[#entries + 1] = {
            list = describeDropList(readOr(function() return subTable.pDropList end), lists),
            weight = formula(subTable.Weight),
            guaranteed = readOr(function() return subTable.IsGuaranteed end) or nil,
            requirement = readOr(function() return requirement(subTable.Requirement) end),
        }
    end
    return entries
end

-- Describes a drop list once into `lists` (by name) and returns its name; nil for no list.
describeDropList = function(list, lists)
    if not usable(list) then
        return nil
    end
    local name = nameOf(list)
    if lists[name] ~= nil then
        return name
    end
    local description = {}
    lists[name] = description -- before the tables: a list may contain itself
    description.class = readOr(function() return list:GetClass():GetFName():ToString() end)
    description.dropChance = readOr(function() return formula(list.m_DropChance) end)
    description.rarityWeights = readOr(function() return formula(list.m_RarityWeights.RarityWeights) end)
    description.randomDrops = readOr(function() return valueRange(list.m_NumRandomDrops) end)
    local fixed = {}
    for _, entry in ipairs(readOr(function() return listOf(list.m_FixedDrops) end) or {}) do
        local drop = itemDrop(entry)
        drop.requirement = readOr(function() return requirement(entry.Requirement) end)
        fixed[#fixed + 1] = drop
    end
    description.fixedDrops = #fixed > 0 and fixed or nil
    description.randomTable = readOr(function() return dropTable(list.m_RandomDropTable, lists) end)
    description.globalFilter = readOr(function() return tagRequirement(list.m_GlobalDropTable.FilterRequirement) end)
    return name
end

function GameDataDump.describeCreature(template, assetPath, lists)
    local creature = template.m_CreatureDesc
    local overrideChance = readOr(function() return creature.OverrideItemDropChance end)
    local overrideCount = readOr(function() return creature.OverrideNumItemDrops end)
    return {
        path = assetPath,
        name = text(function() return creature.Name end),
        title = text(function() return creature.Title end),
        internalName = text(function() return creature.InternalName end),
        tags = readOr(function() return tagNames(creature.GameplayTags) end),
        dropList = describeDropList(readOr(function() return creature.pDropList end), lists),
        dropChance = overrideChance and formula(creature.ItemDropChanceOverride) or nil,
        dropCount = overrideCount and readOr(function() return valueRange(creature.NumItemDropsOverride) end) or nil,
        rarityWeights = readOr(function() return formula(creature.ItemRarityWeights.RarityWeights) end),
    }
end

local describeAffixTable

-- An affix table (FGrimItemAffixTable): weighted affixes with their requirements, sub-tables described once.
local function affixEntries(affixTable, tables)
    local entries = {}
    for _, entry in ipairs(readOr(function() return listOf(affixTable.Entries) end) or {}) do
        local affix = readOr(function() return entry.pAffix end)
        if usable(affix) then
            entries[#entries + 1] = { affix = nameOf(affix), weight = formula(entry.Weight),
                                      requirement = readOr(function() return requirement(entry.Requirement) end) }
        end
    end
    for _, subTable in ipairs(readOr(function() return listOf(affixTable.SubTables) end) or {}) do
        entries[#entries + 1] = { table = describeAffixTable(readOr(function() return subTable.pTable end), tables),
                                  weight = formula(subTable.Weight),
                                  requirement = readOr(function() return requirement(subTable.Requirement) end) }
    end
    return entries
end

describeAffixTable = function(asset, tables)
    if not usable(asset) then
        return nil
    end
    local name = nameOf(asset)
    if tables[name] == nil then
        tables[name] = {}
        tables[name] = affixEntries(asset.m_Table, tables)
    end
    return name
end

function GameDataDump.describeItemType(description, tables)
    return {
        name = nameOf(description),
        type = readOr(function() return description.m_Type.TagName:ToString() end),
        tags = readOr(function() return tagNames(description.m_GameplayTags) end),
        randomAffixes = readOr(function() return affixEntries(description.m_RandomAffixes, tables) end),
    }
end

local function writeFile(path, content, log)
    local file, openError = io.open(path, "w")
    if file == nil then
        log("Game data not written: " .. tostring(openError))
        return false
    end
    file:write(content)
    file:close()
    return true
end

local function finish(dump)
    for _, list in ipairs(FindAllOf(GLOBAL_DROP_LIST_CLASS) or {}) do
        local name = describeDropList(list, dump.data.dropLists)
        if name then
            dump.data.globalDropLists[#dump.data.globalDropLists + 1] = name
        end
    end
    for _, description in ipairs(FindAllOf(ITEM_DESCRIPTION_CLASS) or {}) do
        if usable(description) then
            dump.data.itemTypes[#dump.data.itemTypes + 1] = GameDataDump.describeItemType(description, dump.data.affixTables)
        end
    end
    local dropListCount = 0
    for _ in pairs(dump.data.dropLists) do
        dropListCount = dropListCount + 1
    end
    local json = JsonText.encode(dump.data)
    -- The same data as a script for tools/game_data.html (a page opened from disk may load a script, not a file).
    if writeFile(dump.outputPath, json .. "\n", dump.log)
        and writeFile(dump.pagePath, "window.TQ2_GAME_DATA = " .. json .. ";\n", dump.log) then
        dump.log(string.format("Game data written to %s: %d creatures (%d not loaded), %d drop lists, %d item types",
            dump.outputPath, #dump.data.creatures, #dump.data.notLoaded, dropListCount, #dump.data.itemTypes))
    end
end

function GameDataDump.newState()
    return { job = nil }
end

function GameDataDump.isRunning(state)
    return BatchJob.isRunning(state.job)
end

-- Starts the dump: paths = { cache = JsonMetaDataCache.json, output = JSON file, page = script file for the data
-- page }. Returns false if it cannot start (one already runs, or the cache file is missing). Call on the game thread.
function GameDataDump.start(state, paths, log)
    if GameDataDump.isRunning(state) then
        log("Game data dump already running")
        return false
    end
    local file = io.open(paths.cache, "r")
    if file == nil then
        log("Game data dump: " .. paths.cache .. " not found")
        return false
    end
    local cacheText = file:read("a")
    file:close()
    local dump = {
        outputPath = paths.output, pagePath = paths.page, log = log,
        data = { creatures = {}, notLoaded = {}, dropLists = {}, globalDropLists = {}, itemTypes = {}, affixTables = {} },
    }
    local creaturePaths = GameDataDump.pathsOfClass(cacheText, CREATURE_CLASS)
    log(string.format("Game data dump started: %d creature templates", #creaturePaths))
    state.job = BatchJob.start(creaturePaths, {
        name = "Game data dump", batchSize = BATCH_SIZE, delayMs = BATCH_DELAY_MS, log = log,
        each = function(path)
            local ok, template = pcall(LoadAsset, GameDataDump.objectPath(path))
            if ok and usable(template) then
                dump.data.creatures[#dump.data.creatures + 1] =
                    GameDataDump.describeCreature(template, path, dump.data.dropLists)
            else
                dump.data.notLoaded[#dump.data.notLoaded + 1] = path
            end
        end,
        finish = function() finish(dump) end,
    })
    return true
end

return GameDataDump
