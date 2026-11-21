-- Builds a menu row that steps through a list setting (see settings.lua) with left/right.
local Settings = require("settings")

return function(settings, label, key)
    return {
        label = label,
        value = function() return Settings.selected(settings, key).Name end,
        change = function(direction) Settings.cycle(settings, key, direction) end,
    }
end
