---@class MatterCalibration
local MatterCalibration = {}

-- Phaser's SetBody and Matter's Body.setStatic mutate the values supplied to
-- the scene constructors. These are the values that exist on the source
-- bodies while they are actually simulated, not the declarative level values.
MatterCalibration.APPLE_FRICTION = 0.1
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

return MatterCalibration
