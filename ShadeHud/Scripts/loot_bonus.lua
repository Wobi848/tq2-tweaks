-- Extra loot: raises the number of items a drop list drops.
-- Technique from the Nexus mod "Loot Plus" (Titan Quest II).
local LootBonus = {}

-- A count of -1 means "as many as the drop list itself decides"; that cannot be raised, so the list is dropped
-- a second time with the bonus count afterwards.
local USE_LIST_DEFAULT = -1

-- getExtra() returns the extra count chosen in the menu. Returns { before, after } for DropHooks.
function LootBonus.handler(getExtra)
    local launchingExtra = false
    return {
        before = function(drop)
            local extra = getExtra()
            if launchingExtra or extra == 0 then
                return
            end
            local amount = drop.numToDrop:get()
            if amount ~= nil and amount > 0 then
                drop.numToDrop:set(amount + extra)
            end
        end,
        after = function(drop)
            local extra = getExtra()
            if launchingExtra or extra == 0 or drop.numToDrop:get() ~= USE_LIST_DEFAULT then
                return
            end
            launchingExtra = true
            local ok, err = pcall(drop.launchAgain, extra)
            launchingExtra = false
            if not ok then
                error(err)
            end
        end,
    }
end

return LootBonus
