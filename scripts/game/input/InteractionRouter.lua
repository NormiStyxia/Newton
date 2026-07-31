-- input/InteractionRouter: private runtime functions installed into the App context.
local M = {}

---@param context GameContext
function M.Install(context)
    local Rules = context.Rules
    local ReplayMode = context.ReplayMode
    local CONFIG = context.CONFIG
    local _ENV = context
    function PointerInPlayfield(x, y)
        return x >= frame_.playfieldX + 18 and x <= frame_.playfieldX + frame_.playfieldWidth - 18
            and y >= frame_.playfieldY + 18 and y <= frame_.groundY - 18
    end
    function UpdateHoverState(x, y)
        hoveredNavigation_ = nil
        hoveredLevelIndex_ = nil
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

        local tabStartX = frame_.playfieldX + frame_.playfieldWidth - 290
        for index = 1, CONFIG.levelCount do
            local dx, dy = x - (tabStartX + (index - 1) * 27), y - 46
            if dx * dx + dy * dy <= 10 * 10 then
                hoveredLevelIndex_ = index
                break
            end
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
            hoveredNavigation_, hoveredLevelIndex_, punchHovered_ = nil, nil, false
            SetHoveredCard(nil)
            return
        end
        UpdateHoverState(x, y)
        if context.assistantInputLocked_ then return end
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
                        if inOverlayButton(cx - 80, cy + 65) then
                            BuildLevel(levelIndex_ < CONFIG.levelCount and levelIndex_ + 1 or 1)
                        elseif inOverlayButton(cx + 80, cy + 65) then
                            ResetExperiment()
                        end
                    else
                        if inOverlayButton(cx - 160, cy + 65) then
                            BuildLevel(levelIndex_ < CONFIG.levelCount and levelIndex_ + 1 or 1)
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
            local tabStartX = frame_.playfieldX + frame_.playfieldWidth - 290
            for index = 1, CONFIG.levelCount do
                local tabX = tabStartX + (index - 1) * 27
                local dx, dy = x - tabX, y - 46
                if dx * dx + dy * dy <= 10 * 10 then
                    BuildLevel(index)
                    return
                end
            end
            if x >= titleX + 255 and x <= titleX + 301 and y >= 23 and y <= 69 then
                -- Phaser's back action falls back to restarting this level when
                -- browser history is unavailable, which is the Maker runtime case.
                ResetExperiment()
            elseif x >= titleX + 315 and x <= titleX + 361 and y >= 23 and y <= 69 then
                ResetExperiment()
            elseif x >= titleX + 375 and x <= titleX + 421 and y >= 23 and y <= 69 then
                ToggleTacticalPause()
            elseif x >= frame_.playfieldX + frame_.playfieldWidth - 98 and x <= frame_.playfieldX + frame_.playfieldWidth - 18
                and y >= frame_.cardHandY - 17 and y <= frame_.cardHandY + 63 then
                local removedRules = {}
                for cardId in pairs(rules_.activeFields) do removedRules[#removedRules + 1] = cardId end
                if rules_.phaseActive then removedRules[#removedRules + 1] = "quantum-phase" end
                if Rules.Punch(rules_) then
                    phaseTraversing_ = false
                    SetGravity()
                    ApplyAppleCardMaterial()
                    UpdateAngerFromRules()
                    for _, cardId in ipairs(removedRules) do RecordReplayEvent("RULE_REMOVED", cardId) end
                    RecordReplayEvent("NEWTON_PUNCH")
                    SetStatus("NEWTON · 修正拳已出手")
                    PlaySound("punch")
                end
            elseif not isPaused_ and not launched_ and IsNearApple(x, y) then
                draggedApple_ = true
                -- Phaser starts aiming on POINTER_DOWN, before the first move
                -- event. Keep the line and prediction visible for short drags.
                UpdateAppleDrag(x, y)
            else
                TryCardPress(x, y)
            end
        end
        if down and draggedApple_ and not launched_ then UpdateAppleDrag(x, y) end
        if down and activeCardId_ and activeCardStart_ then
            local dx, dy = x - activeCardStart_.x, y - activeCardStart_.y
            if dx * dx + dy * dy >= 12 * 12 then activeCardDragged_ = true end
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
