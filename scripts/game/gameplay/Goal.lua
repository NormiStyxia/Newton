-- gameplay/Goal: private runtime functions installed into the App context.
local M = {}

function M.Install(context)
    local _ENV = context
    function IsAppleGoalPair(nodeA, nodeB)
        if not nodeA or not nodeB or not runtime_ then return false end
        local goal = LevelData.FindFirst(level_, "goal_sensor")
        if not goal then return false end
        return (nodeA.name == "Apple" and nodeB.name == goal.id) or (nodeB.name == "Apple" and nodeA.name == goal.id)
    end
    function IsAppleNode(node)
        return node and node.name == "Apple"
    end

    -- Box2D contact events are authoritative when delivered. This mirrors the
    -- source Sensor's rectangle using the apple's circle as a deterministic
    -- fallback for engines that omit or prematurely end a trigger callback.
    function GoalSensorContainsApple()
        if not apple_ or not runtime_ or not level_ then return false end
        local goal = LevelData.FindFirst(level_, "goal_sensor")
        local runtimeGoal = goal and runtime_.byId[goal.id] or nil
        if not runtimeGoal then return false end

        local position = apple_.node.position2D
        local dx = position.x - runtimeGoal.worldX
        local dy = position.y - runtimeGoal.worldY
        local rotation = math.rad(runtimeGoal.node.rotation2D)
        local cosine, sine = math.cos(rotation), math.sin(rotation)
        local localX = cosine * dx + sine * dy
        local localY = -sine * dx + cosine * dy
        local halfWidth = runtimeGoal.worldWidth * .5
        local halfHeight = runtimeGoal.worldHeight * .5
        local closestX = math.max(-halfWidth, math.min(localX, halfWidth))
        local closestY = math.max(-halfHeight, math.min(localY, halfHeight))
        local offsetX = localX - closestX
        local offsetY = localY - closestY
        -- Matter's 26-sided apple and Box2D's contact solver both carry a small
        -- collision skin. Include the same tolerance in the deterministic
        -- fallback so callback churn cannot reset an otherwise continuous stay.
        local radius = apple_.radius + GOAL_CONTACT_SKIN
        return offsetX * offsetX + offsetY * offsetY <= radius * radius
    end
    function ResetGoal()
        goalContact_ = false
        goalContactMs_ = 0
        goalEntryRecorded_ = false
        local goal = level_ and LevelData.FindFirst(level_, "goal_sensor") or nil
        local runtimeGoal = goal and runtime_ and runtime_.byId[goal.id] or nil
        if runtimeGoal then
            runtimeGoal.active = false
            runtimeGoal.contactMs = 0
            runtimeGoal.contactProgress = 0
        end
    end
    function BeginGoalContact(recordEntry)
        if not launched_ or replayActive_ or absorbing_ or success_ or failed_ then return false end
        goalContact_ = true
        goalContactMs_ = math.max(1, goalContactMs_)
        local goal = LevelData.FindFirst(level_, "goal_sensor")
        local runtimeGoal = goal and runtime_ and runtime_.byId[goal.id] or nil
        if runtimeGoal then runtimeGoal.active = true end
        if recordEntry and not goalEntryRecorded_ then
            goalEntryRecorded_ = true
            RecordReplayEvent("GOAL_ENTER")
            SetStatus("OBSERVE · 苹果进入观察窗")
        end
        return true
    end

    -- Phaser recalculates its hand only after the burn completes, then tweens the
    -- surviving cards to their new slots for 160ms. Preserve the rendered poses
    -- before consumption so the count change does not produce a visual jump.
    function ActivateGoalContact(nodeA, nodeB, recordEntry)
        if not IsAppleGoalPair(nodeA, nodeB) then return false end
        return BeginGoalContact(recordEntry)
    end
    function RefreshGoalContact()
        if not launched_ or replayActive_ or absorbing_ or success_ or failed_ then return end
        if GoalSensorContainsApple() then
            BeginGoalContact(true)
        elseif goalContact_ then
            ResetGoal()
        end
    end
end

return M
