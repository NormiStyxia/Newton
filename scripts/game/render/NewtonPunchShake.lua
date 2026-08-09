-- Short, visual-only impact response for the Gameplay world.
-- The state is independent from every physics node; it is read only by the
-- world renderer and advances on the existing gameplay visual clock.
local NewtonPunchShake = {}
local WallImpactShake = require("game.render.WallImpactShake")

NewtonPunchShake.CONFIG = {
    enabled = true,
    duration = 0.15,
    translatePx = 8,
    rotationDeg = 0.30,
}

local CONFIG = NewtonPunchShake.CONFIG

local function clear(state)
    if not state then return end
    state.active = false
    state.elapsed = 0
    state.directionX = 0
    state.directionY = 0
    state.rotationAmplitude = 0
    state.visualShakeX = 0
    state.visualShakeY = 0
    state.visualShakeRotation = 0
end

local function ensure(state)
    if not state then return nil end
    if state.active == nil then clear(state) end
    if state.impulseSign == nil then state.impulseSign = 1 end
    return state
end

function NewtonPunchShake.Initialize(state)
    ensure(state)
end

function NewtonPunchShake.Reset(state)
    clear(ensure(state))
end

function NewtonPunchShake.Trigger(state)
    state = ensure(state)
    if not state or rawget(CONFIG, "enabled") == false then return false end

    -- Alternate a small, deterministic impulse direction so repeated runs do
    -- not look like a fixed one-sided camera nudge.
    state.impulseSign = -(state.impulseSign or 1)
    local sign = state.impulseSign
    state.active = true
    state.elapsed = 0
    state.directionX = -0.92 * sign
    state.directionY = 0.26 * sign
    state.rotationAmplitude = math.rad(CONFIG.rotationDeg) * sign
    state.visualShakeX = 0
    state.visualShakeY = 0
    state.visualShakeRotation = 0
    return true
end

function NewtonPunchShake.Update(state, dt)
    state = ensure(state)
    if not state then return end
    if rawget(CONFIG, "enabled") == false then
        clear(state)
        return
    end
    if not state.active then return end
    state.elapsed = state.elapsed + math.max(0, dt or 0)
    local progress = CONFIG.duration > 0 and state.elapsed / CONFIG.duration or 1
    if progress >= 1 then
        clear(state)
        return
    end

    -- Reuse the wall impact response's compact 0 -> hit -> rebound -> zero
    -- curve instead of allocating a tween or sampling per-frame randomness.
    local translation = WallImpactShake.SampleWave(progress, 0.35)
    local rotation = WallImpactShake.SampleWave(progress, 0.40)
    state.visualShakeX = state.directionX * CONFIG.translatePx * translation
    state.visualShakeY = state.directionY * CONFIG.translatePx * translation
    state.visualShakeRotation = state.rotationAmplitude * rotation
end

return NewtonPunchShake
