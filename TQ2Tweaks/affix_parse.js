// Reading the affix dump (affix_dump.txt, written in game with F9) for the browser pages: loot_filter.html and
// tools/game_data.html. parseDump(text) returns the affixes with kind, name parts (titles), effect texts and how often
// they were seen on the ground.
"use strict";

// Kind from the affix type (0 prefix, 1 suffix, else special/unique); base affixes of an item type are "implicit".
function kindOf(name, type) {
  if (name.startsWith("da_implicit_")) return "Base";
  return { "0": "Prefix", "1": "Suffix" }[type] || "Unique";
}

// "{value}|fmt(sign=true,perc100)" and "{Value}" become "X"; "[0] " effect markers are dropped.
function cleanEffect(text) {
  return text.replace(/\{[^}]*\}(\|fmt\([^)]*\))?/g, "X").replace(/^\[\d+\]\s*/, "").trim();
}

// For affixes without an effect text: the stat part of the asset name ("da_affix_SummonIncreasedHealth" ->
// "Summon Increased Health").
function effectFromName(name) {
  return name.replace(/^da_[a-z]+_(\d+_)?/, "").replace(/_/g, " ").replace(/([a-z])([A-Z])/g, "$1 $2").trim();
}

// Lines of the dump; a line that starts neither an affix nor a level continues the previous one (texts may
// contain line breaks).
function joinedLines(text) {
  const lines = [];
  for (const line of text.split(/\r?\n/)) {
    const starts = /^(da_|  L\d+ |AFFIXES|GROUND ITEMS|$)/.test(line) || /^\S+  rarity=/.test(line);
    if (starts || lines.length === 0) lines.push(line); else lines[lines.length - 1] += " " + line.trim();
  }
  return lines;
}

function parseDump(text) {
  const result = [], seenOnGround = {};
  let current = null, ground = false;
  for (const line of joinedLines(text)) {
    if (line.startsWith("GROUND ITEMS")) { ground = true; continue; }
    if (ground) {
      for (const match of line.matchAll(/(da_\S+) L\d+/g)) seenOnGround[match[1]] = (seenOnGround[match[1]] || 0) + 1;
      continue;
    }
    const head = line.match(/^(da_\S+)  type=(\S+)  tags=/);
    if (head) {
      current = { name: head[1], kind: kindOf(head[1], head[2]), titles: [], effects: [] };
      result.push(current);
      continue;
    }
    const level = line.match(/^  L\d+ "(.*?)" adjective "(.*?)": ?(.*)$/);
    if (level && current) {
      const title = level[1].trim();
      if (title && !current.titles.includes(title)) current.titles.push(title);
      for (const part of level[3].split(" | ")) {
        const effect = cleanEffect(part);
        if (effect && !current.effects.includes(effect)) current.effects.push(effect);
      }
    }
  }
  for (const affix of result) {
    affix.seen = seenOnGround[affix.name] || 0;
    // Tiered affixes repeat their text per tier ("… Tier 1 …", "… Tier 2 …"): show the first text and how many follow.
    const extra = affix.effects.length - 1;
    affix.effect = affix.effects.length ? affix.effects[0] + (extra > 0 ? ` (+${extra} more)` : "") : effectFromName(affix.name);
    affix.label = affix.titles.length ? affix.titles.join(" / ") : effectFromName(affix.name);
    affix.searchText = (affix.name + " " + affix.titles.join(" ") + " " + affix.effects.join(" ") + " " + affix.effect).toLowerCase();
  }
  return result.sort((a, b) => b.seen - a.seen || a.kind.localeCompare(b.kind) || a.label.localeCompare(b.label));
}
