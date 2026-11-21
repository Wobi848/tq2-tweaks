-- Keyboard menu: EditKey opens/closes, Page Up/Down switches the tab, up/down selects a row, left/right changes
-- its value. Key callbacks only change Lua values; menu_widget.lua draws on the game thread.
--
-- menu.tabs is a list of { name, entries }; menu.entries always points at the entries of the active tab.
-- An entry is { label = "Text", value = function() return "Shown" end, change = function(direction, fast) }
-- or a section header { header = "Text" }, which selection skips.
local Menu = {}

local function onlyWhileOpen(menu, action)
    return function()
        if menu.open then
            action()
        end
    end
end

local function step(menu, index, direction)
    return (index - 1 + direction) % #menu.entries + 1
end

local function moveSelection(menu, direction)
    local index = step(menu, menu.selected, direction)
    while menu.entries[index].header do
        index = step(menu, index, direction)
    end
    menu.selected = index
end

-- Activates tab `index` and selects its first row.
local function showTab(menu, index)
    menu.tab = index
    menu.entries = menu.tabs[index].entries
    menu.selected = #menu.entries
    moveSelection(menu, 1)
end

local function switchTab(menu, direction)
    showTab(menu, (menu.tab - 1 + direction) % #menu.tabs + 1)
end

local function changeSelected(menu, direction, fast)
    menu.entries[menu.selected].change(direction, fast)
end

local function bindNavigation(menu)
    RegisterKeyBind(Key.UP_ARROW, onlyWhileOpen(menu, function() moveSelection(menu, -1) end))
    RegisterKeyBind(Key.DOWN_ARROW, onlyWhileOpen(menu, function() moveSelection(menu, 1) end))
    RegisterKeyBind(Key.LEFT_ARROW, onlyWhileOpen(menu, function() changeSelected(menu, -1, false) end))
    RegisterKeyBind(Key.RIGHT_ARROW, onlyWhileOpen(menu, function() changeSelected(menu, 1, false) end))
    RegisterKeyBind(Key.LEFT_ARROW, { ModifierKey.SHIFT }, onlyWhileOpen(menu, function() changeSelected(menu, -1, true) end))
    RegisterKeyBind(Key.RIGHT_ARROW, { ModifierKey.SHIFT }, onlyWhileOpen(menu, function() changeSelected(menu, 1, true) end))
    RegisterKeyBind(Key.PAGE_DOWN, onlyWhileOpen(menu, function() switchTab(menu, 1) end))
    RegisterKeyBind(Key.PAGE_UP, onlyWhileOpen(menu, function() switchTab(menu, -1) end))
end

-- Registers the keys. tabs: list of { name, entries } (see menu_tabs.lua). onClose is called when the menu closes
-- (e.g. to save).
function Menu.register(editKeyName, tabs, onClose, log)
    local menu = { open = false, tabs = tabs }
    showTab(menu, 1)
    local toggleKey = Key[editKeyName]
    if toggleKey == nil then
        log("Unknown EditKey '" .. tostring(editKeyName) .. "', menu not available")
        return menu
    end
    RegisterKeyBind(toggleKey, function()
        menu.open = not menu.open
        if not menu.open then
            onClose()
        end
    end)
    bindNavigation(menu)
    return menu
end

return Menu
