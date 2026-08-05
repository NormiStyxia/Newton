local State = require("game.assist_demo.State")

local Runner = {}
Runner.__index = Runner

local SUPPORTED_ACTIONS = {
    RESET_LEVEL = true, SHOW_MESSAGE = true, LAUNCH = true, PLAY_CARD = true,
    NEWTON_PUNCH = true, WAIT_CONDITION = true, WAIT_VISUAL = true,
}

function Runner.New(adapter, view, callbacks)
    local self = setmetatable({}, Runner)
    self.adapter = assert(adapter, "AssistDemoRunner requires an adapter")
    self.view = assert(view, "AssistDemoRunner requires a cursor view")
    self.callbacks = callbacks or {}
    self.state = State.IDLE
    self.solution = nil
    self.actionIndex = 0
    self.action = nil
    self.phase = nil
    self.actionElapsed = 0
    self.phaseElapsed = 0
    self.conditionMemory = {}
    self.errorMessage = nil
    return self
end

Runner.new = Runner.New

function Runner:_setState(state, reason)
    assert(State.IsValid(state), "invalid AssistDemo state")
    local previous = self.state
    if previous == state then return end
    self.state = state
    if self.callbacks.onStateChanged then self.callbacks.onStateChanged(state, previous, reason) end
end

function Runner:getState() return self.state end
function Runner:getError() return self.errorMessage end

function Runner:start(solution, cursorStart)
    if State.IsActive(self.state) then return false, "assist demo is already active" end
    if type(solution) ~= "table" or type(solution.actions) ~= "table" or #solution.actions == 0 then
        return false, "invalid standard solution"
    end
    for _, action in ipairs(solution.actions) do
        if not SUPPORTED_ACTIONS[action.type] then
            return false, "unsupported assist action: " .. tostring(action.type)
        end
        if action.type == "WAIT_CONDITION"
            and (type(action.timeout) ~= "number" or action.timeout <= 0) then
            return false, "WAIT_CONDITION requires a positive timeout"
        end
    end
    self.solution = solution
    self.actionIndex = 0
    self.action = nil
    self.phase = nil
    self.actionElapsed = 0
    self.phaseElapsed = 0
    self.conditionMemory = {}
    self.errorMessage = nil
    self.adapter:beginSession()
    self.view:open(cursorStart and cursorStart.x, cursorStart and cursorStart.y)
    self:_setState(State.READY, "selected")
    return true
end

function Runner:_releaseSimulation()
    if self.conditionMemory.simulationHeld then
        self.adapter:holdSimulation(false)
        self.conditionMemory.simulationHeld = nil
    end
end

function Runner:_fail(message)
    self:_releaseSimulation()
    self.errorMessage = tostring(message or "assist demo failed")
    self.view:setMessage("演示未能完成，当前关卡参数可能已发生变化。")
    self:_setState(State.FAILED, self.errorMessage)
end

function Runner:abort(reason)
    if not State.IsActive(self.state) then return false end
    self:_releaseSimulation()
    self.errorMessage = reason or "aborted"
    self.view:close()
    self:_setState(State.ABORTED, self.errorMessage)
    return true
end

function Runner:_completeAction()
    self:_releaseSimulation()
    self.action = nil
    self.phase = nil
    self.actionElapsed = 0
    self.phaseElapsed = 0
    self.conditionMemory = {}
    self.view:setTarget(nil)
end

function Runner:_nextAction()
    self.actionIndex = self.actionIndex + 1
    self.action = self.solution.actions[self.actionIndex]
    self.phase = "begin"
    self.actionElapsed = 0
    self.phaseElapsed = 0
    self.conditionMemory = {}
    if not self.action then
        self.view:setMessage("轨迹记录完成。")
        self:_setState(State.COMPLETED, "solution-finished")
    end
end

function Runner:_updateLaunch(action)
    if self.phase == "begin" then
        local target = self.adapter:getLauncherTarget()
        if not target then self:_fail("launcher target is unavailable"); return end
        self.conditionMemory.target = target
        self.view:setTarget(target)
        self.view:moveTo(target.x, target.y, 0.42)
        self.phase = "approach"
    elseif self.phase == "approach" and self.view:isMotionFinished() then
        local target = self.conditionMemory.target
        self.view:startDrag()
        self.view:moveTo(target.x + (action.pullX or 0), target.y + (action.pullY or 0), action.cursorDuration or 0.65)
        self.phase = "pull"
    elseif self.phase == "pull" and self.view:isMotionFinished() then
        if not self.adapter:launch(action.pullX or 0, action.pullY or 0) then
            self:_fail("launch action was rejected")
            return
        end
        self.view:endDrag()
        self.phase = "release"
        self.phaseElapsed = 0
    elseif self.phase == "pull" and self.adapter.previewLaunch and self.view.getPosition then
        local x, y = self.view:getPosition()
        self.adapter:previewLaunch(x, y)
    elseif self.phase == "release" and self.phaseElapsed >= (action.postDelay or 0.18) then
        self:_completeAction()
    end
end

function Runner:_updatePlayCard(action)
    if self.phase == "begin" then
        self.adapter:holdSimulation(true)
        self.conditionMemory.simulationHeld = true
        local target = self.adapter:getCardTarget(action.cardId)
        if not target then self:_fail("card target is unavailable: " .. tostring(action.cardId)); return end
        self.conditionMemory.target = target
        self.view:setTarget(target)
        self.view:moveTo(target.x, target.y, action.approachDuration or 0.45)
        self.phase = "approach"
    elseif self.phase == "approach" and self.view:isMotionFinished() then
        local drop = self.adapter:getCardDropTarget(action.parameter)
        self.conditionMemory.drop = drop
        self.view:startDrag()
        self.view:moveTo(drop.x, drop.y, action.cursorDuration or 0.62)
        self.phase = "drag"
    elseif self.phase == "drag" and self.view:isMotionFinished() then
        if not self.adapter:playCard(action.cardId, action.parameter) then
            self:_fail("card action was rejected: " .. tostring(action.cardId))
            return
        end
        self.view:endDrag()
        self.phase = "release"
        self.phaseElapsed = 0
    elseif self.phase == "release" and self.phaseElapsed >= 0.22 then
        self:_completeAction()
    end
end

function Runner:_updatePunch(action)
    if self.phase == "begin" then
        self.adapter:holdSimulation(true)
        self.conditionMemory.simulationHeld = true
        local target = self.adapter:getPunchTarget()
        self.conditionMemory.target = target
        self.view:setTarget(target)
        self.view:moveTo(target.x, target.y, action.cursorDuration or 0.52)
        self.phase = "approach"
    elseif self.phase == "approach" and self.view:isMotionFinished() then
        self.view:click()
        if not self.adapter:newtonPunch() then self:_fail("Newton punch was rejected"); return end
        self.phase = "clicked"
        self.phaseElapsed = 0
    elseif self.phase == "clicked" and self.phaseElapsed >= 0.25 then
        self:_completeAction()
    end
end

function Runner:_prepareWaitTarget(action)
    local prepare = action.prepareTarget
    local target
    if prepare and prepare.type == "CARD" then
        target = self.adapter:getCardTarget(prepare.cardId)
    elseif prepare and prepare.type == "NEWTON_PUNCH" then
        target = self.adapter:getPunchTarget()
    end
    if target then
        self.view:setTarget(target)
        self.view:moveTo(target.x, target.y, prepare.duration or 0.25)
    end
end

function Runner:_updateAction(dt)
    local action = self.action
    self.actionElapsed = self.actionElapsed + dt
    self.phaseElapsed = self.phaseElapsed + dt
    if action.timeout and self.actionElapsed > action.timeout then
        local actionName = action.condition and (action.type .. " " .. action.condition) or action.type
        self:_fail(string.format("%s timed out after %.2fs", actionName, action.timeout))
        return
    end
    if action.type == "RESET_LEVEL" then
        if not self.adapter:resetLevel() then self:_fail("level reset failed"); return end
        self:_completeAction()
    elseif action.type == "SHOW_MESSAGE" then
        if self.phase == "begin" then
            self.view:setMessage(action.text)
            self.phase, self.phaseElapsed = "wait", 0
        elseif self.phaseElapsed >= (action.duration or 0.8) then
            self:_completeAction()
        end
    elseif action.type == "WAIT_VISUAL" then
        if self.phase == "begin" then self.phase, self.phaseElapsed = "wait", 0 end
        if self.phaseElapsed >= (action.duration or 0) then self:_completeAction() end
    elseif action.type == "WAIT_CONDITION" then
        if self.phase == "begin" then
            self.phase, self.phaseElapsed = "wait", 0
            self:_prepareWaitTarget(action)
        end
        if self.adapter:testCondition(action, self.conditionMemory, dt, self.solution.assistRegions or {}) then
            self:_completeAction()
        end
    elseif action.type == "LAUNCH" then
        self:_updateLaunch(action)
    elseif action.type == "PLAY_CARD" then
        self:_updatePlayCard(action)
    elseif action.type == "NEWTON_PUNCH" then
        self:_updatePunch(action)
    end
end

function Runner:update(dt)
    dt = math.max(0, dt or 0)
    self.view:update(dt)
    if self.state == State.READY then
        self:_setState(State.RESETTING, "begin-reset")
        return
    elseif self.state == State.RESETTING then
        self:_setState(State.EXECUTING, "reset-ready")
        self:_nextAction()
    end
    if self.state ~= State.EXECUTING then return end
    if not self.action then self:_nextAction() end
    if self.state ~= State.EXECUTING or not self.action then return end
    if self.action.type ~= "RESET_LEVEL" and self.adapter:isLevelFailed() then
        self:_fail("level entered failed state")
        return
    end
    local ok, errorMessage = pcall(self._updateAction, self, dt)
    if not ok then
        self:_fail(errorMessage)
        return
    end
    if self.state == State.EXECUTING and not self.action then self:_nextAction() end
end

return Runner
