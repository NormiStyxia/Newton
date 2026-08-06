local ExperimentProgress = {}
ExperimentProgress.__index = ExperimentProgress

local ROOT = "experiment-progress"
local PROGRESS_PATH = ROOT .. "/official-experiments.json"
local SCHEMA_VERSION = 2
local VALID_SCORES = { [60] = true, [80] = true, [100] = true }
local SNAPSHOT_SCHEMA_VERSION = 1
local MAX_RULES = 12

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

local function cleanText(value, fallback)
    if type(value) ~= "string" or value == "" then return fallback end
    return value
end

local function cloneStringList(values)
    local result = {}
    if type(values) ~= "table" then return result end
    for _, value in ipairs(values) do
        if type(value) == "string" and value ~= "" then
            result[#result + 1] = value
            if #result >= MAX_RULES then break end
        end
    end
    return result
end

local function cloneSnapshot(snapshot)
    if type(snapshot) ~= "table" or not validLevelId(snapshot.levelId) then return nil end
    local score = validScore(snapshot.score)
    if not score then return nil end
    local clearedAt = math.max(0, math.floor(tonumber(snapshot.clearedAt) or 0))
    return {
        schemaVersion = SNAPSHOT_SCHEMA_VERSION,
        levelId = snapshot.levelId,
        experimentNumber = math.max(1, math.floor(tonumber(snapshot.experimentNumber) or 1)),
        experimentName = cleanText(snapshot.experimentName, "未命名实验"),
        title = cleanText(snapshot.title, "观测成立"),
        clearedAt = clearedAt,
        score = score,
        maxScore = math.max(score, math.floor(tonumber(snapshot.maxScore) or 100)),
        ratingLabel = cleanText(snapshot.ratingLabel, "观测成立"),
        interventionCount = math.max(0, math.floor(tonumber(snapshot.interventionCount) or 0)),
        summaryText = cleanText(snapshot.summaryText, "实验结果已归档"),
        resultDescription = cleanText(snapshot.resultDescription, "实验结果已归档"),
        selectedSelfReview = cleanText(snapshot.selectedSelfReview, nil),
        newtonReview = cleanText(snapshot.newtonReview, "暂无评语。"),
        einsteinReview = cleanText(snapshot.einsteinReview, "暂无评语。"),
        greenReview = cleanText(snapshot.greenReview, "暂无评语。"),
        anger = math.max(0, math.min(100, math.floor(tonumber(snapshot.anger) or 0))),
        newtonDangerAccent = snapshot.newtonDangerAccent == true,
        usedRules = cloneStringList(snapshot.usedRules),
    }
end

local function cloneRecord(record)
    if type(record) ~= "table" then
        return { completed = false, bestScore = nil, lastReportSnapshot = nil }
    end
    local bestScore = validScore(record.bestScore)
    return {
        completed = record.completed == true or bestScore ~= nil,
        bestScore = bestScore,
        lastReportSnapshot = cloneSnapshot(record.lastReportSnapshot),
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

function ExperimentProgress:GetReportSnapshot(levelId)
    if not validLevelId(levelId) then return nil end
    return cloneSnapshot(self.records[levelId] and self.records[levelId].lastReportSnapshot)
end

function ExperimentProgress:HasReportSnapshot(levelId)
    return validLevelId(levelId)
        and self.records[levelId] ~= nil
        and self.records[levelId].lastReportSnapshot ~= nil
end

function ExperimentProgress:Record(levelId, score, reportSnapshot)
    if not validLevelId(levelId) then return nil, "invalid level id" end
    local previous = cloneRecord(self.records[levelId])
    local newScore = validScore(score)
    local snapshot = reportSnapshot ~= nil and cloneSnapshot(reportSnapshot) or nil
    local snapshotError = reportSnapshot ~= nil and not snapshot and "invalid report snapshot" or nil
    local nextRecord = cloneRecord(previous)
    nextRecord.completed = true
    if newScore and (not nextRecord.bestScore or newScore > nextRecord.bestScore) then
        nextRecord.bestScore = newScore
    end
    local previousSnapshot = previous.lastReportSnapshot
    -- Keep the highest-scoring report; a same-score clear replaces it with the latest details.
    local snapshotUpdated = snapshot ~= nil
        and (not previousSnapshot or snapshot.score >= previousSnapshot.score)
    if snapshotUpdated then nextRecord.lastReportSnapshot = snapshot end

    local firstCompletion = previous.completed ~= true
    local bestImproved = nextRecord.bestScore ~= previous.bestScore
    self.records[levelId] = nextRecord

    local persisted, persistenceError = true, nil
    if firstCompletion or bestImproved or snapshotUpdated then
        persisted, persistenceError = writeAtomic(self)
    end
    if firstCompletion or bestImproved then
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
        snapshotUpdated = snapshotUpdated,
        snapshotError = snapshotError,
        persisted = persisted,
        persistenceError = persistenceError,
    }, nil
end

function ExperimentProgress:UpdateReportSnapshot(levelId, reportSnapshot)
    if not validLevelId(levelId) then return false, "invalid level id" end
    local snapshot = cloneSnapshot(reportSnapshot)
    if not snapshot or snapshot.levelId ~= levelId then return false, "invalid report snapshot" end
    local record = cloneRecord(self.records[levelId])
    if not record.completed then return false, "experiment is not completed" end
    local previousSnapshot = record.lastReportSnapshot
    if previousSnapshot and snapshot.score < previousSnapshot.score then return true, nil end
    record.lastReportSnapshot = snapshot
    self.records[levelId] = record
    return writeAtomic(self)
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
