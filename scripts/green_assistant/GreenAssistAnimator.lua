---@class GreenAssistAnimator
local Animator = {}
Animator.__index = Animator

local function CopyTable(source)
    local result = {}
    for key, value in pairs(source or {}) do
        if type(value) == "table" then
            local child = {}
            for childKey, childValue in pairs(value) do child[childKey] = childValue end
            result[key] = child
        else
            result[key] = value
        end
    end
    return result
end

local function ValidateAnimation(name, config)
    assert(type(name) == "string" and name ~= "", "animation name is required")
    assert(type(config) == "table", "animation config is required")
    assert(type(config.frames) == "table" and #config.frames > 0, "animation frames are required: " .. name)
    assert(type(config.fps) == "number" and config.fps > 0, "animation fps must be greater than zero: " .. name)
    for index, frame in ipairs(config.frames) do
        local valid = type(frame) == "string" or type(frame) == "table" and type(frame.path) == "string"
        assert(valid, string.format("animation %s frame %d must be a path or frame table", name, index))
    end
end

function Animator.New(options)
    local self = setmetatable({}, Animator)
    self.animations = {}
    self.fallbackAnimation = options and options.fallbackAnimation or nil
    self.currentAnimation = nil
    self.currentConfig = nil
    self.frameIndex = 1
    self.elapsed = 0
    self.playbackSpeed = 1
    self.playing = false
    self.finished = false
    self.playOptions = nil
    self.onAnimationChanged = options and options.onAnimationChanged or nil
    self.onFrameChanged = options and options.onFrameChanged or nil
    return self
end

Animator.new = Animator.New

function Animator:registerAnimation(name, config)
    ValidateAnimation(name, config)
    local normalized = CopyTable(config)
    normalized.frames = {}
    for index, frame in ipairs(config.frames) do
        normalized.frames[index] = type(frame) == "table" and CopyTable(frame) or frame
    end
    normalized.loop = config.loop == true
    normalized.playbackSpeed = config.playbackSpeed or 1
    normalized.anchor = CopyTable(config.anchor or { x = 0.5, y = 1 })
    if type(config.frameOffset) == "number" then
        normalized.frameOffset = { x = 0, y = 0 }
        normalized.frameIndexOffset = math.floor(config.frameOffset)
    else
        normalized.frameOffset = CopyTable(config.frameOffset or { x = 0, y = 0 })
        normalized.frameIndexOffset = math.floor(config.frameIndexOffset or 0)
    end
    normalized.scale = config.scale or 1
    self.animations[name] = normalized
    return self
end

function Animator:removeAnimation(name)
    if not self.animations[name] then return false end
    self.animations[name] = nil
    if self.currentAnimation == name then
        self.currentAnimation = nil
        self.currentConfig = nil
        self.playing = false
        self.finished = false
        if self.fallbackAnimation and self.animations[self.fallbackAnimation] then
            self:play(self.fallbackAnimation, { restart = true })
        end
    end
    return true
end

function Animator:hasAnimation(name)
    return self.animations[name] ~= nil
end

function Animator:setFallbackAnimation(name)
    self.fallbackAnimation = name
end

function Animator:play(name, options)
    options = options or {}
    local requested = name
    if not self.animations[name] then name = options.fallbackAnimation or self.fallbackAnimation end
    if not name or not self.animations[name] then return false, "animation not registered: " .. tostring(requested) end
    if self.currentAnimation == name and self.playing and options.restart ~= true then
        if options.playbackSpeed then self.playbackSpeed = options.playbackSpeed end
        return true
    end

    local previous = self.currentAnimation
    self.currentAnimation = name
    self.currentConfig = self.animations[name]
    self.frameIndex = 1
    self.elapsed = 0
    self.playbackSpeed = options.playbackSpeed or self.currentConfig.playbackSpeed or 1
    self.playing = true
    self.finished = false
    self.playOptions = options
    if self.onAnimationChanged then self.onAnimationChanged(name, previous, requested) end
    if self.onFrameChanged then self.onFrameChanged(self:getCurrentFrameData()) end
    return true
end

local function Finish(self)
    if self.finished then return end
    self.finished = true
    self.playing = false
    local animationCallback = self.currentConfig and self.currentConfig.onFinished or nil
    local playCallback = self.playOptions and self.playOptions.onFinished or nil
    if animationCallback then animationCallback(self.currentAnimation) end
    if playCallback then playCallback(self.currentAnimation) end
end

function Animator:update(dt)
    if not self.playing or not self.currentConfig then return end
    local speed = math.max(0, self.playbackSpeed or 1)
    if speed == 0 then return end
    local frameDuration = 1 / self.currentConfig.fps
    self.elapsed = self.elapsed + math.max(0, dt or 0) * speed
    while self.elapsed >= frameDuration and self.playing do
        self.elapsed = self.elapsed - frameDuration
        if self.frameIndex < #self.currentConfig.frames then
            self.frameIndex = self.frameIndex + 1
            if self.onFrameChanged then self.onFrameChanged(self:getCurrentFrameData()) end
        elseif self.currentConfig.loop then
            self.frameIndex = 1
            if self.onFrameChanged then self.onFrameChanged(self:getCurrentFrameData()) end
        else
            Finish(self)
        end
    end
end

function Animator:getCurrentAnimation()
    return self.currentAnimation
end

function Animator:getCurrentFrame()
    local data = self:getCurrentFrameData()
    return data and data.path or nil
end

function Animator:getCurrentFrameData()
    if not self.currentConfig then return nil end
    local frameCount = #self.currentConfig.frames
    local offset = self.currentConfig.frameIndexOffset or 0
    local sourceIndex = ((self.frameIndex - 1 + offset) % frameCount) + 1
    local source = self.currentConfig.frames[sourceIndex]
    local frame = type(source) == "table" and CopyTable(source) or { path = source }
    local animationOffset = self.currentConfig.frameOffset or {}
    frame.offsetX = (animationOffset.x or animationOffset[1] or 0) + (frame.offsetX or 0)
    frame.offsetY = (animationOffset.y or animationOffset[2] or 0) + (frame.offsetY or 0)
    frame.anchorX = frame.anchorX or self.currentConfig.anchor.x or self.currentConfig.anchor[1] or 0.5
    frame.anchorY = frame.anchorY or self.currentConfig.anchor.y or self.currentConfig.anchor[2] or 1
    frame.scale = (frame.scale or 1) * (self.currentConfig.scale or 1)
    frame.index = self.frameIndex
    frame.sourceIndex = sourceIndex
    frame.count = frameCount
    frame.animation = self.currentAnimation
    return frame
end

function Animator:isPlaying()
    return self.playing
end

function Animator:isFinished()
    return self.finished
end

return Animator
