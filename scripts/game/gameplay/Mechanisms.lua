-- gameplay/Mechanisms: private runtime functions installed into the App context.
local M = {}

---@param context GameContext
function M.Install(context)
    local Rules = context.Rules
    local CONFIG = context.CONFIG
    local _ENV = context
    function DoorOpenVector(object)
        local distance = object.openDistance * mapper_.objectScale / CONFIG.pixelsPerMeter
        if object.openDirection == "UP" then return 0, distance end
        if object.openDirection == "DOWN" then return 0, -distance end
        if object.openDirection == "LEFT" then return -distance, 0 end
        return distance, 0
    end
    local function ApplyDoorPose(object)
        local ox, oy = DoorOpenVector(object)
        object.node:SetPosition2D(
            object.worldX + ox * object.openness,
            object.worldY + oy * object.openness
        )
    end
    function DoorBlockedByApple(object)
        if not apple_ then return false end
        local openX, openY = DoorOpenVector(object)
        local position = apple_.node.position2D
        local radius = apple_.radius or 0
        local minX = math.min(object.worldX, object.worldX + openX) - object.worldWidth * 0.5 - radius
        local maxX = math.max(object.worldX, object.worldX + openX) + object.worldWidth * 0.5 + radius
        local minY = math.min(object.worldY, object.worldY + openY) - object.worldHeight * 0.5 - radius
        local maxY = math.max(object.worldY, object.worldY + openY) + object.worldHeight * 0.5 + radius
        return position.x >= minX and position.x <= maxX and position.y >= minY and position.y <= maxY
    end
    function SetDoorTarget(object, open)
        object.targetOpen = open
        if not open then object.closeAt = uiElapsed_ * 1000 + object.closeDelay end
    end
    function ApplyDoorSignal(object, active)
        if object.response == "OPEN" then
            SetDoorTarget(object, active)
        elseif object.response == "CLOSE" then
            SetDoorTarget(object, not active)
        elseif active then
            SetDoorTarget(object, not object.targetOpen)
        end
    end
    function EmitChannelSignal(channelId, active, sourceId)
        if not channelId or channelId == "" then return end
        channelStates_[channelId] = { active = active, sourceId = sourceId }
        if not runtime_ then return end
        for _, object in ipairs(runtime_.ordered) do
            if object.type == "door" and object.channelId == channelId then
                ApplyDoorSignal(object, active)
            elseif object.type == "spring" and object.enabledChannel == channelId then
                object.channelEnabled = active
            end
        end
    end
    function EvaluateButton(object)
        local gravityMultiplier = Rules.GetGravityMultiplier(rules_, level_.rules.initialGravity)
        local conditionSatisfied = object.contactCount > 0 and gravityMultiplier >= object.gravityThreshold
        local activationEdge = not object.conditionSatisfied and conditionSatisfied
        local canActivate = uiElapsed_ * 1000 - object.lastActivationAt >= object.debounceTime
        local nextActive = object.active
        if object.mode == "HOLD" then
            nextActive = conditionSatisfied
        elseif activationEdge and canActivate then
            nextActive = not object.active
        end
        object.conditionSatisfied = conditionSatisfied
        local outputChanged = nextActive ~= object.active
        object.active = nextActive
        if (activationEdge and canActivate) or (object.mode == "HOLD" and outputChanged and nextActive) then
            object.lastActivationAt = uiElapsed_ * 1000
        end
        if outputChanged then EmitChannelSignal(object.channelId, object.active, object.id) end
    end
    ReevaluateButtons = function()
        if not runtime_ or not level_ then return end
        for _, object in ipairs(runtime_.ordered) do
            if object.type == "button" then EvaluateButton(object) end
        end
    end
    InitializeMechanisms = function()
        channelStates_ = {}
        if not runtime_ then return end
        for _, object in ipairs(runtime_.ordered) do
            if object.type == "button" then
                object.active = object.data.properties and object.data.properties.initialState == true or false
                object.contactCount = 0
                object.conditionSatisfied = false
                object.lastActivationAt = -math.huge
            elseif object.type == "door" then
                object.targetOpen = object.data.properties and object.data.properties.initialState == "OPEN" or false
                object.openness = object.targetOpen and 1 or 0
                object.state = object.targetOpen and "OPEN" or "CLOSED"
                object.closeAt = 0
            elseif object.type == "spring" then
                object.channelEnabled = true
            end
        end
        for _, object in ipairs(runtime_.ordered) do
            if object.type == "button" then EmitChannelSignal(object.channelId, object.active, object.id) end
        end
    end
    function SnapDoorsToTargets()
        if not runtime_ then return end
        for _, object in ipairs(runtime_.ordered) do
            if object.type == "door" then
                object.openness = object.targetOpen and 1 or 0
                object.state = object.targetOpen and "OPEN" or "CLOSED"
                object.closeAt = 0
                ApplyDoorPose(object)
            end
        end
    end
    function UpdateDoors(dt)
        if not runtime_ then return end
        for _, object in ipairs(runtime_.ordered) do
            if object.type == "door" then
                local target = object.targetOpen and 1 or 0
                local delta = dt * 1000 / math.max(1, object.duration)
                if object.openness < target then
                    object.state = "OPENING"
                    object.openness = math.min(target, object.openness + delta)
                    if object.openness == 1 then object.state = "OPEN" end
                elseif object.openness > target and uiElapsed_ * 1000 >= object.closeAt then
                    if not object.antiCrush or not DoorBlockedByApple(object) then
                        object.state = "CLOSING"
                        object.openness = math.max(target, object.openness - delta)
                        if object.openness == 0 then object.state = "CLOSED" end
                    end
                end
                ApplyDoorPose(object)
            end
        end
    end
    function UpdateSpringExits()
        if not runtime_ or not apple_ then return end
        for _, object in ipairs(runtime_.ordered) do
            if object.type == "spring" and object.pendingExitVelocity then
                apple_.body.linearVelocity = object.pendingExitVelocity
                apple_.body.awake = true
                object.pendingExitVelocity = nil
            end
        end
    end
    function UpdateSpringVisuals(dt)
        if not runtime_ then return end
        for _, object in ipairs(runtime_.ordered) do
            if object.type == "spring" and object.pulseElapsedMs ~= nil then
                object.pulseElapsedMs = object.pulseElapsedMs + math.max(0, dt) * 1000
                if object.pulseElapsedMs >= 140 then object.pulseElapsedMs = nil end
            end
        end
    end
end

return M
