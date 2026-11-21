-- The local player's controller and character. UEHelpers looks the controller up with FindAllOf on every call; the
-- loops ask several times per second, so the controller is kept while it is valid and only searched again after it
-- is gone (level change) or when forget() is called.
local UEHelpers = require("UEHelpers")

local Player = {}

local cachedController = nil

function Player.controller()
    if cachedController ~= nil and cachedController:IsValid() then
        return cachedController
    end
    local controller = UEHelpers.GetPlayerController()
    cachedController = controller:IsValid() and controller or nil
    return controller
end

-- The controlled character (Pawn), or an invalid object like UEHelpers.GetPlayer returns.
function Player.character()
    local controller = Player.controller()
    if controller:IsValid() and controller.Pawn then
        return controller.Pawn
    end
    return UEHelpers.GetPlayer()
end

-- Drops the kept controller (before a level change).
function Player.forget()
    cachedController = nil
end

return Player
