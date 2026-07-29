local Config = require("green_assistant.GreenAssistConfig")
local AnimationSource = require("green_assistant.GreenAssistAnimationSource")
local RuntimeManifest = require("green_assistant.GreenAssistRuntimeManifest")
local CompanionController = require("green_assistant.CompanionController")
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

local COMPANION_BEHAVIORS = {
    IDLE = true,
    WALK = true,
    ROAM = true,
    DRAG = true,
}

local function CompanionBehavior(state)
    if state == CompanionController.State.WALK then return BehaviorState.WALK end
    if state == CompanionController.State.DRAG then return BehaviorState.DRAG end
    return BehaviorState.IDLE
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
    local customAnimations = options.animations ~= nil
        or type(options.config) == "table" and options.config.animations ~= nil
    local useDefaultManifest = not customAnimations and options.animationManifest ~= false
    local manifest = options.animationManifest
    if useDefaultManifest then
        local errorMessage
        manifest, errorMessage = RuntimeManifest.Load(self.config.assets.manifest)
        if not manifest then print("[GreenAssistant] " .. tostring(errorMessage)) end
    end
    if self.config.assets.enabled and manifest then
        local applied, errorMessage = AnimationSource.Apply(self.config, manifest, self.config.assets.variant)
        if not applied then print("[GreenAssistant] runtime animation manifest ignored: " .. tostring(errorMessage)) end
    end
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
    self.companion = CompanionController.New({
        config = self.config.companion,
        random = options.random,
        onEvent = function(eventName, ...)
            self:_onCompanionEvent(eventName, ...)
        end,
    })
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

function GreenAssistant:_scheduleBlink()
    local blink = self.config.blink
    self.blinkTimer = RandomRange(blink.minInterval, blink.maxInterval)
end

function GreenAssistant:_playBehaviorAnimation(behavior, restart)
    local requested = self.animationState:getBehaviorAnimation(behavior) or self.config.fallbackAnimation
    local options = {
        restart = restart == true,
        fallbackAnimation = self.config.fallbackAnimation,
    }
    if behavior == BehaviorState.DRAG and not self.animator:hasAnimation(requested) then options.playbackSpeed = 0 end
    if requested then self.animator:play(requested, options) end
end

function GreenAssistant:_onBehaviorChanged(current, previous, reason)
    if self.companion and not COMPANION_BEHAVIORS[current] then
        self._ignoreCompanionState = true
        self.companion:interrupt("behavior-" .. string.lower(current))
        self._ignoreCompanionState = false
        self:_syncCompanionView()
    elseif self.companion and current == BehaviorState.IDLE
        and self.companion:getState() ~= CompanionController.State.IDLE then
        self._ignoreCompanionState = true
        self.companion:interrupt("behavior-idle")
        self._ignoreCompanionState = false
        self:_syncCompanionView()
    end
    if current ~= BehaviorState.IDLE then self.blinkActive = false end
    self:_playBehaviorAnimation(current, true)
    if current == BehaviorState.IDLE then
        self:_scheduleBlink()
    end
    self:_emit("onBehaviorChanged", current, previous, reason)
end

function GreenAssistant:_syncCompanionView()
    if not self.companion then return end
    local snapshot = self.companion:getSnapshot()
    self.position.x, self.position.y = snapshot.x, snapshot.y
    self.target = snapshot.targetX and { x = snapshot.targetX, y = self.companion.zone.baselineY } or nil
    self.moving = snapshot.state == CompanionController.State.WALK
    self.positionInitialized = self.companion.initialized
    self.view:setPosition(snapshot.x, snapshot.y)
    if self.view.setFacing then
        self.view:setFacing(snapshot.facing)
    else
        self.view:setFacingRight(snapshot.facing == CompanionController.Facing.RIGHT)
    end
end

function GreenAssistant:_onCompanionEvent(eventName, ...)
    if eventName == "stateChanged" then
        local state, _, reason = ...
        if not self._ignoreCompanionState then
            self.behaviorState:set(CompanionBehavior(state), "companion-" .. tostring(reason or state))
        end
    elseif eventName == "moveStarted" then
        self:_emit("onMoveStarted", ...)
    elseif eventName == "moveFinished" then
        self:_emit("onMoveFinished", ...)
    elseif eventName == "dragStarted" then
        self:_emit("onDragStarted", ...)
    elseif eventName == "dragReleased" then
        self:_emit("onDragReleased", ...)
    elseif eventName == "dragFinished" then
        self:_emit("onDragFinished", ...)
    end
    self:_syncCompanionView()
end

function GreenAssistant:setZone(zone)
    local changed = self.companion:setZone(zone)
    self:_syncCompanionView()
    return changed
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
    local zone = frame and frame.companionZone or nil
    if not zone and self.view.getCompanionZone then zone = self.view:getCompanionZone() end
    if zone then self:setZone(zone) end
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

    if COMPANION_BEHAVIORS[behavior] then
        self.companion:update(dt, self.config.features.roam and self.config.roam.enabled)
        self:_syncCompanionView()
        behavior = self.behaviorState:get()
    end
    if behavior == BehaviorState.IDLE then
        self:_updateBlink(dt)
    end
end

function GreenAssistant:render()
    local debugInfo = self.config.debug.enabled and self:getDebugInfo() or nil
    self.view:render(self.animator:getCurrentFrameData(), debugInfo)
end

function GreenAssistant:handlePointer(x, y, pointer)
    if not self.enabled or not self.visible or not pointer then return false end
    pointer.x, pointer.y = x, y
    local behavior = self.behaviorState:get()
    if behavior == BehaviorState.OFFER then
        local _, choice = self.view:hitTestChoice(x, y)
        if pointer.pressed == true and choice then
            if choice.id == "accept" then self:acceptTakeover() else self:declineTakeover() end
            return true
        end
        if (pointer.pressed or pointer.down or pointer.released)
            and (self.view:hitTestBubble(x, y) or self.view:hitTestCharacter(x, y)) then return true end
        return false
    end

    local hitCharacter = self.view:hitTestCharacter(x, y)
    if behavior == BehaviorState.TAKEOVER or behavior == BehaviorState.SUCCESS or behavior == BehaviorState.DISABLED then
        return hitCharacter and (pointer.pressed or pointer.down or pointer.released) or false
    end

    if COMPANION_BEHAVIORS[behavior] then
        local consumed, result = self.companion:handlePointer(pointer, hitCharacter)
        self:_syncCompanionView()
        if consumed then
            if result and result.kind == "tap" and self.config.features.interaction then self:poke() end
            return true
        end
    elseif hitCharacter and (pointer.pressed or pointer.down or pointer.released) then
        return true
    end
    return (pointer.pressed or pointer.down or pointer.released) and self.view:hitTestBubble(x, y) or false
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
    self._ignoreCompanionState = true
    self.companion:interrupt("level-changed")
    self._ignoreCompanionState = false
    self:_syncCompanionView()
    self:_hideMessage()
    if self.enabled then self:setBehavior(BehaviorState.IDLE, "level-changed") end
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
    local normalized = type(state) == "string" and string.upper(state) or state
    if normalized == BehaviorState.WALK or normalized == BehaviorState.ROAM then
        if not self.companion.initialized and self.view.getCompanionZone then self:setZone(self.view:getCompanionZone()) end
        return self.companion:startWalk()
    end
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
    if not self.companion.initialized and self.view.getCompanionZone then self:setZone(self.view:getCompanionZone()) end
    return self.companion:moveTo(x)
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
    local companion = self.companion:getSnapshot()
    local target = self.target and string.format("%.0f, %.0f", self.target.x, self.target.y) or "-"
    return {
        "GreenAssistant",
        "Behavior: " .. self:getBehavior(),
        "Animation: " .. tostring(self.animator:getCurrentAnimation()),
        string.format("Frame: %d / %d", frame and frame.index or 0, frame and frame.count or 0),
        string.format("Position: %.0f, %.0f", self.position.x, self.position.y),
        "Target: " .. target,
        string.format("Zone X: %.0f .. %.0f", companion.validMinX, companion.validMaxX),
        "Facing: " .. companion.facing,
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
