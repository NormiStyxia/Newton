local Config = require("ui.result_report_config")
local Pools = require("ui.review_pools")
local Selector = require("ui.review_selector")

local M = {}

---@param context GameContext
function M.Install(context)
    local _ENV = context
    local CONFIG = context.CONFIG

    resultReportState_ = nil
    resultReportClearCounts_ = {}
    resultReportHistory_ = { einstein = {}, green = {} }
    resultReportNextId_ = 0
    resultReportAnimation_ = 0
    resultReportClosing_ = nil

    function HasResultReportReplay()
        return CanReplay and CanReplay() == true
    end

    function IsResultReportVisible()
        return success_ and resultReportState_ ~= nil
            and replayMode_ == "none" and replayBusinessMode_ == context.ReplayMode.NONE
    end

    function GetResultReportState()
        return resultReportState_
    end

    function ClearResultReportState()
        resultReportState_ = nil
        resultReportClosing_ = nil
        resultReportAnimation_ = 0
    end

    local function newResultId(levelId, clearCount)
        resultReportNextId_ = resultReportNextId_ + 1
        return string.format("%s-%02d-%03d", tostring(levelId or "EXP"), clearCount, resultReportNextId_)
    end

    function GenerateResultReport()
        if resultReportState_ and resultReportState_.levelId == (level_ and level_.levelId) then return resultReportState_ end
        if not level_ then return nil end

        local levelId = level_.levelId or string.format("level_%02d", levelIndex_ or 1)
        local clearCount = (resultReportClearCounts_[levelId] or 0) + 1
        resultReportClearCounts_[levelId] = clearCount
        local resultId = newResultId(levelId, clearCount)
        local seed = table.concat({ tostring(levelId), tostring(clearCount), resultId }, "_")
        local selfOptions = Selector.SampleUnique(Pools.NomiSelfReviewPool, 3, seed .. ":nomi")
        local einstein = Selector.SampleReview(Pools.EinsteinReviewPool, resultReportHistory_.einstein, 2, seed .. ":einstein")
        local green = Selector.SampleReview(Pools.GreenReviewPool, resultReportHistory_.green, 2, seed .. ":green")
        Selector.PushRecent(resultReportHistory_.einstein, einstein, 2)
        Selector.PushRecent(resultReportHistory_.green, green, 2)
        local newtonReview, newtonTier = Config.NewtonReview(anger_)

        resultReportState_ = {
            resultId = resultId,
            experimentNumber = tonumber(levelIndex_) or 1,
            levelId = levelId,
            clearCount = clearCount,
            title = "观测成立",
            experimentName = level_.name or "第一颗苹果",
            resultDescription = observation_ ~= "" and observation_ or "苹果已稳定进入观察窗",
            selfOptions = selfOptions,
            selectedSelfReview = nil,
            newtonReview = newtonReview,
            newtonTier = newtonTier,
            einsteinReview = einstein,
            greenReview = green,
            isDropdownOpen = false,
            dropdownProgress = 0,
            highlightedOption = 1,
            hoveredOption = nil,
            validationMessage = nil,
            reviewOverflowLogged = {},
            anger = math.max(0, math.min(100, tonumber(anger_) or 0)),
        }
        resultReportAnimation_ = 0
        resultReportClosing_ = nil
        isPaused_ = true
        print(string.format("[ResultReport] generated resultId=%s levelId=%s clearCount=%d anger=%d", resultId, levelId, clearCount, resultReportState_.anger))
        return resultReportState_
    end

    function UpdateResultReport(dt)
        if resultReportClosing_ then
            resultReportAnimation_ = math.max(0, resultReportAnimation_ - math.max(0, dt) / Config.Layout.exitDuration)
            if resultReportAnimation_ <= 0 then
                local action = resultReportClosing_
                resultReportClosing_ = nil
                resultReportState_ = nil
                action()
            end
        elseif resultReportState_ then
            resultReportAnimation_ = math.min(1, resultReportAnimation_ + math.max(0, dt) / Config.Layout.enterDuration)
            local target = resultReportState_.isDropdownOpen and 1 or 0
            local response = 1 - math.exp(-math.max(0, dt) / 0.085)
            resultReportState_.dropdownProgress = math.max(0, math.min(1,
                (resultReportState_.dropdownProgress or 0) + (target - (resultReportState_.dropdownProgress or 0)) * response))
        end
    end

    local function pointInRect(x, y, rect)
        return rect and x >= rect.x and x <= rect.x + rect.w and y >= rect.y and y <= rect.y + rect.h
    end

    local function dropdownEaseOut(value)
        value = math.max(0, math.min(1, value or 0))
        return 1 - (1 - value) * (1 - value)
    end

    function BeginResultReportAction(actionName)
        if not resultReportState_ or resultReportClosing_ then return end
        local state = resultReportState_
        if actionName == "next" and Config.Layout.requireSelfReview and not state.selectedSelfReview then
            state.validationMessage = "请先完成本次自我评价"
            return
        end
        state.isDropdownOpen = false
        resultReportClosing_ = function()
            if actionName == "retry" then
                ResetExperiment()
            elseif actionName == "replay" then
                isPaused_ = false
                if not StartReplay() then
                    resultReportState_ = state
                    resultReportAnimation_ = 1
                    isPaused_ = true
                end
            elseif actionName == "next" then
                local nextIndex = levelIndex_ < CONFIG.levelCount and levelIndex_ + 1 or nil
                if nextIndex then BuildLevel(nextIndex) else BuildLevel(1) end
            end
        end
    end

    function HandleResultReportInput(pointerFrame)
        if not IsResultReportVisible() or resultReportClosing_ then return true end
        local state = resultReportState_
        local x, y = pointerFrame.x, pointerFrame.y
        local hasReplay = HasResultReportReplay()
        local rect = Config.ResolveRect(frame_)
        local zones = Config.ResolveZones(rect, hasReplay)
        local animation = math.max(0, math.min(1, resultReportAnimation_ or 1))
        local reportOffsetY = -(1 - (1 - animation) * (1 - animation)) * 24
        local selfBox = {
            x = zones.selfBox.x,
            y = zones.selfBox.y + reportOffsetY,
            w = zones.selfBox.w,
            h = zones.selfBox.h,
        }
        local optionStartY = selfBox.y + selfBox.h + 5
        state.hoveredOption = nil
        if state.isDropdownOpen then
            local optionReveal = dropdownEaseOut(state.dropdownProgress)
            local optionHeight = 25 * math.min(1, optionReveal * 1.15)
            for index = 1, #state.selfOptions do
                local optionRect = {
                    x = selfBox.x,
                    y = optionStartY + (index - 1) * 27 * optionReveal,
                    w = selfBox.w,
                    h = optionHeight,
                }
                if pointInRect(x, y, optionRect) then state.hoveredOption = index; break end
            end
        end
        if input:GetKeyPress(KEY_ESCAPE) then
            state.isDropdownOpen = false
            return true
        end
        if state.isDropdownOpen then
            if input:GetKeyPress(KEY_UP) then
                state.highlightedOption = math.max(1, (state.highlightedOption or 1) - 1)
                return true
            elseif input:GetKeyPress(KEY_DOWN) then
                state.highlightedOption = math.min(#state.selfOptions, (state.highlightedOption or 1) + 1)
                return true
            elseif input:GetKeyPress(KEY_RETURN) or input:GetKeyPress(KEY_SPACE) then
                state.selectedSelfReview = state.selfOptions[state.highlightedOption or 1]
                state.isDropdownOpen = false
                state.validationMessage = nil
                return true
            end
        end
        if not pointerFrame.pressed then return true end
        if state.isDropdownOpen and state.hoveredOption then
            state.selectedSelfReview = state.selfOptions[state.hoveredOption]
            state.highlightedOption = state.hoveredOption
            state.isDropdownOpen = false
            state.validationMessage = nil
            return true
        end
        if pointInRect(x, y, selfBox) then
            state.isDropdownOpen = not state.isDropdownOpen
            state.highlightedOption = 1
            return true
        end
        if state.isDropdownOpen then
            state.isDropdownOpen = false
            return true
        end
        if pointInRect(x, y, zones.retry) then BeginResultReportAction("retry"); return true end
        if zones.replay and pointInRect(x, y, zones.replay) then BeginResultReportAction("replay"); return true end
        if pointInRect(x, y, zones.next) then BeginResultReportAction("next"); return true end
        return true
    end
end

return M
