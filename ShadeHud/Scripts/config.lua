-- Default values. Everything the player can change in the F5 menu is stored in user_settings.lua in the
-- mod folder and takes precedence over these values.
return {
    -- How often the shade display is refreshed (milliseconds).
    UpdateIntervalMs = 100,
    -- How often gameplay tweaks (level points, hook registration) are re-applied (milliseconds).
    GameplayIntervalMs = 1000,
    -- How often auto pickup looks for newly loaded item types (milliseconds). Each pass lists all ~1000 item types,
    -- so it runs less often.
    ItemTypeScanIntervalMs = 5000,

    -- Screen anchor (0..1). 0.5/0.5 = screen centre, i.e. at the character.
    AnchorX = 0.5,
    AnchorY = 0.5,
    -- Offset in pixels from the anchor (positive Y = down).
    OffsetX = 0,
    OffsetY = 110,

    -- Base size at scale 1.0, in pixels.
    BarWidth = 70,
    BarHeight = 16,
    BarSpacing = 6,
    FontSize = 30,
    Scale = 1.0,
    MoveStep = 5,
    MoveStepFast = 50,
    ScaleStep = 0.1,
    ScaleMin = 0.5,
    ScaleMax = 3.0,

    -- Colours as {R, G, B, A} from 0 to 1. Setting values are indices into these lists.
    ColorPreset = 1,
    ColorPresets = {
        { Name = "Teal/Gold", Full = { R = 0.1, G = 1.0, B = 0.9, A = 1.0 }, Charging = { R = 1.0, G = 0.8, B = 0.25, A = 1.0 } },
        { Name = "Purple/White", Full = { R = 0.7, G = 0.4, B = 1.0, A = 1.0 }, Charging = { R = 1.0, G = 1.0, B = 1.0, A = 1.0 } },
        { Name = "Red/Yellow", Full = { R = 1.0, G = 0.25, B = 0.2, A = 1.0 }, Charging = { R = 1.0, G = 0.9, B = 0.2, A = 1.0 } },
        { Name = "Green/White", Full = { R = 0.3, G = 1.0, B = 0.3, A = 1.0 }, Charging = { R = 1.0, G = 1.0, B = 1.0, A = 1.0 } },
    },
    TextColorPreset = 1,
    TextColorPresets = {
        { Name = "White", Color = { R = 1.0, G = 1.0, B = 1.0, A = 1.0 } },
        { Name = "Gold", Color = { R = 1.0, G = 0.82, B = 0.35, A = 1.0 } },
        { Name = "Teal", Color = { R = 0.1, G = 1.0, B = 0.9, A = 1.0 } },
        { Name = "Purple", Color = { R = 0.8, G = 0.55, B = 1.0, A = 1.0 } },
        { Name = "Red", Color = { R = 1.0, G = 0.35, B = 0.3, A = 1.0 } },
        { Name = "Green", Color = { R = 0.4, G = 1.0, B = 0.4, A = 1.0 } },
    },
    DisplayMode = 1,
    DisplayModes = {
        { Name = "Bars + numbers", ShowBars = true, ShowNumbers = true },
        { Name = "Bars only", ShowBars = true, ShowNumbers = false },
        { Name = "Numbers only", ShowBars = false, ShowNumbers = true },
    },

    -- Gameplay tweaks (single player only). List settings are indices into the lists below.
    XpMultiplier = 1,
    GoldMultiplier = 1,
    RewardMultipliers = {
        { Name = "x1 (normal)", Factor = 1 },
        { Name = "x1.5", Factor = 1.5 },
        { Name = "x2", Factor = 2 },
        { Name = "x3", Factor = 3 },
        { Name = "x5", Factor = 5 },
        { Name = "x10", Factor = 10 },
    },
    LootBonus = 1,
    LootBonuses = {
        { Name = "+0 (normal)", Extra = 0 },
        { Name = "+1", Extra = 1 },
        { Name = "+2", Extra = 2 },
        { Name = "+3", Extra = 3 },
        { Name = "+5", Extra = 5 },
    },
    FreeCrafting = 1,
    -- Open the anvil window anywhere with this key (name from the UE4SS key list); switchable in the menu.
    AnvilAnywhere = 2,
    AnvilKey = "F6",
    OnOffOptions = {
        { Name = "Off", Enabled = false },
        { Name = "On", Enabled = true },
    },
    MoveSpeed = 1,
    MoveSpeeds = {
        { Name = "x1 (normal)", Factor = 1 },
        { Name = "x1.1", Factor = 1.1 },
        { Name = "x1.25", Factor = 1.25 },
        { Name = "x1.5", Factor = 1.5 },
        { Name = "x1.75", Factor = 1.75 },
        { Name = "x2", Factor = 2 },
    },
    -- Global time dilation: everything (including enemies) runs faster.
    GameSpeed = 1,
    GameSpeeds = {
        { Name = "x1 (normal)", Factor = 1 },
        { Name = "x1.25", Factor = 1.25 },
        { Name = "x1.5", Factor = 1.5 },
        { Name = "x2", Factor = 2 },
        { Name = "x3", Factor = 3 },
    },
    -- How often movement and game speed are re-applied (milliseconds); the game resets them on buffs and loads.
    SpeedIntervalMs = 250,
    -- Points per level up; defaults are the game's vanilla values.
    AttributePointsPerLevel = 2,
    ActivePointsPerLevel = 2,
    PassivePointsPerLevel = 2,
    MasteryPointsPerLevel = 1,
    PointsMin = 0,
    PointsMax = 20,

    -- Auto pickup: item kinds recognised by lower-case patterns in the item's asset path or type tag (m_Type, e.g.
    -- "GrimVentory.ItemType.Torso"); the first matching category wins. The type tags were taken from the log
    -- ("Auto pickup overview"); crafting materials showed no own tag there, so they are matched by name.
    AutoPickupCategories = {
        { Name = "Crafting materials", Setting = "AutoPickupMaterials",
          Match = { "scrap", "_mat_", "itemtype.crafting", "itemtype.material", "itemtype.resource" } },
        { Name = "Potions", Setting = "AutoPickupPotions", Match = { "itemtype.consumable", "potion" } },
        { Name = "Charms & relics", Setting = "AutoPickupSocketables", Match = { "itemtype.socketable" } },
        -- Equipment is picked up by rarity (equipment_pickup.lua), not via the type flag: rarity is per item.
        { Name = "Equipment", MenuLabel = "Equipment from", Setting = "AutoPickupEquipment", ByRarity = true,
          Match = { "itemtype.weapon", "itemtype.torso", "itemtype.helmet", "itemtype.arm", "itemtype.leg",
                    "itemtype.shoulder", "itemtype.neck", "itemtype.ring" } },
    },
    AutoPickupMaterials = 1,
    AutoPickupPotions = 1,
    AutoPickupSocketables = 1,
    -- Index into EquipmentRarityThresholds. Same key as the former on/off switch: old value 2 ("On") becomes
    -- "Common" (= all equipment), so saved settings keep their meaning.
    AutoPickupEquipment = 1,
    EquipmentRarityThresholds = {
        { Name = "Off" },
        { Name = "Common", Rarity = 0 },
        { Name = "Magic", Rarity = 1 },
        { Name = "Rare", Rarity = 2 },
        { Name = "Infrequent", Rarity = 3 },
        { Name = "Epic", Rarity = 4 },
        { Name = "Legendary", Rarity = 5 },
    },
    -- Loot filter: equipment matching one of the rules made in loot_filter.html (saved as LootFilterFile in the mod
    -- folder) is picked up, in addition to the rarity rule above.
    LootFilter = 1,
    LootFilterFile = "loot_filter.lua",
    -- Equipment pickup: how often it checks remembered ground items, and the range used until the player's own
    -- pickup range (hoover) is found.
    EquipmentPickupIntervalMs = 250,
    EquipmentPickupFallbackRange = 400,
    -- New ground items are judged only after lying this long (their data is filled in after the drop).
    EquipmentJudgeDelaySeconds = 1.5,


    -- Damage meter: counts damage dealt to enemies. Window = seconds for the rolling DPS; an encounter ends
    -- after EncounterTimeout seconds without damage, and the next hit starts a new one.
    DamageMeter = 1,
    DamageMeterWindowSeconds = 5,
    -- How often the panel's numbers and bars are refreshed (seconds); each refresh costs ~70 engine calls.
    DamageMeterIntervalSeconds = 0.25,
    DamageMeterEncounterTimeout = 10,
    -- Where the panel sits: anchor and alignment (0..1) plus offset in pixels. The left edge is taken by the
    -- game's summon/party portraits.
    DamageMeterPosition = 1,
    DamageMeterPositions = {
        -- Right: below the game's quest tracker, which covered the panel at 40 % height.
        { Name = "Right", Anchor = { X = 1, Y = 0.62 }, Alignment = { X = 1, Y = 0 }, Offset = { X = -24, Y = 0 } },
        { Name = "Top centre", Anchor = { X = 0.5, Y = 0 }, Alignment = { X = 0.5, Y = 0 }, Offset = { X = 0, Y = 90 } },
        { Name = "Bottom left", Anchor = { X = 0, Y = 1 }, Alignment = { X = 0, Y = 1 }, Offset = { X = 24, Y = -24 } },
    },
    DamageMeterFontSize = 18,
    -- Graph: damage per second of the last DamageMeterGraphSeconds seconds as vertical bars.
    DamageMeterGraph = 2,
    DamageMeterGraphSeconds = 30,
    DamageGraphBarWidth = 5,
    DamageGraphHeight = 36,
    DamageGraphColor = { R = 1.0, G = 0.65, B = 0.25, A = 1.0 },
    DamageGraphEndedColor = { R = 0.55, G = 0.55, B = 0.55, A = 1.0 },
    -- Damage types: share of the four largest types; colour by name pattern (lower case), else the default.
    DamageMeterTypes = 2,
    DamageTypeNameWidth = 150,
    DamageTypeBarWidth = 110,
    DamageTypeColors = {
        { Match = "fire", Color = { R = 1.0, G = 0.35, B = 0.15, A = 1.0 } },
        { Match = "burn", Color = { R = 1.0, G = 0.35, B = 0.15, A = 1.0 } },
        { Match = "cold", Color = { R = 0.4, G = 0.75, B = 1.0, A = 1.0 } },
        { Match = "frost", Color = { R = 0.4, G = 0.75, B = 1.0, A = 1.0 } },
        { Match = "lightning", Color = { R = 1.0, G = 0.9, B = 0.3, A = 1.0 } },
        { Match = "shock", Color = { R = 1.0, G = 0.9, B = 0.3, A = 1.0 } },
        { Match = "poison", Color = { R = 0.45, G = 0.9, B = 0.3, A = 1.0 } },
        { Match = "vitality", Color = { R = 0.75, G = 0.45, B = 1.0, A = 1.0 } },
        { Match = "divine", Color = { R = 1.0, G = 0.95, B = 0.7, A = 1.0 } },
        { Match = "bleed", Color = { R = 0.8, G = 0.1, B = 0.15, A = 1.0 } },
        { Match = "physical", Color = { R = 0.8, G = 0.8, B = 0.8, A = 1.0 } },
        { Match = "pierce", Color = { R = 0.8, G = 0.8, B = 0.8, A = 1.0 } },
        { Match = "strike", Color = { R = 0.8, G = 0.8, B = 0.8, A = 1.0 } },
    },
    DamageTypeDefaultColor = { R = 0.9, G = 0.9, B = 0.9, A = 1.0 },
    -- Skills: damage share per ability (read from the hit's ability tags).
    DamageMeterSkills = 2,
    -- Colours of the skills by rank (largest first), the same in the compact panel and the detail window;
    -- skills beyond the list share DamageSkillRestColor.
    DamageSkillColors = {
        { R = 0.45, G = 0.85, B = 0.8, A = 1.0 },
        { R = 1.0, G = 0.65, B = 0.25, A = 1.0 },
        { R = 0.75, G = 0.5, B = 1.0, A = 1.0 },
        { R = 0.5, G = 0.9, B = 0.35, A = 1.0 },
        { R = 1.0, G = 0.45, B = 0.55, A = 1.0 },
    },
    DamageSkillRestColor = { R = 0.55, G = 0.55, B = 0.55, A = 1.0 },
    -- Detail window: opened/closed with DamageDetailKey while the damage meter is on. Graph of the last
    -- DamageDetailGraphSeconds seconds, stacked by skill, with a line at the average DPS.
    DamageDetailKey = "F7",
    -- Bottom centre, just above the skill bar; the window grows upwards with more skills. The offset is in UI units,
    -- which the game scales (about 0.55 on a 1080p screen): the skill bar is ~145 px = ~265 units high.
    DamageDetailPosition = { Anchor = { X = 0.5, Y = 1 }, Alignment = { X = 0.5, Y = 1 }, Offset = { X = 0, Y = -290 } },
    DamageDetailGraphSeconds = 60,
    DamageDetailGraphHeight = 140,
    DamageDetailBarWidth = 10,
    DamageDetailFontSize = 16,
    DamageDetailSkillRows = 10,
    DamageDetailTypeRows = 8,
    DamageDetailAverageColor = { R = 1.0, G = 1.0, B = 1.0, A = 0.6 },
    -- The window's numbers change once per second at most (it updates many widgets).
    DamageDetailIntervalSeconds = 1,
    -- Key that resets the damage meter (name from the UE4SS key list).
    DamageMeterResetKey = "F8",
    DamageMeterBackground = { R = 0.04, G = 0.035, B = 0.03, A = 0.75 },

    -- Menu: key to open/close (name from the UE4SS key list) and look.
    EditKey = "F5",
    MenuTitle = "TQ2 TWEAKS",
    -- Tabs of the menu and the sections (headers) each one shows; switched with Page Up/Down.
    MenuTabs = {
        { Name = "Shades", Sections = { "Shade display" } },
        { Name = "Gameplay", Sections = { "Rewards", "Speed", "Points per level" } },
        { Name = "Items", Sections = { "Crafting", "Auto-Pickup" } },
        { Name = "Damage", Sections = { "Damage meter" } },
    },
    -- The menu is centred on the screen; MenuOffsetY moves it.
    MenuOffsetY = 0,
    MenuTitleSize = 28,
    MenuHeaderSize = 18,
    MenuFontSize = 20,
    MenuHintSize = 15,
    MenuLabelWidth = 380,
    MenuBackground = { R = 0.04, G = 0.035, B = 0.03, A = 0.92 },
    MenuTextColor = { R = 0.85, G = 0.85, B = 0.85, A = 1.0 },
    MenuSelectedColor = { R = 1.0, G = 0.82, B = 0.35, A = 1.0 },
    MenuHeaderColor = { R = 0.45, G = 0.85, B = 0.8, A = 1.0 },
    MenuHintColor = { R = 0.6, G = 0.6, B = 0.6, A = 1.0 },

    -- Writes diagnostics to UE4SS.log: shade values read from the game, game HUD state changes (cutscene
    -- detection) and a one-time overview of the item types auto pickup recognises.
    DebugLog = false,
    -- Measures how long the mod's loops take and logs a summary every TimingReportSeconds (performance check).
    TimingLog = false,
    TimingReportSeconds = 60,
    -- Writes all item affixes and the affixes of ground items to AffixDumpFile in the mod folder; loot_filter.html
    -- reads it.
    AffixDumpKey = "F9",
    AffixDumpFile = "affix_dump.txt",
    AffixPageDataFile = "affix_data.js",
    -- The same key also writes the equipped items and the player's inventories (for upgrade advice).
    GearDumpFile = "gear.json",
    -- Developer tool, off by default: with Shift the key loads every creature template of the game and writes
    -- creatures, drop lists (chances and weights as the game's formulas) and the affix tables of all item types to
    -- GameDataFile. Loading ~1000 templates may make the game hang later (seen once, 21.11.): restart after a dump.
    GameDataDump = false,
    GameDataDumpModifier = "SHIFT",
    GameDataFile = "game_data.json",
    GameDataPageFile = "game_data.js",
    -- The game's list of its data assets, relative to the game folder (TQ2).
    GameDataCacheFile = "CookedData/JsonMetaDataCache.json",
}
