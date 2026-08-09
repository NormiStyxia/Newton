local CatalogTransition = require("ui.ExperimentCatalogTransition")
local SketchDrawing = require("ui.SketchDrawing")
local LevelPreviewTransform = require("game.layout.LevelPreviewTransform")
local ResultReportConfig = require("ui.result_report_config")

local M = {}

local CATALOG_TITLE_FONT = "report-summary"
local CATALOG_ORNAMENT_FONT = "report-green"
local CATALOG_HEADING_FONT = "maker-display"
local CATALOG_BODY_FONT = "maker-body"
local CATALOG_MONO_FONT = "report-green"
local sketchDrawing_ = SketchDrawing.New()

local CATALOG_HEADER = {
    backButton = { x = 108, y = 31, w = 82, h = 82 },
    titleX = 218,
    titleCenterY = 60,
    subtitleCenterY = 97,
}

-- Catalog-only illustrations are aligned by their main circular silhouette.
-- Stems, leaves and direction marks intentionally extend beyond object bounds.
local PREVIEW_IMAGE_LAYOUT = {
    launcher = {
        imageKey = "catalogPreviewApple",
        sourceWidth = 563,
        sourceHeight = 597,
        bodyX = 33,
        bodyY = 142,
        bodyWidth = 517,
        bodyHeight = 454,
    },
    goal_sensor = {
        imageKey = "catalogPreviewSensor",
        sourceWidth = 844,
        sourceHeight = 906,
        bodyX = 121,
        bodyY = 208,
        bodyWidth = 696,
        bodyHeight = 698,
    },
}

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

local CATEGORY_OFFICIAL = "official"
local CATEGORY_CUSTOM = "custom"

local function nonBlank(value, fallback)
    if type(value) ~= "string" or value:match("^%s*$") then return fallback end
    return value
end

local function pointIn(rect, x, y)
    return rect and x >= rect.x and x <= rect.x + rect.w and y >= rect.y and y <= rect.y + rect.h
end

local function resolveCatalogHeader(frame)
    local artOffsetX = math.max(0, (frame.logicalWidth - 1880) * .5)
    local source = CATALOG_HEADER.backButton
    return {
        backButton = {
            x = artOffsetX + source.x,
            y = source.y,
            w = source.w,
            h = source.h,
        },
        titleX = artOffsetX + CATALOG_HEADER.titleX,
        titleCenterY = CATALOG_HEADER.titleCenterY,
        subtitleCenterY = CATALOG_HEADER.subtitleCenterY,
    }
end

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function easeOut(value)
    value = clamp(value or 0, 0, 1)
    return 1 - (1 - value) * (1 - value)
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
    font = font or CATALOG_BODY_FONT
    local lines = wrapLines(painter, value, width, font, size)
    for index, line in ipairs(lines) do
        painter:Text(x, y + (index - 1) * lineHeight, line, size, color, nil, font)
    end
    return #lines * lineHeight
end

function M.ResolveLayout(frame)
    local contentWidth = math.min(1774, frame.logicalWidth - 40)
    local x = (frame.logicalWidth - contentWidth) * 0.5
    local y = 154
    local height = math.min(584, math.max(540, frame.logicalHeight - y - 84))
    local gap = 18
    local leftWidth = 390
    local rightWidth = 510
    local centerWidth = contentWidth - leftWidth - rightWidth - gap * 2
    local left = { x = x, y = y, w = leftWidth, h = height }
    local center = { x = left.x + left.w + gap, y = y, w = centerWidth, h = height }
    local right = { x = center.x + center.w + gap, y = y, w = rightWidth, h = height }
    local actionGap = 14
    local actionY = right.y + right.h - 100
    local actionWidth = (right.w - 42 - actionGap) * 0.5
    local briefY = right.y + 72
    local briefViewport = {
        x = right.x + 22,
        y = briefY,
        w = right.w - 50,
        h = math.max(120, actionY - briefY - 14),
    }
    local categoryGap = 8
    local categoryX = left.x + 18
    local categoryY = left.y + 58
    local categoryWidth = (left.w - 36 - categoryGap) * .5
    local listTop = left.y + 106
    local listViewport = {
        x = left.x + 6,
        y = listTop,
        w = left.w - 12,
        h = math.max(80, left.y + left.h - listTop - 10),
    }
    return {
        left = left,
        center = center,
        right = right,
        categoryTabs = {
            official = { x = categoryX, y = categoryY, w = categoryWidth, h = 44 },
            custom = { x = categoryX + categoryWidth + categoryGap, y = categoryY, w = categoryWidth, h = 44 },
        },
        listTop = listTop,
        listItemHeight = listViewport.h / 8,
        listViewport = listViewport,
        listScrollbarTrack = {
            x = listViewport.x + listViewport.w - 15,
            y = listViewport.y + 5,
            w = 12,
            h = listViewport.h - 10,
        },
        briefViewport = briefViewport,
        startButton = { x = right.x + 21, y = actionY, w = actionWidth, h = 76 },
        workshopButton = { x = right.x + 21 + actionWidth + actionGap, y = actionY, w = actionWidth, h = 76 },
        reportButton = { x = right.x + right.w - 296, y = right.y + 15, w = 272, h = 40 },
    }
end

local function resolveListScrollbar(layout, state, levelCount)
    local contentHeight = levelCount * layout.listItemHeight
    local scrollMax = math.max(0, contentHeight - layout.listViewport.h)
    if scrollMax <= 0 then return nil end
    local track = layout.listScrollbarTrack
    local thumbHeight = math.max(48, track.h * layout.listViewport.h / contentHeight)
    local travel = math.max(1, track.h - thumbHeight)
    local scroll = clamp(state.listScroll or 0, 0, scrollMax)
    return {
        track = track,
        thumb = {
            x = track.x + 2,
            y = track.y + travel * scroll / scrollMax,
            w = track.w - 4,
            h = thumbHeight,
        },
        travel = travel,
        scrollMax = scrollMax,
    }
end

local function drawPaperPanel(painter, rect)
    -- The catalog frame skin is authored as nine independent slices. Keeping
    -- the paper fill separate means the ornate corners remain intact while
    -- each catalog column can retain its existing width and height.
    painter:FillRect(rect.x, rect.y, rect.w, rect.h, COLORS.paperLight)
    local skin = painter.skins and painter.skins.catalogPanel
    if skin then
        painter:NineSlice(skin, rect.x, rect.y, rect.w, rect.h,
            { left = 60, right = 60, top = 60, bottom = 60 }, 255)
    else
        painter:StrokeRect(rect.x, rect.y, rect.w, rect.h, COLORS.border, 2)
        painter:StrokeRect(rect.x + 9, rect.y + 9, rect.w - 18, rect.h - 18, COLORS.brassSoft, 1, 170)
    end
end

local function drawSectionTitle(painter, x, y, title)
    painter:Text(x, y, "✦", 19, COLORS.brass, nil, CATALOG_ORNAMENT_FONT)
    local titleX, titleSize = x + 28, 24
    painter:Text(titleX, y - 3, title, titleSize, COLORS.ink, nil, CATALOG_HEADING_FONT)
    local titleWidth = textWidth(painter, title, CATALOG_HEADING_FONT, titleSize)
    painter:Text(titleX + titleWidth + 8, y, "✦", 19, COLORS.brass, nil, CATALOG_ORNAMENT_FONT)
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

local function drawCatalogBackArrow(painter, rect, hovered, pressed)
    local vg = painter.vg
    local scale = pressed and .94 or hovered and 1.045 or 1
    local centerX = rect.x + rect.w * .5
    local centerY = rect.y + rect.h * .5 + (pressed and 1.5 or 0)

    nvgSave(vg)
    nvgTranslate(vg, centerX, centerY)
    nvgScale(vg, scale, scale)
    nvgLineCap(vg, NVG_ROUND)
    nvgLineJoin(vg, NVG_ROUND)
    nvgBeginPath(vg)
    nvgMoveTo(vg, 20, 0)
    nvgLineTo(vg, -18, 0)
    nvgMoveTo(vg, -18, 0)
    nvgLineTo(vg, -3, -14)
    nvgMoveTo(vg, -18, 0)
    nvgLineTo(vg, -3, 14)
    local arrowColor = hovered and COLORS.brassLight or COLORS.paperLight
    nvgStrokeColor(vg, nvgRGBA(arrowColor[1], arrowColor[2], arrowColor[3], pressed and 225 or 255))
    nvgStrokeWidth(vg, 4.2)
    nvgStroke(vg)
    nvgRestore(vg)
end

local function drawCatalogDecor(painter, frame, header, backHovered, backPressed)
    painter:FillRect(0, 0, frame.logicalWidth, frame.logicalHeight, COLORS.paper)
    local background = painter.images and painter.images.ui and painter.images.ui.catalogBackground
    local artOffsetX = math.max(0, (frame.logicalWidth - 1880) * .5)
    if background and background >= 0 then
        painter:ImageRect(background, artOffsetX, 0, 1880, 840, 255)
    else
        painter:FillRect(0, 0, frame.logicalWidth, frame.logicalHeight, COLORS.paper)
    end

    -- The supplied background already contains the plaque, ruler and botanical
    -- ornaments. Only live catalog copy is painted on top of that artwork.
    drawCatalogBackArrow(painter, header.backButton, backHovered, backPressed)
    local leftMiddle = NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE
    painter:Text(header.titleX, header.titleCenterY, "实验目录", 44,
        COLORS.paperLight, leftMiddle, CATALOG_TITLE_FONT)
    painter:Text(header.titleX, header.subtitleCenterY, "EXPERIMENT CATALOG", 14,
        COLORS.brassLight, leftMiddle, CATALOG_TITLE_FONT)
end

local function drawCatalogForegroundDecor(painter, frame)
    local uiImages = painter.images and painter.images.ui
    if not uiImages then return end
    local artOffsetX = math.max(0, (frame.logicalWidth - 1880) * .5)
    painter:ImageRect(uiImages.catalogDecorLeft, artOffsetX + 8, 627, 379, 213, 255)
    painter:ImageRect(uiImages.catalogDecorRight, artOffsetX + 1567, 683, 305, 156, 255)
end

local function isPilotSketchObject(level, object)
    if not level or not object or not sketchDrawing_:IsEnabled(level.levelId) then return false end
    return object.type == "wall"
end

local function drawPreviewImage(painter, objectType, w, h)
    local layout = PREVIEW_IMAGE_LAYOUT[objectType]
    local uiImages = painter.images and painter.images.ui
    local image = layout and uiImages and uiImages[layout.imageKey]
    if not image or image < 0 then return false end

    local drawWidth = w * layout.sourceWidth / layout.bodyWidth
    local drawHeight = h * layout.sourceHeight / layout.bodyHeight
    local bodyCenterX = layout.bodyX + layout.bodyWidth * .5
    local bodyCenterY = layout.bodyY + layout.bodyHeight * .5
    painter:Image(image, 0, 0, drawWidth, drawHeight, 1, nil,
        bodyCenterX / layout.sourceWidth, bodyCenterY / layout.sourceHeight)
    return true
end

local function drawPreviewObject(painter, level, object, previewTransform)
    local transform = object.transform
    if not transform then return end
    local x, y = LevelPreviewTransform.LevelToScreen(previewTransform, transform.x, transform.y)
    local mappedWidth, mappedHeight = LevelPreviewTransform.SizeToScreen(
        previewTransform, transform.width, transform.height)
    local w, h = math.max(3, mappedWidth), math.max(3, mappedHeight)
    local properties = object.properties or {}
    local sketchObject = isPilotSketchObject(level, object)
    local color = object.type == "wall" and sketchObject and COLORS.wall
        or object.type == "launcher" and COLORS.launcher
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
    local fillAlpha = object.type == "wall" and sketchObject and 245
        or properties.isPhaseable and 150 or 215
    nvgFillColor(vg, nvgRGBA(color[1], color[2], color[3], fillAlpha))

    if not sketchObject and drawPreviewImage(painter, object.type, w, h) then
        -- Catalog images replace only the launcher/apple and goal sensor marks.
        -- Existing vector drawing below remains the resource-failure fallback.
    elseif sketchObject then
        local levelId, objectId = level.levelId, object.id or object.type
        local fillAlpha = object.type == "wall" and 245
            or properties.isPhaseable and 150 or 215
        if object.type == "goal_sensor" then
            sketchDrawing_:DrawEllipse(vg, levelId, objectId, "outer",
                0, 0, w * .5, h * .5, color, COLORS.border, 1.5,
                { fillAlpha = fillAlpha, secondary = true })
            local innerMark = sketchDrawing_:GetTextMark(levelId, objectId, "inner-ring")
            sketchDrawing_:DrawEllipse(vg, levelId, objectId, "inner",
                innerMark.offsetX * .65, innerMark.offsetY * .65, w * .31, h * .31,
                nil, COLORS.border, 1.3, { jitter = .55, secondary = false, strokeAlpha = .76 })
        elseif object.type == "launcher" then
            sketchDrawing_:DrawRoundedRect(vg, levelId, objectId, "body",
                -w * .5, -h * .5, w, h, math.min(5, h * .16), color, COLORS.border, 1.5,
                { fillAlpha = fillAlpha, secondary = true })
            sketchDrawing_:DrawArrow(vg, levelId, objectId, "direction",
                -w * .18, 0, w * .27, 0, COLORS.border, 1.5,
                { jitter = .65, secondary = true, headLength = math.min(9, h * .22) })
        else
            sketchDrawing_:DrawRect(vg, levelId, objectId, "wood-frame",
                -w * .5, -h * .5, w, h, color, COLORS.border, 1.5,
                { fillAlpha = fillAlpha, secondary = true })
        end
    elseif object.type == "goal_sensor" then
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

local function drawPreviewPaper(painter, preview, level, pose)
    local vg = painter.vg
    pose = pose or { offsetX = 0, offsetY = 0, rotation = 0, scale = 1, alpha = 1, shadow = 0 }
    local anchorX = pose.anchorX or (preview.x + preview.w * .5)
    local anchorY = pose.anchorY or (preview.y - 12)
    nvgSave(vg)
    -- Keep the hinge at the fixed top clamp rather than rotating around the
    -- paper center. The offset is applied at the hinge so the upper edge stays
    -- visually attached until the withdrawal phase.
    nvgTranslate(vg, anchorX + (pose.offsetX or 0), anchorY + (pose.offsetY or 0))
    nvgRotate(vg, pose.rotation or 0)
    nvgScale(vg, pose.scale or 1, pose.scale or 1)
    nvgTranslate(vg, -anchorX, -anchorY)
    if (pose.shadow or 0) > 0 then
        local shadowAlpha = math.floor(18 * clamp(pose.shadow, 0, 1))
        painter:FillRect(preview.x - 2, preview.y + 5, preview.w + 4, preview.h + 5,
            { 74, 64, 45, 255 }, shadowAlpha)
        painter:FillRect(preview.x - 1, preview.y + 2, preview.w + 2, preview.h + 3,
            { 74, 64, 45, 255 }, math.floor(shadowAlpha * .55))
    end
    painter:FillRect(preview.x, preview.y, preview.w, preview.h, { 252, 243, 215, 255 })
    painter:StrokeRect(preview.x, preview.y, preview.w, preview.h, COLORS.brassSoft, 1)
    if not level then
        painter:Text(preview.x + preview.w * .5, preview.y + preview.h * .5, "实验数据不可用", 22, COLORS.button,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, CATALOG_BODY_FONT)
        nvgRestore(vg)
        return
    end

    -- Graph paper is deliberately drawn inside the existing preview rectangle;
    -- the level's 1400 x 700 content still receives the exact same fit scale.
    nvgStrokeWidth(vg, 1)
    local sketchGrid = sketchDrawing_:IsEnabled(level.levelId)
    local gridIndex = 0
    for gridX = preview.x + 12, preview.x + preview.w - 12, 24 do
        gridIndex = gridIndex + 1
        local alpha = sketchGrid and sketchDrawing_:GridAlpha(level.levelId, "vertical", gridIndex, 76) or 76
        nvgStrokeColor(vg, nvgRGBA(COLORS.grid[1], COLORS.grid[2], COLORS.grid[3], alpha))
        nvgBeginPath(vg); nvgMoveTo(vg, gridX, preview.y); nvgLineTo(vg, gridX, preview.y + preview.h); nvgStroke(vg)
    end
    gridIndex = 0
    for gridY = preview.y + 12, preview.y + preview.h - 12, 24 do
        gridIndex = gridIndex + 1
        local alpha = sketchGrid and sketchDrawing_:GridAlpha(level.levelId, "horizontal", gridIndex, 76) or 76
        nvgStrokeColor(vg, nvgRGBA(COLORS.grid[1], COLORS.grid[2], COLORS.grid[3], alpha))
        nvgBeginPath(vg); nvgMoveTo(vg, preview.x, gridY); nvgLineTo(vg, preview.x + preview.w, gridY); nvgStroke(vg)
    end
    painter:Text(preview.x + preview.w - 14, preview.y + preview.h - 24, "STATIC PLAN · 1400 × 700", 14, COLORS.inkMuted,
        NVG_ALIGN_RIGHT + NVG_ALIGN_TOP, CATALOG_MONO_FONT)
    painter:Text(preview.x + 34, preview.y + 28, "s = ½ gt²", 17, COLORS.inkMuted, nil, CATALOG_MONO_FONT, 110)
    painter:Text(preview.x + 34, preview.y + 55, "v = v₀ + gt", 17, COLORS.inkMuted, nil, CATALOG_MONO_FONT, 110)
    painter:Text(preview.x + preview.w - 160, preview.y + preview.h - 60, "F = ma", 20, COLORS.inkMuted, nil, CATALOG_MONO_FONT, 110)

    local apparatusTransform = LevelPreviewTransform.Fit(level.playfield, preview, { padding = 24 })
    local originX, originY = apparatusTransform.originX, apparatusTransform.originY
    painter:StrokeRect(originX, originY, apparatusTransform.drawWidth, apparatusTransform.drawHeight,
        COLORS.border, 1, 150)
    local _, groundY = LevelPreviewTransform.LevelToScreen(apparatusTransform, 0, 580)
    nvgStrokeColor(vg, nvgRGBA(COLORS.brass[1], COLORS.brass[2], COLORS.brass[3], 180))
    nvgStrokeWidth(vg, 1)
    nvgBeginPath(vg); nvgMoveTo(vg, originX, groundY)
    nvgLineTo(vg, originX + apparatusTransform.drawWidth, groundY); nvgStroke(vg)
    for _, object in ipairs(level.objects or {}) do drawPreviewObject(painter, level, object, apparatusTransform) end

    -- Small compass mark, kept outside the playfield fit calculation.
    local compassX, compassY = preview.x + preview.w - 48, preview.y + 44
    nvgStrokeColor(vg, nvgRGBA(COLORS.brass[1], COLORS.brass[2], COLORS.brass[3], 190))
    nvgStrokeWidth(vg, 1.5)
    nvgBeginPath(vg); nvgCircle(vg, compassX, compassY, 18); nvgStroke(vg)
    nvgBeginPath(vg); nvgMoveTo(vg, compassX, compassY - 25); nvgLineTo(vg, compassX, compassY + 25)
    nvgMoveTo(vg, compassX - 25, compassY); nvgLineTo(vg, compassX + 25, compassY); nvgStroke(vg)
    painter:Text(compassX, compassY - 36, "N", 14, COLORS.ink, NVG_ALIGN_CENTER + NVG_ALIGN_TOP, CATALOG_MONO_FONT)
    nvgRestore(vg)
end

local function drawPreviewLegend(painter, preview)
    -- The legend belongs to the fixed panel, not to either animated sheet.
    local legend = {
        { "墙体", COLORS.wall }, { "发射器", COLORS.launcher }, { "观察皿", COLORS.goal },
        { "弹簧/机构", COLORS.spring }, { "相位", COLORS.phase },
    }
    local legendX, legendY = preview.x + 4, preview.y + preview.h + 24
    for _, entry in ipairs(legend) do
        painter:FillRect(legendX, legendY + 4, 12, 12, entry[2])
        painter:StrokeRect(legendX, legendY + 4, 12, 12, COLORS.border, 1, 150)
        painter:Text(legendX + 18, legendY, entry[1], 16, COLORS.inkMuted, nil, CATALOG_BODY_FONT)
        legendX = legendX + 18 + textWidth(painter, entry[1], CATALOG_BODY_FONT, 16) + 20
    end
end

local function drawSheetMotionLayer(painter, outerClip, preview, levels, papers, paperAnchor)
    local vg = painter.vg
    nvgSave(vg)
    -- Only the central panel boundary clips moving sheets. The original graph
    -- paper rectangle is intentionally not a clip, so lifted corners, shadows
    -- and plan annotations can occupy the panel's title-side breathing room.
    nvgScissor(vg, outerClip.x, outerClip.y, outerClip.w, outerClip.h)
    for _, sheet in ipairs(papers) do
        local pose = sheet.pose or sheet
        pose.anchorX, pose.anchorY = paperAnchor.x, paperAnchor.y
        drawPreviewPaper(painter, preview, levels[sheet.index], pose)
    end
    nvgRestore(vg)
end

local function drawPreview(painter, rect, state, entrance)
    local preview = { x = rect.x + 24, y = rect.y + 62, w = rect.w - 48, h = rect.h - 126 }
    local sheetOuterClip = { x = rect.x + 3, y = rect.y + 3, w = rect.w - 6, h = rect.h - 6 }
    local transition = state.transition
    local paperVisible = not entrance or entrance:IsPaperVisible()
    -- Preserve the established withdrawal distance while decoupling it from
    -- the old graph-paper-sized clip rectangle.
    local papers
    if entrance and paperVisible then
        papers = { {
            index = state.selectedIndex,
            pose = CatalogTransition.GetEntrancePaperPose(entrance:GetPaperProgress(), rect.w - 36),
        } }
    elseif entrance then
        papers = {}
    else
        papers = transition and transition:GetPreviewPapers(rect.w - 36)
            or { { index = state.selectedIndex, pose = { offsetX = 0, offsetY = 0, rotation = 0, alpha = 1, scale = 1 } } }
    end
    local paperAnchor = { x = preview.x + preview.w * .5, y = preview.y - 12 }
    sketchDrawing_:BeginFrame()
    drawSheetMotionLayer(painter, sheetOuterClip, preview, state.levels, papers, paperAnchor)
    sketchDrawing_:EndFrame()

    -- The panel shell title is drawn by the caller with the same local panel
    -- pose. The legend belongs to the paper content and waits for the sheet.
    if paperVisible then drawPreviewLegend(painter, preview) end
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

local function beginContentMotion(vg, pose)
    nvgSave(vg)
    if pose then nvgTranslate(vg, pose.offsetX or 0, pose.offsetY or 0) end
    nvgGlobalAlpha(vg, pose and pose.alpha or 1)
end

local function drawCategoryTab(painter, rect, label, active, hovered)
    local color = active and COLORS.ink or COLORS.inkMuted
    if hovered and not active then color = COLORS.border end
    painter:Text(rect.x + rect.w * .5, rect.y + rect.h * .5 - 1, label, 19, color,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, CATALOG_HEADING_FONT)
    if active then
        painter:FillRect(rect.x + 14, rect.y + rect.h - 3, rect.w - 28, 2, COLORS.border, 235)
        painter:Circle(rect.x + rect.w * .5, rect.y + rect.h - 2, 2.5, COLORS.brass, nil, nil, 245)
    else
        drawDottedDivider(painter, rect.x + 18, rect.y + rect.h - 3, rect.w - 36)
    end
end

local function beginPanelMotion(vg, rect, pose, applyAlpha)
    pose = pose or { offsetX = 0, offsetY = 0, scale = 1, alpha = 1 }
    local centerX, centerY = rect.x + rect.w * .5, rect.y + rect.h * .5
    nvgSave(vg)
    nvgTranslate(vg, centerX + (pose.offsetX or 0), centerY + (pose.offsetY or 0))
    nvgScale(vg, pose.scale or 1, pose.scale or 1)
    nvgTranslate(vg, -centerX, -centerY)
    if applyAlpha then nvgGlobalAlpha(vg, pose.alpha or 1) end
end

local function drawBrief(painter, layout, level, state, rules, entrance)
    local viewport = layout.briefViewport
    local y = viewport.y - state.scroll
    local left, width = viewport.x, viewport.w - 10
    local isCustom = state.category == CATEGORY_CUSTOM
    nvgSave(painter.vg)
    nvgScissor(painter.vg, viewport.x, viewport.y, viewport.w, viewport.h)
    if level then
        local blockPose = function(index)
            return entrance and entrance:GetReportBlockPose(index) or nil
        end
        local titleX, titleSize = left, 32
        beginContentMotion(painter.vg, blockPose(1))
        painter:Text(titleX, y,
            ellipsize(painter, level.name or "未命名实验", width, CATALOG_HEADING_FONT, titleSize),
            titleSize, COLORS.ink, nil, CATALOG_HEADING_FONT)
        y = y + 50
        drawDivider(painter, left, y - 7, width, 100)
        painter:Text(left, y, isCustom and "实验发起人" or "实验目的", 17,
            COLORS.brass, nil, CATALOG_HEADING_FONT)
        local primaryText = isCustom and nonBlank(level.author, "匿名实验员") or (level.objective or "")
        local objectiveHeight = drawWrapped(painter, left, y + 25, width, primaryText, 21,
            COLORS.ink, 29, CATALOG_BODY_FONT)
        nvgRestore(painter.vg)
        y = y + 26 + objectiveHeight
        y = y + 12

        beginContentMotion(painter.vg, blockPose(2))
        painter:Text(left, y, isCustom and "实验介绍" or "实验说明", 17,
            COLORS.brass, nil, CATALOG_HEADING_FONT)
        local description = isCustom and nonBlank(level.description, "暂无实验介绍")
            or (level.description or "暂无说明")
        local descriptionHeight = drawWrapped(painter, left, y + 25, width,
            description, 18, COLORS.inkMuted, 26)
        nvgRestore(painter.vg)
        y = y + 26 + descriptionHeight
        y = y + 12

        beginContentMotion(painter.vg, blockPose(3))
        painter:Text(left, y, "可用规则", 17, COLORS.brass, nil, CATALOG_HEADING_FONT)
        local cards = enabledCardNames(level, rules)
        local cardText = #cards > 0 and table.concat(cards, " · ") or "无需规则干预"
        local cardHeight = drawWrapped(painter, left, y + 25, width, cardText, 18, COLORS.ink, 26)
        nvgRestore(painter.vg)
        y = y + 26 + cardHeight
        y = y + 14

        beginContentMotion(painter.vg, blockPose(4))
        painter:Text(left, y, "评定标准", 17, COLORS.brass, nil, CATALOG_HEADING_FONT)
        y = y + 30
        for _, tier in ipairs(level.scoring and level.scoring.tiers or {}) do
            drawScoreBadge(painter, left + 18, y + 14, tonumber(tier.score) or 0)
            local scoreLabel = string.format("%d ·", tier.score)
            painter:Text(left + 46, y, scoreLabel, 20, COLORS.ink, nil, CATALOG_MONO_FONT)
            local tierTitleX = left + 46 + textWidth(painter, scoreLabel, CATALOG_MONO_FONT, 20) + 8
            painter:Text(tierTitleX, y,
                ellipsize(painter, tier.title or "", left + width - tierTitleX, CATALOG_HEADING_FONT, 20),
                20, COLORS.ink, nil, CATALOG_HEADING_FONT)
            y = y + 29
            y = y + drawWrapped(painter, left + 46, y, width - 46, tier.description or "", 17, COLORS.inkMuted, 24)
            y = y + 14
            drawDivider(painter, left + 46, y - 5, width - 46, 72)
        end
        nvgRestore(painter.vg)
    else
        beginContentMotion(painter.vg, entrance and entrance:GetReportBlockPose(1) or nil)
        painter:Text(left, y, isCustom and "尚未选择自制实验" or "实验数据读取失败",
            22, isCustom and COLORS.inkMuted or COLORS.button, nil, CATALOG_BODY_FONT)
        nvgRestore(painter.vg)
        y = y + 40
    end
    nvgRestore(painter.vg)

    local contentHeight = math.max(0, y + state.scroll - viewport.y)
    state.scrollMax = math.max(0, contentHeight - viewport.h + 8)
    state.scroll = clamp(state.scroll, 0, state.scrollMax)
    if state.scrollMax > 0 then
        local scrollbarPose = entrance and entrance:GetReportBlockPose(4) or nil
        beginContentMotion(painter.vg, scrollbarPose)
        local track = { x = viewport.x + viewport.w + 4, y = viewport.y, w = 3, h = viewport.h }
        painter:FillRect(track.x, track.y, track.w, track.h, COLORS.borderSoft, 110)
        local thumbHeight = math.max(38, track.h * viewport.h / contentHeight)
        local travel = track.h - thumbHeight
        local thumbY = track.y + travel * state.scroll / state.scrollMax
        painter:FillRect(track.x - 1, thumbY, track.w + 2, thumbHeight, COLORS.border, 220)
        nvgRestore(painter.vg)
    end
end

local function drawButton(painter, rect, label, primary, hovered, enabled)
    local fill = primary and COLORS.ink or COLORS.paperLight
    local text = primary and COLORS.paperLight or COLORS.ink
    if not enabled then fill, text = COLORS.borderSoft, COLORS.paper end
    if hovered and enabled then fill = primary and COLORS.border or COLORS.selected end
    local skin = painter.skins and (primary and painter.skins.catalogButtonPrimary or painter.skins.catalogButtonSecondary)
    if skin then
        painter:NineSlice(skin, rect.x, rect.y, rect.w, rect.h,
            { left = 38, right = 45, top = 26, bottom = 33 }, enabled and 255 or 125)
    else
        painter:RoundedRect(rect.x, rect.y, rect.w, rect.h, 4, fill, primary and COLORS.brass or COLORS.border, 2)
        painter:StrokeRect(rect.x + 5, rect.y + 5, rect.w - 10, rect.h - 10, primary and COLORS.brassSoft or COLORS.borderSoft, 1, 180)
    end
    painter:Text(rect.x + rect.w * .5, rect.y + rect.h * .5, label, 23, text,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, CATALOG_HEADING_FONT)
    if enabled and not skin then
        painter:Text(rect.x + rect.w - 14, rect.y + rect.h * .5, primary and "✦" or "❧", 11,
            primary and COLORS.brassLight or COLORS.brass, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, CATALOG_ORNAMENT_FONT)
    end
end

local function drawReportSnapshotButton(painter, rect, hovered)
    local fill = hovered and COLORS.selected or COLORS.paperLight
    local ink = COLORS.ink
    painter:RoundedRect(rect.x, rect.y, rect.w, rect.h, 3, fill, COLORS.border, 1.4)
    painter:StrokeRect(rect.x + 4, rect.y + 4, rect.w - 8, rect.h - 8, COLORS.brassSoft, 1, 145)
    local icon = { x = rect.x + 13, y = rect.y + 10, w = 15, h = 19 }
    painter:StrokeRect(icon.x, icon.y, icon.w, icon.h, ink, 1.2, 220)
    painter:FillRect(icon.x + 3, icon.y + 5, icon.w - 6, 1, ink, 150)
    painter:FillRect(icon.x + 3, icon.y + 9, icon.w - 6, 1, ink, 150)
    painter:Text(rect.x + 37, rect.y + rect.h * .5, "实验报告_最最最终版.pdf", 18, ink,
        NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, CATALOG_HEADING_FONT)
end

local function drawCompletionMark(painter, x, y, alpha, scale)
    local vg = painter.vg
    nvgSave(vg)
    nvgTranslate(vg, x, y)
    nvgScale(vg, scale or 1, scale or 1)
    nvgStrokeColor(vg, nvgRGBA(COLORS.border[1], COLORS.border[2], COLORS.border[3], alpha or 255))
    nvgStrokeWidth(vg, 2.4)
    nvgLineCap(vg, NVG_ROUND)
    nvgBeginPath(vg)
    nvgMoveTo(vg, -8, -1)
    nvgLineTo(vg, -2, 5)
    nvgLineTo(vg, 9, -7)
    nvgStroke(vg)
    nvgRestore(vg)
end

local function drawExperimentProgress(painter, item, record, feedback, feedbackElapsed)
    local statusLeft = item.x + item.w - 82
    if not record or record.completed ~= true then return statusLeft end

    local elapsed = math.max(0, feedbackElapsed or 0)
    local matchingFeedback = feedback and feedback.levelId == record.levelId and feedback or nil
    local checkProgress = matchingFeedback and matchingFeedback.firstCompletion and clamp(elapsed / .16, 0, 1) or 1
    local checkEase = 1 - (1 - checkProgress) ^ 3
    drawCompletionMark(painter, statusLeft + 10, item.y + item.h * .5, math.floor(255 * checkEase), .85 + .15 * checkEase)

    if not record.bestScore then return statusLeft end
    local scoreRight = item.x + item.w - 12
    local scoreY = item.y + item.h * .5
    if matchingFeedback and matchingFeedback.bestImproved then
        local oldScore = tonumber(matchingFeedback.previousScore)
        if oldScore and elapsed < .11 then
            local fade = 1 - clamp(elapsed / .11, 0, 1)
            painter:Text(scoreRight, scoreY, tostring(oldScore), 19, COLORS.border,
                NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE, CATALOG_MONO_FONT, math.floor(255 * fade))
            return statusLeft
        end
        local reveal = clamp((elapsed - .08) / .18, 0, 1)
        local ease = 1 - (1 - reveal) ^ 3
        painter:Text(scoreRight, scoreY + 3 * (1 - ease), tostring(record.bestScore), 19, COLORS.border,
            NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE, CATALOG_MONO_FONT, math.floor(255 * ease))
        return statusLeft
    end
    painter:Text(scoreRight, scoreY, tostring(record.bestScore), 19, COLORS.border,
        NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE, CATALOG_MONO_FONT)
    return statusLeft
end

---@param context GameContext
function M.Install(context)
    local CONFIG = context.CONFIG
    local Rules = context.Rules
    local LevelPresentation = context.LevelPresentation
    local LEVEL_SCORE_PROFILES = context.LEVEL_SCORE_PROFILES
    local DEFAULT_LEVEL_SCORE_PROFILE = context.DEFAULT_LEVEL_SCORE_PROFILE
    local catalogState_ = context.catalogState_
    local experimentProgress_ = context.experimentProgress_
    local navigationTransition_ = context.navigationTransition_
    local _ENV = context

    local function upgradeNavigationTransition(candidate)
        local complete = candidate
            and type(candidate.StartReturn) == "function"
            and type(candidate.IsBackward) == "function"
            and type(candidate.GetPanelPose) == "function"
            and type(candidate.IsPaperVisible) == "function"
        if complete then return candidate end

        local replacement = CatalogTransition.NewEntrance()
        local previousState = candidate and candidate.state or nil
        local previousElapsed = math.max(0, tonumber(candidate and candidate.elapsed) or 0)
        if screen_ == "catalog" or previousState == "CATALOG_IDLE" then
            replacement:SetCatalogIdle()
        elseif previousState == "TITLE_TO_CATALOG"
            or previousState == "CATALOG_ENTER" or previousState == "CATALOG_ENTERING" then
            replacement.state = previousState == "TITLE_TO_CATALOG"
                and CatalogTransition.EntranceState.TITLE_TO_CATALOG
                or CatalogTransition.EntranceState.CATALOG_ENTERING
            replacement.elapsed = math.min(CatalogTransition.EntranceTimeline.total, previousElapsed)
        elseif previousState == "CATALOG_TO_TITLE" or previousState == "TITLE_ENTERING" then
            replacement.state = previousState
            replacement.elapsed = math.min(CatalogTransition.EntranceTimeline.returnTotal, previousElapsed)
        else
            replacement:SetTitleIdle()
        end
        context.navigationTransition_ = replacement
        print("[CatalogTransition] upgraded legacy navigation transition")
        return replacement
    end

    navigationTransition_ = upgradeNavigationTransition(navigationTransition_)

    local function categoryCount(levels)
        return type(levels) == "table" and #levels or 0
    end

    local function clampCategoryIndex(index, levels)
        local count = categoryCount(levels)
        if count == 0 then return 1 end
        return clamp(tonumber(index) or 1, 1, count)
    end

    local function rememberActiveCategory(state)
        if state.category == CATEGORY_CUSTOM then
            state.selectedCustomIndex = state.selectedIndex
            state.customListScroll = state.listScroll or 0
        else
            state.selectedOfficialIndex = state.selectedIndex
            state.officialListScroll = state.listScroll or 0
        end
    end

    local function customEntryIndex(state, entryId)
        if not entryId then return nil end
        for index, entry in ipairs(state.customEntries or {}) do
            if entry.entryId == entryId then return index end
        end
        return nil
    end

    function RefreshExperimentCatalogCustomLevels(preferredEntryId)
        local state = catalogState_
        local previous = state.customEntries
            and state.customEntries[state.selectedCustomIndex or 1] or nil
        preferredEntryId = preferredEntryId or (previous and previous.entryId)
        local ok, recordsOrError = pcall(WorkshopListCustomExperiments)
        local records = ok and type(recordsOrError) == "table" and recordsOrError or {}
        state.customLoadError = ok and nil or tostring(recordsOrError)
        state.customEntries, state.customLevels = {}, {}
        for _, record in ipairs(records) do
            if type(record) == "table" and type(record.document) == "table" then
                local document = record.document
                LevelPresentation.Apply(document, nil, LEVEL_SCORE_PROFILES, DEFAULT_LEVEL_SCORE_PROFILE)
                state.customEntries[#state.customEntries + 1] = record
                state.customLevels[#state.customLevels + 1] = document
            end
        end
        state.selectedCustomIndex = customEntryIndex(state, preferredEntryId)
            or clampCategoryIndex(state.selectedCustomIndex, state.customLevels)
        if state.category == CATEGORY_CUSTOM then
            state.levels = state.customLevels
            state.selectedIndex = state.selectedCustomIndex
            state.listScroll = state.customListScroll or 0
            state.scroll, state.scrollMax = 0, 0
            if state.transition then state.transition:Reset(state.selectedIndex) end
        end
        return #state.customLevels
    end

    local function activateCategory(category)
        local state = catalogState_
        category = category == CATEGORY_CUSTOM and CATEGORY_CUSTOM or CATEGORY_OFFICIAL
        if state.category == category then return false end
        rememberActiveCategory(state)
        if category == CATEGORY_CUSTOM then RefreshExperimentCatalogCustomLevels() end
        state.category = category
        if category == CATEGORY_CUSTOM then
            state.levels = state.customLevels
            state.selectedIndex = clampCategoryIndex(state.selectedCustomIndex, state.levels)
            state.listScroll = state.customListScroll or 0
        else
            state.levels = state.officialLevels
            state.selectedIndex = clampCategoryIndex(state.selectedOfficialIndex, state.levels)
            state.listScroll = state.officialListScroll or 0
        end
        state.scroll, state.scrollMax = 0, 0
        state.listScrollMax = 0
        state.dragStartY, state.listDragStartY, state.listPressIndex = nil, nil, nil
        state.listScrollbarDragOffset = nil
        state.reportSnapshot, state.reportSnapshotAnimation = nil, 0
        state.reportSnapshotClosing = false
        if state.transition then state.transition:Reset(state.selectedIndex) end
        playUIClick()
        return true
    end

    function InitializeExperimentCatalog()
        local state = catalogState_
        sketchDrawing_:Clear()
        state.officialLevels, state.loadErrors = {}, {}
        for index = 1, CONFIG.levelCount do
            local ok, levelOrError = pcall(LoadLevelDefinition, index)
            if ok then
                state.officialLevels[index] = levelOrError
            else
                local message = tostring(levelOrError)
                state.loadErrors[index] = message
                print(string.format("[LevelCatalog] level_%02d load failed: %s", index, message))
            end
        end
        state.category = CATEGORY_OFFICIAL
        state.selectedOfficialIndex = clampCategoryIndex(state.selectedOfficialIndex or state.selectedIndex,
            state.officialLevels)
        state.selectedIndex = state.selectedOfficialIndex
        state.levels = state.officialLevels
        state.officialListScroll, state.customListScroll, state.listScroll = 0, 0, 0
        RefreshExperimentCatalogCustomLevels()
        state.scroll, state.scrollMax = 0, 0
        state.transition = CatalogTransition.New(state.selectedIndex)
        state.progressFeedback, state.progressFeedbackElapsed = nil, 0
        state.reportSnapshot, state.reportSnapshotAnimation = nil, 0
        state.reportSnapshotClosing = false
        state.headerBackPressed = false
    end

    local function resetCatalogForNavigation(selected, category, preferredCustomEntryId)
        local state = catalogState_
        category = category == CATEGORY_CUSTOM and CATEGORY_CUSTOM or CATEGORY_OFFICIAL
        state.category = category
        if category == CATEGORY_CUSTOM then
            RefreshExperimentCatalogCustomLevels(preferredCustomEntryId)
            state.levels = state.customLevels
            state.selectedIndex = customEntryIndex(state, preferredCustomEntryId)
                or clampCategoryIndex(state.selectedCustomIndex, state.levels)
            state.selectedCustomIndex = state.selectedIndex
            state.listScroll = state.customListScroll or 0
        else
            state.levels = state.officialLevels
            state.selectedIndex = clampCategoryIndex(selected or state.selectedOfficialIndex, state.levels)
            state.selectedOfficialIndex = state.selectedIndex
            state.listScroll = state.officialListScroll or 0
        end
        state.scroll, state.scrollMax, state.listScrollMax = 0, 0, 0
        state.dragStartY, state.listDragStartY, state.listPressIndex, state.toast = nil, nil, nil, nil
        state.listScrollbarDragOffset = nil
        catalogState_.reportSnapshot, catalogState_.reportSnapshotAnimation = nil, 0
        catalogState_.reportSnapshotClosing = false
        if catalogState_.transition then catalogState_.transition:Reset(catalogState_.selectedIndex) end
        catalogState_.progressFeedback = category == CATEGORY_OFFICIAL and experimentProgress_
            and experimentProgress_:ConsumeFeedback() or nil
        catalogState_.progressFeedbackElapsed = 0
        hudDropdown_ = nil
    end

    local function closeReportSnapshot()
        if catalogState_.reportSnapshot then
            catalogState_.reportSnapshotClosing = true
            playUIClick()
        end
    end

    function RequestOpenCatalogReportSnapshot()
        if navigationTransition_:IsInputLocked() then return false end
        local state = catalogState_
        if state.category ~= CATEGORY_OFFICIAL then return false end
        local level = state.levels[state.selectedIndex]
        local snapshot = level and experimentProgress_
            and experimentProgress_:GetReportSnapshot(level.levelId) or nil
        if not snapshot then return false end
        snapshot.reviewOverflowLogged = {}
        snapshot.newtonTier = { dangerAccent = snapshot.newtonDangerAccent == true }
        state.reportSnapshot = snapshot
        state.reportSnapshotAnimation = 0
        state.reportSnapshotClosing = false
        state.dragStartY = nil
        state.toast = nil
        playUIClick()
        return true
    end

    function RequestStartLevel(index, suppressUIClick)
        if navigationTransition_:IsInputLocked() then return false end
        if catalogState_.transition and not catalogState_.transition:IsSettled() then return false end
        local state = catalogState_
        index = clampCategoryIndex(index or state.selectedIndex, state.levels)
        if not state.levels[index] then
            catalogState_.toast = "实验数据不可用"
            catalogState_.toastTime = 2.4
            return false
        end
        state.selectedIndex = index
        if state.category == CATEGORY_CUSTOM then
            state.selectedCustomIndex = index
        else
            state.selectedOfficialIndex = index
        end
        catalogState_.progressFeedback, catalogState_.progressFeedbackElapsed = nil, 0
        if experimentProgress_ then experimentProgress_:ClearPendingFeedback() end
        catalogState_.toast, hudDropdown_ = nil, nil
        sketchDrawing_:Clear()
        if state.category == CATEGORY_CUSTOM then
            local entry = state.customEntries[index]
            local document, metadataOrError = nil, "自制实验数据不可用"
            if entry then document, metadataOrError = WorkshopOpenCustomExperiment(entry.entryId) end
            if not document then
                state.toast = metadataOrError or "自制实验数据不可用"
                state.toastTime = 3
                return false
            end
            local session, errorMessage = StartRuntimeSessionFromDocument(document, {
                sourceKind = "custom",
                screen = "game",
                enablePhysicsProbe = true,
                notifyAssistant = false,
                notifyDialogue = false,
            })
            if not session then
                state.toast = "无法开始实验：" .. tostring(errorMessage)
                state.toastTime = 3.5
                return false
            end
        else
            BuildLevel(index)
        end
        if not suppressUIClick then playUIClick() end
        return true
    end

    function RequestReturnToCatalog(preselectIndex, suppressUIClick)
        if navigationTransition_:IsInputLocked() then return false end
        if screen_ == "workshop_preview" then return ExitWorkshopPreview("navigation") end
        local returningSession = GetRuntimeSession and GetRuntimeSession() or nil
        local returningCategory = returningSession and returningSession.sourceKind == "custom"
            and CATEGORY_CUSTOM or CATEGORY_OFFICIAL
        local preferredCustomEntryId = returningSession and returningSession.customLevelId
            and ("custom:" .. returningSession.customLevelId) or nil
        local selected = tonumber(preselectIndex) or levelIndex_ or catalogState_.selectedIndex or 1
        if screen_ == "title" then
            if not BeginTitleCatalogExit() then return false end
            if not navigationTransition_:Start() then return false end
            resetCatalogForNavigation(selected, CATEGORY_OFFICIAL)
            screen_ = "title_catalog_transition"
            if not suppressUIClick then playUIClick() end
            return true
        end
        if scene_ or level_ then ReleaseLevelRuntime() end
        screen_ = "catalog"
        navigationTransition_:SetCatalogIdle()
        resetCatalogForNavigation(selected, returningCategory, preferredCustomEntryId)
        if not suppressUIClick then playUIClick() end
        return true
    end

    function RequestReturnToTitleScreen(suppressUIClick)
        if screen_ ~= "catalog" or not navigationTransition_:StartReturn() then return false end
        screen_ = "title_catalog_transition"
        catalogState_.dragStartY, catalogState_.dragStartScroll = nil, 0
        catalogState_.headerBackPressed = false
        if BeginTitleCatalogEnter then BeginTitleCatalogEnter() end
        if not suppressUIClick then playUIClick() end
        return true
    end

    function FinalizeCatalogToTitleTransition()
        if scene_ or level_ then ReleaseLevelRuntime() end
        catalogState_.dragStartY, catalogState_.dragStartScroll = nil, 0
        catalogState_.toast, catalogState_.toastTime = nil, 0
        catalogState_.reportSnapshot, catalogState_.reportSnapshotAnimation = nil, 0
        catalogState_.reportSnapshotClosing = false
        catalogState_.progressFeedback, catalogState_.progressFeedbackElapsed = nil, 0
        catalogState_.headerBackPressed = false
        hudDropdown_ = nil
        sketchDrawing_:Clear()
    end

    function RequestEnterWorkshop(selectedLevelId)
        if navigationTransition_:IsInputLocked() then return false end
        if catalogState_.transition and not catalogState_.transition:IsSettled() then return false end
        local opened = OpenLevelWorkshop(selectedLevelId)
        if opened then sketchDrawing_:Clear() end
        if opened then playUIClick() end
        return opened
    end

    local function selectLevel(index)
        if navigationTransition_:IsInputLocked() then return end
        index = clampCategoryIndex(index, catalogState_.levels)
        if not catalogState_.levels[index] then return end
        if catalogState_.selectedIndex == index then return end
        catalogState_.selectedIndex = index
        if catalogState_.category == CATEGORY_CUSTOM then
            catalogState_.selectedCustomIndex = index
        else
            catalogState_.selectedOfficialIndex = index
        end
        catalogState_.scroll, catalogState_.scrollMax = 0, 0
        if catalogState_.transition then catalogState_.transition:Request(index) end
        playUIClick()
    end

    function UpdateExperimentCatalog(dt, pointerFrame)
        local state = catalogState_
        if state.transition then state.transition:Update(dt) end
        if state.progressFeedback then
            state.progressFeedbackElapsed = (state.progressFeedbackElapsed or 0) + math.max(0, dt)
            if state.progressFeedbackElapsed >= .28 then
                state.progressFeedback, state.progressFeedbackElapsed = nil, 0
            end
        end
        state.toastTime = math.max(0, (state.toastTime or 0) - math.max(0, dt))
        if state.toastTime <= 0 then state.toast = nil end
        if state.reportSnapshot then
            local duration = state.reportSnapshotClosing
                and ResultReportConfig.Layout.exitDuration or ResultReportConfig.Layout.enterDuration
            local direction = state.reportSnapshotClosing and -1 or 1
            state.reportSnapshotAnimation = clamp((state.reportSnapshotAnimation or 0)
                + direction * math.max(0, dt) / duration, 0, 1)
            if state.reportSnapshotClosing and state.reportSnapshotAnimation <= 0 then
                state.reportSnapshot = nil
                state.reportSnapshotClosing = false
            else
                if not state.reportSnapshotClosing and input:GetKeyPress(KEY_ESCAPE) then
                    closeReportSnapshot()
                    return
                end
                if pointerFrame.pressed and not state.reportSnapshotClosing then
                    local rect = ResultReportConfig.ResolveRect(frame_)
                    local progress = easeOut(state.reportSnapshotAnimation)
                    local offsetY = -(1 - progress) * 24
                    local visualRect = { x = rect.x, y = rect.y + offsetY, w = rect.w, h = rect.h }
                    if not pointIn(visualRect, pointerFrame.x, pointerFrame.y) then
                        closeReportSnapshot()
                    end
                end
                return
            end
        end
        local x, y = pointerFrame.x, pointerFrame.y
        local header = resolveCatalogHeader(frame_)
        local headerHovered = pointIn(header.backButton, x, y)
        if input:GetKeyPress(KEY_ESCAPE) then RequestReturnToTitleScreen(); return end
        if pointerFrame.pressed and headerHovered then
            state.headerBackPressed = true
            state.dragStartY, state.listDragStartY, state.listScrollbarDragOffset = nil, nil, nil
            return
        end
        if pointerFrame.released and state.headerBackPressed then
            state.headerBackPressed = false
            if headerHovered then RequestReturnToTitleScreen() end
            return
        end
        if state.headerBackPressed and not pointerFrame.down then state.headerBackPressed = false end
        if frame_.physicalWidth < frame_.physicalHeight then return end

        local layout = M.ResolveLayout(frame_)
        state.listScrollMax = math.max(0,
            #state.levels * layout.listItemHeight - layout.listViewport.h)
        state.listScroll = clamp(state.listScroll or 0, 0, state.listScrollMax)
        local listScrollbar = resolveListScrollbar(layout, state, #state.levels)
        if input:GetKeyPress(KEY_UP) then selectLevel(state.selectedIndex - 1) end
        if input:GetKeyPress(KEY_DOWN) then selectLevel(state.selectedIndex + 1) end
        local actionsEnabled = not state.transition or state.transition:IsSettled()
        if input:GetKeyPress(KEY_RETURN) and actionsEnabled then RequestStartLevel(state.selectedIndex); return end

        if pointerFrame.pressed then
            if actionsEnabled and listScrollbar and pointIn(listScrollbar.track, x, y) then
                local thumb = listScrollbar.thumb
                if pointIn(thumb, x, y) then
                    state.listScrollbarDragOffset = y - thumb.y
                else
                    local thumbY = clamp(y - thumb.h * .5,
                        listScrollbar.track.y, listScrollbar.track.y + listScrollbar.travel)
                    state.listScroll = (thumbY - listScrollbar.track.y)
                        / listScrollbar.travel * listScrollbar.scrollMax
                    state.listScrollbarDragOffset = thumb.h * .5
                    rememberActiveCategory(state)
                end
                state.listDragStartY, state.listPressIndex = nil, nil
                return
            end
            if actionsEnabled and pointIn(layout.categoryTabs.official, x, y) then
                activateCategory(CATEGORY_OFFICIAL)
                return
            end
            if actionsEnabled and pointIn(layout.categoryTabs.custom, x, y) then
                activateCategory(CATEGORY_CUSTOM)
                return
            end
            if actionsEnabled and pointIn(layout.listViewport, x, y) then
                state.listDragStartY = y
                state.listDragStartScroll = state.listScroll or 0
                state.listDragMoved = false
                local listY = y - layout.listTop + state.listScroll
                local index = math.floor(listY / layout.listItemHeight) + 1
                local item = {
                    x = layout.left.x + 12,
                    y = layout.listTop + (index - 1) * layout.listItemHeight - state.listScroll,
                    w = layout.left.w - 36,
                    h = layout.listItemHeight - 4,
                }
                state.listPressIndex = state.levels[index] and pointIn(item, x, y) and index or nil
            end
            if actionsEnabled and pointIn(layout.startButton, x, y) then RequestStartLevel(state.selectedIndex); return end
            if actionsEnabled and pointIn(layout.workshopButton, x, y) then
                local level = state.levels[state.selectedIndex]
                local customEntry = state.category == CATEGORY_CUSTOM
                    and state.customEntries[state.selectedIndex] or nil
                RequestEnterWorkshop(customEntry and customEntry.entryId or (level and level.levelId or nil))
                return
            end
            local selectedLevel = state.levels[state.selectedIndex]
            local reportAvailable = state.category == CATEGORY_OFFICIAL and selectedLevel and experimentProgress_
                and experimentProgress_:HasReportSnapshot(selectedLevel.levelId) or false
            if actionsEnabled and reportAvailable and pointIn(layout.reportButton, x, y) then
                RequestOpenCatalogReportSnapshot()
                return
            end
            if pointIn(layout.briefViewport, x, y) then
                state.dragStartY, state.dragStartScroll = y, state.scroll
            end
        end
        if state.listScrollbarDragOffset then
            listScrollbar = resolveListScrollbar(layout, state, #state.levels)
            if listScrollbar then
                local thumbY = clamp(y - state.listScrollbarDragOffset,
                    listScrollbar.track.y, listScrollbar.track.y + listScrollbar.travel)
                state.listScroll = (thumbY - listScrollbar.track.y)
                    / listScrollbar.travel * listScrollbar.scrollMax
                rememberActiveCategory(state)
            end
            if pointerFrame.released or not pointerFrame.down then
                state.listScrollbarDragOffset = nil
            end
            return
        end
        if pointerFrame.down and state.listDragStartY then
            local delta = state.listDragStartY - y
            if math.abs(delta) >= 7 then state.listDragMoved = true end
            state.listScroll = clamp(state.listDragStartScroll + delta, 0, state.listScrollMax or 0)
            rememberActiveCategory(state)
        end
        if pointerFrame.released and state.listDragStartY then
            local selectedIndex = not state.listDragMoved and state.listPressIndex or nil
            state.listDragStartY, state.listPressIndex, state.listDragMoved = nil, nil, false
            rememberActiveCategory(state)
            if selectedIndex then selectLevel(selectedIndex); return end
        elseif not pointerFrame.down and not pointerFrame.pressed then
            state.listDragStartY, state.listPressIndex, state.listDragMoved = nil, nil, false
        end
        if not actionsEnabled then
            state.dragStartY, state.listDragStartY, state.listPressIndex = nil, nil, nil
            state.listScrollbarDragOffset = nil
            return
        end
        if pointerFrame.down and state.dragStartY then
            state.scroll = clamp(state.dragStartScroll + state.dragStartY - y, 0, state.scrollMax)
        end
        if pointerFrame.released or not pointerFrame.down then state.dragStartY = nil end
        local wheel = input.mouseMoveWheel or 0
        if wheel ~= 0 then
            if pointIn(layout.listViewport, x, y) then
                local wheelDelta = clamp(wheel, -1, 1)
                state.listScroll = clamp(state.listScroll - wheelDelta * layout.listItemHeight * .42,
                    0, state.listScrollMax or 0)
                rememberActiveCategory(state)
            elseif pointIn(layout.briefViewport, x, y) then
                state.scroll = clamp(state.scroll - wheel * 52, 0, state.scrollMax)
            end
        end
    end

    function DrawExperimentCatalog(visual)
        local painter, state = painter_, catalogState_
        local entrance = visual and visual.transition or nil
        nvgSave(painter.vg)
        nvgTranslate(painter.vg, visual and visual.rootOffsetX or 0, 0)
        local pointerX, pointerY = DesignPointer()
        local pointer = entrance and { x = -10000, y = -10000 } or { x = pointerX, y = pointerY }
        local header = resolveCatalogHeader(frame_)
        local backHovered = pointIn(header.backButton, pointer.x, pointer.y)
        drawCatalogDecor(painter, frame_, header, backHovered, state.headerBackPressed == true)
        if frame_.physicalWidth < frame_.physicalHeight then
            painter:Text(frame_.logicalWidth * .5, frame_.logicalHeight * .5 - 10, "请使用横屏进入实验目录", 32,
                COLORS.ink, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, CATALOG_BODY_FONT)
            painter:Text(frame_.logicalWidth * .5, frame_.logicalHeight * .5 + 38, "LANDSCAPE ORIENTATION REQUIRED", 14,
                COLORS.inkMuted, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, CATALOG_MONO_FONT)
            nvgRestore(painter.vg)
            return
        end

        local layout = M.ResolveLayout(frame_)
        local panelPoses = {
            left = entrance and entrance:GetPanelPose("left") or nil,
            center = entrance and entrance:GetPanelPose("center") or nil,
            right = entrance and entrance:GetPanelPose("right") or nil,
        }
        beginPanelMotion(painter.vg, layout.left, panelPoses.left, true)
        drawPaperPanel(painter, layout.left)
        nvgRestore(painter.vg)
        beginPanelMotion(painter.vg, layout.center, panelPoses.center, true)
        drawPaperPanel(painter, layout.center)
        nvgRestore(painter.vg)
        beginPanelMotion(painter.vg, layout.right, panelPoses.right, true)
        drawPaperPanel(painter, layout.right)
        nvgRestore(painter.vg)
        drawCatalogForegroundDecor(painter, frame_)
        beginPanelMotion(painter.vg, layout.left, panelPoses.left, true)
        drawSectionTitle(painter, layout.left.x + 20, layout.left.y + 20, "实验清单")
        drawCategoryTab(painter, layout.categoryTabs.official, "学院实验",
            state.category == CATEGORY_OFFICIAL, pointIn(layout.categoryTabs.official, pointer.x, pointer.y))
        drawCategoryTab(painter, layout.categoryTabs.custom, "自制实验",
            state.category == CATEGORY_CUSTOM, pointIn(layout.categoryTabs.custom, pointer.x, pointer.y))
        nvgRestore(painter.vg)
        beginPanelMotion(painter.vg, layout.right, panelPoses.right, true)
        drawSectionTitle(painter, layout.right.x + 20, layout.right.y + 20,
            state.category == CATEGORY_CUSTOM and "实验档案" or "预习报告")
        nvgRestore(painter.vg)

        beginPanelMotion(painter.vg, layout.left, panelPoses.left, false)
        local listHeight = layout.listViewport.h
        local listReveal = entrance and entrance:GetListReveal() or 1
        local levelCount = #state.levels
        state.listScrollMax = math.max(0, levelCount * layout.listItemHeight - listHeight)
        state.listScroll = clamp(state.listScroll or 0, 0, state.listScrollMax)
        rememberActiveCategory(state)
        nvgSave(painter.vg)
        nvgScissor(painter.vg, layout.listViewport.x, layout.listViewport.y, layout.listViewport.w,
            math.max(0.01, listHeight * listReveal))
        if levelCount == 0 and state.category == CATEGORY_CUSTOM then
            local emptyY = layout.listTop + 70
            local emptyTitle = state.customLoadError and "自制实验读取失败" or "尚无自制实验"
            local emptyDetail = state.customLoadError and "请稍后重试或前往实验工坊检查地图。"
                or "可前往实验工坊创建或导入地图。"
            painter:Text(layout.left.x + layout.left.w * .5, emptyY, emptyTitle, 22,
                COLORS.ink, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, CATALOG_HEADING_FONT)
            drawWrapped(painter, layout.left.x + 45, emptyY + 34, layout.left.w - 90,
                emptyDetail, 17, COLORS.inkMuted, 25, CATALOG_BODY_FONT)
        end
        local firstVisible = math.max(1, math.floor(state.listScroll / layout.listItemHeight) + 1)
        local lastVisible = math.min(levelCount,
            firstVisible + math.ceil(listHeight / layout.listItemHeight) + 1)
        for index = firstVisible, lastVisible do
            local level = state.levels[index]
            local item = { x = layout.left.x + 12,
                y = layout.listTop + (index - 1) * layout.listItemHeight - state.listScroll,
                w = layout.left.w - 36, h = layout.listItemHeight - 4 }
            local selected = state.selectedIndex == index
            local hovered = pointIn(layout.listViewport, pointer.x, pointer.y)
                and pointIn(item, pointer.x, pointer.y)
            if selected then
                local highlight = entrance and entrance:GetHighlightPose() or { alpha = 1, scaleX = 1 }
                nvgSave(painter.vg)
                nvgTranslate(painter.vg, item.x + item.w * .5, 0)
                nvgScale(painter.vg, highlight.scaleX, 1)
                nvgTranslate(painter.vg, -(item.x + item.w * .5), 0)
                nvgGlobalAlpha(painter.vg, highlight.alpha)
                painter:RoundedRect(item.x + 2, item.y + 2, item.w - 4, item.h - 4, 3, COLORS.selected, COLORS.border, 2)
                nvgRestore(painter.vg)
            elseif hovered then
                painter:FillRect(item.x + 3, item.y + 3, item.w - 6, item.h - 6, COLORS.selected, 84)
            end
            local itemPose = entrance and entrance:GetListItemPose(index) or nil
            beginContentMotion(painter.vg, itemPose)
            local prefix = state.category == CATEGORY_CUSTOM and "自制" or "实验"
            painter:Text(item.x + 13, item.y + item.h * .5, string.format("%s %02d", prefix, index), 18,
                selected and COLORS.ink or COLORS.inkMuted, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, CATALOG_MONO_FONT)
            local name = level and level.name or "数据不可用"
            local nameX = item.x + 92
            local progress = state.category == CATEGORY_OFFICIAL and level and experimentProgress_
                and experimentProgress_:Get(level.levelId) or nil
            if progress then progress.levelId = level.levelId end
            local statusLeft = state.category == CATEGORY_OFFICIAL
                and drawExperimentProgress(painter, item, progress, state.progressFeedback, state.progressFeedbackElapsed)
                or (item.x + item.w - 10)
            painter:Text(nameX, item.y + item.h * .5,
                ellipsize(painter, name, statusLeft - nameX - 10, CATALOG_HEADING_FONT, 21), 21,
                level and COLORS.ink or COLORS.button, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, CATALOG_HEADING_FONT)
            drawDottedDivider(painter, item.x + 12, item.y + item.h - 3, item.w - 24)
            nvgRestore(painter.vg)
        end
        nvgRestore(painter.vg)
        local listScrollbar = resolveListScrollbar(layout, state, levelCount)
        if listScrollbar then
            local track, thumb = listScrollbar.track, listScrollbar.thumb
            painter:RoundedRect(track.x, track.y, track.w, track.h, 3,
                COLORS.paperLight, COLORS.brassSoft, 1)
            painter:RoundedRect(thumb.x, thumb.y, thumb.w, thumb.h, 2,
                COLORS.selected, COLORS.border, 1.4)
            painter:FillRect(thumb.x + 2, thumb.y + thumb.h * .5 - 1,
                thumb.w - 4, 2, COLORS.brass, 175)
        end
        nvgRestore(painter.vg)

        local level = state.levels[state.selectedIndex]
        local reportAvailable = state.category == CATEGORY_OFFICIAL and level and experimentProgress_
            and experimentProgress_:HasReportSnapshot(level.levelId) or false
        if reportAvailable then
            beginPanelMotion(painter.vg, layout.right, panelPoses.right, false)
            beginContentMotion(painter.vg, entrance and entrance:GetReportBlockPose(1) or nil)
            drawReportSnapshotButton(painter, layout.reportButton,
                pointIn(layout.reportButton, pointer.x, pointer.y))
            nvgRestore(painter.vg)
            nvgRestore(painter.vg)
        end
        beginPanelMotion(painter.vg, layout.center, panelPoses.center, false)
        drawPreview(painter, layout.center, state, entrance)
        nvgRestore(painter.vg)
        beginPanelMotion(painter.vg, layout.center, panelPoses.center, true)
        drawSectionTitle(painter, layout.center.x + 22, layout.center.y + 20, "实验装置概览")
        nvgRestore(painter.vg)
        beginPanelMotion(painter.vg, layout.right, panelPoses.right, false)
        drawBrief(painter, layout, level, state, Rules, entrance)
        nvgRestore(painter.vg)
        local actionsEnabled = not state.transition or state.transition:IsSettled()
        local startEnabled = level ~= nil and actionsEnabled
        beginPanelMotion(painter.vg, layout.right, panelPoses.right, false)
        beginContentMotion(painter.vg, entrance and entrance:GetButtonPose(1) or nil)
        drawButton(painter, layout.startButton, "开始实验", true, pointIn(layout.startButton, pointer.x, pointer.y), startEnabled)
        nvgRestore(painter.vg)
        beginContentMotion(painter.vg, entrance and entrance:GetButtonPose(2) or nil)
        drawButton(painter, layout.workshopButton, "实验工坊", false, pointIn(layout.workshopButton, pointer.x, pointer.y), actionsEnabled)
        nvgRestore(painter.vg)
        nvgRestore(painter.vg)

        if state.toast then
            local width = math.max(250, textWidth(painter, state.toast, CATALOG_BODY_FONT, 18) + 50)
            local toast = { x = frame_.logicalWidth * .5 - width * .5, y = 104, w = width, h = 46 }
            painter:FillRect(toast.x, toast.y, toast.w, toast.h, COLORS.overlay, 245)
            painter:StrokeRect(toast.x, toast.y, toast.w, toast.h, COLORS.brass, 2)
            painter:Text(toast.x + toast.w * .5, toast.y + toast.h * .5, state.toast, 18, COLORS.paperLight,
                NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, CATALOG_BODY_FONT)
        end
        if state.reportSnapshot and DrawCatalogReportSnapshot then
            DrawCatalogReportSnapshot(state.reportSnapshot, state.reportSnapshotAnimation)
        end
        nvgRestore(painter.vg)
    end
end

return M
