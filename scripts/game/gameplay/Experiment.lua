-- gameplay/Experiment: private runtime functions installed into the App context.
local M = {}

---@param context GameContext
function M.Install(context)
    local MatterCalibration = context.MatterCalibration
    local Rules = context.Rules
    local LevelData = context.LevelData
    local CONFIG = context.CONFIG
    local _ENV = context
    function PointerToWorld(x, y)
        return context.design_:LogicalToWorld(x, y)
    end
    function AppleScreenPosition()
        local p = apple_.node.position2D
        return context.design_:WorldToLogical(p.x, p.y)
    end
    function IsNearApple(x, y)
        local ax, ay = AppleScreenPosition()
        local dx, dy = x - ax, y - ay
        return dx * dx + dy * dy <= 46 * 46
    end
    function UpdateAppleDrag(x, y)
        local launcher = apple_.launcher
        local launcherWorldX, launcherWorldY = mapper_:LevelToWorld(launcher.spawnLevelX, launcher.spawnLevelY)
        local lx, ly = context.design_:WorldToLogical(launcherWorldX, launcherWorldY)
        local dx, dy = x - lx, y - ly
        local length = math.sqrt(dx * dx + dy * dy)
        if length > 98 then dx, dy = dx * 98 / length, dy * 98 / length end
        dx = math.max(dx, -76)
        dy = math.min(dy, 78)
        aimPreview_ = { x = lx + dx, y = ly + dy, launcherX = lx, launcherY = ly }
        local wx, wy = PointerToWorld(lx + dx, ly + dy)
        apple_.node:SetPosition2D(wx, wy)
    end
    function LaunchApple()
        draggedApple_ = false
        local launcher = apple_.launcher
        local applePos = apple_.node.position2D
        local dx, dy
        if aimPreview_ then
            dx = aimPreview_.x - aimPreview_.launcherX
            dy = aimPreview_.y - aimPreview_.launcherY
        else
            dx = (applePos.x - launcher.spawnWorldX) * CONFIG.pixelsPerMeter
            dy = -(applePos.y - launcher.spawnWorldY) * CONFIG.pixelsPerMeter
        end
        local length = math.sqrt(dx * dx + dy * dy)
        aimPreview_ = nil
        if length < 24 then ResetExperiment(false); return end
        local vx = -dx * 0.165
        local vy = -dy * 0.165
        local timeScale = CurrentPhysicsTimeScale()
        apple_.body.bodyType = BT_DYNAMIC
        -- Switching a Box2D body from static to dynamic recomputes mass data from
        -- the exact circle fixture. Restore the source Matter 26-gon inertia.
        MatterCalibration.ApplyAppleMassProperties(apple_.body)
        -- Matter restores the material captured by setStatic(false), so a card
        -- played while the apple is still mounted does not survive launch.
        apple_.shape.restitution = MatterCalibration.APPLE_INITIAL_RESTITUTION
        apple_.body.linearVelocity = Vector2(
            vx * 60 / CONFIG.pixelsPerMeter * timeScale,
            -vy * 60 / CONFIG.pixelsPerMeter * timeScale
        )
        apple_.body.angularVelocity = -vx * 0.006 * 60 * timeScale
        local flightFrictionAir = apple_.flightFrictionAir or apple_.baseFrictionAir
        apple_.body.linearDamping = MatterCalibration.Box2DLinearDamping(flightFrictionAir, timeScale)
        apple_.body.angularDamping = MatterCalibration.Box2DLinearDamping(flightFrictionAir, timeScale)
        apple_.body.awake = true
        Rules.Launch(rules_)
        launched_ = true
        replaySamples_ = {
            {
                t = 0,
                x = applePos.x,
                y = applePos.y,
                vx = apple_.body.linearVelocity.x,
                vy = apple_.body.linearVelocity.y,
                angle = apple_.node.rotation2D,
            },
        }
        replayEvents_ = {}
        replayNextSampleMs_ = CONFIG.replaySampleMs
        replayPreviousSample_ = replaySamples_[1]
        SetGravity()
        SetStatus("FLIGHT · 规则已生效")
        PlaySound("launch")
    end
    function CancelAppleDrag()
        if not draggedApple_ or launched_ or not apple_ then return end
        draggedApple_ = false
        aimPreview_ = nil
        apple_.node:SetPosition2D(apple_.launcher.spawnWorldX, apple_.launcher.spawnWorldY)
    end
    function UpdateExperiment(dt)
        if replayActive_ then return end
        if absorbing_ then
            if goalPulseElapsedMs_ ~= nil then
                goalPulseElapsedMs_ = goalPulseElapsedMs_ + math.max(0, dt) * 1000
                if goalPulseElapsedMs_ >= 460 then goalPulseElapsedMs_ = nil end
            end
            absorbElapsedMs_ = math.min(520, absorbElapsedMs_ + math.max(0, dt) * 1000)
            if absorbElapsedMs_ >= 520 then
                absorbing_ = false
                success_ = true
                assistedClear_ = context.assistDemoActive_ == true or context.assistUsed_ == true
                if level_ then
                    level_.assistedClear = assistedClear_
                    -- The AssistDemo runner must observe the real success before
                    -- the report pauses its update. Finalization opens the report.
                    level_.resultOverlayVisible = context.assistDemoActive_ ~= true
                end
                local reportState = nil
                if not context.assistDemoActive_ and GenerateResultReport then
                    reportState = GenerateResultReport()
                end
                RecordOfficialExperimentProgress(assistedClear_, reportState)
                SetStatus("CLEARED · 观测成立")
                NotifyGreenAssistantAttemptSucceeded()
            end
            return
        end
        if not launched_ then return end
        flightMs_ = flightMs_ + dt * 1000
        RecordReplay(dt)
        UpdatePhaseTraversal()
        local p = apple_.node.position2D
        local screenX, screenY = context.design_:WorldToLogical(p.x, p.y)
        if flightMs_ - lastTrailAt_ > 55 then
            trail_[#trail_ + 1] = { x = screenX, y = screenY }
            if #trail_ > 18 then table.remove(trail_, 1) end
            lastTrailAt_ = flightMs_
        end
        if goalContact_ then
            -- Preserve the accumulated stay across one adapter dropout, but do
            -- not count or complete an unconfirmed step as source contact time.
            if goalContactConfirmed_ then goalContactMs_ = goalContactMs_ + dt * 1000 end
            local goal = LevelData.FindFirst(level_, "goal_sensor")
            local runtimeGoal = goal and runtime_.byId[goal.id] or nil
            local requiredStayTime = runtimeGoal and runtimeGoal.requiredStayTime or 700
            if runtimeGoal then
                runtimeGoal.contactMs = goalContactMs_
                runtimeGoal.contactProgress = math.max(0, math.min(1, goalContactMs_ / requiredStayTime))
                runtimeGoal.active = true
            end
            if goalContactConfirmed_ and goalContactMs_ >= requiredStayTime then
                CaptureReplayFinalSample()
                absorbing_ = true
                absorbElapsedMs_ = 0
                goalPulseElapsedMs_ = 0
                launched_ = false
                apple_.body.bodyType = BT_STATIC
                apple_.body.linearVelocity = Vector2(0, 0)
                apple_.shape.trigger = true
                activeCardId_ = nil
                primedCardId_ = nil
                ClearCardInteraction()
                observation_ = "苹果已在爱因斯坦观察窗内稳定停留。"
                SetStatus("CLEARED · 观察成立")
                PlaySound("success")
            end
        else goalContactMs_ = 0 end
        if screenX < frame_.playfieldX - 120 or screenX > frame_.playfieldX + frame_.playfieldWidth + 120
            or screenY < frame_.playfieldY - 140 or screenY > frame_.playfieldY + frame_.playfieldHeight + 140 then
            CaptureReplayFinalSample()
            failed_ = true
            launched_ = false
            apple_.body.bodyType = BT_STATIC
            RegisterFailure("OUT_OF_BOUNDS")
        else
            local velocity = apple_.body.linearVelocity
            local matterSpeed = CurrentMatterSpeedFromWorld(velocity)
            stalledMs_ = matterSpeed < 0.1 and stalledMs_ + dt * 1000 or 0
            if stalledMs_ > 10000 then
                CaptureReplayFinalSample()
                failed_ = true
                launched_ = false
                apple_.body.bodyType = BT_STATIC
                RegisterFailure("STALLED")
            end
        end
        if math.abs(p.x) > 7.5 or math.abs(p.y) > 5 then anger_ = math.min(100, anger_ + dt * 2) end
        UpdateDoors(dt)
    end
end

return M
