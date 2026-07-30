---@class ReplayTimeline
local ReplayTimeline = {}

local function InterpolateAngle(from, to, progress)
    local delta = ((to - from + 540) % 360) - 180
    return from + delta * progress
end

---@param playhead number
---@param duration number
---@param frameDeltaMs number
---@param speed number
---@return number
function ReplayTimeline.Advance(playhead, duration, frameDeltaMs, speed)
    local boundedDuration = math.max(0, duration or 0)
    local start = math.max(0, math.min(boundedDuration, playhead or 0))
    local delta = math.max(0, frameDeltaMs or 0)
    local playbackSpeed = math.max(0, speed or 0)
    return math.min(boundedDuration, start + delta * playbackSpeed)
end

---@param samples table[]
---@param playhead number
---@return table|nil
function ReplayTimeline.StateAt(samples, playhead)
    if #samples == 0 then return nil end
    if playhead <= samples[1].t then return samples[1] end
    local last = samples[#samples]
    if playhead >= last.t then return last end

    local low, high = 1, #samples
    while low + 1 < high do
        local middle = math.floor((low + high) * .5)
        if samples[middle].t <= playhead then low = middle else high = middle end
    end
    local from, to = samples[low], samples[high]
    local progress = (playhead - from.t) / math.max(.0001, to.t - from.t)
    return {
        x = from.x + (to.x - from.x) * progress,
        y = from.y + (to.y - from.y) * progress,
        vx = from.vx + (to.vx - from.vx) * progress,
        vy = from.vy + (to.vy - from.vy) * progress,
        angle = InterpolateAngle(from.angle, to.angle, progress),
    }
end

---@param samples table[]
---@param playhead number
---@return table[]
function ReplayTimeline.SamplesThrough(samples, playhead)
    local visible = {}
    for _, sample in ipairs(samples) do
        if sample.t > playhead then break end
        visible[#visible + 1] = sample
    end
    local state = ReplayTimeline.StateAt(samples, playhead)
    if not state then return visible end
    local last = visible[#visible]
    if not last or math.abs(last.t - playhead) > .001 then
        visible[#visible + 1] = {
            t = playhead,
            x = state.x,
            y = state.y,
            vx = state.vx,
            vy = state.vy,
            angle = state.angle,
        }
    end
    return visible
end

return ReplayTimeline
