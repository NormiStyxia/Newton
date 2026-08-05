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
-- Phaser's MatterPhysics constructor replaces Matter's library defaults with
-- restingThresh=4 and restingThreshTangent=6 for the actual game runtime.
MatterCalibration.MATTER_RESTING_TANGENT_SPEED = 6
MatterCalibration.MATTER_RESTING_NORMAL_SPEED = 4
-- Box2D suppresses restitution below this fixed world-speed threshold. Matter
-- scales its own threshold with Engine.timing.timeScale, so the engines have
-- disagreement windows at both normal and slow-motion time scales.
MatterCalibration.BOX2D_RESTITUTION_THRESHOLD = 1
-- setCircle replaces Phaser's declared .0015 with Matter's .01 runtime value.
-- Keep that observed value in free flight as well as on supported contacts.
MatterCalibration.APPLE_FRICTION_AIR = 0.01
MatterCalibration.APPLE_FLIGHT_FRICTION_AIR = 0.01
-- Phaser adds its gravity acceleration after air-friction retention; Box2D
-- damps the gravity-updated velocity. 0.962001 maps Phaser's 10 m/s^2 onto
-- the 10.5 m/s^2 standard profile while compensating that ordering at 60 Hz.
MatterCalibration.APPLE_GAMEPLAY_GRAVITY_SCALE = 0.962001
-- The dotted predictor already executes Matter's update order directly.
MatterCalibration.APPLE_TRAJECTORY_GRAVITY_SCALE = 1
-- Extra tangential energy loss applied only while a contact supports the
-- apple against gravity. This approximates rolling resistance without
-- changing its free-flight trajectory or collision-normal velocity.
MatterCalibration.APPLE_ROLLING_DRAG = 0.005
MatterCalibration.APPLE_SUPPORT_DOT_MIN = 0.55
MatterCalibration.APPLE_STOP_TANGENT_SPEED = 0.06
MatterCalibration.APPLE_STOP_ANGULAR_SPEED = 0.20
MatterCalibration.APPLE_INITIAL_RESTITUTION = 0
-- Matter's runtime probe reports these values after every static body has
-- passed through Body.setStatic(true). The constructor values on floor,
-- ceiling, wall, and spring are not the values used by the solver.
MatterCalibration.SOURCE_STATIC_FRICTION = 1
MatterCalibration.SOURCE_STATIC_RESTITUTION = 0
-- Matter uses the lower kinetic coefficient for a sliding pair. Its static
-- branch has a separate threshold, so do not fold that threshold into the
-- Box2D fixture material or every landing becomes too sticky.
MatterCalibration.MATTER_RESTING_CONTACT_FRICTION = MatterCalibration.APPLE_FRICTION
    * MatterCalibration.APPLE_FRICTION_STATIC
    * MatterCalibration.MATTER_FRICTION_NORMAL_MULTIPLIER
-- Box2D combines fixture friction as sqrt(a * b). Use the source pair's
-- kinetic coefficient for both fixtures so sqrt(.1 * .1) remains .1, matching
-- Matter's min(.1, 1) sliding pair coefficient.
MatterCalibration.BOX2D_CONTACT_FRICTION = math.min(
    MatterCalibration.APPLE_FRICTION,
    MatterCalibration.SOURCE_STATIC_FRICTION
)
MatterCalibration.STATIC_FRICTION = MatterCalibration.BOX2D_CONTACT_FRICTION
MatterCalibration.STATIC_RESTITUTION = MatterCalibration.SOURCE_STATIC_RESTITUTION
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

---@param incoming Vector2
---@param solved Vector2
---@param normal Vector2 Unit normal pointing from the static fixture toward the apple.
---@param restitution number
---@param timeScale number
---@param matterVelocityToWorld number
---@return Vector2|nil corrected
function MatterCalibration.AlignRestitutionThreshold(incoming, solved, normal, restitution, timeScale, matterVelocityToWorld)
    if not incoming or not solved or not normal or restitution <= 0 then return nil end
    local length = math.sqrt(normal.x * normal.x + normal.y * normal.y)
    if length <= .000001 then return nil end
    local nx, ny = normal.x / length, normal.y / length
    local incomingNormal = incoming.x * nx + incoming.y * ny
    if incomingNormal >= 0 then return nil end
    local incomingSpeed = -incomingNormal
    local matterThreshold = MatterCalibration.MATTER_RESTING_NORMAL_SPEED
        * matterVelocityToWorld * timeScale
    local matterRestitutes = incomingSpeed > matterThreshold
    local box2dRestitutes = incomingSpeed > MatterCalibration.BOX2D_RESTITUTION_THRESHOLD
    -- Most impacts need no adapter. Correct only the two narrow disagreement
    -- windows: slow motion where Matter still bounces, and 1x low speed where
    -- Box2D bounces before Matter leaves its resting-contact branch.
    if matterRestitutes == box2dRestitutes then return nil end
    local desiredNormal = matterRestitutes and incomingSpeed * restitution or 0
    local solvedNormal = solved.x * nx + solved.y * ny
    return Vector2(
        solved.x + (desiredNormal - solvedNormal) * nx,
        solved.y + (desiredNormal - solvedNormal) * ny
    )
end

-- Matter's frictionStatic branch is a per-pair cached tangent impulse, not a
-- material coefficient. Box2D exposes no equivalent pair cache, so the
-- production adapter keeps the kinetic coefficient on every static fixture.
-- A global fixture swap on the shared apple would corrupt corners, rolling
-- contacts, and spring exits.

return MatterCalibration
