-- render/OverlayView: private runtime functions installed into the App context.
local M = {}

---@param context GameContext
function M.Install(context)
    local Rules = context.Rules
    local LevelPresentation = context.LevelPresentation
    local _ENV = context

    local function utf8Characters(value)
        local result = {}
        for _, codepoint in utf8.codes(value or "") do result[#result + 1] = utf8.char(codepoint) end
        return result
    end

    local function textWidth(value, size, font)
        painter_:UseFont(font)
        nvgFontSize(painter_.vg, size)
        local width = nvgTextBounds(painter_.vg, 0, 0, value or "", nil)
        return type(width) == "number" and width or #utf8Characters(value) * size
    end

    local function ellipsize(value, maxWidth, size, font)
        if textWidth(value, size, font) <= maxWidth then return value end
        local characters = utf8Characters(value)
        while #characters > 1 do
            table.remove(characters)
            local candidate = table.concat(characters) .. "..."
            if textWidth(candidate, size, font) <= maxWidth then return candidate end
        end
        return "..."
    end

    function ResolveHUDLayout(f)
        local titleX = f.workspaceX - 37
        local summaryX = titleX + 438
        local summaryRight = f.logicalWidth - 28
        local summaryWidth = math.max(780, summaryRight - summaryX)
        local leftWidth = summaryWidth * .28
        local centerWidth = summaryWidth * .44
        -- The communication-history button occupies the first 132 units of
        -- the left summary band. Keep the rule affordance in the open paper
        -- slot between that button and the center divider.
        local ruleX = summaryX + 132 + 18
        local ruleRight = summaryX + leftWidth - 18
        return {
            titleX = titleX,
            left = { x = ruleX, y = 12, w = math.max(1, ruleRight - ruleX), h = 68 },
            center = { x = summaryX + leftWidth, y = 12, w = centerWidth, h = 68 },
            right = { x = summaryX + leftWidth + centerWidth, y = 12,
                w = summaryWidth - leftWidth - centerWidth, h = 68 },
        }
    end

    function ResolveHUDDropdownRect(kind)
        local layout = ResolveHUDLayout(frame_)
        if kind == "rules" then
            return { x = layout.left.x, y = 88, w = math.max(320, layout.left.w),
                h = 62 + math.max(1, #hudRuleList_) * 35 }
        end
        return { x = layout.right.x - 44, y = 88, w = layout.right.w + 44,
            h = 112 + #(level_ and level_.scoring and level_.scoring.tiers or {}) * 64 }
    end

    function UpdateRuleDropdown(ruleList)
        hudRuleList_ = ruleList or {}
    end

    function UpdateRuleSummary(ruleState)
        local list = Rules.ActiveRuleList(ruleState or Rules.NewState())
        UpdateRuleDropdown(list)
        if #list == 0 then
            hudRuleSummary_ = "经典场地"
        elseif #list == 1 then
            hudRuleSummary_ = list[1].label
        else
            hudRuleSummary_ = string.format("已部署 %d 项规则 ▼", #list)
        end
    end

    function UpdateObjectiveText(objective)
        hudObjectiveText_ = objective or ""
    end

    function UpdateExpectedScore(score)
        hudExpectedScore_ = score and math.max(0, math.floor(score)) or nil
    end

    function UpdateInterventionCount(count)
        hudInterventionCount_ = math.max(0, math.floor(tonumber(count) or 0))
    end

    local function CurrentHUDScoreSummary()
        local count = math.max(0, math.floor(tonumber(ruleDeployCount_) or 0))
        if not level_ then return { score = nil, interventionCount = count } end
        return LevelPresentation.BuildResultSummary(level_.scoring, count)
    end

    function RefreshHUDSummary()
        if not level_ then return end
        local summary = CurrentHUDScoreSummary()
        UpdateRuleSummary(rules_)
        UpdateObjectiveText(level_.shortObjective or level_.objective)
        UpdateInterventionCount(summary.interventionCount)
        UpdateExpectedScore(summary.score)
        if #hudRuleList_ < 2 and hudDropdown_ == "rules" then hudDropdown_ = nil end
    end

    function DrawHUD()
        local f = frame_
        local scoreSummary = CurrentHUDScoreSummary()
        local layout = ResolveHUDLayout(f)
        local titleX = layout.titleX
        painter_:Text(titleX + 62, 19, "牛顿看了想打人", 29, Renderer2D.COLORS.white, NVG_ALIGN_LEFT + NVG_ALIGN_TOP, "maker-display")
        painter_:Text(titleX + 62, 57, ellipsize(string.format("实验 %02d · %s", levelIndex_, level_.name or ""), 185, 16, nil),
            16, Renderer2D.COLORS.greenSecondary)
        local function DrawNavigationButton(x, key)
            local hovered = hoveredNavigation_ == key
            painter_:FillRect(x, 23, 46, 46, hovered and Renderer2D.COLORS.darkSecondary or Renderer2D.COLORS.dark, hovered and 255 or 107)
            if painter_.images.ui and painter_.images.ui.buttonFrame and painter_.images.ui.buttonFrame >= 0 then
                painter_:ImageRect(painter_.images.ui.buttonFrame, x - 1, 22, 48, 48, 1)
            else
                painter_:StrokeRect(x, 23, 46, 46, hovered and Renderer2D.COLORS.greenLight or Renderer2D.COLORS.white, 2, hovered and 230 or 115)
            end
            painter_:DrawNavigationIcon(key == "pause" and (isPaused_ and "play" or "pause") or key, x + 23, 46, Renderer2D.COLORS.white)
        end
        DrawNavigationButton(titleX + 255, "back")
        DrawNavigationButton(titleX + 315, "reset")
        DrawNavigationButton(titleX + 375, "pause")
        nvgStrokeColor(painter_.vg, nvgRGBA(117, 143, 120, 110)); nvgStrokeWidth(painter_.vg, 1)
        nvgBeginPath(painter_.vg)
        nvgMoveTo(painter_.vg, layout.center.x, 23); nvgLineTo(painter_.vg, layout.center.x, 69)
        nvgMoveTo(painter_.vg, layout.center.x + layout.center.w, 23); nvgLineTo(painter_.vg, layout.center.x + layout.center.w, 69)
        nvgStroke(painter_.vg)

        local pointerX, pointerY = DesignPointer()
        if pointerX >= layout.left.x and pointerX <= layout.left.x + layout.left.w
            and pointerY >= layout.left.y and pointerY <= layout.left.y + layout.left.h and #hudRuleList_ >= 2 then
            painter_:FillRect(layout.left.x + 5, 17, layout.left.w - 10, 58, Renderer2D.COLORS.greenSoft, 125)
        end
        if pointerX >= layout.right.x and pointerX <= layout.right.x + layout.right.w
            and pointerY >= layout.right.y and pointerY <= layout.right.y + layout.right.h then
            painter_:FillRect(layout.right.x + 5, 17, layout.right.w - 10, 58, Renderer2D.COLORS.greenSoft, 125)
        end

        painter_:Text(layout.left.x + 14, 46,
            ellipsize(hudRuleSummary_, layout.left.w - 28, 20, "maker-display"), 20,
            Renderer2D.COLORS.text, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, "maker-display")
        painter_:Text(layout.center.x + layout.center.w * .5, 46,
            ellipsize(hudObjectiveText_, layout.center.w - 42, 28, "maker-display"), 28,
            Renderer2D.COLORS.text, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, "maker-display")

        local right = layout.right
        local scoreText = scoreSummary.score and tostring(scoreSummary.score) or "--"
        painter_:Text(right.x + 20, 46, "预估分数：", 18, Renderer2D.COLORS.secondary,
            NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, "maker-display")
        painter_:Text(right.x + 132, 46, scoreText, 20, Renderer2D.COLORS.text,
            NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE, "report-green")
        painter_:Text(right.x + 151, 46, "·", 18, Renderer2D.COLORS.secondary,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, "maker-display")
        painter_:Text(right.x + 168, 46, "规则干预：", 18, Renderer2D.COLORS.secondary,
            NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, "maker-display")
        painter_:Text(right.x + 282, 46, tostring(math.min(99, scoreSummary.interventionCount)), 20,
            Renderer2D.COLORS.text, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE, "report-green")
        painter_:Text(right.x + 288, 46, "次", 18, Renderer2D.COLORS.secondary,
            NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, "maker-display")
        local chevronColor = Renderer2D.COLORS.secondary
        nvgSave(painter_.vg)
        nvgStrokeColor(painter_.vg, nvgRGBA(
            chevronColor[1], chevronColor[2], chevronColor[3], 220))
        nvgStrokeWidth(painter_.vg, 2.2)
        nvgLineCap(painter_.vg, NVG_ROUND)
        nvgLineJoin(painter_.vg, NVG_ROUND)
        nvgBeginPath(painter_.vg)
        nvgMoveTo(painter_.vg, right.x + 314, 43)
        nvgLineTo(painter_.vg, right.x + 320, 49)
        nvgLineTo(painter_.vg, right.x + 326, 43)
        nvgStroke(painter_.vg)
        nvgRestore(painter_.vg)
    end

    local function DrawHUDPaperFrame(rect)
        if not rect then return end
        painter_:FillRect(rect.x, rect.y, rect.w, rect.h, Renderer2D.COLORS.panel, 252)
        painter_:StrokeRect(rect.x, rect.y, rect.w, rect.h, Renderer2D.COLORS.darkPrimary, 2)
        painter_:StrokeRect(rect.x + 6, rect.y + 6, rect.w - 12, rect.h - 12,
            Renderer2D.COLORS.greenLight, 1, 190)
    end

    function DrawHUDDropdown()
        if not hudDropdown_ or not level_ then return end
        local rect = ResolveHUDDropdownRect(hudDropdown_)
        DrawHUDPaperFrame(rect)
        if hudDropdown_ == "rules" then
            painter_:Text(rect.x + 18, rect.y + 16, "当前生效规则", 15, Renderer2D.COLORS.secondary, nil, "report-green")
            for index, entry in ipairs(hudRuleList_) do
                local y = rect.y + 50 + (index - 1) * 35
                painter_:Circle(rect.x + 22, y + 3, 4, Renderer2D.COLORS.primaryActive)
                painter_:Text(rect.x + 35, y - 8, ellipsize(entry.label, rect.w - 54, 17, "maker-display"),
                    17, Renderer2D.COLORS.text, nil, "maker-display")
            end
            return
        end

        local scoreSummary = CurrentHUDScoreSummary()
        painter_:Text(rect.x + 18, rect.y + 15, "实时评级摘要", 15, Renderer2D.COLORS.secondary, nil, "report-green")
        painter_:Text(rect.x + 18, rect.y + 39,
            string.format("当前预估分数：%s · 规则干预：%d 次",
                scoreSummary.score and tostring(scoreSummary.score) or "--", scoreSummary.interventionCount),
            18, Renderer2D.COLORS.text, nil, "maker-display")
        painter_:FillRect(rect.x + 18, rect.y + 75, rect.w - 36, 1, Renderer2D.COLORS.greenLight, 180)
        for index, tier in ipairs(level_.scoring and level_.scoring.tiers or {}) do
            local y = rect.y + 90 + (index - 1) * 64
            painter_:Text(rect.x + 18, y, string.format("%d · %s", tier.score, tier.title), 17,
                Renderer2D.COLORS.text, nil, "maker-display")
            painter_:Text(rect.x + 18, y + 28, ellipsize(tier.description, rect.w - 36, 15, nil), 15,
                Renderer2D.COLORS.secondary)
        end
    end
    function DrawPlayfieldOverlay()
        if replayMode_ ~= "none" then return end
        if (activeCardId_ or primedCardId_ or #cardBurns_ > 0) and not isPaused_ and not success_ and not failed_ then
            painter_:RoundedRect(frame_.playfieldX + 8, frame_.playfieldY + 8, frame_.playfieldWidth - 16, frame_.playfieldHeight - 16, 5, Renderer2D.COLORS.greenSoft, nil, nil, 46)
            painter_:RoundedRect(frame_.playfieldX + 8, frame_.playfieldY + 8, frame_.playfieldWidth - 16, frame_.playfieldHeight - 16, 5, nil, Renderer2D.COLORS.primaryActive, 3, 179)
        end
    end

    -- Phaser's pause shade is depth 53, below the ordinary hand (54-58). Keep it
    -- in its own pass so later layer changes cannot accidentally dim rule cards.
    function DrawPauseShade()
        if assistSceneActive_ or replayMode_ ~= "none" or not isPaused_
            or (IsResultReportVisible and IsResultReportVisible()) then return end
        painter_:FillRect(frame_.playfieldX, frame_.playfieldY, frame_.playfieldWidth, frame_.playfieldHeight, { 0, 0, 0, 255 }, 66)
    end

    -- The shade is emitted with the playfield (Phaser depth 53). The label is a
    -- separate depth-67 element and must not be painted into this lower pass.
    function DrawPauseStatus()
        if assistSceneActive_ or replayMode_ ~= "none" or not isPaused_ then return end
        local right = frame_.playfieldX + frame_.playfieldWidth - 24
        local top = frame_.playfieldY + 16
        painter_:FillRect(right - 196, top, 196, 24, Renderer2D.COLORS.panel, 255)
        painter_:Text(
            right - 9,
            top + 3,
            "\u{5B9E}\u{9A8C}\u{6682}\u{505C} \u{00B7} \u{89C4}\u{5219}\u{5361}\u{4ECD}\u{53EF}\u{64CD}\u{4F5C}",
            13,
            Renderer2D.COLORS.text,
            NVG_ALIGN_RIGHT + NVG_ALIGN_TOP
        )
    end
    function DrawResultOverlay()
        if replayMode_ ~= "none" then return end
        if IsResultOverlayVisible() then
            if success_ and IsResultReportVisible and IsResultReportVisible() then
                DrawResultReport()
                return
            end
            -- The result mask covers the entire viewport, including the
            -- letterbox padding painted by Canvas:Begin. Keep it above the
            -- bottom-most background but below the report and companion.
            nvgSave(painter_.vg)
            nvgResetScissor(painter_.vg)
            painter_:FillRect(0, -(frame_.stageOffsetY or 0), frame_.logicalWidth,
                frame_.viewportLogicalHeight or frame_.logicalHeight,
                Renderer2D.COLORS.background, 199)
            nvgRestore(painter_.vg)
            local cx, cy = frame_.playfieldX + frame_.playfieldWidth * .5, frame_.playfieldY + frame_.playfieldHeight * .5
            local function overlayButton(x, y, label, secondary)
                painter_:RoundedRect(x - 73, y - 23, 146, 46, 4, secondary and Renderer2D.COLORS.panelSecondary or Renderer2D.COLORS.greenStrong, secondary and Renderer2D.COLORS.dark or Renderer2D.COLORS.primaryActive, 2)
                painter_:Text(x, y - 8, label, 16, secondary and Renderer2D.COLORS.text or Renderer2D.COLORS.white, NVG_ALIGN_CENTER + NVG_ALIGN_TOP, "maker-display")
            end
            if success_ then
                if assistedClear_ then
                    local panelWidth = math.min(820, math.max(480, frame_.logicalWidth - 48))
                    local panelHeight = 210
                    local panelCenterX = frame_.logicalWidth * .5
                    local panelCenterY = frame_.logicalHeight * .5
                    local panel = {
                        x = panelCenterX - panelWidth * .5,
                        y = panelCenterY - panelHeight * .5,
                        w = panelWidth,
                        h = panelHeight,
                    }
                    DrawHUDPaperFrame(panel)
                    painter_:Text(panelCenterX, panel.y + 38,
                        "辅助观测成功", 34, Renderer2D.COLORS.text,
                        NVG_ALIGN_CENTER + NVG_ALIGN_TOP, "report-green")
                    overlayButton(panelCenterX - 160, panelCenterY + 58, "返回目录", false)
                    overlayButton(panelCenterX + 160, panelCenterY + 58, "再次尝试", true)
                    return
                end
                painter_:RoundedRect(cx - 345, cy - 115, 690, 230, 4, Renderer2D.COLORS.panel, Renderer2D.COLORS.primaryActive, 2)
                painter_:Text(cx, cy - 75, assistedClear_ and "辅助观测成立" or "观测成立", 42, Renderer2D.COLORS.text, NVG_ALIGN_CENTER + NVG_ALIGN_TOP, "maker-display")
                painter_:Text(cx, cy - 6,
                    assistedClear_ and ((level_.name or "实验") .. " · 本次为 assisted clear")
                        or ((level_.name or "实验") .. " · 苹果已稳定进入观察窗"),
                    16, Renderer2D.COLORS.secondary, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
                if assistedClear_ then
                    overlayButton(cx - 80, cy + 65, "返回目录", false)
                    overlayButton(cx + 80, cy + 65, "再次尝试", true)
                else
                    overlayButton(cx - 160, cy + 65, "返回目录", false)
                    overlayButton(cx, cy + 65, "查看实验回放", true)
                    overlayButton(cx + 160, cy + 65, "再次尝试", true)
                end
            else
                painter_:RoundedRect(cx - 310, cy - 105, 620, 210, 4, Renderer2D.COLORS.panel, Renderer2D.COLORS.warning, 2)
                painter_:Text(cx, cy - 67, "实验未成立", 38, Renderer2D.COLORS.warning, NVG_ALIGN_CENTER + NVG_ALIGN_TOP, "maker-display")
                painter_:Text(cx, cy - 5, string.format("第 %d 次偏离记录", failureCount_), 16, Renderer2D.COLORS.secondary, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
                overlayButton(cx, cy + 60, "重新布置", false)
            end
        end
    end
end

return M
