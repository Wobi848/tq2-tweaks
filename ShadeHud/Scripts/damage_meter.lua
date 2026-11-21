-- Damage statistics for the damage meter: rolling DPS, per-second history for the graphs, encounter totals, hits,
-- crits, highest hit and statistics per damage type and per skill. Pure Lua without engine access; the time source
-- is passed in so it can be tested. The damage hook only calls record(); everything else runs in the display loop.
local DamageMeter = {}

-- How many damage types / skills the compact summary lists at most.
local TOP_TYPES = 4
local TOP_SKILLS = 5
-- Name for hits without a skill (e.g. damage over time without ability tags).
DamageMeter.OTHER = "Other"

-- windowSeconds: span of the rolling DPS. encounterTimeout: seconds without damage that end an encounter.
-- historySeconds: how many seconds of per-second history are kept for the graphs (the longest graph).
function DamageMeter.new(windowSeconds, encounterTimeout, historySeconds)
    return { windowSeconds = windowSeconds, encounterTimeout = encounterTimeout, historySeconds = historySeconds or 30,
             hits = {}, buckets = {}, encounter = nil }
end

local function newEncounter(now)
    return { startedAt = now, lastHitAt = now, total = 0, hitCount = 0, critCount = 0, highestHit = 0, peakSecond = 0,
             byType = {}, bySkill = {} }
end

-- Forgets everything (reset key).
function DamageMeter.reset(meter)
    meter.hits, meter.buckets, meter.encounter = {}, {}, nil
end

local function addSkillHit(encounter, skill, damage, isCrit)
    local stats = encounter.bySkill[skill]
    if stats == nil then
        stats = { damage = 0, hits = 0, crits = 0, highest = 0 }
        encounter.bySkill[skill] = stats
    end
    stats.damage = stats.damage + damage
    stats.hits = stats.hits + 1
    stats.crits = stats.crits + (isCrit and 1 or 0)
    stats.highest = math.max(stats.highest, damage)
end

-- Adds the hit to the bucket of its second and returns the bucket's new total.
local function addToSecond(meter, now, damage, skill)
    local second = math.floor(now)
    local bucket = meter.buckets[second]
    if bucket == nil then
        bucket = { total = 0, bySkill = {} }
        meter.buckets[second] = bucket
    end
    bucket.total = bucket.total + damage
    bucket.bySkill[skill] = (bucket.bySkill[skill] or 0) + damage
    return bucket.total
end

-- Records one hit at time `now` (seconds). A hit after a long pause starts a new encounter.
-- damageType and skill are display names such as "Fire" / "Lich" (nil counts as "Other").
function DamageMeter.record(meter, now, damage, isCrit, damageType, skill)
    local encounter = meter.encounter
    if encounter == nil or now - encounter.lastHitAt > meter.encounterTimeout then
        encounter = newEncounter(now)
        meter.encounter = encounter
        meter.hits = {}
    end
    encounter.lastHitAt = now
    encounter.total = encounter.total + damage
    encounter.hitCount = encounter.hitCount + 1
    if isCrit then
        encounter.critCount = encounter.critCount + 1
    end
    encounter.highestHit = math.max(encounter.highestHit, damage)
    local typeName = damageType or DamageMeter.OTHER
    encounter.byType[typeName] = (encounter.byType[typeName] or 0) + damage
    local skillName = skill or DamageMeter.OTHER
    addSkillHit(encounter, skillName, damage, isCrit)
    meter.hits[#meter.hits + 1] = { at = now, damage = damage }
    encounter.peakSecond = math.max(encounter.peakSecond, addToSecond(meter, now, damage, skillName))
end

-- Drops hits that fell out of the rolling window and returns the damage inside it.
local function damageInWindow(meter, now)
    local kept, sum = {}, 0
    for _, hit in ipairs(meter.hits) do
        if now - hit.at <= meter.windowSeconds then
            kept[#kept + 1] = hit
            sum = sum + hit.damage
        end
    end
    meter.hits = kept
    return sum
end

-- Buckets of the `seconds` seconds up to `endTime`, oldest first (empty seconds as an empty bucket); drops buckets older
-- than the kept history.
local function history(meter, endTime, seconds)
    local current = math.floor(endTime)
    local oldestKept = current - meter.historySeconds + 1
    for second in pairs(meter.buckets) do
        if second < oldestKept then
            meter.buckets[second] = nil
        end
    end
    local result = {}
    for second = current - seconds + 1, current do
        result[#result + 1] = meter.buckets[second] or { total = 0, bySkill = {} }
    end
    return result
end

-- Entries of byName sorted by damage, largest first (ties by name, so the order and colours stay stable).
-- damageOf(value) gives the damage of an entry.
local function ranked(byName, damageOf)
    local list = {}
    for name, value in pairs(byName) do
        list[#list + 1] = { name = name, damage = damageOf(value), value = value }
    end
    table.sort(list, function(a, b)
        if a.damage ~= b.damage then return a.damage > b.damage end
        return a.name < b.name
    end)
    return list
end

local function identity(value)
    return value
end

local function skillDamage(stats)
    return stats.damage
end

-- The largest entries as { name, share (0..1) }, at most `limit`.
local function topShares(byName, damageOf, total, limit)
    local result = {}
    for index, entry in ipairs(ranked(byName, damageOf)) do
        if index > limit then break end
        result[index] = { name = entry.name, share = total > 0 and entry.damage / total or 0 }
    end
    return result
end

local function duration(encounter)
    return encounter.lastHitAt - encounter.startedAt
end

local function hasEnded(meter, encounter, now)
    return now - encounter.lastHitAt > meter.encounterTimeout
end

-- End of the graphs: now during a fight; after it the last hit, so the "last fight" stays in view instead of
-- scrolling out of the graph.
local function graphEnd(meter, encounter, now)
    return hasEnded(meter, encounter, now) and encounter.lastHitAt or now
end

-- Summary for the compact display, or nil before the first hit. ended = the encounter is over ("last fight").
-- graphSeconds: length of the returned graph (at most historySeconds).
function DamageMeter.summary(meter, now, graphSeconds)
    local encounter = meter.encounter
    if encounter == nil then
        return nil
    end
    -- At the start of an encounter the window is shorter than windowSeconds; divide by the real span.
    local span = math.max(1, math.min(meter.windowSeconds, now - encounter.startedAt))
    local graph = {}
    for index, bucket in ipairs(history(meter, graphEnd(meter, encounter, now), graphSeconds or meter.historySeconds)) do
        graph[index] = bucket.total
    end
    return {
        dps = damageInWindow(meter, now) / span,
        averageDps = encounter.total / math.max(1, duration(encounter)),
        total = encounter.total,
        hits = encounter.hitCount,
        crits = encounter.critCount,
        highestHit = encounter.highestHit,
        duration = duration(encounter),
        ended = hasEnded(meter, encounter, now),
        graph = graph,
        types = topShares(encounter.byType, identity, encounter.total, TOP_TYPES),
        skills = topShares(encounter.bySkill, skillDamage, encounter.total, TOP_SKILLS),
    }
end

-- Full statistics for the detail window (all zero before the first hit). Like summary(), plus peakDps (best second),
-- every skill { name, damage, share, dps, hits, critShare, highest }, every type { name, damage, share } and the
-- graph as per-second buckets { total, bySkill = { [name] = damage } } of the last `graphSeconds` seconds (of the
-- fight once it has ended).
function DamageMeter.details(meter, now, graphSeconds)
    local encounter = meter.encounter or newEncounter(now)
    local seconds = math.max(1, duration(encounter))
    local total = encounter.total
    local skills = {}
    for index, entry in ipairs(ranked(encounter.bySkill, skillDamage)) do
        local stats = entry.value
        skills[index] = { name = entry.name, damage = stats.damage, share = total > 0 and stats.damage / total or 0,
                          dps = stats.damage / seconds, hits = stats.hits, critShare = stats.crits / stats.hits,
                          highest = stats.highest }
    end
    local types = {}
    for index, entry in ipairs(ranked(encounter.byType, identity)) do
        types[index] = { name = entry.name, damage = entry.damage, share = total > 0 and entry.damage / total or 0 }
    end
    return {
        ended = hasEnded(meter, encounter, now),
        duration = duration(encounter),
        total = total,
        averageDps = total / seconds,
        peakDps = encounter.peakSecond,
        hits = encounter.hitCount,
        crits = encounter.critCount,
        highestHit = encounter.highestHit,
        skills = skills,
        types = types,
        graph = history(meter, graphEnd(meter, encounter, now), graphSeconds),
    }
end

return DamageMeter
