local AssistDemoState = require("game.assist_demo.State")
local StandardSolutions = require("game.assist_demo.StandardSolutions")
local ReplayMode = require("game.replay.Mode")

local Adapter = {}
Adapter.__index = Adapter

function Adapter.New(context)
    return setmetatable({
        context = assert(context, "Newton GreenAssistant adapter requires the App context"),
    }, Adapter)
end

Adapter.new = Adapter.New

function Adapter:canTakeover(levelId)
    local context = self.context
    return context.IsOfficialRuntimeSession ~= nil
        and context.IsOfficialRuntimeSession() == true
        and context.level_ ~= nil
        and context.apple_ ~= nil
        and context.replayBusinessMode_ == ReplayMode.NONE
        and StandardSolutions.Has(levelId)
        and not context.assistDemoActive_
end

function Adapter:lockPlayerInput()
    local context = self.context
    context.assistantInputLocked_ = true
    if context.CancelAppleDrag then context.CancelAppleDrag() end
    if context.ClearCardInteraction then context.ClearCardInteraction() end
    if context.ClearSelectedCard then context.ClearSelectedCard() end
end

function Adapter:unlockPlayerInput()
    self.context.assistantInputLocked_ = false
end

function Adapter:prepareTakeoverScene()
    local context = self.context
    context.assistantInputLocked_ = true
    context.assistSceneActive_ = true
    if context.ClearSelectedCard then context.ClearSelectedCard() end
    if context.level_ then context.level_.resultOverlayVisible = false end
end

function Adapter:getAssistReplay(levelId)
    if not self.context.IsOfficialRuntimeSession
        or self.context.IsOfficialRuntimeSession() ~= true then return nil end
    return StandardSolutions.Get(levelId)
end

function Adapter:beginTakeoverReplay(solution)
    if not self.context.IsOfficialRuntimeSession
        or self.context.IsOfficialRuntimeSession() ~= true then return false end
    return self.context.StartAssistDemo(solution)
end

function Adapter:updateTakeover(_dt)
    local state = self.context.GetAssistDemoState()
    if state == AssistDemoState.FAILED then
        error(self.context.GetAssistDemoError() or "assist demo failed")
    end
end

function Adapter:isTakeoverFinished()
    return self.context.IsAssistDemoFinished()
end

function Adapter:finishTakeover()
    assert(self.context.FinishAssistDemo(), "assist demo could not be finalized")
end

function Adapter:cancelTakeover()
    self.context.AbortAssistDemo("cancelled")
end

return Adapter
