local View = {}

local PANEL_ASPECT = 1343 / 2002
local PANEL_HEIGHT = 660
local FONT = "maker-body"
local MESSAGE_RIGHT_RATIO = 0.70
local SCROLLBAR_CENTER_RATIO = 0.75
local FOOTER_RIGHT_RATIO = 0.82

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
    track = { 79, 117, 72, 255 },
    trackInner = { 190, 211, 157, 255 },
    angerFill = { 217, 130, 118, 255 },
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

local function layoutMessages(painter, messages, visibleCount, viewport)
    local bubbleWidth = math.max(120, viewport.w - 55)
    local entries = {}
    local cursorY = 6
    local font = FONT

    for index = 1, visibleCount do
        local message = messages[index]
        if message.style == "SYSTEM" then
            entries[index] = { y = cursorY, h = 32, system = true, message = message }
            cursorY = cursorY + 42
        else
            local lines = wrapText(painter, message.text or "", bubbleWidth - 28, font, 16)
            local bubbleHeight = 38 + #lines * 22
            local rowHeight = math.max(48, bubbleHeight) + 13
            entries[index] = {
                y = cursorY,
                h = rowHeight,
                bubbleW = bubbleWidth,
                bubbleH = bubbleHeight,
                lines = lines,
                message = message,
            }
            cursorY = cursorY + rowHeight
        end
    end
    return entries, math.max(0, cursorY - 3)
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
    painter:Text(rect.x + 39, rect.y + 11, "通讯记录", 15, COLORS.historyText,
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

local function drawMessage(painter, controller, entry, index, viewport, scrollOffset, panelAlpha)
    local message = entry.message
    local reveal = controller:GetBubbleProgress(index)
    if reveal <= 0 then return end
    local y = viewport.y + entry.y - scrollOffset
    if y + entry.h < viewport.y - 4 or y > viewport.y + viewport.h + 4 then return end

    local vg = painter.vg
    local xOffset = -12 * (1 - reveal)
    nvgSave(vg)
    nvgGlobalAlpha(vg, panelAlpha * reveal)

    if entry.system then
        painter:Text(viewport.x + viewport.w * 0.5 + xOffset, y + 8, message.text or "", 13,
            { 161, 133, 73, 255 }, NVG_ALIGN_CENTER + NVG_ALIGN_TOP, FONT)
        nvgRestore(vg)
        return
    end

    local speaker = message.speaker or (message.style == "GREEN" and "green" or "newton")
    local isGreen = speaker == "green"
    local isEinstein = speaker == "einstein"
    local isNomi = speaker == "nomi"
    local avatarX = viewport.x + 23 + xOffset
    local avatarY = y + 25
    local bubbleX = viewport.x + 55 + xOffset
    local bubbleFill = isGreen and COLORS.greenBubble
        or (isEinstein and COLORS.einsteinBubble or (isNomi and COLORS.nomiBubble or COLORS.cream))
    local bubbleStroke = isGreen and COLORS.greenStroke
        or (isEinstein and COLORS.einsteinStroke or (isNomi and COLORS.nomiStroke or COLORS.creamStroke))
    local avatarFill = isGreen and COLORS.avatarGreen
        or (isEinstein and COLORS.avatarEinstein or (isNomi and COLORS.avatarNomi or COLORS.avatarNewton))
    local avatarImage = painter.images.ui and painter.images.ui.dialogueAvatars
        and painter.images.ui.dialogueAvatars[speaker]
    if avatarImage and avatarImage >= 0 then
        painter:Image(avatarImage, avatarX, avatarY, 44, 44, 1, nil, 0.5, 0.5)
    else
        painter:Circle(avatarX, avatarY, 21, avatarFill, bubbleStroke, 2)
        painter:Text(avatarX, avatarY, message.avatarText or "?", 17, COLORS.dark,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, FONT)
    end
    painter:RoundedRect(bubbleX, y, entry.bubbleW, entry.bubbleH, 7, bubbleFill, bubbleStroke, 1.5)
    painter:Text(bubbleX + 14, y + 9, message.displayName or "", 15, COLORS.dark,
        NVG_ALIGN_LEFT + NVG_ALIGN_TOP, FONT)
    for lineIndex, line in ipairs(entry.lines) do
        painter:Text(bubbleX + 14, y + 34 + (lineIndex - 1) * 22, line, 16, COLORS.body,
            NVG_ALIGN_LEFT + NVG_ALIGN_TOP, FONT)
    end
    nvgRestore(vg)
end

local function drawScrollbar(painter, track, thumbY, thumbSize)
    painter:RoundedRect(track.x, track.y, track.w, track.h, track.w * 0.5, COLORS.track, COLORS.dark, 1)
    painter:RoundedRect(track.x + 3, track.y + 3, track.w - 6, track.h - 6,
        math.max(1, (track.w - 6) * 0.5), COLORS.trackInner)
    local apple = painter.images.apple
    if apple and apple >= 0 then
        painter:Image(apple, track.x + track.w * 0.5, thumbY + thumbSize * 0.5, thumbSize, thumbSize, 1)
    else
        painter:Circle(track.x + track.w * 0.5, thumbY + thumbSize * 0.5, thumbSize * 0.45,
            COLORS.unread, COLORS.dark, 1.5)
    end
end

local function drawFooter(painter, rect, model)
    local footerY = rect.y + rect.h * 0.858
    local labelX = rect.x + rect.w * 0.18
    local right = rect.x + rect.w * FOOTER_RIGHT_RATIO
    local anger = math.max(0, math.min(model.maxAnger, model.anger))
    local progress = model.maxAnger > 0 and anger / model.maxAnger or 0

    painter:Text(labelX, footerY + 14, "牛顿怒气", 15, COLORS.dark,
        NVG_ALIGN_LEFT + NVG_ALIGN_TOP, FONT)
    painter:Text(right, footerY + 14, string.format("%d%%", math.floor(progress * 100 + 0.5)), 15,
        COLORS.unread, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP, FONT)

    local barX = rect.x + rect.w * 0.24
    local barY = footerY + 48
    local barW = math.max(80, right - barX)
    painter:RoundedRect(barX, barY, barW, 13, 6.5, COLORS.angerTrack, COLORS.creamStroke, 1.5)
    if progress > 0 then
        painter:RoundedRect(barX + 2, barY + 2, math.max(1, (barW - 4) * progress), 9, 4.5, COLORS.angerFill)
    end
    local apple = painter.images.apple
    if apple and apple >= 0 then painter:Image(apple, labelX + 10, barY + 6, 30, 30, 1) end
end

function View.Draw(painter, frame, controller)
    local model = controller:GetRenderModel()
    local scale, panelAlpha = controller:GetPanelPresentation()
    if panelAlpha <= 0 then return end

    local rect = panelRect(frame)
    local centerX, centerY = rect.x + rect.w * 0.5, rect.y + rect.h * 0.5
    local button = buttonRect(rect)
    local messageRight = rect.x + rect.w * MESSAGE_RIGHT_RATIO
    local viewport = {
        x = rect.x + 24,
        y = rect.y + rect.h * 0.132,
        w = messageRight - (rect.x + 24),
        h = rect.h * 0.704,
    }
    local track = {
        x = rect.x + rect.w * SCROLLBAR_CENTER_RATIO - 5,
        y = viewport.y + 12,
        w = 10,
        h = viewport.h - 24,
    }
    local thumbSize = 34
    local entries, contentHeight = layoutMessages(painter, model.messages, model.visibleCount, viewport)
    controller:SetScrollMetrics(contentHeight, viewport.h)
    model.scrollOffset = controller.scrollOffset
    model.maxScroll = controller.maxScroll
    local thumbY = track.y + controller:GetScrollProgress() * (track.h - thumbSize)
    local thumb = { x = track.x + track.w * 0.5 - thumbSize * 0.5, y = thumbY, w = thumbSize, h = thumbSize }

    controller:SetViewGeometry({
        button = transformRect(button, scale, centerX, centerY),
        viewport = transformRect(viewport, scale, centerX, centerY),
        track = transformRect({ x = track.x - 12, y = track.y, w = 34, h = track.h }, scale, centerX, centerY),
        thumb = transformRect(thumb, scale, centerX, centerY),
    })

    local vg = painter.vg
    nvgSave(vg)
    nvgTranslate(vg, centerX, centerY)
    nvgScale(vg, scale, scale)
    nvgTranslate(vg, -centerX, -centerY)
    nvgGlobalAlpha(vg, panelAlpha)

    drawPanelBackground(painter, rect)
    drawPanelButton(painter, button, model.buttonKind)

    nvgSave(vg)
    nvgIntersectScissor(vg, viewport.x, viewport.y, viewport.w, viewport.h)
    for index, entry in ipairs(entries) do
        drawMessage(painter, controller, entry, index, viewport, model.scrollOffset, panelAlpha)
    end
    nvgRestore(vg)

    drawScrollbar(painter, track, thumbY, thumbSize)
    drawFooter(painter, rect, model)
    nvgRestore(vg)
end

return View
