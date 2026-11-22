-- The dumps: AffixDumpModifier + AffixDumpKey (Shift+F9) writes the affix dump and the gear dump; the key callback
-- only hands the work to the game thread. All dumps, including the developer ones (config.GameDataDump: "gamedata",
-- "mega", "call"), can be started through the command file (dev_commands.lua).
local AffixDump = require("affix_dump")
local GameDataDump = require("game_data_dump")
local GearDump = require("gear_dump")
local MegaDump = require("mega_dump")
local NativeCall = require("native_call")
local Settings = require("settings")

local DumpKeys = {}

-- The mod folder lies in <game>/Binaries/Win64/ue4ss/Mods, so the game folder is everything before "/Binaries/".
local function gameAssetList(config)
    local gameDir = Settings.modFilePath(""):match("^(.*)[/\\][Bb]inaries[/\\]")
    return gameDir and (gameDir .. "/" .. config.GameDataCacheFile)
end

local function onGameThread(name, log, action)
    return function()
        ExecuteInGameThread(function()
            local ok, err = pcall(action)
            if not ok then
                log(name .. " error: " .. tostring(err))
            end
        end)
    end
end

local function writeAffixAndGear(config, playerState, log)
    local paths = { dump = Settings.modFilePath(config.AffixDumpFile),
                    pageData = Settings.modFilePath(config.AffixPageDataFile),
                    filter = Settings.modFilePath(config.LootFilterFile) }
    local ok, err = pcall(AffixDump.write, paths, log)
    if not ok then
        log("Affix dump error: " .. tostring(err))
    end
    GearDump.write(Settings.modFilePath(config.GearDumpFile), playerState(), log)
end

-- Starts a dump that reads the game's asset list: start(paths) gets `paths` plus cache = the asset list.
local function startWithAssetList(config, name, log, start, paths)
    local cache = gameAssetList(config)
    if cache == nil then
        log(name .. ": game folder not found from the mod path")
        return
    end
    paths.cache = cache
    start(paths)
end

-- The dumps by command name ("dump" = affix and gear dump, "gamedata", "mega", "call"; all but "dump" only with
-- config.GameDataDump). Each runs on the calling thread: call from the game thread. playerState() returns the
-- player's state object or nil (the gear dump needs it).
function DumpKeys.actions(config, playerState, log)
    local actions = { dump = function() writeAffixAndGear(config, playerState, log) end }
    if not config.GameDataDump then
        return actions
    end
    local gameDataDump, megaDump = GameDataDump.newState(), MegaDump.newState()
    actions.gamedata = function()
        startWithAssetList(config, "Game data dump", log,
            function(paths) GameDataDump.start(gameDataDump, paths, log) end,
            { output = Settings.modFilePath(config.GameDataFile), page = Settings.modFilePath(config.GameDataPageFile) })
    end
    actions.mega = function()
        startWithAssetList(config, "Mega dump", log,
            function(paths) MegaDump.start(megaDump, paths, log) end,
            { output = Settings.modFilePath(config.MegaDumpFile), rules = Settings.modFilePath(config.MegaDumpRulesFile) })
    end
    actions.call = function(arguments)
        NativeCall.run(arguments, Settings.modFilePath(config.CallResultFile), log)
    end
    return actions
end

-- Binds the affix and gear dump to AffixDumpModifier + AffixDumpKey. The developer dumps have no key.
function DumpKeys.register(config, actions, log)
    local key, modifier = Key[config.AffixDumpKey], ModifierKey[config.AffixDumpModifier]
    if key == nil or modifier == nil then
        log("Unknown AffixDumpKey/AffixDumpModifier '" .. tostring(config.AffixDumpModifier) .. "+" ..
            tostring(config.AffixDumpKey) .. "'")
        return
    end
    RegisterKeyBind(key, { modifier }, onGameThread("Gear dump", log, actions.dump))
end

return DumpKeys
