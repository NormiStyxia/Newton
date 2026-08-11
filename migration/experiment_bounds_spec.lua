package.path = "scripts/?.lua;scripts/?/init.lua;" .. package.path

local checks = 0
local function expect(condition, message)
    checks = checks + 1
    if not condition then error(message, 2) end
end

local Experiment = require("game.gameplay.Experiment")
local frame = {
    playfieldX = 48,
    playfieldY = 92,
    playfieldWidth = 1400,
    playfieldHeight = 700,
}
local right = frame.playfieldX + frame.playfieldWidth
local bottom = frame.playfieldY + frame.playfieldHeight

expect(not Experiment.IsAppleOutsideFailureBounds(right, 400, frame),
    "apple exactly on the right boundary should remain in play")
expect(Experiment.IsAppleOutsideFailureBounds(right + 0.001, 400, frame),
    "apple crossing the right boundary should fail immediately")
expect(not Experiment.IsAppleOutsideFailureBounds(frame.playfieldX - 120, 400, frame),
    "legacy left escape margin changed")
expect(Experiment.IsAppleOutsideFailureBounds(frame.playfieldX - 120.001, 400, frame),
    "apple beyond the left escape margin should fail")
expect(not Experiment.IsAppleOutsideFailureBounds(700, bottom + 140, frame),
    "legacy vertical escape margin changed")
expect(Experiment.IsAppleOutsideFailureBounds(700, bottom + 140.001, frame),
    "apple beyond the vertical escape margin should fail")

print(string.format("EXPERIMENT_BOUNDS: %d checks passed", checks))
