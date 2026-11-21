-- Shared building blocks for the UMG widgets built at runtime.
local UI = {}

UI.VISIBILITY_VISIBLE = 0
UI.VISIBILITY_COLLAPSED = 1
UI.VISIBILITY_HIT_TEST_INVISIBLE = 3
UI.ALIGN_LEFT = 1
UI.ALIGN_CENTER = 2
UI.ALIGN_FILL = 0
UI.VALIGN_FILL = 0
UI.VALIGN_TOP = 1
UI.VALIGN_CENTER = 2
UI.VALIGN_BOTTOM = 3
UI.JUSTIFY_LEFT = 0
UI.JUSTIFY_CENTER = 1
UI.JUSTIFY_RIGHT = 2
local SLATE_COLOR_USE_SPECIFIED = 0

function UI.construct(className, outer)
    return StaticConstructObject(StaticFindObject("/Script/UMG." .. className), outer)
end

function UI.isUsable(object)
    return object ~= nil and object:IsValid()
end

function UI.setShown(widget, shown)
    widget:SetVisibility(shown and UI.VISIBILITY_VISIBLE or UI.VISIBILITY_COLLAPSED)
end

function UI.setTextColor(textBlock, color)
    textBlock:SetColorAndOpacity({ SpecifiedColor = color, ColorUseRule = SLATE_COLOR_USE_SPECIFIED })
end

-- Text with a black shadow so it stays readable on light and dark backgrounds.
function UI.newText(tree, size, color, justification)
    local textBlock = UI.construct("TextBlock", tree)
    local font = textBlock.Font
    font.Size = size
    textBlock:SetFont(font)
    UI.setTextColor(textBlock, color)
    textBlock:SetShadowOffset({ X = 2, Y = 2 })
    textBlock:SetShadowColorAndOpacity({ R = 0, G = 0, B = 0, A = 1.0 })
    textBlock:SetJustification(justification)
    return textBlock
end

-- New, empty UserWidget with a CanvasPanel as root. Returns userWidget, tree, canvas.
function UI.newRootWidget(outer)
    local userWidget = UI.construct("UserWidget", outer)
    local tree = UI.construct("WidgetTree", userWidget)
    userWidget.WidgetTree = tree
    local canvas = UI.construct("CanvasPanel", tree)
    tree.RootWidget = canvas
    return userWidget, tree, canvas
end

-- Places child on the canvas at a fixed screen position: anchor (0..1), alignment (0..1), offset in pixels.
function UI.placeOnCanvas(canvas, child, anchor, alignment, offset)
    local slot = canvas:AddChildToCanvas(child)
    slot:SetAnchors({ Minimum = anchor, Maximum = anchor })
    slot:SetAlignment(alignment)
    slot:SetPosition(offset)
    slot:SetAutoSize(true)
    return slot
end

-- AddToViewport always sits above the game UI. TQ2 uses the Lyra UI system, whose layout lives in the player
-- layer via AddToPlayerScreen (z-order 1000). HUD elements go below it there: in combat that UI is transparent,
-- while opaque menus (pause, skill tree) cover them.
-- zOrder orders our own widgets among each other; it must stay below 1000 (the game's UI layout).
function UI.addToPlayerScreen(userWidget, playerController, zOrder)
    userWidget:SetVisibility(UI.VISIBILITY_HIT_TEST_INVISIBLE)
    userWidget:SetOwningPlayer(playerController)
    userWidget:AddToPlayerScreen(zOrder or 0)
end

-- A bar made of two colour areas: a dark track with a fill of variable size, growing from the left
-- (horizontal) or from the bottom (vertical). Deliberately not a ProgressBar: its built-in blue tint could not be
-- overridden in TQ2, while Border colours work reliably. Returns the outer widget and the bar for UI.setFill.
function UI.newFillBar(tree, width, height, trackColor, vertical)
    local outer = UI.construct("SizeBox", tree)
    outer:SetWidthOverride(width)
    outer:SetHeightOverride(height)
    local track = UI.construct("Border", tree)
    track:SetBrushColor(trackColor)
    track:SetPadding({ Left = 0, Top = 0, Right = 0, Bottom = 0 })
    track:SetHorizontalAlignment(vertical and UI.ALIGN_FILL or UI.ALIGN_LEFT)
    track:SetVerticalAlignment(vertical and UI.VALIGN_BOTTOM or UI.VALIGN_FILL)
    outer:AddChild(track)
    local fillBox = UI.construct("SizeBox", tree)
    if vertical then fillBox:SetHeightOverride(0) else fillBox:SetWidthOverride(0) end
    track:AddChild(fillBox)
    local fill = UI.construct("Border", tree)
    fillBox:AddChild(fill)
    return outer, { fillBox = fillBox, fill = fill, length = vertical and height or width, vertical = vertical }
end

-- fraction 0..1 of the bar filled with `color`.
function UI.setFill(bar, fraction, color)
    local size = bar.length * math.max(0, math.min(1, fraction))
    if bar.vertical then bar.fillBox:SetHeightOverride(size) else bar.fillBox:SetWidthOverride(size) end
    bar.fill:SetBrushColor(color)
end

function UI.isShowing(userWidget)
    return UI.isUsable(userWidget) and userWidget:IsInViewport()
end

function UI.remove(userWidget)
    if UI.isUsable(userWidget) then
        userWidget:RemoveFromParent()
    end
end

return UI
