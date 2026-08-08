-- The illustrated title page is one fixed design stage.  Its artwork and
-- interaction rectangles share the same coordinates so resize never changes
-- the relationship between the title, characters, and menu.
local M = {}

local SOURCE_OFFSET_X = 0
local TITLE_FILL = { 248, 231, 206, 255 }
local MENU = {
    x = 1290,
    y = 288,
    width = 410,
    rowHeight = 64,
    rowStep = 64,
    textSize = 29,
    scale = 1.35,
}

local MENU_ITEMS = { "实验目录", "实验工坊", "设置", "退出游戏" }
local MENU_INK = { 43, 70, 47, 255 }
local MENU_MUTED = { 91, 111, 81, 225 }
local MENU_ACCENT = { 164, 139, 76, 255 }
local TIP_COLOR = { 77, 96, 72, 180 }
local OVERLAY_FILL = { 250, 239, 216, 246 }
local MENU_TRANSITION_SECONDS = .14
local CHARACTER_HOVER_SECONDS = .14
local DEGREES_TO_RADIANS = math.pi / 180
local TITLE_EXIT_PIVOT = { x = 602, y = 201 }

-- Cropped source layers keep these original 1870 x 841 canvas positions.  The
-- small padding in the files is intentional: it preserves antialiased edges
-- without paying for the original transparent canvas around each layer.
local TITLE_NODES = {
    { key = "bu", baseX = 148, baseY = 94, w = 216, h = 189, baseRotation = 0, baseScale = 1,
        pivotX = .50, pivotY = .58,
        idle = { poseA = -2, poseB = 1.2, holdA = .46, holdB = .38, transition = .07, initialOffset = 0 } },
    { key = "jing", baseX = 357, baseY = 87, w = 187, h = 197, baseRotation = 0, baseScale = 1,
        pivotX = .51, pivotY = .57,
        idle = { poseA = 1.6, poseB = -1.8, holdA = .36, holdB = .52, transition = .065, initialOffset = .21 } },
    { key = "dian", baseX = 530, baseY = 76, w = 207, h = 206, baseRotation = 0, baseScale = 1,
        pivotX = .49, pivotY = .59,
        idle = { poseA = -1.2, poseB = 2, holdA = .56, holdB = .42, transition = .075, initialOffset = .47 } },
    { key = "li", baseX = 683, baseY = 93, w = 188, h = 232, baseRotation = 0, baseScale = 1,
        pivotX = .50, pivotY = .60,
        idle = { poseA = 2, poseB = -1, holdA = .44, holdB = .62, transition = .06, initialOffset = .13 } },
    { key = "xue", baseX = 858, baseY = 76, w = 197, h = 216, baseRotation = 0, baseScale = 1,
        pivotX = .51, pivotY = .58,
        idle = { poseA = -1.6, poseB = 1.6, holdA = .40, holdB = .50, transition = .07, initialOffset = .61 } },
}

local CHARACTER_NODES = {
    { id = "green_archive", key = "left1", hoverKey = "left1",
        base = { x = 248, y = 291, w = 304, h = 489 },
        outline = { x = 275, y = 275, w = 273, h = 517 },
        baseRotation = 0, baseScale = 1, pivotX = .5, pivotY = .985,
        hit = { x = 228, y = 268, w = 345, h = 535 },
        idle = { kind = "rotation", from = -.8, to = .8, duration = 2.3, delay = .12, phase = .15 } },
    { id = "nomi", key = "left2", hoverKey = "left2",
        base = { x = 530, y = 336, w = 216, h = 438 },
        outline = { x = 522, y = 320, w = 236, h = 467 },
        baseRotation = 0, baseScale = 1, pivotX = .5, pivotY = .99,
        hit = { x = 510, y = 313, w = 256, h = 485 },
        idle = { kind = "offsetY", from = 0, to = -3, duration = 1.6, delay = .24, phase = .58 } },
    { id = "newton", key = "right2", hoverKey = "right2",
        base = { x = 760, y = 305, w = 219, h = 475 },
        outline = { x = 745, y = 295, w = 246, h = 494 },
        baseRotation = 0, baseScale = 1, pivotX = .5, pivotY = .99,
        hit = { x = 740, y = 282, w = 259, h = 520 },
        idle = { kind = "rotation", from = -.5, to = .5, duration = 2.6, delay = .08, phase = .73 } },
    { id = "einstein", key = "right1", hoverKey = "right1",
        base = { x = 974, y = 315, w = 272, h = 465 },
        outline = { x = 967, y = 303, w = 293, h = 491 },
        baseRotation = 0, baseScale = 1, pivotX = .5, pivotY = .99,
        hit = { x = 954, y = 292, w = 312, h = 510 },
        idle = { kind = "scale", from = 1, to = 1.015, duration = 2.15, delay = .41, phase = .34 } },
}

local PROFILE_MODE = {
    TITLE_IDLE = "TITLE_IDLE",
    ENTERING = "ENTERING_PROFILE",
    IDLE = "PROFILE_IDLE",
    EXITING = "EXITING_PROFILE",
}

-- The supplied profile layers share a 1280 x 576 logical canvas.  Doodle,
-- signature, and back were exported at 2000 x 900, the exact same aspect and
-- offsets, so every layer can be drawn over the full 1870 x 841 title stage.
local PROFILE = {
    characterId = "newton",
    plateColor = { 251, 234, 212, 255 },
    root = {
        pivotX = 438.3,
        pivotY = 774.0,
        startOffsetX = 431.2,
        startOffsetY = 1.2,
        startScale = .64,
        targetScale = 1,
    },
    enter = {
        sketchFlipStart = 0,
        sketchFlipEnd = .16,
        formalFlipStart = .16,
        formalFlipEnd = .31,
        moveStart = .31,
        moveEnd = .71,
        plateEnd = .30,
        backdropStart = .36,
        backdropEnd = .74,
        frameStart = .55,
        frameDuration = .17,
        frameStagger = .09,
        doodleStart = .91,
        doodleEnd = 1.07,
        signatureStart = .99,
        signatureEnd = 1.19,
        backStart = 1.08,
        backEnd = 1.22,
        total = 1.22,
    },
    exit = {
        backStart = 0,
        backEnd = .12,
        signatureStart = .05,
        signatureEnd = .22,
        doodleStart = .12,
        doodleEnd = .30,
        backdropStart = .28,
        backdropEnd = .56,
        frameStart = .24,
        frameDuration = .13,
        frameStagger = .07,
        moveStart = .56,
        moveEnd = .96,
        formalFlipStart = .96,
        formalFlipEnd = 1.11,
        sketchFlipStart = 1.11,
        sketchFlipEnd = 1.27,
        plateFadeStart = .96,
        plateFadeEnd = 1.27,
        total = 1.27,
    },
    backdropPivot = { x = 470, y = 416 },
    doodlePivot = { x = 441, y = 446 },
    signatureOffset = 16,
    backPivot = { x = 134, y = 79 },
    backHit = { x = 30, y = 20, w = 230, h = 125 },
}

-- The bands share two perpendicular axes but keep independent centers and
-- lengths. Their deliberate overhangs and gaps make a poster composition,
-- rather than a closed square frame.
local PROFILE_FRAME_BANDS = (function()
    local function bandFromCenter(centerX, centerY, length, angleDegrees, t1, t2,
            baseColor, startColor, endColor, reverse)
        local angle = angleDegrees * DEGREES_TO_RADIANS
        local halfLength = length * .5
        local dx, dy = math.cos(angle) * halfLength, math.sin(angle) * halfLength
        local startX, startY = centerX - dx, centerY - dy
        local endX, endY = centerX + dx, centerY + dy
        if reverse then startX, startY, endX, endY = endX, endY, startX, startY end
        return {
            x1 = startX, y1 = startY, x2 = endX, y2 = endY, t1 = t1, t2 = t2,
            baseColor = baseColor, gradientStartColor = startColor, gradientEndColor = endColor,
        }
    end
    return {
        bandFromCenter(456, 85, 758, -13, 116, 112,
            { 236, 64, 0, 255 }, { 232, 61, 0, 255 }, { 240, 67, 2, 255 }, true),
        bandFromCenter(126, 399, 836, 77, 114, 118,
            { 146, 42, 26, 255 }, { 142, 39, 24, 255 }, { 150, 45, 28, 255 }),
        bandFromCenter(481, 778, 732, -13, 122, 118,
            { 249, 131, 0, 255 }, { 246, 127, 0, 255 }, { 252, 135, 3, 255 }),
        bandFromCenter(830, 456, 816, 77, 108, 104,
            { 255, 108, 0, 255 }, { 252, 104, 0, 255 }, { 255, 112, 2, 255 }, true),
    }
end)()

local SETTINGS = {
    x = 1138, y = 206, w = 560, h = 384,
    music = { x = 1210, y = 332, w = 380 },
    sound = { x = 1210, y = 408, w = 380 },
    mute = { x = 1188, y = 485, w = 420, h = 52 },
}

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function smoothStep(value)
    local t = clamp(value, 0, 1)
    return t * t * (3 - 2 * t)
end

local function lerp(from, to, amount)
    return from + (to - from) * clamp(amount, 0, 1)
end

local function rangeProgress(elapsed, startTime, endTime)
    return clamp((elapsed - startTime) / math.max(.001, endTime - startTime), 0, 1)
end

local function easeOutCubic(value)
    local inverse = 1 - clamp(value, 0, 1)
    return 1 - inverse * inverse * inverse
end

local function easeInCubic(value)
    local t = clamp(value, 0, 1)
    return t * t * t
end

local function easeInOutSine(value)
    return .5 - .5 * math.cos(math.pi * clamp(value, 0, 1))
end

local function yoyoAmount(elapsed, animation)
    local duration = math.max(.001, animation.duration or 1)
    local localTime = math.max(0, elapsed - (animation.delay or 0))
    local cycle = (localTime / duration + (animation.phase or 0)) % 2
    local directed = cycle <= 1 and cycle or 2 - cycle
    return easeInOutSine(directed)
end

local function titlePoseRotation(elapsed, animation)
    local transition = math.max(.001, animation.transition)
    local cycleDuration = animation.holdA + transition + animation.holdB + transition
    local time = (math.max(0, elapsed) + (animation.initialOffset or 0)) % cycleDuration
    if time < animation.holdA then return animation.poseA end
    time = time - animation.holdA
    if time < transition then return lerp(animation.poseA, animation.poseB, time / transition) end
    time = time - transition
    if time < animation.holdB then return animation.poseB end
    time = time - animation.holdB
    return lerp(animation.poseB, animation.poseA, time / transition)
end

local function mixColor(from, to, amount)
    local t = clamp(amount, 0, 1)
    return {
        math.floor(from[1] + (to[1] - from[1]) * t + .5),
        math.floor(from[2] + (to[2] - from[2]) * t + .5),
        math.floor(from[3] + (to[3] - from[3]) * t + .5),
        math.floor(from[4] + (to[4] - from[4]) * t + .5),
    }
end

local function pointIn(rect, x, y)
    return rect and rect.x and rect.y and rect.w and rect.h
        and x >= rect.x and x <= rect.x + rect.w
        and y >= rect.y and y <= rect.y + rect.h
end

local function pointInSlider(rect, x, y)
    return pointIn({ x = rect.x - 12, y = rect.y - 24, w = rect.w + 24, h = 48 }, x, y)
end

local function characterAt(x, y)
    local sourceX = x - SOURCE_OFFSET_X
    for _, character in ipairs(CHARACTER_NODES) do
        if pointIn(character.hit, sourceX, y) then return character end
    end
    return nil
end

local function characterById(characterId)
    for _, character in ipairs(CHARACTER_NODES) do
        if character.id == characterId then return character end
    end
    return nil
end

local function image(painter, handle, x, y, w, h, alpha)
    if handle and handle >= 0 then painter:ImageRect(handle, x, y, w, h, alpha or 255) end
end

local function beginVisualTransform(vg, pivotX, pivotY, offsetX, offsetY, rotation, scaleX, scaleY)
    nvgSave(vg)
    nvgTranslate(vg, pivotX + (offsetX or 0), pivotY + (offsetY or 0))
    if rotation and rotation ~= 0 then nvgRotate(vg, rotation * DEGREES_TO_RADIANS) end
    local sx = scaleX or 1
    local sy = scaleY or sx
    if sx ~= 1 or sy ~= 1 then nvgScale(vg, sx, sy) end
    nvgTranslate(vg, -pivotX, -pivotY)
end

local function drawTitleNode(painter, handle, node, elapsed)
    local rotation = (node.baseRotation or 0) + titlePoseRotation(elapsed, node.idle)
    local pivotX = node.baseX + node.w * node.pivotX
    local pivotY = node.baseY + node.h * node.pivotY
    beginVisualTransform(painter.vg, pivotX, pivotY, 0, 0, rotation, node.baseScale or 1)
    image(painter, handle, node.baseX, node.baseY, node.w, node.h)
    nvgRestore(painter.vg)
end

local function characterIdleTransform(node, elapsed)
    local amount = yoyoAmount(elapsed, node.idle)
    local value = lerp(node.idle.from, node.idle.to, amount)
    if node.idle.kind == "rotation" then return 0, value, 1 end
    if node.idle.kind == "offsetY" then return value, 0, 1 end
    if node.idle.kind == "scale" then return 0, 0, value end
    return 0, 0, 1
end

local function drawCharacterNode(painter, art, node, state, exitPose)
    local elapsed = state.animationElapsed or 0
    local idleOffsetY, idleRotation, idleScale = characterIdleTransform(node, elapsed)
    local hoverAmount = exitPose and 0 or smoothStep((state.characterHoverProgress or {})[node.id] or 0)
    local interactionScale = 1 + .025 * hoverAmount
    local finalScale = (node.baseScale or 1) * idleScale * interactionScale
        * (exitPose and exitPose.scale or 1)
    local pivotX = node.base.x + node.base.w * node.pivotX
    local pivotY = node.base.y + node.base.h * node.pivotY
    beginVisualTransform(painter.vg, pivotX, pivotY, exitPose and exitPose.offsetX or 0, idleOffsetY,
        (node.baseRotation or 0) + idleRotation + (exitPose and exitPose.rotation or 0), finalScale)
    if hoverAmount > .001 then
        image(painter, art.characterHover[node.hoverKey], node.outline.x, node.outline.y,
            node.outline.w, node.outline.h, hoverAmount)
    end
    local alpha = math.floor(255 * (exitPose and exitPose.alpha or 1) + .5)
    image(painter, art.characters[node.key], node.base.x, node.base.y, node.base.w, node.base.h, alpha)
    nvgRestore(painter.vg)
end

local function drawSketchCharacterFlip(painter, art, node, elapsed, flipScaleX)
    local idleOffsetY, idleRotation, idleScale = characterIdleTransform(node, elapsed)
    local rootScale = (node.baseScale or 1) * idleScale
    local pivotX = node.base.x + node.base.w * node.pivotX
    local pivotY = node.base.y + node.base.h * node.pivotY
    beginVisualTransform(painter.vg, pivotX, pivotY, 0, idleOffsetY,
        (node.baseRotation or 0) + idleRotation, rootScale * flipScaleX, rootScale)
    image(painter, art.characters[node.key], node.base.x, node.base.y, node.base.w, node.base.h)
    nvgRestore(painter.vg)
end

local function profilePlateProgress(state)
    local mode = state.profileMode
    local elapsed = state.profileElapsed or 0
    if mode == PROFILE_MODE.ENTERING then
        return easeOutCubic(rangeProgress(elapsed, 0, PROFILE.enter.plateEnd))
    elseif mode == PROFILE_MODE.IDLE then
        return 1
    elseif mode == PROFILE_MODE.EXITING then
        return 1 - easeOutCubic(rangeProgress(elapsed, PROFILE.exit.plateFadeStart, PROFILE.exit.plateFadeEnd))
    end
    return 0
end

local function profileLayerProgress(state, layer)
    local mode = state.profileMode
    local elapsed = state.profileElapsed or 0
    if mode == PROFILE_MODE.IDLE then return 1 end
    if mode == PROFILE_MODE.ENTERING then
        return easeOutCubic(rangeProgress(elapsed, PROFILE.enter[layer .. "Start"], PROFILE.enter[layer .. "End"]))
    end
    if mode == PROFILE_MODE.EXITING then
        return 1 - easeOutCubic(rangeProgress(elapsed, PROFILE.exit[layer .. "Start"], PROFILE.exit[layer .. "End"]))
    end
    return 0
end

local function profileRootTransform(state)
    local root = PROFILE.root
    local mode = state.profileMode
    local elapsed = state.profileElapsed or 0
    local amount = 0
    local flipScaleX = 0
    if mode == PROFILE_MODE.ENTERING then
        amount = easeOutCubic(rangeProgress(elapsed, PROFILE.enter.moveStart, PROFILE.enter.moveEnd))
        flipScaleX = rangeProgress(elapsed, PROFILE.enter.formalFlipStart, PROFILE.enter.formalFlipEnd)
    elseif mode == PROFILE_MODE.IDLE then
        amount = 1
        flipScaleX = 1
    elseif mode == PROFILE_MODE.EXITING then
        amount = 1 - easeInCubic(rangeProgress(elapsed, PROFILE.exit.moveStart, PROFILE.exit.moveEnd))
        flipScaleX = 1 - rangeProgress(elapsed, PROFILE.exit.formalFlipStart, PROFILE.exit.formalFlipEnd)
    end
    return lerp(root.startOffsetX, 0, amount), lerp(root.startOffsetY, 0, amount),
        lerp(root.startScale, root.targetScale, amount), flipScaleX
end

local function drawProfileCharacterLayer(painter, handle, offsetX, offsetY, scale, flipScaleX)
    if not handle or handle < 0 or flipScaleX <= .001 then return end
    local root = PROFILE.root
    beginVisualTransform(painter.vg, root.pivotX, root.pivotY, offsetX, offsetY, 0,
        scale * flipScaleX, scale)
    image(painter, handle, 0, 0, 1870, 841)
    nvgRestore(painter.vg)
end

local function profileFrameProgress(state, index)
    local mode = state.profileMode
    if mode == PROFILE_MODE.IDLE then return 1 end
    local elapsed = state.profileElapsed or 0
    if mode == PROFILE_MODE.ENTERING then
        local startTime = PROFILE.enter.frameStart + (index - 1) * PROFILE.enter.frameStagger
        return easeOutCubic(rangeProgress(elapsed, startTime, startTime + PROFILE.enter.frameDuration))
    elseif mode == PROFILE_MODE.EXITING then
        local reverseIndex = #PROFILE_FRAME_BANDS - index
        local startTime = PROFILE.exit.frameStart + reverseIndex * PROFILE.exit.frameStagger
        return 1 - easeOutCubic(rangeProgress(elapsed, startTime, startTime + PROFILE.exit.frameDuration))
    end
    return 0
end

local function drawGrowingBand(vg, band, progress)
    local amount = clamp(progress, 0, 1)
    if amount <= .001 then return end
    local dx, dy = band.x2 - band.x1, band.y2 - band.y1
    local length = math.sqrt(dx * dx + dy * dy)
    if length <= .001 then return end
    local nx, ny = -dy / length, dx / length
    local endX, endY = lerp(band.x1, band.x2, amount), lerp(band.y1, band.y2, amount)
    local endThickness = lerp(band.t1, band.t2, amount)
    local startHalf, endHalf = band.t1 * .5, endThickness * .5
    nvgBeginPath(vg)
    nvgMoveTo(vg, band.x1 + nx * startHalf, band.y1 + ny * startHalf)
    nvgLineTo(vg, endX + nx * endHalf, endY + ny * endHalf)
    nvgLineTo(vg, endX - nx * endHalf, endY - ny * endHalf)
    nvgLineTo(vg, band.x1 - nx * startHalf, band.y1 - ny * startHalf)
    nvgClosePath(vg)
    local startColor = band.gradientStartColor or band.baseColor
    local endColor = band.gradientEndColor or band.baseColor
    if startColor and endColor then
        -- The endpoints follow this segment's own long axis; the delta stays
        -- deliberately narrow so this reads as flat ink, not a luminous bar.
        nvgFillPaint(vg, nvgLinearGradient(vg, band.x1, band.y1, band.x2, band.y2,
            nvgRGBA(startColor[1], startColor[2], startColor[3], startColor[4]),
            nvgRGBA(endColor[1], endColor[2], endColor[3], endColor[4])))
    else
        nvgFillColor(vg, nvgRGBA(band.baseColor[1], band.baseColor[2], band.baseColor[3], band.baseColor[4]))
    end
    nvgFill(vg)
end

local function drawProfileFrames(painter, state)
    for index, band in ipairs(PROFILE_FRAME_BANDS) do
        drawGrowingBand(painter.vg, band, profileFrameProgress(state, index))
    end
end

local function drawProfileBackdrop(painter, handle, state)
    local progress = profileLayerProgress(state, "backdrop")
    if progress <= .001 then return end
    local amount = smoothStep(progress)
    local scale = lerp(.72, 1, amount)
    beginVisualTransform(painter.vg, PROFILE.backdropPivot.x, PROFILE.backdropPivot.y, 0, 0, 0, scale)
    image(painter, handle, 0, 0, 1870, 841, amount)
    nvgRestore(painter.vg)
end

local function drawProfileDoodle(painter, handle, state)
    local progress = profileLayerProgress(state, "doodle")
    if progress <= .001 then return end
    local scale = .97 + .03 * smoothStep(progress)
    beginVisualTransform(painter.vg, PROFILE.doodlePivot.x, PROFILE.doodlePivot.y, 0, 0, 0, scale)
    image(painter, handle, 0, 0, 1870, 841, progress)
    nvgRestore(painter.vg)
end

local function drawProfileSignature(painter, handle, state)
    local progress = profileLayerProgress(state, "signature")
    if progress <= .001 then return end
    nvgSave(painter.vg)
    nvgTranslate(painter.vg, -PROFILE.signatureOffset * (1 - progress), 0)
    image(painter, handle, 0, 0, 1870, 841, progress)
    nvgRestore(painter.vg)
end

local function drawProfileBack(painter, handle, state)
    local progress = profileLayerProgress(state, "back")
    if progress <= .001 then return end
    local hover = smoothStep(state.profileBackHoverProgress or 0)
    local scale = state.profileBackPressed and .97 or 1 + .03 * hover
    beginVisualTransform(painter.vg, PROFILE.backPivot.x, PROFILE.backPivot.y, -4 * hover, 0, 0, scale)
    image(painter, handle, 0, 0, 1870, 841, progress)
    nvgRestore(painter.vg)
end

local function drawProfileScene(painter, art, state)
    local profileArt = art.profiles and art.profiles[PROFILE.characterId]
    if not profileArt then return end
    local node = characterById(PROFILE.characterId)
    local elapsed = state.profileElapsed or 0
    if state.profileMode == PROFILE_MODE.ENTERING and elapsed < PROFILE.enter.sketchFlipEnd then
        local flip = 1 - rangeProgress(elapsed, PROFILE.enter.sketchFlipStart, PROFILE.enter.sketchFlipEnd)
        drawSketchCharacterFlip(painter, art, node, state.profileSketchElapsed or 0, flip)
    end

    local offsetX, offsetY, scale, flipScaleX = profileRootTransform(state)
    local settled = state.profileMode == PROFILE_MODE.IDLE
    local body = settled and profileArt.bodySettled or profileArt.body
    local head = settled and profileArt.headSettled or profileArt.head
    if not body or body < 0 then body = profileArt.body end
    if not head or head < 0 then head = profileArt.head end
    drawProfileBackdrop(painter, profileArt.backdrop, state)
    drawProfileCharacterLayer(painter, body, offsetX, offsetY, scale, flipScaleX)
    drawProfileFrames(painter, state)
    drawProfileCharacterLayer(painter, head, offsetX, offsetY, scale, flipScaleX)
    drawProfileSignature(painter, profileArt.signature, state)
    drawProfileDoodle(painter, profileArt.doodle, state)
    drawProfileBack(painter, profileArt.back, state)

    if state.profileMode == PROFILE_MODE.EXITING and elapsed >= PROFILE.exit.sketchFlipStart then
        local flip = rangeProgress(elapsed, PROFILE.exit.sketchFlipStart, PROFILE.exit.sketchFlipEnd)
        drawSketchCharacterFlip(painter, art, node, state.profileSketchElapsed or 0, flip)
    end
end

local function drawFourPointStar(vg, x, y, radius, progress)
    local amount = clamp(progress, 0, 1)
    local inner = radius * 0.22
    nvgBeginPath(vg)
    nvgMoveTo(vg, x, y - radius)
    nvgLineTo(vg, x + inner, y - inner)
    nvgLineTo(vg, x + radius, y)
    nvgLineTo(vg, x + inner, y + inner)
    nvgLineTo(vg, x, y + radius)
    nvgLineTo(vg, x - inner, y + inner)
    nvgLineTo(vg, x - radius, y)
    nvgLineTo(vg, x - inner, y - inner)
    nvgClosePath(vg)
    if amount > 0 then
        nvgFillColor(vg, nvgRGBA(MENU_ACCENT[1], MENU_ACCENT[2], MENU_ACCENT[3],
            math.floor(255 * amount + .5)))
        nvgFill(vg)
    end
    local outline = mixColor(MENU_MUTED, MENU_ACCENT, amount)
    nvgStrokeColor(vg, nvgRGBA(outline[1], outline[2], outline[3], outline[4]))
    nvgStrokeWidth(vg, 1.35)
    nvgStroke(vg)
end

local function drawArrow(vg, x, y, color, progress)
    local amount = clamp(progress, 0, 1)
    if amount <= 0 then return end
    local startX = x + 4 * (1 - amount)
    local tipX = x + 14 + 8 * amount
    local headWidth = 4 + 3 * amount
    local headHeight = 2.5 + 2 * amount
    local c = nvgRGBA(color[1], color[2], color[3], math.floor(245 * amount + .5))
    nvgStrokeColor(vg, c)
    nvgStrokeWidth(vg, 1.55)
    nvgBeginPath(vg)
    nvgMoveTo(vg, startX, y)
    nvgLineTo(vg, tipX, y)
    nvgMoveTo(vg, tipX, y)
    nvgLineTo(vg, tipX - headWidth, y - headHeight)
    nvgMoveTo(vg, tipX, y)
    nvgLineTo(vg, tipX - headWidth, y + headHeight)
    nvgStroke(vg)
end

local function drawSlider(painter, rect, label, value)
    local vg = painter.vg
    painter:Text(rect.x, rect.y - 25, label, 19, MENU_INK, nil, "maker-body")
    nvgStrokeColor(vg, nvgRGBA(109, 119, 90, 120))
    nvgStrokeWidth(vg, 2)
    nvgBeginPath(vg)
    nvgMoveTo(vg, rect.x, rect.y)
    nvgLineTo(vg, rect.x + rect.w, rect.y)
    nvgStroke(vg)
    local knobX = rect.x + rect.w * clamp(value, 0, 1)
    nvgBeginPath(vg)
    nvgCircle(vg, knobX, rect.y, 7)
    nvgFillColor(vg, nvgRGBA(MENU_ACCENT[1], MENU_ACCENT[2], MENU_ACCENT[3], 255))
    nvgFill(vg)
    painter:Text(rect.x + rect.w + 18, rect.y, string.format("%d%%", math.floor(value * 100 + .5)),
        17, MENU_INK, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, "maker-body")
end

local function setMusicVolume(state, context, value)
    state.musicVolume = clamp(value, 0, 1)
    if not state.muted then context.setBGMVolume(state.musicVolume) end
end

local function setSoundVolume(state, context, value)
    state.soundVolume = clamp(value, 0, 1)
    local audio = context.uiAudio_
    if audio and audio.setVolume then audio:setVolume(state.muted and 0 or state.soundVolume) end
end

local function setMuted(state, context, muted)
    state.muted = muted == true
    context.setBGMVolume(state.muted and 0 or state.musicVolume)
    local audio = context.uiAudio_
    if audio and audio.setMuted then audio:setMuted(state.muted) end
    if audio and audio.setVolume then audio:setVolume(state.muted and 0 or state.soundVolume) end
end

local function moveTowards(current, target, delta)
    if current < target then return math.min(target, current + delta) end
    if current > target then return math.max(target, current - delta) end
    return current
end

local function updateSelection(state, dt)
    local delta = math.max(0, dt or 0) / MENU_TRANSITION_SECONDS
    for index = 1, #MENU_ITEMS do
        local target = state.selectedIndex == index and 1 or 0
        local current = state.selectionProgress[index] or 0
        state.selectionProgress[index] = moveTowards(current, target, delta)
    end
end

local function updateCharacterHover(state, dt)
    local delta = math.max(0, dt or 0) / CHARACTER_HOVER_SECONDS
    state.characterHoverProgress = state.characterHoverProgress or {}
    for _, node in ipairs(CHARACTER_NODES) do
        local active = state.hoverCharacter == node.id or state.academyIdCardCharacter == node.id
        local target = active and 1 or 0
        local current = state.characterHoverProgress[node.id] or 0
        state.characterHoverProgress[node.id] = moveTowards(current, target, delta)
    end
end

local function menuTop()
    return MENU.y - #MENU_ITEMS * MENU.rowStep * (MENU.scale - 1) * .5
end

local function menuHit(index, x, y)
    local top = menuTop() + (index - 1) * MENU.rowStep * MENU.scale
    return pointIn({
        x = MENU.x - 24,
        y = top,
        w = MENU.width * MENU.scale + 24,
        h = MENU.rowHeight * MENU.scale,
    }, x, y)
end

local function menuIndexAt(x, y)
    for index = 1, #MENU_ITEMS do
        if menuHit(index, x, y) then return index end
    end
    return nil
end

local function drawTitleMenu(painter, state)
    local vg = painter.vg
    local top = menuTop()
    for index, label in ipairs(MENU_ITEMS) do
        local centerY = top + ((index - 1) * MENU.rowStep + MENU.rowHeight * .5) * MENU.scale
        local pressed = state.pressedIndex == index
        local progress = smoothStep(state.selectionProgress[index] or 0)
        local visualProgress = pressed and 1 or progress
        local drawScale = pressed and .98 or 1 + .022 * visualProgress
        local textColor = mixColor(MENU_MUTED, MENU_INK, visualProgress)
        nvgSave(vg)
        nvgTranslate(vg, MENU.x, centerY)
        nvgScale(vg, drawScale * MENU.scale, drawScale * MENU.scale)
        drawFourPointStar(vg, 10, 0, 8.2, visualProgress)
        painter:Text(36 + 4 * visualProgress, 0, label, MENU.textSize, textColor,
            NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, "maker-body")
        drawArrow(vg, MENU.width - 47, 0, MENU_ACCENT, visualProgress)
        nvgRestore(vg)
    end
    painter:Text(MENU.x, top + (#MENU_ITEMS * MENU.rowStep + 27) * MENU.scale,
        "（戳左边四个有角色介绍）", 16 * MENU.scale, TIP_COLOR, nil, "maker-body")
end

local function drawTitleContent(painter, art, state, excludedCharacterId, entrance)
    local titleExitPose = entrance and entrance:GetTitlePose() or nil
    if titleExitPose then
        nvgSave(painter.vg)
        nvgTranslate(painter.vg, TITLE_EXIT_PIVOT.x, TITLE_EXIT_PIVOT.y)
        local titleScale = math.max(0.001, titleExitPose.scale)
        nvgScale(painter.vg, titleScale, titleScale)
        nvgTranslate(painter.vg, -TITLE_EXIT_PIVOT.x, -TITLE_EXIT_PIVOT.y)
        nvgGlobalAlpha(painter.vg, titleExitPose.alpha)
    end
    for _, node in ipairs(TITLE_NODES) do
        drawTitleNode(painter, art.title[node.key], node, state.animationElapsed or 0)
    end
    if titleExitPose then nvgRestore(painter.vg) end
    for index, node in ipairs(CHARACTER_NODES) do
        if node.id ~= excludedCharacterId then
            local characterExitPose = entrance and entrance:GetCharacterPose(index) or nil
            drawCharacterNode(painter, art, node, state, characterExitPose)
        end
    end
    drawTitleMenu(painter, state)
end

local function updateSettingSlider(state, context, pointerX)
    local drag = state.settingsDrag
    local rect = drag == "music" and SETTINGS.music or SETTINGS.sound
    if not rect then return end
    local value = clamp((pointerX - rect.x) / rect.w, 0, 1)
    if drag == "music" then setMusicVolume(state, context, value) else setSoundVolume(state, context, value) end
end

local function activateMenu(state, context, index)
    if index == 1 then
        context.playUIClick()
        return context.RequestReturnToCatalog(1, true)
    elseif index == 2 then
        context.playUIClick()
        local catalogState = context.catalogState_
        local level = catalogState and catalogState.levels and catalogState.levels[1]
        if level and context.RequestEnterWorkshop then return context.RequestEnterWorkshop(level.levelId) end
        return context.RequestReturnToCatalog(1, true)
    elseif index == 3 then
        context.playUIClick()
        state.settingsOpen = true
        state.settingsDrag = nil
        return true
    elseif index == 4 then
        context.playUIClick()
        if _G.engine and engine.Exit then engine:Exit()
        elseif _G.GetEngine and GetEngine() and GetEngine().Exit then GetEngine():Exit() end
        return true
    end
    return false
end

---@param context GameContext
function M.Install(context)
    local _ENV = context
    local state = context.titleState_

    function InitializeTitleScreen()
        state.selectedIndex = 1
        state.focusIndex = 1
        state.hoverIndex = nil
        state.pressedIndex = nil
        state.selectionProgress = { 1, 0, 0, 0 }
        state.animationElapsed = 0
        state.characterHoverProgress = {}
        for _, node in ipairs(CHARACTER_NODES) do state.characterHoverProgress[node.id] = 0 end
        state.settingsOpen = false
        state.settingsDrag = nil
        state.academyIdCardCharacter = nil
        state.academyIdCardElapsed = 0
        state.profileMode = PROFILE_MODE.TITLE_IDLE
        state.profileElapsed = 0
        state.profileCharacterId = nil
        state.profileSketchElapsed = 0
        state.profileBackHover = false
        state.profileBackHoverProgress = 0
        state.profileBackPressed = false
        state.musicVolume = state.musicVolume or .4
        state.soundVolume = state.soundVolume or .55
        state.muted = state.muted == true
        setMusicVolume(state, context, state.musicVolume)
        setSoundVolume(state, context, state.soundVolume)
        setMuted(state, context, state.muted)
    end

    function BeginTitleCatalogExit()
        if state.profileMode ~= PROFILE_MODE.TITLE_IDLE or state.settingsOpen then return false end
        state.hoverIndex = nil
        state.hoverCharacter = nil
        state.pressedIndex = nil
        return true
    end

    function BeginTitleCatalogEnter()
        state.hoverIndex = nil
        state.hoverCharacter = nil
        state.pressedIndex = nil
        state.settingsDrag = nil
    end

    function openAcademyIdCard(characterId)
        if state.profileMode ~= PROFILE_MODE.TITLE_IDLE then return false end
        if characterId == PROFILE.characterId then
            state.profileMode = PROFILE_MODE.ENTERING
            state.profileElapsed = 0
            state.profileCharacterId = characterId
            state.profileSketchElapsed = state.animationElapsed or 0
            state.profileBackHover = false
            state.profileBackHoverProgress = 0
            state.profileBackPressed = false
            state.hoverCharacter = nil
            state.academyIdCardCharacter = characterId
            state.academyIdCardElapsed = 0
            context.playUIClick()
            print("[TitleScreen] entering character profile: " .. characterId)
            return true
        end
        state.academyIdCardCharacter = characterId
        state.academyIdCardElapsed = 0
        print("[TitleScreen] profile assets pending for: " .. tostring(characterId))
        return false
    end

    local function startProfileExit()
        if state.profileMode ~= PROFILE_MODE.IDLE then return false end
        state.profileMode = PROFILE_MODE.EXITING
        state.profileElapsed = 0
        state.profileSketchElapsed = state.animationElapsed or 0
        state.profileBackHover = false
        state.profileBackPressed = false
        context.playUIClick()
        return true
    end

    local function finishProfileExit()
        state.profileMode = PROFILE_MODE.TITLE_IDLE
        state.profileElapsed = 0
        state.profileCharacterId = nil
        state.profileBackHover = false
        state.profileBackHoverProgress = 0
        state.profileBackPressed = false
        state.academyIdCardCharacter = nil
        state.academyIdCardElapsed = 0
    end

    local function updateProfile(frameDt, pointerFrame)
        local mode = state.profileMode
        state.profileElapsed = (state.profileElapsed or 0) + frameDt
        if mode == PROFILE_MODE.ENTERING then
            if state.profileElapsed >= PROFILE.enter.total then
                state.profileMode = PROFILE_MODE.IDLE
                state.profileElapsed = 0
            end
            return
        elseif mode == PROFILE_MODE.EXITING then
            state.profileBackHoverProgress = moveTowards(state.profileBackHoverProgress or 0, 0,
                frameDt / CHARACTER_HOVER_SECONDS)
            if state.profileElapsed >= PROFILE.exit.total then finishProfileExit() end
            return
        end

        local hovered = pointIn(PROFILE.backHit, pointerFrame.x, pointerFrame.y)
        state.profileBackHover = hovered
        state.profileBackHoverProgress = moveTowards(state.profileBackHoverProgress or 0, hovered and 1 or 0,
            frameDt / CHARACTER_HOVER_SECONDS)
        if input:GetKeyPress(KEY_ESCAPE) then
            startProfileExit()
            return
        end
        if pointerFrame.pressed then
            state.profileBackPressed = hovered
        elseif pointerFrame.released then
            local pressed = state.profileBackPressed
            state.profileBackPressed = false
            if pressed and hovered then startProfileExit() end
        elseif not pointerFrame.down then
            state.profileBackPressed = false
        end
    end

    local function updateSettings(pointerFrame)
        if input:GetKeyPress(KEY_ESCAPE) then
            state.settingsOpen = false
            state.settingsDrag = nil
            context.playUIClick()
            return
        end
        if pointerFrame.pressed then
            if pointInSlider(SETTINGS.music, pointerFrame.x, pointerFrame.y) then
                state.settingsDrag = "music"
                updateSettingSlider(state, context, pointerFrame.x)
                return
            elseif pointInSlider(SETTINGS.sound, pointerFrame.x, pointerFrame.y) then
                state.settingsDrag = "sound"
                updateSettingSlider(state, context, pointerFrame.x)
                return
            elseif pointIn(SETTINGS.mute, pointerFrame.x, pointerFrame.y) then
                setMuted(state, context, not state.muted)
                context.playUIClick()
                return
            elseif not pointIn(SETTINGS, pointerFrame.x, pointerFrame.y) then
                state.settingsOpen = false
                state.settingsDrag = nil
                context.playUIClick()
                return
            end
        end
        if state.settingsDrag then
            if pointerFrame.down then updateSettingSlider(state, context, pointerFrame.x)
            else state.settingsDrag = nil end
        end
    end

    function UpdateTitleScreen(dt, pointerFrame)
        local frameDt = math.max(0, dt or 0)
        state.animationElapsed = (state.animationElapsed or 0) + frameDt
        if state.profileMode ~= PROFILE_MODE.TITLE_IDLE then
            updateProfile(frameDt, pointerFrame)
            return
        end
        if state.academyIdCardCharacter then
            state.academyIdCardElapsed = state.academyIdCardElapsed + frameDt
            if state.academyIdCardElapsed > .28 then state.academyIdCardCharacter = nil end
        end
        if state.settingsOpen then
            state.hoverCharacter = nil
            updateCharacterHover(state, frameDt)
            updateSettings(pointerFrame)
            return
        end

        local hovered = menuIndexAt(pointerFrame.x, pointerFrame.y)
        local hoveredCharacter = characterAt(pointerFrame.x, pointerFrame.y)
        state.hoverIndex = hovered
        state.hoverCharacter = hoveredCharacter and hoveredCharacter.id or nil
        if hovered then state.selectedIndex = hovered else state.selectedIndex = state.focusIndex or 1 end

        if input:GetKeyPress(KEY_UP) then
            state.focusIndex = math.max(1, (state.focusIndex or 1) - 1)
            state.selectedIndex = state.focusIndex
        elseif input:GetKeyPress(KEY_DOWN) then
            state.focusIndex = math.min(#MENU_ITEMS, (state.focusIndex or 1) + 1)
            state.selectedIndex = state.focusIndex
        elseif input:GetKeyPress(KEY_RETURN) then
            activateMenu(state, context, state.selectedIndex or 1)
            return
        end

        if pointerFrame.pressed then
            state.pressedIndex = hovered
            if hovered then state.selectedIndex, state.focusIndex = hovered, hovered end
        elseif pointerFrame.released then
            local pressed = state.pressedIndex
            state.pressedIndex = nil
            if pressed and pressed == hovered then activateMenu(state, context, pressed) end
            local character = characterAt(pointerFrame.x, pointerFrame.y)
            if character then
                openAcademyIdCard(character.id)
                return
            end
        end
        updateSelection(state, frameDt)
        updateCharacterHover(state, frameDt)
    end

    local function drawSettings(painter)
        local vg = painter.vg
        painter:FillRect(0, 0, 1870, 841, { 38, 50, 36, 255 }, 54)
        painter:FillRect(SETTINGS.x, SETTINGS.y, SETTINGS.w, SETTINGS.h, OVERLAY_FILL)
        painter:StrokeRect(SETTINGS.x, SETTINGS.y, SETTINGS.w, SETTINGS.h, MENU_ACCENT, 1.4, 225)
        painter:Text(SETTINGS.x + 42, SETTINGS.y + 30, "设置", 30, MENU_INK, nil, "maker-body")
        painter:Text(SETTINGS.x + SETTINGS.w - 42, SETTINGS.y + 39, "ESC 关闭", 15, TIP_COLOR,
            NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE, "maker-body")
        drawSlider(painter, SETTINGS.music, "音乐音量", state.musicVolume)
        drawSlider(painter, SETTINGS.sound, "音效音量", state.soundVolume)
        local checkX, checkY = SETTINGS.mute.x + 18, SETTINGS.mute.y + SETTINGS.mute.h * .5
        nvgBeginPath(vg)
        nvgRect(vg, checkX - 10, checkY - 10, 20, 20)
        if state.muted then
            nvgFillColor(vg, nvgRGBA(MENU_ACCENT[1], MENU_ACCENT[2], MENU_ACCENT[3], 255)); nvgFill(vg)
        else
            nvgStrokeColor(vg, nvgRGBA(MENU_MUTED[1], MENU_MUTED[2], MENU_MUTED[3], 190)); nvgStrokeWidth(vg, 1.4); nvgStroke(vg)
        end
        painter:Text(checkX + 30, checkY, "禁用声音 / 静音", 20, MENU_INK,
            NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, "maker-body")
    end

    function DrawTitleScreen(visual)
        if not painter_ or not frame_ then return end
        local art = painter_.images and painter_.images.ui and painter_.images.ui.titleScreen
        if not art then return end
        nvgSave(painter_.vg)
        nvgTranslate(painter_.vg, visual and visual.rootOffsetX or 0, 0)
        local offsetX = SOURCE_OFFSET_X
        image(painter_, art.background, offsetX, 0, 1870, 841)
        if state.profileMode == PROFILE_MODE.TITLE_IDLE then
            drawTitleContent(painter_, art, state, nil, visual and visual.transition or nil)
            if state.settingsOpen then drawSettings(painter_) end
            nvgRestore(painter_.vg)
            return
        end

        local plateProgress = profilePlateProgress(state)
        if plateProgress < .999 then drawTitleContent(painter_, art, state, PROFILE.characterId, nil) end
        painter_:FillRect(0, 0, 1870, 841, PROFILE.plateColor, math.floor(255 * plateProgress + .5))
        drawProfileScene(painter_, art, state)
        nvgRestore(painter_.vg)
    end
end

M.TITLE_FILL = TITLE_FILL
M.DESIGN_WIDTH = 1870
M.DESIGN_HEIGHT = 841

return M
