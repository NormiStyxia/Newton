-- render/OverlayView: private runtime functions installed into the App context.
local M = {}

---@param context GameContext
function M.Install(context)
    local Rules = context.Rules
    local CONFIG = context.CONFIG
    local _ENV = context
    function DrawHUD()
        local f = frame_
        local titleX = f.workspaceX - 37
        painter_:Text(titleX + 36, 19, "牛顿看了想打人", 29, Renderer2D.COLORS.white, NVG_ALIGN_LEFT + NVG_ALIGN_TOP, "maker-display")
        painter_:Text(titleX + 36, 57, string.format("实验 %02d · %s", levelIndex_, level_.name or ""), 13, Renderer2D.COLORS.greenSecondary)
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
        painter_:Text(f.playfieldX + 300, 17, "当前实验状态", 12, Renderer2D.COLORS.secondary)
        painter_:Text(f.playfieldX + 300, 42, status_, 17, Renderer2D.COLORS.text, NVG_ALIGN_LEFT + NVG_ALIGN_TOP, "maker-display")
        painter_:Text(f.playfieldX + 585, 17, "当前场地规则", 12, Renderer2D.COLORS.secondary)
        local g = Rules.GetGravity(rules_, level_.rules.initialGravity)
        painter_:Text(f.playfieldX + 585, 42, string.format("(%d,%d) · %s", g.x, g.y, rules_.activeFields["feather-gravity"] and "轻羽" or "经典场地"), 17, Renderer2D.COLORS.text, NVG_ALIGN_LEFT + NVG_ALIGN_TOP, "maker-display")
        painter_:Text(f.playfieldX + 800, 18, level_.objective or "让苹果进入观察皿", 16, Renderer2D.COLORS.text, NVG_ALIGN_LEFT + NVG_ALIGN_TOP, "maker-display")
        painter_:Text(f.playfieldX + f.playfieldWidth - 290, 17, "关卡", 12, Renderer2D.COLORS.secondary)
        for i = 1, CONFIG.levelCount do
            local x = f.playfieldX + f.playfieldWidth - 290 + (i - 1) * 27
            local scale = hoveredLevelIndex_ == i and 1.14 or 1
            if painter_.images.ui and painter_.images.ui.progressNode and painter_.images.ui.progressNode >= 0 then
                painter_:Image(painter_.images.ui.progressNode, x, 46, 22 * scale, 22 * scale, 1)
            else
                painter_:Circle(x, 46, 10 * scale, i == levelIndex_ and Renderer2D.COLORS.greenStrong or Renderer2D.COLORS.panelSecondary, i == levelIndex_ and Renderer2D.COLORS.primaryActive or Renderer2D.COLORS.greenLight, 1)
            end
            painter_:Text(x, 46, tostring(i), 10 * scale, i == levelIndex_ and Renderer2D.COLORS.white or Renderer2D.COLORS.secondary, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
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
            painter_:FillRect(0, 0, frame_.logicalWidth, frame_.logicalHeight, Renderer2D.COLORS.background, 199)
            local cx, cy = frame_.playfieldX + frame_.playfieldWidth * .5, frame_.playfieldY + frame_.playfieldHeight * .5
            local function overlayButton(x, y, label, secondary)
                painter_:RoundedRect(x - 73, y - 23, 146, 46, 4, secondary and Renderer2D.COLORS.panelSecondary or Renderer2D.COLORS.greenStrong, secondary and Renderer2D.COLORS.dark or Renderer2D.COLORS.primaryActive, 2)
                painter_:Text(x, y - 8, label, 16, secondary and Renderer2D.COLORS.text or Renderer2D.COLORS.white, NVG_ALIGN_CENTER + NVG_ALIGN_TOP, "maker-display")
            end
            if success_ then
                painter_:RoundedRect(cx - 345, cy - 115, 690, 230, 4, Renderer2D.COLORS.panel, Renderer2D.COLORS.primaryActive, 2)
                painter_:Text(cx, cy - 75, assistedClear_ and "辅助观测成立" or "观测成立", 42, Renderer2D.COLORS.text, NVG_ALIGN_CENTER + NVG_ALIGN_TOP, "maker-display")
                painter_:Text(cx, cy - 6,
                    assistedClear_ and ((level_.name or "实验") .. " · 本次为 assisted clear")
                        or ((level_.name or "实验") .. " · 苹果已稳定进入观察窗"),
                    16, Renderer2D.COLORS.secondary, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
                if assistedClear_ then
                    overlayButton(cx - 80, cy + 65, levelIndex_ < CONFIG.levelCount and "下一实验" or "重新观测", false)
                    overlayButton(cx + 80, cy + 65, "再次尝试", true)
                else
                    overlayButton(cx - 160, cy + 65, levelIndex_ < CONFIG.levelCount and "下一实验" or "重新观测", false)
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
