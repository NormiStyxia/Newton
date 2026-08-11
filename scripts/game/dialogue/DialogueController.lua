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

local OPEN_DURATION = 0.34
local CLOSE_DURATION = 0.26
local BUBBLE_DURATION = 0.26
local MESSAGE_INTERVAL = 0.52
local SCROLL_WHEEL_STEP = 54 / 20
local TOUCH_SCROLL_THRESHOLD = 6
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
    self.lastAnger = 0
    self.scrollOffset = 0
    self.maxScroll = 0
    self.contentHeight = 0
    self.viewportHeight = 0
    self.scrollProgressByLevel = {}
    self.pendingScrollProgress = nil
    self.followBottom = true
    self.scrollbarDragging = false
    self.scrollbarGrabY = 0
    self.viewportTouchDrag = nil
    self.viewGeometry = nil
    self.historyButtonGeometry = nil
    self.historyHovered = false
    self.firstWallImpactTriggered = false
end

function Controller:_NotifyTutorialMarker(message)
    if not message or not message.tutorialMarker or not self.context.NotifyTutorialDialogueMarker then return end
    self.context.NotifyTutorialDialogueMarker(self.currentLevelId, message.tutorialMarker)
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
    if self.pendingScrollProgress ~= nil then
        self.scrollOffset = self.maxScroll * clamp(self.pendingScrollProgress, 0, 1)
        self.pendingScrollProgress = nil
        self.followBottom = self.maxScroll - self.scrollOffset <= 18
    elseif self.followBottom then
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

function Controller:_RememberScrollPosition()
    if self.currentLevelId == nil or self.maxScroll <= 0 then return end
    self.scrollProgressByLevel[self.currentLevelId] = self:GetScrollProgress()
end

function Controller:_BeginOpen(mode)
    if self.state ~= STATE.CLOSED then return false end
    local restoreProgress = nil
    if mode == "history" and not self.log:HasUnread(self.currentLevelId) then
        restoreProgress = self.scrollProgressByLevel[self.currentLevelId]
    end
    self.openMode = mode
    self.messages = self.log:GetMessages(self.currentLevelId)
    self.visibleCount = mode == "history" and #self.messages or 0
    self.messageAges = {}
    for index = 1, self.visibleCount do self.messageAges[index] = BUBBLE_DURATION end
    self.stateElapsed = 0
    self.messageElapsed = 0
    self.scrollOffset = 0
    self.maxScroll = 0
    self.pendingScrollProgress = restoreProgress
    self.followBottom = restoreProgress == nil
    self.scrollbarDragging = false
    self.viewportTouchDrag = nil
    self.state = STATE.OPENING
    self.log:MarkRead(self.currentLevelId)
    return true
end

function Controller:OpenIntro()
    return self:_BeginOpen("intro")
end

function Controller:OpenHistory()
    if not self:IsHistoryAvailable() then return false end
    local opened = self:_BeginOpen("history")
    if opened then self.context.playUIClick() end
    return opened
end

function Controller:_RevealNext()
    if self.visibleCount >= #self.messages then return false end
    self.visibleCount = self.visibleCount + 1
    self.messageAges[self.visibleCount] = 0
    self.messageElapsed = 0
    if self.followBottom then self.scrollOffset = self.maxScroll end
    self:_NotifyTutorialMarker(self.messages[self.visibleCount])
    return true
end

function Controller:RevealAll()
    if self.state == STATE.CLOSED or self.state == STATE.CLOSING then return end
    self.context.playUIClick()
    self.visibleCount = #self.messages
    for index = 1, self.visibleCount do self.messageAges[index] = BUBBLE_DURATION end
    self.stateElapsed = OPEN_DURATION
    self.messageElapsed = 0
    self.followBottom = true
    self.scrollOffset = self.maxScroll
    self.state = STATE.REVEALED
    self.log:MarkRead(self.currentLevelId)
    for index = 1, self.visibleCount do self:_NotifyTutorialMarker(self.messages[index]) end
end

function Controller:AppendMessages(levelId, messages)
    if levelId == nil or levelId ~= self.currentLevelId then return false end
    local levelMessages = self.log:GetMessages(levelId)
    for _, message in ipairs(messages or {}) do
        local copy = {}
        for key, value in pairs(message) do copy[key] = value end
        levelMessages[#levelMessages + 1] = copy
    end
    self.messages = levelMessages
    self:_SyncAppendedMessages()
    return #(messages or {}) > 0
end

function Controller:OnWallImpact(levelId)
    if self.firstWallImpactTriggered or levelId == nil or levelId ~= self.currentLevelId then return false end
    local messages = DialogueData.FirstWallImpact(levelId)
    if #messages == 0 then return false end

    if not self:AppendMessages(levelId, messages) then return false end
    self.firstWallImpactTriggered = true
    -- AppendMessages leaves the log read cursor untouched. When communication
    -- is closed (or closing), the existing history-button unread dot is enough;
    -- do not interrupt gameplay by reopening the panel.
    return true
end

function Controller:_CurrentMessageInterval()
    local message = self.messages[self.visibleCount]
    return math.max(BUBBLE_DURATION, tonumber(message and message.revealInterval) or MESSAGE_INTERVAL)
end

function Controller:Close()
    if self.state == STATE.CLOSED or self.state == STATE.CLOSING then return end
    self.context.playUIClick()
    self:_RememberScrollPosition()
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
    self.viewportTouchDrag = nil
    self.pendingScrollProgress = nil
    self.viewGeometry = nil
end

function Controller:Destroy()
    self.state = STATE.CLOSED
end

function Controller:OnLevelReady(levelId, anger)
    if self:IsActive() then
        self:_RememberScrollPosition()
        self:_FinishClose()
    end
    self.currentLevelId = levelId
    self.historyButtonGeometry = nil
    self.firstWallImpactTriggered = false
    self.lastAnger = clamp(anger or 0, 0, MAX_ANGER)
    local intro = DialogueData.Intro(levelId)
    if #intro == 0 then return end
    -- OnLevelReady denotes a new level session, unlike ResetExperiment. Start
    -- a fresh communication timeline so replayed tutorial markers can bind to
    -- the newly reset Tutorial Runner and follow-up messages cannot go stale.
    self.log:ResetLevel(levelId)
    self.log:RecordIntro(levelId, intro)
    self:OpenIntro()
end

function Controller:_SyncAppendedMessages()
    if self.state == STATE.CLOSED or self.state == STATE.CLOSING
        or self.visibleCount >= #self.messages then return end
    if self.openMode == "history" then
        for index = self.visibleCount + 1, #self.messages do
            self.messageAges[index] = BUBBLE_DURATION
        end
        self.visibleCount = #self.messages
        if self.followBottom then self.scrollOffset = self.maxScroll end
    elseif self.state == STATE.REVEALED then
        self.state = STATE.PLAYING
        self:_RevealNext()
    end
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
        self:_SyncAppendedMessages()
    end
    self.lastAnger = current
end

function Controller:_AdvanceState(dt)
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
        if self.visibleCount < #self.messages and self.messageElapsed >= self:_CurrentMessageInterval() then
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
    if not geometry then return false end
    local x, y = pointerFrame.x, pointerFrame.y

    if self.scrollbarDragging then
        if pointerFrame.down then
            local travel = math.max(1, geometry.track.h - geometry.thumb.h)
            local thumbTop = y - self.scrollbarGrabY
            self:SetScrollProgress((thumbTop - geometry.track.y) / travel)
        end
        if pointerFrame.released or not pointerFrame.down then self.scrollbarDragging = false end
        return true
    end

    if pointerFrame.pressed and self.maxScroll > 0 then
        if pointIn(geometry.thumb, x, y) then
            self.scrollbarDragging = true
            self.scrollbarGrabY = y - geometry.thumb.y
            return true
        elseif pointIn(geometry.track, x, y) then
            local travel = math.max(1, geometry.track.h - geometry.thumb.h)
            self:SetScrollProgress((y - geometry.track.y - geometry.thumb.h * 0.5) / travel)
            return true
        end
    end

    local wheel = self.context.input.mouseMoveWheel
    if wheel ~= 0 and pointIn(geometry.viewport, x, y) then
        self:ScrollBy(-wheel * SCROLL_WHEEL_STEP)
        return true
    end
    return false
end

function Controller:_HandleViewportTouch(pointerFrame)
    if pointerFrame.isTouch ~= true then return false end
    local geometry = self.viewGeometry
    local drag = self.viewportTouchDrag

    if drag then
        local deltaY = pointerFrame.y - drag.startY
        if math.abs(deltaY) >= TOUCH_SCROLL_THRESHOLD then drag.moved = true end
        if drag.moved then
            self.scrollOffset = clamp(drag.startOffset - deltaY, 0, self.maxScroll)
            self.followBottom = self.maxScroll - self.scrollOffset <= 18
        end
        if pointerFrame.released or not pointerFrame.down then self.viewportTouchDrag = nil end
        return true
    end

    if pointerFrame.pressed and geometry and pointIn(geometry.viewport, pointerFrame.x, pointerFrame.y) then
        self.viewportTouchDrag = {
            startY = pointerFrame.y,
            startOffset = self.scrollOffset,
            moved = false,
        }
        return true
    end
    return false
end

function Controller:_HandleOpenPointer(pointerFrame)
    if self.state == STATE.CLOSING then return false end
    local consumed = self:_HandleScrollbar(pointerFrame)
    if not consumed then consumed = self:_HandleViewportTouch(pointerFrame) end
    local geometry = self.viewGeometry
    if not pointerFrame.pressed or not geometry or not pointIn(geometry.button, pointerFrame.x, pointerFrame.y) then
        return consumed
    end

    if self.openMode == "history" or self.state == STATE.HISTORY or self.state == STATE.REVEALED then
        self:Close()
    else
        self:RevealAll()
    end
    return true
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
    if self:IsActive() then return self:_HandleOpenPointer(pointerFrame) end
    return false
end

function Controller:GetPanelPresentation()
    if self.state == STATE.OPENING then
        local progress = clamp(self.stateElapsed / OPEN_DURATION, 0, 1)
        local motion = easeOutCubic(progress)
        return 0.72 + 0.28 * motion, motion
    elseif self.state == STATE.CLOSING then
        local progress = clamp(self.stateElapsed / CLOSE_DURATION, 0, 1)
        local motion = 1 - easeOutCubic(progress)
        return 0.72 + 0.28 * motion, motion
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

    local function officialRuntime()
        return context.IsOfficialRuntimeSession and context.IsOfficialRuntimeSession() == true
    end

    function InitializeDialogue()
        dialogueController_ = Controller.New(context)
    end

    function DestroyDialogue()
        if dialogueController_ then dialogueController_:Destroy() end
        dialogueController_ = nil
    end

    function NotifyDialogueLevelReady(levelId)
        if dialogueController_ then
            dialogueController_:OnLevelReady(officialRuntime() and levelId or nil, anger_)
        end
    end

    function AppendDialogueMessages(levelId, messages)
        if officialRuntime() and dialogueController_ then
            return dialogueController_:AppendMessages(levelId, messages)
        end
        return false
    end

    function NotifyDialogueWallImpact(levelId)
        if officialRuntime() and dialogueController_ then
            return dialogueController_:OnWallImpact(levelId)
        end
        return false
    end

    function UpdateDialogue(dt, pointerFrame)
        if not officialRuntime() or not dialogueController_ then return false end
        return dialogueController_:Update(dt, pointerFrame, anger_)
    end

    function DrawDialogueHistoryButton()
        if officialRuntime() and dialogueController_ then
            DialogueOverlayView.DrawHistoryButton(painter_, frame_, dialogueController_)
        end
    end

    function DrawDialogueOverlay()
        if officialRuntime() and dialogueController_ and dialogueController_:IsActive() then
            DialogueOverlayView.Draw(painter_, frame_, dialogueController_)
        end
    end
end

M.STATE = STATE

return M
