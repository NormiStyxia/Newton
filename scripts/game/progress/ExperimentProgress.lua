local ExperimentProgress = {}
ExperimentProgress.__index = ExperimentProgress

local ROOT = "experiment-progress"
local PROGRESS_PATH = ROOT .. "/official-experiments.json"
local SCHEMA_VERSION = 1
local VALID_SCORES = { [60] = true, [80] = true, [100] = true }

local function closeFile(file)
    if file.Close then file:Close() elseif file.Dispose then file:Dispose() end
end

local function createLocalAdapter()
    if _G.GetPlatform and GetPlatform() == "Web" then return nil end
    if not (_G.File and _G.fileSystem and _G.FILE_READ and _G.FILE_WRITE) then return nil end
    local adapter = { kind = "local-slot-best-effort" }
    function adapter:createDir(path) return fileSystem:CreateDir(path) end
    function adapter:exists(path) return fileSystem:FileExists(path) end
    function adapter:delete(path) return fileSystem:Delete(path) end
    function adapter:rename(source, destination) return fileSystem:Rename(source, destination) end
    function adapter:write(path, text)
        local file = File(path, FILE_WRITE)
        if not file or not file:IsOpen() then return false end
        local ok, written = pcall(file.WriteString, file, text)
        closeFile(file)
        return ok and written == true
    end
    function adapter:read(path)
        if not fileSystem:FileExists(path) then return nil end
        local file = File(path, FILE_READ)
        if not file or not file:IsOpen() then return nil end
        local text = file:ReadString()
        closeFile(file)
        return text
    end
    return adapter
end

local function validLevelId(levelId)
    return type(levelId) == "string" and levelId:match("^[%w_-]+$") ~= nil
end

local function validScore(value)
    value = tonumber(value)
    return value and VALID_SCORES[value] and value or nil
end

local function cloneRecord(record)
    if type(record) ~= "table" then return { completed = false, bestScore = nil } end
    local bestScore = validScore(record.bestScore)
    return {
        completed = record.completed == true or bestScore ~= nil,
        bestScore = bestScore,
    }
end

local function encode(self, value)
    if not self.json or type(self.json.encode) ~= "function" then return nil, "JSON encoder unavailable" end
    local ok, text = pcall(self.json.encode, value)
    if not ok or type(text) ~= "string" then return nil, tostring(text) end
    return text, nil
end

local function decode(self, text)
    if not self.json or type(self.json.decode) ~= "function" then return nil, "JSON decoder unavailable" end
    local ok, value = pcall(self.json.decode, text)
    if not ok or type(value) ~= "table" then return nil, tostring(value) end
    return value, nil
end

local function readEnvelope(self, path)
    if not self.adapter then return nil, "local persistence unavailable" end
    local ok, text = pcall(self.adapter.read, self.adapter, path)
    if not ok or not text then return nil, ok and "slot missing" or tostring(text) end
    return decode(self, text)
end

local function writeAtomic(self)
    if not self.adapter then return false, "local persistence unavailable" end
    local text, encodeError = encode(self, {
        kind = "experiment-progress",
        schemaVersion = SCHEMA_VERSION,
        experiments = self.records,
    })
    if not text then return false, encodeError end

    local temporary, backup = PROGRESS_PATH .. ".tmp", PROGRESS_PATH .. ".bak"
    local ok, errorMessage = pcall(function()
        assert(self.adapter:write(temporary, text), "temporary write failed")
        if self.adapter:exists(PROGRESS_PATH) then
            if self.adapter:exists(backup) then self.adapter:delete(backup) end
            assert(self.adapter:rename(PROGRESS_PATH, backup), "backup rotation failed")
        end
        assert(self.adapter:rename(temporary, PROGRESS_PATH), "commit rename failed")
    end)
    if ok then return true, nil end
    pcall(function()
        if self.adapter:exists(temporary) then self.adapter:delete(temporary) end
        if not self.adapter:exists(PROGRESS_PATH) and self.adapter:exists(backup) then
            self.adapter:rename(backup, PROGRESS_PATH)
        end
    end)
    return false, tostring(errorMessage)
end

function ExperimentProgress.New(options)
    local self = setmetatable({}, ExperimentProgress)
    self.json = options and options.json
    self.adapter = options and options.adapter or createLocalAdapter()
    self.records = {}
    self.pendingFeedback = nil
    if self.adapter then pcall(self.adapter.createDir, self.adapter, ROOT) end
    self:Load()
    return self
end

function ExperimentProgress:Load()
    local envelope = readEnvelope(self, PROGRESS_PATH)
    if (not envelope or envelope.kind ~= "experiment-progress") then
        envelope = readEnvelope(self, PROGRESS_PATH .. ".bak")
    end
    if type(envelope) ~= "table" or type(envelope.experiments) ~= "table" then return false end
    for levelId, record in pairs(envelope.experiments) do
        if validLevelId(levelId) then self.records[levelId] = cloneRecord(record) end
    end
    return true
end

function ExperimentProgress:Get(levelId)
    return cloneRecord(self.records[levelId])
end

function ExperimentProgress:Record(levelId, score)
    if not validLevelId(levelId) then return nil, "invalid level id" end
    local previous = cloneRecord(self.records[levelId])
    local newScore = validScore(score)
    local nextRecord = cloneRecord(previous)
    nextRecord.completed = true
    if newScore and (not nextRecord.bestScore or newScore > nextRecord.bestScore) then
        nextRecord.bestScore = newScore
    end

    local firstCompletion = previous.completed ~= true
    local bestImproved = nextRecord.bestScore ~= previous.bestScore
    self.records[levelId] = nextRecord

    local persisted, persistenceError = true, nil
    if firstCompletion or bestImproved then
        persisted, persistenceError = writeAtomic(self)
        self.pendingFeedback = {
            levelId = levelId,
            firstCompletion = firstCompletion,
            bestImproved = bestImproved,
            previousScore = previous.bestScore,
            bestScore = nextRecord.bestScore,
        }
    end
    return {
        completed = true,
        firstCompletion = firstCompletion,
        bestImproved = bestImproved,
        bestScore = nextRecord.bestScore,
        persisted = persisted,
        persistenceError = persistenceError,
    }, nil
end

function ExperimentProgress:ConsumeFeedback()
    local feedback = self.pendingFeedback
    self.pendingFeedback = nil
    return feedback
end

function ExperimentProgress:ClearPendingFeedback()
    self.pendingFeedback = nil
end

function ExperimentProgress:PersistenceKind()
    return self.adapter and (self.adapter.kind or "local-slot") or "memory-only"
end

return ExperimentProgress
