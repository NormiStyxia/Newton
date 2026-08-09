local AssistDemoState = require("game.assist_demo.State")
local GameAdapter = require("game.assist_demo.GameAdapter")
local Runner = require("game.assist_demo.Runner")
local CursorView = require("game.assist_demo.CursorView")

local M = {}

---@param context GameContext
function M.Install(context)
    local _ENV = context

    function InitializeAssistDemo()
        assistDemoView_ = CursorView.New(painter_)
        assistDemoGameAdapter_ = GameAdapter.New(context)
        assistDemoRunner_ = Runner.New(assistDemoGameAdapter_, assistDemoView_, {
            onStateChanged = function(state, _previous, reason)
                SetStatus("ASSIST · " .. state)
                if state == AssistDemoState.FAILED then print("[AssistDemo] failed: " .. tostring(reason)) end
            end,
        })
    end

    function DestroyAssistDemo()
        if assistDemoGameAdapter_ then assistDemoGameAdapter_:shutdown() end
        assistDemoRunner_, assistDemoGameAdapter_, assistDemoView_ = nil, nil, nil
        assistDemoActive_, assistUsed_ = false, false
    end

    function StartAssistDemo(solution)
        if not IsOfficialRuntimeSession() or not assistDemoRunner_ then return false end
        local start = frame_ and { x = frame_.playfieldX + frame_.playfieldWidth * 0.5, y = 86 } or nil
        return assistDemoRunner_:start(solution, start)
    end

    function UpdateAssistDemo(dt)
        if assistDemoRunner_ then assistDemoRunner_:update(dt) end
    end

    function HandleAssistDemoPointer(pointerFrame)
        if not assistSceneActive_ or not assistDemoView_ or not pointerFrame or not pointerFrame.pressed then
            return false
        end
        if not assistDemoView_:containsStatusPoint(frame_, pointerFrame.x, pointerFrame.y) then return false end
        return context.AbortGreenAssistantTakeover("pointer") == true
    end

    function UpdateAssistDemoPhysicsStep(dt)
        if assistDemoRunner_ then assistDemoRunner_:afterPhysicsStep(dt) end
    end

    function AdvanceAssistDemoSimulation(dt)
        if not assistDemoGameAdapter_ then return 0 end
        return assistDemoGameAdapter_:advanceSimulation(dt)
    end

    function DrawAssistDemo()
        if assistDemoView_ then assistDemoView_:render(frame_) end
    end

    function GetAssistDemoState()
        return assistDemoRunner_ and assistDemoRunner_:getState() or AssistDemoState.IDLE
    end

    function GetAssistDemoError()
        return assistDemoRunner_ and assistDemoRunner_:getError() or nil
    end

    function IsAssistDemoFinished()
        return GetAssistDemoState() == AssistDemoState.COMPLETED
    end

    function FinishAssistDemo()
        if not IsAssistDemoFinished() then return false end
        assistDemoGameAdapter_:completeSession()
        assistDemoView_:close()
        return true
    end

    function AbortAssistDemo(reason)
        if not assistDemoRunner_ then return false end
        local state = assistDemoRunner_:getState()
        if AssistDemoState.IsActive(state) then assistDemoRunner_:abort(reason or "aborted") end
        assistDemoGameAdapter_:abortSession()
        assistDemoView_:close()
        return true
    end
end

return M
