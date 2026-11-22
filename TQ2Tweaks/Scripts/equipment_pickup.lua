-- Auto pickup of equipment by rarity and by loot filter rules (loot_rules.lua).
--
-- The game's hoover picks up by item *type* (m_CanAutoPickup), but rarity belongs to the single item
-- (UGrimItemInstance.m_Rarity). So equipment is picked up here instead: new ground items are remembered, and every
-- pass the ones of high enough rarity within hoover range are picked up with AGrimWorldItem:Pickup(player, false).
-- Each item is tried once; if it is still there afterwards (inventory full) it is dropped from the list.
local LootRules = require("loot_rules")
local GameObject = require("game_object")

local EquipmentPickup = {}

-- Remembered ground items are capped so the list cannot grow without bound; the oldest are dropped first.
local MAX_TRACKED = 300
local HOOVER_CLASS = "GrimItemHooverComponent"
-- EGrimItemAffixCategory: 0 base, 1 implicit, 2 random (the ones crafting can replace).
local RANDOM_AFFIX_CATEGORY = 2

-- New ground item (call from the shared NotifyOnNewObject callback for TQ2WorldItem).
-- now: time of the drop (seconds), see judgeDelay in newState.
function EquipmentPickup.remember(state, item, now)
    state.items[#state.items + 1] = { item = item, tried = false, droppedAt = now or 0 }
    if #state.items > MAX_TRACKED then
        table.remove(state.items, 1)
    end
end

-- judgeDelay: seconds a new ground item lies before it is judged. The game fills some item data in after the drop
-- (UGrimItemInstance has an OnPayloadDataLoaded event); reading it right away was suspected in crashes during big
-- fights (21.11.), so the mod waits until the item has settled. 0 = judge at once.
function EquipmentPickup.newState(judgeDelay)
    return { items = {}, rangeCharacter = nil, range = nil, judgeDelay = judgeDelay or 0 }
end

-- Forgets the remembered ground items and the cached range (pickup off, or before a level change).
function EquipmentPickup.clear(state)
    state.items, state.rangeCharacter, state.range = {}, nil, nil
end

-- Pickup range of the game's own hoover for this player (the gold pickup range), cached per character; the
-- fallback is used while no hoover component of the player is found.
function EquipmentPickup.hooverRange(state, character, fallback)
    if state.rangeCharacter == character:GetAddress() and state.range ~= nil then
        return state.range
    end
    local playerState = character.PlayerState
    if playerState == nil or not playerState:IsValid() then
        return fallback
    end
    for _, hoover in ipairs(FindAllOf(HOOVER_CLASS) or {}) do
        local owner = hoover:IsValid() and hoover.m_pOwningPlayer
        if owner and owner:IsValid() and owner:GetAddress() == playerState:GetAddress() then
            state.rangeCharacter, state.range = character:GetAddress(), hoover.m_Range
            return state.range
        end
    end
    return fallback
end

-- Item instance (UGrimItemInstance) of the item on the ground, or nil while its content is not filled in yet. Read
-- from the slot array the same way the gold multiplier reads the pile amount.
function EquipmentPickup.instanceOf(item)
    for _, slot in ipairs(GameObject.listOf(item.m_ContainerData.ItemSlots)) do
        local instance = slot.ItemHandle.pItem
        if instance ~= nil and instance:IsValid() then
            return instance
        end
    end
    return nil
end

-- Affixes of an item instance as { name = affix asset name, level, random = rolled (not base/implicit) }, e.g.
-- "da_prefix_1_Summons_PerIncreasedDamage_All".
function EquipmentPickup.affixesOf(instance)
    local affixes = {}
    for _, affixInstance in ipairs(GameObject.listOf(instance.m_Affixes)) do
        local affix = affixInstance.pAffix
        if affix ~= nil and affix:IsValid() then
            affixes[#affixes + 1] = { name = GameObject.shortName(affix) or "", level = affixInstance.Level,
                                      random = affixInstance.Category == RANDOM_AFFIX_CATEGORY }
        end
    end
    return affixes
end

-- The items the player wears, as { typeName, rarity, affixes, maxAffixes } for LootRules (only upgrades).
function EquipmentPickup.wornItems(character, affixPlaces)
    local equipment = GameObject.read(function() return character.PlayerState.m_pEquipmentContainer end)
    if not GameObject.usable(equipment) then
        return {}
    end
    local worn = {}
    for _, slot in ipairs(GameObject.listOf(equipment.m_ContainerData.ItemSlots)) do
        local instance = slot.ItemHandle.pItem
        local description = GameObject.usable(instance)
            and GameObject.read(function() return instance.m_pDescription.HardReference end)
        if GameObject.usable(description) then
            worn[#worn + 1] = { typeName = GameObject.shortName(description) or "", rarity = instance.m_Rarity,
                                affixes = EquipmentPickup.affixesOf(instance),
                                maxAffixes = affixPlaces and affixPlaces[instance.m_Rarity] }
        end
    end
    return worn
end

-- Whether the ground item passes the rule (see pass).
local function wanted(item, instance, rule)
    if rule.minRarity ~= nil and instance.m_Rarity >= rule.minRarity then
        return true
    end
    if rule.lootRules == nil then
        return false
    end
    return LootRules.matchesAny(rule.lootRules, { rarity = instance.m_Rarity,
        typeName = EquipmentPickup.typeNameOf(item),
        readAffixes = function() return EquipmentPickup.affixesOf(instance) end,
        maxAffixes = rule.affixPlaces and rule.affixPlaces[instance.m_Rarity],
        readWorn = rule.readWorn })
end

-- true/false once the item can be judged, "later" while its content or type is not known yet.
local function decide(item, rule, isEquipment)
    local instance = EquipmentPickup.instanceOf(item)
    local equipment = isEquipment(EquipmentPickup.typeNameOf(item))
    if instance == nil or equipment == nil then
        return "later"
    end
    return equipment and wanted(item, instance, rule)
end

-- Item type name of a ground item: ground items are named "<type>_WorldItem[_<n>]".
function EquipmentPickup.typeNameOf(item)
    return ((GameObject.shortName(item) or ""):gsub("_WorldItem.*$", ""))
end

local function distance(a, b)
    local dx, dy, dz = a.X - b.X, a.Y - b.Y, a.Z - b.Z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- One pass. isEquipment(typeName) says whether the type is equipment, or nil while the type is not known yet (item
-- types are scanned every few seconds; the first item of a newly loaded type waits for the next scan instead of
-- being dropped). rule = { minRarity = lowest rarity or nil, lootRules = rules from LootRules.load or nil,
-- affixPlaces = { [rarity] = random affixes it allows } for crafting-aware rules, upgradesOnly = loot rules with
-- affixes only take items that beat the worn one }: equipment is picked up if it reaches minRarity or matches one of
-- the loot rules; minRarity and lootRules nil = off. Call on the game thread.
function EquipmentPickup.pass(state, character, range, rule, isEquipment, now)
    if rule.minRarity == nil and rule.lootRules == nil then
        state.items = {}
        return 0
    end
    if rule.upgradesOnly then
        -- The worn items are read at most once per pass, and only when an item is judged by an affix rule.
        local worn = nil
        rule.readWorn = function()
            worn = worn or EquipmentPickup.wornItems(character, rule.affixPlaces)
            return worn
        end
    end
    local here = character:K2_GetActorLocation()
    local kept, pickedUp = {}, 0
    for _, entry in ipairs(state.items) do
        local item = entry.item
        if item:IsValid() and not entry.tried then
            -- The decision is made once per item; afterwards only its distance is checked each pass.
            if entry.wanted == nil then
                local settled = now == nil or now - entry.droppedAt >= state.judgeDelay
                entry.wanted = settled and decide(item, rule, isEquipment) or "later"
            end
            if entry.wanted == "later" then
                entry.wanted = nil
                kept[#kept + 1] = entry
            elseif entry.wanted then
                if distance(item:K2_GetActorLocation(), here) <= range then
                    entry.tried = true
                    item:Pickup(character, false)
                    pickedUp = pickedUp + 1
                end
                kept[#kept + 1] = entry
            end
        end
    end
    state.items = kept
    return pickedUp
end

return EquipmentPickup
