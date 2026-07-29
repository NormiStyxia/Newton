local AnimationState = {}
AnimationState.__index = AnimationState

AnimationState.IDLE = "IDLE"
AnimationState.IDLE_BASE = "IDLE_BASE"
AnimationState.MOVE = "MOVE"
AnimationState.WALK = "WALK"
AnimationState.DRAG = "DRAG"
AnimationState.BLINK = "BLINK"
AnimationState.POKE = "POKE"
AnimationState.OBSERVE = "OBSERVE"
AnimationState.THINKING = "THINKING"
AnimationState.TALK = "TALK"
AnimationState.OFFER = "OFFER"
AnimationState.TAKEOVER = "TAKEOVER"
AnimationState.SUCCESS = "SUCCESS"
AnimationState.ANNOYED = "ANNOYED"
AnimationState.SLEEP = "SLEEP"

local function NormalizeBehavior(behavior)
    assert(type(behavior) == "string" and behavior ~= "", "behavior is required")
    return string.upper(behavior)
end

function AnimationState.New(mapping, fallbackAnimation)
    local self = setmetatable({}, AnimationState)
    self.mapping = {}
    self.fallbackAnimation = fallbackAnimation or "idle"
    for behavior, animation in pairs(mapping or {}) do
        self.mapping[NormalizeBehavior(behavior)] = animation
    end
    return self
end

AnimationState.new = AnimationState.New

function AnimationState:setBehaviorAnimation(behavior, animation)
    assert(type(animation) == "string" and animation ~= "", "animation is required")
    self.mapping[NormalizeBehavior(behavior)] = animation
end

function AnimationState:getBehaviorAnimation(behavior)
    return self.mapping[NormalizeBehavior(behavior)]
end

function AnimationState:resolve(behavior, hasAnimation)
    local desired = self:getBehaviorAnimation(behavior) or self.fallbackAnimation
    if not hasAnimation or hasAnimation(desired) then return desired end
    if hasAnimation(self.fallbackAnimation) then return self.fallbackAnimation end
    return nil
end

return AnimationState
