-- Tests: Damage meter, damage hook and the damage panels.
-- Run all tests with: lua5.4 tests/test_tq2tweaks.lua

local T = require("support")
local game, check, last, tagNamed = T.game, T.check, T.last, T.tagNamed
local text = T.text

local DamageMeterWidget = require("damage_meter_widget")
check("number format 1234 / 12.3k / 1.23M", DamageMeterWidget.formatNumber(1234) == "1234"
    and DamageMeterWidget.formatNumber(12345) == "12.3k" and DamageMeterWidget.formatNumber(1234567) == "1.23M")
local DamageMeter = require("damage_meter")
local meter = DamageMeter.new(5, 10)
DamageMeter.record(meter, 0, 100, false)
DamageMeter.record(meter, 4, 100, false)
check("DPS over the actual span at the start (200 in 4 s = 50)", DamageMeter.summary(meter, 4).dps == 50)
check("DPS only within the 5 s window (at 8 s: 100 / 5 = 20)", DamageMeter.summary(meter, 8).dps == 20)
DamageMeter.record(meter, 30, 40, true)
local fresh = DamageMeter.summary(meter, 30)
check("new fight after a 10 s pause", fresh.total == 40 and fresh.hits == 1 and fresh.crits == 1)
local typed = DamageMeter.new(5, 10, 30)
DamageMeter.record(typed, 100.2, 300, false, "Fire")
DamageMeter.record(typed, 101.5, 100, false, "Cold")
DamageMeter.record(typed, 101.7, 100, true, nil)
local typedSummary = DamageMeter.summary(typed, 102)
check("graph: 30 seconds, damage per second (second 100: 300, 101: 200, 102: 0)", #typedSummary.graph == 30
    and typedSummary.graph[28] == 300 and typedSummary.graph[29] == 200 and typedSummary.graph[30] == 0)
check("damage types: shares, largest first, unknown = Other", typedSummary.types[1].name == "Fire"
    and math.abs(typedSummary.types[1].share - 0.6) < 1e-9 and #typedSummary.types == 3)
check("running fight not ended", typedSummary.ended == false)
check("after 10 s without hits: last fight with average DPS", DamageMeter.summary(typed, 115).ended == true
    and math.abs(DamageMeter.summary(typed, 115).averageDps - 500 / 1.5) < 1e-9)
DamageMeter.reset(typed)
check("reset clears the meter", DamageMeter.summary(typed, 116) == nil)
check("text after the fight", DamageMeterWidget.lines({ ended = true, averageDps = 500, dps = 0, total = 500, duration = 1.5,
    hits = 3, crits = 1, highestHit = 300 })[1] == "DAMAGE  ·  last fight")
local DamageHook = require("damage_hook")
local DamageDetailWidget = require("damage_detail_widget")
check("damage type name from the tag", DamageHook.typeName(tagNamed("Damage.Type.VitalityDrain")) == "Vitality Drain"
    and DamageHook.typeName(tagNamed("Damage.Type.Cold")) == "Cold" and DamageHook.typeName(tagNamed("None")) == nil)
local function skillOf(description)
    return DamageHook.skillName({ "GrimAbilitySystem.Ability.AbilityFlag.Mastery.Spirit",
        "GrimAbilitySystem.Description." .. description })
end
check("skill from the description tag (as logged in game)",
    skillOf("bp_bga_player_sp_lich_m_soulBlight") == "Lich" and skillOf("bp_bga_player_sp_lich_basicAttack") == "Lich"
    and skillOf("bp_bga_player_sp_eidolonGuard_basicAttack_melee") == "Eidolon Guard"
    and skillOf("bp_bga_player_fo_automaton_m_coldAttachment_activation") == "Automaton"
    and skillOf("bp_bga_global_retaliation_p") == "Retaliation"
    and skillOf("bp_bga_player_sp_eidolonGuard_summon") == "Eidolon Guard"
    and DamageHook.skillName({ "GrimAbilitySystem.Ability.AbilityFlag.Skill" }) == nil)
local function playerAbility(description)
    return DamageHook.isPlayerAbility({ "GrimAbilitySystem.Description." .. description })
end
check("enemy hits on summons do not count (as logged in game)",
    playerAbility("bp_bga_player_fo_automaton_basicAttack") and playerAbility("bp_bga_global_retaliation_p")
    and DamageHook.isPlayerAbility({}) and not playerAbility("bp_bga_un_skeleton_archer_rangedAttack")
    and not playerAbility("bp_bga_wl_boar_charge"))
local skilled = DamageMeter.new(5, 10, 30)
DamageMeter.record(skilled, 1, 300, false, "Fire", "Lich")
DamageMeter.record(skilled, 1.5, 100, false, "Cold", nil)
local skillSummary = DamageMeter.summary(skilled, 2)
check("damage per skill: share of the total, hits without a skill under Other", #skillSummary.skills == 2
    and skillSummary.skills[1].name == "Lich" and math.abs(skillSummary.skills[1].share - 0.75) < 1e-9
    and skillSummary.skills[2].name == "Other")

local detailed = DamageMeter.new(5, 10, 60)
check("details before the first hit: empty, window says 'no fight yet'",
    DamageMeter.details(detailed, 0, 60).total == 0 and #DamageMeter.details(detailed, 0, 60).graph == 60
    and DamageDetailWidget.title(DamageMeter.details(detailed, 0, 60)):match("no fight yet") ~= nil)
DamageMeter.record(detailed, 10.1, 100, true, "Cold", "Lich")
DamageMeter.record(detailed, 10.5, 300, false, "Cold", "Lich")
DamageMeter.record(detailed, 11.2, 200, false, "Poison", "Automaton")
DamageMeter.record(detailed, 14.1, 400, false, "Cold", "Automaton")
local details = DamageMeter.details(detailed, 15, 60)
local lich, automaton = details.skills[2], details.skills[1]
check("details: best second, average over the fight's duration", details.peakDps == 400 and details.total == 1000
    and math.abs(details.averageDps - 1000 / 4) < 1e-9 and details.ended == false)
check("details per skill: damage, DPS, hits, crit rate, highest hit",
    automaton.name == "Automaton" and automaton.damage == 600 and lich.name == "Lich" and lich.damage == 400
    and lich.hits == 2 and lich.critShare == 0.5 and lich.highest == 300 and math.abs(lich.dps - 100) < 1e-9
    and math.abs(lich.share - 0.4) < 1e-9)
check("details: all damage types with damage", #details.types == 2 and details.types[1].name == "Cold"
    and details.types[1].damage == 800)
local lastSeconds = { details.graph[55], details.graph[56], details.graph[59] }
check("detail graph: seconds with damage per skill (for the stacked bars)", #details.graph == 60
    and lastSeconds[1].total == 400 and lastSeconds[1].bySkill.Lich == 400 and lastSeconds[2].bySkill.Automaton == 200
    and lastSeconds[3].total == 400)
check("detail table row", table.concat(DamageDetailWidget.skillCells(lich), "|") == "Lich|400|100|40%|2|50%|300")
local frozen = DamageMeter.details(detailed, 40, 60)
check("after the fight the graph ends at the last hit instead of scrolling on", frozen.ended == true
    and frozen.graph[60].total == 400 and frozen.graph[57].bySkill.Automaton == 200
    and DamageMeter.summary(detailed, 40, 30).graph[30] == 400)
check("compact graph stays 30 s long with 60 s of history", #DamageMeter.summary(detailed, 15, 30).graph == 30)
check("colour of the damage type", DamageMeterWidget.typeColor(require("config"), "Fire").R == 1.0
    and DamageMeterWidget.typeColor(require("config"), "Mystery") == require("config").DamageTypeDefaultColor)
