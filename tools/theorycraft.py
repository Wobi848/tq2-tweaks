#!/usr/bin/env python3
"""Theorycraft: damage per second of the strongest skills at level 55, best mastery partner for each.

All numbers come from the mega dump (Ctrl+F9 / command file "mega", game 0.7.1, read 21.11.2026). After a game patch,
dump again and update the tables below (skill bases from da_balancing_player_*, passives from bp_bge_player_*,
modifiers from bp_gam_*, scaling from da_tq2_player_damage_scaling_internal).

Model:
  - Unit W = SkillDmgWeak(1) at level 55. Medium = 1.25 W and Strong = 1.5 W (1 + 0.5 x ExpectedDmgScaling_Speed(55));
    PlayerSkillDmgScaling(x) is the same as Weak(x). A weapon hit is about 4.66 W.
  - Increased damage is one additive pool (items, Might, passives of both masteries at max level); "more" modifiers
    multiply. Passives that only work under conditions (melee hits, Soulburn, Overload, ...) are left out.
  - Base action time 1 s, divided by (1 + cast speed). Skills without cooldown are limited by energy regeneration.
  - "burst" assumes full Overwhelm and Flow on every cast where a modifier consumes them.
Not modelled: real animation times, crit, enemy resistances, how often Overwhelm/Flow are full.
Skills and modifiers marked GameEntitlements.Module.Masteries.WIP in the mastery data exist but are not playable
(e.g. Frost Bolt, Chain Lightning, Spectral Arc) and are left out.
"""
import argparse
from dataclasses import dataclass

ITEMS_INCREASED = 150   # same item assumption for every build (several T7 "% type damage" affixes)
MIGHT_INCREASED = 55    # 110 attribute points x 5 = 550 Might, +1 % damage per 10 Might
ITEMS_CAST_SPEED = 20
WEAPON_HIT = 4.66       # W per 100 % weapon damage

# Increased damage at max level by tag, per mastery. "all" applies to every skill.
PASSIVES = {
    "storm": [("spell", 39), ("cold", 52), ("lightning", 52), ("projectile", 15), ("projectile", 55),
              ("elemental", 36), ("all", 32), ("cold", 32), ("lightning", 32), ("lightning", 32)],
    "earth": [("spell", 52), ("fire", 52), ("physical", 39), ("spell", 16), ("attack", 32), ("elemental", 36),
              ("physical", 30), ("all", 32), ("fire", 32), ("physical", 32)],
    "forge": [("physical", 36), ("elemental", 24), ("elemental", 24), ("all", 32), ("physical", 32), ("device", 48)],
    "rogue": [("all", 24), ("all", 39), ("pierce", 54), ("poison", 54), ("vitality", 45), ("fire", 45),
              ("spell", 52), ("attack", 52), ("all", 32), ("physical", 32), ("poison", 32)],
    "spirit": [("all", 16), ("all", 20), ("elemental", 36), ("vitality", 32), ("cold", 32), ("poison", 32),
               ("all", 32), ("vitality", 32)],
    "warfare": [("attack", 39), ("physical", 52), ("melee", 45), ("projectile", 55), ("spell", 32), ("attack", 16),
                ("all", 36), ("all", 32), ("physical", 32), ("vitality", 32)],
}
CAST_SPEED = {"storm": 15, "rogue": 15}  # Raging Mind, Deft Hands
ELEMENTS = {"cold", "fire", "lightning"}


@dataclass
class Skill:
    name: str
    mastery: str
    tags: set
    single: float       # W per cast against one target
    pack: float         # W per cast summed over a pack of 5
    cooldown: float     # s, 0 = none
    energy: float       # per cast, with the chosen modifiers
    more: float         # "more" multiplier of the modifiers, always on
    burst_more: float   # with full Overwhelm/Flow
    note: str


SKILLS = [
    Skill("Ice Shards (Torrent 5, Chaos, Penetration 3, Infused Shard 5)", "storm",
          {"spell", "projectile", "cold"}, 16.8 * 1.35, 140 * 1.35, 0, 38, 1.0, 1.0, "no generic modifiers"),
    Skill("Armor Eruption (Enhanced Damage 10)", "forge",
          {"physical", "projectile"}, 36, 144, 6, 80, 2.0, 2.0, "12 projectiles, about 3 hit one target"),
    Skill("Death Nova (Enhanced Damage 10, Projectiles 2)", "spirit",
          {"spell", "vitality"}, 18.75 + 6, 18.75 * 5 + 6 * 5, 6, 30, 2.0, 2.0, "area plus 24 projectiles"),
    Skill("Scattershot (Additional Projectiles 5)", "rogue",
          {"attack", "projectile", "pierce", "physical"}, 4 * 1.5 * WEAPON_HIT, 10 * 1.5 * WEAPON_HIT, 0, 80,
          1.0, 1.0, "weapon skill, needs a ranged weapon"),
    Skill("Lethal Strike (Mark Focus 5)", "rogue",
          {"attack", "physical", "pierce"}, 30 + 3 * WEAPON_HIT, 30 + 3 * WEAPON_HIT, 5, 30, 1.75, 1.75,
          "single target"),
    Skill("Volcanic Eruption (Enhanced Damage 10)", "earth",
          {"spell", "fire", "physical"}, 28, 28 * 5, 0, 80, 2.0, 2.0, "one eruption per cast assumed"),
]


def increased(skill, masteries):
    total = ITEMS_INCREASED + MIGHT_INCREASED
    for mastery in masteries:
        for tag, value in PASSIVES[mastery]:
            if tag == "all" or tag in skill.tags or (tag == "elemental" and skill.tags & ELEMENTS):
                total += value
    return total


def casts_per_second(skill, masteries, energy_per_second):
    cast_speed = (ITEMS_CAST_SPEED + sum(CAST_SPEED.get(m, 0) for m in masteries)) / 100
    rate = 1 + cast_speed
    if skill.cooldown:
        rate = min(rate, 1 / skill.cooldown)
    return min(rate, energy_per_second / skill.energy)


def best_build(skill, energy_per_second):
    best = None
    for other in PASSIVES:
        if other == skill.mastery:
            continue
        masteries = (skill.mastery, other)
        pool = increased(skill, masteries)
        rate = casts_per_second(skill, masteries, energy_per_second)
        factor = (1 + pool / 100) * rate
        result = {"partner": other, "increased": pool, "single": factor * skill.more * skill.single,
                  "pack": factor * skill.more * skill.pack, "burst": factor * skill.burst_more * skill.single,
                  "energy": skill.energy * rate}
        if best is None or result["single"] + result["pack"] > best["single"] + best["pack"]:
            best = result
    return best


def partners(skill, energy_per_second):
    """Damage of one skill with every mastery partner, best first."""
    rows = []
    for other in PASSIVES:
        if other == skill.mastery:
            continue
        masteries = (skill.mastery, other)
        factor = (1 + increased(skill, masteries) / 100) * casts_per_second(skill, masteries, energy_per_second)
        rows.append((other, factor * skill.more * skill.single, factor * skill.more * skill.pack))
    return sorted(rows, key=lambda row: -(row[1] + row[2]))


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--energy", type=float, default=60, help="energy regeneration per second (default 60)")
    parser.add_argument("--partners", metavar="SKILL", help="show every mastery partner for skills containing SKILL")
    args = parser.parse_args()
    if args.partners:
        for skill in SKILLS:
            if args.partners.lower() in skill.name.lower():
                print(skill.name)
                for other, single, pack in partners(skill, args.energy):
                    print(f"  {skill.mastery}+{other:8} 1 target {single:6.0f}   pack {pack:6.0f}")
        return
    rows = [(skill, best_build(skill, args.energy)) for skill in SKILLS]
    rows.sort(key=lambda row: -(row[1]["single"] + row[1]["pack"]))
    print(f"Level 55, energy regeneration {args.energy:g}/s, damage per second in W")
    print(f"{'Skill':72} {'masteries':16} {'1 target':>8} {'pack':>6} {'burst':>6} {'incr%':>6} {'energy/s':>8}")
    for skill, build in rows:
        print(f"{skill.name[:72]:72} {skill.mastery + '+' + build['partner']:16} {build['single']:8.0f} "
              f"{build['pack']:6.0f} {build['burst']:6.0f} {build['increased']:6.0f} {build['energy']:8.0f}")


if __name__ == "__main__":
    main()
