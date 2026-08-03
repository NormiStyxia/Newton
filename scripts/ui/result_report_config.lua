local M = {}

-- All report styling lives here so the first procedural pass can later swap
-- fonts and decorative assets without changing layout or interaction code.
M.ReportColors = {
    paper = { 245, 235, 207, 255 },
    paperLight = { 251, 246, 232, 255 },
    ink = { 41, 73, 54, 255 },
    inkMuted = { 113, 128, 109, 255 },
    border = { 62, 96, 72, 255 },
    divider = { 140, 153, 126, 255 },
    primary = { 65, 107, 74, 255 },
    primaryText = { 248, 240, 215, 255 },
    danger = { 182, 80, 69, 255 },
    dropdownHover = { 231, 235, 207, 255 },
    disabled = { 177, 181, 160, 255 },
    overlay = { 45, 52, 39, 255 },
    white = { 255, 255, 255, 255 },
}

M.Layout = {
    width = 410,
    height = 650,
    maxHeightRatio = 0.82,
    enterDuration = 0.28,
    exitDuration = 0.18,
    maxTextLines = 2,
    reviewFontMinSize = 15,
    requireSelfReview = true,
    padding = 24,
    innerBorder = 5,
    buttonHeight = 34,
    buttonGap = 8,
}

M.ReviewAuthorStyles = {
    nomi = { font = "maker-body", fontSize = 19, color = M.ReportColors.ink, alignment = "left" },
    newton = { font = "maker-body", fontSize = 18, color = M.ReportColors.ink, alignment = "left" },
    einstein = { font = "maker-body", fontSize = 18, color = M.ReportColors.ink, alignment = "left" },
    green = { font = "maker-body", fontSize = 17, color = M.ReportColors.ink, alignment = "left", useMonospace = false },
}

M.NewtonReviewTiers = {
    { min = 0, max = 24, underlineCount = 0, fontWeight = "normal", textShake = 0, dangerAccent = false, text = "结果基本合格。至少这次没有把最简单的实验也弄坏。" },
    { min = 25, max = 49, underlineCount = 0, fontWeight = "normal", textShake = 0, dangerAccent = false, text = "观测成立。若能减少那些毫无必要的发挥，实验会更像实验。" },
    { min = 50, max = 74, underlineCount = 1, fontWeight = "normal", textShake = 0, dangerAccent = false, text = "结果已记录。请不要误以为成功一次，就足以证明你的方法值得推广。" },
    { min = 75, max = 99, underlineCount = 2, fontWeight = "medium", textShake = 0, dangerAccent = true, text = "实验目标确已完成。本人拒绝承认这套操作与严谨、理性或常识存在关系。" },
    { min = 100, max = 100, underlineCount = 2, fontWeight = "medium", textShake = 0, dangerAccent = true, text = "报告保留，方法作废。实验人员请自行离开，勿迫使我调整其离场速度。" },
}

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

function M.ResolveRect(frame)
    local width = math.min(M.Layout.width, math.max(280, frame.logicalWidth - 36))
    local height = math.min(M.Layout.height, math.max(480, frame.logicalHeight * M.Layout.maxHeightRatio))
    local centerX = frame.playfieldX + frame.playfieldWidth * 0.5
    local centerY = frame.logicalHeight * 0.5
    return {
        x = centerX - width * 0.5,
        y = centerY - height * 0.5,
        w = width,
        h = height,
    }
end

function M.ResolveZones(rect, hasReplay)
    local padding = M.Layout.padding
    local selfBox = { x = rect.x + padding, y = rect.y + 238, w = rect.w - padding * 2, h = 32 }
    local bottom = rect.y + rect.h - padding
    local nextButton = { x = rect.x + padding, y = bottom - M.Layout.buttonHeight, w = rect.w - padding * 2, h = M.Layout.buttonHeight }
    local secondaryY = nextButton.y - M.Layout.buttonGap - M.Layout.buttonHeight
    local secondaryWidth = hasReplay and (nextButton.w - M.Layout.buttonGap) * 0.5 or nextButton.w
    local retry = { x = nextButton.x, y = secondaryY, w = secondaryWidth, h = M.Layout.buttonHeight }
    local replay = hasReplay and {
        x = nextButton.x + secondaryWidth + M.Layout.buttonGap,
        y = secondaryY,
        w = secondaryWidth,
        h = M.Layout.buttonHeight,
    } or nil
    return { selfBox = selfBox, retry = retry, replay = replay, next = nextButton }
end

function M.NewtonReview(anger)
    anger = clamp(tonumber(anger) or 0, 0, 100)
    for _, tier in ipairs(M.NewtonReviewTiers) do
        if anger >= tier.min and anger <= tier.max then return tier.text, tier end
    end
    return M.NewtonReviewTiers[1].text, M.NewtonReviewTiers[1]
end

return M
