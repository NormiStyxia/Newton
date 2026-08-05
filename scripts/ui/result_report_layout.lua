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

        painter_:FillRect(0, 0, frame.logicalWidth, frame.logicalHeight, c.overlay, math.floor(82 * progress))
        local reportBase = painter_.images and painter_.images.ui and painter_.images.ui.reportBase
        if reportBase and reportBase >= 0 then
            painter_:ImageRect(reportBase, x, y, w, rect.h, progress)
        else
            painter_:FillRect(x, y, w, rect.h, c.paper, alpha)
        end
        local reportImages = painter_.images and painter_.images.ui
        local reportDropdown = reportImages and reportImages.reportDropdown
        if reportDropdown and reportDropdown >= 0 then
            painter_:ImageRect(reportDropdown, drawZones.selfBox.x, drawZones.selfBox.y,
                drawZones.selfBox.w, drawZones.selfBox.h, alpha)
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
        local experimentNumber = state.experimentNumber or levelIndex_ or 1
        painter_:Text(x + w * 0.90, y + rect.h * 0.124,
            string.format("No. EXP-%02d", experimentNumber), 10, c.inkMuted,
            NVG_ALIGN_RIGHT + NVG_ALIGN_TOP, "maker-body", alpha)
        if state.assistUsed then
            painter_:Text(x + w * 0.5, y + rect.h * 0.152,
                "本次观测由绿毛同事协助完成 · 不计入个人实验记录", 11, c.primary,
                NVG_ALIGN_CENTER + NVG_ALIGN_TOP, "maker-body", alpha)
        end

        local selfAuthorX, selfY = artPoint(96, 654)
        painter_:Text(selfAuthorX, selfY, "诺米", Config.ReviewAuthorStyles.nomi.fontSize, c.ink,
            NVG_ALIGN_LEFT + NVG_ALIGN_TOP, Config.ReviewAuthorStyles.nomi.font, alpha)
        local selfTextX, selfTextY = artPoint(272, 655)
        drawWrappedText(painter_, selfTextX, selfTextY, artWidth(610),
            state.selectedSelfReview or "请选择本次自我评价", Config.ReviewAuthorStyles.nomi.font,
            Config.Layout.selfReviewFontSize, 12, 1, state.selectedSelfReview and c.ink or c.inkMuted,
            NVG_ALIGN_LEFT + NVG_ALIGN_TOP, 18, alpha)
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
        if reportRetry and reportRetry >= 0 then
            painter_:ImageRect(reportRetry, drawZones.retry.x, drawZones.retry.y,
                drawZones.retry.w, drawZones.retry.h, alpha)
        end
        if drawZones.replay and reportReplay and reportReplay >= 0 then
            painter_:ImageRect(reportReplay, drawZones.replay.x, drawZones.replay.y,
                drawZones.replay.w, drawZones.replay.h, alpha)
        end
        if reportNext and reportNext >= 0 then
            local nextAlpha = Config.Layout.requireSelfReview and not state.selectedSelfReview and math.floor(alpha * 0.48) or alpha
            painter_:ImageRect(reportNext, drawZones.next.x, drawZones.next.y,
                drawZones.next.w, drawZones.next.h, nextAlpha)
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
                painter_:StrokeRect(drawZones.selfBox.x, optionY, drawZones.selfBox.w, optionHeight,
                    c.border, math.max(1, artHeight(2)), math.floor(alpha * optionReveal))
                if optionReveal > 0.28 then
                    painter_:TextBox(drawZones.selfBox.x + 14, optionY + artHeight(27),
                        drawZones.selfBox.w - 28, option, Config.Layout.selfReviewOptionFontSize,
                        c.ink, NVG_ALIGN_LEFT + NVG_ALIGN_TOP, Config.ReviewAuthorStyles.nomi.font, 1.05,
                        math.floor(alpha * optionReveal))
                end
            end
        end
    end
end

return M
