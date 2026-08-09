local GreenAssistant = require("green_assistant.GreenAssistant")
local NewtonGreenAssistAdapter = require("game.green_assistant.NewtonGreenAssistAdapter")

local M = {}

---@param context GameContext
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

    function AbortGreenAssistantTakeover(reason)
        if greenAssistant_ and greenAssistant_.cancelTakeover then
            if greenAssistant_:cancelTakeover(reason) then return true end
        end
        if context.AbortAssistDemo then return context.AbortAssistDemo(reason) end
        return false
    end

    function DestroyGreenAssistant()
        if greenAssistant_ then greenAssistant_:destroy(); greenAssistant_ = nil end
        greenAssistantAdapter_ = nil
    end

    function UpdateGreenAssistant(dt)
        if greenAssistant_ then greenAssistant_:update(dt) end
    end

    function DrawGreenAssistant()
        if greenAssistant_ and frame_ then greenAssistant_:setFrame(frame_) end
        if greenAssistant_ and greenAssistant_:getBehavior() ~= GreenAssistant.Behavior.OFFER then
            greenAssistant_:render()
        end
    end

    function DrawGreenAssistantOverlay()
        if greenAssistant_ and frame_ then greenAssistant_:setFrame(frame_) end
        if greenAssistant_ and greenAssistant_:getBehavior() == GreenAssistant.Behavior.OFFER then
            greenAssistant_:render()
        end
    end

    function HandleGreenAssistantPointer(x, y, pointerFrame)
        if not greenAssistant_ then return false end
        -- Layout is applied first so pointer and CompanionZone share the same
        -- current-frame design-space coordinates.
        greenAssistant_:setFrame(frame_)
        return greenAssistant_:handlePointer(x, y, pointerFrame)
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
