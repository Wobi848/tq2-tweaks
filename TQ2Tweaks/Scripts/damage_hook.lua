-- Feeds the damage meter from the game: every hit on a character runs Multicast_HandleDamageReceived_* on the
-- damaged character with the effect context (ability tags) and the damage context (amount, crit type, damage type).
-- Only hits by the player's abilities (incl. summons) on AI characters count. This hook runs for every hit, so it only reads and records; all
-- statistics are computed in the display loop.
local DamageMeter = require("damage_meter")

local DamageHook = {}

local DAMAGE_RECEIVED = {
    "/Script/TQ2Gameplay.TQ2Character:Multicast_HandleDamageReceived_Unreliable",
    "/Script/TQ2Gameplay.TQ2Character:Multicast_HandleDamageReceived_Reliable",
}
local ENEMY_CLASS = "/Script/TQ2Gameplay.TQ2AICharacter"
local CRIT_TYPE_REGULAR = 0

-- "VitalityDrain" -> "Vitality Drain"
local function spaced(name)
    return (name:gsub("(%l)(%u)", "%1 %2"))
end

-- Display name of a damage type tag: its last part with spaces between words, e.g. "...VitalityDrain" ->
-- "Vitality Drain". nil if unreadable.
function DamageHook.typeName(tag)
    local ok, name = pcall(function() return tag.TagName:ToString() end)
    if not ok or name == nil or name == "" or name == "None" then
        return nil
    end
    return spaced(name:match("([^%.]+)$"))
end

-- Names of the tags in a gameplay tag container (collected first, no work inside the engine loop).
function DamageHook.tagNames(container)
    local tags = {}
    container.GameplayTags:ForEach(function(_, element) tags[#tags + 1] = element:get() end)
    local names = {}
    for _, tag in ipairs(tags) do
        local name = tag.TagName:ToString()
        if name ~= nil and name ~= "" and name ~= "None" then
            names[#names + 1] = name
        end
    end
    return names
end

local DESCRIPTION_PREFIX = "GrimAbilitySystem.Description."

-- "eidolonGuard" -> "Eidolon Guard", "retaliation" -> "Retaliation"
local function title(part)
    return (spaced(part):gsub("^%l", string.upper))
end

-- Blueprint name from the ability's description tag, e.g. "GrimAbilitySystem.Description.bp_bga_player_sp_lich_m_soulBlight"
-- -> "player_sp_lich_m_soulBlight". nil if there is no description tag.
local function blueprintOf(tagNames)
    for _, name in ipairs(tagNames) do
        if name:sub(1, #DESCRIPTION_PREFIX) == DESCRIPTION_PREFIX then
            return (name:sub(#DESCRIPTION_PREFIX + 1):gsub("^bp_bga_", ""))
        end
    end
    return nil
end

-- Whether a hit comes from the player's side. Summons are AI characters too, so enemies hitting them land in the
-- same hook; their abilities are named after the enemy ("un_skeleton_...", "wl_boar_..."), the player's start with
-- "player_" or "global_" (e.g. retaliation). Hits without a description tag (e.g. damage over time) are kept.
function DamageHook.isPlayerAbility(tagNames)
    local blueprint = blueprintOf(tagNames)
    return blueprint == nil or blueprint:find("^player_") ~= nil or blueprint:find("^global_") ~= nil
end

-- Skill name from the description tag: owner ("player_"/"global_"), mastery code ("sp_", "fo_" ...), modifier
-- ("_m_..."), basic attack and summon ability are dropped, so everything a summon does is grouped: "Lich".
-- nil if there is no description tag.
function DamageHook.skillName(tagNames)
    local blueprint = blueprintOf(tagNames)
    if blueprint == nil then
        return nil
    end
    blueprint = blueprint:gsub("^player_%l%l_", ""):gsub("^player_", ""):gsub("^global_", "")
    local skill = blueprint:match("^(.-)_m_") or blueprint:match("^(.-)_basicAttack")
        or blueprint:match("^(.-)_summon") or blueprint
    skill = skill:gsub("_p$", "")
    local words = {}
    for part in skill:gmatch("[^_]+") do words[#words + 1] = title(part) end
    return #words > 0 and table.concat(words, " ") or nil
end

-- isEnabled() tells whether the meter is switched on (nothing is read from the engine while it is off).
-- now() returns the current time in seconds; log should log repeated lines only once.
function DamageHook.register(meter, isEnabled, now, log)
    -- Ability tag names of a hit; an empty list if unreadable.
    local function readTags(effectContext)
        local ok, names = pcall(function() return DamageHook.tagNames(effectContext:get().AbilityTags) end)
        return ok and names or {}
    end
    local function onDamage(character, effectContext, damageContext)
        if not isEnabled() then
            return
        end
        local damaged = character:get()
        if damaged == nil or not damaged:IsValid() or not damaged:IsA(ENEMY_CLASS) then
            return
        end
        local context = damageContext:get()
        if context.Damage <= 0 then
            return
        end
        local tagNames = readTags(effectContext)
        if not DamageHook.isPlayerAbility(tagNames) then
            return
        end
        DamageMeter.record(meter, now(), context.Damage, context.CritType ~= CRIT_TYPE_REGULAR,
            DamageHook.typeName(context.HighestDamageType), DamageHook.skillName(tagNames))
    end
    -- Errors are caught here and logged once, instead of UE4SS logging them for every hit.
    local function guardedOnDamage(...)
        local ok, err = pcall(onDamage, ...)
        if not ok then
            log("Damage hook error: " .. tostring(err))
        end
    end
    for _, functionPath in ipairs(DAMAGE_RECEIVED) do
        RegisterHook(functionPath, guardedOnDamage)
    end
end

return DamageHook
