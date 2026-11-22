-- Mega dump (Ctrl + AffixDumpKey, with config.GameDataDump): loads every data asset the game lists in
-- JsonMetaDataCache.json and writes each one, read generically through the engine's reflection (every property,
-- structs and arrays nested), as one JSON line to a file in the mod folder. Object references are written by name;
-- sub-objects that are part of the asset (also nested ones) are written in full. Class references to abilities,
-- effects, modifiers and skill selectors (bp_bga_*, bp_ge_*, bp_gam_*, bp_selector_*) add their class default object,
-- where the skill values live; referenced balancing objects, which hold the numbers the skill formulas read, are
-- dumped too.
-- Maps and delegates are skipped (this UE4SS cannot read maps). Only reads; assets are loaded in small batches.
local AssetList = require("asset_list")
local GameObject = require("game_object")
local JsonText = require("json_text")
local BatchJob = require("batch_job")
local TextFile = require("text_file")

local MegaDump = {}

local MAX_DEPTH = 10
local MAX_ARRAY = 256
local BATCH_SIZE = 10
local BATCH_DELAY_MS = 50
-- What is dumped besides the assets, unless the rules file (paths.rules, read at every start so it can change while
-- the game runs) says otherwise. All entries are Lua patterns:
--   classes: referenced classes whose class default object is dumped (skill values: abilities bp_bga_*, effects
--            bp_ge_*, modifiers bp_gam_*, skill selectors bp_selector_*, the player's passive effects bp_bge_player_*)
--   objects: referenced objects dumped themselves, matched in the lower-case reference (the balancing data and level
--            scaling tables the skill formulas read their numbers from)
--   globals: classes whose loaded objects are all dumped (the formula system and its tables: the scaling tables are
--            registered there through an interface reference, which UE4SS may not read)
--   defaults: full paths of objects found with StaticFindObject and dumped (settings classes exist only as their
--            default object, e.g. /Script/TQ2Gameplay.Default__TQ2GameplaySettings with the mastery capacity table)
--   skip:    references never dumped. Reading the class default of bp_bge_global_status_immune crashed the game
--            (access violation, 21.11.), and Lua cannot catch that.
local DEFAULT_RULES = {
    classes = { "^[Bb]p_bga_", "^[Bb]p_ge_", "^[Bb]p_gam_", "^[Bb]p_selector_", "^[Bb]p_bge_player_" },
    objects = { "balancing", "scaling" },
    globals = { "GrimDynamicsSubsystem", "GrimDynamicsTable" },
    defaults = { "/Script/TQ2Gameplay.Default__TQ2GameplaySettings" },
    skip = { "bp_bge_global_" },
}
-- How far up the outer chain an object may hang below the asset and still count as part of it (mastery skills sit
-- in a tier, which sits in the mastery).
local MAX_OWNER_DEPTH = 4
local SKIPPED_KINDS = { MapProperty = true, SetProperty = true, DelegateProperty = true,
                        MulticastInlineDelegateProperty = true, MulticastSparseDelegateProperty = true }
local TEXT_KINDS = { StrProperty = true, NameProperty = true, TextProperty = true }
local REFERENCE_KINDS = { ObjectProperty = true, WeakObjectProperty = true, LazyObjectProperty = true,
                          InterfaceProperty = true }

local readOr = GameObject.read
local usable = GameObject.usable

-- Property and field names (GetFName), unlike GameObject.shortName for assets.
local function nameOf(object)
    return object:GetFName():ToString()
end

local function kindOf(property)
    return property:GetClass():GetFName():ToString()
end

-- "Class /Game/Path/Asset.Asset" -> "/Game/Path/Asset.Asset".
local function referenceOf(object)
    local fullName = object:GetFullName()
    return fullName:match("^%S+ (.+)$") or fullName
end

-- Properties of a class or struct including its parents (collected first, no work inside the engine loop).
local function propertiesOf(structType)
    local properties, current, guard = {}, structType, 0
    while usable(current) and guard < 32 do
        local own = {}
        current:ForEachProperty(function(property) own[#own + 1] = property end)
        for _, property in ipairs(own) do
            properties[#properties + 1] = property
        end
        current = readOr(function() return current:GetSuperStruct() end)
        guard = guard + 1
    end
    return properties
end

local serializeFields


local function matchesAny(text, patterns)
    for _, pattern in ipairs(patterns or {}) do
        if text:find(pattern) then
            return true
        end
    end
    return false
end

local function followClass(classObject, context)
    local name = readOr(function() return nameOf(classObject) end)
    if name == nil then
        return
    end
    if matchesAny(name, context.rules.classes) then
        context.follow(classObject, "class")
    end
end

local function serializeValue(property, kind, value, context, depth)
    if value == nil or SKIPPED_KINDS[kind] then
        return nil
    end
    local valueType = type(value)
    if valueType == "number" or valueType == "boolean" or valueType == "string" then
        return value
    end
    if TEXT_KINDS[kind] or kind == "SoftObjectProperty" or kind == "SoftClassProperty" then
        return readOr(function() return value:ToString() end)
    end
    if kind == "ClassProperty" then
        if not usable(value) then
            return nil
        end
        followClass(value, context)
        return readOr(function() return referenceOf(value) end)
    end
    if REFERENCE_KINDS[kind] then
        if not usable(value) then
            return nil
        end
        if depth < MAX_DEPTH and GameObject.isBelow(value, context.rootAddress, MAX_OWNER_DEPTH) then
            return { object = readOr(function() return referenceOf(value) end),
                     fields = serializeFields(propertiesOf(value:GetClass()), value, context, depth + 1) }
        end
        local reference = readOr(function() return referenceOf(value) end)
        if reference and matchesAny(reference:lower(), context.rules.objects) then
            context.follow(value, "object")
        end
        return reference
    end
    if kind == "StructProperty" then
        if depth >= MAX_DEPTH then
            return "..."
        end
        return serializeFields(propertiesOf(property:GetStruct()), value, context, depth + 1)
    end
    if kind == "ArrayProperty" then
        local inner = property:GetInner()
        local innerKind = kindOf(inner)
        local elements = {}
        value:ForEach(function(_, element)
            if #elements < MAX_ARRAY then
                elements[#elements + 1] = element:get()
            end
        end)
        local result = {}
        for index, element in ipairs(elements) do
            result[index] = serializeValue(inner, innerKind, element, context, depth + 1)
        end
        return result
    end
    return readOr(function() return value:ToString() end)
end

-- Every property of a container (an object or a struct value) by name; unreadable ones are left out.
serializeFields = function(properties, container, context, depth)
    local fields = {}
    for _, property in ipairs(properties) do
        local name = readOr(function() return nameOf(property) end)
        local kind = readOr(function() return kindOf(property) end)
        if name and kind and not SKIPPED_KINDS[kind] then
            local value = readOr(function() return container[name] end)
            local ok, serialized = pcall(serializeValue, property, kind, value, context, depth)
            if ok then
                fields[name] = serialized
            end
        end
    end
    return fields
end

-- One object with all its properties, as plain data.
function MegaDump.serializeObject(object, follow, rules)
    local context = { rootAddress = object:GetAddress(), follow = follow or function() end, rules = rules or DEFAULT_RULES }
    return serializeFields(propertiesOf(object:GetClass()), object, context, 0)
end

-- The dump rules from the text of a rules file ({ classes, objects, globals, skip }, data only); a missing key keeps
-- its default. nil text gives the defaults. Returns the rules and an error text if the file could not be used.
function MegaDump.rulesOf(text)
    if text == nil then
        return DEFAULT_RULES
    end
    local chunk, loadError = load(text, "=mega_dump_rules.lua", "t", {})
    local ok, loaded = false, loadError
    if chunk then
        ok, loaded = pcall(chunk)
    end
    if not ok or type(loaded) ~= "table" then
        return DEFAULT_RULES, tostring(loaded)
    end
    local rules = {}
    for key, default in pairs(DEFAULT_RULES) do
        rules[key] = type(loaded[key]) == "table" and loaded[key] or default
    end
    return rules
end

function MegaDump.newState()
    return { job = nil }
end

-- Starts the dump: paths = { cache = JsonMetaDataCache.json, output = JSON lines file, rules = rules file (optional,
-- see DEFAULT_RULES) }. Returns false if it cannot start. Call on the game thread.
function MegaDump.start(state, paths, log)
    if BatchJob.isRunning(state.job) then
        log("Mega dump already running")
        return false
    end
    local cacheText = TextFile.read(paths.cache)
    if cacheText == nil then
        log("Mega dump: " .. paths.cache .. " not found")
        return false
    end
    local rules, rulesError = MegaDump.rulesOf(paths.rules and TextFile.read(paths.rules))
    if rulesError then
        log("Mega dump rules not used, defaults instead: " .. rulesError)
    end
    local items = AssetList.all(cacheText)
    local output, openError = io.open(paths.output, "w")
    if output == nil then
        log("Mega dump not written: " .. tostring(openError))
        return false
    end
    local seen, counts = {}, { assets = 0, classes = 0, objects = 0, failed = 0 }
    -- kind "class": a referenced class, its class default object is dumped; "object": a referenced object itself.
    local function follow(object, kind)
        local address = object:GetAddress()
        if not seen[address] and not matchesAny(readOr(function() return referenceOf(object) end) or "", rules.skip) then
            seen[address] = true
            items[#items + 1] = kind == "class" and { classObject = object } or { object = object }
        end
    end
    for _, path in ipairs(rules.defaults) do
        local object = readOr(function() return StaticFindObject(path) end)
        if usable(object) then
            follow(object, "object")
        end
    end
    for _, className in ipairs(rules.globals) do
        for _, object in ipairs(FindAllOf(className) or {}) do
            follow(object, "object")
        end
    end
    -- Flushed after every record: if reading an object crashes the game, the file shows the last good one.
    local function write(record)
        output:write(JsonText.encode(record), "\n")
        output:flush()
    end
    log(string.format("Mega dump started: %d assets", #items))
    state.job = BatchJob.start(items, {
        name = "Mega dump", batchSize = BATCH_SIZE, delayMs = BATCH_DELAY_MS, log = log,
        each = function(item)
            if item.object then
                if usable(item.object) then
                    write({ object = referenceOf(item.object), data = MegaDump.serializeObject(item.object, follow, rules) })
                    counts.objects = counts.objects + 1
                end
                return
            end
            if item.classObject then
                local cdo = readOr(function() return item.classObject:GetCDO() end)
                if usable(cdo) then
                    write({ classDefault = referenceOf(item.classObject), data = MegaDump.serializeObject(cdo, follow, rules) })
                    counts.classes = counts.classes + 1
                end
                return
            end
            local ok, asset = pcall(LoadAsset, AssetList.objectPath(item.path))
            if ok and usable(asset) then
                write({ class = item.class, path = item.path, data = MegaDump.serializeObject(asset, follow, rules) })
                counts.assets = counts.assets + 1
            else
                write({ class = item.class, path = item.path, notLoaded = true })
                counts.failed = counts.failed + 1
            end
        end,
        finish = function()
            output:close()
            log(string.format("Mega dump written to %s: %d assets (%d not loaded), %d ability/effect classes, "
                .. "%d balancing objects", paths.output, counts.assets, counts.failed, counts.classes, counts.objects))
        end,
    })
    return true
end

return MegaDump
