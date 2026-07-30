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
-- Matter uses this coefficient only when its cached tangent impulse selects
-- the resting-contact branch. Box2D has no equivalent per-contact cache, so
-- keep it as diagnostic evidence rather than applying it to every fixture.
MatterCalibration.MATTER_RESTING_CONTACT_FRICTION = MatterCalibration.APPLE_FRICTION
    * MatterCalibration.APPLE_FRICTION_STATIC
    * MatterCalibration.MATTER_FRICTION_NORMAL_MULTIPLIER
-- Phaser static bodies resolve to friction 1 after Body.setStatic, but Matter
-- takes the apple/static pair's lower .1 coefficient. With the apple also at
-- .1, Box2D needs a .1 static fixture for its geometric mean to produce the
-- same kinetic contact coefficient. The previous .625 fixture value forced
-- .25 friction on every landing and materially shortened slides before a
-- spring or wall.
MatterCalibration.STATIC_FRICTION = MatterCalibration.APPLE_FRICTION
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
-- material coefficient. Box2D exposes no equivalent pair cache; a global
-- fixture swap on the shared apple mid-contact would corrupt corners, rolling
-- contacts, and spring exits. The adapter therefore preserves the source kinetic
-- material, which is the observable branch for a new landing or impact.

return MatterCalibration
