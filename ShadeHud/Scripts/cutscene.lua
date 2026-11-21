-- Tells whether a cutscene is running, so the HUD widgets can be hidden during it.
--
-- Two signals: story cutscenes run through ATQ2CutsceneQuestActor (m_EventRunning), but other sequences (e.g. a
-- boss entrance) do not. During those the game hides its own HUD (wbp_hud_C, which fades with ANIM_Fade), so the
-- game HUD being hidden or faded out counts as "cutscene" too. With a debug log, each change of the game HUD state
-- (including whether it is activated, which is not used) is logged once.
local Cutscene = {}

local CUTSCENE_ACTOR_CLASS = "TQ2CutsceneQuestActor"
local GAME_HUD_CLASS = "wbp_hud_C"
-- Below this render opacity the game HUD counts as faded out.
local MIN_VISIBLE_OPACITY = 0.05
-- The display loop runs 10x per second; the checks are only repeated after this many seconds.
local CHECK_INTERVAL_SECONDS = 0.5

local lastCheckAt, running, lastHudState = nil, false, nil

local function storyCutsceneRunning()
    for _, actor in ipairs(FindAllOf(CUTSCENE_ACTOR_CLASS) or {}) do
        if actor:IsValid() and actor.m_EventRunning then
            return true
        end
    end
    return false
end

local function ask(object, method)
    local ok, value = pcall(function() return object[method](object) end)
    if ok then
        return value
    end
    return nil
end

local function shown(hud)
    local visible, opacity = ask(hud, "IsVisible"), ask(hud, "GetRenderOpacity")
    return visible ~= false and (opacity == nil or opacity >= MIN_VISIBLE_OPACITY), visible, opacity
end

-- True if game HUDs exist and all of them are hidden or faded out. After level changes old, hidden instances may
-- linger, so one shown HUD is enough to count as "no cutscene". No game HUD at all (e.g. main menu) does not
-- count as hidden.
local function gameHudHidden(debugLog)
    local huds, anyShown, states = 0, false, {}
    for _, hud in ipairs(FindAllOf(GAME_HUD_CLASS) or {}) do
        if hud:IsValid() then
            huds = huds + 1
            local isShown, visible, opacity = shown(hud)
            anyShown = anyShown or isShown
            if debugLog ~= nil then
                states[#states + 1] = string.format("visible=%s opacity=%s activated=%s", tostring(visible),
                    tostring(opacity), tostring(ask(hud, "IsActivated")))
            end
        end
    end
    local state = table.concat(states, " | ")
    if state ~= "" and state ~= lastHudState then
        lastHudState = state
        debugLog("Game HUD state: " .. state)
    end
    return huds > 0 and not anyShown
end

-- now: current time in seconds; debugLog: logger for the HUD state, or nil. Call on the game thread.
function Cutscene.isRunning(now, debugLog)
    if lastCheckAt == nil or now - lastCheckAt >= CHECK_INTERVAL_SECONDS then
        lastCheckAt = now
        running = storyCutsceneRunning() or gameHudHidden(debugLog)
    end
    return running
end

return Cutscene
