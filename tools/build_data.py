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
# The game's answer to "call TQ2MasteryActiveAbilityViewModel GetRequiredPointsForCapacity 1 2 3 4 5 6 7 8 9 10" (command
# file, skill window open), used to check the capacity rule read from the data.
CALL_RESULT = ROOT / "TQ2Tweaks" / "call_result.json"
# Affix dump (Shift+F9 in game): the random item affixes with their tooltip texts, for the planner's loot filter.
AFFIX_DUMP = ROOT / "TQ2Tweaks" / "affix_dump.txt"
# Random affixes the loot filter cannot use: potion affixes and leftovers of the game's tests.
SKIPPED_AFFIXES = re.compile(r"Potion|shipcopy|_debug|Unique", re.I)
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
    if selector.startswith("bp_bga_"):
        return [classes[selector]] if selector in classes else []
    names = sorted(set(PLAYER_ABILITY.findall(json.dumps(classes.get(selector) or {}))))
    return [classes[n] for n in names if n in classes] or ([classes[selector]] if selector in classes else [])


def default_variant(selector, classes, variants):
    """The variant a skill has without modifiers: the selector's description that needs no tag to be active (variants
    that modifiers switch on require the modifier's tag), else its sustained description, else the first variant."""
    selector_data = classes.get(selector) or {}
    for description in selector_data.get("m_Descriptions") or []:
        if not tags(description, "m_ActivationRequiredTags") and description.get("m_Description"):
            return classes.get(short(description["m_Description"])) or {}
    sustained = (selector_data.get("m_SustainedDescription") or {}).get("m_Description")
    return classes.get(short(sustained)) or (variants[0] if variants else {})


def balancing_values(variant, objects):
    values = {}
    for provider in (variant.get("m_Data") or {}).get("Context", {}).get("Providers", []):
        reference = provider.get("pObject") or ""
        # The skill's own balancing data (da_balancing_player_*, bp_balancing_*), not the shared templates.
        if provider.get("Type") == 0 and "balancing" in reference.lower() and "_base_" not in reference:
            values.update({k: v for k, v in formulas(objects.get(short(reference))).items() if v})
    return values


def flags_of(ability_tags):
    """What a skill is (Spell, Projectile, Type.Cold, WeaponAttack.Ranged, ...) from its ability tags."""
    return sorted({t.split("AbilityFlag.")[-1] for t in ability_tags if ".AbilityFlag." in t and ".Tier." not in t
                   and ".Mastery." not in t})


UNLOCK_TAG = "GrimAbilitySystem.GameplayEffect."


def variant_switches(selector, classes):
    """Variants a modifier turns on: the selector's descriptions that need a gameplay effect (the modifier grants it,
    e.g. Shadow Dagger grants bp_bge_..._shadowDagger_unlock and Trick Shot becomes a spell): [{unlock, flags}]."""
    switches = []
    for description in (classes.get(selector) or {}).get("m_Descriptions") or []:
        needed = [t[len(UNLOCK_TAG):] for t in tags(description, "m_ActivationRequiredTags") if t.startswith(UNLOCK_TAG)]
        variant = classes.get(short(description.get("m_Description")))
        if len(needed) == 1 and variant:
            switches.append({"unlock": needed[0], "flags": flags_of(tags(variant, "m_AbilityTags"))})
    return switches


GRANTED_EFFECT = re.compile(r'"GameplayEffect": "[^"]*/(bp_bge_[A-Za-z0-9_]+)\.')


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
    # Flags (Spell, Projectile, Type.Cold, ...) of the variant the skill has without modifiers: variants that a modifier
    # turns on (e.g. Lightning Bolt as a weapon attack) must not change what the skill is.
    own_tags = tags(default_variant(selector, classes, variants), "m_AbilityTags") or sorted(skill_tags)
    flags = flags_of(own_tags)
    numbers = values_at(values, 1)
    return {"id": selector, "name": name, "flags": flags, "tags": sorted(skill_tags),
            "text": describe(texts, key, fallback), "values": {k: [v] for k, v in numbers.items()},
            "cost": numbers.get("BaseMPCost") or numbers.get("MPCostBase") or numbers.get("BaseCost")
            or numbers.get("MPCost") or numbers.get("Cost") or numbers.get("BaseCostMP") or numbers.get("BaseCostEnergy"),
            "cooldown": numbers.get("BaseCD") or numbers.get("CD"),
            "reservation": numbers.get("MPReservation"),
            "damage": damage_parts(values, numbers),
            "switches": variant_switches(selector, classes)}


def modifier_entry(name, obj, texts):
    max_level = int(obj.get("m_MaxLevel") or 1)
    formula_by_name = formulas(obj)
    key = text_key(name, "modifier")
    return {"id": name, "name": plain(texts.get(key + "_0Name") or obj.get("m_Name") or name),
            "capacity": obj.get("m_RequiredCapacity") or 0, "max": max_level,
            "requires": tags(obj, "m_DescriptionRequiredTags"),
            "blocks": [t.split(".")[-1] for t in tags(obj, "m_ModifierBlockedTags")],
            "text": describe(texts, key, obj.get("m_Description")),
            "values": values_by_level(formula_by_name, max_level),
            "grants": sorted(set(GRANTED_EFFECT.findall(json.dumps(obj))))}


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
            feats.append({"id": short(feat.get("m_pMainEffect")), "name": plain(effect["m_Name"]),
                          "text": template(effect.get("m_Description")),
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


# Damage formulas of skills: [factor *] <scaling function>[(argument[, level])]. The page computes the scaling at the
# chosen character level (weak, medium, strong; weapon skills scale with weapon damage).
DAMAGE_CALL = re.compile(r"^(?:([0-9.]+)\s*\*\s*)?(PlayerDmgScaling\.PlayerSkillDmgScaling|PlayerDamageScaling\.SkillDmg(Weak|Medium|Strong)"
                         r"_LevelScalingFactor|PlayerDamageScaling\.WeaponSkillDmgStrong_LevelScalingFactor|SummonDamageScaling"
                         r"\.SkillDmg(Weak|Medium|Strong)_LevelScalingFactor)(?:\(([^,()]+)(?:,[^()]*)?\))?$")
DAMAGE_TYPES = {"Strike": "Strike", "Pierce": "Pierce", "Fire": "Fire", "Cold": "Cold", "Light": "Lightning",
                "Lightning": "Lightning", "Poison": "Poison", "Vit": "Vitality", "Vitality": "Vitality"}


def damage_parts(formula_by_name, numbers):
    """Damage lines of a skill: [{label, type, scale, min, max}] with scale weak/medium/strong/weapon/summon and the
    factor of the scaling function (multiplied by the level scaling in the page)."""
    found = {}
    for name, formula in formula_by_name.items():
        if not re.search(r"Dmg|Damage", name) or not formula:
            continue
        match = DAMAGE_CALL.match(formula.strip())
        if not match:
            continue
        factor, function, strength, summon_strength, argument = match.groups()
        if argument is None:
            amount = 1.0
        else:
            # The data mixes spellings (Damage=...(BaseDMG) next to BaseDmg=16).
            by_lower = {k.lower(): v for k, v in numbers.items()}
            argument = argument.strip()
            amount = evaluate(argument, 1, numbers)
            if amount is None and argument.lower() in by_lower:
                amount = by_lower[argument.lower()]
            if amount is None:
                continue
        amount *= float(factor or 1)
        if "WeaponSkill" in function:
            scale = "weapon"
        elif function.startswith("SummonDamageScaling"):
            scale = "summon"
        else:
            scale = (strength or "Weak").lower()
        base = re.sub(r"(Min|Max)(?=Dmg|Damage)|(?<=Dmg|age)(Min|Max)", "", name)
        kind = "max" if re.search(r"Max(Dmg|Damage)|(Dmg|Damage)Max", name) else "min" if re.search(
            r"Min(Dmg|Damage)|(Dmg|Damage)Min", name) else "both"
        entry = found.setdefault(base, {"label": readable(base), "scale": scale, "min": None, "max": None, "names": {},
                                        "type": next((t for k, t in DAMAGE_TYPES.items() if base.startswith(k)), None)})
        entry["names"][name] = amount
        if kind in ("min", "both"):
            entry["min"] = amount
        if kind in ("max", "both"):
            entry["max"] = amount
    parts = []
    for entry in found.values():
        entry["min"] = entry["min"] if entry["min"] is not None else entry["max"]
        entry["max"] = entry["max"] if entry["max"] is not None else entry["min"]
        parts.append(entry)
    return parts


def damage_scaling(objects):
    """Constants of the level scaling of skill damage, read from the game's tables (the page computes
    WeaponDamageScaling, the flat factor and the speed factor from them, see build_planner.html)."""
    weapon = {k: evaluate(v, 1) for k, v in formulas(objects.get("da_tq2_item_WeaponDamageScaling")).items()}
    internal = formulas(objects.get("da_tq2_player_damage_scaling_internal"))
    return {"baseDamage": weapon.get("BaseDamage"), "offset": weapon.get("Offset"), "linear": weapon.get("LinearPart"),
            "expo": weapon.get("ExpoPart"), "expoBase": weapon.get("ExponentBase"),
            "flatFormula": internal.get("PlayerFlatFactor_Items"), "speedFormula": internal.get("ExpectedDmgScaling_Speed")}


def attribute_formulas(objects):
    """The character table's formulas of what the attributes give (DmgIncrease = Character.CurrentMight /10 /100, ...)
    and the attribute gain per point; the page evaluates them with the character's values."""
    table = formulas(objects.get("da_tq2_character_table"))
    names = ["DmgIncrease", "SpeedIncrease", "CooldownFactor", "CostFactor", "HPIncrease", "CritChanceIncrease",
             "CritDamagePoints", "Fitness", "Cunning", "Resolve"]
    return {"perPoint": evaluate(table.get("AttributeIncreasePerPoint"), 1),
            "formulas": {name: table[name] for name in names if table.get(name)}}


def affix_texts():
    """Tooltip templates of every affix in the affix dump (random, implicit and base): name -> one text per effect,
    with the game's {Value}|fmt(...) placeholders for the page to fill with the item's rolled values."""
    if not AFFIX_DUMP.exists():
        return {}
    texts, current, lines = {}, None, []
    def finish():
        if current and lines:
            joined = "\n".join(line for line in lines if line.strip())
            texts[current] = [part.strip() for part in re.split(r"\s*\|\s*\[\d+\]\s*", joined)]
    # A text with line breaks goes on over the next lines (the game's \r\r\n reads as an empty line in between).
    for line in AFFIX_DUMP.read_text(encoding="utf-8").splitlines():
        if re.match(r"^[A-Z ]+ \(\d+", line) and texts:
            break  # the next section of the dump (GROUND ITEMS, AFFIX POOLS)
        header = re.match(r"^(da_\S+)\s+type=", line)
        level = re.match(r'^\s+L\d+ "[^"]*" adjective "[^"]*": \[\d+\] ?(.*)$', line)
        if header:
            finish()
            current, lines = header.group(1), []
        elif level:
            if not lines and level.group(1).strip():
                lines = [level.group(1)]
            elif lines:
                finish()
                current = None
        elif current and lines and not line.startswith(" "):
            lines.append(line)
        elif not line.startswith(" "):
            finish()
            current = None
    finish()
    return texts


def random_affixes():
    """Random prefixes and suffixes from the affix dump: [{name, kind, text}] with the first tooltip text."""
    if not AFFIX_DUMP.exists():
        return []
    affixes, current = [], None
    for line in AFFIX_DUMP.read_text(encoding="utf-8").splitlines():
        header = re.match(r"^(da_(prefix|suffix)_\S+)\s+type=", line)
        if header:
            current = None
            if not SKIPPED_AFFIXES.search(header.group(1)):
                current = {"name": header.group(1), "kind": header.group(2), "text": ""}
                affixes.append(current)
            continue
        level = re.match(r'^\s+L\d+ "[^"]*" adjective "[^"]*": \[\d+\] (.+)$', line)
        if current is not None and level and not current["text"]:
            text = re.sub(r"\{([A-Za-z]+)\}(\|[a-z_]+\([^)]*\))?", "X", level.group(1)).strip()
            current["text"] = re.sub(r"\s*\|\s*\[\d+\]\s*", " · ", text)
        elif not line.startswith(" "):
            current = None
    return [a for a in affixes if a["text"]]


def capacity_points(mastery_capacity):
    """Skill points a skill needs for capacity 1, 2, ...: m_MasteryCapacity lists them (1, 2, 3, 5, ..., 17), so 17
    points give capacity 10. Seen in game on 22.11.2026 (Trick Shot: 17 points, 10 capacity; Ice Shards: 4 points, 3).
    GetRequiredPointsForCapacity(c) answers the points needed beyond capacity c (2, 3, 5, ..., 17, then 0); a newer
    answer in call_result.json is compared."""
    points = list(mastery_capacity)
    if CALL_RESULT.exists():
        result = json.loads(CALL_RESULT.read_text(encoding="utf-8"))
        if result.get("function") == "GetRequiredPointsForCapacity":
            for entry in result.get("results", []):
                capacity, value = entry.get("argument"), entry.get("value")
                if isinstance(capacity, int) and value and capacity < len(points) and points[capacity] != value:
                    print(f"Warning: the game says capacity {capacity + 1} needs {value} points, the data says "
                          f"{points[capacity]}")
    return points


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
        "damageScaling": damage_scaling(objects),
        "rules": {"levelCap": LEVEL_CAP, "activePerLevel": settings["m_ActivePointsPerLevel"],
                  "passivePerLevel": settings["m_PassivePointsPerLevel"], "attributePerLevel": settings["m_APperLevel"],
                  "masteryPerLevel": settings["m_MasteryPointPerLevel"], "masteryFromLevel": settings["m_MasteryPointMinLevel"],
                  "tierThresholds": tier_costs,
                  "capacityPoints": capacity_points(settings["m_MasteryCapacity"]),
                  "capacityBonusMax": settings["m_MasteryActiveCapacityBuffMax"],
                  "maxModifiers": settings["m_MasteryMaxModifiersPerActive"],
                  "featUnlock": settings["m_MasteryFeatUnlockPercentages"]},
        "masteries": mastery_list,
        "modifiers": modifiers,
        "affixes": random_affixes(),
        "affixTexts": affix_texts(),
        "attributes": attribute_formulas(objects),
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
