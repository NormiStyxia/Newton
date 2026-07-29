local Takeover = {}
Takeover.__index = Takeover

local function Call(adapter, method, ...)
    local callback = adapter and adapter[method]
    if type(callback) ~= "function" then return nil end
    return callback(adapter, ...)
end

function Takeover.New(adapter, callbacks)
    local self = setmetatable({}, Takeover)
    self.adapter = adapter
    self.callbacks = callbacks or {}
    self.active = false
    self.levelId = nil
    self.replayData = nil
    return self
end

Takeover.new = Takeover.New

function Takeover:canStart(levelId)
    local ok, allowed = pcall(Call, self.adapter, "canTakeover", levelId)
    return ok and allowed == true
end

local function Rollback(self)
    pcall(Call, self.adapter, "cancelTakeover")
    pcall(Call, self.adapter, "unlockPlayerInput")
    self.active = false
    self.levelId = nil
    self.replayData = nil
end

function Takeover:start(levelId)
    if self.active then return false, "takeover is already active" end
    if not self:canStart(levelId) then return false, "takeover is unavailable" end

    local ok, result = pcall(function()
        Call(self.adapter, "lockPlayerInput")
        Call(self.adapter, "prepareTakeoverScene")
        local replayData = Call(self.adapter, "getAssistReplay", levelId)
        assert(type(replayData) == "table", "assist replay is unavailable")
        local began = Call(self.adapter, "beginTakeoverReplay", replayData)
        assert(began ~= false, "adapter rejected assist replay")
        self.levelId = levelId
        self.replayData = replayData
        self.active = true
        if self.callbacks.onStarted then self.callbacks.onStarted(replayData) end
        return true
    end)
    if not ok then
        Rollback(self)
        return false, tostring(result)
    end
    return result
end

function Takeover:update(dt)
    if not self.active then return false end
    local ok, err = pcall(Call, self.adapter, "updateTakeover", math.max(0, dt or 0))
    if not ok then
        Rollback(self)
        if self.callbacks.onError then self.callbacks.onError(tostring(err)) end
        return false
    end
    local finishedOk, finished = pcall(Call, self.adapter, "isTakeoverFinished")
    if not finishedOk then
        Rollback(self)
        if self.callbacks.onError then self.callbacks.onError(tostring(finished)) end
        return false
    end
    if finished == true then return self:finish() end
    return false
end

function Takeover:finish()
    if not self.active then return false end
    local replayData = self.replayData
    local ok, err = pcall(Call, self.adapter, "finishTakeover")
    pcall(Call, self.adapter, "unlockPlayerInput")
    self.active = false
    self.levelId = nil
    self.replayData = nil
    if not ok then
        if self.callbacks.onError then self.callbacks.onError(tostring(err)) end
        return false
    end
    if self.callbacks.onFinished then self.callbacks.onFinished(replayData) end
    return true
end

function Takeover:cancel()
    if not self.active then return false end
    Rollback(self)
    if self.callbacks.onCancelled then self.callbacks.onCancelled() end
    return true
end

function Takeover:isActive()
    return self.active
end

return Takeover
