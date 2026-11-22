-- Tests: Loot filter rules, crafting-aware matching, rule edits and equipment pickup with rules.
-- Run all tests with: lua5.4 tests/test_tq2tweaks.lua

local T = require("support")
local EquipmentPickup = require("equipment_pickup")
local workDir, keyBinds, check, container = T.workDir, T.keyBinds, T.check, T.container
local text, mockAffix, groundItem, looter = T.text, T.mockAffix, T.groundItem, T.looter
local isEquipmentType, counts = T.isEquipmentType, T.counts

-- Loot filter rules: conditions of a rule combine with "and", an item is picked up if any rule matches.
local LootRules = require("loot_rules")
local SUMMON_DAMAGE, SUMMON_HEALTH = "da_prefix_1_Summons_PerIncreasedDamage_All", "da_suffix_1_Summons_PerIncreasedHealth"
local HEALTH, BARRIER, FIRE = "da_suffix_1_Health", "da_suffix_1_EnergyBarrier", "da_prefix_1_PerIncreasedFireDmg_high"
local RARITY = { Common = 0, Magic = 1, Rare = 2, Infrequent = 3, Epic = 4, Legendary = 5 }
local filterLog = {}
local function logFilter(line) filterLog[#filterLog + 1] = line end
local filterPath = workDir .. "/loot_filter.lua"
local function writeFilter(text)
    local filterFile = io.open(filterPath, "w")
    filterFile:write(text)
    filterFile:close()
end
writeFilter(table.concat({
    'return {',
    '    { name = "Summoner", minRarity = "Rare", needed = 1, types = {}, affixes = {',
    '        "' .. SUMMON_DAMAGE .. '", -- Beastcaller\'s: Summons have X% increased Damage',
    '        "' .. SUMMON_HEALTH .. '",',
    '    } },',
    '    { name = "Defence", minRarity = "Rare", needed = 2, types = { "head", "torso" }, affixes = {',
    '        "' .. HEALTH .. '", "' .. BARRIER .. '",',
    '    } },',
    '    { name = "Epic and better", minRarity = "Epic", needed = 1, types = {}, affixes = {} },',
    '    { name = "Everything", needed = 1, types = {}, affixes = {} },',
    '    { name = "Typo", minRarity = "Rarest" },',
    '}', '' }, "\n"))
local rules = LootRules.load(filterPath, RARITY, logFilter)
check("loot filter: rules loaded, rules without condition or with an unknown rarity left out and logged",
    #rules == 3 and filterLog[#filterLog] == "Loot filter: 3 rule(s) Summoner, Defence, Epic and better"
    and table.concat(filterLog, "|"):match("Everything: no condition") ~= nil
    and table.concat(filterLog, "|"):match("Typo: unknown rarity") ~= nil)
local function matches(rarity, typeName, ...)
    return LootRules.matchesAny(rules, { rarity = rarity, typeName = typeName, affixNames = { ... } })
end
check("rule Summoner: one summon affix on a rare is enough, a magic item is not",
    matches(2, "da_weapon_2h_staff_magic_spirit_greek_t3", SUMMON_DAMAGE, FIRE)
    and not matches(1, "da_weapon_2h_staff_magic_spirit_greek_t3", SUMMON_DAMAGE))
check("rule Defence: two defence affixes on the listed types only",
    matches(2, "da_armor_head_greek_paladin", HEALTH, BARRIER)
    and not matches(2, "da_armor_head_greek_paladin", HEALTH, FIRE)
    and not matches(2, "da_armor_leg_greek_paladin", HEALTH, BARRIER))
writeFilter('return { { name = "Arms", types = { "arm" } } }\n')
local armRules = LootRules.load(filterPath, RARITY, logFilter)
do
    local SPEED, FIRE_DMG, COLD_DMG = "da_prefix_1_Summons_PerIncreasedSpeed_All", "da_prefix_1_PerIncreasedFireDmg", "da_prefix_1_PerIncreasedColdDmg"
    local AGILITY = "da_suffix_1_Agility"
    writeFilter('return { { name = "Jewellery", minRarity = "Magic", needed = 3, craftable = true, affixes = { "'
        .. SUMMON_DAMAGE .. '", "' .. SPEED .. '", "' .. SUMMON_HEALTH .. '" } },\n'
        .. '  { name = "Plain", minRarity = "Magic", needed = 3, affixes = { "' .. SUMMON_DAMAGE .. '", "' .. SPEED .. '", "' .. SUMMON_HEALTH .. '" } } }\n')
    local craftRules = LootRules.load(filterPath, RARITY, logFilter)
    local function item(rarity, maxAffixes, ...)
        local affixes = {}
        for _, name in ipairs({ ... }) do affixes[#affixes + 1] = { name = name, random = true } end
        return { rarity = rarity, typeName = "da_jewelry_ring_x", maxAffixes = maxAffixes, affixes = affixes }
    end
    check("crafting: a magic item with 2 wanted affixes and a free place counts (add + replace)",
        LootRules.matchesAny({ craftRules[1] }, item(1, 3, SUMMON_DAMAGE, SUMMON_HEALTH))
        and not LootRules.matchesAny({ craftRules[2] }, item(1, 3, SUMMON_DAMAGE, SUMMON_HEALTH)))
    check("crafting: a full rare counts when a useless random affix of the missing kind can be replaced",
        LootRules.matchesAny({ craftRules[1] }, item(2, 4, SUMMON_DAMAGE, SUMMON_HEALTH, FIRE_DMG, AGILITY)))
    check("crafting: a prefix cannot become the missing suffix",
        not LootRules.matchesAny({ craftRules[1] }, item(2, 4, SUMMON_DAMAGE, SPEED, FIRE_DMG, COLD_DMG)))
    local unique = { rarity = 4, typeName = "da_jewelry_ring_x", affixes = {
        { name = SUMMON_DAMAGE, random = false }, { name = SPEED, random = false }, { name = FIRE_DMG, random = false } } }
    check("crafting: fixed (non-random) affixes of uniques are not replaceable",
        not LootRules.matchesAny({ craftRules[1] }, unique))
end
do
    local text = table.concat({
        "return {",
        '    { name = "Helmet", minRarity = "Magic", needed = 3, craftable = true, types = { "head" }, affixes = {',
        '        "' .. HEALTH .. '", "' .. BARRIER .. '", "' .. FIRE .. '",',
        "    } },",
        '    { name = "Epic and better", minRarity = "Epic", needed = 1, types = {  }, affixes = {} },',
        "}", "" }, "\n")
    local edited = LootRules.editRule(text, "Helmet", { minRarity = "Rare", needed = 2, enabled = false })
    local editedRules = LootRules.fromText(edited, RARITY, logFilter)
    check("menu edit: rarity, count and on/off written into the rule's header line",
        edited:find('{ name = "Helmet", minRarity = "Rare", needed = 2, craftable = true, enabled = false, types = { "head" }', 1, true) ~= nil
        and #editedRules == 2 and editedRules[1].enabled == false and editedRules[1].needed == 2 and editedRules[2].enabled)
    check("a rule switched off never matches",
        not LootRules.matchesAny({ editedRules[1] }, { rarity = 5, typeName = "da_armor_head_x", affixNames = { HEALTH, BARRIER, FIRE } }))
    local back = LootRules.editRule(edited, "Helmet", { minRarity = false, enabled = true })
    check("menu edit: any rarity and on again", back:find('{ name = "Helmet", minRarity = nil, needed = 2, craftable = true, types =', 1, true) ~= nil)
    check("menu edit: unknown rule gives nil", LootRules.editRule(text, "Nope", { needed = 1 }) == nil)
end
check("type parts match whole parts of the type name (arm is not armor)",
    LootRules.matchesAny(armRules, { rarity = 0, typeName = "da_armor_arm_greek_paladin", affixNames = {} })
    and not LootRules.matchesAny(armRules, { rarity = 0, typeName = "da_armor_head_greek_paladin", affixNames = {} }))
check("rule Epic and better: any epic, whatever its affixes", matches(4, "da_jewelry_ring_normal_greek_t1", FIRE)
    and not matches(3, "da_jewelry_ring_normal_greek_t1", FIRE))
check("missing loot filter file: no rules, logged", #LootRules.load(workDir .. "/none.lua", RARITY, logFilter) == 0
    and filterLog[#filterLog]:match("missing") ~= nil)
writeFilter('os.exit(1)\n')
check("loot filter file cannot run code", #LootRules.load(filterPath, RARITY, logFilter) == 0
    and filterLog[#filterLog]:match("not loaded") ~= nil)

-- Equipment pickup with loot rules next to the rarity rule.
local function affixItem(name, rarity, ...)
    local item = groundItem(name, rarity, 100)
    local affixes = {}
    for _, affixName in ipairs({ ... }) do
        affixes[#affixes + 1] = { pAffix = mockAffix(affixName, {}, {}), Level = 1 }
    end
    item.slot.ItemHandle.pItem.m_Affixes = container(affixes)
    return item
end
local ruleState = EquipmentPickup.newState()
local summonSword = affixItem("da_sword_01_WorldItem_20", 2, SUMMON_DAMAGE, FIRE)
local fireSword = affixItem("da_sword_01_WorldItem_21", 2, FIRE)
local magicSummonSword = affixItem("da_sword_01_WorldItem_22", 1, SUMMON_DAMAGE)
for _, item in ipairs({ summonSword, fireSword, magicSummonSword }) do EquipmentPickup.remember(ruleState, item) end
EquipmentPickup.pass(ruleState, looter, 400, { lootRules = rules }, isEquipmentType)
check("pickup by loot rules: matching item picked up, others stay on the ground",
    summonSword.pickups == 1 and fireSword.pickups == 0 and magicSummonSword.pickups == 0)
local bothState = EquipmentPickup.newState()
local magicFire = affixItem("da_sword_01_WorldItem_25", 1, FIRE)
local rareFire = affixItem("da_sword_01_WorldItem_26", 2, FIRE)
for _, item in ipairs({ magicFire, rareFire }) do EquipmentPickup.remember(bothState, item) end
EquipmentPickup.pass(bothState, looter, 400, { minRarity = 2, lootRules = {} }, isEquipmentType)
check("rarity rule still applies next to the loot rules", rareFire.pickups == 1 and magicFire.pickups == 0)
local farState = EquipmentPickup.newState()
local farSummon = affixItem("da_sword_01_WorldItem_27", 2, SUMMON_DAMAGE)
farSummon.K2_GetActorLocation = function() return { X = 900, Y = 0, Z = 0 } end
local affixReads = 0
local affixArray = farSummon.slot.ItemHandle.pItem.m_Affixes
farSummon.slot.ItemHandle.pItem.m_Affixes = { ForEach = function(self, callback)
    affixReads = affixReads + 1
    return affixArray:ForEach(callback)
end }
EquipmentPickup.remember(farState, farSummon)
for _ = 1, 3 do EquipmentPickup.pass(farState, looter, 400, { lootRules = rules }, isEquipmentType) end
farSummon.K2_GetActorLocation = function() return { X = 300, Y = 0, Z = 0 } end
EquipmentPickup.pass(farState, looter, 400, { lootRules = rules }, isEquipmentType)
check("wanted item out of range: judged once, later only its distance is checked; picked up in range",
    affixReads == 1 and farSummon.pickups == 1)
do
    local delayedState = EquipmentPickup.newState(1.5)
    local fresh = affixItem("da_sword_01_WorldItem_28", 2, SUMMON_DAMAGE)
    local reads = 0
    local freshAffixes = fresh.slot.ItemHandle.pItem.m_Affixes
    fresh.slot.ItemHandle.pItem.m_Affixes = { ForEach = function(self, callback)
        reads = reads + 1
        return freshAffixes:ForEach(callback)
    end }
    EquipmentPickup.remember(delayedState, fresh, 10)
    EquipmentPickup.pass(delayedState, looter, 400, { lootRules = rules }, isEquipmentType, 10.5)
    local readsEarly, pickupsEarly = reads, fresh.pickups
    EquipmentPickup.pass(delayedState, looter, 400, { lootRules = rules }, isEquipmentType, 11.6)
    check("new ground item is left alone until it has settled, then judged and picked up",
        readsEarly == 0 and pickupsEarly == 0 and reads == 1 and fresh.pickups == 1)
end
check("affixes are read only when a rule with affixes is reached (epic item via the rarity-only rule)",
    LootRules.matchesAny(rules, { rarity = 4, typeName = "da_jewelry_ring_x",
        readAffixes = function() error("affixes read") end }) == true)
check("affix dump on Shift+F9 (for the affix picker), F9 alone is free for the meter reset", keyBinds.SHIFTF9 ~= nil)

do
-- Only upgrades: a rule with affixes takes an item only if it scores higher than the worn item of the same slot.
local LootRules = require("loot_rules")
local A, B, C, D = "da_prefix_1_PerColdRes", "da_prefix_1_PerLightningRes", "da_suffix_1_Health", "da_suffix_1_EnergyBarrier"
local upgradeRules = LootRules.fromText('return { { name = "Helmet", minRarity = "Magic", needed = 3, craftable = true, '
    .. 'types = { "head", "ring" }, affixes = { "' .. A .. '", "' .. B .. '", "' .. C .. '", "' .. D .. '" } } }\n',
    { Magic = 1, Rare = 2 }, function() end)
local function randomAffixes(...)
    local affixes = {}
    for index, name in ipairs({ ... }) do affixes[index] = { name = name, random = true } end
    return affixes
end
local wornHelmet = { typeName = "da_armor_head_greek_paladin", rarity = 2, maxAffixes = 4,
                     affixes = randomAffixes(A, B, C, "da_suffix_1_FreeEnergyReservation") }
local function candidate(typeName, rarity, maxAffixes, worn, ...)
    local reads = 0
    local item = { typeName = typeName, rarity = rarity, maxAffixes = maxAffixes, affixes = randomAffixes(...),
                   readWorn = function() reads = reads + 1; return worn end }
    return LootRules.matchesAny(upgradeRules, item), reads
end
-- Worn: 3 wanted + a useless suffix that crafting can replace with the 4th = 4.
check("only upgrades: magic helmet with 2 wanted + a free place (3) loses against the worn one (4)",
    not candidate("da_armor_head_centaur_sorcerer", 1, 3, { wornHelmet }, A, C))
check("only upgrades: the same score as the worn helmet is no upgrade (rare with 4 wanted vs. worn 3 + crafting)",
    not candidate("da_armor_head_centaur_sorcerer", 2, 4, { wornHelmet }, A, B, C, D))
local weakHelmet = { typeName = "da_armor_head_greek_paladin", rarity = 1, maxAffixes = 3, affixes = randomAffixes(A, C, B) }
check("only upgrades: rare helmet with 4 wanted beats a full magic helmet with 3",
    candidate("da_armor_head_centaur_sorcerer", 2, 4, { weakHelmet }, A, B, C, D))
check("only upgrades: an empty slot is always beaten, other slots do not count",
    candidate("da_armor_head_centaur_sorcerer", 1, 3, { { typeName = "da_armor_leg_greek_sorcerer", rarity = 2,
        maxAffixes = 4, affixes = randomAffixes(A, B, C, D) } }, A, B, C))
local strongRing = { typeName = "da_jewelry_ring_normal_greek_agility_t1", rarity = 2, maxAffixes = 4, affixes = randomAffixes(A, B, C, D) }
local weakRing = { typeName = "da_jewelry_ring_normal_greek_knowledge_t1", rarity = 1, maxAffixes = 3, affixes = randomAffixes(A, B, "da_suffix_1_Agility") }
check("only upgrades: a ring is compared with the weaker of both worn rings",
    candidate("da_jewelry_ring_normal_ichthian_might_t1", 2, 4, { strongRing, weakRing }, A, B, C, "da_suffix_1_Agility"))
local _, reads = candidate("da_armor_leg_greek_sorcerer", 2, 4, { wornHelmet }, A, B, C)
check("only upgrades: worn items are not read for items no rule fits", reads == 0)
end

do
-- Worn items read from the player's equipment container, empty slots left out.
local EquipmentPickup = require("equipment_pickup")
local function valid() return true end
local helmet = { IsValid = valid, m_Rarity = 2,
    m_pDescription = { HardReference = { IsValid = valid, GetFullName = function() return "TQ2ItemDescription /Game/x.da_armor_head_greek_paladin" end } },
    m_Affixes = container({ { pAffix = mockAffix("da_prefix_1_PerColdRes", {}, {}), Level = 2, Category = 2 } }) }
local character = { PlayerState = { m_pEquipmentContainer = { IsValid = valid,
    m_ContainerData = { ItemSlots = container({ { ItemHandle = { pItem = helmet } }, { ItemHandle = { pItem = nil } } }) } } } }
local worn = EquipmentPickup.wornItems(character, { [2] = 4 })
check("worn items: type, rarity, affixes and free places from the equipment, empty slots left out",
    #worn == 1 and worn[1].typeName == "da_armor_head_greek_paladin" and worn[1].rarity == 2 and worn[1].maxAffixes == 4
    and worn[1].affixes[1].name == "da_prefix_1_PerColdRes" and worn[1].affixes[1].random == true)
check("worn items: none without an equipment container", #EquipmentPickup.wornItems({ PlayerState = {} }, {}) == 0)
end
