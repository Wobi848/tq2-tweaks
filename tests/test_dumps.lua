-- Tests: Affix dump, game data dump, gear dump, character dump and mega dump.
-- Run all tests with: lua5.4 tests/test_tq2tweaks.lua

local T = require("support")
local workDir, game, instances, keyBinds = T.workDir, T.game, T.instances, T.keyBinds
local check, container, tagNamed, text = T.check, T.container, T.tagNamed, T.text
local mockAffix, groundItem = T.mockAffix, T.groundItem

-- Affix dump (diagnostic): affixes with tags and level texts, ground items with their affixes, written to a file.
local AffixDump = require("affix_dump")
local summonAffix = mockAffix("affix_summon_damage", { tagNamed("Affix.Summon") }, {
    { TitleText = text("of the Legion"), AdjectiveText = text("Commanding"),
      AffixEffects = container({ { Type = 0, ToolTipText = text("+{0}% Summon Damage") } }) } })
local brokenAffix = { IsValid = function() return true end, GetFullName = function() return "GrimItemAffix x.affix_broken" end }
local affixItem = groundItem("da_staff_03_WorldItem_7", 3, 0)
affixItem.slot.ItemHandle.pItem.m_Affixes = container({ { pAffix = summonAffix, Level = 2 } })
local emptyItem = groundItem("da_ring_01_WorldItem_8", nil, 0)
instances.GrimItemAffix = { summonAffix, brokenAffix }
instances.TQ2WorldItem = { affixItem, emptyItem }
local healthAffix = mockAffix("da_suffix_1_Health", {}, {})
local sharedTable = { IsValid = function() return true end, GetFullName = function() return "GrimItemAffixTableAsset x.shared" end }
sharedTable.m_Table = { Entries = container({ { pAffix = healthAffix } }),
                        SubTables = container({ { pTable = sharedTable } }) } -- contains itself
local function itemType(name, entries)
    return { IsValid = function() return true end, GetFullName = function() return "TQ2ItemDescription x." .. name end,
             m_RandomAffixes = { Entries = container(entries), SubTables = container({ { pTable = sharedTable } }) } }
end
local savedDescriptions = instances.TQ2ItemDescription
instances.TQ2ItemDescription = { itemType("da_weapon_2h_staff_a", { { pAffix = summonAffix } }),
                                 itemType("da_jewelry_ring_b", { { pAffix = summonAffix } }),
                                 itemType("da_armor_head_c", {}),
                                 { IsValid = function() return true end, GetFullName = function() return "x.da_broken" end } }
local charmItem = { IsValid = function() return true end, GetFullName = function() return "TQ2ItemDescription x.da_socket_charm_bones_01" end }
local function socketEffect(tooltip, low, high)
    return { ToolTipText = text(tooltip), Scale = { min = { SourceText = text(low) }, max = { SourceText = text(high) } } }
end
instances.TQ2SocketableItemDescription = { { IsValid = function() return true end,
    GetFullName = function() return "TQ2SocketableItemDescription x.Socketable" end,
    GetOuter = function() return charmItem end,
    m_EffectsByCompletionLevel = container({ { effects = container({ socketEffect("+{Value}% Vitality Resistance", "4", "6") }) } }),
    m_CompletionBonus = { effects = container({ socketEffect("+{Value} Health", "20", "40") }) },
    m_pValidTargetFilter = { IsValid = function() return true end, m_AllowedRarities = 7,
        m_ItemTypeRequirement = { BaseRequirement = { RequirementType = 0,
            GameplayTags = { GameplayTags = container({ tagNamed("GrimVentory.ItemType.Arm"), tagNamed("GrimVentory.ItemType.Ring") }) } } },
        m_GameplayTagsRequirement = { BaseRequirement = { RequirementType = 0, GameplayTags = { GameplayTags = container({}) } } } } } }
local dumpPath = workDir .. "/affix_dump.txt"
local dumpLog = {}
local pageDataPath, dumpFilterPath = workDir .. "/affix_data.js", workDir .. "/dump_filter.lua"
local dumpFilterFile = io.open(dumpFilterPath, "w")
dumpFilterFile:write('return { { name = "Say \\"hi\\"" } }\n')
dumpFilterFile:close()
AffixDump.write({ dump = dumpPath, pageData = pageDataPath, filter = dumpFilterPath },
    function(line) dumpLog[#dumpLog + 1] = line end)
local pageDataFile = io.open(pageDataPath, "r")
local pageData = pageDataFile and pageDataFile:read("a") or ""
if pageDataFile then pageDataFile:close() end
check("affix dump: data file for the editor carries the dump and the loot filter, escaped for JavaScript",
    pageData:match('^window%.TQ2_TWEAKS_DATA = { dump: "AFFIXES %(2 loaded%)\\n') ~= nil
    and pageData:find('filter: "return { { name = \\"Say \\\\\\"hi\\\\\\"\\" } }\\n" };', 1, true) ~= nil)
check("affix dump: without a loot filter the data file says null",
    AffixDump.pageData("x", nil) == 'window.TQ2_TWEAKS_DATA = { dump: "x", filter: null };\n')
local dumpFile = io.open(dumpPath, "r")
local dump = dumpFile and dumpFile:read("a") or ""
if dumpFile then dumpFile:close() end
check("affix dump: affix with tags and level texts", dump:match("AFFIXES %(2 loaded%)") ~= nil
    and dump:match("affix_summon_damage  type=1  tags=Affix.Summon") ~= nil
    and dump:match('L1 "of the Legion" adjective "Commanding": %[0%] %+{0}%% Summon Damage') ~= nil)
check("affix dump: unreadable fields do not stop the dump", dump:match("affix_broken  type=%?  tags=%?") ~= nil)
check("affix dump: ground items with their affixes, unfilled ones left out", dump:match("GROUND ITEMS %(1%)") ~= nil
    and dump:match("da_staff_03  rarity=3: affix_summon_damage L2") ~= nil)
instances.TQ2ItemDescription = savedDescriptions
instances.TQ2SocketableItemDescription = nil
check("affix dump: charms and relics with their effects per stage and the completion bonus",
    dump:find("SOCKETABLES (1)\nSOCKETABLE da_socket_charm_bones_01\n  stage 1: +{Value}% Vitality Resistance [4..6]\n  bonus: +{Value} Health [20..40]\n  sockets into: types any of Arm, Ring; rarity mask 7", 1, true) ~= nil)
check("affix dump: pools per item type, through sub-tables, same pools grouped, unreadable types left out",
    dump:match("AFFIX POOLS %(3 item types, 2 pools%)") ~= nil
    and dump:find("POOL types=da_armor_head_c\n  affixes=da_suffix_1_Health\n", 1, true) ~= nil
    and dump:find("POOL types=da_jewelry_ring_b,da_weapon_2h_staff_a\n  affixes=affix_summon_damage,da_suffix_1_Health\n", 1, true) ~= nil)
check("affix dump: logs where it went", dumpLog[1] ~= nil and dumpLog[1]:find(dumpPath, 1, true) ~= nil)

do
-- Game data dump: creature templates from the game's asset list, their drop lists (weights and chances as formula
-- text, sub-lists once even when a list contains itself), item types with their affix tables, all as JSON.
local GameDataDump = require("game_data_dump")
local function formulaOf(source) return { SourceText = text(source) } end
local cacheText = '{ "pathsByClass": { "/Script/Other.Thing": { "paths": [ "/JsonData/x" ] },\n'
    .. '"/Script/TQ2Gameplay.TQ2CreatureTemplateJsonData": { "paths": [ "/JsonData/TQ2/Creatures/da_cr_skeleton",'
    .. ' "/JsonData/TQ2/Creatures/da_missing" ] } } }'
local AssetList = require("asset_list")
check("game data: creature paths from the asset list, object path from the asset path",
    table.concat(AssetList.pathsOfClass(cacheText, "/Script/TQ2Gameplay.TQ2CreatureTemplateJsonData"), "|")
        == "/JsonData/TQ2/Creatures/da_cr_skeleton|/JsonData/TQ2/Creatures/da_missing"
    and AssetList.objectPath("/JsonData/TQ2/Creatures/da_cr_skeleton") == "/JsonData/TQ2/Creatures/da_cr_skeleton.da_cr_skeleton")
local droppedSword = { IsValid = function() return true end, GetFullName = function() return "TQ2ItemDescription x.da_sword_x" end }
local skeletonDrops = { IsValid = function() return true end, GetFullName = function() return "GrimItemDropList x.dl_skeleton" end,
    GetClass = function() return { GetFName = function() return text("GrimItemDropList") end } end,
    m_DropChance = formulaOf("1"), m_NumRandomDrops = { min = formulaOf("1"), max = formulaOf("Level / 10") },
    m_FixedDrops = container({}) }
skeletonDrops.m_RandomDropTable = {
    Entries = container({ { Weight = formulaOf("10"), IsGuaranteed = false,
        Requirement = { GameplayTagRequirement = { BaseRequirement = { RequirementType = 1,
            GameplayTags = { GameplayTags = container({ tagNamed("Difficulty.Normal") }) } },
            AdditionalRequirements = container({}) }, CustomRequirement = formulaOf("") },
        ItemDrop = { pItemDescription = { HardReference = droppedSword },
                     NumToDrop = { min = formulaOf("1"), max = formulaOf("1") } } } }),
    SubTables = container({ { Weight = formulaOf("2"), pDropList = skeletonDrops } }) } -- contains itself
local skeleton = { IsValid = function() return true end, m_CreatureDesc = { Name = text("Skeleton"), Title = text(""),
    InternalName = text("cr_skeleton"), GameplayTags = { GameplayTags = container({ tagNamed("Creature.Undead") }) },
    pDropList = skeletonDrops, OverrideItemDropChance = true, ItemDropChanceOverride = formulaOf("0.5"),
    OverrideNumItemDrops = false } }
function LoadAsset(path)
    if path == "/JsonData/TQ2/Creatures/da_cr_skeleton.da_cr_skeleton" then return skeleton end
    error("not found: " .. path)
end
local gameCachePath, gameDataPath = workDir .. "/JsonMetaDataCache.json", workDir .. "/game_data.json"
local gameCacheFile = io.open(gameCachePath, "w")
gameCacheFile:write(cacheText)
gameCacheFile:close()
local savedItemTypes = instances.TQ2ItemDescription
instances.TQ2ItemDescription = { itemType("da_weapon_2h_staff_a", { { pAffix = summonAffix } }) }
local gameLog = {}
local gameState = GameDataDump.newState()
local gamePagePath = workDir .. "/game_data.js"
GameDataDump.start(gameState, { cache = gameCachePath, output = gameDataPath, page = gamePagePath },
    function(line) gameLog[#gameLog + 1] = line end)
local gamePageFile = io.open(gamePagePath, "r")
local gamePage = gamePageFile and gamePageFile:read("a") or ""
if gamePageFile then gamePageFile:close() end
instances.TQ2ItemDescription = savedItemTypes
local gameDataFile = io.open(gameDataPath, "r")
local gameData = gameDataFile and gameDataFile:read("a") or ""
if gameDataFile then gameDataFile:close() end
check("game data: creature with name, tags, own drop chance and its drop list",
    gameData:find('"dropChance":"0.5","dropList":"dl_skeleton","internalName":"cr_skeleton","name":"Skeleton"', 1, true) ~= nil
    and gameData:find('"tags":["Creature.Undead"]', 1, true) ~= nil)
check("game data: drop list with chance, count range, weighted item entry with its requirement tags",
    gameData:find('"randomDrops":{"max":"Level / 10","min":"1"}', 1, true) ~= nil
    and gameData:find('"item":"da_sword_x"', 1, true) ~= nil and gameData:find('"weight":"10"', 1, true) ~= nil
    and gameData:find('"tags":{"mode":1,"tags":["Difficulty.Normal"]}', 1, true) ~= nil)
check("game data: a list containing itself is written once and referenced by name",
    gameData:find('{"list":"dl_skeleton","weight":"2"}', 1, true) ~= nil)
check("game data: item types with their affix tables, creatures that do not load are listed",
    gameData:find('"name":"da_weapon_2h_staff_a"', 1, true) ~= nil
    and gameData:find('"shared":[{"affix":"da_suffix_1_Health"},{"table":"shared"}]', 1, true) ~= nil
    and gameData:find('"notLoaded":["/JsonData/TQ2/Creatures/da_missing"]', 1, true) ~= nil)
check("game data: the same data as a script for the data page",
    gamePage:sub(1, 24) == "window.TQ2_GAME_DATA = {" and gamePage:find(gameData:sub(1, 200), 1, true) ~= nil)
check("game data: finished and logged, a second start is possible again", GameDataDump.isRunning(gameState) == false
    and gameLog[#gameLog]:match("1 creatures %(1 not loaded%), 1 drop lists, 1 item types") ~= nil)
check("developer dumps have no keys (command file only)", keyBinds.CONTROLF9 == nil)
end

-- Gear dump: equipped items and the player's own inventories with every affix's tier and roll, as JSON.
do
    local GearDump = require("gear_dump")
    local function valid(fields)
        fields.IsValid = function() return true end
        return fields
    end
    local function gearItem(typeName, rarity, affixName, tier, scale)
        return valid({ m_pDescription = { HardReference = valid({ GetFullName = function() return "TQ2ItemDescription x." .. typeName end }) },
                       m_Rarity = rarity, m_Level = 40, m_CustomName = text(""),
                       m_Affixes = container({ { pAffix = mockAffix(affixName, {}, {}), Level = tier, Category = 2,
                                                 EffectScaleMultiplier = 1, AffixEffectInstances = container({ { Scale = scale } }) } }) })
    end
    local function slots(...)
        local list = {}
        for _, instance in ipairs({ ... }) do list[#list + 1] = { ItemHandle = { pItem = instance }, Num = 1 } end
        return { m_ContainerData = { ItemSlots = container(list) } }
    end
    local playerState = valid({ GetAddress = function() return 500 end })
    playerState.m_pEquipmentContainer = valid(slots(gearItem("da_jewelry_ring_a", 2, "da_prefix_1_Summons_PerIncreasedDamage_All", 3, 0.75), false))
    local component = valid({ GetAddress = function() return 501 end, GetOuter = function() return playerState end })
    local bag = valid(slots(gearItem("da_weapon_2h_staff_b", 4, "da_suffix_1_Health", 5, 0.5)))
    bag.GetFullName = function() return "TQ2Inventory x.Backpack" end
    bag.GetOuter = function() return component end
    local foreign = valid(slots(gearItem("da_weapon_2h_axe_c", 1, "da_suffix_1_Health", 1, 0.1)))
    foreign.GetOuter = function() return valid({ GetAddress = function() return 999 end, GetOuter = function() return nil end }) end
    local savedInventories = instances.TQ2Inventory
    instances.TQ2Inventory = { bag, foreign }
    local gearPath, gearLog = workDir .. "/gear.json", {}
    GearDump.write(gearPath, playerState, function(line) gearLog[#gearLog + 1] = line end)
    instances.TQ2Inventory = savedInventories
    local gearFile = io.open(gearPath, "r")
    local gear = gearFile and gearFile:read("a") or ""
    if gearFile then gearFile:close() end
    check("gear dump: equipped item with type, rarity, level and affix tier and roll", gear:find(
        '"equipment":[{"affixes":[{"category":"random","multiplier":1,"name":"da_prefix_1_Summons_PerIncreasedDamage_All","scales":[0.75],"tier":3}],"count":1,"level":40,"rarity":2,"slot":1,"type":"da_jewelry_ring_a"}]',
        1, true) ~= nil)
    check("gear dump: the player's inventories only, foreign ones left out",
        gear:find('"inventories":[{"items":[', 1, true) ~= nil and gear:find('"name":"Backpack"', 1, true) ~= nil
        and gear:find("da_weapon_2h_staff_b", 1, true) ~= nil and gear:find("da_weapon_2h_axe_c", 1, true) == nil
        and gearLog[1]:match("1 equipped, 1 in 1 inventories") ~= nil)
end

-- Character dump: level, attribute points, masteries with skills (points, modifiers) and passives (points, feats) as the
-- game data names them, from the player's own mastery component and attribute sets.
do
    local CharacterDump = require("character_dump")
    local function valid(fields)
        fields.IsValid = function() return true end
        return fields
    end
    local function asset(fullName) return valid({ GetFullName = function() return fullName end }) end
    local playerState = valid({ GetAddress = function() return 600 end })
    local skill = { pMasteryActiveAbilityDescription = { pAbility = asset("BlueprintGeneratedClass /Game/A/bp_selector_trick_shot.bp_selector_trick_shot_C") },
                    InvestedPoints = 17,
                    ModifierSlots = container({ { ModifierClass = asset("BlueprintGeneratedClass /Game/M/bp_gam_shadow_dagger.bp_gam_shadow_dagger_C"), Level = 1 } }) }
    local unspent = { pMasteryActiveAbilityDescription = { pAbility = asset("BlueprintGeneratedClass /Game/A/bp_selector_other.bp_selector_other_C") },
                      InvestedPoints = 0, ModifierSlots = container({}) }
    local passive = { pMasteryPassiveAbilityDescription = { m_pPassiveAbility = asset("BlueprintGeneratedClass /Game/P/bp_ge_player_storm_mind.bp_ge_player_storm_mind_C") },
                      InvestedPoints = 8, FeatSlots = container({ asset("BlueprintGeneratedClass /Game/P/bp_ge_feat_a.bp_ge_feat_a_C") }) }
    playerState.m_pMasteryComponent = valid({ m_Masteries = container({ {
        pMasteryDescription = { HardReference = asset("TQ2MasteryDescription /Game/M/da_mastery_storm.da_mastery_storm") },
        InvestedMasteryPoints = 30, ActiveAbilities = container({ skill, unspent }), PassiveAbilities = container({ passive }) } }),
        m_ActivePointsFromLevel = 54, m_ActivePoints = 56, m_MasteryPoints = 36 })
    local attributes = valid({ GetOuter = function() return playerState end, m_AttributePointsMight = 30,
                               m_AttributePointsAgility = 0, m_AttributePointsKnowledge = 12, m_AttributePointsVigor = 5 })
    local foreignAttributes = valid({ GetOuter = function() return nil end, m_AttributePointsMight = 99 })
    local progression = valid({ GetOuter = function() return playerState end, CurrentLevel = { CurrentValue = 27 },
                               CharacterAP = { CurrentValue = 3 } })
    local component = valid({ GetOuter = function() return playerState end })
    for _, name in ipairs({ "Might", "Agility", "Knowledge", "Vigor" }) do
        component["GetInitial" .. name] = function() return 50 end
        component["GetBase" .. name] = function(self) return 50 + 5 * attributes["m_AttributePoints" .. name] end
        component["GetCurrent" .. name] = function(self) return self["GetBase" .. name](self) + 7 end
    end
    component.GetCurrentFitness = function() return 222 end
    -- The attack set, read through reflection: gameplay attributes give their current value, other fields are left out.
    local function named(value) return { ToString = function() return value end } end
    local function prop(name, kind, struct)
        return { GetFName = function() return named(name) end, GetStruct = function() return struct end,
                 GetClass = function() return { GetFName = function() return named(kind) end } end }
    end
    local attributeData = { IsValid = function() return true end, GetSuperStruct = function() return nil end,
        ForEachProperty = function(_, callback)
            callback(prop("BaseValue", "FloatProperty")); callback(prop("CurrentValue", "FloatProperty")) end }
    local attackClass = { IsValid = function() return true end, GetSuperStruct = function() return nil end,
        ForEachProperty = function(_, callback)
            callback(prop("AbilityCritChance", "StructProperty", attributeData)); callback(prop("m_Count", "IntProperty")) end }
    local attackSet = valid({ GetOuter = function() return playerState end, GetAddress = function() return 610 end,
        GetClass = function() return attackClass end,
        AbilityCritChance = { BaseValue = 0.05, CurrentValue = 0.12 }, m_Count = 4 })
    local saved = { instances.TQ2CharacterAttributesSet, instances.TQ2AttributeSetProgression,
                    instances.TQ2CharacterAttributesComponent, instances.GrimAttributeSetAttack,
                    instances.GrimAttributeSetMovement }
    instances.GrimAttributeSetAttack = { attackSet }
    instances.GrimAttributeSetMovement = nil
    instances.TQ2CharacterAttributesSet = { foreignAttributes, attributes }
    instances.TQ2AttributeSetProgression = { progression }
    instances.TQ2CharacterAttributesComponent = { component }
    local character = CharacterDump.collect(playerState)
    local path, lines = workDir .. "/character.json", {}
    CharacterDump.write(path, playerState, function(line) lines[#lines + 1] = line end)
    instances.TQ2CharacterAttributesSet, instances.TQ2AttributeSetProgression = saved[1], saved[2]
    instances.TQ2CharacterAttributesComponent = saved[3]
    instances.GrimAttributeSetAttack, instances.GrimAttributeSetMovement = saved[4], saved[5]
    local storm = character.masteries[1]
    check("character dump: mastery, skill and modifier named like the game data (no _C), unspent skills left out",
        storm.id == "da_mastery_storm" and storm.points == 30 and #storm.skills == 1
        and storm.skills[1].id == "bp_selector_trick_shot" and storm.skills[1].points == 17
        and storm.skills[1].modifiers[1].id == "bp_gam_shadow_dagger" and storm.skills[1].modifiers[1].level == 1)
    check("character dump: passives with points and feats",
        storm.passives[1].id == "bp_ge_player_storm_mind" and storm.passives[1].points == 8
        and storm.passives[1].feats[1] == "bp_ge_feat_a")
    local might = character.attributes.might
    check("character dump: level and the player's own attribute points, not another set's",
        character.level == 27 and might.points == 30 and character.attributes.knowledge.points == 12
        and character.attributes.vigor.points == 5)
    check("character dump: the game's computed attributes by set, only gameplay attributes",
        character.gameAttributes.GrimAttributeSetAttack.AbilityCritChance == 0.12
        and character.gameAttributes.GrimAttributeSetAttack.m_Count == nil)
    check("character dump: point counters of the mastery component and all attribute points granted",
        character.skillPoints.activeFromLevel == 54 and character.skillPoints.active == 56
        and character.skillPoints.mastery == 36 and character.grantedAttributePoints == 3)
    check("character dump: initial, base and current attribute values from the attributes component",
        might.initial == 50 and might.base == 200 and might.current == 207 and character.attributes.fitness.current == 222)
    check("character dump: file written and summary logged",
        io.open(path, "r") ~= nil and lines[1]:match("level 27, 1 masteries, 1 skills, 0 equipped, might 30 points 207 current") ~= nil)
end

-- Mega dump: every asset of the game's asset list, read through reflection (inherited fields, structs, arrays,
-- references by name), class defaults of referenced effects, maps skipped, assets that do not load listed.
do
    local MegaDump = require("mega_dump")
    local function named(value) return { ToString = function() return value end } end
    local function prop(name, kind, extra)
        local property = { GetFName = function() return named(name) end,
                           GetClass = function() return { GetFName = function() return named(kind) end } end }
        for key, value in pairs(extra or {}) do property[key] = value end
        return property
    end
    local function structType(properties, super)
        return { IsValid = function() return true end, GetSuperStruct = function() return super end,
                 ForEachProperty = function(_, callback) for _, property in ipairs(properties) do callback(property) end end }
    end
    local valid = function() return true end
    local innerStruct = structType({ prop("A", "FloatProperty"),
        prop("List", "ArrayProperty", { GetInner = function() return prop("", "IntProperty") end }) })
    local effectDefaults = { IsValid = valid, GetAddress = function() return 900 end, Magnitude = 2.5,
        GetClass = function() return structType({ prop("Magnitude", "FloatProperty") }) end }
    local effectClass = { IsValid = valid, GetAddress = function() return 901 end,
        GetFName = function() return named("bp_ge_summon_dmg_C") end,
        GetFullName = function() return "BlueprintGeneratedClass /Game/Effects/bp_ge_summon_dmg.bp_ge_summon_dmg_C" end,
        GetCDO = function() return effectDefaults end }
    local texture = { IsValid = valid, GetFullName = function() return "Texture2D /Game/Icons/earth.earth" end,
        GetOuter = function() return { GetAddress = function() return 1 end } end }
    local baseClass = structType({ prop("Title", "TextProperty") })
    local assetClass = structType({ prop("Count", "IntProperty"),
        prop("Inner", "StructProperty", { GetStruct = function() return innerStruct end }),
        prop("Icon", "ObjectProperty"), prop("Effect", "ClassProperty"), prop("Lookup", "MapProperty"),
        prop("Tier", "ObjectProperty"), prop("Balance", "ObjectProperty") }, baseClass)
    local mastery = { IsValid = valid, GetAddress = function() return 700 end, GetClass = function() return assetClass end,
        Title = named("Earth"), Count = 3, Inner = { A = 1.5, List = container({ 1, 2 }) }, Icon = texture,
        Effect = effectClass, Lookup = {} }
    -- A skill inside a tier inside the mastery: part of the asset two levels down, written in full.
    local function subObject(address, outer, path, class, fields)
        local object = { IsValid = valid, GetAddress = function() return address end, GetOuter = function() return outer end,
            GetFullName = function() return "Object " .. path end, GetClass = function() return class end }
        for key, value in pairs(fields) do object[key] = value end
        return object
    end
    local tier = subObject(701, mastery, "/JsonData/m.m:Tier_0", structType({ prop("Skill", "ObjectProperty") }), {})
    tier.Skill = subObject(702, tier, "/JsonData/m.m:Tier_0.Skill_0", structType({ prop("Damage", "IntProperty") }), { Damage = 7 })
    mastery.Tier = tier
    -- Balancing data the skill formulas read: a separate object, dumped because it is referenced.
    mastery.Balance = subObject(800, nil, "/Game/Balancing/da_balancing_x.da_balancing_x",
        structType({ prop("BaseCD", "IntProperty") }), { BaseCD = 12 })
    local savedLoadAsset = LoadAsset
    function LoadAsset(path)
        if path == "/JsonData/TQ2/Masteries/da_mastery_earth.da_mastery_earth" then return mastery end
        error("not found: " .. path)
    end
    local cachePath, outputPath = workDir .. "/mega_cache.json", workDir .. "/mega_dump.jsonl"
    local cacheFile = io.open(cachePath, "w")
    cacheFile:write('{ "pathsByClass": { "/Script/TQ2Gameplay.TQ2MasteryDescription": { "paths": [ '
        .. '"/JsonData/TQ2/Masteries/da_mastery_earth", "/JsonData/TQ2/Masteries/da_missing" ] } } }')
    cacheFile:close()
    local megaLog = {}
    -- No settings objects in this test (the mocked StaticFindObject has none to read).
    local rulesPath = workDir .. "/mega_rules.lua"
    local rulesFile = io.open(rulesPath, "w")
    rulesFile:write("return { defaults = {} }\n")
    rulesFile:close()
    MegaDump.start(MegaDump.newState(), { cache = cachePath, output = outputPath, rules = rulesPath },
        function(line) megaLog[#megaLog + 1] = line end)
    LoadAsset = savedLoadAsset
    local lines = {}
    for line in io.lines(outputPath) do lines[#lines + 1] = line end
    check("mega dump: asset read through reflection (inherited text, number, struct with array, reference by name)",
        lines[1] ~= nil and lines[1]:find('"Count":3', 1, true) ~= nil and lines[1]:find('"Title":"Earth"', 1, true) ~= nil
        and lines[1]:find('"Inner":{"A":1.5,"List":[1,2]}', 1, true) ~= nil
        and lines[1]:find('"Icon":"/Game/Icons/earth.earth"', 1, true) ~= nil and lines[1]:find("Lookup", 1, true) == nil)
    check("mega dump: sub-objects nested inside the asset written in full",
        lines[1] ~= nil and lines[1]:find('"Damage":7', 1, true) ~= nil)
    check("mega dump: assets that do not load are listed, referenced effect classes add their defaults",
        lines[2] ~= nil and lines[2]:find('"notLoaded":true', 1, true) ~= nil
        and lines[3] ~= nil and lines[3]:find('"classDefault":"/Game/Effects/bp_ge_summon_dmg.bp_ge_summon_dmg_C"', 1, true) ~= nil
        and lines[3]:find('"Magnitude":2.5', 1, true) ~= nil
        and megaLog[#megaLog]:match("1 assets %(1 not loaded%), 1 ability/effect classes, 1 balancing objects") ~= nil)
    check("mega dump: referenced balancing objects dumped with their values",
        lines[4] ~= nil and lines[4]:find('"object":"/Game/Balancing/da_balancing_x.da_balancing_x"', 1, true) ~= nil
        and lines[4]:find('"BaseCD":12', 1, true) ~= nil)
end

do
-- Mega dump rules: read from a file at every dump, missing keys keep their defaults, a broken file gives the defaults.
local MegaDump = require("mega_dump")
local defaults = MegaDump.rulesOf(nil)
local rules = MegaDump.rulesOf('return { objects = { "." }, skip = { "bad_" } }')
check("mega dump rules: file overrides given keys, others keep their defaults",
    rules.objects[1] == "." and rules.skip[1] == "bad_" and rules.classes == defaults.classes and rules.globals == defaults.globals)
local fallback, problem = MegaDump.rulesOf("return { broken")
check("mega dump rules: a broken file gives the defaults and says why", fallback == defaults and problem ~= nil)
check("mega dump rules: the crashing global effects are skipped by default, the gameplay settings dumped",
    defaults.skip[1] == "bp_bge_global_" and defaults.defaults[1] == "/Script/TQ2Gameplay.Default__TQ2GameplaySettings")
end
