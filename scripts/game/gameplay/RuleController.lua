-- gameplay/RuleController: private runtime functions installed into the App context.
local M = {}
local NewtonPunchShake = require("game.render.NewtonPunchShake")

---@param context GameContext
function M.Install(context)
    local Rules = context.Rules
    local PhaseWallEffects = context.PhaseWallEffects
    local newtonPunchShake_ = context.newtonPunchShake_
    local _ENV = context
    function RuleFeedbackText(id, candidate)
        if id == "feather-gravity" then return "场地重力强度已减弱，当前重力方向保持不变。" end
        if id == "side-gravity" then
            local labels = { LEFT = "左", RIGHT = "右", UP = "上", DOWN = "下" }
            return "场地重力已改为向" .. (labels[candidate] or "当前") .. "，动态物体速度保持不变。"
        end
        if id == "hooke-bounce" then return "弹簧的弹射倍率已提高。" end
        if id == "up-impulse" then return "向上冲量已叠加到苹果当前速度。" end
        if id == "mirror-motion" then
            return (candidate == "HORIZONTAL" and "水平" or "垂直") .. "速度已镜像，另一轴速度保持不变。"
        end
        return "苹果获得一次相位充能，下一次可穿过玻璃相位墙。"
    end
    function StartRuleFeedback(id, candidate, accent)
        observation_ = RuleFeedbackText(id, candidate)
        rulePulse_ = { elapsed = 0, duration = .22, color = accent or Renderer2D.COLORS.primaryActive }
        ruleFlash_ = {
            elapsed = 0,
            duration = .48,
            cardId = id,
            color = id == "quantum-phase" and Renderer2D.COLORS.quantum or Renderer2D.COLORS.primaryActive,
        }
    end
    function UpdateRuleFeedback(dt)
        if rulePulse_ then
            rulePulse_.elapsed = rulePulse_.elapsed + dt
            if rulePulse_.elapsed >= rulePulse_.duration then rulePulse_ = nil end
        end
        if ruleFlash_ then
            ruleFlash_.elapsed = ruleFlash_.elapsed + dt
            if ruleFlash_.elapsed >= ruleFlash_.duration then ruleFlash_ = nil end
        end
    end
    function UpdatePhaseWallEffects(dt)
        PhaseWallEffects.UpdateRuntime(runtime_, dt)
    end
    function IsInsidePhaseableWall(worldX, worldY)
        return PhaseWallEffects.FindContainingWall(runtime_, worldX, worldY) ~= nil
    end
    local function SegmentPoint(startX, startY, endX, endY, progress)
        return startX + (endX - startX) * progress,
            startY + (endY - startY) * progress
    end
    local function PaddedExitPoint(startX, startY, endX, endY, exitX, exitY)
        local deltaX, deltaY = endX - startX, endY - startY
        local length = math.sqrt(deltaX * deltaX + deltaY * deltaY)
        if length <= 0.000001 then return exitX, exitY end
        local padding = (apple_.radius or 0) + 0.002
        return exitX + deltaX / length * padding,
            exitY + deltaY / length * padding
    end
    local function FinishPhaseTraversal(wall, worldX, worldY, physicalX, physicalY)
        if physicalX and physicalY then
            local velocity = apple_.body.linearVelocity
            -- The post-step sweep may already be beyond a second wall. Put the
            -- apple just beyond the first wall before restoring its collision mask.
            apple_.node:SetPosition2D(physicalX, physicalY)
            apple_.body.linearVelocity = velocity
            apple_.body.awake = true
            phasePreviousX_, phasePreviousY_ = physicalX, physicalY
        end
        if wall then
            PhaseWallEffects.TriggerPass(wall, worldX, worldY,
                apple_.body.linearVelocity, "exit")
        end
        phaseTraversing_ = false
        phaseWallTraversal_ = nil
        Rules.EndPhase(rules_)
        RecordReplayEvent("RULE_REMOVED", "quantum-phase")
        SetGravity()
        UpdateAngerFromRules()
        SetStatus("PHASE · 相位穿墙已消耗")
    end
    function UpdatePhaseTraversal()
        if not apple_ then return end
        local position = apple_.node.position2D
        local previousX, previousY = phasePreviousX_, phasePreviousY_
        phasePreviousX_, phasePreviousY_ = position.x, position.y
        if not rules_.phaseActive then return end
        previousX, previousY = previousX or position.x, previousY or position.y
        local wall = PhaseWallEffects.FindContainingWall(runtime_, position.x, position.y)
        if phaseTraversing_ then
            local traversedWall, _, traversedExitT, startsInside = PhaseWallEffects.FindFirstCrossedWall(
                runtime_, previousX, previousY, position.x, position.y)
            if traversedWall == phaseWallTraversal_ and startsInside
                and traversedExitT < 1 - 0.000001 then
                local exitX, exitY = SegmentPoint(previousX, previousY, position.x, position.y, traversedExitT)
                local physicalX, physicalY = PaddedExitPoint(
                    previousX, previousY, position.x, position.y, exitX, exitY)
                FinishPhaseTraversal(phaseWallTraversal_, exitX, exitY, physicalX, physicalY)
                return
            elseif wall == phaseWallTraversal_ then
                return
            end
            FinishPhaseTraversal(phaseWallTraversal_, position.x, position.y)
            return
        end

        local crossedWall, entryT, exitT = PhaseWallEffects.FindFirstCrossedWall(
            runtime_, previousX, previousY, position.x, position.y)
        if crossedWall then
            local entryX, entryY = SegmentPoint(previousX, previousY, position.x, position.y, entryT)
            phaseTraversing_ = true
            phaseWallTraversal_ = crossedWall
            PhaseWallEffects.TriggerPass(crossedWall, entryX, entryY,
                apple_.body.linearVelocity, "enter")
            -- Consume immediately when the whole wall was crossed in one step,
            -- so a second wall cannot be phased by the same card use.
            if exitT < 1 - 0.000001 then
                local exitX, exitY = SegmentPoint(previousX, previousY, position.x, position.y, exitT)
                local physicalX, physicalY = PaddedExitPoint(
                    previousX, previousY, position.x, position.y, exitX, exitY)
                FinishPhaseTraversal(crossedWall, exitX, exitY, physicalX, physicalY)
            end
        elseif wall then
            phaseTraversing_ = true
            phaseWallTraversal_ = wall
            PhaseWallEffects.TriggerPass(wall, position.x, position.y,
                apple_.body.linearVelocity, "enter")
        end
    end
    function ApplyDecision(id, mirrorAxis)
        if id == "mirror-motion" then
            if not mirrorAxis then
                SetStatus("CARD · 运动镜像需要明确的方向手势")
                return false
            end
        end
        local cardState = cardStates_[id]
        -- Card inventory already owns decision-use limits. A SINGLE_USE card
        -- with count > 1 must be allowed to apply once per remaining copy;
        -- Rules.usedDecisions only protects callers that have no card use left.
        local hasAvailableUse = cardState and (cardState.usageMode == "REUSABLE"
            or (cardState.remainingUses or 0) > 0)
        if not Rules.UseDecision(rules_, id, hasAvailableUse) then return false end
        if id == "up-impulse" then
            local v = apple_.body.linearVelocity
            apple_.body.linearVelocity = Vector2(v.x, v.y + 5.52 * CurrentPhysicsTimeScale())
        elseif id == "mirror-motion" then
            local v = apple_.body.linearVelocity
            if mirrorAxis == "HORIZONTAL" then
                apple_.body.linearVelocity = Vector2(-v.x, v.y)
                rules_.mirrorAxis = "HORIZONTAL"
            else
                apple_.body.linearVelocity = Vector2(v.x, -v.y)
                rules_.mirrorAxis = "VERTICAL"
            end
        elseif id == "quantum-phase" then
            phaseTraversing_ = false
            phaseWallTraversal_ = nil
            local position = apple_.node.position2D
            phasePreviousX_, phasePreviousY_ = position.x, position.y
            SetGravity()
        end
        ruleDeployCount_ = ruleDeployCount_ + 1
        RecordReplayEvent("CARD_PLAYED", id)
        UpdateAngerFromRules()
        SetStatus("RULE DEPLOYED · " .. (Rules.CARDS[id] and Rules.CARDS[id].name or id))
        StartRuleFeedback(id, mirrorAxis, Rules.CARDS[id] and Rules.CARDS[id].accent)
        PlaySound("card")
        return true
    end
    function ApplyCardResolution(id, candidate)
        local definition = Rules.CARDS[id]
        if not definition then return false end
        if definition.kind == "field" then
            if id == "side-gravity" then
                if candidate == "LEFT" then rules_.sideGravity = { x = -1, y = 0 }
                elseif candidate == "RIGHT" then rules_.sideGravity = { x = 1, y = 0 }
                elseif candidate == "UP" then rules_.sideGravity = { x = 0, y = -1 }
                elseif candidate == "DOWN" then rules_.sideGravity = { x = 0, y = 1 }
                else return false end
            end
            Rules.DeployField(rules_, id)
            ruleDeployCount_ = ruleDeployCount_ + 1
            SetGravity()
            ApplyAppleCardMaterial()
            RecordReplayEvent("CARD_PLAYED", id)
            UpdateAngerFromRules()
            SetStatus("RULE DEPLOYED · " .. definition.name)
            StartRuleFeedback(id, candidate, definition.accent)
            PlaySound("card")
            if context.NotifyTutorialFieldRuleActivated then
                context.NotifyTutorialFieldRuleActivated(id)
            end
            return true
        end
        local applied = launched_ and ApplyDecision(id, candidate) or false
        if applied then ApplyAppleCardMaterial() end
        return applied
    end

    function ExecuteNewtonPunch()
        local removedRules = {}
        for cardId in pairs(rules_.activeFields) do removedRules[#removedRules + 1] = cardId end
        if rules_.phaseActive then removedRules[#removedRules + 1] = "quantum-phase" end
        if not Rules.Punch(rules_) then return false end
        NewtonPunchShake.Trigger(newtonPunchShake_)
        phaseTraversing_ = false
        phaseWallTraversal_ = nil
        SetGravity()
        ApplyAppleCardMaterial()
        UpdateAngerFromRules()
        for _, cardId in ipairs(removedRules) do RecordReplayEvent("RULE_REMOVED", cardId) end
        RecordReplayEvent("NEWTON_PUNCH")
        SetStatus("NEWTON · 修正拳已出手")
        PlaySound("punch")
        if context.NotifyTutorialNewtonPunchExecuted then
            context.NotifyTutorialNewtonPunchExecuted(removedRules)
        end
        return true
    end
end

return M
