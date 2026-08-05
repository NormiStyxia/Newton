local GameAdapter = {}
GameAdapter.__index = GameAdapter

local function InRect(x, y, rect)
    return x >= rect.x and x <= rect.x + rect.width
        and y >= rect.y and y <= rect.y + rect.height
end

function GameAdapter.New(context)
    return setmetatable({ context = assert(context, "AssistDemo GameAdapter requires context") }, GameAdapter)
end

GameAdapter.new = GameAdapter.New

function GameAdapter:beginSession()
    local context = self.context
    context.assistSceneActive_ = true
    context.assistDemoActive_ = true
    context.assistUsed_ = true
    context.assistantInputLocked_ = true
    if context.level_ then context.level_.resultOverlayVisible = false end
end

function GameAdapter:resetLevel()
    local context = self.context
    context.ResetExperiment(false)
    context.assistSceneActive_ = true
    context.assistDemoActive_ = true
    context.assistUsed_ = true
    context.assistantInputLocked_ = true
    if context.level_ then context.level_.resultOverlayVisible = false end
    return true
end

function GameAdapter:completeSession()
    local context = self.context
    context.assistDemoActive_ = false
    context.assistSceneActive_ = false
    context.assistUsed_ = true
    context.assistedClear_ = true
    context.CompleteLevel({ assisted = true, assistUsed = true })
end

function GameAdapter:abortSession()
    local context = self.context
    context.assistDemoActive_ = false
    context.assistSceneActive_ = false
    context.ResetExperiment(false)
    context.assistantInputLocked_ = false
end

function GameAdapter:getLauncherTarget()
    local context = self.context
    local launcher = context.apple_ and context.apple_.launcher or nil
    if not launcher then return nil end
    local x, y = context.design_:WorldToLogical(launcher.spawnWorldX, launcher.spawnWorldY)
    return { x = x, y = y, w = 64, h = 64, shape = "circle", radius = 31 }
end

function GameAdapter:getCardTarget(cardId)
    local pose = self.context.CurrentCardVisualPose(cardId)
    if not pose then return nil end
    return {
        x = pose.x,
        y = pose.y,
        w = self.context.CARD_RENDER_WIDTH * (pose.scale or 1),
        h = self.context.CARD_RENDER_HEIGHT * (pose.scale or 1),
        shape = "rect",
    }
end

function GameAdapter:getCardDropTarget(parameter)
    local frame = self.context.frame_
    local x = frame.playfieldX + frame.playfieldWidth * 0.54
    local y = frame.playfieldY + frame.playfieldHeight * 0.48
    local offsets = {
        LEFT = { -64, 0 }, RIGHT = { 64, 0 }, UP = { 0, -64 }, DOWN = { 0, 64 },
        HORIZONTAL = { 64, 0 }, VERTICAL = { 0, 64 },
    }
    local offset = offsets[parameter] or { 0, 0 }
    return { x = x + offset[1], y = y + offset[2], originX = x, originY = y }
end

function GameAdapter:getPunchTarget()
    local frame = self.context.frame_
    return {
        x = frame.playfieldX + frame.playfieldWidth - 58,
        y = frame.cardHandY + 23,
        shape = "circle",
        radius = 40,
    }
end

function GameAdapter:launch(pullX, pullY)
    local target = self:getLauncherTarget()
    if not target then return false end
    self.context.UpdateAppleDrag(target.x + pullX, target.y + pullY)
    self.context.LaunchApple()
    return self.context.launched_ == true
end

function GameAdapter:previewLaunch(screenX, screenY)
    if self.context.launched_ then return false end
    self.context.UpdateAppleDrag(screenX, screenY)
    return true
end

function GameAdapter:playCard(cardId, parameter)
    local drop = self:getCardDropTarget(parameter)
    return self.context.ExecuteCardPlay(cardId, parameter, drop.originX or drop.x, drop.originY or drop.y) == true
end

function GameAdapter:newtonPunch()
    return self.context.ExecuteNewtonPunch() == true
end

function GameAdapter:holdSimulation(held)
    local context = self.context
    context.isPaused_ = held == true
    context.SyncPhysicsUpdateEnabled()
end

function GameAdapter:appleLevelPosition()
    local context = self.context
    if not context.apple_ or not context.mapper_ then return nil, nil end
    local position = context.apple_.node.position2D
    return context.mapper_:WorldToLevel(position.x, position.y)
end

function GameAdapter:isLevelFailed()
    return self.context.failed_ == true
end

function GameAdapter:testCondition(action, memory, dt, regions)
    local condition = action.condition
    if condition == "CARD_EFFECT_APPLIED" then
        return self.context.rules_.activeFields[action.cardId] == true
            or self.context.rules_.usedDecisions[action.cardId] == true
    elseif condition == "NEWTON_PUNCH_COMPLETED" then
        return self.context.rules_.punchUsed == true
    elseif condition == "GOAL_REACHED" then
        return self.context.success_ == true
    elseif condition == "LEVEL_FAILED" then
        return self.context.failed_ == true
    end

    local x, y = self:appleLevelPosition()
    if not x or not y then return false end
    if condition == "APPLE_CROSSED_X" then
        local crossed
        if action.direction == "LEFT" then
            crossed = x <= action.x and (memory.previousX == nil or memory.previousX > action.x)
        else
            crossed = x >= action.x and (memory.previousX == nil or memory.previousX < action.x)
        end
        memory.previousX = x
        return crossed
    elseif condition == "APPLE_CROSSED_Y" then
        local crossed
        if action.direction == "UP" then
            crossed = y <= action.y and (memory.previousY == nil or memory.previousY > action.y)
        else
            crossed = y >= action.y and (memory.previousY == nil or memory.previousY < action.y)
        end
        memory.previousY = y
        return crossed
    elseif condition == "APPLE_ENTER_REGION" or condition == "APPLE_EXIT_REGION" then
        local region = regions[action.regionId]
        if not region then error("unknown assist region: " .. tostring(action.regionId)) end
        local inside = InRect(x, y, region)
        local previous = memory.inside
        memory.inside = inside
        if condition == "APPLE_ENTER_REGION" then return inside and previous ~= true end
        return not inside and previous == true
    elseif condition == "APPLE_STOPPED" then
        local velocity = self.context.apple_.body.linearVelocity
        local speed = math.sqrt(velocity.x * velocity.x + velocity.y * velocity.y)
        if speed <= (action.speedThreshold or 0.08) then
            memory.stoppedFor = (memory.stoppedFor or 0) + math.max(0, dt or 0)
        else
            memory.stoppedFor = 0
        end
        return memory.stoppedFor >= (action.settleDuration or 0.45)
    end
    error("unsupported assist condition: " .. tostring(condition))
end

return GameAdapter
