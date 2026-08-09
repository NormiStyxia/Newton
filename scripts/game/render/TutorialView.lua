-- render/TutorialView: lightweight hand-drawn guidance overlay.
local View = {}

local HIGHLIGHT_COLOR = { 155, 204, 126, 255 }
local HIGHLIGHT_SHADOW = { 43, 72, 52, 255 }
local TEXT_COLOR = { 49, 73, 57, 255 }
local PANEL_FILL = { 242, 235, 207, 245 }
local PANEL_STROKE = { 112, 137, 93, 240 }

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function drawArrow(vg, x, startY, endY, alpha)
    local color = nvgRGBA(HIGHLIGHT_COLOR[1], HIGHLIGHT_COLOR[2], HIGHLIGHT_COLOR[3], alpha)
    nvgStrokeColor(vg, color)
    nvgStrokeWidth(vg, 4)
    nvgLineCap(vg, NVG_ROUND)
    nvgBeginPath(vg)
    nvgMoveTo(vg, x, startY)
    nvgLineTo(vg, x, endY)
    nvgStroke(vg)

    nvgFillColor(vg, color)
    nvgBeginPath(vg)
    nvgMoveTo(vg, x, endY + 1)
    nvgLineTo(vg, x - 12, endY - 14)
    nvgLineTo(vg, x + 12, endY - 14)
    nvgClosePath(vg)
    nvgFill(vg)
end

local function targetCardPose(context, targetId)
    if not context.CardEntries or not context.CardHomePose then return nil end
    local pose = context.CurrentCardVisualPose and context.CurrentCardVisualPose(targetId)
    if pose then return pose end
    return context.CardHomePose(targetId)
end

function View.Draw(painter, frame, context)
    if not painter or not frame or not context or not context.GetTutorialRenderModel then return end
    if context.replayActive_ or context.success_ or context.failed_ or context.assistSceneActive_ then return end
    local model = context.GetTutorialRenderModel()
    if not model.visible or model.targetType ~= "card" then return end

    local pose = targetCardPose(context, model.targetId)
    if not pose then return end

    local elapsed = model.elapsed or 0
    local pulse = 0.5 + 0.5 * math.sin(elapsed * math.pi * 2.4)
    local cardWidth = context.CARD_RENDER_WIDTH or 124
    local cardHeight = context.CARD_RENDER_HEIGHT or 202
    local scale = pose.scale or 1
    local halfWidth = cardWidth * scale * 0.5
    local halfHeight = cardHeight * scale * 0.5
    local x, y = pose.x, pose.y
    local alpha = math.floor(145 + pulse * 80)

    nvgSave(painter.vg)
    nvgTranslate(painter.vg, x, y)
    nvgRotate(painter.vg, math.rad(pose.angle or 0))
    nvgStrokeColor(painter.vg, nvgRGBA(HIGHLIGHT_SHADOW[1], HIGHLIGHT_SHADOW[2], HIGHLIGHT_SHADOW[3], 90))
    nvgStrokeWidth(painter.vg, 8)
    nvgBeginPath(painter.vg)
    nvgRoundedRect(painter.vg, -halfWidth - 8, -halfHeight - 8,
        cardWidth * scale + 16, cardHeight * scale + 16, 11)
    nvgStroke(painter.vg)
    nvgStrokeColor(painter.vg, nvgRGBA(HIGHLIGHT_COLOR[1], HIGHLIGHT_COLOR[2], HIGHLIGHT_COLOR[3], alpha))
    nvgStrokeWidth(painter.vg, 3)
    nvgBeginPath(painter.vg)
    nvgRoundedRect(painter.vg, -halfWidth - 5, -halfHeight - 5,
        cardWidth * scale + 10, cardHeight * scale + 10, 9)
    nvgStroke(painter.vg)
    nvgRestore(painter.vg)

    local tipY = y - halfHeight - 10
    local arrowTop = math.max(frame.playfieldY + 28, tipY - 70 - pulse * 4)
    drawArrow(painter.vg, x, arrowTop, tipY, alpha)

    local labelWidth = math.max(190, math.min(280, cardWidth * scale + 50))
    local labelHeight = 58
    local labelX = clamp(x - labelWidth * 0.5, frame.playfieldX + 12,
        frame.playfieldX + frame.playfieldWidth - labelWidth - 12)
    local labelY = math.max(frame.playfieldY + 10, arrowTop - labelHeight - 10)
    painter:RoundedRect(labelX, labelY, labelWidth, labelHeight, 7,
        PANEL_FILL, PANEL_STROKE, 1.5)
    painter:Text(labelX + labelWidth * 0.5, labelY + 9, model.instruction or "",
        19, TEXT_COLOR, NVG_ALIGN_CENTER + NVG_ALIGN_TOP, "maker-display")
    painter:Text(labelX + labelWidth * 0.5, labelY + 34, model.hint or "",
        15, TEXT_COLOR, NVG_ALIGN_CENTER + NVG_ALIGN_TOP, "maker-body")
end

return View
