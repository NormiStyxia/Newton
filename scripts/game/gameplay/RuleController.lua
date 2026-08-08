-- gameplay/RuleController: private runtime functions installed into the App context.
local M = {}

---@param context GameContext
function M.Install(context)
    local Rules = context.Rules
    local PhaseWallEffects = context.PhaseWallEffects
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
    function UpdatePhaseTraversal()
        if not apple_ or not rules_.phaseActive then return end
        local position = apple_.node.position2D
        local wall = PhaseWallEffects.FindContainingWall(runtime_, position.x, position.y)
        if wall then
            if not phaseTraversing_ then
                -- The gameplay transition is unchanged; these calls only attach
                -- an entry ripple and a local membrane opening to that transition.
                phaseTraversing_ = true
                phaseWallTraversal_ = wall
                PhaseWallEffects.TriggerPass(wall, position.x, position.y,
                    apple_.body.linearVelocity, "enter")
            end
        elseif phaseTraversing_ then
            -- Reaching the far side is the existing phase-consumption point.
            -- Project the exit effect back onto the traversed wall surface.
            if phaseWallTraversal_ then
                PhaseWallEffects.TriggerPass(phaseWallTraversal_, position.x, position.y,
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
        phaseTraversing_ = false
        phaseWallTraversal_ = nil
        SetGravity()
        ApplyAppleCardMaterial()
        UpdateAngerFromRules()
        for _, cardId in ipairs(removedRules) do RecordReplayEvent("RULE_REMOVED", cardId) end
        RecordReplayEvent("NEWTON_PUNCH")
        SetStatus("NEWTON · 修正拳已出手")
        PlaySound("punch")
        return true
    end
end

return M
