-- tutorial/Controller: small, non-blocking onboarding state machine.
-- It observes authoritative gameplay state; it never owns card input, rules, or victory.
local M = {}

local STATE = {
    INACTIVE = "INACTIVE",
    WAITING_FOR_MARKER = "WAITING_FOR_MARKER",
    WAITING_FOR_ACTION = "WAITING_FOR_ACTION",
    COMPLETED = "COMPLETED",
    CANCELLED = "CANCELLED",
}

local GRAVITY_EPSILON = 0.0001

local ACTION_CONFIGS = {
    level_02 = {
        id = "level02_play_feather_gravity",
        steps = {
            {
                id = "deploy_feather_gravity",
                marker = "level02_feather_gravity_action",
                instruction = "拖出「轻羽引力」",
                hint = "拖动这张牌",
                targetType = "card",
                targetId = "feather-gravity",
                completion = "field_rule_activated",
                afterMessages = {
                    {
                        speaker = "nomi",
                        side = "right",
                        displayName = "诺米",
                        avatarText = "诺",
                        text = "好了。场地牌已经生效——现在整个实验场的重力都变轻了。",
                        style = "NOMI",
                    },
                    {
                        speaker = "green",
                        side = "left",
                        displayName = "绿毛同事",
                        avatarText = "绿",
                        text = "减弱重力，轨迹会被拉得更长。",
                        style = "GREEN",
                    },
                    {
                        speaker = "newton",
                        side = "left",
                        displayName = "牛顿",
                        avatarText = "牛",
                        text = "记住：场地牌改的是世界，而且会持续生效。",
                        style = "NEWTON",
                    },
                    {
                        speaker = "newton",
                        side = "left",
                        displayName = "牛顿",
                        avatarText = "牛",
                        text = "还有一种策略牌，只在使用时执行一次效果。遇到的时候再说。",
                        style = "NEWTON",
                    },
                },
            },
        },
    },
    level_03 = {
        id = "level03_field_reset",
        steps = {
            {
                id = "level03_play_side_gravity",
                marker = "level03_side_gravity_action",
                instruction = "拖出「定向引力」",
                hint = "先把规则改掉",
                targetType = "card",
                targetId = "side-gravity",
                completion = "field_rule_activated",
                afterMessages = {
                    {
                        speaker = "green",
                        side = "left",
                        displayName = "绿毛同事",
                        avatarText = "绿",
                        text = "定向引力已经接管实验场了。",
                        style = "GREEN",
                    },
                    {
                        speaker = "green",
                        side = "left",
                        displayName = "绿毛同事",
                        avatarText = "绿",
                        text = "先让苹果按新规则运动。接下来，再把世界改回去。",
                        style = "GREEN",
                        tutorialMarker = "level03_newton_punch_action",
                    },
                },
            },
            {
                id = "level03_use_newton_punch",
                marker = "level03_newton_punch_action",
                instruction = "点击牛顿拳",
                hint = "让规则恢复正常",
                targetType = "ui",
                targetId = "newton_punch",
                prerequisiteTargetId = "side-gravity",
                readyCondition = "apple_stopped",
                readySettleMs = 150,
                completion = "field_rules_reset",
                afterMessages = {
                    {
                        speaker = "newton",
                        side = "left",
                        displayName = "牛顿",
                        avatarText = "牛",
                        text = "修正完成。重力恢复。",
                        style = "NEWTON",
                    },
                    {
                        speaker = "einstein",
                        side = "left",
                        displayName = "爱因斯坦",
                        avatarText = "爱",
                        text = "看见没？牛顿拳会清掉当前持续生效的场地规则。",
                        style = "EINSTEIN",
                    },
                    {
                        speaker = "einstein",
                        side = "left",
                        displayName = "爱因斯坦",
                        avatarText = "爱",
                        text = "所以它不是重来——之前已经发生的运动不会被撤销。",
                        style = "EINSTEIN",
                    },
                    {
                        speaker = "einstein",
                        side = "left",
                        displayName = "爱因斯坦",
                        avatarText = "爱",
                        text = "改规则，再改回来。后面会经常这么干。",
                        style = "EINSTEIN",
                    },
                },
            },
        },
    },
}

local function fieldIsActive(context, cardId)
    local rules = context.rules_
    return rules ~= nil and rules.activeFields ~= nil and rules.activeFields[cardId] == true
end

local function hasNoActiveFields(rules)
    return rules ~= nil and rules.activeFields ~= nil and next(rules.activeFields) == nil
end

local function sameGravity(left, right)
    return left ~= nil and right ~= nil
        and math.abs((left.x or 0) - (right.x or 0)) <= GRAVITY_EPSILON
        and math.abs((left.y or 0) - (right.y or 0)) <= GRAVITY_EPSILON
        and math.abs((left.strength or 0) - (right.strength or 0)) <= GRAVITY_EPSILON
end

local function defaultGravityIsRestored(context)
    local rules = context.rules_
    local level = context.level_
    local Rules = context.Rules
    local base = level and level.rules and level.rules.initialGravity or nil
    if not rules or not base or not Rules or not Rules.GetGravity or not Rules.NewState then return false end
    if not hasNoActiveFields(rules) or rules.phaseActive then return false end
    local currentGravity = Rules.GetGravity(rules, base)
    local defaultGravity = Rules.GetGravity(Rules.NewState(), base)
    return sameGravity(currentGravity, defaultGravity)
end

---@class TutorialController
local Controller = {}
Controller.__index = Controller

function Controller.New(context)
    local self = setmetatable({}, Controller)
    self:Init(context)
    return self
end

function Controller:Init(context)
    self.context = context
    self.levelId = nil
    self.config = nil
    self.state = STATE.INACTIVE
    self.currentStepIndex = 0
    self.step = nil
    self.elapsed = 0
    self.completedSteps = {}
    self.appendedMessagesByStep = {}
    self.observedFieldActivations = {}
    self.observedPunchResets = {}
end

function Controller:ResetForLevel(levelId)
    self.levelId = levelId
    self.config = ACTION_CONFIGS[levelId]
    self.state = self.config and STATE.WAITING_FOR_MARKER or STATE.INACTIVE
    self.currentStepIndex = self.config and 1 or 0
    self.step = nil
    self.elapsed = 0
    self.completedSteps = {}
    self.appendedMessagesByStep = {}
    self.observedFieldActivations = {}
    self.observedPunchResets = {}
end

function Controller:_CurrentStepConfig()
    return self.config and self.config.steps and self.config.steps[self.currentStepIndex] or nil
end

function Controller:_CompletionSatisfied(step)
    if not step then return false end
    if step.completion == "field_rule_activated" then
        return self.observedFieldActivations[step.targetId] == true
            or fieldIsActive(self.context, step.targetId)
    end
    if step.completion == "field_rules_reset" then
        local fieldId = step.prerequisiteTargetId
        local rules = self.context.rules_
        return fieldId ~= nil
            and self.observedFieldActivations[fieldId] == true
            and self.observedPunchResets[fieldId] == true
            and rules ~= nil
            and rules.punchUsed == true
            and hasNoActiveFields(rules)
            and rules.phaseActive == false
            and defaultGravityIsRestored(self.context)
    end
    return false
end

function Controller:_ActionReady(step)
    if not step then return false end
    if step.targetType == "ui" and step.targetId == "newton_punch" then
        local Rules = self.context.Rules
        local ready = Rules ~= nil and Rules.CanPunch ~= nil and self.context.rules_ ~= nil
            and Rules.CanPunch(self.context.rules_) == true
        if ready and step.readyCondition == "apple_stopped" then
            ready = self.context.launched_ == true
                and (self.context.stalledMs_ or 0) >= (step.readySettleMs or 150)
        end
        return ready
    end
    return true
end

function Controller:BeginAction(marker)
    local expected = self:_CurrentStepConfig()
    if not expected or self.state ~= STATE.WAITING_FOR_MARKER or marker ~= expected.marker then
        return false
    end

    self.step = expected
    self.elapsed = 0
    -- Fast players may have completed the gameplay action while dialogue was
    -- still revealing. The runner catches up to authoritative observations.
    if self:_CompletionSatisfied(expected) then
        self:CompleteAction("already-complete")
    else
        self.state = STATE.WAITING_FOR_ACTION
    end
    return true
end

function Controller:CompleteAction(_reason)
    if self.state ~= STATE.WAITING_FOR_ACTION and self.state ~= STATE.WAITING_FOR_MARKER then
        return false
    end
    local completedStep = self.step or self:_CurrentStepConfig()
    if not completedStep then return false end

    if completedStep.completion == "field_rule_activated" then
        self.observedFieldActivations[completedStep.targetId] = true
    end
    self.completedSteps[completedStep.id] = true
    self.step = nil
    self.elapsed = 0
    self.currentStepIndex = self.currentStepIndex + 1
    self.state = self:_CurrentStepConfig() and STATE.WAITING_FOR_MARKER or STATE.COMPLETED

    if not self.appendedMessagesByStep[completedStep.id]
        and self.context.AppendDialogueMessages and completedStep.afterMessages then
        self.appendedMessagesByStep[completedStep.id] = true
        self.context.AppendDialogueMessages(self.levelId, completedStep.afterMessages)
    end
    return true
end

function Controller:ObserveFieldRuleActivated(cardId)
    if not self.config or type(cardId) ~= "string" then return false end
    self.observedFieldActivations[cardId] = true
    if self.state == STATE.WAITING_FOR_ACTION and self.step
        and self.step.completion == "field_rule_activated"
        and self.step.targetId == cardId then
        return self:CompleteAction("field-activated")
    end
    return true
end

function Controller:ObserveNewtonPunchExecuted(removedRules)
    if not self.config then return false end
    for _, cardId in ipairs(removedRules or {}) do
        self.observedPunchResets[cardId] = true
    end
    if self.state == STATE.WAITING_FOR_ACTION and self.step
        and self.step.completion == "field_rules_reset"
        and self:_CompletionSatisfied(self.step) then
        return self:CompleteAction("field-rules-reset")
    end
    return true
end

function Controller:CancelForLevelComplete()
    if self.state == STATE.INACTIVE or self.state == STATE.CANCELLED then return false end
    self.state = STATE.CANCELLED
    self.step = nil
    self.elapsed = 0
    return true
end

function Controller:Update(dt)
    if not self.config then return end
    self.elapsed = self.elapsed + math.max(0, tonumber(dt) or 0)

    -- Victory and failure always win over tutorial progression, including
    -- before a marker is reached. Neither flow waits on onboarding.
    if self.context.success_ or self.context.failed_ then
        self:CancelForLevelComplete()
        return
    end
    if self.state == STATE.WAITING_FOR_ACTION and self.step
        and self:_CompletionSatisfied(self.step) then
        self:CompleteAction("authoritative-state")
    end
end

function Controller:GetRenderModel()
    if self.state ~= STATE.WAITING_FOR_ACTION or not self.step then
        return { visible = false, state = self.state }
    end
    local ready = self:_ActionReady(self.step)
    return {
        visible = ready,
        ready = ready,
        state = self.state,
        tutorialId = self.config and self.config.id or nil,
        stepId = self.step.id,
        instruction = self.step.instruction,
        hint = self.step.hint,
        targetType = self.step.targetType,
        targetId = self.step.targetId,
        elapsed = self.elapsed,
    }
end

M.STATE = STATE
M.ACTION_CONFIGS = ACTION_CONFIGS

---@param context GameContext
function M.Install(context)
    local _ENV = context

    local function officialRuntime()
        return context.IsOfficialRuntimeSession and context.IsOfficialRuntimeSession() == true
    end

    function InitializeTutorial()
        tutorialController_ = Controller.New(context)
    end

    function DestroyTutorial()
        tutorialController_ = nil
    end

    function NotifyTutorialLevelReady(levelId)
        if tutorialController_ then tutorialController_:ResetForLevel(officialRuntime() and levelId or nil) end
    end

    function ResetTutorialForLevel(levelId)
        if tutorialController_ then tutorialController_:ResetForLevel(officialRuntime() and levelId or nil) end
    end

    function NotifyTutorialDialogueMarker(levelId, marker)
        if officialRuntime() and tutorialController_ and tutorialController_.levelId == levelId then
            tutorialController_:BeginAction(marker)
        end
    end

    function NotifyTutorialFieldRuleActivated(cardId)
        if officialRuntime() and tutorialController_ then
            tutorialController_:ObserveFieldRuleActivated(cardId)
        end
    end

    function NotifyTutorialNewtonPunchExecuted(removedRules)
        if officialRuntime() and tutorialController_ then
            tutorialController_:ObserveNewtonPunchExecuted(removedRules)
        end
    end

    function UpdateTutorial(dt)
        if officialRuntime() and tutorialController_ then tutorialController_:Update(dt) end
    end

    function GetTutorialRenderModel()
        return officialRuntime() and tutorialController_ and tutorialController_:GetRenderModel()
            or { visible = false, state = STATE.INACTIVE }
    end

    function CancelTutorialForLevelComplete()
        if tutorialController_ then tutorialController_:CancelForLevelComplete() end
    end
end

M.Controller = Controller

return M
