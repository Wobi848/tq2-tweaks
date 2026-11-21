-- Draws the damage meter as a panel at the screen edge, below the game's menus (player layer): text lines,
-- optionally a DPS graph of the last seconds and the share per damage type.
local Player = require("player")
local UI = require("ui")

local DamageMeterWidget = {}

local LINE_COUNT = 5
local TYPE_ROWS = 4
local SKILL_ROWS = 5
local TRACK_COLOR = { R = 0, G = 0, B = 0, A = 0.5 }

local widgetState = nil

-- 1234 -> "1234", 12345 -> "12.3k", 1234567 -> "1.23M"
function DamageMeterWidget.formatNumber(value)
    if value >= 1e6 then
        return string.format("%.2fM", value / 1e6)
    elseif value >= 1e4 then
        return string.format("%.1fk", value / 1e3)
    end
    return string.format("%d", math.floor(value + 0.5))
end

-- The text lines shown for a summary. After the fight the current DPS is replaced by the average.
function DamageMeterWidget.lines(summary)
    local format = DamageMeterWidget.formatNumber
    local critPercent = summary.hits > 0 and math.floor(summary.crits * 100 / summary.hits + 0.5) or 0
    return {
        summary.ended and "DAMAGE  ·  last fight" or "DAMAGE",
        summary.ended and ("Average DPS  " .. format(summary.averageDps)) or ("DPS  " .. format(summary.dps)),
        string.format("Total  %s  (%d s)", format(summary.total), math.floor(summary.duration + 0.5)),
        string.format("Hits %d  ·  Crits %d (%d%%)", summary.hits, summary.crits, critPercent),
        "Highest hit  " .. format(summary.highestHit),
    }
end

-- Colour of a damage type by name ("Fire" -> red ...); patterns from config, default for unknown types.
function DamageMeterWidget.typeColor(style, name)
    local lower = name:lower()
    for _, entry in ipairs(style.DamageTypeColors) do
        if lower:find(entry.Match, 1, true) then
            return entry.Color
        end
    end
    return style.DamageTypeDefaultColor
end

-- Colour of the skill at `rank` (1 = most damage); the same ranks get the same colours in the detail window.
function DamageMeterWidget.skillColor(style, rank)
    return style.DamageSkillColors[rank] or style.DamageSkillRestColor
end

local function addGraph(list, tree, style, seconds)
    local row = UI.construct("HorizontalBox", tree)
    list:AddChildToVerticalBox(row):SetPadding({ Left = 0, Top = 6, Right = 0, Bottom = 2 })
    local bars = {}
    for index = 1, seconds do
        local outer, bar = UI.newFillBar(tree, style.DamageGraphBarWidth, style.DamageGraphHeight, TRACK_COLOR, true)
        row:AddChildToHorizontalBox(outer):SetPadding({ Left = 0, Top = 0, Right = 1, Bottom = 0 })
        bars[index] = bar
    end
    return bars
end

-- Rows of "name  [bar]  percent" for shares (damage types, skills).
local function addShareRows(list, tree, style, count)
    local rows = {}
    for index = 1, count do
        local row = UI.construct("HorizontalBox", tree)
        list:AddChildToVerticalBox(row):SetPadding({ Left = 0, Top = 2, Right = 0, Bottom = 0 })
        local nameBox = UI.construct("SizeBox", tree)
        nameBox:SetWidthOverride(style.DamageTypeNameWidth)
        local name = UI.newText(tree, style.DamageMeterFontSize - 2, style.MenuTextColor, UI.JUSTIFY_LEFT)
        nameBox:AddChild(name)
        row:AddChildToHorizontalBox(nameBox)
        local outer, bar = UI.newFillBar(tree, style.DamageTypeBarWidth, style.DamageMeterFontSize - 6, TRACK_COLOR, false)
        row:AddChildToHorizontalBox(outer):SetVerticalAlignment(UI.VALIGN_CENTER)
        local percent = UI.newText(tree, style.DamageMeterFontSize - 2, style.MenuTextColor, UI.JUSTIFY_LEFT)
        row:AddChildToHorizontalBox(percent):SetPadding({ Left = 6, Top = 0, Right = 0, Bottom = 0 })
        rows[index] = { row = row, name = name, bar = bar, percent = percent }
    end
    return rows
end

local function create(style, position, options, graphSeconds)
    local gameInstance = FindFirstOf("GameInstance")
    local playerController = Player.controller()
    if not UI.isUsable(gameInstance) or not UI.isUsable(playerController) then
        return nil
    end
    local userWidget, tree, canvas = UI.newRootWidget(gameInstance)
    local panel = UI.construct("Border", tree)
    panel:SetBrushColor(style.DamageMeterBackground)
    panel:SetPadding({ Left = 14, Top = 10, Right = 14, Bottom = 10 })
    UI.placeOnCanvas(canvas, panel, position.Anchor, position.Alignment, position.Offset)
    local list = UI.construct("VerticalBox", tree)
    panel:AddChild(list)
    local texts = {}
    for index = 1, LINE_COUNT do
        local color = index == 1 and style.MenuHeaderColor or style.MenuTextColor
        texts[index] = UI.newText(tree, style.DamageMeterFontSize, color, UI.JUSTIFY_LEFT)
        list:AddChildToVerticalBox(texts[index])
    end
    local state = { userWidget = userWidget, texts = texts }
    if options.graph then
        state.graph = addGraph(list, tree, style, graphSeconds)
    end
    if options.types then
        state.types = addShareRows(list, tree, style, TYPE_ROWS)
    end
    if options.skills then
        local header = UI.newText(tree, style.DamageMeterFontSize - 2, style.MenuHeaderColor, UI.JUSTIFY_LEFT)
        header:SetText(FText("Skills"))
        list:AddChildToVerticalBox(header):SetPadding({ Left = 0, Top = 6, Right = 0, Bottom = 0 })
        state.skills = addShareRows(list, tree, style, SKILL_ROWS)
    end
    UI.addToPlayerScreen(userWidget, playerController)
    return state
end

local function fillGraph(bars, values, color)
    local highest = 0
    for _, value in ipairs(values) do highest = math.max(highest, value) end
    for index, bar in ipairs(bars) do
        UI.setFill(bar, highest > 0 and (values[index] or 0) / highest or 0, color)
    end
end

-- colorOf(name, rank) gives the bar colour of an entry.
local function fillShares(rows, entries, colorOf)
    for index, row in ipairs(rows) do
        local entry = entries[index]
        UI.setShown(row.row, entry ~= nil)
        if entry ~= nil then
            row.name:SetText(FText(entry.name))
            UI.setFill(row.bar, entry.share, colorOf(entry.name, index))
            row.percent:SetText(FText(string.format("%d%%", math.floor(entry.share * 100 + 0.5))))
        end
    end
end

-- Removes the panel; the next show() rebuilds it (e.g. after the position or the options changed).
function DamageMeterWidget.reset()
    if widgetState ~= nil then
        UI.remove(widgetState.userWidget)
        widgetState = nil
    end
end

-- Shows the summary at `position` (an entry of config.DamageMeterPositions); nil (meter off or no hit yet)
-- removes the panel. options = { graph = bool, types = bool, skills = bool }. Call on the game thread.
function DamageMeterWidget.show(summary, style, position, options)
    if summary == nil then
        DamageMeterWidget.reset()
        return
    end
    if widgetState == nil or not UI.isShowing(widgetState.userWidget) then
        widgetState = create(style, position, options, #summary.graph)
        if widgetState == nil then
            return
        end
    end
    for index, line in ipairs(DamageMeterWidget.lines(summary)) do
        widgetState.texts[index]:SetText(FText(line))
    end
    if widgetState.graph then
        fillGraph(widgetState.graph, summary.graph, summary.ended and style.DamageGraphEndedColor or style.DamageGraphColor)
    end
    if widgetState.types then
        fillShares(widgetState.types, summary.types, function(name) return DamageMeterWidget.typeColor(style, name) end)
    end
    if widgetState.skills then
        fillShares(widgetState.skills, summary.skills, function(_, rank)
            return DamageMeterWidget.skillColor(style, rank)
        end)
    end
end

return DamageMeterWidget
