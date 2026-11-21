-- One shared hook on LaunchDropList (the game drops a drop list: enemies, chests ...).
-- Gold and loot modules register before/after handlers here instead of hooking the function twice.
local DropHooks = {}

local LAUNCH_DROP_LIST = "/Script/GrimVentory.GrimWorldItemReplicationHelper:LaunchDropList"

-- Gives handlers lazy access to the hook parameters: nothing is read from the engine unless a handler that is
-- actually active asks for it, so with gold and loot switched off the hook does no engine work at all.
local function newDrop(context, dropList, tags, customData, origin, numToDrop, launchParams)
    return {
        numToDrop = numToDrop,
        source = function() return customData:get() end,
        -- Drops the same list again with another count (used for extra loot).
        launchAgain = function(count)
            context:get():LaunchDropList(dropList:get(), tags:get(), customData:get(), origin:get(), count,
                launchParams:get())
        end,
    }
end

-- handlers: list of { before = function(drop), after = function(drop) } (both optional).
-- Errors of one module are logged and do not affect the others or the game.
function DropHooks.register(handlers, logError)
    local function run(phase, ...)
        local drop = newDrop(...)
        for _, handler in ipairs(handlers) do
            if handler[phase] then
                local ok, err = pcall(handler[phase], drop)
                if not ok then
                    logError("Drop error (" .. phase .. "): " .. tostring(err))
                end
            end
        end
    end
    RegisterHook(LAUNCH_DROP_LIST,
        function(...) run("before", ...) end,
        function(...) run("after", ...) end)
end

return DropHooks
