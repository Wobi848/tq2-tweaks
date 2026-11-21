-- Auto pickup for chosen item kinds via the game's own mechanism.
--
-- Every item type (UGrimItemDescription) has m_CanAutoPickup; the player's UGrimItemHooverComponent pulls in every
-- item in range whose type has it set (gold does by default). Switching the flag on for more types makes them
-- behave exactly like gold: same range (AutoPickupRange), same feel, and the game handles a full inventory.
--
-- Item kinds are recognised by lower-case text patterns in the asset path and the type tag (m_Type), configured in
-- config.AutoPickupCategories. Turning a kind off restores the original flag of every type it changed.
local AutoPickup = {}

local ITEM_DESCRIPTION_CLASS = "TQ2ItemDescription"
local FLAG = "m_CanAutoPickup"
-- How many folders/type tags the one-time overview lists in the log.
local OVERVIEW_LIMIT = 40

-- Item description address -> { original = bool, category = index }
local changed = {}
-- Item description address -> category index or false. Name and type tag are read once per type, because
-- reading them for ~1000 types on every pass cost noticeable frame time.
local categoryByAddress = {}
-- Number of loaded types and enabled categories at the last pass; nothing to do while both are unchanged.
local lastSignature = nil

-- Item type object name (e.g. "da_sword_01") -> category index or false, for equipment_pickup.lua, which only
-- knows the ground item's name.
AutoPickup.kindByName = {}
local overviewWritten = false

local function typeTag(itemDescription)
    local ok, name = pcall(function() return itemDescription.m_Type.TagName:ToString() end)
    return ok and name or ""
end

-- Index of the first category whose pattern occurs in the item's path or type tag, or nil.
function AutoPickup.categoryOf(categories, searchText)
    for index, category in ipairs(categories) do
        for _, pattern in ipairs(category.Match) do
            if searchText:find(pattern, 1, true) then
                return index
            end
        end
    end
    return nil
end

local function searchTextOf(itemDescription)
    return (itemDescription:GetFullName() .. " " .. typeTag(itemDescription)):lower()
end

local function countEntries(counts)
    local list = {}
    for key, count in pairs(counts) do list[#list + 1] = { key = key, count = count } end
    table.sort(list, function(a, b) return a.count > b.count end)
    local parts = {}
    for index = 1, math.min(#list, OVERVIEW_LIMIT) do
        parts[#parts + 1] = string.format("%s=%d", list[index].key, list[index].count)
    end
    return table.concat(parts, ", ")
end

-- Once per session: which folders and type tags exist and how many types each category matches, so the
-- patterns in config can be checked against the real game data.
local function writeOverview(itemDescriptions, categories, log)
    local folders, tags, perCategory = {}, {}, {}
    for _, itemDescription in ipairs(itemDescriptions) do
        -- Full name format: "TQ2ItemDescription /Game/Folder/asset.asset" -> "/Game/Folder"
        local path = itemDescription:GetFullName():match(" (/.*)/[^/]*$") or "?"
        folders[path] = (folders[path] or 0) + 1
        local tag = typeTag(itemDescription)
        tags[tag] = (tags[tag] or 0) + 1
        local category = AutoPickup.categoryOf(categories, searchTextOf(itemDescription))
        local label = category and categories[category].Name or "(none)"
        perCategory[label] = (perCategory[label] or 0) + 1
    end
    log("Auto pickup overview - categories: " .. countEntries(perCategory))
    log("Auto pickup overview - type tags: " .. countEntries(tags))
    log("Auto pickup overview - folders: " .. countEntries(folders))
end

-- enabled[index] tells whether category `index` uses the type flag. needKinds keeps AutoPickup.kindByName filled
-- even if no flag is wanted (equipment pickup by rarity). debugLog (or nil) receives the one-time overview. Call on
-- the game thread, periodically: item types load on demand.
function AutoPickup.apply(categories, enabled, debugLog, needKinds)
    local anyEnabled = false
    for index = 1, #categories do anyEnabled = anyEnabled or enabled[index] end
    if not anyEnabled and not needKinds and next(changed) == nil then
        return
    end
    local itemDescriptions = {}
    for _, itemDescription in ipairs(FindAllOf(ITEM_DESCRIPTION_CLASS) or {}) do
        if itemDescription:IsValid() then
            itemDescriptions[#itemDescriptions + 1] = itemDescription
        end
    end
    local signature = #itemDescriptions .. ":" .. table.concat((function()
        local flags = {}
        for index = 1, #categories do flags[index] = enabled[index] and "1" or "0" end
        return flags
    end)())
    signature = signature .. (needKinds and ":kinds" or "")
    if signature == lastSignature then
        return
    end
    lastSignature = signature
    if debugLog ~= nil and anyEnabled and not overviewWritten then
        overviewWritten = true
        writeOverview(itemDescriptions, categories, debugLog)
    end
    for _, itemDescription in ipairs(itemDescriptions) do
        local address = itemDescription:GetAddress()
        local entry = changed[address]
        if entry ~= nil and not enabled[entry.category] then
            itemDescription[FLAG] = entry.original
            changed[address] = nil
        elseif entry == nil then
            local category = categoryByAddress[address]
            if category == nil then
                category = AutoPickup.categoryOf(categories, searchTextOf(itemDescription)) or false
                categoryByAddress[address] = category
                local objectName = itemDescription:GetFullName():match("%.([^%.]+)$")
                if objectName ~= nil then
                    AutoPickup.kindByName[objectName] = category
                end
            end
            if category and enabled[category] and not itemDescription[FLAG] then
                changed[address] = { original = itemDescription[FLAG], category = category }
                itemDescription[FLAG] = true
            end
        end
    end
end

return AutoPickup
