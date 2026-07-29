local GreenAssistant = require("green_assistant.GreenAssistant")
local NewtonGreenAssistAdapter = require("game.green_assistant.NewtonGreenAssistAdapter")

local M = {}

function M.Install(context)
    local _ENV = context

    function InitializeGreenAssistant()
        greenAssistantAdapter_ = NewtonGreenAssistAdapter.New(context)
        greenAssistant_ = GreenAssistant.new({
            renderer = painter_,
            adapter = greenAssistantAdapter_,
            events = {
                onTakeoverStarted = function()
                    SetStatus("ASSIST · 接管中")
                end,
            },
        })
    end

    function DestroyGreenAssistant()
        if greenAssistant_ then greenAssistant_:destroy(); greenAssistant_ = nil end
        greenAssistantAdapter_ = nil
    end

    function UpdateGreenAssistant(dt)
        if greenAssistant_ then greenAssistant_:update(dt, frame_) end
    end

    function DrawGreenAssistant()
        if greenAssistant_ then greenAssistant_:render() end
    end

    function HandleGreenAssistantPointer(x, y, pointerFrame)
        return greenAssistant_ and greenAssistant_:handlePointer(x, y, pointerFrame) or false
    end

    function NotifyGreenAssistantAttemptFailed(payload)
        if greenAssistant_ then greenAssistant_:onAttemptFailed(payload) end
    end

    function NotifyGreenAssistantAttemptSucceeded()
        if greenAssistant_ then greenAssistant_:onAttemptSucceeded() end
    end

    function NotifyGreenAssistantLevelChanged(levelId)
        if greenAssistant_ then greenAssistant_:onLevelChanged(levelId) end
    end
end

return M
