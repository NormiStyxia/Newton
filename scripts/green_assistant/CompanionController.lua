local CompanionConfig = require("green_assistant.CompanionConfig")

---@class CompanionController
local Controller = {}
Controller.__index = Controller

Controller.State = {
    IDLE = "IDLE",
    WALK = "WALK",
    DRAGGING = "DRAGGING",
}
-- Backwards-compatible symbolic alias.  Runtime state is always DRAGGING.
Controller.State.DRAG = Controller.State.DRAGGING

Controller.Facing = {
    LEFT = "LEFT",
    RIGHT = "RIGHT",
}

local ANIMATION_BY_STATE = {
    IDLE = "idle_base",
    WALK = "walk",
    DRAGGING = "drag",
}

local function Clamp(value, minimum, maximum)
    if maximum < minimum then return minimum end
    return math.max(minimum, math.min(maximum, value))
end

local function RandomRange(random, minimum, maximum)
    if maximum <= minimum then return minimum end
    return minimum + random() * (maximum - minimum)
end

local function CopyZone(zone)
    return {
        left = zone.left,
        right = zone.right,
        top = zone.top,
        bottom = zone.bottom,
        baselineY = zone.baselineY,
        walkingAllowed = zone.walkingAllowed ~= false,
        fallbackX = zone.fallbackX,
    }
end

function Controller.New(options)
    local self = setmetatable({}, Controller)
    self:Init(options or {})
    return self
end

Controller.new = Controller.New

function Controller:Init(options)
    self.config = CompanionConfig.Resolve(options.config)
    self.random = options.random or math.random
    self.onEvent = options.onEvent
    self.state = Controller.State.IDLE
    self.facing = options.facing == Controller.Facing.LEFT and Controller.Facing.LEFT or Controller.Facing.RIGHT
    self.x, self.y = 0, 0
    self.velocityX, self.velocityY = 0, 0
    self.targetX = nil
    self.zone = nil
    self.validMinX, self.validMaxX = 0, 0
    self.initialized = false
    self.walkingAllowed = false
    self.idleRemaining = 0
    self.pointerCandidate = nil
    self.settle = nil
    self:_scheduleIdle()
end

function Controller:_emit(name, ...)
    if self.onEvent then self.onEvent(name, ...) end
end

function Controller:_setState(state, reason)
    if state == self.state then return false end
    local previous = self.state
    self.state = state
    self:_emit("stateChanged", state, previous, reason)
    return true
end

function Controller:_scheduleIdle()
    self.idleRemaining = RandomRange(self.random, self.config.idleMinDuration, self.config.idleMaxDuration)
end

function Controller:_enterIdle(reason)
    self.targetX = nil
    self.velocityX, self.velocityY = 0, 0
    self:_setState(Controller.State.IDLE, reason)
    self:_scheduleIdle()
end

function Controller:_finishWalk(interrupted, reason)
    local targetX = self.targetX
    self.targetX = nil
    self.velocityX, self.velocityY = 0, 0
    self:_setState(Controller.State.IDLE, reason or (interrupted and "walk-interrupted" or "walk-finished"))
    self:_scheduleIdle()
    self:_emit("moveFinished", self.x, self.y, interrupted == true, targetX)
end

function Controller:_chooseDirection()
    local leftDistance = math.max(0, self.x - self.validMinX)
    local rightDistance = math.max(0, self.validMaxX - self.x)
    local minimum = self.config.minWalkDistance
    local canLeft = leftDistance >= minimum
    local canRight = rightDistance >= minimum
    if not canLeft and not canRight then return nil, 0 end
    if canLeft and canRight then
        local total = leftDistance + rightDistance
        if self.random() * total < leftDistance then return -1, leftDistance end
        return 1, rightDistance
    end
    if canLeft then return -1, leftDistance end
    return 1, rightDistance
end

function Controller:_chooseTarget()
    if not self.walkingAllowed then return nil end
    local direction, available = self:_chooseDirection()
    if not direction then return nil end
    local minimum = self.config.minWalkDistance
    local roll = self.random()
    local maximum
    if roll < self.config.shortWalkChance then
        maximum = math.min(available, math.max(minimum, self.config.maxWalkDistance * 0.45))
    elseif roll < 1 - self.config.longWalkChance then
        maximum = math.min(available, math.max(minimum, self.config.maxWalkDistance))
    else
        maximum = available
    end
    local distance = RandomRange(self.random, minimum, maximum)
    return Clamp(self.x + direction * distance, self.validMinX, self.validMaxX)
end

function Controller:_beginWalk(targetX, reason)
    if not self.walkingAllowed or self.state == Controller.State.DRAGGING or self.pointerCandidate then
        return false
    end
    targetX = targetX or self:_chooseTarget()
    if not targetX or math.abs(targetX - self.x) < self.config.minWalkDistance then
        self:_enterIdle("walk-target-unavailable")
        return false
    end
    self.targetX = Clamp(targetX, self.validMinX, self.validMaxX)
    self.facing = self.targetX > self.x and Controller.Facing.RIGHT or Controller.Facing.LEFT
    self.velocityX = self.facing == Controller.Facing.RIGHT and self.config.moveSpeed or -self.config.moveSpeed
    self.velocityY = 0
    self:_setState(Controller.State.WALK, reason or "walk-started")
    self:_emit("moveStarted", self.x, self.y, self.targetX, self.zone.baselineY, self.facing)
    return true
end

function Controller:setZone(zone)
    if type(zone) ~= "table" then return false end
    assert(type(zone.left) == "number" and type(zone.right) == "number", "CompanionZone left/right are required")
    assert(type(zone.top) == "number" and type(zone.bottom) == "number", "CompanionZone top/bottom are required")
    assert(type(zone.baselineY) == "number", "CompanionZone baselineY is required")

    self.zone = CopyZone(zone)
    local inset = self.config.characterHalfWidth + self.config.edgePadding
    self.validMinX = zone.left + inset
    self.validMaxX = zone.right - inset
    self.walkingAllowed = zone.walkingAllowed ~= false
        and self.validMaxX - self.validMinX >= self.config.minWalkDistance

    if self.validMaxX < self.validMinX then
        local fallback = zone.fallbackX or self.validMinX
        self.validMinX, self.validMaxX = fallback, fallback
        self.walkingAllowed = false
    end

    if not self.initialized then
        self.x = Clamp(zone.fallbackX or self.validMinX, self.validMinX, self.validMaxX)
        self.y = zone.baselineY
        self.initialized = true
        self:_emit("positionChanged", self.x, self.y, "initialized")
        return true
    end

    -- Layout owns the legal zone, but an active drag owns the transform.  The
    -- current pointer sample below will apply these new bounds without a
    -- second position writer fighting the drag.
    if self.state == Controller.State.DRAGGING then return true end

    local previousX, previousY = self.x, self.y
    self.x = Clamp(self.x, self.validMinX, self.validMaxX)
    if not self.settle then
        self.y = zone.baselineY
    end
    if self.x ~= previousX or self.y ~= previousY then
        self:_emit("positionChanged", self.x, self.y, "zone-clamped")
    end

    if self.state == Controller.State.WALK and not self.walkingAllowed then
        self:_finishWalk(true, "zone-too-small")
    elseif self.targetX then
        local targetInvalid = self.targetX < self.validMinX or self.targetX > self.validMaxX
        self.targetX = Clamp(self.targetX, self.validMinX, self.validMaxX)
        if targetInvalid and self.state == Controller.State.WALK then
            local replacement = self:_chooseTarget()
            if replacement then
                self.targetX = replacement
                self.facing = replacement > self.x and Controller.Facing.RIGHT or Controller.Facing.LEFT
                self.velocityX = self.facing == Controller.Facing.RIGHT and self.config.moveSpeed or -self.config.moveSpeed
                self.velocityY = 0
                self:_emit("moveRetargeted", replacement, self.facing)
            else
                self:_finishWalk(true, "zone-too-small")
            end
        end
    elseif self.state == Controller.State.WALK then
        self:_enterIdle("missing-walk-target")
    end
    return true
end

function Controller:moveTo(x)
    if not self.initialized or type(x) ~= "number" then return false end
    return self:_beginWalk(Clamp(x, self.validMinX, self.validMaxX), "move-to")
end

function Controller:startWalk()
    if not self.initialized then return false end
    return self:_beginWalk(nil, "walk-requested")
end

function Controller:interrupt(reason)
    self.pointerCandidate = nil
    self.settle = nil
    if self.state == Controller.State.WALK then
        self:_finishWalk(true, reason or "interrupted")
    else
        self:_enterIdle(reason or "interrupted")
    end
end

function Controller:_beginDragging(pointerX, pointerY)
    if self.state == Controller.State.WALK then
        local oldTarget = self.targetX
        self.targetX = nil
        self:_emit("moveFinished", self.x, self.y, true, oldTarget)
    end
    self.targetX = nil
    self.velocityX, self.velocityY = 0, 0
    self.settle = nil
    self:_setState(Controller.State.DRAGGING, "drag-started")
    self:_emit("dragStarted", self.x, self.y, self.facing)
    self:_updateDragging(pointerX, pointerY)
end

function Controller:_trackPointerCandidate(pointerX, pointerY)
    local candidate = self.pointerCandidate
    if not candidate then return end
    candidate.currentX = pointerX
    candidate.currentY = pointerY
    local dx, dy = pointerX - candidate.startX, pointerY - candidate.startY
    if dx * dx + dy * dy >= self.config.dragThreshold * self.config.dragThreshold then
        candidate.moved = true
    end
end

function Controller:_updateDragging(pointerX, pointerY)
    local candidate = self.pointerCandidate
    if not candidate or not self.zone then return end
    self:_trackPointerCandidate(pointerX, pointerY)
    -- Rigid screen-space drag: the grab offset is captured once on pointerDown
    -- and is never replaced by animation, facing, velocity, or layout data.
    if candidate.usesSemanticGrab then
        -- During the lifted pose the pointer owns the cloth-tip anchor, not
        -- the foot/root.  Constrain that hotspot to CompanionZone and derive
        -- the root from it so a bottom-edge pointer is not pushed off the tip.
        local hotspotX = Clamp(pointerX, self.zone.left, self.zone.right)
        local hotspotY = Clamp(pointerY, self.zone.top, self.zone.bottom)
        self.x = hotspotX + candidate.grabOffsetX
        self.y = hotspotY + candidate.grabOffsetY
    else
        self.x = Clamp(pointerX + candidate.grabOffsetX, self.validMinX, self.validMaxX)
        self.y = Clamp(pointerY + candidate.grabOffsetY, self.zone.top, self.zone.bottom)
    end
    self:_emit("positionChanged", self.x, self.y, "drag")
end

function Controller:_releaseDragging()
    local duration = math.max(0, self.config.settleDuration)
    self.x = Clamp(self.x, self.validMinX, self.validMaxX)
    self:_emit("dragReleased", self.x, self.y, self.zone.baselineY)
    self:_enterIdle("drag-released")
    if duration > 0 and self.y ~= self.zone.baselineY then
        self.settle = { fromY = self.y, elapsed = 0, duration = duration }
    else
        self.y = self.zone.baselineY
        self.settle = nil
        self:_emit("dragFinished", self.x, self.y)
    end
end

function Controller:_captureGrabOffset(pointerX, pointerY)
    local hotspotX = self.config.dragGrabOffsetX
    local hotspotY = self.config.dragGrabOffsetY
    if type(hotspotX) == "number" and type(hotspotY) == "number" then
        local sourceFacing = self.config.dragGrabSourceFacing or Controller.Facing.LEFT
        if self.facing ~= sourceFacing then hotspotX = -hotspotX end
        -- hotspot is measured from the logical foot/root to the lifted-cloth
        -- tip.  The rigid drag equation needs the inverse: root - pointer.
        return -hotspotX, -hotspotY, true
    end
    return self.x - pointerX, self.y - pointerY, false
end

function Controller:handlePointer(pointer, hitCharacter)
    if not pointer or not self.initialized then return false, nil end
    local candidate = self.pointerCandidate
    if not candidate then
        if pointer.pressed ~= true or hitCharacter ~= true then return false, nil end
        if self.state == Controller.State.WALK then
            self:_finishWalk(true, "pointer-pressed")
        end
        local grabOffsetX, grabOffsetY, usesSemanticGrab = self:_captureGrabOffset(pointer.x, pointer.y)
        self.pointerCandidate = {
            startX = pointer.x,
            startY = pointer.y,
            currentX = pointer.x,
            currentY = pointer.y,
            grabOffsetX = grabOffsetX,
            grabOffsetY = grabOffsetY,
            usesSemanticGrab = usesSemanticGrab,
            moved = false,
            holdElapsed = 0,
        }
        return true, { kind = "press-pending" }
    end

    self:_trackPointerCandidate(pointer.x, pointer.y)
    if pointer.released == true or pointer.down == false then
        if self.state == Controller.State.DRAGGING then
            self:_updateDragging(pointer.x, pointer.y)
            self.pointerCandidate = nil
            self:_releaseDragging()
            return true, { kind = "drag-released" }
        end
        local wasTap = candidate.moved ~= true
        self.pointerCandidate = nil
        return true, { kind = wasTap and "tap" or "press-cancelled" }
    end

    if self.state == Controller.State.DRAGGING then
        self:_updateDragging(pointer.x, pointer.y)
        return true, { kind = "dragging" }
    end
    return true, { kind = "press-pending" }
end

function Controller:update(dt, allowAutonomy)
    if not self.initialized then return end
    dt = math.max(0, dt or 0)
    if self.state == Controller.State.DRAGGING then return end
    if self.pointerCandidate then
        local candidate = self.pointerCandidate
        candidate.holdElapsed = candidate.holdElapsed + dt
        if candidate.holdElapsed >= math.max(0, self.config.dragHoldDuration) then
            self:_beginDragging(candidate.currentX, candidate.currentY)
        end
        return
    end

    if self.settle then
        local settle = self.settle
        settle.elapsed = math.min(settle.duration, settle.elapsed + dt)
        local linear = settle.duration > 0 and settle.elapsed / settle.duration or 1
        local eased = 1 - (1 - linear) ^ 3
        self.y = settle.fromY + (self.zone.baselineY - settle.fromY) * eased
        self:_emit("positionChanged", self.x, self.y, "settle")
        if linear >= 1 then
            self.y = self.zone.baselineY
            self.settle = nil
            self:_emit("dragFinished", self.x, self.y)
        end
        return
    end

    if self.state == Controller.State.IDLE then
        if allowAutonomy ~= true then return end
        self.idleRemaining = self.idleRemaining - dt
        if self.idleRemaining <= 0 then self:_beginWalk(nil, "idle-finished") end
        return
    end
    if self.state ~= Controller.State.WALK or not self.targetX then return end

    local delta = self.targetX - self.x
    local distance = math.abs(delta)
    if distance <= self.config.arrivalDistance then
        self.x = self.targetX
        self:_finishWalk(false, "arrived")
        return
    end
    local direction = delta > 0 and 1 or -1
    self.velocityX, self.velocityY = direction * self.config.moveSpeed, 0
    local step = math.min(distance, self.config.moveSpeed * dt)
    self.x = self.x + direction * step
    self.y = self.zone.baselineY
    self:_emit("positionChanged", self.x, self.y, "walk")
    if step >= distance then self:_finishWalk(false, "arrived") end
end

function Controller:getState()
    return self.state
end

function Controller:getRequestedAnimation()
    return ANIMATION_BY_STATE[self.state]
end

function Controller:getSnapshot()
    return {
        state = self.state,
        x = self.x,
        y = self.y,
        targetX = self.targetX,
        facing = self.facing,
        requestedAnimation = self:getRequestedAnimation(),
        validMinX = self.validMinX,
        validMaxX = self.validMaxX,
        walkingAllowed = self.walkingAllowed,
        velocityX = self.velocityX,
        velocityY = self.velocityY,
        dragging = self.state == Controller.State.DRAGGING,
        pressPending = self.pointerCandidate ~= nil and self.state ~= Controller.State.DRAGGING,
        pressHoldElapsed = self.pointerCandidate and self.pointerCandidate.holdElapsed or nil,
        settling = self.settle ~= nil,
        dragGrabOffsetX = self.pointerCandidate and self.pointerCandidate.grabOffsetX or nil,
        dragGrabOffsetY = self.pointerCandidate and self.pointerCandidate.grabOffsetY or nil,
        usesSemanticGrab = self.pointerCandidate and self.pointerCandidate.usesSemanticGrab == true or false,
    }
end

return Controller
