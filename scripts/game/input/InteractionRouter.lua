-- input/InteractionRouter: private runtime functions installed into the App context.
local M = {}

---@param context GameContext
function M.Install(context)
    local Rules = context.Rules
    local ReplayMode = context.ReplayMode
    local CONFIG = context.CONFIG
    local _ENV = context
    local function pointInRect(rect, x, y)
        return rect and x >= rect.x and x <= rect.x + rect.w and y >= rect.y and y <= rect.y + rect.h
    end

    local function resultReturnIndex()
        if not IsOfficialRuntimeSession() then return levelIndex_ or 1 end
        return levelIndex_ < CONFIG.levelCount and levelIndex_ + 1 or 1
    end

    function ResolveAssistedResultLayout(frame)
        local centerX = frame.playfieldX + frame.playfieldWidth * .5
        local centerY = frame.playfieldY + frame.playfieldHeight * .5
        local panelWidth, panelHeight = 620, 210
        local buttonOffset, buttonY = 100, centerY + 60
        return {
            centerX = centerX,
            centerY = centerY,
            panel = {
                x = centerX - panelWidth * .5,
                y = centerY - panelHeight * .5,
                w = panelWidth,
                h = panelHeight,
            },
            returnButton = { x = centerX - buttonOffset, y = buttonY },
            retryButton = { x = centerX + buttonOffset, y = buttonY },
        }
    end

    function HandleHUDPointer(pointerFrame)
        local layout = ResolveHUDLayout(frame_)
        local x, y = pointerFrame.x, pointerFrame.y
        if hudDropdown_ then
            local dropdownRect = ResolveHUDDropdownRect(hudDropdown_)
            if pointInRect(dropdownRect, x, y) then return true end
        end
        if not pointerFrame.pressed then return false end
        if pointInRect(layout.left, x, y) and #hudRuleList_ >= 2 then
            hudDropdown_ = hudDropdown_ == "rules" and nil or "rules"
            playUIClick()
            return true
        end
        if pointInRect(layout.right, x, y) then
            hudDropdown_ = hudDropdown_ == "rating" and nil or "rating"
            playUIClick()
            return true
        end
        if hudDropdown_ then
            hudDropdown_ = nil
            playUIClick()
            return true
        end
        return false
    end

    function PointerInPlayfield(x, y)
        return x >= frame_.playfieldX + 18 and x <= frame_.playfieldX + frame_.playfieldWidth - 18
            and y >= frame_.playfieldY + 18 and y <= frame_.groundY - 18
    end
    function UpdateHoverState(x, y)
        hoveredNavigation_ = nil
        punchHovered_ = false
        if replayActive_ or success_ or failed_ then
            SetHoveredCard(nil)
            return
        end

        local titleX = frame_.workspaceX - 37
        if x >= titleX + 255 and x <= titleX + 301 and y >= 23 and y <= 69 then
            hoveredNavigation_ = "back"
        elseif x >= titleX + 315 and x <= titleX + 361 and y >= 23 and y <= 69 then
            hoveredNavigation_ = "reset"
        elseif not isPaused_ and x >= titleX + 375 and x <= titleX + 421 and y >= 23 and y <= 69 then
            hoveredNavigation_ = "pause"
        end

        local punchX, punchY = frame_.playfieldX + frame_.playfieldWidth - 58, frame_.cardHandY + 23
        punchHovered_ = x >= punchX - 40 and x <= punchX + 40 and y >= punchY - 40 and y <= punchY + 40
        -- Tactical pause freezes the experiment, not the rule-card affordance.
        -- Phaser keeps card hover feedback available while paused.
        if activeCardId_ or primedCardId_ or #cardBurns_ > 0 then
            SetHoveredCard(nil)
        else
            local card = FindTopCardAt(x, y)
            SetHoveredCard(card and card.cardId or nil)
        end
    end
    function HandlePointer(pointerFrame, assistantHandled)
        if not frame_ or not apple_ then return end
        pointerFrame = pointerFrame or PointerState()
        local x, y = pointerFrame.x, pointerFrame.y
        local down, press, release = pointerFrame.down, pointerFrame.pressed, pointerFrame.released
        local assistantConsumed = assistantHandled
        if assistantConsumed == nil then
            assistantConsumed = HandleGreenAssistantPointer(x, y, pointerFrame)
        end
        if assistantConsumed then
            hoveredNavigation_, punchHovered_ = nil, false
            SetHoveredCard(nil)
            return
        end
        if IsResultReportVisible and IsResultReportVisible() then
            HandleResultReportInput(pointerFrame)
            return
        end
        if context.assistantInputLocked_ then
            hoveredNavigation_, punchHovered_ = nil, false
            SetHoveredCard(nil)
            return
        end
        if HandleHUDPointer(pointerFrame) then
            hoveredNavigation_, punchHovered_ = nil, false
            SetHoveredCard(nil)
            return
        end
        UpdateHoverState(x, y)
        if replayActive_ then
            if replayBusinessMode_ == ReplayMode.PLAYER_REPLAY then HandleReplayPointer(x, y, press) end
            return
        end
        if IsResultOverlayVisible() then
            if press then
                local cx, cy = frame_.playfieldX + frame_.playfieldWidth * .5, frame_.playfieldY + frame_.playfieldHeight * .5
                local function inOverlayButton(buttonX, buttonY)
                    return x >= buttonX - 73 and x <= buttonX + 73 and y >= buttonY - 23 and y <= buttonY + 23
                end
                if failed_ and inOverlayButton(cx, cy + 60) then
                    ResetExperiment()
                elseif success_ then
                    if assistedClear_ then
                        local layout = ResolveAssistedResultLayout(frame_)
                        if inOverlayButton(layout.returnButton.x, layout.returnButton.y) then
                            RequestReturnToCatalog(resultReturnIndex())
                        elseif inOverlayButton(layout.retryButton.x, layout.retryButton.y) then
                            ResetExperiment()
                        end
                    else
                        if inOverlayButton(cx - 160, cy + 65) then
                            RequestReturnToCatalog(resultReturnIndex())
                        elseif inOverlayButton(cx, cy + 65) then
                            StartReplay()
                        elseif inOverlayButton(cx + 160, cy + 65) then
                            ResetExperiment()
                        end
                    end
                end
            end
            return
        end
        if press then
            local titleX = frame_.workspaceX - 37
            if x >= titleX + 255 and x <= titleX + 301 and y >= 23 and y <= 69 then
                RequestReturnToCatalog(levelIndex_)
            elseif x >= titleX + 315 and x <= titleX + 361 and y >= 23 and y <= 69 then
                hudDropdown_ = nil
                ResetExperiment()
            elseif x >= titleX + 375 and x <= titleX + 421 and y >= 23 and y <= 69 then
                hudDropdown_ = nil
                playUIClick()
                ToggleTacticalPause()
            elseif x >= frame_.playfieldX + frame_.playfieldWidth - 98 and x <= frame_.playfieldX + frame_.playfieldWidth - 18
                and y >= frame_.cardHandY - 17 and y <= frame_.cardHandY + 63 then
                ExecuteNewtonPunch()
            elseif not isPaused_ and not launched_ and IsNearApple(x, y) then
                draggedApple_ = true
                -- Phaser starts aiming on POINTER_DOWN, before the first move
                -- event. Keep the line and prediction visible for short drags.
                UpdateAppleDrag(x, y)
            else
                if not TryCardPress(x, y) then ClearSelectedCard() end
            end
        end
        if down and draggedApple_ and not launched_ then UpdateAppleDrag(x, y) end
        if down and activeCardId_ and activeCardStart_ then
            local dx, dy = x - activeCardStart_.x, y - activeCardStart_.y
            if dx * dx + dy * dy >= 12 * 12 and not activeCardDragged_ then
                activeCardDragged_ = true
                -- A hand gesture has become an action, so the read-only detail
                -- card leaves immediately without changing deployment state.
                ClearSelectedCard()
            end
            activeCardPointer_ = { x = x, y = y }
            if activeCardDragged_ and not activeCardDeploying_ then
                local home = CardHomePose(activeCardId_)
                if home and y >= home.y - 40 then
                    if not cardHandReordering_ then
                        cardHandReordering_ = true
                        SetStatus("HAND · 调整卡牌顺序")
                    end
                    local entries = CardEntries()
                    local poses = Rules.CardHand(#entries, frame_.playfieldX + frame_.playfieldWidth * .5, frame_.cardHandY, frame_.playfieldWidth)
                    local target, nearest = 1, math.huge
                    for i, pose in ipairs(poses) do
                        local distance = math.abs(x - pose.x)
                        if distance < nearest then target, nearest = i, distance end
                    end
                    MoveCardToHandSlot(activeCardId_, target)
                elseif home then
                    activeCardDeploying_ = true
                    cardHandReordering_ = false
                    SetStatus("CARD DRAGGING · 子弹时间 0.05")
                end
            end
        end
        if release then
            if draggedApple_ then LaunchApple() end
            if activeCardId_ then ResolveActiveCard(x, y) end
        end
    end
end

return M
