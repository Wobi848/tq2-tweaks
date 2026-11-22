#!/usr/bin/env python3
"""Builds the data file of the build planner (TQ2Tweaks/build_planner.html) from the mega dump.

    python3 tools/build_data.py [path/to/mega_dump.jsonl]

Reads the masteries, their skills, modifiers, passives and feats and the mastery rules (points per level, tier costs,
capacity) from the mega dump and writes TQ2Tweaks/build_data.js. Content marked GameEntitlements...WIP in the game data
exists but is not playable and is left out. A modifier fits a skill when the skill carries every tag the modifier
requires (m_DescriptionRequiredTags), the same check the game uses to list "available modifiers".
"""
import csv
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_DUMP = ROOT / "TQ2Tweaks" / "mega_dump.jsonl"
OUTPUT = ROOT / "TQ2Tweaks" / "build_data.js"
# Skill points per capacity step, computed by the game in code (not in its data). Asked in game with the command file:
#   call TQ2MasteryActiveAbilityViewModel GetRequiredPointsForCapacity 1 2 3 5 7 9 11 13 15 17
CALL_RESULT = ROOT / "TQ2Tweaks" / "call_result.json"
# Where the game says which version ran (the dump is made in a running game) and which Steam build is installed.
GAME_LOG = Path.home() / ".steam/steam/steamapps/compatdata/1154030/pfx/drive_c/users/steamuser/AppData/Local/TQ2/Saved/Logs/TQ2.log"
STEAM_MANIFEST = Path.home() / ".steam/steam/steamapps/appmanifest_1154030.acf"
ABBREVIATIONS = [(r"\bDmg\b", "Damage"), (r"\bCS\b", "Cast Speed"), (r"\bAS\b", "Attack Speed"), (r"\bMP\b", "Energy"),
                 (r"\bCD\b", "Cooldown"), (r"\bRes\b", "Resistance"), (r"\bPerc\b", "%"), (r"\bHP\b", "Health"),
                 (r" Current$", "")]
# The game's English texts (skill, modifier and passive descriptions with {placeholders}).
TEXT_DIR = Path.home() / ".steam/steam/steamapps/common/Titan Quest II/TQ2/Content/TQ2/Data/Text/Masteries"
SETTINGS_PATH = "/Script/TQ2Gameplay.Default__TQ2GameplaySettings"
WIP = "GameEntitlements.Module.Masteries.WIP"
LEVEL_CAP = 55
SKIPPED_ATTRIBUTES = re.compile(r"(Next|2|_UI)$|^(CurrentLevel|NextLevel|ModifierLevel|ModifierMaxLevel)$")
PLAYER_ABILITY = re.compile(r"(bp_bga_player_[A-Za-z0-9_]+?)\.")


def short(path):
    return path.split("/")[-1].split(".")[0] if isinstance(path, str) else ""


def tags(obj, field):
    return [tag["TagName"] for tag in (obj or {}).get(field, {}).get("GameplayTags", [])]


def locked(obj):
    return WIP in tags(obj, "m_RequiredEntitlements")


def formulas(obj):
    data = (obj or {}).get("m_Data") or {}
    return {a["Name"]: (a.get("Formula") or {}).get("SourceText") for a in data.get("CalculatedAttributes") or []}


def evaluate(formula, level, known=None):
    """Value of a formula that only uses the level, numbers, arithmetic and already known values, else None."""
    if formula is None:
        return None
    text = re.sub(r"\b(CurrentLevel|ModifierLevel)\b", str(level), formula)
    text = re.sub(r"\bNextLevel\b", str(level + 1), text)
    for name, value in (known or {}).items():
        text = re.sub(r"\b" + re.escape(name) + r"\b", repr(value), text)
    if not re.fullmatch(r"[0-9.+\-*/() eE]+", text):
        return None
    try:
        return round(eval(text), 4)  # only digits and operators reach this point
    except (SyntaxError, ZeroDivisionError):
        return None


def values_at(formula_by_name, level):
    """All values that can be computed at a level, resolving formulas that use other values."""
    known = {}
    for _ in range(4):
        for name, formula in formula_by_name.items():
            if name not in known:
                value = evaluate(formula, level, known)
                if value is not None:
                    known[name] = value
    return known


def values_by_level(formula_by_name, max_level):
    """{name: [value at level 1 .. max]} for every value computable at all levels (the text placeholders)."""
    per_level = [values_at(formula_by_name, level) for level in range(1, max_level + 1)]
    names = set.intersection(*(set(v) for v in per_level)) if per_level else set()
    return {name: [v[name] for v in per_level] for name in sorted(names)}


def readable(name):
    words = re.sub(r"(?<=[a-z0-9])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])", " ", name.replace("_", " "))
    for pattern, replacement in ABBREVIATIONS:
        words = re.sub(pattern, replacement, words)
    return words[:1].upper() + words[1:]


def data_version(dump_path):
    """Which game the data comes from: version and build from the game log, Steam build, date of the dump."""
    version = {"dumped": datetime.fromtimestamp(dump_path.stat().st_mtime, timezone.utc).strftime("%Y-%m-%d")}
    if GAME_LOG.exists():
        log = GAME_LOG.read_text(encoding="utf-8", errors="replace")
        match = re.search(r"Set ProjectVersion to ([^ ]+?)\.? Version", log)
        if match:
            version["game"] = match.group(1)
        match = re.search(r"LogInit: Build: (\S+)", log)
        if match:
            version["build"] = match.group(1)
    if STEAM_MANIFEST.exists():
        match = re.search(r'"buildid"\s+"(\d+)"', STEAM_MANIFEST.read_text(encoding="utf-8"))
        if match:
            version["steamBuild"] = match.group(1)
    return version


def load_texts():
    """Key -> English text from the game's mastery text files (empty if the game folder is elsewhere)."""
    texts = {}
    for path in sorted(TEXT_DIR.glob("*.csv")):
        with open(path, encoding="utf-8-sig", newline="") as file:
            for row in csv.reader(file):
                if len(row) >= 2:
                    texts[row[0]] = row[1]
    return texts


def text_key(asset, kind):
    """Text key of an asset: bp_selector_player_st_iceShards -> IceShards, bp_gam_player_st_iceShards_torrent ->
    IceShards_Mod_Torrent, bp_gam_player_generic_enhancedDamage -> Generic_Mod_EnhancedDamage,
    bp_bge_player_st_passive_ragingMind_p -> RagingMind."""
    cap = lambda word: word[:1].upper() + word[1:]
    name = re.sub(r"_p$", "", asset)
    if kind == "modifier":
        parts = re.sub(r"^bp_gam_player_(generic_|[a-z]+_)", lambda m: "Generic_" if m.group(1) == "generic_" else "",
                       name).split("_")
        if parts[0] == "Generic":
            return "Generic_Mod_" + "".join(cap(p) for p in parts[1:])
        return cap(parts[0]) + "_Mod_" + "".join(cap(p) for p in parts[1:])
    name = re.sub(r"^bp_(selector|bga|bge)_player_[a-z]+_(passive_)?", "", name)
    return cap(name.split("_")[0])


def plain(text):
    """Game text with the escapes of the text files resolved."""
    return (text or "").replace("\\'", "'").replace('\\"', '"')


def template(text):
    """Description with markup removed; {placeholders} stay for the page to fill in."""
    text = (re.sub(r"<[^>]*>", "", text or "").replace("\\r", "").replace("\r", "").replace("\\n", "\n")
            .replace("\\'", "'"))
    text = re.sub(r"\{DescriptionComponent\[[^\]]*\]\}\n?", "", text)
    text = re.sub(r"\{AbilityDamage\[[^\]]*\]\}", "{damage}", text)
    text = re.sub(r"\{([A-Za-z0-9_.]+)\}\|[a-z_]+(\([^)]*\))?", r"{\1}", text)
    return re.sub(r"\n{3,}", "\n\n", text).strip()


def describe(texts, key, fallback):
    return template(texts.get(key + "_1Description") or fallback)


def shown_values(formula_by_name, max_level):
    """Values listed under a passive or modifier: [{label, values}] without helper and UI-only values."""
    return [{"label": readable(name), "values": values}
            for name, values in values_by_level(formula_by_name, max_level).items()
            if not SKIPPED_ATTRIBUTES.search(name) and not (len(set(values)) == 1 and values[0] in (0, 1))]


def load_dump(path):
    classes, objects, masteries, settings = {}, {}, {}, None
    with open(path, encoding="utf-8") as dump:
        for line in dump:
            record = json.loads(line)
            if "classDefault" in record:
                classes[short(record["classDefault"])] = record["data"]
            elif "object" in record:
                if record["object"] == SETTINGS_PATH:
                    settings = record["data"]
                objects[short(record["object"])] = record["data"]
            elif record.get("class", "").endswith("TQ2MasteryDescription"):
                masteries[short(record["path"])] = record.get("data")
    return classes, objects, masteries, settings


def ability_variants(selector, classes):
    """The player abilities behind a skill (a selector lists its variants; a plain ability is its own variant)."""
    names = sorted(set(PLAYER_ABILITY.findall(json.dumps(classes.get(selector) or {}))))
    return [classes[n] for n in names if n in classes] or ([classes[selector]] if selector in classes else [])


def balancing_values(variant, objects):
    values = {}
    for provider in (variant.get("m_Data") or {}).get("Context", {}).get("Providers", []):
        reference = provider.get("pObject") or ""
        if provider.get("Type") == 0 and "balancing_player" in reference:
            values.update({k: v for k, v in formulas(objects.get(short(reference))).items() if v})
    return values


def skill_entry(description, classes, objects, texts):
    selector = short(description["pAbility"])
    variants = ability_variants(selector, classes)
    # The skill (selector) carries its own description tag, which skill-specific modifiers ask for.
    skill_tags, values = {"GrimAbilitySystem.Description." + selector}, {}
    skill_tags.update(tags(classes.get(selector), "m_AdditionalSelectionTags"))
    for variant in variants:
        skill_tags.update(tags(variant, "m_AbilityTags"))
        values.update(balancing_values(variant, objects))
    key = text_key(selector, "skill")
    name = plain(texts.get(key + "_0Name") or next((v.get("m_Name") for v in variants if v.get("m_Name")), selector))
    fallback = next((v.get("m_Description") for v in variants if v.get("m_Description")), "")
    flags = sorted({t.split("AbilityFlag.")[-1] for t in skill_tags if ".AbilityFlag." in t and ".Tier." not in t
                    and ".Mastery." not in t})
    numbers = values_at(values, 1)
    return {"id": selector, "name": name, "flags": flags, "tags": sorted(skill_tags),
            "text": describe(texts, key, fallback), "values": {k: [v] for k, v in numbers.items()},
            "cost": numbers.get("BaseMPCost") or numbers.get("MPCostBase") or numbers.get("BaseCost")
            or numbers.get("MPCost"),
            "cooldown": numbers.get("BaseCD") or numbers.get("CD"),
            "reservation": numbers.get("MPReservation")}


def modifier_entry(name, obj, texts):
    max_level = int(obj.get("m_MaxLevel") or 1)
    formula_by_name = formulas(obj)
    key = text_key(name, "modifier")
    return {"id": name, "name": plain(texts.get(key + "_0Name") or obj.get("m_Name") or name),
            "capacity": obj.get("m_RequiredCapacity") or 0, "max": max_level,
            "requires": tags(obj, "m_DescriptionRequiredTags"),
            "blocks": [t.split(".")[-1] for t in tags(obj, "m_ModifierBlockedTags")],
            "text": describe(texts, key, obj.get("m_Description")),
            "values": values_by_level(formula_by_name, max_level)}


def passive_entry(description, classes, texts):
    asset = short(description.get("m_pPassiveAbility"))
    main = classes.get(asset) or {}
    max_level = int(description.get("m_MaxLevel") or 1)
    key = text_key(asset, "passive")
    feats = []
    for feat in description.get("m_SelectableFeatsNew") or []:
        effect = classes.get(short(feat.get("m_pMainEffect"))) or {}
        if effect.get("m_Name"):
            feat_values = values_at(formulas(effect), 1)
            feats.append({"name": plain(effect["m_Name"]), "text": template(effect.get("m_Description")),
                          "values": {k: [v] for k, v in feat_values.items()},
                          "levels": shown_values(formulas(effect), 1)})
    formula_by_name = formulas(main)
    return {"id": asset, "name": plain(texts.get(key + "_0Name") or main.get("m_Name") or "?"), "max": max_level,
            "text": describe(texts, key, main.get("m_Description")),
            "values": values_by_level(formula_by_name, max_level),
            "levels": shown_values(formula_by_name, max_level), "feats": feats}


def srgb(color):
    """Linear game colour {R, G, B} as #rrggbb."""
    def channel(value):
        value = max(0.0, min(1.0, value))
        value = value * 12.92 if value <= 0.0031308 else 1.055 * value ** (1 / 2.4) - 0.055
        return round(value * 255)
    return "#%02x%02x%02x" % tuple(channel((color or {}).get(c, 0)) for c in ("R", "G", "B"))


def capacity_points(capacities):
    """Skill points needed for each capacity step from the game's answer in call_result.json, or None."""
    if not CALL_RESULT.exists():
        return None
    result = json.loads(CALL_RESULT.read_text(encoding="utf-8"))
    if result.get("function") != "GetRequiredPointsForCapacity":
        return None
    by_capacity = {r.get("argument"): r.get("value") for r in result.get("results", [])}
    points = [by_capacity.get(capacity) for capacity in capacities]
    return points if all(isinstance(p, (int, float)) for p in points) else None


def build(path):
    classes, objects, masteries, settings = load_dump(path)
    texts = load_texts()
    if settings is None:
        sys.exit("The dump has no gameplay settings: dump again with the current mod (mega_dump_rules.lua defaults).")
    # The modifiers the masteries list plus every generic one (the generic summon modifiers are missing from the lists);
    # which skill may take one is decided by its required tags below.
    listed = {short(reference) for mastery in masteries.values() if mastery
              for tier in mastery["m_Tiers"] for reference in tier["fields"]["m_SelectableModifiers"]}
    modifiers = {name: modifier_entry(name, obj, texts) for name, obj in classes.items()
                 if (name in listed or name.startswith("bp_gam_player_generic_")) and not locked(obj)}
    mastery_list = []
    for key, mastery in sorted(masteries.items()):
        if "nomastery" in key or not mastery or locked(mastery):
            continue
        tiers = []
        for tier in mastery["m_Tiers"]:
            fields = tier["fields"]
            actives = [skill_entry(a["fields"], classes, objects, texts) for a in fields["m_ActiveAbilities"]
                       if not locked(a["fields"]) and "cheat" not in a["fields"]["pAbility"]]
            passives = [passive_entry(p["fields"], classes, texts) for p in fields["m_PassiveAbilities"]
                        if not locked(p["fields"])]
            tiers.append({"actives": actives, "passives": passives})
        mastery_list.append({"id": key.replace("da_mastery_", ""), "name": mastery.get("m_Title"),
                             "slogan": mastery.get("m_Slogan"), "description": mastery.get("m_Description"),
                             "color": srgb(mastery.get("m_Color")), "accent": srgb(mastery.get("m_SecondaryAccentColor")),
                             "tiers": tiers})
    for mastery in mastery_list:
        for tier in mastery["tiers"]:
            for skill in tier["actives"]:
                owned = set(skill.pop("tags"))
                skill["modifiers"] = [m["id"] for m in modifiers.values() if m["requires"] and set(m["requires"]) <= owned]
    used = {mod for mastery in mastery_list for tier in mastery["tiers"] for skill in tier["actives"] for mod in skill["modifiers"]}
    modifiers = {name: modifier for name, modifier in modifiers.items() if name in used}
    for modifier in modifiers.values():
        modifier.pop("requires")
    tier_costs, total = [], 0
    for cost in settings["m_MasteryTierPointCost"]:
        total += cost
        tier_costs.append(total)
    return {
        "version": data_version(Path(path)),
        "rules": {"levelCap": LEVEL_CAP, "activePerLevel": settings["m_ActivePointsPerLevel"],
                  "passivePerLevel": settings["m_PassivePointsPerLevel"], "attributePerLevel": settings["m_APperLevel"],
                  "masteryPerLevel": settings["m_MasteryPointPerLevel"], "masteryFromLevel": settings["m_MasteryPointMinLevel"],
                  "tierThresholds": tier_costs, "capacity": settings["m_MasteryCapacity"],
                  "capacityPoints": capacity_points(settings["m_MasteryCapacity"]),
                  "capacityBonusMax": settings["m_MasteryActiveCapacityBuffMax"],
                  "maxModifiers": settings["m_MasteryMaxModifiersPerActive"],
                  "featUnlock": settings["m_MasteryFeatUnlockPercentages"]},
        "masteries": mastery_list,
        "modifiers": modifiers,
    }


def main():
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_DUMP
    data = build(path)
    OUTPUT.write_text("window.TQ2_BUILD_DATA = " + json.dumps(data, separators=(",", ":")) + ";\n", encoding="utf-8")
    skills = sum(len(t["actives"]) for m in data["masteries"] for t in m["tiers"])
    print(f"{OUTPUT}: {len(data['masteries'])} masteries, {skills} skills, {len(data['modifiers'])} modifiers, "
          f"game {data['version'].get('game', '?')} (dumped {data['version']['dumped']})")


if __name__ == "__main__":
    main()
