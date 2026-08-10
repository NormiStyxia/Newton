local RuleArchiveOverlay = {}
RuleArchiveOverlay.__index = RuleArchiveOverlay

local CARD_LIMIT = 6
local OPEN_CARD_DURATION = .32
local OPEN_STAGGER = .058
local CLOSE_CARD_DURATION = .24
local CLOSE_STAGGER = .03
local MASK_DURATION = .16
local FOCUS_DURATION = .11
local MAX_BASE_SCALE = 1.82
local MAX_INTERACTION_SCALE = 1.12
local MAX_LIFT = 32

local CARD_ANGLES = { -5, -3, -1, 1, 3, 5 }
local CARD_ARC_OFFSETS = { 13, 6, 1, 1, 6, 13 }

local COLORS = {
    mask = { 25, 42, 31, 255 },
    paper = { 247, 239, 211, 255 },
    brass = { 220, 198, 126, 255 },
    shadow = { 20, 34, 25, 255 },
}

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function lerp(from, to, amount)
    return from + (to - from) * amount
end

local function easeOutCubic(value)
    value = clamp(value, 0, 1)
    return 1 - (1 - value) ^ 3
end

local function easeInCubic(value)
    value = clamp(value, 0, 1)
    return value ^ 3
end

local function pointIn(rect, x, y)
    return x >= rect.x and x <= rect.x + rect.w and y >= rect.y and y <= rect.y + rect.h
end

local function orderedCards(rules)
    local result, seen = {}, {}
    for _, id in ipairs(rules.CARD_ORDER or {}) do
        if rules.CARDS[id] and not seen[id] and #result < CARD_LIMIT then
            result[#result + 1] = { id = id, definition = rules.CARDS[id] }
            seen[id] = true
        end
    end
    if #result >= CARD_LIMIT then return result end

    local remaining = {}
    for id, definition in pairs(rules.CARDS or {}) do
        if not seen[id] then remaining[#remaining + 1] = { id = id, definition = definition } end
    end
    table.sort(remaining, function(a, b)
        local kindA = a.definition.kind == "field" and 1 or 2
        local kindB = b.definition.kind == "field" and 1 or 2
        if kindA ~= kindB then return kindA < kindB end
        return a.id < b.id
    end)
    for _, entry in ipairs(remaining) do
        if #result >= CARD_LIMIT then break end
        result[#result + 1] = entry
    end
    return result
end

function RuleArchiveOverlay.New(options)
    local self = setmetatable({}, RuleArchiveOverlay)
    self:init(options or {})
    return self
end

function RuleArchiveOverlay:init(options)
    self.rules = assert(options.rules, "RuleArchiveOverlay requires rules")
    self.cardWidth = tonumber(options.cardWidth) or 124
    self.cardHeight = tonumber(options.cardHeight) or 202
    self.drawCard = options.drawCard
    self.onFeedback = options.onFeedback
    self.cards = orderedCards(self.rules)
    self.phase = "closed"
    self.phaseElapsed = 0
    self.selectedIndex = nil
    self.hoveredIndex = nil
    self.focus = {}
    for index = 1, #self.cards do self.focus[index] = 0 end
end

function RuleArchiveOverlay:Reset()
    self.phase = "closed"
    self.phaseElapsed = 0
    self.closingOpeningElapsed = nil
    self.selectedIndex = nil
    self.hoveredIndex = nil
    for index = 1, #self.cards do self.focus[index] = 0 end
end

function RuleArchiveOverlay:IsVisible()
    return self.phase ~= "closed"
end

function RuleArchiveOverlay:IsOpen()
    return self.phase == "open"
end

function RuleArchiveOverlay:GetCardCount()
    return #self.cards
end

function RuleArchiveOverlay:Open()
    if self.phase ~= "closed" then return false end
    if #self.cards == 0 then return false end
    self.phase = "opening"
    self.phaseElapsed = 0
    self.closingOpeningElapsed = nil
    self.selectedIndex = nil
    self.hoveredIndex = nil
    return true
end

function RuleArchiveOverlay:Close()
    if self.phase == "closed" or self.phase == "closing" then return false end
    self.closingOpeningElapsed = self.phase == "opening" and self.phaseElapsed or nil
    self.phase = "closing"
    self.phaseElapsed = 0
    self.hoveredIndex = nil
    return true
end

function RuleArchiveOverlay:Toggle()
    if self:IsVisible() then return self:Close() end
    return self:Open()
end

function RuleArchiveOverlay:ResolveLayout(frame)
    local count = math.max(1, #self.cards)
    local gap = 18
    local titleY = clamp(frame.logicalHeight * .10, 68, 92)
    local cardsTop = math.max(titleY + 100, frame.logicalHeight * .235)
    local cardsBottom = frame.logicalHeight - 45
    local availableWidth = math.max(480, math.min(1660, frame.logicalWidth - 100))
    local widthScale = (availableWidth - gap * (count - 1)) / (self.cardWidth * count)
    local maxAngle = math.rad(5)
    local interactionHeight = (self.cardHeight * math.cos(maxAngle)
        + self.cardWidth * math.sin(maxAngle)) * MAX_INTERACTION_SCALE
    local heightScale = (cardsBottom - cardsTop - MAX_LIFT - 26) / interactionHeight
    local scale = math.min(MAX_BASE_SCALE, widthScale, heightScale)
    scale = math.max(.72, scale)
    local cardWidth = self.cardWidth * scale
    local cardHeight = self.cardHeight * scale
    local spacing = cardWidth + gap
    local totalWidth = cardWidth * count + gap * (count - 1)
    local centerX = frame.logicalWidth * .5
    local interactionHalfHeight = interactionHeight * scale * .5
    local centerY = clamp(frame.logicalHeight * .59,
        cardsTop + MAX_LIFT + interactionHalfHeight,
        cardsBottom - interactionHalfHeight - 13)
    local startX = centerX - totalWidth * .5 + cardWidth * .5
    local cards = {}
    for index = 1, #self.cards do
        cards[index] = {
            x = startX + (index - 1) * spacing,
            y = centerY + (CARD_ARC_OFFSETS[index] or 0),
            angle = CARD_ANGLES[index] or 0,
            scale = scale,
        }
    end
    return {
        centerX = centerX,
        titleY = titleY,
        dealX = centerX,
        dealY = math.min(frame.logicalHeight - cardHeight * .44,
            centerY + cardHeight * .42),
        cardWidth = cardWidth,
        cardHeight = cardHeight,
        cards = cards,
    }
end

function RuleArchiveOverlay:_openDuration()
    return OPEN_CARD_DURATION + math.max(0, #self.cards - 1) * OPEN_STAGGER
end

function RuleArchiveOverlay:_closeDuration()
    return CLOSE_CARD_DURATION + math.max(0, #self.cards - 1) * CLOSE_STAGGER
end

function RuleArchiveOverlay:_maskProgress()
    if self.phase == "closed" then return 0 end
    if self.phase == "opening" then return clamp(self.phaseElapsed / MASK_DURATION, 0, 1) end
    if self.phase == "closing" then
        local fadeStart = math.max(0, self:_closeDuration() - MASK_DURATION)
        return 1 - clamp((self.phaseElapsed - fadeStart) / MASK_DURATION, 0, 1)
    end
    return 1
end

function RuleArchiveOverlay:_openingPose(index, layout, elapsed)
    local target = layout.cards[index]
    local delay = (index - 1) * OPEN_STAGGER
    local linear = clamp(((elapsed or 0) - delay) / OPEN_CARD_DURATION, 0, 1)
    local eased = easeOutCubic(linear)
    return {
        x = lerp(layout.dealX, target.x, eased),
        y = lerp(layout.dealY, target.y, eased),
        angle = target.angle * eased,
        scale = target.scale * (.88 + .12 * eased),
        alpha = clamp(linear * 3.2, 0, 1),
    }
end

function RuleArchiveOverlay:_basePose(index, layout)
    local target = layout.cards[index]
    if self.phase == "opening" then
        return self:_openingPose(index, layout, self.phaseElapsed)
    end
    if self.phase == "closing" then
        local delay = (#self.cards - index) * CLOSE_STAGGER
        local linear = clamp((self.phaseElapsed - delay) / CLOSE_CARD_DURATION, 0, 1)
        local eased = easeInCubic(linear)
        local origin = self.closingOpeningElapsed
            and self:_openingPose(index, layout, self.closingOpeningElapsed)
            or { x = target.x, y = target.y, angle = target.angle, scale = target.scale, alpha = 1 }
        return {
            x = lerp(origin.x, layout.dealX, eased),
            y = lerp(origin.y, layout.dealY + 18, eased),
            angle = origin.angle * (1 - eased),
            scale = origin.scale * (1 - .12 * eased),
            alpha = origin.alpha * (1 - clamp((linear - .68) / .32, 0, 1)),
        }
    end
    return {
        x = target.x,
        y = target.y,
        angle = target.angle,
        scale = target.scale,
        alpha = 1,
    }
end

function RuleArchiveOverlay:_pose(index, layout)
    local pose = self:_basePose(index, layout)
    local focus = self.focus[index] or 0
    local selected = self.selectedIndex == index
    pose.y = pose.y - focus * 14 - (selected and 18 or 0)
    pose.scale = pose.scale * (1 + focus * .045 + (selected and .075 or 0))
    pose.angle = pose.angle * (1 - focus * .58 - (selected and .22 or 0))
    return pose
end

function RuleArchiveOverlay:_cardRect(pose)
    local width = self.cardWidth * pose.scale
    local height = self.cardHeight * pose.scale
    return { x = pose.x - width * .5, y = pose.y - height * .5, w = width, h = height }
end

function RuleArchiveOverlay:_hitTest(layout, x, y)
    local selected = self.selectedIndex
    if selected then
        local pose = self:_pose(selected, layout)
        if pose.alpha > .35 and pointIn(self:_cardRect(pose), x, y) then return selected end
    end
    for index = #self.cards, 1, -1 do
        if index ~= selected then
            local pose = self:_pose(index, layout)
            if pose.alpha > .35 and pointIn(self:_cardRect(pose), x, y) then return index end
        end
    end
    return nil
end

function RuleArchiveOverlay:Update(dt, pointerX, pointerY, frame)
    if self.phase == "closed" then return end
    dt = math.max(0, tonumber(dt) or 0)
    self.phaseElapsed = self.phaseElapsed + dt
    if self.phase == "opening" and self.phaseElapsed >= self:_openDuration() then
        self.phase = "open"
        self.phaseElapsed = 0
    elseif self.phase == "closing" and self.phaseElapsed >= self:_closeDuration() then
        self:Reset()
        return
    end

    local layout = self:ResolveLayout(frame)
    self.hoveredIndex = self.phase ~= "closing"
        and self:_hitTest(layout, pointerX or -10000, pointerY or -10000) or nil
    local step = clamp(dt / FOCUS_DURATION, 0, 1)
    for index = 1, #self.cards do
        local target = (self.hoveredIndex == index or self.selectedIndex == index) and 1 or 0
        self.focus[index] = lerp(self.focus[index] or 0, target, step)
    end
end

function RuleArchiveOverlay:HandlePointer(pointerFrame, frame)
    if not self:IsVisible() then return false end
    if not pointerFrame.pressed or self.phase == "closing" then return true end
    local layout = self:ResolveLayout(frame)
    local index = self:_hitTest(layout, pointerFrame.x, pointerFrame.y)
    if index then
        self.selectedIndex = self.selectedIndex == index and nil or index
        if self.onFeedback then self.onFeedback() end
        return true
    end
    if self:Close() and self.onFeedback then self.onFeedback() end
    return true
end

function RuleArchiveOverlay:Draw(painter, frame)
    if not self:IsVisible() then return end
    local maskProgress = self:_maskProgress()
    painter:FillRect(0, 0, frame.logicalWidth, frame.logicalHeight,
        COLORS.mask, math.floor(142 * maskProgress))

    local layout = self:ResolveLayout(frame)
    local titleAlpha = math.floor(255 * maskProgress)
    painter:Text(layout.centerX, layout.titleY, "规则档案", 42, COLORS.paper,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, "maker-display", titleAlpha)
    painter:Text(layout.centerX - 140, layout.titleY, "✦", 20, COLORS.brass,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, "report-green", titleAlpha)
    painter:Text(layout.centerX + 140, layout.titleY, "✦", 20, COLORS.brass,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, "report-green", titleAlpha)

    local drawOrder = {}
    for index = 1, #self.cards do drawOrder[index] = index end
    table.sort(drawOrder, function(a, b)
        local priorityA = self.selectedIndex == a and 2 or self.hoveredIndex == a and 1 or 0
        local priorityB = self.selectedIndex == b and 2 or self.hoveredIndex == b and 1 or 0
        if priorityA ~= priorityB then return priorityA < priorityB end
        return a < b
    end)

    for _, index in ipairs(drawOrder) do
        local entry = self.cards[index]
        local pose = self:_pose(index, layout)
        if pose.alpha > .001 then
            local alpha = pose.alpha * maskProgress
            nvgSave(painter.vg)
            nvgTranslate(painter.vg, pose.x, pose.y)
            nvgRotate(painter.vg, math.rad(pose.angle))
            nvgScale(painter.vg, pose.scale, pose.scale)
            painter:RoundedRect(-self.cardWidth * .5 + 3, -self.cardHeight * .5 + 5,
                self.cardWidth, self.cardHeight, 7, COLORS.shadow, nil, nil,
                math.floor(42 * alpha))
            if self.drawCard then
                self.drawCard(entry.id, entry.definition, {
                    cardId = entry.id,
                    usageMode = "REUSABLE",
                    count = 1,
                }, self.selectedIndex == index, (self.focus[index] or 0) > .15,
                    alpha, { hideUsage = true })
            else
                local image = painter.images and painter.images.ui and painter.images.ui.cardFaces
                    and painter.images.ui.cardFaces[entry.id]
                if image and image >= 0 then
                    painter:Image(image, 0, 0, self.cardWidth, self.cardHeight, alpha)
                end
            end
            nvgRestore(painter.vg)
        end
    end
end

return RuleArchiveOverlay
