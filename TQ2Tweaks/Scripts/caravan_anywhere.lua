-- Opens the caravan (the shared stash) anywhere with a key.
-- Technique from the Nexus mod "CraftnStash" (Titan Quest II), own implementation: the caravan view model is prepared,
-- the player (or the caravan it already has access to) is set as caravan access and the caravan window is opened for
-- it. When the window closes (key again or Escape) the access is cleared again.
local Player = require("player")
local UI = require("ui")

local CaravanAnywhere = {}

local UI_CLOSED = "/Script/TQ2Gameplay.TQ2PlayerCharacter:OnCaravanInventoryClosed"

local opened = false
local closeHookRegistered = false

local function clearAccess(character)
    opened = false
    character:SetCaravanAccess(nil)
    character:ForceNetUpdate()
end

-- When the window is closed with Escape the game calls OnCaravanInventoryClosed itself; clear our access then too.
local function registerCloseHook()
    if closeHookRegistered then
        return
    end
    closeHookRegistered = true
    RegisterHook(UI_CLOSED, function() end, function(context)
        local character = context:get()
        if opened and UI.isUsable(character) then
            clearAccess(character)
        end
    end)
end

local function open(character)
    local playerState = character.PlayerState
    if UI.isUsable(playerState) then
        playerState:GetOrCreateCaravanViewModel()
    end
    local access = character:GetCaravanAccess()
    if not UI.isUsable(access) then
        access = character
    end
    character:SetCaravanAccess(access)
    character:ForceNetUpdate()
    registerCloseHook()
    opened = true
    character:OnCaravanInventoryOpened(access)
end

-- Opens the caravan window, or closes it if this mod opened it. Call on the game thread.
function CaravanAnywhere.toggle()
    local character = Player.character()
    if not UI.isUsable(character) then
        return
    end
    if opened then
        character:OnCaravanInventoryClosed()
        if opened then
            clearAccess(character)
        end
        return
    end
    local ok, err = pcall(open, character)
    if not ok then
        clearAccess(character)
        error(err)
    end
end

return CaravanAnywhere
