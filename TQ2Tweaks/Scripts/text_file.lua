-- Whole text files in and out (dumps, the loot filter, the editor's data file).
local TextFile = {}

-- Content of the file, or nil if it does not exist or cannot be opened.
function TextFile.read(path)
    local file = io.open(path, "r")
    if file == nil then
        return nil
    end
    local text = file:read("a")
    file:close()
    return text
end

-- Writes text to the file. Returns true, or false and the reason; the caller logs it in its own words.
function TextFile.write(path, text)
    local file, openError = io.open(path, "w")
    if file == nil then
        return false, tostring(openError)
    end
    file:write(text)
    file:close()
    return true
end

return TextFile
