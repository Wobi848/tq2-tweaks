-- Command file for developer tools (config.GameDataDump): writing a command into DevCommandFile in the mod folder
-- (e.g. "mega", or "call <Class> <Function> 1 2 3") runs that action, so dumps and queries can be started from
-- outside the game. The words after the command name are passed to the action. The file is removed before the
-- action runs, so each command runs once. Checked by a game-thread loop.
local TextFile = require("text_file")

local DevCommands = {}

-- Runs the command in the file at path, if there is one. actions = { name = function }.
function DevCommands.check(path, actions, log)
    local text = TextFile.read(path)
    if text == nil then
        return
    end
    local removed, reason = os.remove(path)
    if not removed then
        log("Command file not removed, command skipped: " .. tostring(reason))
        return
    end
    local name, arguments = text:match("^%s*(%S+)%s*(.-)%s*$")
    local action = name and actions[name:lower()]
    if action == nil then
        log("Unknown command in " .. path .. ": " .. tostring(name))
        return
    end
    log("Command: " .. name)
    action(arguments)
end

return DevCommands
