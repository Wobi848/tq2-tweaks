-- Draws the keyboard menu as a panel with a dark background in the middle of the screen: title, tab strip (active
-- tab highlighted) and the rows of the active tab. Switching tabs rebuilds the panel.
local Player = require("player")
local UI = require("ui")

local MenuWidget = {}

-- In the player layer like the HUD widgets, above them but below the game's UI (1000): the game's own menus
-- (pause, inventory) cover it instead of the other way round.
local MENU_Z_ORDER = 10
local HINT_TEXT = "PgUp/PgDn: tab    Up/Down: select    Left/Right: change (Shift: faster)    %s: save and close"

local widgetState = nil

local function addRow(list, tree, style, labelWidth)
    local row = UI.construct("HorizontalBox", tree)
    local labelBox = UI.construct("SizeBox", tree)
    labelBox:SetWidthOverride(labelWidth)
    local label = UI.newText(tree, style.MenuFontSize, style.MenuTextColor, UI.JUSTIFY_LEFT)
    labelBox:AddChild(label)
    row:AddChildToHorizontalBox(labelBox)
    local value = UI.newText(tree, style.MenuFontSize, style.MenuTextColor, UI.JUSTIFY_LEFT)
    row:AddChildToHorizontalBox(value)
    list:AddChildToVerticalBox(row):SetPadding({ Left = 0, Top = 2, Right = 0, Bottom = 2 })
    return { label = label, value = value }
end

local function addHeader(list, tree, style, text)
    local header = UI.newText(tree, style.MenuHeaderSize, style.MenuHeaderColor, UI.JUSTIFY_LEFT)
    header:SetText(FText(string.upper(text)))
    list:AddChildToVerticalBox(header):SetPadding({ Left = 0, Top = 10, Right = 0, Bottom = 2 })
end

local function addTabStrip(list, tree, style, menu)
    local strip = UI.construct("HorizontalBox", tree)
    list:AddChildToVerticalBox(strip):SetPadding({ Left = 0, Top = 0, Right = 0, Bottom = 6 })
    for index, tab in ipairs(menu.tabs) do
        local active = index == menu.tab
        local text = UI.newText(tree, style.MenuHeaderSize, active and style.MenuSelectedColor or style.MenuHintColor,
            UI.JUSTIFY_LEFT)
        text:SetText(FText(active and ("[ " .. tab.name .. " ]") or tab.name))
        strip:AddChildToHorizontalBox(text):SetPadding({ Left = 0, Top = 0, Right = 18, Bottom = 0 })
    end
end

local function create(menu, style, outer, playerController)
    local userWidget, tree, canvas = UI.newRootWidget(outer)

    local panel = UI.construct("Border", tree)
    panel:SetBrushColor(style.MenuBackground)
    panel:SetPadding({ Left = 28, Top = 20, Right = 28, Bottom = 20 })
    UI.placeOnCanvas(canvas, panel, { X = 0.5, Y = 0.5 }, { X = 0.5, Y = 0.5 }, { X = 0, Y = style.MenuOffsetY })

    local list = UI.construct("VerticalBox", tree)
    panel:AddChild(list)

    local title = UI.newText(tree, style.MenuTitleSize, style.MenuSelectedColor, UI.JUSTIFY_LEFT)
    title:SetText(FText(style.MenuTitle))
    list:AddChildToVerticalBox(title):SetPadding({ Left = 0, Top = 0, Right = 0, Bottom = 8 })
    addTabStrip(list, tree, style, menu)

    local rows = {}
    for index, entry in ipairs(menu.entries) do
        if entry.header then
            addHeader(list, tree, style, entry.header)
        else
            rows[index] = addRow(list, tree, style, style.MenuLabelWidth)
        end
    end

    local hint = UI.newText(tree, style.MenuHintSize, style.MenuHintColor, UI.JUSTIFY_LEFT)
    hint:SetText(FText(string.format(HINT_TEXT, style.EditKey)))
    list:AddChildToVerticalBox(hint):SetPadding({ Left = 0, Top = 14, Right = 0, Bottom = 0 })

    UI.addToPlayerScreen(userWidget, playerController, MENU_Z_ORDER)
    return { userWidget = userWidget, rows = rows, tab = menu.tab }
end

local function fillRows(menu, style)
    for index, row in pairs(widgetState.rows) do
        local entry = menu.entries[index]
        local selected = index == menu.selected
        local color = selected and style.MenuSelectedColor or style.MenuTextColor
        row.label:SetText(FText((selected and "> " or "   ") .. entry.label))
        row.value:SetText(FText("<  " .. entry.value() .. "  >"))
        UI.setTextColor(row.label, color)
        UI.setTextColor(row.value, color)
    end
end

-- Removes the menu panel; the next update() rebuilds it while the menu is open.
function MenuWidget.reset()
    if widgetState ~= nil then
        UI.remove(widgetState.userWidget)
        widgetState = nil
    end
end

-- Shows the menu while menu.open is set; otherwise removes it.
function MenuWidget.update(menu, style)
    if not menu.open then
        MenuWidget.reset()
        return
    end
    if widgetState ~= nil and widgetState.tab ~= menu.tab then
        MenuWidget.reset()
    end
    if widgetState == nil or not UI.isShowing(widgetState.userWidget) then
        local gameInstance = FindFirstOf("GameInstance")
        local playerController = Player.controller()
        if not UI.isUsable(gameInstance) or not UI.isUsable(playerController) then
            return
        end
        widgetState = create(menu, style, gameInstance, playerController)
    end
    fillRows(menu, style)
end

return MenuWidget
