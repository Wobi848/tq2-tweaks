-- Points per level up (attribute, active, passive and mastery points) via the game settings.
-- Technique from the Nexus mod "Points" (Titan Quest II). Applies to future level ups.
local LevelPoints = {}

local GAMEPLAY_SETTINGS = "/Script/TQ2Gameplay.Default__TQ2GameplaySettings"

-- Menu setting -> field in TQ2GameplaySettings.
LevelPoints.FIELDS = {
    AttributePointsPerLevel = "m_APperLevel",
    ActivePointsPerLevel = "m_ActivePointsPerLevel",
    PassivePointsPerLevel = "m_PassivePointsPerLevel",
    MasteryPointsPerLevel = "m_MasteryPointPerLevel",
}

-- values: menu setting -> count. Writes only what differs. Call on the game thread.
function LevelPoints.apply(values)
    local gameplaySettings = StaticFindObject(GAMEPLAY_SETTINGS)
    if gameplaySettings == nil or not gameplaySettings:IsValid() then
        error(GAMEPLAY_SETTINGS .. " not found")
    end
    for key, field in pairs(LevelPoints.FIELDS) do
        if gameplaySettings[field] ~= values[key] then
            gameplaySettings[field] = values[key]
        end
    end
end

return LevelPoints
