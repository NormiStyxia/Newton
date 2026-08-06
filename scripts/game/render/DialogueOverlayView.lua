local View = {}

local PANEL_ASPECT = 1343 / 2002
local PANEL_HEIGHT = 660
local PANEL_VISUAL_SCALE = 1.06
local FONT = "maker-body"
local NOMI_FONT = "nomi-font"
local AVATAR_SIZE = 68
local CONVERSATION_LEFT_INSET = 20
local CONVERSATION_RIGHT_INSET = 14
local CONVERSATION_TOP_RATIO = 0.132
local CONVERSATION_BOTTOM_RATIO = 0.836
local MESSAGE_ROW_LEFT_PADDING = 18
local AVATAR_COLUMN_WIDTH = 64
local BUBBLE_COLUMN_GAP = 8
local AVATAR_CENTER_Y_OFFSET = AVATAR_SIZE * 0.5
local SCROLLBAR_WIDTH = 9
local SCROLLBAR_RIGHT_INSET = 14
local SCROLLBAR_BUBBLE_GAP = 14
local SCROLLBAR_THUMB_SIZE = 28
local BODY_FONT_SIZE = 19
local NAME_FONT_SIZE = 16
local BODY_LINE_HEIGHT = 25
local BUBBLE_PADDING_X = 16
local BUBBLE_PADDING_TOP = 12
local BUBBLE_PADDING_BOTTOM = 12
local NAME_BUBBLE_GAP = 5
local MESSAGE_GAP = 14
local FOOTER_TOP_RATIO = 0.852
local FOOTER_CONTENT_LEFT_RATIO = 0.27
local FOOTER_CONTENT_RIGHT_RATIO = 0.86
local FOOTER_TITLE_SIZE = 22
local FOOTER_PERCENT_SIZE = 29
local ANGER_TRACK_HEIGHT = 20
local ANGER_APPLE_SIZE = 28
local ANGER_FOLLOW_SPEED = 12
local ANGER_PULSE_DURATION = 0.22

local LAYOUT_CACHE = setmetatable({}, { __mode = "k" })
local FOOTER_STATE = setmetatable({}, { __mode = "k" })

local function fontForMessage(message)
    if message and message.speaker == "nomi" then
        return NOMI_FONT
    end
    return FONT
end

local COLORS = {
    dark = { 47, 73, 56, 255 },
    body = { 64, 83, 68, 255 },
    muted = { 105, 120, 103, 255 },
    cream = { 226, 224, 216, 255 },
    creamStroke = { 140, 134, 126, 255 },
    greenBubble = { 211, 225, 218, 255 },
    greenStroke = { 106, 137, 128, 255 },
    avatarNewton = { 221, 210, 207, 255 },
    avatarGreen = { 201, 219, 211, 255 },
    avatarEinstein = { 216, 211, 224, 255 },
    avatarNomi = { 207, 220, 232, 255 },
    einsteinBubble = { 218, 214, 226, 255 },
    einsteinStroke = { 126, 119, 148, 255 },
    nomiBubble = { 211, 222, 233, 255 },
    nomiStroke = { 105, 127, 151, 255 },
    scrollTrack = { 79, 117, 72, 88 },
    scrollTrackInner = { 190, 211, 157, 82 },
    angerFill = { 217, 130, 118, 255 },
    angerFillHigh = { 187, 73, 67, 255 },
    angerTrack = { 231, 226, 189, 255 },
    history = { 47, 73, 56, 255 },
    historyHover = { 82, 117, 93, 255 },
    historyText = { 255, 253, 248, 255 },
    unread = { 220, 91, 72, 255 },
    buttonClose = { 218, 111, 94, 255 },
    buttonSkip = { 242, 207, 133, 255 },
    buttonStroke = { 76, 66, 45, 255 },
    buttonHighlight = { 255, 224, 174, 255 },
}

local function panelRect(frame)
    local height = math.min(PANEL_HEIGHT, frame.logicalHeight - 124)
    local width = height * PANEL_ASPECT
    return {
        x = math.max(16, frame.workspaceX - 28),
        y = math.max(88, frame.newtonY - 16),
        w = width,
        h = height,
    }
end

local function historyButtonRect(frame)
    return { x = frame.playfieldX + 135, y = 25, w = 132, h = 42 }
end

local function transformRect(rect, scale, centerX, centerY)
    return {
        x = centerX + (rect.x - centerX) * scale,
        y = centerY + (rect.y - centerY) * scale,
        w = rect.w * scale,
        h = rect.h * scale,
    }
end

local function applyCenteredScale(vg, scale, centerX, centerY)
    nvgTranslate(vg, centerX, centerY)
    nvgScale(vg, scale, scale)
    nvgTranslate(vg, -centerX, -centerY)
end

local function snapToPixel(value, pixelScale)
    pixelScale = math.max(0.001, pixelScale or 1)
    return math.floor(value * pixelScale + 0.5) / pixelScale
end

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function lerpColor(from, to, progress)
    return {
        math.floor(from[1] + (to[1] - from[1]) * progress + 0.5),
        math.floor(from[2] + (to[2] - from[2]) * progress + 0.5),
        math.floor(from[3] + (to[3] - from[3]) * progress + 0.5),
        math.floor((from[4] or 255) + ((to[4] or 255) - (from[4] or 255)) * progress + 0.5),
    }
end

local function elapsedSeconds()
    if GetTime then
        local clock = GetTime()
        if clock then return clock:GetElapsedTime() end
    end
    return os.clock()
end

local function updateFooterState(controller, targetProgress)
    local now = elapsedSeconds()
    local targetPercent = math.floor(targetProgress * 100 + 0.5)
    local state = FOOTER_STATE[controller]
    if not state then
        state = {
            displayedProgress = targetProgress,
            targetProgress = targetProgress,
            targetPercent = targetPercent,
            lastTime = now,
            pulseElapsed = ANGER_PULSE_DURATION,
        }
        FOOTER_STATE[controller] = state
        return state
    end

    local dt = clamp(now - state.lastTime, 0, 0.1)
    state.lastTime = now
    if math.abs(targetProgress - state.targetProgress) > 0.0001 then
        state.targetProgress = targetProgress
    end
    if targetPercent ~= state.targetPercent then
        state.targetPercent = targetPercent
        state.pulseElapsed = 0
    end

    local follow = 1 - math.exp(-ANGER_FOLLOW_SPEED * dt)
    state.displayedProgress = state.displayedProgress
        + (state.targetProgress - state.displayedProgress) * follow
    if math.abs(state.targetProgress - state.displayedProgress) < 0.0005 then
        state.displayedProgress = state.targetProgress
    end
    state.pulseElapsed = math.min(ANGER_PULSE_DURATION, state.pulseElapsed + dt)
    return state
end

local function utf8Length(value)
    local length = utf8.len(value)
    return length or #value
end

local function wrapText(painter, value, maxWidth, font, size)
    local vg = painter.vg
    painter:UseFont(font)
    nvgFontSize(vg, size)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)

    local lines = {}
    local line = ""
    for _, codepoint in utf8.codes(value or "") do
        local character = utf8.char(codepoint)
        if character == "\n" then
            lines[#lines + 1] = line
            line = ""
        else
            local candidate = line .. character
            local measured = nvgTextBounds(vg, 0, 0, candidate, nil)
            if type(measured) ~= "number" then measured = utf8Length(candidate) * size * 0.92 end
            if line ~= "" and measured > maxWidth then
                lines[#lines + 1] = line
                line = character
            else
                line = candidate
            end
        end
    end
    if line ~= "" or #lines == 0 then lines[#lines + 1] = line end
    return lines
end

local function layoutMessages(painter, messages, viewport)
    local bubbleWidth = viewport.bubbleW
    local entries = {}
    local cursorY = 6

    for index = 1, #messages do
        local message = messages[index]
        if message.style == "SYSTEM" then
            entries[index] = { y = cursorY, h = 32, system = true, message = message }
            cursorY = cursorY + 42
        else
            local font = fontForMessage(message)
            local lines = wrapText(painter, message.text or "",
                bubbleWidth - BUBBLE_PADDING_X * 2, font, BODY_FONT_SIZE)
            local textHeight = BODY_FONT_SIZE + math.max(0, #lines - 1) * BODY_LINE_HEIGHT
            local bubbleHeight = BUBBLE_PADDING_TOP + textHeight + BUBBLE_PADDING_BOTTOM
            local bubbleOffsetY = NAME_FONT_SIZE + NAME_BUBBLE_GAP
            local contentHeight = bubbleOffsetY + bubbleHeight
            local avatarHeight = AVATAR_CENTER_Y_OFFSET + AVATAR_SIZE * 0.5
            local rowHeight = math.max(contentHeight, avatarHeight) + MESSAGE_GAP
            entries[index] = {
                y = cursorY,
                h = rowHeight,
                bubbleW = bubbleWidth,
                bubbleH = bubbleHeight,
                bubbleOffsetY = bubbleOffsetY,
                lines = lines,
                font = font,
                message = message,
            }
            cursorY = cursorY + rowHeight
        end
    end
    return entries, math.max(0, cursorY - 3)
end

local function cachedLayout(painter, controller, messages, viewport)
    local widthKey = math.floor(viewport.bubbleW * 1000 + 0.5)
    local messageCount = #messages
    local cache = LAYOUT_CACHE[controller]
    if cache and cache.messages == messages and cache.messageCount == messageCount
        and cache.widthKey == widthKey then
        return cache.entries
    end

    local entries = layoutMessages(painter, messages, viewport)
    LAYOUT_CACHE[controller] = {
        messages = messages,
        messageCount = messageCount,
        widthKey = widthKey,
        entries = entries,
    }
    return entries
end

local function visibleContentHeight(entries, visibleCount)
    if visibleCount <= 0 then return 0 end
    local last = entries[visibleCount]
    if not last then return 0 end
    return math.max(0, last.y + last.h - 3)
end

local function drawHistoryIcon(painter, x, y, color)
    local vg = painter.vg
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x - 8, y - 7, 16, 12, 3)
    nvgStrokeColor(vg, nvgRGBA(color[1], color[2], color[3], color[4]))
    nvgStrokeWidth(vg, 1.8)
    nvgStroke(vg)
    nvgBeginPath(vg)
    nvgMoveTo(vg, x - 3, y + 5)
    nvgLineTo(vg, x - 6, y + 9)
    nvgLineTo(vg, x + 1, y + 5)
    nvgStroke(vg)
end

function View.DrawHistoryButton(painter, frame, controller)
    if not painter or not frame or not controller:IsHistoryAvailable() then
        if controller then controller:SetHistoryButtonGeometry(nil) end
        return
    end
    local rect = historyButtonRect(frame)
    controller:SetHistoryButtonGeometry(rect)
    local fill = controller.historyHovered and COLORS.historyHover or COLORS.history
    painter:RoundedRect(rect.x, rect.y, rect.w, rect.h, 5, fill, COLORS.creamStroke, 1.5)
    drawHistoryIcon(painter, rect.x + 22, rect.y + rect.h * 0.5, COLORS.historyText)
    painter:Text(rect.x + 39, rect.y + 10, "通讯记录", 17, COLORS.historyText,
        NVG_ALIGN_LEFT + NVG_ALIGN_TOP, FONT)
    if controller:HasUnread() then
        painter:Circle(rect.x + rect.w - 8, rect.y + 8, 5, COLORS.unread, COLORS.cream, 1.5)
    end
end

local function drawPanelBackground(painter, rect)
    local image = painter.images.ui and painter.images.ui.dialoguePanel
    if image and image >= 0 then
        painter:ImageRect(image, rect.x, rect.y, rect.w, rect.h, 1)
    else
        painter:RoundedRect(rect.x, rect.y, rect.w, rect.h, 6, COLORS.cream, COLORS.dark, 2)
    end
end

local function buttonRect(rect)
    return {
        x = rect.x + rect.w * 0.60,
        y = rect.y + rect.h * 0.057,
        w = rect.w * 0.22,
        h = rect.h * 0.058,
    }
end

local function conversationGeometry(rect)
    local viewport = {
        x = rect.x + CONVERSATION_LEFT_INSET,
        y = rect.y + rect.h * CONVERSATION_TOP_RATIO,
        w = rect.w - CONVERSATION_LEFT_INSET - CONVERSATION_RIGHT_INSET,
        h = rect.h * (CONVERSATION_BOTTOM_RATIO - CONVERSATION_TOP_RATIO),
    }
    local track = {
        x = rect.x + rect.w - SCROLLBAR_RIGHT_INSET - SCROLLBAR_WIDTH,
        y = viewport.y + 12,
        w = SCROLLBAR_WIDTH,
        h = viewport.h - 24,
    }
    local avatarLeft = viewport.x + MESSAGE_ROW_LEFT_PADDING
    viewport.avatarCenterX = avatarLeft + AVATAR_SIZE * 0.5
    viewport.bubbleX = avatarLeft + AVATAR_COLUMN_WIDTH + BUBBLE_COLUMN_GAP
    viewport.bubbleW = math.max(80, track.x - SCROLLBAR_BUBBLE_GAP - viewport.bubbleX)
    return viewport, track
end

local function drawButtonGlyph(painter, rect, kind)
    local vg = painter.vg
    nvgBeginPath(vg)
    nvgStrokeColor(vg, nvgRGBA(COLORS.buttonStroke[1], COLORS.buttonStroke[2],
        COLORS.buttonStroke[3], COLORS.buttonStroke[4]))
    nvgStrokeWidth(vg, 2)
    if kind == "close" then
        local centerX = rect.x + rect.w * 0.8
        local centerY = rect.y + rect.h * 0.5
        local radius = math.min(6, rect.h * 0.17)
        nvgMoveTo(vg, centerX - radius, centerY - radius)
        nvgLineTo(vg, centerX + radius, centerY + radius)
        nvgMoveTo(vg, centerX + radius, centerY - radius)
        nvgLineTo(vg, centerX - radius, centerY + radius)
    else
        local startX = rect.x + rect.w * 0.75
        local centerY = rect.y + rect.h * 0.5
        local radius = math.min(6, rect.h * 0.17)
        for offset = 0, radius * 1.05, radius * 1.05 do
            nvgMoveTo(vg, startX + offset - radius * 0.55, centerY - radius)
            nvgLineTo(vg, startX + offset + radius * 0.45, centerY)
            nvgLineTo(vg, startX + offset - radius * 0.55, centerY + radius)
        end
    end
    nvgStroke(vg)
end

local function drawPanelButton(painter, rect, kind)
    local fill = kind == "close" and COLORS.buttonClose or COLORS.buttonSkip
    local radius = math.min(8, rect.h * 0.24)
    painter:RoundedRect(rect.x, rect.y, rect.w, rect.h, radius,
        fill, COLORS.buttonStroke, 2.5)
    painter:RoundedRect(rect.x + 3, rect.y + 3, rect.w - 6, rect.h - 6,
        math.max(2, radius - 3), nil, COLORS.buttonHighlight, 1)
    painter:Text(rect.x + rect.w * 0.42, rect.y + rect.h * 0.5,
        kind == "close" and "关闭" or "跳过", 16, COLORS.buttonStroke,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, FONT)
    drawButtonGlyph(painter, rect, kind)
end

local function drawMessage(painter, controller, entry, index, viewport, scrollOffset, panelAlpha, pixelScale)
    local message = entry.message
    local reveal = controller:GetBubbleProgress(index)
    if reveal <= 0 then return end
    local y = snapToPixel(viewport.y + entry.y - scrollOffset, pixelScale)
    if y + entry.h < viewport.y - 4 or y > viewport.y + viewport.h + 4 then return end

    local vg = painter.vg
    local xOffset = snapToPixel(-12 * (1 - reveal), pixelScale)
    nvgSave(vg)
    nvgGlobalAlpha(vg, panelAlpha * reveal)

    if entry.system then
        local systemX = snapToPixel(viewport.x + viewport.w * 0.5 + xOffset, pixelScale)
        painter:Text(systemX, snapToPixel(y + 8, pixelScale), message.text or "", 13,
            { 161, 133, 73, 255 }, NVG_ALIGN_CENTER + NVG_ALIGN_TOP, FONT)
        nvgRestore(vg)
        return
    end

    local speaker = message.speaker or (message.style == "GREEN" and "green" or "newton")
    local isGreen = speaker == "green"
    local isEinstein = speaker == "einstein"
    local isNomi = speaker == "nomi"
    local messageFont = entry.font or (isNomi and NOMI_FONT or FONT)
    local avatarX = snapToPixel(viewport.avatarCenterX + xOffset, pixelScale)
    local avatarY = snapToPixel(y + AVATAR_CENTER_Y_OFFSET, pixelScale)
    local bubbleX = snapToPixel(viewport.bubbleX + xOffset, pixelScale)
    local nameY = y
    local bubbleY = snapToPixel(y + entry.bubbleOffsetY, pixelScale)
    local bubbleWidth = snapToPixel(entry.bubbleW, pixelScale)
    local bubbleHeight = snapToPixel(entry.bubbleH, pixelScale)
    local bubbleFill = isGreen and COLORS.greenBubble
        or (isEinstein and COLORS.einsteinBubble or (isNomi and COLORS.nomiBubble or COLORS.cream))
    local bubbleStroke = isGreen and COLORS.greenStroke
        or (isEinstein and COLORS.einsteinStroke or (isNomi and COLORS.nomiStroke or COLORS.creamStroke))
    local avatarFill = isGreen and COLORS.avatarGreen
        or (isEinstein and COLORS.avatarEinstein or (isNomi and COLORS.avatarNomi or COLORS.avatarNewton))
    local avatarImage = painter.images.ui and painter.images.ui.dialogueAvatars
        and painter.images.ui.dialogueAvatars[speaker]
    if avatarImage and avatarImage >= 0 then
        painter:Image(avatarImage, avatarX, avatarY, AVATAR_SIZE, AVATAR_SIZE, 1, nil, 0.5, 0.5)
    else
        painter:Circle(avatarX, avatarY, AVATAR_SIZE * 0.48, avatarFill, bubbleStroke, 2)
        painter:Text(avatarX, avatarY, message.avatarText or "?", 17, COLORS.dark,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, messageFont)
    end
    painter:Text(bubbleX, nameY, message.displayName or "", NAME_FONT_SIZE, COLORS.dark,
        NVG_ALIGN_LEFT + NVG_ALIGN_TOP, messageFont)
    painter:RoundedRect(bubbleX, bubbleY, bubbleWidth, bubbleHeight, 7, bubbleFill, bubbleStroke, 1.5)
    for lineIndex, line in ipairs(entry.lines) do
        local lineY = bubbleY + BUBBLE_PADDING_TOP + (lineIndex - 1) * BODY_LINE_HEIGHT
        painter:Text(snapToPixel(bubbleX + BUBBLE_PADDING_X, pixelScale),
            snapToPixel(lineY, pixelScale), line, BODY_FONT_SIZE, COLORS.body,
            NVG_ALIGN_LEFT + NVG_ALIGN_TOP, messageFont)
    end
    nvgRestore(vg)
end

local function drawScrollbar(painter, track, thumbY, thumbSize, scrollable)
    if not scrollable then return end
    painter:RoundedRect(track.x, track.y, track.w, track.h, track.w * 0.5, COLORS.scrollTrack)
    painter:RoundedRect(track.x + 3, track.y + 3, track.w - 6, track.h - 6,
        math.max(1, (track.w - 6) * 0.5), COLORS.scrollTrackInner)
    local apple = painter.images.apple
    if apple and apple >= 0 then
        painter:Image(apple, track.x + track.w * 0.5, thumbY + thumbSize * 0.5, thumbSize, thumbSize, 1)
    else
        painter:Circle(track.x + track.w * 0.5, thumbY + thumbSize * 0.5, thumbSize * 0.45,
            COLORS.unread, COLORS.dark, 1.5)
    end
end

local function drawAngerFooter(painter, rect, model, controller, pixelScale)
    local anger = clamp(model.anger or 0, 0, model.maxAnger or 0)
    local targetProgress = model.maxAnger > 0 and anger / model.maxAnger or 0
    local state = updateFooterState(controller, targetProgress)
    local progress = clamp(state.displayedProgress, 0, 1)
    local footerY = rect.y + rect.h * FOOTER_TOP_RATIO
    local contentLeft = rect.x + rect.w * FOOTER_CONTENT_LEFT_RATIO
    local contentRight = rect.x + rect.w * FOOTER_CONTENT_RIGHT_RATIO
    local labelY = footerY + 12
    local pulseProgress = clamp(state.pulseElapsed / ANGER_PULSE_DURATION, 0, 1)
    local percentScale = 1 + math.sin(pulseProgress * math.pi) * 0.07

    painter:Text(contentLeft, labelY, "牛顿怒气", FOOTER_TITLE_SIZE, COLORS.dark,
        NVG_ALIGN_LEFT + NVG_ALIGN_TOP, FONT)
    painter:Text(contentRight, labelY - 2,
        string.format("%d%%", math.floor(progress * 100 + 0.5)),
        FOOTER_PERCENT_SIZE * percentScale, COLORS.unread,
        NVG_ALIGN_RIGHT + NVG_ALIGN_TOP, FONT)

    local track = {
        x = contentLeft + ANGER_APPLE_SIZE * 0.5,
        y = footerY + 54,
        w = math.max(80, contentRight - contentLeft - ANGER_APPLE_SIZE),
        h = ANGER_TRACK_HEIGHT,
    }
    painter:RoundedRect(track.x, track.y, track.w, track.h, track.h * 0.5,
        COLORS.angerTrack, COLORS.creamStroke, 1.5)
    if progress > 0.001 then
        local fillWidth = track.w * progress
        local fill = lerpColor(COLORS.angerFill, COLORS.angerFillHigh, progress)
        painter:RoundedRect(track.x, track.y, fillWidth, track.h,
            math.min(track.h * 0.5, fillWidth * 0.5), fill)
    end

    local appleCenterX = snapToPixel(track.x + track.w * progress, pixelScale)
    local appleCenterY = snapToPixel(track.y + track.h * 0.5, pixelScale)
    local apple = painter.images.apple
    if apple and apple >= 0 then
        painter:Image(apple, appleCenterX, appleCenterY,
            ANGER_APPLE_SIZE, ANGER_APPLE_SIZE, 1)
    else
        painter:Circle(appleCenterX, appleCenterY, ANGER_APPLE_SIZE * 0.43,
            COLORS.unread, COLORS.creamStroke, 1.5)
    end
end

function View.Draw(painter, frame, controller)
    local model = controller:GetRenderModel()
    local presentationScale, panelAlpha = controller:GetPanelPresentation()
    if panelAlpha <= 0 then return end
    local contentScale = PANEL_VISUAL_SCALE
    local backgroundScale = presentationScale * PANEL_VISUAL_SCALE

    local rect = panelRect(frame)
    local centerX, centerY = rect.x + rect.w * 0.5, rect.y + rect.h * 0.5
    local button = buttonRect(rect)
    local viewport, track = conversationGeometry(rect)
    local thumbSize = SCROLLBAR_THUMB_SIZE
    local entries = cachedLayout(painter, controller, model.messages, viewport)
    local contentHeight = visibleContentHeight(entries, model.visibleCount)
    controller:SetScrollMetrics(contentHeight, viewport.h)
    model.scrollOffset = controller.scrollOffset
    model.maxScroll = controller.maxScroll
    local thumbY = track.y + controller:GetScrollProgress() * (track.h - thumbSize)
    local thumb = { x = track.x + track.w * 0.5 - thumbSize * 0.5, y = thumbY, w = thumbSize, h = thumbSize }

    controller:SetViewGeometry({
        button = transformRect(button, contentScale, centerX, centerY),
        viewport = transformRect(viewport, contentScale, centerX, centerY),
        track = transformRect({ x = track.x - 11, y = track.y, w = 31, h = track.h },
            contentScale, centerX, centerY),
        thumb = transformRect(thumb, contentScale, centerX, centerY),
    })

    local vg = painter.vg
    local revealScale = math.max(0, math.min(1, presentationScale))
    local animatedClip = transformRect(rect, revealScale, centerX, centerY)
    local pixelScale = math.max(0.001,
        (frame.dpr or 1) * (frame.renderScale or 1) * contentScale)

    -- The panel keeps the established center-scale animation.
    nvgSave(vg)
    applyCenteredScale(vg, backgroundScale, centerX, centerY)
    nvgGlobalAlpha(vg, panelAlpha)
    drawPanelBackground(painter, rect)
    nvgRestore(vg)

    -- Header, conversation, scrollbar overlay, and footer use final coordinates.
    -- Only scrolling message rows are clipped by the conversation viewport.
    nvgSave(vg)
    applyCenteredScale(vg, contentScale, centerX, centerY)
    nvgGlobalAlpha(vg, panelAlpha)
    nvgIntersectScissor(vg, animatedClip.x, animatedClip.y, animatedClip.w, animatedClip.h)
    drawPanelButton(painter, button, model.buttonKind)

    nvgSave(vg)
    nvgIntersectScissor(vg, viewport.x, viewport.y, viewport.w, viewport.h)
    for index = 1, model.visibleCount do
        local entry = entries[index]
        if entry then
            drawMessage(painter, controller, entry, index, viewport,
                model.scrollOffset, panelAlpha, pixelScale)
        end
    end
    nvgRestore(vg)

    drawScrollbar(painter, track, thumbY, thumbSize, model.maxScroll > 0)
    drawAngerFooter(painter, rect, model, controller, pixelScale)
    nvgRestore(vg)
end

return View
