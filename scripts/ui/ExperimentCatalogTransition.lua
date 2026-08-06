local Transition = {}
Transition.__index = Transition

Transition.State = {
    IDLE = "IDLE",
    TRANSITIONING = "TRANSITIONING",
}

local PAPER_DURATION = 0.40
local PAPER_ENTRY_DELAY = 0.08
local FAST_SETTLE_DURATION = 0.10
local REPORT_FADE_OUT = 0.13
local REPORT_BIND_DELAY = 0.20
local REPORT_FADE_IN = 0.18

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function easeOutCubic(value)
    value = clamp(value or 0, 0, 1)
    return 1 - (1 - value) ^ 3
end

function Transition.New(initialIndex)
    local self = setmetatable({}, Transition)
    self.currentIndex = math.max(1, tonumber(initialIndex) or 1)
    self.outgoingIndex = nil
    self.incomingIndex = nil
    self.pendingIndex = nil
    self.direction = 1
    self.elapsed = 0
    self.fastSettle = false
    self.state = Transition.State.IDLE
    self.briefFromIndex = self.currentIndex
    self.briefToIndex = self.currentIndex
    self.briefElapsed = REPORT_BIND_DELAY + REPORT_FADE_IN
    return self
end

function Transition:Reset(index)
    self.currentIndex = math.max(1, tonumber(index) or self.currentIndex or 1)
    self.outgoingIndex, self.incomingIndex, self.pendingIndex = nil, nil, nil
    self.elapsed, self.fastSettle = 0, false
    self.state = Transition.State.IDLE
    self.briefFromIndex, self.briefToIndex = self.currentIndex, self.currentIndex
    self.briefElapsed = REPORT_BIND_DELAY + REPORT_FADE_IN
end

function Transition:_briefVisibleIndex()
    if self.briefElapsed < REPORT_FADE_OUT then return self.briefFromIndex end
    if self.briefElapsed < REPORT_BIND_DELAY then return nil end
    return self.briefToIndex
end

function Transition:_beginBriefTransition(targetIndex)
    self.briefFromIndex = self:_briefVisibleIndex() or self.briefToIndex or self.currentIndex
    self.briefToIndex = targetIndex
    self.briefElapsed = 0
end

function Transition:_start(fromIndex, toIndex, preserveBrief)
    if fromIndex == toIndex then self:Reset(toIndex); return false end
    self.currentIndex = fromIndex
    self.outgoingIndex = fromIndex
    self.incomingIndex = toIndex
    self.direction = toIndex > fromIndex and 1 or -1
    self.elapsed, self.fastSettle = 0, false
    self.state = Transition.State.TRANSITIONING
    if not preserveBrief then self:_beginBriefTransition(toIndex) end
    return true
end

function Transition:Request(targetIndex)
    targetIndex = math.max(1, tonumber(targetIndex) or self.currentIndex)
    if self.state == Transition.State.IDLE then
        return self:_start(self.currentIndex, targetIndex, false)
    end
    if targetIndex == self.pendingIndex then return false end
    if targetIndex == self.incomingIndex then
        self.pendingIndex = nil
        self.fastSettle = true
        self:_beginBriefTransition(targetIndex)
        return true
    end

    -- Do not queue paper swaps. The active pair settles quickly, then the
    -- latest requested experiment becomes the only new destination.
    self.pendingIndex = targetIndex
    self.fastSettle = true
    self:_beginBriefTransition(targetIndex)
    return true
end

function Transition:Update(dt)
    dt = math.max(0, tonumber(dt) or 0)
    self.briefElapsed = self.briefElapsed + dt
    if self.state ~= Transition.State.TRANSITIONING then return end

    if self.fastSettle then
        self.elapsed = math.min(PAPER_DURATION, self.elapsed + dt * PAPER_DURATION / FAST_SETTLE_DURATION)
    else
        self.elapsed = self.elapsed + dt
    end
    if self.elapsed < PAPER_DURATION then return end

    self.currentIndex = self.incomingIndex or self.currentIndex
    local pending = self.pendingIndex
    self.outgoingIndex, self.incomingIndex, self.pendingIndex = nil, nil, nil
    self.elapsed, self.fastSettle = 0, false
    self.state = Transition.State.IDLE
    if pending and pending ~= self.currentIndex then
        self:_start(self.currentIndex, pending, true)
    end
end

function Transition:IsSettled()
    return self.state == Transition.State.IDLE and self.pendingIndex == nil
end

function Transition:GetPreviewPapers(viewportWidth)
    if self.state == Transition.State.IDLE then
        return { { index = self.currentIndex, offsetX = 0, rotation = 0, alpha = 1, scale = 1 } }
    end
    local outgoingProgress = easeOutCubic(self.elapsed / PAPER_DURATION)
    local entryProgress = easeOutCubic((self.elapsed - PAPER_ENTRY_DELAY) / (PAPER_DURATION - PAPER_ENTRY_DELAY))
    local span = math.max(1, viewportWidth) * 1.05
    return {
        {
            index = self.outgoingIndex,
            offsetX = -self.direction * span * outgoingProgress,
            rotation = -self.direction * math.rad(1.1) * outgoingProgress,
            alpha = 1 - .08 * outgoingProgress,
            scale = 1,
        },
        {
            index = self.incomingIndex,
            offsetX = self.direction * span * (1 - entryProgress),
            rotation = self.direction * math.rad(1.1) * (1 - entryProgress),
            alpha = .92 + .08 * entryProgress,
            scale = 1.005 - .005 * entryProgress,
        },
    }
end

function Transition:GetBriefView()
    if self.briefElapsed < REPORT_FADE_OUT then
        return {
            index = self.briefFromIndex,
            alpha = 1 - easeOutCubic(self.briefElapsed / REPORT_FADE_OUT),
        }
    end
    if self.briefElapsed < REPORT_BIND_DELAY then return nil end
    return {
        index = self.briefToIndex,
        alpha = easeOutCubic((self.briefElapsed - REPORT_BIND_DELAY) / REPORT_FADE_IN),
    }
end

return Transition
