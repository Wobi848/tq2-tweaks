-- Tests: Auto pickup, anvil anywhere, equipment pickup by rarity, menu tabs, gold multiplier.
-- Run all tests with: lua5.4 tests/test_tq2tweaks.lua

local T = require("support")
local logLines, created, game, sword = T.logLines, T.created, T.game, T.sword
local instances, press, hooks, newObjectCallbacks = T.instances, T.press, T.hooks, T.newObjectCallbacks
local param, check, last, container = T.param, T.check, T.last, T.container
local groundItem, looter, equipmentKinds, isEquipmentType = T.groundItem, T.looter, T.equipmentKinds, T.isEquipmentType

-- Auto pickup on its own: categories by path/type tag, flag on for enabled kinds, original restored when off.
local AutoPickup = require("auto_pickup")
local categories = require("config").AutoPickupCategories
local function described(path, tag, canAutoPickup)
    return { IsValid = function() return true end, GetFullName = function() return "TQ2ItemDescription " .. path end,
             GetAddress = function() return path end, m_CanAutoPickup = canAutoPickup,
             m_Type = { TagName = { ToString = function() return tag end } } }
end
local scrapType = described("/Game/TQ2/Items/Crafting/da_item_scrap.da_item_scrap", "", false)
local potionType = described("/Game/TQ2/Items/Consumables/da_item_potion_health.da_item_potion_health", "GrimVentory.ItemType.Consumable", false)
local swordType = described("/Game/TQ2/Items/Weapons/da_sword_01.da_sword_01", "GrimVentory.ItemType.Weapon.Sword1H.Normal", false)
local goldType = described("/Game/TQ2/Items/Misc/da_item_gold.da_item_gold", "GrimVentory.ItemType.Currency", true)
local questType = described("/Game/TQ2/Items/Quest/da_quest_key.da_quest_key", "GrimVentory.ItemType.QuestItem", false)
instances.TQ2ItemDescription = { scrapType, potionType, swordType, goldType, questType }
check("auto pickup: categories recognised",
    categories[AutoPickup.categoryOf(categories, "/game/tq2/items/crafting/da_item_scrap")].Name == "Crafting materials"
    and categories[AutoPickup.categoryOf(categories, "grimventory.itemtype.consumable")].Name == "Potions"
    and categories[AutoPickup.categoryOf(categories, "grimventory.itemtype.weapon.sword1h.normal")].Name == "Equipment"
    and categories[AutoPickup.categoryOf(categories, "grimventory.itemtype.torso")].Name == "Equipment"
    and categories[AutoPickup.categoryOf(categories, "grimventory.itemtype.socketable.relic")].Name == "Charms & relics"
    and AutoPickup.categoryOf(categories, "grimventory.itemtype.currency") == nil
    and AutoPickup.categoryOf(categories, "grimventory.itemtype.questitem") == nil)
local pickupLog = {}
AutoPickup.apply(categories, { true, false, false, false }, function(line) pickupLog[#pickupLog + 1] = line end)
check("auto pickup materials on: only scrap switched on", scrapType.m_CanAutoPickup == true
    and potionType.m_CanAutoPickup == false and swordType.m_CanAutoPickup == false and goldType.m_CanAutoPickup == true)
check("auto pickup: overview logged once", #pickupLog == 3 and pickupLog[1]:match("Crafting materials=1") ~= nil)
AutoPickup.apply(categories, { true, true, false, false }, function() end)
check("auto pickup: potions added", potionType.m_CanAutoPickup == true and scrapType.m_CanAutoPickup == true)
AutoPickup.apply(categories, { false, false, false, false }, function() end)
AutoPickup.apply(categories, { true, true, true, true }, function() end)
check("auto pickup all on: quest items untouched", swordType.m_CanAutoPickup == true and questType.m_CanAutoPickup == false)
AutoPickup.apply(categories, { false, false, false, false }, function() end)
check("auto pickup off: original values back, gold untouched", scrapType.m_CanAutoPickup == false and swordType.m_CanAutoPickup == false
    and potionType.m_CanAutoPickup == false and goldType.m_CanAutoPickup == true)

-- Anvil anywhere: F6 opens the crafting window for the player, adding a crafting component if needed.
local anvil = { access = "none", opened = 0, closedByGame = 0 }
local craftingComponent = { IsValid = function() return true end, m_pInventory = { IsValid = function() return true end },
                            SetIsReplicated = function() end, Activate = function() end }
local anvilPlayerState = { IsValid = function() return true end, TryClearCraftingCache = function() anvil.cacheCleared = true end,
                           GetOrCreateCraftingCacheViewModel = function() end }
local anvilCharacter = {
    IsValid = function() return true end, PlayerState = anvilPlayerState, m_pCraftingComponent = nil,
    RootComponent = { GetRelativeTransform = function() return {} end },
    AddComponentByClass = function(_, class) anvil.addedClass = class; return craftingComponent end,
    GetCraftingAccess = function() return nil end,
    SetCraftingAccess = function(_, access) anvil.access = access end,
    ForceNetUpdate = function() end,
    OnCraftingUIOpened = function(_, provider) anvil.opened = anvil.opened + 1; anvil.provider = provider end,
    OnCraftingUIClosed = function() anvil.closedByGame = anvil.closedByGame + 1 end,
}
playerPawn = anvilCharacter
press("F6")
check("F6 opens the anvil: component added, player is its own access", anvil.opened == 1
    and anvil.addedClass ~= nil and anvilCharacter.m_pCraftingComponent == craftingComponent
    and anvil.access == anvilCharacter and anvil.provider == anvilCharacter and anvil.cacheCleared)
press("F6")
check("F6 again closes and clears the access", anvil.closedByGame == 1 and anvil.access == nil)
press("F6")
hooks["/Script/TQ2Gameplay.TQ2PlayerCharacter:OnCraftingUIClosed"].after(param(anvilCharacter))
check("closing with Esc clears the access", anvil.access == nil and anvil.opened == 2)

-- Caravan anywhere: F4 opens the caravan for the player (or the caravan it already reaches), closing clears the access.
local caravan = { access = "none", opened = 0, closedByGame = 0, viewModel = 0 }
local caravanCharacter = {
    IsValid = function() return true end,
    PlayerState = { IsValid = function() return true end, GetOrCreateCaravanViewModel = function() caravan.viewModel = caravan.viewModel + 1 end },
    GetCaravanAccess = function() return nil end,
    SetCaravanAccess = function(_, access) caravan.access = access end,
    ForceNetUpdate = function() end,
    OnCaravanInventoryOpened = function(_, access) caravan.opened = caravan.opened + 1; caravan.openedFor = access end,
    OnCaravanInventoryClosed = function() caravan.closedByGame = caravan.closedByGame + 1 end,
}
playerPawn = caravanCharacter
press("F4")
check("F4 opens the caravan: view model prepared, player is its own access", caravan.opened == 1 and caravan.viewModel == 1
    and caravan.access == caravanCharacter and caravan.openedFor == caravanCharacter)
press("F4")
check("F4 again closes the caravan and clears the access", caravan.closedByGame == 1 and caravan.access == nil)
press("F4")
hooks["/Script/TQ2Gameplay.TQ2PlayerCharacter:OnCaravanInventoryClosed"].after(param(caravanCharacter))
check("closing the caravan with Esc clears the access", caravan.access == nil and caravan.opened == 2)
local nearCaravan = { IsValid = function() return true end }
caravanCharacter.GetCaravanAccess = function() return nearCaravan end
press("F4")
check("next to a caravan it opens that one", caravan.openedFor == nearCaravan)
press("F4")

-- Equipment pickup by rarity: threshold, range, one try per item, items not filled yet wait.
local EquipmentPickup = require("equipment_pickup")
check("type name from the ground item", EquipmentPickup.typeNameOf(groundItem("da_sword_01_WorldItem_2147", 2, 0)) == "da_sword_01")
local equipment = EquipmentPickup.newState()
local magicSword = groundItem("da_sword_01_WorldItem_1", 1, 100)
local rareRing = groundItem("da_ring_02_WorldItem_1", 2, 100)
local farEpic = groundItem("da_sword_01_WorldItem_2", 4, 900)
local unfilled = groundItem("da_sword_01_WorldItem_3", nil, 50)
local potion = groundItem("da_item_potion_WorldItem", 3, 50)
for _, item in ipairs({ magicSword, rareRing, farEpic, unfilled, potion }) do EquipmentPickup.remember(equipment, item) end
EquipmentPickup.pass(equipment, looter, 400, { minRarity = 2 }, isEquipmentType)
check("equipment from Rare: rare ring picked up, magic sword not", rareRing.pickups == 1
    and rareRing.by == looter and rareRing.manual == false and magicSword.pickups == 0)
check("out of range and not filled yet: wait; no potion", farEpic.pickups == 0 and unfilled.pickups == 0
    and potion.pickups == 0)
unfilled.slot.ItemHandle.pItem = { IsValid = function() return true end, m_Rarity = 3 }
EquipmentPickup.pass(equipment, looter, 400, { minRarity = 2 }, isEquipmentType)
check("content filled in: picked up now; ring (inventory full) not tried again",
    unfilled.pickups == 1 and rareRing.pickups == 1)
farEpic.K2_GetActorLocation = function() return { X = 300, Y = 0, Z = 0 } end
EquipmentPickup.pass(equipment, looter, 400, { minRarity = 2 }, isEquipmentType)
check("came into range: picked up", farEpic.pickups == 1)
local newTypeAxe = groundItem("da_axe_09_WorldItem_1", 3, 100)
EquipmentPickup.remember(equipment, newTypeAxe)
EquipmentPickup.pass(equipment, looter, 400, { minRarity = 2 }, isEquipmentType)
equipmentKinds.da_axe_09 = true -- the next item type scan found the new type
EquipmentPickup.pass(equipment, looter, 400, { minRarity = 2 }, isEquipmentType)
check("new, not yet scanned type: waits for the scan instead of staying on the ground", newTypeAxe.pickups == 1)
EquipmentPickup.pass(equipment, looter, 400, {}, isEquipmentType)
check("equipment off: list cleared", #equipment.items == 0)
local hoover = { IsValid = function() return true end, m_Range = 650, m_pOwningPlayer = looter.PlayerState }
instances.GrimItemHooverComponent = { hoover }
check("range from the player's hoover", EquipmentPickup.hooverRange(equipment, looter, 400) == 650)
instances.GrimItemHooverComponent = nil

-- Menu tabs: sections by header into tabs; unknown sections go to the last tab, empty tabs are left out.
local MenuTabs = require("menu_tabs")
local built = MenuTabs.build({ { header = "A" }, { label = "a1" }, { header = "New" }, { label = "n1" },
    { header = "B" }, { label = "b1" } }, { { Name = "One", Sections = { "A" } }, { Name = "Empty", Sections = { "X" } },
    { Name = "Two", Sections = { "B" } } })
check("tabs: sections assigned, unknown ones in the last tab, empty tab left out", #built == 2
    and built[1].name == "One" and #built[1].entries == 2 and built[2].name == "Two" and #built[2].entries == 4
    and built[2].entries[1].header == "New")

-- Gold multiplier on its own: only piles created during an enemy drop, only when the factor is not 1.
local GoldMultiplier = require("gold_multiplier")
local goldFactor, clock = 1, 0
local gold = GoldMultiplier.handler(function() return goldFactor end, function(line) logLines[#logLines + 1] = line end,
    function() return clock end)
local onWorldItem = newObjectCallbacks["/Script/TQ2Gameplay.TQ2WorldItem"]
local function goldPile(amount)
    local slot = { Num = amount }
    return {
        slot = slot,
        IsValid = function() return true end,
        GetFullName = function() return "bp_tq2_world_loot_item_C /Game/Level.da_item_gold_WorldItem_3" end,
        OnUpdateWorldRepresentation = function() end,
        m_ContainerData = { ItemSlots = container({ slot }) },
    }
end
local enemy = { IsValid = function() return true end, IsA = function(_, class) return class:match("AICharacter") ~= nil end,
                GetFullName = function() return "bp_ai_default_character_C /Game/Level.Skeleton_1" end }
local chest = { IsValid = function() return true end, IsA = function() return false end,
                GetFullName = function() return "TQ2Chest /Game/Level.Chest_1" end }
local function dropFrom(source) return { source = function() return source end } end

goldFactor = 3
gold.before(dropFrom(enemy))
clock = 0.5 -- the game spawns the dropped items a moment after LaunchDropList returned
local enemyPile = goldPile(10)
onWorldItem(enemyPile)
check("gold x3: pile shortly after an enemy drop 10 -> 30", enemyPile.slot.Num == 30)
clock = 10
gold.before(dropFrom(chest))
local chestPile = goldPile(10)
onWorldItem(chestPile)
check("gold: pile from a chest unchanged", chestPile.slot.Num == 10)
clock = 20
local loadedPile = goldPile(10)
onWorldItem(loadedPile)
check("gold: pile when loading (no enemy drop shortly before) unchanged", loadedPile.slot.Num == 10)
goldFactor = 1
gold.before(dropFrom(enemy))
local normalPile = goldPile(10)
onWorldItem(normalPile)
check("gold x1: unchanged", normalPile.slot.Num == 10)
local goldLines = 0
for _, line in ipairs(logLines) do if line:match("Gold") then goldLines = goldLines + 1 end end
check("gold: no log while everything works", goldLines == 0)

for _, line in ipairs(logLines) do
    if line:match("error") then check("no error in the log: " .. line, false) end
end
