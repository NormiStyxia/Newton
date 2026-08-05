local FixedStepClock = {}
FixedStepClock.__index = FixedStepClock

function FixedStepClock.New(options)
    options = options or {}
    local self = setmetatable({}, FixedStepClock)
    self.step = options.step or (1 / 60)
    self.maxFrameDelta = options.maxFrameDelta or 0.25
    self.accumulator = 0
    self.scene = nil
    self.previousUpdateEnabled = true
    self.active = false
    return self
end

FixedStepClock.new = FixedStepClock.New

function FixedStepClock:start(scene)
    assert(scene, "AssistDemo fixed-step clock requires a scene")
    if self.active and self.scene == scene then return end
    if self.active then self:stop() end
    self.scene = scene
    self.previousUpdateEnabled = type(scene.IsUpdateEnabled) == "function"
        and scene:IsUpdateEnabled() or true
    self.accumulator = 0
    self.active = true
    scene:SetUpdateEnabled(false)
end

function FixedStepClock:stop()
    local scene = self.scene
    self.active = false
    self.accumulator = 0
    self.scene = nil
    if scene then scene:SetUpdateEnabled(self.previousUpdateEnabled) end
    self.previousUpdateEnabled = true
end

function FixedStepClock:isActive()
    return self.active
end

function FixedStepClock:advance(dt, canStep)
    if not self.active or not self.scene then return 0 end
    local scene = self.scene
    scene:SetUpdateEnabled(false)
    if canStep and not canStep() then
        self.accumulator = 0
        return 0
    end

    self.accumulator = self.accumulator
        + math.min(self.maxFrameDelta, math.max(0, dt or 0))
    local steps = 0
    while self.accumulator + 0.0000001 >= self.step do
        if not self.active or self.scene ~= scene or canStep and not canStep() then
            self.accumulator = 0
            break
        end
        self.accumulator = self.accumulator - self.step
        scene:SetUpdateEnabled(true)
        local ok, errorMessage = pcall(scene.Update, scene, self.step)
        if self.active and self.scene == scene then scene:SetUpdateEnabled(false) end
        if not ok then error(errorMessage, 0) end
        steps = steps + 1
    end
    if self.active and self.scene == scene then scene:SetUpdateEnabled(false) end
    return steps
end

return FixedStepClock
