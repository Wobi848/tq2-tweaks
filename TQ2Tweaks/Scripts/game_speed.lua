-- Game speed via the engine's global time dilation: everything, including enemies, runs faster.
local Player = require("player")
local UI = require("ui")

local GameSpeed = {}

local GAMEPLAY_STATICS = "/Script/Engine.Default__GameplayStatics"

local lastApplied = 1

-- Re-applied periodically because a level load resets the dilation. At x1 it is only written once, when
-- switching back, so the game's own short slow-motion effects are left alone. Call on the game thread.
function GameSpeed.apply(factor)
    if factor == 1 and lastApplied == 1 then
        return
    end
    local controller = Player.controller()
    local statics = StaticFindObject(GAMEPLAY_STATICS)
    if not UI.isUsable(controller) or not UI.isUsable(statics) then
        return
    end
    statics:SetGlobalTimeDilation(controller, factor)
    lastApplied = factor
end

return GameSpeed
