local Config = require("green_assistant.GreenAssistConfig")
local Animator = require("green_assistant.GreenAssistAnimator")
local AnimationState = require("green_assistant.GreenAssistAnimationState")
local BehaviorState = require("green_assistant.GreenAssistBehaviorState")
local Interaction = require("green_assistant.GreenAssistInteraction")
local FailureAssist = require("green_assistant.GreenAssistFailureAssist")
local Takeover = require("green_assistant.GreenAssistTakeover")
local Adapter = require("green_assistant.GreenAssistAdapter")
local View = require("green_assistant.GreenAssistView")

---@class GreenAssistant
local GreenAssistant = {}
GreenAssistant.__index = GreenAssistant

GreenAssistant.Behavior = BehaviorState
GreenAssistant.Animation = AnimationState

local function RandomRange(minimum, maximum)
    if maximum <= minimum then return minimum end
    return minimum + math.random() * (maximum - minimum)
end

local function CopyOptions(options)
    local config = {}
    for key, value in pairs(options.config or {}) do config[key] = value end
    if options.features then config.features = options.features end
    if options.animations then config.animations = options.animations end
    if options.behaviorAnimationMap then config.behaviorAnimationMap = options.behaviorAnimationMap end
    if options.debug ~= nil then config.debug = type(options.debug) == "table" and options.debug or { enabled = options.debug == true } end
    return config
end

function GreenAssistant.New(options)
    options = options or {}
    local self = setmetatable({}, GreenAssistant)
    self.config = Config.Resolve(CopyOptions(options))
    self.adapter = options.adapter or Adapter.New()
    self.listeners = {}
    self.elapsed = 0
    self.levelId = nil
    self.enabled = options.enabled ~= false
    self.visible = options.visible ~= false
    self.positionInitialized = false
    self.position = { x = 0, y = 0 }
    self.target = nil
    self.moving = false
    self.behaviorTimer = nil
    self.timedBehavior = nil
    self.idleTimer = 0
    self.blinkTimer = 0
    self.blinkActive = false
    self.blinkJustFinished = false

    for name, callback in pairs(options.events or {}) do self:on(name, callback) end

    self.animator = Animator.New({
        fallbackAnimation = self.config.fallbackAnimation,
        onAnimationChanged = function(current, previous, requested)
            self:_emit("onAnimationChanged", current, previous, requested)
        end,
    })
    for name, animation in pairs(self.config.animations) do self.animator:registerAnimation(name, animation) end

    self.animationState = AnimationState.New(self.config.behaviorAnimationMap, self.config.fallbackAnimation)
    self.behaviorState = BehaviorState.New(self.enabled and BehaviorState.IDLE or BehaviorState.DISABLED)
    self.behaviorState:setOnChanged(function(current, previous, reason)
        self:_onBehaviorChanged(current, previous, reason)
    end)
    self.view = options.view or View.New({ renderer = options.renderer, config = self.config })
    if self.view.preloadAnimations then self.view:preloadAnimations(self.config.animations) end
    self.view:setEnabled(self.enabled)
    self.view:setVisible(self.visible)
    self.interaction = Interaction.New(self.config.interaction)
    self.failureAssist = FailureAssist.New({ failureThreshold = self.config.failureThreshold })
    self.takeover = Takeover.New(self.adapter, {
        onStarted = function(replayData)
            self:_emit("onTakeoverStarted", replayData)
        end,
        onFinished = function(replayData)
            self:_emit("onTakeoverFinished", replayData)
            self:setBehavior(BehaviorState.SUCCESS, "takeover-finished")
            self:_showTimedMessage(self.config.failureAssist.successText, 1.8, BehaviorState.SUCCESS)
        end,
        onError = function(errorMessage)
            print("[GreenAssistant] takeover failed: " .. tostring(errorMessage))
            self:setBehavior(BehaviorState.IDLE, "takeover-error")
            self:_showTimedMessage(self.config.failureAssist.unavailableText, 2.2, BehaviorState.DIALOGUE)
        end,
    })
    self:_scheduleIdle()
    self:_scheduleBlink()
    self:_playBehaviorAnimation(self.behaviorState:get(), true)
    return self
end

GreenAssistant.new = GreenAssistant.New

function GreenAssistant:on(eventName, callback)
    assert(type(eventName) == "string" and eventName ~= "", "event name is required")
    assert(type(callback) == "function", "event callback must be a function")
    local listeners = self.listeners[eventName] or {}
    listeners[#listeners + 1] = callback
    self.listeners[eventName] = listeners
    return callback
end

function GreenAssistant:off(eventName, callback)
    local listeners = self.listeners[eventName]
    if not listeners then return false end
    for index = #listeners, 1, -1 do
        if listeners[index] == callback then table.remove(listeners, index); return true end
    end
    return false
end

function GreenAssistant:_emit(eventName, ...)
    for _, callback in ipairs(self.listeners[eventName] or {}) do callback(self, ...) end
end

function GreenAssistant:_scheduleIdle()
    local roam = self.config.roam
    self.idleTimer = RandomRange(roam.minIdleTime, roam.maxIdleTime)
end

function GreenAssistant:_scheduleBlink()
    local blink = self.config.blink
    self.blinkTimer = RandomRange(blink.minInterval, blink.maxInterval)
end

function GreenAssistant:_playBehaviorAnimation(behavior, restart)
    local animation = self.animationState:resolve(behavior, function(name) return self.animator:hasAnimation(name) end)
    if animation then self.animator:play(animation, { restart = restart == true }) end
end

function GreenAssistant:_onBehaviorChanged(current, previous, reason)
    if previous == BehaviorState.ROAM and current ~= BehaviorState.ROAM and self.moving then
        self.moving = false
        self.target = nil
        self:_emit("onMoveFinished", self.position.x, self.position.y, true)
    end
    if current ~= BehaviorState.IDLE then self.blinkActive = false end
    self:_playBehaviorAnimation(current, true)
    if current == BehaviorState.IDLE then
        self:_scheduleIdle()
        self:_scheduleBlink()
    end
    self:_emit("onBehaviorChanged", current, previous, reason)
end

function GreenAssistant:_ensurePosition()
    if self.positionInitialized then return end
    local x, y = self.view:getHomePosition()
    self.position.x, self.position.y = x, y
    self.positionInitialized = true
    self.view:setPosition(x, y)
end

function GreenAssistant:_clampPosition()
    local xMin, xMax, yMin, yMax = self.view:getRoamBounds()
    self.position.x = math.max(xMin, math.min(xMax, self.position.x))
    self.position.y = math.max(yMin, math.min(yMax, self.position.y))
    self.view:setPosition(self.position.x, self.position.y)
end

function GreenAssistant:_tryRoam()
    if not self.config.features.roam or not self.config.roam.enabled then return false end
    local xMin, xMax, yMin, yMax = self.view:getRoamBounds()
    local angle = math.random() * math.pi * 2
    local distance = RandomRange(self.config.roam.maxDistance * 0.35, self.config.roam.maxDistance)
    local targetX = math.max(xMin, math.min(xMax, self.position.x + math.cos(angle) * distance))
    local targetY = math.max(yMin, math.min(yMax, self.position.y + math.sin(angle) * distance * 0.35))
    if math.abs(targetX - self.position.x) < 4 and math.abs(targetY - self.position.y) < 2 then
        self:_scheduleIdle()
        return false
    end
    return self:moveTo(targetX, targetY)
end

function GreenAssistant:_updateRoam(dt)
    if not self.target then self:setBehavior(BehaviorState.IDLE, "missing-target"); return end
    local dx, dy = self.target.x - self.position.x, self.target.y - self.position.y
    local distance = math.sqrt(dx * dx + dy * dy)
    if distance <= self.config.roam.arrivalDistance then
        self.position.x, self.position.y = self.target.x, self.target.y
        self.view:setPosition(self.position.x, self.position.y)
        self.target = nil
        self.moving = false
        self:_emit("onMoveFinished", self.position.x, self.position.y, false)
        self:setBehavior(BehaviorState.IDLE, "arrived")
        return
    end
    local step = math.min(distance, self.config.roam.moveSpeed * dt)
    self.position.x = self.position.x + dx / distance * step
    self.position.y = self.position.y + dy / distance * step
    if math.abs(dx) > 0.01 then self.view:setFacingRight(dx > 0) end
    self.view:setPosition(self.position.x, self.position.y)
end

function GreenAssistant:_updateBlink(dt)
    local config = self.config.blink
    if self.blinkJustFinished then self.blinkJustFinished = false; return end
    if not config.enabled or self.blinkActive or self.behaviorState:get() ~= BehaviorState.IDLE then return end
    if not self.animator:hasAnimation(config.animation) then return end
    self.blinkTimer = self.blinkTimer - dt
    if self.blinkTimer > 0 then return end
    self.blinkActive = true
    self.animator:play(config.animation, {
        restart = true,
        onFinished = function()
            self.blinkActive = false
            self.blinkJustFinished = true
            self:_scheduleBlink()
            if self.behaviorState:get() == BehaviorState.IDLE then self:_playBehaviorAnimation(BehaviorState.IDLE, true) end
        end,
    })
end

function GreenAssistant:_showTimedMessage(text, duration, behavior)
    if not self.config.features.dialogue then return end
    self.view:showMessage(text)
    self.behaviorTimer = math.max(0, duration or 1.8)
    self.timedBehavior = behavior or BehaviorState.DIALOGUE
    self:setBehavior(self.timedBehavior, "message")
    self:_emit("onDialogueOpened", text)
end

function GreenAssistant:_hideMessage()
    if self.view.message ~= nil then
        self.view:hideMessage()
        self:_emit("onDialogueClosed")
    end
    self.behaviorTimer = nil
    self.timedBehavior = nil
end

function GreenAssistant:update(dt, frame)
    dt = math.max(0, dt or 0)
    self.elapsed = self.elapsed + dt
    if frame then self.view:setFrame(frame) end
    self:_ensurePosition()
    self:_clampPosition()
    if not self.enabled then return end

    self.behaviorState:update(dt)
    self.animator:update(dt)
    local behavior = self.behaviorState:get()
    if behavior == BehaviorState.TAKEOVER then
        self.takeover:update(dt)
        return
    end

    if self.behaviorTimer and self.timedBehavior == behavior then
        self.behaviorTimer = self.behaviorTimer - dt
        if self.behaviorTimer <= 0 then
            self:_hideMessage()
            self:setBehavior(BehaviorState.IDLE, "timer-finished")
            behavior = self.behaviorState:get()
        end
    end

    if behavior == BehaviorState.ROAM then
        self:_updateRoam(dt)
    elseif behavior == BehaviorState.IDLE then
        self:_updateBlink(dt)
        self.idleTimer = self.idleTimer - dt
        if self.idleTimer <= 0 then self:_tryRoam() end
    end
end

function GreenAssistant:render()
    local debugInfo = self.config.debug.enabled and self:getDebugInfo() or nil
    self.view:render(self.animator:getCurrentFrameData(), debugInfo)
end

function GreenAssistant:handlePointer(x, y, pointer)
    if not self.enabled or not self.visible or not pointer or pointer.pressed ~= true then return false end
    local behavior = self.behaviorState:get()
    if behavior == BehaviorState.OFFER then
        local _, choice = self.view:hitTestChoice(x, y)
        if choice then
            if choice.id == "accept" then self:acceptTakeover() else self:declineTakeover() end
            return true
        end
        if self.view:hitTestBubble(x, y) or self.view:hitTestCharacter(x, y) then return true end
    end
    if self.view:hitTestCharacter(x, y) then
        if behavior == BehaviorState.TAKEOVER or behavior == BehaviorState.SUCCESS or behavior == BehaviorState.DISABLED then
            return true
        end
        if self.config.features.interaction then self:poke() end
        return true
    end
    return self.view:hitTestBubble(x, y)
end

function GreenAssistant:poke()
    if not self.enabled or not self.config.features.interaction then return false end
    local behavior = self.behaviorState:get()
    if behavior == BehaviorState.OFFER or behavior == BehaviorState.TAKEOVER or behavior == BehaviorState.SUCCESS then return false end
    local line, pokeCount = self.interaction:poke(self.elapsed)
    self:_showTimedMessage(line, self.config.interaction.duration, BehaviorState.INTERACT)
    self:_emit("onPoked", pokeCount, line)
    return true
end

function GreenAssistant:onAttemptFailed(payload)
    if not self.enabled or not self.config.features.failureAssist then return false end
    local behavior = self.behaviorState:get()
    if behavior == BehaviorState.OFFER or behavior == BehaviorState.TAKEOVER or behavior == BehaviorState.DISABLED then return false end
    local result = self.failureAssist:onAttemptFailed(payload or {})
    if result.kind == "offer" and self.config.features.takeover and self.takeover:canStart(self.levelId) then
        self.failureAssist:markOffered()
        self:_hideMessage()
        self:setBehavior(BehaviorState.OFFER, "failure-threshold")
        self.view:showChoice(self.config.failureAssist.offerText, {
            { id = "decline", label = self.config.failureAssist.declineText },
            { id = "accept", label = self.config.failureAssist.acceptText },
        })
        self:_emit("onDialogueOpened", self.config.failureAssist.offerText)
        self:_emit("onTakeoverOffered", result)
        return true
    end

    local lines = self.config.failureAssist.observeLines
    local line = lines[math.min(#lines, math.max(1, result.failureCount))] or "我看到了。"
    self:_showTimedMessage(line, self.config.failureAssist.observeDuration, BehaviorState.OBSERVE)
    return true
end

function GreenAssistant:onAttemptSucceeded()
    self.failureAssist:onAttemptSucceeded()
    if not self.enabled or self.takeover:isActive() then return end
    self:_showTimedMessage(self.config.failureAssist.successText, 1.8, BehaviorState.SUCCESS)
end

function GreenAssistant:onLevelChanged(levelId)
    if self.takeover:isActive() then self.takeover:cancel() end
    self.levelId = levelId
    self.failureAssist:onLevelChanged()
    self.interaction:reset()
    self.target = nil
    self.moving = false
    self:_hideMessage()
    if self.enabled then self:setBehavior(BehaviorState.IDLE, "level-changed") end
    self.positionInitialized = false
end

function GreenAssistant:acceptTakeover()
    if self.behaviorState:get() ~= BehaviorState.OFFER then return false end
    self:_emit("onTakeoverAccepted", self.levelId)
    self:_hideMessage()
    self:setBehavior(BehaviorState.TAKEOVER, "accepted")
    local started, errorMessage = self.takeover:start(self.levelId)
    if not started then
        print("[GreenAssistant] takeover unavailable: " .. tostring(errorMessage))
        self:_showTimedMessage(self.config.failureAssist.unavailableText, 2.2, BehaviorState.DIALOGUE)
        return false
    end
    return true
end

function GreenAssistant:declineTakeover()
    if self.behaviorState:get() ~= BehaviorState.OFFER then return false end
    self:_emit("onTakeoverDeclined", self.levelId)
    self:_hideMessage()
    self:setBehavior(BehaviorState.IDLE, "declined")
    return true
end

function GreenAssistant:registerAnimation(name, config)
    self.animator:registerAnimation(name, config)
    if self.view.preloadAnimation then self.view:preloadAnimation(config) end
    return self
end

function GreenAssistant:removeAnimation(name)
    return self.animator:removeAnimation(name)
end

function GreenAssistant:setBehaviorAnimation(behavior, animation)
    self.animationState:setBehaviorAnimation(behavior, animation)
    if string.upper(behavior) == self.behaviorState:get() then self:_playBehaviorAnimation(self.behaviorState:get(), true) end
    return self
end

function GreenAssistant:hasAnimation(name)
    return self.animator:hasAnimation(name)
end

function GreenAssistant:setBehavior(state, reason)
    return self.behaviorState:set(state, reason)
end

function GreenAssistant:getBehavior()
    return self.behaviorState:get()
end

function GreenAssistant:playAnimation(name, options)
    return self.animator:play(name, options)
end

function GreenAssistant:say(text, duration)
    self:_showTimedMessage(text, duration or 2, BehaviorState.DIALOGUE)
end

function GreenAssistant:moveTo(x, y)
    if not self.enabled then return false end
    self.target = { x = x, y = y }
    self.moving = true
    self:setBehavior(BehaviorState.ROAM, "move-to")
    self:_emit("onMoveStarted", self.position.x, self.position.y, x, y)
    return true
end

function GreenAssistant:setEnabled(enabled)
    enabled = enabled == true
    if self.enabled == enabled then return end
    self.enabled = enabled
    self.view:setEnabled(enabled)
    if enabled then self:setBehavior(BehaviorState.IDLE, "enabled")
    else
        if self.takeover:isActive() then self.takeover:cancel() end
        self:_hideMessage()
        self:setBehavior(BehaviorState.DISABLED, "disabled")
    end
end

function GreenAssistant:setVisible(visible)
    self.visible = visible == true
    self.view:setVisible(self.visible)
end

function GreenAssistant:getDebugInfo()
    local frame = self.animator:getCurrentFrameData()
    local target = self.target and string.format("%.0f, %.0f", self.target.x, self.target.y) or "-"
    return {
        "GreenAssistant",
        "Behavior: " .. self:getBehavior(),
        "Animation: " .. tostring(self.animator:getCurrentAnimation()),
        string.format("Frame: %d / %d", frame and frame.index or 0, frame and frame.count or 0),
        string.format("Position: %.0f, %.0f", self.position.x, self.position.y),
        "Target: " .. target,
        string.format("Failures: %d / %d", self.failureAssist.failureCount, self.failureAssist.threshold),
        "Offer: " .. tostring(self.failureAssist.hasOfferedThisLevel),
        "Takeover: " .. tostring(self.takeover:isActive()),
    }
end

function GreenAssistant:destroy()
    if self.takeover:isActive() then self.takeover:cancel() end
    self.view:destroy()
    self.listeners = {}
end

return GreenAssistant
