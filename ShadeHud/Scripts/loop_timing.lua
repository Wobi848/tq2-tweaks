-- Performance measurement for the mod's loops (config.TimingLog): how often each loop ran in a period, how long it
-- took on average and at most, and which share of the period it used. Pure Lua; the caller passes the times (os.clock,
-- which is wall time in milliseconds steps under Windows/Wine, so single values are coarse but averages hold).
local LoopTiming = {}

function LoopTiming.new(reportSeconds)
    return { reportSeconds = reportSeconds, startedAt = nil, byName = {} }
end

-- Adds one run of loop `name` that took `seconds`.
function LoopTiming.record(timing, name, seconds)
    local entry = timing.byName[name]
    if entry == nil then
        entry = { runs = 0, total = 0, longest = 0 }
        timing.byName[name] = entry
    end
    entry.runs = entry.runs + 1
    entry.total = entry.total + seconds
    entry.longest = math.max(entry.longest, seconds)
end

-- The summary line once a period has passed (and starts the next period), else nil.
function LoopTiming.report(timing, now)
    if timing.startedAt == nil then
        timing.startedAt = now
        return nil
    end
    local period = now - timing.startedAt
    if period < timing.reportSeconds then
        return nil
    end
    local entries = {}
    for name, entry in pairs(timing.byName) do
        entries[#entries + 1] = { name = name, entry = entry }
    end
    table.sort(entries, function(a, b) return a.entry.total > b.entry.total end)
    local parts, total = {}, 0
    for _, item in ipairs(entries) do
        local entry = item.entry
        total = total + entry.total
        parts[#parts + 1] = string.format("%s %d× avg %.2f ms max %.0f ms", item.name, entry.runs,
            entry.total / entry.runs * 1000, entry.longest * 1000)
    end
    timing.startedAt, timing.byName = now, {}
    if #parts == 0 then
        return string.format("Timing over %.0f s: no loop ran", period)
    end
    return string.format("Timing over %.0f s: %.2f %% of the time in the mod | %s", period, total / period * 100,
        table.concat(parts, " | "))
end

return LoopTiming
