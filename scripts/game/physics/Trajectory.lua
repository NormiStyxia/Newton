---@class TrajectoryPrediction
local TrajectoryPrediction = {}

local MATTER_BASE_DELTA_MS = 1000 / 60

---@param input table
---@return table
function TrajectoryPrediction.PredictFreeFlight(input)
    local points = {}
    local frictionFactor = math.max(0, 1 - input.frictionAir)
    local accelerationScale = input.forceScale * MATTER_BASE_DELTA_MS * MATTER_BASE_DELTA_MS
    local accelerationX = input.gravityX * accelerationScale
    local accelerationY = input.gravityY * accelerationScale
    local x, y = input.x, input.y
    local velocityX, velocityY = input.velocityX, input.velocityY

    for frame = 1, input.steps do
        velocityX = velocityX * frictionFactor + accelerationX
        velocityY = velocityY * frictionFactor + accelerationY
        x = x + velocityX
        y = y + velocityY

        local speed = math.sqrt(velocityX * velocityX + velocityY * velocityY)
        if speed > input.maxSpeed then
            velocityX = velocityX * input.maxSpeed / speed
            velocityY = velocityY * input.maxSpeed / speed
        end
        if frame % input.sampleEvery == 0 then
            points[#points + 1] = { x = x, y = y, frame = frame }
        end
    end
    return points
end

return TrajectoryPrediction
