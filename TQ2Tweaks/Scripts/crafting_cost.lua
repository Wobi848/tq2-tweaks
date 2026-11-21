-- Free crafting via the per-item cost override built into the game, active only while the anvil window is open.
--
-- Every UTQ2ItemDescription has m_CraftingCostsToOverride (one bit per crafting action) and
-- m_OverriddenCraftingCostByAction[4] (the replacement cost per action). The costs are formulas
-- (FGrimDynamicsFormula: SourceText compiled into hidden data), so writing numbers has no effect; ImportText
-- re-parses the text, like the Nexus mod "Loot Plus" does for rarity weights.
--
-- Earlier this ran every few seconds during play and left the override switched on all the time; with it on,
-- the game froze or crashed in fights, with it off the game ran stable. Now:
-- - the replacement cost ("gold 0, no resources") is imported once per item type, when the anvil opens;
-- - only while the anvil window is open the override bits are switched on, and on closing they are restored.
-- Item types that already have an override of their own are left alone (their cost text cannot be read back).
local CraftingCost = {}

local ITEM_DESCRIPTION_CLASS = "TQ2ItemDescription"
local OVERRIDE_MASK = "m_CraftingCostsToOverride"
local OVERRIDE_COSTS = "m_OverriddenCraftingCostByAction"
-- ETQ2ItemCraftingAction: RaiseLevel, ExchangeAffix, RerollAffix, AddAffix.
local ACTION_COUNT = 4
local ALL_ACTIONS_MASK = 0x0F
local FREE_COST_TEXT = '(Gold=(Parameters=,UseGameplayTagParameters=True,SourceText="0"),Resources=())'
local PORT_FLAGS_NONE = 0

-- "full name@address" of the item type objects whose override slots already hold the free cost. Both parts: an
-- address can be reused by another type after unloading, and a reloaded type has its original slots again.
local imported = {}
-- Item description address -> description, for every type switched to free while the anvil is open.
local switchedOn = {}

local function importFreeCost(itemDescription)
    local costsProperty = itemDescription:Reflection():GetProperty(OVERRIDE_COSTS)
    for action = 0, ACTION_COUNT - 1 do
        local data = costsProperty:ContainerPtrToValuePtr(itemDescription, action)
        costsProperty:ImportText(FREE_COST_TEXT, data, PORT_FLAGS_NONE, itemDescription)
    end
end

-- Call on the game thread when the anvil window has opened.
function CraftingCost.onAnvilOpened(log)
    local newlyImported, ownOverride, switched = 0, 0, 0
    for _, itemDescription in ipairs(FindAllOf(ITEM_DESCRIPTION_CLASS) or {}) do
        if itemDescription:IsValid() then
            local address = itemDescription:GetAddress()
            if itemDescription[OVERRIDE_MASK] ~= 0 and switchedOn[address] == nil then
                ownOverride = ownOverride + 1
            elseif switchedOn[address] == nil then
                local key = itemDescription:GetFullName() .. "@" .. tostring(address)
                if not imported[key] then
                    importFreeCost(itemDescription)
                    imported[key] = true
                    newlyImported = newlyImported + 1
                end
                itemDescription[OVERRIDE_MASK] = ALL_ACTIONS_MASK
                switchedOn[address] = itemDescription
                switched = switched + 1
            end
        end
    end
    log(string.format("Free crafting on: %d item types (%d newly prepared, %d with own override left alone)",
        switched, newlyImported, ownOverride))
end

-- Call on the game thread when the anvil window has closed: every type returns to its normal cost.
function CraftingCost.onAnvilClosed(log)
    local restored = 0
    for _, itemDescription in pairs(switchedOn) do
        if itemDescription:IsValid() then
            itemDescription[OVERRIDE_MASK] = 0
            restored = restored + 1
        end
    end
    switchedOn = {}
    if restored > 0 then
        log(string.format("Free crafting off: %d item types back to normal cost", restored))
    end
end

return CraftingCost
