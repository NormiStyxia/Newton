local M = {}

local COLORS = {
    paper = { 247, 239, 211, 255 },
    paperLight = { 253, 249, 235, 255 },
    ink = { 43, 73, 55, 255 },
    inkMuted = { 100, 116, 99, 255 },
    border = { 54, 91, 66, 255 },
    borderSoft = { 139, 157, 126, 255 },
    selected = { 226, 232, 193, 255 },
    brass = { 164, 139, 76, 255 },
    brassLight = { 220, 198, 126, 255 },
    brassSoft = { 205, 184, 132, 255 },
    grid = { 211, 193, 145, 255 },
    wall = { 164, 184, 151, 255 },
    launcher = { 171, 91, 67, 255 },
    goal = { 87, 139, 100, 255 },
    spring = { 178, 143, 59, 255 },
    button = { 191, 105, 76, 255 },
    door = { 132, 108, 58, 255 },
    phase = { 126, 111, 171, 255 },
    overlay = { 35, 49, 39, 255 },
}

local function pointIn(rect, x, y)
    return rect and x >= rect.x and x <= rect.x + rect.w and y >= rect.y and y <= rect.y + rect.h
end

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function utf8Characters(value)
    local result = {}
    for _, codepoint in utf8.codes(value or "") do result[#result + 1] = utf8.char(codepoint) end
    return result
end

local function textWidth(painter, value, font, size)
    painter:UseFont(font)
    nvgFontSize(painter.vg, size)
    local measured = nvgTextBounds(painter.vg, 0, 0, value or "", nil)
    return type(measured) == "number" and measured or #utf8Characters(value) * size
end

local function ellipsize(painter, value, maxWidth, font, size)
    value = value or ""
    if textWidth(painter, value, font, size) <= maxWidth then return value end
    local characters = utf8Characters(value)
    local suffix = "..."
    while #characters > 1 do
        table.remove(characters)
        local candidate = table.concat(characters) .. suffix
        if textWidth(painter, candidate, font, size) <= maxWidth then return candidate end
    end
    return suffix
end

local function wrapLines(painter, value, maxWidth, font, size)
    local lines, current = {}, ""
    for _, character in ipairs(utf8Characters(value or "")) do
        if character == "\n" then
            lines[#lines + 1], current = current, ""
        else
            local candidate = current .. character
            if current ~= "" and textWidth(painter, candidate, font, size) > maxWidth then
                lines[#lines + 1], current = current, character
            else
                current = candidate
            end
        end
    end
    if current ~= "" or #lines == 0 then lines[#lines + 1] = current end
    return lines
end

local function drawWrapped(painter, x, y, width, value, size, color, lineHeight, font)
    local lines = wrapLines(painter, value, width, font or "maker-body", size)
    for index, line in ipairs(lines) do
        painter:Text(x, y + (index - 1) * lineHeight, line, size, color, nil, font)
    end
    return #lines * lineHeight
end

function M.ResolveLayout(frame)
    local contentWidth = math.min(1808, frame.logicalWidth - 40)
    local x = (frame.logicalWidth - contentWidth) * 0.5
    local y = 126
    local height = math.min(680, math.max(590, frame.logicalHeight - y - 34))
    local gap = 18
    local leftWidth = 328
    local rightWidth = 496
    local centerWidth = contentWidth - leftWidth - rightWidth - gap * 2
    local left = { x = x, y = y, w = leftWidth, h = height }
    local center = { x = left.x + left.w + gap, y = y, w = centerWidth, h = height }
    local right = { x = center.x + center.w + gap, y = y, w = rightWidth, h = height }
    local actionGap = 12
    local actionY = right.y + right.h - 62
    local actionWidth = (right.w - 36 - actionGap) * 0.5
    local briefViewport = { x = right.x + 22, y = right.y + 72, w = right.w - 50, h = right.h - 158 }
    return {
        left = left,
        center = center,
        right = right,
        listTop = left.y + 54,
        listItemHeight = (left.h - 70) / 9,
        briefViewport = briefViewport,
        startButton = { x = right.x + 18, y = actionY, w = actionWidth, h = 44 },
        workshopButton = { x = right.x + 18 + actionWidth + actionGap, y = actionY, w = actionWidth, h = 44 },
    }
end

local function drawPaperPanel(painter, rect)
    -- The gameplay frame skin is authored as nine independent slices. Keeping
    -- the paper fill separate means the ornate corners remain intact while
    -- each catalog column can retain its existing width and height.
    painter:FillRect(rect.x, rect.y, rect.w, rect.h, COLORS.paperLight)
    local skin = painter.skins and painter.skins.gameplay
    if skin then
        painter:NineSlice(skin, rect.x, rect.y, rect.w, rect.h,
            { left = 38, right = 38, top = 38, bottom = 38 }, 255)
    else
        painter:StrokeRect(rect.x, rect.y, rect.w, rect.h, COLORS.border, 2)
    end
    painter:StrokeRect(rect.x, rect.y, rect.w, rect.h, COLORS.border, 1, 180)
    painter:StrokeRect(rect.x + 9, rect.y + 9, rect.w - 18, rect.h - 18, COLORS.brassSoft, 1, 170)
end

local function drawSectionTitle(painter, x, y, title)
    painter:Text(x, y, "✦", 16, COLORS.brass, nil, "maker-display")
    painter:Text(x + 24, y - 2, title, 19, COLORS.ink, nil, "maker-display")
    local titleWidth = textWidth(painter, title, "maker-display", 19)
    painter:Text(x + 31 + titleWidth, y, "✦", 16, COLORS.brass, nil, "maker-display")
end

local function drawDivider(painter, x, y, w, alpha)
    nvgStrokeColor(painter.vg, nvgRGBA(COLORS.brass[1], COLORS.brass[2], COLORS.brass[3], alpha or 120))
    nvgStrokeWidth(painter.vg, 1)
    nvgBeginPath(painter.vg)
    nvgMoveTo(painter.vg, x, y)
    nvgLineTo(painter.vg, x + w, y)
    nvgStroke(painter.vg)
end

local function drawDottedDivider(painter, x, y, w)
    nvgStrokeColor(painter.vg, nvgRGBA(COLORS.brass[1], COLORS.brass[2], COLORS.brass[3], 125))
    nvgStrokeWidth(painter.vg, 1)
    nvgBeginPath(painter.vg)
    for tick = x, x + w, 6 do
        nvgMoveTo(painter.vg, tick, y)
        nvgLineTo(painter.vg, math.min(tick + 2, x + w), y)
    end
    nvgStroke(painter.vg)
    painter:Circle(x, y, 2, COLORS.brassSoft, nil, nil, 180)
    painter:Circle(x + w, y, 2, COLORS.brassSoft, nil, nil, 180)
end

local function drawCatalogDecor(painter, frame)
    painter:FillRect(0, 0, frame.logicalWidth, frame.logicalHeight, COLORS.paper)
    painter:FillRect(0, 0, frame.logicalWidth, 104, COLORS.paperLight)
    painter:FillRect(0, 101, frame.logicalWidth, 3, COLORS.brass)

    local plaque = painter.images and painter.images.ui and painter.images.ui.titlePlaque
    if plaque and plaque >= 0 then
        painter:ImageRect(plaque, 28, 10, 404, 88, 1)
        painter:Text(120, 24, "实验目录", 36, COLORS.paperLight, nil, "maker-display")
        painter:Text(122, 66, "EXPERIMENT CATALOG", 12, COLORS.brassLight, nil, "report-green")
    else
        painter:RoundedRect(30, 12, 398, 82, 10, COLORS.ink, COLORS.brass, 2)
        painter:Text(52, 24, "实验目录", 36, COLORS.paperLight, nil, "maker-display")
        painter:Text(54, 66, "EXPERIMENT CATALOG", 12, COLORS.brassLight, nil, "report-green")
    end

    painter:RoundedRect(frame.logicalWidth - 310, 27, 264, 46, 8, COLORS.paper, COLORS.brassSoft, 2)
    painter:Text(frame.logicalWidth - 178, 39, "牛顿实验档案 · 01—09", 14, COLORS.ink,
        NVG_ALIGN_RIGHT + NVG_ALIGN_TOP, "maker-display")

    -- A restrained archive ruler and an orbit sketch carry the botanical
    -- laboratory language without taking space from the three columns.
    drawDivider(painter, 454, 87, frame.logicalWidth - 500, 150)
    nvgStrokeColor(painter.vg, nvgRGBA(COLORS.brass[1], COLORS.brass[2], COLORS.brass[3], 150))
    nvgStrokeWidth(painter.vg, 1)
    nvgBeginPath(painter.vg)
    for x = 470, frame.logicalWidth - 70, 40 do
        nvgMoveTo(painter.vg, x, 83)
        nvgLineTo(painter.vg, x, 83 + ((x - 470) % 160 == 0 and 12 or 7))
    end
    nvgStroke(painter.vg)
    nvgStrokeWidth(painter.vg, 1.2)
    nvgBeginPath(painter.vg)
    nvgEllipse(painter.vg, frame.logicalWidth * .48, 44, 34, 10)
    nvgEllipse(painter.vg, frame.logicalWidth * .48, 44, 10, 34)
    nvgStroke(painter.vg)

    local rulerY = frame.logicalHeight - 18
    painter:FillRect(0, rulerY, frame.logicalWidth, 18, COLORS.brassLight)
    nvgStrokeColor(painter.vg, nvgRGBA(COLORS.ink[1], COLORS.ink[2], COLORS.ink[3], 180))
    nvgStrokeWidth(painter.vg, 1)
    nvgBeginPath(painter.vg)
    for x = 18, frame.logicalWidth - 18, 24 do
        nvgMoveTo(painter.vg, x, rulerY)
        nvgLineTo(painter.vg, x, rulerY + ((x - 18) % 96 == 0 and 14 or 8))
    end
    nvgStroke(painter.vg)

    local leafX, leafY = frame.logicalWidth - 92, 76
    nvgStrokeColor(painter.vg, nvgRGBA(COLORS.border[1], COLORS.border[2], COLORS.border[3], 180))
    nvgStrokeWidth(painter.vg, 3)
    nvgBeginPath(painter.vg); nvgMoveTo(painter.vg, leafX, leafY); nvgLineTo(painter.vg, leafX + 34, leafY + 40); nvgStroke(painter.vg)
    for index = 0, 2 do
        local x, y = leafX + index * 10, leafY + index * 11
        nvgBeginPath(painter.vg); nvgEllipse(painter.vg, x - 6, y, 10, 5)
        nvgFillColor(painter.vg, nvgRGBA(COLORS.selected[1], COLORS.selected[2], COLORS.selected[3], 255)); nvgFill(painter.vg)
        nvgStroke(painter.vg)
    end
end

local function drawPreviewObject(painter, object, originX, originY, scale)
    local transform = object.transform
    if not transform then return end
    local x, y = originX + transform.x * scale, originY + transform.y * scale
    local w, h = math.max(3, transform.width * scale), math.max(3, transform.height * scale)
    local properties = object.properties or {}
    local color = object.type == "launcher" and COLORS.launcher
        or object.type == "goal_sensor" and COLORS.goal
        or object.type == "spring" and COLORS.spring
        or object.type == "button" and COLORS.button
        or object.type == "door" and COLORS.door
        or properties.isPhaseable and COLORS.phase or COLORS.wall
    local vg = painter.vg
    nvgSave(vg)
    nvgTranslate(vg, x, y)
    nvgRotate(vg, math.rad(transform.rotation or 0))
    nvgStrokeColor(vg, nvgRGBA(COLORS.border[1], COLORS.border[2], COLORS.border[3], 235))
    nvgStrokeWidth(vg, 1.5)
    nvgFillColor(vg, nvgRGBA(color[1], color[2], color[3], properties.isPhaseable and 150 or 215))

    if object.type == "goal_sensor" then
        nvgBeginPath(vg); nvgEllipse(vg, 0, 0, w * 0.5, h * 0.5); nvgFill(vg); nvgStroke(vg)
        nvgBeginPath(vg); nvgEllipse(vg, 0, 0, w * 0.31, h * 0.31); nvgStroke(vg)
    elseif object.type == "launcher" then
        nvgBeginPath(vg); nvgRoundedRect(vg, -w * .5, -h * .5, w, h, math.min(5, h * .16)); nvgFill(vg); nvgStroke(vg)
        nvgBeginPath(vg); nvgMoveTo(vg, -w * .18, 0); nvgLineTo(vg, w * .27, 0)
        nvgLineTo(vg, w * .12, -h * .15); nvgMoveTo(vg, w * .27, 0); nvgLineTo(vg, w * .12, h * .15); nvgStroke(vg)
    elseif object.type == "spring" then
        nvgBeginPath(vg)
        for step = 0, 8 do
            local px = -w * .5 + w * step / 8
            local py = (step == 0 or step == 8) and 0 or (step % 2 == 0 and h * .36 or -h * .36)
            if step == 0 then nvgMoveTo(vg, px, py) else nvgLineTo(vg, px, py) end
        end
        nvgStrokeWidth(vg, 2); nvgStroke(vg)
    elseif object.type == "button" then
        nvgBeginPath(vg); nvgEllipse(vg, 0, 0, w * .5, h * .5); nvgFill(vg); nvgStroke(vg)
        nvgBeginPath(vg); nvgMoveTo(vg, -w * .22, 0); nvgLineTo(vg, w * .22, 0); nvgStroke(vg)
    elseif object.type == "door" then
        nvgBeginPath(vg); nvgRect(vg, -w * .5, -h * .5, w, h); nvgFill(vg); nvgStroke(vg)
        nvgBeginPath(vg); nvgMoveTo(vg, 0, -h * .5); nvgLineTo(vg, 0, h * .5); nvgStroke(vg)
    else
        nvgBeginPath(vg); nvgRect(vg, -w * .5, -h * .5, w, h); nvgFill(vg); nvgStroke(vg)
        if properties.isPhaseable then
            nvgBeginPath(vg); nvgMoveTo(vg, -w * .42, -h * .25); nvgLineTo(vg, w * .42, h * .25); nvgStroke(vg)
        end
    end
    nvgRestore(vg)
end

local function drawPreview(painter, rect, level)
    drawSectionTitle(painter, rect.x + 22, rect.y + 20, "平面预览")
    painter:Text(rect.x + rect.w - 22, rect.y + 23, "STATIC PLAN · 1400 × 700", 10, COLORS.inkMuted,
        NVG_ALIGN_RIGHT + NVG_ALIGN_TOP, "report-green")
    local preview = { x = rect.x + 24, y = rect.y + 62, w = rect.w - 48, h = rect.h - 126 }
    painter:FillRect(preview.x, preview.y, preview.w, preview.h, { 252, 243, 215, 255 })
    painter:StrokeRect(preview.x, preview.y, preview.w, preview.h, COLORS.brassSoft, 1)
    if not level then
        painter:Text(preview.x + preview.w * .5, preview.y + preview.h * .5, "关卡数据不可用", 18, COLORS.button,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, "maker-display")
        return
    end

    nvgSave(painter.vg)
    nvgScissor(painter.vg, preview.x, preview.y, preview.w, preview.h)
    -- Graph paper is deliberately drawn inside the existing preview rectangle;
    -- the level's 1400 x 700 content still receives the exact same fit scale.
    nvgStrokeColor(painter.vg, nvgRGBA(COLORS.grid[1], COLORS.grid[2], COLORS.grid[3], 76))
    nvgStrokeWidth(painter.vg, 1)
    for gridX = preview.x + 12, preview.x + preview.w - 12, 24 do
        nvgBeginPath(painter.vg); nvgMoveTo(painter.vg, gridX, preview.y); nvgLineTo(painter.vg, gridX, preview.y + preview.h); nvgStroke(painter.vg)
    end
    for gridY = preview.y + 12, preview.y + preview.h - 12, 24 do
        nvgBeginPath(painter.vg); nvgMoveTo(painter.vg, preview.x, gridY); nvgLineTo(painter.vg, preview.x + preview.w, gridY); nvgStroke(painter.vg)
    end
    painter:Text(preview.x + 34, preview.y + 28, "s = ½ gt²", 14, COLORS.inkMuted, nil, "report-green", 110)
    painter:Text(preview.x + 34, preview.y + 51, "v = v₀ + gt", 14, COLORS.inkMuted, nil, "report-green", 110)
    painter:Text(preview.x + preview.w - 160, preview.y + preview.h - 56, "F = ma", 17, COLORS.inkMuted, nil, "report-green", 110)

    local padding = 24
    local scale = math.min((preview.w - padding * 2) / level.playfield.width,
        (preview.h - padding * 2) / level.playfield.height)
    local drawnWidth, drawnHeight = level.playfield.width * scale, level.playfield.height * scale
    local originX = preview.x + (preview.w - drawnWidth) * .5
    local originY = preview.y + (preview.h - drawnHeight) * .5
    painter:StrokeRect(originX, originY, drawnWidth, drawnHeight, COLORS.border, 1, 150)
    local groundY = originY + 580 * scale
    nvgStrokeColor(painter.vg, nvgRGBA(COLORS.brass[1], COLORS.brass[2], COLORS.brass[3], 180))
    nvgStrokeWidth(painter.vg, 1)
    nvgBeginPath(painter.vg); nvgMoveTo(painter.vg, originX, groundY); nvgLineTo(painter.vg, originX + drawnWidth, groundY); nvgStroke(painter.vg)
    for _, object in ipairs(level.objects or {}) do drawPreviewObject(painter, object, originX, originY, scale) end

    -- Small compass mark, kept outside the playfield fit calculation.
    local compassX, compassY = preview.x + preview.w - 48, preview.y + 44
    nvgStrokeColor(painter.vg, nvgRGBA(COLORS.brass[1], COLORS.brass[2], COLORS.brass[3], 190))
    nvgStrokeWidth(painter.vg, 1.5)
    nvgBeginPath(painter.vg); nvgCircle(painter.vg, compassX, compassY, 18); nvgStroke(painter.vg)
    nvgBeginPath(painter.vg); nvgMoveTo(painter.vg, compassX, compassY - 25); nvgLineTo(painter.vg, compassX, compassY + 25)
    nvgMoveTo(painter.vg, compassX - 25, compassY); nvgLineTo(painter.vg, compassX + 25, compassY); nvgStroke(painter.vg)
    painter:Text(compassX, compassY - 34, "N", 11, COLORS.ink, NVG_ALIGN_CENTER + NVG_ALIGN_TOP, "report-green")
    nvgRestore(painter.vg)

    local legend = {
        { "墙体", COLORS.wall }, { "发射器", COLORS.launcher }, { "观察皿", COLORS.goal },
        { "弹簧/机构", COLORS.spring }, { "相位", COLORS.phase },
    }
    local legendX, legendY = rect.x + 28, rect.y + rect.h - 40
    for _, entry in ipairs(legend) do
        painter:FillRect(legendX, legendY + 3, 10, 10, entry[2])
        painter:StrokeRect(legendX, legendY + 3, 10, 10, COLORS.border, 1, 150)
        painter:Text(legendX + 15, legendY, entry[1], 11, COLORS.inkMuted, nil, "maker-body")
        legendX = legendX + 15 + textWidth(painter, entry[1], "maker-body", 11) + 20
    end
end

local function enabledCardNames(level, rules)
    local names = {}
    for _, card in ipairs(level and level.cardDeck and level.cardDeck.cards or {}) do
        if card.enabled then
            local definition = rules.CARDS[card.cardId]
            names[#names + 1] = definition and definition.name or card.cardId
        end
    end
    return names
end

local function drawScoreBadge(painter, x, y, score)
    local fill = score >= 100 and { 224, 190, 95, 255 }
        or score >= 80 and { 187, 193, 181, 255 }
        or { 196, 133, 91, 255 }
    painter:Circle(x, y, 16, fill, COLORS.ink, 1.5, 235)
    painter:Circle(x, y, 11, nil, COLORS.paperLight, 1, 220)
    nvgStrokeColor(painter.vg, nvgRGBA(COLORS.ink[1], COLORS.ink[2], COLORS.ink[3], 210))
    nvgStrokeWidth(painter.vg, 1.3)
    nvgBeginPath(painter.vg)
    for point = 0, 5 do
        local angle = -math.pi * .5 + point * math.pi * 2 / 5
        local radius = point % 2 == 0 and 7 or 3
        local px, py = x + math.cos(angle) * radius, y + math.sin(angle) * radius
        if point == 0 then nvgMoveTo(painter.vg, px, py) else nvgLineTo(painter.vg, px, py) end
    end
    nvgClosePath(painter.vg); nvgStroke(painter.vg)
end

local function drawBrief(painter, layout, level, state, rules)
    local viewport = layout.briefViewport
    local y = viewport.y - state.scroll
    local left, width = viewport.x, viewport.w - 10
    nvgSave(painter.vg)
    nvgScissor(painter.vg, viewport.x, viewport.y, viewport.w, viewport.h)
    if level then
        painter:Text(left, y, ellipsize(painter, level.name or "未命名实验", width, "maker-display", 27),
            27, COLORS.ink, nil, "maker-display")
        y = y + 44
        drawDivider(painter, left, y - 7, width, 100)
        painter:Text(left, y, "实验目标", 13, COLORS.brass, nil, "report-green")
        y = y + 22 + drawWrapped(painter, left, y + 20, width, level.objective or "", 17, COLORS.ink, 24, "maker-display")
        y = y + 10
        painter:Text(left, y, "简短说明", 13, COLORS.brass, nil, "report-green")
        y = y + 22 + drawWrapped(painter, left, y + 20, width, level.description or "暂无说明", 14, COLORS.inkMuted, 21)
        y = y + 10
        painter:Text(left, y, "可使用的规则牌", 13, COLORS.brass, nil, "report-green")
        local cards = enabledCardNames(level, rules)
        local cardText = #cards > 0 and table.concat(cards, " · ") or "无需规则牌"
        y = y + 22 + drawWrapped(painter, left, y + 20, width, cardText, 14, COLORS.ink, 21)
        y = y + 12
        painter:Text(left, y, "评级标准", 13, COLORS.brass, nil, "report-green")
        y = y + 24
        for _, tier in ipairs(level.scoring and level.scoring.tiers or {}) do
            drawScoreBadge(painter, left + 16, y + 12, tonumber(tier.score) or 0)
            painter:Text(left + 42, y, string.format("%d · %s", tier.score, tier.title), 16, COLORS.ink, nil, "maker-display")
            y = y + 23
            y = y + drawWrapped(painter, left + 42, y, width - 42, tier.description or "", 13, COLORS.inkMuted, 19)
            y = y + 12
            drawDivider(painter, left + 42, y - 5, width - 42, 72)
        end
    else
        painter:Text(left, y, "关卡数据读取失败", 18, COLORS.button, nil, "maker-display")
        y = y + 40
    end
    nvgRestore(painter.vg)

    local contentHeight = math.max(0, y + state.scroll - viewport.y)
    state.scrollMax = math.max(0, contentHeight - viewport.h + 8)
    state.scroll = clamp(state.scroll, 0, state.scrollMax)
    if state.scrollMax > 0 then
        local track = { x = viewport.x + viewport.w + 4, y = viewport.y, w = 3, h = viewport.h }
        painter:FillRect(track.x, track.y, track.w, track.h, COLORS.borderSoft, 110)
        local thumbHeight = math.max(38, track.h * viewport.h / contentHeight)
        local travel = track.h - thumbHeight
        local thumbY = track.y + travel * state.scroll / state.scrollMax
        painter:FillRect(track.x - 1, thumbY, track.w + 2, thumbHeight, COLORS.border, 220)
    end
end

local function drawButton(painter, rect, label, primary, hovered, enabled)
    local fill = primary and COLORS.ink or COLORS.paperLight
    local text = primary and COLORS.paperLight or COLORS.ink
    if not enabled then fill, text = COLORS.borderSoft, COLORS.paper end
    if hovered and enabled then fill = primary and COLORS.border or COLORS.selected end
    painter:RoundedRect(rect.x, rect.y, rect.w, rect.h, 4, fill, primary and COLORS.brass or COLORS.border, 2)
    painter:StrokeRect(rect.x + 5, rect.y + 5, rect.w - 10, rect.h - 10, primary and COLORS.brassSoft or COLORS.borderSoft, 1, 180)
    painter:Text(rect.x + rect.w * .5, rect.y + rect.h * .5, label, 17, text,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, "maker-display")
    if enabled then
        painter:Text(rect.x + rect.w - 14, rect.y + rect.h * .5, primary and "✦" or "❧", 11,
            primary and COLORS.brassLight or COLORS.brass, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, "maker-display")
    end
end

---@param context GameContext
function M.Install(context)
    local CONFIG = context.CONFIG
    local Rules = context.Rules
    local catalogState_ = context.catalogState_
    local _ENV = context

    function InitializeExperimentCatalog()
        local state = catalogState_
        state.levels, state.loadErrors = {}, {}
        for index = 1, CONFIG.levelCount do
            local ok, levelOrError = pcall(LoadLevelDefinition, index)
            if ok then
                state.levels[index] = levelOrError
            else
                local message = tostring(levelOrError)
                state.loadErrors[index] = message
                print(string.format("[LevelCatalog] level_%02d load failed: %s", index, message))
            end
        end
        state.selectedIndex = clamp(tonumber(state.selectedIndex) or 1, 1, CONFIG.levelCount)
        state.scroll, state.scrollMax = 0, 0
    end

    function RequestStartLevel(index)
        index = clamp(tonumber(index) or catalogState_.selectedIndex or 1, 1, CONFIG.levelCount)
        if not catalogState_.levels[index] then
            catalogState_.toast = "关卡数据不可用"
            catalogState_.toastTime = 2.4
            return false
        end
        catalogState_.selectedIndex = index
        catalogState_.toast, hudDropdown_ = nil, nil
        BuildLevel(index)
        return true
    end

    function RequestReturnToCatalog(preselectIndex)
        if screen_ == "workshop_preview" then return ExitWorkshopPreview("navigation") end
        local selected = tonumber(preselectIndex) or levelIndex_ or catalogState_.selectedIndex or 1
        if scene_ or level_ then ReleaseLevelRuntime() end
        screen_ = "catalog"
        catalogState_.selectedIndex = clamp(selected, 1, CONFIG.levelCount)
        catalogState_.scroll, catalogState_.scrollMax = 0, 0
        catalogState_.dragStartY, catalogState_.toast = nil, nil
        hudDropdown_ = nil
        return true
    end

    function RequestEnterWorkshop(selectedLevelId)
        return OpenLevelWorkshop(selectedLevelId)
    end

    local function selectLevel(index)
        index = clamp(index, 1, CONFIG.levelCount)
        if catalogState_.selectedIndex == index then return end
        catalogState_.selectedIndex = index
        catalogState_.scroll, catalogState_.scrollMax = 0, 0
    end

    function UpdateExperimentCatalog(dt, pointerFrame)
        local state = catalogState_
        state.toastTime = math.max(0, (state.toastTime or 0) - math.max(0, dt))
        if state.toastTime <= 0 then state.toast = nil end
        if frame_.physicalWidth < frame_.physicalHeight then return end

        local layout = M.ResolveLayout(frame_)
        local x, y = pointerFrame.x, pointerFrame.y
        if input:GetKeyPress(KEY_UP) then selectLevel(state.selectedIndex - 1) end
        if input:GetKeyPress(KEY_DOWN) then selectLevel(state.selectedIndex + 1) end
        if input:GetKeyPress(KEY_RETURN) then RequestStartLevel(state.selectedIndex); return end

        if pointerFrame.pressed then
            for index = 1, CONFIG.levelCount do
                local item = { x = layout.left.x + 12, y = layout.listTop + (index - 1) * layout.listItemHeight,
                    w = layout.left.w - 24, h = layout.listItemHeight - 4 }
                if pointIn(item, x, y) then selectLevel(index); return end
            end
            if pointIn(layout.startButton, x, y) then RequestStartLevel(state.selectedIndex); return end
            if pointIn(layout.workshopButton, x, y) then
                local level = state.levels[state.selectedIndex]
                RequestEnterWorkshop(level and level.levelId or nil)
                return
            end
            if pointIn(layout.briefViewport, x, y) then
                state.dragStartY, state.dragStartScroll = y, state.scroll
            end
        end
        if pointerFrame.down and state.dragStartY then
            state.scroll = clamp(state.dragStartScroll + state.dragStartY - y, 0, state.scrollMax)
        end
        if pointerFrame.released or not pointerFrame.down then state.dragStartY = nil end
        local wheel = input.mouseMoveWheel or 0
        if wheel ~= 0 and pointIn(layout.briefViewport, x, y) then
            state.scroll = clamp(state.scroll - wheel * 52, 0, state.scrollMax)
        end
    end

    function DrawExperimentCatalog()
        local painter, state = painter_, catalogState_
        drawCatalogDecor(painter, frame_)
        if frame_.physicalWidth < frame_.physicalHeight then
            painter:Text(frame_.logicalWidth * .5, frame_.logicalHeight * .5 - 10, "请使用横屏进入实验目录", 28,
                COLORS.ink, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, "maker-display")
            painter:Text(frame_.logicalWidth * .5, frame_.logicalHeight * .5 + 34, "LANDSCAPE ORIENTATION REQUIRED", 11,
                COLORS.inkMuted, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, "report-green")
            return
        end

        local layout = M.ResolveLayout(frame_)
        drawPaperPanel(painter, layout.left)
        drawPaperPanel(painter, layout.center)
        drawPaperPanel(painter, layout.right)
        drawSectionTitle(painter, layout.left.x + 20, layout.left.y + 20, "关卡目录")
        drawSectionTitle(painter, layout.right.x + 20, layout.right.y + 20, "实验简报")

        local pointerX, pointerY = DesignPointer()
        local pointer = { x = pointerX, y = pointerY }
        for index = 1, CONFIG.levelCount do
            local level = state.levels[index]
            local item = { x = layout.left.x + 12, y = layout.listTop + (index - 1) * layout.listItemHeight,
                w = layout.left.w - 24, h = layout.listItemHeight - 4 }
            local selected = state.selectedIndex == index
            local hovered = pointIn(item, pointer.x, pointer.y)
            if selected then
                painter:RoundedRect(item.x + 2, item.y + 2, item.w - 4, item.h - 4, 3, COLORS.selected, COLORS.border, 2)
            elseif hovered then
                painter:FillRect(item.x + 3, item.y + 3, item.w - 6, item.h - 6, COLORS.selected, 84)
            end
            painter:Text(item.x + 13, item.y + item.h * .5, string.format("实验 %02d", index), 14,
                selected and COLORS.ink or COLORS.inkMuted, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, "report-green")
            local name = level and level.name or "数据不可用"
            local nameX = item.x + 92
            painter:Text(nameX, item.y + item.h * .5,
                ellipsize(painter, name, item.x + item.w - nameX - 10, "maker-display", 17), 17,
                level and COLORS.ink or COLORS.button, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, "maker-display")
            drawDottedDivider(painter, item.x + 12, item.y + item.h - 3, item.w - 24)
        end

        local level = state.levels[state.selectedIndex]
        drawPreview(painter, layout.center, level)
        drawBrief(painter, layout, level, state, Rules)
        local startEnabled = level ~= nil
        drawButton(painter, layout.startButton, "开始实验", true, pointIn(layout.startButton, pointer.x, pointer.y), startEnabled)
        drawButton(painter, layout.workshopButton, "关卡工坊", false, pointIn(layout.workshopButton, pointer.x, pointer.y), true)

        if state.toast then
            local width = math.max(230, textWidth(painter, state.toast, "maker-display", 15) + 46)
            local toast = { x = frame_.logicalWidth * .5 - width * .5, y = 104, w = width, h = 42 }
            painter:FillRect(toast.x, toast.y, toast.w, toast.h, COLORS.overlay, 245)
            painter:StrokeRect(toast.x, toast.y, toast.w, toast.h, COLORS.brass, 2)
            painter:Text(toast.x + toast.w * .5, toast.y + toast.h * .5, state.toast, 15, COLORS.paperLight,
                NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, "maker-display")
        end
    end
end

return M
