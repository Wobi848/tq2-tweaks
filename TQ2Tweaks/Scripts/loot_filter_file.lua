-- The loot filter file (loot_filter.lua): checked periodically and read again when it changed (saved from the browser
-- page or edited in the F5 tab "Filter"). The tab's changes are queued by key callbacks and written into the file by
-- check(), on the game thread, together with the editor's data file (so the page shows them too).
local AffixDump = require("affix_dump")
local LootRules = require("loot_rules")
local TextFile = require("text_file")

local LootFilterFile = {}

-- paths = { filter, dump (affix dump), pageData (editor data file) }; onChange(rules) runs after every reload.
function LootFilterFile.new(paths, rarityByName, log, onChange)
    return { paths = paths, rarityByName = rarityByName, log = log, onChange = onChange,
             rules = {}, text = nil, edits = {}, missingLogged = false }
end

-- Short state for the menu: "5 rules" or "no file yet".
function LootFilterFile.describe(filter)
    return filter.text and (#filter.rules .. " rules") or "no file yet"
end

-- Only changes Lua state, so key callbacks may call it.
function LootFilterFile.queueEdit(filter, name, changes)
    filter.edits[#filter.edits + 1] = { name = name, changes = changes }
end

local function write(filter, path, text)
    local ok, reason = TextFile.write(path, text)
    if not ok then
        filter.log("Not written: " .. path .. " (" .. reason .. ")")
    end
    return ok
end

local function applyEdits(filter, text)
    for _, edit in ipairs(filter.edits) do
        local edited = LootRules.editRule(text, edit.name, edit.changes)
        if edited then
            text = edited
        else
            filter.log("Loot filter: rule '" .. edit.name .. "' not found in the file")
        end
    end
    filter.edits = {}
    return text
end

-- Writes queued edits into the file and the editor's data file; returns the text now in the file.
local function saveEdits(filter, text)
    local edited = applyEdits(filter, text)
    if edited == text or not write(filter, filter.paths.filter, edited) then
        return text
    end
    local dump = TextFile.read(filter.paths.dump)
    if dump then
        write(filter, filter.paths.pageData, AffixDump.pageData(dump, edited))
    end
    return edited
end

-- Applies queued edits and reloads the rules if the file changed. Call on the game thread.
function LootFilterFile.check(filter)
    local text = TextFile.read(filter.paths.filter)
    if text and #filter.edits > 0 then
        text = saveEdits(filter, text)
    end
    if text == nil and not filter.missingLogged then
        filter.log("No loot filter yet (" .. filter.paths.filter .. " missing): create it with loot_filter.html")
    end
    filter.missingLogged = text == nil
    if text == filter.text then
        return
    end
    filter.text = text
    filter.rules = text and LootRules.fromText(text, filter.rarityByName, filter.log) or {}
    filter.onChange(filter.rules)
end

return LootFilterFile
