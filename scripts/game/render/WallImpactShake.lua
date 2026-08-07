-- Short, visual-only impact response for level wall renderers.
local WallImpactShake = {}

-- Speeds are 1x gameplay metres/second; amplitudes are final logical pixels.
-- Launches span roughly 2.38-9.70 m/s, the gameplay cap is 15 m/s, and the
-- native wall probes observed a light 3.36 m/s touch and a 17.64 m/s hard hit.
WallImpactShake.CONFIG = {
    enabled = true,
    minImpactSpeed = 4.0,
    strongImpactSpeed = 15.0,
    minAmplitudePx = 0.6,
    maxAmplitudePx = 4.0,
    minDuration = 0.07,
    maxDuration = 0.18,
    maxRotationDeg = 0.28,
    retriggerCooldown = 0.06,
    tangentRatio = 0.08,
    debug = false,
}

local CONFIG = WallImpactShake.CONFIG

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function smoothstep(value)
    local t = clamp(value, 0, 1)
    return t * t * (3 - 2 * t)
end

local function stableSign(id)
    local text = tostring(id or "wall")
    local hash = 0
    for index = 1, #text do
        hash = (hash + string.byte(text, index) * index) % 2
    end
    return hash == 0 and -1 or 1
end

local function ensureState(wall)
    if not wall.wallShake then
        wall.wallShake = {
            active = false,
            amplitude = 0,
            directionX = 0,
            directionY = 0,
            rotationAmplitude = 0,
            elapsed = 0,
            duration = 0,
            cooldownRemaining = 0,
            visualShakeX = 0,
            visualShakeY = 0,
            visualShakeRotation = 0,
            fallbackSign = stableSign(wall.id),
        }
    end
    return wall.wallShake
end

local function clearVisualState(state)
    state.active = false
    state.amplitude = 0
    state.directionX = 0
    state.directionY = 0
    state.rotationAmplitude = 0
    state.elapsed = 0
    state.duration = 0
    state.cooldownRemaining = 0
    state.visualShakeX = 0
    state.visualShakeY = 0
    state.visualShakeRotation = 0
end

function WallImpactShake.Initialize(wall)
    ensureState(wall)
end

function WallImpactShake.Reset(wall)
    if wall and wall.wallShake then clearVisualState(wall.wallShake) end
end

function WallImpactShake.ResetRuntime(runtime)
    for _, wall in ipairs(runtime and runtime.ordered or {}) do
        if wall.type == "wall" then WallImpactShake.Reset(wall) end
    end
end

local function impactWave(progress, rebound)
    if progress <= 0.25 then
        return smoothstep(progress / 0.25)
    end
    if progress <= 0.55 then
        local t = smoothstep((progress - 0.25) / 0.30)
        return 1 + (-rebound - 1) * t
    end
    local t = smoothstep((progress - 0.55) / 0.45)
    return -rebound * (1 - t)
end

local function updateWall(wall, dt)
    local state = wall.wallShake
    if not state then return end
    state.cooldownRemaining = math.max(0, state.cooldownRemaining - dt)
    if not state.active then return end

    state.elapsed = state.elapsed + dt
    local progress = state.duration > 0 and state.elapsed / state.duration or 1
    if progress >= 1 then
        clearVisualState(state)
        return
    end

    local translation = impactWave(progress, 0.35)
    local rotation = impactWave(progress, 0.40)
    local offset = state.amplitude * translation
    state.visualShakeX = state.directionX * offset
    state.visualShakeY = state.directionY * offset
    state.visualShakeRotation = state.rotationAmplitude * rotation
end

function WallImpactShake.UpdateRuntime(runtime, dt)
    ---@diagnostic disable-next-line: unnecessary-if
    if rawget(CONFIG, "enabled") == false then
        WallImpactShake.ResetRuntime(runtime)
        return
    end
    dt = math.max(0, dt or 0)
    for _, wall in ipairs(runtime and runtime.ordered or {}) do
        if wall.type == "wall" and wall.wallShake then updateWall(wall, dt) end
    end
end

---@param wall table
---@param appleVelocity Vector2
---@param collisionNormal Vector2 Surface normal pointing from the wall toward the apple.
---@param contactX number|nil
---@param contactY number|nil
---@param timeScale number|nil
---@return boolean triggered
---@return number impactSpeed
---@return number intensity
function WallImpactShake.Trigger(wall, appleVelocity, collisionNormal, contactX, contactY, timeScale)
    if rawget(CONFIG, "enabled") == false
        or not wall or wall.type ~= "wall" or not appleVelocity or not collisionNormal then
        return false, 0, 0
    end

    local normalLength = math.sqrt(collisionNormal.x * collisionNormal.x + collisionNormal.y * collisionNormal.y)
    if normalLength <= 0.000001 then return false, 0, 0 end
    local normalX, normalY = collisionNormal.x / normalLength, collisionNormal.y / normalLength

    local wallVelocityX, wallVelocityY = 0, 0
    if wall.body then
        local wallVelocity = wall.body.linearVelocity
        if wallVelocity then wallVelocityX, wallVelocityY = wallVelocity.x, wallVelocity.y end
    end
    local scale = math.max(0.001, math.abs(timeScale or 1))
    local relativeX = (appleVelocity.x - wallVelocityX) / scale
    local relativeY = (appleVelocity.y - wallVelocityY) / scale
    local impactSpeed = math.abs(relativeX * normalX + relativeY * normalY)
    if impactSpeed <= CONFIG.minImpactSpeed then return false, impactSpeed, 0 end

    local range = math.max(0.000001, CONFIG.strongImpactSpeed - CONFIG.minImpactSpeed)
    local normalized = clamp((impactSpeed - CONFIG.minImpactSpeed) / range, 0, 1)
    local intensity = smoothstep(normalized)
    local amplitude = CONFIG.minAmplitudePx
        + (CONFIG.maxAmplitudePx - CONFIG.minAmplitudePx) * intensity
    local duration = CONFIG.minDuration
        + (CONFIG.maxDuration - CONFIG.minDuration) * intensity
    local state = ensureState(wall)

    -- Begin-contact already suppresses stays. The cooldown additionally rejects
    -- duplicate begin events, while a genuinely stronger hit may replace one shake.
    if state.cooldownRemaining > 0 and (not state.active or amplitude <= state.amplitude) then
        return false, impactSpeed, intensity
    end
    if state.active and amplitude <= state.amplitude then return false, impactSpeed, intensity end

    -- The wall first moves away from the apple. Convert the Y-up world vector
    -- to the Y-down NanoVG design space, then add a small deterministic tangent.
    local directionX, directionY = -normalX, normalY
    local tangentX, tangentY = -directionY, directionX
    local tangent = CONFIG.tangentRatio * intensity * state.fallbackSign
    directionX, directionY = directionX + tangentX * tangent, directionY + tangentY * tangent
    local directionLength = math.sqrt(directionX * directionX + directionY * directionY)
    directionX, directionY = directionX / directionLength, directionY / directionLength

    local rotationSign = state.fallbackSign
    local center = wall.node and wall.node.position2D or nil
    if contactX ~= nil and contactY ~= nil and center then
        local forceX, forceY = -normalX, -normalY
        local torque = (contactX - center.x) * forceY - (contactY - center.y) * forceX
        if math.abs(torque) > 0.000001 then rotationSign = torque > 0 and -1 or 1 end
    end

    state.active = true
    state.amplitude = amplitude
    state.directionX = directionX
    state.directionY = directionY
    state.rotationAmplitude = math.rad(CONFIG.maxRotationDeg * intensity) * rotationSign
    state.elapsed = 0
    state.duration = duration
    state.cooldownRemaining = CONFIG.retriggerCooldown
    state.visualShakeX = 0
    state.visualShakeY = 0
    state.visualShakeRotation = 0

    ---@diagnostic disable-next-line: unnecessary-if
    if rawget(CONFIG, "debug") == true then
        print(string.format(
            "[WallImpact] wall=%s speed=%.2f intensity=%.2f amp=%.2fpx duration=%.3fs",
            tostring(wall.id), impactSpeed, intensity, amplitude, duration
        ))
    end
    return true, impactSpeed, intensity
end

return WallImpactShake
