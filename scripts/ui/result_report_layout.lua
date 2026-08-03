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
                lines[#lines + 1] = line
                line = character
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

local function drawActionButton(painter, button, label, primary, hovered, disabled, alpha)
    local fill = disabled and Config.ReportColors.disabled or (primary and Config.ReportColors.primary or Config.ReportColors.paperLight)
    local text = primary and Config.ReportColors.primaryText or Config.ReportColors.ink
    if hovered and not disabled then fill = primary and Config.ReportColors.border or Config.ReportColors.dropdownHover end
    painter:RoundedRect(button.x, button.y, button.w, button.h, 3, fill, Config.ReportColors.border, 1.5, alpha)
    painter:Text(button.x + button.w * 0.5, button.y + 8, label, primary and 15 or 14, text, NVG_ALIGN_CENTER + NVG_ALIGN_TOP, "maker-body", alpha)
end

---@param context GameContext
function M.Install(context)
    local _ENV = context

    local function drawReview(painter, state, key, author, y, width, alpha)
        local style = Config.ReviewAuthorStyles[key]
        painter:Text(width.x, y, author, style.fontSize, style.color, NVG_ALIGN_LEFT + NVG_ALIGN_TOP, style.font, alpha)
        local body = state[key .. "Review"] or "暂无评语。"
        local textColor = style.color
        if key == "newton" and state.newtonTier and state.newtonTier.dangerAccent then textColor = Config.ReportColors.danger end
        local size = style.fontSize
        local lines, overflow
        repeat
            lines, overflow = wrapText(painter, body, width.w, style.font, size, Config.Layout.maxTextLines)
            if overflow and size > Config.Layout.reviewFontMinSize then size = size - 1 end
        until not overflow or size <= Config.Layout.reviewFontMinSize
        local bodyY = y + 23
        for index, line in ipairs(lines) do
            painter:Text(width.x, bodyY + (index - 1) * 18, line, size, textColor, NVG_ALIGN_LEFT + NVG_ALIGN_TOP, style.font, alpha)
        end
        if key == "newton" and state.newtonTier and state.newtonTier.underlineCount then
            local underlineY = bodyY + #lines * 18 + 1
            for index = 1, state.newtonTier.underlineCount do
                painter:FillRect(width.x, underlineY + (index - 1) * 3, width.w * 0.74, 1, textColor, alpha)
            end
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
            retry = shiftZone(zones.retry),
            replay = shiftZone(zones.replay),
            next = shiftZone(zones.next),
        }

        painter_:FillRect(0, 0, frame.logicalWidth, frame.logicalHeight, c.overlay, math.floor(82 * progress))
        painter_:FillRect(x, y, w, rect.h, c.paper, alpha)
        painter_:StrokeRect(x, y, w, rect.h, c.border, 2.5, alpha)
        painter_:StrokeRect(x + Config.Layout.innerBorder, y + Config.Layout.innerBorder, w - Config.Layout.innerBorder * 2, rect.h - Config.Layout.innerBorder * 2, c.border, 1, alpha)

        drawLeaf(painter_, x + 23, y + 25, 0.7, c.primary, alpha)
        drawDiamond(painter_, x + w - 27, y + 26, 4, c.danger, alpha)
        painter_:Text(x + w - 24, y + 44, string.format("No. %s", state.resultId or "EXP-01"), 10, c.inkMuted, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP, "maker-body", alpha)
        painter_:Text(x + w * 0.5, y + 24, "实验观测报告", 24, c.ink, NVG_ALIGN_CENTER + NVG_ALIGN_TOP, "maker-display", alpha)
        painter_:Text(x + w * 0.5, y + 53, "OBSERVATION REPORT", 10, c.inkMuted, NVG_ALIGN_CENTER + NVG_ALIGN_TOP, "maker-body", alpha)

        painter_:Text(x + 24, y + 83, state.title, 24, c.ink, NVG_ALIGN_LEFT + NVG_ALIGN_TOP, "maker-display", alpha)
        painter_:Text(x + 24, y + 114, string.format("实验 %02d · %s", levelIndex_ or 1, state.experimentName), 13, c.ink, NVG_ALIGN_LEFT + NVG_ALIGN_TOP, "maker-body", alpha)
        painter_:TextBox(x + 24, y + 137, w - 48, state.resultDescription, 12, c.inkMuted, NVG_ALIGN_LEFT + NVG_ALIGN_TOP, "maker-body", 1.15, alpha)
        drawDivider(painter_, x + 24, y + 177, w - 48, alpha)
        painter_:Text(x + 24, y + 189, "实验小组评议", 13, c.ink, NVG_ALIGN_LEFT + NVG_ALIGN_TOP, "maker-display", alpha)

        painter_:Text(x + 24, y + 211, "自我评价 · 诺米", Config.ReviewAuthorStyles.nomi.fontSize, c.ink, NVG_ALIGN_LEFT + NVG_ALIGN_TOP, "maker-body", alpha)
        painter_:RoundedRect(zones.selfBox.x, y + 238, zones.selfBox.w, zones.selfBox.h, 2, c.paperLight, c.border, 1, alpha)
        painter_:TextBox(zones.selfBox.x + 12, y + 246, zones.selfBox.w - 38, state.selectedSelfReview or "请选择本次自我评价", 12, state.selectedSelfReview and c.ink or c.inkMuted, NVG_ALIGN_LEFT + NVG_ALIGN_TOP, Config.ReviewAuthorStyles.nomi.font, 1.05, alpha)
        painter_:Text(zones.selfBox.x + zones.selfBox.w - 14, y + 246, state.isDropdownOpen and "▲" or "▼", 12, c.primary, NVG_ALIGN_CENTER + NVG_ALIGN_TOP, "maker-body", alpha)

        local reviewWidth = { x = x + 24, w = w - 48 }
        local reviewY = y + 282
        drawReview(painter_, state, "newton", "牛顿", reviewY, reviewWidth, alpha)
        drawDivider(painter_, x + 24, reviewY + 58, w - 48, alpha)
        drawReview(painter_, state, "einstein", "爱因斯坦", reviewY + 67, reviewWidth, alpha)
        drawDivider(painter_, x + 24, reviewY + 125, w - 48, alpha)
        drawReview(painter_, state, "green", "绿毛同事", reviewY + 134, reviewWidth, alpha)

        -- The stamp is deliberately procedural and restrained; later artwork can
        -- replace this draw block without touching report state or hit testing.
        local vg = painter_.vg
        local stampScale = 0.94 + 0.06 * progress
        nvgSave(vg)
        nvgTranslate(vg, x + w - 73, y + 128)
        nvgRotate(vg, -0.12)
        nvgScale(vg, stampScale, stampScale)
        painter_:StrokeRect(-55, -16, 110, 32, c.danger, 1.5, alpha)
        painter_:Text(0, -8, "已记录", 14, c.danger, NVG_ALIGN_CENTER + NVG_ALIGN_TOP, "maker-display", alpha)
        nvgRestore(vg)

        local retryHover = false
        local replayHover = false
        local nextHover = false
        local pointer = input.mousePosition
        if pointer then
            local px, py = context.design_:ScreenToLogical(pointer.x, pointer.y)
            retryHover = px >= drawZones.retry.x and px <= drawZones.retry.x + drawZones.retry.w and py >= drawZones.retry.y and py <= drawZones.retry.y + drawZones.retry.h
            replayHover = drawZones.replay and px >= drawZones.replay.x and px <= drawZones.replay.x + drawZones.replay.w and py >= drawZones.replay.y and py <= drawZones.replay.y + drawZones.replay.h
            nextHover = px >= drawZones.next.x and px <= drawZones.next.x + drawZones.next.w and py >= drawZones.next.y and py <= drawZones.next.y + drawZones.next.h
        end
        drawActionButton(painter_, drawZones.retry, "重新实验", false, retryHover, false, alpha)
        if drawZones.replay then drawActionButton(painter_, drawZones.replay, "调阅回放", false, replayHover, false, alpha) end
        drawActionButton(painter_, drawZones.next, levelIndex_ < context.CONFIG.levelCount and "进入下一实验" or "返回实验目录", true, nextHover, Config.Layout.requireSelfReview and not state.selectedSelfReview, alpha)
        if state.validationMessage then
            painter_:Text(x + w * 0.5, drawZones.next.y - 17, state.validationMessage, 11, c.danger, NVG_ALIGN_CENTER + NVG_ALIGN_TOP, "maker-body", alpha)
        end

        -- Dropdown is painted last so its paper strips sit above the reviews.
        if state.isDropdownOpen then
            local optionStartY = y + 276
            for index, option in ipairs(state.selfOptions) do
                local optionY = optionStartY + (index - 1) * 28
                local hovered = state.hoveredOption == index or state.highlightedOption == index
                painter_:RoundedRect(zones.selfBox.x, optionY, zones.selfBox.w, 26, 2, hovered and c.dropdownHover or c.paperLight, c.border, 1, alpha)
                painter_:TextBox(zones.selfBox.x + 10, optionY + 5, zones.selfBox.w - 20, option, 11, c.ink, NVG_ALIGN_LEFT + NVG_ALIGN_TOP, Config.ReviewAuthorStyles.nomi.font, 1.05, alpha)
            end
        end
    end
end

return M
