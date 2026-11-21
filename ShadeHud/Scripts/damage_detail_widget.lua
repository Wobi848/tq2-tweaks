-- The damage meter's detail window (toggled by a key): a large graph of the last seconds stacked by skill with a
-- line at the average DPS, a table per skill and the share of every damage type. Above the skill bar in the
-- player layer, below the game's menus. Built only while it is open.
local Player = require("player")
local UI = require("ui")
local DamageMeterWidget = require("damage_meter_widget")

local DamageDetailWidget = {}

local TRACK_COLOR = { R = 0, G = 0, B = 0, A = 0.5 }
local AVERAGE_LINE_HEIGHT = 2
local SWATCH_SIZE = 10
-- Skill table: title and width of each column after the colour swatch.
local SKILL_COLUMNS = {
    { title = "Skill", width = 190, justify = UI.JUSTIFY_LEFT },
    { title = "Damage", width = 90, justify = UI.JUSTIFY_RIGHT },
    { title = "DPS", width = 80, justify = UI.JUSTIFY_RIGHT },
    { title = "Share", width = 70, justify = UI.JUSTIFY_RIGHT },
    { title = "Hits", width = 60, justify = UI.JUSTIFY_RIGHT },
    { title = "Crit", width = 60, justify = UI.JUSTIFY_RIGHT },
    { title = "Highest", width = 90, justify = UI.JUSTIFY_RIGHT },
}
local TYPE_NAME_WIDTH = 150
local TYPE_BAR_WIDTH = 100
local TYPE_NUMBER_WIDTH = 80

local widgetState = nil

local function percent(share)
    return string.format("%d%%", math.floor(share * 100 + 0.5))
end

-- 83 -> "1:23"
local function minutes(seconds)
    local whole = math.floor(seconds + 0.5)
    return string.format("%d:%02d", whole // 60, whole % 60)
end

-- Text of the window's title line.
function DamageDetailWidget.title(details)
    if details.total == 0 then
        return "DAMAGE DETAILS  ·  no fight yet"
    end
    return details.ended and "DAMAGE DETAILS  ·  last fight" or "DAMAGE DETAILS  ·  current fight"
end

-- Text of the line below the title.
function DamageDetailWidget.overview(details)
    local format = DamageMeterWidget.formatNumber
    local critShare = details.hits > 0 and details.crits / details.hits or 0
    return string.format("Duration %s  ·  Total %s  ·  Average DPS %s  ·  Best second %s  ·  Hits %d  ·  Crits %s",
        minutes(details.duration), format(details.total), format(details.averageDps), format(details.peakDps),
        details.hits, percent(critShare))
end

-- Values of a skill table row, in the order of SKILL_COLUMNS.
function DamageDetailWidget.skillCells(skill)
    local format = DamageMeterWidget.formatNumber
    return { skill.name, format(skill.damage), format(skill.dps), percent(skill.share), tostring(skill.hits),
             percent(skill.critShare), format(skill.highest) }
end

-- Empty box of the swatch size: the header's placeholder above the swatches.
local function newSwatchBox(tree)
    local box = UI.construct("SizeBox", tree)
    box:SetWidthOverride(SWATCH_SIZE)
    box:SetHeightOverride(SWATCH_SIZE)
    return box
end

-- A text of fixed width in a horizontal row.
local function addCell(row, tree, size, color, width, justification)
    local box = UI.construct("SizeBox", tree)
    box:SetWidthOverride(width)
    local text = UI.newText(tree, size, color, justification)
    box:AddChild(text)
    row:AddChildToHorizontalBox(box):SetVerticalAlignment(UI.VALIGN_CENTER)
    return text
end

local function newRow(list, tree, topPadding)
    local row = UI.construct("HorizontalBox", tree)
    list:AddChildToVerticalBox(row):SetPadding({ Left = 0, Top = topPadding, Right = 0, Bottom = 0 })
    return row
end

-- One column per second: a dark track holding one segment per ranked skill plus one for the rest, stacked from
-- the bottom (rank 1 lowest).
local function addGraphColumns(bars, tree, style, seconds)
    local columns = {}
    local segmentCount = #style.DamageSkillColors + 1
    for index = 1, seconds do
        local outer = UI.construct("SizeBox", tree)
        outer:SetWidthOverride(style.DamageDetailBarWidth)
        outer:SetHeightOverride(style.DamageDetailGraphHeight)
        local track = UI.construct("Border", tree)
        track:SetBrushColor(TRACK_COLOR)
        track:SetPadding({ Left = 0, Top = 0, Right = 0, Bottom = 0 })
        track:SetHorizontalAlignment(UI.ALIGN_FILL)
        track:SetVerticalAlignment(UI.VALIGN_BOTTOM)
        outer:AddChild(track)
        local stack = UI.construct("VerticalBox", tree)
        track:AddChild(stack)
        local segments = {}
        for rank = segmentCount, 1, -1 do
            local box = UI.construct("SizeBox", tree)
            box:SetHeightOverride(0)
            local fill = UI.construct("Border", tree)
            fill:SetBrushColor(DamageMeterWidget.skillColor(style, rank))
            box:AddChild(fill)
            stack:AddChildToVerticalBox(box)
            segments[rank] = box
        end
        bars:AddChildToHorizontalBox(outer):SetPadding({ Left = 0, Top = 0, Right = 1, Bottom = 0 })
        columns[index] = segments
    end
    return columns
end

local function addGraph(list, tree, style, seconds)
    local overlay = UI.construct("Overlay", tree)
    local overlaySlot = list:AddChildToVerticalBox(overlay)
    overlaySlot:SetPadding({ Left = 0, Top = 4, Right = 0, Bottom = 10 })
    -- Left-aligned, so the overlay is only as wide as the bars and the average line ends with the graph.
    overlaySlot:SetHorizontalAlignment(UI.ALIGN_LEFT)
    local bars = UI.construct("HorizontalBox", tree)
    overlay:AddChildToOverlay(bars)
    local columns = addGraphColumns(bars, tree, style, seconds)
    local lineBox = UI.construct("SizeBox", tree)
    lineBox:SetHeightOverride(AVERAGE_LINE_HEIGHT)
    local line = UI.construct("Border", tree)
    line:SetBrushColor(style.DamageDetailAverageColor)
    lineBox:AddChild(line)
    local lineSlot = overlay:AddChildToOverlay(lineBox)
    lineSlot:SetHorizontalAlignment(UI.ALIGN_FILL)
    lineSlot:SetVerticalAlignment(UI.VALIGN_TOP)
    return { columns = columns, line = lineBox, lineSlot = lineSlot }
end

local function addSkillTable(list, tree, style)
    local size = style.DamageDetailFontSize
    local header = newRow(list, tree, 0)
    header:AddChildToHorizontalBox(newSwatchBox(tree)):SetPadding({ Left = 0, Top = 0, Right = 8, Bottom = 0 })
    for _, column in ipairs(SKILL_COLUMNS) do
        addCell(header, tree, size, style.MenuHeaderColor, column.width, column.justify):SetText(FText(column.title))
    end
    local rows = {}
    for index = 1, style.DamageDetailSkillRows do
        local row = newRow(list, tree, 2)
        local swatchBox = newSwatchBox(tree)
        local swatch = UI.construct("Border", tree)
        swatchBox:AddChild(swatch)
        row:AddChildToHorizontalBox(swatchBox):SetPadding({ Left = 0, Top = 0, Right = 8, Bottom = 0 })
        swatch:SetBrushColor(DamageMeterWidget.skillColor(style, index))
        local cells = {}
        for column, definition in ipairs(SKILL_COLUMNS) do
            cells[column] = addCell(row, tree, size, style.MenuTextColor, definition.width, definition.justify)
        end
        rows[index] = { row = row, cells = cells }
    end
    return rows
end

local function addTypeTable(list, tree, style)
    local size = style.DamageDetailFontSize
    addCell(newRow(list, tree, 0), tree, size, style.MenuHeaderColor, TYPE_NAME_WIDTH, UI.JUSTIFY_LEFT)
        :SetText(FText("Damage type"))
    local rows = {}
    for index = 1, style.DamageDetailTypeRows do
        local row = newRow(list, tree, 2)
        local name = addCell(row, tree, size, style.MenuTextColor, TYPE_NAME_WIDTH, UI.JUSTIFY_LEFT)
        local outer, bar = UI.newFillBar(tree, TYPE_BAR_WIDTH, size - 6, TRACK_COLOR, false)
        row:AddChildToHorizontalBox(outer):SetVerticalAlignment(UI.VALIGN_CENTER)
        local damage = addCell(row, tree, size, style.MenuTextColor, TYPE_NUMBER_WIDTH, UI.JUSTIFY_RIGHT)
        local share = addCell(row, tree, size, style.MenuTextColor, TYPE_NUMBER_WIDTH, UI.JUSTIFY_RIGHT)
        rows[index] = { row = row, name = name, bar = bar, damage = damage, share = share }
    end
    return rows
end

local function create(style, graphSeconds)
    local gameInstance = FindFirstOf("GameInstance")
    local playerController = Player.controller()
    if not UI.isUsable(gameInstance) or not UI.isUsable(playerController) then
        return nil
    end
    local userWidget, tree, canvas = UI.newRootWidget(gameInstance)
    local panel = UI.construct("Border", tree)
    panel:SetBrushColor(style.DamageMeterBackground)
    panel:SetPadding({ Left = 18, Top = 14, Right = 18, Bottom = 14 })
    local position = style.DamageDetailPosition
    UI.placeOnCanvas(canvas, panel, position.Anchor, position.Alignment, position.Offset)
    local list = UI.construct("VerticalBox", tree)
    panel:AddChild(list)
    local size = style.DamageDetailFontSize
    local state = { userWidget = userWidget }
    state.title = UI.newText(tree, size + 4, style.MenuHeaderColor, UI.JUSTIFY_LEFT)
    list:AddChildToVerticalBox(state.title)
    state.overview = UI.newText(tree, size, style.MenuTextColor, UI.JUSTIFY_LEFT)
    list:AddChildToVerticalBox(state.overview):SetPadding({ Left = 0, Top = 4, Right = 0, Bottom = 8 })
    state.caption = UI.newText(tree, size - 2, style.MenuHintColor, UI.JUSTIFY_LEFT)
    list:AddChildToVerticalBox(state.caption)
    state.graph = addGraph(list, tree, style, graphSeconds)
    local tables = UI.construct("HorizontalBox", tree)
    list:AddChildToVerticalBox(tables)
    local skillList = UI.construct("VerticalBox", tree)
    tables:AddChildToHorizontalBox(skillList)
    state.skills = addSkillTable(skillList, tree, style)
    local typeList = UI.construct("VerticalBox", tree)
    tables:AddChildToHorizontalBox(typeList):SetPadding({ Left = 30, Top = 0, Right = 0, Bottom = 0 })
    state.types = addTypeTable(typeList, tree, style)
    state.hint = UI.newText(tree, size - 2, style.MenuHintColor, UI.JUSTIFY_LEFT)
    list:AddChildToVerticalBox(state.hint):SetPadding({ Left = 0, Top = 10, Right = 0, Bottom = 0 })
    state.hint:SetText(FText(string.format("%s close  ·  %s reset", style.DamageDetailKey, style.DamageMeterResetKey)))
    UI.addToPlayerScreen(userWidget, playerController)
    return state
end

-- Heights of a column's segments: one per ranked skill, the rest of the second's damage in the last segment.
local function fillColumn(segments, bucket, rankedNames, scale)
    local ranked = 0
    for rank = 1, #segments - 1 do
        local damage = rankedNames[rank] and bucket.bySkill[rankedNames[rank]] or 0
        ranked = ranked + damage
        segments[rank]:SetHeightOverride(damage * scale)
    end
    segments[#segments]:SetHeightOverride(math.max(0, bucket.total - ranked) * scale)
end

local function fillGraph(graph, details, style)
    local highest = 0
    for _, bucket in ipairs(details.graph) do highest = math.max(highest, bucket.total) end
    local height = style.DamageDetailGraphHeight
    local scale = highest > 0 and height / highest or 0
    local rankedNames = {}
    for rank = 1, #style.DamageSkillColors do
        rankedNames[rank] = details.skills[rank] and details.skills[rank].name
    end
    for index, segments in ipairs(graph.columns) do
        fillColumn(segments, details.graph[index], rankedNames, scale)
    end
    local lineShown = highest > 0 and details.averageDps > 0
    UI.setShown(graph.line, lineShown)
    if lineShown then
        local top = height * (1 - math.min(1, details.averageDps / highest))
        graph.lineSlot:SetPadding({ Left = 0, Top = math.max(0, top - AVERAGE_LINE_HEIGHT), Right = 0, Bottom = 0 })
    end
end

local function fillSkills(rows, skills)
    for index, row in ipairs(rows) do
        local skill = skills[index]
        UI.setShown(row.row, skill ~= nil)
        if skill ~= nil then
            for column, value in ipairs(DamageDetailWidget.skillCells(skill)) do
                row.cells[column]:SetText(FText(value))
            end
        end
    end
end

local function fillTypes(rows, types, style)
    for index, row in ipairs(rows) do
        local entry = types[index]
        UI.setShown(row.row, entry ~= nil)
        if entry ~= nil then
            row.name:SetText(FText(entry.name))
            UI.setFill(row.bar, entry.share, DamageMeterWidget.typeColor(style, entry.name))
            row.damage:SetText(FText(DamageMeterWidget.formatNumber(entry.damage)))
            row.share:SetText(FText(percent(entry.share)))
        end
    end
end

function DamageDetailWidget.reset()
    if widgetState ~= nil then
        UI.remove(widgetState.userWidget)
        widgetState = nil
    end
end

-- Shows the details (from DamageMeter.details); nil closes the window. Call on the game thread.
function DamageDetailWidget.show(details, style)
    if details == nil then
        DamageDetailWidget.reset()
        return
    end
    if widgetState == nil or not UI.isShowing(widgetState.userWidget) then
        widgetState = create(style, #details.graph)
        if widgetState == nil then
            return
        end
    end
    widgetState.title:SetText(FText(DamageDetailWidget.title(details)))
    widgetState.overview:SetText(FText(DamageDetailWidget.overview(details)))
    fillGraph(widgetState.graph, details, style)
    widgetState.caption:SetText(FText(string.format("Last %d s  ·  line = average %s/s", #details.graph,
        DamageMeterWidget.formatNumber(details.averageDps))))
    fillSkills(widgetState.skills, details.skills)
    fillTypes(widgetState.types, details.types, style)
end

return DamageDetailWidget
