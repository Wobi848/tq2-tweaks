-- Gear dump (written together with the affix dump, F9): the player's equipped items and the items in the player's
-- inventories (bags, stash) with type, rarity, item level and every affix with its tier (Level) and roll quality
-- (the scales of its effects), as JSON in the mod folder. Groundwork for upgrade advice. Only reads.
local GameObject = require("game_object")
local JsonText = require("json_text")
local TextFile = require("text_file")

local GearDump = {}

local INVENTORY_CLASS = "TQ2Inventory"
-- How far up the outer chain an inventory may hang below the player state (it may sit in a component).
local MAX_OUTER_DEPTH = 4
local AFFIX_CATEGORIES = { [0] = "base", [1] = "implicit", [2] = "random" }

local readOr = GameObject.read
local listOf = GameObject.listOf
local nameOf = GameObject.shortName
local usable = GameObject.usable

local function describeAffix(affixInstance)
    local scales = {}
    for _, effect in ipairs(readOr(function() return listOf(affixInstance.AffixEffectInstances) end) or {}) do
        scales[#scales + 1] = readOr(function() return effect.Scale end)
    end
    return {
        name = readOr(function() return nameOf(affixInstance.pAffix) end),
        tier = readOr(function() return affixInstance.Level end),
        category = AFFIX_CATEGORIES[readOr(function() return affixInstance.Category end)],
        scales = #scales > 0 and scales or nil,
        multiplier = readOr(function() return affixInstance.EffectScaleMultiplier end),
    }
end

-- One item instance (UGrimItemInstance) as plain data.
function GearDump.describeItem(instance)
    local affixes = {}
    for _, affixInstance in ipairs(readOr(function() return listOf(instance.m_Affixes) end) or {}) do
        affixes[#affixes + 1] = describeAffix(affixInstance)
    end
    return {
        type = readOr(function() return nameOf(instance.m_pDescription.HardReference) end),
        rarity = readOr(function() return instance.m_Rarity end),
        level = readOr(function() return instance.m_Level end),
        customName = readOr(function() local name = instance.m_CustomName:ToString() return name ~= "" and name or nil end),
        affixes = affixes,
    }
end

-- Items of a container (equipment or inventory) with their slot index; empty slots are left out.
function GearDump.containerItems(container)
    local items = {}
    for index, slot in ipairs(readOr(function() return listOf(container.m_ContainerData.ItemSlots) end) or {}) do
        local instance = readOr(function() return slot.ItemHandle.pItem end)
        if usable(instance) then
            local item = GearDump.describeItem(instance)
            item.slot = index
            item.count = readOr(function() return slot.Num end)
            items[#items + 1] = item
        end
    end
    return items
end

-- Equipment and the player's inventories, each { name, items }.
function GearDump.collect(playerState)
    local result = { equipment = {}, inventories = {} }
    local equipment = readOr(function() return playerState.m_pEquipmentContainer end)
    if usable(equipment) then
        result.equipment = GearDump.containerItems(equipment)
    end
    for _, inventory in ipairs(FindAllOf(INVENTORY_CLASS) or {}) do
        if usable(inventory) and GameObject.isBelow(inventory, playerState:GetAddress(), MAX_OUTER_DEPTH) then
            result.inventories[#result.inventories + 1] = { name = nameOf(inventory),
                                                            items = GearDump.containerItems(inventory) }
        end
    end
    return result
end

-- Writes the gear of the player behind `playerState` to `path` and logs a summary. Call on the game thread.
function GearDump.write(path, playerState, log)
    if not usable(playerState) then
        log("Gear dump: no player")
        return
    end
    local gear = GearDump.collect(playerState)
    local ok, reason = TextFile.write(path, JsonText.encode(gear) .. "\n")
    if not ok then
        log("Gear dump not written: " .. reason)
        return
    end
    local carried = 0
    for _, inventory in ipairs(gear.inventories) do
        carried = carried + #inventory.items
    end
    log(string.format("Gear written to %s: %d equipped, %d in %d inventories", path, #gear.equipment, carried,
        #gear.inventories))
end

return GearDump
