-- Developer tool (command file "call <Class> <Function> <number> ..."): calls a game function on the first loaded
-- object of a class once per number and writes the results to a JSON file in the mod folder. For values the game
-- computes in code and keeps out of its data files, e.g. the skill points per capacity step:
--   call TQ2MasteryActiveAbilityViewModel GetRequiredPointsForCapacity 1 2 3 5 7 9 11 13 15 17
-- (that view model exists while the skill window is open). Only reads.
local GameObject = require("game_object")
local JsonText = require("json_text")
local TextFile = require("text_file")

local NativeCall = {}

-- { class, func, numbers } from the command arguments, or nil and the reason.
function NativeCall.parse(arguments)
    local className, functionName, rest = (arguments or ""):match("^%s*(%S+)%s+(%S+)%s*(.*)$")
    if className == nil then
        return nil, "usage: call <Class> <Function> <number> ..."
    end
    local numbers = {}
    for word in rest:gmatch("%S+") do
        local number = tonumber(word)
        if number == nil then
            return nil, "not a number: " .. word
        end
        numbers[#numbers + 1] = number
    end
    return { class = className, func = functionName, numbers = numbers }
end

local function firstObject(className)
    for _, object in ipairs(FindAllOf(className) or {}) do
        if GameObject.usable(object) then
            return object
        end
    end
    return nil
end

-- Runs the call and writes { class, function, results = [{ argument, value } or { argument, error }] } to path.
-- Call on the game thread.
function NativeCall.run(arguments, path, log)
    local call, problem = NativeCall.parse(arguments)
    if call == nil then
        log("Call: " .. problem)
        return
    end
    local object = firstObject(call.class)
    if object == nil then
        log("Call: no loaded " .. call.class)
        return
    end
    local results = {}
    local inputs = #call.numbers > 0 and call.numbers or { false }
    for _, number in ipairs(inputs) do
        local ok, value = pcall(function()
            if number then
                return object[call.func](object, number)
            end
            return object[call.func](object)
        end)
        local entry = { argument = number or nil }
        if ok then
            entry.value = type(value) == "userdata" and tostring(value) or value
        else
            entry.error = tostring(value)
        end
        results[#results + 1] = entry
    end
    local written, reason = TextFile.write(path, JsonText.encode({ class = call.class, ["function"] = call.func,
                                                                   results = results }) .. "\n")
    if not written then
        log("Call result not written: " .. reason)
        return
    end
    log(string.format("Call %s.%s: %d result(s) written to %s", call.class, call.func, #results, path))
end

return NativeCall
