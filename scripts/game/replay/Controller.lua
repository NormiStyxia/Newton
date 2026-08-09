-- replay/Controller: private runtime functions installed into the App context.
local M = {}
local WallImpactShake = require("game.render.WallImpactShake")
local NewtonPunchShake = require("game.render.NewtonPunchShake")

---@param frame table
---@return table
function M.ResolveFinishedControls(frame)
    local panelWidth, panelHeight = 350, 48
    local buttonHeight, replayWidth, exitWidth = 34, 92, 84
    local rightPadding, buttonGap = 8, 6
    local centerX = frame.playfieldX + frame.playfieldWidth - 190
    local centerY = frame.playfieldY + frame.playfieldHeight - 54
    local panel = {
        x = centerX - panelWidth * .5,
        y = centerY - panelHeight * .5,
        w = panelWidth,
        h = panelHeight,
    }
    local exit = {
        x = panel.x + panel.w - rightPadding - exitWidth,
        y = centerY - buttonHeight * .5,
        w = exitWidth,
        h = buttonHeight,
    }
    local replay = {
        x = exit.x - buttonGap - replayWidth,
        y = centerY - buttonHeight * .5,
        w = replayWidth,
        h = buttonHeight,
    }
    return {
        panel = panel,
        replay = replay,
        exit = exit,
        titleX = panel.x + 15,
        titleY = centerY - 9,
    }
end

---@param context GameContext
function M.Install(context)
    local ReplayMode = context.ReplayMode
    local ReplayTimeline = context.ReplayTimeline
    local CONFIG = context.CONFIG
    local newtonPunchShake_ = context.newtonPunchShake_
    local _ENV = context
    local function ApplyReplayState(state)
        if not state or not apple_ then return end
        apple_.body.bodyType = BT_STATIC
        apple_.node:SetPosition2D(state.x, state.y)
        apple_.node:SetRotation2D(state.angle or 0)
        apple_.body.linearVelocity = Vector2(0, 0)
        apple_.body.angularVelocity = 0
        if state.mechanisms and ApplyReplayMechanisms then ApplyReplayMechanisms(state.mechanisms) end
    end
    function SetReplayMode(mode, businessMode)
        assert(mode == "none" or mode == "playing" or mode == "paused" or mode == "finished",
            "unknown replay mode: " .. tostring(mode))
        if mode == "none" then
            replayBusinessMode_ = ReplayMode.NONE
        elseif businessMode ~= nil then
            assert(ReplayMode.IsValid(businessMode) and businessMode ~= ReplayMode.NONE,
                "invalid replay business mode: " .. tostring(businessMode))
            replayBusinessMode_ = businessMode
        elseif replayBusinessMode_ == ReplayMode.NONE then
            replayBusinessMode_ = ReplayMode.PLAYER_REPLAY
        end
        replayMode_ = mode
        replayActive_ = mode ~= "none"
        replayPaused_ = mode == "paused" or mode == "finished"
        replayFinished_ = mode == "finished"
        if mode ~= "none" then
            ClearSelectedCard()
            WallImpactShake.ResetRuntime(runtime_)
            NewtonPunchShake.Reset(newtonPunchShake_)
        end
        -- Replay exclusively owns the modal layer. Outcome state remains intact
        -- so an explicit exit can restore it, but it must never receive input or
        -- draw over replay controls while a replay mode is active.
        if level_ then
            level_.resultOverlayVisible = mode == "none" and (success_ or failed_) or false
        end
    end
    function ReplayLog(event)
        print(string.format(
            "[Replay] %s business=%s state=%s overlay=%s samples=%d duration=%.3f",
            event,
            ReplayMode.Name(replayBusinessMode_),
            replayMode_,
            tostring(level_ and level_.resultOverlayVisible == true),
            #replaySamples_,
            (#replaySamples_ > 0 and (replaySamples_[#replaySamples_].t or 0) or 0) / 1000
        ))
    end
    function IsResultOverlayVisible()
        return replayBusinessMode_ == ReplayMode.NONE and replayMode_ == "none"
            and level_ and level_.resultOverlayVisible == true
    end
    function HandleReplayPointer(x, y, press)
        if replayBusinessMode_ ~= ReplayMode.PLAYER_REPLAY then return end
        if not press then return end
        local cx, cy = frame_.playfieldX + frame_.playfieldWidth * .5, frame_.playfieldY + 34
        if replayFinished_ then
            local controls = M.ResolveFinishedControls(frame_)
            local function inEndButton(rect)
                return x >= rect.x and x <= rect.x + rect.w
                    and y >= rect.y and y <= rect.y + rect.h
            end
            if inEndButton(controls.replay) then
                replayTime_ = 0
                SetReplayMode("playing")
                ApplyReplayState(ReplayStateAt(0))
                ReplayLog("restart")
                return
            elseif inEndButton(controls.exit) then
                StopReplay()
                return
            end
        end
        local function inButton(buttonX, width)
            return x >= buttonX - width * .5 and x <= buttonX + width * .5 and y >= cy - 17 and y <= cy + 17
        end
        if inButton(cx - 92, 44) then
            if replayFinished_ then
                replayTime_ = 0
                SetReplayMode("playing")
                ApplyReplayState(ReplayStateAt(0))
                ReplayLog("restart")
            else
                local wasPaused = replayMode_ == "paused"
                SetReplayMode(wasPaused and "playing" or "paused")
                ReplayLog(wasPaused and "resume" or "pause")
            end
        elseif inButton(cx - 27, 58) then
            replaySpeed_ = .5
        elseif inButton(cx + 37, 58) then
            replaySpeed_ = 1
        elseif inButton(cx + 101, 58) then
            replaySpeed_ = 2
        elseif inButton(cx + 238, 78) then
            StopReplay()
        end
    end
    function RecordReplay(dt)
        if not launched_ or replayActive_ or not apple_ then return end
        local p = apple_.node.position2D
        local v = apple_.body.linearVelocity
        local current = {
            t = flightMs_,
            x = p.x,
            y = p.y,
            vx = v.x,
            vy = v.y,
            angle = apple_.node.rotation2D,
            mechanisms = CaptureReplayMechanisms and CaptureReplayMechanisms() or nil,
        }
        local previous = replayPreviousSample_ or current
        local simulationDelta = math.max(0, dt * 1000)
        local frameStart = flightMs_ - simulationDelta
        while replayNextSampleMs_ <= flightMs_ + .0001 do
            local progress = simulationDelta > 0 and math.max(0, math.min(1, (replayNextSampleMs_ - frameStart) / simulationDelta)) or 1
            local deltaAngle = ((current.angle - previous.angle + 540) % 360) - 180
            replaySamples_[#replaySamples_ + 1] = {
                t = replayNextSampleMs_,
                x = previous.x + (current.x - previous.x) * progress,
                y = previous.y + (current.y - previous.y) * progress,
                vx = previous.vx + (current.vx - previous.vx) * progress,
                vy = previous.vy + (current.vy - previous.vy) * progress,
                angle = previous.angle + deltaAngle * progress,
                mechanisms = ReplayTimeline.InterpolateMechanisms(
                    previous.mechanisms, current.mechanisms, progress),
            }
            replayNextSampleMs_ = replayNextSampleMs_ + CONFIG.replaySampleMs
        end
        replayPreviousSample_ = current
    end
    function CaptureReplayFinalSample()
        if not apple_ or #replaySamples_ == 0 then return end
        local last = replaySamples_[#replaySamples_]
        ---@type number
        local terminalTime = flightMs_
        if last and math.abs((last.t or 0) - terminalTime) < .001 then
            -- A successful launch normally has many samples. Keep the rare
            -- zero-duration terminal record replayable instead of leaving the
            -- success modal wired to a no-op button.
            if #replaySamples_ > 1 then return end
            terminalTime = (last.t or 0) + CONFIG.replaySampleMs
        end
        local p, v = apple_.node.position2D, apple_.body.linearVelocity
        replaySamples_[#replaySamples_ + 1] = {
            t = terminalTime, x = p.x, y = p.y, vx = v.x, vy = v.y, angle = apple_.node.rotation2D,
            mechanisms = CaptureReplayMechanisms and CaptureReplayMechanisms() or nil,
        }
        replayPreviousSample_ = replaySamples_[#replaySamples_]
    end
    RecordReplayEvent = function(kind, cardId)
        local prelaunchRuleEvent = kind == "CARD_PLAYED" or kind == "RULE_REMOVED" or kind == "NEWTON_PUNCH"
        if replayActive_ or (not launched_ and not prelaunchRuleEvent) then return end
        local p = apple_.node.position2D
        replayEvents_[#replayEvents_ + 1] = {
            t = launched_ and flightMs_ or 0,
            type = kind,
            cardId = cardId,
            x = p.x,
            y = p.y,
        }
    end
    function ReplayDuration()
        local last = replaySamples_[#replaySamples_]
        return last and last.t or 0
    end
    function CanReplay()
        return #replaySamples_ >= 2 and ReplayDuration() > 0
    end
    function ReplayStateAt(time)
        return ReplayTimeline.StateAt(replaySamples_, time)
    end
    StartReplay = function()
        if replayActive_ or not apple_ or not success_ then return false end
        CaptureReplayFinalSample()
        if not CanReplay() then
            -- Phaser only constructs a replay from a real recorded timeline. A
            -- fabricated 33 ms record finishes on the next frame and looks frozen.
            SetStatus("REPLAY · 轨迹记录不足")
            ReplayLog("rejected")
            return false
        end
        local p, v = apple_.node.position2D, apple_.body.linearVelocity
        replaySavedApple_ = {
            x = p.x, y = p.y, angle = apple_.node.rotation2D,
            bodyType = apple_.body.bodyType, vx = v.x, vy = v.y, angularVelocity = apple_.body.angularVelocity,
            mechanisms = CaptureReplayMechanisms and CaptureReplayMechanisms() or nil,
        }
        SetReplayMode("playing", ReplayMode.PLAYER_REPLAY)
        absorbing_ = false
        absorbElapsedMs_ = 0
        ResetGoal()
        isPaused_ = false
        SetBulletTimeActive(false)
        replayTime_ = 0
        replaySpeed_ = 1
        ClearCardInteraction()
        apple_.body.bodyType = BT_STATIC
        apple_.body.linearVelocity = Vector2(0, 0)
        apple_.body.angularVelocity = 0
        RestoreAppleContactMaterial()
        ApplyReplayState(ReplayStateAt(0))
        SyncPhysicsUpdateEnabled()
        SetStatus("REPLAY · 轨迹回放")
        ReplayLog("start")
        return true
    end
    StopReplay = function()
        if replayBusinessMode_ ~= ReplayMode.PLAYER_REPLAY or not replayActive_ or not apple_ then return end
        local saved = replaySavedApple_
        SetReplayMode("none")
        replayTime_ = 0
        replaySavedApple_ = nil
        isPaused_ = success_ or failed_
        if saved then
            apple_.node:SetPosition2D(saved.x, saved.y)
            apple_.node:SetRotation2D(saved.angle)
            apple_.body.bodyType = saved.bodyType
            apple_.body.linearVelocity = Vector2(saved.vx, saved.vy)
            apple_.body.angularVelocity = saved.angularVelocity
            apple_.body.awake = true
            if saved.mechanisms and ApplyReplayMechanisms then ApplyReplayMechanisms(saved.mechanisms) end
        end
        RestoreAppleContactMaterial()
        SyncPhysicsUpdateEnabled()
        if success_ then SetStatus("CLEARED · 观测成立")
        elseif failed_ then SetStatus("FAILED · 实验未成立")
        else SetStatus(launched_ and "FLIGHT · 规则已生效" or "READY · 等待发射") end
        ReplayLog("exit")
    end
    function UpdateReplay(dt)
        if replayMode_ ~= "playing" then return end
        replayTime_ = ReplayTimeline.Advance(replayTime_, ReplayDuration(), math.max(0, dt) * 1000, replaySpeed_)
        local state = ReplayStateAt(replayTime_)
        ApplyReplayState(state)
        if replayTime_ >= ReplayDuration() then
            SetReplayMode("finished")
            ReplayLog("finished")
        end
    end

    StartAssistReplay = function(replayData)
        if not IsOfficialRuntimeSession() or replayActive_ or not apple_
            or type(replayData) ~= "table" then return false end
        if type(replayData.samples) ~= "table" or #replayData.samples < 2 then return false end
        replaySamples_ = replayData.samples
        replayEvents_ = replayData.events or {}
        replaySavedApple_ = nil
        replayTime_, replaySpeed_ = 0, 1
        success_, failed_, absorbing_, launched_ = false, false, false, false
        assistedClear_ = false
        ResetGoal()
        isPaused_ = false
        SetBulletTimeActive(false)
        ClearCardInteraction()
        apple_.body.bodyType = BT_STATIC
        apple_.body.linearVelocity = Vector2(0, 0)
        apple_.body.angularVelocity = 0
        apple_.shape.trigger = false
        SetReplayMode("playing", ReplayMode.ASSIST_TAKEOVER)
        local state = ReplayStateAt(0)
        ApplyReplayState(state)
        SyncPhysicsUpdateEnabled()
        SetStatus("ASSIST · 接管中")
        ReplayLog("assist-start")
        return true
    end

    FinishAssistReplay = function()
        if replayBusinessMode_ ~= ReplayMode.ASSIST_TAKEOVER or not replayFinished_ then return false end
        local state = ReplayStateAt(ReplayDuration())
        if state and apple_ then
            apple_.node:SetPosition2D(state.x, state.y)
            apple_.node:SetRotation2D(state.angle or 0)
            apple_.body.bodyType = BT_STATIC
            apple_.body.linearVelocity = Vector2(0, 0)
            apple_.body.angularVelocity = 0
        end
        SetReplayMode("none")
        replayTime_ = 0
        replaySamples_, replayEvents_, replaySavedApple_ = {}, {}, nil
        SyncPhysicsUpdateEnabled()
        ReplayLog("assist-finish")
        return true
    end

    CancelAssistReplay = function()
        if replayBusinessMode_ ~= ReplayMode.ASSIST_TAKEOVER then return false end
        SetReplayMode("none")
        replayTime_ = 0
        replaySamples_, replayEvents_, replaySavedApple_ = {}, {}, nil
        ResetExperiment(false)
        ReplayLog("assist-cancel")
        return true
    end
end

return M
