-- tutorial/Controller: small, non-blocking onboarding state machine.
-- It observes authoritative gameplay state; it never owns card input or victory.
local M = {}

local STATE = {
    INACTIVE = "INACTIVE",
    WAITING_FOR_MARKER = "WAITING_FOR_MARKER",
    WAITING_FOR_ACTION = "WAITING_FOR_ACTION",
    COMPLETED = "COMPLETED",
    CANCELLED = "CANCELLED",
}

local ACTION_CONFIGS = {
    level_02 = {
        id = "level02_play_feather_gravity",
        marker = "level02_feather_gravity_action",
        step = {
            id = "deploy_feather_gravity",
            instruction = "拖出「轻羽引力」",
            hint = "拖动这张牌",
            targetType = "card",
            targetId = "feather-gravity",
        },
        afterMessages = {
            {
                speaker = "green",
                side = "left",
                displayName = "绿毛同事",
                avatarText = "绿",
                text = "好了。场地牌已经生效——现在整个实验场的重力都变轻了。",
                style = "GREEN",
            },
            {
                speaker = "newton",
                side = "left",
                displayName = "牛顿",
                avatarText = "牛",
                text = "减弱重力，轨迹会被拉得更长。",
                style = "NEWTON",
            },
            {
                speaker = "green",
                side = "left",
                displayName = "绿毛同事",
                avatarText = "绿",
                text = "记住：场地牌改的是世界，而且会持续生效。",
                style = "GREEN",
            },
            {
                speaker = "green",
                side = "left",
                displayName = "绿毛同事",
                avatarText = "绿",
                text = "还有一种策略牌，只在使用时执行一次效果。遇到的时候再说。",
                style = "GREEN",
            },
        },
    },
}

local function fieldIsActive(context, cardId)
    local rules = context.rules_
    return rules ~= nil and rules.activeFields ~= nil and rules.activeFields[cardId] == true
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
    self.step = nil
    self.elapsed = 0
    self.afterMessagesAppended = false
end

function Controller:ResetForLevel(levelId)
    self.levelId = levelId
    self.config = ACTION_CONFIGS[levelId]
    self.state = self.config and STATE.WAITING_FOR_MARKER or STATE.INACTIVE
    self.step = nil
    self.elapsed = 0
    self.afterMessagesAppended = false
end

function Controller:BeginAction(marker)
    if not self.config or self.state ~= STATE.WAITING_FOR_MARKER
        or marker ~= self.config.marker then
        return false
    end

    self.step = self.config.step
    self.elapsed = 0
    -- A fast player may have deployed the card while the intro was still
    -- revealing. Treat that authoritative state as completion immediately.
    if fieldIsActive(self.context, self.step.targetId) then
        self:CompleteAction("already-active")
    else
        self.state = STATE.WAITING_FOR_ACTION
    end
    return true
end

function Controller:CompleteAction(_reason)
    if self.state ~= STATE.WAITING_FOR_ACTION and self.state ~= STATE.WAITING_FOR_MARKER then
        return false
    end
    self.state = STATE.COMPLETED
    self.step = nil
    self.elapsed = 0
    if not self.afterMessagesAppended and self.context.AppendDialogueMessages and self.config then
        self.afterMessagesAppended = true
        self.context.AppendDialogueMessages(self.levelId, self.config.afterMessages)
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

    -- This is intentionally checked outside the action branch. Victory always
    -- wins over tutorial progression, including before the marker is reached.
    if self.context.success_ or self.context.failed_ then
        self:CancelForLevelComplete()
        return
    end
    if self.state == STATE.WAITING_FOR_ACTION and self.step
        and fieldIsActive(self.context, self.step.targetId) then
        self:CompleteAction("field-active")
    end
end

function Controller:GetRenderModel()
    if self.state ~= STATE.WAITING_FOR_ACTION or not self.step then
        return { visible = false, state = self.state }
    end
    return {
        visible = true,
        state = self.state,
        tutorialId = self.config and self.config.id or nil,
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

    function InitializeTutorial()
        tutorialController_ = Controller.New(context)
    end

    function DestroyTutorial()
        tutorialController_ = nil
    end

    function NotifyTutorialLevelReady(levelId)
        if tutorialController_ then tutorialController_:ResetForLevel(levelId) end
    end

    function ResetTutorialForLevel(levelId)
        if tutorialController_ then tutorialController_:ResetForLevel(levelId) end
    end

    function NotifyTutorialDialogueMarker(levelId, marker)
        if tutorialController_ and tutorialController_.levelId == levelId then
            tutorialController_:BeginAction(marker)
        end
    end

    function UpdateTutorial(dt)
        if tutorialController_ then tutorialController_:Update(dt) end
    end

    function GetTutorialRenderModel()
        return tutorialController_ and tutorialController_:GetRenderModel()
            or { visible = false, state = STATE.INACTIVE }
    end

    function CancelTutorialForLevelComplete()
        if tutorialController_ then tutorialController_:CancelForLevelComplete() end
    end
end

M.Controller = Controller

return M
