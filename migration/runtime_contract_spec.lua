package.path = "scripts/?.lua;scripts/?/init.lua;" .. package.path

local checks = 0
local function expect(condition, message)
    checks = checks + 1
    if not condition then error(message, 2) end
end

local function near(actual, expected, tolerance, message)
    expect(math.abs(actual - expected) <= (tolerance or 1e-9),
        string.format("%s: expected %.12g, got %.12g", message, expected, actual))
end

local CoordinateMapper = require("game.layout.CoordinateMapper")
local mapper = CoordinateMapper.New({
    levelWidth = 1400,
    levelHeight = 700,
    viewportWidth = 1500,
    viewportHeight = 596,
    pixelsPerMeter = 100,
})
local centerX, centerY = mapper:LevelToWorld(700, 350)
near(centerX, 0, 1e-12, "level center x")
near(centerY, 0, 1e-12, "level center y")
local cornerX, cornerY = mapper:LevelToWorld(0, 0)
near(cornerX, -7.5, 1e-12, "level corner x")
near(cornerY, 2.98, 1e-12, "level corner y")
local sizeX, sizeY = mapper:LevelSizeToWorld(1400, 700)
near(sizeX, 11.92, 1e-12, "level width")
near(sizeY, 5.96, 1e-12, "level height")
local _, _, dragX, dragY = mapper:ClampLauncherDrag(1400, 700)
expect(math.sqrt(dragX * dragX + dragY * dragY) <= 98 + 1e-9, "launcher drag exceeds radius")
expect(dragX >= -76 and dragY <= 78, "launcher directional clamp differs")

local Rules = require("game.gameplay.Rules")
local rules = Rules.NewState()
expect(Rules.ToggleField(rules, "feather-gravity"), "field cannot be selected before launch")
expect(Rules.Launch(rules), "first launch rejected")
expect(not Rules.Launch(rules), "second launch accepted")
local gravity = Rules.GetGravity(rules, { x = 0, y = 1, strength = 1 })
near(gravity.strength, 1.05 * 0.55, 1e-12, "feather gravity")
expect(Rules.UseDecision(rules, "quantum-phase", false) and rules.phaseActive, "phase decision failed")
expect(not Rules.UseDecision(rules, "quantum-phase", false), "single-use decision repeated")
expect(Rules.CanPunch(rules) and Rules.Punch(rules), "Newton punch failed")
expect(not Rules.CanPunch(rules), "Newton punch repeated")
for count = 1, 10 do
    local hand = Rules.CardHand(count, 900, 800, 1500)
    expect(#hand == count, "card hand count mismatch: " .. tostring(count))
    for index = 2, #hand do expect(hand[index - 1].x < hand[index].x, "card hand order is unstable") end
end

local Calibration = require("game.physics.Calibration")
near(Calibration.Box2DLinearDamping(0.01, 1, 1 / 60), 60 * (1 / 0.99 - 1), 1e-10, "standard damping")
near(Calibration.CardRestitution(0), 0, 1e-12, "minimum restitution")
near(Calibration.CardRestitution(100), 0.98, 1e-12, "maximum restitution")
local body = {}
Calibration.ApplyAppleMassProperties(body)
near(body.mass, 1, 1e-12, "apple mass")
near(body.inertia, 0.1443867317, 1e-12, "apple inertia")

local Profiles = require("game.physics.Profiles")
local standard = Profiles.Resolve(nil)
local incident = Profiles.Resolve(Profiles.INCIDENT_ID)
expect(standard.id == Profiles.DEFAULT_ID and standard.boundaries.ceiling and standard.boundaries.left,
    "standard physics profile resolution failed")
expect(incident.id == Profiles.INCIDENT_ID and not incident.boundaries.ceiling and not incident.boundaries.left,
    "incident physics profile resolution failed")
standard.boundaries.left = false
expect(Profiles.Resolve(nil).boundaries.left, "physics profile returned shared mutable state")

local LevelData = require("game.level.LevelData")
local boundaryLevel = {
    schemaVersion = 1,
    levelId = "boundary_rounding",
    playfield = { width = 1400, height = 700 },
    objects = {
        {
            id = "launcher", type = "launcher",
            transform = { x = 100, y = 100, width = 20, height = 20, rotation = 0 },
            properties = {},
        },
        {
            id = "goal", type = "goal_sensor",
            transform = { x = 1300, y = 100, width = 20, height = 20, rotation = 0 },
            properties = {},
        },
        {
            id = "wall_10", type = "wall",
            transform = {
                x = 472.5620537282992,
                y = 502.70239503850445,
                width = 198.63064255100974,
                height = 20,
                rotation = 135,
            },
            properties = {},
        },
    },
    cardDeck = { cards = {} },
    rules = { initialGravity = { x = 0, y = 1, strength = 1 } },
}
local boundaryValid = LevelData.Validate(boundaryLevel)
expect(boundaryValid, "rotated object touching the playfield boundary was rejected")
boundaryLevel.objects[3].transform.y = boundaryLevel.objects[3].transform.y + 1e-4
local overflowValid = LevelData.Validate(boundaryLevel)
expect(not overflowValid, "object beyond the boundary tolerance was accepted")

local Timeline = require("game.replay.Timeline")
local samples = {
    { t = 0, x = 0, y = 0, vx = 1, vy = 2, angle = 350 },
    { t = 100, x = 10, y = 20, vx = 3, vy = 4, angle = 10 },
}
local middle = Timeline.StateAt(samples, 50)
near(middle.x, 5, 1e-12, "replay x interpolation")
near(middle.y, 10, 1e-12, "replay y interpolation")
near(middle.angle, 360, 1e-12, "replay shortest-angle interpolation")
local visible = Timeline.SamplesThrough(samples, 50)
expect(#visible == 2 and visible[2].t == 50, "replay playhead sample missing")

local Feed = require("game.replay.Feed")
local feed = Feed.Items({
    { t = 0, type = "CARD_PLAYED", cardId = "feather-gravity" },
    { t = 200, type = "RULE_REMOVED", cardId = "feather-gravity" },
    { t = 300, type = "NEWTON_PUNCH" },
}, 400, Rules.CARDS)
expect(#feed == 2 and not feed[1].active and feed[2].title ~= nil, "replay event feed state failed")

local Trajectory = require("game.physics.Trajectory")
local points = Trajectory.PredictFreeFlight({
    x = 0, y = 0, velocityX = 1, velocityY = 0,
    gravityX = 0, gravityY = 1, forceScale = 0.001,
    frictionAir = 0.01, maxSpeed = 25, steps = 12, sampleEvery = 3,
})
expect(#points == 4 and points[1].frame == 3 and points[4].frame == 12, "trajectory sampling failed")
expect(points[4].x > points[1].x and points[4].y > points[1].y, "trajectory integration direction failed")

local State = require("game.State")
local designStub = { New = function(pixelsPerMeter) return { pixelsPerMeter = pixelsPerMeter } end }
local context = State.New({ DesignSpace = designStub, Rules = Rules }, { CONFIG = { pixelsPerMeter = 100 } })
expect(context.domains.experiment.mode == "ready", "initial experiment mode")
expect(context.domains.cards.mode == "idle", "initial cards mode")
expect(context.domains.replay.mode == "none", "initial replay mode")
context.draggedApple_ = true
expect(context.domains.experiment.mode == "aiming", "aiming experiment mode")
context.draggedApple_, context.launched_ = false, true
expect(context.domains.experiment.mode == "launched", "launched experiment mode")
context.isPaused_ = true
expect(context.domains.experiment.mode == "paused", "paused experiment mode")
context.activeCardId_ = "feather-gravity"
expect(context.domains.cards.mode == "pressed", "pressed card mode")
context.replayMode_ = "playing"
expect(context.domains.replay.mode == "playing", "playing replay mode")
local snapshot = State.BeginGameSnapshot(context)
expect(snapshot.modes.experiment == "paused" and snapshot.modes.replay == "playing", "snapshot mode capture")
local writable = pcall(function() context.failed_ = true end)
expect(not writable and context.failed_ == false, "GameSnapshot allowed state mutation")
State.EndGameSnapshot(context)
context.failed_ = true
expect(context.domains.experiment.mode == "failed", "failed experiment mode")

local App = require("game.App")
local app = App.New()
for _, method in ipairs({
    "Start", "Stop", "Update", "OnPhysicsPreStep", "OnPhysicsPostStep", "OnScreenMode",
    "OnTouchBegin", "OnTouchMove", "OnTouchEnd", "OnContactBegin", "OnContactUpdate",
    "OnContactEnd", "Render",
}) do
    expect(type(app[method]) == "function", "App adapter method missing: " .. method)
end
expect(type(app.context.BuildLevel) == "function" and type(app.context.HandlePointer) == "function"
    and type(app.context.HandleRender) == "function", "App installers did not compose")

dofile("scripts/main.lua")
for _, callback in ipairs({
    "Start", "Stop", "HandleUpdate", "HandlePhysicsPreStep", "HandlePhysicsPostStep",
    "HandleScreenMode", "HandleTouchBegin", "HandleTouchMove", "HandleTouchEnd",
    "HandleCollisionBegin", "HandleCollisionUpdate", "HandleCollisionEnd", "HandleRender",
}) do
    expect(type(_G[callback]) == "function", "engine entry callback missing: " .. callback)
end

print(string.format('{"mode":"PURE_LUA_RUNTIME_CONTRACT","checks":%d,"status":"pass"}', checks))
