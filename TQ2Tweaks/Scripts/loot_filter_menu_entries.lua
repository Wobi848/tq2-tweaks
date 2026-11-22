-- Menu rows for the loot filter rules (tab "Filter"): per rule on/off, rarity from and how many affixes are needed.
-- The rows are refilled whenever the rules are (re)loaded. A change only queues an edit (key callbacks only change Lua
-- values); the game loop writes it into loot_filter.lua, which is then reloaded.
local LootFilterMenuEntries = {}

LootFilterMenuEntries.HEADER = "Loot filter rules"

-- false = any rarity.
local RARITIES = { false, "Common", "Magic", "Rare", "Infrequent", "Epic", "Legendary" }
local MAX_NEEDED = 4

local function rarityIndex(rule)
    for index, name in ipairs(RARITIES) do
        if name == (rule.rarityName or false) then
            return index
        end
    end
    return 1
end

-- The section as it is built at start: the header and an info row (a tab needs at least one selectable row).
function LootFilterMenuEntries.section(describeFile)
    return {
        { header = LootFilterMenuEntries.HEADER },
        { label = "Rules in loot_filter.lua", value = describeFile, change = function() end },
    }
end

local function ruleRows(rule, queueEdit)
    local rows = {
        { label = rule.name,
          value = function() return rule.enabled and "On" or "Off" end,
          change = function() queueEdit(rule.name, { enabled = not rule.enabled }) end },
        { label = "   rarity from",
          value = function() return rule.rarityName or "Any" end,
          change = function(direction)
              local index = (rarityIndex(rule) - 1 + direction) % #RARITIES + 1
              queueEdit(rule.name, { minRarity = RARITIES[index] })
          end },
    }
    if rule.affixCount > 0 then
        rows[#rows + 1] = {
            label = "   affixes needed",
            value = function() return string.format("%d of %d", rule.needed, rule.affixCount) end,
            change = function(direction)
                local most = math.min(MAX_NEEDED, rule.affixCount)
                local needed = math.max(1, math.min(most, rule.needed + direction))
                if needed ~= rule.needed then
                    queueEdit(rule.name, { needed = needed })
                end
            end }
    end
    return rows
end

-- Replaces the rule rows of the tab's entry list (keeps the header and the info row at the start).
function LootFilterMenuEntries.fill(entries, rules, queueEdit)
    for index = #entries, 3, -1 do
        entries[index] = nil
    end
    for _, rule in ipairs(rules) do
        for _, row in ipairs(ruleRows(rule, queueEdit)) do
            entries[#entries + 1] = row
        end
    end
end

-- Entry list of the tab that holds the loot filter section, or nil if no tab does.
function LootFilterMenuEntries.tabEntries(menuTabs)
    for _, tab in ipairs(menuTabs) do
        if tab.entries[1] and tab.entries[1].header == LootFilterMenuEntries.HEADER then
            return tab.entries
        end
    end
    return nil
end

return LootFilterMenuEntries
