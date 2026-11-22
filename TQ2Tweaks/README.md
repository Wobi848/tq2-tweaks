# TQ2 Tweaks – shade display, rewards, speed, points, crafting and a damage meter for Titan Quest II

Shows the **shades of the Spirit mastery** large and clearly below your character, instead of only small at the
resource orb in the bottom right:

- one bar per shade: full shades in teal, the next one fills up in gold with the regeneration progress
- large numbers below, e.g. `2/3 · 20%` (shades / maximum · progress to the next one)

For characters without the Spirit mastery and during cutscenes the display stays hidden. It never catches mouse
clicks.

On top of that, an in-game menu (F5) offers gameplay tweaks, auto pickup and a damage meter (see below).

Built for Titan Quest II Early Access **0.7.1**. **Single player only.**

## Requirement: UE4SS

TQ2 Tweaks is a Lua mod and needs **UE4SS for TQ2** from Nexus Mods (not included here):
<https://www.nexusmods.com/titanquest2/mods/77>

Download the normal version, not the DEV version. The general UE4SS release from GitHub crashes TQ2
(Unreal Engine 5.7) on start.

## Download

Get `tq2-tweaks-<version>.zip` from the [releases](https://github.com/Wobi848/tq2-tweaks/releases); it contains
the folder `TQ2Tweaks`. Online data pages (monsters & drops, item affixes, loot filter editor):
<https://wobi848.github.io/tq2-tweaks/>

## Installation

1. **Install UE4SS:** copy the content of the UE4SS zip (`dwmapi.dll` and the folder `UE4SS`) into this game
   folder:
   ```sh
   <Steam>\steamapps\common\Titan Quest II\TQ2\Binaries\Win64\
   ```
2. **Install the mod:** copy the folder `TQ2Tweaks` to
   ```sh
   ...\TQ2\Binaries\Win64\UE4SS\Mods\
   ```
   Afterwards there is `UE4SS\Mods\TQ2Tweaks\Scripts\main.lua`.
3. **Enable it:** add this line to `UE4SS\Mods\mods.txt`, above the line `; Built-in keybinds, do not move up!`:
   ```sh
   TQ2Tweaks : 1
   ```
   If there is also a `UE4SS\Mods\mods.json`, add it to that list as well:
   ```json
   { "mod_name": "TQ2Tweaks", "mod_enabled": true }
   ```
4. **Linux / Steam Deck (Proton) only:** in Steam → Titan Quest II → Properties → Launch options, enter:
   ```sh
   WINEDLLOVERRIDES="dwmapi=n,b" %command%
   ```
   Not needed on Windows.
5. Start the game and load a character.

### Updating from 1.0.0 (folder ShadeHud)

From 2.0.0 the mod folder is called `TQ2Tweaks`. Copy your `user_settings.lua` and `loot_filter.lua` from
`Mods\ShadeHud` into the new `Mods\TQ2Tweaks`, then delete the folder `ShadeHud` and replace the line `ShadeHud : 1` in
`mods.txt` (and `mods.json`) with `TQ2Tweaks : 1`. Keys changed too: F7 caravan (stash), F8 damage details, F9 meter
reset, Shift+F9 dumps.

## In-game settings (F5)

**F5** opens a menu in the middle of the screen. Without a Spirit character a preview of the shade display is
shown.

| Key | Action |
| --- | --- |
| Page Up / Page Down | switch tab (Shades, Gameplay, Items, Damage) |
| Arrow up / down | select a row |
| Arrow left / right | change the value (with Shift: large steps for the position) |
| F5 | save and close |

Settings:

- **Shade display:** bar colour (teal/gold, purple/white, red/yellow, green/white), text colour, display
  (bars + numbers, bars only, numbers only), size, position left/right and up/down
- **Rewards:** experience x1 to x10, gold from enemies x1 to x10, extra loot +0 to +5
- **Speed:** movement speed x1 to x2, game speed x1 to x3 (everything runs faster, enemies too)
- **Points per level:** attribute, active skill, passive skill and mastery points (for future level ups)
- **Crafting:** free crafting on/off (all crafting costs 0); **anvil anywhere**: F6 opens the blacksmith window
  anywhere (F6 again or Esc closes it); **caravan anywhere**: F7 opens your caravan (the shared stash) anywhere
- **Auto pickup:** crafting materials, potions, charms & relics, each on/off – picked up automatically like gold;
  **equipment from** a chosen rarity (Off, Common … Legendary), same range as gold, without the flying animation;
  **loot filter**: picks up equipment that matches one of your loot filter rules (see below)
- **Damage meter:** on/off; position right, top centre or bottom left. Shows DPS of the last 5 seconds, total
  damage, hits, crits and the highest hit, plus (each switchable) a graph of the last 30 seconds, the share per
  damage type and the share of the 5 strongest skills (summons grouped by name, e.g. "Lich", "Automaton"). Counts
  only damage dealt by you and your summons to enemies; after 10 seconds without a hit a new fight starts, until
  then the last fight stays visible with its average DPS. **F9** resets it.
  **F8** opens a large detail window: graph of the last 60 seconds coloured by skill with an average line, a table
  per skill (damage, DPS, share, hits, crit rate, highest hit), all damage types and the best second. F8 again
  closes it.

### Loot filter (e.g. only items with summon stats)

Rules like in other ARPG loot filters: within a rule all conditions must hold, and an item is picked up if any rule
matches. A rule has a **rarity from** (e.g. Rare), optional **item types** (helmet, ring, staff …) and optional
optional **affixes** with how many of them one item needs. **Count crafting** lets an item with one wanted affix
too few still count, if the blacksmith can add it (a free affix place, or a useless random affix of the same kind –
prefix or suffix – to replace). **Only upgrades** (F5 menu, under "Loot filter", on by default): a rule with affixes
only picks up an item that scores higher than the item you wear in that slot (wanted affixes, plus one with Count
crafting; for rings the weaker ring counts), so items that cannot become better than your gear stay on the ground.
**Presets** (Summoner, Survivability, Epic and better) give a starting point. Example: "Summoner: Rare+, 1 of the summon affixes",
"Defence: Rare+, 2 of health/barrier/resistance", "Epic and better: Epic+".

1. In game press **Shift+F9**. This writes `TQ2Tweaks\affix_dump.txt` with all affixes, charms and relics of the game (and
   the affixes of the items on the ground, shown as "on ground") and `TQ2Tweaks\affix_data.js`, which the editor
   loads by itself. It also writes `TQ2Tweaks\gear.json` with your equipped items, bags and stash, and
   `TQ2Tweaks\character.json` with your level, attributes, skills and equipped items ("Load character" in
   `build_planner.html` reads it).
2. Open `TQ2Tweaks\loot_filter.html` in your browser (it works offline): it shows all affixes and your current
   `loot_filter.lua`. Add rules, set rarity, item types and the number of affixes needed, and add affixes – each row
   shows the names the affix gives an item (e.g. "Beastcaller's … Wraithlord's") and its effect.
3. Click **Save loot_filter.lua** and put the file into the `TQ2Tweaks` folder.
4. In the F5 menu (Items) switch **Loot filter** on. The mod notices a new or changed `loot_filter.lua` by itself
   within a few seconds.

In game, the F5 tab **Filter** lists your rules: switch each one on or off and change its rarity and how many affixes
it needs. The changes are written into `loot_filter.lua` (and shown by the editor after the next Shift+F9).

For developers: with `GameDataDump = true` in `config.lua`, writing `gamedata` into `TQ2Tweaks\dev_command.txt` while the
game runs writes `TQ2Tweaks\game_data.json` (all creatures with their drop lists, and which affixes each item type can
roll); `mega` dumps every data asset. They load many assets; under some Proton builds the game hung afterwards.

Rewards, speed, points, crafting and auto pickup are meant **for single player only**. Back up your save games
first.

Settings are saved in `TQ2Tweaks\user_settings.lua`. Delete the file to go back to the defaults.
Defaults, colour presets, the menu's look and the keys themselves (F5, F6, F7, F8, F9) are in
`TQ2Tweaks\Scripts\config.lua`.

While the menu is open, character movement is blocked so the arrow keys only operate the menu.

## Troubleshooting

- **Nothing shows up:** look for lines with `[TQ2Tweaks]` in `UE4SS\UE4SS.log`. If there are none, UE4SS or the
  mod was not loaded (check step 3 and, on Linux, step 4). For more details set `DebugLog = true` in
  `config.lua`.
- **The game crashes on start:** rename `dwmapi.dll` to `dwmapi.dll.disabled`; the game then starts without mods.
- **The game freezes (Linux/Steam Deck):** freezes seen with a custom Proton build came from audio (PipeWire) and
  the Steam overlay, not from the mod. Use an official Proton version (Steam → Properties → Compatibility) and turn
  off the Steam overlay for the game. To find the cause of a freeze, add `PROTON_LOG=1` to the launch options; the
  log is written to `~/steam-1154030.log`.
- **Multiplayer:** not supported; in co-op the display may show another player's shades.

## Uninstall

Delete `dwmapi.dll` and the folder `UE4SS` from `TQ2\Binaries\Win64`. Save games are not changed.

## Credits

Thanks to the authors of the Nexus mods "Exp Plus", "Gold", "Loot Plus", "Points" and "CraftnStash" for the
techniques (only the techniques were adopted, the code is our own), and to "TQ2 Companion" for the ideas of a game
speed setting and a damage meter.

Item type icons in the browser pages: [game-icons.net](https://game-icons.net) by Lorc, Delapouite and
Willdabeast, licensed [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/) (bundled in `icons.js`, only the
motif kept).

## License

MIT, see [LICENSE](../LICENSE).
