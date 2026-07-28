---@class MatterCalibration
local MatterCalibration = {}

-- Phaser's SetBody and Matter's Body.setStatic mutate the values supplied to
-- the scene constructors. These are the values that exist on the source
-- bodies while they are actually simulated, not the declarative level values.
MatterCalibration.APPLE_FRICTION = 0.1
-- Matter has an additional static-friction multiplier. It only selects the
-- solver branch; it does not replace the pair's dynamic friction material.
-- Box2D cannot expose that branch independently, so production fixtures stay
-- at the source pair's actual friction coefficient below.
MatterCalibration.APPLE_FRICTION_STATIC = 0.5
MatterCalibration.MATTER_FRICTION_NORMAL_MULTIPLIER = 5
MatterCalibration.MATTER_RESTING_TANGENT_SPEED = math.sqrt(6)
MatterCalibration.APPLE_FRICTION_AIR = 0.01
MatterCalibration.APPLE_INITIAL_RESTITUTION = 0
MatterCalibration.STATIC_FRICTION = 0.1
MatterCalibration.STATIC_RESTITUTION = 0
MatterCalibration.CARD_RESTITUTION_BASE = 0.36
MatterCalibration.MATTER_FRAMES_PER_SECOND = 60

---@param frictionAir number
---@param timeScale? number
---@param timeStep? number
---@return number
function MatterCalibration.Box2DLinearDamping(frictionAir, timeScale, timeStep)
    local scale = timeScale or 1
    local step = timeStep and math.max(0.000001, timeStep) or (1 / MatterCalibration.MATTER_FRAMES_PER_SECOND)
    -- Matter reduces velocity by frictionAir * (deltaTime / baseDelta). Box2D
    -- applies damping as v / (1 + damping * dt), so solve for the damping that
    -- produces the same retention for this exact physics step.
    local retention = math.max(0.000001, 1 - frictionAir * scale * step * MatterCalibration.MATTER_FRAMES_PER_SECOND)
    return (1 / step) * (1 / retention - 1)
end

---@param multiplier number
---@return number
function MatterCalibration.CardRestitution(multiplier)
    return math.max(0, math.min(0.98, MatterCalibration.CARD_RESTITUTION_BASE * multiplier))
end

---@return number
function MatterCalibration.MatterStaticFrictionThreshold()
    -- Resolver.solveVelocity compares tangential velocity against
    -- pair.friction * pair.frictionStatic * _frictionNormalMultiplier.
    -- Keep this source fact available for telemetry; do not mutate Box2D
    -- fixtures in an attempt to emulate Matter's internal solver branch.
    return MatterCalibration.APPLE_FRICTION
        * MatterCalibration.APPLE_FRICTION_STATIC
        * MatterCalibration.MATTER_FRICTION_NORMAL_MULTIPLIER
end

---@return number
function MatterCalibration.AppleFixtureFrictionForMatterStaticContact()
    -- Box2D mixes fixture friction with sqrt(a * b). Static laboratory
    -- fixtures remain at 0.1, so set the apple fixture to produce Matter's
    -- .25 low-speed static contact coefficient: sqrt(.625 * .1) == .25.
    local contactFriction = MatterCalibration.MatterStaticFrictionThreshold()
    return (contactFriction * contactFriction) / MatterCalibration.STATIC_FRICTION
end

return MatterCalibration
