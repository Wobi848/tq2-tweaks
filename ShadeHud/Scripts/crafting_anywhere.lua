-- Opens the blacksmith (anvil) window anywhere with a key.
-- Technique from the Nexus mod "CraftnStash" (Titan Quest II), own implementation: the player character becomes its
-- own crafting provider (it gets a TQ2CraftingComponent if it has none), is set as its own crafting access and the
-- crafting UI is opened for it. When the window closes (key again or Escape) the access is cleared again.
local Player = require("player")
local UI = require("ui")

local CraftingAnywhere = {}

local CRAFTING_COMPONENT_CLASS = "/Script/TQ2Gameplay.TQ2CraftingComponent"
local UI_CLOSED = "/Script/TQ2Gameplay.TQ2PlayerCharacter:OnCraftingUIClosed"

local opened = false
local closeHookRegistered = false

-- The actor's crafting component, if it is complete (component and its inventory exist).
local function craftingComponentOf(actor)
    if not UI.isUsable(actor) then
        return nil
    end
    local component = actor.m_pCraftingComponent
    if UI.isUsable(component) and UI.isUsable(component.m_pInventory) then
        return component
    end
    return nil
end

local function addCraftingComponent(character)
    local componentClass = StaticFindObject(CRAFTING_COMPONENT_CLASS)
    if not UI.isUsable(componentClass) then
        error(CRAFTING_COMPONENT_CLASS .. " not found")
    end
    local transform = character.RootComponent:GetRelativeTransform()
    local component = character:AddComponentByClass(componentClass, false, transform, false)
    if not UI.isUsable(component) then
        error("could not add a crafting component to the player")
    end
    character.m_pCraftingComponent = component
    component:SetIsReplicated(true)
    component:Activate(false)
    character:ForceNetUpdate()
end

-- The actor that provides crafting: the current access if it can craft, otherwise the player itself.
local function craftingProvider(character)
    local access = character:GetCraftingAccess()
    if craftingComponentOf(access) then
        return access
    end
    if not craftingComponentOf(character) then
        addCraftingComponent(character)
    end
    if not craftingComponentOf(character) then
        error("player has no usable crafting component")
    end
    return character
end

local function clearAccess(character)
    opened = false
    character:SetCraftingAccess(nil)
    character:ForceNetUpdate()
end

-- When the window is closed with Escape the game calls OnCraftingUIClosed itself; clear our access then too.
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
    local provider = craftingProvider(character)
    if UI.isUsable(playerState) then
        playerState:TryClearCraftingCache()
    end
    character:SetCraftingAccess(provider)
    character:ForceNetUpdate()
    if UI.isUsable(playerState) then
        playerState:GetOrCreateCraftingCacheViewModel()
    end
    registerCloseHook()
    opened = true
    character:OnCraftingUIOpened(provider)
end

-- Opens the anvil window, or closes it if this mod opened it. Call on the game thread.
function CraftingAnywhere.toggle()
    local character = Player.character()
    if not UI.isUsable(character) then
        return
    end
    if opened then
        character:OnCraftingUIClosed()
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

return CraftingAnywhere
