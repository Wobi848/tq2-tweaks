-- Reads the shade values from the view model that the game's own display uses.
local ShadeState = {}

local VIEW_MODEL_CLASS = "TQ2PlayerCharacterViewModel"

local cachedViewModel = nil

-- Drops the cached view model (before a level change).
function ShadeState.forget()
    cachedViewModel = nil
end

local function isUsable(object)
    return object ~= nil and object:IsValid()
end

-- There can be several view models (character selection, other players). Take the first one whose
-- character has shades at all, i.e. the Spirit mastery.
local function findViewModel()
    if isUsable(cachedViewModel) and cachedViewModel:GetMaximumShades() > 0 then
        return cachedViewModel
    end
    cachedViewModel = nil
    local candidates = FindAllOf(VIEW_MODEL_CLASS)
    if candidates == nil then
        return nil
    end
    for _, viewModel in ipairs(candidates) do
        if isUsable(viewModel) and viewModel:GetMaximumShades() > 0 then
            cachedViewModel = viewModel
            return viewModel
        end
    end
    return nil
end

-- Progress (0..1) to the next shade. The regen effect view model reports the remaining duration
-- normalized (1 = just started, 0 = about to finish).
local function readRegenProgress(viewModel)
    local regenEffect = viewModel:GetShadeRegenEffectViewModel()
    if not isUsable(regenEffect) then
        return 0
    end
    local remaining = regenEffect:GetRemainingDurationNormalized()
    return math.max(0, math.min(1, 1 - remaining))
end

-- Returns { current, maximum, progress }, or nil if no Spirit character is active.
function ShadeState.read()
    local viewModel = findViewModel()
    if viewModel == nil then
        return nil
    end
    local maximum = math.floor(viewModel:GetMaximumShades() + 0.5)
    local current = math.floor(viewModel:GetCurrentShades() + 0.001)
    local progress = 0
    if current < maximum then
        progress = readRegenProgress(viewModel)
    end
    return { current = current, maximum = maximum, progress = progress }
end

return ShadeState
