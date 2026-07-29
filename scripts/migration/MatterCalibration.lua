---@class MatterCalibration
local MatterCalibration = {}

-- Phaser's SetBody and Matter's Body.setStatic mutate the values supplied to
-- the scene constructors. These are the values that exist on the source
-- bodies while they are actually simulated, not the declarative level values.
MatterCalibration.APPLE_FRICTION = 0.1
-- Matter has an additional static-friction multiplier. It only selects the
-- solver branch; it does not replace the pair's dynamic friction material.
-- Box2D cannot expose that branch independently, so production fixtures keep
-- the observed dynamic material instead of mutating a global apple fixture.
MatterCalibration.APPLE_FRICTION_STATIC = 0.5
MatterCalibration.MATTER_FRICTION_NORMAL_MULTIPLIER = 5
MatterCalibration.MATTER_RESTING_TANGENT_SPEED = math.sqrt(6)
MatterCalibration.APPLE_FRICTION_AIR = 0.01
MatterCalibration.APPLE_INITIAL_RESTITUTION = 0
MatterCalibration.STATIC_FRICTION = 0.1
MatterCalibration.STATIC_RESTITUTION = 0
MatterCalibration.CARD_RESTITUTION_BASE = 0.36
MatterCalibration.MATTER_FRAMES_PER_SECOND = 60
MatterCalibration.PIXELS_PER_METER = 100
MatterCalibration.APPLE_MASS = 1
-- Matter creates the apple as a 26-sided circle. Its observed inertia is in
-- kilogram-pixel-squared; convert it once to Box2D's kilogram-metre-squared.
MatterCalibration.APPLE_MATTER_INERTIA_PX2 = 1443.867317
MatterCalibration.APPLE_INERTIA = MatterCalibration.APPLE_MATTER_INERTIA_PX2
    / (MatterCalibration.PIXELS_PER_METER * MatterCalibration.PIXELS_PER_METER)

---@param body RigidBody2D
function MatterCalibration.ApplyAppleMassProperties(body)
    body.mass = MatterCalibration.APPLE_MASS
    body.inertia = MatterCalibration.APPLE_INERTIA
end

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

-- Matter's frictionStatic branch is a per-pair cached tangent impulse, not a
-- material coefficient. Box2D exposes no equivalent pair cache, so the
-- production adapter keeps both fixtures at their observed .1 material. A
-- global fixture swap would corrupt corners, rolling contacts and springs.

return MatterCalibration
