-- XP multiplier: hooks the point where the game grants experience and multiplies the amount.
-- Technique from the Nexus mod "Exp Plus" (Titan Quest II).
local XpMultiplier = {}

local GRANT_PROGRESS = "/Script/TQ2Gameplay.TQ2AttributeSetProgression:Server_GrantLevelProgress"

-- getFactor() returns the factor currently chosen in the menu; changes apply immediately.
function XpMultiplier.register(getFactor)
    RegisterHook(GRANT_PROGRESS, function(_, progress, override)
        local factor = getFactor()
        -- Override = the game sets the progress outright (e.g. when loading); that is not new experience.
        if factor == 1 or override:get() then
            return
        end
        local amount = progress:get()
        if amount ~= nil and amount > 0 then
            progress:set(amount * factor)
        end
    end)
end

return XpMultiplier
