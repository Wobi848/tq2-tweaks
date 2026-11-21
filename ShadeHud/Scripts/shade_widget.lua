-- Builds the UMG widget for the shade display at runtime and fills it with values.
local Player = require("player")
local UI = require("ui")

local ShadeWidget = {}

local BAR_TRACK_COLOR = { R = 0, G = 0, B = 0, A = 0.6 }

local widgetState = nil

local function create(layout)
    local gameInstance = FindFirstOf("GameInstance")
    local playerController = Player.controller()
    if not UI.isUsable(gameInstance) or not UI.isUsable(playerController) then
        return nil
    end
    local userWidget, tree, canvas = UI.newRootWidget(gameInstance)

    local column = UI.construct("VerticalBox", tree)
    UI.placeOnCanvas(canvas, column, { X = layout.anchorX, Y = layout.anchorY }, { X = 0.5, Y = 0 },
        { X = layout.offsetX, Y = layout.offsetY })

    local barRow = UI.construct("HorizontalBox", tree)
    column:AddChildToVerticalBox(barRow):SetHorizontalAlignment(UI.ALIGN_CENTER)
    UI.setShown(barRow, layout.showBars)

    local label = UI.newText(tree, layout.fontSize, layout.textColor, UI.JUSTIFY_CENTER)
    column:AddChildToVerticalBox(label):SetHorizontalAlignment(UI.ALIGN_CENTER)
    UI.setShown(label, layout.showNumbers)

    UI.addToPlayerScreen(userWidget, playerController)

    return { userWidget = userWidget, tree = tree, barRow = barRow, label = label, bars = {} }
end

local function rebuildBars(state, count, layout)
    state.barRow:ClearChildren()
    state.bars = {}
    for index = 1, count do
        local outer, bar = UI.newFillBar(state.tree, layout.barWidth, layout.barHeight, BAR_TRACK_COLOR, false)
        local barSlot = state.barRow:AddChildToHorizontalBox(outer)
        local halfSpacing = layout.barSpacing / 2
        barSlot:SetPadding({ Left = halfSpacing, Top = 0, Right = halfSpacing, Bottom = 4 })
        state.bars[index] = bar
    end
end

local function ensureWidget(layout)
    if widgetState ~= nil and UI.isShowing(widgetState.userWidget) then
        return widgetState
    end
    widgetState = create(layout)
    return widgetState
end

local function formatLabel(shades)
    if shades.current >= shades.maximum then
        return string.format("%d/%d", shades.current, shades.maximum)
    end
    return string.format("%d/%d  ·  %d%%", shades.current, shades.maximum,
        -- Small epsilon against floating point leftovers (1 - 0.8 = 0.1999...), otherwise 20% shows as 19%.
        math.floor(shades.progress * 100 + 1e-6))
end

local function fillBars(state, shades, layout)
    for index, bar in ipairs(state.bars) do
        if index <= shades.current then
            UI.setFill(bar, 1, layout.fullColor)
        elseif index == shades.current + 1 then
            UI.setFill(bar, shades.progress, layout.chargingColor)
        else
            UI.setFill(bar, 0, layout.chargingColor)
        end
    end
end

-- Removes the widget; the next show() rebuilds it with the current layout.
function ShadeWidget.reset()
    if widgetState ~= nil then
        UI.remove(widgetState.userWidget)
    end
    widgetState = nil
end

-- Shows the shades; shades == nil hides the display.
function ShadeWidget.show(shades, layout)
    if shades == nil then
        if widgetState ~= nil and UI.isUsable(widgetState.userWidget) then
            widgetState.userWidget:SetVisibility(UI.VISIBILITY_COLLAPSED)
            widgetState.shownKey = nil
        end
        return
    end
    local state = ensureWidget(layout)
    if state == nil then
        return
    end
    -- The display loop runs several times per second; bars and text only change with the values (1 % steps).
    local key = string.format("%d/%d/%.2f", shades.current, shades.maximum, shades.progress)
    if state.shownKey == key then
        return
    end
    state.userWidget:SetVisibility(UI.VISIBILITY_HIT_TEST_INVISIBLE)
    if #state.bars ~= shades.maximum then
        rebuildBars(state, shades.maximum, layout)
    end
    fillBars(state, shades, layout)
    state.label:SetText(FText(formatLabel(shades)))
    state.shownKey = key
end

return ShadeWidget
