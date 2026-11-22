-- Tests TQ2Tweaks against a mocked UE4SS API (no game needed). Run from the project folder:
--   lua5.4 tests/test_tq2tweaks.lua
-- The test files share one loaded mod (support.lua) and run in this order: later files rely on the state the
-- mod is in after the earlier ones (registered keys and hooks, saved settings).
local testsDir = arg[0]:match("^(.*)/[^/]+$") or "."
package.path = testsDir .. "/?.lua;" .. package.path
local T = require("support")

local TEST_FILES = { "test_mod", "test_damage", "test_pickup", "test_dumps", "test_loot_filter", "test_misc" }
for _, name in ipairs(TEST_FILES) do
    dofile(testsDir .. "/" .. name .. ".lua")
end

os.execute(string.format("rm -rf '%s'", T.workDir))
local failures = T.failures()
io.write(failures == 0 and "\nAll tests passed\n" or ("\n" .. failures .. " test(s) failed\n"))
os.exit(failures == 0 and 0 or 1)
