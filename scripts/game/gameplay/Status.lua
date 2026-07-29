-- gameplay/Status: private runtime functions installed into the App context.
local M = {}

function M.Install(context)
    local _ENV = context
    function SetStatus(value)
        status_ = value
        print("[Migration] " .. value)
    end

    ---@param mode "none"|"playing"|"paused"|"finished"
    function PlaySound(kind)
        if audio_ then audio_:Play(kind) end
    end
    function UpdateAngerFromRules()
        local persistent = next(rules_.activeFields) ~= nil or rules_.phaseActive
        if persistent then
            anger_ = math.min(96, 54 + ruleDeployCount_ * 10)
        else
            anger_ = math.min(68, failureCount_ * 18)
        end
    end
    function ToggleTacticalPause()
        if success_ or failed_ or absorbing_ then return end
        if not isPaused_ then CancelAppleDrag() end
        isPaused_ = not isPaused_
        if isPaused_ then
            SetStatus("TACTICAL PAUSE 路 规则卡仍可操作")
        else
            SetStatus(launched_ and "RUNNING 路 实验进行中" or "READY 路 等待发射")
        end
    end
    function RegisterFailure()
        failureCount_ = failureCount_ + 1
        if level_ then failureCountsByLevel_[level_.levelId] = failureCount_ end
        observation_ = "轨迹停止。重置后再次发射。"
        if level_ then level_.resultOverlayVisible = true end
        SetStatus("FAILED · 实验未成立")
    end
end

return M
