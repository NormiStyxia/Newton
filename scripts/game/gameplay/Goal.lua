-- gameplay/Goal: private runtime functions installed into the App context.
local M = {}

---@param context GameContext
function M.Install(context)
    local LevelData = context.LevelData
    local CONFIG = context.CONFIG
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

    -- The visible Sensor is circular even though its trigger fixture is a box.
    -- Use the apple collision circle plus the Sensor's outer visual radius so
    -- timing starts at actual volume overlap, not at the fixture's corners.
    function GoalSensorContainsApple()
        if not apple_ or not runtime_ or not level_ then return false end
        local goal = LevelData.FindFirst(level_, "goal_sensor")
        local runtimeGoal = goal and runtime_.byId[goal.id] or nil
        if not runtimeGoal then return false end

        local position = apple_.node.position2D
        local dx = position.x - runtimeGoal.worldX
        local dy = position.y - runtimeGoal.worldY
        local pixelsPerMeter = CONFIG and CONFIG.pixelsPerMeter or 100
        local sensorRadius = math.max(24 / pixelsPerMeter,
            math.min(runtimeGoal.worldWidth * .4, runtimeGoal.worldHeight * .5))
        local overlapRadius = sensorRadius + apple_.radius
        return dx * dx + dy * dy <= overlapRadius * overlapRadius
    end
    function ResetGoal()
        goalContact_ = false
        goalContactMs_ = 0
        goalEntryRecorded_ = false
        goalContactEventSeen_ = false
        goalContactEndSeen_ = false
        goalContactConfirmed_ = false
        goalContactMissSteps_ = 0
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
        goalContactConfirmed_ = true
        goalContactMissSteps_ = 0
        goalContactMs_ = math.max(0, goalContactMs_)
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
        if GoalSensorContainsApple() then
            goalContactEventSeen_ = true
            BeginGoalContact(recordEntry)
        end
        return true
    end
    function DeactivateGoalContact(nodeA, nodeB)
        if not IsAppleGoalPair(nodeA, nodeB) then return false end
        goalContactEndSeen_ = true
        return true
    end
    function RefreshGoalContact()
        if not launched_ or replayActive_ or absorbing_ or success_ or failed_ then return end
        -- The circle overlap is the sole source of truth. A complete separation
        -- clears the timer immediately; a later re-entry starts from zero.
        local contactConfirmed = GoalSensorContainsApple()
        goalContactEventSeen_ = false
        goalContactEndSeen_ = false
        if contactConfirmed then
            BeginGoalContact(true)
        else
            ResetGoal()
        end
    end
end

return M
