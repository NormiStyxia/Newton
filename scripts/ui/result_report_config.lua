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
    summaryHeading = { 77, 105, 80, 255 },
    summaryValue = { 39, 73, 52, 255 },
    summaryRule = { 100, 122, 91, 255 },
    summaryMuted = { 92, 113, 87, 255 },
}

M.Layout = {
    artWidth = 1086,
    artHeight = 1448,
    width = 520,
    height = 760,
    maxHeightRatio = 0.90,
    enterDuration = 0.28,
    exitDuration = 0.18,
    maxTextLines = 2,
    reviewFontMinSize = 15,
    requireSelfReview = false,
    fallbackSelfReview = "反正绿毛同事会补",
    selfReviewFontSize = 18,
    selfReviewOptionFontSize = 18,
    dropdownOptionGap = 5,
    padding = 24,
    innerBorder = 5,
    buttonHeight = 34,
    buttonGap = 8,
    scoreSummary = {
        font = "report-summary",
        referenceReportWidth = 570,
        left = 122,
        right = 964,
        topRuleY = 369,
        headingY = 385,
        valueY = 421,
        bottomRuleY = 508,
        summaryY = 497,
        columnCenters = { 225, 543, 817 },
        separators = { 395, 693 },
        separatorTop = 389,
        separatorBottom = 481,
        separatorNodeY = 434,
        headingSize = 16,
        scoreSize = 43,
        scoreSuffixSize = 22,
        ratingSize = 29,
        interventionSize = 43,
        interventionSuffixSize = 22,
        summarySize = 15,
        valueSuffixOffsetY = 16,
        valueGap = 2,
        headingMaxWidth = 176,
        ratingMaxWidth = 236,
        summaryMaxWidth = 410,
        bottomRuleGap = 18,
        lineWidth = 1.6,
        diamondRadius = 4,
    },
}

M.ReviewAuthorStyles = {
    nomi = { font = "nomi-font", fontSize = 19, color = M.ReportColors.ink, alignment = "left" },
    newton = { font = "report-newton", fontSize = 18, color = M.ReportColors.ink, alignment = "left" },
    einstein = { font = "report-einstein", fontSize = 18, color = M.ReportColors.ink, alignment = "left" },
    green = { font = "report-green", fontSize = 17, color = M.ReportColors.ink, alignment = "left", useMonospace = false },
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
    local aspect = M.Layout.artWidth / M.Layout.artHeight
    local height = math.min(M.Layout.height, math.max(520, frame.logicalHeight * M.Layout.maxHeightRatio))
    local width = height * aspect
    local maxWidth = math.max(360, frame.logicalWidth - 36)
    if width > maxWidth then
        width = maxWidth
        height = width / aspect
    end
    local centerX = frame.logicalWidth * 0.5
    local centerY = frame.logicalHeight * 0.5
    return {
        x = centerX - width * 0.5,
        y = centerY - height * 0.5,
        w = width,
        h = height,
    }
end

function M.ResolveZones(rect, hasReplay)
    local function artRect(x, y, w, h)
        return {
            x = rect.x + rect.w * x / M.Layout.artWidth,
            y = rect.y + rect.h * y / M.Layout.artHeight,
            w = rect.w * w / M.Layout.artWidth,
            h = rect.h * h / M.Layout.artHeight,
        }
    end
    local selfBox = artRect(237, 621, 746, 102)
    local retry = artRect(176, 1157, 337, 93)
    local replay = hasReplay and artRect(557, 1141, 350, 105) or nil
    local nextButton = artRect(169, 1267, 739, 115)
    return { selfBox = selfBox, retry = retry, replay = replay, next = nextButton }
end

function M.ResolveReportArtRect(rect, x, y, w, h)
    return {
        x = rect.x + rect.w * x / M.Layout.artWidth,
        y = rect.y + rect.h * y / M.Layout.artHeight,
        w = rect.w * w / M.Layout.artWidth,
        h = rect.h * h / M.Layout.artHeight,
    }
end

function M.NewtonReview(anger)
    anger = clamp(tonumber(anger) or 0, 0, 100)
    for _, tier in ipairs(M.NewtonReviewTiers) do
        if anger >= tier.min and anger <= tier.max then return tier.text, tier end
    end
    return M.NewtonReviewTiers[1].text, M.NewtonReviewTiers[1]
end

return M
