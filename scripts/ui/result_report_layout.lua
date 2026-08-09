local Config = require("ui.result_report_config")

local M = {}

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function easeOut(value)
    value = clamp(value, 0, 1)
    return 1 - (1 - value) * (1 - value)
end

local function utf8Length(value)
    return utf8.len(value or "") or #(value or "")
end

local function trimUtf8(value, keep)
    local characters = {}
    for _, codepoint in utf8.codes(value or "") do
        characters[#characters + 1] = utf8.char(codepoint)
        if #characters >= keep then break end
    end
    return table.concat(characters)
end

local function splitLastUtf8(value)
    local start = utf8.offset(value or "", -1)
    if not start then return "", value or "" end
    return value:sub(1, start - 1), value:sub(start)
end

local NO_BREAK_PUNCTUATION = {
    ["，"] = true, ["。"] = true, ["！"] = true, ["？"] = true, ["；"] = true,
    ["："] = true, ["、"] = true, ["》"] = true, ["】"] = true, ["〕"] = true,
    ["〉"] = true, ["」"] = true, ["』"] = true, ["］"] = true, ["）"] = true,
    ["%"] = true, ["."] = true, [","] = true, ["!"] = true, ["?"] = true,
    [";"] = true, [":"] = true, ["]"] = true, ["}"] = true, [")"] = true,
    ["…"] = true, ["—"] = true, ["～"] = true, ["·"] = true,
    ["\""] = true, ["'"] = true, ["”"] = true, ["’"] = true,
}

local function isNoBreakPunctuation(character)
    return NO_BREAK_PUNCTUATION[character] == true
end

local function wrapText(painter, value, maxWidth, font, size, maxLines)
    painter:UseFont(font)
    nvgFontSize(painter.vg, size)
    nvgTextAlign(painter.vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    local lines, line, overflow = {}, "", false
    for _, codepoint in utf8.codes(value or "") do
        local character = utf8.char(codepoint)
        if character == "\n" then
            lines[#lines + 1] = line
            line = ""
        else
            local candidate = line .. character
            local measured = nvgTextBounds(painter.vg, 0, 0, candidate, nil)
            if type(measured) ~= "number" then measured = utf8Length(candidate) * size * 0.92 end
            if line ~= "" and measured > maxWidth then
                if isNoBreakPunctuation(character) then
                    local prefix, last = splitLastUtf8(line)
                    if prefix ~= "" then
                        lines[#lines + 1] = prefix
                        line = last .. character
                    else
                        lines[#lines + 1] = line
                        line = character
                    end
                else
                    lines[#lines + 1] = line
                    line = character
                end
            else
                line = candidate
            end
        end
    end
    if line ~= "" or #lines == 0 then lines[#lines + 1] = line end
    if #lines > maxLines then
        overflow = true
        while #lines > maxLines do table.remove(lines) end
        lines[maxLines] = trimUtf8(lines[maxLines], math.max(1, utf8Length(lines[maxLines]) - 3)) .. "..."
    end
    return lines, overflow
end

local function drawWrappedText(painter, x, y, width, value, font, size, minSize, maxLines, color, align, lineGap, alpha)
    local currentSize = size
    local lines, overflow
    repeat
        lines, overflow = wrapText(painter, value or "", width, font, currentSize, maxLines)
        if overflow and currentSize > minSize then currentSize = currentSize - 1 end
    until not overflow or currentSize <= minSize
    for index, line in ipairs(lines) do
        painter:Text(x, y + (index - 1) * lineGap, line, currentSize, color, align, font, alpha)
    end
    return currentSize, overflow
end

local function drawContainedWrappedText(painter, rect, value, font, size, minSize, maxLines, color, alpha)
    local currentSize = size
    local lines, overflow
    repeat
        lines, overflow = wrapText(painter, value or "", rect.w, font, currentSize, maxLines)
        if overflow and currentSize > minSize then currentSize = currentSize - 1 end
    until not overflow or currentSize <= minSize

    local lineGap = currentSize + 1
    local blockHeight = currentSize + (#lines - 1) * lineGap
    local textY = rect.y + math.max(0, (rect.h - blockHeight) * 0.5)
    nvgSave(painter.vg)
    nvgIntersectScissor(painter.vg, rect.x, rect.y, rect.w, rect.h)
    for index, line in ipairs(lines) do
        painter:Text(rect.x, textY + (index - 1) * lineGap, line, currentSize, color,
            NVG_ALIGN_LEFT + NVG_ALIGN_TOP, font, alpha)
    end
    nvgRestore(painter.vg)
    return currentSize, overflow
end

local function drawDiamond(painter, x, y, radius, color, alpha)
    local vg = painter.vg
    nvgBeginPath(vg)
    nvgMoveTo(vg, x, y - radius)
    nvgLineTo(vg, x + radius, y)
    nvgLineTo(vg, x, y + radius)
    nvgLineTo(vg, x - radius, y)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(color[1], color[2], color[3], alpha))
    nvgFill(vg)
end

local function drawLeaf(painter, x, y, scale, color, alpha)
    local vg = painter.vg
    nvgSave(vg)
    nvgTranslate(vg, x, y)
    nvgRotate(vg, -0.35)
    nvgBeginPath(vg)
    nvgMoveTo(vg, 0, 0)
    nvgBezierTo(vg, 8 * scale, -12 * scale, 19 * scale, -10 * scale, 22 * scale, 0)
    nvgBezierTo(vg, 13 * scale, 6 * scale, 5 * scale, 8 * scale, 0, 0)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(color[1], color[2], color[3], alpha))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(color[1], color[2], color[3], alpha))
    nvgStrokeWidth(vg, 1)
    nvgBeginPath(vg)
    nvgMoveTo(vg, 1, 1)
    nvgLineTo(vg, 17 * scale, -5 * scale)
    nvgStroke(vg)
    nvgRestore(vg)
end

local function drawDivider(painter, x, y, width, alpha)
    painter:FillRect(x, y, width, 1, Config.ReportColors.divider, alpha)
end

local function measureText(painter, value, font, size)
    painter:UseFont(font)
    nvgFontSize(painter.vg, size)
    nvgTextAlign(painter.vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    local width = nvgTextBounds(painter.vg, 0, 0, value, nil)
    if type(width) ~= "number" then return utf8Length(value) * size * 0.82 end
    return width
end

local function fitTextSize(painter, value, font, preferredSize, maxWidth, minimumSize)
    local size = preferredSize
    while size > minimumSize and measureText(painter, value, font, size) > maxWidth do
        size = math.max(minimumSize, size - 0.5)
    end
    return size
end

local function drawHairline(painter, x1, y1, x2, y2, color, width, alpha)
    local vg = painter.vg
    nvgBeginPath(vg)
    nvgMoveTo(vg, x1, y1)
    nvgLineTo(vg, x2, y2)
    nvgStrokeColor(vg, nvgRGBA(color[1], color[2], color[3], alpha))
    nvgStrokeWidth(vg, width)
    nvgStroke(vg)
end

local function drawMixedValue(painter, centerX, y, mainText, suffixText, font,
        mainSize, suffixSize, suffixOffsetY, gap, maxWidth, color, alpha)
    local mainWidth = measureText(painter, mainText, font, mainSize)
    local suffixWidth = measureText(painter, suffixText, font, suffixSize)
    local totalWidth = mainWidth + gap + suffixWidth
    if totalWidth > maxWidth then
        local scale = maxWidth / totalWidth
        mainSize = mainSize * scale
        suffixSize = suffixSize * scale
        suffixOffsetY = suffixOffsetY * scale
        gap = gap * scale
        mainWidth = measureText(painter, mainText, font, mainSize)
        suffixWidth = measureText(painter, suffixText, font, suffixSize)
        totalWidth = mainWidth + gap + suffixWidth
    end
    local startX = centerX - totalWidth * 0.5
    painter:Text(startX, y, mainText, mainSize, color,
        NVG_ALIGN_LEFT + NVG_ALIGN_TOP, font, alpha)
    painter:Text(startX + mainWidth + gap, y + suffixOffsetY, suffixText, suffixSize, color,
        NVG_ALIGN_LEFT + NVG_ALIGN_TOP, font, alpha)
end

-- The artwork provides the frame; this is the requested stateful disclosure arrow.
local function drawDropdownArrow(painter, x, y, size, progress, color, alpha)
    local vg = painter.vg
    local angle = math.pi - easeOut(progress) * math.pi * 0.5
    local ux, uy = math.cos(angle), math.sin(angle)
    local px, py = -uy, ux
    local baseX = x - ux * size * 0.9
    local baseY = y - uy * size * 0.9
    nvgBeginPath(vg)
    nvgMoveTo(vg, x + ux * size, y + uy * size)
    nvgLineTo(vg, baseX + px * size * 0.78, baseY + py * size * 0.78)
    nvgLineTo(vg, baseX - px * size * 0.78, baseY - py * size * 0.78)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(color[1], color[2], color[3], alpha))
    nvgFill(vg)
end

---@param context GameContext
function M.Install(context)
    local _ENV = context

    local function drawScoreSummary(painter, state, reportWidth, artPoint, artWidth, artHeight, alpha)
        local layout = Config.Layout.scoreSummary
        local colors = Config.ReportColors
        local font = layout.font
        local fontScale = clamp(reportWidth / layout.referenceReportWidth, 0.63, 1)
        local lineAlpha = math.floor(alpha * 0.82)
        local lineWidth = math.max(0.7, artHeight(layout.lineWidth))
        local diamondRadius = math.max(1.8, artHeight(layout.diamondRadius))
        local leftX, topY = artPoint(layout.left, layout.topRuleY)
        local rightX = artPoint(layout.topRuleRight, layout.topRuleY)
        local centerX = artPoint((layout.left + layout.right) * 0.5, layout.topRuleY)

        drawHairline(painter, leftX, topY, centerX - diamondRadius * 2.4, topY,
            colors.summaryRule, lineWidth, lineAlpha)
        drawHairline(painter, centerX + diamondRadius * 2.4, topY, rightX, topY,
            colors.summaryRule, lineWidth, lineAlpha)
        drawDiamond(painter, centerX, topY, diamondRadius, colors.summaryRule, lineAlpha)

        for _, separatorArtX in ipairs(layout.separators) do
            local separatorX, separatorTop = artPoint(separatorArtX, layout.separatorTop)
            local _, separatorBottom = artPoint(separatorArtX, layout.separatorBottom)
            local _, nodeY = artPoint(separatorArtX, layout.separatorNodeY)
            drawHairline(painter, separatorX, separatorTop, separatorX, separatorBottom,
                colors.summaryRule, lineWidth, lineAlpha)
            drawDiamond(painter, separatorX, nodeY, diamondRadius, colors.summaryRule, lineAlpha)
        end

        local headings = { "实验得分", "实验评定", "规则干预" }
        local headingSize = layout.headingSize * fontScale
        local headingMaxWidth = artWidth(layout.headingMaxWidth)
        local _, headingY = artPoint(0, layout.headingY)
        for index, label in ipairs(headings) do
            local columnX = artPoint(layout.columnCenters[index], layout.headingY)
            local fittedSize = fitTextSize(painter, label, font, headingSize,
                headingMaxWidth, headingSize * 0.78)
            painter:Text(columnX, headingY, label, fittedSize, colors.summaryHeading,
                NVG_ALIGN_CENTER + NVG_ALIGN_TOP, font, alpha)
        end

        local scoreX, valueY = artPoint(layout.columnCenters[1], layout.valueY)
        drawMixedValue(painter, scoreX, valueY,
            tostring(math.floor(tonumber(state.score) or 60)),
            " / " .. tostring(math.floor(tonumber(state.maxScore) or 100)),
            font, layout.scoreSize * fontScale, layout.scoreSuffixSize * fontScale,
            layout.valueSuffixOffsetY * fontScale, layout.valueGap * fontScale,
            artWidth(layout.separators[1] - layout.left - 24), colors.summaryValue, alpha)

        local ratingX = artPoint(layout.columnCenters[2], layout.valueY)
        local rating = tostring(state.ratingLabel or "观测成立")
        local ratingSize = fitTextSize(painter, rating, font, layout.ratingSize * fontScale,
            artWidth(layout.ratingMaxWidth), layout.ratingSize * fontScale * 0.7)
        painter:Text(ratingX, valueY + 5 * fontScale, rating, ratingSize, colors.summaryValue,
            NVG_ALIGN_CENTER + NVG_ALIGN_TOP, font, alpha)

        local interventionX = artPoint(layout.columnCenters[3], layout.valueY)
        drawMixedValue(painter, interventionX, valueY,
            tostring(math.floor(tonumber(state.interventionCount) or 0)), " 张", font,
            layout.interventionSize * fontScale, layout.interventionSuffixSize * fontScale,
            layout.valueSuffixOffsetY * fontScale, layout.valueGap * fontScale,
            artWidth(layout.right - layout.separators[2] - 24), colors.summaryValue, alpha)

    end

    local function drawReview(painter, state, key, author, y, columns, alpha)
        local style = Config.ReviewAuthorStyles[key]
        painter:Text(columns.nameX, y, author, style.fontSize, style.color,
            NVG_ALIGN_LEFT + NVG_ALIGN_TOP, style.font, alpha)
        local body = state[key .. "Review"] or "暂无评语。"
        local textColor = style.color
        if key == "newton" and state.newtonTier and state.newtonTier.dangerAccent then textColor = Config.ReportColors.danger end
        local size = style.fontSize
        local lines, overflow
        repeat
            lines, overflow = wrapText(painter, body, columns.bodyW, style.font, size, Config.Layout.maxTextLines)
            if overflow and size > Config.Layout.reviewFontMinSize then size = size - 1 end
        until not overflow or size <= Config.Layout.reviewFontMinSize
        local lineGap = math.max(16, size + 2)
        local bodyY = y
        for index, line in ipairs(lines) do
            painter:Text(columns.bodyX, bodyY + (index - 1) * lineGap, line, size, textColor,
                NVG_ALIGN_LEFT + NVG_ALIGN_TOP, style.font, alpha)
        end
        if overflow and not state.reviewOverflowLogged[key] then
            state.reviewOverflowLogged[key] = true
            print(string.format("[ResultReport] review text too long: %s", key))
        end
    end

    function DrawResultReport()
        if not IsResultReportVisible() then return end
        local state = resultReportState_
        local progress = easeOut(resultReportAnimation_)
        local alpha = math.floor(255 * progress)
        local frame = frame_
        local rect = Config.ResolveRect(frame)
        local hasReplay = HasResultReportReplay()
        local zones = Config.ResolveZones(rect, hasReplay)
        local y = rect.y - (1 - progress) * 24
        local x = rect.x
        local w = rect.w
        local c = Config.ReportColors
        local offsetY = y - rect.y
        local function shiftZone(zone)
            if not zone then return nil end
            return { x = zone.x, y = zone.y + offsetY, w = zone.w, h = zone.h }
        end
        local drawZones = {
            selfBox = shiftZone(zones.selfBox),
            retry = shiftZone(zones.retry),
            replay = shiftZone(zones.replay),
            next = shiftZone(zones.next),
        }

        -- Dim the same full viewport that Canvas:Begin backgrounds. The
        -- report mask must include letterbox padding without inheriting the
        -- gameplay stage scissor; the companion is drawn afterward.
        nvgSave(painter_.vg)
        nvgResetScissor(painter_.vg)
        painter_:FillRect(0, -(frame.stageOffsetY or 0), frame.logicalWidth,
            frame.viewportLogicalHeight or frame.logicalHeight,
            c.overlay, math.floor(82 * progress))
        nvgRestore(painter_.vg)
        local reportBase = painter_.images and painter_.images.ui and painter_.images.ui.reportBase
        if reportBase and reportBase >= 0 then
            painter_:ImageRect(reportBase, x, y, w, rect.h, progress)
        else
            painter_:FillRect(x, y, w, rect.h, c.paper, alpha)
        end
        local reportImages = painter_.images and painter_.images.ui
        local reportDropdown = reportImages and reportImages.reportDropdown

        local function artPoint(px, py)
            return x + w * px / Config.Layout.artWidth, y + rect.h * py / Config.Layout.artHeight
        end
        local function artWidth(value)
            return w * value / Config.Layout.artWidth
        end
        local function artHeight(value)
            return rect.h * value / Config.Layout.artHeight
        end
        drawScoreSummary(painter_, state, w, artPoint, artWidth, artHeight, alpha)
        local experimentNumber = state.experimentNumber or levelIndex_ or 1
        painter_:Text(x + w * 0.90, y + rect.h * 0.124,
            string.format("No. EXP-%02d", experimentNumber), 10, c.inkMuted,
            NVG_ALIGN_RIGHT + NVG_ALIGN_TOP, "maker-body", alpha)
        if state.assistUsed then
            painter_:Text(x + w * 0.5, y + rect.h * 0.152,
                "本次观测由绿毛同事协助完成 · 不计入个人实验记录", 11, c.primary,
                NVG_ALIGN_CENTER + NVG_ALIGN_TOP, "maker-body", alpha)
        end

        local selfAuthorX = artPoint(96, 0)
        painter_:Text(selfAuthorX, drawZones.selfBox.y + drawZones.selfBox.h * 0.5,
            "诺米", Config.ReviewAuthorStyles.nomi.fontSize, c.ink,
            NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, Config.ReviewAuthorStyles.nomi.font, alpha)
        local selfTextX = drawZones.selfBox.x + artWidth(15)
        drawContainedWrappedText(painter_, {
            x = selfTextX,
            y = drawZones.selfBox.y + artHeight(5),
            w = artWidth(665),
            h = drawZones.selfBox.h - artHeight(10),
        }, state.selectedSelfReview or "请选择本次自我评价", Config.ReviewAuthorStyles.nomi.font,
            Config.Layout.selfReviewFontSize, Config.Layout.selfReviewFontMinSize, 2,
            state.selectedSelfReview and c.ink or c.inkMuted, alpha)
        local arrowX, arrowY = artPoint(943, 674)
        drawDropdownArrow(painter_, arrowX, arrowY, artHeight(16), state.dropdownProgress or 0,
            c.primary, alpha)

        local reviewColumns = {
            nameX = artPoint(92, 0),
            bodyX = artPoint(296, 0),
            bodyW = artWidth(590),
        }
        local _, newtonY = artPoint(92, 808)
        local _, einsteinY = artPoint(92, 926)
        local _, greenY = artPoint(92, 1043)
        drawReview(painter_, state, "newton", "牛顿", newtonY, reviewColumns, alpha)
        drawReview(painter_, state, "einstein", "爱因斯坦", einsteinY, reviewColumns, alpha)
        drawReview(painter_, state, "green", "绿毛同事", greenY, reviewColumns, alpha)

        local reportRetry = reportImages and reportImages.reportRetry
        local reportReplay = reportImages and reportImages.reportReplay
        local reportNext = reportImages and reportImages.reportNext
        local reportWorkshop = reportImages and reportImages.reportWorkshop
        if reportRetry and reportRetry >= 0 then
            painter_:ImageRect(reportRetry, drawZones.retry.x, drawZones.retry.y,
                drawZones.retry.w, drawZones.retry.h, alpha)
        end
        if drawZones.replay and reportReplay and reportReplay >= 0 then
            painter_:ImageRect(reportReplay, drawZones.replay.x, drawZones.replay.y,
                drawZones.replay.w, drawZones.replay.h, alpha)
        end
        if state.sourceKind == "official" and reportNext and reportNext >= 0 then
            local nextAlpha = Config.Layout.requireSelfReview and not state.selectedSelfReview and math.floor(alpha * 0.48) or alpha
            painter_:ImageRect(reportNext, drawZones.next.x, drawZones.next.y,
                drawZones.next.w, drawZones.next.h, nextAlpha)
        elseif state.sourceKind ~= "official" then
            local returnLabel = state.sourceScreen == "workshop_preview"
                and "返回实验工坊" or "返回实验目录"
            if reportWorkshop and reportWorkshop >= 0 then
                painter_:ImageRect(reportWorkshop, drawZones.next.x, drawZones.next.y,
                    drawZones.next.w, drawZones.next.h, alpha)
            else
                painter_:RoundedRect(drawZones.next.x, drawZones.next.y, drawZones.next.w, drawZones.next.h,
                    4, c.primary, c.border, 1, alpha)
            end
            painter_:Text(drawZones.next.x + drawZones.next.w * 0.5,
                drawZones.next.y + drawZones.next.h * 0.5, returnLabel, 20, c.primaryText,
                NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, "report-summary", alpha)
        end
        if state.validationMessage then
            painter_:Text(x + w * 0.5, drawZones.next.y - 17, state.validationMessage, 11, c.danger, NVG_ALIGN_CENTER + NVG_ALIGN_TOP, "maker-body", alpha)
        end

        -- Dropdown is painted last so its paper strips sit above the reviews.
        local dropdownProgress = state.dropdownProgress or 0
        if dropdownProgress > 0.01 then
            local optionStartY = drawZones.selfBox.y + drawZones.selfBox.h + 5
            local optionReveal = easeOut(dropdownProgress)
            local optionHeight = drawZones.selfBox.h
            local optionStep = optionHeight + Config.Layout.dropdownOptionGap
            for index, option in ipairs(state.selfOptions) do
                local optionY = optionStartY + (index - 1) * optionStep * optionReveal
                if reportDropdown and reportDropdown >= 0 then
                    painter_:ImageRect(reportDropdown, drawZones.selfBox.x, optionY, drawZones.selfBox.w, optionHeight,
                        math.floor(alpha * optionReveal))
                end
                if optionReveal > 0.28 then
                    local optionPaddingX = artWidth(18)
                    local optionPaddingY = artHeight(7)
                    drawContainedWrappedText(painter_, {
                        x = drawZones.selfBox.x + optionPaddingX,
                        y = optionY + optionPaddingY,
                        w = drawZones.selfBox.w - optionPaddingX * 2,
                        h = optionHeight - optionPaddingY * 2,
                    }, option, Config.ReviewAuthorStyles.nomi.font,
                        Config.Layout.selfReviewOptionFontSize, Config.Layout.selfReviewFontMinSize, 2,
                        c.ink, math.floor(alpha * optionReveal))
                end
            end
        end
    end

    local function formatSnapshotTime(timestamp)
        timestamp = tonumber(timestamp)
        if not timestamp or timestamp <= 0 or not os.date then return nil end
        local ok, value = pcall(os.date, "%Y-%m-%d  %H:%M", timestamp)
        return ok and value or nil
    end

    function DrawCatalogReportSnapshot(state, animation)
        if not state then return end
        state.reviewOverflowLogged = state.reviewOverflowLogged or {}
        state.newtonTier = state.newtonTier or { dangerAccent = state.newtonDangerAccent == true }

        local progress = easeOut(animation or 0)
        local alpha = math.floor(255 * progress)
        local frame = frame_
        local rect = Config.ResolveRect(frame)
        local y = rect.y - (1 - progress) * 24
        local x, w = rect.x, rect.w
        local c = Config.ReportColors

        painter_:FillRect(0, 0, frame.logicalWidth, frame.logicalHeight, c.overlay,
            math.floor(106 * progress))
        local reportImages = painter_.images and painter_.images.ui
        local reportBase = reportImages and reportImages.reportBase
        if reportBase and reportBase >= 0 then
            painter_:ImageRect(reportBase, x, y, w, rect.h, progress)
        else
            painter_:FillRect(x, y, w, rect.h, c.paper, alpha)
        end

        local function artPoint(px, py)
            return x + w * px / Config.Layout.artWidth, y + rect.h * py / Config.Layout.artHeight
        end
        local function artWidth(value)
            return w * value / Config.Layout.artWidth
        end
        local function artHeight(value)
            return rect.h * value / Config.Layout.artHeight
        end

        drawScoreSummary(painter_, state, w, artPoint, artWidth, artHeight, alpha)
        painter_:Text(x + w * 0.90, y + rect.h * 0.124,
            string.format("No. EXP-%02d", state.experimentNumber or 1), 10, c.inkMuted,
            NVG_ALIGN_RIGHT + NVG_ALIGN_TOP, "maker-body", alpha)
        local recordedAt = formatSnapshotTime(state.clearedAt)
        if recordedAt then
            painter_:Text(x + w * 0.90, y + rect.h * 0.143, recordedAt, 9, c.inkMuted,
                NVG_ALIGN_RIGHT + NVG_ALIGN_TOP, "report-green", alpha)
        end
        local experimentX, experimentY = artPoint(543, 336)
        drawWrappedText(painter_, experimentX, experimentY, artWidth(760),
            string.format("实验 %02d · %s", state.experimentNumber or 1, state.experimentName or "未命名实验"),
            "maker-display", 17, 17, 1, c.ink, NVG_ALIGN_CENTER + NVG_ALIGN_TOP, 18, alpha)

        local snapshotZones = Config.ResolveZones({ x = x, y = y, w = w, h = rect.h }, false)
        local selfAuthorX = artPoint(96, 0)
        painter_:Text(selfAuthorX, snapshotZones.selfBox.y + snapshotZones.selfBox.h * 0.5,
            "诺米", Config.ReviewAuthorStyles.nomi.fontSize, c.ink,
            NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, Config.ReviewAuthorStyles.nomi.font, alpha)
        local selfReview = state.selectedSelfReview or state.resultDescription
            or state.summaryText or "本次实验结果已归档"
        drawContainedWrappedText(painter_, {
            x = snapshotZones.selfBox.x + artWidth(15),
            y = snapshotZones.selfBox.y + artHeight(5),
            w = artWidth(665),
            h = snapshotZones.selfBox.h - artHeight(10),
        }, selfReview, Config.ReviewAuthorStyles.nomi.font,
            Config.Layout.selfReviewFontSize, Config.Layout.selfReviewFontMinSize, 2,
            c.ink, alpha)

        local reviewColumns = {
            nameX = artPoint(92, 0),
            bodyX = artPoint(296, 0),
            bodyW = artWidth(590),
        }
        local _, newtonY = artPoint(92, 808)
        local _, einsteinY = artPoint(92, 926)
        local _, greenY = artPoint(92, 1043)
        drawReview(painter_, state, "newton", "牛顿", newtonY, reviewColumns, alpha)
        drawReview(painter_, state, "einstein", "爱因斯坦", einsteinY, reviewColumns, alpha)
        drawReview(painter_, state, "green", "绿毛同事", greenY, reviewColumns, alpha)

        local dividerLeft, dividerY = artPoint(124, 1152)
        local dividerRight = artPoint(962, 1152)
        drawHairline(painter_, dividerLeft, dividerY, dividerRight, dividerY,
            c.summaryRule, math.max(0.7, artHeight(1.4)), math.floor(alpha * 0.7))
        local signatureLabelX, signatureLabelY = artPoint(150, 1242)
        painter_:Text(signatureLabelX, signatureLabelY, "学生签名：", 18, c.ink,
            NVG_ALIGN_LEFT + NVG_ALIGN_TOP, "maker-display", alpha)
        local signature = reportImages and reportImages.reportSignature
        if signature and signature >= 0 then
            local signatureRect = Config.ResolveReportArtRect(
                { x = x, y = y, w = w, h = rect.h }, 342, 1168, 520, 271)
            painter_:ImageRect(signature, signatureRect.x, signatureRect.y,
                signatureRect.w, signatureRect.h, progress)
        end

        local hintY = math.min(frame.logicalHeight - 18, y + rect.h + 28)
        local pulse = 0.28 + 0.72 * (0.5 + 0.5 * math.sin((uiElapsed_ or 0) * 2.4))
        painter_:Text(frame.logicalWidth * 0.5, hintY, "点击空白处关闭", 18, c.white,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, "maker-body", math.floor(alpha * pulse))
    end
end

return M
