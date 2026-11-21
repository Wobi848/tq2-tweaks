-- Works through a list in small batches on the game thread, one batch every delayMs, so long jobs (loading many game
-- assets for the data dumps) do not freeze the game. An error ends the job (logged) instead of leaving it marked as
-- running.
local BatchJob = {}

-- options = { name, batchSize, delayMs, each = function(item, index), finish = function(), log }. Returns the job;
-- job.running is false once it ended. Call on the game thread.
function BatchJob.start(items, options)
    local job = { running = true, next = 1 }
    local step
    local function run()
        local ok, err = pcall(step)
        if not ok then
            options.log(options.name .. " error: " .. tostring(err))
            job.running = false
        end
    end
    step = function()
        local last = math.min(job.next + options.batchSize - 1, #items)
        for index = job.next, last do
            options.each(items[index], index)
        end
        job.next = last + 1
        if job.next <= #items then
            ExecuteInGameThreadWithDelay(options.delayMs, run)
            return
        end
        job.running = false
        options.finish()
    end
    run()
    return job
end

function BatchJob.isRunning(job)
    return job ~= nil and job.running
end

return BatchJob
