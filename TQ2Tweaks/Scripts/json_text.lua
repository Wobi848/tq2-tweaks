-- Lua values as JSON text (for the data files the browser pages read). Tables with entries 1..n are arrays, other
-- tables objects with their keys sorted (so the files are stable between runs); nil becomes null.
local JsonText = {}

local ESCAPES = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }

function JsonText.string(text)
    return '"' .. text:gsub('[%c"\\]', function(char)
        return ESCAPES[char] or string.format("\\u%04x", char:byte())
    end) .. '"'
end

local function isArray(value)
    local count = 0
    for _ in pairs(value) do
        count = count + 1
    end
    return count == #value
end

local function encodeNumber(value)
    if value ~= value or value == math.huge or value == -math.huge then
        return "null"
    end
    if math.type(value) == "integer" then
        return tostring(value)
    end
    return string.format("%.6g", value)
end

function JsonText.encode(value)
    local kind = type(value)
    if value == nil then
        return "null"
    elseif kind == "boolean" then
        return tostring(value)
    elseif kind == "number" then
        return encodeNumber(value)
    elseif kind == "string" then
        return JsonText.string(value)
    elseif kind ~= "table" then
        return JsonText.string(tostring(value))
    end
    local parts = {}
    if isArray(value) then
        for _, item in ipairs(value) do
            parts[#parts + 1] = JsonText.encode(item)
        end
        return "[" .. table.concat(parts, ",") .. "]"
    end
    local keys = {}
    for key in pairs(value) do
        keys[#keys + 1] = tostring(key)
    end
    table.sort(keys)
    for _, key in ipairs(keys) do
        parts[#parts + 1] = JsonText.string(key) .. ":" .. JsonText.encode(value[key])
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

return JsonText
