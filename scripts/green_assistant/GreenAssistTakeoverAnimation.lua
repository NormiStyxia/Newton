---@class GreenAssistTakeoverAnimation
local TakeoverAnimation = {}
TakeoverAnimation.__index = TakeoverAnimation

TakeoverAnimation.Phase = {
    IDLE = "IDLE",
    RAISE = "RAISE",
    LOOP = "LOOP",
    FINISH = "FINISH",
}

function TakeoverAnimation.New(animator, config, callbacks)
    local self = setmetatable({}, TakeoverAnimation)
    self.animator = assert(animator, "GreenAssistTakeoverAnimation animator is required")
    self.config = config or {}
    self.callbacks = callbacks or {}
    self.phase = TakeoverAnimation.Phase.IDLE
    self.loopElapsed = 0
    self.finishRequest = nil
    self.token = 0
    return self
end

TakeoverAnimation.new = TakeoverAnimation.New

function TakeoverAnimation:_play(name, options)
    if type(name) ~= "string" or not self.animator:hasAnimation(name) then return false end
    options = options or {}
    options.restart = true
    options.fallbackAnimation = self.config.fallbackAnimation
    return self.animator:play(name, options)
end

function TakeoverAnimation:_minimumLoopDuration()
    local cycles = math.max(0, self.config.minimumLoopCycles or 1)
    if cycles == 0 then return 0 end
    local duration = self.animator:getAnimationDuration(self.config.loop)
    return duration and duration * cycles or 0
end

function TakeoverAnimation:_complete(token)
    if token ~= self.token then return end
    local request = self.finishRequest
    self.phase = TakeoverAnimation.Phase.IDLE
    self.loopElapsed = 0
    self.finishRequest = nil
    if self.callbacks.onFinished then self.callbacks.onFinished(request) end
end

function TakeoverAnimation:_beginFinish(token)
    if token ~= self.token or self.phase == TakeoverAnimation.Phase.FINISH then return false end
    self.phase = TakeoverAnimation.Phase.FINISH
    local played = self:_play(self.config.finish, {
        onFinished = function()
            self:_complete(token)
        end,
    })
    if not played then self:_complete(token) end
    return true
end

function TakeoverAnimation:_beginLoop(token)
    if token ~= self.token then return false end
    self.phase = TakeoverAnimation.Phase.LOOP
    self.loopElapsed = 0
    self:_play(self.config.loop)
    if self.finishRequest and self:_minimumLoopDuration() <= 0 then
        self:_beginFinish(token)
    end
    return true
end

function TakeoverAnimation:start()
    self.token = self.token + 1
    local token = self.token
    self.finishRequest = nil
    self.loopElapsed = 0
    self.phase = TakeoverAnimation.Phase.RAISE
    local played = self:_play(self.config.raise, {
        onFinished = function()
            self:_beginLoop(token)
        end,
    })
    if not played then self:_beginLoop(token) end
    return true
end

function TakeoverAnimation:requestFinish(request)
    if self.phase == TakeoverAnimation.Phase.IDLE then return false end
    self.finishRequest = request or {}
    if self.phase == TakeoverAnimation.Phase.LOOP
        and self.loopElapsed >= self:_minimumLoopDuration() then
        self:_beginFinish(self.token)
    end
    return true
end

function TakeoverAnimation:update(dt)
    if self.phase ~= TakeoverAnimation.Phase.LOOP then return end
    self.loopElapsed = self.loopElapsed + math.max(0, dt or 0)
    if self.finishRequest and self.loopElapsed >= self:_minimumLoopDuration() then
        self:_beginFinish(self.token)
    end
end

function TakeoverAnimation:abort()
    self.token = self.token + 1
    self.phase = TakeoverAnimation.Phase.IDLE
    self.loopElapsed = 0
    self.finishRequest = nil
end

function TakeoverAnimation:isActive()
    return self.phase ~= TakeoverAnimation.Phase.IDLE
end

function TakeoverAnimation:getPhase()
    return self.phase
end

return TakeoverAnimation
