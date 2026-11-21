-- Blocks character movement while the menu is open so the arrow keys only operate the menu.
-- SetIgnoreMoveInput counts internally (true = +1, false = -1), so lock exactly once and unlock exactly once.
local Player = require("player")
local UI = require("ui")

local MovementLock = {}

local lockedController = nil

-- Call on the game thread: matches the lock to the menu state.
function MovementLock.sync(menuOpen)
    if menuOpen and lockedController == nil then
        local controller = Player.controller()
        if UI.isUsable(controller) then
            controller:SetIgnoreMoveInput(true)
            lockedController = controller
        end
    elseif not menuOpen and lockedController ~= nil then
        -- After a level change the old controller is gone, and so is its lock.
        if UI.isUsable(lockedController) then
            lockedController:SetIgnoreMoveInput(false)
        end
        lockedController = nil
    end
end

return MovementLock
