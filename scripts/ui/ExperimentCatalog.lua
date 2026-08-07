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

local function pointIn(rect, x, y)
    return rect and x >= rect.x and x <= rect.x + rect.w and y >= rect.y and y <= rect.y + rect.h
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
    return {
        left = left,
        center = center,
        right = right,
        listTop = left.y + 54,
        listItemHeight = (left.h - 70) / 9,
        briefViewport = briefViewport,
        startButton = { x = right.x + 21, y = actionY, w = actionWidth, h = 76 },
        workshopButton = { x = right.x + 21 + actionWidth + actionGap, y = actionY, w = actionWidth, h = 76 },
        reportButton = { x = right.x + right.w - 296, y = right.y + 15, w = 272, h = 40 },
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

local function drawCatalogDecor(painter, frame)
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
    painter:Text(artOffsetX + 126, 18, "实验目录", 44, COLORS.paperLight, nil, CATALOG_TITLE_FONT)
    painter:Text(artOffsetX + 118, 70, "EXPERIMENT CATALOG", 14, COLORS.brassLight, nil, CATALOG_TITLE_FONT)
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

local function drawPreview(painter, rect, state)
    local preview = { x = rect.x + 24, y = rect.y + 62, w = rect.w - 48, h = rect.h - 126 }
    local sheetOuterClip = { x = rect.x + 3, y = rect.y + 3, w = rect.w - 6, h = rect.h - 6 }
    local transition = state.transition
    -- Preserve the established withdrawal distance while decoupling it from
    -- the old graph-paper-sized clip rectangle.
    local papers = transition and transition:GetPreviewPapers(rect.w - 36)
        or { { index = state.selectedIndex, pose = { offsetX = 0, offsetY = 0, rotation = 0, alpha = 1, scale = 1 } } }
    local paperAnchor = { x = preview.x + preview.w * .5, y = preview.y - 12 }
    sketchDrawing_:BeginFrame()
    drawSheetMotionLayer(painter, sheetOuterClip, preview, state.levels, papers, paperAnchor)
    sketchDrawing_:EndFrame()

    -- The panel nine-slice was painted before the sheets, so lifted graph
    -- paper correctly passes over its four inner corner ornaments. Only the
    -- title and legend remain fixed above the moving paper.
    drawSectionTitle(painter, rect.x + 22, rect.y + 20, "实验装置概览")
    drawPreviewLegend(painter, preview)
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
        local titleX, titleSize = left, 32
        painter:Text(titleX, y,
            ellipsize(painter, level.name or "未命名实验", width, CATALOG_HEADING_FONT, titleSize),
            titleSize, COLORS.ink, nil, CATALOG_HEADING_FONT)
        y = y + 50
        drawDivider(painter, left, y - 7, width, 100)
        painter:Text(left, y, "实验目的", 17, COLORS.brass, nil, CATALOG_HEADING_FONT)
        y = y + 26 + drawWrapped(painter, left, y + 25, width, level.objective or "", 21, COLORS.ink, 29, CATALOG_BODY_FONT)
        y = y + 12
        painter:Text(left, y, "实验说明", 17, COLORS.brass, nil, CATALOG_HEADING_FONT)
        y = y + 26 + drawWrapped(painter, left, y + 25, width, level.description or "暂无说明", 18, COLORS.inkMuted, 26)
        y = y + 12
        painter:Text(left, y, "可用规则", 17, COLORS.brass, nil, CATALOG_HEADING_FONT)
        local cards = enabledCardNames(level, rules)
        local cardText = #cards > 0 and table.concat(cards, " · ") or "无需规则干预"
        y = y + 26 + drawWrapped(painter, left, y + 25, width, cardText, 18, COLORS.ink, 26)
        y = y + 14
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
    else
        painter:Text(left, y, "实验数据读取失败", 22, COLORS.button, nil, CATALOG_BODY_FONT)
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
    local catalogState_ = context.catalogState_
    local experimentProgress_ = context.experimentProgress_
    local _ENV = context

    function InitializeExperimentCatalog()
        local state = catalogState_
        sketchDrawing_:Clear()
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
        state.transition = CatalogTransition.New(state.selectedIndex)
        state.progressFeedback, state.progressFeedbackElapsed = nil, 0
        state.reportSnapshot, state.reportSnapshotAnimation = nil, 0
        state.reportSnapshotClosing = false
    end

    local function closeReportSnapshot()
        if catalogState_.reportSnapshot then
            catalogState_.reportSnapshotClosing = true
            playUIClick()
        end
    end

    function RequestOpenCatalogReportSnapshot()
        local state = catalogState_
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
        if catalogState_.transition and not catalogState_.transition:IsSettled() then return false end
        index = clamp(tonumber(index) or catalogState_.selectedIndex or 1, 1, CONFIG.levelCount)
        if not catalogState_.levels[index] then
            catalogState_.toast = "实验数据不可用"
            catalogState_.toastTime = 2.4
            return false
        end
        catalogState_.selectedIndex = index
        catalogState_.progressFeedback, catalogState_.progressFeedbackElapsed = nil, 0
        if experimentProgress_ then experimentProgress_:ClearPendingFeedback() end
        catalogState_.toast, hudDropdown_ = nil, nil
        sketchDrawing_:Clear()
        BuildLevel(index)
        if not suppressUIClick then playUIClick() end
        return true
    end

    function RequestReturnToCatalog(preselectIndex, suppressUIClick)
        if screen_ == "workshop_preview" then return ExitWorkshopPreview("navigation") end
        local selected = tonumber(preselectIndex) or levelIndex_ or catalogState_.selectedIndex or 1
        if scene_ or level_ then ReleaseLevelRuntime() end
        screen_ = "catalog"
        catalogState_.selectedIndex = clamp(selected, 1, CONFIG.levelCount)
        catalogState_.scroll, catalogState_.scrollMax = 0, 0
        catalogState_.dragStartY, catalogState_.toast = nil, nil
        catalogState_.reportSnapshot, catalogState_.reportSnapshotAnimation = nil, 0
        catalogState_.reportSnapshotClosing = false
        if catalogState_.transition then catalogState_.transition:Reset(catalogState_.selectedIndex) end
        catalogState_.progressFeedback = experimentProgress_ and experimentProgress_:ConsumeFeedback() or nil
        catalogState_.progressFeedbackElapsed = 0
        hudDropdown_ = nil
        if not suppressUIClick then playUIClick() end
        return true
    end

    function RequestEnterWorkshop(selectedLevelId)
        if catalogState_.transition and not catalogState_.transition:IsSettled() then return false end
        local opened = OpenLevelWorkshop(selectedLevelId)
        if opened then sketchDrawing_:Clear() end
        if opened then playUIClick() end
        return opened
    end

    local function selectLevel(index)
        index = clamp(index, 1, CONFIG.levelCount)
        if catalogState_.selectedIndex == index then return end
        catalogState_.selectedIndex = index
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
        if frame_.physicalWidth < frame_.physicalHeight then return end

        local layout = M.ResolveLayout(frame_)
        local x, y = pointerFrame.x, pointerFrame.y
        if input:GetKeyPress(KEY_UP) then selectLevel(state.selectedIndex - 1) end
        if input:GetKeyPress(KEY_DOWN) then selectLevel(state.selectedIndex + 1) end
        local actionsEnabled = not state.transition or state.transition:IsSettled()
        if input:GetKeyPress(KEY_RETURN) and actionsEnabled then RequestStartLevel(state.selectedIndex); return end

        if pointerFrame.pressed then
            for index = 1, CONFIG.levelCount do
                local item = { x = layout.left.x + 12, y = layout.listTop + (index - 1) * layout.listItemHeight,
                    w = layout.left.w - 24, h = layout.listItemHeight - 4 }
                if pointIn(item, x, y) then selectLevel(index); return end
            end
            if actionsEnabled and pointIn(layout.startButton, x, y) then RequestStartLevel(state.selectedIndex); return end
            if actionsEnabled and pointIn(layout.workshopButton, x, y) then
                local level = state.levels[state.selectedIndex]
                RequestEnterWorkshop(level and level.levelId or nil)
                return
            end
            local selectedLevel = state.levels[state.selectedIndex]
            local reportAvailable = selectedLevel and experimentProgress_
                and experimentProgress_:HasReportSnapshot(selectedLevel.levelId) or false
            if actionsEnabled and reportAvailable and pointIn(layout.reportButton, x, y) then
                RequestOpenCatalogReportSnapshot()
                return
            end
            if pointIn(layout.briefViewport, x, y) then
                state.dragStartY, state.dragStartScroll = y, state.scroll
            end
        end
        if not actionsEnabled then
            state.dragStartY = nil
            return
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
            painter:Text(frame_.logicalWidth * .5, frame_.logicalHeight * .5 - 10, "请使用横屏进入实验目录", 32,
                COLORS.ink, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, CATALOG_BODY_FONT)
            painter:Text(frame_.logicalWidth * .5, frame_.logicalHeight * .5 + 38, "LANDSCAPE ORIENTATION REQUIRED", 14,
                COLORS.inkMuted, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, CATALOG_MONO_FONT)
            return
        end

        local layout = M.ResolveLayout(frame_)
        drawPaperPanel(painter, layout.left)
        drawPaperPanel(painter, layout.center)
        drawPaperPanel(painter, layout.right)
        drawCatalogForegroundDecor(painter, frame_)
        drawSectionTitle(painter, layout.left.x + 20, layout.left.y + 20, "实验清单")
        drawSectionTitle(painter, layout.right.x + 20, layout.right.y + 20, "预习报告")

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
            painter:Text(item.x + 13, item.y + item.h * .5, string.format("实验 %02d", index), 18,
                selected and COLORS.ink or COLORS.inkMuted, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, CATALOG_MONO_FONT)
            local name = level and level.name or "数据不可用"
            local nameX = item.x + 92
            local progress = level and experimentProgress_ and experimentProgress_:Get(level.levelId) or nil
            if progress then progress.levelId = level.levelId end
            local statusLeft = drawExperimentProgress(painter, item, progress, state.progressFeedback, state.progressFeedbackElapsed)
            painter:Text(nameX, item.y + item.h * .5,
                ellipsize(painter, name, statusLeft - nameX - 10, CATALOG_HEADING_FONT, 21), 21,
                level and COLORS.ink or COLORS.button, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, CATALOG_HEADING_FONT)
            drawDottedDivider(painter, item.x + 12, item.y + item.h - 3, item.w - 24)
        end

        local level = state.levels[state.selectedIndex]
        local reportAvailable = level and experimentProgress_
            and experimentProgress_:HasReportSnapshot(level.levelId) or false
        if reportAvailable then
            drawReportSnapshotButton(painter, layout.reportButton,
                pointIn(layout.reportButton, pointer.x, pointer.y))
        end
        drawPreview(painter, layout.center, state)
        drawBrief(painter, layout, level, state, Rules)
        local actionsEnabled = not state.transition or state.transition:IsSettled()
        local startEnabled = level ~= nil and actionsEnabled
        drawButton(painter, layout.startButton, "开始实验", true, pointIn(layout.startButton, pointer.x, pointer.y), startEnabled)
        drawButton(painter, layout.workshopButton, "实验工坊", false, pointIn(layout.workshopButton, pointer.x, pointer.y), actionsEnabled)

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
    end
end

return M
