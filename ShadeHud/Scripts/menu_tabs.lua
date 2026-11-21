-- Groups the menu entries into tabs. Entries come as one list with section headers ({ header = "..." });
-- config.MenuTabs says which sections go into which tab. Sections not named in any tab land in the last tab,
-- so a new section never disappears from the menu.
local MenuTabs = {}

-- Splits the flat entry list into sections: { header = "Rewards", entries = { header entry, rows... } }.
local function sections(entries)
    local result, current = {}, nil
    for _, entry in ipairs(entries) do
        if entry.header then
            current = { header = entry.header, entries = { entry } }
            result[#result + 1] = current
        elseif current ~= nil then
            current.entries[#current.entries + 1] = entry
        end
    end
    return result
end

-- tabDefinitions: list of { Name = "Gameplay", Sections = { "Rewards", "Speed" } }. Returns list of
-- { name, entries } in tab order; tabs without entries are left out.
function MenuTabs.build(entries, tabDefinitions)
    local tabOfSection = {}
    for index, definition in ipairs(tabDefinitions) do
        for _, header in ipairs(definition.Sections) do
            tabOfSection[header] = index
        end
    end
    local tabEntries = {}
    for index = 1, #tabDefinitions do tabEntries[index] = {} end
    for _, section in ipairs(sections(entries)) do
        local target = tabEntries[tabOfSection[section.header] or #tabDefinitions]
        for _, entry in ipairs(section.entries) do
            target[#target + 1] = entry
        end
    end
    local tabs = {}
    for index, definition in ipairs(tabDefinitions) do
        if #tabEntries[index] > 0 then
            tabs[#tabs + 1] = { name = definition.Name, entries = tabEntries[index] }
        end
    end
    return tabs
end

return MenuTabs
