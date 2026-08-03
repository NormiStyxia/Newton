-- render/ReplayView: private runtime functions installed into the App context.
local M = {}

---@param context GameContext
function M.Install(context)
    local ReplayMode = context.ReplayMode
    local ReplayTimeline = context.ReplayTimeline
    local ReplayFeed = context.ReplayFeed
    local Rules = context.Rules
    local _ENV = context
    function DrawReplay()
        local state = ReplayStateAt(replayTime_)
        if not state then return end
        if replayBusinessMode_ == ReplayMode.ASSIST_TAKEOVER then
            painter_:FillRect(frame_.playfieldX, frame_.playfieldY, frame_.playfieldWidth, frame_.playfieldHeight,
                { 32, 55, 44, 255 }, 52)
        end
        local samples = ReplayTimeline.SamplesThrough(replaySamples_, replayTime_)
        if #samples > 0 then
            for i = 2, #samples do
                local from, to = samples[i - 1], samples[i]
                local fromX, fromY = context.design_:WorldToLogical(from.x, from.y)
                local toX, toY = context.design_:WorldToLogical(to.x, to.y)
                local recent = replayTime_ - to.t <= 1300
                nvgStrokeWidth(painter_.vg, recent and 4 or 2)
                nvgStrokeColor(painter_.vg, nvgRGBA(95, 143, 104, recent and 204 or 64))
                nvgBeginPath(painter_.vg)
                nvgMoveTo(painter_.vg, fromX, fromY)
                nvgLineTo(painter_.vg, toX, toY)
                nvgStroke(painter_.vg)
            end

            local startX, startY = context.design_:WorldToLogical(samples[1].x, samples[1].y)
            painter_:Circle(startX, startY, 10, nil, Renderer2D.COLORS.darkPrimary, 3, 209)

            local traversed, nextArrow = 0, 110
            for i = 2, #samples do
                local from, to = samples[i - 1], samples[i]
                local fromX, fromY = context.design_:WorldToLogical(from.x, from.y)
                local toX, toY = context.design_:WorldToLogical(to.x, to.y)
                local dx, dy = toX - fromX, toY - fromY
                local length = math.sqrt(dx * dx + dy * dy)
                if length >= .001 then
                    while traversed + length >= nextArrow do
                        local progress = (nextArrow - traversed) / length
                        local x, y = fromX + dx * progress, fromY + dy * progress
                        local ux, uy = dx / length, dy / length
                        local normalX, normalY = -uy, ux
                        local arrowTime = from.t + (to.t - from.t) * progress
                        local recent = replayTime_ - arrowTime <= 1300
                        nvgFillColor(painter_.vg, nvgRGBA(82, 117, 93, recent and 209 or 117))
                        nvgBeginPath(painter_.vg)
                        nvgMoveTo(painter_.vg, x + ux * 8, y + uy * 8)
                        nvgLineTo(painter_.vg, x - ux * 5 + normalX * 5, y - uy * 5 + normalY * 5)
                        nvgLineTo(painter_.vg, x - ux * 5 - normalX * 5, y - uy * 5 - normalY * 5)
                        nvgClosePath(painter_.vg)
                        nvgFill(painter_.vg)
                        nextArrow = nextArrow + 110
                    end
                    traversed = traversed + length
                end
            end

            if replayFinished_ then
                local finishSample = samples[#samples]
                local endX, endY = context.design_:WorldToLogical(finishSample.x, finishSample.y)
                painter_:Circle(endX, endY, 7, Renderer2D.COLORS.darkPrimary, nil, nil, 230)
                nvgStrokeColor(painter_.vg, nvgRGBA(47, 73, 56, 230))
                nvgStrokeWidth(painter_.vg, 2)
                nvgBeginPath(painter_.vg)
                nvgMoveTo(painter_.vg, endX + 10, endY + 9)
                nvgLineTo(painter_.vg, endX + 10, endY - 18)
                nvgStroke(painter_.vg)
                nvgFillColor(painter_.vg, nvgRGBA(117, 180, 110, 242))
                nvgBeginPath(painter_.vg)
                nvgMoveTo(painter_.vg, endX + 10, endY - 18)
                nvgLineTo(painter_.vg, endX + 31, endY - 12)
                nvgLineTo(painter_.vg, endX + 10, endY - 6)
                nvgClosePath(painter_.vg)
                nvgFill(painter_.vg)
            end
        end

        local sequence = 0
        for _, event in ipairs(replayEvents_) do
            if event.type == "CARD_PLAYED" or event.type == "NEWTON_PUNCH" then
                sequence = sequence + 1
            end
            if event.t <= replayTime_ and (event.type == "CARD_PLAYED" or event.type == "NEWTON_PUNCH") then
                local x, y = context.design_:WorldToLogical(event.x, event.y)
                local card = event.cardId and Rules.CARDS[event.cardId] or nil
                local accent = card and card.accent or Renderer2D.COLORS.warning
                painter_:Circle(x, y, 15, Renderer2D.COLORS.panel, accent, 2, 245)
                if card then
                    nvgSave(painter_.vg)
                    nvgTranslate(painter_.vg, x, y)
                    nvgScale(painter_.vg, .22, .22)
                    painter_:DrawCardSymbol(event.cardId, 0, 0, Renderer2D.COLORS.text)
                    nvgRestore(painter_.vg)
                else
                    painter_:Text(x, y - 7, "N", 13, Renderer2D.COLORS.warning, NVG_ALIGN_CENTER + NVG_ALIGN_TOP, "maker-display")
                end
                painter_:Circle(x + 11, y - 11, 8, Renderer2D.COLORS.dark, nil, nil, 255)
                painter_:Text(x + 11, y - 15, tostring(sequence), 9, Renderer2D.COLORS.white, NVG_ALIGN_CENTER + NVG_ALIGN_TOP, "maker-display")
            end
        end

        local appleX, appleY = context.design_:WorldToLogical(state.x, state.y)
        painter_:Circle(appleX, appleY, 37, Renderer2D.COLORS.primaryActive, nil, nil, 48)
        painter_:Circle(appleX, appleY, 37, nil, Renderer2D.COLORS.primaryActive, 2, 122)
        -- Replay angles are recorded from the UrhoX Y-up body; mirror the
        -- presentation sign for the same clockwise screen-space motion.
        painter_:Image(painter_.images.apple, appleX, appleY, 64, 64, 1, math.rad(-(state.angle or 0)))

        if replayBusinessMode_ == ReplayMode.ASSIST_TAKEOVER then
            local labelX = frame_.playfieldX + frame_.playfieldWidth - 158
            local labelY = frame_.playfieldY + 18
            painter_:RoundedRect(labelX, labelY, 140, 38, 5, Renderer2D.COLORS.dark,
                Renderer2D.COLORS.greenLight, 1, 235)
            painter_:Text(labelX + 70, labelY + 9,
                replayFinished_ and "ASSIST · 完成" or "ASSIST · 接管中",
                13, Renderer2D.COLORS.white, NVG_ALIGN_CENTER + NVG_ALIGN_TOP, "maker-display")
            return
        end

        local cx, cy = frame_.playfieldX + frame_.playfieldWidth * .5, frame_.playfieldY + 34
        painter_:RoundedRect(cx - 289, cy - 27, 578, 54, 5, Renderer2D.COLORS.dark, Renderer2D.COLORS.greenLight, 1, 240)
        painter_:Text(cx - 272, cy - 9, "实验回放", 14, Renderer2D.COLORS.white, NVG_ALIGN_LEFT + NVG_ALIGN_TOP, "maker-display")
        painter_:Text(cx - 272, cy + 10, string.format("%.2f / %.2f s", replayTime_ / 1000, ReplayDuration() / 1000), 10, Renderer2D.COLORS.greenSecondary)
        local function replayButton(x, width, label, active)
            painter_:RoundedRect(x - width * .5, cy - 17, width, 34, 4, active and Renderer2D.COLORS.greenStrong or Renderer2D.COLORS.darkSecondary, Renderer2D.COLORS.greenLight, 1, active and 255 or 168)
            painter_:Text(x, cy - 7, label, 12, active and Renderer2D.COLORS.white or Renderer2D.COLORS.greenSecondary, NVG_ALIGN_CENTER + NVG_ALIGN_TOP, "maker-display")
        end
        replayButton(cx - 92, 44, replayPaused_ and "▶" or "Ⅱ", not replayPaused_)
        replayButton(cx - 27, 58, "0.5×", replaySpeed_ == .5)
        replayButton(cx + 37, 58, "1×", replaySpeed_ == 1)
        replayButton(cx + 101, 58, "2×", replaySpeed_ == 2)
        replayButton(cx + 238, 78, "退出", false)

        local feedX, feedY = frame_.playfieldX + 18, frame_.playfieldY + frame_.playfieldHeight - 166
        painter_:RoundedRect(feedX, feedY, 310, 148, 3, Renderer2D.COLORS.dark, Renderer2D.COLORS.greenLight, 1, 232)
        painter_:Text(feedX + 14, feedY + 11, replayFinished_ and "本次规则使用顺序" or "REPLAY · 规则记录", 13, Renderer2D.COLORS.white, NVG_ALIGN_LEFT + NVG_ALIGN_TOP, "maker-display")
        local feedItems = ReplayFeed.Items(replayEvents_, replayTime_, Rules.CARDS)
        local start = math.max(1, #feedItems - 2)
        if #feedItems == 0 then painter_:Text(feedX + 14, feedY + 57, "未使用规则卡", 13, Renderer2D.COLORS.greenSecondary) end
        for i = start, #feedItems do
            local item = feedItems[i]
            local row = i - start
            local iconX, iconY = feedX + 22, feedY + 52 + row * 34
            painter_:Circle(iconX, iconY, 11, item.accent, nil, nil, item.active and 242 or 107)
            if item.cardId then
                nvgSave(painter_.vg)
                nvgTranslate(painter_.vg, iconX, iconY)
                nvgScale(painter_.vg, .18, .18)
                painter_:DrawCardSymbol(item.cardId, 0, 0, Renderer2D.COLORS.dark, item.active and 255 or 145)
                nvgRestore(painter_.vg)
            else
                painter_:Text(iconX, iconY - 7, "N", 10, Renderer2D.COLORS.dark, NVG_ALIGN_CENTER + NVG_ALIGN_TOP, "maker-display")
            end
            painter_:Text(feedX + 42, feedY + 42 + row * 34, item.title, 13, Renderer2D.COLORS.white, NVG_ALIGN_LEFT + NVG_ALIGN_TOP, "maker-display")
            painter_:Text(feedX + 42, feedY + 58 + row * 34, item.status, 10, item.active and Renderer2D.COLORS.greenSecondary or Renderer2D.COLORS.secondary)
        end
        if replayFinished_ then
            local endX = frame_.playfieldX + frame_.playfieldWidth - 190
            local endY = frame_.playfieldY + frame_.playfieldHeight - 54
            painter_:RoundedRect(endX - 175, endY - 24, 350, 48, 4, Renderer2D.COLORS.panel, Renderer2D.COLORS.primaryActive, 2, 245)
            painter_:Text(endX - 160, endY - 7, "回放完成", 13, Renderer2D.COLORS.text, NVG_ALIGN_LEFT + NVG_ALIGN_TOP, "maker-display")
            local function endButton(x, width, label)
                painter_:RoundedRect(x - width * .5, endY - 17, width, 34, 4, Renderer2D.COLORS.darkSecondary, Renderer2D.COLORS.greenLight, 1, 168)
                painter_:Text(x, endY - 7, label, 12, Renderer2D.COLORS.greenSecondary, NVG_ALIGN_CENTER + NVG_ALIGN_TOP, "maker-display")
            end
            endButton(endX + 38, 92, "再次播放")
            endButton(endX + 137, 84, "退出回放")
        end
    end
end

return M
