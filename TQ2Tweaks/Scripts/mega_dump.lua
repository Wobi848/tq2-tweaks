-- Mega dump (Ctrl + AffixDumpKey, with config.GameDataDump): loads every data asset the game lists in
-- JsonMetaDataCache.json and writes each one, read generically through the engine's reflection (every property,
-- structs and arrays nested), as one JSON line to a file in the mod folder. Object references are written by name;
-- sub-objects owned by the asset are written in full. Class references to abilities and effects (bp_bga_*, bp_ge_*)
-- add their class default object, where the skill values live. Maps and delegates are skipped (this UE4SS cannot read
-- maps). Only reads; assets are loaded in small batches.
local JsonText = require("json_text")
local BatchJob = require("batch_job")

local MegaDump = {}

local MAX_DEPTH = 10
local MAX_ARRAY = 256
local BATCH_SIZE = 10
local BATCH_DELAY_MS = 50
-- Classes whose class default object is dumped when an asset refers to them.
local FOLLOWED_CLASSES = { "^bp_bga_", "^bp_ge_", "^Bp_bga_", "^Bp_ge_" }
local SKIPPED_KINDS = { MapProperty = true, SetProperty = true, DelegateProperty = true,
                        MulticastInlineDelegateProperty = true, MulticastSparseDelegateProperty = true }
local TEXT_KINDS = { StrProperty = true, NameProperty = true, TextProperty = true }
local REFERENCE_KINDS = { ObjectProperty = true, WeakObjectProperty = true, LazyObjectProperty = true,
                          InterfaceProperty = true }

local function readOr(read)
    local ok, value = pcall(read)
    if ok then
        return value
    end
    return nil
end

local function usable(object)
    return object ~= nil and readOr(function() return object:IsValid() end) == true
end

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

local function followClass(classObject, context)
    local name = readOr(function() return nameOf(classObject) end)
    if name == nil then
        return
    end
    for _, pattern in ipairs(FOLLOWED_CLASSES) do
        if name:find(pattern) then
            context.follow(classObject)
            return
        end
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
        local owned = readOr(function() return value:GetOuter():GetAddress() == context.rootAddress end)
        if owned and depth < MAX_DEPTH then
            return { object = readOr(function() return referenceOf(value) end),
                     fields = serializeFields(propertiesOf(value:GetClass()), value, context, depth + 1) }
        end
        return readOr(function() return referenceOf(value) end)
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
function MegaDump.serializeObject(object, follow)
    local context = { rootAddress = object:GetAddress(), follow = follow or function() end }
    return serializeFields(propertiesOf(object:GetClass()), object, context, 0)
end

-- Every asset path of every class in JsonMetaDataCache.json, as { class, path }.
function MegaDump.assetsOf(cacheText)
    local assets = {}
    for className, block in cacheText:gmatch('"([^"]+)"%s*:%s*{%s*"paths"%s*:%s*%[(.-)%]') do
        for path in block:gmatch('"([^"]+)"') do
            assets[#assets + 1] = { class = className, path = path }
        end
    end
    return assets
end

function MegaDump.newState()
    return { job = nil }
end

-- Starts the dump: paths = { cache = JsonMetaDataCache.json, output = JSON lines file }. Returns false if it cannot
-- start. Call on the game thread.
function MegaDump.start(state, paths, log)
    if BatchJob.isRunning(state.job) then
        log("Mega dump already running")
        return false
    end
    local cacheFile = io.open(paths.cache, "r")
    if cacheFile == nil then
        log("Mega dump: " .. paths.cache .. " not found")
        return false
    end
    local items = MegaDump.assetsOf(cacheFile:read("a"))
    cacheFile:close()
    local output, openError = io.open(paths.output, "w")
    if output == nil then
        log("Mega dump not written: " .. tostring(openError))
        return false
    end
    local seenClasses, counts = {}, { assets = 0, classes = 0, failed = 0 }
    local function follow(classObject)
        local address = classObject:GetAddress()
        if not seenClasses[address] then
            seenClasses[address] = true
            items[#items + 1] = { classObject = classObject }
        end
    end
    local function write(record)
        output:write(JsonText.encode(record), "\n")
    end
    log(string.format("Mega dump started: %d assets", #items))
    state.job = BatchJob.start(items, {
        name = "Mega dump", batchSize = BATCH_SIZE, delayMs = BATCH_DELAY_MS, log = log,
        each = function(item)
            if item.classObject then
                local cdo = readOr(function() return item.classObject:GetCDO() end)
                if usable(cdo) then
                    write({ classDefault = referenceOf(item.classObject), data = MegaDump.serializeObject(cdo, follow) })
                    counts.classes = counts.classes + 1
                end
                return
            end
            local objectPath = item.path .. "." .. item.path:match("([^/]+)$")
            local ok, asset = pcall(LoadAsset, objectPath)
            if ok and usable(asset) then
                write({ class = item.class, path = item.path, data = MegaDump.serializeObject(asset, follow) })
                counts.assets = counts.assets + 1
            else
                write({ class = item.class, path = item.path, notLoaded = true })
                counts.failed = counts.failed + 1
            end
        end,
        finish = function()
            output:close()
            log(string.format("Mega dump written to %s: %d assets (%d not loaded), %d ability/effect classes",
                paths.output, counts.assets, counts.failed, counts.classes))
        end,
    })
    return true
end

return MegaDump
