local BehaviorState = {}
BehaviorState.__index = BehaviorState

BehaviorState.IDLE = "IDLE"
BehaviorState.WALK = "WALK"
BehaviorState.ROAM = "ROAM"
BehaviorState.DRAGGING = "DRAGGING"
BehaviorState.DRAG = BehaviorState.DRAGGING
BehaviorState.INTERACT = "INTERACT"
BehaviorState.OBSERVE = "OBSERVE"
BehaviorState.DIALOGUE = "DIALOGUE"
BehaviorState.OFFER = "OFFER"
BehaviorState.TAKEOVER = "TAKEOVER"
BehaviorState.SUCCESS = "SUCCESS"
BehaviorState.DISABLED = "DISABLED"

BehaviorState.ALL = {
    IDLE = true,
    WALK = true,
    ROAM = true,
    DRAGGING = true,
    INTERACT = true,
    OBSERVE = true,
    DIALOGUE = true,
    OFFER = true,
    TAKEOVER = true,
    SUCCESS = true,
    DISABLED = true,
}

local function Normalize(state)
    assert(type(state) == "string" and state ~= "", "behavior state is required")
    local normalized = string.upper(state)
    if normalized == "DRAG" then normalized = BehaviorState.DRAGGING end
    assert(BehaviorState.ALL[normalized], "unknown GreenAssistant behavior: " .. tostring(state))
    return normalized
end

function BehaviorState.New(initialState, onChanged)
    local self = setmetatable({}, BehaviorState)
    self.current = Normalize(initialState or BehaviorState.IDLE)
    self.previous = nil
    self.elapsed = 0
    self.onChanged = onChanged
    return self
end

BehaviorState.new = BehaviorState.New

function BehaviorState:setOnChanged(callback)
    self.onChanged = callback
end

function BehaviorState:set(state, reason)
    local nextState = Normalize(state)
    if nextState == self.current then return false end
    local previous = self.current
    self.previous = previous
    self.current = nextState
    self.elapsed = 0
    if self.onChanged then self.onChanged(nextState, previous, reason) end
    return true
end

function BehaviorState:update(dt)
    self.elapsed = self.elapsed + math.max(0, dt or 0)
end

function BehaviorState:get()
    return self.current
end

function BehaviorState:is(state)
    return self.current == Normalize(state)
end

return BehaviorState
