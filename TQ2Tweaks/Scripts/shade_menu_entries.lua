-- Menu rows for the shade display.
local Settings = require("settings")
local listEntry = require("setting_entry")

local ShadeMenuEntries = {}

local function moveStep(config, fast)
    return fast and config.MoveStepFast or config.MoveStep
end

function ShadeMenuEntries.create(settings)
    local config, values = settings.config, settings.values
    return {
        { header = "Shade display" },
        listEntry(settings, "Bar colour", "ColorPreset"),
        listEntry(settings, "Text colour", "TextColorPreset"),
        listEntry(settings, "Display", "DisplayMode"),
        {
            label = "Size",
            value = function() return string.format("%.1fx", values.Scale) end,
            change = function(direction) Settings.resize(settings, direction) end,
        },
        {
            label = "Position left/right",
            value = function() return tostring(values.OffsetX) end,
            change = function(direction, fast) Settings.move(settings, direction * moveStep(config, fast), 0) end,
        },
        {
            label = "Position up/down",
            value = function() return tostring(values.OffsetY) end,
            -- Right/plus moves down, matching the screen coordinate.
            change = function(direction, fast) Settings.move(settings, 0, direction * moveStep(config, fast)) end,
        },
    }
end

return ShadeMenuEntries
