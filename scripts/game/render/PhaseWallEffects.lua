-- Visual-only NanoVG effects for phaseable walls.
local PhaseWallEffects = {}

-- Central tuning surface. Durations are seconds; drawing sizes are design pixels.
PhaseWallEffects.CONFIG = {
    maxRipples = 8,
    maxOpenings = 6,
    edgeSampleSpacing = 20,
    edgeMaxSamples = 36,
    edgeOuterAmplitude = 0.85,
    edgeInnerAmplitude = 1.35,
    edgeFrequency = 10.5,
    rippleDuration = 0.28,
    rippleMaxRadius = 58,
    rippleStrength = 1,
    passDuration = 0.28,
    passOpenDuration = 0.09,
    passOpeningWidth = 54,
    passOpeningOffset = 7,
}

local CONFIG = PhaseWallEffects.CONFIG

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function rgba(color, alpha)
    return nvgRGBA(color[1], color[2], color[3], alpha or color[4] or 255)
end

local function ensureState(wall)
    if not wall.phaseFx then
        wall.phaseFx = {
            time = 0,
            ripples = {},
            openings = {},
        }
    end
    return wall.phaseFx
end

local function pushLimited(list, value, limit)
    if #list >= limit then table.remove(list, 1) end
    list[#list + 1] = value
end

local function compactTimedEvents(list, dt)
    local writeIndex = 1
    for readIndex = 1, #list do
        local event = list[readIndex]
        event.age = event.age + dt
        if event.age < event.duration then
            list[writeIndex] = event
            writeIndex = writeIndex + 1
        end
    end
    for index = #list, writeIndex, -1 do list[index] = nil end
end

function PhaseWallEffects.Initialize(wall)
    ensureState(wall)
end

function PhaseWallEffects.ResetRuntime(runtime)
    for _, wall in ipairs(runtime and runtime.ordered or {}) do
        if wall.type == "wall" and wall.phaseable then
            local fx = ensureState(wall)
            fx.time = 0
            for index = #fx.ripples, 1, -1 do fx.ripples[index] = nil end
            for index = #fx.openings, 1, -1 do fx.openings[index] = nil end
        end
    end
end

function PhaseWallEffects.UpdateRuntime(runtime, dt)
    dt = math.max(0, dt or 0)
    for _, wall in ipairs(runtime and runtime.ordered or {}) do
        if wall.type == "wall" and wall.phaseable then
            local fx = ensureState(wall)
            fx.time = fx.time + dt
            compactTimedEvents(fx.ripples, dt)
            compactTimedEvents(fx.openings, dt)
        end
    end
end

local function wallLocalPoint(wall, worldX, worldY)
    local rotation = math.rad(wall.node.rotation2D)
    local cosine, sine = math.cos(rotation), math.sin(rotation)
    local dx, dy = worldX - wall.worldX, worldY - wall.worldY
    return cosine * dx + sine * dy,
        -sine * dx + cosine * dy,
        cosine,
        sine
end

function PhaseWallEffects.FindContainingWall(runtime, worldX, worldY)
    for _, wall in ipairs(runtime and runtime.ordered or {}) do
        if wall.type == "wall" and wall.phaseable then
            local localX, localY = wallLocalPoint(wall, worldX, worldY)
            if math.abs(localX) <= wall.worldWidth * 0.5
                and math.abs(localY) <= wall.worldHeight * 0.5 then
                return wall
            end
        end
    end
    return nil
end

local function segmentAxisInterval(start, delta, minimum, maximum)
    if math.abs(delta) <= 0.000001 then
        if start < minimum or start > maximum then return nil end
        return -math.huge, math.huge
    end
    local first = (minimum - start) / delta
    local second = (maximum - start) / delta
    return math.min(first, second), math.max(first, second)
end

-- Find the first phaseable wall crossed by the swept apple-center segment.
-- This catches a complete crossing that happens between two physics callbacks.
function PhaseWallEffects.FindFirstCrossedWall(runtime, startX, startY, endX, endY)
    local bestWall, bestEntry, bestExit, bestStartsInside = nil, nil, nil, false
    for _, wall in ipairs(runtime and runtime.ordered or {}) do
        if wall.type == "wall" and wall.phaseable then
            local startLocalX, startLocalY = wallLocalPoint(wall, startX, startY)
            local endLocalX, endLocalY = wallLocalPoint(wall, endX, endY)
            local halfWidth, halfHeight = wall.worldWidth * 0.5, wall.worldHeight * 0.5
            local startInside = math.abs(startLocalX) <= halfWidth
                and math.abs(startLocalY) <= halfHeight
            local deltaX, deltaY = endLocalX - startLocalX, endLocalY - startLocalY
            local entryX, exitX = segmentAxisInterval(startLocalX, deltaX, -halfWidth, halfWidth)
            local entryY, exitY = segmentAxisInterval(startLocalY, deltaY, -halfHeight, halfHeight)
            if entryX and exitX and entryY and exitY then
                local entry = math.max(entryX, entryY)
                local exit = math.min(exitX, exitY)
                local crossed = entry <= exit and exit >= 0 and entry <= 1
                    and (not startInside or exit < 1 - 0.000001)
                if crossed then
                    entry = math.max(0, entry)
                    if not bestEntry or entry < bestEntry then
                        bestWall, bestEntry, bestExit, bestStartsInside =
                            wall, entry, math.min(1, exit), startInside
                    end
                end
            end
        end
    end
    return bestWall, bestEntry, bestExit, bestStartsInside
end

-- Project an apple position onto the nearest/expected wall face. The returned
-- u/v coordinates are normalized in the wall's visual local space.
local function surfacePoint(wall, worldX, worldY, velocity, traversalKind)
    local localX, localY, cosine, sine = wallLocalPoint(wall, worldX, worldY)
    local halfWidth = math.max(0.0001, wall.worldWidth * 0.5)
    local halfHeight = math.max(0.0001, wall.worldHeight * 0.5)
    local inside = math.abs(localX) <= halfWidth and math.abs(localY) <= halfHeight

    if inside and velocity then
        local velocityX = cosine * velocity.x + sine * velocity.y
        local velocityY = -sine * velocity.x + cosine * velocity.y
        if math.abs(velocityX) >= math.abs(velocityY) then
            local forward = velocityX >= 0 and halfWidth or -halfWidth
            localX = traversalKind == "enter" and -forward or forward
            localY = clamp(localY, -halfHeight, halfHeight)
        else
            local forward = velocityY >= 0 and halfHeight or -halfHeight
            localY = traversalKind == "enter" and -forward or forward
            localX = clamp(localX, -halfWidth, halfWidth)
        end
    elseif math.abs(localX / halfWidth) >= math.abs(localY / halfHeight) then
        localX = localX < 0 and -halfWidth or halfWidth
        localY = clamp(localY, -halfHeight, halfHeight)
    else
        localY = localY < 0 and -halfHeight or halfHeight
        localX = clamp(localX, -halfWidth, halfWidth)
    end

    -- World Y is up while NanoVG local Y is down.
    return clamp(localX / halfWidth, -1, 1), clamp(-localY / halfHeight, -1, 1)
end

function PhaseWallEffects.TriggerImpact(wall, worldX, worldY, velocity, strength)
    if not wall or not wall.phaseable then return end
    local u, v = surfacePoint(wall, worldX, worldY, velocity, "impact")
    local fx = ensureState(wall)
    pushLimited(fx.ripples, {
        u = u,
        v = v,
        age = 0,
        duration = CONFIG.rippleDuration,
        maxRadius = CONFIG.rippleMaxRadius,
        strength = strength or CONFIG.rippleStrength,
    }, CONFIG.maxRipples)
end

function PhaseWallEffects.TriggerPass(wall, worldX, worldY, velocity, kind)
    if not wall or not wall.phaseable then return end
    local u, v = surfacePoint(wall, worldX, worldY, velocity, kind)
    local fx = ensureState(wall)
    pushLimited(fx.ripples, {
        u = u,
        v = v,
        age = 0,
        duration = CONFIG.rippleDuration,
        maxRadius = CONFIG.rippleMaxRadius,
        strength = kind == "enter" and 1 or 0.82,
    }, CONFIG.maxRipples)
    pushLimited(fx.openings, {
        u = u,
        v = v,
        age = 0,
        duration = CONFIG.passDuration,
        openDuration = CONFIG.passOpenDuration,
        width = CONFIG.passOpeningWidth,
        offset = CONFIG.passOpeningOffset,
        kind = kind,
    }, CONFIG.maxOpenings)
end

local function eventFrame(event, halfWidth, halfHeight)
    local localX, localY = event.u * halfWidth, event.v * halfHeight
    if math.abs(event.u) >= math.abs(event.v) then
        local edge = event.u < 0 and "left" or "right"
        return edge, clamp(localY, -halfHeight, halfHeight),
            event.u < 0 and -halfWidth or halfWidth, localY
    end
    local edge = event.v < 0 and "top" or "bottom"
    return edge, clamp(localX, -halfWidth, halfWidth),
        localX, event.v < 0 and -halfHeight or halfHeight
end

local function openingFactor(event)
    if event.age <= event.openDuration then
        local progress = clamp(event.age / math.max(0.0001, event.openDuration), 0, 1)
        return math.sin(progress * math.pi * 0.5)
    end
    local closeDuration = math.max(0.0001, event.duration - event.openDuration)
    local progress = clamp((event.age - event.openDuration) / closeDuration, 0, 1)
    return math.cos(progress * math.pi * 0.5)
end

local function openingAt(fx, edge, along, halfWidth, halfHeight)
    ---@type boolean
    local gap = false
    local displacement = 0.0
    for _, event in ipairs(fx.openings) do
        local eventEdge, center = eventFrame(event, halfWidth, halfHeight)
        if eventEdge == edge then
            local factor = openingFactor(event)
            local halfGap = event.width * factor * 0.5
            local distance = math.abs(along - center)
            if distance < halfGap then gap = true end
            local shoulderRange = halfGap + 13
            if distance < shoulderRange and shoulderRange > 0 then
                local influence = 1 - clamp((distance - halfGap) / 13, 0, 1)
                displacement = math.max(displacement, event.offset * factor * influence)
            end
        end
    end
    return gap, displacement
end

local EDGE_PHASE = { top = 0.2, right = 1.7, bottom = 3.1, left = 4.6 }
local EDGE_ORDER = { "top", "right", "bottom", "left" }

-- Rebuild one border edge from sampled points so it remains readable while
-- carrying a restrained, time-varying field instability.
local function drawEdge(vg, fx, edge, halfWidth, halfHeight, inset, amplitude, speedScale, strokeColor, strokeWidth)
    local horizontal = edge == "top" or edge == "bottom"
    local halfLength = horizontal and halfWidth or halfHeight
    local length = halfLength * 2
    local samples = clamp(math.ceil(length / CONFIG.edgeSampleSpacing), 6, CONFIG.edgeMaxSamples)
    local normalX, normalY = 0, 0
    if edge == "top" then normalY = -1
    elseif edge == "bottom" then normalY = 1
    elseif edge == "left" then normalX = -1
    else normalX = 1 end
    local baseX = normalX * (halfWidth - inset)
    local baseY = normalY * (halfHeight - inset)
    local drawing = false

    nvgBeginPath(vg)
    for index = 0, samples do
        local along = -halfLength + length * index / samples
        local phase = fx.time * CONFIG.edgeFrequency * speedScale
            + along * 0.082 + EDGE_PHASE[edge]
        local noise = math.sin(phase) * 0.67
            + math.sin(phase * 1.71 - along * 0.039 + 0.8) * 0.33
        local gap, openingOffset = openingAt(fx, edge, along, halfWidth, halfHeight)
        local displacement = amplitude * noise + openingOffset
        local pointX = horizontal and along or baseX + normalX * displacement
        local pointY = horizontal and baseY + normalY * displacement or along
        if gap then
            drawing = false
        elseif drawing then
            nvgLineTo(vg, pointX, pointY)
        else
            nvgMoveTo(vg, pointX, pointY)
            drawing = true
        end
    end
    nvgStrokeColor(vg, strokeColor)
    nvgStrokeWidth(vg, strokeWidth)
    nvgStroke(vg)
end

local function drawFlowHighlights(vg, fx, halfWidth, halfHeight, colors)
    local horizontal = halfWidth >= halfHeight
    local halfLength = horizontal and halfWidth or halfHeight
    local length = halfLength * 2
    local center = -halfLength + ((fx.time * 72) % math.max(1, length + 42)) - 21
    local startAt = clamp(center - 12, -halfLength, halfLength)
    local endAt = clamp(center + 12, -halfLength, halfLength)
    if endAt <= startAt then return end
    local pulse = 0.55 + math.sin(fx.time * 8.2) * 0.2
    nvgStrokeColor(vg, rgba(colors.quantumSoft, math.floor(125 * pulse)))
    nvgStrokeWidth(vg, 1.35)
    nvgBeginPath(vg)
    if horizontal then
        nvgMoveTo(vg, startAt, -halfHeight + 2.2)
        nvgLineTo(vg, endAt, -halfHeight + 2.2)
        nvgMoveTo(vg, -endAt, halfHeight - 2.2)
        nvgLineTo(vg, -startAt, halfHeight - 2.2)
    else
        nvgMoveTo(vg, -halfWidth + 2.2, startAt)
        nvgLineTo(vg, -halfWidth + 2.2, endAt)
        nvgMoveTo(vg, halfWidth - 2.2, -endAt)
        nvgLineTo(vg, halfWidth - 2.2, -startAt)
    end
    nvgStroke(vg)
end

-- Contact diffraction: 2-3 flattened rings expand along the wall tangent and
-- fade quickly. A short edge highlight keeps the impact anchored to the membrane.
local function drawRipples(vg, fx, halfWidth, halfHeight, colors)
    for _, event in ipairs(fx.ripples) do
        local edge, _, centerX, centerY = eventFrame(event, halfWidth, halfHeight)
        local horizontal = edge == "top" or edge == "bottom"
        local progress = clamp(event.age / event.duration, 0, 1)
        for ring = 1, 3 do
            local delay = (ring - 1) * 0.1
            local ringProgress = clamp((progress - delay) / (1 - delay), 0, 1)
            local eased = 1 - (1 - ringProgress) * (1 - ringProgress)
            local radius = event.maxRadius * (0.16 + eased * 0.84)
            local alpha = math.floor((1 - ringProgress) * (1 - ringProgress)
                * event.strength * (ring == 1 and 150 or ring == 2 and 105 or 70))
            if alpha > 0 then
                nvgBeginPath(vg)
                if horizontal then
                    nvgEllipse(vg, centerX, centerY, radius, radius * 0.34)
                else
                    nvgEllipse(vg, centerX, centerY, radius * 0.34, radius)
                end
                nvgStrokeColor(vg, rgba(ring == 1 and colors.quantumSoft or colors.glassEdge, alpha))
                nvgStrokeWidth(vg, ring == 1 and 2 or 1.15)
                nvgStroke(vg)
            end
        end

        local edgeAlpha = math.floor((1 - progress) * event.strength * 185)
        local highlightLength = 12 + event.maxRadius * progress * 0.55
        nvgStrokeColor(vg, rgba(colors.quantumSoft, edgeAlpha))
        nvgStrokeWidth(vg, 2.6 - progress * 1.2)
        nvgBeginPath(vg)
        if horizontal then
            nvgMoveTo(vg, centerX - highlightLength, centerY)
            nvgLineTo(vg, centerX + highlightLength, centerY)
        else
            nvgMoveTo(vg, centerX, centerY - highlightLength)
            nvgLineTo(vg, centerX, centerY + highlightLength)
        end
        nvgStroke(vg)
    end
end

-- Pass-through opening: the sampled border leaves a gap; these two elastic
-- shoulders pull outward during the opening phase and then snap closed.
local function drawOpeningShoulders(vg, fx, halfWidth, halfHeight, colors)
    for _, event in ipairs(fx.openings) do
        local edge, _, centerX, centerY = eventFrame(event, halfWidth, halfHeight)
        local factor = openingFactor(event)
        local halfGap = event.width * factor * 0.5
        local offset = event.offset * factor
        local tangentX, tangentY, normalX, normalY
        if edge == "top" then tangentX, tangentY, normalX, normalY = 1, 0, 0, -1
        elseif edge == "bottom" then tangentX, tangentY, normalX, normalY = 1, 0, 0, 1
        elseif edge == "left" then tangentX, tangentY, normalX, normalY = 0, 1, -1, 0
        else tangentX, tangentY, normalX, normalY = 0, 1, 1, 0 end
        local alpha = math.floor(205 * factor)
        nvgStrokeColor(vg, rgba(event.kind == "enter" and colors.quantumSoft or colors.glassEdge, alpha))
        nvgStrokeWidth(vg, 2.2)
        nvgBeginPath(vg)
        for sideIndex = 1, 2 do
            local side = sideIndex == 1 and -1 or 1
            local shoulder = halfGap + 11
            nvgMoveTo(vg,
                centerX + tangentX * shoulder * side,
                centerY + tangentY * shoulder * side)
            nvgLineTo(vg,
                centerX + tangentX * (halfGap + 3) * side + normalX * offset * 0.55,
                centerY + tangentY * (halfGap + 3) * side + normalY * offset * 0.55)
            nvgLineTo(vg,
                centerX + tangentX * halfGap * side + normalX * offset,
                centerY + tangentY * halfGap * side + normalY * offset)
        end
        nvgStroke(vg)
    end
end

function PhaseWallEffects.Draw(renderer, wall, width, height, colors)
    local vg = renderer.vg
    local fx = ensureState(wall)
    local halfWidth, halfHeight = width * 0.5, height * 0.5

    -- Edge instability: a stable outer contour, livelier inner line, and faint
    -- after-image retain a clear collision silhouette without neon bloom.
    for _, edge in ipairs(EDGE_ORDER) do
        drawEdge(vg, fx, edge, halfWidth, halfHeight, 0,
            CONFIG.edgeOuterAmplitude * 1.55, 0.82, rgba(colors.glassEdge, 45), 4.2)
        drawEdge(vg, fx, edge, halfWidth, halfHeight, 0,
            CONFIG.edgeOuterAmplitude, 1, rgba(colors.glassEdge, 225), 2.25)
        drawEdge(vg, fx, edge, halfWidth, halfHeight, 3,
            CONFIG.edgeInnerAmplitude, 1.18, rgba(colors.quantumSoft, 155), 1.05)
    end
    drawFlowHighlights(vg, fx, halfWidth, halfHeight, colors)
    drawRipples(vg, fx, halfWidth, halfHeight, colors)
    drawOpeningShoulders(vg, fx, halfWidth, halfHeight, colors)
end

return PhaseWallEffects
