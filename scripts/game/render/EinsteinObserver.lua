local M = {}

local CONFIG = {
    portrait = {
        width = 438,
        height = 453,
        originX = 0.5,
        originY = 0.5077348066,
    },
    leftEye = {
        centerX = 0.3675799087,
        centerY = 0.5486187845,
        radius = 0.0473744292,
    },
    rightEye = {
        centerX = 0.6181506849,
        centerY = 0.5475138122,
        radius = 0.0473744292,
    },
    dotRadius = 0.010,
    padding = 0.004,
    followSpeed = 10,
    epsilon = 0.0001,
}

M.CONFIG = CONFIG

local DOT_FILL = { 255, 253, 244, 255 }
local DOT_EDGE = { 196, 204, 244, 255 }

local function updateGoalDirection(goal, apple, dt)
    if not goal.node or not apple or not apple.node then return end
    local sensorPosition = goal.node.position2D
    local applePosition = apple.node.position2D
    if not sensorPosition or not applePosition then return end

    local dx = applePosition.x - sensorPosition.x
    local dy = applePosition.y - sensorPosition.y
    local distanceSquared = dx * dx + dy * dy
    if distanceSquared < CONFIG.epsilon * CONFIG.epsilon then return end

    local inverseDistance = 1 / math.sqrt(distanceSquared)
    local targetX = dx * inverseDistance
    -- World coordinates are Y-up; NanoVG portrait coordinates are Y-down.
    local targetY = -dy * inverseDistance
    local trackedX = goal.einsteinTrackedDirX
    local trackedY = goal.einsteinTrackedDirY
    if trackedX == nil or trackedY == nil then
        goal.einsteinTrackedDirX = targetX
        goal.einsteinTrackedDirY = targetY
        return
    end

    local follow = 1 - math.exp(-CONFIG.followSpeed * math.max(0, dt or 0))
    local blendedX = trackedX + (targetX - trackedX) * follow
    local blendedY = trackedY + (targetY - trackedY) * follow
    local blendedLengthSquared = blendedX * blendedX + blendedY * blendedY
    if blendedLengthSquared <= 0.000000000001 then return end
    local inverseBlendedLength = 1 / math.sqrt(blendedLengthSquared)
    goal.einsteinTrackedDirX = blendedX * inverseBlendedLength
    goal.einsteinTrackedDirY = blendedY * inverseBlendedLength
end

function M.Update(runtime, apple, dt, paused)
    if paused or not runtime or not runtime.ordered or not apple then return end
    for _, object in ipairs(runtime.ordered) do
        if object.type == "goal_sensor" then
            updateGoalDirection(object, apple, dt)
        end
    end
end

local function drawEyeDot(renderer, portraitLeft, portraitTop, portraitWidth, portraitHeight, eye, dirX, dirY)
    local dotRadius = math.max(1, CONFIG.dotRadius * portraitWidth)
    local padding = CONFIG.padding * portraitWidth
    local eyeRadius = eye.radius * portraitWidth
    local moveRadius = math.max(0, eyeRadius - dotRadius - padding)
    local eyeX = portraitLeft + eye.centerX * portraitWidth
    local eyeY = portraitTop + eye.centerY * portraitHeight
    renderer:Circle(
        eyeX + dirX * moveRadius,
        eyeY + dirY * moveRadius,
        dotRadius,
        DOT_FILL,
        DOT_EDGE,
        math.max(0.65, portraitWidth * 0.002),
        248
    )
end

function M.Draw(renderer, image, centerX, centerY, diameter, goal)
    if not image or image < 0 or diameter <= 0 then return false end
    local portraitWidth = diameter
    local portraitHeight = portraitWidth * CONFIG.portrait.height / CONFIG.portrait.width
    local portraitLeft = centerX - portraitWidth * CONFIG.portrait.originX
    local portraitTop = centerY - portraitHeight * CONFIG.portrait.originY
    renderer:Image(
        image,
        centerX,
        centerY,
        portraitWidth,
        portraitHeight,
        1,
        nil,
        CONFIG.portrait.originX,
        CONFIG.portrait.originY
    )

    local dirX = goal and goal.einsteinTrackedDirX or 0
    local dirY = goal and goal.einsteinTrackedDirY or -1
    drawEyeDot(renderer, portraitLeft, portraitTop, portraitWidth, portraitHeight, CONFIG.leftEye, dirX, dirY)
    drawEyeDot(renderer, portraitLeft, portraitTop, portraitWidth, portraitHeight, CONFIG.rightEye, dirX, dirY)
    return true
end

return M
