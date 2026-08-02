-- gameplay/Goal: private runtime functions installed into the App context.
local M = {}

-- One unconfirmed physics step is tolerated. This is long enough to bridge
-- UrhoX's contact-callback/node-transform handoff, but a real exit still clears
-- on the next step. The grace step never advances or completes the stay timer.
local GOAL_CONTACT_MISS_LIMIT = 2

---@param context GameContext
function M.Install(context)
    local LevelData = context.LevelData
    local GOAL_CONTACT_SKIN = context.GOAL_CONTACT_SKIN
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
        -- PhysicsBegin/UpdateContact2D are sampled by the matching post-step.
        -- Keep the bit set even if EndContact churns later in the same solver
        -- pass; the post-step geometry check remains the independent fallback.
        goalContactEventSeen_ = true
        return BeginGoalContact(recordEntry)
    end
    function DeactivateGoalContact(nodeA, nodeB)
        if not IsAppleGoalPair(nodeA, nodeB) then return false end
        -- EndContact is authoritative for this step, but ResetGoal is delayed
        -- until post-step so a premature callback becomes a frozen grace step.
        goalContactEndSeen_ = true
        return true
    end
    function RefreshGoalContact()
        if not launched_ or replayActive_ or absorbing_ or success_ or failed_ then return end
        -- A begin/update in the same solver pass wins over an end. Otherwise an
        -- end wins over the one-frame-old node transform, preventing a real
        -- exit from gaining stay time just because visual synchronization lags.
        local contactConfirmed = goalContactEventSeen_
            or (not goalContactEndSeen_ and GoalSensorContainsApple())
        goalContactEventSeen_ = false
        goalContactEndSeen_ = false
        if contactConfirmed then
            BeginGoalContact(true)
        elseif goalContact_ then
            goalContactConfirmed_ = false
            goalContactMissSteps_ = goalContactMissSteps_ + 1
            if goalContactMissSteps_ >= GOAL_CONTACT_MISS_LIMIT then ResetGoal() end
        else
            goalContactConfirmed_ = false
            goalContactMissSteps_ = 0
        end
    end
end

return M
