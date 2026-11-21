-- Loot filter rules for equipment pickup, made with the loot filter editor (loot_filter.html) and saved as
-- loot_filter.lua in the mod folder. Modelled on the rule lists of other ARPG loot filters: every rule combines its
-- conditions with "and", and an item is picked up if any rule matches. A rule (all fields optional):
--   { name = "Summoner", minRarity = "Rare", types = { "staff", "ring" }, needed = 1, affixes = { "<affix asset>" } }
-- types are parts of the item type name (da_weapon_2h_staff_..., da_jewelry_ring_...); needed = how many of the
-- listed affixes one item must carry (default 1).
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
    return { name = name, minRarity = minRarity, types = types,
             affixes = affixCount > 0 and affixes or nil,
             needed = math.min(affixCount, math.max(1, math.floor(tonumber(entry.needed) or 1))) }
end

-- Loads the rules from `path`; missing or broken files and unusable rules are logged and left out.
function LootRules.load(path, rarityByName, log)
    local file = io.open(path, "r")
    if file == nil then
        log("No loot filter yet (" .. path .. " missing): create it with loot_filter.html")
        return {}
    end
    file:close()
    -- Empty environment: the file is data only and may not call anything.
    local chunk, loadError = loadfile(path, "t", {})
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
            names[#names + 1] = rule.name
        else
            log("Loot filter rule left out: " .. problem)
        end
    end
    log(string.format("Loot filter: %d rule(s) %s", #rules, table.concat(names, ", ")))
    return rules
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

local function affixesMatch(rule, affixNames)
    if rule.affixes == nil then
        return true
    end
    local count = 0
    for _, affixName in ipairs(affixNames) do
        if rule.affixes[affixName] then
            count = count + 1
        end
    end
    return count >= rule.needed
end

-- Whether an item { rarity, typeName, affixNames or readAffixNames } matches one of the rules. Rules without an affix
-- condition are checked first; readAffixNames is called at most once, and only when a rule with affixes fits by
-- rarity and type (reading the affixes of a game item is the expensive and touchy part).
function LootRules.matchesAny(rules, item)
    local function fits(rule)
        return (rule.minRarity == nil or item.rarity >= rule.minRarity) and typeMatches(rule, item.typeName)
    end
    for _, rule in ipairs(rules) do
        if rule.affixes == nil and fits(rule) then
            return true
        end
    end
    local affixNames = item.affixNames
    for _, rule in ipairs(rules) do
        if rule.affixes ~= nil and fits(rule) then
            affixNames = affixNames or item.readAffixNames()
            if affixesMatch(rule, affixNames) then
                return true
            end
        end
    end
    return false
end

return LootRules
