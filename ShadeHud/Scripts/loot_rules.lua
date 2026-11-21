-- Loot filter rules for equipment pickup, made with the loot filter editor (loot_filter.html) and saved as
-- loot_filter.lua in the mod folder. Modelled on the rule lists of other ARPG loot filters: every rule combines its
-- conditions with "and", and an item is picked up if any rule matches. A rule (all fields optional):
--   { name = "Summoner", minRarity = "Rare", types = { "staff", "ring" }, needed = 1, affixes = { "<affix asset>" } }
-- types are parts of the item type name (da_weapon_2h_staff_..., da_jewelry_ring_...); needed = how many of the
-- listed affixes one item must carry (default 1). With craftable = true, one more counts if crafting can add it: the
-- blacksmith replaces one random affix (a prefix stays a prefix, a suffix a suffix) and fills free affix places, so an
-- item that misses one wanted affix still counts when it has a useless random affix of the right kind or a free place.
local LootRules = {}

local function setOf(names)
    local set, count = {}, 0
    for _, name in ipairs(names or {}) do
        if type(name) == "string" then
            set[name] = true
            count = count + 1
        end
    end
    return set, count
end

local function typesOf(list)
    local types = {}
    for _, part in ipairs(list or {}) do
        if type(part) == "string" and part ~= "" then
            types[#types + 1] = "_" .. part:lower() .. "_"
        end
    end
    return types
end

-- A checked rule, or nil plus the reason it is unusable. rarityByName maps rarity names to the game's numbers.
local function ruleOf(entry, rarityByName)
    if type(entry) ~= "table" then
        return nil, "not a rule"
    end
    local name = tostring(entry.name or "Rule")
    local minRarity = nil
    if entry.minRarity ~= nil then
        minRarity = rarityByName[entry.minRarity]
        if minRarity == nil then
            return nil, name .. ": unknown rarity '" .. tostring(entry.minRarity) .. "'"
        end
    end
    local affixes, affixCount = setOf(entry.affixes)
    local types = typesOf(entry.types)
    if minRarity == nil and #types == 0 and affixCount == 0 then
        return nil, name .. ": no condition, it would pick up everything"
    end
    return { name = name, minRarity = minRarity, rarityName = entry.minRarity, types = types,
             craftable = entry.craftable == true, enabled = entry.enabled ~= false, affixCount = affixCount,
             affixes = affixCount > 0 and affixes or nil,
             needed = math.min(affixCount, math.max(1, math.floor(tonumber(entry.needed) or 1))) }
end

-- Rules from the text of a loot filter file; broken text and unusable rules are logged and left out. Rules switched
-- off (enabled = false) are kept, so the menu can show them, but never match.
function LootRules.fromText(text, rarityByName, log)
    -- Empty environment: the file is data only and may not call anything.
    local chunk, loadError = load(text, "=loot_filter.lua", "t", {})
    if chunk == nil then
        log("Loot filter not loaded: " .. tostring(loadError))
        return {}
    end
    local ok, list = pcall(chunk)
    if not ok or type(list) ~= "table" then
        log("Loot filter not loaded: the file does not return a list of rules")
        return {}
    end
    local rules, names = {}, {}
    for _, entry in ipairs(list) do
        local rule, problem = ruleOf(entry, rarityByName)
        if rule then
            rules[#rules + 1] = rule
            names[#names + 1] = rule.name .. (rule.enabled and "" or " (off)")
        else
            log("Loot filter rule left out: " .. problem)
        end
    end
    log(string.format("Loot filter: %d rule(s) %s", #rules, table.concat(names, ", ")))
    return rules
end

-- Reads `path` and returns its rules (see fromText); a missing file gives no rules.
function LootRules.load(path, rarityByName, log)
    local file = io.open(path, "r")
    if file == nil then
        log("No loot filter yet (" .. path .. " missing): create it with loot_filter.html")
        return {}
    end
    local text = file:read("a")
    file:close()
    return LootRules.fromText(text, rarityByName, log)
end

local function typeMatches(rule, typeName)
    if #rule.types == 0 then
        return true
    end
    local name = "_" .. typeName:lower() .. "_"
    for _, part in ipairs(rule.types) do
        if name:find(part, 1, true) then
            return true
        end
    end
    return false
end

-- "prefix" or "suffix" for a random affix by its asset name (da_prefix_..., da_suffix_...), nil for other affixes.
local function slotKind(name)
    return name:match("^da_(prefix)_") or name:match("^da_(suffix)_")
end

-- 1 if crafting can add one more wanted affix: a wanted kind (prefix/suffix) is still missing and the item has a free
-- affix place or a useless random affix of that kind to replace; else 0.
local function craftBonus(rule, affixes, freePlaces)
    local present, missingKinds = {}, {}
    for _, affix in ipairs(affixes) do
        present[affix.name] = true
    end
    for name in pairs(rule.affixes) do
        local kind = not present[name] and slotKind(name)
        if kind then
            missingKinds[kind] = true
        end
    end
    if next(missingKinds) == nil then
        return 0
    end
    if freePlaces > 0 then
        return 1
    end
    for _, affix in ipairs(affixes) do
        local kind = affix.random and not rule.affixes[affix.name] and slotKind(affix.name)
        if kind and missingKinds[kind] then
            return 1
        end
    end
    return 0
end

local function affixesMatch(rule, affixes, freePlaces)
    if rule.affixes == nil then
        return true
    end
    local count = 0
    for _, affix in ipairs(affixes) do
        if rule.affixes[affix.name] then
            count = count + 1
        end
    end
    if count >= rule.needed then
        return true
    end
    return rule.craftable and count + craftBonus(rule, affixes, freePlaces) >= rule.needed
end

-- The item's affixes as { name, random } (a plain list of names counts as random affixes).
local function affixesOfItem(item)
    if item.affixes then
        return item.affixes
    end
    if item.affixNames then
        local affixes = {}
        for index, name in ipairs(item.affixNames) do
            affixes[index] = { name = name, random = true }
        end
        return affixes
    end
    return item.readAffixes()
end

local function freePlacesOf(item, affixes)
    if item.maxAffixes == nil then
        return 0
    end
    local random = 0
    for _, affix in ipairs(affixes) do
        random = random + (affix.random and 1 or 0)
    end
    return math.max(0, item.maxAffixes - random)
end

-- Whether an item { rarity, typeName, affixes or affixNames or readAffixes, maxAffixes } matches one of the rules.
-- affixes are { name, random }; maxAffixes is how many random affixes its rarity allows (nil = no crafting). Rules
-- without an affix condition are checked first; readAffixes is called at most once, and only when a rule with
-- affixes fits by rarity and type (reading the affixes of a game item is the expensive and touchy part).
function LootRules.matchesAny(rules, item)
    local function fits(rule)
        return rule.enabled and (rule.minRarity == nil or item.rarity >= rule.minRarity)
            and typeMatches(rule, item.typeName)
    end
    for _, rule in ipairs(rules) do
        if rule.affixes == nil and fits(rule) then
            return true
        end
    end
    local affixes, freePlaces
    for _, rule in ipairs(rules) do
        if rule.affixes ~= nil and fits(rule) then
            if affixes == nil then
                affixes = affixesOfItem(item)
                freePlaces = freePlacesOf(item, affixes)
            end
            if affixesMatch(rule, affixes, freePlaces) then
                return true
            end
        end
    end
    return false
end

local function escapePattern(text)
    return (text:gsub("%p", "%%%0"))
end

-- The loot filter text with the header line of rule `name` changed: changes = { minRarity = "Rare" or false (any),
-- needed = n, enabled = true/false }. Works on the one-line rule headers loot_filter.html writes. Returns the new text,
-- or nil if the rule's header line is not found.
function LootRules.editRule(text, name, changes)
    local lineStart = text:find('\n[ \t]*{ name = "' .. escapePattern(name) .. '",')
    if lineStart == nil then
        return nil
    end
    local lineEnd = text:find("\n", lineStart + 1) or (#text + 1)
    local line = text:sub(lineStart, lineEnd - 1)
    if changes.minRarity ~= nil then
        local value = changes.minRarity and ('"' .. changes.minRarity .. '"') or "nil"
        line = line:gsub('minRarity = [^,]+,', function() return "minRarity = " .. value .. "," end, 1)
    end
    if changes.needed ~= nil then
        line = line:gsub("needed = %d+,", "needed = " .. changes.needed .. ",", 1)
    end
    if changes.enabled ~= nil then
        line = line:gsub(" enabled = false,", "", 1)
        if changes.enabled == false then
            line = line:gsub(" types = ", " enabled = false, types = ", 1)
        end
    end
    return text:sub(1, lineStart - 1) .. line .. text:sub(lineEnd)
end

return LootRules
