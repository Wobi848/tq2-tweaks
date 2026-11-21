# TQ2 Tweaks

UE4SS Lua mod for Titan Quest II (Early Access 0.7.1, Unreal Engine 5.7; developed and tested on Linux/Proton).
The mod folder is `ShadeHud`; in game it is the F5 menu "TQ2 Tweaks". **Single player only.**

- Player guide (installation, keys, settings): [ShadeHud/README.md](ShadeHud/README.md)
- Downloads: [releases](https://github.com/Wobi848/tq2-tweaks/releases); data pages online:
  <https://wobi848.github.io/tq2-tweaks/> (built into `docs/` by `tools/build_site.sh <game version>` from the
  dumps; only game data goes online – the ground items and the player's own loot filter are left out)
- License: MIT, see [LICENSE](LICENSE)
- The rest of this file is for developers: structure, decisions and why things are done the way they are.

## Features and status

| Feature | Module | Confirmed in game |
| --- | --- | --- |
| Shade display (bars + numbers) | `shade_state.lua`, `shade_widget.lua` | yes |
| F5 menu with tabs, movement lock while open | `menu.lua`, `menu_tabs.lua`, `menu_widget.lua`, `movement_lock.lua` | yes |
| Experience x1–x10 | `xp_multiplier.lua` | yes |
| Gold from enemies x1–x10 | `gold_multiplier.lua` | yes |
| Extra loot +0–+5 | `loot_bonus.lua` | yes |
| Movement speed | `movement_speed.lua` | yes |
| Game speed | `game_speed.lua` | yes |
| Points per level | `level_points.lua` | no |
| Free crafting | `crafting_cost.lua` | yes (at the anvil) |
| Auto pickup by kind | `auto_pickup.lua` | yes |
| Auto pickup of equipment by rarity | `equipment_pickup.lua`, `world_items.lua` | yes |
| Anvil anywhere (F6) | `crafting_anywhere.lua` | yes |
| Hiding during cutscenes | `cutscene.lua` | no |
| Damage meter with graph, damage types, skills | `damage_meter.lua`, `damage_hook.lua`, `damage_meter_widget.lua` | yes |
| Damage detail window (F7) | `damage_detail_widget.lua` | yes |
| Game data dump (Shift+F9): creatures, drop lists, affix tables | `game_data_dump.lua`, `json_text.lua` | yes (once) |
| Gear dump (with F9): equipped items and own inventories with affix tiers and rolls | `gear_dump.lua` | yes |
| Mega dump (Ctrl+F9, with `GameDataDump`): every data asset via reflection | `mega_dump.lua`, `batch_job.lua` | no |
| Data page: monsters & drops, affix chances per item kind | `tools/game_data.html` | – |
| Affix dump (F9) incl. charms/relics, and loot filter | `affix_dump.lua`, `loot_rules.lua`, `equipment_pickup.lua`, `ShadeHud/loot_filter.html` | yes |
| Cleanup before a level change | `main.lua` (`RegisterLoadMapPreHook`), `player.lua` | no |
| Loop timing (`TimingLog`, off by default) | `loop_timing.lua` | yes |

## Structure and decisions

- **UE4SS Lua mod instead of a pak mod**: no game files are changed, which survives patches better. UE4SS is
  loaded through `dwmapi.dll`.
- **Modules**: `main.lua` only wires things together. `config.lua` = defaults, `settings.lua` = values changed in
  game (saved to `ShadeHud/user_settings.lua`), `ui.lua` = shared UMG building blocks,
  `*_menu_entries.lua` + `setting_entry.lua` = menu rows. A menu entry is
  `{ label, value(), change(direction, fast) }` or `{ header = "…" }`.
- **Hooks only when needed**: the experience, drop and damage hooks are registered only once their feature is
  switched on in the menu (`lazyHooks` in `main.lua`); movement speed does nothing while it was never active.
  "Off" therefore means no intervention at all – important when narrowing down crashes.
- **Threads**: loops use `LoopInGameThreadWithDelay`, delays `ExecuteInGameThreadWithDelay`. Key callbacks only
  change Lua values; widgets are (re)built on the game thread.
- **Layers**: everything goes through `AddToPlayerScreen` below the game's Lyra UI (layer 1000), so the game's menus
  (pause, inventory) cover our widgets: HUD widgets on layer 0, F5 menu on 10. (With `AddToViewport` the F5 menu
  sat above the pause menu.)
- **Performance**: every call through UE4SS costs time. Auto pickup and free crafting walk all ~1000 item types –
  only every 5 s, only when the number of types or the setting changed, with the kind of each type determined once
  and cached (before that: thousands of calls per second and a visible FPS drop). The damage panels are refreshed at
  most 4×/s (compact) and 1×/s (detail window).
- **Cutscenes** (`cutscene.lua`): the HUD widgets are hidden while an `ATQ2CutsceneQuestActor` has
  `m_EventRunning` or the game's own HUD `wbp_hud_C` is invisible or faded out (boss sequences run without a
  cutscene actor). Checked at most every 0.5 s; with `DebugLog = true` each change of the game HUD's state is logged
  ("Game HUD state"). The F5 menu stays usable.
- **Bars** are made of `Border` colour areas (`UI.newFillBar`/`UI.setFill`): `ProgressBar` is tinted blue and
  `SetWidgetStyle` cannot be called in TQ2.
- **Tabs** (`menu_tabs.lua`, `config.MenuTabs`): sections (headers) are assigned to tabs (Shades, Gameplay, Items,
  Damage); unknown sections land in the last tab. Page Up/Down switches, the panel is rebuilt.
- **Keyboard menu**: click delegates of buttons cannot be bound reliably from UE4SS Lua. The menu sits in the
  screen centre because it became too tall for a spot above the character.
- **Shade values**: `TQ2PlayerCharacterViewModel` (`GetCurrentShades`, `GetMaximumShades`,
  `GetShadeRegenEffectViewModel():GetRemainingDurationNormalized()`).
- **Experience**: hook on `TQ2AttributeSetProgression:Server_GrantLevelProgress`, multiplies the amount (not when
  `Override` is set, e.g. when loading).
- **Gold and loot**: one shared hook on `GrimWorldItemReplicationHelper:LaunchDropList` (`drop_hooks.lua`) that reads
  parameters only while gold or loot is active. Gold: piles (`ItemSlots[].Num`) created up to 2 s after an enemy
  drop (the game spawns dropped items later via `m_PendingItemSpawns`); only `Num` is written, in place.
  Writing the whole slot struct back with `element:set(slot)` was suspected of crashes. Loot: raise `NumToDrop`, or
  drop the list once more when it is `-1` ("list decides").
- **Movement speed**: walking follows `MoveSpeedFactor` (GAS attribute in the player's `GrimAttributeSetMovement`;
  measured 629 = 500 × 1.26). `MaxWalkSpeed` and `m_CustomMoveSpeedMultiplier` have no effect. The attribute set is
  found through its outer chain (set → component → character/PlayerState); only the attribute is scaled, and the
  game's own recalculations are detected as deviations from the last written value.
- **Game speed**: `GameplayStatics:SetGlobalTimeDilation`; at x1 it is reset only once, so the game's own
  slow-motion effects are left alone.
- **Points per level**: fields of `Default__TQ2GameplaySettings` (settings classes exist only as default object:
  `StaticFindObject("/Script/<Module>.Default__<Class>")`).
- **Free crafting**: the costs are formulas (`FGrimDynamicsFormula`: `SourceText` + hidden compiled data), so writing
  numbers has no effect. Every `UTQ2ItemDescription` has `m_CraftingCostsToOverride` (one bit per action) and
  `m_OverriddenCraftingCostByAction[4]`. **Only while the anvil window is open** (hooks on
  `OnCraftingUIOpened`/`OnCraftingUIClosed`): on opening, "gold 0, no resources" is imported once per type with
  `ImportText` (key name@address) and all four bits are set; on closing the bits go back to 0. Types with their own
  override are left alone. An earlier version kept the override on all the time and re-applied it in the
  background – that froze or crashed the game in fights.
- **Auto pickup**: sets `UGrimItemDescription.m_CanAutoPickup` for item types of the chosen kinds – the same
  mechanism as gold (`UGrimItemHooverComponent`), the game handles a full inventory. Kinds are recognised by text
  patterns in the asset path and the `m_Type` tag (`config.AutoPickupCategories`, first match wins); with
  `DebugLog = true` a one-time overview of the real folders/tags goes to the log. Switching off restores the
  original flag.
- **Equipment by rarity** (`equipment_pickup.lua`): rarity belongs to the single item, not the type, so equipment
  does not get the type flag. New ground items are remembered through `world_items.lua` (one shared
  `NotifyOnNewObject` for gold and equipment); every 250 ms: rarity from
  `m_ContainerData.ItemSlots[].ItemHandle.pItem.m_Rarity`, kind from the type name (`<type>_WorldItem…`) and
  `AutoPickup.kindByName` (items of a type not scanned yet wait for the next scan), range = `m_Range` of the
  player's `GrimItemHooverComponent`; matching items → `AGrimWorldItem:Pickup(player, false)`, one try per item.
  The setting `AutoPickupEquipment` is an index into `EquipmentRarityThresholds` (the old value 2 = "On" became
  "Common" = everything).
- **Anvil anywhere**: technique from "CraftnStash", own code. The player gets a `TQ2CraftingComponent` if needed
  (`AddComponentByClass`), becomes its own crafting access (`SetCraftingAccess`), then `OnCraftingUIOpened`.
  Closing by key or Esc (hook on `OnCraftingUIClosed`) clears the access again.
- **Damage meter**: hook on `TQ2Character:Multicast_HandleDamageReceived_*` (runs for every hit on every
  character). It only reads damage, crit, strongest damage type (`HighestDamageType.TagName`, last part as name) and
  the ability tags, then calls `DamageMeter.record`; errors are caught and logged once. Everything else (rolling DPS
  over 5 s, per-second buckets, shares, "last fight" after 10 s without hits, reset with F8) is computed in the
  display loop.
- **Damage per skill**: the name comes from the tag `GrimAbilitySystem.Description.bp_bga_…` (owner, mastery code,
  `_m_…` modifiers, `_basicAttack…` and `_summon…` dropped → one row per summon). Summons are `TQ2AICharacter`s
  too, so enemies hitting them land in the same hook; only abilities named `player_…`/`global_…` count (or without
  a tag, e.g. damage over time → "Other").
- **Detail window (F7)**: `damage_detail_widget.lua`, data from `DamageMeter.details` (per-second buckets per skill,
  60 s history). Stacked bars from `SizeBox` + `Border` per skill rank (colours `DamageSkillColors`, same ranks as in
  the compact panel), average line via the padding of an `Overlay` slot. Many widgets → built only while open; the
  compact panel steps aside meanwhile, and the window steps aside for the F5 menu.
- **Loot filter** (e.g. summon stats on any item type): affixes are data assets (`UGrimItemAffix`: `m_Type` 0 prefix /
  1 suffix / 2 special, `m_Levels.Levels[].TitleText/AffixEffects[].ToolTipText`); an item carries them in
  `UGrimItemInstance.m_Affixes[].pAffix`. All 491 are loaded at any time (two dumps, same count). F9 writes them plus
  the ground items' affixes to `affix_dump.txt` (every field under `pcall`, unreadable = `?`). Modelled on Path of
  Exile (filter file + web editor FilterBlade) and Last Epoch (rules with "at least N affixes of this pool"): a
  file `loot_filter.lua` with rules `{ name, minRarity, needed, craftable, types, affixes }` (craftable: one wanted affix
  may be missing if crafting can add it – a free place by rarity, `AffixPlacesByRarity`, or a useless random affix of
  the same kind; the kind comes from the asset name `da_prefix_`/`da_suffix_`, "random" from the affix instance's
  `Category`) – conditions of a rule combine with
  "and", rules with "or"; pickup only, nothing is hidden. A first version with one count for all affixes was too
  coarse (one summon stat is enough, defence needs two). Editing happens outside the game in `loot_filter.html`
  (offline, no libraries; ~490 affixes are too many for the keyboard menu); the menu only switches the filter. A page
  opened from disk may not read files by itself, but it may load a script beside it: F9 also writes `affix_data.js`
  (dump + current filter as JavaScript strings), so the editor opens filled in. Rules from that file replace the ones
  kept in the browser only when the file changed since the last visit.
  The file is loaded with an empty environment (data only), rules without a condition or with an unknown rarity are
  left out and logged. `main.lua` reads it every `LootFilterCheckMs` and reloads it when the text changed. The F5 tab
  "Filter" (`loot_filter_menu_entries.lua`, rows refilled on every reload) edits a rule's on/off, rarity and count;
  key callbacks only queue the edit, the loop writes it into the rule's one-line header (`LootRules.editRule`) and
  refreshes `affix_data.js`. Item types are parts of
  the type name (`da_armor_head_…`, `da_jewelry_neck_…`, `da_weapon_2h_staff_…`).
- **Game data dump** (groundwork for a data page: who drops what, with which chance): the data assets are cooked
  into the IoStore container (`TQ2-Windows.utoc/.ucas`), not the `.pak` (checked with repak: only config, images,
  fonts), so reading them from disk would need retoc + a usmap + an asset parser. Instead the game loads them itself:
  `CookedData/JsonMetaDataCache.json` (loose in the game folder) lists every data asset by class; the dump loads all
  `TQ2CreatureTemplateJsonData` with UE4SS `LoadAsset` in batches of 20 (`ExecuteInGameThreadWithDelay`), follows
  `pDropList` → `UGrimItemDropList` (`m_DropChance`, `m_NumRandomDrops`, `m_FixedDrops`, `m_RandomDropTable` with
  weighted entries and sub-lists) and writes everything as JSON. Chances, weights and counts are
  `FGrimDynamicsFormula`s; their `SourceText` is written as it is. Item types add their random affix tables with each
  entry's weight and requirement (gameplay tags, item level). Off by default (`GameDataDump`): the game froze ~40 s
  after the first dump (probably the cleanup of ~1000 loaded templates with everything they reference); the data
  only changes with game patches, so one dump per patch plus a restart is enough.
- **Gear dump**: `ATQ2PlayerState.m_pEquipmentContainer` holds the equipped items, the player's bags and stash are
  `TQ2Inventory` objects found by their outer chain (up to 4 levels) leading to the player state; both keep items in
  `m_ContainerData.ItemSlots` like ground items. Per affix: `Level` (tier), `Category` (base/implicit/random) and the
  `Scale` of each effect (roll quality); the shown numbers themselves are formulas and not computed.
- **Browser pages** (`ShadeHud/loot_filter.html`, `tools/game_data.html`): standalone and offline – no CDN, fonts or
  network calls; data comes from scripts the mod writes next to them (`affix_data.js`, `game_data.js`), shared code in
  `ShadeHud/affix_parse.js`, `ShadeHud/page_style.css` and `ShadeHud/icons.js` (17 item type icons from game-icons.net,
  CC BY 3.0, downloaded once; only the motif path kept so it takes the text colour). The data page computes the chance per prefix/suffix roll by
  walking the item type's affix tables: at every level only entries whose tag requirement fits the item (type tag with
  its parents, build direction, chosen rarity) count, each with its weight among them. Tag requirement modes:
  0 any, 1 all, 2 none, 3 not all.
- **Discarded**:
  - Auto salvage: native salvage functions fail because of the `TScriptInterface` limit (below); the detour through
    the anvil window (`wbp_crafting_C.OnBulkSalvagingChoiceMade`) salvaged nothing. Anvil anywhere plus the game's
    own bulk salvage is enough.
  - Experience/gold via `CombatXPGain`/`CombatGoldGain` (not readable as numbers there); crafting via
    `Default__TQ2ItemCraftingSettings.m_CostByAction` (formulas, see above; walking that map also failed because this
    UE4SS has no `GetValueProp`).
  - Several languages: the mod is English only.
- **UE4SS limit `TScriptInterface`**: `push_interfaceproperty` (UE4SS `LuaUObject.cpp`) only sets the object
  pointer, not the interface pointer. Native functions with interface parameters (e.g.
  `GrimItemContainerFunctionLibrary.GetNumItemSlots`, `BulkSalvageItems`) therefore see an empty container
  (logged: `GetNumItemSlots=0` with 384 slots). The fix would be `GetInterfaceAddress(InterfaceClass)` there;
  building a custom UE4SS for the TQ2 variant is a lot of work.
- **Sources of techniques**: Nexus mods for Titan Quest II "Exp Plus", "Gold", "Loot Plus", "Points",
  "CraftnStash" (only the techniques were adopted, the code is our own). "TQ2 Companion" is a closed DLL (also
  `dwmapi.dll`, so it cannot run alongside UE4SS); only its ideas of a game speed setting and a DPS meter were
  adopted.
- **Tools**: UE4SS API in `UE4SS/Mods/shared/Types.lua` of the dev version of "UE4SS for TQ2"; header dump of all
  game classes with Ctrl+H in game to `UE4SS/CXXHeaderDump`.

## Stability notes

- TQ2 itself crashes or hangs now and then, also without mods (e.g. garbage collection stuck after a loading
  screen).
- Crashes during development were traced to two designs that are gone now: free crafting kept active in the
  background (now only while the anvil is open) and work handed across threads several times per second (now
  everything runs on the game thread). Since then long sessions with all features on ran stable.
- Level changes: `RegisterLoadMapPreHook` drops all our widgets and cached game objects (view model, movement set,
  remembered ground items, movement lock) before the old world is torn down; they are found or built again on the
  next loop. Added after two hangs on exit and one crash right after a loading screen (21.11.); whether those were
  ours is not proven.
- Performance: `TimingLog = true` in `config.lua` times every loop and logs once a minute how often it ran, its
  average and longest run and the share of time spent in the mod (`os.clock` is wall time in ms steps under
  Windows/Wine). Hooks (damage, drops) are not included.
- Measured hot spots (21.11., ~2 % of the time in the mod) and what was done: `UEHelpers.GetPlayer/
  GetPlayerController` run `FindAllOf("PlayerController")` on every call → `player.lua` keeps the controller while
  valid (forgotten on level change); equipment pickup re-judged every remembered item each pass (affixes read again)
  → judged once per item, then only the distance is checked; the shade display rewrote bars and text ~9×/s → only
  when the values change.
- Three crashes in big fights on 21.11. (no mod error, no crash report) all happened while the loot filter read the
  affixes of fresh ground items; the rarity-only pickup of the day before ran 3 h without one. Not proven, but the
  item data is partly filled in after the drop (`OnPayloadDataLoaded`), so now: an item is judged only after lying
  1.5 s (`EquipmentJudgeDelaySeconds`), rules without affixes are checked first and affixes are read only when a rule
  needs them.
- The "crashes" of 21.11. turned out to be freezes: with `PROTON_LOG=1` (log in `~/steam-1154030.log`, overwritten
  on every start) two of them showed no access violation but critical-section deadlocks among non-game-thread
  threads – one created together with Wine's PipeWire audio threads (`winepipewire_timer`), the Steam overlay
  thread holding the process heap lock, and the game's last log line an FMOD message. That points to audio under the
  custom Proton build used ("wineland-11.0") rather than to the mod; switching to an official Proton and turning off
  the Steam overlay is the first thing to try. For a new freeze, read the Proton log first
  (`RtlpWaitForCriticalSection`, `c0000005`).
- To narrow down a new problem: switch features off one by one – a feature that is off registers no hooks.

## Tests

```sh
luac5.4 -p ShadeHud/Scripts/*.lua
lua5.4 tests/test_shadehud.lua
```

Runs without the game against a mocked UE4SS API.

## Development setup

```sh
./install.sh <unpacked UE4SS release>   # links the mod folder into the game
./backup_saves.sh <label>              # copies the save games to ~/tq2-save-backups/
```

UE4SS release: **"UE4SS for TQ2" from Nexus** (nexusmods.com/titanquest2/mods/77, normal version, not DEV).
The GitHub release (v4.0.0-8) crashes TQ2 (UE 5.7) on start ("Locating KismetStringLibrary CDO",
UE4SS issue #1482); the Nexus version ships a matching `MemberVariableLayout.ini`.

Steam → Titan Quest II → Properties → Launch options:

```sh
WINEDLLOVERRIDES="dwmapi=n,b" %command%
```

Logs: `TQ2/Binaries/Win64/UE4SS/UE4SS.log` (lines with `[ShadeHud]`) and the game log under
`compatdata/1154030/pfx/drive_c/users/steamuser/AppData/Local/TQ2/Saved/Logs/` (crash causes; times are UTC).
