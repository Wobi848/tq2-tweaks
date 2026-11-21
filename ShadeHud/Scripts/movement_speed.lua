-- Movement speed multiplier.
--
-- In game the walking speed follows MoveSpeedFactor, a GAS attribute in the player's GrimAttributeSetMovement
-- (logged: velocity 629 = 500 x 1.26). Neither CharacterMovement.MaxWalkSpeed (set to 1260, still 629) nor
-- ATQ2Character.m_CustomMoveSpeedMultiplier change the speed, so only the attribute is scaled.
--
-- The game rewrites the attribute itself (buffs, slows, level loads). We remember what we wrote; if the current
-- value differs, the game has recalculated and that value is the new "natural" one. At x1 it is written back.
local Player = require("player")
local UI = require("ui")

local MovementSpeed = {}

local MOVEMENT_SET_CLASS = "GrimAttributeSetMovement"
local TOLERANCE = 1e-4
-- How many outers up the chain an attribute set may sit below its owning actor (set -> component -> actor).
local MAX_OUTER_DEPTH = 4

-- Seconds between searches while the player's movement set is not found (searching scans all characters).
local SEARCH_INTERVAL_SECONDS = 5

local state = { character = nil, movementSet = nil, attribute = {}, searchedAt = nil, reportedMissing = false }

-- Drops the cached character and movement set with their tracked values (before a level change); the next apply()
-- searches again.
function MovementSpeed.forget()
    state.character, state.movementSet, state.attribute, state.searchedAt = nil, nil, {}, nil
end

-- Scales one value by factor, keeping track of the game's own value (see header). Writes only on change.
local function applyScaled(tracker, read, write, factor)
    local current = read()
    if tracker.written == nil or math.abs(current - tracker.written) > TOLERANCE then
        tracker.natural = current
    end
    tracker.written = tracker.natural * factor
    if math.abs(current - tracker.written) > TOLERANCE then
        write(tracker.written)
    end
end

-- True if the player character or the player's PlayerState appears in the set's outer chain (the set may belong
-- to the actor directly or to its ability system component).
local function ownsSet(movementSet, owners)
    local outer = movementSet:GetOuter()
    for _ = 1, MAX_OUTER_DEPTH do
        if not UI.isUsable(outer) then
            return false
        end
        if owners[outer:GetAddress()] then
            return true
        end
        outer = outer:GetOuter()
    end
    return false
end

local function outerChain(object)
    local names = {}
    local outer = object:GetOuter()
    for _ = 1, MAX_OUTER_DEPTH do
        if not UI.isUsable(outer) then
            break
        end
        names[#names + 1] = outer:GetFullName()
        outer = outer:GetOuter()
    end
    return table.concat(names, " <- ")
end

-- The movement attribute set of the player. If none matches, logs where the first set actually hangs.
local function findMovementSet(character, log)
    local owners = { [character:GetAddress()] = true }
    local playerState = character.PlayerState
    if UI.isUsable(playerState) then
        owners[playerState:GetAddress()] = true
    end
    local movementSets = FindAllOf(MOVEMENT_SET_CLASS) or {}
    for _, movementSet in ipairs(movementSets) do
        if movementSet:IsValid() and ownsSet(movementSet, owners) then
            return movementSet
        end
    end
    if movementSets[1] ~= nil and not state.reportedMissing then
        state.reportedMissing = true
        log(string.format("Movement: no player movement set among %d; first one hangs at: %s | player: %s",
            #movementSets, outerChain(movementSets[1]), character:GetFullName()))
    end
    return nil
end

-- Call on the game thread. log reports a missing movement set; now (seconds) paces the search for it.
function MovementSpeed.apply(factor, log, now)
    -- Never switched on: leave the game completely alone.
    if factor == 1 and state.attribute.written == nil then
        return
    end
    local character = Player.character()
    if not UI.isUsable(character) then
        return
    end
    if state.character ~= character:GetAddress() then
        state = { character = character:GetAddress(), movementSet = nil, attribute = {}, searchedAt = nil,
                  reportedMissing = false }
    end
    if not UI.isUsable(state.movementSet)
        and (state.searchedAt == nil or now - state.searchedAt >= SEARCH_INTERVAL_SECONDS) then
        state.searchedAt = now
        state.movementSet = findMovementSet(character, log)
        state.attribute = {}
    end
    local movementSet = state.movementSet
    if UI.isUsable(movementSet) then
        applyScaled(state.attribute,
            function() return movementSet.MoveSpeedFactor.CurrentValue end,
            function(value) movementSet.MoveSpeedFactor.CurrentValue = value end,
            factor)
    end
end

return MovementSpeed
