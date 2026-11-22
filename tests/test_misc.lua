-- Tests: Player lookup and loop timing.
-- Run all tests with: lua5.4 tests/test_tq2tweaks.lua

local T = require("support")
local check, counts = T.check, T.counts

-- Player lookup: the controller is searched once and kept while valid, searched again after forget().
local Player = require("player")
Player.forget()
local lookupsBefore = counts.controllerLookups
for _ = 1, 5 do Player.controller() end
local lookupsKept = counts.controllerLookups - lookupsBefore
Player.forget()
Player.controller()
check("player controller searched once and kept, again after forget", lookupsKept == 1
    and counts.controllerLookups - lookupsBefore == 2 and Player.character() == playerPawn)

do
-- Loop timing: runs, average, maximum and share of the period per loop, reported once per period.
local LoopTiming = require("loop_timing")
local timed = LoopTiming.new(60)
check("timing: no report before the period has passed", LoopTiming.report(timed, 100) == nil)
LoopTiming.record(timed, "Display", 0.002)
LoopTiming.record(timed, "Display", 0.004)
LoopTiming.record(timed, "Speed", 0.001)
check("timing: still nothing inside the period", LoopTiming.report(timed, 130) == nil)
local timingLine = LoopTiming.report(timed, 160)
check("timing: summary sorted by total time, with share of the period",
    timingLine == "Timing over 60 s: 0.01 % of the time in the mod | Display 2× avg 3.00 ms max 4 ms | Speed 1× avg 1.00 ms max 1 ms")
check("timing: next period starts empty", LoopTiming.report(timed, 220) == "Timing over 60 s: no loop ran")
end

do
-- Shared helpers: failing reads give nil, destroyed objects are not usable, tag containers as names.
local GameObject = require("game_object")
local container, tagNamed = T.container, T.tagNamed
check("game object: a failing read gives nil", GameObject.read(function() error("no field") end) == nil
    and GameObject.read(function() return 5 end) == 5)
check("game object: nil and destroyed objects are not usable", not GameObject.usable(nil)
    and not GameObject.usable({ IsValid = function() return false end })
    and GameObject.usable({ IsValid = function() return true end }))
check("game object: short name without class and path",
    GameObject.shortName({ GetFullName = function() return "Class /Game/Items/da_x.da_x" end }) == "da_x")
check("game object: tag names without empty ones", table.concat(GameObject.tagNames({ GameplayTags =
    container({ tagNamed("A.B"), tagNamed("None"), tagNamed("") }) }), ",") == "A.B"
    and #GameObject.listOf(nil) == 0)

-- Text files: missing file reads as nil, a write into a missing folder says why.
local TextFile = require("text_file")
local path = T.workDir .. "/text_file_test.txt"
check("text file: written and read back", TextFile.write(path, "a\nb") == true and TextFile.read(path) == "a\nb")
local ok, reason = TextFile.write(T.workDir .. "/missing/x.txt", "x")
check("text file: missing file nil, failed write with reason", TextFile.read(T.workDir .. "/nope") == nil
    and ok == false and type(reason) == "string")
end

do
-- Command file: runs the named action once (file removed first), unknown commands are logged.
local DevCommands = require("dev_commands")
local path = T.workDir .. "/dev_command.txt"
local runs, commandLog = 0, {}
local actions = { mega = function() runs = runs + 1 end }
local function logCommand(line) commandLog[#commandLog + 1] = line end
DevCommands.check(path, actions, logCommand)
check("command file: nothing happens without a file", runs == 0 and #commandLog == 0)
local TextFile = require("text_file")
TextFile.write(path, "  MEGA\n")
DevCommands.check(path, actions, logCommand)
DevCommands.check(path, actions, logCommand)
check("command file: command runs once, file removed", runs == 1 and TextFile.read(path) == nil)
TextFile.write(path, "format_disk")
DevCommands.check(path, actions, logCommand)
check("command file: unknown command logged, nothing run", runs == 1
    and commandLog[#commandLog]:match("Unknown command") ~= nil and TextFile.read(path) == nil)
end

do
-- Command arguments and the native call: the words after the command reach the action; "call" runs a game function
-- once per number on the first loaded object of a class and writes the results.
local DevCommands = require("dev_commands")
local NativeCall = require("native_call")
local TextFile = require("text_file")
local commandPath, resultPath = T.workDir .. "/dev_command_args.txt", T.workDir .. "/call_result.json"
local received
TextFile.write(commandPath, "call Thing GetValue 1 2\n")
DevCommands.check(commandPath, { call = function(arguments) received = arguments end }, function() end)
check("command file: the words after the command reach the action", received == "Thing GetValue 1 2")
check("native call: bad arguments are refused with the usage", NativeCall.parse("Thing") == nil
    and select(2, NativeCall.parse("Thing GetValue x")) == "not a number: x")
local savedInstances = T.instances.TQ2MasteryActiveAbilityViewModel
T.instances.TQ2MasteryActiveAbilityViewModel = { { IsValid = function() return true end,
    GetRequiredPointsForCapacity = function(_, capacity)
        if capacity > 5 then error("out of range") end
        return capacity * 2
    end } }
local callLog = {}
NativeCall.run("TQ2MasteryActiveAbilityViewModel GetRequiredPointsForCapacity 1 5 7", resultPath,
    function(line) callLog[#callLog + 1] = line end)
local result = TextFile.read(resultPath) or ""
check("native call: one result per number, errors kept per number",
    result:find('{"argument":1,"value":2}', 1, true) ~= nil and result:find('{"argument":5,"value":10}', 1, true) ~= nil
    and result:find('"argument":7,"error":', 1, true) ~= nil and callLog[1]:match("3 result%(s%)") ~= nil)
NativeCall.run("Missing GetValue 1", resultPath, function(line) callLog[#callLog + 1] = line end)
check("native call: a class without loaded objects is logged", callLog[#callLog] == "Call: no loaded Missing")
T.instances.TQ2MasteryActiveAbilityViewModel = savedInstances
end
