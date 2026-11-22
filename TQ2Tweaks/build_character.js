// Character import, attributes and gear of the build planner (build_planner.html loads this file before its main script
// and calls these functions; they read the page's globals DATA, RULES, build, nodeById and masteryById when called).
"use strict";

const ATTRIBUTE_NAMES = ["might", "agility", "knowledge", "vigor"];
const ATTRIBUTE_LABELS = { might: "Might", agility: "Agility", knowledge: "Knowledge", vigor: "Vigor" };
const SLOT_LABELS = [[/^da_armor_head_/, "Head"], [/^da_armor_shoulder_/, "Shoulders"], [/^da_armor_torso_/, "Chest"],
  [/^da_armor_arm_/, "Arms"], [/^da_armor_leg_/, "Legs"], [/^da_jewelry_neck_/, "Amulet"], [/^da_jewelry_ring_/, "Ring"],
  [/^da_weapon_offhand_/, "Off-hand"], [/^da_weapon_/, "Weapon"]];
const RARITY_NAMES = ["Common", "Magic", "Rare", "Infrequent", "Epic", "Legendary"];

// "+12% increased Spell Damage" lines of a filled game text, as add(phrase, value) calls ("Spell Damage", 12).
function addPercentBonuses(text, add) {
  for (const line of text.split("\n").map(part => part.trim())) {
    const match = line.match(/^\+?(\d+(?:\.\d+)?)%\s+(increased .+)$/i);
    if (match) add(match[2].replace(/^increased /i, "").trim(), Number(match[1]));
  }
}

// ---- Attributes ----------------------------------------------------------------------------------------------------

const attributePointsOf = name => (build.attributes || {})[name] || 0;

function attributeBudget() {
  return { spent: ATTRIBUTE_NAMES.reduce((sum, name) => sum + attributePointsOf(name), 0),
           total: RULES.attributePerLevel * build.level };
}

// Sets the points of one attribute within the level's budget; returns why more are not possible, or null.
function setAttributePoints(name, value) {
  const current = attributePointsOf(name);
  let target = Math.max(0, value);
  if (target > current) {
    const { spent, total } = attributeBudget();
    const free = total - spent;
    if (free <= 0) return `No attribute points left at level ${build.level}.`;
    target = Math.min(target, current + free);
  }
  build.attributes = Object.assign({}, build.attributes, { [name]: target });
  if (!target) delete build.attributes[name];
  return null;
}

// Attribute values: with a loaded character the game's initial value plus what items and buffs gave in game plus the
// planned points; without one only what the points give (the initial values are not in the game data).
function attributeValues() {
  const perPoint = DATA.attributes.perPoint;
  const character = build.character;
  const values = {};
  for (const name of ATTRIBUTE_NAMES) {
    const fromPoints = perPoint * attributePointsOf(name);
    values[name] = character ? character.initial[name] + (character.extra[name] || 0) + fromPoints : fromPoints;
  }
  return values;
}

// One of the character table's formulas with the attribute values (only numbers and + - * / ( ) after filling in).
function attributeFormula(name, values) {
  const text = DATA.attributes.formulas[name];
  if (!text) return null;
  const body = text.replace(/Character\.Current(Might|Agility|Knowledge|Vigor)/g, (_, attribute) => `(${values[attribute.toLowerCase()]})`);
  if (!/^[0-9.+\-*/()\s]*$/.test(body)) return null;
  return new Function(`return ${body};`)();
}

// What the attributes give, as the game's character table computes it: [{ label, value, unit }].
function attributeEffects() {
  const values = attributeValues();
  const at = name => attributeFormula(name, values);
  const percent = value => value === null ? null : value * 100;
  const reduction = factor => factor === null ? null : (1 - factor) * 100;
  return [
    { label: "increased Damage", value: percent(at("DmgIncrease")), unit: "%" },
    { label: "increased Crit Chance", value: percent(at("CritChanceIncrease")), unit: "%" },
    { label: "Crit Damage points", value: at("CritDamagePoints"), unit: "" },
    { label: "increased Speed", value: percent(at("SpeedIncrease")), unit: "%" },
    { label: "shorter Cooldowns", value: reduction(at("CooldownFactor")), unit: "%" },
    { label: "lower Energy Cost", value: reduction(at("CostFactor")), unit: "%" },
    { label: "increased Health", value: percent(at("HPIncrease")), unit: "%" },
    { label: "Fitness", value: at("Fitness"), unit: "" },
    { label: "Cunning", value: at("Cunning"), unit: "" },
    { label: "Resolve", value: at("Resolve"), unit: "" },
  ].filter(effect => effect.value !== null);
}

// ---- Gear ----------------------------------------------------------------------------------------------------------

const equippedGear = () => ((build.character && build.character.gear) || []).filter(item => item.affixes && item.affixes.length);

function slotOf(typeName) {
  const found = SLOT_LABELS.find(([pattern]) => pattern.test(typeName || ""));
  return found ? found[1] : "Item";
}

function itemName(item) {
  if (item.customName) return item.customName;
  const words = (item.type || "?").replace(/^da_(armor|jewelry|weapon)_(head|shoulder|torso|arm|leg|neck|ring|offhand|1h|2h)_/, "")
    .split("_").filter(word => !/^(t\d|normal|unique|MI|startinggear)$/i.test(word));
  const name = words.join(" ");
  return name.charAt(0).toUpperCase() + name.slice(1);
}

// One affix of an item with its rolled values filled into the game's tooltip text.
function affixText(affix) {
  const templates = DATA.affixTexts[affix.name] || [];
  const scales = affix.scales || [];
  const filled = templates.map((template, index) => template.replace(/\{([A-Za-z]+)\}(\|fmt\(([^)]*)\))?/g, (_, name, format, options) => {
    const scale = scales[index] !== undefined ? scales[index] : scales[0];
    if (scale === undefined) return "?";
    const value = scale * (affix.multiplier || 1);
    return (/sign=true/.test(options || "") && value > 0 ? "+" : "") + formatNumber(value);
  }));
  return filled.map(text => text.trim()).filter(Boolean).join("\n");
}

// "% increased ..." of all equipped items, summed by what they increase: [{ phrase, value }].
function gearTotals() {
  const sums = new Map();
  const add = (phrase, value) => sums.set(phrase, (sums.get(phrase) || 0) + value);
  for (const item of equippedGear()) {
    for (const affix of item.affixes) addPercentBonuses(affixText(affix), add);
  }
  return [...sums.entries()].map(([phrase, value]) => ({ phrase, value })).sort((a, b) => b.value - a.value);
}

// ---- Import from the game (character.json, written by the mod with Shift+F9) ---------------------------------------

// The planner build of an exported character; unknown entries are left to sanitizeBuild.
function buildFromCharacter(character) {
  const target = emptyBuild();
  target.level = Math.max(1, Math.min(RULES.levelCap, Math.round(character.level || 1)));
  for (const mastery of character.masteries || []) {
    const id = String(mastery.id || "").replace(/^da_mastery_/, "");
    if (!masteryById[id] || target.masteries.length >= 2) continue;
    target.masteries.push(id);
    target.masteryLevel[id] = mastery.points || 0;
    for (const skill of mastery.skills || []) {
      target.points[skill.id] = skill.points;
      target.mods[skill.id] = {};
      for (const modifier of skill.modifiers || []) target.mods[skill.id][modifier.id] = modifier.level || 1;
    }
    for (const passive of mastery.passives || []) {
      target.points[passive.id] = passive.points;
      const node = nodeById[passive.id] && nodeById[passive.id].node;
      target.feats[passive.id] = node ? (passive.feats || []).map(id => node.feats.findIndex(feat => feat.id === id)).filter(i => i >= 0) : [];
    }
  }
  target.tab = target.masteries[0] || null;
  const attributes = character.attributes || {};
  target.attributes = {};
  target.character = { initial: {}, extra: {}, gear: character.equipment || [] };
  for (const name of ATTRIBUTE_NAMES) {
    const value = attributes[name] || {};
    if (value.points) target.attributes[name] = value.points;
    target.character.initial[name] = value.initial || 0;
    target.character.extra[name] = (value.current || 0) - (value.base || 0);
  }
  return target;
}

// Reads a character.json the user picked; returns the build or throws with a readable reason.
function parseCharacter(text) {
  let character;
  try {
    character = JSON.parse(text);
  } catch (error) {
    throw new Error("This is not a character.json from the mod.");
  }
  if (!character || !Array.isArray(character.masteries)) throw new Error("This file has no masteries: pick character.json.");
  return buildFromCharacter(character);
}
