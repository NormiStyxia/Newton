local AssistReplayData = require("game.replay.AssistReplayData")
local ReplayMode = require("game.replay.Mode")

local Adapter = {}
Adapter.__index = Adapter

function Adapter.New(context)
    local self = setmetatable({}, Adapter)
    self.context = assert(context, "Newton GreenAssistant adapter requires the App context")
    self.cache = {}
    return self
end

Adapter.new = Adapter.New

function Adapter:_load(levelId)
    if self.cache[levelId] ~= nil then return self.cache[levelId] or nil end
    local resourcePath = string.format("Data/Assist/%s.json", tostring(levelId))
    local data, errorMessage = AssistReplayData.Load(resourcePath, levelId)
    if not data then
        print("[GreenAssistant] " .. tostring(errorMessage))
        self.cache[levelId] = false
        return nil
    end
    local runtime = AssistReplayData.ToRuntime(data, self.context.mapper_)
    self.cache[levelId] = runtime
    return runtime
end

function Adapter:canTakeover(levelId)
    local context = self.context
    return context.level_ ~= nil
        and context.apple_ ~= nil
        and context.replayBusinessMode_ == ReplayMode.NONE
        and self:_load(levelId) ~= nil
end

function Adapter:lockPlayerInput()
    local context = self.context
    context.assistantInputLocked_ = true
    if context.CancelAppleDrag then context.CancelAppleDrag() end
    if context.ClearCardInteraction then context.ClearCardInteraction() end
end

function Adapter:unlockPlayerInput()
    self.context.assistantInputLocked_ = false
end

function Adapter:prepareTakeoverScene()
    local context = self.context
    context.ResetExperiment(false)
    context.assistantInputLocked_ = true
    context.assistSceneActive_ = true
    if context.level_ then context.level_.resultOverlayVisible = false end
end

function Adapter:getAssistReplay(levelId)
    return self:_load(levelId)
end

function Adapter:beginTakeoverReplay(replayData)
    return self.context.StartAssistReplay(replayData)
end

function Adapter:updateTakeover(_dt)
    -- AppRuntime owns the shared ReplayPlayer update. The adapter only exposes
    -- completion state to GreenAssistant and never advances a second timeline.
end

function Adapter:isTakeoverFinished()
    local context = self.context
    return context.replayBusinessMode_ == ReplayMode.ASSIST_TAKEOVER and context.replayFinished_ == true
end

function Adapter:finishTakeover()
    local context = self.context
    assert(context.FinishAssistReplay(), "assist replay could not be finalized")
    context.CompleteLevel({ assisted = true })
    context.assistSceneActive_ = false
end

function Adapter:cancelTakeover()
    local context = self.context
    if context.replayBusinessMode_ == ReplayMode.ASSIST_TAKEOVER then context.CancelAssistReplay() end
    context.assistSceneActive_ = false
end

return Adapter
