-- Gold multiplier: multiplies gold piles dropped by enemies.
-- Technique from the Nexus mod "Gold" (Titan Quest II).
--
-- Only piles created shortly after an enemy dropped its drop list are changed, so gold that reappears when a
-- level loads is not multiplied again. "Shortly after" and not "during": the game queues dropped items
-- (UGrimVentoryWorldSubsystem.m_PendingItemSpawns) and spawns them after LaunchDropList has returned.
local WorldItems = require("world_items")
local GameObject = require("game_object")

local GoldMultiplier = {}

local ENEMY_CLASS = "/Script/TQ2Gameplay.TQ2AICharacter"
local GOLD_ITEM_NAME = "da_item_gold_WorldItem"
-- The amount is filled in shortly after the pile is created; check again at this interval.
local RETRY_DELAY_MS = 5
local MAX_ATTEMPTS = 50
-- Seconds after an enemy drop during which new gold piles count as part of it.
local ENEMY_DROP_WINDOW_SECONDS = 2

-- The slot structs of the pile.
local function slotsOf(item)
    return GameObject.listOf(item.m_ContainerData.ItemSlots)
end

local function isEnemy(source)
    return source ~= nil and source:IsValid() and source:IsA(ENEMY_CLASS)
end

-- Multiplies the amount in the first filled slot of the pile. Returns "applied" or "not applied" if a slot was
-- written, nil while the pile is still empty.
-- Only the Num field is written, in place. Writing the whole slot back with element:set(slot) (as the reference
-- mod does) copies a struct that holds references onto itself; two game crashes happened with that version.
local function multiplySlots(item, factor)
    for index, slot in ipairs(slotsOf(item)) do
        if slot.Num ~= nil and slot.Num > 0 then
            local before = slot.Num
            local target = math.floor(before * factor)
            slot.Num = target
            -- Read back from the item: confirms the in-place write reached the game's memory.
            if slotsOf(item)[index].Num ~= target then
                return string.format("not applied (%d -> %d)", before, target)
            end
            return "applied"
        end
    end
    return nil
end

-- Runs on the game thread directly (no async thread in between) and gives up if the pile is gone.
local function multiplyPile(item, factor, attempt, log)
    ExecuteInGameThreadWithDelay(RETRY_DELAY_MS, function()
        if not item:IsValid() then
            return
        end
        local ok, result = pcall(multiplySlots, item, factor)
        if not ok then
            log("Gold error: " .. tostring(result))
        elseif result == "applied" then
            item:OnUpdateWorldRepresentation()
        elseif result ~= nil then
            log("Gold error: pile " .. result)
        elseif attempt < MAX_ATTEMPTS then
            multiplyPile(item, factor, attempt + 1, log)
        end
    end)
end

-- getFactor() returns the factor chosen in the menu, now() the time in seconds; log should log repeated lines
-- only once. Returns { before } for DropHooks.
function GoldMultiplier.handler(getFactor, log, now)
    local lastEnemyDropAt = nil

    WorldItems.subscribe(function(item)
        local factor = getFactor()
        if factor == 1 then
            return
        end
        if not item:GetFullName():find(GOLD_ITEM_NAME, 1, true) then
            return
        end
        if lastEnemyDropAt == nil or now() - lastEnemyDropAt > ENEMY_DROP_WINDOW_SECONDS then
            return
        end
        multiplyPile(item, factor, 1, log)
    end, log)

    return {
        before = function(drop)
            if getFactor() == 1 then
                return
            end
            if isEnemy(drop.source()) then
                lastEnemyDropAt = now()
            end
        end,
    }
end

return GoldMultiplier
