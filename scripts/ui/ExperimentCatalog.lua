local ResponsiveCatalogRoot = require("ui.ResponsiveCatalogRoot")

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

function M.ResolveLayout(frame, state)
    return ResponsiveCatalogRoot.Resolve(frame, state)
end

local function drawPaperPanel(painter, panelRect, border)
    -- The catalog frame skin is authored as nine independent slices. Keeping
    -- the paper fill separate means the ornate corners remain intact while
    -- each catalog column can retain its existing width and height.
    painter:FillRect(panelRect.x, panelRect.y, panelRect.w, panelRect.h, COLORS.paperLight)
    local skin = painter.skins and painter.skins.catalogPanel
    if skin then
        painter:NineSlice(skin, panelRect.x, panelRect.y, panelRect.w, panelRect.h,
            { left = border, right = border, top = border, bottom = border }, 255)
    else
        painter:StrokeRect(panelRect.x, panelRect.y, panelRect.w, panelRect.h, COLORS.border, 2)
        painter:StrokeRect(panelRect.x + 9, panelRect.y + 9, panelRect.w - 18, panelRect.h - 18,
            COLORS.brassSoft, 1, 170)
    end
end

local function drawSectionTitle(painter, x, y, title)
    painter:Text(x, y, "✦", 19, COLORS.brass, nil, "maker-display")
    painter:Text(x + 28, y - 3, title, 24, COLORS.ink, nil, "maker-display")
    local titleWidth = textWidth(painter, title, "maker-display", 24)
    painter:Text(x + 36 + titleWidth, y, "✦", 19, COLORS.brass, nil, "maker-display")
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

local function drawCatalogDecor(painter, layout)
    painter:FillRect(layout.viewport.x, layout.viewport.y, layout.viewport.w, layout.viewport.h, COLORS.paper)
    local outerSkin = painter.skins and painter.skins.catalogOuterFrame
    if outerSkin then
        painter:NineSlice(outerSkin, layout.outer.x, layout.outer.y, layout.outer.w, layout.outer.h,
            layout.outerBorder, 255)
    else
        painter:FillRect(layout.outer.x, layout.outer.y, layout.outer.w, layout.outer.h, COLORS.paperLight)
        painter:StrokeRect(layout.outer.x, layout.outer.y, layout.outer.w, layout.outer.h, COLORS.border, 2)
    end

    local uiImages = painter.images and painter.images.ui
    if not uiImages then return end
    local decor = layout.decor
    painter:ImageRect(uiImages.catalogHeaderPlaque, decor.headerPlaque.x, decor.headerPlaque.y,
        decor.headerPlaque.w, decor.headerPlaque.h, 255)
    painter:ImageRect(uiImages.catalogHeaderInstrument, decor.headerInstrument.x, decor.headerInstrument.y,
        decor.headerInstrument.w, decor.headerInstrument.h, 255)
    painter:ImageRect(uiImages.catalogDecorTopRight, decor.topRight.x, decor.topRight.y,
        decor.topRight.w, decor.topRight.h, 255)

    local plaque = decor.headerPlaque
    local plaqueScale = plaque.w / 359
    painter:Text(plaque.x + 37 * plaqueScale, plaque.y + 14 * plaqueScale, "实验目录",
        clamp(34 * plaqueScale, 28, 42), COLORS.paperLight, nil, "maker-display")
    painter:Text(plaque.x + 39 * plaqueScale, plaque.y + 60 * plaqueScale, "EXPERIMENT CATALOG",
        clamp(13 * plaqueScale, 12, 15), COLORS.brassLight, nil, "report-green")
    local archive = decor.archive
    painter:Text(archive.x + archive.w, archive.y + archive.h * .5, "牛顿实验档案 · 01—09",
        14, COLORS.ink, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE, "maker-display")
end

local function drawCatalogForegroundDecor(painter, layout)
    local uiImages = painter.images and painter.images.ui
    if not uiImages then return end
    local decor = layout.decor
    painter:ImageRect(uiImages.catalogDecorBottomLeft, decor.bottomLeft.x, decor.bottomLeft.y,
        decor.bottomLeft.w, decor.bottomLeft.h, 255)
    painter:ImageRect(uiImages.catalogDecorBottomRight, decor.bottomRight.x, decor.bottomRight.y,
        decor.bottomRight.w, decor.bottomRight.h, 255)
end

local function drawWideRatioWarning(painter, layout)
    if not layout.wideWarning then return end
    local message = "当前窗口比例较宽，调整窗口可获得最佳显示效果。"
    local width = math.min(layout.outer.w - 32, math.max(360,
        textWidth(painter, message, "maker-body", 15) + 38))
    local warning = {
        x = layout.outer.x + (layout.outer.w - width) * .5,
        y = layout.outer.y + layout.outerBorder.top - 34,
        w = width,
        h = 30,
    }
    painter:FillRect(warning.x, warning.y, warning.w, warning.h, COLORS.paperLight, 230)
    painter:StrokeRect(warning.x, warning.y, warning.w, warning.h, COLORS.brassSoft, 1, 190)
    painter:Text(warning.x + warning.w * .5, warning.y + warning.h * .5, message, 15, COLORS.inkMuted,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, "maker-body")
end

local function drawPreviewObject(painter, object, originX, originY, scale)
    local transform = object.transform
    if not transform then return end
    local x, y = originX + transform.x * scale, originY + transform.y * scale
    local w, h = math.max(0.01, transform.width * scale), math.max(0.01, transform.height * scale)
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

local function previewBounds(level)
    local minX, minY = math.huge, math.huge
    local maxX, maxY = -math.huge, -math.huge
    local count = 0
    for _, object in ipairs(level and level.objects or {}) do
        local transform = object.transform
        if transform then
            local x = tonumber(transform.x) or 0
            local y = tonumber(transform.y) or 0
            local width = math.abs(tonumber(transform.width) or 0)
            local height = math.abs(tonumber(transform.height) or 0)
            local rotation = math.rad(tonumber(transform.rotation) or 0)
            local cosine, sine = math.abs(math.cos(rotation)), math.abs(math.sin(rotation))
            local halfWidth = cosine * width * .5 + sine * height * .5
            local halfHeight = sine * width * .5 + cosine * height * .5
            minX, maxX = math.min(minX, x - halfWidth), math.max(maxX, x + halfWidth)
            minY, maxY = math.min(minY, y - halfHeight), math.max(maxY, y + halfHeight)
            count = count + 1
        end
    end
    if count == 0 then
        local playfield = level and level.playfield or {}
        minX, minY = 0, 0
        maxX = math.max(1, tonumber(playfield.width) or 1400)
        maxY = math.max(1, tonumber(playfield.height) or 700)
    end
    return {
        minX = minX,
        minY = minY,
        maxX = maxX,
        maxY = maxY,
        width = math.max(1, maxX - minX),
        height = math.max(1, maxY - minY),
    }
end

local function drawPreview(painter, panelRect, level)
    drawSectionTitle(painter, panelRect.x + 22, panelRect.y + 20, "实验装置概览")
    if panelRect.w >= 560 then
        painter:Text(panelRect.x + panelRect.w - 22, panelRect.y + 23, "STATIC PLAN · 1400 × 700", 14,
            COLORS.inkMuted, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP, "report-green")
    end

    local legend = {
        { "墙体", COLORS.wall }, { "发射器", COLORS.launcher }, { "观察皿", COLORS.goal },
        { "弹簧/机构", COLORS.spring }, { "相位", COLORS.phase },
    }
    local legendAvailable = math.max(80, panelRect.w - 56)
    local legendRows, rowWidth = 1, 0
    for _, entry in ipairs(legend) do
        local entryWidth = 18 + textWidth(painter, entry[1], "maker-body", 16) + 20
        if rowWidth > 0 and rowWidth + entryWidth > legendAvailable then
            legendRows, rowWidth = legendRows + 1, entryWidth
        else
            rowWidth = rowWidth + entryWidth
        end
    end
    local legendAreaHeight = 18 + legendRows * 24
    local preview = {
        x = panelRect.x + 24,
        y = panelRect.y + 62,
        w = math.max(40, panelRect.w - 48),
        h = math.max(48, panelRect.h - 62 - legendAreaHeight),
    }
    painter:FillRect(preview.x, preview.y, preview.w, preview.h, { 252, 243, 215, 255 })
    painter:StrokeRect(preview.x, preview.y, preview.w, preview.h, COLORS.brassSoft, 1)
    if not level then
        painter:Text(preview.x + preview.w * .5, preview.y + preview.h * .5, "实验数据不可用", 22, COLORS.button,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, "maker-display")
        return
    end

    nvgSave(painter.vg)
    nvgScissor(painter.vg, preview.x, preview.y, preview.w, preview.h)
    local gridStep = clamp(math.min(preview.w, preview.h) * .09, 18, 32)
    nvgStrokeColor(painter.vg, nvgRGBA(COLORS.grid[1], COLORS.grid[2], COLORS.grid[3], 76))
    nvgStrokeWidth(painter.vg, 1)
    for gridX = preview.x + gridStep * .5, preview.x + preview.w, gridStep do
        nvgBeginPath(painter.vg); nvgMoveTo(painter.vg, gridX, preview.y)
        nvgLineTo(painter.vg, gridX, preview.y + preview.h); nvgStroke(painter.vg)
    end
    for gridY = preview.y + gridStep * .5, preview.y + preview.h, gridStep do
        nvgBeginPath(painter.vg); nvgMoveTo(painter.vg, preview.x, gridY)
        nvgLineTo(painter.vg, preview.x + preview.w, gridY); nvgStroke(painter.vg)
    end
    if preview.w >= 360 and preview.h >= 120 then
        painter:Text(preview.x + 20, preview.y + 18, "s = ½ gt²", 15, COLORS.inkMuted, nil, "report-green", 90)
        painter:Text(preview.x + 20, preview.y + 42, "v = v₀ + gt", 15, COLORS.inkMuted, nil, "report-green", 90)
        painter:Text(preview.x + preview.w - 92, preview.y + preview.h - 34, "F = ma", 17,
            COLORS.inkMuted, nil, "report-green", 90)
    end

    local bounds = previewBounds(level)
    local padding = clamp(math.min(preview.w, preview.h) * .08, 10, 28)
    local scale = math.min(math.max(1, preview.w - padding * 2) / bounds.width,
        math.max(1, preview.h - padding * 2) / bounds.height)
    local drawnWidth, drawnHeight = bounds.width * scale, bounds.height * scale
    local apparatusX = preview.x + (preview.w - drawnWidth) * .5
    local apparatusY = preview.y + (preview.h - drawnHeight) * .5
    local mapOriginX = apparatusX - bounds.minX * scale
    local mapOriginY = apparatusY - bounds.minY * scale
    painter:StrokeRect(apparatusX, apparatusY, drawnWidth, drawnHeight, COLORS.border, 1, 120)
    local groundY = mapOriginY + 580 * scale
    if groundY >= apparatusY and groundY <= apparatusY + drawnHeight then
        nvgStrokeColor(painter.vg, nvgRGBA(COLORS.brass[1], COLORS.brass[2], COLORS.brass[3], 150))
        nvgStrokeWidth(painter.vg, 1)
        nvgBeginPath(painter.vg); nvgMoveTo(painter.vg, apparatusX, groundY)
        nvgLineTo(painter.vg, apparatusX + drawnWidth, groundY); nvgStroke(painter.vg)
    end
    for _, object in ipairs(level.objects or {}) do
        drawPreviewObject(painter, object, mapOriginX, mapOriginY, scale)
    end

    if preview.w >= 300 and preview.h >= 100 then
        local radius = clamp(math.min(preview.w, preview.h) * .075, 12, 18)
        local compassX, compassY = preview.x + preview.w - radius - 18, preview.y + radius + 18
        nvgStrokeColor(painter.vg, nvgRGBA(COLORS.brass[1], COLORS.brass[2], COLORS.brass[3], 190))
        nvgStrokeWidth(painter.vg, 1.5)
        nvgBeginPath(painter.vg); nvgCircle(painter.vg, compassX, compassY, radius); nvgStroke(painter.vg)
        nvgBeginPath(painter.vg); nvgMoveTo(painter.vg, compassX, compassY - radius - 6)
        nvgLineTo(painter.vg, compassX, compassY + radius + 6)
        nvgMoveTo(painter.vg, compassX - radius - 6, compassY)
        nvgLineTo(painter.vg, compassX + radius + 6, compassY); nvgStroke(painter.vg)
        painter:Text(compassX, compassY - radius - 20, "N", 13, COLORS.ink,
            NVG_ALIGN_CENTER + NVG_ALIGN_TOP, "report-green")
    end
    nvgRestore(painter.vg)

    local legendX, legendY = panelRect.x + 28, preview.y + preview.h + 12
    for _, entry in ipairs(legend) do
        local entryWidth = 18 + textWidth(painter, entry[1], "maker-body", 16) + 20
        if legendX > panelRect.x + 28 and legendX + entryWidth > panelRect.x + panelRect.w - 28 then
            legendX, legendY = panelRect.x + 28, legendY + 24
        end
        painter:FillRect(legendX, legendY + 4, 12, 12, entry[2])
        painter:StrokeRect(legendX, legendY + 4, 12, 12, COLORS.border, 1, 150)
        painter:Text(legendX + 18, legendY, entry[1], 16, COLORS.inkMuted, nil, "maker-body")
        legendX = legendX + entryWidth
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
        painter:Text(left, y, ellipsize(painter, level.name or "未命名实验", width, "maker-display", 32),
            32, COLORS.ink, nil, "maker-display")
        y = y + 50
        drawDivider(painter, left, y - 7, width, 100)
        painter:Text(left, y, "实验目的", 17, COLORS.brass, nil, "report-green")
        y = y + 26 + drawWrapped(painter, left, y + 25, width, level.objective or "", 21, COLORS.ink, 29, "maker-display")
        y = y + 12
        painter:Text(left, y, "实验说明", 17, COLORS.brass, nil, "report-green")
        y = y + 26 + drawWrapped(painter, left, y + 25, width, level.description or "暂无说明", 18, COLORS.inkMuted, 26)
        y = y + 12
        painter:Text(left, y, "可用规则", 17, COLORS.brass, nil, "report-green")
        local cards = enabledCardNames(level, rules)
        local cardText = #cards > 0 and table.concat(cards, " · ") or "无需规则干预"
        y = y + 26 + drawWrapped(painter, left, y + 25, width, cardText, 18, COLORS.ink, 26)
        y = y + 14
        painter:Text(left, y, "评定标准", 17, COLORS.brass, nil, "report-green")
        y = y + 30
        for _, tier in ipairs(level.scoring and level.scoring.tiers or {}) do
            drawScoreBadge(painter, left + 18, y + 14, tonumber(tier.score) or 0)
            painter:Text(left + 46, y, string.format("%d · %s", tier.score, tier.title), 20, COLORS.ink, nil, "maker-display")
            y = y + 29
            y = y + drawWrapped(painter, left + 46, y, width - 46, tier.description or "", 17, COLORS.inkMuted, 24)
            y = y + 14
            drawDivider(painter, left + 46, y - 5, width - 46, 72)
        end
    else
        painter:Text(left, y, "实验数据读取失败", 22, COLORS.button, nil, "maker-display")
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
    local skin = painter.skins and (primary and painter.skins.catalogButtonPrimary or painter.skins.catalogButtonSecondary)
    if skin then
        local skinScale = clamp(rect.h / 145, .30, .56)
        painter:NineSlice(skin, rect.x, rect.y, rect.w, rect.h,
            { left = 68 * skinScale, right = 88 * skinScale,
                top = 50 * skinScale, bottom = 64 * skinScale }, enabled and 255 or 125)
    else
        painter:RoundedRect(rect.x, rect.y, rect.w, rect.h, 4, fill, primary and COLORS.brass or COLORS.border, 2)
        painter:StrokeRect(rect.x + 5, rect.y + 5, rect.w - 10, rect.h - 10, primary and COLORS.brassSoft or COLORS.borderSoft, 1, 180)
    end
    local fontSize = 23
    local renderedLabel = ellipsize(painter, label, math.max(20, rect.w - 36), "maker-display", fontSize)
    painter:Text(rect.x + rect.w * .5, rect.y + rect.h * .5, renderedLabel, fontSize, text,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, "maker-display")
    if enabled and not skin then
        painter:Text(rect.x + rect.w - 14, rect.y + rect.h * .5, primary and "✦" or "❧", 11,
            primary and COLORS.brassLight or COLORS.brass, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, "maker-display")
    end
end

local function drawTab(painter, rect, label, active, hovered)
    drawButton(painter, rect, label, active, hovered, true)
end

local function refreshListScroll(layout, state, levelCount)
    local viewport = layout.listViewport
    local contentHeight = levelCount * layout.listItemHeight
    state.listScrollMax = math.max(0, contentHeight - viewport.h)
    state.listScroll = clamp(tonumber(state.listScroll) or 0, 0, state.listScrollMax)
    if state.ensureSelectionVisible then
        local itemTop = (state.selectedIndex - 1) * layout.listItemHeight
        local itemBottom = itemTop + layout.listItemHeight
        if itemTop < state.listScroll then state.listScroll = itemTop end
        if itemBottom > state.listScroll + viewport.h then state.listScroll = itemBottom - viewport.h end
        state.listScroll = clamp(state.listScroll, 0, state.listScrollMax)
        state.ensureSelectionVisible = false
    end
    return contentHeight
end

local function listItemRect(layout, state, index)
    local viewport = layout.listViewport
    return {
        x = viewport.x,
        y = viewport.y - state.listScroll + (index - 1) * layout.listItemHeight,
        w = math.max(20, viewport.w - (state.listScrollMax > 0 and 10 or 0)),
        h = math.max(20, layout.listItemHeight - 4),
    }
end

local function listIndexAt(layout, state, x, y, levelCount)
    if not pointIn(layout.listViewport, x, y) then return nil end
    local index = math.floor((y - layout.listViewport.y + state.listScroll) / layout.listItemHeight) + 1
    if index < 1 or index > levelCount then return nil end
    return index
end

local function drawLevelList(painter, layout, state, levelCount, pointer)
    local viewport = layout.listViewport
    local contentHeight = refreshListScroll(layout, state, levelCount)
    nvgSave(painter.vg)
    nvgScissor(painter.vg, viewport.x, viewport.y, viewport.w, viewport.h)
    for index = 1, levelCount do
        local level = state.levels[index]
        local item = listItemRect(layout, state, index)
        if item.y + item.h >= viewport.y and item.y <= viewport.y + viewport.h then
            local selected = state.selectedIndex == index
            local hovered = pointIn(item, pointer.x, pointer.y) and pointIn(viewport, pointer.x, pointer.y)
            if selected then
                painter:RoundedRect(item.x + 2, item.y + 2, item.w - 4, item.h - 4, 3,
                    COLORS.selected, COLORS.border, 2)
            elseif hovered then
                painter:FillRect(item.x + 3, item.y + 3, item.w - 6, item.h - 6, COLORS.selected, 84)
            end
            local numberWidth = clamp(item.w * .30, 76, 96)
            painter:Text(item.x + 13, item.y + item.h * .5, string.format("实验 %02d", index), 18,
                selected and COLORS.ink or COLORS.inkMuted,
                NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, "report-green")
            local name = level and level.name or "数据不可用"
            local nameX = item.x + numberWidth
            painter:Text(nameX, item.y + item.h * .5,
                ellipsize(painter, name, math.max(20, item.x + item.w - nameX - 10), "maker-display", 21),
                21, level and COLORS.ink or COLORS.button,
                NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, "maker-display")
            drawDottedDivider(painter, item.x + 12, item.y + item.h - 3, item.w - 24)
        end
    end
    nvgRestore(painter.vg)
    if state.listScrollMax > 0 then
        local track = { x = viewport.x + viewport.w - 4, y = viewport.y, w = 3, h = viewport.h }
        painter:FillRect(track.x, track.y, track.w, track.h, COLORS.borderSoft, 110)
        local thumbHeight = math.max(38, track.h * viewport.h / contentHeight)
        local travel = math.max(0, track.h - thumbHeight)
        local thumbY = track.y + travel * state.listScroll / state.listScrollMax
        painter:FillRect(track.x - 1, thumbY, track.w + 2, thumbHeight, COLORS.border, 220)
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
        state.activeTab = state.activeTab == "preview" and "preview" or state.activeTab == "brief" and "brief" or "list"
        state.listScroll, state.listScrollMax = 0, 0
        state.scroll, state.scrollMax = 0, 0
        state.dragTarget, state.dragStartY, state.pressedLevelIndex = nil, nil, nil
        state.dragMoved, state.ensureSelectionVisible = false, true
    end

    function RequestStartLevel(index)
        index = clamp(tonumber(index) or catalogState_.selectedIndex or 1, 1, CONFIG.levelCount)
        if not catalogState_.levels[index] then
            catalogState_.toast = "实验数据不可用"
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
        catalogState_.dragTarget, catalogState_.dragStartY = nil, nil
        catalogState_.pressedLevelIndex, catalogState_.toast = nil, nil
        catalogState_.ensureSelectionVisible = true
        hudDropdown_ = nil
        return true
    end

    function RequestEnterWorkshop(selectedLevelId)
        return OpenLevelWorkshop(selectedLevelId)
    end

    local function selectLevel(index)
        index = clamp(index, 1, CONFIG.levelCount)
        if catalogState_.selectedIndex == index then
            catalogState_.ensureSelectionVisible = true
            return
        end
        catalogState_.selectedIndex = index
        catalogState_.scroll, catalogState_.scrollMax = 0, 0
        catalogState_.ensureSelectionVisible = true
    end

    function UpdateExperimentCatalog(dt, pointerFrame)
        local state = catalogState_
        state.toastTime = math.max(0, (state.toastTime or 0) - math.max(0, dt))
        if state.toastTime <= 0 then state.toast = nil end
        local layout = M.ResolveLayout(frame_, state)
        if layout.viewport.w < layout.viewport.h then return end

        local pointer = ResponsiveCatalogRoot.MapPointer(layout, pointerFrame)
        local x, y = pointer.x, pointer.y
        refreshListScroll(layout, state, CONFIG.levelCount)
        if input:GetKeyPress(KEY_UP) then selectLevel(state.selectedIndex - 1) end
        if input:GetKeyPress(KEY_DOWN) then selectLevel(state.selectedIndex + 1) end
        if input:GetKeyPress(KEY_RETURN) then RequestStartLevel(state.selectedIndex); return end

        if pointer.pressed and layout.tabs then
            for tabId, tabRect in pairs(layout.tabs) do
                if pointIn(tabRect, x, y) then
                    state.activeTab = tabId
                    state.dragTarget, state.dragStartY, state.pressedLevelIndex = nil, nil, nil
                    return
                end
            end
        end

        if pointer.pressed then
            if pointIn(layout.startButton, x, y) then RequestStartLevel(state.selectedIndex); return end
            if pointIn(layout.workshopButton, x, y) then
                local level = state.levels[state.selectedIndex]
                RequestEnterWorkshop(level and level.levelId or nil)
                return
            end
            if layout.visible.list and pointIn(layout.listViewport, x, y) then
                state.dragTarget = "list"
                state.dragStartY, state.dragStartScroll = y, state.listScroll
                state.dragMoved = false
                state.pressedLevelIndex = listIndexAt(layout, state, x, y, CONFIG.levelCount)
            elseif layout.visible.brief and pointIn(layout.briefViewport, x, y) then
                state.dragTarget = "brief"
                state.dragStartY, state.dragStartScroll = y, state.scroll
                state.dragMoved = false
                state.pressedLevelIndex = nil
            end
        end

        if pointer.down and state.dragTarget and state.dragStartY then
            local delta = state.dragStartY - y
            local threshold = pointer.isTouch and 8 or 5
            if math.abs(delta) >= threshold then state.dragMoved = true end
            if state.dragTarget == "list" then
                state.listScroll = clamp(state.dragStartScroll + delta, 0, state.listScrollMax)
            elseif state.dragTarget == "brief" then
                state.scroll = clamp(state.dragStartScroll + delta, 0, state.scrollMax)
            end
        end

        if pointer.released then
            if state.dragTarget == "list" and not state.dragMoved and state.pressedLevelIndex then
                local releasedIndex = listIndexAt(layout, state, x, y, CONFIG.levelCount)
                if releasedIndex == state.pressedLevelIndex then selectLevel(releasedIndex) end
            end
            state.dragTarget, state.dragStartY, state.pressedLevelIndex = nil, nil, nil
            state.dragMoved = false
        elseif not pointer.down and state.dragTarget then
            state.dragTarget, state.dragStartY, state.pressedLevelIndex = nil, nil, nil
            state.dragMoved = false
        end

        local wheel = input.mouseMoveWheel or 0
        if wheel ~= 0 and layout.visible.list and pointIn(layout.listViewport, x, y) then
            state.listScroll = clamp(state.listScroll - wheel * 52, 0, state.listScrollMax)
        elseif wheel ~= 0 and layout.visible.brief and pointIn(layout.briefViewport, x, y) then
            state.scroll = clamp(state.scroll - wheel * 52, 0, state.scrollMax)
        end
    end

    function DrawExperimentCatalog()
        local painter, state = painter_, catalogState_
        local layout = M.ResolveLayout(frame_, state)
        ResponsiveCatalogRoot.Begin(painter, layout)
        drawCatalogDecor(painter, layout)
        if layout.viewport.w < layout.viewport.h then
            painter:Text(layout.viewport.w * .5, layout.viewport.h * .5 - 10, "请使用横屏进入实验目录", 32,
                COLORS.ink, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, "maker-display")
            painter:Text(layout.viewport.w * .5, layout.viewport.h * .5 + 38, "LANDSCAPE ORIENTATION REQUIRED", 14,
                COLORS.inkMuted, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, "report-green")
            ResponsiveCatalogRoot.Finish(painter)
            return
        end

        local pointerX, pointerY = DesignPointer()
        local pointer = ResponsiveCatalogRoot.MapPointer(layout, { x = pointerX, y = pointerY })

        if layout.mode == "square" then
            local panel = layout.activeTab == "preview" and layout.center
                or layout.activeTab == "brief" and layout.right or layout.left
            drawPaperPanel(painter, panel, layout.panelBorder)
        else
            drawPaperPanel(painter, layout.left, layout.panelBorder)
            drawPaperPanel(painter, layout.center, layout.panelBorder)
            drawPaperPanel(painter, layout.right, layout.panelBorder)
        end
        drawCatalogForegroundDecor(painter, layout)
        if layout.mode == "square" then
            drawTab(painter, layout.tabs.list, "实验清单", layout.activeTab == "list",
                pointIn(layout.tabs.list, pointer.x, pointer.y))
            drawTab(painter, layout.tabs.preview, "装置概览", layout.activeTab == "preview",
                pointIn(layout.tabs.preview, pointer.x, pointer.y))
            drawTab(painter, layout.tabs.brief, "预习报告", layout.activeTab == "brief",
                pointIn(layout.tabs.brief, pointer.x, pointer.y))
        end

        local level = state.levels[state.selectedIndex]
        if layout.visible.list then
            drawSectionTitle(painter, layout.left.x + 20, layout.left.y + 20, "实验清单")
            drawLevelList(painter, layout, state, CONFIG.levelCount, pointer)
        end
        if layout.visible.preview then drawPreview(painter, layout.center, level) end
        if layout.visible.brief then
            drawSectionTitle(painter, layout.right.x + 20, layout.right.y + 20, "预习报告")
            drawBrief(painter, layout, level, state, Rules)
        end

        local startEnabled = level ~= nil
        drawButton(painter, layout.startButton, "开始实验", true, pointIn(layout.startButton, pointer.x, pointer.y), startEnabled)
        drawButton(painter, layout.workshopButton, "实验工坊", false, pointIn(layout.workshopButton, pointer.x, pointer.y), true)

        if state.toast then
            local width = math.min(layout.outer.w - 32,
                math.max(250, textWidth(painter, state.toast, "maker-display", 18) + 50))
            local toast = { x = layout.outer.x + (layout.outer.w - width) * .5,
                y = layout.content.y - 50, w = width, h = 42 }
            painter:FillRect(toast.x, toast.y, toast.w, toast.h, COLORS.overlay, 245)
            painter:StrokeRect(toast.x, toast.y, toast.w, toast.h, COLORS.brass, 2)
            painter:Text(toast.x + toast.w * .5, toast.y + toast.h * .5, state.toast, 18, COLORS.paperLight,
                NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, "maker-display")
        else
            drawWideRatioWarning(painter, layout)
        end
        ResponsiveCatalogRoot.Finish(painter)
    end
end

return M
