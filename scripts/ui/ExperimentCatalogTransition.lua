local Transition = {}
Transition.__index = Transition

---@class CatalogEntranceTransition
---@field state string
---@field elapsed number
local Entrance = {}
Entrance.__index = Entrance

Transition.State = {
    IDLE = "IDLE",
    PREPARING = "PREPARING",
    LIFTING = "LIFTING",
    WITHDRAWING = "WITHDRAWING",
    COMMITTING = "COMMITTING",
}

-- The paper is held for one frame before motion starts so the incoming sheet
-- is already rendered underneath the outgoing sheet.
local LIFT_END = 0.22
local ROTATE_START = 0.09
local ROTATE_END = 0.26
local WITHDRAW_END = 0.66
local LIFT_OFFSET_Y = -7
local LIFT_SCALE = 1.022
local MAX_PIVOT_ANGLE = math.rad(3.2)
local EXTRA_WITHDRAW_ANGLE = math.rad(3.0)
local ENTRANCE_SETTLE_ANGLE = math.rad(-0.75)

Transition.EntranceState = {
    TITLE_IDLE = "TITLE_IDLE",
    TITLE_TO_CATALOG = "TITLE_TO_CATALOG",
    CATALOG_ENTERING = "CATALOG_ENTERING",
    CATALOG_IDLE = "CATALOG_IDLE",
    CATALOG_TO_TITLE = "CATALOG_TO_TITLE",
    TITLE_ENTERING = "TITLE_ENTERING",
}

Transition.EntranceTimeline = {
    titleRootEnd = 0.58,
    catalogRootEnd = 0.63,
    titleEnd = 0.38,
    characterDuration = 0.30,
    characterStagger = 0.025,
    leftPanelStart = 0.44,
    leftPanelDuration = 0.24,
    centerPanelStart = 0.49,
    centerPanelDuration = 0.26,
    rightPanelStart = 0.54,
    rightPanelDuration = 0.24,
    listStart = 0.71,
    listDuration = 0.41,
    listItemDuration = 0.15,
    listItemStagger = 0.035,
    paperStart = 0.73,
    paperDuration = 0.40,
    reportStart = 0.79,
    reportDuration = 0.18,
    reportStagger = 0.05,
    highlightStart = 1.00,
    highlightDuration = 0.12,
    buttonStart = 1.01,
    buttonDuration = 0.15,
    buttonStagger = 0.04,
    total = 1.20,
    returnCatalogEnd = 0.54,
    returnTitleEnd = 0.58,
    returnStateSwitch = 0.22,
    titleEnterStart = 0.22,
    titleEnterDuration = 0.32,
    characterEnterStart = 0.20,
    characterEnterDuration = 0.30,
    returnTotal = 0.60,
}

local PANEL_ENTRANCE = {
    left = { offsetX = -70, offsetY = -35, start = "leftPanelStart", duration = "leftPanelDuration" },
    center = { offsetX = 0, offsetY = -55, start = "centerPanelStart", duration = "centerPanelDuration" },
    right = { offsetX = 70, offsetY = 35, start = "rightPanelStart", duration = "rightPanelDuration" },
}

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function easeOutCubic(value)
    value = clamp(value or 0, 0, 1)
    return 1 - (1 - value) ^ 3
end

local function easeInOutCubic(value)
    value = clamp(value or 0, 0, 1)
    if value < 0.5 then return 4 * value * value * value end
    return 1 - ((-2 * value + 2) ^ 3) * 0.5
end

local function progress(elapsed, startTime, duration)
    return clamp(((elapsed or 0) - startTime) / math.max(0.001, duration), 0, 1)
end

local function lerp(from, to, amount)
    return from + (to - from) * clamp(amount or 0, 0, 1)
end

function Entrance.New()
    local self = setmetatable({}, Entrance)
    self:Init()
    return self
end

function Entrance:Init()
    self.state = Transition.EntranceState.TITLE_IDLE
    self.elapsed = 0.0
end

function Entrance:Start()
    if self.state ~= Transition.EntranceState.TITLE_IDLE then return false end
    self.state = Transition.EntranceState.TITLE_TO_CATALOG
    self.elapsed = 0.0
    return true
end

function Entrance:StartReturn()
    if self.state ~= Transition.EntranceState.CATALOG_IDLE then return false end
    self.state = Transition.EntranceState.CATALOG_TO_TITLE
    self.elapsed = 0.0
    return true
end

function Entrance:SetTitleIdle()
    self.state = Transition.EntranceState.TITLE_IDLE
    self.elapsed = 0.0
end

function Entrance:SetCatalogIdle()
    self.state = Transition.EntranceState.CATALOG_IDLE
    self.elapsed = Transition.EntranceTimeline.total
end

function Entrance:Update(dt)
    local timeline = Transition.EntranceTimeline
    local frameTime = math.max(0, tonumber(dt) or 0)
    if self:IsForward() then
        self.elapsed = math.min(timeline.total, self.elapsed + frameTime)
        if self.elapsed >= timeline.total then
            self:SetCatalogIdle()
            return "catalog"
        end
        if self.elapsed >= timeline.leftPanelStart then
            self.state = Transition.EntranceState.CATALOG_ENTERING
        end
        return nil
    end
    if self:IsBackward() then
        self.elapsed = math.min(timeline.returnTotal, self.elapsed + frameTime)
        if self.elapsed >= timeline.returnTotal then
            self:SetTitleIdle()
            return "title"
        end
        if self.elapsed >= timeline.returnStateSwitch then
            self.state = Transition.EntranceState.TITLE_ENTERING
        end
    end
    return nil
end

function Entrance:IsInputLocked()
    return self.state == Transition.EntranceState.TITLE_TO_CATALOG
        or self.state == Transition.EntranceState.CATALOG_ENTERING
        or self.state == Transition.EntranceState.CATALOG_TO_TITLE
        or self.state == Transition.EntranceState.TITLE_ENTERING
end

function Entrance:IsForward()
    return self.state == Transition.EntranceState.TITLE_TO_CATALOG
        or self.state == Transition.EntranceState.CATALOG_ENTERING
end

function Entrance:IsBackward()
    return self.state == Transition.EntranceState.CATALOG_TO_TITLE
        or self.state == Transition.EntranceState.TITLE_ENTERING
end

function Entrance:IsCatalogAssembled()
    return self.state == Transition.EntranceState.CATALOG_IDLE or self:IsBackward()
end

function Entrance:GetRootOffsets(designWidth)
    local width = math.max(1, tonumber(designWidth) or 1)
    local timeline = Transition.EntranceTimeline
    if self:IsBackward() then
        local titleProgress = easeInOutCubic(progress(self.elapsed, 0, timeline.returnTitleEnd))
        local catalogProgress = easeInOutCubic(progress(self.elapsed, 0, timeline.returnCatalogEnd))
        return -width * (1 - titleProgress), width * catalogProgress
    end
    if self.state == Transition.EntranceState.CATALOG_IDLE then return -width, 0 end
    local titleProgress = easeInOutCubic(progress(self.elapsed, 0, timeline.titleRootEnd))
    local catalogProgress = easeInOutCubic(progress(self.elapsed, 0, timeline.catalogRootEnd))
    return -width * titleProgress, width * (1 - catalogProgress)
end

function Entrance:GetTitlePose()
    local timeline = Transition.EntranceTimeline
    if self:IsBackward() then
        local amount = easeOutCubic(progress(self.elapsed, timeline.titleEnterStart, timeline.titleEnterDuration))
        local scale = amount < 0.55
            and lerp(0, 0.7, easeOutCubic(amount / 0.55))
            or lerp(0.7, 1, easeOutCubic((amount - 0.55) / 0.45))
        return { scale = scale, alpha = amount }
    end
    if not self:IsForward() then return { scale = 1, alpha = 1 } end
    local scale
    if self.elapsed < 0.27 then
        scale = lerp(1, 0.65, easeInOutCubic(progress(self.elapsed, 0, 0.27)))
    else
        scale = lerp(0.65, 0, easeInOutCubic(progress(self.elapsed, 0.27, timeline.titleEnd - 0.27)))
    end
    local alpha = 1 - easeOutCubic(progress(self.elapsed, 0.28, timeline.titleEnd - 0.28))
    return { scale = scale, alpha = alpha }
end

function Entrance:GetCharacterPose(index)
    local timeline = Transition.EntranceTimeline
    local delay = math.max(0, (tonumber(index) or 1) - 1) * timeline.characterStagger
    if self:IsBackward() then
        local amount = easeOutCubic(progress(self.elapsed,
            timeline.characterEnterStart + delay, timeline.characterEnterDuration))
        return {
            offsetX = 32 * (1 - amount),
            rotation = 90 * (1 - amount),
            scale = 1,
            alpha = amount,
        }
    end
    if not self:IsForward() then
        return { offsetX = 0, rotation = 0, scale = 1, alpha = 1 }
    end
    local amount = easeInOutCubic(progress(self.elapsed, delay, timeline.characterDuration))
    return {
        offsetX = 32 * amount,
        rotation = 90 * amount,
        scale = 1,
        alpha = 1 - easeOutCubic(amount),
    }
end

function Entrance:GetPanelPose(panelName)
    local config = PANEL_ENTRANCE[panelName]
    if not config then return { offsetX = 0, offsetY = 0, scale = 1, alpha = 1 } end
    if self:IsCatalogAssembled() then
        return { offsetX = 0, offsetY = 0, scale = 1, alpha = 1 }
    end
    local timeline = Transition.EntranceTimeline
    local amount = self:IsForward()
        and easeOutCubic(progress(self.elapsed, timeline[config.start], timeline[config.duration])) or 0
    return {
        offsetX = config.offsetX * (1 - amount),
        offsetY = config.offsetY * (1 - amount),
        scale = lerp(0.985, 1, amount),
        alpha = lerp(0.65, 1, amount),
    }
end

function Entrance:GetListReveal()
    if self:IsCatalogAssembled() then return 1 end
    local timeline = Transition.EntranceTimeline
    return easeOutCubic(progress(self.elapsed, timeline.listStart, timeline.listDuration))
end

function Entrance:GetListItemPose(index)
    if self:IsCatalogAssembled() then return { offsetY = 0, alpha = 1 } end
    local timeline = Transition.EntranceTimeline
    local startTime = timeline.listStart + math.max(0, (tonumber(index) or 1) - 1) * timeline.listItemStagger
    local amount = easeOutCubic(progress(self.elapsed, startTime, timeline.listItemDuration))
    return { offsetY = -8 * (1 - amount), alpha = amount }
end

function Entrance:GetHighlightPose()
    if self:IsCatalogAssembled() then return { scaleX = 1, alpha = 1 } end
    local timeline = Transition.EntranceTimeline
    local amount = easeOutCubic(progress(self.elapsed, timeline.highlightStart, timeline.highlightDuration))
    return { scaleX = lerp(0.96, 1, amount), alpha = amount }
end

function Entrance:GetPaperProgress()
    if self:IsCatalogAssembled() then return 1 end
    local timeline = Transition.EntranceTimeline
    return progress(self.elapsed, timeline.paperStart, timeline.paperDuration)
end

function Entrance:IsPaperVisible()
    return self:IsCatalogAssembled()
        or self:IsForward() and self.elapsed >= Transition.EntranceTimeline.paperStart
end

function Entrance:GetReportBlockPose(index)
    if self:IsCatalogAssembled() then return { offsetX = 0, alpha = 1 } end
    local timeline = Transition.EntranceTimeline
    local startTime = timeline.reportStart + math.max(0, (tonumber(index) or 1) - 1) * timeline.reportStagger
    local amount = easeOutCubic(progress(self.elapsed, startTime, timeline.reportDuration))
    return { offsetX = 22 * (1 - amount), alpha = amount }
end

function Entrance:GetButtonPose(index)
    if self:IsCatalogAssembled() then return { offsetY = 0, alpha = 1 } end
    local timeline = Transition.EntranceTimeline
    local startTime = timeline.buttonStart + math.max(0, (tonumber(index) or 1) - 1) * timeline.buttonStagger
    local amount = easeOutCubic(progress(self.elapsed, startTime, timeline.buttonDuration))
    return { offsetY = 10 * (1 - amount), alpha = amount }
end

function Transition.NewEntrance()
    return Entrance.New()
end

-- The catalog entrance samples the same top-hinge pose used by page changes.
-- Only the travel span is shortened so the incoming sheet reads as a placed
-- archive page rather than a second level-selection transition.
function Transition.GetEntrancePaperPose(amount, viewportWidth)
    local t = clamp(amount or 0, 0, 1)
    local mainEnd = 0.84
    local motion = 1 - easeOutCubic(t / mainEnd)
    local correction = easeOutCubic((t - mainEnd) / (1 - mainEnd))
    local angle = t < mainEnd
        and lerp(MAX_PIVOT_ANGLE, ENTRANCE_SETTLE_ANGLE, easeOutCubic(t / mainEnd))
        or lerp(ENTRANCE_SETTLE_ANGLE, 0, correction)
    local span = clamp((tonumber(viewportWidth) or 1) * 0.15, 80, 130)
    return {
        offsetX = span * motion,
        offsetY = (LIFT_OFFSET_Y - 50) * motion,
        rotation = angle,
        scale = 1 + (LIFT_SCALE - 1) * motion,
        alpha = 1,
        shadow = motion,
    }
end

local function easeWithdraw(value)
    value = clamp(value or 0, 0, 1)
    return value * value * (3 - 2 * value)
end

function Transition.New(initialIndex)
    local self = setmetatable({}, Transition)
    self.currentIndex = math.max(1, tonumber(initialIndex) or 1)
    self.outgoingIndex = nil
    self.incomingIndex = nil
    self.pendingIndex = nil
    self.direction = 1
    self.elapsed = 0
    self.state = Transition.State.IDLE
    return self
end

function Transition:Reset(index)
    self.currentIndex = math.max(1, tonumber(index) or self.currentIndex or 1)
    self.outgoingIndex, self.incomingIndex, self.pendingIndex = nil, nil, nil
    self.elapsed = 0
    self.state = Transition.State.IDLE
end

function Transition:_start(fromIndex, toIndex)
    if fromIndex == toIndex then
        self:Reset(toIndex)
        return false
    end
    self.currentIndex = fromIndex
    self.outgoingIndex = fromIndex
    self.incomingIndex = toIndex
    self.direction = toIndex > fromIndex and 1 or -1
    self.elapsed = 0
    self.state = Transition.State.PREPARING
    return true
end

function Transition:Request(targetIndex)
    targetIndex = math.max(1, tonumber(targetIndex) or self.currentIndex)
    if self.state == Transition.State.IDLE then
        return self:_start(self.currentIndex, targetIndex)
    end
    if targetIndex == self.pendingIndex then return false end

    -- Keep only the latest request. The currently prepared pair finishes once,
    -- then the latest target starts directly from the newly committed sheet.
    if targetIndex == self.incomingIndex then
        self.pendingIndex = nil
    else
        self.pendingIndex = targetIndex
    end
    return true
end

function Transition:Update(dt)
    dt = math.max(0, tonumber(dt) or 0)
    if self.state == Transition.State.IDLE then return end

    if self.state == Transition.State.PREPARING then
        -- Leave one complete render pass for the next sheet to settle below the
        -- outgoing sheet before any transform is applied.
        self.state = Transition.State.LIFTING
        self.elapsed = 0
        return
    end

    if self.state == Transition.State.COMMITTING then
        local committedIndex = self.incomingIndex or self.currentIndex
        local pending = self.pendingIndex
        self.currentIndex = committedIndex
        self.outgoingIndex, self.incomingIndex, self.pendingIndex = nil, nil, nil
        self.elapsed = 0
        self.state = Transition.State.IDLE
        if pending and pending ~= self.currentIndex then
            self:_start(self.currentIndex, pending)
        end
        return
    end

    self.elapsed = self.elapsed + dt
    if self.state == Transition.State.LIFTING and self.elapsed >= LIFT_END then
        self.state = Transition.State.WITHDRAWING
    end
    if self.elapsed >= WITHDRAW_END then
        self.elapsed = WITHDRAW_END
        self.state = Transition.State.COMMITTING
    end
end

function Transition:IsSettled()
    return self.state == Transition.State.IDLE and self.pendingIndex == nil
end

local function stationaryPose()
    return { offsetX = 0, offsetY = 0, rotation = 0, scale = 1, alpha = 1, shadow = 0 }
end

function Transition:GetPreviewPapers(viewportWidth)
    if self.state == Transition.State.IDLE then
        return { { index = self.currentIndex, pose = stationaryPose() } }
    end

    if self.state == Transition.State.COMMITTING then
        return { { index = self.incomingIndex or self.currentIndex, pose = stationaryPose() } }
    end

    local elapsed = self.elapsed
    local liftProgress = easeOutCubic(elapsed / LIFT_END)
    local pivotProgress = easeOutCubic((elapsed - ROTATE_START) / (ROTATE_END - ROTATE_START))
    local withdrawProgress = easeWithdraw((elapsed - LIFT_END) / (WITHDRAW_END - LIFT_END))
    local pivotAngle = MAX_PIVOT_ANGLE * pivotProgress
    local pullAngle = EXTRA_WITHDRAW_ANGLE * withdrawProgress
    local span = math.max(1, tonumber(viewportWidth) or 1) * 1.18

    local pose = {
        offsetX = -self.direction * span * withdrawProgress,
        offsetY = LIFT_OFFSET_Y * math.min(1, liftProgress) - 44 * withdrawProgress,
        rotation = self.direction * (pivotAngle + pullAngle),
        scale = 1 + (LIFT_SCALE - 1) * math.min(1, liftProgress),
        -- Kept at one for the entire animation. The paper must not fade out.
        alpha = 1,
        shadow = math.max(liftProgress, withdrawProgress),
    }
    return {
        -- Draw the next sheet first. It is present and stationary underneath.
        { index = self.incomingIndex, pose = stationaryPose() },
        -- The outgoing sheet is the only animated layer.
        { index = self.outgoingIndex, pose = pose },
    }
end

return Transition
