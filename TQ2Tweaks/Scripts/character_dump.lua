-- Character dump (written with the gear dump, Shift+F9): the local player's level, attributes, masteries with their
-- skills (points, modifiers), passives (points, feats) and the equipped items, as JSON in the mod folder. The build
-- planner loads the file ("Load character"). Reads the game's own data (mastery component, attribute sets and the
-- attributes component's getters), not the UI view models. Only reads.
local GameObject = require("game_object")
local GearDump = require("gear_dump")
local JsonText = require("json_text")
local TextFile = require("text_file")

local CharacterDump = {}

local ATTRIBUTE_SET_CLASS = "TQ2CharacterAttributesSet"
local PROGRESSION_SET_CLASS = "TQ2AttributeSetProgression"
local ATTRIBUTES_COMPONENT_CLASS = "TQ2CharacterAttributesComponent"
-- How far up the outer chain an attribute set may hang below the player state or the character.
local MAX_OUTER_DEPTH = 3
local ATTRIBUTES = { might = "Might", agility = "Agility", knowledge = "Knowledge", vigor = "Vigor" }
-- The mastery component's point counters (from level and in total, including rewards); exported as they are.
local POINT_FIELDS = { activeFromLevel = "m_ActivePointsFromLevel", passiveFromLevel = "m_PassivePointsFromLevel",
                       masteryFromLevel = "m_MasteryPointsFromLevel", active = "m_ActivePoints",
                       passive = "m_PassivePoints", mastery = "m_MasteryPoints" }
-- Attributes the game derives from the four above; only their current values are read.
local DERIVED_ATTRIBUTES = { fitness = "Fitness", cunning = "Cunning", resolve = "Resolve" }

local readOr = GameObject.read
local listOf = GameObject.listOf
local usable = GameObject.usable

-- Asset or class name as the game data (mega dump) names it: "bp_gam_x_C" -> "bp_gam_x".
function CharacterDump.assetName(object)
    if not usable(object) then
        return nil
    end
    return (GameObject.shortName(object):gsub("_C$", ""))
end

local assetName = CharacterDump.assetName

local function describeSkill(instance)
    local modifiers = {}
    for _, slot in ipairs(readOr(function() return listOf(instance.ModifierSlots) end) or {}) do
        local id = readOr(function() return assetName(slot.ModifierClass) end)
        if id ~= nil then
            modifiers[#modifiers + 1] = { id = id, level = readOr(function() return slot.Level end) }
        end
    end
    return { id = readOr(function() return assetName(instance.pMasteryActiveAbilityDescription.pAbility) end),
             points = readOr(function() return instance.InvestedPoints end),
             modifiers = modifiers }
end

local function describePassive(instance)
    local feats = {}
    for _, feat in ipairs(readOr(function() return listOf(instance.FeatSlots) end) or {}) do
        feats[#feats + 1] = readOr(function() return assetName(feat) end)
    end
    return { id = readOr(function() return assetName(instance.pMasteryPassiveAbilityDescription.m_pPassiveAbility) end),
             points = readOr(function() return instance.InvestedPoints end),
             feats = feats }
end

-- One mastery instance (FTQ2MasteryInstance) as plain data; skills and passives without points are left out.
function CharacterDump.describeMastery(instance)
    local mastery = { id = readOr(function() return assetName(instance.pMasteryDescription.HardReference) end),
                      points = readOr(function() return instance.InvestedMasteryPoints end),
                      skills = {}, passives = {} }
    for _, skill in ipairs(readOr(function() return listOf(instance.ActiveAbilities) end) or {}) do
        local described = describeSkill(skill)
        if (described.points or 0) > 0 then
            mastery.skills[#mastery.skills + 1] = described
        end
    end
    for _, passive in ipairs(readOr(function() return listOf(instance.PassiveAbilities) end) or {}) do
        local described = describePassive(passive)
        if (described.points or 0) > 0 then
            mastery.passives[#mastery.passives + 1] = described
        end
    end
    return mastery
end

-- The first object of className that hangs below one of the owners (addresses), or nil.
local function ownedObject(className, owners)
    for _, object in ipairs(FindAllOf(className) or {}) do
        if usable(object) then
            for _, owner in ipairs(owners) do
                if GameObject.isBelow(object, owner, MAX_OUTER_DEPTH) then
                    return object
                end
            end
        end
    end
    return nil
end

-- Per attribute: invested points (attribute set), and from the character's attributes component the initial value
-- (without points), the base value (initial + points) and the current value (with items and buffs).
local function attributesOf(attributeSet, component)
    local attributes = {}
    for key, name in pairs(ATTRIBUTES) do
        attributes[key] = {
            points = attributeSet and readOr(function() return attributeSet["m_AttributePoints" .. name] end),
            initial = component and readOr(function() return component["GetInitial" .. name](component) end),
            base = component and readOr(function() return component["GetBase" .. name](component) end),
            current = component and readOr(function() return component["GetCurrent" .. name](component) end),
        }
    end
    for key, name in pairs(DERIVED_ATTRIBUTES) do
        attributes[key] = { current = component and readOr(function() return component["GetCurrent" .. name](component) end) }
    end
    return attributes
end

-- Everything the planner needs from the player behind playerState.
function CharacterDump.collect(playerState)
    local owners = { playerState:GetAddress() }
    local pawn = readOr(function() return playerState.PawnPrivate end)
    if usable(pawn) then
        owners[#owners + 1] = pawn:GetAddress()
    end
    local progression = ownedObject(PROGRESSION_SET_CLASS, owners)
    local character = {
        level = progression and readOr(function() return progression.CurrentLevel.CurrentValue end),
        attributes = attributesOf(ownedObject(ATTRIBUTE_SET_CLASS, owners),
            ownedObject(ATTRIBUTES_COMPONENT_CLASS, owners)),
        -- CharacterAP counts every attribute point granted so far, spent or not (level 30: 58 with 52 spent).
        grantedAttributePoints = progression and readOr(function() return progression.CharacterAP.CurrentValue end),
        skillPoints = {},
        masteries = {},
        equipment = {},
    }
    local component = readOr(function() return playerState.m_pMasteryComponent end)
    if usable(component) then
        for key, field in pairs(POINT_FIELDS) do
            character.skillPoints[key] = readOr(function() return component[field] end)
        end
        for _, instance in ipairs(readOr(function() return listOf(component.m_Masteries) end) or {}) do
            local mastery = CharacterDump.describeMastery(instance)
            if mastery.id ~= nil then
                character.masteries[#character.masteries + 1] = mastery
            end
        end
    end
    local equipment = readOr(function() return playerState.m_pEquipmentContainer end)
    if usable(equipment) then
        character.equipment = GearDump.containerItems(equipment)
    end
    return character
end

-- Writes the character behind playerState to path and logs a summary. Call on the game thread.
function CharacterDump.write(path, playerState, log)
    if not usable(playerState) then
        log("Character dump: no player")
        return
    end
    local character = CharacterDump.collect(playerState)
    local ok, reason = TextFile.write(path, JsonText.encode(character) .. "\n")
    if not ok then
        log("Character dump not written: " .. reason)
        return
    end
    local skills = 0
    for _, mastery in ipairs(character.masteries) do
        skills = skills + #mastery.skills
    end
    local might = character.attributes.might
    log(string.format("Character written to %s: level %s, %d masteries, %d skills, %d equipped, might %s points %s current",
        path, tostring(character.level), #character.masteries, skills, #character.equipment, tostring(might.points),
        tostring(might.current)))
end

return CharacterDump
