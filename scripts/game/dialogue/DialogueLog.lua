local DialogueLog = {}
DialogueLog.__index = DialogueLog

local function cloneMessage(message)
    local copy = {}
    for key, value in pairs(message) do copy[key] = value end
    return copy
end

function DialogueLog.New()
    local self = setmetatable({}, DialogueLog)
    self:Init()
    return self
end

function DialogueLog:Init()
    self.levels = {}
end

function DialogueLog:_Level(levelId)
    local level = self.levels[levelId]
    if level then return level end
    level = {
        messages = {},
        introRecorded = false,
        thresholds = {},
        readCount = 0,
    }
    self.levels[levelId] = level
    return level
end

function DialogueLog:RecordIntro(levelId, messages)
    local level = self:_Level(levelId)
    if level.introRecorded then return false end
    for _, message in ipairs(messages or {}) do
        level.messages[#level.messages + 1] = cloneMessage(message)
    end
    level.introRecorded = true
    return true
end

function DialogueLog:HasIntro(levelId)
    local level = self.levels[levelId]
    return level ~= nil and level.introRecorded
end

function DialogueLog:IsThresholdRecorded(levelId, threshold)
    local level = self.levels[levelId]
    return level ~= nil and level.thresholds[threshold] == true
end

function DialogueLog:RecordThresholds(levelId, crossedThresholds, message)
    local level = self:_Level(levelId)
    for _, threshold in ipairs(crossedThresholds or {}) do
        level.thresholds[threshold] = true
    end
    if message then level.messages[#level.messages + 1] = cloneMessage(message) end
end

function DialogueLog:GetMessages(levelId)
    local level = self.levels[levelId]
    return level and level.messages or {}
end

function DialogueLog:MessageCount(levelId)
    local level = self.levels[levelId]
    return level and #level.messages or 0
end

function DialogueLog:MarkRead(levelId)
    local level = self:_Level(levelId)
    level.readCount = #level.messages
end

function DialogueLog:HasUnread(levelId)
    local level = self.levels[levelId]
    return level ~= nil and level.readCount < #level.messages
end

return DialogueLog
