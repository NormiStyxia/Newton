local DialogueData = require("game.dialogue.DialogueData")
local DialogueLog = require("game.dialogue.DialogueLog")
local DialogueOverlayView = require("game.render.DialogueOverlayView")

local M = {}

local STATE = {
    CLOSED = "CLOSED",
    OPENING = "OPENING",
    PLAYING = "PLAYING",
    REVEALED = "REVEALED",
    HISTORY = "HISTORY",
    CLOSING = "CLOSING",
}

local OPEN_DURATION = 0.21
local CLOSE_DURATION = 0.18
local BUBBLE_DURATION = 0.15
local MESSAGE_INTERVAL = 0.34
local MAX_ANGER = 100

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function pointIn(rect, x, y)
    return rect ~= nil and x >= rect.x and x <= rect.x + rect.w
        and y >= rect.y and y <= rect.y + rect.h
end

local function easeOutCubic(value)
    local inverse = 1 - clamp(value, 0, 1)
    return 1 - inverse * inverse * inverse
end

local function easeOutBack(value)
    local t = clamp(value, 0, 1) - 1
    local c1 = 1.70158
    local c3 = c1 + 1
    return 1 + c3 * t * t * t + c1 * t * t
end

---@class DialogueController
local Controller = {}
Controller.__index = Controller

function Controller.New(context)
    local self = setmetatable({}, Controller)
    self:Init(context)
    return self
end

function Controller:Init(context)
    self.context = context
    self.log = DialogueLog.New()
    self.state = STATE.CLOSED
    self.openMode = nil
    self.currentLevelId = nil
    self.messages = {}
    self.visibleCount = 0
    self.messageAges = {}
    self.stateElapsed = 0
    self.messageElapsed = 0
    self.savedPhysicsEnabled = nil
    self.savedPhysicsWorld = nil
    self.lastAnger = 0
    self.scrollOffset = 0
    self.maxScroll = 0
    self.contentHeight = 0
    self.viewportHeight = 0
    self.followBottom = true
    self.scrollbarDragging = false
    self.scrollbarGrabY = 0
    self.viewGeometry = nil
    self.historyButtonGeometry = nil
    self.historyHovered = false
end

function Controller:IsActive()
    return self.state ~= STATE.CLOSED
end

function Controller:IsHistoryAvailable()
    return self.currentLevelId ~= nil and self.log:MessageCount(self.currentLevelId) > 0
end

function Controller:HasUnread()
    return self.currentLevelId ~= nil and self.log:HasUnread(self.currentLevelId)
end

function Controller:SetHistoryButtonGeometry(geometry)
    self.historyButtonGeometry = geometry
end

function Controller:SetViewGeometry(geometry)
    self.viewGeometry = geometry
end

function Controller:SetScrollMetrics(contentHeight, viewportHeight)
    self.contentHeight = math.max(0, contentHeight or 0)
    self.viewportHeight = math.max(0, viewportHeight or 0)
    self.maxScroll = math.max(0, self.contentHeight - self.viewportHeight)
    if self.followBottom then
        self.scrollOffset = self.maxScroll
    else
        self.scrollOffset = clamp(self.scrollOffset, 0, self.maxScroll)
        if self.maxScroll - self.scrollOffset <= 18 then self.followBottom = true end
    end
end

function Controller:GetScrollProgress()
    if self.maxScroll <= 0 then return 0 end
    return clamp(self.scrollOffset / self.maxScroll, 0, 1)
end

function Controller:ScrollBy(delta)
    if self.maxScroll <= 0 then
        self.scrollOffset = 0
        self.followBottom = true
        return
    end
    self.scrollOffset = clamp(self.scrollOffset + delta, 0, self.maxScroll)
    self.followBottom = self.maxScroll - self.scrollOffset <= 18
end

function Controller:SetScrollProgress(progress)
    self.scrollOffset = self.maxScroll * clamp(progress, 0, 1)
    self.followBottom = self.maxScroll - self.scrollOffset <= 18
end

function Controller:_FreezeGameplay()
    local physicsWorld = self.context.physicsWorld_
    self.savedPhysicsWorld = physicsWorld
    self.savedPhysicsEnabled = physicsWorld and physicsWorld:IsUpdateEnabled() or nil
    if physicsWorld then physicsWorld:SetUpdateEnabled(false) end
end

function Controller:_RestoreGameplay()
    local physicsWorld = self.savedPhysicsWorld
    if physicsWorld and self.savedPhysicsEnabled ~= nil then
        physicsWorld:SetUpdateEnabled(self.savedPhysicsEnabled)
    end
    self.savedPhysicsWorld = nil
    self.savedPhysicsEnabled = nil
end

function Controller:_BeginOpen(mode)
    if self.state ~= STATE.CLOSED then return false end
    self.openMode = mode
    self.messages = self.log:GetMessages(self.currentLevelId)
    self.visibleCount = mode == "history" and #self.messages or 0
    self.messageAges = {}
    for index = 1, self.visibleCount do self.messageAges[index] = BUBBLE_DURATION end
    self.stateElapsed = 0
    self.messageElapsed = 0
    self.scrollOffset = 0
    self.maxScroll = 0
    self.followBottom = true
    self.scrollbarDragging = false
    self.state = STATE.OPENING
    self:_FreezeGameplay()
    self.log:MarkRead(self.currentLevelId)
    return true
end

function Controller:OpenIntro()
    return self:_BeginOpen("intro")
end

function Controller:OpenHistory()
    if not self:IsHistoryAvailable() then return false end
    return self:_BeginOpen("history")
end

function Controller:_RevealNext()
    if self.visibleCount >= #self.messages then return false end
    self.visibleCount = self.visibleCount + 1
    self.messageAges[self.visibleCount] = 0
    self.messageElapsed = 0
    if self.followBottom then self.scrollOffset = self.maxScroll end
    return true
end

function Controller:RevealAll()
    if self.state == STATE.CLOSED or self.state == STATE.CLOSING then return end
    self.visibleCount = #self.messages
    for index = 1, self.visibleCount do self.messageAges[index] = BUBBLE_DURATION end
    self.stateElapsed = OPEN_DURATION
    self.messageElapsed = 0
    self.followBottom = true
    self.scrollOffset = self.maxScroll
    self.state = STATE.REVEALED
    self.log:MarkRead(self.currentLevelId)
end

function Controller:Close()
    if self.state == STATE.CLOSED or self.state == STATE.CLOSING then return end
    self.state = STATE.CLOSING
    self.stateElapsed = 0
    self.scrollbarDragging = false
end

function Controller:_FinishClose()
    self.state = STATE.CLOSED
    self.openMode = nil
    self.messages = {}
    self.visibleCount = 0
    self.messageAges = {}
    self.stateElapsed = 0
    self.messageElapsed = 0
    self.scrollbarDragging = false
    self.viewGeometry = nil
    self:_RestoreGameplay()
end

function Controller:Destroy()
    if self:IsActive() then self:_RestoreGameplay() end
    self.state = STATE.CLOSED
end

function Controller:OnLevelReady(levelId, anger)
    self.currentLevelId = levelId
    self.lastAnger = clamp(anger or 0, 0, MAX_ANGER)
    if levelId ~= DialogueData.FIRST_LEVEL_ID or self.log:HasIntro(levelId) then return end
    self.log:RecordIntro(levelId, DialogueData.Intro(levelId))
    self:OpenIntro()
end

function Controller:_TrackAnger(anger)
    if self.currentLevelId ~= DialogueData.FIRST_LEVEL_ID then return end
    local current = clamp(anger or 0, 0, MAX_ANGER)
    if current < self.lastAnger then
        self.lastAnger = current
        return
    end

    local crossed = {}
    local highest = nil
    for _, threshold in ipairs(DialogueData.ANGER_THRESHOLDS) do
        if self.lastAnger < threshold and current >= threshold
            and not self.log:IsThresholdRecorded(self.currentLevelId, threshold) then
            crossed[#crossed + 1] = threshold
            highest = threshold
        end
    end
    if highest then
        self.log:RecordThresholds(self.currentLevelId, crossed, DialogueData.AngerMessage(highest))
    end
    self.lastAnger = current
end

function Controller:_AdvanceState(dt)
    if self.savedPhysicsWorld then self.savedPhysicsWorld:SetUpdateEnabled(false) end

    for index = 1, self.visibleCount do
        self.messageAges[index] = math.min(BUBBLE_DURATION, (self.messageAges[index] or 0) + dt)
    end

    if self.state == STATE.OPENING then
        self.stateElapsed = math.min(OPEN_DURATION, self.stateElapsed + dt)
        if self.stateElapsed >= OPEN_DURATION then
            if self.openMode == "history" then
                self.state = STATE.HISTORY
            else
                self.state = STATE.PLAYING
                self:_RevealNext()
            end
        end
    elseif self.state == STATE.PLAYING then
        self.messageElapsed = self.messageElapsed + dt
        if self.visibleCount < #self.messages and self.messageElapsed >= MESSAGE_INTERVAL then
            self:_RevealNext()
        elseif self.visibleCount >= #self.messages
            and (self.messageAges[self.visibleCount] or BUBBLE_DURATION) >= BUBBLE_DURATION then
            self.state = STATE.REVEALED
            self.log:MarkRead(self.currentLevelId)
        end
    elseif self.state == STATE.CLOSING then
        self.stateElapsed = math.min(CLOSE_DURATION, self.stateElapsed + dt)
        if self.stateElapsed >= CLOSE_DURATION then self:_FinishClose() end
    end
end

function Controller:_HandleScrollbar(pointerFrame)
    local geometry = self.viewGeometry
    if not geometry then return end
    local x, y = pointerFrame.x, pointerFrame.y

    if self.scrollbarDragging then
        if pointerFrame.down then
            local travel = math.max(1, geometry.track.h - geometry.thumb.h)
            local thumbTop = y - self.scrollbarGrabY
            self:SetScrollProgress((thumbTop - geometry.track.y) / travel)
        end
        if pointerFrame.released or not pointerFrame.down then self.scrollbarDragging = false end
        return
    end

    if pointerFrame.pressed and self.maxScroll > 0 then
        if pointIn(geometry.thumb, x, y) then
            self.scrollbarDragging = true
            self.scrollbarGrabY = y - geometry.thumb.y
        elseif pointIn(geometry.track, x, y) then
            local travel = math.max(1, geometry.track.h - geometry.thumb.h)
            self:SetScrollProgress((y - geometry.track.y - geometry.thumb.h * 0.5) / travel)
        end
    end

    local wheel = self.context.input.mouseMoveWheel
    if wheel ~= 0 and pointIn(geometry.viewport, x, y) then
        self:ScrollBy(-wheel * 54)
    end
end

function Controller:_HandleOpenPointer(pointerFrame)
    if self.state == STATE.CLOSING then return end
    self:_HandleScrollbar(pointerFrame)
    local geometry = self.viewGeometry
    if not pointerFrame.pressed or not geometry or not pointIn(geometry.button, pointerFrame.x, pointerFrame.y) then return end

    if self.openMode == "history" or self.state == STATE.HISTORY or self.state == STATE.REVEALED then
        self:Close()
    else
        self:RevealAll()
    end
end

function Controller:Update(dt, pointerFrame, anger)
    self:_TrackAnger(anger)
    local wasActive = self:IsActive()

    if not wasActive then
        self.historyHovered = self:IsHistoryAvailable()
            and pointIn(self.historyButtonGeometry, pointerFrame.x, pointerFrame.y)
        if self.historyHovered and pointerFrame.pressed then
            self:OpenHistory()
            return true
        end
        return false
    end

    self.historyHovered = false
    self:_AdvanceState(math.max(0, dt or 0))
    if self:IsActive() then self:_HandleOpenPointer(pointerFrame) end
    return true
end

function Controller:GetPanelPresentation()
    if self.state == STATE.OPENING then
        local progress = clamp(self.stateElapsed / OPEN_DURATION, 0, 1)
        return 0.72 + 0.28 * easeOutBack(progress), progress
    elseif self.state == STATE.CLOSING then
        local progress = clamp(self.stateElapsed / CLOSE_DURATION, 0, 1)
        return 1 - 0.28 * easeOutCubic(progress), 1 - progress
    end
    return 1, 1
end

function Controller:GetBubbleProgress(index)
    return easeOutCubic((self.messageAges[index] or 0) / BUBBLE_DURATION)
end

function Controller:GetButtonKind()
    if self.openMode == "history" or self.state == STATE.HISTORY or self.state == STATE.REVEALED then
        return "close"
    end
    return "skip"
end

function Controller:GetRenderModel()
    return {
        state = self.state,
        messages = self.messages,
        visibleCount = self.visibleCount,
        scrollOffset = self.scrollOffset,
        maxScroll = self.maxScroll,
        anger = clamp(self.context.anger_ or 0, 0, MAX_ANGER),
        maxAnger = MAX_ANGER,
        buttonKind = self:GetButtonKind(),
    }
end

---@param context GameContext
function M.Install(context)
    local _ENV = context

    function InitializeDialogue()
        dialogueController_ = Controller.New(context)
    end

    function DestroyDialogue()
        if dialogueController_ then dialogueController_:Destroy() end
        dialogueController_ = nil
    end

    function NotifyDialogueLevelReady(levelId)
        if dialogueController_ then dialogueController_:OnLevelReady(levelId, anger_) end
    end

    function UpdateDialogue(dt, pointerFrame)
        if not dialogueController_ then return false end
        return dialogueController_:Update(dt, pointerFrame, anger_)
    end

    function DrawDialogueHistoryButton()
        if dialogueController_ then
            DialogueOverlayView.DrawHistoryButton(painter_, frame_, dialogueController_)
        end
    end

    function DrawDialogueOverlay()
        if dialogueController_ and dialogueController_:IsActive() then
            DialogueOverlayView.Draw(painter_, frame_, dialogueController_)
        end
    end
end

M.STATE = STATE

return M
