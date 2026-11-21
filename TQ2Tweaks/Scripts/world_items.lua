-- One shared notification for new ground items (TQ2WorldItem): gold multiplier and equipment pickup subscribe here
-- instead of each registering NotifyOnNewObject themselves (like drop_hooks.lua for LaunchDropList).
local WorldItems = {}

local WORLD_ITEM_CLASS = "/Script/TQ2Gameplay.TQ2WorldItem"

local subscribers = {}
local registered = false

-- callback(item) is called for every new ground item. Errors of one subscriber are logged and do not affect the
-- others. The engine notification is registered with the first subscriber.
function WorldItems.subscribe(callback, logError)
    subscribers[#subscribers + 1] = callback
    if registered then
        return
    end
    registered = true
    NotifyOnNewObject(WORLD_ITEM_CLASS, function(item)
        for _, subscriber in ipairs(subscribers) do
            local ok, err = pcall(subscriber, item)
            if not ok then
                logError("World item error: " .. tostring(err))
            end
        end
    end)
end

return WorldItems
